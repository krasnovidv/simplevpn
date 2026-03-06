// Package transport provides pluggable transport abstractions for the VPN tunnel.
//
// The transport layer sits between TCP and the VPN protocol (auth + encrypted tunnel).
// Different transport implementations handle different ways of carrying VPN traffic:
//
//   - Raw TLS: direct TLS 1.3 connection (original protocol)
//   - WebSocket: VPN traffic wrapped in WebSocket binary frames over HTTPS
//   - uTLS: TLS with browser-mimicking ClientHello fingerprints
//
// On the client side, a Dialer establishes outbound connections.
// On the server side, a Listener accepts inbound connections.
// Both return net.Conn instances ready for VPN authentication and tunneling.
//
// For WebSocket transport, the returned net.Conn transparently handles
// WebSocket framing — callers read/write raw VPN data as usual.
//
// Transport implementations register themselves via RegisterDialer.
// Import sub-packages for side effects to register:
//
//	import _ "simplevpn/pkg/transport/rawtls"
//	import _ "simplevpn/pkg/transport/ws"
package transport

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"sync"
)

// Type identifies a transport protocol.
type Type string

const (
	TypeTLS Type = "tls" // Raw TLS 1.3 (default, backward compatible)
	TypeWS  Type = "ws"  // WebSocket over TLS
)

// FingerprintProfile identifies a TLS ClientHello fingerprint to mimic.
type FingerprintProfile string

const (
	FingerprintNone    FingerprintProfile = "none"    // Use Go's default TLS stack
	FingerprintChrome  FingerprintProfile = "chrome"  // Mimic Chrome browser
	FingerprintFirefox FingerprintProfile = "firefox" // Mimic Firefox browser
	FingerprintSafari  FingerprintProfile = "safari"  // Mimic Safari browser
)

// DialConfig holds client-side transport configuration.
type DialConfig struct {
	// ServerAddr is the server address (host:port).
	ServerAddr string

	// SNI is the TLS Server Name Indication value.
	SNI string

	// TLSConfig is the base TLS configuration.
	// If nil, a default config is created from SNI.
	TLSConfig *tls.Config

	// Fingerprint selects the ClientHello fingerprint profile.
	// Only used with uTLS-capable transports.
	Fingerprint FingerprintProfile

	// DialControl is an optional function passed to net.Dialer.Control
	// for socket-level operations (e.g., Android VPN socket protection).
	DialControl func(network, address string, c interface{}) error
}

// ListenConfig holds server-side transport configuration.
type ListenConfig struct {
	// Addr is the listen address (e.g., ":443").
	Addr string

	// TLSConfig is the TLS configuration for the listener.
	TLSConfig *tls.Config
}

// Dialer establishes outbound transport connections (client-side).
type Dialer interface {
	// Dial connects to the server and returns a connection ready for VPN auth.
	// The returned net.Conn handles any transport-specific framing transparently.
	Dial(ctx context.Context, cfg *DialConfig) (net.Conn, error)

	// Type returns the transport type.
	Type() Type
}

// Listener accepts inbound transport connections (server-side).
type Listener interface {
	// Accept waits for and returns the next transport connection.
	// For auto-detecting listeners, this peeks at incoming data to determine
	// the transport type and performs any necessary upgrades (e.g., WebSocket).
	Accept() (net.Conn, error)

	// Close stops the listener.
	Close() error

	// Addr returns the listener's network address.
	Addr() net.Addr
}

// --- Dialer Registry ---

// DialerFactory creates a Dialer. Called by NewDialer.
type DialerFactory func(fingerprint FingerprintProfile) Dialer

var (
	dialersMu   sync.RWMutex
	dialerFactories = make(map[Type]DialerFactory)
)

// RegisterDialer registers a dialer factory for a transport type.
// Called from sub-package init() functions.
func RegisterDialer(t Type, factory DialerFactory) {
	dialersMu.Lock()
	defer dialersMu.Unlock()
	dialerFactories[t] = factory
	log.Printf("[transport] Registered dialer: %s", t)
}

// NewDialer creates a Dialer for the given transport type and fingerprint.
func NewDialer(t Type, fingerprint FingerprintProfile) (Dialer, error) {
	log.Printf("[transport] Creating dialer: type=%s, fingerprint=%s", t, fingerprint)

	dialersMu.RLock()
	factory, ok := dialerFactories[t]
	dialersMu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("unknown or unregistered transport type: %s (did you import the sub-package?)", t)
	}

	return factory(fingerprint), nil
}

// --- Server Listener ---

// NewListener creates a Listener that auto-detects transport type.
// It accepts both raw TLS and WebSocket connections on the same port.
func NewListener(cfg *ListenConfig) (Listener, error) {
	log.Printf("[transport] Creating auto-detect listener on %s", cfg.Addr)

	tlsListener, err := tls.Listen("tcp", cfg.Addr, cfg.TLSConfig)
	if err != nil {
		return nil, fmt.Errorf("tls listen on %s: %w", cfg.Addr, err)
	}

	log.Printf("[transport] Listening on %s (TLS, auto-detect WS/raw)", cfg.Addr)
	return &autoDetectListener{inner: tlsListener}, nil
}

// autoDetectListener wraps a TLS listener and auto-detects whether each
// incoming connection is a WebSocket upgrade or raw TLS auth.
type autoDetectListener struct {
	inner net.Listener
}

func (l *autoDetectListener) Accept() (net.Conn, error) {
	conn, err := l.inner.Accept()
	if err != nil {
		return nil, err
	}

	log.Printf("[transport] Accepted connection from %s, will auto-detect transport", conn.RemoteAddr())

	// Wrap in a peekable connection for transport detection.
	// Detection happens lazily on first read — the caller (server auth logic)
	// reads data and the peeked bytes are replayed transparently.
	return newPeekConn(conn), nil
}

func (l *autoDetectListener) Close() error {
	log.Printf("[transport] Closing listener")
	return l.inner.Close()
}

func (l *autoDetectListener) Addr() net.Addr {
	return l.inner.Addr()
}

// PeekConn wraps a net.Conn and buffers the first bytes read,
// allowing transport auto-detection by the server's connection handler.
type PeekConn struct {
	net.Conn
	peeked   []byte
	peekDone bool
}

func newPeekConn(conn net.Conn) *PeekConn {
	return &PeekConn{Conn: conn}
}

// Peek reads up to n bytes without consuming them.
// Subsequent Read calls will replay the peeked bytes first.
func (c *PeekConn) Peek(n int) ([]byte, error) {
	if c.peekDone {
		return c.peeked, nil
	}

	buf := make([]byte, n)
	nr, err := c.Conn.Read(buf)
	if err != nil {
		return nil, err
	}
	c.peeked = buf[:nr]
	c.peekDone = true
	log.Printf("[transport] Peeked %d bytes from %s (first byte=0x%02x)", nr, c.Conn.RemoteAddr(), buf[0])
	return c.peeked, nil
}

func (c *PeekConn) Read(b []byte) (int, error) {
	if len(c.peeked) > 0 {
		n := copy(b, c.peeked)
		c.peeked = c.peeked[n:]
		return n, nil
	}
	return c.Conn.Read(b)
}

// IsWebSocketUpgrade checks if peeked data starts with an HTTP method,
// indicating a WebSocket upgrade request.
func IsWebSocketUpgrade(data []byte) bool {
	if len(data) < 3 {
		return false
	}
	// WebSocket upgrade starts with "GET" (HTTP method)
	return data[0] == 'G' && data[1] == 'E' && data[2] == 'T'
}
