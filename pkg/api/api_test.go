package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"simplevpn/pkg/config"
)

func testServer() *Server {
	cfg := &config.ServerConfig{
		Listen:   ":443",
		PSK:      "test-psk",
		CertFile: "cert.pem",
		KeyFile:  "key.pem",
		TunIP:    "10.0.0.1/24",
		TunName:  "tun0",
		MTU:      1380,
		LogLevel: "info",
		API: config.APIConfig{
			Enabled:     true,
			Listen:      ":8443",
			BearerToken: "test-token",
		},
	}
	return NewServer(cfg, "0.1.0-test")
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

	// Config should NOT contain PSK
	if _, ok := resp["psk"]; ok {
		t.Error("Config response should not contain PSK")
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
