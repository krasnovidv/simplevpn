package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"sync"
	"time"

	"simplevpn/pkg/logx"
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
		logx.Debugf("[api] /api/update serving cached manifest (mtime=%s)", mc.modTime.Format(time.RFC3339))
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

	logx.Debugf("[api] /api/update reloaded manifest from disk (mtime=%s, size=%d)", info.ModTime().Format(time.RFC3339), len(data))
	return data, nil
}

var updateCache = &manifestCache{}

// apkHashCache caches the hex-encoded SHA-256 of the APK file, keyed by its
// modification time and size. Hashing a multi-MB file on every poll would be
// wasteful, so we recompute only when the file actually changes.
type apkHashCache struct {
	mu      sync.RWMutex
	hash    string
	modTime time.Time
	size    int64
}

func (ac *apkHashCache) get(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}

	ac.mu.RLock()
	if ac.hash != "" && info.ModTime().Equal(ac.modTime) && info.Size() == ac.size {
		h := ac.hash
		ac.mu.RUnlock()
		return h, nil
	}
	ac.mu.RUnlock()

	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	sum := hex.EncodeToString(h.Sum(nil))

	ac.mu.Lock()
	ac.hash = sum
	ac.modTime = info.ModTime()
	ac.size = info.Size()
	ac.mu.Unlock()

	logx.Debugf("[api] /api/update hashed APK %s (mtime=%s, size=%d, sha256=%s)", path, info.ModTime().Format(time.RFC3339), info.Size(), sum)
	return sum, nil
}

var apkHashes = &apkHashCache{}

// updateSigningKey derives the manifest-signing key from the server key,
// mirroring the tunnel key-derivation scheme (see pkg/tunnel/keys.go).
// The mobile client holds the same server key (delivered as "server_key" in the
// VPN config) and derives the identical key to verify the signature.
func updateSigningKey(serverKey string) []byte {
	k := sha256.Sum256(append([]byte(serverKey), []byte("update-signing")...))
	return k[:]
}

// signUpdate returns the hex-encoded HMAC-SHA256 of body keyed by the
// server-key-derived signing key.
func signUpdate(serverKey string, body []byte) string {
	mac := hmac.New(sha256.New, updateSigningKey(serverKey))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

func (s *Server) handleUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	manifestPath := s.cfg.API.UpdateManifest
	if manifestPath == "" {
		manifestPath = "/opt/simplevpn/update.json"
	}

	logx.Debugf("[api] GET /api/update from %s, manifest_path=%s", r.RemoteAddr, manifestPath)

	data, err := updateCache.get(manifestPath)
	if err != nil {
		if os.IsNotExist(err) {
			logx.Debugf("[api] /api/update manifest not found at %s", manifestPath)
			http.Error(w, `{"error":"no update manifest"}`, http.StatusNotFound)
			return
		}
		logx.Errorf("[api] /api/update reading manifest: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	// Parse the manifest and inject the APK's SHA-256 so the signed manifest
	// authenticates the binary itself, not just its metadata.
	var manifest map[string]interface{}
	if err := json.Unmarshal(data, &manifest); err != nil {
		logx.Errorf("[api] /api/update manifest is not valid JSON: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	apkPath := s.cfg.API.ApkPath
	if apkPath == "" {
		apkPath = "/opt/simplevpn/simplevpn.apk"
	}
	if sum, herr := apkHashes.get(apkPath); herr != nil {
		// Without an APK hash the client cannot verify the download and will
		// (correctly) refuse to install. Log loudly but still serve a signed
		// manifest so the client gets a clear, authenticated "no APK" signal.
		logx.Warnf("[api] /api/update could not hash APK at %s: %v", apkPath, herr)
	} else {
		manifest["apk_sha256"] = sum
	}

	body, err := json.Marshal(manifest)
	if err != nil {
		logx.Errorf("[api] /api/update marshaling manifest: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	// Authenticate the manifest (and embedded APK hash) with HMAC-SHA256 keyed
	// by the shared server key. The update channel disables TLS certificate
	// validation on the client to support self-signed deployments, so this
	// signature — not the transport — is what prevents an on-path attacker from
	// substituting a malicious manifest or APK (which would be remote code
	// execution on the device).
	sig := signUpdate(s.cfg.ServerKey, body)

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Update-Signature", sig)
	w.Write(body)
}
