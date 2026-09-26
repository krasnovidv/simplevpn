// RKNPNH redesign — three hero "connect" objects. mood: idle | connecting | connected | error
const { useRef: useHR, useState: useHS } = React;
const useUid = (p) => { const r = useHR(null); if (!r.current) r.current = p + Math.random().toString(36).slice(2, 8); return r.current; };
const lerp = (a, b, k) => a + (b - a) * k;

// ─── 1. CHROME — liquid-metal metaballs that fuse into a holo sphere ───
function ChromeHero({ T, mood, size = 280, pressed }) {
  const t = useTime(); const id = useUid('ch');
  const st = useHR({ spread: 0.3, speed: 0.4, rot: 0, main: 0.28, last: t, drip: 0 });
  const s = st.current; const dt = Math.min(0.05, Math.max(0, t - s.last)); s.last = t;
  const tgt = { idle: [0.3, 0.5, 0.27, 0], connecting: [0.42, 3.2, 0.24, 0], connected: [0.02, 0.6, 0.33, 0], disconnecting: [0.38, 1.6, 0.26, 0], error: [0.2, 0.15, 0.25, 1] }[mood];
  s.spread = lerp(s.spread, tgt[0], 0.06); s.speed = lerp(s.speed, tgt[1], 0.05); s.main = lerp(s.main, tgt[2], 0.08); s.drip = lerp(s.drip, tgt[3], 0.05);
  s.rot += dt * s.speed;
  const S = size, C = S / 2;
  const sats = [0, 1, 2, 3].map(i => {
    const a = s.rot + i * Math.PI / 2 + Math.sin(t * 0.9 + i) * 0.3;
    const d = S * (s.spread + 0.04 * Math.sin(t * 1.7 + i * 2));
    const dripY = s.drip * (S * 0.2 + i * S * 0.06);
    return { x: C + Math.cos(a) * d * (1 - s.drip * 0.6), y: C + Math.sin(a) * d * 0.9 * (1 - s.drip) + dripY, r: S * (0.12 + 0.03 * ((i % 2) ? 1 : 0.4)) };
  });
  const pal = {
    idle: ['#FFFFFF', '#D6DAE6', '#474B61', '#9AA0B8', '#F4F5FB'],
    connecting: ['#FFFFFF', '#CFE9FF', '#3B3F66', '#B7A9FF', '#FFF4FB'],
    connected: ['#FFFFFF', '#B8F4FF', '#5E4BFF', '#FF9EE6', '#FFF6C9'],
    disconnecting: ['#FFFFFF', '#DCDDE8', '#45485E', '#A7A2C9', '#F5F4FB'],
    error: ['#F4ECEC', '#C7B0B0', '#5A3B3B', '#B99494', '#F1E6E6'],
  }[mood];
  const holo = mood === 'connected' ? 0.55 : mood === 'connecting' ? 0.35 : mood === 'disconnecting' ? 0.15 : 0.08;
  const main = { x: C, y: C + s.drip * S * 0.06 + Math.sin(t * 1.2) * 3, r: S * s.main * (1 + 0.02 * Math.sin(t * 2.3)) };
  // ── ripples: periodic + on tap ──
  if (!s.ripples) { s.ripples = []; s.next = t + 0.8; }
  const period = { idle: 3.8, connecting: 1.1, connected: 2.6, disconnecting: 1.6, error: 0 }[mood];
  if (period && t > s.next) { s.ripples.push({ t0: t, x: (Math.random() - 0.5) * 0.25, y: (Math.random() - 0.5) * 0.25, k: 5 + Math.floor(Math.random() * 4) }); s.next = t + period * (0.7 + Math.random() * 0.6); }
  if (pressed && !s.wasPressed) s.ripples.push({ t0: t, x: 0, y: 0, k: 8, big: 1 });
  s.wasPressed = pressed;
  s.ripples = s.ripples.filter(r => t - r.t0 < 1.8);
  let env = 0;
  s.ripples.forEach(r => { env += Math.exp(-(t - r.t0) * 2.6) * (r.big ? 1.4 : 1); });
  env = Math.min(env, 1.6);
  const N = 72;
  const mainPath = 'M' + Array.from({ length: N }).map((_, i) => {
    const th = (i / N) * Math.PI * 2;
    let k = 1 + 0.012 * Math.sin(3 * th + t * 1.5);
    s.ripples.forEach(r => { const a = t - r.t0; k += 0.075 * Math.exp(-a * 2.6) * (r.big ? 1.4 : 1) * Math.sin(r.k * th - a * 14); });
    return (main.x + Math.cos(th) * main.r * k).toFixed(1) + ' ' + (main.y + Math.sin(th) * main.r * k).toFixed(1);
  }).join(' L') + 'Z';
  const disp = 3 + 24 * env;
  return (
    <svg width={S} height={S} viewBox={`0 0 ${S} ${S}`} style={{ overflow: 'visible', display: 'block' }}>
      <defs>
        <filter id={id + 'g'} x="-30%" y="-30%" width="160%" height="160%">
          <feGaussianBlur stdDeviation={S * 0.035}></feGaussianBlur>
          <feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 24 -10"></feColorMatrix>
        </filter>
        <mask id={id + 'm'} maskUnits="userSpaceOnUse" x={-S} y={-S} width={S * 3} height={S * 3}>
          <g filter={`url(#${id}g)`} fill="#fff">
            <path d={mainPath}></path>
            {sats.map((p, i) => <circle key={i} cx={p.x} cy={p.y} r={p.r}></circle>)}
          </g>
        </mask>
        <linearGradient id={id + 'c'} x1="0" y1="0" x2="0" y2="1" gradientTransform={`rotate(${Math.sin(t * 0.7) * 12} .5 .5)`}>
          {[0, 0.42, 0.5, 0.6, 1].map((o, i) => <stop key={i} offset={o} style={{ stopColor: pal[i], transition: 'stop-color .8s' }}></stop>)}
        </linearGradient>
        <linearGradient id={id + 'h'} x1="0" y1="0" x2="1" y2="1" gradientTransform={`rotate(${t * 50} .5 .5)`}>
          <stop offset="0" stopColor="#FF6BD6"></stop><stop offset=".33" stopColor="#6BF0FF"></stop><stop offset=".66" stopColor="#D4FF6B"></stop><stop offset="1" stopColor="#FF6BD6"></stop>
        </linearGradient>
        <filter id={id + 'd'} x="-20%" y="-20%" width="140%" height="140%">
          <feTurbulence type="fractalNoise" baseFrequency={`${0.012 + 0.004 * Math.sin(t * 0.7)} ${0.03 + 0.006 * Math.cos(t * 0.5)}`} numOctaves="2" seed="7"></feTurbulence>
          <feDisplacementMap in="SourceGraphic" scale={disp} xChannelSelector="R" yChannelSelector="G"></feDisplacementMap>
        </filter>
        <radialGradient id={id + 'spec'}><stop offset="0" stopColor="#fff" stopOpacity="1"></stop><stop offset=".45" stopColor="#fff" stopOpacity=".55"></stop><stop offset="1" stopColor="#fff" stopOpacity="0"></stop></radialGradient>
        <radialGradient id={id + 'glow'}><stop offset="0" stopColor={T.accent} stopOpacity=".55"></stop><stop offset="1" stopColor={T.accent} stopOpacity="0"></stop></radialGradient>
      </defs>
      {mood === 'connected' && <circle cx={C} cy={C} r={S * 0.55 * (1 + 0.04 * Math.sin(t * 2))} fill={`url(#${id}glow)`}></circle>}
      {mood === 'connecting' && <ellipse cx={C} cy={C} rx={S * 0.48} ry={S * 0.16} fill="none" stroke={T.accent} strokeWidth="1.5" strokeDasharray="4 8" transform={`rotate(${t * 120} ${C} ${C})`} opacity=".7"></ellipse>}
      <g mask={`url(#${id}m)`}>
        <g filter={`url(#${id}d)`}>
          <rect x={-S * 0.2} y={-S * 0.2} width={S * 1.4} height={S * 1.4} fill={`url(#${id}c)`}></rect>
          <rect x={-S * 0.2} y={-S * 0.2} width={S * 1.4} height={S * 1.4} fill={`url(#${id}h)`} opacity={Math.min(0.8, holo + env * 0.25)} style={{ mixBlendMode: 'color', transition: 'opacity .8s' }}></rect>
          {s.ripples.map((r, ri) => {
            const a = t - r.t0, fade = Math.max(0, 1 - a / 1.8);
            return [0, 1, 2].map(k => {
              const rr = (a * (r.big ? 1.15 : 0.95) - k * 0.13) * S * 0.5;
              if (rr <= 2) return null;
              const cx = C + r.x * S, cy = C + r.y * S;
              return <g key={ri + '-' + k}>
                <circle cx={cx} cy={cy} r={rr} fill="none" stroke="#fff" strokeWidth={3.2 - k * 0.8} opacity={0.7 * fade}></circle>
                <circle cx={cx} cy={cy} r={Math.max(1, rr - 5)} fill="none" stroke={T.dark ? '#1a1b3a' : '#3b3f66'} strokeWidth={1.6 - k * 0.3} opacity={0.35 * fade}></circle>
              </g>;
            });
          })}
        </g>
        {(() => {
          // soft specular that orbits with a slow virtual light, stretches along the surface, and flares on ripples
          const la = -2.2 + Math.sin(t * 0.35) * 0.9 + s.rot * 0.15;
          const lx = main.x + Math.cos(la) * main.r * 0.48, ly = main.y + Math.sin(la) * main.r * 0.48;
          const ang = (la * 180 / Math.PI) + 90;
          const w = main.r * (0.5 + 0.08 * Math.sin(t * 0.9)) * (1 + env * 0.25), hgt = main.r * (0.2 + 0.04 * Math.cos(t * 1.3));
          const op = (mood === 'error' ? 0.25 : 0.5) + env * 0.25;
          const ra = la + Math.PI, rx = main.x + Math.cos(ra) * main.r * 0.7, ry = main.y + Math.sin(ra) * main.r * 0.7;
          return <g style={{ mixBlendMode: 'screen' }}>
            <ellipse cx={lx} cy={ly} rx={w} ry={hgt} fill={`url(#${id}spec)`} opacity={op} transform={`rotate(${ang} ${lx} ${ly})`}></ellipse>
            <ellipse cx={rx} cy={ry} rx={main.r * 0.55} ry={main.r * 0.12} fill={`url(#${id}spec)`} opacity={0.18 + env * 0.15} transform={`rotate(${ang} ${rx} ${ry})`}></ellipse>
          </g>;
        })()}
      </g>
    </svg>
  );
}

