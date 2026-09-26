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
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"simplevpn/pkg/api"
	"simplevpn/pkg/auth"
	"simplevpn/pkg/auththrottle"
	"simplevpn/pkg/config"
	"simplevpn/pkg/ippool"
	"simplevpn/pkg/logx"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
	"simplevpn/pkg/transport/ws"
	"simplevpn/pkg/tunnel"
)

// clientSession holds the active tunnel and stats for a connected client.
type clientSession struct {
	id       string
	username string
	conn     net.Conn // closed by disconnect callback to terminate recv loop
	tun      *tunnel.Tunnel
	bytesIn  atomic.Int64 // plaintext bytes received from client (client→TUN)
	bytesOut atomic.Int64 // plaintext bytes sent to client (TUN→client)

	// out queues packets for this client. The TUN relay only ever enqueues
	// (dropping when full), and sessionSender does the blocking network
	// write — so one slow or dead client can never stall the others.
	out     chan []byte
	dropped atomic.Int64 // packets dropped because out was full
}

const (
	// sessionQueueLen is ~1.4 MB of full-size packets per client.
	sessionQueueLen = 1024
	// sendTimeout: a client that cannot take a single packet for this long
	// is gone (half-open flow, dead radio); its session is torn down.
	sendTimeout = 20 * time.Second
	// preAuthTimeout bounds everything before a client is authenticated:
	// TLS handshake, transport detection, WebSocket upgrade.
	preAuthTimeout = 15 * time.Second
	// maxPreAuth caps connections that have not authenticated yet, so a
	// flood of idle handshakes cannot exhaust the process.
	maxPreAuth = 4096
	// maxSessionsPerUser caps concurrent sessions of one account. A phone
	// that reconnects after its network dropped leaves a ghost session
	// behind until TCP notices; the oldest session is evicted first.
	maxSessionsPerUser = 4
)

// preAuthSlots is the semaphore behind maxPreAuth.
var preAuthSlots = make(chan struct{}, maxPreAuth)

// serverTunAddr is the server's own tunnel address (e.g. 10.0.0.1). Clients
// may talk to it — the app's liveness probes ping it — but not to each other.
var serverTunAddr netip.Addr

var (
	userSessionsMu sync.Mutex
	userSessions   = map[string][]*clientSession{}
)

// trackUserSession registers s under its account, evicting the oldest
// sessions beyond maxSessionsPerUser. The returned func unregisters s.
func trackUserSession(s *clientSession) (untrack func()) {
	userSessionsMu.Lock()
	list := append(userSessions[s.username], s)
	var evict []*clientSession
	for len(list) > maxSessionsPerUser {
		evict = append(evict, list[0])
		list = list[1:]
	}
	userSessions[s.username] = list
	userSessionsMu.Unlock()

	for _, old := range evict {
		log.Printf("[server] session limit: evicting oldest session %s", old.id)
		old.conn.Close()
	}
	return func() {
		userSessionsMu.Lock()
		defer userSessionsMu.Unlock()
		list := userSessions[s.username]
		for i, x := range list {
			if x == s {
				list = append(list[:i:i], list[i+1:]...)
				break
			}
		}
		if len(list) == 0 {
			delete(userSessions, s.username)
		} else {
			userSessions[s.username] = list
		}
	}
}

// sessionSender drains sess.out onto the client's connection until done is
// closed or a write fails; a failed or timed-out write closes the conn,
// which ends the session's receive loop and with it the session.
func sessionSender(sess *clientSession, done <-chan struct{}) {
	for {
		select {
		case <-done:
			return
		case pkt := <-sess.out:
			sess.conn.SetWriteDeadline(time.Now().Add(sendTimeout))
			if err := sess.tun.Send(pkt); err != nil {
				logx.Debugf("[relay] send to session %s failed: %v", sess.id, err)
				sess.conn.Close()
				return
			}
			sess.bytesOut.Add(int64(len(pkt)))
		}
	}
}

// apiSrv is the management API server; nil when API is disabled.
var apiSrv *api.Server

