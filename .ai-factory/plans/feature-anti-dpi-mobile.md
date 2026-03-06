# Anti-DPI Mobile Transport Layer

**Branch:** `feature/anti-dpi-mobile`
**Created:** 2026-03-07
**Base branch:** `feature/vpn-platform`

## Settings

- **Testing:** Yes
- **Logging:** Verbose (DEBUG)
- **Documentation:** Yes

## Problem

Current protocol uses raw TLS on port 443. On mobile networks with aggressive DPI (ТСПУ, MTS, Megafon, Beeline):

1. **Go TLS fingerprint** — Go's `crypto/tls` ClientHello has a unique fingerprint, trivially detected by JA3/JA4
2. **No HTTP camouflage** — traffic inside TLS is not HTTP-shaped; DPI expects HTTP on 443
3. **Port restrictions** — mobile carriers may throttle/block suspicious traffic on specific ports
4. **No transport diversity** — single transport makes blocking easy: block the fingerprint = block all users

## Solution

### 1. Transport Abstraction Layer
Decouple tunnel from transport. `Transport` interface allows pluggable transports (raw TLS, WebSocket, future HTTP/2).

### 2. WebSocket Transport (primary for mobile)
VPN traffic wrapped in WebSocket binary frames over HTTPS:
- HTTP Upgrade looks like a normal browser connection
- After upgrade, binary frames are indistinguishable from any WebSocket app (chat, game, etc.)
- Same port 443, same TLS — but now looks like real web traffic
- Server auto-detects: WS upgrade vs raw TLS auth vs HTTP probe

### 3. uTLS Fingerprint Mimicry
Replace Go's TLS on client side with uTLS (refraction-networking/utls):
- Mimic Chrome/Firefox/Safari ClientHello exactly
- JA3 fingerprint matches a real browser
- Default: Chrome on Android, Safari on iOS

### 4. Multi-port Listening
Server can listen on multiple ports simultaneously (443, 80, 8080, etc.) — if carrier blocks one, another works.

## Architecture

```
Mobile App                                    Server
    |                                           |
    |  [uTLS ClientHello: Chrome fingerprint]   |
    |  ------TCP:443 TLS 1.3 Handshake-------> |
    |                                           |
    |  GET /ws HTTP/1.1                         |
    |  Upgrade: websocket                       |
    |  ---------------------------------------->|
    |                                           |  (detect: WS upgrade)
    |  <--- 101 Switching Protocols ----------- |
    |                                           |
    |  [WS Binary Frame: auth token (56B)]      |
    |  ---------------------------------------->|  (verify HMAC)
    |  <--- [WS Binary Frame: "OK"] ----------- |
    |                                           |
    |  [WS Binary: obfs(encrypt(IP packet))]    |
    |  <======================================> |  (tunnel active)
```

## Tasks

### Phase 1: Core Transport Layer (Tasks 1-4)

| # | Task | Files |
|---|------|-------|
| ~~1~~ | ~~Transport abstraction (interface + factory)~~ | ~~`pkg/transport/transport.go`~~ |
| ~~2~~ | ~~Raw TLS transport (extract existing logic)~~ | ~~`pkg/transport/rawtls/rawtls.go`~~ |
| ~~3~~ | ~~WebSocket transport (minimal RFC 6455)~~ | ~~`pkg/transport/ws/ws.go`, `ws/conn.go`, `ws/frame.go`~~ |
| ~~4~~ | ~~uTLS fingerprint mimicry~~ | ~~`pkg/transport/utlsdial/utls.go`~~ |

**Commit checkpoint:** `feat(transport): add transport abstraction with TLS, WebSocket, uTLS`

### Phase 2: Integration (Tasks 5-7)

| # | Task | Files |
|---|------|-------|
| ~~5~~ | ~~Config extensions~~ | ~~`pkg/config/config.go`~~ |
| ~~6~~ | ~~Server + client binary integration~~ | ~~`cmd/server-hardened/main.go`, `cmd/client-hardened/main.go`~~ |
| ~~7~~ | ~~Mobile vpnlib integration~~ | ~~`mobile/vpnlib/vpnlib.go`~~ |

**Commit checkpoint:** `feat(transport): integrate WS+uTLS into server, client, mobile`

### Phase 3: Tests & Docs (Tasks 8-9)

| # | Task | Files |
|---|------|-------|
| ~~8~~ | ~~Tests for transport packages~~ | ~~`pkg/transport/*_test.go`~~ |
| ~~9~~ | ~~Documentation update~~ | ~~`docs/architecture.md`, `docs/configuration.md`, `docs/security.md`~~ |

**Commit checkpoint:** `test+docs: transport layer tests and documentation`

## Dependencies

```
Task 1 (transport interface)
  ├── Task 2 (TLS transport)
  ├── Task 3 (WS transport)
  ├── Task 4 (uTLS)
  └── Task 5 (config)
        ├── Task 6 (server/client integration) ← also blocked by 2,3,4
        ├── Task 7 (mobile vpnlib) ← also blocked by 3,4
        └── Task 8 (tests) ← blocked by 2,3,4
              └── Task 9 (docs) ← blocked by 6,7
```

## New Dependencies (go.mod)

- `github.com/refraction-networking/utls` — uTLS for ClientHello mimicry
- No WebSocket library needed — minimal RFC 6455 implementation (avoids gomobile issues)

## Backward Compatibility

- Old clients (raw TLS) still work — server auto-detects transport
- Old QR codes without transport/fingerprint fields use defaults
- Default transport for new mobile clients: WebSocket + Chrome fingerprint
