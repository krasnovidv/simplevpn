package transport

import (
	"syscall"
	"time"
)

// userTimeout bounds how long data we sent may stay unacknowledged before the
// kernel drops the connection (TCP_USER_TIMEOUT, inherited by accepted
// sockets). Without it a client whose network silently vanished while we
// had data queued lingers until the retransmission timeout — about 15 min —
// holding its session and tunnel address. TCP keepalive alone does not help
// then: it only runs on idle connections.
const userTimeout = 90 * time.Second

const tcpUserTimeout = 0x12 // TCP_USER_TIMEOUT, not exported by package syscall

func listenControl(network, address string, c syscall.RawConn) error {
	var serr error
	if err := c.Control(func(fd uintptr) {
		serr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, tcpUserTimeout, int(userTimeout/time.Millisecond))
	}); err != nil {
		return err
	}
	return serr
}
