//go:build !linux && !android

package tunnel

import (
	"fmt"
	"os"
)

func openTun(name string) (*os.File, error) {
	return nil, fmt.Errorf("TUN not supported on this platform")
}
