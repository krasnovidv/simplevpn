package api

import (
	"embed"
	"io/fs"
	"log"
	"net/http"
)

//go:embed web/*
var webFS embed.FS

// RegisterWebUI adds the embedded web admin panel to the API server.
// It serves the SPA at the root path (/).
func (s *Server) RegisterWebUI() {
	subFS, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Printf("[api] Failed to create sub filesystem for web UI: %v", err)
		return
	}

	s.mux.Handle("/", http.FileServer(http.FS(subFS)))
	log.Printf("[api] Web admin UI registered at /")
}
