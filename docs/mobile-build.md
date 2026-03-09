[← API-справочник](api.md) · [Назад к README](../README.md) · [Продакшн-гайд →](production-playbook.md)

# Сборка мобильного приложения

## Требования

- **Go** 1.25+ с установленным `gomobile`
- **Android SDK** с NDK (для gomobile)
- **Flutter** 3.19+ с настроенным Android toolchain
- **Java** 17 (для Gradle)

### Установка gomobile

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

### Проверка Flutter

```bash
flutter doctor
# Убедитесь, что "Android toolchain" показывает зелёную галочку
```

## Сборка

### 1. Сборка gomobile AAR

Из директории `mobile/`:

```bash
cd mobile
make install-android
```

Создаёт `vpnlib.aar` и копирует в `app/android/app/libs/`.

### 2. Настройка local.properties

```bash
cd mobile/app/android
echo "sdk.dir=$ANDROID_HOME" > local.properties
echo "flutter.sdk=$FLUTTER_HOME" >> local.properties
```

Замените `$ANDROID_HOME` и `$FLUTTER_HOME` на реальные пути.

### 3. Debug APK

```bash
cd mobile/app
flutter pub get
flutter build apk --debug
```

Результат: `build/app/outputs/flutter-apk/app-debug.apk`

### 4. Release APK

```bash
flutter build apk --release
```

> **Примечание:** Release-сборка использует debug signing key. Для Google Play настройте release keystore в `android/app/build.gradle.kts`.

### 5. Установка на устройство

```bash
flutter install
# или
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Полная сборка одной командой

```bash
cd mobile && make install-android && cd app && flutter build apk --debug
```

## Тесты

### Dart-тесты

```bash
cd mobile/app
flutter test
```

### Go-тесты

```bash
cd mobile
go test ./vpnlib/
```

## Подключение к серверу

### Через настройки

1. Откройте приложение → Настройки
2. Введите сервер: `ваш-сервер:443`
3. Введите server key, username и password
4. Включите "Skip TLS Verification" (если самоподписанный сертификат)
5. Сохраните → Подключиться

### Через QR-код

Отсканируйте QR с JSON-конфигурацией:

```json
{"server":"ваш-сервер:443","server_key":"KEY","username":"alice","password":"strongpass123","skip_verify":true}
```

Генерация QR из командной строки:

```bash
echo -n '{"server":"YOUR_IP:443","server_key":"KEY","username":"alice","password":"strongpass123","skip_verify":true}' | qrencode -o config.png
```

## Структура проекта

```
mobile/
├── Makefile              # gomobile build targets
├── vpnlib/
│   ├── vpnlib.go         # Go VPN библиотека (gomobile-совместимая)
│   └── vpnlib_test.go
└── app/
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── models/vpn_config.dart
    │   ├── services/
    │   │   ├── vpn_service.dart       # Управление VPN, поллинг статуса
    │   │   ├── config_storage.dart    # SharedPreferences
    │   │   └── event_log.dart         # Журнал событий
    │   └── screens/
    │       ├── home_screen.dart       # Главный экран, кнопка Connect
    │       ├── settings_screen.dart   # Конфигурация сервера
    │       ├── log_screen.dart        # Просмотр логов
    │       └── qr_scanner_screen.dart # Сканер QR-конфигурации
    └── android/
        └── app/src/main/kotlin/com/simplevpn/app/
            ├── MainActivity.kt
            ├── SimpleVpnService.kt    # Android VpnService
            └── VpnPlugin.kt          # Flutter MethodChannel
```

## See Also

- [Начало работы](getting-started.md) — установка сервера
- [Конфигурация](configuration.md) — формат QR JSON и параметры
- [Архитектура](architecture.md) — общая структура проекта
