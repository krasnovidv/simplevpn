[← Архитектура](architecture.md) · [Назад к README](../README.md) · [Безопасность →](security.md)

# Конфигурация

## YAML-конфигурация сервера

Основной способ конфигурации — файл `server.yaml`:

```yaml
listen: ":443"
server_key: "a1b2c3d4e5f6..."    # 64-char hex, openssl rand -hex 32
users_file: "/etc/simplevpn/users.yaml"

cert: "/etc/simplevpn/certs/server.crt"
key: "/etc/simplevpn/certs/server.key"

tun_ip: "10.0.0.1/24"
tun_name: "tun0"
mtu: 1380

log_level: "info"

transport:
  extra_listens:
    - ":80"
    - ":8080"

api:
  enabled: true
  listen: ":8443"
  bearer_token: "e5f6a7b8..."
```

| Поле | Обязательно | Default | Описание |
|------|-------------|---------|----------|
| `listen` | да | `:443` | TCP-адрес VPN |
| `server_key` | да | — | 64-char hex ключ шифрования туннеля |
| `users_file` | да | — | Путь к файлу пользователей |
| `cert` | да | `cert.pem` | TLS-сертификат |
| `key` | да | `key.pem` | TLS приватный ключ |
| `tun_ip` | да | `10.0.0.1/24` | IP TUN-интерфейса (CIDR) |
| `tun_name` | нет | `tun0` | Имя TUN-интерфейса |
| `mtu` | нет | `1380` | MTU (500-9000) |
| `log_level` | нет | `info` | Уровень логов: debug, info, warn, error |
| `transport.extra_listens` | нет | `[]` | Дополнительные порты |
| `api.enabled` | нет | `false` | Включить REST API |
| `api.listen` | нет | `:8443` | Адрес API |
| `api.bearer_token` | при api | — | Bearer-токен для API |

## Флаги сервера (CLI)

CLI-флаги переопределяют значения из конфиг-файла:

| Флаг | Описание |
|------|----------|
| `-config` | Путь к YAML-конфигу |
| `-listen` | TCP-адрес (TLS) |
| `-server-key` | Ключ шифрования туннеля |
| `-users-file` | Путь к файлу пользователей |
| `-cert` | TLS-сертификат |
| `-key` | TLS приватный ключ |
| `-tun-ip` | IP TUN-интерфейса (CIDR) |
| `-tun-name` | Имя TUN-интерфейса |
| `-mtu` | MTU |

### Пример

```bash
simplevpn-server -config server.yaml -listen :8443 -log-level debug
```

## Флаги клиента (CLI)

| Флаг | Default | Описание |
|------|---------|----------|
| `-server` | — | Адрес сервера host:port (обязательно) |
| `-server-key` | — | Ключ шифрования туннеля (обязательно) |
| `-username` | — | Имя пользователя (обязательно) |
| `-password` | — | Пароль (обязательно) |
| `-sni` | (из `-server`) | SNI для TLS handshake |
| `-transport` | `tls` | Транспорт: `tls` (raw TLS) или `ws` (WebSocket) |
| `-fingerprint` | `none` | Профиль TLS отпечатка: `none`, `chrome`, `firefox`, `safari` |
| `-tun-ip` | `10.0.0.2/24` | IP TUN-интерфейса клиента (CIDR) |
| `-tun-name` | `tun0` | Имя TUN-интерфейса |
| `-mtu` | `1380` | MTU |
| `-route-all` | `false` | Направить весь трафик через VPN |
| `-jitter` | `5` | Макс. timing jitter (мс), 0 = выкл. |
| `-skip-verify` | `false` | Не проверять TLS-сертификат (только тесты!) |

### Пример — базовое подключение

```bash
sudo ./simplevpn-client \
  -server example.com:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -tun-ip 10.0.0.2/24
```

### Пример — весь трафик через VPN

```bash
sudo ./simplevpn-client \
  -server example.com:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -tun-ip 10.0.0.2/24 \
  -route-all
```

### Пример — WebSocket + Chrome fingerprint (anti-DPI)

```bash
sudo ./simplevpn-client \
  -server example.com:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -transport ws \
  -fingerprint chrome \
  -tun-ip 10.0.0.2/24
```

### Пример — самоподписанный сертификат (тест)

```bash
sudo ./simplevpn-client \
  -server 192.168.1.100:443 \
  -server-key "a1b2c3d4e5f6..." \
  -username alice \
  -password strongpass123 \
  -tun-ip 10.0.0.2/24 \
  -skip-verify
```

## Мобильная конфигурация (QR JSON)

QR-код для мобильного приложения содержит JSON:

```json
{
  "server": "example.com:443",
  "server_key": "a1b2c3d4e5f6...",
  "username": "alice",
  "password": "strongpass123",
  "sni": "example.com",
  "transport": "ws",
  "fingerprint": "chrome"
}
```

| Поле | Обязательно | Default | Описание |
|------|-------------|---------|----------|
| `server` | да | — | Адрес сервера host:port |
| `server_key` | да | — | Ключ шифрования туннеля |
| `username` | да | — | Имя пользователя |
| `password` | да | — | Пароль |
| `sni` | нет | из server | SNI для TLS |
| `transport` | нет | `ws` | Транспорт: `ws` или `tls` |
| `fingerprint` | нет | `chrome` (Android), `safari` (iOS) | TLS отпечаток |
| `skip_verify` | нет | `false` | Пропуск верификации сертификата |

## MTU

Значение по умолчанию `1380` учитывает overhead от TLS (до 40 байт), framing (4 байта), obfuscation header (5 байт) и random padding (0-255 байт). Если наблюдаются проблемы с фрагментацией, попробуйте уменьшить до `1300`.

## Timing jitter

Флаг `-jitter` на клиенте добавляет случайную задержку (0..N мс) перед отправкой каждого пакета. Это размывает временные паттерны трафика, которые DPI может использовать для детекции. Значение `0` отключает jitter полностью.

## Маршрутизация

Флаг `-route-all` на клиенте:

1. Добавляет маршрут к серверу через текущий default gateway (чтобы VPN-трафик не зациклился)
2. Добавляет `0.0.0.0/1` и `128.0.0.0/1` через TUN-интерфейс (перекрывает default route без его удаления)

## See Also

- [Начало работы](getting-started.md) — пошаговая инструкция запуска
- [Безопасность](security.md) — криптографические детали
- [API-справочник](api.md) — управление пользователями через REST API
