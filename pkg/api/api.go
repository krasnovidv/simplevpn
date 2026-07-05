// Package api provides a management REST API for the VPN server.
//
// The API runs on a separate port (default :8443) with TLS and bearer token auth.
// It provides endpoints for monitoring server status, managing connected clients,
// and viewing/reloading configuration.
package api

import (
	"context"
	"crypto/subtle"
	"crypto/tls"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"simplevpn/pkg/auth"
	"simplevpn/pkg/config"
)

// rateLimiter tracks request counts per IP with a sliding window.
type rateLimiter struct {
	mu       sync.Mutex
	requests map[string][]time.Time
	limit    int
	window   time.Duration
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}
}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-rl.window)

	// Remove expired entries
	entries := rl.requests[ip]
	valid := entries[:0]
	for _, t := range entries {
		if t.After(cutoff) {
			valid = append(valid, t)
		}
	}

	if len(valid) == 0 {
		delete(rl.requests, ip)
	}

	if len(valid) >= rl.limit {
		rl.requests[ip] = valid
		return false
	}

	rl.requests[ip] = append(valid, now)
	return true
}

// ClientInfo holds information about a connected VPN client.
type ClientInfo struct {
	ID          string    `json:"id"`
	RemoteAddr  string    `json:"remote_addr"`
	ConnectedAt time.Time `json:"connected_at"`
	BytesIn     int64     `json:"bytes_in"`
	BytesOut    int64     `json:"bytes_out"`
	AssignedIP  string    `json:"assigned_ip"`
	Username    string    `json:"username"`
}

// Server is the management API server.
type Server struct {
	cfg       *config.ServerConfig
	startTime time.Time
	version   string

	mu      sync.RWMutex
	clients map[string]*ClientInfo

	store        *auth.FileStore
	disconnectFn func(clientID string) error
	limiter      *rateLimiter
	pubLimiter   *rateLimiter

	mux        *http.ServeMux
	httpServer *http.Server
	pubServer  *http.Server
}

// securityHeaders wraps a handler with a baseline set of hardening headers.
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

// NewServer creates a new management API server.
func NewServer(cfg *config.ServerConfig, version string, store *auth.FileStore) *Server {
	s := &Server{
		cfg:       cfg,
		startTime: time.Now(),
		version:   version,
		clients:   make(map[string]*ClientInfo),
		store:      store,
		limiter:    newRateLimiter(30, time.Minute),
		pubLimiter: newRateLimiter(120, time.Minute),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/api/status", s.authMiddleware(s.handleStatus))
	mux.HandleFunc("/api/clients", s.authMiddleware(s.handleClients))
	mux.HandleFunc("/api/clients/", s.authMiddleware(s.handleClientAction))
	mux.HandleFunc("/api/config", s.authMiddleware(s.handleConfig))
	s.registerUserRoutes(mux)
	mux.HandleFunc("/join", s.pubLimit(s.handleJoin))
	mux.HandleFunc("/download/", s.pubLimit(s.handleDownload))
	mux.HandleFunc("/api/update", s.pubLimit(s.handleUpdate))

	s.mux = mux
	s.httpServer = &http.Server{
		Handler:           securityHeaders(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       120 * time.Second,
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
	s.mu.Lock()
	defer s.mu.Unlock()
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

// ListenAndServeHTTP starts a plain HTTP server for public pages (/join, /download).
func (s *Server) ListenAndServeHTTP() error {
	addr := s.cfg.API.HTTPListen
	if addr == "" {
		addr = ":8080"
	}

	pubMux := http.NewServeMux()
	pubMux.HandleFunc("/healthz", s.handleHealthz)
	pubMux.HandleFunc("/join", s.pubLimit(s.handleJoin))
	pubMux.HandleFunc("/download/", s.pubLimit(s.handleDownload))
	pubMux.HandleFunc("/api/update", s.pubLimit(s.handleUpdate))

	srv := &http.Server{
		Addr:              addr,
		Handler:           securityHeaders(pubMux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		// WriteTimeout is intentionally generous: /download streams a multi-MB
		// APK and a short deadline would truncate it on slow mobile links.
		// Slowloris on the write side is bounded by IdleTimeout instead.
		WriteTimeout: 5 * time.Minute,
		IdleTimeout:  120 * time.Second,
	}
	s.pubServer = srv

	log.Printf("[api] Public HTTP server listening on %s", addr)
	return srv.ListenAndServe()
}

// pubLimit rate-limits an unauthenticated public handler by client IP.
func (s *Server) pubLimit(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ip, _, _ := net.SplitHostPort(r.RemoteAddr)
		if ip == "" {
			ip = r.RemoteAddr
		}
		if !s.pubLimiter.allow(ip) {
			http.Error(w, `{"error":"too many requests"}`, http.StatusTooManyRequests)
			return
		}
		next(w, r)
	}
}

// handleHealthz is an unauthenticated liveness probe for load balancers and
// container healthchecks.
func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// Shutdown gracefully shuts down the API server, draining in-flight requests.
func (s *Server) Shutdown(ctx context.Context) error {
	log.Printf("[api] Shutting down management API")
	err := s.httpServer.Shutdown(ctx)
	if s.pubServer != nil {
		if perr := s.pubServer.Shutdown(ctx); perr != nil && err == nil {
			err = perr
		}
	}
	return err
}

// authMiddleware checks the bearer token and applies rate limiting.
func (s *Server) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Rate limit by IP
		ip, _, _ := net.SplitHostPort(r.RemoteAddr)
		if ip == "" {
			ip = r.RemoteAddr
		}
		if !s.limiter.allow(ip) {
			log.Printf("[api] Rate limit exceeded from %s", r.RemoteAddr)
			http.Error(w, `{"error":"too many requests"}`, http.StatusTooManyRequests)
			return
		}

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
	if !strings.HasPrefix(path, prefix) || !strings.HasSuffix(path, suffix) || len(path) <= len(prefix)+len(suffix) {
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

	// Return sanitized config (no server_key, no bearer token)
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
