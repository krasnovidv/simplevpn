// Three footer-variant ideas to replace the speed meters.
// All consume {state, secs} like the original Footer.
//   #16 FooterMap     — live ASCII hop-map of your fake route
//   #10 FooterReceipt — dot-matrix receipt printing line by line
//   #19 FooterPet     — tiny pixel mascot (your anonymity), healthy when connected

const { useState: useStateF, useEffect: useEffectF, useRef: useRefF } = React;

const FPAL = {
  bg:        '#120a1f',
  bgDeep:    '#0a0612',
  paper:     '#f3ecd8',   // for the receipt
  paperInk:  '#1a1410',
  magenta:   '#ff2bd6',
  magentaHi: '#ff5ce0',
  cyan:      '#00f0ff',
  cyanHi:    '#7af6ff',
  purple:    '#a259ff',
  yellow:    '#fff200',
  green:     '#7cff8e',
  red:       '#ff4f6d',
  white:     '#f5f3ff',
  dim:       '#5a4a7a',
  dim2:      '#2a1f3a',
};

const fmtTimeF = (s) => `${String(Math.floor(s/3600)).padStart(2,'0')}:${String(Math.floor(s/60)%60).padStart(2,'0')}:${String(s%60).padStart(2,'0')}`;

// inject footer-specific keyframes once
if (typeof document !== 'undefined' && !document.getElementById('rk-footer-anim')) {
  const s = document.createElement('style');
  s.id = 'rk-footer-anim';
  s.textContent = `
    @keyframes rk-print-in { from { opacity: 0; transform: translateY(-6px); clip-path: inset(0 0 100% 0); } to { opacity: 1; transform: translateY(0); clip-path: inset(0 0 0 0); } }
    @keyframes rk-paper-feed { 0% { transform: translateY(-2px); } 50% { transform: translateY(0); } 100% { transform: translateY(-1px); } }
    @keyframes rk-blink-cursor { 0%,49% { opacity: 1; } 50%,100% { opacity: 0; } }
    @keyframes rk-pet-bob { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-2px); } }
    @keyframes rk-pet-shake { 0%,100% { transform: translate(0,0); } 25% { transform: translate(-1px, 0); } 75% { transform: translate(1px, 0); } }
    @keyframes rk-heart-beat { 0%,100% { transform: scale(1); } 30% { transform: scale(1.25); } 60% { transform: scale(0.95); } }
    @keyframes rk-zzz { 0% { opacity: 0; transform: translate(0,0); } 50% { opacity: 1; } 100% { opacity: 0; transform: translate(6px,-8px); } }
    @keyframes rk-map-glow { 0%,100% { opacity: 0.3; } 50% { opacity: 1; } }
    @keyframes rk-hop { 0% { opacity: 0; transform: scale(0.5); } 30% { opacity: 1; transform: scale(1.4); } 100% { opacity: 1; transform: scale(1); } }
    @keyframes rk-trail { from { stroke-dashoffset: 100; } to { stroke-dashoffset: 0; } }
  `;
  document.head.appendChild(s);
}

