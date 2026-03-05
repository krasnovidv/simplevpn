package replay_test

import (
	"testing"

	"simplevpn/pkg/replay"
)

func TestBasicAccept(t *testing.T) {
	w := replay.New()
	if !w.Check(1) {
		t.Error("Should accept first packet seq=1")
	}
	if !w.Check(2) {
		t.Error("Should accept seq=2")
	}
	if !w.Check(100) {
		t.Error("Should accept seq=100 (forward jump)")
	}
}

func TestReplayDetection(t *testing.T) {
	w := replay.New()
	w.Check(10)
	if w.Check(10) {
		t.Error("Duplicate packet seq=10 should be rejected (replay)")
	}
}

func TestTooOldPacket(t *testing.T) {
	w := replay.New()
	w.Check(replay.WindowSize + 100)
	if w.Check(1) {
		t.Error("Too old packet should be rejected")
	}
}

func TestWindowBoundary(t *testing.T) {
	w := replay.New()
	top := uint64(replay.WindowSize + 100)
	w.Check(top)
	boundary := top - uint64(replay.WindowSize) + 1
	if !w.Check(boundary) {
		t.Errorf("Packet at window boundary (seq=%d) should be accepted", boundary)
	}
	tooOld := boundary - 1
	if w.Check(tooOld) {
		t.Errorf("Packet beyond window (seq=%d) should be rejected", tooOld)
	}
}

func TestOutOfOrderAccepted(t *testing.T) {
	w := replay.New()
	w.Check(5)
	w.Check(3)
	w.Check(4)
	if !w.Check(1) {
		t.Error("Packet seq=1 should be accepted (within window, not duplicate)")
	}
}

func BenchmarkCheck(b *testing.B) {
	w := replay.New()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		w.Check(uint64(i))
	}
}
