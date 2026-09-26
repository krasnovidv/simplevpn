// 6 logo directions for RKNPNH — neon cyber palette, each rendered as
// app-icon (rounded square), social avatar (circle), and a sticker variant.

const NEON = {
  bg: '#0a0612',
  bgAlt: '#120a1f',
  ink: '#0a0612',
  cyan: '#00f0ff',
  magenta: '#ff2bd6',
  purple: '#a259ff',
  yellow: '#fff200',
  white: '#f5f3ff',
  dim: '#5a4a7a',
};

const ICON = (bg, extra = {}) => ({
  width: 220, height: 220, borderRadius: 48,
  background: bg, position: 'relative', overflow: 'hidden',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontFamily: '"Space Grotesk", "Inter", system-ui, sans-serif',
  ...extra,
});

const AVATAR = (bg, extra = {}) => ({
  width: 220, height: 220, borderRadius: '50%',
  background: bg, position: 'relative', overflow: 'hidden',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontFamily: '"Space Grotesk", "Inter", system-ui, sans-serif',
  ...extra,
});

const STICKER = (bg, extra = {}) => ({
  width: 320, height: 220,
  background: bg, position: 'relative', overflow: 'hidden',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontFamily: '"Space Grotesk", "Inter", system-ui, sans-serif',
  ...extra,
});

// ─── 01 — Balaclava Cat ──────────────────────────────────────
function BalaclavaCat({ size = 140, accent = NEON.cyan, eye = NEON.magenta }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100">
      <path d="M20 50 Q20 20 50 20 Q80 20 80 50 L80 78 Q80 88 70 88 L30 88 Q20 88 20 78 Z" fill={NEON.ink} stroke={accent} strokeWidth="2.5"/>
      <path d="M28 28 L24 14 L38 22 Z" fill={NEON.ink} stroke={accent} strokeWidth="2.5" strokeLinejoin="round"/>
      <path d="M72 28 L76 14 L62 22 Z" fill={NEON.ink} stroke={accent} strokeWidth="2.5" strokeLinejoin="round"/>
      <path d="M28 44 Q28 38 34 38 L66 38 Q72 38 72 44 L72 56 Q72 62 66 62 L34 62 Q28 62 28 56 Z" fill={accent}/>
      <circle cx="40" cy="50" r="5" fill={NEON.ink}/>
      <circle cx="60" cy="50" r="5" fill={NEON.ink}/>
      <circle cx="41.5" cy="48.5" r="1.6" fill={eye}/>
      <circle cx="61.5" cy="48.5" r="1.6" fill={eye}/>
      <circle cx="36" cy="74" r="1" fill={accent}/>
      <circle cx="50" cy="76" r="1" fill={accent}/>
      <circle cx="64" cy="74" r="1" fill={accent}/>
    </svg>
  );
}

function Logo01_Icon() {
  return (
    <div style={ICON(NEON.bg)}>
      <div style={{ position: 'absolute', inset: -40, background: `radial-gradient(circle at 50% 60%, ${NEON.purple}40, transparent 60%)` }} />
      <BalaclavaCat size={150} accent={NEON.cyan} eye={NEON.magenta} />
      <div style={{ position: 'absolute', bottom: 14, left: 0, right: 0, textAlign: 'center',
        fontSize: 11, fontWeight: 800, letterSpacing: 3, color: NEON.cyan }}>RKNPNH</div>
    </div>
  );
}
function Logo01_Avatar() {
  return (
    <div style={AVATAR(NEON.bg)}>
      <div style={{ position: 'absolute', inset: -40, background: `radial-gradient(circle, ${NEON.purple}40, transparent 60%)` }} />
      <BalaclavaCat size={170} accent={NEON.cyan} eye={NEON.magenta} />
    </div>
  );
}
function Logo01_Sticker() {
  return (
    <div style={STICKER(NEON.bg, { gap: 18, padding: 24 })}>
      <BalaclavaCat size={130} accent={NEON.cyan} eye={NEON.magenta} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div style={{ fontSize: 36, fontWeight: 900, letterSpacing: 1, color: NEON.white, lineHeight: 1 }}>RKNPNH</div>
        <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: 4, color: NEON.cyan }}>STAY ANON</div>
      </div>
    </div>
  );
}

