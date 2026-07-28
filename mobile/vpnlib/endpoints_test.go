package vpnlib

import (
	"strings"
	"testing"
)

// The retired address is the one users still carry in their stored config after
// the July 2026 move, so the ordering rules below are what decides whether
// connecting feels instant or costs a dialTimeout first.
const (
	retiredAddr = "193.23.3.93:443"
	liveAddr    = "89.40.233.67:443"
)

func TestEndpointCandidates(t *testing.T) {
	tests := []struct {
		name string
		cfg  Config
		want []string
	}{
		{
			name: "plain config yields just the server",
			cfg:  Config{Server: "1.2.3.4:443"},
			want: []string{"1.2.3.4:443"},
		},
		{
			name: "explicit endpoints follow the server",
			cfg:  Config{Server: "1.2.3.4:443", Endpoints: []string{"5.6.7.8:443", "9.9.9.9:2053"}},
			want: []string{"1.2.3.4:443", "5.6.7.8:443", "9.9.9.9:2053"},
		},
		{
			// The whole point of the rebuild: a stored config still naming the
			// dead server must reach the live one on the first attempt.
			name: "retired primary is demoted behind its successor",
			cfg:  Config{Server: retiredAddr},
			want: []string{liveAddr, retiredAddr},
		},
		{
			name: "retired address stays last however it entered the list",
			cfg:  Config{Server: liveAddr, Endpoints: []string{retiredAddr, "89.40.233.67:2053"}},
			want: []string{liveAddr, "89.40.233.67:2053", retiredAddr},
		},
		{
			name: "duplicates collapse, first position wins",
			cfg:  Config{Server: "1.2.3.4:443", Endpoints: []string{"1.2.3.4:443", "5.6.7.8:443"}},
			want: []string{"1.2.3.4:443", "5.6.7.8:443"},
		},
		{
			name: "blank entries are dropped",
			cfg:  Config{Server: " 1.2.3.4:443 ", Endpoints: []string{"", "   ", "5.6.7.8:443"}},
			want: []string{"1.2.3.4:443", "5.6.7.8:443"},
		},
		{
			name: "no usable address yields nothing rather than an empty string",
			cfg:  Config{Server: "  "},
			want: nil,
		},
		{
			// A config aimed elsewhere must never be redirected to our servers.
			name: "unknown server gets no compiled-in fallback",
			cfg:  Config{Server: "example.org:443"},
			want: []string{"example.org:443"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := endpointCandidates(&tt.cfg)
			if len(got) != len(tt.want) {
				t.Fatalf("got %d candidates %v, want %d %v", len(got), got, len(tt.want), tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Fatalf("candidate %d = %q, want %q\nfull: %v", i, got[i], tt.want[i], got)
				}
			}
		})
	}
}

// Every retired address must have somewhere to go, otherwise demoting it just
// moves the timeout to the end of the list instead of removing it.
func TestRetiredServersHaveSuccessors(t *testing.T) {
	for addr := range retiredServers {
		successors := migrationFallbacks[addr]
		if len(successors) == 0 {
			t.Errorf("retired %q has no entry in migrationFallbacks: clients holding it would have nothing to fall back to", addr)
			continue
		}
		for _, s := range successors {
			if _, gone := retiredServers[s]; gone {
				t.Errorf("retired %q falls back to %q, which is also retired", addr, s)
			}
			if !strings.Contains(s, ":") {
				t.Errorf("successor %q of %q is not host:port", s, addr)
			}
		}
	}
}
