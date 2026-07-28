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
	"sync/atomic"
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

	// Endpoints are additional "host:port" addresses tried, in order, when
	// Server does not answer. Migrating between hosting providers changes the
	// server's address but nothing else — same server key, same accounts — so a
	// client that knows several addresses survives the move without the user
	// re-importing a config. The winning address is reported by ActiveServer()
	// so the app can promote it to Server and skip the dead one next time.
	Endpoints []string `json:"endpoints,omitempty"`
}

// migrationFallbacks maps a retiring deployment address to its successors,
// compiled into the client and appended only for configs that actually point at
// the old address.
//
// This exists because of the July 2026 provider move: a client that only ever
// learned the old address has no way to be told about the new one once the old
// server stops answering — the update channel carrying that news lives at the
// same dead address. Baking the destination into the build closes the window
// for anyone who installs this version at all.
//
// Keyed on the old address rather than applied unconditionally, so a config
// aimed at some other deployment is never silently redirected here.
// Safe to prune once the old deployment is long retired.
var migrationFallbacks = map[string][]string{
	"193.23.3.93:443": {"89.40.233.67:443"},
}

// retiredServers lists addresses whose deployment is known to be gone. Configs
// naming one are not broken, merely out of date — but trying such an address
// first makes every single connect pay a full dialTimeout before reaching a
// server that works, which users experience as the app being broken.
//
// Demoted to last rather than dropped: once a live candidate answers the
// retired one is never dialled at all, so keeping it costs nothing, and it
// still serves as a last resort if the address is ever brought back while the
// current server is unreachable.
var retiredServers = map[string]struct{}{
	"193.23.3.93:443": {},
}

// endpointCandidates returns Server, then Endpoints, then any compiled-in
// successor for Server — trimmed and de-duplicated, order otherwise preserved,
// with retired addresses moved to the end. A healthy primary is never penalised
// by the fallback machinery; a dead one no longer delays everyone behind it.
func endpointCandidates(cfg *Config) []string {
	all := append([]string{cfg.Server}, cfg.Endpoints...)
	all = append(all, migrationFallbacks[strings.TrimSpace(cfg.Server)]...)
	seen := make(map[string]struct{}, len(all))
	out := make([]string, 0, len(all))
	var retired []string
	for _, addr := range all {
		addr = strings.TrimSpace(addr)
		if addr == "" {
			continue
		}
		if _, dup := seen[addr]; dup {
			continue
		}
		seen[addr] = struct{}{}
		if _, gone := retiredServers[addr]; gone {
			retired = append(retired, addr)
			continue
		}
		out = append(out, addr)
	}
	return append(out, retired...)
}

// activeServer records the endpoint the live session actually dialled, which is
// not necessarily cfg.Server when a fallback won. Guarded by activeServerMu.
var (
	activeServerMu sync.RWMutex
	activeServer   string
)

func setActiveServer(addr string) {
	activeServerMu.Lock()
	activeServer = addr
	activeServerMu.Unlock()
}

// ActiveServer returns the "host:port" the current session is connected
// through, or "" when there is no session. The app persists this as the new
// primary address after a fallback wins.
func ActiveServer() string {
	activeServerMu.RLock()
	defer activeServerMu.RUnlock()
	return activeServer
}

// dialTimeout bounds a single endpoint attempt. The worst case for a connect is
// this multiplied by the number of candidates, so it stays tight enough that
// walking past a dead primary still feels responsive.
const dialTimeout = 15 * time.Second

// dialWithFallback tries the candidate endpoints in order and returns the first
// connection that comes up, together with the address that produced it. base is
// mutated per attempt (ServerAddr/SNI), so it must not be shared across
// concurrent dials. When every candidate fails the last error is returned — it
// describes the most recently tried address.
func dialWithFallback(dialer transport.Dialer, cfg *Config, base *transport.DialConfig, tag string) (net.Conn, string, error) {
	candidates := endpointCandidates(cfg)
	var lastErr error

	for i, addr := range candidates {
		// SNI follows the address being dialled unless pinned explicitly, so a
		// fallback endpoint on a different host still presents a coherent
		// ClientHello.
		sni := cfg.SNI
		if sni == "" {
			if h, _, err := net.SplitHostPort(addr); err == nil {
				sni = h
			}
		}
		base.ServerAddr = addr
		base.SNI = sni
		if base.TLSConfig != nil {
			base.TLSConfig.ServerName = sni
		}

		log.Printf("[vpnlib] %s: dialing %s (candidate %d/%d, sni=%s)", tag, addr, i+1, len(candidates), sni)
		ctx, cancel := context.WithTimeout(context.Background(), dialTimeout)
		conn, err := dialer.Dial(ctx, base)
		cancel()
		if err == nil {
			if i > 0 {
				log.Printf("[vpnlib] %s: primary unreachable, fell back to %s", tag, addr)
			}
			return conn, addr, nil
		}
		lastErr = err
		log.Printf("[vpnlib] %s: candidate %s failed: %v", tag, addr, err)
	}

	if lastErr == nil {
		lastErr = fmt.Errorf("no usable server address in config")
	}
	return nil, "", lastErr
}