// ─── #16 FooterMap — ASCII route map ──────────────────────────────────
function FooterMap({ state, secs }) {
  // Fake hop-route through cities. While "connecting" we pulse hops in sequence.
  // While "connected" we cycle which hop is "active".
  const HOPS = [
    { code: 'YOU', x: 8,  y: 4, real: true },
    { code: 'AMS', x: 26, y: 2 },
    { code: 'STO', x: 36, y: 5 },
    { code: 'OSL', x: 44, y: 3 },
    { code: 'REY', x: 52, y: 4, exit: true },
  ];
  const W = 60, H = 7;
  const [pulse, setPulse] = useStateF(0);
  useEffectF(() => {
    const i = setInterval(() => setPulse(p => p + 1), state === 'connecting' ? 220 : 700);
    return () => clearInterval(i);
  }, [state]);

  // Build ASCII grid
  const grid = Array.from({ length: H }, () => Array.from({ length: W }, () => ' '));

  // Stipple background — gentle ocean dots
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      if ((x * 7 + y * 13) % 11 === 0) grid[y][x] = '·';
    }
  }

  // Some land outlines (very abstract)
  const land = [
    '       ___        ___       __     __',
    '      /   \\__   _/   \\__  _/  \\___/  \\__',
    '     /        \\_/        \\/            \\',
    '    /                                   \\',
  ];
  land.forEach((row, i) => {
    for (let x = 0; x < row.length && x < W; x++) {
      const ch = row[x];
      if (ch !== ' ') grid[i][x] = ch;
    }
  });

  // Trail between hops (dashes/dots)
  const activeHop = state === 'connected'
    ? (pulse % HOPS.length)
    : state === 'connecting'
      ? Math.min(HOPS.length - 1, pulse % (HOPS.length + 1))
      : 0;

  if (state !== 'idle') {
    for (let i = 0; i < HOPS.length - 1; i++) {
      if (state === 'connecting' && i >= activeHop) break;
      const a = HOPS[i], b = HOPS[i+1];
      const steps = Math.abs(b.x - a.x);
      for (let s = 1; s < steps; s++) {
        const x = a.x + s;
        const y = Math.round(a.y + (b.y - a.y) * (s / steps));
        if (y >= 0 && y < H && x >= 0 && x < W) {
          grid[y][x] = (s % 2 === 0) ? '─' : '·';
        }
      }
    }
  }

  // Stamp hops on top
  HOPS.forEach((h, i) => {
    if (h.y < H) {
      const isActive = state === 'connected' && i === activeHop;
      const reached = state === 'idle' ? (i === 0) : i <= activeHop;
      const ch = h.real ? '◉' : h.exit ? '◆' : (isActive ? '●' : reached ? '○' : '·');
      grid[h.y][h.x] = ch;
    }
  });

  // Render — color hops/trail by index using a span overlay
  const rows = grid.map(r => r.join(''));

  // For colorization we re-walk and emit segments
  return (
    <div style={{ padding: '0 20px 36px', position: 'relative', zIndex: 2 }}>
      <div style={{
        background: 'rgba(255,255,255,0.04)', border: `1px solid ${FPAL.dim2}`,
        borderRadius: 18, padding: 14, backdropFilter: 'blur(10px)',
      }}>
        {/* Header line */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: FPAL.dim, letterSpacing: 2 }}>
            // ROUTE/{state === 'idle' ? 'DIRECT' : state === 'connecting' ? 'BUILDING…' : 'OBFUSCATED'}
          </span>
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: state === 'connected' ? FPAL.cyan : FPAL.dim, letterSpacing: 2 }}>
            {state === 'connected' ? `▲ HOPS: ${HOPS.length-1}` : `▲ HOPS: 0`}
          </span>
        </div>

        {/* Map */}
        <div style={{
          fontFamily: 'JetBrains Mono, monospace', fontSize: 10, lineHeight: 1.15,
          color: state === 'idle' ? FPAL.dim : FPAL.cyan,
          letterSpacing: 0, whiteSpace: 'pre', overflow: 'hidden',
          background: FPAL.bgDeep, padding: '8px 6px', borderRadius: 8, border: `1px solid ${FPAL.dim2}`,
        }}>
          {rows.map((row, y) => (
            <div key={y} style={{ display: 'flex' }}>
              {row.split('').map((ch, x) => {
                const hop = HOPS.find(h => h.x === x && h.y === y);
                let color = ch === '─' || ch === '·' ? (state === 'connected' ? FPAL.cyan : FPAL.dim)
                          : (ch === '/' || ch === '\\' || ch === '_') ? FPAL.dim2
                          : FPAL.dim;
                let weight = 400;
                let anim = 'none';
                if (hop) {
                  if (hop.real) { color = FPAL.magenta; weight = 700; }
                  else if (hop.exit) { color = state === 'connected' ? FPAL.cyan : FPAL.dim; weight = 700; }
                  else { color = state === 'connected' || (state === 'connecting' && HOPS.indexOf(hop) <= activeHop) ? FPAL.cyanHi : FPAL.dim; }
                  if (state === 'connected' && HOPS.indexOf(hop) === activeHop && !hop.real) {
                    anim = 'rk-hop 0.7s ease-out';
                    color = FPAL.white;
                  }
                }
                return <span key={x} style={{ color, fontWeight: weight, animation: anim, display: 'inline-block', width: 6 }}>{ch}</span>;
              })}
            </div>
          ))}
        </div>

        {/* City labels */}
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, fontFamily: 'JetBrains Mono, monospace', fontSize: 9, letterSpacing: 1.5 }}>
          {HOPS.map((h, i) => (
            <span key={i} style={{
              color: h.real ? FPAL.magenta
                   : state === 'connected' ? FPAL.cyan
                   : state === 'connecting' && i <= activeHop ? FPAL.cyanHi
                   : FPAL.dim,
              fontWeight: h.real || h.exit ? 700 : 400,
            }}>
              {h.code}
            </span>
          ))}
        </div>

        {/* Bottom status line */}
        <div style={{
          marginTop: 10, paddingTop: 10, borderTop: `1px dashed ${FPAL.dim2}`,
          display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
          fontFamily: 'JetBrains Mono, monospace', fontSize: 10,
        }}>
          <span style={{ color: FPAL.dim, letterSpacing: 1 }}>
            {state === 'connected' ? `EXIT → ${HOPS[HOPS.length-1].code} 🇮🇸` : 'EXIT → —'}
          </span>
          <span style={{ color: state === 'connected' ? FPAL.cyan : FPAL.dim, fontWeight: 600 }}>
            {state === 'connected' ? fmtTimeF(secs) : '00:00:00'}
            <span style={{ animation: 'rk-blink-cursor 1s step-end infinite', marginLeft: 2 }}>▮</span>
          </span>
        </div>
      </div>
    </div>
  );
}

