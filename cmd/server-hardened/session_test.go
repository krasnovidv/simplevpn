package main

import (
	"bufio"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
)

func TestTrackUserSessionEvictsOldest(t *testing.T) {
	var sessions []*clientSession
	var untrack []func()
	for i := 0; i < maxSessionsPerUser+1; i++ {
		srv, cli := net.Pipe()
		defer cli.Close()
		s := &clientSession{id: string(rune('a' + i)), username: "evict-test", conn: srv}
		sessions = append(sessions, s)
		untrack = append(untrack, trackUserSession(s))
	}

	// The first session's conn was closed by the eviction.
	if _, err := sessions[0].conn.Write([]byte{1}); err == nil {
		t.Fatal("oldest session was not evicted")
	}
	userSessionsMu.Lock()
	n := len(userSessions["evict-test"])
	userSessionsMu.Unlock()
	if n != maxSessionsPerUser {
		t.Fatalf("tracked sessions = %d, want %d", n, maxSessionsPerUser)
	}

	for _, u := range untrack {
		u()
	}
	userSessionsMu.Lock()
	_, left := userSessions["evict-test"]
	userSessionsMu.Unlock()
	if left {
		t.Fatal("user entry not removed after all sessions ended")
	}
}

func TestIPv4Addrs(t *testing.T) {
	p := make([]byte, 20)
	p[0] = 0x45
	copy(p[12:16], []byte{10, 0, 0, 2})
	copy(p[16:20], []byte{1, 1, 1, 1})
	src, dst, ok := ipv4Addrs(p)
	if !ok || src != netip.MustParseAddr("10.0.0.2") || dst != netip.MustParseAddr("1.1.1.1") {
		t.Fatalf("ipv4Addrs = %s %s %v", src, dst, ok)
	}
	p[0] = 0x60
	if _, _, ok := ipv4Addrs(p); ok {
		t.Fatal("IPv6 packet accepted")
	}
	if _, _, ok := ipv4Addrs(p[:10]); ok {
		t.Fatal("short packet accepted")
	}
}

// startDecoyServer runs the real listener + serveConnection. Only the
// pre-auth paths are exercised, so no TUN, pool or user store is needed.
func startDecoyServer(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	certFile, keyFile := writeTestCert(t, dir)
	tlsCfg, err := tlsdecoy.NewDecoyTLSConfig(certFile, keyFile)
	if err != nil {
		t.Fatal(err)
	}
	l, err := transport.NewListener(&transport.ListenConfig{Addr: "127.0.0.1:0", TLSConfig: tlsCfg})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			go serveConnection(c, nil, nil, nil, nil, nil)
		}
	}()
	return l.Addr().String()
}

func probe(t *testing.T, addr string, payload []byte) string {
	t.Helper()
	c, err := tls.Dial("tcp", addr, &tls.Config{InsecureSkipVerify: true, NextProtos: []string{"h2", "http/1.1"}})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if p := c.ConnectionState().NegotiatedProtocol; p != "http/1.1" {
		t.Errorf("negotiated ALPN %q, want http/1.1", p)
	}
	c.SetDeadline(time.Now().Add(5 * time.Second))
	c.Write(payload)
	out, _ := io.ReadAll(c)
	return string(out)
}

func TestDecoyAnswers(t *testing.T) {
	addr := startDecoyServer(t)

	check := func(name, payload string, wantStatus int) {
		t.Helper()
		out := probe(t, addr, []byte(payload))
		resp, err := http.ReadResponse(bufio.NewReader(strings.NewReader(out)), nil)
		if err != nil {
			t.Fatalf("%s: unparsable reply %q: %v", name, out, err)
		}
		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != wantStatus || resp.Header.Get("Date") == "" ||
			resp.ContentLength != int64(len(body)) {
			t.Fatalf("%s: status=%d date=%q len=%d/%d", name, resp.StatusCode,
				resp.Header.Get("Date"), resp.ContentLength, len(body))
		}
	}

	check("landing page", "GET / HTTP/1.1\r\nHost: x\r\n\r\n", 200)
	check("unknown path", "GET /admin HTTP/1.1\r\nHost: x\r\n\r\n", 404)
	check("upgrade on a foreign path", "GET /chat HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n"+
		"Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n", 404)
	check("POST", "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n", 200)
	check("binary garbage", "\x02\x00garbage", 400)
}

func writeTestCert(t *testing.T, dir string) (certFile, keyFile string) {
	t.Helper()
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "test"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &priv.PublicKey, priv)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, _ := x509.MarshalECPrivateKey(priv)
	certFile, keyFile = filepath.Join(dir, "c.pem"), filepath.Join(dir, "k.pem")
	os.WriteFile(certFile, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600)
	os.WriteFile(keyFile, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}), 0o600)
	return certFile, keyFile
}
