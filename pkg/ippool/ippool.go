// Package ippool manages a pool of IP addresses allocated to VPN clients.
package ippool

import (
	"errors"
	"fmt"
	"log"
	"net/netip"
	"sync"
)

// ErrPoolExhausted is returned when no free addresses remain in the pool.
var ErrPoolExhausted = errors.New("ip pool exhausted")

// Pool manages IP address allocation within a CIDR block.
// The network address and broadcast address are automatically reserved.
// Additional addresses (e.g. the server's own TUN IP) can be reserved via New.
type Pool struct {
	mu        sync.Mutex
	prefix    netip.Prefix
	reserved  map[netip.Addr]struct{}
	allocated map[netip.Addr]struct{}
}

// New creates a Pool for the given CIDR string, reserving the listed addresses.
// reserved typically contains the server's own TUN IP.
func New(cidr string, reserved ...netip.Addr) (*Pool, error) {
	prefix, err := netip.ParsePrefix(cidr)
	if err != nil {
		return nil, fmt.Errorf("parse cidr %q: %w", cidr, err)
	}
	prefix = prefix.Masked()

	res := make(map[netip.Addr]struct{})
	// Reserve network address and broadcast.
	res[prefix.Addr()] = struct{}{}
	res[lastAddr(prefix)] = struct{}{}

	for _, a := range reserved {
		res[a] = struct{}{}
	}

	p := &Pool{
		prefix:    prefix,
		reserved:  res,
		allocated: make(map[netip.Addr]struct{}),
	}
	log.Printf("[ippool] New pool: cidr=%s reserved=%d capacity=%d", cidr, len(res), p.capacity())
	return p, nil
}

// Allocate returns the next free address in the pool.
func (p *Pool) Allocate() (netip.Addr, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	for addr := p.prefix.Addr(); p.prefix.Contains(addr); addr = addr.Next() {
		if _, res := p.reserved[addr]; res {
			continue
		}
		if _, used := p.allocated[addr]; used {
			continue
		}
		p.allocated[addr] = struct{}{}
		log.Printf("[ippool] DEBUG allocated %s  used=%d/%d", addr, len(p.allocated), p.capacity())
		return addr, nil
	}

	log.Printf("[ippool] DEBUG pool exhausted  used=%d/%d", len(p.allocated), p.capacity())
	return netip.Addr{}, ErrPoolExhausted
}

// Release returns addr back to the pool.
func (p *Pool) Release(addr netip.Addr) {
	p.mu.Lock()
	defer p.mu.Unlock()

	delete(p.allocated, addr)
	log.Printf("[ippool] DEBUG released %s  used=%d/%d", addr, len(p.allocated), p.capacity())
}

// Prefix returns the CIDR prefix this pool manages.
func (p *Pool) Prefix() netip.Prefix { return p.prefix }

// Size returns the total number of allocatable addresses (excluding reserved).
func (p *Pool) Size() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.capacity()
}

// Used returns the number of currently allocated addresses.
func (p *Pool) Used() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.allocated)
}

// capacity is the usable pool size; must be called with mu held.
func (p *Pool) capacity() int {
	count := 0
	for addr := p.prefix.Addr(); p.prefix.Contains(addr); addr = addr.Next() {
		if _, res := p.reserved[addr]; !res {
			count++
		}
	}
	return count
}

// lastAddr returns the broadcast (last) address of an IPv4 prefix.
func lastAddr(prefix netip.Prefix) netip.Addr {
	a4 := prefix.Addr().As4()
	ones := prefix.Bits()
	for i := ones; i < 32; i++ {
		a4[i/8] |= 1 << (7 - uint(i%8))
	}
	return netip.AddrFrom4(a4)
}
