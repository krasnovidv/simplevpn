package api

import "testing"

// TestSignUpdateKnownAnswer locks the HMAC manifest-signing scheme to a fixed
// vector. The mobile client (update_service.dart) verifies against the same
// vector in its unit test — if either side changes the derivation, both tests
// must be updated together, preventing silent client/server divergence that
// would break (or weaken) update verification.
func TestSignUpdateKnownAnswer(t *testing.T) {
	const serverKey = "test-server-key"
	body := []byte(`{"apk_sha256":"abc123","version":"1.0.0","versionCode":7}`)
	const want = "f7d9d4b65e95ee7ca0e271cf3baa0ac92dffc1d68602b784800dacc7b744f9d8"

	got := signUpdate(serverKey, body)
	if got != want {
		t.Fatalf("signUpdate mismatch:\n got:  %s\n want: %s", got, want)
	}
}

func TestSignUpdateRejectsTamper(t *testing.T) {
	const serverKey = "test-server-key"
	body := []byte(`{"version":"1.0.0"}`)
	sig := signUpdate(serverKey, body)

	// A different body or a different key must produce a different signature.
	if signUpdate(serverKey, []byte(`{"version":"6.6.6"}`)) == sig {
		t.Error("tampered body produced identical signature")
	}
	if signUpdate("attacker-key", body) == sig {
		t.Error("wrong key produced identical signature")
	}
}
