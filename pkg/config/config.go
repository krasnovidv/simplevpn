// Package config provides YAML configuration for the VPN server.
//
// Configuration is loaded from a YAML file. CLI flags override config file values.
// If no config file is specified, only CLI flags are used (backward compatible).
package config

import (
	"fmt"
	"log"
	"os"

	"gopkg.in/yaml.v3"
)

// ServerConfig holds all server configuration.
type ServerConfig struct {
	// VPN listener
	Listen  string `yaml:"listen"`
	PSK     string `yaml:"psk"`
	CertFile string `yaml:"cert"`
	KeyFile  string `yaml:"key"`

	// TUN interface
	TunIP   string `yaml:"tun_ip"`
	TunName string `yaml:"tun_name"`
	MTU     int    `yaml:"mtu"`

	// Management API
	API APIConfig `yaml:"api"`

	// Logging
	LogLevel string `yaml:"log_level"`
}

// APIConfig holds management API configuration.
type APIConfig struct {
	Enabled    bool   `yaml:"enabled"`
	Listen     string `yaml:"listen"`
	BearerToken string `yaml:"bearer_token"`
	CertFile   string `yaml:"cert"`
	KeyFile    string `yaml:"key"`
}

// Defaults returns a ServerConfig with default values.
func Defaults() *ServerConfig {
	return &ServerConfig{
		Listen:  ":443",
		CertFile: "cert.pem",
		KeyFile:  "key.pem",
		TunIP:   "10.0.0.1/24",
		TunName: "tun0",
		MTU:     1380,
		LogLevel: "info",
		API: APIConfig{
			Listen: ":8443",
		},
	}
}

// Load reads a YAML config file and returns a ServerConfig.
// Unset fields retain their default values.
func Load(path string) (*ServerConfig, error) {
	cfg := Defaults()

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}

	log.Printf("[config] Loading config from %s (%d bytes)", path, len(data))

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}

	log.Printf("[config] Config loaded: listen=%s tun=%s/%s mtu=%d api_enabled=%v",
		cfg.Listen, cfg.TunName, cfg.TunIP, cfg.MTU, cfg.API.Enabled)

	return cfg, nil
}

// Validate checks that required fields are set and values are reasonable.
func (c *ServerConfig) Validate() error {
	if c.PSK == "" {
		return fmt.Errorf("psk is required")
	}
	if c.Listen == "" {
		return fmt.Errorf("listen address is required")
	}
	if c.CertFile == "" {
		return fmt.Errorf("cert file is required")
	}
	if c.KeyFile == "" {
		return fmt.Errorf("key file is required")
	}
	if c.TunIP == "" {
		return fmt.Errorf("tun_ip is required")
	}
	if c.MTU < 500 || c.MTU > 9000 {
		return fmt.Errorf("mtu must be between 500 and 9000, got %d", c.MTU)
	}
	if c.API.Enabled && c.API.BearerToken == "" {
		return fmt.Errorf("api.bearer_token is required when api is enabled")
	}
	return nil
}
