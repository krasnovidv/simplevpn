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
// The fd parameter is the file descriptor of the TUN device, which must be
// created by the platform layer (NEPacketTunnelProvider on iOS, VpnService on Android).
package vpnlib

import (
	"crypto/sha256"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sync"
	"time"

	"simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/tunnel"
)

// Config is the JSON configuration passed from the mobile app.
type Config struct {
	Server string `json:"server"` // host:port
	PSK    string `json:"psk"`
	SNI    string `json:"sni"`
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

// Connect establishes a VPN connection.
//   - configJSON: JSON string with server, psk, sni fields
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

	log.Printf("[vpnlib] Connect called, config length=%d", len(configJSON))

	var cfg Config
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		setStatus("disconnected")
		return fmt.Errorf("parse config: %w", err)
	}

	if cfg.Server == "" || cfg.PSK == "" {
		setStatus("disconnected")
		return fmt.Errorf("server and psk are required")
	}

	// Derive keys
	keys, err := tunnel.DeriveKeys(cfg.PSK)
	if err != nil {
		setStatus("disconnected")
		return fmt.Errorf("derive keys: %w", err)
	}

	// TUN file from fd
	tunFile := os.NewFile(uintptr(fd), "tun")
	if tunFile == nil {
		setStatus("disconnected")
		return fmt.Errorf("invalid tun fd: %d", fd)
	}

	// Resolve SNI
	sni := cfg.SNI
	if sni == "" {
		h, _, err := net.SplitHostPort(cfg.Server)
		if err == nil {
			sni = h
		}
	}

	// TLS connection
	log.Printf("[vpnlib] Connecting to %s (SNI: %s)", cfg.Server, sni)
	setStatus("connecting")

	tlsCfg := &tls.Config{
		ServerName: sni,
		MinVersion: tls.VersionTLS13,
		NextProtos: []string{"h2", "http/1.1"},
	}

	rawConn, err := net.DialTimeout("tcp", cfg.Server, 10*time.Second)
	if err != nil {
		setStatus("disconnected")
		return fmt.Errorf("tcp connect: %w", err)
	}

	tlsConn := tls.Client(rawConn, tlsCfg)
	if err := tlsConn.Handshake(); err != nil {
		tlsConn.Close()
		setStatus("disconnected")
		return fmt.Errorf("tls handshake: %w", err)
	}
	log.Printf("[vpnlib] TLS handshake OK")

	// Authenticate
	masterKey := sha256.Sum256([]byte(cfg.PSK))
	_, authToken, err := tlsdecoy.GenerateAuthToken(masterKey)
	if err != nil {
		tlsConn.Close()
		setStatus("disconnected")
		return fmt.Errorf("generate auth: %w", err)
	}

	if _, err := tlsConn.Write(authToken); err != nil {
		tlsConn.Close()
		setStatus("disconnected")
		return fmt.Errorf("send auth: %w", err)
	}

	okBuf := make([]byte, 2)
	tlsConn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(tlsConn, okBuf); err != nil {
		tlsConn.Close()
		setStatus("disconnected")
		return fmt.Errorf("auth response: %w", err)
	}
	tlsConn.SetReadDeadline(time.Time{})

	if string(okBuf) != "OK" {
		tlsConn.Close()
		setStatus("disconnected")
		return fmt.Errorf("auth rejected")
	}
	log.Printf("[vpnlib] Authenticated")

	// Store connection state
	current.mu.Lock()
	current.connected = true
	current.conn = tlsConn
	current.tunFile = tunFile
	current.status = "connected"
	stopCh := current.stopCh
	current.mu.Unlock()

	log.Printf("[vpnlib] Tunnel active")

	// Create tunnel
	tun := tunnel.New(keys, tlsConn)

	// Buffers
	encBuf := make([]byte, 0, tunnel.MaxFrameSize+crypto.Overhead)
	obfsBuf := make([]byte, 0, tunnel.MaxFrameSize+crypto.Overhead+obfs.HeaderSize+obfs.MaxPad)
	_, _ = encBuf, obfsBuf // used by tunnel internally

	// TUN → TLS (send)
	go func() {
		buf := make([]byte, tunnel.MaxFrameSize)
		for {
			select {
			case <-stopCh:
				return
			default:
			}

			n, err := tunFile.Read(buf)
			if err != nil {
				log.Printf("[vpnlib] TUN read: %v", err)
				return
			}

			if err := tun.Send(buf[:n]); err != nil {
				log.Printf("[vpnlib] Send: %v", err)
				return
			}
		}
	}()

	// TLS → TUN (receive) — blocks until disconnect
	for {
		select {
		case <-stopCh:
			cleanup(tlsConn, tunFile)
			return nil
		default:
		}

		plaintext, err := tun.Recv()
		if err != nil {
			log.Printf("[vpnlib] Recv: %v", err)
			cleanup(tlsConn, tunFile)
			return err
		}

		if _, err := tunFile.Write(plaintext); err != nil {
			log.Printf("[vpnlib] TUN write: %v", err)
			cleanup(tlsConn, tunFile)
			return err
		}
	}
}

// Disconnect closes the VPN connection.
func Disconnect() {
	current.mu.Lock()
	defer current.mu.Unlock()

	if !current.connected {
		return
	}

	log.Printf("[vpnlib] Disconnect called")

	close(current.stopCh)
	if current.conn != nil {
		current.conn.Close()
	}
	current.connected = false
	current.status = "disconnected"
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
