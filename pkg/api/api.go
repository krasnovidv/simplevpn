// Package api provides a management REST API for the VPN server.
//
// The API runs on a separate port (default :8443) with TLS and bearer token auth.
// It provides endpoints for monitoring server status, managing connected clients,
// and viewing/reloading configuration.
package api

import (
	"crypto/subtle"
	"crypto/tls"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"simplevpn/pkg/config"
)

// ClientInfo holds information about a connected VPN client.
type ClientInfo struct {
	ID          string    `json:"id"`
	RemoteAddr  string    `json:"remote_addr"`
	ConnectedAt time.Time `json:"connected_at"`
	BytesIn     int64     `json:"bytes_in"`
	BytesOut    int64     `json:"bytes_out"`
}

// Server is the management API server.
type Server struct {
	cfg       *config.ServerConfig
	startTime time.Time
	version   string

	mu      sync.RWMutex
	clients map[string]*ClientInfo

	disconnectFn func(clientID string) error

	mux        *http.ServeMux
	httpServer *http.Server
}

// NewServer creates a new management API server.
func NewServer(cfg *config.ServerConfig, version string) *Server {
	s := &Server{
		cfg:       cfg,
		startTime: time.Now(),
		version:   version,
		clients:   make(map[string]*ClientInfo),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/status", s.authMiddleware(s.handleStatus))
	mux.HandleFunc("/api/clients", s.authMiddleware(s.handleClients))
	mux.HandleFunc("/api/clients/", s.authMiddleware(s.handleClientAction))
	mux.HandleFunc("/api/config", s.authMiddleware(s.handleConfig))

	s.mux = mux
	s.httpServer = &http.Server{
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	log.Printf("[api] Management API server created, version=%s", version)
	return s
}

// SetDisconnectFunc sets the callback for disconnecting clients.
func (s *Server) SetDisconnectFunc(fn func(clientID string) error) {
	s.disconnectFn = fn
}

// RegisterClient adds a client to the connected clients list.
func (s *Server) RegisterClient(info *ClientInfo) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clients[info.ID] = info
	log.Printf("[api] Client registered: id=%s addr=%s", info.ID, info.RemoteAddr)
}

// UnregisterClient removes a client from the connected clients list.
func (s *Server) UnregisterClient(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.clients, id)
	log.Printf("[api] Client unregistered: id=%s", id)
}

// UpdateClientStats updates byte counters for a client.
func (s *Server) UpdateClientStats(id string, bytesIn, bytesOut int64) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if c, ok := s.clients[id]; ok {
		c.BytesIn = bytesIn
		c.BytesOut = bytesOut
	}
}

// ListenAndServeTLS starts the API server with TLS.
func (s *Server) ListenAndServeTLS() error {
	certFile := s.cfg.API.CertFile
	keyFile := s.cfg.API.KeyFile
	if certFile == "" {
		certFile = s.cfg.CertFile
	}
	if keyFile == "" {
		keyFile = s.cfg.KeyFile
	}

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return err
	}

	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS12,
	}

	ln, err := net.Listen("tcp", s.cfg.API.Listen)
	if err != nil {
		return err
	}

	tlsLn := tls.NewListener(ln, tlsCfg)
	log.Printf("[api] Management API listening on %s (TLS)", s.cfg.API.Listen)
	return s.httpServer.Serve(tlsLn)
}

// Shutdown gracefully shuts down the API server.
func (s *Server) Shutdown() error {
	log.Printf("[api] Shutting down management API")
	return s.httpServer.Close()
}

// authMiddleware checks the bearer token.
func (s *Server) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("Authorization")
		expected := "Bearer " + s.cfg.API.BearerToken

		if subtle.ConstantTimeCompare([]byte(token), []byte(expected)) != 1 {
			log.Printf("[api] Auth failed from %s: invalid bearer token", r.RemoteAddr)
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	s.mu.RLock()
	clientCount := len(s.clients)
	s.mu.RUnlock()

	resp := map[string]interface{}{
		"status":       "running",
		"version":      s.version,
		"uptime_secs":  int(time.Since(s.startTime).Seconds()),
		"client_count": clientCount,
		"listen":       s.cfg.Listen,
	}

	log.Printf("[api] GET /api/status from %s", r.RemoteAddr)
	writeJSON(w, resp)
}

func (s *Server) handleClients(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	s.mu.RLock()
	clients := make([]*ClientInfo, 0, len(s.clients))
	for _, c := range s.clients {
		clients = append(clients, c)
	}
	s.mu.RUnlock()

	log.Printf("[api] GET /api/clients from %s, count=%d", r.RemoteAddr, len(clients))
	writeJSON(w, map[string]interface{}{"clients": clients})
}

func (s *Server) handleClientAction(w http.ResponseWriter, r *http.Request) {
	// Extract client ID from path: /api/clients/{id}/disconnect
	path := r.URL.Path
	// Minimal path parsing
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// Expected path: /api/clients/{id}/disconnect
	const prefix = "/api/clients/"
	const suffix = "/disconnect"
	if len(path) <= len(prefix)+len(suffix) {
		http.Error(w, `{"error":"invalid path"}`, http.StatusBadRequest)
		return
	}

	clientID := path[len(prefix) : len(path)-len(suffix)]
	if clientID == "" {
		http.Error(w, `{"error":"missing client id"}`, http.StatusBadRequest)
		return
	}

	log.Printf("[api] POST /api/clients/%s/disconnect from %s", clientID, r.RemoteAddr)

	if s.disconnectFn == nil {
		http.Error(w, `{"error":"disconnect not supported"}`, http.StatusNotImplemented)
		return
	}

	if err := s.disconnectFn(clientID); err != nil {
		log.Printf("[api] Disconnect client %s failed: %v", clientID, err)
		http.Error(w, `{"error":"disconnect failed"}`, http.StatusInternalServerError)
		return
	}

	writeJSON(w, map[string]string{"status": "disconnected", "client_id": clientID})
}

func (s *Server) handleConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// Return sanitized config (no PSK, no bearer token)
	resp := map[string]interface{}{
		"listen":   s.cfg.Listen,
		"tun_ip":   s.cfg.TunIP,
		"tun_name": s.cfg.TunName,
		"mtu":      s.cfg.MTU,
		"log_level": s.cfg.LogLevel,
		"api": map[string]interface{}{
			"enabled": s.cfg.API.Enabled,
			"listen":  s.cfg.API.Listen,
		},
	}

	log.Printf("[api] GET /api/config from %s", r.RemoteAddr)
	writeJSON(w, resp)
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("[api] JSON encode error: %v", err)
	}
}
