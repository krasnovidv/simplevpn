[← Мобильное приложение](mobile-build.md) · [Назад к README](../README.md)

# Продакшн-гайд

Полный цикл: деплой сервера, настройка клиентов, траблшутинг.

---

## Быстрый старт

**Деплой сервера (одна команда):**

```bash
cd /opt/simplevpn && bash deploy/deploy.sh YOUR_SERVER_IP ip
```

**Сборка мобильного APK (одна команда):**

```bash
cd mobile && make install-android && cd app && flutter build apk --debug
```

**Подключение десктоп-клиента (одна команда):**

```bash
sudo ./simplevpn-client -server YOUR_IP:443 -server-key "KEY" -username alice -password strongpass123 -skip-verify -route-all
```

---

## 1. Деплой сервера (Docker)

### 1.1 Требования

- Linux VPS с root-доступом (Ubuntu 22.04+)
- Docker
- Открытые порты 443 и 8443 в облачном файрволе

### 1.2 Клонирование и деплой

```bash
cd /opt
git clone <repo-url> simplevpn
cd simplevpn
```

### 1.3 Запуск деплой-скрипта

**IP-режим (самоподписанный сертификат):**

```bash
bash deploy/deploy.sh 203.0.113.10 ip
```

**Domain-режим (Let's Encrypt):**

```bash
bash deploy/deploy.sh vpn.example.com domain admin@example.com
```

Скрипт автоматически:
1. Создаёт директории `config/` и `certs/`
2. Генерирует TLS-сертификат (самоподписанный EC или Let's Encrypt)
3. Генерирует `server_key` (64-char hex) и `api_token` (32-char hex)
4. Записывает `config/server.yaml` и сохраняет секреты в `config/.secrets`
5. Запускает `deploy/setup-firewall.sh` (ip_forward, NAT, порты)
6. Собирает и запускает Docker-контейнер

### 1.4 Получение секретов

```bash
cat config/.secrets
```

```
server_key=a1b2c3d4...   # 64-char hex — нужен всем клиентам
api_token=e5f6a7b8...     # 32-char hex — для API-запросов
```

### 1.5 Ручная сборка Docker (без скрипта)

```bash
cd /opt/simplevpn

docker build -t simplevpn-server .

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

Entrypoint-скрипт (`deploy/entrypoint.sh`) внутри контейнера:
- Настраивает NAT: `iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE`
- Генерирует конфиг и пользователей, если не существуют
- Запускает сервер с `-config /etc/simplevpn/server.yaml`

### 1.6 Docker Compose

```bash
cd /opt/simplevpn

# IP-режим
docker compose up -d --build vpn-server

# Domain-режим — сначала сертификат, потом сервер
DOMAIN=vpn.example.com EMAIL=admin@example.com \
  docker compose --profile setup run --rm certbot
docker compose up -d --build vpn-server
```

### 1.7 Проверка запуска

```bash
docker logs simplevpn-server --tail 20
```

Ожидаемый вывод:

```
[entrypoint] Secrets saved to /etc/simplevpn/.secrets (chmod 600)
Crypto initialized
TUN tun0 up: 10.0.0.1/24
TLS 1.3 configured (cert: /etc/simplevpn/certs/server.crt)
Listening on :443 (TLS, auto-detect WS/raw)
[api] Management API listening on :8443 (TLS)
```

---

## 2. TLS-сертификаты

### Самоподписанный (IP-режим)

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout certs/server.key -out certs/server.crt \
  -days 3650 -nodes \
  -subj "/CN=203.0.113.10" \
  -addext "subjectAltName=IP:203.0.113.10"
```

Клиенты должны использовать `skip_verify: true`.

### Let's Encrypt (domain-режим)

```bash
DOMAIN=vpn.example.com EMAIL=admin@example.com \
  docker compose --profile setup run --rm certbot
```

Обновление сертификата (cron):

```bash
0 3 * * * cd /opt/simplevpn && DOMAIN=vpn.example.com EMAIL=admin@example.com docker compose --profile setup run --rm certbot && docker compose restart vpn-server
```

---

## 3. Десктоп-клиент

Сборка:

```bash
# Кросс-компиляция для Linux
GOOS=linux GOARCH=amd64 go build -o simplevpn-client ./cmd/client-hardened/

# Нативная сборка
go build -o simplevpn-client ./cmd/client-hardened/
```

### Подключение — Raw TLS

```bash
sudo ./simplevpn-client \
  -server 203.0.113.10:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -skip-verify
```

### Подключение — Anti-DPI (WebSocket + Chrome)

```bash
sudo ./simplevpn-client \
  -server 203.0.113.10:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -transport ws \
  -fingerprint chrome \
  -skip-verify
```

### Весь трафик через VPN

```bash
sudo ./simplevpn-client \
  -server 203.0.113.10:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -route-all \
  -skip-verify
```

---

## 4. Траблшутинг

### Ошибки TUN

**`TUNSETIFF: Operation not permitted`** — контейнер без NET_ADMIN:

```bash
docker run --cap-add NET_ADMIN --device /dev/net/tun ...
```

**`/dev/net/tun: no such file or directory`** — модуль TUN не загружен:

```bash
sudo modprobe tun
```

### NAT не работает (клиенты без интернета)

Проверьте NAT-правило внутри контейнера:

```bash
docker exec simplevpn-server iptables -t nat -L POSTROUTING
```

Должно быть `MASQUERADE  all  --  10.0.0.0/24  anywhere`. Если нет — перезапустите контейнер (entrypoint.sh настраивает NAT при старте).

Проверьте IP forwarding на хосте:

```bash
sysctl net.ipv4.ip_forward
# Должно быть 1. Если нет:
sudo sysctl -w net.ipv4.ip_forward=1
```

### Ошибки TLS

**`x509: certificate signed by unknown authority`** — самоподписанный сертификат без skip-verify. Используйте `-skip-verify` или `"skip_verify": true` в QR.

**`certificate is valid for X, not Y`** — SAN сертификата не совпадает с адресом. Пересоздайте сертификат с правильным IP/доменом.

### Ошибки gomobile

**`gomobile: command not found`**:

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

**`NDK not found`**:

```bash
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/<version>
```

### Ошибки Flutter

**`Could not find vpnlib.aar`** — AAR не собран:

```bash
cd mobile && make install-android
```

**`Gradle build failed`** — проверьте `android/local.properties`. Запустите `flutter doctor`.

---

## 5. Чеклист

### Серверная часть

1. Клонировать репо на VPS в `/opt/simplevpn`
2. Запустить `bash deploy/deploy.sh YOUR_IP ip`
3. Прочитать секреты: `cat config/.secrets`
4. Создать пользователя: `curl -k -X POST https://YOUR_IP:8443/api/users -H "Authorization: Bearer API_TOKEN" -d '{"username":"alice","password":"strongpass123"}'`
5. Проверить: `docker logs simplevpn-server --tail 5`

### Клиентская часть

1. Собрать: `cd mobile && make install-android && cd app && flutter build apk --debug`
2. Установить: `adb install -r mobile/app/build/app/outputs/flutter-apk/app-debug.apk`
3. Сгенерировать QR: `echo -n '{"server":"YOUR_IP:443","server_key":"KEY","username":"alice","password":"strongpass123","skip_verify":true}' | qrencode -o config.png`
4. Открыть приложение, сканировать QR, подключиться

### Десктоп

```bash
sudo ./simplevpn-client -server YOUR_IP:443 -server-key "KEY" -username alice -password strongpass123 -skip-verify -route-all
```

## See Also

- [Начало работы](getting-started.md) — базовая установка
- [Конфигурация](configuration.md) — все параметры и флаги
- [API-справочник](api.md) — управление пользователями
