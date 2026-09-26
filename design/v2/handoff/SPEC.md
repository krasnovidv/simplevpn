# RKNPNH — Main Screen + Connect Animation Handoff

## What this is
Reference prototype for the **rknpnh** VPN app's main screen. Two HTML files in this folder are the source of truth:

- `RKNPNH Main Screen.html` — the main screen with 3 variants (use **#01 Stamped**)
- `RKNPNH Connect Animation.html` — the standalone connect animation (the one that plays during `connecting` → first beats of `connected`)

Open both in a browser to see the actual motion. Don't try to read the JSX cold — watch them run first.

## What to build

A single main screen with this state machine:

```
idle  ──tap──▶  connecting  ──~2.2s──▶  connected  ──tap──▶  disconnecting  ──~0.9s──▶  idle
```

### Layout (top → bottom)
1. **Status bar** (system, native)
2. **Header**
   - `RKN·PNH` wordmark (Archivo Black, the `·` is magenta `#ff2bd6`)
   - Subtitle (12px, dim purple `#5a4a7a`):
     - idle: "A VPN by you, against them"
     - connected: "Your traffic has been denied by us instead of them"
   - Settings gear (top-right, 36×36 circle, 1px `#2a1f3a` border)
3. **Center stage** — the tappable area (whole region is the button)
   - **idle**: stamp icon + 3 pulse rings radiating outward
   - **connecting**: connect animation plays (see below)
   - **connected (first ~4s)**: connect animation holds on the "PROTECTED" beat
   - **connected (after 4s)**: stamp returns, pulsing in cyan
   - **disconnecting**: stamp shakes
4. **Status copy** (under center stage)
   - mono caption (11px, letter-spacing 2): `// STATUS: EXPOSED` / `// SCANNING ROUTES…` / `// STATUS: HIDDEN` / `// CLOSING TUNNEL…`
   - big CTA (Archivo Black, 22px): **TAP TO HIDE** / **HOLD ON** / **YOU'RE GHOST** / **BYE**
5. **Footer card — ASCII Route Map** (rounded 18px, frosted, 1px `#2a1f3a` border, padding 14). See "ASCII Route Map footer" below — this replaces the previous speed-meter footer.

### Palette
| token       | hex        | use                          |
|-------------|------------|------------------------------|
| bg          | `#120a1f`  | screen background            |
| bgDeep      | `#0a0612`  | tile bg, deep accents        |
| magenta     | `#ff2bd6`  | brand primary (idle/exposed) |
| magentaHi   | `#ff5ce0`  | hover/active                 |
| cyan        | `#00f0ff`  | success / connected / heal   |
| white       | `#f5f3ff`  | primary text                 |
| dim         | `#5a4a7a`  | secondary text               |
| dim2        | `#2a1f3a`  | borders / dividers           |

Background under the stamp: a soft radial glow — magenta (idle) or cyan (connected). 600ms ease cross-fade.

### Type
- Display: **Archivo Black**
- UI / body: **Space Grotesk** (500/700)
- Mono / status: **JetBrains Mono** (500/700)

### App icon
`icon.svg` is in the project root — square 1024×1024, dark bg with the magenta NOT APPROVED stamp. The OS handles rounding/squircle.

---

## ASCII Route Map footer

Replaces the speed-meter tiles. Lives in the same rounded card position. Conveys "your traffic is being bounced through these cities" using a monospaced grid map. **No real network values are shown** — this is a brand/atmosphere element, not a metric.

### Card structure (top → bottom inside the rounded card)
1. **Header row** — JetBrains Mono, 9px, letter-spacing 2
   - Left: `// ROUTE/DIRECT` (idle) · `// ROUTE/BUILDING…` (connecting) · `// ROUTE/OBFUSCATED` (connected)
   - Right: `▲ HOPS: 0` (idle/connecting) · `▲ HOPS: 4` cyan (connected)
2. **Map block** — JetBrains Mono, 10px, line-height 1.15, `#0a0612` bg, 1px `#2a1f3a` border, radius 8, padding 8/6. Each character is a fixed 6px-wide cell.
3. **City label row** — JetBrains Mono, 9px, letter-spacing 1.5. Five labels evenly spaced with `space-between`: `YOU` (magenta, bold) · `AMS` · `STO` · `OSL` · `REY` (cyan, bold). Intermediate labels go cyan as their hop activates.
4. **Status row** — top border `1px dashed #2a1f3a`, padding-top 10. JetBrains Mono, 10px.
   - Left, dim: `EXIT → —` (idle) · `EXIT → REY 🇮🇸` (connected)
   - Right: `00:00:00` dim (idle) · live `HH:MM:SS` cyan (connected) + blinking `▮` cursor (1s step-end)

### Map grid
- 60 columns × 7 rows of monospaced characters.
- **Background stipple**: print `·` at every cell where `(x*7 + y*13) % 11 === 0` (color `#5a4a7a`, the "dim" token). Gives a stary-ocean texture.
- **Land outlines** (rendered above stipple, color `#2a1f3a`):
  ```
  Row 0:        ___        ___       __     __
  Row 1:       /   \__   _/   \__  _/  \___/  \__
  Row 2:      /        \_/        \/            \
  Row 3:     /                                   \
  ```
  Stamp those characters into rows 0–3 starting at column 0. Rows 4–6 are open ocean.
- **Hops** — 5 fixed positions:
  | code | x  | y | role  | char           |
  |------|----|---|-------|----------------|
  | YOU  | 8  | 4 | start | `◉` magenta bold |
  | AMS  | 26 | 2 | relay | `○` / `●`        |
  | STO  | 36 | 5 | relay | `○` / `●`        |
  | OSL  | 44 | 3 | relay | `○` / `●`        |
  | REY  | 52 | 4 | exit  | `◆` cyan bold    |
- **Trail between consecutive hops**: linearly interpolate the cells between `(a.x, a.y)` and `(b.x, b.y)` (step by 1 column, round y). Even-indexed steps render `─`, odd render `·`. Trail color: cyan when connected, dim when idle. During `connecting` the trail only draws up to the currently-active hop.

### State machine
A single `pulse` integer increments on a timer:
- `connecting`: every **220ms** (fast — feels like it's racing to build)
- `connected`: every **700ms** (slow cycle through hops)
- `idle`: timer can keep running but `activeHop` is forced to 0

`activeHop` derivation:
- `idle` → `0`
- `connecting` → `min(HOPS.length - 1, pulse % (HOPS.length + 1))` — sweeps 0 → 4, briefly all five lit, repeats
- `connected` → `pulse % HOPS.length` — cycles 0,1,2,3,4,0,1,… so a single hop "highlights" at a time

Per-hop rendering rules:
- `i === 0` (YOU) → always `◉` magenta `#ff2bd6` bold
- `i === 4` (REY, exit) → cyan `#00f0ff` bold when state is `connected`, dim when not
- relays (i = 1,2,3):
  - reached (`i <= activeHop`) → `○` cyan-hi `#7af6ff`
  - not yet reached → `·` dim
  - currently active during `connected` → `●` white, with a one-shot pop animation (scale 0.5 → 1.4 → 1.0 over 700ms ease-out)

### Animations / timing
- **Pop on active hop**: keyframes `0% scale(0.5) opacity 0` → `30% scale(1.4) opacity 1` → `100% scale(1) opacity 1`, duration 700ms ease-out, runs once each time a relay becomes the active hop.
- **Cursor blink**: `▮` opacity 1 → 0 with `step-end` at 1s.
- No additional motion on the trail itself — re-rendering each tick is enough.

### Idle / connecting / connected examples
**idle** — only YOU lit, no trail, dim city labels (REY also dim), exit `—`, time `00:00:00`.
**connecting** — pulsing rapidly: trail draws to `activeHop`, relays light cyan-hi sequentially, copy reads `// ROUTE/BUILDING…`. The fast 220ms cadence is the entire "this is working" signal.
**connected** — full trail YOU→AMS→STO→OSL→REY in cyan, REY exit highlighted, header reads `// ROUTE/OBFUSCATED · ▲ HOPS: 4`, status reads `EXIT → REY 🇮🇸 · 00:00:42 ▮`. A single relay pulses white once per 700ms tick to show the route is "live".

### Notes for re-implementation
- The map is a **static logical grid**, not a globe projection. Don't try to map real coordinates — the city positions are layout choices. Pick coords that read well on the target viewport width.
- The "ocean stipple + land sketch" is intentional ASCII-art whimsy. Native targets that don't have a great mono font option can swap to a small SVG with the same beats (5 dots, lines between, scrolling pulse).
- The five-city set (AMS/STO/OSL/REY) is a placeholder route. In production this would come from the actual server selection.
- Counter blink uses `step-end` so the cursor visibly snaps, not fades.

### Reference
See `footer-variants.jsx` → `FooterMap` for the working source. The other two functions in that file (`FooterReceipt`, `FooterPet`) are alternate explorations — **ignore them**, the chosen design is the route map.

---

## The connect animation

A 0–4s motion sequence (the part during `connecting`; from 3.4s onwards is the held "connected" beat).

| t (s)   | beat                                                                    |
|---------|-------------------------------------------------------------------------|
| 0.0–0.6 | RKNPNH stamp logo idles with magenta drop-shadow pulse                  |
| 0.6–1.4 | Stamp splits: `RKN` half drifts up-right, `PNH` half drifts down-left, frame fades, debris ring of magenta particles bursts outward |
| 1.2–2.0 | Two pictogram figures fade in: **PNH** on left (standing, arm out, holds a syringe), **RKN** on right (side-profile, both hands cupped at face level — drinking pose) |
| 1.6–2.2 | PNH's arm raises; syringe needle tip starts to glow cyan                |
| 1.8–2.8 | Cyan stream arcs from needle tip across to RKN's cupped hands (quadratic bezier, glowing core + outer halo + falling droplets) |
| 2.6–3.4 | Stream contacts hands → splash: shockwave rings, burst particles, RKN's body cross-fades magenta→cyan, mouth glows, healing aura grows |
| 3.4–6.0 | Hold "PROTECTED" state: ambient cyan particles drift, "PROTECTED" pill + route + uptime visible |

**Implementation freedom**: don't try to byte-port the SVG. Use whatever animation library is idiomatic for the stack (Lottie, Rive, native iOS animations, Reanimated, Compose graphics, etc.). The HTML reference is the source of truth for *what* should happen, *when*, and *what palette*.

If targeting native and you want a one-shot solution, **export the connect animation as a Lottie or video** and play it during `connecting` + first 4s of `connected`. Tap-to-cancel should still work.

### State timing
- `connecting` is fixed at ~2.2s in the reference (network call would replace this in production).
- `connected` first 4s plays the held "PROTECTED" beat from the animation, then transitions back to the static stamp pulsing in cyan.
- `disconnecting` is ~0.9s.

---

## Files in this handoff
- `RKNPNH Main Screen.html` — the main file. Tap the stamp on phone #01 ("Stamped (with HIDE button)") to see the full flow.
- `RKNPNH Connect Animation.html` — standalone connect animation with a scrubber. Use this to step through frame-by-frame.
- `icon.svg` — the app icon as a clean square SVG.
- `main-screens.jsx`, `connect-anim.jsx`, `animations.jsx`, `ios-frame.jsx`, `design-canvas.jsx` — JSX source for the prototype. Read for layout/timing details if needed.
- `footer-variants.jsx` — source for the ASCII Route Map footer (`FooterMap` function). Other footers in this file are unused alternate explorations — ignore.

## How to view
1. `cd handoff && python3 -m http.server 8080`
2. Open `http://localhost:8080/RKNPNH%20Main%20Screen.html`
3. Click "01 · Stamped (with HIDE button)" → tap the stamp on the phone

## Acceptance
- Main screen renders in palette, hits all 4 states cleanly
- Tap-to-connect/disconnect works
- Connect animation plays during `connecting`, holds during first ~4s of `connected`
- Footer values update live (uptime, IP swaps to fake server IP, etc.)
- Tappable area is the whole center; minimum hit target 44pt

That's it. Ask if anything's ambiguous — better to clarify than guess.
