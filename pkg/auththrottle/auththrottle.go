// Package auththrottle provides per-IP brute-force throttling for VPN
// credential authentication.
//
// bcrypt already makes each password check expensive, but that alone does not
// stop an attacker from opening many connections and guessing passwords (and it
// lets them burn server CPU doing so). This throttle caps how many *failed*
// authentication attempts a single source IP may make within a sliding time
// window. Once the cap is reached, further attempts from that IP are refused
// (the server hands them the decoy response) until older failures age out. A
// successful authentication clears the IP's failure count.
package auththrottle

import (
	"sync"
	"time"
)

const (
	// DefaultMaxFailures is the number of failed attempts per window before an
	// IP is throttled. Chosen to be lenient enough not to lock out legitimate
	// users behind a shared NAT after a few typos, while still cutting online
	// guessing to a trickle (combined with bcrypt's per-attempt cost).
	DefaultMaxFailures = 10
	// DefaultWindow is the sliding window over which failures are counted.
	DefaultWindow = time.Minute
)

// Throttle tracks failed authentication attempts per source IP.
// It is safe for concurrent use.
type Throttle struct {
	mu          sync.Mutex
	failures    map[string][]time.Time
	maxFailures int
	window      time.Duration
}

// New creates a Throttle. Non-positive arguments fall back to the defaults.
func New(maxFailures int, window time.Duration) *Throttle {
	if maxFailures <= 0 {
		maxFailures = DefaultMaxFailures
	}
	if window <= 0 {
		window = DefaultWindow
	}
	return &Throttle{
		failures:    make(map[string][]time.Time),
		maxFailures: maxFailures,
		window:      window,
	}
}

// Allowed reports whether an authentication attempt from ip may proceed.
// It returns false once ip has accumulated maxFailures within the window.
func (t *Throttle) Allowed(ip string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return len(t.validFailures(ip, time.Now())) < t.maxFailures
}

// Fail records a failed authentication attempt from ip.
func (t *Throttle) Fail(ip string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := time.Now()
	valid := t.validFailures(ip, now)
	t.failures[ip] = append(valid, now)
}

// Reset clears recorded failures for ip, e.g. after a successful login.
func (t *Throttle) Reset(ip string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.failures, ip)
}

// validFailures returns ip's failure timestamps still within the window,
// pruning expired ones (and dropping the IP entirely if none remain so the map
// does not grow without bound). Must be called with mu held.
func (t *Throttle) validFailures(ip string, now time.Time) []time.Time {
	cutoff := now.Add(-t.window)
	entries := t.failures[ip]
	valid := entries[:0]
	for _, ts := range entries {
		if ts.After(cutoff) {
			valid = append(valid, ts)
		}
	}
	if len(valid) == 0 {
		delete(t.failures, ip)
		return nil
	}
	t.failures[ip] = valid
	return valid
}
