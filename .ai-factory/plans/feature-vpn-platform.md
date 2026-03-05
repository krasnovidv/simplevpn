# VPN Platform — Server + Mobile Apps

**Branch:** `feature/vpn-platform`
**Created:** 2026-03-05
**Description:** Build a complete VPN platform: production-ready VPS server with web admin panel, and Flutter mobile apps (iOS + Android) using the existing DPI-resistant protocol.

## Settings

| Setting  | Value                     |
|----------|---------------------------|
| Testing  | Yes                       |
| Logging  | Verbose (DEBUG)           |
| Docs     | No                        |
| Mobile   | Flutter (iOS + Android)   |
| Features | Auto-reconnect, Kill switch, QR config, Web admin |

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   VPS Server                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐ │
│  │ VPN Core │  │ Mgmt API │  │  Web Admin    │ │
│  │ (TLS+TUN)│  │ (:8443)  │  │  (embedded)   │ │
│  └────┬─────┘  └────┬─────┘  └───────┬───────┘ │
│       │              │                │          │
│  ┌────┴──────────────┴────────────────┴───────┐ │
│  │         pkg/tunnel + pkg/config             │ │
│  │         pkg/crypto + pkg/obfs               │ │
│  │         pkg/replay + pkg/tlsdecoy           │ │
│  └─────────────────────────────────────────────┘ │
│                   Docker / systemd               │
└─────────────────────────────────────────────────┘
                        │
                   TLS 1.3 :443
                        │
┌─────────────────────────────────────────────────┐
│              Flutter Mobile App                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐ │
│  │  UI/UX   │  │ QR Scan  │  │  Settings     │ │
│  │ (Dart)   │  │ (Camera) │  │  Kill Switch  │ │
│  └────┬─────┘  └──────────┘  └───────────────┘ │
│       │                                          │
│  ┌────┴─────────────────────────────────────┐   │
│  │    Platform Channel (Method Channel)      │   │
│  └────┬─────────────────────────────┬───────┘   │
│       │                             │            │
│  ┌────┴─────────┐  ┌──────────────┴──────────┐ │
│  │ iOS           │  │ Android                  │ │
│  │ NEPacketTunnel│  │ VpnService               │ │
│  │ + Go .xcframe │  │ + Go .aar                │ │
│  └───────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## Tasks

### Phase 1: Core Refactoring (Server Foundation)

| # | Task | Files | Blocked By |
|---|------|-------|------------|
| 1 | ~~Extract shared VPN protocol library (pkg/tunnel)~~ | `pkg/tunnel/*.go` | — | [x] |
| 8 | ~~Add YAML config file support to server~~ | `pkg/config/*.go`, `cmd/server-hardened/main.go` | #1 | [x] |

### Phase 2: Server Features (API + Deployment)

| # | Task | Files | Blocked By |
|---|------|-------|------------|
| 6 | ~~Add management REST API to server~~ | `pkg/api/*.go` | #1, #8 | [x] |
| 7 | ~~Create Docker deployment setup for VPS~~ | `Dockerfile`, `docker-compose.yml`, `deploy/` | #8 | [x] |
| 3 | ~~Build web admin panel (embedded SPA)~~ | `pkg/api/web/`, `pkg/api/embed.go` | #6 | [x] |

### Phase 3: Mobile Library + Flutter App

| # | Task | Files | Blocked By |
|---|------|-------|------------|
| 5 | ~~Build Go mobile library with gomobile~~ | `mobile/vpnlib/*.go`, `mobile/Makefile` | #1 | [x] |
| 10 | ~~Create Flutter project scaffold + platform channels~~ | `mobile/app/` | #5 | [x] |
| 2 | ~~Implement Flutter UI — MVP screens~~ | `mobile/app/lib/` | #10 | [x] |
| 9 | ~~Implement kill switch (iOS + Android)~~ | native code + Flutter | #10 | [x] |

### Phase 4: Testing

| # | Task | Files | Blocked By |
|---|------|-------|------------|
| 4 | ~~Write tests for core packages and API~~ | `*_test.go` | #1, #8, #6, #5 | [x] |

## Commit Plan

| Checkpoint | After Tasks | Commit Message |
|------------|-------------|----------------|
| 1 | #1, #8 | `feat: extract shared tunnel library and add config support` |
| 2 | #6, #7 | `feat: add management API and Docker deployment` |
| 3 | #3 | `feat: add embedded web admin panel` |
| 4 | #5, #10 | `feat: add gomobile library and Flutter scaffold` |
| 5 | #2, #9 | `feat: implement Flutter UI, QR config, and kill switch` |
| 6 | #4 | `test: add comprehensive test coverage` |

## Key Decisions

1. **gomobile** for Go→mobile bridge (proven approach, used by Tailscale/WireGuard)
2. **Flutter** for cross-platform UI (single codebase, good perf)
3. **Embedded web admin** (no separate frontend deploy, single binary)
4. **Config via QR** — JSON payload: `{"server":"host:443","psk":"...","sni":"domain"}`
5. **Kill switch** via OS-native VPN APIs (NEPacketTunnelProvider / VpnService)
6. **MVP first** — connect/disconnect works before adding polish
