package crypto

import (
	"bytes"
	"testing"
)

func testKey(b byte) [32]byte {
	var k [32]byte
	for i := range k {
		k[i] = b
	}
	return k
}

func TestEncryptDecryptRoundtrip(t *testing.T) {
	c, err := NewCipherFromKey(testKey(0x42))
	if err != nil {
		t.Fatalf("NewCipherFromKey: %v", err)
	}

	cases := [][]byte{
		[]byte("hello"),
		{},
		bytes.Repeat([]byte{0xAB}, 1500), // typical MTU-sized packet
		bytes.Repeat([]byte{0x00}, 65535),
	}
	for _, plaintext := range cases {
		sealed, err := c.Encrypt(nil, plaintext)
		if err != nil {
			t.Fatalf("Encrypt(%d bytes): %v", len(plaintext), err)
		}
		if len(sealed) != len(plaintext)+Overhead {
			t.Errorf("sealed length = %d, want %d", len(sealed), len(plaintext)+Overhead)
		}
		opened, err := c.Decrypt(nil, sealed)
		if err != nil {
			t.Fatalf("Decrypt(%d bytes): %v", len(plaintext), err)
		}
		if !bytes.Equal(opened, plaintext) {
			t.Errorf("roundtrip mismatch for %d-byte plaintext", len(plaintext))
		}
	}
}

func TestDecryptRejectsTamperedCiphertext(t *testing.T) {
	c, _ := NewCipherFromKey(testKey(0x42))
	sealed, err := c.Encrypt(nil, []byte("sensitive packet"))
	if err != nil {
		t.Fatalf("Encrypt: %v", err)
	}

	// Flip one bit in every position: nonce, ciphertext body, GCM tag.
	for i := range sealed {
		tampered := append([]byte(nil), sealed...)
		tampered[i] ^= 0x01
		if _, err := c.Decrypt(nil, tampered); err == nil {
			t.Errorf("Decrypt accepted ciphertext with bit flipped at offset %d", i)
		}
	}
}

func TestDecryptRejectsTruncatedInput(t *testing.T) {
	c, _ := NewCipherFromKey(testKey(0x42))
	for _, n := range []int{0, 1, NonceSize, Overhead - 1} {
		if _, err := c.Decrypt(nil, make([]byte, n)); err == nil {
			t.Errorf("Decrypt accepted %d-byte input, want error", n)
		}
	}
}

func TestDecryptRejectsWrongKey(t *testing.T) {
	c1, _ := NewCipherFromKey(testKey(0x01))
	c2, _ := NewCipherFromKey(testKey(0x02))

	sealed, err := c1.Encrypt(nil, []byte("packet"))
	if err != nil {
		t.Fatalf("Encrypt: %v", err)
	}
	if _, err := c2.Decrypt(nil, sealed); err == nil {
		t.Error("Decrypt with wrong key succeeded, want error")
	}
}

func TestEncryptNonceUniqueness(t *testing.T) {
	c, _ := NewCipherFromKey(testKey(0x42))
	seen := make(map[string]bool, 10000)
	plaintext := []byte("same plaintext every time")

	for i := 0; i < 10000; i++ {
		sealed, err := c.Encrypt(nil, plaintext)
		if err != nil {
			t.Fatalf("Encrypt: %v", err)
		}
		nonce := string(sealed[:NonceSize])
		if seen[nonce] {
			t.Fatalf("nonce reused after %d encryptions", i)
		}
		seen[nonce] = true
	}
}

func TestEncryptAppendsToDst(t *testing.T) {
	c, _ := NewCipherFromKey(testKey(0x42))
	prefix := []byte("header")

	sealed, err := c.Encrypt(append([]byte(nil), prefix...), []byte("payload"))
	if err != nil {
		t.Fatalf("Encrypt: %v", err)
	}
	if !bytes.HasPrefix(sealed, prefix) {
		t.Fatal("Encrypt did not preserve dst prefix")
	}
	opened, err := c.Decrypt(nil, sealed[len(prefix):])
	if err != nil {
		t.Fatalf("Decrypt: %v", err)
	}
	if !bytes.Equal(opened, []byte("payload")) {
		t.Error("payload mismatch after dst-prefix roundtrip")
	}
}

func BenchmarkEncrypt1500(b *testing.B) {
	c, _ := NewCipherFromKey(testKey(0x42))
	packet := make([]byte, 1500)
	buf := make([]byte, 0, 1500+Overhead)
	b.SetBytes(1500)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		out, err := c.Encrypt(buf[:0], packet)
		if err != nil {
			b.Fatal(err)
		}
		_ = out
	}
}

func BenchmarkDecrypt1500(b *testing.B) {
	c, _ := NewCipherFromKey(testKey(0x42))
	sealed, _ := c.Encrypt(nil, make([]byte, 1500))
	buf := make([]byte, 0, 1500)
	b.SetBytes(1500)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		out, err := c.Decrypt(buf[:0], sealed)
		if err != nil {
			b.Fatal(err)
		}
		_ = out
	}
}
