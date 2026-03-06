// Package ws implements the WebSocket transport for SimpleVPN.
//
// VPN traffic is wrapped in WebSocket binary frames over HTTPS.
// This makes VPN traffic look like a normal WebSocket application
// (chat, game, etc.) to DPI systems:
//
//   - HTTP Upgrade looks like a normal browser connection
//   - After upgrade, binary frames are indistinguishable from any WS app
//   - Same port 443, same TLS — but now looks like real web traffic
//
// The client performs a WebSocket upgrade after TLS handshake.
// The server auto-detects WS upgrade vs raw TLS auth by peeking
// at the first bytes of the connection.
//
// No external WebSocket library is used — this is a minimal RFC 6455
// implementation to avoid gomobile compatibility issues.
//
// Import for side effects to register the dialer:
//
//	import _ "simplevpn/pkg/transport/ws"
package ws

import (
	"bufio"
	"context"
	"crypto/rand"
	"crypto/sha1"
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"syscall"
	"time"

	"simplevpn/pkg/transport"
	"simplevpn/pkg/transport/utlsdial"
)

func init() {
	transport.RegisterDialer(transport.TypeWS, func(fp transport.FingerprintProfile) transport.Dialer {
		return NewDialer()
	})
}

// WebSocket handshake constants (RFC 6455)
const (
	websocketGUID = "258EAFA5-E914-47DA-95CA-5AB5DC11D85B"
	wsPath        = "/ws"
)

// Dialer establishes WebSocket connections over TLS.
type Dialer struct{}

// NewDialer creates a new WebSocket dialer.
func NewDialer() *Dialer {
	return &Dialer{}
}

// Type returns the transport type.
func (d *Dialer) Type() transport.Type {
	return transport.TypeWS
}

// Dial connects to the server via TCP + TLS (or uTLS) + WebSocket upgrade.
// If a fingerprint profile is set in cfg, uTLS is used for browser mimicry.
// Returns a net.Conn that transparently handles WS binary framing.
func (d *Dialer) Dial(ctx context.Context, cfg *transport.DialConfig) (net.Conn, error) {
	log.Printf("[transport/ws] Dialing %s (SNI=%s, fingerprint=%s)", cfg.ServerAddr, cfg.SNI, cfg.Fingerprint)

	var tlsConn net.Conn
	var err error

	useUTLS := cfg.Fingerprint != "" && cfg.Fingerprint != transport.FingerprintNone
	if useUTLS {
		// uTLS: mimic browser ClientHello
		tlsConn, err = utlsdial.Dial(ctx, cfg)
	} else {
		// Standard Go TLS
		tlsConn, err = dialStandardTLS(ctx, cfg)
	}
	if err != nil {
		return nil, err
	}

	// WebSocket upgrade
	log.Printf("[transport/ws] Performing WebSocket upgrade ...")
	wsConn, err := clientUpgrade(tlsConn, cfg.SNI)
	if err != nil {
		log.Printf("[transport/ws] WebSocket upgrade failed: %v", err)
		tlsConn.Close()
		return nil, fmt.Errorf("ws upgrade: %w", err)
	}

	log.Printf("[transport/ws] WebSocket connection established to %s", cfg.ServerAddr)
	return wsConn, nil
}

// dialStandardTLS establishes a TCP + Go TLS connection (no fingerprint mimicry).
func dialStandardTLS(ctx context.Context, cfg *transport.DialConfig) (net.Conn, error) {
	tlsCfg := cfg.TLSConfig
	if tlsCfg == nil {
		tlsCfg = &tls.Config{
			ServerName: cfg.SNI,
			MinVersion: tls.VersionTLS13,
			NextProtos: []string{"http/1.1"},
		}
	}

	netDialer := &net.Dialer{
		Timeout: 10 * time.Second,
	}
	if cfg.DialControl != nil {
		netDialer.Control = func(network, address string, c syscall.RawConn) error {
			return cfg.DialControl(network, address, c)
		}
	}

	dialCtx := ctx
	if dialCtx == nil {
		var cancel context.CancelFunc
		dialCtx, cancel = context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
	}

	log.Printf("[transport/ws] TCP connecting to %s ...", cfg.ServerAddr)
	rawConn, err := netDialer.DialContext(dialCtx, "tcp", cfg.ServerAddr)
	if err != nil {
		log.Printf("[transport/ws] TCP dial failed: %v", err)
		return nil, fmt.Errorf("tcp connect to %s: %w", cfg.ServerAddr, err)
	}
	log.Printf("[transport/ws] TCP connected (local=%s)", rawConn.LocalAddr())

	log.Printf("[transport/ws] TLS handshake (SNI=%s) ...", tlsCfg.ServerName)
	tlsConn := tls.Client(rawConn, tlsCfg)
	if err := tlsConn.HandshakeContext(dialCtx); err != nil {
		log.Printf("[transport/ws] TLS handshake failed: %v", err)
		tlsConn.Close()
		return nil, fmt.Errorf("tls handshake: %w", err)
	}
	cs := tlsConn.ConnectionState()
	log.Printf("[transport/ws] TLS handshake OK (version=0x%04x, cipher=0x%04x)", cs.Version, cs.CipherSuite)

	return tlsConn, nil
}

