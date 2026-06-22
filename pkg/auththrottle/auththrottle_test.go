package auththrottle

import (
	"sync"
	"testing"
	"time"
)

func TestAllowsUntilMaxFailures(t *testing.T) {
	th := New(3, time.Minute)
	const ip = "1.2.3.4"

	for i := 0; i < 3; i++ {
		if !th.Allowed(ip) {
			t.Fatalf("attempt %d should be allowed", i)
		}
		th.Fail(ip)
	}

	if th.Allowed(ip) {
		t.Fatal("4th attempt should be throttled after 3 failures")
	}
}

func TestResetClearsFailures(t *testing.T) {
	th := New(3, time.Minute)
	const ip = "1.2.3.4"

	th.Fail(ip)
	th.Fail(ip)
	th.Fail(ip)
	if th.Allowed(ip) {
		t.Fatal("should be throttled after 3 failures")
	}

	th.Reset(ip)
	if !th.Allowed(ip) {
		t.Fatal("Reset should re-allow the IP")
	}
}

func TestWindowExpiry(t *testing.T) {
	th := New(2, 50*time.Millisecond)
	const ip = "1.2.3.4"

	th.Fail(ip)
	th.Fail(ip)
	if th.Allowed(ip) {
		t.Fatal("should be throttled after 2 failures")
	}

	time.Sleep(70 * time.Millisecond)
	if !th.Allowed(ip) {
		t.Fatal("failures should expire after the window slides")
	}
}

func TestPerIPIsolation(t *testing.T) {
	th := New(2, time.Minute)
	th.Fail("1.1.1.1")
	th.Fail("1.1.1.1")

	if th.Allowed("1.1.1.1") {
		t.Fatal("offending IP should be throttled")
	}
	if !th.Allowed("2.2.2.2") {
		t.Fatal("a different IP must not be affected")
	}
}

func TestExpiredEntriesArePruned(t *testing.T) {
	th := New(5, 20*time.Millisecond)
	th.Fail("1.1.1.1")
	time.Sleep(30 * time.Millisecond)
	// Touching the throttle prunes the now-expired entry.
	th.Allowed("1.1.1.1")

	th.mu.Lock()
	_, present := th.failures["1.1.1.1"]
	th.mu.Unlock()
	if present {
		t.Fatal("expired IP entry should have been pruned from the map")
	}
}

func TestConcurrentUse(t *testing.T) {
	th := New(100, time.Minute)
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			ip := "10.0.0." + string(rune('0'+n%10))
			th.Allowed(ip)
			th.Fail(ip)
			th.Reset(ip)
		}(i)
	}
	wg.Wait()
}
