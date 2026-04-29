// Package vpnlib provides a simple API for mobile apps to connect to a SimpleVPN server.
//
// This package is designed to be compiled with gomobile into:
//   - iOS: .xcframework
//   - Android: .aar
//
// The API is intentionally simple — three functions:
//   - Connect(configJSON string, fd int) error
//   - Disconnect()
//   - Status() string
//
// Transport support:
//   - "ws" (default): WebSocket over TLS with uTLS fingerprint mimicry
//   - "tls": Raw TLS 1.3 (backward compatible, legacy)
//
// The fd parameter is the file descriptor of the TUN device, which must be
// created by the platform layer (NEPacketTunnelProvider on iOS, VpnService on Android).
package vpnlib

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/netip"
	"os"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
	_ "simplevpn/pkg/transport/rawtls"
	_ "simplevpn/pkg/transport/ws"
	"simplevpn/pkg/tunnel"
)

// Config is the JSON configuration passed from the mobile app.
type Config struct {
	Server      string `json:"server"`                // host:port
	ServerKey   string `json:"server_key"`
	Username    string `json:"username"`
	Password    string `json:"password"`
	SNI         string `json:"sni"`
	SkipVerify  bool   `json:"skip_verify,omitempty"`
	Transport   string `json:"transport,omitempty"`   // "ws" (default) or "tls"
	Fingerprint string `json:"fingerprint,omitempty"` // "chrome" (default Android), "safari" (default iOS), "firefox", "none"
}

// logBuffer captures log output for retrieval by the mobile app.
type logBuffer struct {
	mu      sync.Mutex
	entries []string
	maxSize int
}

var logBuf = &logBuffer{maxSize: 200}

func (lb *logBuffer) Write(p []byte) (n int, err error) {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	line := string(p)
	lb.entries = append(lb.entries, line)
	if len(lb.entries) > lb.maxSize {
		lb.entries = lb.entries[len(lb.entries)-lb.maxSize:]
	}
	// Also write to stderr so logcat still works
	return os.Stderr.Write(p)
}

// Drain returns all buffered log lines and clears the buffer.
func (lb *logBuffer) Drain() string {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	if len(lb.entries) == 0 {
		return ""
	}
	result := ""
	for _, e := range lb.entries {
		result += e
	}
	lb.entries = lb.entries[:0]
	return result
}

func init() {
	log.SetOutput(logBuf)
	log.SetFlags(log.Ltime | log.Lmicroseconds)
}

// Logs returns buffered log lines from the Go layer and clears the buffer.
// Call this periodically from the mobile app to surface Go-side logs in the UI.
func Logs() string {
	return logBuf.Drain()
}

// SocketProtector is implemented by the platform (Android/iOS) to protect
// the VPN socket from being routed through the TUN interface.
// On Android, the implementation calls VpnService.protect(fd).
type SocketProtector interface {
	// ProtectSocket marks the socket fd to bypass VPN routing.
	// Returns true on success.
	ProtectSocket(fd int32) bool
}

var protector SocketProtector

// SetProtector sets the platform socket protector.
// Must be called before Connect(). On Android, pass an implementation
// that calls VpnService.protect(fd).
func SetProtector(p SocketProtector) {
	protector = p
	log.Printf("[vpnlib] Socket protector set: %v", p != nil)
}

// errKind classifies the most recent error so the platform layer can decide
// whether to retry. The platform owns retry policy; vpnlib only categorizes.
//
//   - kindNone:      no error since last Connect/Preflight
//   - kindTransient: network error, dial failure, RST, relay error — retry with backoff
//   - kindAuth:      server rejected credentials (HTTP 401 or "auth rejected" auth-line) — do not retry
//   - kindFatal:     TLS handshake permanent failure, malformed config, programmer error — do not retry
type errKind int

const (
	kindNone errKind = iota
	kindTransient
	kindAuth
	kindFatal
)

func (k errKind) String() string {
	switch k {
	case kindTransient:
		return "transient"
	case kindAuth:
		return "auth"
	case kindFatal:
		return "fatal"
	default:
		return "none"
	}
}

