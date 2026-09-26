// RKNPNH redesign — screens + app state. Depends on core.jsx + heroes.jsx.
const { useState: uS, useEffect: uE, useRef: uR } = React;
const fmtT = (s) => [Math.floor(s / 3600), Math.floor(s / 60) % 60, s % 60].map(n => String(n).padStart(2, '0')).join(':');

function Wordmark({ T }) {
  if (T.dir === 'chrome') return <div style={{ fontFamily: T.display, fontWeight: 800, fontSize: 20, letterSpacing: 1, background: T.grad, WebkitBackgroundClip: 'text', color: 'transparent', filter: T.dark ? 'none' : 'saturate(1.4) brightness(.8)' }}>RKNPNH</div>;
  if (T.dir === 'acid') return <div style={{ fontFamily: T.display, fontSize: 20, color: T.dark ? T.accent : T.text, display: 'flex', alignItems: 'center', gap: 6 }}>RKN<span style={{ color: T.accent2 }}>✦</span>PNH</div>;
  return <div style={{ fontFamily: T.display, fontWeight: 900, fontSize: 24, color: T.accent, letterSpacing: -0.5, textShadow: T.dark ? 'none' : '0 3px 0 rgba(255,62,154,0.18)' }}>rknpnh</div>;
}

function Chip({ T, mood }) {
  const txt = { idle: 'засвечен', connecting: 'прячемся', disconnecting: 'выходим', connected: 'невидимка', error: 'нет сети' }[mood];
  const busy = mood === 'connecting' || mood === 'disconnecting';
  const c = mood === 'connected' ? T.good : busy ? (T.accent3 || T.accent) : T.bad;
  const dot = <span style={{ width: 8, height: 8, borderRadius: 4, background: c, animation: busy ? 'y2k-pulse .6s infinite' : 'none', boxShadow: `0 0 10px ${c}` }}></span>;
  if (T.dir === 'acid') return <div key={mood} style={{ '--r': '-5deg', animation: 'y2k-pop .5s both', transform: 'rotate(-5deg)', background: mood === 'connected' ? T.accent : T.accent2, color: mood === 'connected' ? T.onAccent : '#fff', fontFamily: T.display, fontSize: 12, padding: '6px 12px', borderRadius: 8, border: `2px solid ${T.dark ? T.bg : T.line}`, letterSpacing: 1, textTransform: 'uppercase' }}>{txt}</div>;
  if (T.dir === 'jelly') return <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.card, boxShadow: T.puff, borderRadius: 999, padding: '8px 14px', fontWeight: 800, fontSize: 13 }}>{dot}{txt}</div>;
  return <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.card, border: `1px solid ${T.line}`, backdropFilter: 'blur(12px)', borderRadius: 999, padding: '7px 14px', fontWeight: 700, fontSize: 12, letterSpacing: 0.5 }}>{dot}{txt}</div>;
}

function Headline({ T, lines, size, hot }) {
  const fs = size || { chrome: 46, acid: 54, jelly: 58 }[T.dir];
  const st = { fontFamily: T.display, fontSize: fs, lineHeight: 0.98, fontWeight: T.dir === 'jelly' ? 900 : 800, letterSpacing: T.dir === 'chrome' ? -1 : T.dir === 'jelly' ? -2 : 0, textTransform: T.upper ? 'uppercase' : 'none', margin: 0, textWrap: 'balance' };
  return (
    <h1 className="y2k-in" key={lines.join()} style={st}>
      {lines.map((l, i) => {
        const accentLine = i === lines.length - 1;
        let s = {};
        if (accentLine && T.dir === 'chrome') s = hot ? { background: T.grad, WebkitBackgroundClip: 'text', color: 'transparent', filter: T.dark ? 'none' : 'saturate(1.5) brightness(.78)' } : { color: T.sub };
        if (accentLine && T.dir === 'acid') s = { color: hot ? T.accent : T.accent2, WebkitTextStroke: T.dark ? 0 : `1.5px ${T.line}` };
        if (accentLine && T.dir === 'jelly') s = { color: hot ? T.accent2 : T.accent };
        return <div key={i} style={s}>{l}</div>;
      })}
    </h1>
  );
}

