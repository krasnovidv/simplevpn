// Package logx is a minimal leveled wrapper over the standard log package.
//
// The VPN server previously emitted a large amount of always-on output —
// per-connection metadata, per-packet drops, usernames on every auth attempt —
// regardless of the configured log_level (which was parsed but never applied).
// logx gives log_level real effect: a single process-wide threshold gates
// output so that verbose, privacy-sensitive detail stays at debug level and is
// silent in a default (info) production deployment.
//
// Usage:
//
//	logx.SetLevelString(cfg.LogLevel) // once at startup
//	logx.Debugf("[server] session id=%s user=%q", id, user)
//	logx.Infof("[server] client connected addr=%s", addr)
package logx

import (
	"log"
	"strings"
	"sync/atomic"
)

// Level is a logging severity threshold.
type Level int32

const (
	LevelDebug Level = iota
	LevelInfo
	LevelWarn
	LevelError
)

// current holds the active threshold; messages below it are dropped.
// Defaults to info so production output is quiet unless explicitly enabled.
var current atomic.Int32

func init() { current.Store(int32(LevelInfo)) }

// SetLevel sets the active logging threshold.
func SetLevel(l Level) { current.Store(int32(l)) }

// SetLevelString sets the threshold from a config string
// ("debug", "info", "warn"/"warning", "error"). Unknown/empty values map to info.
func SetLevelString(s string) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "debug":
		SetLevel(LevelDebug)
	case "warn", "warning":
		SetLevel(LevelWarn)
	case "error":
		SetLevel(LevelError)
	default:
		SetLevel(LevelInfo)
	}
}

func enabled(l Level) bool { return Level(current.Load()) <= l }

// Debugf logs at debug level. Use for high-volume or privacy-sensitive detail
// (connection metadata, usernames, per-packet events).
func Debugf(format string, args ...interface{}) {
	if enabled(LevelDebug) {
		log.Printf(format, args...)
	}
}

// Infof logs at info level (default).
func Infof(format string, args ...interface{}) {
	if enabled(LevelInfo) {
		log.Printf(format, args...)
	}
}

// Warnf logs at warn level.
func Warnf(format string, args ...interface{}) {
	if enabled(LevelWarn) {
		log.Printf(format, args...)
	}
}

// Errorf logs at error level.
func Errorf(format string, args ...interface{}) {
	if enabled(LevelError) {
		log.Printf(format, args...)
	}
}