// authGate throttles repeated failed VPN credential attempts per source IP to
// blunt online password guessing and limit bcrypt CPU exhaustion.
var authGate = auththrottle.New(auththrottle.DefaultMaxFailures, auththrottle.DefaultWindow)

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

	// Apply the configured log level so verbose/privacy-sensitive output
	// (connection metadata, usernames, per-packet events) is gated.
	logx.SetLevelString(cfg.LogLevel)

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
	serverTunAddr = tunPrefix.Addr()
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
					logx.Debugf("[server] disconnect requested: id=%s user=%q", clientID, sess.username)
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
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			apiSrv.Shutdown(ctx)
			cancel()
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
			logx.Debugf("[relay] drop packet: %v", err)
			continue
		}

		val, ok := sessions.Load(dst)
		if !ok {
			logx.Debugf("[relay] drop packet: no session for dst=%s", dst)
			continue
		}

		sess := val.(*clientSession)
		pkt := make([]byte, n)
		copy(pkt, buf[:n])
		select {
		case sess.out <- pkt:
		default:
			// The client is not keeping up; drop like a full router queue
			// would, rather than stall every other client behind it.
			if sess.dropped.Add(1)%1000 == 1 {
				logx.Debugf("[relay] queue full for session %s, dropping", sess.id)
			}
		}
	}
}

// ipv4Addrs returns the source and destination of an IPv4 packet.
func ipv4Addrs(p []byte) (src, dst netip.Addr, ok bool) {
	if len(p) < 20 || p[0]>>4 != 4 {
		return netip.Addr{}, netip.Addr{}, false
	}
	return netip.AddrFrom4([4]byte(p[12:16])), netip.AddrFrom4([4]byte(p[16:20])), true
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

	// Defense-in-depth: a panic while parsing attacker-controlled wire data
	// (e.g. a malformed frame) must only kill this connection's goroutine, never
	// the whole server process.
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[server] recovered from panic handling %s: %v", remoteAddr, r)
		}
	}()

	select {
	case preAuthSlots <- struct{}{}:
	default:
		log.Printf("[server] Too many unauthenticated connections, dropping %s", remoteAddr)
		return
	}
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { <-preAuthSlots }) }
	defer release()

	// Everything up to a successful login must finish within preAuthTimeout.
	// ReadCredAuth sets and clears its own read deadline, which also lifts
	// this one for the tunnel that follows.
	conn.SetReadDeadline(time.Now().Add(preAuthTimeout))

	peekConn, isPeekable := conn.(*transport.PeekConn)
	if !isPeekable {
		serveAuth(conn, keys, store, tun, remoteAddr, pool, sessions, release, rejectRaw)
		return
	}

	peeked, err := peekConn.Peek(3)
	if err != nil {
		// A client that completes TLS and then says nothing gets nothing
		// back — exactly what an idle nginx connection would do.
		logx.Debugf("[server] Peek failed from %s: %v", remoteAddr, err)
		return
	}

	// Credential frames start with a version byte (0x02); anything that
	// starts like an HTTP method is handled as HTTP.
	if peeked[0] >= 'A' && peeked[0] <= 'Z' {
		serveHTTP(peekConn, keys, store, tun, remoteAddr, pool, sessions, release)
	} else {
		serveAuth(peekConn, keys, store, tun, remoteAddr, pool, sessions, release, rejectRaw)
	}
}

// serveHTTP handles a connection that speaks HTTP: a WebSocket upgrade on the
// tunnel path becomes a tunnel; any other request is answered by the decoy site.
func serveHTTP(
	conn *transport.PeekConn,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tun *tunnel.TunDevice,
	remoteAddr string,
	pool *ippool.Pool,
	sessions *sync.Map,
	release func(),
) {
	wsConn, err := ws.ServerUpgrade(conn, nil)
	if err != nil {
		var nu *ws.NotUpgradeError
		if errors.As(err, &nu) {
			tlsdecoy.WriteDecoyResponse(conn, nu.Method, nu.Path)
		} else {
			logx.Debugf("[server] Bad HTTP request from %s: %v", remoteAddr, err)
			tlsdecoy.WriteBadRequest(conn)
		}
		return
	}
	log.Printf("[server] WebSocket established with %s", remoteAddr)
	// After a 101 there is no HTTP left to answer with; a failed login just
	// closes the socket like a WebSocket app rejecting a session.
	serveAuth(wsConn, keys, store, tun, remoteAddr, pool, sessions, release, func(net.Conn) {})
}

