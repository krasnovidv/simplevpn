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
	"errors"
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
	Server      string `json:"server"` // host:port
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
	"193.23.3.93:443":  {"185.192.246.127:443", "185.192.246.127:2053"},
	"89.40.233.67:443": {"185.192.246.127:443", "185.192.246.127:2053"},
}

// abandonedServers lists addresses that are no longer ours. They are never
// dialled: the provider hands such an IP to someone else, and a client that
// kept dialling it would send its credentials to whoever holds it now (the
// TLS layer does not pin our certificate). Configs naming one still reach the
// current server through migrationFallbacks, which is keyed on the old
// address, and then promote the address that answered.
//
//   - 193.23.3.93  — Beget VPS, gone since 2026-07-28.
//   - 89.40.233.67 — reinstalled for another tenant by 2026-09-26 (new SSH
//     host key, our ports closed).
var abandonedServers = map[string]struct{}{
	"193.23.3.93:443":   {},
	"89.40.233.67:443":  {},
	"89.40.233.67:2053": {},
}

// endpointCandidates returns Server, then Endpoints, then any compiled-in
// successor for Server — trimmed and de-duplicated, order otherwise preserved,
// with abandoned addresses removed.
func endpointCandidates(cfg *Config) []string {
	all := append([]string{cfg.Server}, cfg.Endpoints...)
	all = append(all, migrationFallbacks[strings.TrimSpace(cfg.Server)]...)
	seen := make(map[string]struct{}, len(all))
	out := make([]string, 0, len(all))
	for _, addr := range all {
		addr = strings.TrimSpace(addr)
		if addr == "" {
			continue
		}
		if _, dup := seen[addr]; dup {
			continue
		}
		seen[addr] = struct{}{}
		if _, gone := abandonedServers[addr]; gone {
			continue
		}
		out = append(out, addr)
	}
	return out
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
// describes the most recently tried address. Cancelling ctx stops the walk.
func dialWithFallback(ctx context.Context, dialer transport.Dialer, cfg *Config, base *transport.DialConfig, tag string) (net.Conn, string, error) {
	candidates := endpointCandidates(cfg)
	var lastErr error

	for i, addr := range candidates {
		if err := ctx.Err(); err != nil {
			return nil, "", err
		}
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
		dctx, cancel := context.WithTimeout(ctx, dialTimeout)
		conn, err := dialer.Dial(dctx, base)
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

// state holds the current connection state. Every field is guarded by mu.
//
// Lifecycle: Preflight (dial + auth) → pending → RunTunnel (relay) → idle.
// Disconnect may arrive in any of those phases and must end the session
// cleanly in each of them: it cancels an in-flight dial, drops a pending
// authenticated conn, or tears down the relay. A session ended by Disconnect
// is never reported as an error — the user asked for it.
type state struct {
	mu             sync.Mutex
	connected      bool
	conn           net.Conn
	tunFile        *os.File
	stopCh         chan struct{} // closed by Disconnect; tells the relay the stop was deliberate
	cancelDial     context.CancelFunc
	status         string
	assignedPrefix netip.Prefix // IP assigned by server, e.g. "10.0.0.2/24"
	lastKind       errKind      // most recent error classification (see errKind)

	// Pending preflight state — valid between Preflight() and RunTunnel() calls.
	pendingBC         *bufConn // authenticated + bufio-wrapped connection
	pendingKeys       *tunnel.Keys
	preflightCh       chan struct{} // closed by RunTunnel/Disconnect to cancel the watchdog
	connectUnlockOnce *sync.Once    // ensures connectMu.Unlock is called exactly once
}

// signalStopLocked closes stopCh at most once. Caller holds s.mu.
func (s *state) signalStopLocked() {
	if s.stopCh == nil {
		return
	}
	select {
	case <-s.stopCh:
	default:
		close(s.stopCh)
	}
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

// connectMu is held from Preflight() until RunTunnel() returns (or the watchdog
// fires, or Disconnect drops the pending session). It serialises sessions.
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

// Connect establishes a VPN connection on an already configured TUN fd and
// blocks until it ends. Kept for API compatibility: it is Preflight followed by
// RunTunnel, which is what the platforms use directly (they need the assigned
// address before they can build the TUN).
func Connect(configJSON string, fd int) error {
	res := Preflight(configJSON)
	if strings.HasPrefix(res, "error:") {
		return fmt.Errorf("%s", strings.TrimSpace(strings.TrimPrefix(res, "error:")))
	}
	return RunTunnel(fd)
}

// sessionErr carries an establish() failure together with its retry class and a
// short source tag for the errKind log line.
type sessionErr struct {
	kind errKind
	src  string
	err  error
}

func (e *sessionErr) Error() string { return e.err.Error() }

func fail(kind errKind, src string, format string, args ...any) *sessionErr {
	return &sessionErr{kind: kind, src: src, err: fmt.Errorf(format, args...)}
}

// establish parses the config, dials the first reachable endpoint and
// authenticates. On success the returned conn is positioned at the first tunnel
// frame. Cancelling ctx aborts the dial and the auth exchange.
func establish(ctx context.Context, configJSON string) (*bufConn, *tunnel.Keys, netip.Prefix, *sessionErr) {
	var none netip.Prefix

	var cfg Config
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return nil, nil, none, fail(kindFatal, "config-parse", "bad config: %w", err)
	}
	if cfg.Server == "" || cfg.ServerKey == "" || cfg.Username == "" || cfg.Password == "" {
		return nil, nil, none, fail(kindFatal, "config-validate", "server, server_key, username, and password are required")
	}

	keys, err := tunnel.DeriveKeys(cfg.ServerKey)
	if err != nil {
		return nil, nil, none, fail(kindFatal, "derive-keys", "derive keys: %w", err)
	}

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
		return nil, nil, none, fail(kindFatal, "transport-create", "transport: %w", err)
	}

	// ServerAddr/SNI are filled in per attempt by dialWithFallback, since a
	// fallback address may live on a different host than the primary.
	dialCfg := &transport.DialConfig{Fingerprint: fp}
	if cfg.SkipVerify {
		dialCfg.TLSConfig = &tls.Config{
			InsecureSkipVerify: true,
			MinVersion:         tls.VersionTLS13,
			NextProtos:         []string{"http/1.1"},
		}
	}
	if p := protector; p != nil {
		dialCfg.DialControl = func(network, address string, c interface{}) error {
			rawConn, ok := c.(syscall.RawConn)
			if !ok {
				return nil
			}
			var protectErr error
			if err := rawConn.Control(func(fd uintptr) {
				if !p.ProtectSocket(int32(fd)) {
					protectErr = fmt.Errorf("protect socket fd=%d failed", fd)
				}
			}); err != nil {
				return fmt.Errorf("raw conn control: %w", err)
			}
			return protectErr
		}
	} else {
		log.Printf("[vpnlib] WARNING: no socket protector set, VPN routing loop may occur")
	}

	log.Printf("[vpnlib] Connecting: server=%s endpoints=%d transport=%s fingerprint=%s user=%s",
		cfg.Server, len(cfg.Endpoints), tt, fp, cfg.Username)

	conn, dialedAddr, err := dialWithFallback(ctx, dialer, &cfg, dialCfg, "Preflight")
	if err != nil {
		return nil, nil, none, fail(classifyDialErr(err), "dial", "connect: %w", err)
	}
	setActiveServer(dialedAddr)

	// Disconnect during the auth exchange closes the conn, which unblocks the
	// read below; stop() detaches that hook once auth is done.
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	defer stop()

	credFrame, err := tlsdecoy.GenerateCredAuth(cfg.Username, cfg.Password)
	if err != nil {
		conn.Close()
		return nil, nil, none, fail(kindFatal, "auth-gen", "auth gen: %w", err)
	}
	if _, err := conn.Write(credFrame); err != nil {
		conn.Close()
		return nil, nil, none, fail(kindTransient, "auth-send", "auth send: %w", err)
	}

	// Read auth response line: "OK <ip>/<prefix>\n". bufConn keeps whatever the
	// reader buffered past '\n' so the first tunnel frame is not lost.
	br := bufio.NewReader(conn)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	line, err := br.ReadString('\n')
	conn.SetReadDeadline(time.Time{})
	if err != nil {
		conn.Close()
		return nil, nil, none, fail(kindTransient, "auth-response", "auth response: %w", err)
	}
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "OK ") {
		conn.Close()
		return nil, nil, none, fail(kindAuth, "auth-rejected", "auth rejected: %s", line)
	}
	assigned, err := netip.ParsePrefix(strings.TrimPrefix(line, "OK "))
	if err != nil {
		conn.Close()
		return nil, nil, none, fail(kindFatal, "assigned-prefix", "bad assigned prefix: %w", err)
	}
	log.Printf("[vpnlib] Authenticated via %s, assigned=%s", dialedAddr, assigned)
	return &bufConn{r: br, Conn: conn}, keys, assigned, nil
}

// Preflight authenticates with the VPN server and returns the assigned IP prefix
// (e.g. "10.0.0.2/24"). The caller must use this IP to configure the TUN interface
// and then call RunTunnel(fd) within 10 seconds.
//
// Returns "error: <message>" on failure. Returns the assigned prefix on success.
// A Disconnect() while Preflight runs aborts it with "error: cancelled" and
// leaves LastErrorKind at "none".
//
// Lifecycle guarantee: holds connectMu after returning successfully.
// RunTunnel, Disconnect or a 10-second watchdog will release it.
func Preflight(configJSON string) string {
	connectMu.Lock()
	unlockOnce := &sync.Once{}
	release := func() { unlockOnce.Do(connectMu.Unlock) }

	resetLastKind()
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, time.Now().UnixMilli())

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	current.mu.Lock()
	if current.connected {
		current.mu.Unlock()
		release()
		return "error: already connected"
	}
	current.status = "connecting"
	current.stopCh = make(chan struct{})
	current.cancelDial = cancel
	current.mu.Unlock()

	bc, keys, assigned, serr := establish(ctx, configJSON)

	current.mu.Lock()
	current.cancelDial = nil
	cancelled := ctx.Err() != nil
	if cancelled {
		// Disconnect already reset status/lastKind; don't overwrite them with
		// the error the aborted dial produced.
		current.mu.Unlock()
		if bc != nil {
			bc.Close()
		}
		release()
		log.Printf("[vpnlib] Preflight cancelled by Disconnect")
		return "error: cancelled"
	}
	if serr != nil {
		current.mu.Unlock()
		setLastKind(serr.kind, serr.src, serr.err)
		setStatus("error: " + serr.Error())
		release()
		return "error: " + serr.Error()
	}

	preflightCh := make(chan struct{})
	current.pendingBC = bc
	current.pendingKeys = keys
	current.assignedPrefix = assigned
	current.preflightCh = preflightCh
	current.connectUnlockOnce = unlockOnce
	current.mu.Unlock()

	// Watchdog: close pending conn and release mutex if RunTunnel not called in 10s.
	go func() {
		select {
		case <-preflightCh:
		case <-time.After(10 * time.Second):
			log.Printf("[vpnlib] Preflight watchdog: RunTunnel not called, closing conn")
			current.mu.Lock()
			if current.pendingBC == bc {
				bc.Close()
				current.pendingBC = nil
				current.pendingKeys = nil
				current.preflightCh = nil
				current.status = "disconnected"
			}
			current.mu.Unlock()
			release()
		}
	}()

	return assigned.String()
}

