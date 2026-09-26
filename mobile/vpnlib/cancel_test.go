package vpnlib

import (
	"net"
	"net/netip"
	"testing"
	"time"
)

// Disconnect while Preflight is still dialling aborts it promptly and is not
// reported as an error.
func TestDisconnectCancelsPreflight(t *testing.T) {
	current = &state{status: "disconnected"}

	// Accepts TCP but never speaks TLS, so the handshake hangs.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			defer c.Close()
		}
	}()

	done := make(chan string, 1)
	go func() { done <- Preflight(makeTestConfig(l.Addr().String())) }()

	deadline := time.Now().Add(2 * time.Second)
	for Status() != "connecting" && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(100 * time.Millisecond)
	Disconnect()

	select {
	case res := <-done:
		if res != "error: cancelled" {
			t.Fatalf("Preflight = %q, want error: cancelled", res)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("Preflight did not return after Disconnect")
	}
	if s := Status(); s != "disconnected" {
		t.Fatalf("Status = %q, want disconnected", s)
	}
	if k := LastErrorKind(); k != "none" {
		t.Fatalf("LastErrorKind = %q, want none", k)
	}
}

func makeTestConfig(addr string) string {
	return `{"server":"` + addr + `","server_key":"00000000000000000000000000000000","username":"u","password":"p","skip_verify":true,"transport":"tls"}`
}

func TestProbePacketRoundTrip(t *testing.T) {
	local := netip.MustParseAddr("10.0.0.2")
	gw := gatewayFor(netip.MustParsePrefix("10.0.0.2/24"))
	if gw != netip.MustParseAddr("10.0.0.1") {
		t.Fatalf("gateway = %s, want 10.0.0.1", gw)
	}
	req := icmpEcho(local, gw, 0xBEEF, 7)
	if checksum(req[:20]) != 0 || checksum(req[20:]) != 0 {
		t.Fatal("probe has a bad IP or ICMP checksum")
	}
	if isEchoReply(req, gw, 0xBEEF) {
		t.Fatal("request mistaken for a reply")
	}
	reply := append([]byte(nil), req...)
	copy(reply[12:16], req[16:20])
	copy(reply[16:20], req[12:16])
	reply[20] = 0
	if !isEchoReply(reply, gw, 0xBEEF) {
		t.Fatal("reply not recognised")
	}
	if isEchoReply(reply, gw, 0xBEEE) {
		t.Fatal("reply with foreign id recognised")
	}
	if gatewayFor(netip.MustParsePrefix("10.0.0.1/24")).IsValid() {
		t.Fatal("gateway equal to the local address must be rejected")
	}
}
