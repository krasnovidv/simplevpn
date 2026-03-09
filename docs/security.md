[← Конфигурация](configuration.md) · [Назад к README](../README.md) · [API-справочник →](api.md)

# Безопасность

## Криптографические свойства

| Свойство | Реализация |
|----------|------------|
| Конфиденциальность | AES-256-GCM (random nonce 12 байт, tag 16 байт) |
| Аутентификация клиента | Username/Password (bcrypt, cost=12) + server key |
| Защита от replay | Timestamp +/-5 мин + sliding window 1024 пакета |
| Entropy masking | ChaCha20 XOR, уникальный seed (4 байта) на пакет |
| Size fingerprinting | Random padding 0-255 байт на пакет |
| Timing fingerprinting | Random jitter 0-N мс на пакет (клиент) |
| Transport | TLS 1.3, ALPN h2+http/1.1 |
| WebSocket transport | VPN данные в WS binary frames — неотличимо от чата/игры |
| TLS fingerprint mimicry | uTLS: Chrome/Firefox/Safari ClientHello (JA3/JA4 match) |
| Multi-port | Сервер на нескольких портах — устойчив к блокировке порта |
| Active probe resistance | HTML decoy (nginx/1.24.0), auth-gating |

## Модель аутентификации

Сервер использует двухуровневую аутентификацию:

1. **Server key** (64-char hex) — общий ключ для шифрования туннеля. Из него выводятся ключи шифрования (AES-256-GCM) и обфускации (ChaCha20).
2. **Username/Password** — индивидуальные учётные данные для каждого клиента. Пароли хранятся как bcrypt-хэши (cost=12) в файле `users.yaml`.

### Протокол подключения

1. Клиент устанавливает TCP-соединение на порт 443
2. TLS 1.3 handshake (SNI = домен сервера, ALPN = h2/http/1.1)
3. Клиент отправляет учётные данные (username + password)
4. Сервер проверяет credentials через bcrypt
   - Если верно → ответ "OK", туннель активен
   - Если неверно → HTML-страница (decoy), соединение закрыто

## Derive ключей

Из server key выводятся независимые ключи:

```
server_key (hex string)
  -> SHA256 -> masterKey (32 байта)
    -> SHA256(masterKey || "encryption")   -> encKey (AES-256-GCM)
    -> SHA256(masterKey || "obfuscation")  -> DeriveObfsKey() -> obfsKey (ChaCha20)
    -> masterKey напрямую                  -> authKey (HMAC-SHA256)
```

Функция `DeriveObfsKey()` применяет XOR с магическими константами для дополнительного разделения ключей.

## Replay protection

Sliding window с 1024 слотами. Каждый пакет имеет монотонно возрастающий sequence number.

- **seq > maxSeq** — новый пакет, окно сдвигается
- **seq в пределах окна, не видели** — принимается
- **seq в пределах окна, уже видели** — отклоняется (replay)
- **seq < (maxSeq - 1024)** — слишком старый, отклоняется

При потере связи и задержке более 1024 пакетов легитимные пакеты будут отклонены. В этом случае клиенту необходимо переподключиться.

## Модель угроз

### От чего защищает

- **Пассивный DPI** — трафик выглядит как HTTPS (TLS 1.3 на порту 443)
- **JA3/JA4 fingerprinting** — uTLS мимикрирует отпечаток реального браузера
- **Анализ трафика внутри TLS** — WebSocket framing делает трафик похожим на обычное веб-приложение
- **Статистический анализ** — entropy masking + random padding ломают паттерны
- **Блокировка по порту** — multi-port listening, переключение на другой порт
- **Active probing** — сканеры видят HTML-страницу nginx
- **Replay-атаки** — sliding window + timestamp validation
- **Перехват без ключа** — AES-256-GCM шифрование
- **Компрометация одного клиента** — индивидуальные учётные данные, отключение через API

### Ограничения

- **Нет perfect forward secrecy** для VPN-данных — server key статичен (TLS 1.3 обеспечивает PFS для транспорта)
- **Нет ротации ключей** — server key не меняется автоматически
- **Сервер — Linux only** — TUN-интерфейс через `/dev/net/tun`
- **Клиент — Linux и Android** — мобильный клиент через gomobile + Android VpnService

## Рекомендации

- Используйте длинный случайный server key: `openssl rand -hex 32`
- Используйте сертификат Let's Encrypt (самоподписанный — легко детектируется)
- Создавайте отдельные учётные данные для каждого клиента
- Отключайте скомпрометированных пользователей через API
- Не используйте `-skip-verify` в продакшне

## See Also

- [Архитектура](architecture.md) — структура проекта и протокол
- [Начало работы](getting-started.md) — настройка и запуск
- [API-справочник](api.md) — управление пользователями
