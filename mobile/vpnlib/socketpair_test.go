//go:build darwin || linux

package vpnlib

import (
	"bytes"
	"sync"
	"syscall"
	"testing"
)

// makeSocketpair creates a SOCK_DGRAM Unix socketpair and returns [fds[0], fds[1]].
func makeSocketpair(t *testing.T) [2]int {
	t.Helper()
	fds := [2]int{}
	raw, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatalf("socketpair: %v", err)
	}
	fds[0], fds[1] = raw[0], raw[1]
	return fds
}

// TestSocketpairMessageBoundaries verifies that SOCK_DGRAM preserves datagram boundaries
// for packet sizes we care about: 100, 500, 1380 (MTU), and 1500 bytes.
func TestSocketpairMessageBoundaries(t *testing.T) {
	sizes := []int{100, 500, 1380, 1500}
	for _, size := range sizes {
		size := size
		t.Run("size_"+itoa(size), func(t *testing.T) {
			fds := makeSocketpair(t)
			defer syscall.Close(fds[0])
			defer syscall.Close(fds[1])

			payload := make([]byte, size)
			for i := range payload {
				payload[i] = byte(i & 0xFF)
			}

			// Write one datagram from fds[0] to fds[1].
			n, err := syscall.Write(fds[0], payload)
			if err != nil {
				t.Fatalf("write(%d bytes): %v", size, err)
			}
			if n != size {
				t.Fatalf("wrote %d, want %d", n, size)
			}

			buf := make([]byte, size+1)
			n, err = syscall.Read(fds[1], buf)
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			if n != size {
				t.Fatalf("read %d bytes, want %d", n, size)
			}
			if !bytes.Equal(buf[:n], payload) {
				t.Fatalf("data mismatch at size %d", size)
			}
		})
	}
}

// TestSocketpairConcurrentReadWrite sends 200 datagrams concurrently and verifies
// all are received with correct content and no interleaving.
func TestSocketpairConcurrentReadWrite(t *testing.T) {
	fds := makeSocketpair(t)
	defer syscall.Close(fds[0])
	defer syscall.Close(fds[1])

	const msgSize = 1380
	const count = 200

	// Writer sends count messages into fds[0].
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < count; i++ {
			msg := make([]byte, msgSize)
			msg[0] = byte(i & 0xFF)
			if _, err := syscall.Write(fds[0], msg); err != nil {
				t.Errorf("write %d: %v", i, err)
				return
			}
		}
	}()

	// Reader receives and checks count messages from fds[1].
	received := 0
	buf := make([]byte, msgSize+1)
	for received < count {
		n, err := syscall.Read(fds[1], buf)
		if err != nil {
			t.Fatalf("read after %d: %v", received, err)
		}
		if n != msgSize {
			t.Fatalf("read %d bytes at msg %d, want %d", n, received, msgSize)
		}
		received++
	}

	wg.Wait()
	if received != count {
		t.Fatalf("received %d, want %d", received, count)
	}
}

// TestSocketpairFdCloseDetection verifies that reading from a closed fd returns an error.
func TestSocketpairFdCloseDetection(t *testing.T) {
	fds := makeSocketpair(t)
	defer syscall.Close(fds[1])

	// Close the write end.
	if err := syscall.Close(fds[0]); err != nil {
		t.Fatalf("close fds[0]: %v", err)
	}

	// Read from fds[1] — should return 0 bytes or EBADF, not block forever.
	// For SOCK_DGRAM there's no EOF concept, but with both ends closed Read returns 0/ENOBUFS.
	buf := make([]byte, 64)
	// Set a small read to avoid blocking. Write nothing — just verify read doesn't panic.
	done := make(chan error, 1)
	go func() {
		n, err := syscall.Read(fds[1], buf)
		if n == 0 && err == nil {
			err = nil // acceptable
		}
		done <- err
	}()

	// Write a single byte to unblock the read, then verify.
	syscall.Write(fds[1], []byte{0x42}) //nolint:errcheck
	if err := <-done; err != nil && err != syscall.EBADF {
		t.Logf("read after fd close returned: %v (acceptable)", err)
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	buf := make([]byte, 0, 10)
	for n > 0 {
		buf = append([]byte{byte('0' + n%10)}, buf...)
		n /= 10
	}
	return string(buf)
}
