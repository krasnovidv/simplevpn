//go:build darwin || linux

// Integration tests for the Preflight→RunTunnel lifecycle.
// iOS is the first real consumer of this API — Android still uses the legacy Connect() path.
// These tests verify the full sequence: Preflight → bufConn handoff → RunTunnel → relay → Disconnect.
//
// Tests run on darwin and linux; building/executing on Windows is not supported.

package vpnlib

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"syscall"
	"testing"
	"time"

	"simplevpn/pkg/tlsdecoy"
)

const testServerKey = "test-server-key-for-integration-tests-only"
const testAssignedPrefix = "10.0.0.2/24"

// mockServer is a minimal TLS server that speaks the SimpleVPN auth protocol.
type mockServer struct {
	listener net.Listener
}

func newMockServer(t *testing.T, behavior string) (*mockServer, string) {
	t.Helper()

	cert := generateSelfSignedCert(t)
	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13,
	}

	ln, err := tls.Listen("tcp", "127.0.0.1:0", tlsCfg)
	if err != nil {
		t.Fatalf("tls.Listen: %v", err)
	}

	ms := &mockServer{listener: ln}
	go ms.serve(t, behavior)
	t.Cleanup(func() { ln.Close() })

	return ms, ln.Addr().String()
}

func (ms *mockServer) serve(t *testing.T, behavior string) {
	for {
		conn, err := ms.listener.Accept()
		if err != nil {
			return
		}
		go ms.handleConn(t, conn, behavior)
	}
}

func (ms *mockServer) handleConn(t *testing.T, conn net.Conn, behavior string) {
	defer conn.Close()

	_, _, err := tlsdecoy.ReadCredAuth(conn)
	if err != nil {
		return
	}

	switch behavior {
	case "auth_fail":
		fmt.Fprintf(conn, "DENY bad credentials\n")
		return
	default:
		fmt.Fprintf(conn, "OK %s\n", testAssignedPrefix)
		// Keep connection alive so RunTunnel can use it.
		time.Sleep(30 * time.Second)
	}
}

func makeConfigJSON(addr string) string {
	cfg := map[string]interface{}{
		"server":      addr,
		"server_key":  testServerKey,
		"username":    "testuser",
		"password":    "testpass",
		"skip_verify": true,
		"transport":   "tls",
	}
	b, _ := json.Marshal(cfg)
	return string(b)
}

// makeTestSocketpair creates a SOCK_DGRAM Unix socketpair for use as a TUN fd substitute.
// Returns (dupFd for RunTunnel, peerFd to keep open). Caller must close peerFd.
func makeTestSocketpair(t *testing.T) (dupFd, peerFd int) {
	t.Helper()
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatalf("socketpair: %v", err)
	}
	dup, err := syscall.Dup(fds[0])
	if err != nil {
		syscall.Close(fds[0])
		syscall.Close(fds[1])
		t.Fatalf("dup: %v", err)
	}
	syscall.Close(fds[0]) // original; os.NewFile in RunTunnel owns dup
	return dup, fds[1]
}

// resetVpnState resets global vpnlib state between tests.
func resetVpnState(t *testing.T) {
	t.Helper()
	current = &state{status: "disconnected"}
}

