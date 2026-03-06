# SimpleVPN Mobile — Build Guide

## Prerequisites

- **Go** 1.21+ with `gomobile` installed
- **Android SDK** with NDK (for gomobile)
- **Flutter** 3.19+ with Android toolchain configured
- **Java** 17 (for Gradle)

### Install gomobile

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

### Verify Flutter setup

```bash
flutter doctor
# Ensure "Android toolchain" shows a green checkmark
```

## Build Steps

### 1. Build gomobile AAR

From the `mobile/` directory:

```bash
cd mobile
make install-android
```

This builds `vpnlib.aar` and copies it to `app/android/app/libs/`.

### 2. Create local.properties

```bash
cd mobile/app/android
echo "sdk.dir=$ANDROID_HOME" > local.properties
echo "flutter.sdk=$FLUTTER_HOME" >> local.properties
```

Replace `$ANDROID_HOME` and `$FLUTTER_HOME` with actual paths.

### 3. Build debug APK

```bash
cd mobile/app
flutter pub get
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### 4. Build release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

> **Note:** Release builds use the debug signing key by default. For Play Store, configure a release keystore in `android/app/build.gradle.kts`.

### 5. Install on device

```bash
flutter install
# or
adb install build/app/outputs/flutter-apk/app-debug.apk
```

## Running Tests

### Dart tests

```bash
cd mobile/app
flutter test
```

### Go tests

```bash
cd mobile
go test ./vpnlib/
```

## Project Structure

```
mobile/
├── Makefile              # gomobile build targets
├── BUILD.md              # this file
├── vpnlib/
│   ├── vpnlib.go         # Go VPN library (gomobile-compatible)
│   └── vpnlib_test.go    # Go tests
└── app/
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── models/vpn_config.dart
    │   ├── services/
    │   │   ├── vpn_service.dart
    │   │   ├── config_storage.dart
    │   │   └── event_log.dart
    │   └── screens/
    │       ├── home_screen.dart
    │       ├── settings_screen.dart
    │       ├── log_screen.dart
    │       └── qr_scanner_screen.dart
    ├── test/
    │   ├── models/vpn_config_test.dart
    │   └── services/event_log_test.dart
    └── android/
        ├── settings.gradle.kts
        ├── build.gradle.kts
        ├── gradle.properties
        └── app/
            ├── build.gradle.kts
            ├── libs/vpnlib.aar      # built by gomobile
            └── src/main/
                ├── AndroidManifest.xml
                ├── res/
                └── kotlin/com/simplevpn/app/
                    ├── MainActivity.kt
                    ├── SimpleVpnService.kt
                    └── VpnPlugin.kt
```

## Connecting to Test Server

1. Open the app → Settings
2. Enter server: `193.23.3.93:443`
3. Enter your PSK
4. Enable "Skip TLS Verification" (self-signed cert)
5. Save → Connect

Or scan a QR code with JSON config:
```json
{"server":"193.23.3.93:443","psk":"YOUR_PSK","sni":"193.23.3.93","skip_verify":true}
```
