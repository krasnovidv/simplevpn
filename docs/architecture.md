[<- Начало работы](getting-started.md) · [Назад к README](../README.md) · [Конфигурация ->](configuration.md)

# Архитектура

## Структура проекта

```
simplevpn/
├── cmd/
│   ├── server-hardened/        # TLS-сервер с DPI-resistance
│   │   ├── main.go             # Точка входа, accept loop, VPN-логика
│   │   └── tun_linux.go        # Создание TUN через ioctl
│   └── client-hardened/        # TLS-клиент с DPI-resistance
│       ├── main.go             # Подключение, аутентификация, туннель
│       └── tun_linux.go        # Создание TUN через ioctl
├── pkg/
│   ├── crypto/                 # AES-256-GCM шифрование
│   ├── obfs/                   # ChaCha20 entropy masking + padding
│   ├── replay/                 # Sliding window replay protection
│   └── tlsdecoy/               # HMAC-аутентификация + HTML-decoy
├── go.mod
└── Makefile
```

## Уровни защиты

```
┌─────────────────────────────────────────────────────┐
│  TLS 1.3 на порту 443                                │
│  -> DPI видит обычный HTTPS, не VPN                  │
├─────────────────────────────────────────────────────┤
│  Active Probe Resistance                              │
│  -> Сканеры получают HTML-страницу (nginx decoy)     │
├─────────────────────────────────────────────────────┤
│  HMAC-SHA256 аутентификация (PSK)                    │
│  -> Только клиенты с ключом открывают туннель        │
├─────────────────────────────────────────────────────┤
│  AES-256-GCM шифрование                              │
│  -> Содержимое туннеля криптостойко                  │
├─────────────────────────────────────────────────────┤
│  ChaCha20 entropy masking                             │
│  -> Разрушает статистические паттерны                │
├─────────────────────────────────────────────────────┤
│  Random padding + Timing jitter                       │
│  -> Скрывает размеры и временные паттерны            │
├─────────────────────────────────────────────────────┤
│  Sliding window replay protection                     │
│  -> Защита от повторного воспроизведения пакетов     │
└─────────────────────────────────────────────────────┘
```

## Протокол подключения

1. Клиент устанавливает TCP-соединение на порт 443
2. TLS 1.3 handshake (SNI = домен сервера, ALPN = h2/http/1.1)
3. Клиент отправляет auth-токен (56 байт): `HMAC-SHA256(PSK, "vpn-auth" || timestamp || nonce)`
4. Сервер проверяет HMAC и timestamp (допуск +/-5 минут)
   - Если верно -> ответ "OK", туннель активен
   - Если неверно -> HTML-страница (decoy), соединение закрыто

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

## Поток данных (клиент -> сервер)

```
IP-пакет из TUN
  -> AES-256-GCM Encrypt (nonce || ciphertext || tag)
    -> ChaCha20 XOR masking + random padding
      -> Framing (length prefix)
        -> TLS 1.3 запись
          -> TCP на порт 443
```

## Derive ключей

Один PSK порождает три независимых ключа через SHA-256:

```
masterKey   = SHA256(PSK)
encKey      = SHA256(masterKey || "encryption")     -> AES-256-GCM
obfsMaster  = SHA256(masterKey || "obfuscation")    -> DeriveObfsKey() -> ChaCha20
authKey     = masterKey                              -> HMAC-SHA256
```

## Пакеты (pkg/)

| Пакет | Назначение |
|-------|------------|
| `pkg/crypto` | AES-256-GCM: Encrypt/Decrypt с random nonce (12 байт) |
| `pkg/obfs` | ChaCha20 XOR masking, random padding, timing jitter, entropy scoring |
| `pkg/replay` | Sliding window (1024 слота) для защиты от replay-атак |
| `pkg/tlsdecoy` | HMAC-аутентификация, TLS config, HTML decoy handler |

## See Also

- [Безопасность](security.md) — криптографические свойства и модель угроз
- [Конфигурация](configuration.md) — все флаги командной строки
