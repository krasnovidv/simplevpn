package ws

import (
	"bytes"
	"errors"
	"io"
	"net"
	"testing"
	"time"
)

// rawFrame builds a single frame by hand (unmasked unless maskKey given).
func rawFrame(opcode byte, fin bool, payload []byte, maskKey []byte) []byte {
	b0 := opcode
	if fin {
		b0 |= finBit
	}
	out := []byte{b0}
	b1 := byte(len(payload)) // tests keep payloads ≤125
	if maskKey != nil {
		b1 |= maskBit
	}
	out = append(out, b1)
	if maskKey != nil {
		out = append(out, maskKey...)
		m := make([]byte, len(payload))
		for i := range payload {
			m[i] = payload[i] ^ maskKey[i%4]
		}
		payload = m
	}
	return append(out, payload...)
}

func upgradeRequest(path string) string {
	return "GET " + path + " HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
		"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
}

// A client that sends its first frame in the same write as the upgrade
// request must not have those bytes handed to the caller still framed.
func TestServerUpgradeKeepsPipelinedFrame(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	payload := []byte("first-frame")
	go func() {
		client.Write(append([]byte(upgradeRequest(wsPath)), rawFrame(opcodeBinary, true, payload, []byte{1, 2, 3, 4})...))
		io.Copy(io.Discard, client)
	}()

	server.SetDeadline(time.Now().Add(2 * time.Second))
	c, err := ServerUpgrade(server, nil)
	if err != nil {
		t.Fatalf("upgrade: %v", err)
	}
	buf := make([]byte, 64)
	n, err := c.Read(buf)
	if err != nil || !bytes.Equal(buf[:n], payload) {
		t.Fatalf("Read = %q, %v; want %q", buf[:n], err, payload)
	}
}

func TestServerUpgradeRejectsOtherPaths(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()
	go client.Write([]byte(upgradeRequest("/chat")))

	server.SetDeadline(time.Now().Add(2 * time.Second))
	_, err := ServerUpgrade(server, nil)
	var nu *NotUpgradeError
	if !errors.As(err, &nu) || nu.Path != "/chat" {
		t.Fatalf("err = %v, want NotUpgradeError for /chat", err)
	}
}

// Fragmented message with a ping in the middle: the message is reassembled
// and the ping answered.
func TestReadReassemblesFragments(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()
	c := WrapServer(server)

	key := []byte{9, 8, 7, 6}
	go func() {
		client.Write(rawFrame(opcodeBinary, false, []byte("hello "), key))
		client.Write(rawFrame(opcodePing, true, []byte("p"), key))
		// The pong comes back before the rest of the message is sent.
		hdr := make([]byte, 3)
		io.ReadFull(client, hdr)
		client.Write(rawFrame(opcodeContinuation, true, []byte("world"), key))
	}()

	server.SetDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 64)
	n, err := c.Read(buf)
	if err != nil || string(buf[:n]) != "hello world" {
		t.Fatalf("Read = %q, %v; want \"hello world\"", buf[:n], err)
	}
}
