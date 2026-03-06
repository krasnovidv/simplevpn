// WebSocket connection wrapper.
//
// Conn implements net.Conn over a WebSocket connection, transparently
// encoding/decoding VPN data as WebSocket binary frames.
// Callers read/write raw VPN data — framing is handled internally.
package ws

import (
	"fmt"
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
	return &Conn{inner: conn, masked: true}
}

// WrapServer wraps a net.Conn as a server-side WebSocket connection.
// Server frames are unmasked per RFC 6455.
func WrapServer(conn net.Conn) *Conn {
	log.Printf("[transport/ws] Wrapping server connection from %s", conn.RemoteAddr())
	return &Conn{inner: conn, masked: false}
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

	// Read next frame
	for {
		opcode, data, err := readFrame(c.inner)
		if err != nil {
			return 0, err
		}

		switch opcode {
		case opcodeBinary:
			n := copy(b, data)
			if n < len(data) {
				c.readBuf = append(c.readBuf[:0], data[n:]...)
			}
			return n, nil

		case opcodePing:
			log.Printf("[transport/ws] Received ping from %s, sending pong", c.inner.RemoteAddr())
			if err := writePong(c.inner, data, c.masked); err != nil {
				return 0, fmt.Errorf("send pong: %w", err)
			}
			continue // read next frame

		case opcodeClose:
			log.Printf("[transport/ws] Received close frame from %s", c.inner.RemoteAddr())
			return 0, fmt.Errorf("websocket closed by peer")

		default:
			log.Printf("[transport/ws] Ignoring frame opcode=0x%x from %s", opcode, c.inner.RemoteAddr())
			continue
		}
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
