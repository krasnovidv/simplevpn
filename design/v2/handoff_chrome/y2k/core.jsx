// RKNPNH redesign — shared core: ticker, themes, backgrounds, icons, phone shell.
const { useState: useS, useEffect: useE, useRef: useR } = React;

// ── one global rAF ticker; components subscribe and get seconds ──
const __tick = { subs: new Set(), t: 0, raf: 0 };
function __loop(now) { __tick.t = now / 1000; __tick.subs.forEach(f => f(__tick.t)); __tick.raf = requestAnimationFrame(__loop); }
function useTime() {
  const [t, setT] = useS(0);
  useE(() => {
    __tick.subs.add(setT);
    if (!__tick.raf) __tick.raf = requestAnimationFrame(__loop);
    return () => { __tick.subs.delete(setT); };
  }, []);
  return t;
}

// ── keyframes ──
if (!document.getElementById('y2k-kf')) {
  const s = document.createElement('style'); s.id = 'y2k-kf';
  s.textContent = `
  @keyframes y2k-drift1{0%,100%{transform:translate(0,0) scale(1)}33%{transform:translate(60px,40px) scale(1.15)}66%{transform:translate(-40px,80px) scale(.9)}}
  @keyframes y2k-drift2{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(-70px,-50px) scale(1.2)}}
  @keyframes y2k-drift3{0%,100%{transform:translate(0,0)}50%{transform:translate(50px,-90px)}}
  @keyframes y2k-grid{from{background-position:0 0}to{background-position:0 40px}}
  @keyframes y2k-twinkle{0%,100%{opacity:.15;transform:scale(.6) rotate(0)}50%{opacity:1;transform:scale(1.1) rotate(45deg)}}
  @keyframes y2k-rise{0%{transform:translateY(0) translateX(0);opacity:0}10%{opacity:1}100%{transform:translateY(-900px) translateX(30px);opacity:0}}
  @keyframes y2k-meridian{0%{transform:scaleX(1)}50%{transform:scaleX(-1)}100%{transform:scaleX(1)}}
  @keyframes y2k-spin{to{transform:rotate(360deg)}}
  @keyframes y2k-spin-rev{to{transform:rotate(-360deg)}}
  @keyframes y2k-in{from{opacity:0;transform:translateY(18px) scale(.97)}to{opacity:1;transform:none}}
  @keyframes y2k-pop{0%{transform:scale(.4) rotate(-20deg);opacity:0}60%{transform:scale(1.12) rotate(4deg);opacity:1}100%{transform:scale(1) rotate(var(--r,0deg))}}
  @keyframes y2k-marquee{from{transform:translateX(0)}to{transform:translateX(-50%)}}
  @keyframes y2k-shine{0%{transform:translateX(-120%) skewX(-20deg)}60%,100%{transform:translateX(220%) skewX(-20deg)}}
  @keyframes y2k-pulse{0%,100%{opacity:.5;transform:scale(1)}50%{opacity:1;transform:scale(1.25)}}
  @keyframes y2k-shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-3px)}75%{transform:translateX(3px)}}
  @keyframes y2k-snack{from{transform:translateY(120%)}to{transform:none}}
  .y2k-in{animation:y2k-in .55s cubic-bezier(.2,1.4,.4,1) both}
  `;
  document.head.appendChild(s);
}

const SPRING = 'cubic-bezier(.3,1.6,.5,1)';

