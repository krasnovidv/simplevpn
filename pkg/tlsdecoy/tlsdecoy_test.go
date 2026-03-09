package tlsdecoy

import (
	"bytes"
	"net"
	"testing"
	"time"
)

func TestGenerateCredAuth_Roundtrip(t *testing.T) {
	username := "testuser"
	password := "testpassword123"

	frame, err := GenerateCredAuth(username, password)
	if err != nil {
		t.Fatalf("GenerateCredAuth: %v", err)
	}

	parsedUser, parsedPass, err := ParseCredAuth(frame)
	if err != nil {
		t.Fatalf("ParseCredAuth: %v", err)
	}

	if parsedUser != username {
		t.Errorf("username: got %q, want %q", parsedUser, username)
	}
	if parsedPass != password {
		t.Errorf("password: got %q, want %q", parsedPass, password)
	}
}

func TestGenerateCredAuth_Version(t *testing.T) {
	frame, err := GenerateCredAuth("user", "pass")
	if err != nil {
		t.Fatalf("GenerateCredAuth: %v", err)
	}
	if frame[0] != CredAuthVersion {
		t.Errorf("version: got 0x%02x, want 0x%02x", frame[0], CredAuthVersion)
	}
}

func TestGenerateCredAuth_EmptyUsername(t *testing.T) {
	_, err := GenerateCredAuth("", "password")
	if err == nil {
		t.Error("expected error for empty username")
	}
}

func TestGenerateCredAuth_EmptyPassword(t *testing.T) {
	_, err := GenerateCredAuth("user", "")
	if err == nil {
		t.Error("expected error for empty password")
	}
}

func TestGenerateCredAuth_MaxUsername(t *testing.T) {
	longUser := string(make([]byte, MaxUsernameLen+1))
	_, err := GenerateCredAuth(longUser, "pass")
	if err == nil {
		t.Error("expected error for username exceeding max length")
	}
}

func TestParseCredAuth_BadVersion(t *testing.T) {
	data := []byte{0x01, 4, 'u', 's', 'e', 'r', 0, 4, 'p', 'a', 's', 's'}
	_, _, err := ParseCredAuth(data)
	if err == nil {
		t.Error("expected error for wrong version")
	}
}

func TestParseCredAuth_TooShort(t *testing.T) {
	_, _, err := ParseCredAuth([]byte{0x02})
	if err == nil {
		t.Error("expected error for too-short data")
	}
}

func TestParseCredAuth_Truncated(t *testing.T) {
	// Valid header but truncated password
	data := []byte{CredAuthVersion, 4, 'u', 's', 'e', 'r', 0, 10}
	_, _, err := ParseCredAuth(data)
	if err == nil {
		t.Error("expected error for truncated password")
	}
}

func TestReadCredAuth_ViaPipe(t *testing.T) {
	username := "alice"
	password := "secret123"

	frame, err := GenerateCredAuth(username, password)
	if err != nil {
		t.Fatalf("GenerateCredAuth: %v", err)
	}

	// Use a net.Pipe to simulate a connection
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	// Write frame from client side
	go func() {
		client.Write(frame)
	}()

	// Read from server side
	gotUser, gotPass, err := ReadCredAuth(server)
	if err != nil {
		t.Fatalf("ReadCredAuth: %v", err)
	}

	if gotUser != username {
		t.Errorf("username: got %q, want %q", gotUser, username)
	}
	if gotPass != password {
		t.Errorf("password: got %q, want %q", gotPass, password)
	}
}

func TestReadCredAuth_Timeout(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	// Don't write anything — should timeout
	done := make(chan error, 1)
	go func() {
		_, _, err := ReadCredAuth(server)
		done <- err
	}()

	select {
	case err := <-done:
		if err == nil {
			t.Error("expected timeout error")
		}
	case <-time.After(15 * time.Second):
		t.Error("ReadCredAuth did not timeout")
	}
}

func TestGenerateCredAuth_UTF8(t *testing.T) {
	username := "пользователь"
	password := "пароль123"

	frame, err := GenerateCredAuth(username, password)
	if err != nil {
		t.Fatalf("GenerateCredAuth: %v", err)
	}

	gotUser, gotPass, err := ParseCredAuth(frame)
	if err != nil {
		t.Fatalf("ParseCredAuth: %v", err)
	}

	if gotUser != username {
		t.Errorf("username: got %q, want %q", gotUser, username)
	}
	if gotPass != password {
		t.Errorf("password: got %q, want %q", gotPass, password)
	}
}

func TestFrameSize(t *testing.T) {
	frame, _ := GenerateCredAuth("user", "pass")
	expected := 1 + 1 + 4 + 2 + 4 // version + ulen + "user" + plen + "pass"
	if len(frame) != expected {
		t.Errorf("frame size: got %d, want %d", len(frame), expected)
	}
}

func TestGenerateCredAuth_BinaryContent(t *testing.T) {
	frame, _ := GenerateCredAuth("user", "pass")

	// Verify version byte
	if frame[0] != 0x02 {
		t.Errorf("version byte: got 0x%02x", frame[0])
	}
	// Verify username length byte
	if frame[1] != 4 {
		t.Errorf("username length: got %d", frame[1])
	}
	// Verify username
	if !bytes.Equal(frame[2:6], []byte("user")) {
		t.Errorf("username bytes: got %x", frame[2:6])
	}
	// Verify password length (big-endian)
	if frame[6] != 0 || frame[7] != 4 {
		t.Errorf("password length bytes: got [%d, %d]", frame[6], frame[7])
	}
	// Verify password
	if !bytes.Equal(frame[8:12], []byte("pass")) {
		t.Errorf("password bytes: got %x", frame[8:12])
	}
}
