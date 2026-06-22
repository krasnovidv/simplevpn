// Three animated VPN main-screen variations. Each variation owns its own
// state machine (idle → connecting → connected → disconnecting) so the
// user can play with the connect button.

const { useState, useEffect, useRef } = React;

// Which footer to render. Set on window by the host page.
const getFooterKind = () => (typeof window !== 'undefined' && window.__rkFooter) || 'map';

const PAL = {
  bg:        '#120a1f',
  bgDeep:    '#0a0612',
  magenta:   '#ff2bd6',
  magentaHi: '#ff5ce0',
  cyan:      '#00f0ff',
  purple:    '#a259ff',
  yellow:    '#fff200',
  white:     '#f5f3ff',
  dim:       '#5a4a7a',
  dim2:      '#2a1f3a',
};

// inject keyframes once
if (typeof document !== 'undefined' && !document.getElementById('rk-anim')) {
  const s = document.createElement('style');
  s.id = 'rk-anim';
  s.textContent = `
    @keyframes rk-stamp-pulse { 0%,100% { transform: rotate(-7deg) scale(1); } 50% { transform: rotate(-7deg) scale(1.04); } }
    @keyframes rk-stamp-shake { 0%,100% { transform: rotate(-7deg); } 25% { transform: rotate(-10deg); } 75% { transform: rotate(-4deg); } }
    @keyframes rk-stamp-slam  { 0% { transform: rotate(-7deg) scale(2.2); opacity:0; } 60% { transform: rotate(-7deg) scale(0.92); opacity:1; } 80% { transform: rotate(-7deg) scale(1.05); } 100% { transform: rotate(-7deg) scale(1); } }
    @keyframes rk-spin       { to { transform: rotate(360deg); } }
    @keyframes rk-orbit      { to { transform: rotate(360deg); } }
    @keyframes rk-pulse-ring { 0% { transform: scale(0.6); opacity:0.6; } 100% { transform: scale(1.6); opacity:0; } }
    @keyframes rk-scan       { 0% { transform: translateY(-100%); } 100% { transform: translateY(800%); } }
    @keyframes rk-blink      { 0%,100% { opacity:1; } 50% { opacity:0.2; } }
    @keyframes rk-tick       { from { width: 0; } to { width: 100%; } }
    @keyframes rk-glitch     { 0%,100% { transform: translate(0,0); }
      20% { transform: translate(-2px,1px); }
      40% { transform: translate(2px,-1px); }
      60% { transform: translate(-1px,-1px); }
      80% { transform: translate(1px,1px); } }
    @keyframes rk-bg-shift   { 0%,100% { background-position: 0 0; } 50% { background-position: 40px 40px; } }
    @keyframes rk-fade-in    { from { opacity:0; transform: translateY(6px); } to { opacity:1; transform: translateY(0); } }
    .rk-fade { animation: rk-fade-in .35s ease both; }
  `;
  document.head.appendChild(s);
}

// Tiny SVG stamp matching icon.svg, sized via prop
function StampSVG({ size = 200, color = PAL.magenta, animation }) {
  return (
    <svg width={size} height={size} viewBox="0 0 200 200" style={{ animation, transformOrigin: '50% 50%' }}>
      <g transform="translate(100 100) rotate(-7) translate(-72 -64)">
        <rect width="144" height="128" rx="8" fill="none" stroke={color} strokeWidth="5"/>
        <rect x="5" y="5" width="134" height="118" rx="5" fill="none" stroke={color} strokeWidth="1.4" opacity="0.6"/>
        <g fill={color}>
          <circle cx="8" cy="8" r="1.8"/><circle cx="136" cy="8" r="1.8"/>
          <circle cx="8" cy="120" r="1.8"/><circle cx="136" cy="120" r="1.8"/>
        </g>
        <text x="72" y="56" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="42" fontWeight="900" fill={color} letterSpacing="2">RKN</text>
        <text x="72" y="94" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="42" fontWeight="900" fill={color} letterSpacing="2">PNH</text>
        <text x="72" y="112" textAnchor="middle" fontFamily="Space Grotesk, sans-serif" fontWeight="700" fontSize="7.5" fill={color} letterSpacing="3">★ NOT APPROVED ★</text>
      </g>
    </svg>
  );
}

