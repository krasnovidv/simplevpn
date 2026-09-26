//go:build unix

package vpnlib

import "syscall"

// setNonblock puts the TUN fd in non-blocking mode so os.NewFile returns a
// pollable file whose Close interrupts a pending Read.
func setNonblock(fd int) error { return syscall.SetNonblock(fd, true) }
