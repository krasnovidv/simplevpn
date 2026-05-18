package api

import (
	"log"
	"net/http"
)

func (s *Server) handleJoin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	log.Printf("[api] GET /join from %s", r.RemoteAddr)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(joinPageHTML))
}

const joinPageHTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>RKNPNH — Подключение</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:#120a1f;color:#e2e8f0;min-height:100vh;display:flex;
  align-items:center;justify-content:center;padding:24px}
.card{max-width:420px;width:100%;background:#1a1028;border-radius:16px;
  padding:32px;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.5);
  border:1px solid #2a1f3a}
.logo{font-size:28px;font-weight:900;letter-spacing:3px;margin-bottom:4px;
  color:#ff2bd6}
.sub{color:#5a4a7a;font-size:13px;margin-bottom:24px;letter-spacing:1px}
.status{padding:12px;border-radius:8px;margin-bottom:20px;font-size:14px}
.status.opening{background:rgba(0,240,255,.08);color:#00f0ff}
.status.fallback{background:rgba(255,43,214,.08);color:#ff2bd6}
.btn{display:inline-block;padding:14px 28px;border-radius:10px;
  font-size:16px;font-weight:600;text-decoration:none;cursor:pointer;
  border:none;transition:background .2s;margin-bottom:12px}
.btn-primary{background:#ff2bd6;color:#fff}
.btn-primary:hover{background:#ff5ce0}
.steps{margin-top:20px;text-align:left;background:#0a0612;border-radius:8px;
  padding:16px;font-size:13px;line-height:1.8;border:1px solid #2a1f3a}
.steps ol{padding-left:20px;color:#94a3b8}
.steps li{margin-bottom:4px}
.steps strong{color:#f5f3ff}
.info{margin-top:16px;text-align:left;background:#0a0612;border-radius:8px;
  padding:16px;font-size:13px;line-height:1.6;border:1px solid #2a1f3a}
.info dt{color:#5a4a7a;font-weight:500}
.info dd{color:#f5f3ff;margin-bottom:8px;word-break:break-all}
#fallback{display:none}
</style>
</head>
<body>
<div class="card">
  <div class="logo">RKNPNH</div>
  <p class="sub">VPN / КОНФИГУРАЦИЯ</p>

  <div id="opening" class="status opening">Открываю приложение&hellip;</div>

  <div id="fallback">
    <div class="status fallback">Приложение не установлено</div>
    <a id="download-btn" class="btn btn-primary" href="/download/simplevpn.apk">
      ⬇ Скачать APK
    </a>
    <div class="steps">
      <ol>
        <li>Скачай и установи APK</li>
        <li>Открой эту ссылку снова</li>
        <li>Конфиг импортируется автоматически</li>
      </ol>
    </div>
    <div id="config-info" class="info"></div>
  </div>
</div>
<script>
(function(){
  var frag = window.location.hash.substring(1);
  if (!frag) {
    document.getElementById('opening').textContent = 'Нет конфигурации в ссылке';
    return;
  }

  // Try opening the app via deep link
  var deepLink = 'simplevpn://connect/' + frag;
  window.location = deepLink;

  // After 2s, show fallback
  setTimeout(function(){
    document.getElementById('opening').style.display = 'none';
    document.getElementById('fallback').style.display = 'block';

    // Decode and show config summary (mask sensitive fields)
    try {
      var b64 = frag.replace(/-/g,'+').replace(/_/g,'/');
      while (b64.length % 4) b64 += '=';
      var json = JSON.parse(atob(b64));
      var html = '<dl>';
      if (json.server) html += '<dt>Сервер</dt><dd>' + esc(json.server) + '</dd>';
      if (json.username) html += '<dt>Логин</dt><dd>' + esc(json.username) + '</dd>';
      if (json.sni) html += '<dt>SNI</dt><dd>' + esc(json.sni) + '</dd>';
      html += '</dl>';
      document.getElementById('config-info').innerHTML = html;
    } catch(e) {
      document.getElementById('config-info').innerHTML = '<p>Не удалось декодировать конфигурацию</p>';
    }
  }, 2000);

  function esc(s){
    var d = document.createElement('div');
    d.appendChild(document.createTextNode(s));
    return d.innerHTML;
  }
})();
</script>
</body>
</html>`
