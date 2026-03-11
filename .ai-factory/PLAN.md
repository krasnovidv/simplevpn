# Plan: Server Address Validation (IP:port)

**Mode:** Fast
**Created:** 2026-03-09

## Settings

- **Testing:** No
- **Logging:** Verbose (DEBUG logs in validator)
- **Docs:** No

## Requirements

Add validation for the server address field in the Flutter app config:
- Server address must be a valid IPv4 address with port (e.g. `192.168.1.1:443`)
- Show validation error inline under the input field in SettingsScreen
- Disable the Connect button on HomeScreen when server address is invalid

## Tasks

### Phase 1: Validation Logic

| # | Task | Files | Status |
|---|------|-------|--------|
| 1 | Add IP:port validation helper | `mobile/app/lib/utils/validators.dart` (new) | done |

### Phase 2: UI Integration (blocked by Task 1)

| # | Task | Files | Status |
|---|------|-------|--------|
| 2 | Add inline validation to server address field | `mobile/app/lib/screens/settings_screen.dart` | done |
| 3 | Disable Connect button when server address is invalid | `mobile/app/lib/screens/home_screen.dart` | done |

## Implementation Details

### Task 1 — Validation Helper
- Create `mobile/app/lib/utils/validators.dart`
- Function: `String? validateServerAddress(String value)` — returns null if valid, error string if not
- IPv4 only: 4 octets (0-255), colon, port (1-65535)
- Add DEBUG logging for invalid input (log the reason, not the value)

### Task 2 — Inline Validation in SettingsScreen
- Convert server TextField → TextFormField or use `onChanged` + `errorText`
- Add `_serverError` state variable, update on every text change
- Show error text inline below the field immediately as user types

### Task 3 — Disable Connect Button
- After loading config, validate server address using shared validator
- Add condition to disable Connect button if server address is invalid
- Update existing `_validateConfig()` to use shared validator for consistency
