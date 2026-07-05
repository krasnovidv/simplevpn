package tunnel

import (
	"fmt"
	"log"
	"os"
	"os/exec"
)

// TunDevice represents a TUN network interface.
//
// Read/Write are defined per-platform (tun_linux.go / tun_other.go). On Linux
// they use blocking raw syscalls on fd, deliberately bypassing Go's runtime
// netpoller: a TUN character device is not reliably epoll-pollable, and going
// through the poller makes the very first Read fail with "not pollable", which
// silently kills the TUN→client relay. Raw blocking reads are immune to that.
type TunDevice struct {
	f    *os.File
	fd   int
	Name string
}

// Close closes the TUN device.
func (t *TunDevice) Close() error {
	log.Printf("[tunnel] Closing TUN device %s", t.Name)
	return t.f.Close()
}

// CreateTUN creates and configures a TUN device with the given name, CIDR, and MTU.
func CreateTUN(name, cidr string, mtu int) (*TunDevice, error) {
	log.Printf("[tunnel] Creating TUN device: name=%s cidr=%s mtu=%d", name, cidr, mtu)

	f, err := openTun(name)
	if err != nil {
		return nil, err
	}

	if err := runCmd("ip", "addr", "add", cidr, "dev", name); err != nil {
		f.Close()
		return nil, fmt.Errorf("ip addr add: %w", err)
	}
	if err := runCmd("ip", "link", "set", "dev", name, "mtu", fmt.Sprint(mtu)); err != nil {
		f.Close()
		return nil, fmt.Errorf("ip link mtu: %w", err)
	}
	if err := runCmd("ip", "link", "set", "dev", name, "up"); err != nil {
		f.Close()
		return nil, fmt.Errorf("ip link up: %w", err)
	}

	// Fd() puts the descriptor into blocking mode and detaches it from the
	// runtime netpoller, so the raw unix.Read/unix.Write in tun_linux.go operate
	// on a plain blocking fd. Keep f alive in the struct so it is not finalized.
	log.Printf("[tunnel] TUN device %s created and configured", name)
	return &TunDevice{f: f, fd: int(f.Fd()), Name: name}, nil
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
