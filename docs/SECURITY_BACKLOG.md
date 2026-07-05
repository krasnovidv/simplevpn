# Security & Performance Backlog

This document captures the higher-risk findings that require a **coordinated
rollout** (protocol/format changes that would break already-deployed 1.4.8
clients) or larger refactors. They were deliberately **not** shipped as
drop-in changes because doing so silently would break live users. Items are
ordered by severity.

Everything in this file was surfaced by the 2026-07-05 deep audit. The
lower-risk fixes from that audit have already been applied to the branch.

---

## 1. CRITICAL — OTA update signing is symmetric (forgeable → RCE on devices)

**Where:** `pkg/api/update.go` (`updateSigningKey` / `signUpdate`), mobile
`update_verifier`.

**Problem:** the update manifest is signed with
`HMAC(SHA256(server_key || "update-signing"))`. Every client holds `server_key`,
so **every subscriber can derive the signing key and forge a manifest**. The
update channel also disables TLS verification, so this HMAC is the *only* thing
standing between an on-path attacker and pushing a trojaned APK to every device.
This is a remote-code-execution-class issue gated only on the shared PSK.

**Fix (breaking — needs a migration):**
1. Generate an **Ed25519** keypair server-side. Keep the private key in a new
   config field (`update_signing_key`), separate from `server_key`.
2. Bake the **public** key into the app at build time.
3. Sign the manifest body with `ed25519.Sign`; verify on-device with the
   embedded public key. Drop the HMAC path.
4. Re-enable TLS verification on the update channel (defense in depth).

**Migration:** ship one transitional app version that accepts *either* the old
HMAC or the new Ed25519 signature, roll it out via the (still-HMAC) OTA channel,
then cut over to Ed25519-only once telemetry shows old clients are gone.

---

## 2. CRITICAL — replay protection is dead code; nonces are random

**Where:** `pkg/tunnel/tunnel.go` (`replay.New()` / `ReplayWindow()` are never
checked in the live path), `pkg/crypto/crypto.go` (random 96-bit nonce),
`pkg/obfs/obfs.go` (random seed).

**Problem:** the wire format carries **no sequence number**, so `replay.Window`
can't be used and isn't — the whole `pkg/replay` package is inert. Separately,
the AES-256-GCM key is derived only from the static `server_key`, is **identical
for every client**, and never rotates. With random 96-bit nonces under one
fleet-wide key, the safe-usage bound (~2³² packets, NIST SP 800-38D) is
aggregated across *all* clients and *all* time; a nonce collision leaks
plaintext XOR and forgery material.

**Fix (breaking — wire-format change):** replace the random nonce with a
**counter nonce**: `session_prefix(4B) || packet_counter(8B)`, and derive a
**per-session key** via HKDF over `server_key` + a random per-session salt
exchanged at auth. This single change:
- gives per-client key isolation + forward secrecy,
- eliminates the fleet-wide nonce-collision risk,
- makes the counter the replay sequence number, so `replayWin.Check(counter)`
  finally does something,
- removes the two hottest `crypto/rand` reads per packet (see §5).

---

## 3. HIGH — public endpoints defeat active-probe resistance

**Where:** `pkg/api/api.go` (always-on plain-HTTP server), `pkg/api/join.go`,
`pkg/api/download.go`.

**Problem:** the point of `pkg/tlsdecoy` is to look like nginx to censors, but
`/join` (titled "RKNPNH — Подключение", with a download button),
`/download/simplevpn.apk`, and `/api/update` are served unauthenticated on
:8080/:8443. A prober instantly fingerprints the host as a VPN server. `/join`
also carries the full config (incl. PSK) in the URL fragment over plaintext
HTTP, so an on-path attacker can rewrite the page's JS to exfiltrate it.

**Fix (needs product decision):**
- Add an `http_enabled` config flag (default **off**); serve `/join` and
  `/download/` only over the TLS listener when possible.
- Gate `/join` behind an unguessable path token, or move it to a separate
  domain / CDN so probing the VPN IP reveals nothing.
