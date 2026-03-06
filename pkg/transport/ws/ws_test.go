package ws

import (
	"bytes"
	"net"
	"testing"
	"time"
)

func TestWebSocketFrameRoundTrip(t *testing.T) {
	tests := []struct {
		name   string
		data   []byte
		masked bool
	}{
		{"small unmasked", []byte("hello"), false},
		{"small masked", []byte("hello"), true},
		{"medium unmasked", bytes.Repeat([]byte("x"), 1000), false},
		{"medium masked", bytes.Repeat([]byte("x"), 1000), true},
		{"large unmasked", bytes.Repeat([]byte("y"), 70000), false},
		{"empty unmasked", []byte{}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer

			if err := writeFrame(&buf, tt.data, tt.masked); err != nil {
				t.Fatalf("writeFrame: %v", err)
			}

			opcode, data, err := readFrame(&buf)
			if err != nil {
				t.Fatalf("readFrame: %v", err)
			}

			if opcode != opcodeBinary {
				t.Errorf("opcode = 0x%x, want 0x%x (binary)", opcode, opcodeBinary)
			}
			if !bytes.Equal(data, tt.data) {
				t.Errorf("data length = %d, want %d", len(data), len(tt.data))
			}
		})
	}
}

func TestWebSocketConnReadWrite(t *testing.T) {
	serverRaw, clientRaw := net.Pipe()
	defer serverRaw.Close()
	defer clientRaw.Close()

	clientWS := WrapClient(clientRaw)
	serverWS := WrapServer(serverRaw)

	testData := []byte("VPN packet data here")

	// Client writes, server reads
	go func() {
		clientWS.Write(testData)
	}()

	buf := make([]byte, 1024)
	serverRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, err := serverWS.Read(buf)
	if err != nil {
		t.Fatalf("server Read: %v", err)
	}
	if !bytes.Equal(buf[:n], testData) {
		t.Errorf("server got %q, want %q", buf[:n], testData)
	}

	// Server writes, client reads
	go func() {
		serverWS.Write(testData)
	}()

	clientRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, err = clientWS.Read(buf)
	if err != nil {
		t.Fatalf("client Read: %v", err)
	}
	if !bytes.Equal(buf[:n], testData) {
		t.Errorf("client got %q, want %q", buf[:n], testData)
	}
}

func TestWebSocketUpgradeHandshake(t *testing.T) {
	serverRaw, clientRaw := net.Pipe()
	defer serverRaw.Close()
	defer clientRaw.Close()

	var serverErr error
	var serverWSConn *Conn

	go func() {
		serverWSConn, serverErr = ServerUpgrade(serverRaw, nil)
	}()

	clientRaw.SetDeadline(time.Now().Add(2 * time.Second))
	clientWSConn, err := clientUpgrade(clientRaw, "test.example.com")
	if err != nil {
		t.Fatalf("client upgrade: %v", err)
	}

	time.Sleep(100 * time.Millisecond)
	if serverErr != nil {
		t.Fatalf("server upgrade: %v", serverErr)
	}

	// Exchange data over WebSocket
	testData := []byte("authenticated VPN data")

	go func() {
		clientWSConn.Write(testData)
	}()

	buf := make([]byte, 1024)
	serverRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, err := serverWSConn.Read(buf)
	if err != nil {
		t.Fatalf("read after upgrade: %v", err)
	}
	if !bytes.Equal(buf[:n], testData) {
		t.Errorf("got %q, want %q", buf[:n], testData)
	}
}

func TestComputeAcceptKey(t *testing.T) {
	// Verify self-consistency: client and server compute the same key
	key := "dGhlIHNhbXBsZSBub25jZQ=="
	accept := computeAcceptKey(key)
	if accept == "" {
		t.Error("computeAcceptKey returned empty string")
	}

	// Verify it produces the same result on repeated calls
	accept2 := computeAcceptKey(key)
	if accept != accept2 {
		t.Errorf("computeAcceptKey not deterministic: %q != %q", accept, accept2)
	}

	// Different key should produce different accept
	accept3 := computeAcceptKey("different-key")
	if accept == accept3 {
		t.Error("different keys produced same accept value")
	}
}

func TestMultipleFrames(t *testing.T) {
	serverRaw, clientRaw := net.Pipe()
	defer serverRaw.Close()
	defer clientRaw.Close()

	clientWS := WrapClient(clientRaw)
	serverWS := WrapServer(serverRaw)

	packets := [][]byte{
		[]byte("packet 1"),
		[]byte("packet 2 is longer"),
		bytes.Repeat([]byte("x"), 500),
	}

	// Send all packets
	go func() {
		for _, p := range packets {
			if _, err := clientWS.Write(p); err != nil {
				t.Errorf("write: %v", err)
				return
			}
		}
	}()

	// Receive all packets
	buf := make([]byte, 1024)
	for i, want := range packets {
		serverRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, err := serverWS.Read(buf)
		if err != nil {
			t.Fatalf("read packet %d: %v", i, err)
		}
		if !bytes.Equal(buf[:n], want) {
			t.Errorf("packet %d: got %d bytes, want %d bytes", i, n, len(want))
		}
	}
}
