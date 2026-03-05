// Frame encoding/decoding for the VPN protocol.
//
// Each message over TLS is length-prefixed:
//
//	[length uint32 big-endian] [obfuscated(encrypted(IP-packet))]
//
// This framing is needed because TLS is a stream protocol.
package tunnel

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
)

const (
	// MaxFrameSize is the maximum size of an IP packet payload.
	MaxFrameSize = 65535

	frameLenSize = 4 // uint32 big-endian
)

// WriteFrame writes a length-prefixed frame to w.
func WriteFrame(w io.Writer, data []byte) error {
	frame := make([]byte, frameLenSize+len(data))
	binary.BigEndian.PutUint32(frame[:frameLenSize], uint32(len(data)))
	copy(frame[frameLenSize:], data)
	_, err := w.Write(frame)
	return err
}

// ReadFrame reads a length-prefixed frame from r into buf.
// Returns the frame payload slice (within buf) and any error.
// buf must be large enough to hold the largest expected frame.
func ReadFrame(r io.Reader, buf []byte) ([]byte, error) {
	var lenBuf [frameLenSize]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return nil, fmt.Errorf("read frame length: %w", err)
	}
	frameLen := binary.BigEndian.Uint32(lenBuf[:])
	if frameLen > uint32(len(buf)) {
		log.Printf("[tunnel] Frame too large: %d > %d", frameLen, len(buf))
		return nil, fmt.Errorf("frame too large: %d", frameLen)
	}
	if _, err := io.ReadFull(r, buf[:frameLen]); err != nil {
		return nil, fmt.Errorf("read frame body: %w", err)
	}
	return buf[:frameLen], nil
}
