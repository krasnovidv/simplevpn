# Plan: Android VPN Application

**Created:** 2026-03-06
**Mode:** Fast
**Branch:** feature/vpn-platform (existing)

## Settings

- **Testing:** Yes
- **Logging:** Verbose (DEBUG level throughout)
- **Docs:** BUILD.md for build process

## Overview

Complete the Android application for SimpleVPN. The Flutter scaffolding exists (UI screens, models, services) but the Android native layer is incomplete — missing AndroidManifest.xml, build.gradle, gomobile AAR integration, and the Kotlin↔Go wiring.

## Tasks

### Phase 1: Android Build Foundation

**Task 1: Set up Android build configuration** ✅
- Create AndroidManifest.xml with VPN permissions (BIND_VPN_SERVICE, INTERNET, FOREGROUND_SERVICE)
- Create/fix build.gradle.kts files (minSdk 21, targetSdk 34)
- Register SimpleVpnService with VPN intent filter
- Files: `mobile/app/android/`

**Task 2: Build gomobile AAR and integrate** ✅
- Build AAR via `make android` (gomobile bind)
- Copy to `android/app/libs/vpnlib.aar`
- Add flatDir + AAR dependency in build.gradle
- Blocked by: Task 1

### Phase 2: Native Integration

**Task 3: Wire Kotlin VPN service with gomobile** ✅
- Uncomment gomobile imports in SimpleVpnService.kt
- Wire `Vpnlib.connect(configJson, fd)` with TUN FD from `establish()`
- Wire `Vpnlib.disconnect()` and `Vpnlib.status()`
- Add verbose logging at every lifecycle step
- Blocked by: Tasks 1, 2

### Phase 3: Flutter Polish

**Task 4: Complete Flutter UI and state management** ✅
- Wire real VPN status polling (2s timer)
- Add error handling, loading states, config validation
- Replace sample logs with real event log
- Blocked by: Task 3

**Task 5: Add test server connection support** ✅
- Add `skip_verify` option to vpnlib Config for self-signed certs
- Test connection to 193.23.3.93:443
- Blocked by: Task 3

### Phase 4: Quality & Ship

**Task 6: Write unit and integration tests** ✅
- Dart: VpnConfig, ConfigStorage, VpnService, HomeScreen widget tests
- Go: vpnlib config parsing, status transitions
- Blocked by: Task 4

**Task 7: Build release APK and document** ✅
- Build debug + release APKs
- Create mobile/BUILD.md with full instructions
- Blocked by: Tasks 4, 5

## Commit Plan

**Commit 1** (after Tasks 1-2): `feat(android): add build configuration and gomobile AAR integration`
**Commit 2** (after Task 3): `feat(android): wire Kotlin VPN service with gomobile bindings`
**Commit 3** (after Tasks 4-5): `feat(android): complete Flutter UI and test server support`
**Commit 4** (after Tasks 6-7): `test(android): add tests and build documentation`