// state holds the current connection state.
type state struct {
	mu             sync.Mutex
	connected      bool
	conn           net.Conn
	tunFile        *os.File
	stopCh         chan struct{}
	status         string
	assignedPrefix netip.Prefix // IP assigned by server, e.g. "10.0.0.2/24"
	lastKind       errKind      // most recent error classification (see errKind)

	// Pending preflight state — valid between Preflight() and RunTunnel() calls.
	pendingBC         *bufConn     // authenticated + bufio-wrapped connection
	pendingKeys       *tunnel.Keys
	preflightCh       chan struct{} // closed by RunTunnel to cancel watchdog
	connectUnlockOnce *sync.Once   // ensures connectMu.Unlock is called exactly once
}

// AssignedPrefix returns the IP prefix assigned by the server for this session.
// Returns an empty string when not connected or when the server did not assign an IP.
func AssignedPrefix() string {
	current.mu.Lock()
	defer current.mu.Unlock()
	if !current.assignedPrefix.IsValid() {
		return ""
	}
	return current.assignedPrefix.String()
}

// bufConn wraps a net.Conn to replay bytes already consumed by a bufio.Reader.
// After using bufio.Reader to read the auth response line, the reader may have
// pre-buffered bytes beyond the '\n'. Without this wrapper, tunnel.New would
// read from the raw conn and lose those buffered bytes.
type bufConn struct {
	r *bufio.Reader
	net.Conn
}

func (bc *bufConn) Read(p []byte) (int, error) { return bc.r.Read(p) }

var current = &state{status: "disconnected"}

// connectMu is held from Preflight() until RunTunnel() returns (or the watchdog fires).
// This prevents concurrent connection attempts.
var connectMu sync.Mutex

// defaultTransport returns the default transport type for the current platform.
func defaultTransport() transport.Type {
	return transport.TypeWS
}

// defaultFingerprint returns the default TLS fingerprint for the current platform.
func defaultFingerprint() transport.FingerprintProfile {
	if runtime.GOOS == "ios" || runtime.GOOS == "darwin" {
		return transport.FingerprintSafari
	}
	return transport.FingerprintChrome
}

