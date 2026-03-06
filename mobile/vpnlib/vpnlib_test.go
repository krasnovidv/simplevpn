package vpnlib

import (
	"encoding/json"
	"testing"
)

func TestConfigParsing(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
		check   func(Config) bool
	}{
		{
			name:  "full config",
			input: `{"server":"1.2.3.4:443","psk":"secret","sni":"example.com","skip_verify":true}`,
			check: func(c Config) bool {
				return c.Server == "1.2.3.4:443" && c.PSK == "secret" && c.SNI == "example.com" && c.SkipVerify
			},
		},
		{
			name:  "minimal config",
			input: `{"server":"host:443","psk":"key"}`,
			check: func(c Config) bool {
				return c.Server == "host:443" && c.PSK == "key" && c.SNI == "" && !c.SkipVerify
			},
		},
		{
			name:    "invalid json",
			input:   `{invalid`,
			wantErr: true,
		},
		{
			name:  "skip_verify false by default",
			input: `{"server":"h:1","psk":"p"}`,
			check: func(c Config) bool {
				return !c.SkipVerify
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var cfg Config
			err := json.Unmarshal([]byte(tt.input), &cfg)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.check != nil && !tt.check(cfg) {
				t.Fatalf("check failed for config: %+v", cfg)
			}
		})
	}
}

func TestStatusTransitions(t *testing.T) {
	// Reset state
	current = &state{status: "disconnected"}

	if s := Status(); s != "disconnected" {
		t.Fatalf("initial status = %q, want disconnected", s)
	}

	setStatus("connecting")
	if s := Status(); s != "connecting" {
		t.Fatalf("after setStatus(connecting) = %q", s)
	}

	setStatus("connected")
	if s := Status(); s != "connected" {
		t.Fatalf("after setStatus(connected) = %q", s)
	}

	// Disconnect when not actually connected shouldn't panic
	Disconnect()
	if s := Status(); s != "connected" {
		// Disconnect checks current.connected which is false, so status stays
		t.Logf("status after no-op Disconnect: %s", s)
	}
}

func TestConnectValidation(t *testing.T) {
	// Reset state
	current = &state{status: "disconnected"}

	// Empty server should fail
	err := Connect(`{"server":"","psk":"key"}`, 0)
	if err == nil {
		t.Fatal("expected error for empty server")
	}

	// Empty PSK should fail
	err = Connect(`{"server":"host:443","psk":""}`, 0)
	if err == nil {
		t.Fatal("expected error for empty psk")
	}

	// Invalid JSON should fail
	err = Connect(`{bad`, 0)
	if err == nil {
		t.Fatal("expected error for invalid json")
	}
}
