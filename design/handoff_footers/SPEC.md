# RKNPNH — Status Widget (footer) system · Claude Code handoff

This bundle covers the **status widget** that lives under the connect button on the main screen — the area that used to show plain up/down speed meters. It is now a **swappable, playful graphic** with five styles plus an in-app setting to pick one or get a **random one each launch**.

## What's in this bundle
- `footer-variants.jsx` — **the source of truth** for all five footer components (`FooterMap`, `FooterReceipt`, `FooterPet`, `FooterMonster`, `FooterTugWar`). Read this for exact geometry, timing, and palette use.
- `main-screens.jsx` — contains the wiring you need to port: `FooterRender` (id → component switch), `useFooterSetting` (preference + random resolution), `SettingsSheet` (the in-app picker), `FOOTER_OPTIONS` / `RANDOM_POOL` (the catalog), and how the gear icon opens settings. Search for those names.
- `RKNPNH Main Screen.html` — open in a browser to play with all of it (Tap a phone's stamp to run the connect flow; tap the **gear** top-right to open Settings).

> These are **design references in HTML/React-via-Babel**, not production code to paste. Recreate them in your app's real environment (React Native, SwiftUI, Compose, Flutter, web, …) using its own patterns. The HTML is the source of truth for *what it looks like and how it behaves*.

## The slot contract
Every footer is a self-contained component that receives exactly two inputs:

```ts
type ConnState = 'idle' | 'connecting' | 'connected' | 'disconnecting';
function Footer(props: { state: ConnState; secs: number }): View
```
- `state` — the VPN connection state machine (already exists on the main screen).
- `secs` — seconds connected (0 unless `connected`). Drives uptime readouts.

No footer takes real network metrics — the numbers are **theatre** (mood, not telemetry). Treat them as decorative. If you later want real bytes, they map naturally (see each footer's “real-data hook” note below), but the brief is personality, not a dashboard.

Lives in the existing footer card slot: full width minus 20px page gutters, sits above the home indicator. Card chrome: `rgba(255,255,255,0.04)` fill, `1px #2A1F3A` border, radius 18, padding 14, `backdrop-blur`.

## Palette (shared by every footer)
| token     | hex       | use                                   |
|-----------|-----------|---------------------------------------|
| bg        | `#120A1F` | screen background                     |
| bgDeep    | `#0A0612` | inset panels / tank / map / terminal  |
| magenta   | `#FF2BD6` | brand primary, YOU, exposed/active    |
| magentaHi | `#FF5CE0` | hover / emphasis                      |
| cyan      | `#00F0FF` | connected / success / route           |
| cyanHi    | `#7AF6FF` | secondary cyan accents                |
| green     | `#7CFF8E` | pet "gleeful"                         |
| yellow    | `#FFF200` | "straining" / connecting warnings     |
| red       | `#FF4F6D` | danger / exposed / defeated           |
| white     | `#F5F3FF` | primary text                          |
| dim       | `#5A4A7A` | secondary text                        |
| dim2      | `#2A1F3A` | borders / dividers                    |
| paper     | `#F3ECD8` | receipt paper                         |
| paperInk  | `#1A1410` | receipt text                          |

Fonts: **Archivo Black** (display), **Space Grotesk** (UI), **JetBrains Mono** (labels/numbers).

---

## The five footers
Brief intent + state behavior for each. **Exact drawing/animation is in `footer-variants.jsx` — port from there, don't reinvent from this summary.**

### 1. Tug of War — `FooterTugWar`  *(default / hero)*
The brand line made literal: **YOU** (magenta scrapper) vs **THE WATCHER** (a surveillance eyeball on legs) hauling a rope across the **firewall** line. Your traffic is ground you reel in.
- A `pos` value runs −1 (you fully win) … +1 (watcher wins), eased toward a target each frame. Data packets travel down the rope toward you; each arrival nudges `pos` negative and bumps **REELED IN** MB.
- **idle** → target +0.55, `OUTGUNNED`, watcher dragging you back. **connecting** → target 0, `TAKING THE STRAIN…`, dead even. **connected** → eases to −0.92, marker crosses the firewall, `WINNING`; at ≤ −0.86 → `FLAWLESS` and the Watcher tips over, eyes X-ed out.
- Readouts: REELED IN (MB), ADVANTAGE (%), a YOU/THEM bar, uptime “HELD”.
- Real-data hook: `pos` velocity ∝ download throughput; REELED IN = cumulative bytes down.

### 2. Traffic Gremlin — `FooterMonster`
A hungry pixel gremlin in a feeding tank. Download packets fly in from the right; it **chomps** them (↓ EATEN), its **belly** fills, then it **burps** them back as upload (↑ BURPED).
- **idle** `STARVING` + 💤, asleep. **connecting** `WAKING UP`, packets start. **connected** `MUNCHING`/`NOM NOM`, body bulges with belly; `STUFFED` past 75%.
- Real-data hook: spawn rate ∝ download rate; EATEN = bytes down; BURPED = bytes up.

### 3. ASCII Route — `FooterMap`
A monospaced map of your hops `YOU → AMS → STO → OSL → REY`. Relays light in sequence; the exit pulses. (Already separately spec'd; full detail in `footer-variants.jsx → FooterMap`.)
- **idle** direct/no trail, **connecting** builds at 220ms cadence, **connected** full obfuscated route, exit `REY 🇮🇸`, live uptime.

### 4. Denial Receipt — `FooterReceipt`
A dot-matrix receipt feeds out of a printer slot and prints line-by-line on connect: IP REVOKED / IDENTITY ERASED / LOCATION REYKJAVÍK / TRACKERS DENIED, ending in a tilted magenta **★ NOT APPROVED ★** stamp, then live TRACKERS DENIED / DECOYS SENT counters.
- **idle** `— VOID —` stub, **connecting** `PRINTING…`, **connected** prints + counters tick.

### 5. Ghost Pet — `FooterPet`
A pixel mascot ("GHOST") = your anonymity. Mood: exposed → hopeful → safe → gleeful. ANONYMITY and VIBES bars fill while connected; hearts when safe; sleepy `z` when idle.
- Real-data hook: ANONYMITY ∝ time connected; could reflect leak-test status.

---

## The Setting: pick one, or random each launch

### Behavior
The user chooses their status-widget style in **Settings**:
- **Fixed** — one of the five (Tug of War, Traffic Gremlin, ASCII Route, Denial Receipt, Ghost Pet), or the legacy **Classic Speeds** meters.
- **🎲 Random each launch** — on every app launch the widget is a randomly chosen concrete footer from `RANDOM_POOL` (the five playful ones; Classic Speeds excluded). Persist the *mode* (`random`), not the rolled result, so each cold start surprises.

Persistence: store the chosen footer id (or `'random'`) in user settings/prefs. Default ships as **Tug of War** (`tug`).

### Catalog (`FOOTER_OPTIONS` in `main-screens.jsx`)
```
random  🎲 Random each launch   — Surprise me every session
tug     Tug of War              — You vs the Watcher
monster Traffic Gremlin         — It devours your packets
map     ASCII Route             — Live hop map of the tunnel
receipt Denial Receipt          — Your paperwork, printed
pet     Ghost Pet               — Your anonymity, kept alive
speed   Classic Speeds          — Plain up / down meters
RANDOM_POOL = [tug, monster, map, receipt, pet]
```

### Resolution logic (`useFooterSetting`)
```
pref = stored setting (default 'tug')
resolved = (pref === 'random') ? rolledConcreteFooter : pref
// roll once at launch; in the prototype it also re-rolls on each
// idle→connecting transition so you can see the variety. In production,
// "each launch" = each cold start is enough.
render <FooterRender kind={resolved} state secs/>
```
`FooterRender` is a simple switch from id → component (see `main-screens.jsx`). Falls back to Classic Speeds for `speed`/unknown.

### Settings entry point & UI
- Entry: the **gear icon** in the main-screen header opens the settings sheet (`onGear` → open). In production this can live wherever your Settings live; the sheet is just the relevant control.
- `SettingsSheet` (see `main-screens.jsx`): a bottom sheet titled **STATUS WIDGET** / "what lives under the button", a grab handle, a **DONE** dismiss, and a vertical list of option rows. Each row: leading indicator (🎲 for random, else a square radio that fills magenta when active), bold name + dim description, trailing ✓ when selected. Active row tinted `rgba(255,43,214,0.10)` with a magenta border. When **Random** is active it shows `→ <currently rolled footer name>` in cyan so the user knows what they'll get.

---

## Acceptance
- All five footers render and animate across `idle → connecting → connected → disconnecting`; none show a pre-animation blank in print/reduced-motion.
- Settings lets the user pick any footer or Random; choice persists across launches.
- Random yields a different concrete footer across launches (pool of 5).
- Footer numbers are decorative; no footer blocks the connect tap target.
- Palette + fonts match the table above.

Questions welcome — better to clarify than guess.
