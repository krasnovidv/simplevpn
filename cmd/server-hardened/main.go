// Hardened VPN Server — DPI-resistant
//
// Supports configuration via YAML file and/or CLI flags.
// CLI flags override config file values.
//
// The server auto-detects incoming connections:
//   - WebSocket upgrade → WS transport (anti-DPI)
//   - Raw auth token → legacy TLS transport (backward compatible)
//   - Anything else → decoy HTTP response
//
// # Usage
//
//	# With config file:
//	sudo ./server-hardened -config server.yaml
//
//	# With CLI flags (backward compatible):
//	sudo ./server-hardened -psk "my-secret" -cert cert.pem -key key.pem
//
//	# Mix: config file + flag overrides:
//	sudo ./server-hardened -config server.yaml -listen :8443
package main

import (
	"flag"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"simplevpn/pkg/api"
	"simplevpn/pkg/config"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
	"simplevpn/pkg/transport/ws"
	"simplevpn/pkg/tunnel"
)

func main() {
	// CLI flags
	configFile := flag.String("config", "", "YAML config file path")
	listenAddr := flag.String("listen", "", "TCP listen address (TLS)")
	psk := flag.String("psk", "", "Pre-shared key")
	certFile := flag.String("cert", "", "TLS certificate")
	keyFile := flag.String("key", "", "TLS private key")
	tunIP := flag.String("tun-ip", "", "TUN interface IP (CIDR)")
	tunName := flag.String("tun-name", "", "TUN interface name")
	mtu := flag.Int("mtu", 0, "MTU (reduced for TLS overhead)")
	flag.Parse()

	// Load config: file first, then CLI overrides
	var cfg *config.ServerConfig
	var err error

	if *configFile != "" {
		cfg, err = config.Load(*configFile)
		if err != nil {
			log.Fatalf("Load config: %v", err)
		}
	} else {
		cfg = config.Defaults()
	}

	// CLI flags override config file values
	if *listenAddr != "" {
		cfg.Listen = *listenAddr
	}
	if *psk != "" {
		cfg.PSK = *psk
	}
	if *certFile != "" {
		cfg.CertFile = *certFile
	}
	if *keyFile != "" {
		cfg.KeyFile = *keyFile
	}
	if *tunIP != "" {
		cfg.TunIP = *tunIP
	}
	if *tunName != "" {
		cfg.TunName = *tunName
	}
	if *mtu > 0 {
		cfg.MTU = *mtu
	}

	if err := cfg.Validate(); err != nil {
		log.Fatalf("Config validation: %v", err)
	}

	// -- Derive keys from PSK --
	keys, err := tunnel.DeriveKeys(cfg.PSK)
	if err != nil {
		log.Fatalf("Init crypto: %v", err)
	}
	log.Println("Crypto initialized")

	// -- TUN interface --
	tun, err := tunnel.CreateTUN(cfg.TunName, cfg.TunIP, cfg.MTU)
	if err != nil {
		log.Fatalf("Create TUN: %v", err)
	}
	defer tun.Close()
	log.Printf("TUN %s up: %s", cfg.TunName, cfg.TunIP)

	// -- TLS config --
	tlsCfg, err := tlsdecoy.NewDecoyTLSConfig(cfg.CertFile, cfg.KeyFile)
	if err != nil {
		log.Fatalf("TLS config: %v", err)
	}
	log.Printf("TLS 1.3 configured (cert: %s)", cfg.CertFile)

	// -- Transport listener (auto-detects WS and raw TLS) --
	listener, err := transport.NewListener(&transport.ListenConfig{
		Addr:      cfg.Listen,
		TLSConfig: tlsCfg,
	})
	if err != nil {
		log.Fatalf("Listen %s: %v", cfg.Listen, err)
	}
	defer listener.Close()
	log.Printf("Listening on %s (TLS, auto-detect WS/raw)", cfg.Listen)

	// -- Extra listeners (multi-port) --
	for _, extra := range cfg.Transport.ExtraListens {
		el, err := transport.NewListener(&transport.ListenConfig{
			Addr:      extra,
			TLSConfig: tlsCfg,
		})
		if err != nil {
			log.Printf("WARNING: extra listen %s failed: %v", extra, err)
			continue
		}
		defer el.Close()
		log.Printf("Extra listener on %s", extra)
		go acceptLoop(el, keys, tun)
	}

	// -- Management API --
	var apiServer *api.Server
	if cfg.API.Enabled {
		apiServer = api.NewServer(cfg, "0.2.0")
		apiServer.RegisterWebUI()
		go func() {
			if err := apiServer.ListenAndServeTLS(); err != nil {
				log.Printf("API server error: %v", err)
			}
		}()
	}

	// -- Graceful shutdown --
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("\nShutting down...")
		if apiServer != nil {
			apiServer.Shutdown()
		}
		listener.Close()
		os.Exit(0)
	}()

	// -- Accept loop (main listener) --
	acceptLoop(listener, keys, tun)
}

// activeTunnel is the channel for the current active client tunnel.
var activeTunnel = make(chan *tunnel.Tunnel, 1)