// logBuffer captures log output for retrieval by the mobile app.
type logBuffer struct {
	mu      sync.Mutex
	entries []string
	maxSize int
}

var logBuf = &logBuffer{maxSize: 200}

var (
	statsBytesIn     int64 // accessed via sync/atomic; reset on Connect/Preflight
	statsBytesOut    int64
	statsConnectedAt int64 // Unix ms; 0 when not connected
)

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
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, time.Now().UnixMilli())

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

	// SNI is resolved per candidate endpoint inside dialWithFallback, since a
	// fallback address may live on a different host than the primary.

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

	// Build dial config. ServerAddr/SNI are filled in per attempt by
	// dialWithFallback.
	dialCfg := &transport.DialConfig{
		Fingerprint: fp,
	}
	if cfg.SkipVerify {
		dialCfg.TLSConfig = &tls.Config{
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

	// Dial via transport, walking the fallback endpoints when the primary is dead.
	log.Printf("[vpnlib] Step 2/4: Connecting via %s transport ...", tt)

	conn, dialedAddr, err := dialWithFallback(dialer, &cfg, dialCfg, "Connect")
	if err != nil {
		log.Printf("[vpnlib] ERROR: transport dial failed on all endpoints: %v", err)
		setLastKind(classifyDialErr(err), "dial", err)
		setStatus("error: connect: " + err.Error())
		return fmt.Errorf("transport dial: %w", err)
	}
	setActiveServer(dialedAddr)
	log.Printf("[vpnlib] Transport connected to %s", dialedAddr)

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
			atomic.AddInt64(&statsBytesOut, int64(n))
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
		atomic.AddInt64(&statsBytesIn, int64(len(plaintext)))
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
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, time.Now().UnixMilli())

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

	// SNI is resolved per candidate endpoint inside dialWithFallback.
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

	// ServerAddr/SNI are filled in per attempt by dialWithFallback.
	dialCfg := &transport.DialConfig{
		Fingerprint: fp,
	}
	if cfg.SkipVerify {
		dialCfg.TLSConfig = &tls.Config{
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

	log.Printf("[vpnlib] Preflight: dialing via %s", tt)

	conn, dialedAddr, err := dialWithFallback(dialer, &cfg, dialCfg, "Preflight")
	if err != nil {
		setLastKind(classifyDialErr(err), "dial", err)
		setStatus("error: connect: " + err.Error())
		unlockOnce.Do(connectMu.Unlock)
		return "error: connect: " + err.Error()
	}
	setActiveServer(dialedAddr)
	log.Printf("[vpnlib] Preflight: connected to %s, authenticating", dialedAddr)

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
			atomic.AddInt64(&statsBytesOut, int64(n))
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
		atomic.AddInt64(&statsBytesIn, int64(len(plaintext)))
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
	setActiveServer("")
	log.Printf("[vpnlib] Cleanup done")
}

// GetStats returns a JSON snapshot of traffic counters for the current session.
// Returns {"bytes_in":N,"bytes_out":N,"since_ms":N,"active_server":"host:port"}
// where since_ms is the Unix millisecond timestamp when the current session
// started. All values are zero/empty when no session is active.
//
// active_server rides along here rather than on its own channel method because
// the app already polls stats once a second; that gives it a free signal for
// "a fallback endpoint won, persist it as the new primary".
func GetStats() string {
	in := atomic.LoadInt64(&statsBytesIn)
	out := atomic.LoadInt64(&statsBytesOut)
	since := atomic.LoadInt64(&statsConnectedAt)
	return fmt.Sprintf(`{"bytes_in":%d,"bytes_out":%d,"since_ms":%d,"active_server":%q}`,
		in, out, since, ActiveServer())
}
