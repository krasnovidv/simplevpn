package main

import (
	"net/netip"
	"testing"
)

func TestDstFromIPv4(t *testing.T) {
	tests := []struct {
		name    string
		packet  []byte
		want    netip.Addr
		wantErr bool
	}{
		{
			name: "valid IPv4 packet dst=10.0.0.2",
			// Minimal valid IPv4 header: version/IHL=0x45, then zeros, then src/dst
			packet: func() []byte {
				b := make([]byte, 20)
				b[0] = 0x45 // version=4, IHL=5
				// bytes 12-15: src = 10.0.0.1
				b[12] = 10
				// bytes 16-19: dst = 10.0.0.2
				b[16] = 10
				b[19] = 2
				return b
			}(),
			want:    netip.MustParseAddr("10.0.0.2"),
			wantErr: false,
		},
		{
			name:    "too short packet",
			packet:  make([]byte, 19),
			wantErr: true,
		},
		{
			name: "non-IPv4 version nibble",
			packet: func() []byte {
				b := make([]byte, 20)
				b[0] = 0x60 // version=6 (IPv6)
				return b
			}(),
			wantErr: true,
		},
		{
			name:    "empty packet",
			packet:  []byte{},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := dstFromIPv4(tt.packet)
			if (err != nil) != tt.wantErr {
				t.Fatalf("dstFromIPv4() error = %v, wantErr = %v", err, tt.wantErr)
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("got %s, want %s", got, tt.want)
			}
		})
	}
}
