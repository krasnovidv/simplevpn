// Hardened VPN Server — DPI-resistant, multi-client
//
// Supports configuration via YAML file and/or CLI flags.
// CLI flags override config file values.
//
// The server auto-detects incoming connections:
//   - WebSocket upgrade → WS transport (anti-DPI)
//   - Raw credential auth → legacy TLS transport (backward compatible)
//   - Anything else → decoy HTTP response
//
// # Usage
//
//	# With config file:
//	sudo ./server-hardened -config server.yaml
//
//	# With CLI flags:
//	sudo ./server-hardened -server-key "my-secret" -users-file users.yaml -cert cert.pem -key key.pem
//
//	# Mix: config file + flag overrides:
//	sudo ./server-hardened -config server.yaml -listen :8443
package main

import (
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"log"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"simplevpn/pkg/api"
	"simplevpn/pkg/auth"
	"simplevpn/pkg/config"
	"simplevpn/pkg/ippool"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
	"simplevpn/pkg/transport/ws"
	"simplevpn/pkg/tunnel"
)

// clientSession holds the active tunnel and stats for a connected client.
type clientSession struct {
	id       string
	username string
	conn     net.Conn     // closed by disconnect callback to terminate recv loop
	tun      *tunnel.Tunnel
	bytesIn  atomic.Int64 // plaintext bytes received from client (client→TUN)
	bytesOut atomic.Int64 // plaintext bytes sent to client (TUN→client)
}

// apiSrv is the management API server; nil when API is disabled.
var apiSrv *api.Server

// newSessionID returns a 16-char hex random session ID (URL-safe, no colons).
func newSessionID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		// Fallback: use time — should never happen.
		log.Printf("[server] WARNING: rand.Read failed: %v", err)
	}
	return hex.EncodeToString(b[:])
}

func main() {
	// CLI flags
	configFile := flag.String("config", "", "YAML config file path")
	listenAddr := flag.String("listen", "", "TCP listen address (TLS)")
	serverKey := flag.String("server-key", "", "Server key for tunnel encryption")
	usersFile := flag.String("users-file", "", "Path to users YAML file")
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
	if *serverKey != "" {
		cfg.ServerKey = *serverKey
	}
	if *usersFile != "" {
		cfg.UsersFile = *usersFile
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

	// -- Load user store --
	store, err := auth.NewFileStore(cfg.UsersFile)
	if err != nil {
		log.Fatalf("Load users: %v", err)
	}
	log.Printf("[server] User store loaded from %s", cfg.UsersFile)

	// -- Derive keys from server key --
	keys, err := tunnel.DeriveKeys(cfg.ServerKey)
	if err != nil {
		log.Fatalf("Init crypto: %v", err)
	}
	log.Println("Crypto initialized")

	// -- TUN interface --
	tunDev, err := tunnel.CreateTUN(cfg.TunName, cfg.TunIP, cfg.MTU)
	if err != nil {
		log.Fatalf("Create TUN: %v", err)
	}
	defer tunDev.Close()
	log.Printf("TUN %s up: %s", cfg.TunName, cfg.TunIP)

	// -- IP pool for client address assignment --
	tunPrefix, err := netip.ParsePrefix(cfg.TunIP)
	if err != nil {
		log.Fatalf("Parse tun_ip: %v", err)
	}
	pool, err := ippool.New(cfg.ClientSubnet, tunPrefix.Addr())
	if err != nil {
		log.Fatalf("IP pool: %v", err)
	}
	log.Printf("[server] IP pool ready: subnet=%s size=%d", cfg.ClientSubnet, pool.Size())

	// -- Per-client session map: netip.Addr → *clientSession --
	var sessions sync.Map

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
		go acceptLoop(el, keys, store, tunDev, pool, &sessions)
	}

	// -- Management API --
	if cfg.API.Enabled {
		apiSrv = api.NewServer(cfg, "0.4.0", store)
		apiSrv.RegisterWebUI()
		// Disconnect callback: close the client's conn so the recv-loop in
		// serveAuth returns an error and triggers deferred cleanup + pool release.
		apiSrv.SetDisconnectFunc(func(clientID string) error {
			found := false
			sessions.Range(func(_, val interface{}) bool {
				sess := val.(*clientSession)
				if sess.id == clientID {
					log.Printf("[server] DEBUG disconnect requested: id=%s user=%q", clientID, sess.username)
					sess.conn.Close()
					found = true
					return false
				}
				return true
			})
			if !found {
				return fmt.Errorf("client %s not found", clientID)
			}
			return nil
		})
		go func() {
			if err := apiSrv.ListenAndServeTLS(); err != nil {
				log.Printf("API server error: %v", err)
			}
		}()
		go func() {
			if err := apiSrv.ListenAndServeHTTP(); err != nil {
				log.Printf("HTTP public server error: %v", err)
			}
		}()
	}

	// -- TUN→client relay (single goroutine, routes by dest IP) --
	go tunToClientRelay(tunDev, &sessions)

	// -- Graceful shutdown --
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("\nShutting down...")
		if apiSrv != nil {
			apiSrv.Shutdown()
		}
		listener.Close()
		os.Exit(0)
	}()

	// -- Accept loop (main listener) --
	acceptLoop(listener, keys, store, tunDev, pool, &sessions)
}

