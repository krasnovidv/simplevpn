package ippool

import (
	"net/netip"
	"sync"
	"testing"
)

func mustPool(t *testing.T, cidr string, reserved ...netip.Addr) *Pool {
	t.Helper()
	p, err := New(cidr, reserved...)
	if err != nil {
		t.Fatalf("New(%q): %v", cidr, err)
	}
	return p
}

func TestAllocateAndRelease(t *testing.T) {
	// /30 has 4 addresses: .0 (net), .1, .2, .3 (broadcast)
	p := mustPool(t, "10.0.0.0/30")
	if p.Size() != 2 {
		t.Fatalf("Size() = %d, want 2", p.Size())
	}

	a1, err := p.Allocate()
	if err != nil {
		t.Fatalf("Allocate 1: %v", err)
	}
	a2, err := p.Allocate()
	if err != nil {
		t.Fatalf("Allocate 2: %v", err)
	}
	if a1 == a2 {
		t.Fatalf("Got duplicate address %s", a1)
	}
	if p.Used() != 2 {
		t.Errorf("Used() = %d, want 2", p.Used())
	}

	// Pool exhausted.
	_, err = p.Allocate()
	if err != ErrPoolExhausted {
		t.Fatalf("Expected ErrPoolExhausted, got %v", err)
	}

	// Release and re-allocate.
	p.Release(a1)
	if p.Used() != 1 {
		t.Errorf("Used() after release = %d, want 1", p.Used())
	}

	a3, err := p.Allocate()
	if err != nil {
		t.Fatalf("Allocate after release: %v", err)
	}
	if a3 != a1 {
		t.Errorf("Expected reuse of %s, got %s", a1, a3)
	}
}

func TestReservedExcluded(t *testing.T) {
	// /29 has 8 addresses: .0 (net), .1-.6, .7 (broadcast)
	// Reserve .1 (server TUN).
	server := netip.MustParseAddr("10.0.0.1")
	p := mustPool(t, "10.0.0.0/29", server)

	// Size should be 5: .2 .3 .4 .5 .6 (not .0, .1, .7)
	if p.Size() != 5 {
		t.Fatalf("Size() = %d, want 5", p.Size())
	}

	for i := 0; i < 5; i++ {
		addr, err := p.Allocate()
		if err != nil {
			t.Fatalf("Allocate %d: %v", i, err)
		}
		if addr == server {
			t.Fatalf("Allocated reserved address %s", server)
		}
	}

	_, err := p.Allocate()
	if err != ErrPoolExhausted {
		t.Fatalf("Expected ErrPoolExhausted after exhausting, got %v", err)
	}
}

func TestConcurrentAllocate(t *testing.T) {
	// /24 has 254 usable addresses (.1-.254)
	p := mustPool(t, "10.1.0.0/24")

	const workers = 20
	const allocsEach = 10

	addrs := make(chan netip.Addr, workers*allocsEach)
	errs := make(chan error, workers*allocsEach)
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < allocsEach; j++ {
				a, err := p.Allocate()
				if err != nil {
					errs <- err
					return
				}
				addrs <- a
			}
		}()
	}
	wg.Wait()
	close(addrs)
	close(errs)

	for err := range errs {
		t.Fatalf("concurrent Allocate error: %v", err)
	}

	// All returned addresses must be unique.
	seen := make(map[netip.Addr]struct{})
	for a := range addrs {
		if _, dup := seen[a]; dup {
			t.Errorf("duplicate address allocated: %s", a)
		}
		seen[a] = struct{}{}
	}

	if p.Used() != workers*allocsEach {
		t.Errorf("Used() = %d, want %d", p.Used(), workers*allocsEach)
	}
}

func TestInvalidCIDR(t *testing.T) {
	_, err := New("notacidr")
	if err == nil {
		t.Fatal("Expected error for invalid CIDR")
	}
}
