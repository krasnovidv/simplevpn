// Connect-animation: RKNPNH logo splits → two letter-figures → cyan stream → splash glow.
// 0.0–0.6 logo idle pulse
// 0.6–1.6 logo splits, letters morph into two silhouettes (RKN right-low, PNH left-high)
// 1.6–3.0 PNH wields a syringe-like wand of letters; cyan stream arcs across screen
// 2.4–3.4 stream contacts RKN — splash particles, expanding shockwave, healing glow envelopes RKN
// 3.4–6.0 hold connected state with ambient particles + "PROTECTED" copy

const { useState: uS, useEffect: uE, useRef: uR } = React;

const P = {
  bg: '#0a0612', bg2: '#120a1f',
  magenta: '#ff2bd6', cyan: '#00f0ff', cyanHi: '#7df9ff',
  white: '#f5f3ff', dim: '#5a4a7a',
};

const W = 390, H = 844;

// ── Simplified pictogram silhouettes ──────────────────────────────────
// Clean, minimal figures (think international sign / restroom pictogram):
// circle head, capsule torso, simple legs. Letters embedded as small label
// chip on the chest. Easy to read, no anatomy issues.

// PNH — giver, standing, right arm extended forward holding syringe.
function PNHFigure({ x, y, scale = 1, glow = 0, armRaise = 0, t = 0 }) {
  const armR = -10 - armRaise * 50;
  const breathe = Math.sin(t * 2) * 1;
  const color = P.magenta;
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`} style={{ filter: glow ? `drop-shadow(0 0 ${glow*20}px ${color})` : 'none' }}>
      {/* head — simple circle */}
      <circle cx="0" cy={-92 + breathe} r="18" fill={color}/>
      {/* torso — rounded capsule, narrows at waist */}
      <path d="M -22 -64 Q -26 -60 -24 -50 L -20 -10 Q -22 10 -18 30 L -14 60 Q -10 70 0 70 Q 10 70 14 60 L 18 30 Q 22 10 20 -10 L 24 -50 Q 26 -60 22 -64 Q 12 -70 0 -70 Q -12 -70 -22 -64 Z" fill={color}/>
      {/* tucked left arm */}
      <path d="M -22 -54 Q -32 -42 -32 -22 Q -32 -6 -28 6 L -22 6 Q -22 -8 -20 -22 Q -18 -38 -16 -52 Z" fill={color}/>
      {/* legs — simple tapered */}
      <path d="M -14 60 L -16 150 Q -16 156 -10 156 L -4 156 Q -2 156 -2 150 L -2 70 Z" fill={color}/>
      <path d="M 14 60 L 16 150 Q 16 156 10 156 L 4 156 Q 2 156 2 150 L 2 70 Z" fill={color}/>

      {/* PNH label chip on chest */}
      <g transform="translate(0 -28)">
        <rect x="-18" y="-9" width="36" height="18" rx="3" fill={P.bg} opacity="0.55"/>
        <text x="0" y="5" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="14" fontWeight="900" fill={P.white} letterSpacing="0.5">PNH</text>
      </g>

      {/* Right arm + syringe (rotates with armRaise) */}
      <g transform={`translate(20 -50) rotate(${armR})`}>
        <path d="M 0 -7 Q 6 -9 12 -7 L 60 -5 Q 66 -3 66 0 Q 66 3 60 5 L 12 7 Q 6 9 0 7 Z" fill={color}/>
        <circle cx="68" cy="0" r="6" fill={color}/>
        {/* syringe */}
        <rect x="74" y="-6" width="24" height="12" rx="2" fill="none" stroke={color} strokeWidth="2.5"/>
        <rect x="77" y="-3" width="14" height="6" rx="1" fill={color} opacity="0.6"/>
        <rect x="71" y="-8" width="3" height="16" rx="1" fill={color}/>
        <line x1="98" y1="0" x2="114" y2="0" stroke={color} strokeWidth="2.5"/>
        <circle cx="114" cy="0" r={3 + armRaise*2} fill={P.cyanHi} opacity={0.5 + 0.5*armRaise}/>
        <circle cx="114" cy="0" r={8 + armRaise*4} fill={P.cyan} opacity={0.2 + 0.3*armRaise} filter="url(#blur1)"/>
      </g>
    </g>
  );
}

// RKN — receiver, simplified pictogram, side-leaning toward viewer's left.
// Both arms raised forward, hands meet to form a simple cupped bowl at face
// level. Head leans down to drink from the bowl.
function RKNFigure({ x, y, scale = 1, glow = 0, healing = 0, t = 0 }) {
  const breathe = Math.sin(t * 2 + 1) * 1;
  const baseColor = P.magenta;
  const healColor = P.cyan;
  const color = healing > 0.5 ? healColor : baseColor;
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`} style={{ filter: glow ? `drop-shadow(0 0 ${glow*22}px ${color})` : 'none' }}>
      {/* heal aura */}
      {healing > 0 && (
        <>
          <circle cx="-10" cy="-10" r={80 + healing*30 + Math.sin(t*4)*4} fill={P.cyan} opacity={healing * 0.1}/>
          <circle cx="-10" cy="-10" r={60 + healing*20} fill={P.cyan} opacity={healing * 0.18} filter="url(#blur2)"/>
        </>
      )}

      {/* legs */}
      <path d="M -14 60 L -16 150 Q -16 156 -10 156 L -4 156 Q -2 156 -2 150 L -2 70 Z" fill={color}/>
      <path d="M 14 60 L 16 150 Q 16 156 10 156 L 4 156 Q 2 156 2 150 L 2 70 Z" fill={color}/>

      {/* torso — capsule, very slight forward lean */}
      <path d="M -22 -64 Q -26 -60 -24 -50 L -20 -10 Q -22 10 -18 30 L -14 60 Q -10 70 0 70 Q 10 70 14 60 L 18 30 Q 22 10 20 -10 L 24 -50 Q 26 -60 22 -64 Q 12 -70 0 -70 Q -12 -70 -22 -64 Z" fill={color}/>

      {/* head — circle, leaning slightly forward (left) toward bowl */}
      <g transform={`translate(-6 ${-92 + breathe})`}>
        <circle r="18" fill={color}/>
        {/* mouth notch on viewer's left */}
        <ellipse cx="-10" cy="4" rx="3" ry="2" fill={P.bg} opacity={0.5 + healing*0.5}/>
        {healing > 0 && <circle cx="-10" cy="4" r={1.5 + healing} fill={P.cyanHi} opacity={healing*0.9}/>}
      </g>

      {/* both arms forward + up, meeting at cupped hands (a single shape
          for clarity instead of two overlapping arms) */}
      {/* near arm */}
      <path d="M -18 -54 Q -34 -50 -38 -32 Q -40 -16 -32 -14 L -22 -22 Q -18 -38 -14 -52 Z" fill={color}/>
      {/* far arm */}
      <path d="M 6 -58 Q -10 -56 -16 -38 Q -20 -22 -10 -18 L -2 -28 Q 2 -42 6 -54 Z" fill={color} opacity="0.88"/>

      {/* CUPPED HANDS — clean bowl shape just below mouth */}
      <g transform="translate(-22 -22)">
        {/* bowl outline */}
        <path d="M -16 0 Q -18 8 -12 14 Q -2 18 8 14 Q 14 8 12 0 Q 0 -4 -16 0 Z" fill={color}/>
        {/* thumb hint */}
        <ellipse cx="12" cy="-1" rx="3" ry="4" fill={color}/>
        <ellipse cx="-16" cy="-1" rx="3" ry="4" fill={color}/>
        {/* pool of glowing liquid */}
        {healing > 0 && (
          <>
            <ellipse cx="-2" cy="4" rx={10 + healing*3} ry={2.5 + healing} fill={P.cyanHi} opacity={0.8 + healing*0.2}/>
            <ellipse cx="-2" cy="4" rx={14} ry={3.5} fill={P.cyan} opacity={healing*0.5} filter="url(#blur1)"/>
          </>
        )}
      </g>

      {/* RKN label chip on chest */}
      <g transform="translate(0 -28)">
        <rect x="-18" y="-9" width="36" height="18" rx="3" fill={P.bg} opacity="0.55"/>
        <text x="0" y="5" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="14" fontWeight="900" fill={P.white} letterSpacing="0.5">RKN</text>
      </g>

      {/* shimmer particles */}
      {healing > 0.2 && Array.from({length: 8}).map((_, i) => {
        const a = (i / 8) * Math.PI * 2 + t;
        const r = 50 + Math.sin(t*2 + i) * 8;
        return <circle key={i} cx={Math.cos(a)*r} cy={Math.sin(a)*r*0.8 - 10} r="1.5" fill={P.cyanHi} opacity={healing*0.8}/>;
      })}
    </g>
  );
}

