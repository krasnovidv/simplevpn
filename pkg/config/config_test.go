package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaults(t *testing.T) {
	cfg := Defaults()

	if cfg.Listen != ":443" {
		t.Errorf("Listen: got %q, want %q", cfg.Listen, ":443")
	}
	if cfg.MTU != 1380 {
		t.Errorf("MTU: got %d, want %d", cfg.MTU, 1380)
	}
	if cfg.TunName != "tun0" {
		t.Errorf("TunName: got %q, want %q", cfg.TunName, "tun0")
	}
	if cfg.TunIP != "10.0.0.1/24" {
		t.Errorf("TunIP: got %q, want %q", cfg.TunIP, "10.0.0.1/24")
	}
	if cfg.API.Listen != ":8443" {
		t.Errorf("API.Listen: got %q, want %q", cfg.API.Listen, ":8443")
	}
	if cfg.UsersFile != "/etc/simplevpn/users.yaml" {
		t.Errorf("UsersFile: got %q, want %q", cfg.UsersFile, "/etc/simplevpn/users.yaml")
	}
}

func TestLoadYAML(t *testing.T) {
	yaml := `
listen: ":8080"
server_key: "my-secret-key"
users_file: "/data/users.yaml"
cert: "/path/to/cert.pem"
key: "/path/to/key.pem"
tun_ip: "10.1.0.1/24"
tun_name: "tun1"
mtu: 1400
log_level: "debug"
api:
  enabled: true
  listen: ":9443"
  bearer_token: "admin-token"
`
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte(yaml), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if cfg.Listen != ":8080" {
		t.Errorf("Listen: got %q, want %q", cfg.Listen, ":8080")
	}
	if cfg.ServerKey != "my-secret-key" {
		t.Errorf("ServerKey: got %q, want %q", cfg.ServerKey, "my-secret-key")
	}
	if cfg.UsersFile != "/data/users.yaml" {
		t.Errorf("UsersFile: got %q, want %q", cfg.UsersFile, "/data/users.yaml")
	}
	if cfg.MTU != 1400 {
		t.Errorf("MTU: got %d, want %d", cfg.MTU, 1400)
	}
	if cfg.TunName != "tun1" {
		t.Errorf("TunName: got %q, want %q", cfg.TunName, "tun1")
	}
	if cfg.LogLevel != "debug" {
		t.Errorf("LogLevel: got %q, want %q", cfg.LogLevel, "debug")
	}
	if !cfg.API.Enabled {
		t.Error("API.Enabled: got false, want true")
	}
	if cfg.API.BearerToken != "admin-token" {
		t.Errorf("API.BearerToken: got %q, want %q", cfg.API.BearerToken, "admin-token")
	}
}

func TestLoadPartialYAML(t *testing.T) {
	// Only set some fields — defaults should fill the rest
	yaml := `
server_key: "test-key"
cert: "cert.pem"
key: "key.pem"
`
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	os.WriteFile(path, []byte(yaml), 0644)

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	// Defaults should be preserved
	if cfg.Listen != ":443" {
		t.Errorf("Listen should default to :443, got %q", cfg.Listen)
	}
	if cfg.MTU != 1380 {
		t.Errorf("MTU should default to 1380, got %d", cfg.MTU)
	}
	if cfg.ServerKey != "test-key" {
		t.Errorf("ServerKey: got %q, want %q", cfg.ServerKey, "test-key")
	}
}

func TestValidate(t *testing.T) {
	tests := []struct {
		name    string
		modify  func(*ServerConfig)
		wantErr bool
	}{
		{
			name: "valid config",
			modify: func(c *ServerConfig) {
				c.ServerKey = "test-key"
			},
			wantErr: false,
		},
		{
			name:    "missing server_key",
			modify:  func(c *ServerConfig) {},
			wantErr: true,
		},
		{
			name: "missing users_file",
			modify: func(c *ServerConfig) {
				c.ServerKey = "test-key"
				c.UsersFile = ""
			},
			wantErr: true,
		},
		{
			name: "MTU too low",
			modify: func(c *ServerConfig) {
				c.ServerKey = "test-key"
				c.MTU = 100
			},
			wantErr: true,
		},
		{
			name: "MTU too high",
			modify: func(c *ServerConfig) {
				c.ServerKey = "test-key"
				c.MTU = 10000
			},
			wantErr: true,
		},
		{
			name: "API enabled without token",
			modify: func(c *ServerConfig) {
				c.ServerKey = "test-key"
				c.API.Enabled = true
			},
			wantErr: true,
		},
		{
			name: "API enabled with token",
			modify: func(c *ServerConfig) {
				c.ServerKey = "test-key"
				c.API.Enabled = true
				c.API.BearerToken = "secret"
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := Defaults()
			tt.modify(cfg)
			err := cfg.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestLoadFileNotFound(t *testing.T) {
	_, err := Load("/nonexistent/config.yaml")
	if err == nil {
		t.Error("Expected error for missing file")
	}
}

func TestLoadInvalidYAML(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.yaml")
	os.WriteFile(path, []byte("{{{{not yaml"), 0644)

	_, err := Load(path)
	if err == nil {
		t.Error("Expected error for invalid YAML")
	}
}
