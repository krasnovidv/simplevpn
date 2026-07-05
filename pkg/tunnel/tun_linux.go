package tunnel

import (
	"fmt"
	"os"
	"unsafe"

	"golang.org/x/sys/unix"
)

func openTun(name string) (*os.File, error) {
	f, err := os.OpenFile("/dev/net/tun", os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/net/tun: %w", err)
	}

	var ifr [unix.IFNAMSIZ + 64]byte
	copy(ifr[:], name)
	// IFF_TUN | IFF_NO_PI
	*(*uint16)(unsafe.Pointer(&ifr[unix.IFNAMSIZ])) = unix.IFF_TUN | unix.IFF_NO_PI

	_, _, errno := unix.Syscall(unix.SYS_IOCTL, f.Fd(), unix.TUNSETIFF, uintptr(unsafe.Pointer(&ifr[0])))
	if errno != 0 {
		f.Close()
		return nil, fmt.Errorf("ioctl TUNSETIFF: %v", errno)
	}

	return f, nil
}

// Read reads one packet from the TUN device via a blocking raw syscall,
// bypassing Go's netpoller (see TunDevice doc comment). EINTR is retried
// because the Go runtime can interrupt blocking syscalls (e.g. SIGURG for
// goroutine preemption).
func (t *TunDevice) Read(b []byte) (int, error) {
	for {
		n, err := unix.Read(t.fd, b)
		if err == unix.EINTR {
			continue
		}
		return n, err
	}
}

// Write writes one packet to the TUN device via a blocking raw syscall.
func (t *TunDevice) Write(b []byte) (int, error) {
	for {
		n, err := unix.Write(t.fd, b)
		if err == unix.EINTR {
			continue
		}
		return n, err
	}
}