// The intact stamp logo — two halves rendered separately so each can animate
// during the split. RKN is on top, PNH on bottom.
function StampLogoSplit({ splitE = 0, opacity = 1, t = 0 }) {
  // splitE 0→1: halves separate, RKN drifts up-right, PNH drifts down-left,
  // both fade and shrink as figures take over.
  const rknDx =  splitE * 70;   // RKN → right
  const rknDy = -splitE * 30;   // RKN → up
  const rknRot = -7 + splitE * 8;
  const pnhDx = -splitE * 70;   // PNH → left
  const pnhDy =  splitE * 30;   // PNH → down
  const pnhRot = -7 - splitE * 8;
  const halfOp = clamp(1 - splitE * 1.2, 0, 1) * opacity;

  return (
    <g style={{ filter: `drop-shadow(0 0 ${8 + Math.sin(t*4)*4}px ${P.magenta})` }}>
      {/* frame fades quickly */}
      <g transform={`translate(${W/2} ${H/2 - 40}) rotate(-7) translate(-95 -82)`} opacity={clamp(1 - splitE*2, 0, 1) * opacity}>
        <rect width="190" height="164" rx="10" fill="none" stroke={P.magenta} strokeWidth="5"/>
        <rect x="6" y="6" width="178" height="152" rx="6" fill="none" stroke={P.magenta} strokeWidth="1.6" opacity="0.6"/>
        <text x="95" y="148" textAnchor="middle" fontFamily="Space Grotesk, sans-serif" fontWeight="700" fontSize="9" fill={P.magenta} letterSpacing="3.5">★ NOT APPROVED ★</text>
      </g>
      {/* RKN — top half, drifts up & right */}
      <g transform={`translate(${W/2 + rknDx} ${H/2 - 40 + rknDy}) rotate(${rknRot})`} opacity={halfOp}>
        <text x="0" y="-8" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="56" fontWeight="900" fill={P.magenta} letterSpacing="3">RKN</text>
      </g>
      {/* PNH — bottom half, drifts down & left */}
      <g transform={`translate(${W/2 + pnhDx} ${H/2 - 40 + pnhDy}) rotate(${pnhRot})`} opacity={halfOp}>
        <text x="0" y="42" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="56" fontWeight="900" fill={P.magenta} letterSpacing="3">PNH</text>
      </g>
    </g>
  );
}