// ─── 2. ACID — wireframe globe with a surveillance eye → sunglasses ───
function AcidHero({ T, mood, size = 280 }) {
  const t = useTime(); const id = useUid('ac');
  const S = size, C = S / 2, R = S * 0.36;
  const dur = { idle: 9, connecting: 1.1, connected: 5, error: 0 }[mood];
  const col = mood === 'error' ? T.sub : T.ink;
  const ring = mood === 'connected' ? '• ТЕБЯ НЕТ • ТЕБЯ НЕТ • ТЕБЯ НЕТ ' : mood === 'error' ? '• НЕТ СЕТИ • НЕТ СЕТИ • НЕТ СЕТИ ' : '• ЖМИ • СПРЯЧЬСЯ • ЖМИ • СПРЯЧЬСЯ ';
  const look = { x: Math.sin(t * 0.8) * R * 0.14 + Math.sin(t * 2.3) * 3, y: Math.cos(t * 0.6) * R * 0.08 };
  const blink = (t % 3.4) < 0.12 ? 0.1 : 1;
  return (
    <svg width={S} height={S} viewBox={`0 0 ${S} ${S}`} style={{ overflow: 'visible', display: 'block' }}>
      <defs>
        <path id={id + 'p'} d={`M ${C} ${C} m -${R + 30} 0 a ${R + 30} ${R + 30} 0 1 1 ${2 * (R + 30)} 0 a ${R + 30} ${R + 30} 0 1 1 -${2 * (R + 30)} 0`}></path>
        <radialGradient id={id + 'f'} cx=".35" cy=".3"><stop offset="0" stopColor={T.accent3} stopOpacity=".5"></stop><stop offset="1" stopColor={T.accent3} stopOpacity="0.05"></stop></radialGradient>
        <clipPath id={id + 'cl'}><circle cx={C} cy={C} r={R}></circle></clipPath>
      </defs>
      <g style={{ display: S < 170 ? 'none' : 'block', transformOrigin: `${C}px ${C}px`, animation: mood === 'error' ? 'none' : `y2k-spin ${mood === 'connecting' ? 4 : 18}s linear infinite` }}>
        <text fontFamily="'Dela Gothic One', sans-serif" fontSize="15" letterSpacing="3" fill={mood === 'connected' ? T.accent2 : col}>
          <textPath href={`#${id}p`}>{ring}</textPath>
        </text>
      </g>
      <circle cx={C} cy={C} r={R} fill={`url(#${id}f)`} stroke={col} strokeWidth="2.5"></circle>
      <g clipPath={`url(#${id}cl)`} stroke={col} strokeWidth="1.4" fill="none" opacity=".7">
        {[-0.66, -0.33, 0, 0.33, 0.66].map((k, i) => <ellipse key={i} cx={C} cy={C + k * R} rx={R * Math.sqrt(1 - k * k)} ry={R * 0.12 * Math.sqrt(1 - k * k)}></ellipse>)}
        {[0, 1, 2, 3, 4, 5].map(i => (
          <ellipse key={i} cx={C} cy={C} rx={R} ry={R} style={{ transformOrigin: `${C}px ${C}px`, transformBox: 'view-box',
            animation: dur ? `y2k-meridian ${dur}s linear ${-(i / 6) * dur}s infinite` : 'none', transform: dur ? undefined : `scaleX(${Math.cos(i / 6 * Math.PI)})` }}></ellipse>
        ))}
      </g>
      {/* face */}
      <g transform={`translate(${C} ${C})`}>
        {mood === 'idle' && (<g>
          <path d={`M ${-R * 0.55} 0 Q 0 ${-R * 0.5 * blink} ${R * 0.55} 0 Q 0 ${R * 0.5 * blink} ${-R * 0.55} 0 Z`} fill="#fff" stroke={T.dark ? T.bg : T.ink} strokeWidth="3"></path>
          {blink > 0.5 && <><circle cx={look.x} cy={look.y} r={R * 0.2} fill={T.accent2}></circle><circle cx={look.x} cy={look.y} r={R * 0.09} fill="#0D0917"></circle><circle cx={look.x - 5} cy={look.y - 5} r="3" fill="#fff"></circle></>}
        </g>)}
        {mood === 'connecting' && (<g style={{ animation: 'y2k-shake .15s linear infinite' }}>
          <path d={`M ${-R * 0.5} 0 Q 0 ${-R * 0.08} ${R * 0.5} 0 Q 0 ${R * 0.08} ${-R * 0.5} 0 Z`} fill="#fff" stroke={T.dark ? T.bg : T.ink} strokeWidth="3"></path>
          <text x={R * 0.45} y={-R * 0.3} fontFamily="'Dela Gothic One'" fontSize="26" fill={T.accent2}>!?</text>
        </g>)}
        {mood === 'connected' && (<g>
          <rect x={-R * 0.62} y={-R * 0.2} width={R * 0.54} height={R * 0.32} rx={R * 0.12} fill="#0D0917" stroke={T.accent} strokeWidth="2"></rect>
          <rect x={R * 0.08} y={-R * 0.2} width={R * 0.54} height={R * 0.32} rx={R * 0.12} fill="#0D0917" stroke={T.accent} strokeWidth="2"></rect>
          <path d={`M ${-R * 0.08} ${-R * 0.1} h ${R * 0.16}`} stroke={T.accent} strokeWidth="3"></path>
          <rect x={-R * 0.55 + ((t * 60) % (R * 1.4))} y={-R * 0.18} width="5" height={R * 0.28} fill="#fff" opacity=".7" transform="skewX(-20)"></rect>
          <path d={`M ${-R * 0.18} ${R * 0.36} Q ${R * 0.05} ${R * 0.5} ${R * 0.28} ${R * 0.3}`} stroke={T.accent} strokeWidth="4" fill="none" strokeLinecap="round"></path>
        </g>)}
        {mood === 'error' && (<g stroke={T.bad} strokeWidth="5" strokeLinecap="round">
          <path d={`M ${-R * 0.45} ${-R * 0.18} l ${R * 0.24} ${R * 0.24} m 0 ${-R * 0.24} l ${-R * 0.24} ${R * 0.24}`}></path>
          <path d={`M ${R * 0.21} ${-R * 0.18} l ${R * 0.24} ${R * 0.24} m 0 ${-R * 0.24} l ${-R * 0.24} ${R * 0.24}`}></path>
          <path d={`M ${-R * 0.2} ${R * 0.38} q ${R * 0.1} ${-R * 0.1} ${R * 0.2} 0 t ${R * 0.2} 0`} fill="none" strokeWidth="4"></path>
        </g>)}
      </g>
      {mood !== 'error' && [0, 1, 2].map(i => {
        const a = t * (mood === 'connecting' ? 3 : 0.8) + i * 2.1;
        return <text key={i} x={C + Math.cos(a) * (R + 8)} y={C + Math.sin(a) * (R * 0.35) + 6} fontSize={16 + i * 4} fill={i % 2 ? T.accent2 : T.accent} textAnchor="middle" opacity={Math.sin(a) > -0.2 ? 1 : 0.25}>✦</text>;
      })}
    </svg>
  );
}