// Shared connection-state hook
function useConnState() {
  const [state, setState] = useState('idle'); // idle | connecting | connected | disconnecting
  const [secs, setSecs] = useState(0);
  useEffect(() => {
    let t;
    if (state === 'connecting') t = setTimeout(() => setState('connected'), 2200);
    if (state === 'disconnecting') t = setTimeout(() => setState('idle'), 900);
    return () => clearTimeout(t);
  }, [state]);
  useEffect(() => {
    if (state !== 'connected') { setSecs(0); return; }
    const i = setInterval(() => setSecs(s => s + 1), 1000);
    return () => clearInterval(i);
  }, [state]);
  const toggle = () => {
    if (state === 'idle') setState('connecting');
    else if (state === 'connected') setState('disconnecting');
  };
  return { state, secs, toggle };
}

const fmtTime = (s) => `${String(Math.floor(s/3600)).padStart(2,'0')}:${String(Math.floor(s/60)%60).padStart(2,'0')}:${String(s%60).padStart(2,'0')}`;

// ─── Variation 1: STAMPED + SCANNER COPY hybrid — stamp visual, "TAP TO HIDE" CTA ──
function VarStamp() {
  const { state, secs, toggle } = useConnState();
  const fs = useFooterSetting(state);
  const animMap = {
    idle:          'rk-stamp-pulse 2.4s ease-in-out infinite',
    connecting:    'rk-stamp-shake 0.4s ease-in-out infinite',
    connected:     'rk-stamp-slam 0.7s cubic-bezier(.2,.7,.3,1) both, rk-stamp-pulse 2.8s ease-in-out 0.7s infinite',
    disconnecting: 'rk-stamp-shake 0.3s ease-in-out infinite',
  };
  // Connect animation takes over center area during connecting + first beats of connected
  const showAnim = state === 'connecting' || (state === 'connected' && secs < 4);
  return (
    <Screen state={state} variant="stamp">
      <Header subtitle={state === 'connected' ? 'Your traffic has been denied by us instead of them' : 'A VPN by you, against them'} onGear={() => fs.setOpen(true)}/>
      <div onClick={toggle} style={{ flex: 1, display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', cursor: 'pointer', position: 'relative' }}>
        {showAnim ? (
          <div style={{ width: 320, height: 360, display:'flex', alignItems:'center', justifyContent:'center' }}>
            <ConnectAnimEmbed state={state} secs={secs}/>
          </div>
        ) : (
          <>
            {state === 'idle' && (<><Ring delay="0s"/><Ring delay="0.8s"/><Ring delay="1.6s"/></>)}
            <StampSVG size={220} color={state === 'connected' ? PAL.cyan : PAL.magenta} animation={animMap[state]}/>
          </>
        )}
        {/* Status copy from Scanner variant */}
        <div key={state} className="rk-fade" style={{ marginTop: 24, textAlign: 'center' }}>
          <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: PAL.dim, letterSpacing: 2, marginBottom: 6 }}>
            {state==='idle' && '// STATUS: EXPOSED'}
            {state==='connecting' && '// SCANNING ROUTES…'}
            {state==='connected' && '// STATUS: HIDDEN'}
            {state==='disconnecting' && '// CLOSING TUNNEL…'}
          </div>
          <div style={{ fontFamily: 'Archivo Black, Impact, sans-serif', fontSize: 22, color: state==='connected' ? PAL.cyan : PAL.magenta, letterSpacing: 1 }}>
            {state==='idle' ? 'TAP TO HIDE' : state==='connecting' ? 'HOLD ON' : state==='connected' ? 'YOU\u2019RE GHOST' : 'BYE'}
          </div>
        </div>
      </div>
      <FooterRender kind={fs.resolved} state={state} secs={secs}/>
      <SettingsSheet open={fs.open} onClose={() => fs.setOpen(false)} pref={fs.pref} resolved={fs.resolved} onPick={fs.setPref}/>
    </Screen>
  );
}

