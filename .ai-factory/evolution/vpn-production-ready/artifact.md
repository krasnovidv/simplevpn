# SimpleVPN Production Readiness Playbook

Complete guide to building, deploying, and running the SimpleVPN server and clients.

---

## Quick Start

**Deploy server (one command):**

```bash
cd /opt/simplevpn && bash deploy/deploy.sh YOUR_SERVER_IP ip
```

**Build mobile APK (one command):**

```bash
cd mobile && make install-android && cd app && flutter build apk --debug
```

**Connect desktop client (one command):**

```bash
sudo ./simplevpn-client -server YOUR_IP:443 -server-key "KEY" -username alice -password strongpass123 -skip-verify -route-all
```

See detailed sections below for full setup instructions.

---

## 1. Server Deployment (Docker)

### 1.1 Prerequisites

- Linux VPS with root access (Ubuntu 22.04+ recommended)
- Docker installed
- Ports 443 and 8443 open in cloud firewall

### 1.2 Clone and deploy

```bash
# On your VPS
cd /opt
git clone <your-repo-url> simplevpn
cd simplevpn
```

The repo includes a ready-to-use config template at `server.example.yaml` — copy and edit it to create your config:

```bash
cp server.example.yaml config/server.yaml
```

The server binary is built from `cmd/server-hardened/` (see Section 7 for building the desktop client from `cmd/client-hardened/`).

### 1.3 Deploy with the deploy script

The deploy script handles everything: generates config, creates TLS certs, sets up firewall, and starts the container.

**IP mode (self-signed certificate):**

```bash
bash deploy/deploy.sh 203.0.113.10 ip
```

