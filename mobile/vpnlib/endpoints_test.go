package vpnlib

import (
	"strings"
	"testing"
)

// Both earlier deployments are gone and their addresses belong to other people
// now; configs still naming them must go straight to the current server and
// never dial the old address (see abandonedServers).
const (
	firstAddr  = "193.23.3.93:443"
	secondAddr = "89.40.233.67:443"
	newAddr    = "185.192.246.127:443"
	newAddrAlt = "185.192.246.127:2053"
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
			name: "first-generation primary goes straight to the current server",
			cfg:  Config{Server: firstAddr},
			want: []string{newAddr, newAddrAlt},
		},
		{
			name: "second-generation primary goes straight to the current server",
			cfg:  Config{Server: secondAddr},
			want: []string{newAddr, newAddrAlt},
		},
		{
			name: "announced endpoints come before compiled fallbacks",
			cfg:  Config{Server: secondAddr, Endpoints: []string{newAddrAlt}},
			want: []string{newAddrAlt, newAddr},
		},
		{
			name: "abandoned addresses are dropped however they entered the list",
			cfg:  Config{Server: newAddr, Endpoints: []string{firstAddr, "89.40.233.67:2053", newAddrAlt}},
			want: []string{newAddr, newAddrAlt},
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

// Every abandoned address that can be a config's primary must lead somewhere,
// or such a config would have no candidate at all.
func TestAbandonedServersHaveSuccessors(t *testing.T) {
	for _, addr := range []string{firstAddr, secondAddr} {
		if len(endpointCandidates(&Config{Server: addr})) == 0 {
			t.Errorf("config with primary %q has nothing to dial", addr)
		}
	}
	for addr, successors := range migrationFallbacks {
		for _, s := range successors {
			if _, gone := abandonedServers[s]; gone {
				continue // skipped at dial time; the rest of the list carries it
			}
			if !strings.Contains(s, ":") {
				t.Errorf("successor %q of %q is not host:port", s, addr)
			}
		}
	}
}
