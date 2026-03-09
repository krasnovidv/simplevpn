package tunnel

import (
	"bytes"
	"testing"
)

func TestDeriveKeys(t *testing.T) {
	keys, err := DeriveKeys("test-psk-123")
	if err != nil {
		t.Fatalf("DeriveKeys: %v", err)
	}
	if keys.Cipher == nil {
		t.Fatal("Cipher is nil")
	}
	if keys.Obfuscator == nil {
		t.Fatal("Obfuscator is nil")
	}

	// Same server key should produce same keys
	keys2, err := DeriveKeys("test-psk-123")
	if err != nil {
		t.Fatalf("DeriveKeys (2nd): %v", err)
	}
	if keys.Master != keys2.Master {
		t.Error("Master keys differ for same server key")
	}
	if keys.Enc != keys2.Enc {
		t.Error("Encryption keys differ for same server key")
	}
	if keys.Obfs != keys2.Obfs {
		t.Error("Obfuscation keys differ for same server key")
	}

	// Different server key should produce different keys
	keys3, err := DeriveKeys("different-psk")
	if err != nil {
		t.Fatalf("DeriveKeys (3rd): %v", err)
	}
	if keys.Master == keys3.Master {
		t.Error("Master keys should differ for different server key")
	}
}

func TestFrameRoundtrip(t *testing.T) {
	testData := []byte("hello VPN tunnel frame test")

	var buf bytes.Buffer
	if err := WriteFrame(&buf, testData); err != nil {
		t.Fatalf("WriteFrame: %v", err)
	}

	// Written data should be 4 bytes length + payload
	if buf.Len() != 4+len(testData) {
		t.Errorf("Expected %d bytes, got %d", 4+len(testData), buf.Len())
	}

	readBuf := make([]byte, MaxFrameSize)
	result, err := ReadFrame(&buf, readBuf)
	if err != nil {
		t.Fatalf("ReadFrame: %v", err)
	}

	if !bytes.Equal(result, testData) {
		t.Errorf("Data mismatch: got %q, want %q", result, testData)
	}
}

func TestFrameEmptyPayload(t *testing.T) {
	var buf bytes.Buffer
	if err := WriteFrame(&buf, []byte{}); err != nil {
		t.Fatalf("WriteFrame empty: %v", err)
	}
	if buf.Len() != 4 {
		t.Errorf("Expected 4 bytes for empty frame, got %d", buf.Len())
	}
}

func TestFrameTooLarge(t *testing.T) {
	// Write a frame that claims to be larger than our read buffer
	var buf bytes.Buffer
	data := make([]byte, 100)
	WriteFrame(&buf, data)

	smallBuf := make([]byte, 10) // too small
	_, err := ReadFrame(&buf, smallBuf)
	if err == nil {
		t.Error("Expected error for frame too large")
	}
}

func TestTunnelSendRecv(t *testing.T) {
	keys, err := DeriveKeys("test-psk-roundtrip")
	if err != nil {
		t.Fatalf("DeriveKeys: %v", err)
	}

	// Use a pipe-like buffer for bidirectional test
	var pipe bytes.Buffer

	sender := New(keys, &pipe)
	original := []byte("Hello, this is a test IP packet payload for VPN tunnel roundtrip")

	if err := sender.Send(original); err != nil {
		t.Fatalf("Send: %v", err)
	}

	receiver := New(keys, &pipe)
	received, err := receiver.Recv()
	if err != nil {
		t.Fatalf("Recv: %v", err)
	}

	if !bytes.Equal(received, original) {
		t.Errorf("Roundtrip mismatch:\n  got:  %x\n  want: %x", received, original)
	}
}

func TestTunnelLargePacket(t *testing.T) {
	keys, err := DeriveKeys("test-large-packet")
	if err != nil {
		t.Fatalf("DeriveKeys: %v", err)
	}

	var pipe bytes.Buffer
	sender := New(keys, &pipe)

	// 1500 byte "IP packet" (typical MTU)
	original := make([]byte, 1500)
	for i := range original {
		original[i] = byte(i % 256)
	}

	if err := sender.Send(original); err != nil {
		t.Fatalf("Send large: %v", err)
	}

	receiver := New(keys, &pipe)
	received, err := receiver.Recv()
	if err != nil {
		t.Fatalf("Recv large: %v", err)
	}

	if !bytes.Equal(received, original) {
		t.Error("Large packet roundtrip mismatch")
	}
}

func TestTunnelMultiplePackets(t *testing.T) {
	keys, err := DeriveKeys("test-multi-packet")
	if err != nil {
		t.Fatalf("DeriveKeys: %v", err)
	}

	var pipe bytes.Buffer
	sender := New(keys, &pipe)

	packets := []string{
		"packet one",
		"packet two with more data",
		"packet three is even longer than the others!",
	}

	for _, p := range packets {
		if err := sender.Send([]byte(p)); err != nil {
			t.Fatalf("Send %q: %v", p, err)
		}
	}

	receiver := New(keys, &pipe)
	for _, expected := range packets {
		received, err := receiver.Recv()
		if err != nil {
			t.Fatalf("Recv: %v", err)
		}
		if string(received) != expected {
			t.Errorf("Got %q, want %q", string(received), expected)
		}
	}
}
