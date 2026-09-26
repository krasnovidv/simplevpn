//go:build e2e && linux

// End-to-end check of the real client against a real server with a TUN
// (e.g. the Docker image). Not run by default:
//
//	E2E_SERVER=host:443 E2E_KEY=... E2E_USER=... E2E_PASS=... \
//	  go test -tags e2e -run E2E ./mobile/vpnlib/
package vpnlib

import (
	"encoding/json"
	"net/netip"
	"os"
	"syscall"
	"testing"
	"time"
)

func e2eConfig(t *testing.T, transport string) string {
	t.Helper()
	server := os.Getenv("E2E_SERVER")
	if server == "" {
		t.Skip("E2E_SERVER not set")
	}
	b, _ := json.Marshal(map[string]any{
		"server":      server,
		"server_key":  os.Getenv("E2E_KEY"),
		"username":    os.Getenv("E2E_USER"),
		"password":    os.Getenv("E2E_PASS"),
		"skip_verify": true,
		"transport":   transport,
	})
	return string(b)
}

// pingThrough sends an ICMP echo from src to dst into the tunnel and reports
// whether the matching reply comes back within wait.
func pingThrough(t *testing.T, peer int, src, dst netip.Addr, id uint16, wait time.Duration) bool {
	t.Helper()
	if _, err := syscall.Write(peer, icmpEcho(src, dst, id, 1)); err != nil {
		t.Fatalf("write to tunnel: %v", err)
	}
	deadline := time.Now().Add(wait)
	buf := make([]byte, 2048)
	for time.Now().Before(deadline) {
		tv := syscall.NsecToTimeval(int64(200 * time.Millisecond))
		syscall.SetsockoptTimeval(peer, syscall.SOL_SOCKET, syscall.SO_RCVTIMEO, &tv)
		n, err := syscall.Read(peer, buf)
		if err != nil || n <= 0 {
			continue
		}
		if isEchoReply(buf[:n], dst, id) {
			return true
		}
	}
	return false
}

func TestE2E(t *testing.T) {
	for _, tr := range []string{"ws", "tls"} {
		t.Run(tr, func(t *testing.T) {
			resetVpnState(t)
			res := Preflight(e2eConfig(t, tr))
			prefix, err := netip.ParsePrefix(res)
			if err != nil {
				t.Fatalf("Preflight = %q", res)
			}
			local, gw := prefix.Addr(), gatewayFor(prefix)

			dupFd, peer := makeTestSocketpair(t)
			defer syscall.Close(peer)
			errCh := make(chan error, 1)
			go func() { errCh <- RunTunnel(dupFd) }()

			if !pingThrough(t, peer, local, gw, 0x1111, 3*time.Second) {
				t.Fatal("no echo reply from the server's tunnel address")
			}
			if !pingThrough(t, peer, local, netip.MustParseAddr("1.1.1.1"), 0x2222, 5*time.Second) {
				t.Error("no echo reply from 1.1.1.1 through NAT")
			}
			spoofed := netip.MustParseAddr("10.0.0.77")
			if pingThrough(t, peer, spoofed, gw, 0x3333, 2*time.Second) {
				t.Error("server answered a packet with a spoofed source address")
			}

			Disconnect()
			select {
			case err := <-errCh:
				if err != nil {
					t.Fatalf("RunTunnel after Disconnect = %v", err)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("RunTunnel did not return after Disconnect")
			}
		})
	}
}
