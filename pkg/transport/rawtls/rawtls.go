// Package rawtls implements the raw TLS transport for SimpleVPN.
//
// This is the original transport: direct TLS 1.3 connection to the server.
// The client connects via TCP, performs a TLS handshake, and then the
// VPN protocol (auth + encrypted tunnel) runs directly over the TLS stream.
//
// This transport preserves backward compatibility with existing clients
// and servers that don't support WebSocket or uTLS.
//
// Import for side effects to register the dialer:
//
//	import _ "simplevpn/pkg/transport/rawtls"
package rawtls

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"syscall"
	"time"

	"simplevpn/pkg/transport"
)

func init() {
	transport.RegisterDialer(transport.TypeTLS, func(fp transport.FingerprintProfile) transport.Dialer {
		return New()
	})
}

// Dialer establishes raw TLS connections to the VPN server.
type Dialer struct{}

// New creates a new raw TLS dialer.
func New() *Dialer {
	return &Dialer{}
}

// Type returns the transport type.
func (d *Dialer) Type() transport.Type {
	return transport.TypeTLS
}

// Dial connects to the server via TCP + TLS 1.3 and returns a connection
// ready for VPN authentication.
func (d *Dialer) Dial(ctx context.Context, cfg *transport.DialConfig) (net.Conn, error) {
	log.Printf("[transport/tls] Dialing %s (SNI=%s)", cfg.ServerAddr, cfg.SNI)

	// Build TLS config
	tlsCfg := cfg.TLSConfig
	if tlsCfg == nil {
		tlsCfg = &tls.Config{
			ServerName: cfg.SNI,
			MinVersion: tls.VersionTLS13,
			NextProtos: []string{"h2", "http/1.1"},
		}
	}

	// TCP dial with optional socket control (e.g., Android VPN protect)
	dialer := &net.Dialer{
		Timeout: 10 * time.Second,
	}
	if cfg.DialControl != nil {
		dialer.Control = func(network, address string, c syscall.RawConn) error {
			return cfg.DialControl(network, address, c)
		}
	}

	dialCtx := ctx
	if dialCtx == nil {
		var cancel context.CancelFunc
		dialCtx, cancel = context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
	}

	log.Printf("[transport/tls] TCP connecting to %s ...", cfg.ServerAddr)
	rawConn, err := dialer.DialContext(dialCtx, "tcp", cfg.ServerAddr)
	if err != nil {
		log.Printf("[transport/tls] TCP dial failed: %v", err)
		return nil, fmt.Errorf("tcp connect to %s: %w", cfg.ServerAddr, err)
	}
	log.Printf("[transport/tls] TCP connected (local=%s)", rawConn.LocalAddr())

	// TLS handshake
	log.Printf("[transport/tls] TLS handshake (SNI=%s) ...", tlsCfg.ServerName)
	tlsConn := tls.Client(rawConn, tlsCfg)
	if err := tlsConn.HandshakeContext(dialCtx); err != nil {
		log.Printf("[transport/tls] TLS handshake failed: %v", err)
		tlsConn.Close()
		return nil, fmt.Errorf("tls handshake: %w", err)
	}

	cs := tlsConn.ConnectionState()
	log.Printf("[transport/tls] TLS handshake OK (version=0x%04x, cipher=0x%04x, proto=%s)",
		cs.Version, cs.CipherSuite, cs.NegotiatedProtocol)

	return tlsConn, nil
}
