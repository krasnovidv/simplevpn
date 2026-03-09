package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"simplevpn/pkg/auth"
	"simplevpn/pkg/config"
)

var testCounter int

func testServer() *Server {
	// Create a unique temp users file for each test
	testCounter++
	tmpDir := os.TempDir()
	usersPath := filepath.Join(tmpDir, fmt.Sprintf("test-users-%d-%d.yaml", os.Getpid(), testCounter))
	os.Remove(usersPath) // ensure clean state
	cfg := &config.ServerConfig{
		Listen:    ":443",
		ServerKey: "test-server-key",
		UsersFile: usersPath,
		CertFile:  "cert.pem",
		KeyFile:   "key.pem",
		TunIP:     "10.0.0.1/24",
		TunName:   "tun0",
		MTU:       1380,
		LogLevel:  "info",
		API: config.APIConfig{
			Enabled:     true,
			Listen:      ":8443",
			BearerToken: "test-token",
		},
	}
	store, _ := auth.NewFileStore(usersPath)
	return NewServer(cfg, "0.1.0-test", store)
}

func TestStatusEndpoint(t *testing.T) {
	s := testServer()

	req := httptest.NewRequest("GET", "/api/status", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Status code: got %d, want %d", w.Code, http.StatusOK)
	}

	var resp map[string]interface{}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("Decode: %v", err)
	}

	if resp["status"] != "running" {
		t.Errorf("status: got %v, want running", resp["status"])
	}
	if resp["version"] != "0.1.0-test" {
		t.Errorf("version: got %v, want 0.1.0-test", resp["version"])
	}
}