// ─── 02 — Glitched Tongue Hex ────────────────────────────────
function TongueFace({ size = 140 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100">
      <defs>
        <linearGradient id="tf-grad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={NEON.yellow}/>
          <stop offset="1" stopColor="#ffae00"/>
        </linearGradient>
        <pattern id="tf-scan" width="2" height="3" patternUnits="userSpaceOnUse">
          <rect width="2" height="1.4" fill="rgba(0,0,0,0.18)"/>
        </pattern>
      </defs>
      <circle cx="50" cy="50" r="40" fill="url(#tf-grad)"/>
      <g stroke={NEON.ink} strokeWidth="3.5" strokeLinecap="round">
        <path d="M30 40 L40 50 M40 40 L30 50"/>
        <path d="M60 40 L70 50 M70 40 L60 50"/>
      </g>
      <path d="M30 62 Q50 80 70 62" fill="none" stroke={NEON.ink} strokeWidth="3.5" strokeLinecap="round"/>
      <path d="M44 70 Q44 84 50 84 Q56 84 56 70 Z" fill={NEON.magenta} stroke={NEON.ink} strokeWidth="2.5"/>
      <line x1="50" y1="74" x2="50" y2="82" stroke={NEON.ink} strokeWidth="1.5"/>
      <circle cx="50" cy="50" r="40" fill="url(#tf-scan)"/>
      <rect x="0" y="48" width="100" height="4" fill={NEON.cyan} opacity="0.7" transform="translate(3 0)"/>
      <rect x="0" y="48" width="100" height="4" fill={NEON.magenta} opacity="0.7" transform="translate(-3 0)"/>
    </svg>
  );
}
function Logo02_Icon() {
  return (
    <div style={ICON(NEON.bgAlt)}>
      <div style={{ position: 'absolute', inset: 0,
        backgroundImage: `repeating-linear-gradient(0deg, transparent 0 3px, rgba(255,255,255,0.03) 3px 4px)` }}/>
      <TongueFace size={150}/>
    </div>
  );
}
function Logo02_Avatar() {
  return (
    <div style={AVATAR(NEON.bgAlt)}>
      <div style={{ position: 'absolute', inset: 0,
        backgroundImage: `repeating-linear-gradient(0deg, transparent 0 3px, rgba(255,255,255,0.03) 3px 4px)` }}/>
      <TongueFace size={160}/>
    </div>
  );
}
function Logo02_Sticker() {
  return (
    <div style={STICKER(NEON.bgAlt, { padding: 24, gap: 18 })}>
      <div style={{ position: 'absolute', inset: 0,
        backgroundImage: `repeating-linear-gradient(0deg, transparent 0 3px, rgba(255,255,255,0.03) 3px 4px)` }}/>
      <TongueFace size={140}/>
      <div style={{ position: 'relative', display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontSize: 38, fontWeight: 900, color: NEON.yellow, lineHeight: 0.95, letterSpacing: -1, textShadow: `3px 3px 0 ${NEON.magenta}` }}>RKN</div>
        <div style={{ fontSize: 38, fontWeight: 900, color: NEON.yellow, lineHeight: 0.95, letterSpacing: -1, textShadow: `3px 3px 0 ${NEON.cyan}` }}>PNH</div>
      </div>
    </div>
  );
}

