package transport

import (
	"bytes"
	"net"
	"testing"
	"time"
)

func TestIsWebSocketUpgrade(t *testing.T) {
	tests := []struct {
		name string
		data []byte
		want bool
	}{
		{"GET request", []byte("GET /ws HTTP/1.1\r\n"), true},
		{"Binary auth token", []byte{0x12, 0x34, 0x56}, false},
		{"Empty", []byte{}, false},
		{"Short", []byte("GE"), false},
		{"POST request", []byte("POST /api"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := IsWebSocketUpgrade(tt.data)
			if got != tt.want {
				t.Errorf("IsWebSocketUpgrade(%q) = %v, want %v", tt.data, got, tt.want)
			}
		})
	}
}

func TestPeekConn(t *testing.T) {
	// Create a pipe to simulate a connection
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	pc := &PeekConn{Conn: server}

	// Write data from client side
	testData := []byte("GET /ws HTTP/1.1\r\nHost: test\r\n\r\n")
	go func() {
		client.Write(testData)
	}()

	// Peek first 3 bytes
	server.SetReadDeadline(time.Now().Add(time.Second))
	peeked, err := pc.Peek(3)
	server.SetReadDeadline(time.Time{})
	if err != nil {
		t.Fatalf("Peek failed: %v", err)
	}
	if string(peeked) != "GET" {
		t.Errorf("Peek returned %q, want %q", peeked, "GET")
	}

	// Second Peek should return cached data
	peeked2, err := pc.Peek(3)
	if err != nil {
		t.Fatalf("Second Peek failed: %v", err)
	}
	if !bytes.Equal(peeked, peeked2) {
		t.Errorf("Second Peek returned %q, want %q", peeked2, peeked)
	}

	// Read should replay peeked bytes first
	buf := make([]byte, len(testData))
	n, err := pc.Read(buf[:3])
	if err != nil {
		t.Fatalf("Read failed: %v", err)
	}
	if string(buf[:n]) != "GET" {
		t.Errorf("Read after peek returned %q, want %q", buf[:n], "GET")
	}

	// Next Read should continue from underlying connection
	server.SetReadDeadline(time.Now().Add(time.Second))
	n, err = pc.Read(buf)
	server.SetReadDeadline(time.Time{})
	if err != nil {
		t.Fatalf("Read after peek exhausted: %v", err)
	}
	if n == 0 {
		t.Error("Expected data from underlying connection")
	}
}

func TestDialerRegistry(t *testing.T) {
	// Register a test dialer
	RegisterDialer("test-transport", func(fp FingerprintProfile) Dialer {
		return nil
	})

	// Should find registered dialer
	_, err := NewDialer("test-transport", FingerprintNone)
	if err != nil {
		t.Errorf("NewDialer for registered type failed: %v", err)
	}

	// Should fail for unregistered type
	_, err = NewDialer("nonexistent", FingerprintNone)
	if err == nil {
		t.Error("NewDialer for unregistered type should fail")
	}
}
