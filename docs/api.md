[← Безопасность](security.md) · [Назад к README](../README.md) · [Мобильное приложение →](mobile-build.md)

# API-справочник

REST API управления сервером. Работает на порту 8443 (TLS). Все запросы требуют заголовок `Authorization: Bearer <api_token>`.

Для серверов с самоподписанным сертификатом используйте `curl -k`.

## Управление пользователями

### Создать пользователя

```bash
curl -k -X POST https://SERVER:8443/api/users \
  -H "Authorization: Bearer API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"strongpass123"}'
```

Ответ (201 Created):

```json
{"status":"created","username":"alice"}
```

Требования: пароль 8-1024 символов, username до 255 символов.

### Список пользователей

```bash
curl -k https://SERVER:8443/api/users \
  -H "Authorization: Bearer API_TOKEN"
```

Ответ:

```json
{"users":[{"username":"alice","created_at":"2026-03-09T12:00:00Z","disabled":false}]}
```

### Сменить пароль

```bash
curl -k -X PUT https://SERVER:8443/api/users/alice/password \
  -H "Authorization: Bearer API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"newstrongpass456"}'
```

### Отключить / включить пользователя

```bash
# Отключить
curl -k -X POST https://SERVER:8443/api/users/alice/disable \
  -H "Authorization: Bearer API_TOKEN"

# Включить
curl -k -X POST https://SERVER:8443/api/users/alice/enable \
  -H "Authorization: Bearer API_TOKEN"
```

### Удалить пользователя

```bash
curl -k -X DELETE https://SERVER:8443/api/users/alice \
  -H "Authorization: Bearer API_TOKEN"
```

## Мониторинг

### Статус сервера

```bash
curl -k https://SERVER:8443/api/status \
  -H "Authorization: Bearer API_TOKEN"
```

Ответ:

```json
{"status":"running","version":"0.3.0","uptime_secs":3600,"client_count":1,"listen":":443"}
```

### Подключённые клиенты

```bash
curl -k https://SERVER:8443/api/clients \
  -H "Authorization: Bearer API_TOKEN"
```

### Отключить клиента

```bash
curl -k -X POST https://SERVER:8443/api/clients/CLIENT_ID/disconnect \
  -H "Authorization: Bearer API_TOKEN"
```

## Сводка эндпоинтов

| Метод | Путь | Описание |
|-------|------|----------|
| `GET` | `/api/status` | Статус сервера |
| `GET` | `/api/users` | Список пользователей |
| `POST` | `/api/users` | Создать пользователя |
| `DELETE` | `/api/users/{username}` | Удалить пользователя |
| `PUT` | `/api/users/{username}/password` | Сменить пароль |
| `POST` | `/api/users/{username}/disable` | Отключить аккаунт |
| `POST` | `/api/users/{username}/enable` | Включить аккаунт |
| `GET` | `/api/clients` | Подключённые клиенты |
| `POST` | `/api/clients/{id}/disconnect` | Отключить клиента |

## Конфигурация API

В `server.yaml`:

```yaml
api:
  enabled: true
  listen: ":8443"
  bearer_token: "e5f6a7b8..."
```

API включается флагом `api.enabled: true`. Без `bearer_token` API не запустится.

## See Also

- [Конфигурация](configuration.md) — YAML-параметры и CLI-флаги
- [Начало работы](getting-started.md) — деплой и первый пользователь
- [Продакшн-гайд](production-playbook.md) — полный цикл настройки
