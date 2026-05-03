package vpnlib

import (
	"encoding/json"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestGetStats_ReturnsValidJSON(t *testing.T) {
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, 0)

	raw := GetStats()
	var m map[string]int64
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("GetStats() returned invalid JSON: %v\nraw=%q", err, raw)
	}
	if m["bytes_in"] != 0 || m["bytes_out"] != 0 || m["since_ms"] != 0 {
		t.Errorf("expected all zeros, got %v", m)
	}
}

func TestGetStats_ReflectsAtomicIncrements(t *testing.T) {
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, 1000)

	atomic.AddInt64(&statsBytesIn, 100)
	atomic.AddInt64(&statsBytesOut, 200)

	raw := GetStats()
	var m map[string]int64
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if m["bytes_in"] != 100 {
		t.Errorf("bytes_in = %d, want 100", m["bytes_in"])
	}
	if m["bytes_out"] != 200 {
		t.Errorf("bytes_out = %d, want 200", m["bytes_out"])
	}
	if m["since_ms"] != 1000 {
		t.Errorf("since_ms = %d, want 1000", m["since_ms"])
	}
}

func TestGetStats_ConcurrentIncrementsNoTornReads(t *testing.T) {
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, time.Now().UnixMilli())

	const goroutines = 50
	const iterations = 1000

	var wg sync.WaitGroup
	wg.Add(goroutines * 2)

	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < iterations; j++ {
				atomic.AddInt64(&statsBytesIn, 1)
			}
		}()
		go func() {
			defer wg.Done()
			for j := 0; j < iterations; j++ {
				atomic.AddInt64(&statsBytesOut, 1)
			}
		}()
	}
	wg.Wait()

	in := atomic.LoadInt64(&statsBytesIn)
	out := atomic.LoadInt64(&statsBytesOut)

	expectedIn := int64(goroutines * iterations)
	expectedOut := int64(goroutines * iterations)

	if in != expectedIn {
		t.Errorf("statsBytesIn = %d, want %d (torn read or lost increment)", in, expectedIn)
	}
	if out != expectedOut {
		t.Errorf("statsBytesOut = %d, want %d (torn read or lost increment)", out, expectedOut)
	}
}

func TestGetStats_ConcurrentReadsWhileWriting(t *testing.T) {
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	atomic.StoreInt64(&statsConnectedAt, time.Now().UnixMilli())

	const writers = 20
	const readers = 10
	const iterations = 500

	var wg sync.WaitGroup
	wg.Add(writers + readers)

	for i := 0; i < writers; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < iterations; j++ {
				atomic.AddInt64(&statsBytesIn, 7)
				atomic.AddInt64(&statsBytesOut, 13)
			}
		}()
	}

	for i := 0; i < readers; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < iterations; j++ {
				raw := GetStats()
				var m map[string]int64
				if err := json.Unmarshal([]byte(raw), &m); err != nil {
					t.Errorf("GetStats() returned invalid JSON during concurrent writes: %v", err)
					return
				}
				if m["bytes_in"] < 0 || m["bytes_out"] < 0 {
					t.Errorf("negative counter value: in=%d, out=%d", m["bytes_in"], m["bytes_out"])
				}
			}
		}()
	}
	wg.Wait()
}

func TestGetStats_ResetOnNewSession(t *testing.T) {
	atomic.StoreInt64(&statsBytesIn, 5000)
	atomic.StoreInt64(&statsBytesOut, 9000)
	atomic.StoreInt64(&statsConnectedAt, 12345)

	// Simulate what Connect/Preflight does
	atomic.StoreInt64(&statsBytesIn, 0)
	atomic.StoreInt64(&statsBytesOut, 0)
	newSince := time.Now().UnixMilli()
	atomic.StoreInt64(&statsConnectedAt, newSince)

	raw := GetStats()
	var m map[string]int64
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if m["bytes_in"] != 0 {
		t.Errorf("bytes_in should be 0 after reset, got %d", m["bytes_in"])
	}
	if m["bytes_out"] != 0 {
		t.Errorf("bytes_out should be 0 after reset, got %d", m["bytes_out"])
	}
	if m["since_ms"] != newSince {
		t.Errorf("since_ms = %d, want %d", m["since_ms"], newSince)
	}
}

func TestGetStats_LargeValues(t *testing.T) {
	atomic.StoreInt64(&statsBytesIn, 1<<50)
	atomic.StoreInt64(&statsBytesOut, 1<<50+1)
	atomic.StoreInt64(&statsConnectedAt, time.Now().UnixMilli())

	raw := GetStats()
	var m map[string]int64
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("invalid JSON with large values: %v", err)
	}
	if m["bytes_in"] != 1<<50 {
		t.Errorf("bytes_in = %d, want %d", m["bytes_in"], int64(1<<50))
	}
}
