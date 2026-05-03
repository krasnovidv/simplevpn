# SimpleVPN Hardened

> DPI-resistant VPN на Go: 8 уровней защиты поверх TLS 1.3

VPN-туннель, неотличимый от обычного HTTPS для систем глубокой инспекции пакетов (DPI/ТСПУ/GFW). Сканеры и зонды видят обычный веб-сайт на nginx, а не VPN-сервер.

## Что видит DPI

| Что проверяет DPI         | Что видит                    | Результат   |
|---------------------------|------------------------------|-------------|
| Порт назначения           | 443                          | HTTPS       |
| TLS handshake             | Валидный TLS 1.3             | Легитимно   |
| HTTP-запрос к серверу     | HTML-страница (nginx decoy)  | Веб-сайт    |
| Entropy payload           | Маскирована ChaCha20         | Не детект.  |
| Размеры пакетов           | Случайные (padding)          | Не детект.  |
| Timing паттерн            | Случайный jitter             | Не детект.  |
| Активное зондирование     | Получает HTML, не VPN-ответ  | Не детект.  |

## Быстрый старт

### Docker-деплой на VPS (рекомендуется)

```bash
# Скопировать файлы на сервер
scp -r deploy/ Dockerfile docker-compose.yml server.example.yaml root@YOUR_SERVER:/opt/simplevpn/

# Запустить деплой (IP-режим — самоподписанный сертификат)
ssh root@YOUR_SERVER "cd /opt/simplevpn && bash deploy/deploy.sh YOUR_SERVER_IP"

# Или с доменом (Let's Encrypt)
ssh root@YOUR_SERVER "cd /opt/simplevpn && bash deploy/deploy.sh yourdomain.com domain your@email.com"
```

Скрипт сгенерирует `server_key` и API-токен — **сохраните их**.

После деплоя создайте пользователя через API:

```bash
curl -k -X POST https://YOUR_SERVER:8443/api/users \
  -H "Authorization: Bearer API_TOKEN" \
  -d '{"username":"alice","password":"strongpass123"}'
```

## Ключевые возможности

- **TLS 1.3 на порту 443** — трафик неотличим от HTTPS
- **Active Probe Resistance** — зонды получают HTML-страницу nginx
- **AES-256-GCM + ChaCha20 masking** — шифрование и маскировка энтропии
- **Random padding + timing jitter** — скрывает размеры и паттерны пакетов
- **Username/Password аутентификация** — управление пользователями через REST API
- **Multi-user с IP-пулом** — несколько клиентов одновременно, каждый получает свой IP из `client_subnet`
- **Admin UI в мобильном приложении** — управление пользователями, просмотр клиентов, генерация QR
- **Sliding window replay protection** — защита от повторного воспроизведения

## Конфигурация сервера (Phase 2)

### `client_subnet`

Новый параметр YAML `client_subnet` задаёт пул IP-адресов для клиентов:

```yaml
client_subnet: "10.0.0.0/24"   # по умолчанию
tun_ip: "10.0.0.1/24"          # IP самого сервера (исключается из пула)
```

Каждый подключившийся клиент получает уникальный IP из этой подсети. При отключении IP возвращается в пул.

### Breaking change: протокол аутентификации

**Версия 1.1.x несовместима со старыми клиентами (1.0.x).**

Формат ответа сервера на успешную аутентификацию изменён:

| Версия | Ответ сервера                     |
|--------|-----------------------------------|
| 1.0.x  | `OK` (2 байта, без разделителя)   |
| 1.1.x  | `OK 10.0.0.2/24\n` (с IP-префиксом и `\n`) |

Клиент использует полученный IP для настройки TUN-интерфейса Android VpnService вместо захардкоженного `10.0.0.2/24`.

### Admin UI

В мобильном приложении (v1.1.0+) доступен Admin-интерфейс.

**Настройка:** Settings → Admin API → задайте URL (`https://server:8443`), bearer-токен и при необходимости включите "Skip TLS Verification".

После сохранения на главном экране появится кнопка ⚙ (admin_panel_settings).

**Возможности:**
- Вкладка **Users**: список пользователей, создание, смена пароля, включение/отключение, удаление
- Вкладка **Clients**: список подключённых клиентов с назначенными IP, принудительное отключение
- Вкладка **Server**: статус сервера (версия, uptime, количество клиентов), генератор QR-кодов для новых пользователей

**Генератор QR** (Server → Generate Client QR): заполните данные нового пользователя — приложение сформирует QR-код с полным конфигом (включая пароль). Сканируйте вторым телефоном в разделе Settings → Scan QR.

## Phase 4 — Resilience & UX (v1.3.0)

- **Auto-reconnect** — exponential backoff (1→2→4→…→60 s cap), configurable max retries (0 = unlimited). Auth-fail short-circuits immediately (no wasted retries).
- **Kill switch** — blocks all traffic when VPN disconnects unexpectedly. Android reuses existing TUN fd during retries. iOS uses `includeAllNetworks` (requires iOS 14.2+; graceful fallback with UI warning on older versions).
- **Split tunneling** — Android: per-app allowlist/blocklist. iOS: per-route CIDR allowlist/excludelist. Empty allowlist falls back to full tunnel to prevent traffic black-hole.
- **Traffic stats** — atomic byte counters in Go, polled at 1 Hz from Dart. Home screen shows cumulative transfer + 60 s throughput sparkline (down/up series).
- **Structured status protocol** — native → Dart via typed Map (replaces brittle string parsing).

## iOS Client (Phase 3)

**Prerequisites:** macOS with Xcode 15+, Apple Developer account, gomobile.

```bash
# Build xcframework (on macOS)
cd mobile && make install-ios

# Generate Xcode project
cd mobile/app && flutter build ios --no-codesign
```

Open `mobile/app/ios/Runner.xcworkspace` in Xcode. See [IOS_SETUP.md](IOS_SETUP.md) for the full step-by-step guide (entitlements, extension target, provisioning profiles).

**Minimum iOS version:** 15.0

**Architecture:** `NEPacketTunnelProvider` bridges iOS `packetFlow` ↔ Go `RunTunnel` via a Unix DGRAM socketpair. Go code is unchanged — the socketpair fd is indistinguishable from a TUN fd.

## Тесты

```bash
make test          # юнит-тесты
make bench         # бенчмарки
```

---

## Документация

| Раздел | Описание |
|--------|----------|
| [Начало работы](docs/getting-started.md) | Установка, настройка, запуск |
| [Архитектура](docs/architecture.md) | Структура проекта, протокол, поток данных |
| [Конфигурация](docs/configuration.md) | YAML-конфигурация, флаги сервера и клиента |
| [Безопасность](docs/security.md) | Криптография, протокол аутентификации, модель угроз |
| [API-справочник](docs/api.md) | REST API управления пользователями и сервером |
| [Мобильное приложение](docs/mobile-build.md) | Сборка Android-клиента, gomobile, Flutter |
| [Продакшн-гайд](docs/production-playbook.md) | Полный цикл: деплой, настройка, клиенты, траблшутинг |
