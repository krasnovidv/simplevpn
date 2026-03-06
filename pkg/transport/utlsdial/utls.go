// Package utlsdial provides uTLS-based TLS dialing with browser fingerprint mimicry.
//
// Instead of Go's crypto/tls (which has a unique, easily fingerprinted ClientHello),
// this uses uTLS to mimic the TLS ClientHello of real browsers:
//
//   - Chrome: default on Android
//   - Firefox: alternative desktop fingerprint
//   - Safari: default on iOS
//
// The resulting JA3/JA4 fingerprint matches the selected browser,
// making VPN traffic indistinguishable from normal browser HTTPS.
//
// This package is used by the WebSocket transport on the client side.
// It is NOT used on the server side (servers use Go's standard TLS).
package utlsdial

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"syscall"
	"time"

	utls "github.com/refraction-networking/utls"

	"simplevpn/pkg/transport"
)

// profileMap maps FingerprintProfile to uTLS ClientHelloIDs.
var profileMap = map[transport.FingerprintProfile]*utls.ClientHelloID{
	transport.FingerprintChrome:  &utls.HelloChrome_Auto,
	transport.FingerprintFirefox: &utls.HelloFirefox_Auto,
	transport.FingerprintSafari:  &utls.HelloSafari_Auto,
}

// Dial establishes a TCP connection and performs a uTLS handshake
// with the specified browser fingerprint.
//
// Returns a net.Conn ready for VPN protocol (or WebSocket upgrade).
// The connection's TLS ClientHello will match the selected browser.
func Dial(ctx context.Context, cfg *transport.DialConfig) (net.Conn, error) {
	profile := cfg.Fingerprint
	if profile == "" || profile == transport.FingerprintNone {
		profile = transport.FingerprintChrome
	}

	helloID, ok := profileMap[profile]
	if !ok {
		return nil, fmt.Errorf("unknown fingerprint profile: %s", profile)
	}

	log.Printf("[transport/utls] Dialing %s (SNI=%s, fingerprint=%s)", cfg.ServerAddr, cfg.SNI, profile)

	// TCP dial with optional socket control
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

	log.Printf("[transport/utls] TCP connecting to %s ...", cfg.ServerAddr)
	rawConn, err := netDialer.DialContext(dialCtx, "tcp", cfg.ServerAddr)
	if err != nil {
		log.Printf("[transport/utls] TCP dial failed: %v", err)
		return nil, fmt.Errorf("tcp connect to %s: %w", cfg.ServerAddr, err)
	}
	log.Printf("[transport/utls] TCP connected (local=%s)", rawConn.LocalAddr())

	// Build uTLS config from standard tls.Config or defaults
	utlsCfg := &utls.Config{
		ServerName:         cfg.SNI,
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: false,
		NextProtos:         []string{"http/1.1"},
	}
	if cfg.TLSConfig != nil {
		utlsCfg.ServerName = cfg.TLSConfig.ServerName
		utlsCfg.InsecureSkipVerify = cfg.TLSConfig.InsecureSkipVerify
		if len(cfg.TLSConfig.NextProtos) > 0 {
			utlsCfg.NextProtos = cfg.TLSConfig.NextProtos
		}
	}

	// uTLS handshake with browser fingerprint
	log.Printf("[transport/utls] uTLS handshake (SNI=%s, profile=%s) ...", utlsCfg.ServerName, profile)
	tlsConn := utls.UClient(rawConn, utlsCfg, *helloID)
	if err := tlsConn.HandshakeContext(dialCtx); err != nil {
		log.Printf("[transport/utls] uTLS handshake failed: %v", err)
		tlsConn.Close()
		return nil, fmt.Errorf("utls handshake (%s): %w", profile, err)
	}

	cs := tlsConn.ConnectionState()
	log.Printf("[transport/utls] uTLS handshake OK (version=0x%04x, cipher=0x%04x, profile=%s)",
		cs.Version, cs.CipherSuite, profile)

	return tlsConn, nil
}
