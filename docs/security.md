[← Конфигурация](configuration.md) · [Назад к README](../README.md) · [Сборка мобильного приложения →](mobile-build.md)

# Безопасность

## Криптографические свойства

| Свойство | Реализация |
|----------|------------|
| Конфиденциальность | AES-256-GCM (random nonce 12 байт, tag 16 байт) |
| Аутентификация клиента | HMAC-SHA256(PSK, "vpn-auth" \|\| timestamp \|\| nonce) |
| Защита от replay | Timestamp +/-5 мин + sliding window 1024 пакета |
| Entropy masking | ChaCha20 XOR, уникальный seed (4 байта) на пакет |
| Size fingerprinting | Random padding 0-255 байт на пакет |
| Timing fingerprinting | Random jitter 0-N мс на пакет (клиент) |
| Transport | TLS 1.3, ALPN h2+http/1.1 |
| WebSocket transport | VPN данные в WS binary frames — неотличимо от чата/игры |
| TLS fingerprint mimicry | uTLS: Chrome/Firefox/Safari ClientHello (JA3/JA4 match) |
| Multi-port | Сервер на нескольких портах — устойчив к блокировке порта |
| Active probe resistance | HTML decoy (nginx/1.24.0), auth-gating |

## Протокол аутентификации

Клиент в первом TLS-сообщении после handshake отправляет 56 байт:

```
[HMAC-SHA256(masterKey, "vpn-auth" || timestamp || nonce)]  32 байта
[timestamp uint64 big-endian]                                8 байт
[nonce random]                                              16 байт
```

Сервер проверяет:

1. **Timestamp** — разница с текущим временем не более 5 минут (защита от replay старых токенов)
2. **HMAC** — пересчитывает HMAC с тем же masterKey и сравнивает через `hmac.Equal` (constant-time)

При провале проверки сервер отвечает как обычный веб-сервер: HTTP 200 с HTML-страницей и заголовком `Server: nginx/1.24.0`.

## Derive ключей

Из одного PSK выводятся независимые ключи:

```
PSK (строка)
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
- **Перехват без PSK** — AES-256-GCM шифрование

### Ограничения

- **Один PSK на все клиенты** — компрометация одного клиента компрометирует всех
- **Нет perfect forward secrecy** для VPN-данных — PSK статичен (TLS 1.3 обеспечивает PFS для транспорта)
- **Нет ротации ключей** — PSK не меняется автоматически
- **Сервер — Linux only** — TUN-интерфейс через `/dev/net/tun`
- **Клиент — Linux и Android** — мобильный клиент через gomobile + Android VpnService
- **Один активный клиент** — сервер хранит только последнее соединение для отправки пакетов

## Рекомендации

- Используйте длинный случайный PSK (32+ символов)
- Используйте сертификат Let's Encrypt (самоподписанный — легко детектируется)
- Регулярно меняйте PSK вручную
- Не используйте `-skip-verify` в продакшне

## See Also

- [Архитектура](architecture.md) — структура проекта и протокол
- [Начало работы](getting-started.md) — настройка и запуск
- [Сборка мобильного приложения](mobile-build.md) — сборка и установка Android-клиента
