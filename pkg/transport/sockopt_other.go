//go:build !linux

package transport

import "syscall"

func listenControl(network, address string, c syscall.RawConn) error { return nil }