func TestClientsEndpoint(t *testing.T) {
	s := testServer()

	// Register a test client
	s.RegisterClient(&ClientInfo{
		ID:         "test-client-1",
		RemoteAddr: "1.2.3.4:5678",
	})

	req := httptest.NewRequest("GET", "/api/clients", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Status code: got %d, want %d", w.Code, http.StatusOK)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)

	clients := resp["clients"].([]interface{})
	if len(clients) != 1 {
		t.Errorf("clients count: got %d, want 1", len(clients))
	}
}

func TestClientsEndpointEmpty(t *testing.T) {
	s := testServer()

	req := httptest.NewRequest("GET", "/api/clients", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)

	clients := resp["clients"].([]interface{})
	if len(clients) != 0 {
		t.Errorf("clients count: got %d, want 0", len(clients))
	}
}

func TestConfigEndpoint(t *testing.T) {
	s := testServer()

	req := httptest.NewRequest("GET", "/api/config", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Status code: got %d, want %d", w.Code, http.StatusOK)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)

	// Config should NOT contain server_key
	if _, ok := resp["server_key"]; ok {
		t.Error("Config response should not contain server_key")
	}

	if resp["listen"] != ":443" {
		t.Errorf("listen: got %v, want :443", resp["listen"])
	}
}

func TestAuthRequired(t *testing.T) {
	s := testServer()

	endpoints := []string{"/api/status", "/api/clients", "/api/config"}

	for _, ep := range endpoints {
		t.Run(ep, func(t *testing.T) {
			// No auth header
			req := httptest.NewRequest("GET", ep, nil)
			w := httptest.NewRecorder()
			s.mux.ServeHTTP(w, req)

			if w.Code != http.StatusUnauthorized {
				t.Errorf("No auth: got %d, want %d", w.Code, http.StatusUnauthorized)
			}

			// Wrong token
			req = httptest.NewRequest("GET", ep, nil)
			req.Header.Set("Authorization", "Bearer wrong-token")
			w = httptest.NewRecorder()
			s.mux.ServeHTTP(w, req)

			if w.Code != http.StatusUnauthorized {
				t.Errorf("Wrong token: got %d, want %d", w.Code, http.StatusUnauthorized)
			}
		})
	}
}

func TestMethodNotAllowed(t *testing.T) {
	s := testServer()

	// POST to GET-only endpoint
	req := httptest.NewRequest("POST", "/api/status", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()
	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Errorf("Wrong method: got %d, want %d", w.Code, http.StatusMethodNotAllowed)
	}
}

func TestRegisterUnregisterClient(t *testing.T) {
	s := testServer()

	s.RegisterClient(&ClientInfo{ID: "c1", RemoteAddr: "1.1.1.1:1234"})
	s.RegisterClient(&ClientInfo{ID: "c2", RemoteAddr: "2.2.2.2:5678"})

	s.mu.RLock()
	if len(s.clients) != 2 {
		t.Errorf("clients: got %d, want 2", len(s.clients))
	}
	s.mu.RUnlock()

	s.UnregisterClient("c1")

	s.mu.RLock()
	if len(s.clients) != 1 {
		t.Errorf("clients after unregister: got %d, want 1", len(s.clients))
	}
	s.mu.RUnlock()
}

// --- User CRUD tests ---

func TestCreateUser(t *testing.T) {
	s := testServer()

	body := `{"username":"alice","password":"secret12345"}`
	req := httptest.NewRequest("POST", "/api/users", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("Create user: got %d, want %d", w.Code, http.StatusCreated)
	}

	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["username"] != "alice" {
		t.Errorf("username: got %q, want alice", resp["username"])
	}
}

func TestCreateUser_Duplicate(t *testing.T) {
	s := testServer()
	s.store.AddUser("alice", "password123")

	body := `{"username":"alice","password":"password456"}`
	req := httptest.NewRequest("POST", "/api/users", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusConflict {
		t.Errorf("Duplicate user: got %d, want %d", w.Code, http.StatusConflict)
	}
}

func TestCreateUser_ShortPassword(t *testing.T) {
	s := testServer()

	body := `{"username":"alice","password":"short"}`
	req := httptest.NewRequest("POST", "/api/users", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("Short password: got %d, want %d", w.Code, http.StatusBadRequest)
	}
}

func TestListUsers(t *testing.T) {
	s := testServer()
	s.store.AddUser("alice", "password1")
	s.store.AddUser("bob", "password2")

	req := httptest.NewRequest("GET", "/api/users", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("List users: got %d, want %d", w.Code, http.StatusOK)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)

	users := resp["users"].([]interface{})
	if len(users) != 2 {
		t.Errorf("users count: got %d, want 2", len(users))
	}
}

func TestDeleteUser(t *testing.T) {
	s := testServer()
	s.store.AddUser("alice", "password123")

	req := httptest.NewRequest("DELETE", "/api/users/alice", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Delete user: got %d, want %d", w.Code, http.StatusOK)
	}

	// Verify user is gone
	users := s.store.ListUsers()
	if len(users) != 0 {
		t.Errorf("users after delete: got %d, want 0", len(users))
	}
}

func TestDeleteUser_NotFound(t *testing.T) {
	s := testServer()

	req := httptest.NewRequest("DELETE", "/api/users/nobody", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Delete nonexistent: got %d, want %d", w.Code, http.StatusNotFound)
	}
}

func TestUpdatePassword(t *testing.T) {
	s := testServer()
	s.store.AddUser("alice", "old-password")

	body := `{"password":"new-password"}`
	req := httptest.NewRequest("PUT", "/api/users/alice/password", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()

	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Update password: got %d, want %d", w.Code, http.StatusOK)
	}

	if s.store.Authenticate("alice", "old-password") {
		t.Error("old password should not work")
	}
	if !s.store.Authenticate("alice", "new-password") {
		t.Error("new password should work")
	}
}

func TestDisableEnableUser(t *testing.T) {
	s := testServer()
	s.store.AddUser("alice", "password123")

	// Disable
	req := httptest.NewRequest("POST", "/api/users/alice/disable", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()
	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Disable: got %d, want %d", w.Code, http.StatusOK)
	}
	if s.store.Authenticate("alice", "password123") {
		t.Error("disabled user should not authenticate")
	}

	// Enable
	req = httptest.NewRequest("POST", "/api/users/alice/enable", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	w = httptest.NewRecorder()
	s.mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Enable: got %d, want %d", w.Code, http.StatusOK)
	}
	if !s.store.Authenticate("alice", "password123") {
		t.Error("re-enabled user should authenticate")
	}
}

func TestUserEndpoints_AuthRequired(t *testing.T) {
	s := testServer()

	endpoints := []struct {
		method string
		path   string
	}{
		{"GET", "/api/users"},
		{"POST", "/api/users"},
		{"DELETE", "/api/users/alice"},
		{"PUT", "/api/users/alice/password"},
	}

	for _, ep := range endpoints {
		t.Run(ep.method+" "+ep.path, func(t *testing.T) {
			req := httptest.NewRequest(ep.method, ep.path, nil)
			w := httptest.NewRecorder()
			s.mux.ServeHTTP(w, req)

			if w.Code != http.StatusUnauthorized {
				t.Errorf("got %d, want %d", w.Code, http.StatusUnauthorized)
			}
		})
	}
}
