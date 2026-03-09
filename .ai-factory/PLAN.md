# Plan: Авторизация по логину/паролю (вместо PSK)

**Дата:** 2026-03-09
**Подход:** Вариант 1 (простой) — credentials передаются после TLS handshake

## Settings

- **Testing:** Yes
- **Logging:** Verbose (DEBUG)
- **Docs:** No

## Обзор

Переход от PSK (Pre-Shared Key) авторизации к авторизации по логину и паролю.
Текущая система использует единый PSK для всех клиентов (нет идентификации).
Новая система даёт per-user identity с bcrypt-хешами на сервере.

### Протокол (после TLS 1.3 handshake):
```
Client → Server:
  [1 byte: version = 0x02]
  [1 byte: username_len]
  [N bytes: username (UTF-8)]
  [2 bytes: password_len (big-endian)]
  [N bytes: password (UTF-8)]

Server → Client:
  "OK" (2 bytes) — успех
  decoy HTML    — провал
```

Пароль защищён TLS 1.3 — передаётся в открытом виде только внутри зашифрованного туннеля.

## Tasks

### Фаза 1: Серверная основа

1. - [x] **[Task #1] Создать пакет pkg/auth — хранение пользователей (bcrypt)**
   - `pkg/auth/store.go` — FileStore (YAML), потокобезопасный (sync.RWMutex)
   - `pkg/auth/user.go` — User struct {Username, PasswordHash, CreatedAt, Disabled}
   - Authenticate, AddUser, RemoveUser, ListUsers, UpdatePassword
   - Логирование: username в логах, пароль НИКОГДА

2. - [x] **[Task #2] Изменить протокол аутентификации в pkg/tlsdecoy**
   - Удалить: `GenerateAuthToken`, `VerifyAuthToken`, `AuthToken` struct, `computeHMAC`, `AuthTokenSize`
   - Добавить: `GenerateCredAuth(username, password)` → credential frame (version 0x02)
   - Добавить: `ParseCredAuth(data)` → username, password
   - Добавить: `ReadCredAuth(conn)` → читает frame из соединения с таймаутом
   - *Blocked by: Task #1*

3. - [x] **[Task #3] Обновить конфиг сервера (pkg/config)**
   - Убрать `PSK`, добавить `ServerKey` (yaml: `server_key`), `UsersFile` (yaml: `users_file`)
   - Обновить `Validate()` — убрать проверку PSK, добавить проверку ServerKey и UsersFile
   - Дефолт `UsersFile`: `/etc/simplevpn/users.yaml`
   - *Blocked by: Task #1*

4. - [x] **[Task #4] Обновить tunnel.DeriveKeys — принимать server_key**
   - `pkg/tunnel/keys.go`: переименовать параметр `psk` → `serverKey`, обновить комментарии
   - Обновить вызовы в 3 местах: server main.go, client main.go, mobile vpnlib.go
   - Обновить тесты в `tunnel_test.go`
   - *Blocked by: Task #3*

### Фаза 2: Интеграция сервера

5. - [x] **[Task #5] Обновить серверный main.go — credential auth**
   - Загрузка `UserStore` из `cfg.UsersFile`
   - `serveAuth()`: `ReadCredAuth(conn)` → `store.Authenticate(username, password)`
   - `DeriveKeys(cfg.ServerKey)` вместо `DeriveKeys(cfg.PSK)`
   - Маскировка паролей: логировать username, НИКОГДА password
   - Передать store в API для user management
   - *Blocked by: Tasks #1, #2, #3, #4*

6. - [x] **[Task #6] Обновить cmd/client-hardened — credentials вместо PSK**
   - Убрать `-psk`, добавить `-username`, `-password`, `-server-key`
   - `GenerateCredAuth(username, password)` вместо `GenerateAuthToken(keys.Master)`
   - `DeriveKeys(*serverKey)` вместо `DeriveKeys(*psk)`
   - Обновить doc comment с примерами
   - *Blocked by: Tasks #2, #4*

7. - [x] **[Task #7] Добавить API для управления пользователями**
   - CRUD: GET/POST/DELETE/PUT users (защищены Bearer token)
   - `Server` struct получает `store *auth.FileStore`
   - Маскировка паролей в request/response
   - *Blocked by: Tasks #1, #3*

**--- Commit checkpoint: "feat(auth): replace PSK with login/password auth" ---**

### Фаза 3: Клиенты

8. - [x] **[Task #8] Обновить mobile/vpnlib — credentials**
   - Config: `ServerKey`+`Username`+`Password` вместо `PSK`
   - Connect(): `DeriveKeys(cfg.ServerKey)`, `GenerateCredAuth(username, password)` вместо HMAC token
   - Маскировка паролей в логах
   - *Blocked by: Tasks #2, #4*

9. - [x] **[Task #9] Обновить Flutter UI — login/password**
   - VpnConfig model: serverKey, username, password вместо psk
   - Settings screen: поля Username, Password, Server Key вместо PSK
   - QR формат: `{"server":"...","server_key":"...","username":"...","password":"...","sni":"..."}`
   - Config storage: обновить ключи SharedPreferences
   - *Blocked by: Task #8*

**--- Commit checkpoint: "feat(mobile): update auth to login/password" ---**

### Фаза 4: Deploy & Тесты

10. - [x] **[Task #10] Обновить deploy конфиг и пример YAML**
    - Пример конфига: `server_key` + `users_file` вместо `psk`
    - `deploy/users.yaml.example` — шаблон файла пользователей
    - `deploy/entrypoint.sh` — генерация server_key и users.yaml при первом запуске
    - *Blocked by: Task #3*

11. - [x] **[Task #11] Написать тесты для credential auth**
    - `pkg/auth/store_test.go` — CRUD, bcrypt, concurrent access, edge cases
    - `pkg/tlsdecoy/tlsdecoy_test.go` — credential frame roundtrip, edge cases
    - `pkg/api/api_test.go` — user CRUD через API, auth required
    - Проверить маскировку паролей в логах
    - *Blocked by: Tasks #1, #2, #7*

**--- Commit checkpoint: "test(auth): add tests for credential auth" ---**

## Ключи шифрования туннеля

Сейчас `tunnel.DeriveKeys(psk)` деривирует ключи шифрования из PSK.
Решение: новое поле `server_key` в конфиге — фиксированный секрет для шифрования туннеля.
Генерируется один раз при установке. Клиент получает его через QR/настройки вместе с credentials.
