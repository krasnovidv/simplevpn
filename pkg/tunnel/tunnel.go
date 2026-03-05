// Package tunnel provides the shared VPN tunnel protocol used by both server and client.
//
// It encapsulates the full packet pipeline:
//
//	Send: IP packet → AES-256-GCM encrypt → ChaCha20 obfuscate → length-prefixed frame → TLS
//	Recv: TLS → length-prefixed frame → de-obfuscate → decrypt → IP packet
package tunnel

import (
	"fmt"
	"io"
	"log"

	vpncrypto "simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
	"simplevpn/pkg/replay"
)

// Tunnel handles encrypting/obfuscating outgoing packets and
// decrypting/deobfuscating incoming packets over a TLS connection.
type Tunnel struct {
	keys        *Keys
	replayWin   *replay.Window
	conn        io.ReadWriter
	frameBuf    []byte
	encBuf      []byte
	obfsBuf     []byte
	decBuf      []byte
}

// New creates a Tunnel that reads/writes framed, encrypted, obfuscated packets over conn.
func New(keys *Keys, conn io.ReadWriter) *Tunnel {
	maxObfs := MaxFrameSize + vpncrypto.Overhead + obfs.HeaderSize + obfs.MaxPad
	t := &Tunnel{
		keys:     keys,
		replayWin: replay.New(),
		conn:     conn,
		frameBuf: make([]byte, maxObfs),
		encBuf:   make([]byte, 0, MaxFrameSize+vpncrypto.Overhead),
		obfsBuf:  make([]byte, 0, maxObfs),
		decBuf:   make([]byte, 0, MaxFrameSize),
	}
	log.Printf("[tunnel] New tunnel created, max frame=%d", maxObfs)
	return t
}

// Send encrypts, obfuscates, and writes a packet (IP payload) to the connection.
func (t *Tunnel) Send(packet []byte) error {
	encrypted, err := t.keys.Cipher.Encrypt(t.encBuf[:0], packet)
	if err != nil {
		return fmt.Errorf("encrypt: %w", err)
	}

	obfuscated, err := t.keys.Obfuscator.Wrap(t.obfsBuf[:0], encrypted)
	if err != nil {
		return fmt.Errorf("obfuscate: %w", err)
	}

	if err := WriteFrame(t.conn, obfuscated); err != nil {
		return fmt.Errorf("write frame: %w", err)
	}
	return nil
}

// Recv reads a frame from the connection, deobfuscates, and decrypts it.
// Returns the plaintext IP packet.
func (t *Tunnel) Recv() ([]byte, error) {
	frame, err := ReadFrame(t.conn, t.frameBuf)
	if err != nil {
		return nil, err
	}

	encrypted, err := t.keys.Obfuscator.Unwrap(frame)
	if err != nil {
		return nil, fmt.Errorf("deobfuscate: %w", err)
	}

	plaintext, err := t.keys.Cipher.Decrypt(t.decBuf[:0], encrypted)
	if err != nil {
		return nil, fmt.Errorf("decrypt: %w", err)
	}

	return plaintext, nil
}

// ReplayWindow returns the replay protection window for this tunnel.
func (t *Tunnel) ReplayWindow() *replay.Window {
	return t.replayWin
}
