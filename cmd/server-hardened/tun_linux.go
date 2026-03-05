package main

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