// RunTunnel starts the VPN data relay using the given TUN file descriptor.
// Must be called within 10 seconds of a successful Preflight() call.
// Blocks until the tunnel closes or Disconnect() is called; returns nil for a
// Disconnect and the cause otherwise.
func RunTunnel(fd int) error {
	current.mu.Lock()
	bc := current.pendingBC
	keys := current.pendingKeys
	stopCh := current.stopCh
	unlockOnce := current.connectUnlockOnce
	assigned := current.assignedPrefix

	if bc == nil || keys == nil || unlockOnce == nil {
		current.mu.Unlock()
		// The fd was handed over to us; don't leak it.
		if f := os.NewFile(uintptr(fd), "tun"); f != nil {
			f.Close()
		}
		return fmt.Errorf("RunTunnel called without a pending Preflight, or it was cancelled")
	}

	// Cancel the watchdog — we own the connection now.
	close(current.preflightCh)
	current.pendingBC = nil
	current.pendingKeys = nil
	current.preflightCh = nil
	current.mu.Unlock()

	// connectMu is released when RunTunnel returns (tunnel closes or Disconnect called).
	defer unlockOnce.Do(connectMu.Unlock)

	// A pollable (non-blocking) fd lets Close() interrupt a Read parked on an
	// idle TUN; with a blocking fd the reader goroutine would sit in read(2)
	// until the next packet and keep the interface alive after teardown.
	if err := setNonblock(fd); err != nil {
		log.Printf("[vpnlib] RunTunnel: set non-blocking on fd=%d failed: %v", fd, err)
	}
	tunFile := os.NewFile(uintptr(fd), "tun")
	if tunFile == nil {
		bc.Close()
		setLastKind(kindFatal, "tun-fd", nil)
		setStatus("error: invalid tun fd")
		return fmt.Errorf("invalid tun fd: %d", fd)
	}

	current.mu.Lock()
	select {
	case <-stopCh:
		// Disconnect raced in between Preflight and here.
		current.mu.Unlock()
		bc.Close()
		tunFile.Close()
		return nil
	default:
	}
	current.connected = true
	current.conn = bc
	current.tunFile = tunFile
	current.status = "connected"
	current.mu.Unlock()

	log.Printf("[vpnlib] RunTunnel: fd=%d assigned=%s, relay started", fd, assigned)
	err := relay(tunnel.New(keys, bc), bc, tunFile, assigned.Addr(), gatewayFor(assigned))

	current.mu.Lock()
	current.connected = false
	current.conn = nil
	current.tunFile = nil
	deliberate := false
	select {
	case <-stopCh:
		deliberate = true
	default:
	}
	if deliberate {
		current.status = "disconnected"
	}
	current.mu.Unlock()
	setActiveServer("")

	if deliberate {
		log.Printf("[vpnlib] RunTunnel: stopped by Disconnect")
		return nil
	}
	log.Printf("[vpnlib] RunTunnel: tunnel lost: %v", err)
	setLastKind(kindTransient, "relay", err)
	setStatus("error: " + err.Error())
	return err
}