- Show the APK SHA-256 on the join page so browser-side installs are verifiable
  (in-app OTA already checks `apk_sha256`; the browser download does not).

Already applied on the branch: rate-limiting + `%q` log-injection hardening on
these endpoints, and a `Referrer-Policy: no-referrer` header so the fragment
isn't leaked via `Referer`.

---

## 4. MEDIUM — first-connect VPN consent dead-ends the in-app flow

**Where:** `mobile/.../VpnPlugin.kt` (`startVpn` → `startActivityForResult`),
`MainActivity.kt` (no `onActivityResult`).

**Problem:** the very first connect fires the system VPN-consent dialog and
returns error `VPN_PERMISSION`, but nothing handles the activity result, so the
UI shows a red "connection error" and the user must guess to tap again. (The
home-screen widget path handles this correctly; the in-app path does not.)

**Fix:** implement `ActivityResultListener` in `VpnPlugin`, register it via
`binding.addActivityResultListener` in `onAttachedToActivity`, stash the pending
connect params, and on `RESULT_OK` start the service + emit `connecting`.
Dart-only stopgap: catch `PlatformException(code == 'VPN_PERMISSION')` in
`VpnService.connect` and surface a distinct "grant VPN and tap again" status
instead of a generic error.

---

## 5. Performance — packet hot path (server throughput)

**Where:** `pkg/crypto`, `pkg/obfs`, `pkg/transport/ws/frame.go`,
`pkg/tunnel/frame.go`, `cmd/server-hardened/main.go`,
`cmd/client-hardened/main.go`.

Ranked, each is a concrete change:

1. **Per-packet `crypto/rand` draws** — up to 4 RNG reads + a `big.Int` alloc
   per packet (`obfs.go` uses `rand.Int(big.NewInt(MaxPad+1))` just to pick a
   0–255 pad length). Fold into the counter-nonce work (§2) and derive pad
   length from one cheap byte. Biggest single throughput win on send.
2. **Per-packet heap allocations** despite the tunnel's reusable buffers —
   `WriteFrame` `make`s a fresh slice and ignores `t.frameBuf`; `obfs.xorStream`
   allocates output + rebuilds a ChaCha20 cipher every packet; WS
   `writeFrame`/`readFrame` allocate per call. Introduce `sync.Pool`s / reuse
   fields; target zero steady-state allocs.
3. **Single-goroutine server relay** (`tunToClientRelay`) serializes all
   outbound crypto through one goroutine; a slow client head-of-line-blocks the
   whole fleet. Move to per-session send workers with bounded queues.
4. **No buffered reader server-side** — `tunnel.New(conn)` reads the raw TLS
   conn twice per packet (length, then body). Wrap in a `bufio.Reader` (the
   mobile client already does).
5. **Client injects up to 5 ms `time.Sleep` per packet** (`-jitter`), capping
   throughput at ~200 pps. Default to 0 or sample a small fraction of packets.
6. **Redundant double framing on WS** — the inner 4-byte length prefix
   duplicates the WS frame boundary; drop it on the WS transport.

---

## 6. Other applied vs. deferred

**Applied on this branch (low risk):** WS negative-length DoS panic fix +
regression test; server-goroutine `recover()`; constant-time auth (username
enumeration); `pkg/crypto` test suite; API `ReadHeaderTimeout`/`IdleTimeout`,
graceful `Shutdown(ctx)`, `/healthz`, security headers, public-endpoint rate
limiting, bcrypt 72-byte password cap; Docker EOL-alpine bump + HEALTHCHECK;
CI quality gates; activated Flutter lints; Flutter dead stats-poller gating,
EventLog bound, `VpnService` dispose hardening, footer 60 Hz → repaint-driven.

**Deferred (needs product/coord):** §1–§4 above, plus: force-disconnect live
sessions on user disable/delete (`handleDisableUser` only flips a flag today);
move plaintext widget-config cache to `EncryptedSharedPreferences`; localize
remaining English strings shown during connection trouble; add `Semantics` to
the main connect control for TalkBack; drop the unused `flutter_riverpod` /
`fl_chart` deps or adopt them.
