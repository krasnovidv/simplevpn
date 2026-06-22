# RKNPNH — ASCII Route Map Footer (addition)

This is a **standalone addition** to the already-shipped main screen. It replaces the old speed-meter footer card with a monospaced ASCII map showing your traffic bouncing through cities. No real metrics — purely brand atmosphere.

## What to build

A new footer component that drops into the same slot as the previous footer card (rounded 18px, frosted, 1px `#2a1f3a` border, padding 14, full-width minus 20px horizontal page padding, sits above the home indicator).

It consumes the same `{ state, secs }` the old footer did:
- `state ∈ { idle, connecting, connected, disconnecting }`
- `secs` — uptime in seconds (already ticking at 1Hz when connected)

## Card structure (top → bottom)

1. **Header row** — JetBrains Mono, 9px, letter-spacing 2
   - Left, dim `#5a4a7a`: `// ROUTE/DIRECT` (idle) · `// ROUTE/BUILDING…` (connecting) · `// ROUTE/OBFUSCATED` (connected)
   - Right: `▲ HOPS: 0` dim (idle/connecting) · `▲ HOPS: 4` cyan `#00f0ff` (connected)

2. **Map block** — JetBrains Mono, 10px, line-height 1.15, bg `#0a0612`, 1px `#2a1f3a` border, radius 8, padding 8/6. Each character occupies a fixed 6px-wide cell.

3. **City label row** — JetBrains Mono, 9px, letter-spacing 1.5. Five labels with `space-between`: `YOU` (magenta `#ff2bd6`, bold) · `AMS` · `STO` · `OSL` · `REY` (cyan, bold). Intermediate labels turn cyan-hi `#7af6ff` as their hop activates.

4. **Status row** — top border `1px dashed #2a1f3a`, padding-top 10. JetBrains Mono, 10px.
   - Left, dim: `EXIT → —` (idle) · `EXIT → REY 🇮🇸` (connected)
   - Right: `00:00:00` dim (idle) · live `HH:MM:SS` cyan (connected) + blinking `▮` cursor (1s step-end)

## Map grid

- 60 columns × 7 rows of monospaced characters.
- **Background stipple**: print `·` at every cell where `(x*7 + y*13) % 11 === 0` (color `#5a4a7a`). Stary-ocean texture.
- **Land outlines** (above stipple, color `#2a1f3a`):
  ```
  Row 0:        ___        ___       __     __
  Row 1:       /   \__   _/   \__  _/  \___/  \__
  Row 2:      /        \_/        \/            \
  Row 3:     /                                   \
  ```
  Stamp those characters into rows 0–3 starting at column 0. Rows 4–6 are open ocean.
- **Hops** — 5 fixed grid positions:

  | code | x  | y | role  | char idle/inactive | char active        |
  |------|----|---|-------|--------------------|--------------------|
  | YOU  | 8  | 4 | start | `◉` magenta bold   | (always magenta)   |
  | AMS  | 26 | 2 | relay | `·` dim            | `○` cyan-hi → `●` white pop |
  | STO  | 36 | 5 | relay | `·` dim            | `○` cyan-hi → `●` white pop |
  | OSL  | 44 | 3 | relay | `·` dim            | `○` cyan-hi → `●` white pop |
  | REY  | 52 | 4 | exit  | `◆` dim            | `◆` cyan bold (when connected) |

- **Trail between consecutive hops**: linearly interpolate cells between `(a.x, a.y)` and `(b.x, b.y)` (step by 1 column, round y). Even-indexed steps render `─`, odd render `·`. Trail color: cyan when connected, dim when idle. During `connecting` the trail only draws up to the currently-active hop.

## State machine

A `pulse` integer increments on a timer:
- `connecting` — every **220ms** (fast, racing to build the route)
- `connected` — every **700ms** (slow cycle through hops)
- `idle` — `activeHop` is forced to 0

`activeHop` derivation:
- `idle` → `0`
- `connecting` → `min(HOPS.length - 1, pulse % (HOPS.length + 1))` — sweeps 0 → 4, briefly all five lit, repeats
- `connected` → `pulse % HOPS.length` — cycles 0,1,2,3,4,0,1,…

Per-hop rendering rules:
- `i === 0` (YOU) → always `◉` magenta bold
- `i === 4` (REY, exit) → cyan bold when state is `connected`, dim otherwise
- relays (i = 1,2,3):
  - reached (`i <= activeHop`) → `○` cyan-hi
  - not yet reached → `·` dim
  - currently active during `connected` → `●` white, with one-shot pop animation

## Animations

- **Pop on active hop**: keyframes `0% scale(0.5) opacity 0` → `30% scale(1.4) opacity 1` → `100% scale(1) opacity 1`, duration 700ms ease-out, runs once each time a relay becomes the active hop.
- **Cursor blink**: `▮` opacity 1 → 0 with `step-end` at 1s.
- No motion on the trail itself — re-render per tick is enough.

## Palette (already in your tokens)

| token       | hex        | use                                      |
|-------------|------------|------------------------------------------|
| bgDeep      | `#0a0612`  | map block background                     |
| magenta     | `#ff2bd6`  | YOU hop, real/origin marker              |
| cyan        | `#00f0ff`  | active route, connected exit, status     |
| cyanHi      | `#7af6ff`  | reached relay nodes                      |
| white       | `#f5f3ff`  | currently-active hop pop                 |
| dim         | `#5a4a7a`  | secondary text, stipple, idle states     |
| dim2        | `#2a1f3a`  | borders, dividers, land outlines         |

## States — quick reference

- **idle** — only YOU lit, no trail, dim city labels, exit `—`, time `00:00:00`. Header: `// ROUTE/DIRECT · ▲ HOPS: 0`.
- **connecting** — trail draws to `activeHop` at 220ms cadence, relays light cyan-hi sequentially. Header: `// ROUTE/BUILDING…`.
- **connected** — full trail YOU→AMS→STO→OSL→REY in cyan, REY exit highlighted, single relay pops white once per 700ms tick. Header: `// ROUTE/OBFUSCATED · ▲ HOPS: 4`. Status: `EXIT → REY 🇮🇸 · HH:MM:SS ▮`.

## Notes

- The map is a **static logical grid**, not a globe projection. Don't try to map real coordinates — these are layout choices. Pick coords that read well on your viewport width.
- The five-city set (AMS/STO/OSL/REY) is a placeholder route. In production it would come from actual server selection — keep the same visual rhythm (4 intermediate hops including the exit, all evenly distributed across the grid horizontally).
- Native targets without a great mono font can swap to a small SVG with the same beats (5 dots, dashed lines between, sweep pulse) — keep timing identical.
- Cursor uses `step-end` so it visibly snaps, not fades.

## Reference

`footer-variants.jsx` → `FooterMap` is the working source. Read it for the exact ASCII grid construction and per-cell rendering loop.