// ─── 03 — Burning Camera ─────────────────────────────────────
function BurningCam({ size = 140 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100">
      <defs>
        <radialGradient id="bc-flame" cx="0.5" cy="0.7" r="0.6">
          <stop offset="0" stopColor={NEON.yellow}/>
          <stop offset="0.5" stopColor={NEON.magenta}/>
          <stop offset="1" stopColor={NEON.purple} stopOpacity="0"/>
        </radialGradient>
      </defs>
      <path d="M20 40 Q15 20 28 22 Q26 10 38 14 Q40 4 50 10 Q60 4 62 14 Q74 10 72 22 Q85 20 80 40 Q90 30 88 50 Q92 65 80 62 Q82 75 70 70 Q70 80 58 74 Q54 84 50 78 Q46 84 42 74 Q30 80 30 70 Q18 75 20 62 Q8 65 12 50 Q10 30 20 40 Z" fill="url(#bc-flame)"/>
      <g transform="translate(50 56) rotate(-8)">
        <rect x="-22" y="-10" width="32" height="20" rx="3" fill={NEON.ink} stroke={NEON.cyan} strokeWidth="2"/>
        <circle cx="14" cy="0" r="9" fill={NEON.ink} stroke={NEON.cyan} strokeWidth="2"/>
        <circle cx="14" cy="0" r="5" fill={NEON.cyan}/>
        <circle cx="12" cy="-2" r="1.5" fill={NEON.white}/>
        <rect x="-22" y="-16" width="6" height="6" fill={NEON.ink} stroke={NEON.cyan} strokeWidth="2"/>
        <line x1="-19" y1="-16" x2="-19" y2="-26" stroke={NEON.cyan} strokeWidth="2"/>
        <g stroke={NEON.magenta} strokeWidth="2.5" strokeLinecap="round">
          <path d="M10 -4 L18 4"/>
          <path d="M18 -4 L10 4"/>
        </g>
      </g>
      <circle cx="22" cy="24" r="1.5" fill={NEON.yellow}/>
      <circle cx="80" cy="30" r="1.2" fill={NEON.yellow}/>
      <circle cx="74" cy="14" r="1" fill={NEON.white}/>
    </svg>
  );
}
function Logo03_Icon() {
  return (
    <div style={ICON(NEON.bg)}>
      <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(circle at 50% 70%, #ff2bd640, transparent 65%)` }}/>
      <BurningCam size={170}/>
    </div>
  );
}
function Logo03_Avatar() {
  return (
    <div style={AVATAR(NEON.bg)}>
      <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(circle at 50% 70%, #ff2bd640, transparent 65%)` }}/>
      <BurningCam size={180}/>
    </div>
  );
}
function Logo03_Sticker() {
  return (
    <div style={STICKER(NEON.bg, { padding: 20, gap: 14 })}>
      <BurningCam size={160}/>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start' }}>
        <div style={{ fontSize: 32, fontWeight: 900, color: NEON.yellow, lineHeight: 1, letterSpacing: 0 }}>RKNPNH</div>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 3, color: NEON.magenta, marginTop: 4 }}>NO SIGNAL</div>
      </div>
    </div>
  );
}

