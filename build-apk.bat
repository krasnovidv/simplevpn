@echo off
:: Сборка release APK
:: Использование: build-apk.bat [--debug]

set FLUTTER=D:\flutter\bin\flutter

echo === Сборка gomobile AAR ===
cd /d "%~dp0mobile"
if errorlevel 1 (echo Ошибка: директория mobile не найдена & exit /b 1)
call gomobile bind -target=android -androidapi 21 -o build\vpnlib.aar simplevpn/mobile/vpnlib
if errorlevel 1 (echo Ошибка сборки AAR & exit /b 1)
copy /y build\vpnlib.aar app\android\app\libs\vpnlib.aar >nul
if errorlevel 1 (echo Ошибка копирования AAR & exit /b 1)

echo === Сборка APK ===
cd /d "%~dp0mobile\app"
call %FLUTTER% pub get
if errorlevel 1 (echo Ошибка flutter pub get & exit /b 1)

if "%~1"=="--debug" (
    call %FLUTTER% build apk --debug
) else (
    call %FLUTTER% build apk --release
)
if errorlevel 1 (echo Ошибка сборки APK & exit /b 1)

if not exist "%~dp0apks" mkdir "%~dp0apks"

if "%~1"=="--debug" (
    copy /y build\app\outputs\flutter-apk\app-debug.apk "%~dp0apks\simplevpn-debug.apk" >nul
) else (
    copy /y build\app\outputs\flutter-apk\app-release.apk "%~dp0apks\simplevpn-release.apk" >nul
)
if errorlevel 1 (echo Ошибка копирования APK & exit /b 1)

echo === Готово ===
if "%~1"=="--debug" (
    echo APK: apks\simplevpn-debug.apk
) else (
    echo APK: apks\simplevpn-release.apk
)