// Connect establishes a VPN connection.
//   - configJSON: JSON string with server, server_key, username, password, sni, transport, fingerprint fields
//   - fd: TUN device file descriptor (from platform VPN service)
//
// This function blocks until the connection is closed or Disconnect() is called.
func Connect(configJSON string, fd int) error {
	// [FIX] Prevent concurrent Connect() calls from racing
	connectMu.Lock()
	defer connectMu.Unlock()
	log.Printf("[FIX] Connect mutex acquired")

	resetLastKind()

	current.mu.Lock()
	if current.connected {
		current.mu.Unlock()
		log.Printf("[FIX] Connect called but already connected — skipping")
		return fmt.Errorf("already connected")
	}
	current.status = "connecting"
	current.stopCh = make(chan struct{})
	current.mu.Unlock()

	log.Printf("[vpnlib] Connect called, config length=%d, fd=%d", len(configJSON), fd)

	var cfg Config
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		log.Printf("[vpnlib] ERROR: failed to parse config JSON: %v", err)
		setLastKind(kindFatal, "config-parse", err)
		setStatus("error: bad config: " + err.Error())
		return fmt.Errorf("parse config: %w", err)
	}

	// Log config (mask sensitive fields)
	keyPreview := cfg.ServerKey
	if len(keyPreview) > 4 {
		keyPreview = keyPreview[:4] + "..."
	}
	log.Printf("[vpnlib] Config: server=%s, sni=%s, skipVerify=%v, server_key=%s, user=%s, transport=%s, fingerprint=%s",
		cfg.Server, cfg.SNI, cfg.SkipVerify, keyPreview, cfg.Username, cfg.Transport, cfg.Fingerprint)

	if cfg.Server == "" || cfg.ServerKey == "" || cfg.Username == "" || cfg.Password == "" {
		log.Printf("[vpnlib] ERROR: server, server_key, username, and password are all required")
		setLastKind(kindFatal, "config-validate", nil)
		setStatus("error: server, server_key, username, and password are required")
		return fmt.Errorf("server, server_key, username, and password are required")
	}

	// Derive keys
	log.Printf("[vpnlib] Deriving keys from server key...")
	keys, err := tunnel.DeriveKeys(cfg.ServerKey)
	if err != nil {
		log.Printf("[vpnlib] ERROR: derive keys: %v", err)
		setLastKind(kindFatal, "derive-keys", err)
		setStatus("error: derive keys: " + err.Error())
		return fmt.Errorf("derive keys: %w", err)
	}
	log.Printf("[vpnlib] Keys derived OK")

	// TUN file from fd
	log.Printf("[vpnlib] Opening TUN fd=%d", fd)
	tunFile := os.NewFile(uintptr(fd), "tun")
	if tunFile == nil {
		log.Printf("[vpnlib] ERROR: os.NewFile returned nil for fd=%d", fd)
		setLastKind(kindFatal, "tun-fd", nil)
		setStatus("error: invalid tun fd")
		return fmt.Errorf("invalid tun fd: %d", fd)
	}
	log.Printf("[vpnlib] TUN file opened OK")

	// Resolve SNI
	sni := cfg.SNI
	if sni == "" {
		h, _, err := net.SplitHostPort(cfg.Server)
		if err == nil {
			sni = h
		}
		log.Printf("[vpnlib] SNI not set, derived from server: %s", sni)
	}

	// Resolve transport settings with defaults
	tt := transport.Type(cfg.Transport)
	if tt == "" {
		tt = defaultTransport()
		log.Printf("[vpnlib] Transport not set, using default: %s", tt)
	}
	fp := transport.FingerprintProfile(cfg.Fingerprint)
	if fp == "" {
		fp = defaultFingerprint()
		log.Printf("[vpnlib] Fingerprint not set, using default: %s", fp)
	}

	// Create transport dialer
	log.Printf("[vpnlib] Step 1/4: Creating transport (type=%s, fingerprint=%s) ...", tt, fp)
	setStatus("connecting")

	dialer, err := transport.NewDialer(tt, fp)
	if err != nil {
		log.Printf("[vpnlib] ERROR: create transport dialer: %v", err)
		setLastKind(kindFatal, "transport-create", err)
		setStatus("error: transport: " + err.Error())
		return fmt.Errorf("create transport: %w", err)
	}

	// Build dial config
	dialCfg := &transport.DialConfig{
		ServerAddr:  cfg.Server,
		SNI:         sni,
		Fingerprint: fp,
	}
	if cfg.SkipVerify {
		dialCfg.TLSConfig = &tls.Config{
			ServerName:         sni,
			InsecureSkipVerify: true,
			MinVersion:         tls.VersionTLS13,
			NextProtos:         []string{"http/1.1"},
		}
	}

	// Socket protection for Android VPN
	if protector != nil {
		dialCfg.DialControl = func(network, address string, c interface{}) error {
			rawConn, ok := c.(syscall.RawConn)
			if !ok {
				log.Printf("[vpnlib] WARNING: DialControl received non-RawConn type: %T", c)
				return nil
			}
			var protectErr error
			err := rawConn.Control(func(fd uintptr) {
				log.Printf("[vpnlib] Protecting socket fd=%d from VPN routing", fd)
				if !protector.ProtectSocket(int32(fd)) {
					protectErr = fmt.Errorf("protect socket fd=%d failed", fd)
				} else {
					log.Printf("[vpnlib] Socket fd=%d protected OK", fd)
				}
			})
			if err != nil {
				return fmt.Errorf("raw conn control: %w", err)
			}
			return protectErr
		}
	} else {
		log.Printf("[vpnlib] WARNING: no socket protector set, VPN routing loop may occur")
	}

	// Dial via transport
	log.Printf("[vpnlib] Step 2/4: Connecting to %s via %s transport ...", cfg.Server, tt)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, err := dialer.Dial(ctx, dialCfg)
	if err != nil {
		log.Printf("[vpnlib] ERROR: transport dial failed: %v", err)
		setLastKind(classifyDialErr(err), "dial", err)
		setStatus("error: connect: " + err.Error())
		return fmt.Errorf("transport dial: %w", err)
	}
	log.Printf("[vpnlib] Transport connected to %s", cfg.Server)

	// Authenticate with credentials
	log.Printf("[vpnlib] Step 3/4: Sending credentials for user %q ...", cfg.Username)
	credFrame, err := tlsdecoy.GenerateCredAuth(cfg.Username, cfg.Password)
	if err != nil {
		log.Printf("[vpnlib] ERROR: generate credential frame: %v", err)
		conn.Close()
		setLastKind(kindFatal, "auth-gen", err)
		setStatus("error: auth gen: " + err.Error())
		return fmt.Errorf("generate credentials: %w", err)
	}
	log.Printf("[vpnlib] Credential frame generated, length=%d bytes", len(credFrame))

	if _, err := conn.Write(credFrame); err != nil {
		log.Printf("[vpnlib] ERROR: send credentials: %v", err)
		conn.Close()
		setLastKind(kindTransient, "auth-send", err)
		setStatus("error: auth send: " + err.Error())
		return fmt.Errorf("send credentials: %w", err)
	}
	log.Printf("[vpnlib] Credentials sent, waiting for server response (10s timeout) ...")

	// Read auth response line: "OK <ip>/<prefix>\n"
	// Use bufio so we can read up to '\n' precisely; wrap conn in bufConn
	// afterwards so any pre-buffered bytes are not lost when tunnel.New reads.
	br := bufio.NewReader(conn)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	line, err := br.ReadString('\n')
	conn.SetReadDeadline(time.Time{})
	if err != nil {
		log.Printf("[vpnlib] ERROR: reading auth response line: %v", err)
		conn.Close()
		setLastKind(kindTransient, "auth-response", err)
		setStatus("error: auth response: " + err.Error())
		return fmt.Errorf("auth response: %w", err)
	}

	line = strings.TrimSpace(line)
	log.Printf("[vpnlib] Auth response received: %q", line)

	if !strings.HasPrefix(line, "OK ") {
		log.Printf("[vpnlib] ERROR: auth rejected (response=%q)", line)
		conn.Close()
		setLastKind(kindAuth, "auth-rejected", nil)
		setStatus("error: auth rejected")
		return fmt.Errorf("auth rejected: %s", line)
	}

	assignedPrefix, err := netip.ParsePrefix(strings.TrimPrefix(line, "OK "))
	if err != nil {
		log.Printf("[vpnlib] ERROR: parse assigned prefix %q: %v", line, err)
		conn.Close()
		setLastKind(kindFatal, "assigned-prefix", err)
		setStatus("error: bad assigned prefix")
		return fmt.Errorf("parse assigned prefix: %w", err)
	}
	log.Printf("[vpnlib] Step 4/4: Authenticated OK, assigned=%s (transport=%s, fingerprint=%s)", assignedPrefix, tt, fp)

	// Store connection state and assigned IP.
	current.mu.Lock()
	current.connected = true
	current.conn = conn
	current.tunFile = tunFile
	current.status = "connected"
	current.assignedPrefix = assignedPrefix
	stopCh := current.stopCh
	current.mu.Unlock()

	log.Printf("[vpnlib] Tunnel active, starting data relay goroutines")

	// Wrap conn in bufConn so buffered bytes past '\n' are not lost.
	bc := &bufConn{r: br, Conn: conn}

	// Create tunnel
	tun := tunnel.New(keys, bc)

	// TUN → Transport (send)
	// [FIX] tunReaderDone signals when the goroutine exits, so cleanup waits for it
	tunReaderDone := make(chan struct{})
	go func() {
		defer close(tunReaderDone)
		// [FIX] Panic recovery — prevent native crash from killing the Go runtime
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[FIX] Panic in TUN→Transport goroutine: %v", r)
				setLastKind(kindFatal, "tun-reader-panic", nil)
				setStatus("error: tun reader panic")
			}
		}()

		buf := make([]byte, tunnel.MaxFrameSize)
		var sendCount int64
		log.Printf("[vpnlib] TUN→Transport goroutine started, reading from TUN fd=%d", fd)
		for {
			select {
			case <-stopCh:
				log.Printf("[vpnlib] TUN→Transport goroutine stopping (stop signal), sent %d packets", sendCount)
				return
			default:
			}

			n, err := tunFile.Read(buf)
			if err != nil {
				log.Printf("[vpnlib] TUN read error (after %d packets): %v", sendCount, err)
				return
			}

			if sendCount < 5 {
				log.Printf("[vpnlib] TUN read: %d bytes (packet #%d, first byte=0x%02x)", n, sendCount+1, buf[0])
			} else if sendCount == 5 {
				log.Printf("[vpnlib] TUN reads working, suppressing per-packet logs")
			}

			if err := tun.Send(buf[:n]); err != nil {
				log.Printf("[vpnlib] Send error (after %d packets): %v", sendCount, err)
				return
			}
			sendCount++
			if sendCount%1000 == 0 {
				log.Printf("[vpnlib] TUN→Transport stats: sent %d packets", sendCount)
			}
		}
	}()

	// Transport → TUN (receive) — blocks until disconnect
	var recvCount int64
	log.Printf("[vpnlib] Transport→TUN receive loop started, writing to TUN fd=%d", fd)
	for {
		select {
		case <-stopCh:
			log.Printf("[vpnlib] Transport→TUN loop stopping (stop signal), received %d packets", recvCount)
			cleanup(conn, tunFile)
			return nil
		default:
		}

		plaintext, err := tun.Recv()
		if err != nil {
			log.Printf("[vpnlib] Recv error (after %d packets): %v", recvCount, err)
			cleanup(conn, tunFile)
			setLastKind(kindTransient, "recv", err)
			setStatus("error: recv: " + err.Error())
			return err
		}

		if _, err := tunFile.Write(plaintext); err != nil {
			log.Printf("[vpnlib] TUN write error (after %d packets): %v", recvCount, err)
			cleanup(conn, tunFile)
			setLastKind(kindTransient, "tun-write", err)
			setStatus("error: tun write: " + err.Error())
			return err
		}
		recvCount++
	}
}

