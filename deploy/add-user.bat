@echo off
:: Добавление пользователя на VPN-сервер через API
:: Использование: add-user.bat <username> [password]

set SERVER=193.23.3.93
set API_PORT=8443
set DEFAULT_PASSWORD=0123456789

if "%~1"=="" (
    echo Использование: %~nx0 ^<username^> [password]
    exit /b 1
)

set USERNAME=%~1
if "%~2"=="" (set PASSWORD=%DEFAULT_PASSWORD%) else (set PASSWORD=%~2)

if "%SIMPLEVPN_API_TOKEN%"=="" (
    echo Ошибка: задайте переменную SIMPLEVPN_API_TOKEN
    echo   set SIMPLEVPN_API_TOKEN=ваш_токен
    exit /b 1
)

echo Создаю пользователя: %USERNAME%

curl -k -s -X POST "https://%SERVER%:%API_PORT%/api/users" ^
    -H "Authorization: Bearer %SIMPLEVPN_API_TOKEN%" ^
    -H "Content-Type: application/json" ^
    -d "{\"username\":\"%USERNAME%\",\"password\":\"%PASSWORD%\"}" ^
    -w "\nHTTP %%{http_code}\n"