// clientUpgrade performs the WebSocket client handshake.
func clientUpgrade(conn net.Conn, host string) (*Conn, error) {
	// Generate random key
	keyBytes := make([]byte, 16)
	if _, err := rand.Read(keyBytes); err != nil {
		return nil, fmt.Errorf("generate ws key: %w", err)
	}
	wsKey := base64.StdEncoding.EncodeToString(keyBytes)
	expectedAccept := computeAcceptKey(wsKey)

	// Send upgrade request
	req := fmt.Sprintf(
		"GET %s HTTP/1.1\r\n"+
			"Host: %s\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Key: %s\r\n"+
			"Sec-WebSocket-Version: 13\r\n"+
			"Origin: https://%s\r\n"+
			"\r\n",
		wsPath, host, wsKey, host,
	)

	log.Printf("[transport/ws] Sending upgrade request (key=%s...)", wsKey[:8])
	if _, err := conn.Write([]byte(req)); err != nil {
		return nil, fmt.Errorf("send upgrade request: %w", err)
	}

	// Read response
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	conn.SetReadDeadline(time.Time{})
	if err != nil {
		return nil, fmt.Errorf("read upgrade response: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusSwitchingProtocols {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("upgrade rejected: status=%d body=%q", resp.StatusCode, body)
	}

	// Verify accept key
	gotAccept := resp.Header.Get("Sec-WebSocket-Accept")
	if gotAccept != expectedAccept {
		return nil, fmt.Errorf("invalid Sec-WebSocket-Accept: got=%q want=%q", gotAccept, expectedAccept)
	}

	log.Printf("[transport/ws] Upgrade accepted (101 Switching Protocols)")
	return WrapClient(conn), nil
}

// ServerUpgrade performs the server-side WebSocket handshake.
// It reads the HTTP upgrade request from the connection and sends
// the 101 Switching Protocols response.
//
// The peekedData contains any bytes already read from the connection
// (from auto-detection). These bytes are prepended to the request.
func ServerUpgrade(conn net.Conn, peekedData []byte) (*Conn, error) {
	log.Printf("[transport/ws] Server processing WebSocket upgrade from %s", conn.RemoteAddr())

	// Create a reader that replays peeked data + remaining connection data
	var reader io.Reader
	if len(peekedData) > 0 {
		reader = io.MultiReader(
			strings.NewReader(string(peekedData)),
			conn,
		)
	} else {
		reader = conn
	}

	// Parse HTTP request
	req, err := http.ReadRequest(bufio.NewReader(reader))
	if err != nil {
		return nil, fmt.Errorf("read upgrade request: %w", err)
	}

	// Validate upgrade request
	if !strings.EqualFold(req.Header.Get("Upgrade"), "websocket") {
		conn.Write([]byte("HTTP/1.1 400 Bad Request\r\n\r\n"))
		return nil, fmt.Errorf("not a WebSocket upgrade request")
	}

	wsKey := req.Header.Get("Sec-WebSocket-Key")
	if wsKey == "" {
		conn.Write([]byte("HTTP/1.1 400 Bad Request\r\n\r\n"))
		return nil, fmt.Errorf("missing Sec-WebSocket-Key")
	}

	acceptKey := computeAcceptKey(wsKey)

	// Send 101 Switching Protocols
	resp := fmt.Sprintf(
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n"+
			"\r\n",
		acceptKey,
	)

	if _, err := conn.Write([]byte(resp)); err != nil {
		return nil, fmt.Errorf("send upgrade response: %w", err)
	}

	log.Printf("[transport/ws] WebSocket upgrade complete for %s (path=%s)", conn.RemoteAddr(), req.URL.Path)
	return WrapServer(conn), nil
}

// computeAcceptKey calculates the Sec-WebSocket-Accept value (RFC 6455 §4.2.2).
func computeAcceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key))
	h.Write([]byte(websocketGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}