// rejectRaw answers a failed raw-TLS login the way nginx answers bytes that
// are not HTTP.
func rejectRaw(conn net.Conn) { tlsdecoy.WriteBadRequest(conn) }

// serveAuth authenticates the client, assigns an IP from the pool, and runs the tunnel.
// release frees the connection's pre-auth slot; reject answers a failed login.
func serveAuth(
	conn net.Conn,
	keys *tunnel.Keys,
	store *auth.FileStore,
	tunDev *tunnel.TunDevice,
	remoteAddr string,
	pool *ippool.Pool,
	sessions *sync.Map,
	release func(),
	reject func(net.Conn),
) {
	// Throttle brute-force attempts before doing any (expensive) work.
	ip, _, splitErr := net.SplitHostPort(remoteAddr)
	if splitErr != nil {
		ip = remoteAddr
	}
	if !authGate.Allowed(ip) {
		log.Printf("[server] Auth throttled for %s (too many failed attempts)", remoteAddr)
		reject(conn)
		return
	}

	username, password, err := tlsdecoy.ReadCredAuth(conn)
	if err != nil {
		log.Printf("[server] Credential read failed from %s: %v", remoteAddr, err)
		reject(conn)
		return
	}

	if !store.Authenticate(username, password) {
		authGate.Fail(ip)
		log.Printf("[server] Auth FAILED from %s", remoteAddr)
		reject(conn)
		return
	}

	// Successful login clears the IP's failure count.
	authGate.Reset(ip)
	release()

	// Allocate a client IP from the pool.
	assignedIP, err := pool.Allocate()
	if err != nil {
		log.Printf("[server] Pool exhausted, rejecting %s: %v", remoteAddr, err)
		return
	}
	assignedPrefix := netip.PrefixFrom(assignedIP, pool.Prefix().Bits())
	defer pool.Release(assignedIP)

	log.Printf("[server] VPN client authenticated: addr=%s assigned=%s", remoteAddr, assignedPrefix)
	logx.Debugf("[server] authenticated user=%q addr=%s assigned=%s", username, remoteAddr, assignedPrefix)

	// Respond with the assigned IP so the client can configure its TUN.
	// Random trailing spaces (clients trim them) keep the reply's size from
	// being a constant that marks the handshake.
	var pad [1]byte
	rand.Read(pad[:])
	okLine := "OK " + assignedPrefix.String() + strings.Repeat(" ", int(pad[0]%128)) + "\n"
	conn.SetWriteDeadline(time.Now().Add(sendTimeout))
	if _, err := io.WriteString(conn, okLine); err != nil {
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
		out:      make(chan []byte, sessionQueueLen),
	}

	// Register session for packet routing.
	sessions.Store(assignedIP, sess)
	defer sessions.Delete(assignedIP)
	defer trackUserSession(sess)()

	senderDone := make(chan struct{})
	defer close(senderDone)
	go sessionSender(sess, senderDone)

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

	logx.Debugf("[server] session registered: id=%s ip=%s user=%q", sessionID, assignedIP, username)

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
	var rejected int64
	for {
		plaintext, err := tun2.Recv()
		if err != nil {
			log.Printf("[server] Client %s (ip=%s) disconnected: %v", remoteAddr, assignedIP, err)
			logx.Debugf("[server] client disconnected user=%q ip=%s: %v", username, assignedIP, err)
			return
		}

		// Only IPv4 from the client's own address, and not to other clients:
		// a spoofed source would be NATed and its replies delivered to
		// someone else, and client-to-client traffic would expose devices.
		src, dst, ok := ipv4Addrs(plaintext)
		if !ok || src != assignedIP || (pool.Prefix().Contains(dst) && dst != serverTunAddr) {
			if rejected++; rejected%1000 == 1 {
				logx.Debugf("[server] dropping packet from %s: src=%s dst=%s", assignedIP, src, dst)
			}
			continue
		}

		if _, werr := tunDev.Write(plaintext); werr != nil {
			log.Printf("[server] TUN write: %v", werr)
		} else {
			sess.bytesIn.Add(int64(len(plaintext)))
		}
	}
}
