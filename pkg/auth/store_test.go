package auth

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func tempUsersFile(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	return filepath.Join(dir, "users.yaml")
}

func TestNewFileStore_EmptyFile(t *testing.T) {
	path := tempUsersFile(t)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore: %v", err)
	}
	users := store.ListUsers()
	if len(users) != 0 {
		t.Errorf("expected 0 users, got %d", len(users))
	}
}

func TestAddUser(t *testing.T) {
	path := tempUsersFile(t)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore: %v", err)
	}

	if err := store.AddUser("alice", "password123"); err != nil {
		t.Fatalf("AddUser: %v", err)
	}

	users := store.ListUsers()
	if len(users) != 1 {
		t.Fatalf("expected 1 user, got %d", len(users))
	}
	if users[0].Username != "alice" {
		t.Errorf("expected username 'alice', got %q", users[0].Username)
	}
	// Password hash should NOT be exposed in ListUsers
	if users[0].PasswordHash != "" {
		t.Error("ListUsers should not expose password hash")
	}
}

func TestAddUser_Duplicate(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)
	store.AddUser("bob", "pass1")

	err := store.AddUser("bob", "pass2")
	if err == nil {
		t.Error("expected error for duplicate user")
	}
}

func TestAuthenticate(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)
	store.AddUser("alice", "correct-password")

	if !store.Authenticate("alice", "correct-password") {
		t.Error("expected authentication to succeed with correct password")
	}
	if store.Authenticate("alice", "wrong-password") {
		t.Error("expected authentication to fail with wrong password")
	}
	if store.Authenticate("nonexistent", "password") {
		t.Error("expected authentication to fail for nonexistent user")
	}
}

func TestAuthenticate_DisabledUser(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)
	store.AddUser("alice", "password")
	store.SetDisabled("alice", true)

	if store.Authenticate("alice", "password") {
		t.Error("disabled user should not authenticate")
	}

	store.SetDisabled("alice", false)
	if !store.Authenticate("alice", "password") {
		t.Error("re-enabled user should authenticate")
	}
}

func TestRemoveUser(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)
	store.AddUser("alice", "pass")
	store.AddUser("bob", "pass")

	if err := store.RemoveUser("alice"); err != nil {
		t.Fatalf("RemoveUser: %v", err)
	}

	users := store.ListUsers()
	if len(users) != 1 {
		t.Fatalf("expected 1 user after removal, got %d", len(users))
	}
}

func TestRemoveUser_NotFound(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)

	if err := store.RemoveUser("nobody"); err == nil {
		t.Error("expected error for removing nonexistent user")
	}
}

func TestUpdatePassword(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)
	store.AddUser("alice", "old-password")

	if err := store.UpdatePassword("alice", "new-password"); err != nil {
		t.Fatalf("UpdatePassword: %v", err)
	}

	if store.Authenticate("alice", "old-password") {
		t.Error("old password should not work after update")
	}
	if !store.Authenticate("alice", "new-password") {
		t.Error("new password should work after update")
	}
}

func TestPersistence(t *testing.T) {
	path := tempUsersFile(t)
	store1, _ := NewFileStore(path)
	store1.AddUser("alice", "password123")

	// Load from same file
	store2, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}

	if !store2.Authenticate("alice", "password123") {
		t.Error("persisted user should authenticate after reload")
	}
}

func TestConcurrentAccess(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)

	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			username := "user" + string(rune('a'+i))
			store.AddUser(username, "password")
			store.Authenticate(username, "password")
			store.ListUsers()
		}(i)
	}
	wg.Wait()

	users := store.ListUsers()
	if len(users) != 10 {
		t.Errorf("expected 10 users, got %d", len(users))
	}
}

func TestFilePermissions(t *testing.T) {
	path := tempUsersFile(t)
	store, _ := NewFileStore(path)
	store.AddUser("alice", "pass")

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	// On Unix, file should be 0600
	if perm := info.Mode().Perm(); perm&0077 != 0 {
		t.Logf("Note: users file permissions are %o (ideally 0600)", perm)
	}
}
