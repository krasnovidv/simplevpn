package transport

import (
	"net"
	"syscall"
	"testing"
	"time"
)

// Accepted connections must carry the listener's TCP_USER_TIMEOUT.
func TestAcceptedConnInheritsUserTimeout(t *testing.T) {
	l, err := (&net.ListenConfig{Control: listenControl}).Listen(t.Context(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	go func() {
		c, err := net.Dial("tcp", l.Addr().String())
		if err == nil {
			time.Sleep(time.Second)
			c.Close()
		}
	}()
	c, err := l.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	raw, _ := c.(*net.TCPConn).SyscallConn()
	var got int
	raw.Control(func(fd uintptr) {
		got, err = syscall.GetsockoptInt(int(fd), syscall.IPPROTO_TCP, tcpUserTimeout)
	})
	if err != nil || got != int(userTimeout/time.Millisecond) {
		t.Fatalf("TCP_USER_TIMEOUT = %d (%v), want %d", got, err, userTimeout/time.Millisecond)
	}
}