// Quadratic bezier point
const qb = (t, p0, p1, p2) => ({
  x: (1-t)*(1-t)*p0.x + 2*(1-t)*t*p1.x + t*t*p2.x,
  y: (1-t)*(1-t)*p0.y + 2*(1-t)*t*p1.y + t*t*p2.y,
});

function SceneSVG() {
  const t = useTime();

  // logo split phase: 0.6 → 1.6
  const splitT = clamp((t - 0.6) / 1.0, 0, 1);
  const splitE = Easing.easeInOutCubic(splitT);
  const logoOpacity = clamp(1 - splitT*1.6, 0, 1);

  // figure entry
  const figT = clamp((t - 1.2) / 0.8, 0, 1);
  const figE = Easing.easeOutCubic(figT);

  // arm raise
  const armT = clamp((t - 1.6) / 0.6, 0, 1);

  // stream emit window: 1.8 → 3.4
  const streamT = clamp((t - 1.8) / 1.2, 0, 1);
  const streamHead = Easing.easeInOutCubic(streamT);

  // splash starts at ~2.6
  const splashT = clamp((t - 2.6) / 0.9, 0, 1);
  const healing = clamp((t - 2.8) / 0.8, 0, 1);

  // protected reveal
  const protT = clamp((t - 3.6) / 0.5, 0, 1);

  // PNH (giver) on LEFT, RKN (receiver) on RIGHT — receiver lower so stream arcs down
  const pnhX = 100, pnhY = H/2 - 50;
  const rknX = 285, rknY = H/2 + 130;

  // syringe tip in figure-local: arm group at (28, -54) from figure origin,
  // rotated by armR; needle tip is at (132, 0) in arm-local space.
  const figScale = 0.85;
  const armR = -10 - armT * 50;
  const armRot = armR * Math.PI / 180;
  // PNH arm group at (20, -50); needle tip at (114, 0) in arm-local.
  const tipLocal = {
    x: 20 + Math.cos(armRot) * 114,
    y: -50 + Math.sin(armRot) * 114,
  };
  const tip = {
    x: pnhX + tipLocal.x * figScale,
    y: pnhY + tipLocal.y * figScale,
  };
  // Target: RKN cupped-hands bowl. Group at translate(-22,-22) inside figure;
  // bowl center ≈ (-2, 4) in group → figure-local (-24, -18).
  const handsLocal = { x: -24, y: -18 };
  const target = {
    x: rknX + handsLocal.x * figScale,
    y: rknY + handsLocal.y * figScale,
  };
  const ctrl = { x: (tip.x + target.x)/2, y: Math.min(tip.y, target.y) - 70 };

  // stream as series of points along bezier, head moves from 0→1
  const streamPts = [];
  const segs = 28;
  for (let i = 0; i <= segs; i++) {
    const u = i / segs;
    if (u > streamHead) break;
    streamPts.push(qb(u, tip, ctrl, target));
  }

  return (
    <>
      {/* deep bg + radial glow */}
      <rect width={W} height={H} fill={P.bg}/>
      <defs>
        <radialGradient id="bgglow" cx="0.5" cy="0.5" r="0.6">
          <stop offset="0" stopColor={P.magenta} stopOpacity={0.18 - healing*0.1}/>
          <stop offset="1" stopColor={P.magenta} stopOpacity="0"/>
        </radialGradient>
        <radialGradient id="cyanglow" cx="0.5" cy="0.5" r="0.6">
          <stop offset="0" stopColor={P.cyan} stopOpacity={healing*0.4}/>
          <stop offset="1" stopColor={P.cyan} stopOpacity="0"/>
        </radialGradient>
        <filter id="blur1"><feGaussianBlur stdDeviation="3"/></filter>
        <filter id="blur2"><feGaussianBlur stdDeviation="6"/></filter>
      </defs>
      <rect width={W} height={H} fill="url(#bgglow)"/>
      <rect width={W} height={H} fill="url(#cyanglow)"/>

      {/* ambient encrypted particles */}
      {Array.from({length: 18}).map((_, i) => {
        const seed = i * 7.13;
        const px = ((Math.sin(seed) * 0.5 + 0.5) * W);
        const py = ((Math.cos(seed*1.7) * 0.5 + 0.5) * H);
        const drift = Math.sin(t * 0.6 + i) * 10;
        return <rect key={i} x={px+drift} y={py - t*8 % H} width="2" height="2" fill={healing > 0 ? P.cyan : P.dim} opacity="0.5"/>;
      })}

      {/* Phase 1: intact logo splitting */}
      {logoOpacity > 0.01 && (
        <StampLogoSplit splitE={splitE} opacity={logoOpacity} t={t}/>
      )}

      {/* Phase 2: figures fade in as logo splits */}
      {figT > 0 && (
        <>
          <g opacity={figE} transform={`translate(${(1-figE) * -30} 0)`}>
            <PNHFigure x={pnhX} y={pnhY} scale={figScale} glow={0.5 + Math.sin(t*3)*0.15} armRaise={armT} t={t}/>
          </g>
          <g opacity={figE} transform={`translate(${(1-figE) * 30} 0)`}>
            <RKNFigure x={rknX} y={rknY} scale={figScale} glow={0.4 + healing*0.5} healing={healing} t={t}/>
          </g>
        </>
      )}

      {/* split debris particles during morph */}
      {splitT > 0 && splitT < 1 && Array.from({length: 14}).map((_, i) => {
        const a = (i/14) * Math.PI * 2;
        const r = splitE * 90;
        return <circle key={i} cx={W/2 + Math.cos(a)*r} cy={H/2 - 40 + Math.sin(a)*r} r={2} fill={P.magenta} opacity={1 - splitE}/>;
      })}

      {/* stream — glowing arc of points */}
      {streamPts.length > 1 && (
        <>
          {/* outer glow */}
          <polyline
            points={streamPts.map(p => `${p.x},${p.y}`).join(' ')}
            fill="none" stroke={P.cyanHi} strokeWidth="14" strokeLinecap="round" strokeLinejoin="round"
            opacity="0.35" filter="url(#blur2)"
          />
          {/* mid */}
          <polyline
            points={streamPts.map(p => `${p.x},${p.y}`).join(' ')}
            fill="none" stroke={P.cyan} strokeWidth="6" strokeLinecap="round" strokeLinejoin="round"
            opacity="0.85" filter="url(#blur1)"
          />
          {/* core */}
          <polyline
            points={streamPts.map(p => `${p.x},${p.y}`).join(' ')}
            fill="none" stroke={P.white} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
            opacity="0.95"
          />
          {/* head sparkle */}
          {(() => {
            const head = streamPts[streamPts.length - 1];
            return (
              <>
                <circle cx={head.x} cy={head.y} r="8" fill={P.cyanHi} opacity="0.5" filter="url(#blur1)"/>
                <circle cx={head.x} cy={head.y} r="3" fill={P.white}/>
              </>
            );
          })()}
        </>
      )}

      {/* droplets falling from stream */}
      {streamT > 0.2 && Array.from({length: 6}).map((_, i) => {
        const u = ((t * 0.4 + i*0.15) % 1) * streamHead;
        if (u < 0.05 || u > streamHead) return null;
        const p = qb(u, tip, ctrl, target);
        const fall = Math.max(0, t*1.5 - i*0.3) % 2;
        return <circle key={i} cx={p.x + (i%2?2:-2)} cy={p.y + fall*30} r="1.5" fill={P.cyan} opacity={1 - fall/2}/>;
      })}

      {/* SPLASH at impact */}
      {splashT > 0 && (
        <g transform={`translate(${target.x} ${target.y})`}>
          {/* shockwave rings */}
          {[0, 0.25, 0.5].map((delay, i) => {
            const lt = clamp(splashT - delay, 0, 1);
            if (lt <= 0) return null;
            const r = lt * 70;
            return <circle key={i} r={r} fill="none" stroke={P.cyan} strokeWidth={2 - lt*1.5} opacity={1 - lt}/>;
          })}
          {/* burst particles */}
          {Array.from({length: 22}).map((_, i) => {
            const seed = Math.sin(i * 12.9898) * 43758.5453;
            const a = (seed - Math.floor(seed)) * Math.PI * 2;
            const speed = 30 + ((Math.sin(i*2.7) * 0.5 + 0.5)) * 60;
            const r = splashT * speed;
            const fall = splashT * splashT * 18;
            const px = Math.cos(a) * r;
            const py = Math.sin(a) * r * 0.7 + fall;
            const sz = 2 + (1 - splashT) * 2;
            return <circle key={i} cx={px} cy={py} r={sz} fill={i%3===0 ? P.white : P.cyan} opacity={Math.max(0, 1 - splashT*0.9)}/>;
          })}
          {/* hanging luminous particles */}
          {splashT > 0.3 && Array.from({length: 10}).map((_, i) => {
            const seed = Math.sin(i * 7.1) * 9999;
            const a = (seed - Math.floor(seed)) * Math.PI * 2;
            const r = 30 + ((seed*1.3) - Math.floor(seed*1.3)) * 30;
            const drift = Math.sin(t*1.5 + i) * 4;
            return <circle key={i} cx={Math.cos(a)*r + drift} cy={Math.sin(a)*r*0.6} r="1.5" fill={P.cyanHi} opacity={(1 - splashT*0.4)*0.8} filter="url(#blur1)"/>;
          })}
        </g>
      )}

      {/* PROTECTED status pill */}
      {protT > 0 && (
        <g transform={`translate(${W/2} ${H - 200}) scale(${0.9 + protT*0.1})`} opacity={protT}>
          <rect x="-95" y="-22" width="190" height="44" rx="22" fill="rgba(0,240,255,0.1)" stroke={P.cyan} strokeWidth="1"/>
          <circle cx="-72" cy="0" r="4" fill="#4ade80"/>
          <circle cx="-72" cy="0" r="8" fill="#4ade80" opacity="0.3"/>
          <text x="-58" y="5" fontFamily="Space Grotesk, sans-serif" fontWeight="700" fontSize="13" fill={P.white} letterSpacing="2">PROTECTED</text>
        </g>
      )}

      {/* server label */}
      {protT > 0 && (
        <g opacity={protT} transform={`translate(${W/2} ${H - 145})`}>
          <text textAnchor="middle" fontFamily="JetBrains Mono, monospace" fontSize="10" fill={P.dim} letterSpacing="2">// ROUTE</text>
          <text y="20" textAnchor="middle" fontFamily="Space Grotesk, sans-serif" fontWeight="700" fontSize="16" fill={P.white}>Reykjavík, Iceland 🇮🇸</text>
          <text y="40" textAnchor="middle" fontFamily="JetBrains Mono, monospace" fontSize="11" fill={P.cyan}>00:00:0{Math.floor(t-3.5).toString().padStart(1,'0')}</text>
        </g>
      )}

      {/* status header */}
      <g opacity={1 - logoOpacity*0.5}>
        <text x={W/2} y="80" textAnchor="middle" fontFamily="Archivo Black, Impact, sans-serif" fontSize="14" fill={P.white} letterSpacing="3">RKN<tspan fill={P.magenta}>·</tspan>PNH</text>
        <text x={W/2} y="100" textAnchor="middle" fontFamily="JetBrains Mono, monospace" fontSize="9" fill={healing > 0.3 ? P.cyan : P.dim} letterSpacing="3">
          {t < 0.6 ? '// IDLE' : t < 1.6 ? '// INITIATING' : t < 2.6 ? '// DELIVERING' : t < 3.6 ? '// SECURING' : '// PROTECTED'}
        </text>
      </g>
    </>
  );
}

function App() {
  return (
    <div style={{ width: '100vw', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#0a0612', fontFamily: 'Space Grotesk, sans-serif' }}>
      <Stage width={W} height={H} duration={6} fps={60} loop={true} background="#0a0612" style={{ borderRadius: 48, overflow: 'hidden', boxShadow: '0 30px 80px rgba(255,43,214,0.15), 0 0 0 8px #1a1428' }}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{ display: 'block' }}>
          <SceneSVG/>
        </svg>
      </Stage>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
