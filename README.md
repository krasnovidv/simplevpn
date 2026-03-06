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

Скрипт сгенерирует PSK и API-токен — **сохраните их**.

### Локальная сборка

```bash
go mod tidy
make build

# Самоподписанный сертификат (для тестов)
make cert

# Сервер
sudo ./simplevpn-server-hardened \
  -listen :443 -psk "my-secret" \
  -cert cert.pem -key key.pem -tun-ip 10.0.0.1/24

# Клиент
sudo ./simplevpn-client-hardened \
  -server yourserver.com:443 -psk "my-secret" \
  -tun-ip 10.0.0.2/24 -route-all
```

## Ключевые возможности

- **TLS 1.3 на порту 443** — трафик неотличим от HTTPS
- **Active Probe Resistance** — зонды получают HTML-страницу nginx
- **AES-256-GCM + ChaCha20 masking** — шифрование и маскировка энтропии
- **Random padding + timing jitter** — скрывает размеры и паттерны пакетов
- **HMAC-SHA256 аутентификация** — только клиенты с PSK открывают туннель
- **Sliding window replay protection** — защита от повторного воспроизведения

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
| [Конфигурация](docs/configuration.md) | Все флаги сервера и клиента |
| [Безопасность](docs/security.md) | Криптография, протокол аутентификации, модель угроз |
| [Мобильное приложение](docs/mobile-build.md) | Сборка Android-клиента, gomobile, Flutter |