// ─── 04 — Glitch Wordmark ────────────────────────────────────
function Logo04_Icon() {
  return (
    <div style={ICON(NEON.bg)}>
      <div style={{ position: 'absolute', inset: 0,
        background: `repeating-linear-gradient(0deg, transparent 0 6px, rgba(0,240,255,0.05) 6px 7px)` }}/>
      <div style={{ position: 'relative', textAlign: 'center', lineHeight: 0.9 }}>
        <div style={{ fontSize: 56, fontWeight: 900, color: NEON.white, letterSpacing: -2, position: 'relative' }}>
          <span style={{ position: 'absolute', inset: 0, color: NEON.cyan, transform: 'translate(-3px, 0)', mixBlendMode: 'screen' }}>RKN</span>
          <span style={{ position: 'absolute', inset: 0, color: NEON.magenta, transform: 'translate(3px, 0)', mixBlendMode: 'screen' }}>RKN</span>
          <span style={{ position: 'relative' }}>RKN</span>
        </div>
        <div style={{ fontSize: 56, fontWeight: 900, color: NEON.white, letterSpacing: -2, position: 'relative', marginTop: 4 }}>
          <span style={{ position: 'absolute', inset: 0, color: NEON.cyan, transform: 'translate(-3px, 0)', mixBlendMode: 'screen' }}>PNH</span>
          <span style={{ position: 'absolute', inset: 0, color: NEON.magenta, transform: 'translate(3px, 0)', mixBlendMode: 'screen' }}>PNH</span>
          <span style={{ position: 'relative' }}>PNH</span>
        </div>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: '52%', height: 6, background: NEON.bg }}/>
      <div style={{ position: 'absolute', left: 4, right: 0, top: '54%', height: 2, background: NEON.cyan, opacity: 0.8 }}/>
    </div>
  );
}
function Logo04_Avatar() {
  return (
    <div style={AVATAR(NEON.bg)}>
      <div style={{ position: 'relative', textAlign: 'center', lineHeight: 0.9 }}>
        <div style={{ fontSize: 50, fontWeight: 900, color: NEON.white, letterSpacing: -2, position: 'relative' }}>
          <span style={{ position: 'absolute', inset: 0, color: NEON.cyan, transform: 'translate(-3px, 0)', mixBlendMode: 'screen' }}>RKN</span>
          <span style={{ position: 'absolute', inset: 0, color: NEON.magenta, transform: 'translate(3px, 0)', mixBlendMode: 'screen' }}>RKN</span>
          <span style={{ position: 'relative' }}>RKN</span>
        </div>
        <div style={{ fontSize: 50, fontWeight: 900, color: NEON.white, letterSpacing: -2, position: 'relative', marginTop: 4 }}>
          <span style={{ position: 'absolute', inset: 0, color: NEON.cyan, transform: 'translate(-3px, 0)', mixBlendMode: 'screen' }}>PNH</span>
          <span style={{ position: 'absolute', inset: 0, color: NEON.magenta, transform: 'translate(3px, 0)', mixBlendMode: 'screen' }}>PNH</span>
          <span style={{ position: 'relative' }}>PNH</span>
        </div>
      </div>
    </div>
  );
}
function Logo04_Sticker() {
  return (
    <div style={STICKER(NEON.bg, { flexDirection: 'column', gap: 4 })}>
      <div style={{ position: 'relative' }}>
        <div style={{ fontSize: 78, fontWeight: 900, color: NEON.white, letterSpacing: -3, lineHeight: 0.9 }}>
          <span style={{ position: 'absolute', inset: 0, color: NEON.cyan, transform: 'translate(-4px, 0)', mixBlendMode: 'screen' }}>RKNPNH</span>
          <span style={{ position: 'absolute', inset: 0, color: NEON.magenta, transform: 'translate(4px, 0)', mixBlendMode: 'screen' }}>RKNPNH</span>
          <span style={{ position: 'relative' }}>RKNPNH</span>
        </div>
      </div>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 6, color: NEON.cyan }}>// VPN.EXE_</div>
    </div>
  );
}

// ─── 05 — Vanish Ghost ───────────────────────────────────────
function Ghost({ size = 140 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100">
      <defs>
        <linearGradient id="g-grad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={NEON.cyan}/>
          <stop offset="1" stopColor={NEON.purple}/>
        </linearGradient>
      </defs>
      <path d="M22 50 Q22 22 50 22 Q78 22 78 50 L78 84 L72 78 L66 84 L60 78 L54 84 L46 84 L40 78 L34 84 L28 78 L22 84 Z"
        fill="url(#g-grad)" stroke={NEON.white} strokeWidth="2" strokeLinejoin="round"/>
      <ellipse cx="40" cy="48" rx="5" ry="7" fill={NEON.ink}/>
      <ellipse cx="60" cy="48" rx="5" ry="7" fill={NEON.ink}/>
      <circle cx="41.5" cy="46" r="1.6" fill={NEON.white}/>
      <circle cx="61.5" cy="46" r="1.6" fill={NEON.white}/>
      <path d="M42 62 Q50 70 58 62 L58 62 Q58 72 50 72 Q42 72 42 62 Z" fill={NEON.ink}/>
      <path d="M48 68 Q48 76 52 76 Q56 76 56 68 Z" fill={NEON.magenta}/>
      <circle cx="32" cy="58" r="3" fill={NEON.magenta} opacity="0.5"/>
      <circle cx="68" cy="58" r="3" fill={NEON.magenta} opacity="0.5"/>
    </svg>
  );
}
function Logo05_Icon() {
  return (
    <div style={ICON(NEON.bg)}>
      <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(circle at 50% 50%, ${NEON.cyan}30, transparent 65%)` }}/>
      <Ghost size={160}/>
    </div>
  );
}
function Logo05_Avatar() {
  return (
    <div style={AVATAR(NEON.bg)}>
      <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(circle at 50% 50%, ${NEON.cyan}30, transparent 65%)` }}/>
      <Ghost size={170}/>
    </div>
  );
}
function Logo05_Sticker() {
  return (
    <div style={STICKER(NEON.bg, { padding: 20, gap: 18 })}>
      <Ghost size={150}/>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontSize: 34, fontWeight: 900, color: NEON.white, letterSpacing: 0, lineHeight: 1 }}>RKNPNH</div>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 3, color: NEON.cyan, marginTop: 4 }}>POOF. GONE.</div>
      </div>
    </div>
  );
}