// Preflight authenticates with the VPN server and returns the assigned IP prefix
// (e.g. "10.0.0.2/24"). The caller must use this IP to configure the TUN interface
// and then call RunTunnel(fd) within 10 seconds.
//
// Returns "error: <message>" on failure. Returns the assigned prefix on success.
//
// Lifecycle guarantee: holds connectMu after returning successfully.
// Either RunTunnel or a 10-second watchdog will release it.
func Preflight(configJSON string) string {
	connectMu.Lock()
	log.Printf("[vpnlib] Preflight: connectMu acquired")

	resetLastKind()

	unlockOnce := &sync.Once{}

	current.mu.Lock()
	if current.connected {
		current.mu.Unlock()
		unlockOnce.Do(connectMu.Unlock)
		return "error: already connected"
	}
	current.status = "connecting"
	current.stopCh = make(chan struct{})
	current.mu.Unlock()

	log.Printf("[vpnlib] Preflight: config len=%d", len(configJSON))

	var cfg Config
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		setLastKind(kindFatal, "config-parse", err)
		setStatus("error: bad config: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: bad config: " + err.Error()
	}

	if cfg.Server == "" || cfg.ServerKey == "" || cfg.Username == "" || cfg.Password == "" {
		setLastKind(kindFatal, "config-validate", nil)
		setStatus("error: missing required fields")
		unlockOnce.Do(connectMu.Unlock)
		return "error: server, server_key, username, and password are required"
	}

	keys, err := tunnel.DeriveKeys(cfg.ServerKey)
	if err != nil {
		setLastKind(kindFatal, "derive-keys", err)
		setStatus("error: derive keys: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: derive keys: " + err.Error()
	}

	sni := cfg.SNI
	if sni == "" {
		h, _, e := net.SplitHostPort(cfg.Server)
		if e == nil {
			sni = h
		}
	}
	tt := transport.Type(cfg.Transport)
	if tt == "" {
		tt = defaultTransport()
	}
	fp := transport.FingerprintProfile(cfg.Fingerprint)
	if fp == "" {
		fp = defaultFingerprint()
	}

	dialer, err := transport.NewDialer(tt, fp)
	if err != nil {
		setLastKind(kindFatal, "transport-create", err)
		setStatus("error: transport: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: transport: " + err.Error()
	}

	dialCfg := &transport.DialConfig{
		ServerAddr:  cfg.Server,
		SNI:         sni,
		Fingerprint: fp,
	}
	if cfg.SkipVerify {
		dialCfg.TLSConfig = &tls.Config{
			ServerName:         sni,
			InsecureSkipVerify: true,
			MinVersion:         tls.VersionTLS13,
			NextProtos:         []string{"http/1.1"},
		}
	}
	if protector != nil {
		dialCfg.DialControl = func(network, address string, c interface{}) error {
			rawConn, ok := c.(syscall.RawConn)
			if !ok {
				return nil
			}
			var protectErr error
			rawConn.Control(func(fd uintptr) { //nolint:errcheck
				if !protector.ProtectSocket(int32(fd)) {
					protectErr = fmt.Errorf("protect socket fd=%d failed", fd)
				}
			})
			return protectErr
		}
	} else {
		log.Printf("[vpnlib] WARNING: no socket protector set in Preflight")
	}

	log.Printf("[vpnlib] Preflight: dialing %s via %s", cfg.Server, tt)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, err := dialer.Dial(ctx, dialCfg)
	if err != nil {
		setLastKind(classifyDialErr(err), "dial", err)
		setStatus("error: connect: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: connect: " + err.Error()
	}
	log.Printf("[vpnlib] Preflight: connected to %s, authenticating", cfg.Server)

	credFrame, err := tlsdecoy.GenerateCredAuth(cfg.Username, cfg.Password)
	if err != nil {
		conn.Close()
		setLastKind(kindFatal, "auth-gen", err)
		setStatus("error: auth gen: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: auth gen: " + err.Error()
	}
	if _, err := conn.Write(credFrame); err != nil {
		conn.Close()
		setLastKind(kindTransient, "auth-send", err)
		setStatus("error: auth send: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: auth send: " + err.Error()
	}

	br := bufio.NewReader(conn)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	line, err := br.ReadString('\n')
	conn.SetReadDeadline(time.Time{})
	if err != nil {
		conn.Close()
		setLastKind(kindTransient, "auth-response", err)
		setStatus("error: auth response: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: auth response: " + err.Error()
	}

	line = strings.TrimSpace(line)
	log.Printf("[vpnlib] Preflight: auth response=%q", line)

	if !strings.HasPrefix(line, "OK ") {
		conn.Close()
		setLastKind(kindAuth, "auth-rejected", nil)
		setStatus("error: auth rejected")
		unlockOnce.Do(connectMu.Unlock)
		return "error: auth rejected: " + line
	}

	assignedPrefix, err := netip.ParsePrefix(strings.TrimPrefix(line, "OK "))
	if err != nil {
		conn.Close()
		setLastKind(kindFatal, "assigned-prefix", err)
		setStatus("error: bad assigned prefix")
		unlockOnce.Do(connectMu.Unlock)
		return "error: bad assigned prefix: " + err.Error()
	}
	log.Printf("[vpnlib] Preflight: assigned=%s", assignedPrefix)

	bc := &bufConn{r: br, Conn: conn}
	preflightCh := make(chan struct{})

	current.mu.Lock()
	current.pendingBC = bc
	current.pendingKeys = keys
	current.assignedPrefix = assignedPrefix
	current.preflightCh = preflightCh
	current.connectUnlockOnce = unlockOnce
	current.mu.Unlock()

	// Watchdog: close pending conn and release mutex if RunTunnel not called in 10s.
	go func() {
		select {
		case <-preflightCh:
			log.Printf("[vpnlib] Preflight watchdog: cancelled by RunTunnel")
		case <-time.After(10 * time.Second):
			log.Printf("[vpnlib] Preflight watchdog: RunTunnel not called, closing conn")
			current.mu.Lock()
			if current.pendingBC != nil {
				current.pendingBC.Close()
				current.pendingBC = nil
				current.pendingKeys = nil
			}
			current.status = "disconnected"
			current.mu.Unlock()
			unlockOnce.Do(connectMu.Unlock)
		}
	}()

	return assignedPrefix.String()
}

// RunTunnel starts the VPN data relay using the given TUN file descriptor.
// Must be called within 10 seconds of a successful Preflight() call.
// Blocks until the tunnel closes or Disconnect() is called.
func RunTunnel(fd int) error {
	current.mu.Lock()
	bc := current.pendingBC
	keys := current.pendingKeys
	stopCh := current.stopCh
	unlockOnce := current.connectUnlockOnce

	if bc == nil || keys == nil || unlockOnce == nil {
		current.mu.Unlock()
		return fmt.Errorf("RunTunnel called without a pending Preflight, or watchdog expired")
	}

	// Cancel the watchdog — we own the connection now.
	close(current.preflightCh)
	current.pendingBC = nil
	current.pendingKeys = nil
	current.preflightCh = nil
	current.mu.Unlock()

	// connectMu is released when RunTunnel returns (tunnel closes or Disconnect called).
	defer unlockOnce.Do(connectMu.Unlock)

	log.Printf("[vpnlib] RunTunnel: fd=%d assigned=%s", fd, current.assignedPrefix)

	tunFile := os.NewFile(uintptr(fd), "tun")
	if tunFile == nil {
		setLastKind(kindFatal, "tun-fd", nil)
		setStatus("error: invalid tun fd")
		return fmt.Errorf("invalid tun fd: %d", fd)
	}

	current.mu.Lock()
	current.connected = true
	current.conn = bc
	current.tunFile = tunFile
	current.status = "connected"
	current.mu.Unlock()

	log.Printf("[vpnlib] RunTunnel: tunnel active, starting relay goroutines")

	tun := tunnel.New(keys, bc)

	tunReaderDone := make(chan struct{})
	go func() {
		defer close(tunReaderDone)
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[FIX] Panic in TUN→Transport goroutine (RunTunnel): %v", r)
				setLastKind(kindFatal, "tun-reader-panic", nil)
				setStatus("error: tun reader panic")
			}
		}()
		buf := make([]byte, tunnel.MaxFrameSize)
		var count int64
		for {
			select {
			case <-stopCh:
				log.Printf("[vpnlib] RunTunnel TUN→Transport stopping (sent %d pkts)", count)
				return
			default:
			}
			n, err := tunFile.Read(buf)
			if err != nil {
				log.Printf("[vpnlib] RunTunnel TUN read error: %v", err)
				return
			}
			if err := tun.Send(buf[:n]); err != nil {
				log.Printf("[vpnlib] RunTunnel Send error: %v", err)
				return
			}
			count++
		}
	}()

	var recvCount int64
	for {
		select {
		case <-stopCh:
			log.Printf("[vpnlib] RunTunnel recv loop stopping (received %d pkts)", recvCount)
			cleanup(bc, tunFile)
			return nil
		default:
		}

		plaintext, err := tun.Recv()
		if err != nil {
			log.Printf("[vpnlib] RunTunnel Recv error (after %d pkts): %v", recvCount, err)
			cleanup(bc, tunFile)
			setLastKind(kindTransient, "recv", err)
			setStatus("error: recv: " + err.Error())
			return err
		}

		if _, err := tunFile.Write(plaintext); err != nil {
			log.Printf("[vpnlib] RunTunnel TUN write error: %v", err)
			cleanup(bc, tunFile)
			setLastKind(kindTransient, "tun-write", err)
			setStatus("error: tun write: " + err.Error())
			return err
		}
		recvCount++
	}
}

// Disconnect closes the VPN connection.
func Disconnect() {
	current.mu.Lock()
	defer current.mu.Unlock()

	if !current.connected {
		log.Printf("[vpnlib] Disconnect called but not connected (status=%s)", current.status)
		return
	}

	log.Printf("[vpnlib] Disconnect called, closing connection...")

	close(current.stopCh)

	// [FIX] Close tunFile to unblock any goroutine stuck in tunFile.Read()
	// This must happen BEFORE conn.Close() so the TUN reader goroutine exits cleanly.
	if current.tunFile != nil {
		log.Printf("[FIX] Closing TUN file to unblock reader goroutine")
		current.tunFile.Close()
		current.tunFile = nil
	}

	if current.conn != nil {
		current.conn.Close()
		log.Printf("[vpnlib] Connection closed")
	}
	current.connected = false
	current.status = "disconnected"
	log.Printf("[vpnlib] Disconnected OK")
}

// Status returns the current connection status: "disconnected", "connecting", or "connected".
func Status() string {
	current.mu.Lock()
	defer current.mu.Unlock()
	return current.status
}

// LastErrorKind returns the most recent error classification:
// "none" | "transient" | "auth" | "fatal". Reset to "none" on every
// Connect()/Preflight() entry. Used by the platform retry loop to decide
// whether to back off (transient) or stop retrying (auth/fatal).
func LastErrorKind() string {
	current.mu.Lock()
	defer current.mu.Unlock()
	return current.lastKind.String()
}

func setStatus(s string) {
	current.mu.Lock()
	current.status = s
	current.mu.Unlock()
	log.Printf("[vpnlib] Status -> %s", s)
}

// setLastKind transitions the lastKind state and emits a DEBUG line.
// src is a short tag (e.g. "dial", "auth-response", "recv") so the log
// shows where the classification came from.
func setLastKind(k errKind, src string, cause error) {
	current.mu.Lock()
	prev := current.lastKind
	current.lastKind = k
	current.mu.Unlock()
	if cause != nil {
		log.Printf("[vpnlib] errKind %s -> %s (src=%s, cause=%v)", prev, k, src, cause)
	} else {
		log.Printf("[vpnlib] errKind %s -> %s (src=%s)", prev, k, src)
	}
}

// resetLastKind clears the classification at the start of every Connect/Preflight.
func resetLastKind() {
	current.mu.Lock()
	current.lastKind = kindNone
	current.mu.Unlock()
}

// classifyDialErr classifies an error returned by transport.Dialer.Dial.
// TLS/cert problems → fatal (won't fix on retry). HTTP 401 from the WS
// upgrade → auth (creds rejected). Anything else → transient.
func classifyDialErr(err error) errKind {
	if err == nil {
		return kindNone
	}
	msg := strings.ToLower(err.Error())
	switch {
	case strings.Contains(msg, "401") || strings.Contains(msg, "unauthorized"):
		return kindAuth
	case strings.Contains(msg, "x509") ||
		strings.Contains(msg, "certificate") ||
		strings.Contains(msg, "tls handshake") ||
		strings.Contains(msg, "tls: handshake") ||
		strings.Contains(msg, "bad certificate") ||
		strings.Contains(msg, "unknown authority"):
		return kindFatal
	default:
		return kindTransient
	}
}

func cleanup(conn net.Conn, tunFile *os.File) {
	current.mu.Lock()
	defer current.mu.Unlock()
	if conn != nil {
		conn.Close()
	}
	// [FIX] Close tunFile to prevent fd leak and unblock TUN reader goroutine
	if tunFile != nil && current.tunFile != nil {
		log.Printf("[FIX] Closing TUN file in cleanup")
		tunFile.Close()
		current.tunFile = nil
	}
	current.connected = false
	current.status = "disconnected"
	log.Printf("[vpnlib] Cleanup done")
}