// ── three directions × light/dark ──
const DIRS = {
  chrome: {
    name: 'Жидкий хром', display: "'Unbounded', sans-serif", body: "'Manrope', sans-serif", upper: true, radius: 28,
    dark: { bg: '#0A0B18', text: '#F2F4FF', sub: '#9CA3C9', card: 'rgba(255,255,255,0.06)', line: 'rgba(255,255,255,0.10)',
      accent: '#C9B8FF', grad: 'linear-gradient(115deg,#A8F0FF 0%,#D9B8FF 45%,#FFC4EC 75%,#FFF3B8 100%)', onAccent: '#0A0B18',
      blobs: ['#5B3BFF', '#00D1FF', '#FF4FD8'], nav: 'rgba(14,15,32,0.72)', good: '#8CFFD9', bad: '#FF8FA8' },
    light: { bg: '#ECEEF6', text: '#121320', sub: '#5A6082', card: 'rgba(255,255,255,0.62)', line: 'rgba(18,19,32,0.08)',
      accent: '#6B4DFF', grad: 'linear-gradient(115deg,#7FE3FF 0%,#B79BFF 45%,#FF9BDB 75%,#FFE58A 100%)', onAccent: '#121320',
      blobs: ['#B9A8FF', '#9BEAFF', '#FFB8E6'], nav: 'rgba(255,255,255,0.72)', good: '#00A67E', bad: '#E0325C' },
  },
  acid: {
    name: 'Кислота', display: "'Dela Gothic One', sans-serif", body: "'Onest', sans-serif", upper: true, radius: 18,
    dark: { bg: '#0D0917', text: '#F4FFE0', sub: '#A99CC8', card: '#1A1330', line: 'rgba(198,255,0,0.28)',
      accent: '#C6FF00', accent2: '#FF3DF2', accent3: '#7B5CFF', onAccent: '#0D0917', ink: '#C6FF00',
      nav: '#140E24', good: '#C6FF00', bad: '#FF3D6E', shadow: '4px 4px 0 #FF3DF2' },
    light: { bg: '#EFFFC4', text: '#150D29', sub: '#5B4F7A', card: '#FFFFFF', line: '#150D29',
      accent: '#6B2BFF', accent2: '#FF2BB8', accent3: '#00C2FF', onAccent: '#FFFFFF', ink: '#150D29',
      nav: '#FFFFFF', good: '#1FA800', bad: '#FF2B5E', shadow: '4px 4px 0 #150D29' },
  },
  jelly: {
    name: 'Желе', display: "'Rubik', sans-serif", body: "'Nunito', sans-serif", upper: false, radius: 32,
    dark: { bg: '#1B0A2A', text: '#FFE8F6', sub: '#C491C4', card: '#2A1340', line: 'rgba(255,255,255,0.08)',
      accent: '#FF5FAE', accent2: '#3EE0FF', accent3: '#FFD84A', onAccent: '#2A0A24', face: '#2A0A24',
      nav: '#23103A', good: '#3EE0FF', bad: '#FF7A9C',
      puff: 'inset 0 2px 0 rgba(255,255,255,0.10), inset 0 -6px 0 rgba(0,0,0,0.28), 0 12px 28px rgba(0,0,0,0.4)' },
    light: { bg: '#FFE6F2', text: '#3A1236', sub: '#9A5C8E', card: '#FFFFFF', line: 'rgba(58,18,54,0.08)',
      accent: '#FF3E9A', accent2: '#1FC8F0', accent3: '#FFC928', onAccent: '#FFFFFF', face: '#3A1236',
      nav: '#FFFFFF', good: '#0FB5DB', bad: '#FF4F7B',
      puff: 'inset 0 2px 0 #fff, inset 0 -6px 0 rgba(255,62,154,0.12), 0 12px 26px rgba(255,62,154,0.18)' },
  },
};
function themeFor(dir, dark) { const D = DIRS[dir]; return { ...D, ...(dark ? D.dark : D.light), dir, dark }; }

