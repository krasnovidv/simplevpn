// WebSocket frame encoding/decoding (RFC 6455).
//
// Minimal implementation — only binary frames and close frames are supported.
// Text frames, fragmentation, and extensions are not needed for VPN traffic.
package ws

import (
	"encoding/binary"
	"fmt"
	"io"
	"math/rand"
)

// Frame opcodes (RFC 6455 §5.2)
const (
	opcodeBinary = 0x2
	opcodeClose  = 0x8
	opcodePing   = 0x9
	opcodePong   = 0xA
)

// Frame header bits
const (
	finBit  = 0x80
	maskBit = 0x80
)

// writeFrame writes a WebSocket binary frame.
// Client frames are masked (RFC 6455 §5.3), server frames are unmasked.
func writeFrame(w io.Writer, data []byte, masked bool) error {
	// Header: FIN + opcode
	header := []byte{finBit | opcodeBinary}

	// Payload length
	payloadLen := len(data)
	var maskFlag byte
	if masked {
		maskFlag = maskBit
	}

	switch {
	case payloadLen <= 125:
		header = append(header, byte(payloadLen)|maskFlag)
	case payloadLen <= 65535:
		header = append(header, 126|maskFlag)
		lenBuf := make([]byte, 2)
		binary.BigEndian.PutUint16(lenBuf, uint16(payloadLen))
		header = append(header, lenBuf...)
	default:
		header = append(header, 127|maskFlag)
		lenBuf := make([]byte, 8)
		binary.BigEndian.PutUint64(lenBuf, uint64(payloadLen))
		header = append(header, lenBuf...)
	}

	// Masking key (client only)
	if masked {
		maskKey := make([]byte, 4)
		binary.BigEndian.PutUint32(maskKey, rand.Uint32())
		header = append(header, maskKey...)

		// Apply mask to payload
		masked := make([]byte, len(data))
		for i, b := range data {
			masked[i] = b ^ maskKey[i%4]
		}
		data = masked
	}

	// Write header + payload atomically
	buf := make([]byte, 0, len(header)+len(data))
	buf = append(buf, header...)
	buf = append(buf, data...)
	_, err := w.Write(buf)
	return err
}

// frameHeader holds a parsed WebSocket frame header.
type frameHeader struct {
	fin        bool
	opcode     byte
	masked     bool
	payloadLen int64
	maskKey    [4]byte
}

// readFrameHeader reads and parses a WebSocket frame header.
func readFrameHeader(r io.Reader) (*frameHeader, error) {
	var buf [2]byte
	if _, err := io.ReadFull(r, buf[:]); err != nil {
		return nil, fmt.Errorf("read frame header: %w", err)
	}

	h := &frameHeader{
		fin:    buf[0]&finBit != 0,
		opcode: buf[0] & 0x0F,
		masked: buf[1]&maskBit != 0,
	}

	// Payload length
	lenField := int64(buf[1] & 0x7F)
	switch {
	case lenField <= 125:
		h.payloadLen = lenField
	case lenField == 126:
		var extLen [2]byte
		if _, err := io.ReadFull(r, extLen[:]); err != nil {
			return nil, fmt.Errorf("read extended length: %w", err)
		}
		h.payloadLen = int64(binary.BigEndian.Uint16(extLen[:]))
	case lenField == 127:
		var extLen [8]byte
		if _, err := io.ReadFull(r, extLen[:]); err != nil {
			return nil, fmt.Errorf("read extended length: %w", err)
		}
		h.payloadLen = int64(binary.BigEndian.Uint64(extLen[:]))
	}

	// Masking key
	if h.masked {
		if _, err := io.ReadFull(r, h.maskKey[:]); err != nil {
			return nil, fmt.Errorf("read mask key: %w", err)
		}
	}

	return h, nil
}

// readFrame reads a complete WebSocket frame payload.
// Returns the opcode and unmasked payload data.
func readFrame(r io.Reader) (opcode byte, data []byte, err error) {
	h, err := readFrameHeader(r)
	if err != nil {
		return 0, nil, err
	}

	if h.payloadLen > 1<<20 { // 1MB sanity limit for VPN packets
		return 0, nil, fmt.Errorf("frame too large: %d bytes", h.payloadLen)
	}

	data = make([]byte, h.payloadLen)
	if h.payloadLen > 0 {
		if _, err := io.ReadFull(r, data); err != nil {
			return 0, nil, fmt.Errorf("read frame payload: %w", err)
		}

		// Unmask
		if h.masked {
			for i := range data {
				data[i] ^= h.maskKey[i%4]
			}
		}
	}

	return h.opcode, data, nil
}

// writePong sends a pong frame with the given payload.
func writePong(w io.Writer, payload []byte, masked bool) error {
	header := []byte{finBit | opcodePong}
	var maskFlag byte
	if masked {
		maskFlag = maskBit
	}
	header = append(header, byte(len(payload))|maskFlag)

	if masked {
		maskKey := make([]byte, 4)
		binary.BigEndian.PutUint32(maskKey, rand.Uint32())
		header = append(header, maskKey...)
		maskedPayload := make([]byte, len(payload))
		for i, b := range payload {
			maskedPayload[i] = b ^ maskKey[i%4]
		}
		payload = maskedPayload
	}

	buf := make([]byte, 0, len(header)+len(payload))
	buf = append(buf, header...)
	buf = append(buf, payload...)
	_, err := w.Write(buf)
	return err
}