// ─── 3. JELLY — squishy candy blob with a face; morphs shape per mood ───
function JellyHero({ T, mood, size = 280, pressed }) {
  const t = useTime(); const id = useUid('jl');
  const N = 96, S = size, C = S / 2, R0 = S * 0.34;
  const st = useHR(null);
  if (!st.current) st.current = { r: Array(N).fill(1), sq: 1 };
  const cfg = { idle: [9, 0.05, 0.3], connecting: [6, 0.11, 2.4], connected: [12, 0.035, 0.5], error: [4, 0.025, 0.1] }[mood];
  const rs = st.current.r;
  for (let i = 0; i < N; i++) {
    const th = (i / N) * Math.PI * 2;
    const target = 1 + cfg[1] * Math.cos(cfg[0] * th + t * cfg[2]) + 0.025 * Math.sin(3 * th - t * 1.3);
    rs[i] = lerp(rs[i], target, 0.1);
  }
  st.current.sq = lerp(st.current.sq, pressed ? 0.86 : 1, 0.25);
  const breathe = mood === 'connecting' ? 1 + 0.05 * Math.sin(t * 14) : 1 + 0.03 * Math.sin(t * 2.2);
  const sx = (mood === 'error' ? 1.1 : 1) * (2 - st.current.sq) * breathe, sy = (mood === 'error' ? 0.88 : 1) * st.current.sq * breathe;
  const pts = rs.map((r, i) => { const th = (i / N) * Math.PI * 2; return [Math.cos(th) * R0 * r * sx, Math.sin(th) * R0 * r * sy]; });
  const d = 'M' + pts.map(p => p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' L') + 'Z';
  const body = { idle: T.accent, connecting: T.accent3, connected: T.accent2, error: T.dark ? '#6E5A80' : '#C9B6D6' }[mood];
  const f = T.face; const blink = (t % 3) < 0.14;
  const bob = mood === 'connected' ? Math.sin(t * 3) * 6 : 0;
  return (
    <svg width={S} height={S} viewBox={`${-C} ${-C} ${S} ${S}`} style={{ overflow: 'visible', display: 'block' }}>
      <defs>
        <radialGradient id={id + 'b'} cx=".35" cy=".28" r=".85">
          <stop offset="0" style={{ stopColor: '#fff', stopOpacity: 0.85 }}></stop>
          <stop offset=".35" style={{ stopColor: body, transition: 'stop-color .6s' }}></stop>
          <stop offset="1" style={{ stopColor: body, transition: 'stop-color .6s', filter: 'brightness(.7)' }}></stop>
        </radialGradient>
        <filter id={id + 's'} x="-50%" y="-50%" width="200%" height="200%"><feDropShadow dx="0" dy="18" stdDeviation="14" floodColor={body} floodOpacity=".45"></feDropShadow></filter>
      </defs>
      <ellipse cx="0" cy={R0 * 1.25} rx={R0 * 0.8 * sx} ry={R0 * 0.12} fill={T.dark ? '#000' : body} opacity=".18"></ellipse>
      <g transform={`translate(0 ${-Math.abs(bob)})`}>
        <path d={d} fill={`url(#${id}b)`} filter={`url(#${id}s)`}></path>
        <path d={d} fill="none" stroke="rgba(0,0,0,0.12)" strokeWidth="2" transform="scale(.97) translate(0 4)"></path>
        <ellipse cx={-R0 * 0.38} cy={-R0 * 0.52} rx={R0 * 0.28} ry={R0 * 0.14} fill="#fff" opacity=".7" transform={`rotate(-28 ${-R0 * 0.38} ${-R0 * 0.52})`}></ellipse>
        <circle cx={-R0 * 0.08} cy={-R0 * 0.66} r={R0 * 0.05} fill="#fff" opacity=".85"></circle>
        {/* face */}
        <g stroke={f} strokeWidth="6" strokeLinecap="round" fill="none" transform={`translate(0 ${R0 * 0.05})`}>
          {mood === 'idle' && (<>
            <path d={blink ? `M -${R0 * 0.42} -4 h ${R0 * 0.22} M ${R0 * 0.2} -4 h ${R0 * 0.22}` : `M -${R0 * 0.42} -6 h ${R0 * 0.22} M ${R0 * 0.2} -6 h ${R0 * 0.22}`}></path>
            <path d={`M -${R0 * 0.12} ${R0 * 0.3} h ${R0 * 0.24}`}></path>
          </>)}
          {mood === 'connecting' && (<>
            <path d={`M -${R0 * 0.42} -${R0 * 0.14} l ${R0 * 0.16} ${R0 * 0.1} l -${R0 * 0.16} ${R0 * 0.1} M ${R0 * 0.42} -${R0 * 0.14} l -${R0 * 0.16} ${R0 * 0.1} l ${R0 * 0.16} ${R0 * 0.1}`}></path>
            <ellipse cx="0" cy={R0 * 0.32} rx={R0 * 0.08} ry={R0 * 0.1} fill={f}></ellipse>
          </>)}
          {mood === 'connected' && (<>
            <path d={`M -${R0 * 0.44} -2 q ${R0 * 0.12} -${R0 * 0.18} ${R0 * 0.24} 0 M ${R0 * 0.2} -2 q ${R0 * 0.12} -${R0 * 0.18} ${R0 * 0.24} 0`}></path>
            <path d={`M -${R0 * 0.26} ${R0 * 0.18} q ${R0 * 0.26} ${R0 * 0.34} ${R0 * 0.52} 0 z`} fill={f}></path>
            <ellipse cx={-R0 * 0.56} cy={R0 * 0.16} rx={R0 * 0.12} ry={R0 * 0.06} fill="#FF7FB8" stroke="none" opacity=".75"></ellipse>
            <ellipse cx={R0 * 0.56} cy={R0 * 0.16} rx={R0 * 0.12} ry={R0 * 0.06} fill="#FF7FB8" stroke="none" opacity=".75"></ellipse>
          </>)}
          {mood === 'error' && (<>
            <circle cx={-R0 * 0.3} cy="-4" r="5" fill={f}></circle><circle cx={R0 * 0.3} cy="-4" r="5" fill={f}></circle>
            <path d={`M -${R0 * 0.2} ${R0 * 0.34} q ${R0 * 0.1} -${R0 * 0.12} ${R0 * 0.2} 0 t ${R0 * 0.2} 0`} transform={`translate(-${R0 * 0.1} 0)`}></path>
            <path d={`M ${R0 * 0.34} ${R0 * 0.06 + ((t * 30) % 30)} q 6 10 0 14 q -6 -4 0 -14`} fill={T.accent2} stroke="none" opacity=".9"></path>
          </>)}
        </g>
      </g>
      {mood === 'connected' && [0, 1, 2, 3, 4].map(i => {
        const p = ((t * 0.35 + i / 5) % 1);
        return <circle key={i} cx={Math.sin(i * 2.4 + t) * R0 * 1.1} cy={R0 - p * R0 * 2.6} r={4 + (i % 3) * 3} fill="none" stroke={T.accent2} strokeWidth="2" opacity={1 - p}></circle>;
      })}
    </svg>
  );
}

function Hero(props) {
  const H = { chrome: ChromeHero, acid: AcidHero, jelly: JellyHero }[props.T.dir];
  const mood = props.mood === 'disconnecting' && props.T.dir !== 'chrome' ? 'connecting' : props.mood;
  return <H {...props} mood={mood}></H>;
}

Object.assign(window, { Hero, ChromeHero, AcidHero, JellyHero });