// tunToClientRelay reads packets from the TUN device and routes each to the
// matching client session by inspecting the IPv4 destination address (bytes 16-19).
// Packets for unknown destinations are dropped with a debug log.
func tunToClientRelay(tun *tunnel.TunDevice, sessions *sync.Map) {
	buf := make([]byte, tunnel.MaxFrameSize)
	for {
		n, err := tun.Read(buf)
		if err != nil {
			log.Printf("[relay] TUN read error: %v", err)
			return
		}

		dst, err := dstFromIPv4(buf[:n])
		if err != nil {
			log.Printf("[relay] DEBUG drop packet: %v", err)
			continue
		}

		val, ok := sessions.Load(dst)
		if !ok {
			log.Printf("[relay] DEBUG drop packet: no session for dst=%s", dst)
			continue
		}

		sess := val.(*clientSession)
		if err := sess.tun.Send(buf[:n]); err != nil {
			log.Printf("[relay] Send to %s (user=%q): %v", dst, sess.username, err)
		} else {
			sess.bytesOut.Add(int64(n))
		}
	}
}

// dstFromIPv4 extracts the destination IP address from an IPv4 packet.
// Returns an error if the packet is too short or not IPv4.
func dstFromIPv4(packet []byte) (netip.Addr, error) {
	if len(packet) < 20 {
		return netip.Addr{}, fmt.Errorf("packet too short (%d bytes, need ≥20)", len(packet))
	}
	if packet[0]>>4 != 4 {
		return netip.Addr{}, fmt.Errorf("not IPv4 (version nibble=%d)", packet[0]>>4)
	}
	return netip.AddrFrom4([4]byte(packet[16:20])), nil
}

func acceptLoop(
	listener transport.Listener,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tun *tunnel.TunDevice,
	pool *ippool.Pool,
	sessions *sync.Map,
) {
	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("Accept: %v", err)
			return
		}

		go serveConnection(conn, keys, store, tun, pool, sessions)
	}
}

func serveConnection(
	conn net.Conn,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tun *tunnel.TunDevice,
	pool *ippool.Pool,
	sessions *sync.Map,
) {
	defer conn.Close()
	remoteAddr := conn.RemoteAddr().String()

	peekConn, isPeekable := conn.(*transport.PeekConn)
	if !isPeekable {
		log.Printf("[server] Connection from %s is not peekable, treating as raw TLS", remoteAddr)
		serveRawAuth(conn, keys, store, tun, remoteAddr, pool, sessions)
		return
	}

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
		serveWebSocket(peekConn, keys, store, tun, remoteAddr, pool, sessions)
	} else {
		log.Printf("[server] Raw TLS auth detected from %s (peeked=%x)", remoteAddr, peeked)
		serveRawAuth(peekConn, keys, store, tun, remoteAddr, pool, sessions)
	}
}

