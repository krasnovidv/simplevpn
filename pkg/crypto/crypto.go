// Package crypto реализует AES-256-GCM шифрование для VPN-пакетов.
//
// Каждый пакет шифруется с уникальным nonce (генерируется случайно).
// Формат зашифрованного пакета:
//
//	[nonce (12 байт)] [ciphertext + GCM tag (16 байт)]
package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"fmt"
	"io"
)

const (
	NonceSize = 12                    // AES-GCM стандартный nonce
	TagSize   = 16                    // GCM authentication tag
	Overhead  = NonceSize + TagSize   // доп. байты на каждый пакет
)

// Cipher — AES-256-GCM шифратор/дешифратор.
type Cipher struct {
	aead cipher.AEAD
}

// NewCipherFromKey создаёт Cipher из 32-байтного ключа (SHA-256 hash).
func NewCipherFromKey(key [32]byte) (*Cipher, error) {
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, fmt.Errorf("aes.NewCipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("cipher.NewGCM: %w", err)
	}
	return &Cipher{aead: aead}, nil
}

// Encrypt шифрует plaintext и возвращает [nonce || ciphertext].
// dst может использоваться для предаллокации буфера (append-семантика).
func (c *Cipher) Encrypt(dst, plaintext []byte) ([]byte, error) {
	nonce := make([]byte, NonceSize)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("generate nonce: %w", err)
	}

	dst = append(dst, nonce...)
	dst = c.aead.Seal(dst, nonce, plaintext, nil)
	return dst, nil
}

// Decrypt расшифровывает данные формата [nonce || ciphertext].
// dst может использоваться для предаллокации буфера (append-семантика).
func (c *Cipher) Decrypt(dst, data []byte) ([]byte, error) {
	if len(data) < Overhead {
		return nil, fmt.Errorf("ciphertext too short: %d < %d", len(data), Overhead)
	}

	nonce := data[:NonceSize]
	ciphertext := data[NonceSize:]

	plaintext, err := c.aead.Open(dst, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("decrypt: %w", err)
	}
	return plaintext, nil
}