// ── Embedded version of the connect animation (svg, looped) ────────────
function ConnectAnimEmbed({ state, secs }) {
  // Drive a local "connect anim time" — runs 0→4s; held at 5.5s when connected to show PROTECTED.
  const [t, setT] = useState(0);
  const startRef = useRef(performance.now());
  useEffect(() => {
    startRef.current = performance.now();
    let raf;
    const loop = (now) => {
      const elapsed = (now - startRef.current) / 1000;
      // Map: connecting plays 0→3.6, connected plays 3.6→6.0
      let mapped;
      if (state === 'connecting') {
        mapped = Math.min(3.6, elapsed * 1.6); // ~2.2s realtime → reach 3.6
      } else {
        mapped = Math.min(6, 3.6 + elapsed * 0.6);
      }
      setT(mapped);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [state]);
  // Render a small SVG mirroring the key beats: split logo → two simple figures → cyan stream → splash
  const W2 = 300, H2 = 340;
  const splitT = clamp((t - 0.4) / 0.8, 0, 1);
  const figT = clamp((t - 1.0) / 0.6, 0, 1);
  const streamT = clamp((t - 1.6) / 1.0, 0, 1);
  const splashT = clamp((t - 2.4) / 0.7, 0, 1);
  const healing = clamp((t - 2.6) / 0.8, 0, 1);
  const armT = clamp((t - 1.4) / 0.5, 0, 1);
  const protT = clamp((t - 3.4) / 0.4, 0, 1);

  const pnhX = 70, pnhY = H2/2;
  const rknX = 220, rknY = H2/2 + 40;
  const armR = (-10 - armT*40) * Math.PI/180;
  const tip = { x: pnhX + Math.cos(armR)*60, y: pnhY - 28 + Math.sin(armR)*60 };
  const target = { x: rknX - 18, y: rknY - 20 };
  const ctrl = { x: (tip.x+target.x)/2, y: Math.min(tip.y,target.y) - 50 };
  const qb = (u,p0,p1,p2)=>({x:(1-u)*(1-u)*p0.x+2*(1-u)*u*p1.x+u*u*p2.x, y:(1-u)*(1-u)*p0.y+2*(1-u)*u*p1.y+u*u*p2.y});
  const segs = 22;
  const streamPts = [];
  for (let i=0;i<=segs;i++){ const u=i/segs; if (u>streamT) break; streamPts.push(qb(u,tip,ctrl,target)); }

  const figColor = healing > 0.5 ? PAL.cyan : PAL.magenta;
  return (
    <svg width={W2} height={H2} viewBox={`0 0 ${W2} ${H2}`} style={{ overflow: 'visible' }}>
      <defs>
        <filter id="b1"><feGaussianBlur stdDeviation="2"/></filter>
        <filter id="b2"><feGaussianBlur stdDeviation="5"/></filter>
      </defs>
      {/* Phase 1: split logo */}
      {splitT < 1 && (
        <g opacity={1 - splitT}>
          <text x={W2/2 + splitT*40} y={H2/2 - 10 - splitT*15} textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="44" fontWeight="900" fill={PAL.magenta} letterSpacing="2">RKN</text>
          <text x={W2/2 - splitT*40} y={H2/2 + 30 + splitT*15} textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="44" fontWeight="900" fill={PAL.magenta} letterSpacing="2">PNH</text>
        </g>
      )}
      {/* Figures */}
      {figT > 0 && (
        <>
          {/* PNH (left, giver) */}
          <g opacity={figT} transform={`translate(${pnhX} ${pnhY})`}>
            <circle cx="0" cy="-50" r="13" fill={PAL.magenta}/>
            <rect x="-14" y="-36" width="28" height="50" rx="14" fill={PAL.magenta}/>
            <rect x="-12" y="14" width="9" height="38" rx="4" fill={PAL.magenta}/>
            <rect x="3" y="14" width="9" height="38" rx="4" fill={PAL.magenta}/>
            <rect x="-22" y="-10" width="44" height="14" rx="3" fill={PAL.bgDeep} opacity="0.45"/>
            <text x="0" y="0" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="11" fill={PAL.white} letterSpacing="1">PNH</text>
            {/* arm + syringe */}
            <g transform={`translate(12 -28) rotate(${-10 - armT*40})`}>
              <rect x="0" y="-3" width="40" height="6" rx="3" fill={PAL.magenta}/>
              <rect x="42" y="-5" width="14" height="10" rx="2" fill="none" stroke={PAL.magenta} strokeWidth="2"/>
              <line x1="56" y1="0" x2="62" y2="0" stroke={PAL.magenta} strokeWidth="2"/>
              <circle cx="62" cy="0" r={2 + armT} fill={PAL.cyan} opacity={0.5+armT*0.5}/>
            </g>
          </g>
          {/* RKN (right, receiver — drinking pose) */}
          <g opacity={figT} transform={`translate(${rknX} ${rknY})`} style={{filter: healing>0 ? `drop-shadow(0 0 ${healing*16}px ${PAL.cyan})` : 'none'}}>
            {healing>0 && <circle cx="0" cy="-15" r={45 + healing*15} fill={PAL.cyan} opacity={healing*0.18}/>}
            <circle cx="-2" cy="-50" r="13" fill={figColor}/>
            <rect x="-14" y="-36" width="28" height="50" rx="14" fill={figColor}/>
            <rect x="-12" y="14" width="9" height="38" rx="4" fill={figColor}/>
            <rect x="3" y="14" width="9" height="38" rx="4" fill={figColor}/>
            <rect x="-22" y="-10" width="44" height="14" rx="3" fill={PAL.bgDeep} opacity="0.45"/>
            <text x="0" y="0" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="11" fill={PAL.white} letterSpacing="1">RKN</text>
            {/* cupped hands */}
            <path d="M -22 -22 Q -10 -30 4 -22 Q 10 -16 4 -10 Q -10 -6 -22 -10 Z" fill={figColor}/>
            {healing>0 && <ellipse cx="-9" cy="-16" rx={5+healing*2} ry={1.5+healing*0.5} fill={PAL.cyanHi} opacity={0.7+healing*0.3}/>}
          </g>
        </>
      )}
      {/* Stream */}
      {streamPts.length > 1 && (
        <>
          <polyline points={streamPts.map(p=>`${p.x},${p.y}`).join(' ')} fill="none" stroke={PAL.cyan} strokeWidth="10" strokeLinecap="round" opacity="0.35" filter="url(#b2)"/>
          <polyline points={streamPts.map(p=>`${p.x},${p.y}`).join(' ')} fill="none" stroke={PAL.cyan} strokeWidth="4" strokeLinecap="round" filter="url(#b1)"/>
          <polyline points={streamPts.map(p=>`${p.x},${p.y}`).join(' ')} fill="none" stroke={PAL.white} strokeWidth="1.5" strokeLinecap="round"/>
        </>
      )}
      {/* Splash */}
      {splashT > 0 && (
        <g transform={`translate(${target.x} ${target.y})`}>
          {[0,0.25,0.5].map((d,i)=>{const lt=clamp(splashT-d,0,1); if(lt<=0) return null; return <circle key={i} r={lt*40} fill="none" stroke={PAL.cyan} strokeWidth={1.5-lt} opacity={1-lt}/>;})}
          {Array.from({length: 14}).map((_,i)=>{
            const a = (Math.sin(i*12.9898)*43758.5453); const ang = (a-Math.floor(a))*Math.PI*2;
            const r = splashT * (20 + ((Math.sin(i*2.7)*0.5+0.5))*30);
            const fall = splashT*splashT*8;
            return <circle key={i} cx={Math.cos(ang)*r} cy={Math.sin(ang)*r*0.7+fall} r={1.5} fill={PAL.cyan} opacity={Math.max(0,1-splashT*0.9)}/>;
          })}
        </g>
      )}
    </svg>
  );
}

const clamp = (v,a,b)=>Math.max(a,Math.min(b,v));

// ─── Variation 2: SCANNER — center radar/scanner with ticker ──
function VarScanner() {
  const { state, secs, toggle } = useConnState();
  const fs = useFooterSetting(state);
  const ringColor = state==='connected' ? PAL.cyan : PAL.magenta;
  return (
    <Screen state={state} variant="scanner">
      <Header subtitle={state==='connected' ? 'You are nobody. Enjoy.' : 'Operation: Disappear'} onGear={() => fs.setOpen(true)}/>
      <div onClick={toggle} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', position: 'relative' }}>
        {/* concentric rings */}
        <div style={{ width: 280, height: 280, position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {[0.4, 0.6, 0.8, 1].map((s,i) => (
            <div key={i} style={{
              position: 'absolute', width: 280*s, height: 280*s, borderRadius: '50%',
              border: `1px solid ${ringColor}`, opacity: 0.15 + i*0.08,
              animation: state==='connecting' ? `rk-spin ${4+i}s linear infinite` : 'none',
            }}/>
          ))}
          {/* sweep arm */}
          {state==='connecting' && (
            <div style={{ position: 'absolute', inset: 0, animation: 'rk-orbit 1.6s linear infinite' }}>
              <div style={{ position: 'absolute', left: '50%', top: 0, width: 2, height: 140, background: `linear-gradient(180deg, ${PAL.cyan}, transparent)` }}/>
            </div>
          )}
          <StampSVG size={140} color={ringColor} animation={state==='connected' ? 'rk-stamp-pulse 2.4s ease-in-out infinite' : ''}/>
          {/* dots around */}
          {Array.from({length:12}).map((_,i)=>{
            const a = (i/12)*Math.PI*2;
            const r = 132;
            return <div key={i} style={{
              position:'absolute', width:5, height:5, borderRadius:'50%',
              background: ringColor, opacity: state==='connected'? 0.9 : 0.4,
              left:'50%', top:'50%',
              transform:`translate(${Math.cos(a)*r-2.5}px, ${Math.sin(a)*r-2.5}px)`,
              animation: state==='connecting' ? `rk-blink 0.8s ${i*0.06}s ease-in-out infinite` : 'none',
            }}/>;
          })}
        </div>
        <div key={state} className="rk-fade" style={{ marginTop: 28, textAlign: 'center' }}>
          <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: PAL.dim, letterSpacing: 2, marginBottom: 6 }}>
            {state==='idle' && '// STATUS: EXPOSED'}
            {state==='connecting' && '// SCANNING ROUTES…'}
            {state==='connected' && '// STATUS: HIDDEN'}
            {state==='disconnecting' && '// CLOSING TUNNEL…'}
          </div>
          <div style={{ fontFamily: 'Archivo Black, Impact, sans-serif', fontSize: 22, color: state==='connected' ? PAL.white : PAL.magenta, letterSpacing: 1 }}>
            {state==='idle' ? 'TAP TO HIDE' : state==='connecting' ? 'HOLD ON' : state==='connected' ? 'YOU\u2019RE GHOST' : 'BYE'}
          </div>
        </div>
      </div>
      <FooterRender kind={fs.resolved} state={state} secs={secs}/>
      <SettingsSheet open={fs.open} onClose={() => fs.setOpen(false)} pref={fs.pref} resolved={fs.resolved} onPick={fs.setPref}/>
    </Screen>
  );
}

// ─── Variation 3: GLITCH — chromatic noise calms when connected ──
function VarGlitch() {
  const { state, secs, toggle } = useConnState();
  const fs = useFooterSetting(state);
  const noisy = state === 'idle' || state === 'connecting' || state === 'disconnecting';
  return (
    <Screen state={state} variant="glitch">
      {/* chromatic noise overlay */}
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', zIndex: 1,
        opacity: noisy ? 0.9 : 0.15, transition: 'opacity 0.5s' }}>
        <div style={{ position:'absolute', inset:0,
          backgroundImage: `repeating-linear-gradient(0deg, transparent 0 3px, rgba(0,240,255,0.06) 3px 4px)`,
          animation: noisy ? 'rk-bg-shift 2s linear infinite' : 'none' }}/>
        <div style={{ position:'absolute', left:0, right:0, top:0, height: 24,
          background: `linear-gradient(180deg, ${PAL.cyan}30, transparent)`,
          animation: noisy ? 'rk-scan 4s linear infinite' : 'none' }}/>
      </div>
      <Header subtitle={state==='connected' ? 'The signal is clean.' : 'Signal compromised'} onGear={() => fs.setOpen(true)}/>
      <div onClick={toggle} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', position: 'relative', zIndex: 2 }}>
        <div style={{ position: 'relative', animation: noisy ? 'rk-glitch 0.18s steps(2) infinite' : 'none' }}>
          {/* RGB-split layers */}
          <div style={{ position: 'absolute', inset: 0, transform: 'translate(-3px, 0)', mixBlendMode: 'screen', opacity: noisy ? 0.7 : 0 }}>
            <StampSVG size={220} color={PAL.cyan}/>
          </div>
          <div style={{ position: 'absolute', inset: 0, transform: 'translate(3px, 0)', mixBlendMode: 'screen', opacity: noisy ? 0.7 : 0 }}>
            <StampSVG size={220} color={PAL.magenta}/>
          </div>
          <StampSVG size={220} color={state==='connected' ? PAL.magentaHi : PAL.white} animation={state==='connected' ? 'rk-stamp-pulse 2.4s ease-in-out infinite' : ''}/>
        </div>
        <div key={state} className="rk-fade" style={{ marginTop: 30, textAlign:'center', fontFamily:'JetBrains Mono, monospace' }}>
          <div style={{ fontSize: 12, color: PAL.cyan, letterSpacing: 3, marginBottom: 4 }}>
            {state==='idle' && '> ./vpn --connect'}
            {state==='connecting' && '> establishing tunnel...'}
            {state==='connected' && '> connection: ESTABLISHED ✓'}
            {state==='disconnecting' && '> tearing down...'}
          </div>
          <div style={{ fontSize: 12, color: state==='connected' ? PAL.cyan : PAL.magenta, letterSpacing: 3, opacity: 0.7 }}>
            {state==='connected' ? 'press to terminate' : 'press to begin'}
          </div>
        </div>
      </div>
      <FooterRender kind={fs.resolved} state={state} secs={secs}/>
      <SettingsSheet open={fs.open} onClose={() => fs.setOpen(false)} pref={fs.pref} resolved={fs.resolved} onPick={fs.setPref}/>
    </Screen>
  );
}

