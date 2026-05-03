# Phase 4 — Device Test Plan

Manual verification checklist for Phase 4 invariants that unit tests cannot prove.
Each scenario lists steps, pass criteria, and which patch/mechanism it guards.

---

## 1. Kill switch holds during retry

**Guards:** patch `2026-03-09-18.30` (TUN fd reuse), Android `builder.establish()` single-call invariant.

**Steps (Android):**
1. Enable kill switch + auto-reconnect in Settings.
2. Connect to VPN — verify "Protected" state.
3. Toggle airplane mode ON for 10 seconds, then OFF.
4. While reconnecting, open a terminal app and run `curl https://1.1.1.1`.
5. Observe that `curl` times out / fails — traffic is blocked.
6. Wait for VPN to reconnect successfully.
7. Re-run `curl https://1.1.1.1` — should succeed.

**Pass criteria:**
- [ ] `curl` fails during all retry attempts (no traffic leak).
- [ ] Status shows "Reconnecting..." with attempt counter.
- [ ] After reconnection, traffic flows normally.

**Steps (iOS 14.2+):**
1. Enable kill switch in Settings.
2. Connect, then kill the VPN server process.
3. Open Safari and try to load any page — should fail.
4. Restart server, wait for auto-reconnect.
5. Safari loads pages after reconnect.

**Pass criteria:**
- [ ] No traffic during retry window.
- [ ] `includeAllNetworks` persists across reconnect settings re-application.

---

## 2. Auth-fail short-circuit

**Guards:** retry counter does NOT advance on `auth` kind.

**Steps:**
1. Connect with valid credentials — verify connected.
2. On the server, revoke PSK (change `server_key` in config and restart).
3. Disconnect and reconnect from the app.
4. Observe status changes.

**Pass criteria:**
- [ ] Client shows "error: auth rejected" after exactly 1 attempt.
- [ ] No further retry attempts are made (counter stays at 0 or 1).
- [ ] App is responsive — no "Reconnecting..." loop.

---

## 3. TUN fd identity across retries (Android)

**Guards:** patch `2026-03-09-18.30` — second `establish()` invalidates live TUN fd → phone reboot.

**Steps:**
1. Enable auto-reconnect, connect successfully.
2. Run `adb shell ip link show tun0` — note the `ifindex`.
3. Kill the VPN server to trigger disconnection.
4. Wait through 3+ retry attempts.
5. Run `adb shell ip link show tun0` again after each retry.

**Pass criteria:**
- [ ] `ifindex` is identical across all retry attempts (same TUN interface reused).
- [ ] No "new TUN interface created" log entry during retries.
- [ ] `builder.establish()` is NOT called during retry loop (check logcat for absence of "VpnBuilder.establish").

---

## 4. Split-tunnel: allowlist (Android) & routes (iOS)

**Android (per-app):**
1. Set mode = Allowlist, add only the browser app.
2. Connect to VPN.
3. In browser: visit `ifconfig.me` → should show VPN IP.
4. In a non-allowlisted app (e.g., curl via Termux): visit `ifconfig.me` → should show real IP.

**iOS (per-route):**
1. Set mode = Blocklist, add `192.168.0.0/16`.
2. Connect to VPN.
3. `ping 192.168.1.1` (LAN) → should use direct route (bypass VPN).
4. `curl ifconfig.me` → should show VPN IP.

**Pass criteria:**
- [ ] Android: only allowlisted apps see VPN.
- [ ] iOS: excluded routes bypass the tunnel.
- [ ] Empty allowlist treated as full tunnel (no black-hole).

---

## 5. Stats reset on reconnect

**Guards:** sparkline doesn't show negative spike after counter reset.

**Steps:**
1. Connect and transfer some data (browse a few pages).
2. Observe sparkline shows activity and cumulative counter increases.
3. Kill server to trigger reconnect.
4. Observe sparkline freezes with "Reconnecting…" overlay.
5. Restart server, wait for reconnect.
6. Observe sparkline restarts from zero without negative spike.

**Pass criteria:**
- [ ] Sparkline freezes (no gaps or jumps) during reconnect.
- [ ] After reconnect, cumulative counters start fresh.
- [ ] No negative delta shown in sparkline.

---

## 6. Background polling — no zombie timers

**Guards:** patch `2026-03-09-18.30` (lifecycle observer pauses polling).

**Steps:**
1. Connect to VPN.
2. Verify stats sparkline is updating (1 Hz).
3. Press Home (background the app) for 60 seconds.
4. Check battery usage / logcat for VPN service — should show no stats polling.
5. Return to app.
6. Verify sparkline resumes (may show a gap, but no crash or zombie timer).

**Pass criteria:**
- [ ] No `getStats` IPC calls in logcat while backgrounded.
- [ ] No `_pollStats` Dart log entries while backgrounded.
- [ ] Sparkline resumes smoothly on foreground.
- [ ] Battery usage of the app is minimal during background period.
