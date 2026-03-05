package obfs_test

import (
	"bytes"
	"testing"

	"simplevpn/pkg/obfs"
)

func TestWrapUnwrap(t *testing.T) {
	key := [32]byte{}
	copy(key[:], "test-key-for-obfuscation-32bytes")
	o := obfs.New(key)

	original := []byte("Hello, this is a test VPN packet with some data inside it!")

	wrapped, err := o.Wrap(nil, original)
	if err != nil {
		t.Fatalf("Wrap: %v", err)
	}

	if bytes.Contains(wrapped, original) {
		t.Error("Wrapped packet contains original data — obfuscation not working")
	}

	if len(wrapped) < len(original)+obfs.HeaderSize {
		t.Errorf("Wrapped packet too small: %d < %d", len(wrapped), len(original)+obfs.HeaderSize)
	}

	unwrapped, err := o.Unwrap(wrapped)
	if err != nil {
		t.Fatalf("Unwrap: %v", err)
	}

	if !bytes.Equal(original, unwrapped) {
		t.Fatalf("Data mismatch after Unwrap:\nExpected: %q\nGot:      %q", original, unwrapped)
	}
}

func TestWrapRandomness(t *testing.T) {
	key := [32]byte{}
	o := obfs.New(key)
	data := []byte("same data every time")

	w1, _ := o.Wrap(nil, data)
	w2, _ := o.Wrap(nil, data)

	if bytes.Equal(w1, w2) {
		t.Error("Two Wraps of same data produced identical results — seed not random!")
	}
}

func TestWrapTamper(t *testing.T) {
	key := [32]byte{}
	o := obfs.New(key)
	data := []byte("sensitive data")

	wrapped, _ := o.Wrap(nil, data)

	tampered := make([]byte, len(wrapped))
	copy(tampered, wrapped)
	tampered[0] ^= 0xFF

	unwrapped, err := o.Unwrap(tampered)
	if err == nil && bytes.Equal(unwrapped, data) {
		t.Error("Tampered seed did not change data — XOR not applied to seed?")
	}
}

func TestPaddingRandomizesSizes(t *testing.T) {
	key := [32]byte{}
	o := obfs.New(key)
	data := make([]byte, 100)

	sizes := make(map[int]bool)
	for i := 0; i < 50; i++ {
		w, _ := o.Wrap(nil, data)
		sizes[len(w)] = true
	}

	if len(sizes) < 5 {
		t.Errorf("Packet sizes not diverse enough: %d unique out of 50", len(sizes))
	}
	t.Logf("Unique sizes: %d out of 50 attempts", len(sizes))
}

func TestEntropyScore(t *testing.T) {
	zeros := make([]byte, 100)
	h := obfs.EntropyScore(zeros)
	if h != 0 {
		t.Errorf("Entropy of zeros should be 0, got %.2f", h)
	}

	random := make([]byte, 256)
	for i := range random {
		random[i] = byte(i)
	}
	h = obfs.EntropyScore(random)
	if h < 7.9 {
		t.Errorf("Entropy of uniform distribution should be ~8, got %.2f", h)
	}
}

func BenchmarkWrap(b *testing.B) {
	key := [32]byte{}
	o := obfs.New(key)
	data := make([]byte, 1420)

	b.ResetTimer()
	b.SetBytes(int64(len(data)))

	for i := 0; i < b.N; i++ {
		o.Wrap(nil, data)
	}
}

func BenchmarkUnwrap(b *testing.B) {
	key := [32]byte{}
	o := obfs.New(key)
	data := make([]byte, 1420)

	wrapped, _ := o.Wrap(nil, data)

	b.ResetTimer()
	b.SetBytes(int64(len(data)))

	for i := 0; i < b.N; i++ {
		o.Unwrap(wrapped)
	}
}