function FooterRender({ kind, state, secs }) {
  if (kind === 'map' && window.FooterMap) return <FooterMap state={state} secs={secs}/>;
  if (kind === 'receipt' && window.FooterReceipt) return <FooterReceipt state={state} secs={secs}/>;
  if (kind === 'pet' && window.FooterPet) return <FooterPet state={state} secs={secs}/>;
  if (kind === 'monster' && window.FooterMonster) return <FooterMonster state={state} secs={secs}/>;
  if (kind === 'tug' && window.FooterTugWar) return <FooterTugWar state={state} secs={secs}/>;
  return <Footer state={state} secs={secs}/>;
}

// Footer catalog, also used by the in-app Settings sheet.
const FOOTER_OPTIONS = [
  { value: 'random',  name: 'Random each launch', desc: 'Surprise me every session', dice: true },
  { value: 'tug',     name: 'Tug of War',       desc: 'You vs the Watcher' },
  { value: 'monster', name: 'Traffic Gremlin',  desc: 'It devours your packets' },
  { value: 'map',     name: 'ASCII Route',      desc: 'Live hop map of the tunnel' },
  { value: 'receipt', name: 'Denial Receipt',   desc: 'Your paperwork, printed' },
  { value: 'pet',     name: 'Ghost Pet',        desc: 'Your anonymity, kept alive' },
  { value: 'speed',   name: 'Classic Speeds',   desc: 'Plain up / down meters' },
];
const RANDOM_POOL = ['tug', 'monster', 'map', 'receipt', 'pet'];

