package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
)

// registerUserRoutes adds user management endpoints to the mux.
func (s *Server) registerUserRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/users", s.authMiddleware(s.handleUsers))
	mux.HandleFunc("/api/users/", s.authMiddleware(s.handleUserAction))
}

// handleUsers handles GET /api/users and POST /api/users.
func (s *Server) handleUsers(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleListUsers(w, r)
	case http.MethodPost:
		s.handleCreateUser(w, r)
	default:
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

// handleListUsers returns all users (without password hashes).
func (s *Server) handleListUsers(w http.ResponseWriter, r *http.Request) {
	users := s.store.ListUsers()

	type userResp struct {
		Username  string `json:"username"`
		CreatedAt string `json:"created_at"`
		Disabled  bool   `json:"disabled"`
	}

	result := make([]userResp, len(users))
	for i, u := range users {
		result[i] = userResp{
			Username:  u.Username,
			CreatedAt: u.CreatedAt.Format("2006-01-02T15:04:05Z"),
			Disabled:  u.Disabled,
		}
	}

	log.Printf("[api] GET /api/users from %s, count=%d", r.RemoteAddr, len(result))
	writeJSON(w, map[string]interface{}{"users": result})
}

// handleCreateUser creates a new user. POST /api/users with {"username":"...", "password":"..."}.
func (s *Server) handleCreateUser(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Username == "" || req.Password == "" {
		http.Error(w, `{"error":"username and password are required"}`, http.StatusBadRequest)
		return
	}
	if len(req.Username) > 255 {
		http.Error(w, `{"error":"username too long (max 255)"}`, http.StatusBadRequest)
		return
	}
	if len(req.Password) < 8 || len(req.Password) > 1024 {
		http.Error(w, `{"error":"password must be 8-1024 characters"}`, http.StatusBadRequest)
		return
	}

	log.Printf("[api] POST /api/users from %s: creating user %q", r.RemoteAddr, req.Username)

	if err := s.store.AddUser(req.Username, req.Password); err != nil {
		log.Printf("[api] Create user %q failed: %v", req.Username, err)
		http.Error(w, `{"error":"failed to create user"}`, http.StatusConflict)
		return
	}

	w.WriteHeader(http.StatusCreated)
	writeJSON(w, map[string]string{"status": "created", "username": req.Username})
}

// handleUserAction handles DELETE /api/users/{username} and PUT /api/users/{username}.
func (s *Server) handleUserAction(w http.ResponseWriter, r *http.Request) {
	// Extract username from path: /api/users/{username}
	path := strings.TrimPrefix(r.URL.Path, "/api/users/")
	if path == "" {
		http.Error(w, `{"error":"missing username"}`, http.StatusBadRequest)
		return
	}

	// Check for sub-actions: /api/users/{username}/password, /api/users/{username}/disable
	parts := strings.SplitN(path, "/", 2)
	username := parts[0]

	if len(parts) == 2 {
		switch parts[1] {
		case "password":
			s.handleUpdatePassword(w, r, username)
		case "disable":
			s.handleDisableUser(w, r, username)
		case "enable":
			s.handleEnableUser(w, r, username)
		default:
			http.Error(w, `{"error":"unknown action"}`, http.StatusBadRequest)
		}
		return
	}

	switch r.Method {
	case http.MethodDelete:
		s.handleDeleteUser(w, r, username)
	default:
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

// handleDeleteUser removes a user. DELETE /api/users/{username}.
func (s *Server) handleDeleteUser(w http.ResponseWriter, r *http.Request, username string) {
	log.Printf("[api] DELETE /api/users/%s from %s", username, r.RemoteAddr)

	if err := s.store.RemoveUser(username); err != nil {
		log.Printf("[api] Delete user %q failed: %v", username, err)
		http.Error(w, `{"error":"user not found"}`, http.StatusNotFound)
		return
	}

	writeJSON(w, map[string]string{"status": "deleted", "username": username})
}

// handleUpdatePassword changes a user's password. PUT /api/users/{username}/password with {"password":"..."}.
func (s *Server) handleUpdatePassword(w http.ResponseWriter, r *http.Request, username string) {
	if r.Method != http.MethodPut {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	var req struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if req.Password == "" {
		http.Error(w, `{"error":"password is required"}`, http.StatusBadRequest)
		return
	}
	if len(req.Password) < 8 || len(req.Password) > 1024 {
		http.Error(w, `{"error":"password must be 8-1024 characters"}`, http.StatusBadRequest)
		return
	}

	log.Printf("[api] PUT /api/users/%s/password from %s", username, r.RemoteAddr)

	if err := s.store.UpdatePassword(username, req.Password); err != nil {
		log.Printf("[api] Update password for %q failed: %v", username, err)
		http.Error(w, `{"error":"user not found"}`, http.StatusNotFound)
		return
	}

	writeJSON(w, map[string]string{"status": "password_updated", "username": username})
}

// handleDisableUser disables a user account. POST /api/users/{username}/disable.
func (s *Server) handleDisableUser(w http.ResponseWriter, r *http.Request, username string) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	log.Printf("[api] POST /api/users/%s/disable from %s", username, r.RemoteAddr)

	if err := s.store.SetDisabled(username, true); err != nil {
		log.Printf("[api] Disable user %q failed: %v", username, err)
		http.Error(w, `{"error":"user not found"}`, http.StatusNotFound)
		return
	}

	writeJSON(w, map[string]string{"status": "disabled", "username": username})
}

// handleEnableUser enables a user account. POST /api/users/{username}/enable.
func (s *Server) handleEnableUser(w http.ResponseWriter, r *http.Request, username string) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	log.Printf("[api] POST /api/users/%s/enable from %s", username, r.RemoteAddr)

	if err := s.store.SetDisabled(username, false); err != nil {
		log.Printf("[api] Enable user %q failed: %v", username, err)
		http.Error(w, `{"error":"user not found"}`, http.StatusNotFound)
		return
	}

	writeJSON(w, map[string]string{"status": "enabled", "username": username})
}
