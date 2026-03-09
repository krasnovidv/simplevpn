package auth

import "time"

// User represents a VPN user account.
type User struct {
	Username     string    `yaml:"username"`
	PasswordHash string    `yaml:"password_hash"`
	CreatedAt    time.Time `yaml:"created_at"`
	Disabled     bool      `yaml:"disabled,omitempty"`
}
