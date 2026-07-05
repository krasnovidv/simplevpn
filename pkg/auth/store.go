package auth

import (
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gopkg.in/yaml.v3"

	"simplevpn/pkg/logx"
)

const bcryptCost = 12

// dummyHash is a valid bcrypt hash at bcryptCost, compared against when a user
// is unknown or disabled so that every authentication attempt pays the same
// bcrypt cost. This closes the username-enumeration timing oracle where a
// missing user would otherwise return in microseconds versus tens of ms for a
// real bcrypt comparison. Generated at init so it is guaranteed well-formed.
var dummyHash []byte

func init() {
	h, err := bcrypt.GenerateFromPassword([]byte("simplevpn-timing-equalizer"), bcryptCost)
	if err != nil {
		panic("auth: failed to generate dummy bcrypt hash: " + err.Error())
	}
	dummyHash = h
}

// FileStore manages user accounts persisted in a YAML file.
type FileStore struct {
	mu       sync.RWMutex
	path     string
	users    map[string]*User
	logLevel string
}

// usersFile is the YAML structure for the users file.
type usersFile struct {
	Users []*User `yaml:"users"`
}

// NewFileStore creates a new FileStore. If the file does not exist, it starts empty.
func NewFileStore(path string) (*FileStore, error) {
	s := &FileStore{
		path:  path,
		users: make(map[string]*User),
	}

	if _, err := os.Stat(path); os.IsNotExist(err) {
		log.Printf("[auth] users file %s does not exist, starting with empty store", path)
		return s, nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("[auth] failed to read users file: %w", err)
	}

	var f usersFile
	if err := yaml.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("[auth] failed to parse users file: %w", err)
	}

	for _, u := range f.Users {
		s.users[u.Username] = u
	}

	log.Printf("[auth] loaded %d users from %s", len(s.users), path)
	return s, nil
}

// Authenticate checks username/password. Returns true if valid and not disabled.
func (s *FileStore) Authenticate(username, password string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()

	u, ok := s.users[username]

	// Always run a bcrypt comparison — against the real hash if the user exists
	// and is enabled, otherwise against a dummy hash — so unknown/disabled users
	// cost the same wall-clock time as a wrong password for a real user. This
	// prevents an attacker from enumerating valid usernames by timing.
	hash := dummyHash
	valid := ok && !u.Disabled
	if valid {
		hash = []byte(u.PasswordHash)
	}

	err := bcrypt.CompareHashAndPassword(hash, []byte(password))
	if !valid {
		if !ok {
			logx.Debugf("[auth] authentication failed: user %q not found", username)
		} else {
			logx.Debugf("[auth] authentication failed: user %q is disabled", username)
		}
		return false
	}
	if err != nil {
		logx.Debugf("[auth] authentication failed: invalid password for user %q", username)
		return false
	}

	logx.Debugf("[auth] user %q authenticated successfully", username)
	return true
}

// AddUser creates a new user with the given password. Returns error if user already exists.
func (s *FileStore) AddUser(username, password string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.users[username]; ok {
		return fmt.Errorf("[auth] user %q already exists", username)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return fmt.Errorf("[auth] failed to hash password: %w", err)
	}

	s.users[username] = &User{
		Username:     username,
		PasswordHash: string(hash),
		CreatedAt:    time.Now(),
	}

	log.Printf("[auth] user %q created", username)
	return s.save()
}

// RemoveUser deletes a user. Returns error if user does not exist.
func (s *FileStore) RemoveUser(username string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.users[username]; !ok {
		return fmt.Errorf("[auth] user %q not found", username)
	}

	delete(s.users, username)
	log.Printf("[auth] user %q removed", username)
	return s.save()
}

// ListUsers returns all users (without password hashes).
func (s *FileStore) ListUsers() []User {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]User, 0, len(s.users))
	for _, u := range s.users {
		result = append(result, User{
			Username:  u.Username,
			CreatedAt: u.CreatedAt,
			Disabled:  u.Disabled,
		})
	}
	return result
}

// UpdatePassword changes a user's password. Returns error if user does not exist.
func (s *FileStore) UpdatePassword(username, newPassword string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	u, ok := s.users[username]
	if !ok {
		return fmt.Errorf("[auth] user %q not found", username)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcryptCost)
	if err != nil {
		return fmt.Errorf("[auth] failed to hash password: %w", err)
	}

	u.PasswordHash = string(hash)
	log.Printf("[auth] password updated for user %q", username)
	return s.save()
}

// SetDisabled enables or disables a user account.
func (s *FileStore) SetDisabled(username string, disabled bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	u, ok := s.users[username]
	if !ok {
		return fmt.Errorf("[auth] user %q not found", username)
	}

	u.Disabled = disabled
	state := "enabled"
	if disabled {
		state = "disabled"
	}
	log.Printf("[auth] user %q %s", username, state)
	return s.save()
}

// save writes the current users to the YAML file. Must be called with mu held.
func (s *FileStore) save() error {
	f := usersFile{
		Users: make([]*User, 0, len(s.users)),
	}
	for _, u := range s.users {
		f.Users = append(f.Users, u)
	}

	data, err := yaml.Marshal(&f)
	if err != nil {
		return fmt.Errorf("[auth] failed to marshal users: %w", err)
	}

	if err := os.WriteFile(s.path, data, 0600); err != nil {
		return fmt.Errorf("[auth] failed to write users file: %w", err)
	}

	log.Printf("[auth] saved %d users to %s", len(s.users), s.path)
	return nil
}
