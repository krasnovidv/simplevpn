//go:build darwin || linux

package vpnlib

import (
	"errors"
	"syscall"
	"testing"
	"time"
)

// startTunnel runs Preflight against a mock server with the given behaviour and
// starts RunTunnel on a socketpair, returning RunTunnel's result channel.
func startTunnel(t *testing.T, behavior string) <-chan error {
	t.Helper()
	resetVpnState(t)
	_, addr := newMockServer(t, behavior)
	if res := Preflight(makeConfigJSON(addr)); res != testAssignedPrefix {
		t.Fatalf("Preflight = %q", res)
	}
	dupFd, peerFd := makeTestSocketpair(t)
	t.Cleanup(func() { syscall.Close(peerFd) })
	errCh := make(chan error, 1)
	go func() { errCh <- RunTunnel(dupFd) }()
	return errCh
}

func waitErr(t *testing.T, ch <-chan error, within time.Duration) error {
	t.Helper()
	select {
	case err := <-ch:
		return err
	case <-time.After(within):
		t.Fatalf("RunTunnel did not return within %s", within)
		return nil
	}
}

// Regression: disconnecting (e.g. from the home-screen widget) used to surface
// "recv: read frame length: ... use of closed network connection" as an error.
func TestDisconnectIsNotAnError(t *testing.T) {
	errCh := startTunnel(t, "happy")
	time.Sleep(50 * time.Millisecond)

	Disconnect()
	if err := waitErr(t, errCh, 3*time.Second); err != nil {
		t.Fatalf("RunTunnel after Disconnect = %v, want nil", err)
	}
	if s := Status(); s != "disconnected" {
		t.Fatalf("Status = %q, want disconnected", s)
	}
	if k := LastErrorKind(); k != "none" {
		t.Fatalf("LastErrorKind = %q, want none", k)
	}
}

func TestServerDropIsTransientError(t *testing.T) {
	errCh := startTunnel(t, "drop")
	if err := waitErr(t, errCh, 3*time.Second); err == nil {
		t.Fatal("RunTunnel returned nil after the server dropped the connection")
	}
	if k := LastErrorKind(); k != "transient" {
		t.Fatalf("LastErrorKind = %q, want transient", k)
	}
	if s := Status(); len(s) < 6 || s[:6] != "error:" {
		t.Fatalf("Status = %q, want error:", s)
	}
	// A late Disconnect (the platform's teardown) must not wipe the error the
	// retry loop is about to read.
	Disconnect()
	if k := LastErrorKind(); k != "transient" {
		t.Fatalf("LastErrorKind after idle Disconnect = %q, want transient", k)
	}
}

func shortLiveness(t *testing.T) {
	pi, st := probeInterval, stallTimeout
	probeInterval, stallTimeout = 100*time.Millisecond, 350*time.Millisecond
	t.Cleanup(func() { probeInterval, stallTimeout = pi, st })
}

func TestSilentTunnelIsDetected(t *testing.T) {
	shortLiveness(t)
	errCh := startTunnel(t, "happy") // authenticates, then never sends a byte
	err := waitErr(t, errCh, 3*time.Second)
	if !errors.Is(err, errStalled) {
		t.Fatalf("RunTunnel = %v, want errStalled", err)
	}
	if k := LastErrorKind(); k != "transient" {
		t.Fatalf("LastErrorKind = %q, want transient", k)
	}
}

func TestAnsweredProbesKeepTunnelUp(t *testing.T) {
	shortLiveness(t)
	errCh := startTunnel(t, "echo")
	select {
	case err := <-errCh:
		t.Fatalf("tunnel with answered probes was torn down: %v", err)
	case <-time.After(1500 * time.Millisecond):
	}
	if s := Status(); s != "connected" {
		t.Fatalf("Status = %q, want connected", s)
	}
	Disconnect()
	if err := waitErr(t, errCh, 3*time.Second); err != nil {
		t.Fatalf("RunTunnel after Disconnect = %v, want nil", err)
	}
}

// Disconnect between Preflight and RunTunnel drops the pending session and
// releases connectMu, so the next connect is not blocked by the watchdog.
func TestDisconnectWhilePending(t *testing.T) {
	resetVpnState(t)
	_, addr := newMockServer(t, "happy")
	if res := Preflight(makeConfigJSON(addr)); res != testAssignedPrefix {
		t.Fatalf("Preflight = %q", res)
	}
	Disconnect()
	if err := RunTunnel(-1); err == nil {
		t.Fatal("RunTunnel after Disconnect of a pending session succeeded")
	}
	if k := LastErrorKind(); k != "none" {
		t.Fatalf("LastErrorKind = %q, want none", k)
	}
	done := make(chan string, 1)
	go func() { done <- Preflight(makeConfigJSON(addr)) }()
	select {
	case res := <-done:
		if res != testAssignedPrefix {
			t.Fatalf("second Preflight = %q", res)
		}
		Disconnect()
	case <-time.After(2 * time.Second):
		t.Fatal("Preflight blocked after Disconnect of a pending session — connectMu leaked")
	}
}
