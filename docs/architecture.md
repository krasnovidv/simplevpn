[← Начало работы](getting-started.md) · [Назад к README](../README.md) · [Конфигурация →](configuration.md)

# Архитектура

## Структура проекта

```
simplevpn/
├── cmd/
│   ├── server-hardened/        # TLS-сервер с DPI-resistance
│   │   └── main.go             # Точка входа, accept loop, VPN-логика
│   └── client-hardened/        # TLS-клиент с DPI-resistance
│       └── main.go             # Подключение, аутентификация, туннель
├── pkg/
│   ├── tunnel/                 # Общий VPN-протокол (TUN, framing, ключи, крипто)
│   ├── transport/              # Абстракция транспортного уровня (pluggable transports)
│   │   ├── transport.go        # Интерфейсы Dialer/Listener, реестр, auto-detect
│   │   ├── rawtls/             # Raw TLS 1.3 транспорт (backward compatible)
│   │   ├── ws/                 # WebSocket over TLS (anti-DPI, RFC 6455)
│   │   └── utlsdial/           # uTLS fingerprint mimicry (Chrome/Firefox/Safari)
│   ├── crypto/                 # AES-256-GCM шифрование
│   ├── obfs/                   # ChaCha20 entropy masking + padding
│   ├── replay/                 # Sliding window replay protection
│   ├── tlsdecoy/               # HMAC-аутентификация + HTML-decoy
│   ├── config/                 # YAML-конфигурация сервера
│   └── api/                    # REST API управления + встроенный web UI
├── mobile/
│   ├── vpnlib/                 # Go-библиотека для мобильных (gomobile)
│   │   ├── vpnlib.go           # Connect/Disconnect/Status API
│   │   └── vpnlib_test.go
│   └── app/                    # Flutter-приложение (Android + iOS)
│       ├── lib/
│       │   ├── services/       # VPN-сервис, хранение конфигурации, логи
│       │   ├── screens/        # UI: главный экран, настройки, логи, QR
│       │   └── models/         # Модель VPN-конфигурации
│       └── android/
│           └── app/src/main/kotlin/
│               ├── SimpleVpnService.kt  # Android VpnService
│               ├── VpnPlugin.kt         # Flutter MethodChannel
│               └── MainActivity.kt
├── deploy/
│   ├── deploy.sh               # Деплой на VPS (IP/domain режимы)
│   ├── setup-firewall.sh       # NAT, ip_forward
│   └── simplevpn.service       # systemd unit
├── Dockerfile
├── docker-compose.yml
├── Makefile
├── server.example.yaml
└── go.mod
```

## Компоненты

### Серверная часть (Go)

Серверный бинарник (`cmd/server-hardened/`) — TLS-сервер на порту 443:
- Принимает TCP-подключения, устанавливает TLS 1.3
- Аутентифицирует клиентов по username/password (bcrypt)
- Создаёт TUN-интерфейс и маршрутизирует IP-пакеты
- Предоставляет REST API для управления пользователями (порт 8443)

### Мобильное приложение (Flutter + Go)

Двухслойная архитектура:

```
┌────────────────────────────────────────┐
│  Flutter (Dart)                        │
│  ├── HomeScreen — UI, кнопка Connect   │
│  ├── VpnService — состояние, поллинг   │
│  ├── ConfigStorage — SharedPreferences │
│  └── EventLog — журнал событий         │
├────────────────────────────────────────┤
│  MethodChannel "com.simplevpn/vpn"     │
│  connect / disconnect / status / logs  │
├────────────────────────────────────────┤
│  Kotlin (Android)                      │
│  ├── VpnPlugin — обработка каналов     │
│  └── SimpleVpnService — VpnService OS  │
│      ├── TUN-интерфейс                 │
│      ├── Foreground notification       │
│      └── Socket protection             │
├────────────────────────────────────────┤
│  Go (gomobile AAR)                     │
│  └── vpnlib — transport, auth, tunnel │
│      ├── WebSocket + uTLS (default)   │
│      └── Raw TLS (legacy fallback)    │
└────────────────────────────────────────┘
```

Flutter общается с Kotlin через `MethodChannel`, Kotlin управляет Android `VpnService` и вызывает Go-библиотеку `vpnlib` через gomobile binding.

### Деплой

Автоматизированный деплой через Docker:
- `deploy.sh` — генерирует PSK, сертификат, firewall, запускает контейнер
- IP-режим — самоподписанный сертификат для быстрого старта
- Domain-режим — Let's Encrypt для продакшна

## Транспортный уровень (Anti-DPI)

Транспортный уровень находится между TCP и VPN-протоколом. Он обеспечивает множество
способов доставки VPN-трафика, делая его неотличимым от обычного веб-трафика.

### WebSocket транспорт (по умолчанию для мобильных)

```
Мобильное приложение                           Сервер
    |                                           |
    |  [uTLS ClientHello: Chrome fingerprint]   |
    |  ------TCP:443 TLS 1.3 Handshake-------> |
    |                                           |
    |  GET /ws HTTP/1.1                         |
    |  Upgrade: websocket                       |
    |  ---------------------------------------->|
    |                                           |  (auto-detect: WS upgrade)
    |  <--- 101 Switching Protocols ----------- |
    |                                           |
    |  [WS Binary Frame: auth token (56B)]      |
    |  ---------------------------------------->|  (verify HMAC)
    |  <--- [WS Binary Frame: "OK"] ----------- |
    |                                           |
    |  [WS Binary: obfs(encrypt(IP packet))]    |
    |  <======================================> |  (tunnel active)
```