func serveWebSocket(
	conn *transport.PeekConn,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tun *tunnel.TunDevice,
	remoteAddr string,
	pool *ippool.Pool,
	sessions *sync.Map,
) {
	wsConn, err := ws.ServerUpgrade(conn, nil)
	if err != nil {
		log.Printf("[server] WS upgrade failed from %s: %v -> decoy mode", remoteAddr, err)
		serveDecoy(conn)
		return
	}
	log.Printf("[server] WebSocket established with %s", remoteAddr)
	serveAuth(wsConn, keys, store, tun, remoteAddr, pool, sessions)
}

func serveRawAuth(
	conn net.Conn,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tun *tunnel.TunDevice,
	remoteAddr string,
	pool *ippool.Pool,
	sessions *sync.Map,
) {
	serveAuth(conn, keys, store, tun, remoteAddr, pool, sessions)
}

// serveAuth authenticates the client, assigns an IP from the pool, and runs the tunnel.
func serveAuth(
	conn net.Conn,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tunDev *tunnel.TunDevice,
	remoteAddr string,
	pool *ippool.Pool,
	sessions *sync.Map,
) {
	username, password, err := tlsdecoy.ReadCredAuth(conn)
	if err != nil {
		log.Printf("[server] Credential read failed from %s: %v -> decoy mode", remoteAddr, err)
		serveDecoy(conn)
		return
	}

	if !store.Authenticate(username, password) {
		log.Printf("[server] Auth FAILED for user %q from %s -> decoy mode", username, remoteAddr)
		serveDecoy(conn)
		return
	}

	// Allocate a client IP from the pool.
	assignedIP, err := pool.Allocate()
	if err != nil {
		log.Printf("[server] Pool exhausted, rejecting user=%q from %s: %v", username, remoteAddr, err)
		conn.Close()
		return
	}
	assignedPrefix := netip.PrefixFrom(assignedIP, pool.Prefix().Bits())
	defer pool.Release(assignedIP)

	log.Printf("[server] VPN client authenticated: user=%q addr=%s assigned=%s", username, remoteAddr, assignedPrefix)

	// Respond with the assigned IP so the client can configure its TUN.
	if _, err := fmt.Fprintf(conn, "OK %s\n", assignedPrefix.String()); err != nil {
		log.Printf("[server] Failed to send OK to %s: %v", remoteAddr, err)
		return
	}

	sessionID := newSessionID()
	tun2 := tunnel.New(keys, conn)
	sess := &clientSession{
		id:       sessionID,
		username: username,
		conn:     conn,
		tun:      tun2,
	}

	// Register session for packet routing.
	sessions.Store(assignedIP, sess)
	defer sessions.Delete(assignedIP)

	// Register with management API.
	if apiSrv != nil {
		apiSrv.RegisterClient(&api.ClientInfo{
			ID:          sessionID,
			RemoteAddr:  remoteAddr,
			ConnectedAt: time.Now(),
			AssignedIP:  assignedPrefix.String(),
			Username:    username,
		})
		defer apiSrv.UnregisterClient(sessionID)
	}

	log.Printf("[server] DEBUG session registered: id=%s ip=%s user=%q", sessionID, assignedIP, username)

	// Per-session stats ticker: update API every second.
	if apiSrv != nil {
		done := make(chan struct{})
		defer close(done)
		go func() {
			ticker := time.NewTicker(time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-done:
					return
				case <-ticker.C:
					apiSrv.UpdateClientStats(sessionID, sess.bytesIn.Load(), sess.bytesOut.Load())
				}
			}
		}()
	}

	// Receive packets from client → write to TUN.
	for {
		plaintext, err := tun2.Recv()
		if err != nil {
			log.Printf("[server] Client %s (user=%q ip=%s) disconnected: %v", remoteAddr, username, assignedIP, err)
			return
		}

		if _, werr := tunDev.Write(plaintext); werr != nil {
			log.Printf("[server] TUN write: %v", werr)
		} else {
			sess.bytesIn.Add(int64(len(plaintext)))
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
