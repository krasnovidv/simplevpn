package tunnel

import (
	"fmt"
	"log"
	"os"
	"os/exec"
)

// TunDevice represents a TUN network interface.
type TunDevice struct {
	f    *os.File
	Name string
}

// Read reads a packet from the TUN device.
func (t *TunDevice) Read(b []byte) (int, error) { return t.f.Read(b) }

// Write writes a packet to the TUN device.
func (t *TunDevice) Write(b []byte) (int, error) { return t.f.Write(b) }

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

	log.Printf("[tunnel] TUN device %s created and configured", name)
	return &TunDevice{f: f, Name: name}, nil
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
