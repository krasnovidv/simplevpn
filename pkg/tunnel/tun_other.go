//go:build !linux && !android

package tunnel

import (
	"fmt"
	"os"
)

func openTun(name string) (*os.File, error) {
	return nil, fmt.Errorf("TUN not supported on this platform")
}

// Read/Write fall back to os.File on non-Linux platforms. The server (which is
// the only consumer that actually opens a TUN device) is Linux-only, so these
// exist purely to keep the package compiling on Windows/macOS for the client.
func (t *TunDevice) Read(b []byte) (int, error)  { return t.f.Read(b) }
func (t *TunDevice) Write(b []byte) (int, error) { return t.f.Write(b) }