// Liveness probing. The protocol has no ping frame, but every server answers
// ICMP echo on its own tunnel address, so a probe sent through the tunnel tests
// the whole path (TCP flow, TLS, server relay) with no server change. Without
// it a flow that a middlebox silently stopped forwarding — a routine DPI
// tactic — looks "connected" until TCP gives up, which takes up to ~15 min.
// Variables rather than constants only so tests can shorten them.
var (
	probeInterval = 25 * time.Second // probe once the tunnel has been quiet this long
	stallTimeout  = 70 * time.Second // nothing received for this long ⇒ path is dead
)

var errStalled = errors.New("tunnel stalled: no data from server")

// relay pumps packets both ways until either side fails or the conn/TUN is
// closed from outside (Disconnect). Whichever direction fails first tears the
// other down, so the call never outlives a half-dead tunnel.
func relay(tun *tunnel.Tunnel, conn net.Conn, tunFile *os.File, local, gateway netip.Addr) error {
	var (
		once    sync.Once
		cause   error
		lastRx  atomic.Int64 // unix nanos of the last frame from the server
		gotRx   atomic.Bool
		probeOK atomic.Bool // the server answered a probe this session
	)
	teardown := func(err error) {
		once.Do(func() {
			cause = err
			conn.Close()
			tunFile.Close()
		})
	}
	lastRx.Store(time.Now().UnixNano())
	probeID := uint16(time.Now().UnixNano())

	// TUN → server.
	senderDone := make(chan struct{})
	go func() {
		defer close(senderDone)
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[vpnlib] panic in TUN reader: %v", r)
				teardown(fmt.Errorf("tun reader panic: %v", r))
			}
		}()
		buf := make([]byte, tunnel.MaxFrameSize)
		for {
			n, err := tunFile.Read(buf)
			if err != nil {
				teardown(fmt.Errorf("tun read: %w", err))
				return
			}
			// The server routes IPv4 only. The platform captures IPv6 too so
			// it cannot leak around the tunnel; it ends here.
			if n == 0 || buf[0]>>4 != 4 {
				continue
			}
			if err := tun.Send(buf[:n]); err != nil {
				teardown(fmt.Errorf("send: %w", err))
				return
			}
			atomic.AddInt64(&statsBytesOut, int64(n))
		}
	}()

	// Liveness watchdog.
	watchDone := make(chan struct{})
	defer close(watchDone)
	if gateway.IsValid() && local.Is4() {
		go func() {
			t := time.NewTicker(probeInterval)
			defer t.Stop()
			var seq uint16
			for {
				select {
				case <-watchDone:
					return
				case <-t.C:
				}
				idle := time.Since(time.Unix(0, lastRx.Load()))
				// Only trust silence once probes are known to work here, or when
				// the session has never delivered a byte — otherwise a server
				// with an unusual tunnel address would be dropped every minute.
				if idle >= stallTimeout && (probeOK.Load() || !gotRx.Load()) {
					log.Printf("[vpnlib] liveness: nothing received for %s, dropping tunnel", idle.Round(time.Second))
					teardown(errStalled)
					return
				}
				if idle >= probeInterval {
					seq++
					if err := tun.Send(icmpEcho(local, gateway, probeID, seq)); err != nil {
						teardown(fmt.Errorf("send probe: %w", err))
						return
					}
				}
			}
		}()
	}

	// Server → TUN.
	for {
		pkt, err := tun.Recv()
		if err != nil {
			teardown(fmt.Errorf("recv: %w", err))
			break
		}
		lastRx.Store(time.Now().UnixNano())
		gotRx.Store(true)
		if isEchoReply(pkt, gateway, probeID) {
			probeOK.Store(true)
			continue
		}
		if _, err := tunFile.Write(pkt); err != nil {
			teardown(fmt.Errorf("tun write: %w", err))
			break
		}
		atomic.AddInt64(&statsBytesIn, int64(len(pkt)))
	}

	select {
	case <-senderDone:
	case <-time.After(2 * time.Second):
		log.Printf("[vpnlib] TUN reader did not exit within 2s (blocking fd?)")
	}
	return cause
}

