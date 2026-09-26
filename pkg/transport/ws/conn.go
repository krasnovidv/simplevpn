// WebSocket connection wrapper.
//
// Conn implements net.Conn over a WebSocket connection, transparently
// encoding/decoding VPN data as WebSocket binary frames.
// Callers read/write raw VPN data — framing is handled internally.
package ws

import (
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"time"
)

// Conn wraps a net.Conn and provides WebSocket binary frame read/write.
// It implements net.Conn so it can be used directly by tunnel.Tunnel.
type Conn struct {
	inner  net.Conn
	masked bool // true for client (sends masked frames), false for server

	// src is where frames are read from: the bufio.Reader that parsed the
	// HTTP upgrade (it may already hold the first frames) or inner itself.
	src io.Reader

	// Read buffering: WebSocket frames may contain more data than
	// the caller's buffer, so we buffer the excess.
	readMu  sync.Mutex
	readBuf []byte

	writeMu sync.Mutex
}

// WrapClient wraps a net.Conn as a client-side WebSocket connection.
// Client frames are masked per RFC 6455.
func WrapClient(conn net.Conn) *Conn {
	log.Printf("[transport/ws] Wrapping client connection to %s", conn.RemoteAddr())
	return &Conn{inner: conn, masked: true, src: conn}
}

// WrapServer wraps a net.Conn as a server-side WebSocket connection.
// Server frames are unmasked per RFC 6455.
func WrapServer(conn net.Conn) *Conn {
	log.Printf("[transport/ws] Wrapping server connection from %s", conn.RemoteAddr())
	return &Conn{inner: conn, masked: false, src: conn}
}

// Read reads data from the WebSocket connection.
// It reads a binary frame if the internal buffer is empty,
// and returns data from the buffer.
func (c *Conn) Read(b []byte) (int, error) {
	c.readMu.Lock()
	defer c.readMu.Unlock()

	// Return buffered data first
	if len(c.readBuf) > 0 {
		n := copy(b, c.readBuf)
		c.readBuf = c.readBuf[n:]
		return n, nil
	}

	// Read the next data message. Control frames may be interleaved with the
	// fragments of a message (RFC 6455 §5.4), so they are handled in-line.
	var msg []byte
	inMessage := false
	for {
		opcode, fin, data, err := readFrameFin(c.src)
		if err != nil {
			return 0, err
		}

		switch opcode {
		case opcodeBinary, opcodeText:
			if inMessage {
				return 0, fmt.Errorf("websocket: new data frame inside a fragmented message")
			}
			msg, inMessage = data, true
		case opcodeContinuation:
			if !inMessage {
				return 0, fmt.Errorf("websocket: continuation frame without a message")
			}
			if len(msg)+len(data) > maxMessageSize {
				return 0, fmt.Errorf("websocket: message exceeds %d bytes", maxMessageSize)
			}
			msg = append(msg, data...)
		case opcodePing:
			if len(data) > 125 || !fin {
				return 0, fmt.Errorf("websocket: invalid ping frame")
			}
			c.writeMu.Lock()
			err := writePong(c.inner, data, c.masked)
			c.writeMu.Unlock()
			if err != nil {
				return 0, fmt.Errorf("send pong: %w", err)
			}
			continue
		case opcodePong:
			continue
		case opcodeClose:
			log.Printf("[transport/ws] Received close frame from %s", c.inner.RemoteAddr())
			return 0, fmt.Errorf("websocket closed by peer")
		default:
			return 0, fmt.Errorf("websocket: unknown opcode 0x%x", opcode)
		}

		if !fin {
			continue
		}
		n := copy(b, msg)
		if n < len(msg) {
			c.readBuf = append(c.readBuf[:0], msg[n:]...)
		}
		return n, nil
	}
}

// Write sends data as a WebSocket binary frame.
func (c *Conn) Write(b []byte) (int, error) {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if err := writeFrame(c.inner, b, c.masked); err != nil {
		return 0, err
	}
	return len(b), nil
}

func (c *Conn) Close() error                       { return c.inner.Close() }
func (c *Conn) LocalAddr() net.Addr                { return c.inner.LocalAddr() }
func (c *Conn) RemoteAddr() net.Addr               { return c.inner.RemoteAddr() }
func (c *Conn) SetDeadline(t time.Time) error      { return c.inner.SetDeadline(t) }
func (c *Conn) SetReadDeadline(t time.Time) error  { return c.inner.SetReadDeadline(t) }
func (c *Conn) SetWriteDeadline(t time.Time) error { return c.inner.SetWriteDeadline(t) }
