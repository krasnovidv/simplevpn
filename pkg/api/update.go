package api

import (
	"log"
	"net/http"
	"os"
	"sync"
	"time"
)

type manifestCache struct {
	mu      sync.RWMutex
	data    []byte
	modTime time.Time
}

func (mc *manifestCache) get(path string) ([]byte, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}

	mc.mu.RLock()
	if mc.data != nil && info.ModTime().Equal(mc.modTime) {
		defer mc.mu.RUnlock()
		log.Printf("[api] DEBUG /api/update serving cached manifest (mtime=%s)", mc.modTime.Format(time.RFC3339))
		return mc.data, nil
	}
	mc.mu.RUnlock()

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	mc.mu.Lock()
	mc.data = data
	mc.modTime = info.ModTime()
	mc.mu.Unlock()

	log.Printf("[api] DEBUG /api/update reloaded manifest from disk (mtime=%s, size=%d)", info.ModTime().Format(time.RFC3339), len(data))
	return data, nil
}

var updateCache = &manifestCache{}

func (s *Server) handleUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	manifestPath := s.cfg.API.UpdateManifest
	if manifestPath == "" {
		manifestPath = "/opt/simplevpn/update.json"
	}

	log.Printf("[api] DEBUG GET /api/update from %s, manifest_path=%s", r.RemoteAddr, manifestPath)

	data, err := updateCache.get(manifestPath)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("[api] DEBUG /api/update manifest not found at %s", manifestPath)
			http.Error(w, `{"error":"no update manifest"}`, http.StatusNotFound)
			return
		}
		log.Printf("[api] ERROR /api/update reading manifest: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}
