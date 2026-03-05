[<- Архитектура](architecture.md) · [Назад к README](../README.md) · [Безопасность ->](security.md)

# Конфигурация

## Флаги сервера (server-hardened)

| Флаг | Default | Описание |
|------|---------|----------|
| `-listen` | `:443` | TCP-адрес для прослушивания (TLS) |
| `-psk` | — | Pre-shared key (обязательно) |
| `-cert` | `cert.pem` | Путь к TLS-сертификату |
| `-key` | `key.pem` | Путь к TLS приватному ключу |
| `-tun-ip` | `10.0.0.1/24` | IP-адрес TUN-интерфейса (CIDR) |
| `-tun-name` | `tun0` | Имя TUN-интерфейса |
| `-mtu` | `1380` | MTU TUN-интерфейса (меньше стандартного из-за TLS overhead) |

### Пример

```bash
sudo ./simplevpn-server-hardened \
  -listen :443 \
  -psk "my-strong-secret-key" \
  -cert /etc/letsencrypt/live/example.com/fullchain.pem \
  -key  /etc/letsencrypt/live/example.com/privkey.pem \
  -tun-ip 10.0.0.1/24
```

## Флаги клиента (client-hardened)

| Флаг | Default | Описание |
|------|---------|----------|
| `-server` | — | Адрес сервера host:port (обязательно) |
| `-psk` | — | Pre-shared key (обязательно, должен совпадать с сервером) |
| `-sni` | (из `-server`) | SNI для TLS handshake (домен сервера) |
| `-tun-ip` | `10.0.0.2/24` | IP-адрес TUN-интерфейса клиента (CIDR) |
| `-tun-name` | `tun0` | Имя TUN-интерфейса |
| `-mtu` | `1380` | MTU TUN-интерфейса |
| `-route-all` | `false` | Направить весь трафик через VPN |
| `-jitter` | `5` | Максимальный timing jitter (мс), 0 = выключить |
| `-skip-verify` | `false` | Не проверять TLS-сертификат сервера (только для тестов!) |

### Пример — базовое подключение

```bash
sudo ./simplevpn-client-hardened \
  -server example.com:443 \
  -psk "my-strong-secret-key" \
  -tun-ip 10.0.0.2/24
```

### Пример — весь трафик через VPN

```bash
sudo ./simplevpn-client-hardened \
  -server example.com:443 \
  -psk "my-strong-secret-key" \
  -tun-ip 10.0.0.2/24 \
  -route-all
```

### Пример — тестовое подключение (самоподписанный сертификат)

```bash
sudo ./simplevpn-client-hardened \
  -server 192.168.1.100:443 \
  -psk "test-key" \
  -tun-ip 10.0.0.2/24 \
  -skip-verify
```

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