**Domain mode (Let's Encrypt):**

```bash
bash deploy/deploy.sh vpn.example.com domain admin@example.com
```

The script will:
1. Create `config/` and `certs/` directories
2. Generate a self-signed EC certificate (IP mode) or obtain a Let's Encrypt cert (domain mode)
3. Generate a random `server_key` (64-char hex) and `api_token` (32-char hex)
4. Write `config/server.yaml` and save secrets to `config/.secrets`
5. Run `deploy/setup-firewall.sh` (enables ip_forward, NAT, opens ports)
6. Build and start the Docker container via `docker compose up -d --build vpn-server`

### 1.4 Retrieve secrets

After deployment, read the generated secrets:

```bash
cat config/.secrets
```

Output:

```
server_key=a1b2c3d4...   # 64-char hex — clients need this
api_token=e5f6a7b8...     # 32-char hex — for API calls
```

Save both values. The `server_key` goes into every client config. The `api_token` is your Bearer token for the management API.

### 1.5 Manual Docker build and run (without deploy script)

If you prefer manual control:

```bash
cd /opt/simplevpn

# Build the image
docker build -t simplevpn-server .

# Run the container
docker run -d \
  --name simplevpn-server \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v /opt/simplevpn/config:/etc/simplevpn \
  -v /opt/simplevpn/certs:/etc/simplevpn/certs \
  -p 443:443 \
  -p 8443:8443 \
  simplevpn-server
```

The entrypoint script (`deploy/entrypoint.sh`) runs automatically inside the container and:
- Sets up NAT: `iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE`
- Generates `config.yaml` and `users.yaml` if they do not exist
- Saves secrets to `/etc/simplevpn/.secrets`
- Starts the server binary with `-config /etc/simplevpn/server.yaml`

### 1.6 Docker Compose

Alternatively, use the included `docker-compose.yml`:

```bash
cd /opt/simplevpn

# IP mode — just start the server
docker compose up -d --build vpn-server

# Domain mode — get cert first, then start server
DOMAIN=vpn.example.com EMAIL=admin@example.com \
  docker compose --profile setup run --rm certbot
docker compose up -d --build vpn-server
```

### 1.7 Verify the server is running

```bash
docker logs simplevpn --tail 20
```

You should see:

```
[entrypoint] Secrets saved to /etc/simplevpn/.secrets (chmod 600)
Crypto initialized
TUN tun0 up: 10.0.0.1/24
TLS 1.3 configured (cert: /etc/simplevpn/certs/server.crt)
Listening on :443 (TLS, auto-detect WS/raw)
[api] Management API listening on :8443 (TLS)
```

---

## 2. Server Configuration

### 2.1 Full server.yaml reference

```yaml
# VPN listener address
listen: ":443"

# Server key — 64-char hex string. All clients must have the same key.
# Generate with: openssl rand -hex 32
server_key: "a1b2c3d4e5f6..."

# Path to users YAML file (contains username/password hashes)
users_file: "/etc/simplevpn/users.yaml"

# TLS certificate and private key
cert: "/etc/simplevpn/certs/server.crt"
key: "/etc/simplevpn/certs/server.key"

# TUN interface settings
tun_ip: "10.0.0.1/24"
tun_name: "tun0"
mtu: 1380

# Logging: debug, info, warn, error
log_level: "info"

# Transport settings (optional)
transport:
  # Additional listen addresses (multi-port support)
  extra_listens:
    - ":80"
    - ":8080"

# Management API (optional but recommended)
api:
  enabled: true
  listen: ":8443"
  bearer_token: "e5f6a7b8..."
  # Optional: separate TLS cert for the API (uses main cert if omitted)
  # cert: "/path/to/admin-cert.pem"
  # key: "/path/to/admin-key.pem"
```

### 2.2 Config field details

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `listen` | yes | `:443` | TCP listen address for VPN connections |
| `server_key` | yes | — | 64-char hex key for tunnel encryption |
| `users_file` | yes | `/etc/simplevpn/users.yaml` | Path to users file |
| `cert` | yes | `cert.pem` | TLS certificate path |
| `key` | yes | `key.pem` | TLS private key path |
| `tun_ip` | yes | `10.0.0.1/24` | Server TUN interface IP (CIDR) |
| `tun_name` | no | `tun0` | TUN interface name |
| `mtu` | no | `1380` | MTU (valid range: 500-9000) |
| `log_level` | no | `info` | Log level: debug, info, warn, error |
| `transport.extra_listens` | no | `[]` | Additional listen ports |
| `api.enabled` | no | `false` | Enable management API |
| `api.listen` | no | `:8443` | API listen address |
| `api.bearer_token` | if api enabled | — | Bearer token for API auth |

### 2.3 Server CLI flags

CLI flags override config file values:

```
-config        YAML config file path
-listen        TCP listen address (overrides config)
-server-key    Server key (overrides config)
-users-file    Users file path (overrides config)
-cert          TLS certificate (overrides config)
-key           TLS private key (overrides config)
-tun-ip        TUN IP CIDR (overrides config)
-tun-name      TUN interface name (overrides config)
-mtu           MTU (overrides config)
```

Example combining config file with flag overrides:

```bash
simplevpn-server -config server.yaml -listen :8443 -log-level debug
```

---

## 3. TLS Certificates

### 3.1 Self-signed certificate (IP mode)

For servers accessed by IP address (no domain name):

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout certs/server.key -out certs/server.crt \
  -days 3650 -nodes \
  -subj "/CN=203.0.113.10" \
  -addext "subjectAltName=IP:203.0.113.10"
```

Clients must use `skip_verify: true` (or `-skip-verify` flag) when connecting to a server with a self-signed certificate.

### 3.2 Let's Encrypt (domain mode)

For servers with a domain name:

```bash
# Using the certbot service in docker-compose.yml
DOMAIN=vpn.example.com EMAIL=admin@example.com \
  docker compose --profile setup run --rm certbot
```

Certificates are stored in the `certs` Docker volume at `/etc/letsencrypt/live/<domain>/`.

Set in `server.yaml`:

```yaml
cert: "/etc/letsencrypt/live/vpn.example.com/fullchain.pem"
key: "/etc/letsencrypt/live/vpn.example.com/privkey.pem"
```

### 3.3 Certificate renewal

Let's Encrypt certificates expire after 90 days. Add a cron job on the host:

```bash
0 3 * * * cd /opt/simplevpn && DOMAIN=vpn.example.com EMAIL=admin@example.com docker compose --profile setup run --rm certbot && docker compose restart vpn-server
```

---

## 4. User Management via API

All API requests require the `Authorization: Bearer <api_token>` header. The API runs on port 8443 with TLS. For self-signed certs, use `curl -k`.

### 4.1 Create a user

```bash
curl -k -X POST https://203.0.113.10:8443/api/users \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"strongpass123"}'
```

Response (201 Created):

```json
{"status":"created","username":"alice"}
```

Password requirements: 8-1024 characters. Username max: 255 characters.

### 4.2 List users

```bash
curl -k https://203.0.113.10:8443/api/users \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

Response:

```json
{"users":[{"username":"alice","created_at":"2026-03-09T12:00:00Z","disabled":false}]}
```

### 4.3 Change a user's password

```bash
curl -k -X PUT https://203.0.113.10:8443/api/users/alice/password \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"newstrongpass456"}'
```

### 4.4 Disable / enable a user

```bash
# Disable
curl -k -X POST https://203.0.113.10:8443/api/users/alice/disable \
  -H "Authorization: Bearer YOUR_API_TOKEN"

# Enable
curl -k -X POST https://203.0.113.10:8443/api/users/alice/enable \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

### 4.5 Delete a user

```bash
curl -k -X DELETE https://203.0.113.10:8443/api/users/alice \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

### 4.6 Server status

```bash
curl -k https://203.0.113.10:8443/api/status \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

Response:

```json
{"status":"running","version":"0.3.0","uptime_secs":3600,"client_count":1,"listen":":443"}
```

### 4.7 List connected clients

```bash
curl -k https://203.0.113.10:8443/api/clients \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

### 4.8 Disconnect a client

```bash
curl -k -X POST https://203.0.113.10:8443/api/clients/CLIENT_ID/disconnect \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

---

## 5. Mobile Client Build

### 5.1 Prerequisites

- Go 1.25+ installed
- Android SDK with NDK installed (for Android builds)
- Flutter SDK 3.2+ installed
- `gomobile` tool installed:

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

### 5.2 Build the Go AAR library (Android)

The `mobile/Makefile` contains all build targets: `android`, `install-android`, `ios`, and `clean`.

```bash
cd mobile
make android
```

This runs:

```bash
gomobile bind -target=android -androidapi 21 \
  -o build/vpnlib.aar \
  simplevpn/mobile/vpnlib
```

Output: `mobile/build/vpnlib.aar`

### 5.3 Install AAR into Flutter app

```bash
cd mobile
make install-android
```

This copies `build/vpnlib.aar` to `app/android/app/libs/vpnlib.aar`.

### 5.4 Build the Flutter APK

```bash
cd mobile/app

# Debug build (faster, larger APK, includes debug tools)
flutter build apk --debug

# Release build (optimized, smaller APK)
flutter build apk --release
```

Output: `mobile/app/build/app/outputs/flutter-apk/app-debug.apk` (or `app-release.apk`)

### 5.5 Install on device

```bash
adb install -r mobile/app/build/app/outputs/flutter-apk/app-debug.apk
```

### 5.6 Full build pipeline (one-shot)

```bash
cd mobile && make install-android && cd app && flutter build apk --debug
```

---

## 6. Mobile Client Configuration

### 6.1 QR code JSON format

The mobile app scans a QR code containing a JSON config string:

```json
{
  "server": "203.0.113.10:443",
  "server_key": "a1b2c3d4e5f6...",
  "username": "alice",
  "password": "strongpass123",
  "sni": "example.com",
  "skip_verify": true,
  "transport": "ws",
  "fingerprint": "chrome"
}
```

### 6.2 Config field details

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `server` | yes | — | Server address as `host:port` |
| `server_key` | yes | — | Server key (same as server's `server_key`) |
| `username` | yes | — | Username created via API |
| `password` | yes | — | User's password |
| `sni` | no | derived from `server` host | TLS SNI override (for domain fronting) |
| `skip_verify` | no | `false` | Skip TLS cert verification (required for self-signed certs) |
| `transport` | no | `ws` | Transport type: `ws` (WebSocket) or `tls` (raw TLS) |
| `fingerprint` | no | `chrome` (Android), `safari` (iOS) | TLS fingerprint: `chrome`, `firefox`, `safari`, `none` |

### 6.3 Minimal QR config (self-signed IP server)

```json
{"server":"203.0.113.10:443","server_key":"a1b2c3d4...","username":"alice","password":"strongpass123","skip_verify":true}
```

### 6.4 Minimal QR config (domain with valid cert)

```json
{"server":"vpn.example.com:443","server_key":"a1b2c3d4...","username":"alice","password":"strongpass123"}
```

### 6.5 Generating a QR code

Use any QR generator. From the command line with `qrencode`:

```bash
echo -n '{"server":"203.0.113.10:443","server_key":"YOUR_KEY","username":"alice","password":"strongpass123","skip_verify":true}' | qrencode -o vpn-config.png
```

---

## 7. Desktop Client Usage

The desktop client binary is `cmd/client-hardened`. Build it with:

```bash
# Cross-compile for Linux
GOOS=linux GOARCH=amd64 go build -o simplevpn-client ./cmd/client-hardened/

# Native build
go build -o simplevpn-client ./cmd/client-hardened/
```

### 7.1 CLI flags

```
Required:
  -server        Server address host:port
  -server-key    Server key for tunnel encryption
  -username       Username for authentication
  -password       Password for authentication

Optional:
  -sni           SNI for TLS handshake (default: derived from server host)
  -tun-ip        Client TUN IP CIDR (default: 10.0.0.2/24)
  -tun-name      TUN interface name (default: tun0)
  -mtu           TUN MTU (default: 1380)
  -transport     Transport type: tls or ws (default: tls)
  -fingerprint   TLS fingerprint: none, chrome, firefox, safari (default: none)
  -route-all     Route all traffic through VPN (default: false)
  -jitter        Max timing jitter in ms (default: 5)
  -skip-verify   Skip TLS cert verification (default: false)
```

### 7.2 Basic connection (raw TLS)

```bash
sudo ./simplevpn-client \
  -server 203.0.113.10:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username "alice" \
  -password "strongpass123" \
  -skip-verify
```

### 7.3 Anti-DPI mode (WebSocket + Chrome fingerprint)

```bash
sudo ./simplevpn-client \
  -server 203.0.113.10:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username "alice" \
  -password "strongpass123" \
  -transport ws \
  -fingerprint chrome \
  -skip-verify
```

### 7.4 Route all traffic through VPN

```bash
sudo ./simplevpn-client \
  -server 203.0.113.10:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username "alice" \
  -password "strongpass123" \
  -route-all \
  -skip-verify
```

When `-route-all` is set, the client:
1. Adds a host route for the server IP via the default gateway
2. Routes `0.0.0.0/1` and `128.0.0.0/1` through the TUN interface

### 7.5 Domain mode (valid TLS cert, no skip-verify needed)

```bash
sudo ./simplevpn-client \
  -server vpn.example.com:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username "alice" \
  -password "strongpass123" \
  -transport ws \
  -fingerprint chrome \
  -route-all
```

---

## 8. Troubleshooting

### TUN device errors

**`TUNSETIFF: Operation not permitted`** — container lacks NET_ADMIN capability:

```bash
docker run --cap-add NET_ADMIN --device /dev/net/tun ...
```

**`/dev/net/tun: no such file or directory`** — TUN module not loaded on host:

```bash
sudo modprobe tun
```

### NAT not working (clients can't reach internet)

Verify NAT rule is active inside the container:

```bash
docker exec simplevpn-server iptables -t nat -L POSTROUTING
```

Should show `MASQUERADE  all  --  10.0.0.0/24  anywhere`. If missing, restart the container — `entrypoint.sh` sets it up on start.

Also verify IP forwarding on the host:

```bash
sysctl net.ipv4.ip_forward
# Should be 1. If not:
sudo sysctl -w net.ipv4.ip_forward=1
```

### TLS certificate issues

**`x509: certificate signed by unknown authority`** — client connecting to self-signed cert without skip-verify. Use `-skip-verify` flag or `"skip_verify": true` in QR config.

**`certificate is valid for X, not Y`** — cert SAN doesn't match server address. Regenerate cert with correct IP/domain in the SAN field.

### gomobile build failures

**`gomobile: command not found`** — install gomobile:

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

**`NDK not found`** — set `ANDROID_NDK_HOME`:

```bash
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/<version>
```

### Flutter build errors

**`Could not find vpnlib.aar`** — AAR not built or not copied. Run:

```bash
cd mobile && make install-android
```

**`Gradle build failed`** — check `android/local.properties` has correct SDK path. Run `flutter doctor` to diagnose.

---

## 9. Quick Start Checklist

### Server side

1. Clone repo to VPS at `/opt/simplevpn`
2. Run `bash deploy/deploy.sh YOUR_IP ip`
3. Read secrets: `cat config/.secrets`
4. Create a user: `curl -k -X POST https://YOUR_IP:8443/api/users -H "Authorization: Bearer API_TOKEN" -d '{"username":"alice","password":"strongpass123"}'`
5. Verify: `docker logs simplevpn --tail 5`

### Client side

1. Build: `cd mobile && make install-android && cd app && flutter build apk --debug`
2. Install: `adb install -r mobile/app/build/app/outputs/flutter-apk/app-debug.apk`
3. Generate QR: `echo -n '{"server":"YOUR_IP:443","server_key":"KEY","username":"alice","password":"strongpass123","skip_verify":true}' | qrencode -o config.png`
4. Open app, scan QR, connect

### Desktop

```bash
sudo ./simplevpn-client -server YOUR_IP:443 -server-key "KEY" -username alice -password strongpass123 -skip-verify -route-all
```
