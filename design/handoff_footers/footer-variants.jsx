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
    @keyframes rk-burp-up { 0% { opacity: 0; transform: translate(0,0) scale(0.6); } 25% { opacity: 1; } 100% { opacity: 0; transform: translate(10px,-26px) scale(1.1); } }
    @keyframes rk-mon-bob { 0%,100% { transform: translateY(0) rotate(0deg); } 50% { transform: translateY(-2px) rotate(-1deg); } }
    @keyframes rk-belch { 0%,100% { transform: translateX(0); } 30% { transform: translateX(-2px); } 60% { transform: translateX(2px); } }
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

// ─── FooterMonster — the traffic GREMLIN that eats your data ───────────
// Funny "traffic usage" graphic: download packets fly in from the right,
// the gremlin chomps them (DOWN), its belly fills, then it BURPS the bytes
// back out as upload (UP). Numbers are theatre, not real metrics.
function FooterMonster({ state, secs }) {
  const W = 320, H = 120;
  const MOUTH = { x: 74, y: 64 };

  const packetsRef = useRefF([]);
  const lastSpawnRef = useRefF(0);
  const seedRef = useRefF(1);
  const [, tick] = useStateF(0);

  const [eaten, setEaten]   = useStateF(0);   // MB devoured (down)
  const [burped, setBurped] = useStateF(0);   // MB belched (up)
  const [belly, setBelly]   = useStateF(0);   // 0..100
  const [chomp, setChomp]   = useStateF(0);   // timestamp of last chomp
  const [burps, setBurps]   = useStateF([]);  // floating burp bubbles

  const rnd = () => { const x = Math.sin(seedRef.current++) * 43758.5453; return x - Math.floor(x); };

  useEffectF(() => {
    let raf, prev = performance.now();
    const loop = (now) => {
      const dt = Math.min(64, now - prev); prev = now;
      const eating = state === 'connecting' || state === 'connected';

      // spawn packets from the right edge
      if (eating) {
        const gap = state === 'connecting' ? 260 : 480;
        if (now - lastSpawnRef.current > gap + rnd() * 240) {
          lastSpawnRef.current = now;
          const size = 0.4 + rnd() * 2.6;
          packetsRef.current.push({
            id: now + rnd(),
            x: W + 8,
            y: 30 + rnd() * 60,
            size,
            color: rnd() > 0.5 ? FPAL.cyan : FPAL.magenta,
            spd: 0.06 + rnd() * 0.05,
          });
        }
      }

      // advance packets toward the mouth
      const speedMul = state === 'connecting' ? 1.5 : 1;
      packetsRef.current.forEach(p => {
        p.x -= p.spd * dt * 60 / 16 * speedMul;
        p.y += (MOUTH.y - p.y) * 0.06;
      });
      // eat the ones that reached the mouth
      const survivors = [];
      let ateThisFrame = 0;
      for (const p of packetsRef.current) {
        if (p.x <= MOUTH.x) { ateThisFrame += p.size; }
        else survivors.push(p);
      }
      packetsRef.current = survivors;
      if (ateThisFrame > 0) {
        setEaten(e => e + ateThisFrame);
        setChomp(now);
        setBelly(b => {
          const nb = b + ateThisFrame * 9;
          if (nb >= 100) {
            // BURP! release a bubble, bump upload
            const chunk = 1 + rnd() * 4;
            setBurped(u => u + chunk);
            setBurps(list => [...list.slice(-4), { id: now, t: now }]);
            return nb - 100;
          }
          return nb;
        });
      }

      tick(t => (t + 1) % 1000000);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [state]);

  // reset on disconnect to idle
  useEffectF(() => {
    if (state === 'idle') {
      packetsRef.current = [];
      setEaten(0); setBurped(0); setBelly(0); setBurps([]);
    }
  }, [state]);

  // prune old burp bubbles
  useEffectF(() => {
    if (!burps.length) return;
    const t = setTimeout(() => setBurps(list => list.filter(b => performance.now() - b.t < 1100)), 1100);
    return () => clearTimeout(t);
  }, [burps]);

  const chomping = performance.now() - chomp < 160;
  const mood = state === 'idle' ? 'STARVING'
             : state === 'connecting' ? 'WAKING UP'
             : belly > 75 ? 'STUFFED'
             : chomping ? 'NOM NOM' : 'MUNCHING';
  const moodColor = state === 'idle' ? FPAL.dim
                  : state === 'connecting' ? FPAL.yellow
                  : belly > 75 ? FPAL.magentaHi : FPAL.cyan;

  // gremlin geometry
  const bodyColor = state === 'idle' ? FPAL.dim : FPAL.cyan;
  const bellyBulge = 1 + Math.min(0.22, belly / 100 * 0.22);
  const mouthOpen = state === 'idle' ? 3 : chomping ? 22 : 9;
  const asleep = state === 'idle';

  return (
    <div style={{ padding: '0 20px 36px', position: 'relative', zIndex: 2 }}>
      <div style={{
        background: 'rgba(255,255,255,0.04)', border: `1px solid ${FPAL.dim2}`,
        borderRadius: 18, padding: 14, backdropFilter: 'blur(10px)',
      }}>
        {/* header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: FPAL.dim, letterSpacing: 2 }}>
            // TRAFFIC GREMLIN
          </span>
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, letterSpacing: 2, color: moodColor }}>
            {mood}
          </span>
        </div>

        {/* feeding tank */}
        <div style={{
          background: FPAL.bgDeep, border: `1px solid ${FPAL.dim2}`, borderRadius: 10,
          overflow: 'hidden',
        }}>
          <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: 'block' }}>
            {/* floor line */}
            <line x1="0" y1={H - 16} x2={W} y2={H - 16} stroke={FPAL.dim2} strokeWidth="1"/>

            {/* incoming packets */}
            {packetsRef.current.map(p => (
              <g key={p.id} transform={`translate(${p.x} ${p.y})`}>
                <rect x="-6" y="-6" width="12" height="12" rx="2" fill="none" stroke={p.color} strokeWidth="1.6"/>
                <rect x="-2.5" y="-2.5" width="5" height="5" fill={p.color}/>
              </g>
            ))}

            {/* burp bubbles rising from mouth */}
            {burps.map(b => (
              <text key={b.id} x={MOUTH.x + 6} y={MOUTH.y - 14}
                fontFamily="JetBrains Mono, monospace" fontSize="11" fontWeight="700" fill={FPAL.cyanHi}
                style={{ animation: 'rk-burp-up 1.1s ease-out forwards' }}>↑</text>
            ))}

            {/* the gremlin — outer group positions, inner group animates */}
            <g transform={`translate(46 ${H - 16})`}>
            <g style={{
              animation: asleep ? 'none'
                       : chomping ? 'rk-belch 0.16s steps(2)'
                       : 'rk-mon-bob 1.6s ease-in-out infinite',
              transformBox: 'fill-box',
              transformOrigin: 'center bottom',
            }}>
              {/* glow when fed */}
              {!asleep && <ellipse cx="14" cy="-26" rx={34 * bellyBulge} ry="30" fill={FPAL.cyan} opacity="0.10"/>}
              {/* body */}
              <g transform={`translate(14 -26) scale(${bellyBulge} 1) translate(-14 26)`}>
                <path d={`M -16 0
                          C -20 -36, 12 -52, 14 -52
                          C 16 -52, 48 -36, 44 0 Z`} fill={bodyColor}/>
                {/* belly shade */}
                <ellipse cx="14" cy="-12" rx="18" ry="14" fill={FPAL.bgDeep} opacity="0.18"/>
                {/* feet */}
                <rect x="-8" y="-4" width="12" height="8" rx="3" fill={bodyColor}/>
                <rect x="24" y="-4" width="12" height="8" rx="3" fill={bodyColor}/>
              </g>

              {/* eyes */}
              {asleep ? (
                <>
                  <path d="M 2 -40 q 6 4 12 0" stroke={FPAL.bgDeep} strokeWidth="2.4" fill="none" strokeLinecap="round"/>
                  <path d="M 18 -40 q 6 4 12 0" stroke={FPAL.bgDeep} strokeWidth="2.4" fill="none" strokeLinecap="round"/>
                  <text x="40" y="-48" fontFamily="JetBrains Mono, monospace" fontSize="10" fill={FPAL.dim}
                    style={{ animation: 'rk-zzz 1.8s ease-in-out infinite' }}>z</text>
                </>
              ) : (
                <>
                  <circle cx="8" cy="-40" r="7" fill={FPAL.white}/>
                  <circle cx="26" cy="-40" r="7" fill={FPAL.white}/>
                  <circle cx={8 + (chomping ? 1 : 2)} cy="-38" r="3.2" fill={FPAL.bgDeep}/>
                  <circle cx={26 + (chomping ? 1 : 2)} cy="-38" r="3.2" fill={FPAL.bgDeep}/>
                </>
              )}

              {/* mouth */}
              <g transform="translate(17 -26)">
                <ellipse cx="0" cy="0" rx="11" ry={mouthOpen} fill={FPAL.bgDeep}/>
                {!asleep && mouthOpen > 12 && (
                  <>
                    {/* teeth */}
                    <path d="M -9 -6 l 3 4 l 3 -4 l 3 4 l 3 -4 l 3 4 l 3 -4" stroke={FPAL.white} strokeWidth="1.4" fill="none"/>
                    {/* tongue */}
                    <ellipse cx="0" cy={mouthOpen * 0.45} rx="6" ry="3.5" fill={FPAL.magenta}/>
                  </>
                )}
              </g>
            </g>
            </g>

            {/* belly meter, vertical, right side */}
            <g transform={`translate(${W - 26} 18)`}>
              <text x="6" y="-4" textAnchor="middle" fontFamily="JetBrains Mono, monospace" fontSize="7" fill={FPAL.dim} letterSpacing="1">BELLY</text>
              <rect x="0" y="0" width="12" height="72" rx="3" fill="none" stroke={FPAL.dim2} strokeWidth="1"/>
              <rect x="2" y={2 + (72 - 4) * (1 - belly / 100)} width="8" height={(72 - 4) * (belly / 100)} rx="2"
                fill={belly > 75 ? FPAL.magenta : FPAL.cyan}/>
            </g>
          </svg>
        </div>

        {/* stat strip */}
        <div style={{
          marginTop: 10, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end',
          fontFamily: 'JetBrains Mono, monospace',
        }}>
          <div>
            <div style={{ fontSize: 9, color: FPAL.dim, letterSpacing: 1.5 }}>↓ EATEN</div>
            <div style={{ fontSize: 20, fontWeight: 700, color: FPAL.cyan, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>
              {eaten.toFixed(1)}<span style={{ fontSize: 10, color: FPAL.dim, marginLeft: 3 }}>MB</span>
            </div>
          </div>
          <div style={{ textAlign: 'center', color: FPAL.dim, fontSize: 9, letterSpacing: 1, paddingBottom: 2 }}>
            {state === 'connected' ? fmtTimeF(secs) : state === 'connecting' ? 'sniffing…' : 'asleep'}
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 9, color: FPAL.dim, letterSpacing: 1.5 }}>↑ BURPED</div>
            <div style={{ fontSize: 20, fontWeight: 700, color: FPAL.magentaHi, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>
              {burped.toFixed(1)}<span style={{ fontSize: 10, color: FPAL.dim, marginLeft: 3 }}>MB</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── FooterTugWar — YOU vs THE WATCHER, hauling traffic across the firewall ──
// The brand line made literal: "a VPN by you, against them." You (magenta)
// play tug-of-war against a surveillance eyeball-on-legs over a rope that
// crosses the firewall. Your throughput is ground you reel in — connect and
// you drag the marker onto your side until the Watcher eats dirt.
const clampF = (v, a, b) => Math.max(a, Math.min(b, v));

function FooterTugWar({ state, secs }) {
  const W = 320, H = 132;
  const FIRE = 160;                 // firewall x (center)
  const ROPE_Y = 64;
  const YOU_HAND = { x: 70, y: 64 };
  const THEM_HAND = { x: 250, y: 64 };
  const FLOOR = 104;

  const posRef = useRefF(0.55);     // -1 you fully win .. +1 watcher wins
  const packetsRef = useRefF([]);
  const yankRef = useRefF(0);
  const lastSpawnRef = useRefF(0);
  const seedRef = useRefF(3);
  const [, tick] = useStateF(0);
  const [ground, setGround] = useStateF(0);
  const dispRef = useRefF({ pos: 0.55, pull: 0.15 });

  const rnd = () => { const x = Math.sin(seedRef.current++) * 43758.5453; return x - Math.floor(x); };

  useEffectF(() => { if (state === 'idle') { posRef.current = 0.55; packetsRef.current = []; setGround(0); } }, [state]);

  useEffectF(() => {
    let raf, prev = performance.now();
    const loop = (now) => {
      const dt = Math.min(64, now - prev); prev = now; const f = dt / 16;
      const target = state === 'idle' ? 0.55 : state === 'connecting' ? 0.0 : -0.92;
      const ease = state === 'connected' ? 0.010 : 0.05;
      posRef.current += (target - posRef.current) * ease * f;

      // spawn data packets travelling from the Watcher toward YOU when winning
      if (state === 'connecting' || state === 'connected') {
        const gap = state === 'connecting' ? 420 : 560;
        if (now - lastSpawnRef.current > gap + rnd() * 280) {
          lastSpawnRef.current = now;
          packetsRef.current.push({ id: now + rnd(), u: 0, size: 0.4 + rnd() * 2.4, color: rnd() > 0.5 ? FPAL.cyan : FPAL.magenta });
        }
      }
      let arrived = 0;
      packetsRef.current = packetsRef.current.filter(p => {
        p.u += (0.0011 + p.size * 0.0002) * dt;
        if (p.u >= 1) { arrived += p.size; return false; }
        return true;
      });
      if (arrived > 0) {
        setGround(g => g + arrived);
        posRef.current = clampF(posRef.current - arrived * 0.04, -1, 1);
        yankRef.current = now;
      }

      const sinceYank = now - yankRef.current;
      dispRef.current = {
        pos: clampF(posRef.current, -1, 1),
        pull: state === 'connecting' ? 0.85 : sinceYank < 220 ? 1 : state === 'connected' ? 0.45 : 0.12,
      };
      tick(t => (t + 1) % 1e6);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [state]);

  const { pos, pull } = dispRef.current;
  const youWin = pos < 0;
  const markerX = FIRE + pos * 78;
  const youPct = Math.round((1 - pos) / 2 * 100);
  const defeated = pos <= -0.86;        // watcher hauled fully over
  const overrun = pos >= 0.5;           // you're losing badly (idle)

  const status = state === 'idle' ? 'OUTGUNNED'
               : state === 'connecting' ? 'TAKING THE STRAIN…'
               : defeated ? 'FLAWLESS' : 'WINNING';
  const statusColor = state === 'idle' ? FPAL.red
                    : state === 'connecting' ? FPAL.yellow
                    : FPAL.cyan;

  // YOU figure — heels dug in, leaning away from the firewall (to the left)
  const youLean = (youWin ? 9 : 3) + pull * 7;
  const youSlide = Math.max(0, pos) * 10;               // shoved back when losing
  const yX = 50 + youSlide;
  const youHip = { x: yX, y: 86 }, youSh = { x: yX - youLean, y: 64 }, youHead = { x: yX - youLean * 1.25, y: 53 };

  // WATCHER (eyeball on legs) — leans right when winning, dragged left when losing
  const themSlide = Math.max(0, -pos) * 22;             // hauled toward firewall
  const tX = 270 - themSlide;
  const themLean = defeated ? -10 : (pos > 0 ? 8 : 3) + pull * 6;
  const irisDX = -4 - pull * 2;                          // looking at the rope

  return (
    <div style={{ padding: '0 20px 36px', position: 'relative', zIndex: 2 }}>
      <div style={{
        background: 'rgba(255,255,255,0.04)', border: `1px solid ${FPAL.dim2}`,
        borderRadius: 18, padding: 14, backdropFilter: 'blur(10px)',
      }}>
        {/* header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: FPAL.dim, letterSpacing: 2 }}>
            // TUG OF WAR · YOU vs THEM
          </span>
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, letterSpacing: 2, color: statusColor }}>
            {status}
          </span>
        </div>

        {/* arena */}
        <div style={{ background: FPAL.bgDeep, border: `1px solid ${FPAL.dim2}`, borderRadius: 10, overflow: 'hidden' }}>
          <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: 'block' }}>
            {/* floor */}
            <line x1="0" y1={FLOOR} x2={W} y2={FLOOR} stroke={FPAL.dim2} strokeWidth="1"/>

            {/* firewall line */}
            <line x1={FIRE} y1="20" x2={FIRE} y2={FLOOR} stroke={youWin ? FPAL.cyan : FPAL.dim} strokeWidth="1" strokeDasharray="3 4" opacity="0.7"/>
            <text x={FIRE} y="16" textAnchor="middle" fontFamily="JetBrains Mono, monospace" fontSize="7" letterSpacing="2"
              fill={youWin ? FPAL.cyan : FPAL.dim}>FIREWALL</text>

            {/* rope */}
            <path d={`M ${YOU_HAND.x} ${YOU_HAND.y} Q ${(YOU_HAND.x + markerX) / 2} ${ROPE_Y + 7} ${markerX} ${ROPE_Y}
                      Q ${(markerX + THEM_HAND.x) / 2} ${ROPE_Y + 7} ${THEM_HAND.x} ${THEM_HAND.y}`}
              fill="none" stroke={FPAL.dim} strokeWidth="2.4" strokeLinecap="round"/>

            {/* data packets reeling along the rope */}
            {packetsRef.current.map(p => {
              const x = THEM_HAND.x + (YOU_HAND.x - THEM_HAND.x) * p.u;
              const y = ROPE_Y + 7 * Math.sin(Math.PI * (1 - Math.abs(0.5 - p.u) * 2)) - 3;
              return <rect key={p.id} x={x - 4} y={y - 4} width="8" height="8" rx="1.5" fill="none" stroke={p.color} strokeWidth="1.5"
                transform={`rotate(${(p.u * 180) % 90} ${x} ${y})`}/>;
            })}

            {/* center knot + pennant (leader's colour) */}
            <g transform={`translate(${markerX} ${ROPE_Y})`}>
              <path d={`M 1 -3 L ${youWin ? 16 : -16} -10 L 1 -17 Z`} fill={youWin ? FPAL.magenta : FPAL.cyan}/>
              <rect x="-3.5" y="-3.5" width="7" height="7" rx="1.5" fill={FPAL.white} transform="rotate(45)"/>
            </g>

            {/* YOU — magenta scrapper */}
            <g style={{ animation: pull > 0.7 ? 'rk-belch 0.2s steps(2) infinite' : 'none' }}>
              {/* back + front leg, braced */}
              <line x1={youHip.x} y1={youHip.y} x2={yX - 16} y2={FLOOR} stroke={FPAL.magenta} strokeWidth="5" strokeLinecap="round"/>
              <line x1={youHip.x} y1={youHip.y} x2={yX + 8} y2={FLOOR} stroke={FPAL.magenta} strokeWidth="5" strokeLinecap="round"/>
              {/* torso */}
              <line x1={youHip.x} y1={youHip.y} x2={youSh.x} y2={youSh.y} stroke={FPAL.magenta} strokeWidth="7" strokeLinecap="round"/>
              {/* arms to rope */}
              <line x1={youSh.x} y1={youSh.y} x2={YOU_HAND.x} y2={YOU_HAND.y} stroke={FPAL.magenta} strokeWidth="5" strokeLinecap="round"/>
              {/* head */}
              <circle cx={youHead.x} cy={youHead.y} r="9" fill={FPAL.magenta}/>
              {/* tiny stamp glint on head */}
              <circle cx={youHead.x - 3} cy={youHead.y - 2} r="2" fill={FPAL.bgDeep} opacity="0.5"/>
              {/* effort grunt */}
              {pull > 0.6 && <text x={youHead.x - 14} y={youHead.y - 10} fontFamily="JetBrains Mono, monospace" fontSize="9" fill={FPAL.magentaHi} opacity="0.9">!</text>}
            </g>

            {/* THE WATCHER — eyeball on legs */}
            <g transform={`rotate(${themLean} ${tX} ${FLOOR})`} style={{ animation: pull > 0.7 && !defeated ? 'rk-belch 0.2s steps(2) infinite' : 'none' }}>
              {/* legs */}
              <line x1={tX - 6} y1="84" x2={defeated ? tX - 16 : tX - 7} y2={FLOOR} stroke={FPAL.dim} strokeWidth="5" strokeLinecap="round"/>
              <line x1={tX + 6} y1="84" x2={defeated ? tX + 16 : tX + 7} y2={FLOOR} stroke={FPAL.dim} strokeWidth="5" strokeLinecap="round"/>
              {/* arms gripping rope */}
              <line x1={tX - 10} y1="72" x2={THEM_HAND.x} y2={THEM_HAND.y} stroke={FPAL.dim} strokeWidth="5" strokeLinecap="round"/>
              <line x1={tX + 4} y1="74" x2={THEM_HAND.x + 4} y2={THEM_HAND.y + 5} stroke={FPAL.dim} strokeWidth="4" strokeLinecap="round"/>
              {/* eyeball body */}
              <circle cx={tX} cy="68" r="16" fill={FPAL.white} stroke={FPAL.dim2} strokeWidth="1.5"/>
              {defeated ? (
                <>
                  {/* X-ed out eye */}
                  <line x1={tX - 6} y1="62" x2={tX + 6} y2="74" stroke={FPAL.red} strokeWidth="2.4" strokeLinecap="round"/>
                  <line x1={tX + 6} y1="62" x2={tX - 6} y2="74" stroke={FPAL.red} strokeWidth="2.4" strokeLinecap="round"/>
                </>
              ) : (
                <>
                  <circle cx={tX + irisDX} cy="68" r="7" fill={FPAL.cyan}/>
                  <circle cx={tX + irisDX} cy="68" r="3" fill={FPAL.bgDeep}/>
                  {/* worried sweat when losing */}
                  {pos < 0 && <path d={`M ${tX + 13} 60 q 3 5 0 8 q -3 -3 0 -8`} fill={FPAL.cyan} opacity="0.8"/>}
                </>
              )}
            </g>
          </svg>
        </div>

        {/* stat strip */}
        <div style={{
          marginTop: 10, display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          fontFamily: 'JetBrains Mono, monospace',
        }}>
          <div>
            <div style={{ fontSize: 9, color: FPAL.dim, letterSpacing: 1.5 }}>↙ REELED IN</div>
            <div style={{ fontSize: 20, fontWeight: 700, color: FPAL.cyan, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>
              {ground.toFixed(1)}<span style={{ fontSize: 10, color: FPAL.dim, marginLeft: 3 }}>MB</span>
            </div>
          </div>
          {/* advantage bar */}
          <div style={{ flex: 1, margin: '0 14px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 8, letterSpacing: 1, marginBottom: 3 }}>
              <span style={{ color: FPAL.magenta }}>YOU</span>
              <span style={{ color: FPAL.dim }}>THEM</span>
            </div>
            <div style={{ height: 6, borderRadius: 3, background: FPAL.dim2, position: 'relative', overflow: 'hidden' }}>
              <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${youPct}%`, background: FPAL.magenta, transition: 'width 0.1s linear' }}/>
            </div>
            <div style={{ textAlign: 'center', fontSize: 8, color: FPAL.dim, marginTop: 3, letterSpacing: 1 }}>
              {state === 'connected' ? `${fmtTimeF(secs)} HELD` : state === 'connecting' ? 'bracing…' : 'rope slipping'}
            </div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 9, color: FPAL.dim, letterSpacing: 1.5 }}>ADVANTAGE</div>
            <div style={{ fontSize: 20, fontWeight: 700, color: youWin ? FPAL.magentaHi : FPAL.dim, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>
              {youPct}<span style={{ fontSize: 10, color: FPAL.dim, marginLeft: 2 }}>%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { FooterMap, FooterReceipt, FooterPet, FooterMonster, FooterTugWar });
