package api

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
)

func (s *Server) handleDownload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	filename := filepath.Base(r.URL.Path)
	// %q quotes the untrusted path segment so it can't inject newlines/control
	// chars into the log stream (log forging from an unauthenticated endpoint).
	log.Printf("[api] GET /download/%q from %s", filename, r.RemoteAddr)

	if filename != "simplevpn.apk" {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}

	apkPath := s.cfg.API.ApkPath
	if apkPath == "" {
		apkPath = "/opt/simplevpn/simplevpn.apk"
	}

	if _, err := os.Stat(apkPath); os.IsNotExist(err) {
		log.Printf("[api] APK not found at %s", apkPath)
		http.Error(w, "APK file not available", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", "attachment; filename=\"simplevpn.apk\"")
	http.ServeFile(w, r, apkPath)
}