function Switch({ T, on, onChange }) {
  const trackOn = T.dir === 'chrome' ? T.grad : T.accent;
  return (
    <div onClick={(e) => { e.stopPropagation(); onChange(!on); }} role="switch" aria-checked={on} style={{ width: 52, height: 32, borderRadius: 16, flexShrink: 0, cursor: 'pointer', position: 'relative',
      background: on ? trackOn : 'transparent', border: `2px solid ${on ? 'transparent' : T.sub}`, boxSizing: 'border-box', transition: 'background .25s',
      boxShadow: T.dir === 'jelly' && on ? 'inset 0 -3px 0 rgba(0,0,0,0.15)' : T.dir === 'acid' && on && !T.dark ? `2px 2px 0 ${T.line}` : 'none' }}>
      <div style={{ position: 'absolute', top: '50%', left: on ? 24 : 6, width: on ? 24 : 16, height: on ? 24 : 16, marginTop: on ? -12 : -8, borderRadius: '50%',
        background: on ? (T.dir === 'chrome' ? T.onAccent : T.onAccent) : T.sub, transition: `all .35s ${SPRING}` }}></div>
    </div>
  );
}

function NavBar({ T, screen, go }) {
  const items = [['main', 'home', 'Главная'], ['split', 'apps', 'Приложения'], ['settings', 'gear', 'Настройки']];
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 20, height: 100, paddingBottom: 20, boxSizing: 'border-box', display: 'flex', justifyContent: 'space-around', alignItems: 'center',
      background: T.nav, backdropFilter: 'blur(20px)', borderTop: T.dir === 'acid' ? `2px solid ${T.line}` : `1px solid ${T.line}` }}>
      {items.map(([k, ic, lb]) => {
        const a = screen === k || (k === 'main' && screen === 'error');
        const pill = T.dir === 'chrome' ? { background: T.grad } : T.dir === 'acid' ? { background: T.accent, border: `2px solid ${T.dark ? T.accent : T.line}` } : { background: T.accent, boxShadow: 'inset 0 2px 0 rgba(255,255,255,.4), inset 0 -3px 0 rgba(0,0,0,.15)' };
        return (
          <div key={k} onClick={() => go(k)} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, cursor: 'pointer', minWidth: 80 }}>
            <div style={{ width: a ? 64 : 32, height: 32, borderRadius: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', transition: `all .4s ${SPRING}`, ...(a ? pill : {}) }}>
              <Ico n={ic} s={22} c={a ? T.onAccent : T.sub}></Ico>
            </div>
            <div style={{ fontSize: 12, fontWeight: a ? 800 : 600, color: a ? T.text : T.sub }}>{lb}</div>
          </div>
        );
      })}
    </div>
  );
}