func acceptLoop(listener transport.Listener, keys *tunnel.Keys, tun *tunnel.TunDevice) {
	// Start TUN→client relay (only once for main listener)
	go tunToClientRelay(tun)

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("Accept: %v", err)
			return
		}

		go serveConnection(conn, keys, tun)
	}
}

func tunToClientRelay(tun *tunnel.TunDevice) {
	var current *tunnel.Tunnel
	buf := make([]byte, tunnel.MaxFrameSize)
	for {
		select {
		case t := <-activeTunnel:
			current = t
		default:
		}

		if current == nil {
			select {
			case t := <-activeTunnel:
				current = t
			case <-time.After(100 * time.Millisecond):
				continue
			}
		}

		n, readErr := tun.Read(buf)
		if readErr != nil {
			log.Printf("TUN read: %v", readErr)
			return
		}

		if sendErr := current.Send(buf[:n]); sendErr != nil {
			log.Printf("Send to client: %v", sendErr)
			current = nil
		}
	}
}

func serveConnection(
	conn net.Conn,
	keys *tunnel.Keys,
	tun *tunnel.TunDevice,
) {
	defer conn.Close()
	remoteAddr := conn.RemoteAddr().String()

	// Auto-detect transport: peek first bytes to determine WS vs raw TLS
	peekConn, isPeekable := conn.(*transport.PeekConn)
	if !isPeekable {
		log.Printf("[server] Connection from %s is not peekable, treating as raw TLS", remoteAddr)
		serveRawAuth(conn, keys, tun, remoteAddr)
		return
	}

	// Peek at first bytes with a timeout
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	peeked, err := peekConn.Peek(3)
	conn.SetReadDeadline(time.Time{})
	if err != nil {
		log.Printf("[server] Peek failed from %s: %v -> decoy mode", remoteAddr, err)
		serveDecoy(conn)
		return
	}

	if transport.IsWebSocketUpgrade(peeked) {
		log.Printf("[server] WebSocket upgrade detected from %s (peeked=%x)", remoteAddr, peeked)
		serveWebSocket(peekConn, keys, tun, remoteAddr)
	} else {
		log.Printf("[server] Raw TLS auth detected from %s (peeked=%x)", remoteAddr, peeked)
		serveRawAuth(peekConn, keys, tun, remoteAddr)
	}
}

// serveWebSocket handles a WebSocket client connection.
func serveWebSocket(conn *transport.PeekConn, keys *tunnel.Keys, tun *tunnel.TunDevice, remoteAddr string) {
	// PeekConn.Read() transparently replays peeked bytes,
	// so ServerUpgrade reads the full HTTP request from it.
	wsConn, err := ws.ServerUpgrade(conn, nil)
	if err != nil {
		log.Printf("[server] WS upgrade failed from %s: %v -> decoy mode", remoteAddr, err)
		serveDecoy(conn)
		return
	}
	log.Printf("[server] WebSocket established with %s", remoteAddr)

	// Now authenticate over WebSocket
	serveAuth(wsConn, keys, tun, remoteAddr)
}

// serveRawAuth handles raw TLS auth (legacy protocol).
func serveRawAuth(conn net.Conn, keys *tunnel.Keys, tun *tunnel.TunDevice, remoteAddr string) {
	serveAuth(conn, keys, tun, remoteAddr)
}

// serveAuth performs VPN authentication and starts the tunnel.
// Works with both raw TLS and WebSocket connections.
func serveAuth(conn net.Conn, keys *tunnel.Keys, tun *tunnel.TunDevice, remoteAddr string) {
	// Read auth token (56 bytes)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	authBuf := make([]byte, tlsdecoy.AuthTokenSize)
	if _, err := io.ReadFull(conn, authBuf); err != nil {
		log.Printf("[server] Auth timeout from %s: %v -> decoy mode", remoteAddr, err)
		serveDecoy(conn)
		return
	}
	conn.SetReadDeadline(time.Time{})

	if !tlsdecoy.VerifyAuthToken(keys.Master, authBuf) {
		log.Printf("[server] Auth FAILED from %s -> decoy mode", remoteAddr)
		serveDecoy(conn)
		return
	}

	log.Printf("[server] VPN client authenticated: %s", remoteAddr)
	conn.Write([]byte("OK"))

	tun2 := tunnel.New(keys, conn)
	activeTunnel <- tun2

	// Read packets from client
	for {
		plaintext, err := tun2.Recv()
		if err != nil {
			log.Printf("[server] Client %s disconnected: %v", remoteAddr, err)
			return
		}

		if _, err := tun.Write(plaintext); err != nil {
			log.Printf("[server] TUN write: %v", err)
		}
	}
}

func serveDecoy(conn net.Conn) {
	resp := "HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html; charset=utf-8\r\n" +
		"Server: nginx/1.24.0\r\n" +
		"Connection: close\r\n\r\n" +
		"<html><body><h1>Welcome</h1><p>Service running.</p></body></html>"
	conn.Write([]byte(resp))
}
