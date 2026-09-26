//go:build !unix

package vpnlib

func setNonblock(fd int) error { return nil }
