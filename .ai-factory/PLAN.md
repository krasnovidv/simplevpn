# Plan: Fix VPN Connection Logging & Status Bug

**Created:** 2026-03-06
**Mode:** Fast
**Branch:** feature/vpn-platform (existing)

## Settings

- **Testing:** No
- **Logging:** Verbose
- **Docs:** No

## Problem

App shows no logs when trying to connect to server. Root causes:
1. `SimpleVpnService.kt:114` sets `currentStatus = "connected"` before Go actually connects
2. Go-side logs (`log.Printf`) go to logcat only, never reach Flutter UI
3. Connection errors from Go thread aren't surfaced to the app
4. Insufficient logging at Flutter/Kotlin layers

## Tasks

### Phase 1: Go Log Buffer

- [x] Task 8: Add Go-side log buffer and expose via `Logs()` gomobile function

### Phase 2: Kotlin Fixes

- [x] Task 9: Fix premature "connected" status bug + add Go log fetching in Kotlin
  - Blocked by: Task 8

### Phase 3: Flutter Logging

- [x] Task 10: Surface Go/native logs in Flutter UI + extend Dart logging
  - Blocked by: Tasks 8, 9

### Phase 4: Build & Install

- [x] Task 11: Build AAR, build APK, install on phone
  - Blocked by: Tasks 8, 9, 10

## Commit Plan

Single commit after all tasks: `fix(mobile): extend logging, fix status bug, surface Go logs in UI`