// ─── #10 FooterReceipt — printing dot-matrix receipt ──────────────────
function FooterReceipt({ state, secs }) {
  // Build lines that get revealed one by one when transitioning to "connected".
  // When idle, show a "VOID" stub. When connecting, show the printer warming up.
  const RECEIPT_LINES = [
    { k: 'header',  text: '━━ RKN·PNH ━━━━━━━━━━━━━━' },
    { k: 'sub',     text: 'OFFICE OF DENIED PERMISSIONS' },
    { k: 'date',    text: '2026-05-05 · TICKET #2C7F4A' },
    { k: 'rule',    text: '────────────────────────' },
    { k: 'item1',   text: 'IP ADDRESS .......... REVOKED' },
    { k: 'item2',   text: 'IDENTITY ............ ERASED' },
    { k: 'item3',   text: 'LOCATION ........... REYKJAVÍK' },
    { k: 'item4',   text: 'TRACKERS ............ DENIED' },
    { k: 'rule2',   text: '────────────────────────' },
    { k: 'stamp',   text: '       ★ NOT APPROVED ★' },
    { k: 'sig',     text: 'BY ORDER OF: PNH' },
    { k: 'foot',    text: 'KEEP THIS RECEIPT. THEY WONT.' },
    { k: 'tear',    text: '✂ - - - - - - - - - - - - - -' },
  ];

  const [revealed, setRevealed] = useStateF(0);
  useEffectF(() => {
    if (state !== 'connected') { setRevealed(0); return; }
    setRevealed(0);
    let i = 0;
    const tick = () => {
      i++;
      setRevealed(i);
      if (i < RECEIPT_LINES.length) setTimeout(tick, 110);
    };
    const t = setTimeout(tick, 200);
    return () => clearTimeout(t);
  }, [state]);

  // tracker/decoy counters that tick when connected
  const [blocked, setBlocked] = useStateF(0);
  const [decoys, setDecoys] = useStateF(0);
  useEffectF(() => {
    if (state !== 'connected') { setBlocked(0); setDecoys(0); return; }
    const i = setInterval(() => {
      setBlocked(b => b + Math.floor(Math.random() * 3));
      setDecoys(d => d + Math.floor(Math.random() * 2));
    }, 800);
    return () => clearInterval(i);
  }, [state]);

  return (
    <div style={{ padding: '0 20px 36px', position: 'relative', zIndex: 2 }}>
      {/* Printer slot */}
      <div style={{
        height: 6, background: FPAL.bgDeep, borderRadius: '6px 6px 0 0',
        borderTop: `1px solid ${FPAL.dim2}`, borderLeft: `1px solid ${FPAL.dim2}`, borderRight: `1px solid ${FPAL.dim2}`,
        marginBottom: -1,
        boxShadow: state === 'connected' ? `inset 0 -2px 0 ${FPAL.cyan}66` : 'none',
      }}/>
      <div style={{
        background: FPAL.paper,
        color: FPAL.paperInk,
        borderRadius: '2px 2px 4px 4px',
        padding: '14px 16px 4px',
        fontFamily: 'JetBrains Mono, monospace',
        fontSize: 11,
        lineHeight: 1.45,
        letterSpacing: 0.5,
        position: 'relative',
        boxShadow: '0 6px 20px rgba(0,0,0,0.4), inset 0 0 0 1px rgba(0,0,0,0.05)',
        // subtle paper texture
        backgroundImage: `repeating-linear-gradient(180deg, rgba(0,0,0,0.018) 0 1px, transparent 1px 3px)`,
        animation: state === 'connecting' ? 'rk-paper-feed 0.4s ease-in-out infinite' : 'none',
        // edge curl
        clipPath: 'polygon(0 0, 100% 0, 100% 100%, 96% 98%, 92% 100%, 88% 98%, 84% 100%, 80% 98%, 76% 100%, 72% 98%, 68% 100%, 64% 98%, 60% 100%, 56% 98%, 52% 100%, 48% 98%, 44% 100%, 40% 98%, 36% 100%, 32% 98%, 28% 100%, 24% 98%, 20% 100%, 16% 98%, 12% 100%, 8% 98%, 4% 100%, 0 98%)',
        minHeight: 80,
      }}>
        {state === 'idle' && (
          <div style={{ textAlign: 'center', padding: '12px 0 18px', color: '#7a6f5e' }}>
            <div style={{ fontWeight: 700, letterSpacing: 3, fontSize: 12 }}>— VOID —</div>
            <div style={{ fontSize: 10, marginTop: 4 }}>NO TICKET ISSUED</div>
            <div style={{ fontSize: 10, marginTop: 10, color: '#a8987c' }}>tap stamp to file paperwork</div>
          </div>
        )}

        {state === 'connecting' && (
          <div style={{ textAlign: 'center', padding: '12px 0 18px', color: '#5a4f3e' }}>
            <div style={{ fontWeight: 700, letterSpacing: 3, fontSize: 12 }}>PRINTING…</div>
            <div style={{ fontSize: 10, marginTop: 6, opacity: 0.6 }}>
              <span style={{ animation: 'rk-blink-cursor 0.6s step-end infinite' }}>▮▮▮▮▮▮▮▮</span>
            </div>
          </div>
        )}

        {(state === 'connected' || state === 'disconnecting') && (
          <div>
            {RECEIPT_LINES.slice(0, state === 'disconnecting' ? RECEIPT_LINES.length : revealed).map((line, i) => {
              const isStamp = line.k === 'stamp';
              const isHeader = line.k === 'header' || line.k === 'sub';
              const isFoot = line.k === 'foot' || line.k === 'tear';
              return (
                <div key={i} style={{
                  textAlign: line.k === 'sub' || line.k === 'date' || isStamp || isFoot ? 'center' : 'left',
                  fontWeight: isHeader || isStamp ? 700 : 400,
                  color: isStamp ? FPAL.magenta : FPAL.paperInk,
                  fontSize: isStamp ? 13 : 11,
                  letterSpacing: isStamp ? 2 : 0.5,
                  animation: state === 'connected' ? `rk-print-in 0.18s ease-out both` : 'none',
                  transform: isStamp ? 'rotate(-3deg)' : 'none',
                  margin: isStamp ? '6px 0' : 0,
                  textShadow: isStamp ? `0 0 1px ${FPAL.magenta}` : 'none',
                  filter: isStamp ? 'contrast(1.1)' : 'none',
                }}>
                  {line.text}
                </div>
              );
            })}

            {/* live counters as a footer block on the receipt */}
            {revealed >= RECEIPT_LINES.length && state === 'connected' && (
              <div style={{
                marginTop: 6, paddingTop: 6, borderTop: '1px dashed #b8a98c',
                display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4,
                fontSize: 10, color: '#5a4f3e',
              }}>
                <div>TRACKERS DENIED <b style={{ color: FPAL.paperInk, fontVariantNumeric: 'tabular-nums' }}>{blocked}</b></div>
                <div style={{ textAlign: 'right' }}>DECOYS SENT <b style={{ color: FPAL.paperInk, fontVariantNumeric: 'tabular-nums' }}>{decoys}</b></div>
                <div>UPTIME <b style={{ color: FPAL.paperInk, fontVariantNumeric: 'tabular-nums' }}>{fmtTimeF(secs)}</b></div>
                <div style={{ textAlign: 'right' }}>EXIT <b style={{ color: FPAL.paperInk }}>REY 🇮🇸</b></div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── #19 FooterPet — pixel mascot Tamagotchi ──────────────────────────
function FooterPet({ state, secs }) {
  // The pet ("GHOST") is healthy/happy when connected; sickly/exposed when idle.
  // Health auto-fills while connected, drops while idle.
  const [health, setHealth] = useStateF(20);
  const [mood, setMood] = useStateF('exposed');

  useEffectF(() => {
    const i = setInterval(() => {
      setHealth(h => {
        if (state === 'connected') return Math.min(100, h + 4);
        if (state === 'idle') return Math.max(0, h - 2);
        if (state === 'connecting') return Math.min(100, h + 8);
        return h;
      });
    }, 400);
    return () => clearInterval(i);
  }, [state]);

  useEffectF(() => {
    if (state === 'idle') setMood('exposed');
    else if (state === 'connecting') setMood('hopeful');
    else if (state === 'connected') setMood(health > 80 ? 'gleeful' : 'safe');
    else setMood('worried');
  }, [state, health]);

  const moodColor = mood === 'exposed' ? FPAL.red
                  : mood === 'worried' ? FPAL.yellow
                  : mood === 'hopeful' ? FPAL.cyan
                  : mood === 'safe' ? FPAL.cyan
                  : FPAL.green;

  // Pet face drawn from a 12×10 pixel grid. We swap grids per mood.
  // Legend: 0 = empty, 1 = body, 2 = eye, 3 = mouth/blush
  const SHEETS = {
    exposed: [
      '............',
      '...111111...',
      '..11111111..',
      '.1112112111.',
      '.1112112111.',
      '.111111111..', // tear/crack
      '.11111111...',
      '.111133111..',
      '.1133113311.',
      '..1.1..1.1..', // wobbly legs
    ],
    worried: [
      '............',
      '...111111...',
      '..11111111..',
      '.1112112111.',
      '.1112112111.',
      '.1111111111.',
      '.1111111111.',
      '.111133111..',
      '.1111111111.',
      '..1.11.1.1..',
    ],
    hopeful: [
      '............',
      '...111111...',
      '..11111111..',
      '.1112112111.',
      '.1112112111.',
      '.1111111111.',
      '.1111111111.',
      '.1113113111.',
      '.1111111111.',
      '..11..11..11',
    ],
    safe: [
      '............',
      '...111111...',
      '..11111111..',
      '.1111121111.', // closed-eye smug
      '.1112221111.',
      '.1111111111.',
      '.1111111111.',
      '.1133333111.', // smile
      '.1111111111.',
      '..11..11....',
    ],
    gleeful: [
      '...11..11...',
      '..1111111...', // arms up!
      '.111111111..',
      '.1112112111.',
      '.1112112111.',
      '.1111111111.',
      '.1111111111.',
      '.1133333111.',
      '.1111111111.',
      '..11..11....',
    ],
  };

  const sheet = SHEETS[mood] || SHEETS.safe;
  const PX = 7;

  // Heart that pulses every connect-tick
  const heartCount = state === 'connected' ? 1 + Math.floor(secs / 30) : 0;

  return (
    <div style={{ padding: '0 20px 36px', position: 'relative', zIndex: 2 }}>
      <div style={{
        background: 'rgba(255,255,255,0.04)',
        border: `1px solid ${FPAL.dim2}`,
        borderRadius: 18,
        padding: 14,
        backdropFilter: 'blur(10px)',
        display: 'grid',
        gridTemplateColumns: '108px 1fr',
        gap: 14,
        alignItems: 'center',
      }}>
        {/* Pet enclosure */}
        <div style={{
          width: 108, height: 108,
          background: state === 'connected'
            ? `radial-gradient(circle at 50% 70%, ${FPAL.cyan}22, ${FPAL.bgDeep})`
            : `radial-gradient(circle at 50% 70%, ${FPAL.red}22, ${FPAL.bgDeep})`,
          border: `1px solid ${FPAL.dim2}`,
          borderRadius: 12,
          position: 'relative',
          overflow: 'hidden',
          imageRendering: 'pixelated',
          transition: 'background 0.5s',
        }}>
          {/* horizon line */}
          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 14,
            height: 1, background: FPAL.dim2,
          }}/>
          {/* z's when idle */}
          {state === 'idle' && (
            <div style={{
              position: 'absolute', top: 8, right: 10,
              fontFamily: 'JetBrains Mono, monospace', fontSize: 10, color: FPAL.dim,
              animation: 'rk-zzz 1.6s ease-in-out infinite',
            }}>z</div>
          )}
          {/* hearts when gleeful */}
          {heartCount > 0 && (
            <div style={{
              position: 'absolute', top: 8, right: 10,
              color: FPAL.magenta, fontSize: 12,
              animation: 'rk-heart-beat 1.1s ease-in-out infinite',
            }}>♥</div>
          )}

          {/* pixel pet */}
          <div style={{
            position: 'absolute', left: '50%', bottom: 10,
            transform: 'translateX(-50%)',
            animation: state === 'connecting' ? 'rk-pet-shake 0.18s steps(2) infinite'
                     : state === 'connected' ? 'rk-pet-bob 1.6s ease-in-out infinite'
                     : 'none',
          }}>
            <svg width={12 * PX} height={10 * PX} viewBox={`0 0 ${12 * PX} ${10 * PX}`} shapeRendering="crispEdges">
              {sheet.map((row, y) => row.split('').map((c, x) => {
                if (c === '.') return null;
                const fill = c === '1' ? moodColor
                           : c === '2' ? FPAL.bgDeep
                           : c === '3' ? FPAL.bgDeep
                           : 'transparent';
                return <rect key={`${x}-${y}`} x={x * PX} y={y * PX} width={PX} height={PX} fill={fill}/>;
              }))}
            </svg>
          </div>
        </div>

        {/* Stats panel */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
          }}>
            <span style={{ fontFamily: 'Archivo Black, Impact, sans-serif', fontSize: 14, color: FPAL.white, letterSpacing: 1 }}>
              GHOST
            </span>
            <span style={{
              fontFamily: 'JetBrains Mono, monospace', fontSize: 9, letterSpacing: 2,
              color: moodColor, textTransform: 'uppercase',
            }}>
              {mood}
            </span>
          </div>

          <StatBar label="ANONYMITY" value={health} color={moodColor}/>
          <StatBar label="VIBES" value={state === 'connected' ? Math.min(100, 60 + secs) : state === 'connecting' ? 50 : 15} color={state === 'connected' ? FPAL.cyan : FPAL.dim}/>

          <div style={{
            display: 'flex', justifyContent: 'space-between',
            fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: FPAL.dim, letterSpacing: 1.5,
            marginTop: 2,
          }}>
            <span>AGE {state === 'connected' ? fmtTimeF(secs) : '00:00:00'}</span>
            <span>{state === 'connected' ? '🇮🇸 SAFE' : state === 'connecting' ? '… HIDING' : '👁 WATCHED'}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatBar({ label, value, color }) {
  const v = Math.max(0, Math.min(100, value));
  const filled = Math.round(v / 10);
  return (
    <div>
      <div style={{
        display: 'flex', justifyContent: 'space-between',
        fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: FPAL.dim, letterSpacing: 1.5,
        marginBottom: 2,
      }}>
        <span>{label}</span>
        <span style={{ color, fontVariantNumeric: 'tabular-nums' }}>{Math.round(v)}%</span>
      </div>
      <div style={{
        fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: 1, color,
        lineHeight: 1,
      }}>
        {Array.from({ length: 10 }).map((_, i) => (
          <span key={i} style={{ opacity: i < filled ? 1 : 0.18 }}>█</span>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { FooterMap, FooterReceipt, FooterPet });