// Per-phone footer preference. Follows the global Tweaks value, but the in-app
// Settings sheet can override it per device. 'random' rolls a concrete footer
// on mount and re-rolls on each launch (idle → connecting).
function useFooterSetting(state) {
  const [pref, setPref] = useState(() => getFooterKind());
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const h = () => setPref(getFooterKind());
    window.addEventListener('rk-footer-change', h);
    return () => window.removeEventListener('rk-footer-change', h);
  }, []);
  const roll = () => RANDOM_POOL[Math.floor(Math.random() * RANDOM_POOL.length)];
  const rolledRef = useRef(roll());
  const prevState = useRef(state);
  useEffect(() => {
    if (pref === 'random' && prevState.current === 'idle' && state === 'connecting') {
      rolledRef.current = roll();
    }
    prevState.current = state;
  }, [state, pref]);
  const resolved = pref === 'random' ? rolledRef.current : pref;
  return { pref, setPref, open, setOpen, resolved };
}

// In-app Settings sheet — slides up inside the phone from the gear icon.
function SettingsSheet({ open, onClose, pref, resolved, onPick }) {
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 30,
      pointerEvents: open ? 'auto' : 'none',
    }}>
      {/* scrim */}
      <div onClick={onClose} style={{
        position: 'absolute', inset: 0, background: 'rgba(6,3,12,0.6)',
        opacity: open ? 1 : 0, transition: 'opacity 0.25s', backdropFilter: open ? 'blur(2px)' : 'none',
      }}/>
      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        background: PAL.bgDeep, borderTop: `1px solid ${PAL.dim2}`,
        borderRadius: '22px 22px 0 0', padding: '14px 18px 28px',
        transform: open ? 'translateY(0)' : 'translateY(100%)',
        transition: 'transform 0.32s cubic-bezier(.2,.8,.2,1)',
        boxShadow: '0 -20px 50px rgba(0,0,0,0.5)',
      }}>
        <div style={{ width: 40, height: 4, borderRadius: 2, background: PAL.dim2, margin: '0 auto 14px' }}/>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 4 }}>
          <div style={{ fontFamily: 'Archivo Black, Impact, sans-serif', fontSize: 17, color: PAL.white, letterSpacing: 0.5 }}>STATUS WIDGET</div>
          <div onClick={onClose} style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: PAL.magenta, cursor: 'pointer', letterSpacing: 1 }}>DONE</div>
        </div>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, color: PAL.dim, letterSpacing: 1, marginBottom: 12 }}>
          what lives under the button
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7, maxHeight: 360, overflowY: 'auto' }}>
          {FOOTER_OPTIONS.map(o => {
            const active = pref === o.value;
            return (
              <div key={o.value} onClick={() => onPick(o.value)} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '11px 14px', borderRadius: 14, cursor: 'pointer',
                background: active ? 'rgba(255,43,214,0.10)' : 'rgba(255,255,255,0.03)',
                border: `1px solid ${active ? PAL.magenta : PAL.dim2}`,
                transition: 'background 0.15s, border-color 0.15s',
              }}>
                <div style={{ fontSize: 18, width: 22, textAlign: 'center', filter: active ? 'none' : 'grayscale(0.4)' }}>
                  {o.dice ? '🎲' : ''}
                  {!o.dice && (
                    <span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3,
                      background: active ? PAL.magenta : 'transparent', border: `1.5px solid ${active ? PAL.magenta : PAL.dim}` }}/>
                  )}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 14, fontWeight: 700, color: active ? PAL.white : '#b8a8d8' }}>
                    {o.name}
                    {o.value === 'random' && active && (
                      <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: PAL.cyan, marginLeft: 8, letterSpacing: 1 }}>
                        → {(FOOTER_OPTIONS.find(x => x.value === resolved) || {}).name}
                      </span>
                    )}
                  </div>
                  <div style={{ fontSize: 11, color: PAL.dim }}>{o.desc}</div>
                </div>
                {active && <div style={{ color: PAL.magenta, fontSize: 14 }}>✓</div>}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// Shared screen chrome