// gatewayFor returns the server's tunnel address for an assigned prefix: the
// first host of the subnet, which is where the server puts its own TUN.
func gatewayFor(p netip.Prefix) netip.Addr {
	if !p.IsValid() || !p.Addr().Is4() || p.Bits() > 30 {
		return netip.Addr{}
	}
	gw := p.Masked().Addr().Next()
	if gw == p.Addr() {
		return netip.Addr{}
	}
	return gw
}

// icmpEcho builds an IPv4 ICMP echo request from src to dst.
func icmpEcho(src, dst netip.Addr, id, seq uint16) []byte {
	const ipLen, icmpLen = 20, 16
	p := make([]byte, ipLen+icmpLen)
	p[0] = 0x45                  // IPv4, 20-byte header
	putU16(p[2:], ipLen+icmpLen) // total length
	putU16(p[4:], seq)           // identification
	p[8] = 64                    // TTL
	p[9] = 1                     // ICMP
	s, d := src.As4(), dst.As4()
	copy(p[12:16], s[:])
	copy(p[16:20], d[:])
	putU16(p[10:], checksum(p[:ipLen]))

	icmp := p[ipLen:]
	icmp[0] = 8 // echo request
	putU16(icmp[4:], id)
	putU16(icmp[6:], seq)
	putU16(icmp[2:], checksum(icmp))
	return p
}

