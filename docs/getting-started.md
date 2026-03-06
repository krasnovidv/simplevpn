[Назад к README](../README.md) · [Архитектура →](architecture.md)

# Начало работы

## Требования

- **Go 1.21+** — сборка из исходников
- **Linux** — серверная и клиентская части используют TUN-интерфейс (`/dev/net/tun`)
- **Root-доступ** — для создания TUN-интерфейса и работы с портом 443
- **TLS-сертификат** — самоподписанный (тест) или Let's Encrypt (продакшн)

## Вариант 1: Docker-деплой на VPS (рекомендуется)

```bash
# Скопировать файлы на VPS
scp -r deploy/ Dockerfile docker-compose.yml server.example.yaml root@YOUR_SERVER:/opt/simplevpn/

# Деплой по IP (самоподписанный сертификат)
ssh root@YOUR_SERVER "cd /opt/simplevpn && bash deploy/deploy.sh YOUR_SERVER_IP"

# Деплой с доменом (Let's Encrypt)
ssh root@YOUR_SERVER "cd /opt/simplevpn && bash deploy/deploy.sh yourdomain.com domain your@email.com"
```

Скрипт автоматически:
- Генерирует PSK и API-токен
- Создаёт TLS-сертификат (самоподписанный или Let's Encrypt)
- Настраивает firewall (NAT, ip_forward)
- Запускает VPN-сервер в Docker

**Сохраните PSK и API-токен** — они понадобятся для подключения клиентов.

## Вариант 2: Локальная сборка

```bash
git clone <repo-url> && cd simplevpn
go mod tidy
make build
```

На выходе два бинарника:
- `simplevpn-server-hardened` — сервер
- `simplevpn-client-hardened` — клиент

## TLS-сертификат (для локальной сборки)

### Для тестов (самоподписанный)

```bash
make cert
# Создаёт cert.pem и key.pem в текущей директории
```

### Для продакшна (Let's Encrypt)

```bash
certbot certonly --standalone -d yourdomain.com
```

Пути к сертификатам:
- `/etc/letsencrypt/live/yourdomain.com/fullchain.pem`
- `/etc/letsencrypt/live/yourdomain.com/privkey.pem`

## Запуск сервера (локально)

```bash
sudo ./simplevpn-server-hardened \
  -listen :443 \
  -psk "твой-секретный-ключ" \
  -cert /etc/letsencrypt/live/yourdomain.com/fullchain.pem \
  -key  /etc/letsencrypt/live/yourdomain.com/privkey.pem \
  -tun-ip 10.0.0.1/24
```

Сервер начнёт слушать на порту 443. Для DPI это выглядит как обычный HTTPS-сервер.

## Запуск клиента

```bash
sudo ./simplevpn-client-hardened \
  -server yourdomain.com:443 \
  -psk "твой-секретный-ключ" \
  -sni yourdomain.com \
  -tun-ip 10.0.0.2/24 \
  -route-all
```

Флаг `-route-all` направляет весь трафик через VPN. Без него — только трафик в подсеть `10.0.0.0/24`.

## Проверка

```bash
# Туннель работает
ping 10.0.0.1

# DPI-зонд видит веб-сайт
curl -k https://yourdomain.com
# -> <html><body><h1>Welcome</h1>...
```

При подключении клиент выведет:

```
Crypto initialized
TUN tun0: 10.0.0.2/24
Connecting to yourdomain.com:443 (TLS SNI: yourdomain.com)...
TLS 1.3 handshake OK
Authentication OK
Tunnel active: 10.0.0.2/24 <-> yourdomain.com:443
```

## Тесты

```bash
make test    # юнит-тесты пакетов pkg/
make bench   # бенчмарки (Wrap/Unwrap, Check)
```

## See Also

- [Конфигурация](configuration.md) — полный список флагов сервера и клиента
- [Архитектура](architecture.md) — как устроен проект внутри
- [Мобильное приложение](mobile-build.md) — сборка Android-клиента
