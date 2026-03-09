# Production Readiness Plan

**Source:** `docs/production-playbook.md`
**Created:** 2026-03-09
**Refined:** 2026-03-09 (iteration 2)
**Mode:** Fast

## Settings

- **Testing:** Yes
- **Logging:** Verbose (DEBUG)
- **Docs:** No

## Summary

Codebase analysis against the production playbook shows core server, client, deploy, and mobile functionality is **fully implemented**. Plan focuses on fixing gaps, hardening, wiring partially-implemented mobile features, and fixing broken tests.

**Removed from original plan:** API tests (Task #8) and config tests (Task #9) — already exist with comprehensive coverage (24 and 7 test functions respectively).

## Phase 1: Config & Hardening Fixes

| # | Task | Files | Status |
|---|------|-------|--------|
| 1 | Update root `server.example.yaml` to new auth schema (PSK → server_key + users_file) | `server.example.yaml` | done |
| 2 | Fix `simplevpn.service` — set `NoNewPrivileges=true` | `deploy/simplevpn.service` | done |

## Phase 2: Mobile App Gaps

| # | Task | Files | Status |
|---|------|-------|--------|
| 3 | Add transport/fingerprint fields to Dart VpnConfig model + dropdown selectors in settings UI | `vpn_config.dart`, `settings_screen.dart`, `vpn_service.dart` | done |
| 4 | Wire auto-reconnect toggle from Dart → platform + add exponential backoff (Android network monitoring + iOS on-demand already exist) | `vpn_service.dart`, `SimpleVpnService.kt`, `VpnPlugin.kt` | done |
| 5 | Implement Android kill switch + wire Dart toggle to both platforms (iOS `includeAllNetworks` already works) | `SimpleVpnService.kt`, `VpnPlugin.kt`, `vpn_service.dart` | done |

## Phase 3: Deploy Verification

| # | Task | Files | Status |
|---|------|-------|--------|
| 6 | Verify deploy.sh end-to-end flow matches playbook (all 6 steps) | `deploy/deploy.sh`, `setup-firewall.sh`, `entrypoint.sh` | done |
| 7 | Fix docker-compose.yml volume `:ro` conflict + add cert renewal automation | `docker-compose.yml` | done |

## Phase 4: Test Fixes & Coverage

| # | Task | Files | Status |
|---|------|-------|--------|
| 8 | Fix broken mobile tests — update PSK → login/password auth fields | `mobile/vpnlib/vpnlib_test.go`, `mobile/app/test/models/vpn_config_test.dart` | done |
| 9 | Add transport/fingerprint fields to Flutter tests | `mobile/app/test/models/vpn_config_test.dart` | done |

## Commit Plan

- **After Phase 1 (tasks 1-2):** `fix: update example config and harden systemd service`
- **After Phase 2 (tasks 3-5):** `feat(mobile): add transport/fingerprint settings, wire auto-reconnect and kill switch`
- **After Phase 3 (tasks 6-7):** `fix(deploy): fix docker-compose volumes and align deploy scripts with playbook`
- **After Phase 4 (tasks 8-9):** `test: fix broken mobile tests and add transport/fingerprint test coverage`

## What's Already Working

Based on deep codebase exploration, these are **fully implemented and tested**:
- Server: 8 CLI flags, config parsing with all fields (server_key, users_file, transport, API)
- Client: 10 CLI flags including transport, fingerprint, route-all
- Auth: FileStore with bcrypt hashing, user CRUD, enable/disable — 10 tests in store_test.go
- API: 10 endpoints (user CRUD, disable/enable, status, clients, disconnect, config) — 24 tests in api_test.go
- Config: YAML loading, defaults, validation — 7 tests in config_test.go
- Deploy: deploy.sh, entrypoint.sh, setup-firewall.sh, Dockerfile (Go 1.25, multi-stage), docker-compose.yml
- Mobile: vpnlib Go bindings (Connect/Disconnect/Status/Logs), Flutter app with QR scan + settings UI
- Mobile partial: Android auto-reconnect (ConnectivityManager), iOS kill switch (includeAllNetworks), iOS on-demand reconnect