**Преимущества:**
- HTTP Upgrade выглядит как обычное WebSocket-приложение (чат, игра)
- uTLS мимикрирует JA3/JA4 отпечаток настоящего браузера
- Совместим с CDN и reverse-proxy
- Один порт для всех транспортов (auto-detect на сервере)

### Raw TLS транспорт (legacy, backward compatible)

Прямое TLS 1.3 соединение без WebSocket — оригинальный протокол.
Старые клиенты продолжают работать без изменений.

### uTLS Fingerprint Mimicry

Заменяет Go TLS на uTLS (refraction-networking/utls) на клиенте:
- **Chrome** — по умолчанию на Android
- **Safari** — по умолчанию на iOS
- **Firefox** — альтернативный профиль

JA3 отпечаток полностью соответствует реальному браузеру.

### Multi-port Listening

Сервер может слушать на нескольких портах одновременно (443, 80, 8080).
Если оператор блокирует один порт — другой продолжает работать.

## Уровни защиты

```
┌─────────────────────────────────────────────────────┐
│  WebSocket + uTLS на порту 443                       │
│  → DPI видит обычный WebSocket (чат/игра)            │
├─────────────────────────────────────────────────────┤
│  TLS 1.3 на порту 443                                │
│  → DPI видит обычный HTTPS, не VPN                   │
├─────────────────────────────────────────────────────┤
│  Active Probe Resistance                              │
│  → Сканеры получают HTML-страницу (nginx decoy)      │
├─────────────────────────────────────────────────────┤
│  Username/Password аутентификация (bcrypt)             │
│  → Только зарегистрированные пользователи             │
├─────────────────────────────────────────────────────┤
│  AES-256-GCM шифрование                              │
│  → Содержимое туннеля криптостойко                   │
├─────────────────────────────────────────────────────┤
│  ChaCha20 entropy masking                             │
│  → Разрушает статистические паттерны                 │
├─────────────────────────────────────────────────────┤
│  Random padding + Timing jitter                       │
│  → Скрывает размеры и временные паттерны             │
├─────────────────────────────────────────────────────┤
│  Sliding window replay protection                     │
│  → Защита от повторного воспроизведения пакетов      │
└─────────────────────────────────────────────────────┘
```

## Протокол подключения

1. Клиент устанавливает TCP-соединение на порт 443
2. TLS 1.3 handshake (SNI = домен сервера, ALPN = h2/http/1.1)
3. Клиент отправляет учётные данные (username + password)
4. Сервер проверяет credentials через bcrypt
   - Если верно → ответ "OK", туннель активен
   - Если неверно → HTML-страница (decoy), соединение закрыто

## Формат фрейма поверх TLS

TLS — потоковый протокол, поэтому нужен framing:

```
[length uint32 big-endian] [obfuscated(encrypted(IP-packet))]
```

### Формат обфусцированного пакета

```
┌──────────┬──────────┬──────────────────────────────┬─────────────┐
│ Seed(4B) │PadLen(1B)│ XOR(AES-payload, PRG(seed))  │ Random Pad  │
└──────────┴──────────┴──────────────────────────────┴─────────────┘
```

- **Seed** — случайный, уникальный для каждого пакета
- **PadLen** — длина случайного padding (0-255 байт)
- **XOR-поток** — ChaCha20 с ключом, производным от seed + obfs key
- **Random Pad** — случайные байты для рандомизации размера

## Поток данных (клиент → сервер)

```
IP-пакет из TUN
  → AES-256-GCM Encrypt (nonce || ciphertext || tag)
    → ChaCha20 XOR masking + random padding
      → Framing (length prefix)
        → TLS 1.3 запись
          → TCP на порт 443
```

## Derive ключей

Server key порождает три независимых ключа через SHA-256:

```
masterKey   = SHA256(server_key)
encKey      = SHA256(masterKey || "encryption")     → AES-256-GCM
obfsMaster  = SHA256(masterKey || "obfuscation")    → DeriveObfsKey() → ChaCha20
authKey     = masterKey                              → HMAC-SHA256
```

## Пакеты (pkg/)

| Пакет | Назначение |
|-------|------------|
| `pkg/tunnel` | TUN-интерфейс, framing, derive ключей, общий туннельный протокол |
| `pkg/transport` | Абстракция транспорта: интерфейсы, реестр, auto-detect WS/TLS |
| `pkg/transport/rawtls` | Raw TLS 1.3 транспорт (legacy) |
| `pkg/transport/ws` | WebSocket транспорт (anti-DPI, RFC 6455 binary frames) |
| `pkg/transport/utlsdial` | uTLS диалер с мимикрией браузера (Chrome/Firefox/Safari) |
| `pkg/crypto` | AES-256-GCM: Encrypt/Decrypt с random nonce (12 байт) |
| `pkg/obfs` | ChaCha20 XOR masking, random padding, timing jitter, entropy scoring |
| `pkg/replay` | Sliding window (1024 слота) для защиты от replay-атак |
| `pkg/tlsdecoy` | HMAC-аутентификация, TLS config, HTML decoy handler |
| `pkg/config` | YAML-конфигурация сервера (listen, PSK, TLS, TUN, API) |
| `pkg/api` | REST API управления: статус, клиенты, метрики + web UI |

## See Also

- [Безопасность](security.md) — криптографические свойства и модель угроз
- [Конфигурация](configuration.md) — YAML-параметры и CLI-флаги
- [API-справочник](api.md) — управление пользователями через REST API
- [Сборка мобильного приложения](mobile-build.md) — gomobile, Flutter, APK