// isEchoReply reports whether pkt is the answer to one of our probes.
func isEchoReply(pkt []byte, gateway netip.Addr, id uint16) bool {
	if len(pkt) < 28 || pkt[0]>>4 != 4 || pkt[9] != 1 {
		return false
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+8 {
		return false
	}
	if netip.AddrFrom4([4]byte(pkt[12:16])) != gateway {
		return false
	}
	icmp := pkt[ihl:]
	return icmp[0] == 0 && uint16(icmp[4])<<8|uint16(icmp[5]) == id
}

func putU16(b []byte, v uint16) { b[0], b[1] = byte(v>>8), byte(v) }

func checksum(b []byte) uint16 {
	var sum uint32
	for i := 0; i+1 < len(b); i += 2 {
		sum += uint32(b[i])<<8 | uint32(b[i+1])
	}
	if len(b)%2 == 1 {
		sum += uint32(b[len(b)-1]) << 8
	}
	for sum>>16 != 0 {
		sum = sum&0xffff + sum>>16
	}
	return ^uint16(sum)
}

// Disconnect ends the current session, whatever phase it is in: an in-flight
// dial/auth is cancelled, a pending (authenticated, pre-RunTunnel) conn is
// dropped, and a running relay is torn down. The session then reports
// "disconnected" with no error. Calling it with no session is a no-op that
// leaves the last error in place (the iOS retry loop reads it afterwards).
func Disconnect() {
	current.mu.Lock()
	defer current.mu.Unlock()

	active := current.connected || current.cancelDial != nil || current.pendingBC != nil
	if !active {
		log.Printf("[vpnlib] Disconnect: no active session (status=%s)", current.status)
		return
	}
	log.Printf("[vpnlib] Disconnect: stopping session (status=%s)", current.status)

	current.signalStopLocked()
	if current.cancelDial != nil {
		current.cancelDial()
		current.cancelDial = nil
	}
	if current.pendingBC != nil {
		current.pendingBC.Close()
		current.pendingBC = nil
		current.pendingKeys = nil
		if current.preflightCh != nil {
			close(current.preflightCh)
			current.preflightCh = nil
		}
		if current.connectUnlockOnce != nil {
			current.connectUnlockOnce.Do(connectMu.Unlock)
		}
	}
	// Closing both ends unblocks the relay's reader and writer; RunTunnel
	// sees stopCh closed and returns nil.
	if current.tunFile != nil {
		current.tunFile.Close()
		current.tunFile = nil
	}
	if current.conn != nil {
		current.conn.Close()
		current.conn = nil
	}
	current.connected = false
	current.status = "disconnected"
	current.lastKind = kindNone
}

// Status returns the current connection status: "disconnected", "connecting",
// "connected" or "error: <message>".
func Status() string {
	current.mu.Lock()
	defer current.mu.Unlock()
	return current.status
}

// LastErrorKind returns the most recent error classification:
// "none" | "transient" | "auth" | "fatal". Reset to "none" on every
// Preflight() entry and by a Disconnect() that stopped a session. Used by the
// platform retry loop to decide whether to back off (transient) or stop
// retrying (auth/fatal).
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
// src is a short tag (e.g. "dial", "auth-response", "relay") so the log
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

// resetLastKind clears the classification at the start of every Preflight.
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
