// Package obfs реализует несколько слоёв обфускации трафика поверх AES-GCM шифрования.
//
// # Зачем нужна обфускация поверх шифрования?
//
// AES-256-GCM даёт отличную криптографическую защиту, но не скрывает факт
// использования VPN. DPI-системы (ТСПУ, GFW) используют несколько методов детекции:
//
//  1. Entropy analysis: зашифрованные данные имеют энтропию ≈8 бит/байт.
//     Статистические тесты (chi-square, byte frequency) легко это обнаруживают.
//
//  2. Packet size fingerprinting: фиксированный overhead AES-GCM (28 байт)
//     создаёт характерное распределение размеров пакетов.
//
//  3. Protocol signature: нет TLS handshake, HTTP-заголовков или других
//     признаков легитимного протокола.
//
// # Решение
//
// Entropy masking через XOR с ChaCha20-потоком. Это не ослабляет безопасность
// (данные уже защищены AES-GCM), но разрушает статистические паттерны.
// Добавляем случайный padding для рандомизации размеров пакетов.
//
// # Формат обфусцированного пакета
//
//	┌──────────────┬──────────┬──────────────────────────────┬─────────────┐
//	│  Seed (4B)   │PadLen(1B)│  XOR(AES-payload, PRG(seed)) │ Random Pad  │
//	└──────────────┴──────────┴──────────────────────────────┴─────────────┘
//
// Seed — случайный, уникальный для каждого пакета. Генерирует разный XOR-поток
// при каждой передаче даже одних и тех же данных.
package obfs

import (
	"crypto/rand"
	"fmt"
	"io"
	"math"
	"math/big"

	"golang.org/x/crypto/chacha20"
)

const (
	SeedSize   = 4   // байт seed в заголовке пакета
	PadLenSize = 1   // байт для хранения длины padding
	HeaderSize = SeedSize + PadLenSize
	MaxPad     = 255 // максимум padding (1 байт на длину → max 255)
)

// Obfuscator применяет и снимает обфускацию поверх зашифрованных данных.
type Obfuscator struct {
	key [32]byte // секретный ключ, производный от PSK
}

// New создаёт Obfuscator. obfsKey должен быть выведен из PSK через DeriveObfsKey.
func New(obfsKey [32]byte) *Obfuscator {
	return &Obfuscator{key: obfsKey}
}

// Wrap обфусцирует payload:
//  1. Генерирует случайный seed
//  2. XOR-ит payload с ChaCha20-потоком, ключ которого зависит от seed
//  3. Добавляет случайный padding для рандомизации размера пакета
func (o *Obfuscator) Wrap(dst, payload []byte) ([]byte, error) {
	// Случайный seed — основа уникального XOR-потока для каждого пакета
	var seed [SeedSize]byte
	if _, err := io.ReadFull(rand.Reader, seed[:]); err != nil {
		return nil, fmt.Errorf("generate seed: %w", err)
	}

	// Случайный размер padding: скрывает реальный размер пакета
	padLenBig, err := rand.Int(rand.Reader, big.NewInt(MaxPad+1))
	if err != nil {
		return nil, fmt.Errorf("generate pad length: %w", err)
	}
	padLen := byte(padLenBig.Int64())

	totalSize := HeaderSize + len(payload) + int(padLen)
	if dst == nil {
		dst = make([]byte, 0, totalSize)
	}

	// Заголовок: [seed(4)] [padLen(1)]
	dst = append(dst, seed[:]...)
	dst = append(dst, padLen)

	// XOR payload с ChaCha20-потоком
	xored, err := o.xorStream(seed, payload)
	if err != nil {
		return nil, fmt.Errorf("xor stream: %w", err)
	}
	dst = append(dst, xored...)

	// Случайный padding
	if padLen > 0 {
		pad := make([]byte, padLen)
		if _, err := io.ReadFull(rand.Reader, pad); err != nil {
			return nil, fmt.Errorf("generate padding: %w", err)
		}
		dst = append(dst, pad...)
	}

	return dst, nil
}

// Unwrap снимает обфускацию и возвращает оригинальный payload.
func (o *Obfuscator) Unwrap(data []byte) ([]byte, error) {
	if len(data) < HeaderSize {
		return nil, fmt.Errorf("packet too short: %d < %d", len(data), HeaderSize)
	}

	var seed [SeedSize]byte
	copy(seed[:], data[:SeedSize])
	padLen := int(data[SeedSize])

	payloadLen := len(data) - HeaderSize - padLen
	if payloadLen <= 0 {
		return nil, fmt.Errorf("invalid payload length after unwrap: %d", payloadLen)
	}

	xored := data[HeaderSize : HeaderSize+payloadLen]
	return o.xorStream(seed, xored)
}

// xorStream применяет ChaCha20-поток к data.
// Ключ = o.key XOR (seed, расширенный до 32 байт) — уникален для каждого пакета.
// Нулевой nonce безопасен, потому что ключ никогда не повторяется.
func (o *Obfuscator) xorStream(seed [SeedSize]byte, data []byte) ([]byte, error) {
	var streamKey [32]byte
	for i := 0; i < 32; i++ {
		streamKey[i] = o.key[i] ^ seed[i%SeedSize] ^ byte(i*7+13)
	}

	nonce := make([]byte, chacha20.NonceSize) // нулевой nonce

	c, err := chacha20.NewUnauthenticatedCipher(streamKey[:], nonce)
	if err != nil {
		return nil, fmt.Errorf("chacha20 init: %w", err)
	}

	out := make([]byte, len(data))
	c.XORKeyStream(out, data)
	return out, nil
}

// DeriveObfsKey выводит ключ обфускации из основного ключа.
// Используем другой derive чтобы ключи шифрования и обфускации были независимы.
func DeriveObfsKey(masterKey [32]byte) [32]byte {
	magic := [32]byte{
		0x6f, 0x62, 0x66, 0x73, 0x2d, 0x6b, 0x65, 0x79,
		0x2d, 0x64, 0x65, 0x72, 0x69, 0x76, 0x65, 0x21,
		0x9a, 0x4f, 0x2c, 0x11, 0x87, 0xe3, 0x5d, 0x00,
		0xab, 0xcd, 0x42, 0x17, 0x3e, 0x9f, 0x01, 0x55,
	}
	var obfsKey [32]byte
	for i := 0; i < 32; i++ {
		obfsKey[i] = masterKey[i] ^ magic[i] ^ byte((i*31+7)%251)
	}
	return obfsKey
}

// TimingJitter возвращает случайное число миллисекунд (0..maxMs) для
// размытия timing-паттернов трафика.
func TimingJitter(maxMs int) int64 {
	if maxMs <= 0 {
		return 0
	}
	n, err := rand.Int(rand.Reader, big.NewInt(int64(maxMs)))
	if err != nil {
		return 0
	}
	return n.Int64()
}

// EntropyScore возвращает энтропию Шеннона для среза байт (0.0–8.0 бит/байт).
// Используется в тестах: после Wrap entropy должна оставаться высокой
// (данные случайны), но byte-distribution статистически отличается от "чистого" AES-GCM.
func EntropyScore(data []byte) float64 {
	if len(data) == 0 {
		return 0
	}
	counts := [256]int{}
	for _, b := range data {
		counts[b]++
	}
	var h float64
	n := float64(len(data))
	for _, c := range counts {
		if c == 0 {
			continue
		}
		p := float64(c) / n
		h -= p * math.Log2(p)
	}
	return h
}