// card / button / chip styles per direction
function cardStyle(T) {
  if (T.dir === 'chrome') return { background: `linear-gradient(${T.dark ? '#14152A' : '#F6F7FC'},${T.dark ? '#14152A' : '#F6F7FC'}) padding-box, ${T.grad} border-box`,
    border: '1.5px solid transparent', borderRadius: T.radius, boxShadow: T.dark ? '0 10px 40px rgba(91,59,255,0.18)' : '0 10px 30px rgba(107,77,255,0.12)' };
  if (T.dir === 'acid') return { background: T.card, border: `2px solid ${T.line}`, borderRadius: T.radius, boxShadow: T.dark ? 'none' : T.shadow };
  return { background: T.card, borderRadius: T.radius, boxShadow: T.puff };
}
function btnStyle(T, kind = 'primary') {
  const base = { height: 56, borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: T.body, fontWeight: 800, fontSize: 16,
    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, padding: '0 24px', position: 'relative', overflow: 'hidden' };
  if (kind === 'ghost') return { ...base, background: 'transparent', color: T.text, border: `2px solid ${T.dir === 'acid' ? T.line : T.line}` };
  if (T.dir === 'chrome') return { ...base, background: T.grad, color: T.onAccent, boxShadow: '0 8px 30px rgba(201,184,255,0.35)' };
  if (T.dir === 'acid') return { ...base, background: T.accent, color: T.onAccent, borderRadius: 14, border: `2px solid ${T.dark ? T.accent : T.line}`, boxShadow: T.shadow, fontFamily: T.display, fontWeight: 400, letterSpacing: 0.5 };
  return { ...base, background: T.accent, color: T.onAccent, boxShadow: `inset 0 3px 0 rgba(255,255,255,0.45), inset 0 -6px 0 rgba(0,0,0,0.18), 0 10px 22px ${T.accent}55` };
}

// ── backgrounds ──
function Backdrop({ T, mood }) {
  if (T.dir === 'chrome') {
    const on = mood === 'connected';
    return (
      <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: T.bg }}>
        {T.blobs.map((c, i) => (
          <div key={i} style={{ position: 'absolute', width: 340, height: 340, borderRadius: '50%', background: c,
            filter: 'blur(70px)', opacity: (T.dark ? 0.45 : 0.7) * (mood === 'error' ? 0.35 : on ? 1 : 0.6),
            left: [-80, 180, 40][i], top: [80, 300, 560][i], transition: 'opacity 1s',
            animation: `y2k-drift${i + 1} ${[14, 18, 22][i] / (mood === 'connecting' ? 3 : 1)}s ease-in-out infinite` }}></div>
        ))}
        <div style={{ position: 'absolute', inset: 0, backgroundImage: `radial-gradient(${T.dark ? 'rgba(255,255,255,0.05)' : 'rgba(18,19,32,0.05)'} 1px, transparent 1px)`, backgroundSize: '4px 4px' }}></div>
      </div>
    );
  }
  if (T.dir === 'acid') {
    const gc = T.dark ? 'rgba(198,255,0,0.35)' : 'rgba(107,43,255,0.35)';
    return (
      <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: T.dark ? `radial-gradient(120% 60% at 50% 0%, #2A1558 0%, ${T.bg} 60%)` : `radial-gradient(120% 60% at 50% 0%, #FFFFFF 0%, ${T.bg} 60%)` }}>
        <div style={{ position: 'absolute', left: '-50%', right: '-50%', bottom: -40, height: 380, transformOrigin: '50% 100%', transform: 'perspective(260px) rotateX(62deg)',
          backgroundImage: `linear-gradient(${gc} 1.5px, transparent 1.5px), linear-gradient(90deg, ${gc} 1.5px, transparent 1.5px)`, backgroundSize: '40px 40px',
          animation: `y2k-grid ${mood === 'connecting' ? 0.25 : 1.6}s linear infinite`, maskImage: 'linear-gradient(transparent, #000 60%)', WebkitMaskImage: 'linear-gradient(transparent, #000 60%)' }}></div>
        {[[40, 120], [340, 90], [300, 260], [70, 420], [360, 470], [180, 60]].map(([x, y], i) => (
          <div key={i} style={{ position: 'absolute', left: x, top: y, color: i % 2 ? T.accent2 : T.accent, fontSize: 14 + (i % 3) * 6,
            animation: `y2k-twinkle ${2 + i * 0.4}s ease-in-out ${i * 0.3}s infinite` }}>✦</div>
        ))}
      </div>
    );
  }
  // jelly
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: T.dark ? `radial-gradient(100% 70% at 50% 30%, #3A1650 0%, ${T.bg} 70%)` : `radial-gradient(100% 70% at 50% 30%, #FFF6FA 0%, ${T.bg} 70%)` }}>
      {Array.from({ length: 12 }).map((_, i) => {
        const s = 10 + (i * 37) % 34;
        const c = [T.accent, T.accent2, T.accent3][i % 3];
        return <div key={i} style={{ position: 'absolute', left: (i * 83) % 400, bottom: -60, width: s, height: s, borderRadius: '50%',
          background: `radial-gradient(circle at 30% 30%, #fff 0 18%, ${c}AA 45%, ${c}33 100%)`, opacity: T.dark ? 0.55 : 0.7,
          animation: `y2k-rise ${(10 + (i % 5) * 3) / (mood === 'connecting' ? 3 : 1)}s linear ${-i * 1.7}s infinite` }}></div>;
      })}
    </div>
  );
}