// ─── 06 — NOT APPROVED Stamp ─────────────────────────────────
function Logo06_Icon() {
  return (
    <div style={ICON('#1a0a1f', { padding: 18 })}>
      <div style={{
        border: `5px solid ${NEON.magenta}`, borderRadius: 8, padding: '12px 14px',
        transform: 'rotate(-7deg)', position: 'relative',
        boxShadow: `inset 0 0 0 2px ${NEON.bg}, 0 0 24px ${NEON.magenta}40`,
      }}>
        <div style={{ fontSize: 38, fontWeight: 900, color: NEON.magenta, letterSpacing: 2, lineHeight: 1, fontFamily: '"Archivo Black", "Inter", sans-serif' }}>RKNPNH</div>
        <div style={{ fontSize: 9, fontWeight: 700, color: NEON.magenta, letterSpacing: 4, textAlign: 'center', marginTop: 4 }}>★ NOT APPROVED ★</div>
      </div>
    </div>
  );
}
function Logo06_Avatar() {
  return (
    <div style={AVATAR('#1a0a1f')}>
      <div style={{
        border: `5px solid ${NEON.magenta}`, borderRadius: 8, padding: '10px 12px',
        transform: 'rotate(-7deg)',
        boxShadow: `0 0 24px ${NEON.magenta}40`,
      }}>
        <div style={{ fontSize: 32, fontWeight: 900, color: NEON.magenta, letterSpacing: 2, lineHeight: 1 }}>RKNPNH</div>
        <div style={{ fontSize: 8, fontWeight: 700, color: NEON.magenta, letterSpacing: 3, textAlign: 'center', marginTop: 3 }}>★ NOT APPROVED ★</div>
      </div>
    </div>
  );
}
function Logo06_Sticker() {
  return (
    <div style={STICKER('#1a0a1f', { padding: 24 })}>
      <div style={{
        border: `6px solid ${NEON.magenta}`, borderRadius: 10, padding: '16px 22px',
        transform: 'rotate(-5deg)',
        boxShadow: `0 0 32px ${NEON.magenta}50`,
      }}>
        <div style={{ fontSize: 56, fontWeight: 900, color: NEON.magenta, letterSpacing: 2, lineHeight: 1 }}>RKNPNH</div>
        <div style={{ fontSize: 12, fontWeight: 700, color: NEON.magenta, letterSpacing: 6, textAlign: 'center', marginTop: 6 }}>★ NOT APPROVED ★</div>
      </div>
    </div>
  );
}

Object.assign(window, {
  Logo01_Icon, Logo01_Avatar, Logo01_Sticker,
  Logo02_Icon, Logo02_Avatar, Logo02_Sticker,
  Logo03_Icon, Logo03_Avatar, Logo03_Sticker,
  Logo04_Icon, Logo04_Avatar, Logo04_Sticker,
  Logo05_Icon, Logo05_Avatar, Logo05_Sticker,
  Logo06_Icon, Logo06_Avatar, Logo06_Sticker,
  NEON,
});
