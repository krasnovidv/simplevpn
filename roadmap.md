# SimpleVPN Roadmap

## Phase 1 — Mobile Client (Android) ✅

- [x] 1.1 Flutter app scaffold (home, settings, log screens)
- [x] 1.2 gomobile VPN library (Go → Android)
- [x] 1.3 Android VpnService integration
- [x] 1.4 QR code config scanner
- [x] 1.5 Server address IP:port validation
- [x] 1.6 WebSocket transport (anti-DPI) + WS frame framing fix

## Phase 2 — Multi-user (shared server) ✅

- [x] 2.1 Per-client IP pool (`pkg/ippool`, `client_subnet` config)
- [x] 2.2 Per-client session map + IPv4-destination packet routing (removes single-client chokepoint)
- [x] 2.3 Duplicate relay goroutine fix (extra listeners no longer spawn extra relay loops)
- [x] 2.4 Extended auth protocol: `"OK <ip>/<prefix>\n"` (breaking change vs 1.0.x clients)
- [x] 2.5 Android uses server-assigned TUN IP (no more hardcoded 10.0.0.2/24)
- [x] 2.6 API client lifecycle wired: RegisterClient, UpdateClientStats, disconnect callback
- [x] 2.7 Mobile admin UI: user CRUD, connected clients, server status, QR generator
- [x] 2.8 Admin settings in mobile app (URL, bearer token, skip-verify)
- [x] 2.9 Tunnel write-mutex (fixes relay+keepalive concurrent-Send race)

## Phase 3 — iOS client

- [ ] 3.1 iOS PacketTunnelProvider integration
- [ ] 3.2 iOS Network Extension entitlements
- [ ] 3.3 gomobile iOS build pipeline

## Phase 4 — Resilience & UX

- [ ] 4.1 Auto-reconnect with exponential backoff
- [ ] 4.2 Kill switch (block non-VPN traffic on disconnect)
- [ ] 4.3 Split tunneling configuration
- [ ] 4.4 Traffic statistics UI (bytes in/out per session)

## Phase 5 — Distribution

- [ ] 5.1 F-Droid build metadata
- [ ] 5.2 Play Store listing
- [ ] 5.3 Automated release pipeline

---

Phase 3 next.
