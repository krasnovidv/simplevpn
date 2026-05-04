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
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SimpleVPN — Connect</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:#0f172a;color:#e2e8f0;min-height:100vh;display:flex;
  align-items:center;justify-content:center;padding:24px}
.card{max-width:400px;width:100%;background:#1e293b;border-radius:16px;
  padding:32px;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.4)}
.shield{font-size:64px;margin-bottom:16px}
h1{font-size:24px;margin-bottom:8px;color:#f8fafc}
.sub{color:#94a3b8;font-size:14px;margin-bottom:24px}
.status{padding:12px;border-radius:8px;margin-bottom:20px;font-size:14px}
.status.opening{background:#1e3a5f;color:#60a5fa}
.status.fallback{background:#1c1917;color:#fbbf24}
.btn{display:inline-block;padding:14px 28px;border-radius:10px;
  font-size:16px;font-weight:600;text-decoration:none;cursor:pointer;
  border:none;transition:background .2s}
.btn-primary{background:#3b82f6;color:#fff}
.btn-primary:hover{background:#2563eb}
.info{margin-top:20px;text-align:left;background:#0f172a;border-radius:8px;
  padding:16px;font-size:13px;line-height:1.6}
.info dt{color:#94a3b8;font-weight:500}
.info dd{color:#e2e8f0;margin-bottom:8px;word-break:break-all}
#fallback{display:none}
</style>
</head>
<body>
<div class="card">
  <div class="shield">&#128737;</div>
  <h1>SimpleVPN</h1>
  <p class="sub">VPN configuration link</p>

  <div id="opening" class="status opening">Opening app&hellip;</div>

  <div id="fallback">
    <div class="status fallback">App not installed or couldn&rsquo;t open automatically</div>
    <a id="download-btn" class="btn btn-primary" href="/download/simplevpn.apk">
      Download for Android
    </a>
    <div id="config-info" class="info"></div>
  </div>
</div>
<script>
(function(){
  var frag = window.location.hash.substring(1);
  if (!frag) {
    document.getElementById('opening').textContent = 'No configuration in link';
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
      if (json.server) html += '<dt>Server</dt><dd>' + esc(json.server) + '</dd>';
      if (json.username) html += '<dt>Username</dt><dd>' + esc(json.username) + '</dd>';
      if (json.sni) html += '<dt>SNI</dt><dd>' + esc(json.sni) + '</dd>';
      html += '</dl>';
      document.getElementById('config-info').innerHTML = html;
    } catch(e) {
      document.getElementById('config-info').innerHTML = '<p>Could not decode configuration</p>';
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