function Screen({ children, state, variant }) {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: PAL.bg,
      position: 'relative', overflow: 'hidden',
      display: 'flex', flexDirection: 'column',
      paddingTop: 60, // status bar
      color: PAL.white,
      fontFamily: 'Space Grotesk, system-ui, sans-serif',
    }}>
      {/* radial bg */}
      <div style={{ position: 'absolute', inset: 0,
        background: state==='connected'
          ? `radial-gradient(circle at 50% 35%, ${PAL.cyan}22, transparent 60%)`
          : `radial-gradient(circle at 50% 50%, ${PAL.magenta}22, transparent 60%)`,
        transition: 'background 0.6s' }}/>
      {children}
    </div>
  );
}

function Header({ subtitle, onGear }) {
  return (
    <div style={{ padding: '20px 24px 0', position: 'relative', zIndex: 2 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ fontFamily: 'Archivo Black, Impact, sans-serif', fontSize: 22, color: PAL.white, letterSpacing: 1 }}>RKN<span style={{ color: PAL.magenta }}>·</span>PNH</div>
        <div onClick={onGear} role="button" title="Status widget settings" style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${PAL.dim2}`, display:'flex', alignItems:'center', justifyContent:'center', cursor: 'pointer' }}>
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke={PAL.dim} strokeWidth="1.5"><circle cx="8" cy="8" r="2.5"/><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3 3l1.5 1.5M11.5 11.5L13 13M3 13l1.5-1.5M11.5 4.5L13 3"/></svg>
        </div>
      </div>
      <div style={{ marginTop: 8, fontSize: 12, color: PAL.dim, letterSpacing: 0.5 }}>{subtitle}</div>
    </div>
  );
}

function Ring({ delay }) {
  return (
    <div style={{
      position: 'absolute', width: 240, height: 240, borderRadius: '50%',
      border: `1.5px solid ${PAL.magenta}`,
      animation: `rk-pulse-ring 2.4s ${delay} ease-out infinite`,
    }}/>
  );
}

function Footer({ state, secs }) {
  const data = state==='connected' ? {
    server: 'Reykjavík, Iceland', ip: '185.93.0.42', up: '12.4', down: '88.1',
  } : { server: '— select route —', ip: '93.184.27.11', up: '0', down: '0' };
  return (
    <div style={{ padding: '0 20px 36px', position: 'relative', zIndex: 2 }}>
      <div style={{ background: 'rgba(255,255,255,0.04)', border: `1px solid ${PAL.dim2}`,
        borderRadius: 18, padding: 16, backdropFilter: 'blur(10px)' }}>
        <Row k="route" v={data.server} accent={state==='connected' ? PAL.cyan : PAL.dim}/>
        <Row k="public ip" v={state==='connected' ? `${data.ip} 🇮🇸` : `${data.ip} (real)`} accent={state==='connected' ? PAL.cyan : PAL.magenta}/>
        <Row k="uptime" v={state==='connected' ? fmtTime(secs) : '—'}/>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 12 }}>
          <Tile label="↓ DOWN" value={data.down} unit="MB/s"/>
          <Tile label="↑ UP" value={data.up} unit="MB/s"/>
        </div>
      </div>
    </div>
  );
}

function Row({ k, v, accent = PAL.white }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
      padding: '6px 0', borderBottom: `1px dashed ${PAL.dim2}` }}>
      <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, color: PAL.dim, letterSpacing: 1.5, textTransform: 'uppercase' }}>{k}</span>
      <span style={{ fontSize: 13, color: accent, fontWeight: 600 }}>{v}</span>
    </div>
  );
}

function Tile({ label, value, unit }) {
  return (
    <div style={{ background: PAL.bgDeep, borderRadius: 12, padding: '10px 12px' }}>
      <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 9, color: PAL.dim, letterSpacing: 2 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 2 }}>
        <span style={{ fontSize: 22, fontWeight: 700, color: PAL.white, fontVariantNumeric: 'tabular-nums' }}>{value}</span>
        <span style={{ fontSize: 10, color: PAL.dim }}>{unit}</span>
      </div>
    </div>
  );
}

Object.assign(window, { VarStamp, VarScanner, VarGlitch });