// TestPreflightRunTunnelHappyPath verifies the full lifecycle without errors.
func TestPreflightRunTunnelHappyPath(t *testing.T) {
	resetVpnState(t)
	_, addr := newMockServer(t, "happy")

	prefix := Preflight(makeConfigJSON(addr))
	if len(prefix) >= 5 && prefix[:5] == "error" {
		t.Fatalf("Preflight returned error: %s", prefix)
	}
	if prefix != testAssignedPrefix {
		t.Fatalf("assigned prefix = %q, want %q", prefix, testAssignedPrefix)
	}
	t.Logf("Preflight OK: prefix=%s", prefix)

	dupFd, peerFd := makeTestSocketpair(t)
	defer syscall.Close(peerFd)

	tunnelErrCh := make(chan error, 1)
	go func() {
		tunnelErrCh <- RunTunnel(dupFd)
	}()

	// Give RunTunnel time to set current.connected = true.
	time.Sleep(50 * time.Millisecond)

	if s := Status(); s != "connected" {
		t.Fatalf("status after RunTunnel start = %q, want connected", s)
	}

	Disconnect()

	select {
	case err := <-tunnelErrCh:
		if err != nil {
			t.Fatalf("RunTunnel returned error: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("RunTunnel did not return within 3s after Disconnect")
	}

	if s := Status(); s != "disconnected" {
		t.Fatalf("status after Disconnect = %q, want disconnected", s)
	}
}

// TestPreflightAuthFailure verifies that a server rejection causes an "error:" return
// and releases connectMu so the next Preflight can proceed.
func TestPreflightAuthFailure(t *testing.T) {
	resetVpnState(t)
	_, addr := newMockServer(t, "auth_fail")

	result := Preflight(makeConfigJSON(addr))
	if len(result) < 5 || result[:5] != "error" {
		t.Fatalf("expected error prefix, got: %q", result)
	}
	t.Logf("Preflight correctly returned: %s", result)

	// connectMu must be released — a subsequent Preflight must not deadlock.
	done := make(chan struct{}, 1)
	go func() {
		defer close(done)
		// Will fail (no real server), but must not block forever.
		Preflight(`{"server":"127.0.0.1:1","server_key":"k","username":"u","password":"p","transport":"tls","skip_verify":true}`)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("second Preflight after auth failure blocked — connectMu not released")
	}
}

// TestPreflightSerializesWithRunTunnel verifies that Preflight is serialized with RunTunnel:
// a second Preflight call must block while RunTunnel is active (connectMu held)
// and only proceed after Disconnect is called.
func TestPreflightSerializesWithRunTunnel(t *testing.T) {
	resetVpnState(t)
	_, addr := newMockServer(t, "happy")

	prefix := Preflight(makeConfigJSON(addr))
	if len(prefix) >= 5 && prefix[:5] == "error" {
		t.Fatalf("first Preflight failed: %s", prefix)
	}

	dupFd, peerFd := makeTestSocketpair(t)
	defer syscall.Close(peerFd)

	tunnelErrCh := make(chan error, 1)
	go func() {
		tunnelErrCh <- RunTunnel(dupFd)
	}()

	// Wait until RunTunnel is running (holds connectMu).
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if Status() == "connected" {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if Status() != "connected" {
		t.Fatal("timed out waiting for RunTunnel")
	}

	// The second Preflight should block because connectMu is held.
	// We verify it does NOT complete before Disconnect is called.
	secondDone := make(chan struct{}, 1)
	go func() {
		// This will unblock only after RunTunnel returns and releases connectMu.
		Preflight(`{"server":"127.0.0.1:1","server_key":"k","username":"u","password":"p","transport":"tls","skip_verify":true}`)
		close(secondDone)
	}()

	// Second Preflight must NOT complete while tunnel is running.
	select {
	case <-secondDone:
		t.Fatal("second Preflight returned while RunTunnel was still active — connectMu not held")
	case <-time.After(200 * time.Millisecond):
		t.Log("second Preflight correctly blocked while RunTunnel is active")
	}

	// Disconnect → RunTunnel returns → connectMu released → second Preflight unblocks.
	Disconnect()
	<-tunnelErrCh

	select {
	case <-secondDone:
		t.Log("second Preflight unblocked after Disconnect — serialization verified")
	case <-time.After(3 * time.Second):
		t.Fatal("second Preflight did not unblock after RunTunnel returned")
	}
}

// TestPreflightWatchdogExpiry verifies that Preflight releases connectMu after 10s
// if RunTunnel is never called. Skipped in short mode.
func TestPreflightWatchdogExpiry(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping 10s watchdog test in -short mode")
	}
	resetVpnState(t)
	_, addr := newMockServer(t, "happy")

	prefix := Preflight(makeConfigJSON(addr))
	if len(prefix) >= 5 && prefix[:5] == "error" {
		t.Fatalf("Preflight failed: %s", prefix)
	}
	t.Log("Preflight OK, not calling RunTunnel — waiting for 10s watchdog...")

	time.Sleep(11 * time.Second)

	if s := Status(); s != "disconnected" {
		t.Fatalf("status after watchdog = %q, want disconnected", s)
	}
	t.Log("watchdog fired, status is disconnected")

	// A new Preflight must not deadlock after the watchdog releases the mutex.
	done := make(chan string, 1)
	go func() {
		_, addr2 := newMockServer(t, "happy")
		done <- Preflight(makeConfigJSON(addr2))
	}()
	select {
	case result := <-done:
		t.Logf("post-watchdog Preflight result: %s", result)
	case <-time.After(5 * time.Second):
		t.Fatal("Preflight after watchdog blocked — connectMu not released")
	}
}

// generateSelfSignedCert creates a self-signed ECDSA TLS certificate for test servers.
func generateSelfSignedCert(t *testing.T) tls.Certificate {
	t.Helper()

	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}

	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "simplevpn-test"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		DNSNames:     []string{"localhost"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &priv.PublicKey, priv)
	if err != nil {
		t.Fatalf("create cert: %v", err)
	}

	keyDER, err := x509.MarshalECPrivateKey(priv)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}

	cert, err := tls.X509KeyPair(
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER}),
		pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}),
	)
	if err != nil {
		t.Fatalf("X509KeyPair: %v", err)
	}
	return cert
}