// ── icons (stroke) ──
function Ico({ n, s = 24, c = 'currentColor', w = 2 }) {
  const P = {
    home: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z',
    apps: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
    gear: 'M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z',
    chev: 'M9 6l6 6-6 6', search: 'M11 18a7 7 0 100-14 7 7 0 000 14zM21 21l-4.3-4.3',
    wifioff: 'M2 2l20 20M8.5 16.5a5 5 0 017 0M5 12.9a10 10 0 015.2-2.8M19 12.9a10 10 0 00-2.3-1.6M2 8.8a15 15 0 014.2-2.7M22 8.8A15 15 0 0010.7 5M12 20h.01',
    retry: 'M3 12a9 9 0 0115.5-6.3L21 8M21 3v5h-5M21 12a9 9 0 01-15.5 6.3L3 16M3 21v-5h5',
    power: 'M12 2v10M18.4 6.6a9 9 0 11-12.8 0', bolt: 'M13 2L4 14h7l-1 8 9-12h-7l1-8z', globe: 'M12 21a9 9 0 100-18 9 9 0 000 18zM3 12h18M12 3a14 14 0 010 18M12 3a14 14 0 000 18',
  };
  return <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d={P[n]}></path></svg>;
}

// Netherlands-style flag disk
function Flag({ s = 36, c = ['#AE1C28', '#FFFFFF', '#21468B'] }) {
  return <div style={{ width: s, height: s, borderRadius: '50%', flexShrink: 0, background: `linear-gradient(${c[0]} 0 33.3%, ${c[1]} 33.3% 66.6%, ${c[2]} 66.6%)`, boxShadow: 'inset 0 0 0 1.5px rgba(0,0,0,0.12)' }}></div>;
}

// ── phone shell: edge-to-edge content with overlaid status bar + gesture pill ──
function Phone({ T, children }) {
  const c = T.dark ? '#fff' : '#111';
  return (
    <div style={{ width: 412, height: 880, borderRadius: 44, border: '7px solid #0d0d10', boxSizing: 'border-box', overflow: 'hidden', position: 'relative', background: T.bg,
      boxShadow: '0 30px 80px rgba(0,0,0,0.3), inset 0 0 0 1px rgba(255,255,255,0.06)', fontFamily: T.body, color: T.text }}>
      {children}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 22px', zIndex: 60, pointerEvents: 'none', fontFamily: 'Roboto, system-ui', fontSize: 14, color: c }}>
        <span>12:47</span>
        <div style={{ position: 'absolute', left: '50%', top: 10, width: 22, height: 22, marginLeft: -11, borderRadius: 11, background: '#0d0d10' }}></div>
        <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
          <svg width="15" height="15" viewBox="0 0 16 16"><path d="M8 13.3L.67 5.97a10.37 10.37 0 0114.66 0L8 13.3z" fill={c}></path></svg>
          <svg width="15" height="15" viewBox="0 0 16 16"><path d="M14.67 14.67V1.33L1.33 14.67h13.34z" fill={c}></path></svg>
          <svg width="15" height="15" viewBox="0 0 16 16"><rect x="3.75" y="2" width="8.5" height="13" rx="1.5" fill={c}></rect></svg>
        </div>
      </div>
      <div style={{ position: 'absolute', bottom: 8, left: '50%', width: 108, height: 4, marginLeft: -54, borderRadius: 2, background: c, opacity: 0.45, zIndex: 60, pointerEvents: 'none' }}></div>
    </div>
  );
}

Object.assign(window, { useTime, DIRS, themeFor, cardStyle, btnStyle, Backdrop, Ico, Flag, Phone, SPRING });
