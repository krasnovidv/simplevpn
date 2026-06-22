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
5. **Footer card** (rounded 18px, frosted, 1px `#2a1f3a` border, padding 16)
   - rows (label/value, dashed bottom border): route, public IP, uptime
   - 2-column grid: ↓ DOWN MB/s, ↑ UP MB/s

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