function TopBar({ T, right }) {
  return <div style={{ position: 'relative', zIndex: 5, height: 56, marginTop: 44, padding: '0 22px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}><Wordmark T={T}></Wordmark>{right}</div>;
}

function Tape({ T, text }) {
  const row = Array(6).fill(text).join('  ✦  ');
  return (
    <div style={{ position: 'absolute', left: -20, right: -20, transform: 'rotate(-4deg)', background: T.accent2, color: '#fff', borderTop: `2px solid ${T.dark ? T.bg : T.line}`, borderBottom: `2px solid ${T.dark ? T.bg : T.line}`, overflow: 'hidden', whiteSpace: 'nowrap', fontFamily: T.display, fontSize: 13, padding: '6px 0', letterSpacing: 1 }}>
      <div style={{ display: 'inline-block', animation: 'y2k-marquee 12s linear infinite' }}>{row}  ✦  {row}  ✦  </div>
    </div>
  );
}

// ─── MAIN ───
function MainScreen({ T, mood, secs, toggle, go }) {
  const [pressed, setPressed] = uS(false);
  const L = { idle: ['Тебя', 'видно'], connecting: ['Прячем', 'тебя…'], disconnecting: ['Снимаем', 'маску…'], connected: ['Тебя', 'нет'] }[mood];
  const sub = { idle: 'РКН уже подглядывает. Жми на штуку — исчезнешь.', connecting: 'Заметаем следы, путаем провода…', connected: 'Для всех ты в Амстердаме. Для мамы — дома.', disconnecting: 'Возвращаем тебя в поле зрения. Сам захотел.' }[mood];
  return (
    <>
      <TopBar T={T} right={<Chip T={T} mood={mood}></Chip>}></TopBar>
      <div style={{ position: 'relative', zIndex: 3, padding: '14px 24px 0' }}>
        <Headline T={T} lines={L} hot={mood === 'connected'}></Headline>
        <p key={sub} className="y2k-in" style={{ margin: '12px 0 0', fontSize: 15, lineHeight: 1.45, color: T.sub, fontWeight: 600, maxWidth: 300, textWrap: 'pretty' }}>{sub}</p>
      </div>
      <div onClick={toggle} onPointerDown={() => setPressed(true)} onPointerUp={() => setPressed(false)} onPointerLeave={() => setPressed(false)}
        style={{ position: 'relative', zIndex: 3, height: 300, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', transform: pressed && T.dir !== 'jelly' ? 'scale(.94)' : 'none', transition: `transform .4s ${SPRING}` }}>
        <Hero T={T} mood={mood} size={T.dir === 'acid' ? 250 : 270} pressed={pressed}></Hero>
      </div>
      {T.dir === 'acid' && <div style={{ position: 'relative', height: 30, marginTop: -14, zIndex: 2 }}><Tape T={T} text={mood === 'connected' ? 'НЕ ОДОБРЕНО РКН' : 'ЖМИ НА ГЛОБУС'}></Tape></div>}
      <div style={{ position: 'relative', zIndex: 3, margin: T.dir === 'acid' ? '14px 20px 0' : '0 20px', padding: 16, ...cardStyle(T) }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <Flag></Flag>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 800, fontSize: 16 }}>Нидерланды</div>
            <div style={{ fontSize: 13, color: T.sub, fontWeight: 600 }}>Амстердам · единственный и любимый</div>
          </div>
          <div title="Сигнал" style={{ display: 'flex', alignItems: 'flex-end', gap: 3, height: 18 }}>
            {[6, 10, 14, 18].map((h, i) => <span key={i} style={{ width: 4, height: h, borderRadius: 2, transition: 'background .4s', background: i < ({ connected: 4, connecting: 2, disconnecting: 2 }[mood] || 1) ? (mood === 'connected' ? T.good : T.sub) : T.line }}></span>)}
          </div>
        </div>
        <div style={{ height: 1, background: T.line, margin: '14px 0 12px', opacity: T.dir === 'acid' ? 0.4 : 1 }}></div>
        <div key={mood} className="y2k-in" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', fontSize: 13, fontWeight: 700, color: T.sub }}>
          {mood === 'connected' && <><span style={{ fontFamily: T.display, fontSize: 20, color: T.text, fontVariantNumeric: 'tabular-nums', fontWeight: 700 }}>{fmtT(secs)}</span><span>IP 185.93.0.42</span></>}
          {mood === 'idle' && <><span>Твой IP 93.184.27.11</span><span style={{ color: T.bad }}>его видят все</span></>}
          {mood === 'connecting' && <><span>Ищем самый тёмный угол…</span><span style={{ color: T.accent3 || T.accent }}>••</span></>}
          {mood === 'disconnecting' && <><span>Закрываем туннель…</span><span style={{ color: T.accent3 || T.accent }}>••</span></>}
        </div>
      </div>
    </>
  );
}

// ─── SPLIT TUNNELING ───
const APPS = [
  ['Госуслуги', 'им и так всё известно', '#2E6BFF', true], ['Сбер', 'банки не любят Амстердам', '#21A038', true],
  ['Telegram', 'а вот тут лучше с нами', '#27A7E7', false], ['YouTube', 'без нас — слайд-шоу', '#FF0033', false],
  ['Яндекс Карты', 'чтобы такси нашло тебя', '#FFCC00', true], ['Instagram', 'сам знаешь почему', '#E1306C', false],
  ['Кинопоиск', 'работает и так', '#FF6600', true], ['Chrome', 'всё через туннель', '#4285F4', false],
];
function SplitScreen({ T }) {
  const [mode, setMode] = uS(1);
  const [on, setOn] = uS(APPS.map(a => a[3]));
  const n = on.filter(Boolean).length;
  const seg = ['Всё через VPN', 'Кроме этих', 'Только эти'];
  return (
    <div style={{ position: 'absolute', inset: 0, overflowY: 'auto', paddingBottom: 110, scrollbarWidth: 'none' }}>
      <TopBar T={T}></TopBar>
      <div style={{ padding: '8px 22px 0', position: 'relative', zIndex: 3 }}>
        <Headline T={T} lines={['Кому', 'без маски']} size={T.dir === 'chrome' ? 36 : 44} hot></Headline>
        <p style={{ margin: '10px 0 16px', color: T.sub, fontWeight: 600, fontSize: 14, lineHeight: 1.45 }}>Эти приложения пойдут напрямую — <b style={{ color: T.text }}>{n} из {APPS.length}</b>. Остальные спрячем.</p>
        <div style={{ display: 'flex', padding: 4, gap: 4, borderRadius: 999, ...(T.dir === 'acid' ? { border: `2px solid ${T.line}`, borderRadius: 14, background: T.card } : { background: T.card, boxShadow: T.dir === 'jelly' ? T.puff : 'none', border: T.dir === 'chrome' ? `1px solid ${T.line}` : 'none' }) }}>
          {seg.map((s, i) => (
            <div key={i} onClick={() => setMode(i)} style={{ flex: 1, textAlign: 'center', padding: '10px 4px', fontSize: 12.5, fontWeight: 800, cursor: 'pointer', borderRadius: T.dir === 'acid' ? 10 : 999, transition: `all .35s ${SPRING}`,
              ...(mode === i ? { background: T.dir === 'chrome' ? T.grad : T.accent, color: T.onAccent } : { color: T.sub }) }}>{s}</div>
          ))}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, margin: '14px 0', padding: '0 16px', height: 50, ...cardStyle(T), borderRadius: 999, boxShadow: 'none' }}>
          <Ico n="search" s={20} c={T.sub}></Ico><span style={{ color: T.sub, fontWeight: 600, fontSize: 15 }}>Найти приложение</span>
        </div>
        <div style={{ ...cardStyle(T), padding: '4px 0', opacity: mode === 0 ? 0.4 : 1, transition: 'opacity .3s', pointerEvents: mode === 0 ? 'none' : 'auto' }}>
          {APPS.map(([name, joke, c], i) => (
            <div key={name} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '11px 16px', borderTop: i ? `1px solid ${T.line}` : 'none', borderTopColor: T.dir === 'acid' ? 'rgba(128,128,128,0.25)' : T.line }}>
              <div style={{ width: 42, height: 42, borderRadius: T.dir === 'acid' ? 10 : 14, background: c, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 900, fontSize: 17, flexShrink: 0, boxShadow: T.dir === 'jelly' ? 'inset 0 2px 0 rgba(255,255,255,.35), inset 0 -3px 0 rgba(0,0,0,.18)' : 'none' }}>{name[0]}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 800, fontSize: 15 }}>{name}</div>
                <div style={{ fontSize: 12.5, color: T.sub, fontWeight: 600 }}>{joke}</div>
              </div>
              <Switch T={T} on={on[i]} onChange={(v) => setOn(o => o.map((x, j) => j === i ? v : x))}></Switch>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── SETTINGS ───
function SettingsScreen({ T, setDark }) {
  const [v, setV] = uS({ kill: true, auto: true, stealth: true, anim: true, notif: true });
  const tog = (k) => (x) => setV(o => ({ ...o, [k]: x }));
  const Row = ({ title, sub, k, value, last }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px', borderBottom: last ? 'none' : `1px solid ${T.dir === 'acid' ? 'rgba(128,128,128,0.25)' : T.line}` }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontWeight: 800, fontSize: 15 }}>{title}</div>
        {sub && <div style={{ fontSize: 12.5, color: T.sub, fontWeight: 600, lineHeight: 1.4, marginTop: 2 }}>{sub}</div>}
      </div>
      {k ? <Switch T={T} on={v[k]} onChange={tog(k)}></Switch> : <div style={{ display: 'flex', alignItems: 'center', gap: 2, color: T.sub, fontWeight: 700, fontSize: 13 }}>{value}<Ico n="chev" s={18}></Ico></div>}
    </div>
  );
  const Group = ({ label, children }) => (
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 12, fontWeight: 800, letterSpacing: 1.5, textTransform: 'uppercase', color: T.dir === 'acid' ? (T.dark ? T.accent : T.accent) : T.sub, margin: '0 6px 8px' }}>{label}</div>
      <div style={{ ...cardStyle(T), overflow: 'hidden' }}>{children}</div>
    </div>
  );
  const themes = [['Светлая', false], ['Тёмная', true]];
  return (
    <div style={{ position: 'absolute', inset: 0, overflowY: 'auto', paddingBottom: 110, scrollbarWidth: 'none' }}>
      <TopBar T={T}></TopBar>
      <div style={{ padding: '8px 20px 0', position: 'relative', zIndex: 3 }}>
        <div style={{ padding: '0 2px 18px' }}><Headline T={T} lines={['Настройки']} size={{ chrome: 30, acid: 34, jelly: 40 }[T.dir]} hot></Headline></div>
        <Group label="Защита">
          <Row title="Рубильник" sub="Упал VPN — режем интернет, чтобы ничего не утекло" k="kill"></Row>
          <Row title="Автоподключение" sub="В чужом Wi-Fi включаемся сами" k="auto"></Row>
          <Row title="Режим «Я не VPN»" sub="Притворяемся скучным HTTPS-трафиком" k="stealth" last></Row>
        </Group>
        <Group label="Соединение">
          <Row title="Протокол" value="VLESS Reality"></Row>
          <Row title="DNS" value="Свой, без слежки" last></Row>
        </Group>
        <Group label="Внешний вид">
          <div style={{ padding: 12, display: 'flex', gap: 8 }}>
            {themes.map(([l, d]) => (
              <div key={l} onClick={() => setDark(d)} style={{ flex: 1, textAlign: 'center', padding: '12px 0', borderRadius: T.dir === 'acid' ? 12 : 999, cursor: 'pointer', fontWeight: 800, fontSize: 14, transition: `all .35s ${SPRING}`,
                ...(T.dark === d ? { background: T.dir === 'chrome' ? T.grad : T.accent, color: T.onAccent } : { color: T.sub, border: `1.5px solid ${T.dir === 'acid' ? 'rgba(128,128,128,0.4)' : T.line}` }) }}>{l}</div>
            ))}
          </div>
          <Row title="Анимации на максимум" sub="Батарейке будет грустно. Нам — весело" k="anim"></Row>
          <Row title="Статус в шторке" sub="Таймер и трафик в уведомлении" k="notif" last></Row>
        </Group>
        <div style={{ textAlign: 'center', color: T.sub, fontSize: 12, fontWeight: 700, padding: '4px 0 10px' }}>RKNPNH 2.0 · сделано без одобрения</div>
      </div>
    </div>
  );
}

