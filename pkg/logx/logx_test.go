package logx

import (
	"bytes"
	"log"
	"testing"
)

// capture redirects the standard logger's output for the duration of fn.
func capture(fn func()) string {
	var buf bytes.Buffer
	old := log.Writer()
	flags := log.Flags()
	log.SetOutput(&buf)
	log.SetFlags(0)
	defer func() {
		log.SetOutput(old)
		log.SetFlags(flags)
	}()
	fn()
	return buf.String()
}

func TestLevelGating(t *testing.T) {
	t.Cleanup(func() { SetLevel(LevelInfo) })

	SetLevel(LevelInfo)
	out := capture(func() {
		Debugf("debug-line")
		Infof("info-line")
		Warnf("warn-line")
		Errorf("error-line")
	})
	if bytes.Contains([]byte(out), []byte("debug-line")) {
		t.Error("debug should be suppressed at info level")
	}
	for _, want := range []string{"info-line", "warn-line", "error-line"} {
		if !bytes.Contains([]byte(out), []byte(want)) {
			t.Errorf("expected %q at info level", want)
		}
	}
}

func TestDebugLevelShowsAll(t *testing.T) {
	t.Cleanup(func() { SetLevel(LevelInfo) })

	SetLevel(LevelDebug)
	out := capture(func() { Debugf("dbg") })
	if !bytes.Contains([]byte(out), []byte("dbg")) {
		t.Error("debug message should appear at debug level")
	}
}

func TestErrorLevelSuppressesInfo(t *testing.T) {
	t.Cleanup(func() { SetLevel(LevelInfo) })

	SetLevel(LevelError)
	out := capture(func() {
		Infof("info-line")
		Warnf("warn-line")
		Errorf("error-line")
	})
	if bytes.Contains([]byte(out), []byte("info-line")) || bytes.Contains([]byte(out), []byte("warn-line")) {
		t.Error("info/warn should be suppressed at error level")
	}
	if !bytes.Contains([]byte(out), []byte("error-line")) {
		t.Error("error should appear at error level")
	}
}

func TestSetLevelString(t *testing.T) {
	t.Cleanup(func() { SetLevel(LevelInfo) })

	cases := map[string]Level{
		"debug":   LevelDebug,
		"info":    LevelInfo,
		"warn":    LevelWarn,
		"warning": LevelWarn,
		"error":   LevelError,
		"":        LevelInfo,
		"bogus":   LevelInfo,
		"DEBUG":   LevelDebug,
		"  info ": LevelInfo,
	}
	for in, want := range cases {
		SetLevelString(in)
		if got := Level(current.Load()); got != want {
			t.Errorf("SetLevelString(%q): got %d, want %d", in, got, want)
		}
	}
}
