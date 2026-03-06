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
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"runtime"
	"sync"
	"syscall"
	"time"

	"simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
	_ "simplevpn/pkg/transport/rawtls"
	_ "simplevpn/pkg/transport/ws"
	"simplevpn/pkg/tunnel"
)

// Config is the JSON configuration passed from the mobile app.
type Config struct {
	Server      string `json:"server"`                // host:port
	PSK         string `json:"psk"`
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

// state holds the current connection state.
type state struct {
	mu        sync.Mutex
	connected bool
	conn      net.Conn
	tunFile   *os.File
	stopCh    chan struct{}
	status    string
}

var current = &state{status: "disconnected"}

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
//   - configJSON: JSON string with server, psk, sni, transport, fingerprint fields
//   - fd: TUN device file descriptor (from platform VPN service)
//
// This function blocks until the connection is closed or Disconnect() is called.
func Connect(configJSON string, fd int) error {
	current.mu.Lock()
	if current.connected {
		current.mu.Unlock()
		return fmt.Errorf("already connected")
	}
	current.status = "connecting"
	current.stopCh = make(chan struct{})
	current.mu.Unlock()

	log.Printf("[vpnlib] Connect called, config length=%d, fd=%d", len(configJSON), fd)

	var cfg Config
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		log.Printf("[vpnlib] ERROR: failed to parse config JSON: %v", err)
		setStatus("error: bad config: " + err.Error())
		return fmt.Errorf("parse config: %w", err)
	}

	// Log config (mask PSK)
	pskPreview := cfg.PSK
	if len(pskPreview) > 4 {
		pskPreview = pskPreview[:4] + "..."
	}
	log.Printf("[vpnlib] Config: server=%s, sni=%s, skipVerify=%v, psk=%s, transport=%s, fingerprint=%s",
		cfg.Server, cfg.SNI, cfg.SkipVerify, pskPreview, cfg.Transport, cfg.Fingerprint)

	if cfg.Server == "" || cfg.PSK == "" {
		log.Printf("[vpnlib] ERROR: server=%q psk=%q — both are required", cfg.Server, pskPreview)
		setStatus("error: server and psk are required")
		return fmt.Errorf("server and psk are required")
	}

	// Derive keys
	log.Printf("[vpnlib] Deriving keys from PSK...")
	keys, err := tunnel.DeriveKeys(cfg.PSK)
	if err != nil {
		log.Printf("[vpnlib] ERROR: derive keys: %v", err)
		setStatus("error: derive keys: " + err.Error())
		return fmt.Errorf("derive keys: %w", err)
	}
	log.Printf("[vpnlib] Keys derived OK")

	// TUN file from fd
	log.Printf("[vpnlib] Opening TUN fd=%d", fd)
	tunFile := os.NewFile(uintptr(fd), "tun")
	if tunFile == nil {
		log.Printf("[vpnlib] ERROR: os.NewFile returned nil for fd=%d", fd)
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
			MinVersion:         tls.VersionTLS12,
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
		setStatus("error: connect: " + err.Error())
		return fmt.Errorf("transport dial: %w", err)
	}
	log.Printf("[vpnlib] Transport connected to %s", cfg.Server)

	// Authenticate
	log.Printf("[vpnlib] Step 3/4: Sending auth token ...")
	masterKey := sha256.Sum256([]byte(cfg.PSK))
	_, authToken, err := tlsdecoy.GenerateAuthToken(masterKey)
	if err != nil {
		log.Printf("[vpnlib] ERROR: generate auth token: %v", err)
		conn.Close()
		setStatus("error: auth gen: " + err.Error())
		return fmt.Errorf("generate auth: %w", err)
	}
	log.Printf("[vpnlib] Auth token generated, length=%d bytes", len(authToken))

	if _, err := conn.Write(authToken); err != nil {
		log.Printf("[vpnlib] ERROR: send auth token: %v", err)
		conn.Close()
		setStatus("error: auth send: " + err.Error())
		return fmt.Errorf("send auth: %w", err)
	}
	log.Printf("[vpnlib] Auth token sent, waiting for server response (10s timeout) ...")

	okBuf := make([]byte, 2)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(conn, okBuf); err != nil {
		log.Printf("[vpnlib] ERROR: reading auth response: %v", err)
		conn.Close()
		setStatus("error: auth response: " + err.Error())
		return fmt.Errorf("auth response: %w", err)
	}
	conn.SetReadDeadline(time.Time{})

	log.Printf("[vpnlib] Auth response received: %q", string(okBuf))
	if string(okBuf) != "OK" {
		log.Printf("[vpnlib] ERROR: auth rejected (got %q, expected \"OK\")", string(okBuf))
		conn.Close()
		setStatus("error: auth rejected")
		return fmt.Errorf("auth rejected")
	}
	log.Printf("[vpnlib] Step 4/4: Authenticated OK (transport=%s, fingerprint=%s)", tt, fp)

	// Store connection state
	current.mu.Lock()
	current.connected = true
	current.conn = conn
	current.tunFile = tunFile
	current.status = "connected"
	stopCh := current.stopCh
	current.mu.Unlock()

	log.Printf("[vpnlib] Tunnel active, starting data relay goroutines")

	// Create tunnel
	tun := tunnel.New(keys, conn)

	// Buffers
	encBuf := make([]byte, 0, tunnel.MaxFrameSize+crypto.Overhead)
	obfsBuf := make([]byte, 0, tunnel.MaxFrameSize+crypto.Overhead+obfs.HeaderSize+obfs.MaxPad)
	_, _ = encBuf, obfsBuf // used by tunnel internally

	// TUN → Transport (send)
	go func() {
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
			setStatus("error: recv: " + err.Error())
			return err
		}

		if _, err := tunFile.Write(plaintext); err != nil {
			log.Printf("[vpnlib] TUN write error (after %d packets): %v", recvCount, err)
			cleanup(conn, tunFile)
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

func setStatus(s string) {
	current.mu.Lock()
	current.status = s
	current.mu.Unlock()
	log.Printf("[vpnlib] Status -> %s", s)
}

func cleanup(conn net.Conn, tunFile *os.File) {
	current.mu.Lock()
	defer current.mu.Unlock()
	if conn != nil {
		conn.Close()
	}
	current.connected = false
	current.status = "disconnected"
	log.Printf("[vpnlib] Cleanup done")
}