// ─── ERROR ───
function ErrorScreen({ T, retry }) {
  return (
    <>
      <TopBar T={T} right={<Chip T={T} mood="error"></Chip>}></TopBar>
      <div style={{ position: 'relative', zIndex: 3, height: 210, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Hero T={T} mood="error" size={190}></Hero>
      </div>
      <div style={{ position: 'relative', zIndex: 3, padding: '0 24px' }}>
        <Headline T={T} lines={['Интернет', 'ушёл', 'за хлебом']} size={{ chrome: 36, acid: 42, jelly: 46 }[T.dir]}></Headline>
        <p style={{ margin: '12px 0 22px', fontSize: 15, lineHeight: 1.45, color: T.sub, fontWeight: 600 }}>Проверь Wi-Fi или мобильные данные. Мы подождём — нам не привыкать.</p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <button onClick={retry} style={btnStyle(T)}><Ico n="retry" s={20} c={T.onAccent}></Ico>Попробовать снова</button>
          <button style={btnStyle(T, 'ghost')}>Настройки Wi-Fi</button>
        </div>
      </div>
      <div style={{ position: 'absolute', left: 16, right: 16, bottom: 112, zIndex: 25, display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px', borderRadius: T.dir === 'acid' ? 12 : 16,
        background: T.dark ? '#F4F1FA' : '#1E1B26', color: T.dark ? '#1E1B26' : '#F4F1FA', animation: 'y2k-snack .6s .3s both cubic-bezier(.2,1.3,.4,1)', boxShadow: '0 10px 30px rgba(0,0,0,0.3)' }}>
        <Ico n="bolt" s={20} c={T.dir === 'acid' ? T.accent2 : T.accent}></Ico>
        <div style={{ flex: 1, fontSize: 13.5, fontWeight: 700, lineHeight: 1.35 }}>Рубильник сработал: интернет выключен, ничего не утекло</div>
        <div style={{ fontWeight: 900, fontSize: 13, color: T.dir === 'acid' ? T.accent2 : T.accent }}>ОК</div>
      </div>
    </>
  );
}

// ─── HOME SCREEN: widgets + ongoing notification ───
function WidgetScreen({ T, mood, secs, toggle }) {
  const on = mood === 'connected';
  const wCard = { ...cardStyle(T), background: T.dir === 'chrome' ? cardStyle(T).background : T.card };
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {/* heads-up ongoing notification */}
      <div style={{ position: 'absolute', top: 46, left: 10, right: 10, zIndex: 10, padding: '12px 14px', borderRadius: 24, background: T.dark ? 'rgba(30,27,38,0.92)' : 'rgba(255,255,255,0.94)', backdropFilter: 'blur(20px)', boxShadow: '0 8px 30px rgba(0,0,0,0.2)', animation: 'y2k-in .7s both cubic-bezier(.2,1.3,.4,1)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: T.sub, fontWeight: 700 }}>
          <div style={{ width: 20, height: 20, borderRadius: 10, background: T.dir === 'chrome' ? T.grad : T.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Ico n="home" s={12} c={T.onAccent} w={3}></Ico></div>
          RKNPNH · {on ? fmtT(secs) : 'сейчас'}
        </div>
        <div style={{ fontWeight: 800, fontSize: 15, marginTop: 6 }}>{on ? 'Ты невидимка' : mood === 'connecting' ? 'Прячем тебя…' : 'Ты снова на виду'}</div>
        <div style={{ fontSize: 13, color: T.sub, fontWeight: 600, marginTop: 2 }}>{on ? 'Амстердам · спрятали 342 МБ' : 'Нажми, чтобы исчезнуть'}</div>
        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          <div onClick={toggle} style={{ padding: '8px 14px', borderRadius: 999, background: T.dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)', fontSize: 13, fontWeight: 800, cursor: 'pointer' }}>{on ? 'Отключить' : 'Подключить'}</div>
        </div>
      </div>
      {/* clock */}
      <div style={{ position: 'absolute', top: 230, left: 26, right: 26, zIndex: 3 }}>
        <div style={{ fontFamily: T.display, fontSize: 84, fontWeight: 800, lineHeight: 1, letterSpacing: -2 }}>12:47</div>
        <div style={{ fontSize: 16, fontWeight: 700, color: T.sub, marginTop: 6 }}>суббота, 26 сентября</div>
      </div>
      {/* 4×2 widget */}
      <div onClick={toggle} style={{ position: 'absolute', top: 390, left: 18, right: 18, height: 170, zIndex: 3, display: 'flex', alignItems: 'center', gap: 6, padding: '0 20px 0 6px', cursor: 'pointer', ...wCard }}>
        <div style={{ width: 150, height: 150, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Hero T={T} mood={mood} size={T.dir === 'acid' ? 118 : 140}></Hero></div>
        <div style={{ flex: 1 }}>
          <div style={{ fontFamily: T.display, fontSize: T.dir === 'chrome' ? 20 : 24, fontWeight: 800, lineHeight: 1.05, textTransform: T.upper ? 'uppercase' : 'none' }}>{on ? 'Тебя нет' : mood === 'connecting' ? 'Прячем…' : 'Тебя видно'}</div>
          <div style={{ fontSize: 13, color: T.sub, fontWeight: 700, margin: '6px 0 12px' }}>{on ? `Амстердам · ${fmtT(secs)}` : 'тапни по виджету'}</div>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 800, ...(on ? { background: T.dir === 'chrome' ? T.grad : T.accent, color: T.onAccent } : { border: `1.5px solid ${T.sub}`, color: T.text }) }}><Ico n="power" s={16} c={on ? T.onAccent : T.text}></Ico>{on ? 'Вкл' : 'Выкл'}</div>
        </div>
      </div>
      {/* 2×2 widgets */}
      <div style={{ position: 'absolute', top: 578, left: 18, right: 18, zIndex: 3, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
        <div onClick={toggle} style={{ height: 170, ...wCard, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6, cursor: 'pointer' }}>
          <div style={{ width: 96, height: 96, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: on ? (T.dir === 'chrome' ? T.grad : T.accent) : 'transparent', border: on ? 'none' : `2px dashed ${T.sub}`, transition: `all .4s ${SPRING}`, transform: on ? 'scale(1)' : 'scale(.92)' }}>
            <Ico n="power" s={40} c={on ? T.onAccent : T.sub} w={2.5}></Ico>
          </div>
          <div style={{ fontWeight: 800, fontSize: 13 }}>{on ? 'спрятан' : 'на виду'}</div>
        </div>
        <div style={{ height: 170, ...wCard, padding: 18, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
          <div style={{ fontSize: 12, fontWeight: 800, color: T.sub, textTransform: 'uppercase', letterSpacing: 1 }}>Сегодня</div>
          <div>
            <div style={{ fontFamily: T.display, fontSize: 38, fontWeight: 800, lineHeight: 1, color: T.dir === 'acid' && T.dark ? T.accent : T.text }}>1,2<span style={{ fontSize: 16 }}> ГБ</span></div>
            <div style={{ fontSize: 12.5, fontWeight: 700, color: T.sub, marginTop: 4 }}>спрятали от глаз</div>
          </div>
        </div>
      </div>
      {/* search pill */}
      <div style={{ position: 'absolute', bottom: 40, left: 24, right: 24, height: 54, borderRadius: 27, zIndex: 3, background: T.dark ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.8)', backdropFilter: 'blur(12px)', display: 'flex', alignItems: 'center', padding: '0 20px', gap: 12, color: T.sub, fontWeight: 600 }}>
        <Ico n="search" s={20} c={T.sub}></Ico>Поиск
      </div>
    </div>
  );
}

// ─── FIRST LAUNCH + Android VPN permission ───
function OnboardScreen({ T, allow }) {
  const [ask, setAsk] = uS(false);
  const dlgBg = T.dark ? '#2B2930' : '#F3EDF7', dlgTx = T.dark ? '#E6E0E9' : '#1D1B20', dlgSub = T.dark ? '#CAC4D0' : '#49454F', dlgAcc = T.dark ? '#D0BCFF' : '#6750A4';
  return (
    <>
      <TopBar T={T}></TopBar>
      <div style={{ position: 'relative', zIndex: 3, height: 330, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Hero T={T} mood={ask ? 'connecting' : 'idle'} size={300}></Hero>
      </div>
      <div style={{ position: 'relative', zIndex: 3, padding: '0 24px' }}>
        <Headline T={T} lines={['Привет,', 'невидимка']} size={{ chrome: 38, acid: 42, jelly: 50 }[T.dir]} hot></Headline>
        <p style={{ margin: '14px 0 0', fontSize: 15, lineHeight: 1.5, color: T.sub, fontWeight: 600, textWrap: 'pretty' }}>Один сервер, одна кнопка, ноль вопросов. Сейчас Android спросит разрешение — не пугайся, он всех спрашивает.</p>
      </div>
      <div style={{ position: 'absolute', left: 24, right: 24, bottom: 44, zIndex: 3, display: 'flex', flexDirection: 'column', gap: 14, alignItems: 'stretch' }}>
        <button onClick={() => setAsk(true)} style={btnStyle(T)}>Спрятаться<Ico n="chev" s={20} c={T.onAccent} w={2.5}></Ico>
          <span style={{ position: 'absolute', inset: 0, background: 'linear-gradient(90deg,transparent,rgba(255,255,255,.7),transparent)', width: '40%', animation: 'y2k-shine 2.8s ease-in-out infinite' }}></span>
        </button>
        <div style={{ textAlign: 'center', fontSize: 12.5, color: T.sub, fontWeight: 700 }}>Без логов · без регистрации · без одобрения</div>
      </div>
      <div style={{ position: 'absolute', inset: 0, zIndex: 40, pointerEvents: ask ? 'auto' : 'none' }}>
        <div onClick={() => setAsk(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.45)', opacity: ask ? 1 : 0, transition: 'opacity .25s' }}></div>
        <div style={{ position: 'absolute', left: 32, right: 32, top: '50%', background: dlgBg, borderRadius: 28, padding: 24, fontFamily: 'Roboto, system-ui, sans-serif',
          transform: `translateY(-50%) scale(${ask ? 1 : 0.85})`, opacity: ask ? 1 : 0, transition: `all .35s ${SPRING}` }}>
          <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={dlgAcc} strokeWidth="2" strokeLinecap="round"><circle cx="8" cy="15" r="4"></circle><path d="M11 12l9-9M17 6l3 3M15 8l2 2"></path></svg></div>
          <div style={{ fontSize: 24, color: dlgTx, textAlign: 'center', marginBottom: 16 }}>Запрос на подключение</div>
          <div style={{ fontSize: 14, lineHeight: '20px', color: dlgSub, letterSpacing: 0.25 }}>Приложение RKNPNH запрашивает разрешение на подключение к сети VPN, что позволит ему отслеживать сетевой трафик. Разрешайте, только если доверяете источнику.</div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 24 }}>
            <div onClick={() => setAsk(false)} style={{ padding: '10px 12px', color: dlgAcc, fontSize: 14, fontWeight: 500, cursor: 'pointer' }}>Отмена</div>
            <div onClick={allow} style={{ padding: '10px 12px', color: dlgAcc, fontSize: 14, fontWeight: 500, cursor: 'pointer' }}>ОК</div>
          </div>
        </div>
      </div>
    </>
  );
}

// ─── APP: owns connection state + navigation ───
function App({ dir, dark: darkProp, initialScreen = 'main', initialState = 'idle' }) {
  const [dark, setDark] = uS(darkProp);
  uE(() => setDark(darkProp), [darkProp]);
  const [screen, setScreen] = uS(initialScreen);
  const [conn, setConn] = uS(initialState);
  const [secs, setSecs] = uS(initialState === 'connected' ? 4327 : 0);
  uE(() => { if (conn !== 'connecting') return; const t = setTimeout(() => setConn('connected'), 2600); return () => clearTimeout(t); }, [conn]);
  uE(() => { if (conn !== 'disconnecting') return; const t = setTimeout(() => setConn('idle'), 1300); return () => clearTimeout(t); }, [conn]);
  uE(() => { if (conn !== 'connected') return; const i = setInterval(() => setSecs(s => s + 1), 1000); return () => clearInterval(i); }, [conn]);
  const toggle = () => { if (conn === 'idle') { setSecs(0); setConn('connecting'); } else if (conn === 'connected') setConn('disconnecting'); };
  const T = themeFor(dir, dark);
  const mood = screen === 'error' ? 'error' : conn;
  return (
    <Phone T={T}>
      <Backdrop T={T} mood={screen === 'widget' ? conn : mood}></Backdrop>
      <div key={screen} className="y2k-in" style={{ position: 'absolute', inset: 0 }}>
        {screen === 'main' && <MainScreen T={T} mood={conn} secs={secs} toggle={toggle} go={setScreen}></MainScreen>}
        {screen === 'split' && <SplitScreen T={T}></SplitScreen>}
        {screen === 'settings' && <SettingsScreen T={T} setDark={setDark}></SettingsScreen>}
        {screen === 'error' && <ErrorScreen T={T} retry={() => { setScreen('main'); setConn('connecting'); }}></ErrorScreen>}
        {screen === 'onboarding' && <OnboardScreen T={T} allow={() => { setScreen('main'); setSecs(0); setConn('connecting'); }}></OnboardScreen>}
        {screen === 'widget' && <WidgetScreen T={T} mood={conn} secs={secs} toggle={toggle}></WidgetScreen>}
      </div>
      {screen !== 'widget' && screen !== 'onboarding' && <NavBar T={T} screen={screen} go={setScreen}></NavBar>}
    </Phone>
  );
}

Object.assign(window, { App });
