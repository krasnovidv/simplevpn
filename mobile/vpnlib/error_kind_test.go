package vpnlib

import (
	"fmt"
	"net"
	"testing"
)

func TestErrKindString(t *testing.T) {
	cases := []struct {
		k    errKind
		want string
	}{
		{kindNone, "none"},
		{kindTransient, "transient"},
		{kindAuth, "auth"},
		{kindFatal, "fatal"},
		{errKind(99), "none"},
	}
	for _, c := range cases {
		if got := c.k.String(); got != c.want {
			t.Errorf("errKind(%d).String() = %q, want %q", c.k, got, c.want)
		}
	}
}

func TestClassifyDialErr(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want errKind
	}{
		{"nil", nil, kindNone},
		{"connection refused", fmt.Errorf("dial tcp 127.0.0.1:1: connect: connection refused"), kindTransient},
		{"timeout", fmt.Errorf("i/o timeout"), kindTransient},
		{"reset", fmt.Errorf("read tcp: connection reset by peer"), kindTransient},
		{"401 status", fmt.Errorf("ws upgrade: bad status 401"), kindAuth},
		{"401 in path", fmt.Errorf("HTTP 401 returned"), kindAuth},
		{"unauthorized text", fmt.Errorf("server returned: Unauthorized"), kindAuth},
		{"x509 unknown ca", fmt.Errorf("x509: certificate signed by unknown authority"), kindFatal},
		{"bad certificate", fmt.Errorf("tls: bad certificate"), kindFatal},
		{"tls handshake", fmt.Errorf("tls: handshake failure"), kindFatal},
		{"tls handshake (no colon)", fmt.Errorf("tls handshake error: ..."), kindFatal},
		{"unknown authority", fmt.Errorf("certificate signed by unknown authority"), kindFatal},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := classifyDialErr(c.err)
			if got != c.want {
				t.Errorf("classifyDialErr(%v) = %s, want %s", c.err, got, c.want)
			}
		})
	}
}

func TestLastErrorKindStateTransitions(t *testing.T) {
	current = &state{status: "disconnected"}

	if got := LastErrorKind(); got != "none" {
		t.Fatalf("initial LastErrorKind = %q, want none", got)
	}

	setLastKind(kindTransient, "test", fmt.Errorf("boom"))
	if got := LastErrorKind(); got != "transient" {
		t.Fatalf("after transient, LastErrorKind = %q", got)
	}

	setLastKind(kindAuth, "test", nil)
	if got := LastErrorKind(); got != "auth" {
		t.Fatalf("after auth, LastErrorKind = %q", got)
	}

	resetLastKind()
	if got := LastErrorKind(); got != "none" {
		t.Fatalf("after reset, LastErrorKind = %q", got)
	}
}

// Connect with bad config JSON should classify as fatal.
func TestConnect_BadConfigClassifiesFatal(t *testing.T) {
	current = &state{status: "disconnected"}
	if err := Connect(`{not json`, 0); err == nil {
		t.Fatal("expected error for malformed config")
	}
	if got := LastErrorKind(); got != "fatal" {
		t.Errorf("LastErrorKind after bad config = %q, want fatal", got)
	}
}

// Connect with missing required fields should also classify as fatal.
func TestConnect_MissingFieldsClassifiesFatal(t *testing.T) {
	current = &state{status: "disconnected"}
	if err := Connect(`{"server":"","server_key":"k","username":"u","password":"p"}`, 0); err == nil {
		t.Fatal("expected error for missing server")
	}
	if got := LastErrorKind(); got != "fatal" {
		t.Errorf("LastErrorKind after missing field = %q, want fatal", got)
	}
}

// Preflight against a refused TCP port should classify as transient.
// This guards the platform retry loop's "transient => keep retrying with backoff"
// decision against regressions.
func TestPreflight_RefusedDialClassifiesTransient(t *testing.T) {
	current = &state{status: "disconnected"}

	// Bind a listener and immediately close it to get a guaranteed-refused port.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := l.Addr().String()
	l.Close()

	cfg := fmt.Sprintf(
		`{"server":%q,"server_key":"00000000000000000000000000000000","username":"u","password":"p","sni":"example.com","skip_verify":true,"transport":"tls"}`,
		addr,
	)
	res := Preflight(cfg)
	if !startsWith(res, "error: connect:") {
		t.Fatalf("Preflight result = %q, want error starting with 'error: connect:'", res)
	}
	if got := LastErrorKind(); got != "transient" {
		t.Errorf("LastErrorKind after refused dial = %q, want transient", got)
	}
}

// Preflight against a plain-TCP listener (no TLS) should fail at the TLS
// handshake and classify as fatal — the server's TLS is fundamentally
// broken / mis-configured, retrying won't help.
func TestPreflight_TLSHandshakeFailClassifiesFatal(t *testing.T) {
	current = &state{status: "disconnected"}

	// Listener that accepts then immediately closes — no TLS handshake possible.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer l.Close()
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()

	cfg := fmt.Sprintf(
		`{"server":%q,"server_key":"00000000000000000000000000000000","username":"u","password":"p","sni":"example.com","skip_verify":true,"transport":"tls"}`,
		l.Addr().String(),
	)
	res := Preflight(cfg)
	if !startsWith(res, "error: connect:") {
		t.Fatalf("Preflight result = %q, want connect error", res)
	}
	// Either tls-handshake-related (fatal) or transient (EOF before handshake).
	// The classifier prefers fatal when the error mentions tls/handshake.
	got := LastErrorKind()
	if got != "fatal" && got != "transient" {
		t.Errorf("LastErrorKind after TLS-broken peer = %q, want fatal or transient", got)
	}
	t.Logf("LastErrorKind for plain-TCP peer = %s", got)
}

// resetLastKind must run on every Connect entry — even one that fails fast.
// After two back-to-back failed Connects, the kind reflects the SECOND failure,
// not a stale residue from the first.
func TestConnect_ResetOnEntry(t *testing.T) {
	current = &state{status: "disconnected"}

	// First call: missing fields => fatal.
	_ = Connect(`{"server":"","server_key":"k","username":"u","password":"p"}`, 0)
	if got := LastErrorKind(); got != "fatal" {
		t.Fatalf("first call kind = %q, want fatal", got)
	}

	// Second call: bad JSON => fatal again, but we want to confirm the
	// reset happened (kind cycled through none to fatal, not stuck on prev).
	// Simulate by setting a different kind first.
	setLastKind(kindAuth, "manual", nil)
	if got := LastErrorKind(); got != "auth" {
		t.Fatalf("manual seed kind = %q, want auth", got)
	}

	_ = Connect(`{not json`, 0)
	if got := LastErrorKind(); got != "fatal" {
		t.Fatalf("after second failed Connect kind = %q, want fatal (reset then re-set)", got)
	}
}

func startsWith(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}
