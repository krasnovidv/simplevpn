// Package tlsdecoy реализует Active Probe Resistance.
//
// # Проблема: активное зондирование
//
// Продвинутые DPI-системы (GFW, ТСПУ) не просто анализируют трафик пассивно.
// Они активно зондируют подозрительные адреса: отправляют HTTP/HTTPS запросы
// и смотрят, что отвечает сервер. Если сервер отвечает не как веб-сайт —
// IP блокируется.
//
// # Решение
//
// Наш сервер слушает на порту 443 и ведёт себя как настоящий HTTPS-сервер.
// Любой запрос, не содержащий правильных credentials,
// получает реальный HTML-ответ (404 страница, redirect и т.д.).
//
// Только клиент с валидным логином/паролем может авторизоваться
// и получить VPN-соединение.
//
// # Протокол аутентификации (v2 — credentials)
//
// Клиент в первом TLS-сообщении после handshake отправляет:
//
//	[1 byte: version = 0x02]
//	[1 byte: username_len]
//	[N bytes: username (UTF-8)]
//	[2 bytes: password_len (big-endian)]
//	[N bytes: password (UTF-8)]
//
// Сервер проверяет credentials через UserStore (bcrypt).
// Если проверка провалилась — отвечает как обычный веб-сервер и закрывает соединение.
package tlsdecoy

import (
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"time"
)

const (
	CredAuthVersion = 0x02
	MaxUsernameLen  = 255
	MaxPasswordLen  = 1024
	AuthReadTimeout = 10 * time.Second
)

// GenerateCredAuth создаёт credential frame для отправки серверу.
// Формат: [version 1B][username_len 1B][username][password_len 2B][password]
func GenerateCredAuth(username, password string) ([]byte, error) {
	if len(username) == 0 || len(username) > MaxUsernameLen {
		return nil, fmt.Errorf("username length must be 1-%d, got %d", MaxUsernameLen, len(username))
	}
	if len(password) == 0 || len(password) > MaxPasswordLen {
		return nil, fmt.Errorf("password length must be 1-%d, got %d", MaxPasswordLen, len(password))
	}

	size := 1 + 1 + len(username) + 2 + len(password)
	buf := make([]byte, size)
	offset := 0

	buf[offset] = CredAuthVersion
	offset++

	buf[offset] = byte(len(username))
	offset++

	copy(buf[offset:], username)
	offset += len(username)

	binary.BigEndian.PutUint16(buf[offset:], uint16(len(password)))
	offset += 2

	copy(buf[offset:], password)

	log.Printf("[tlsdecoy] generated credential frame for user %q (%d bytes)", username, size)
	return buf, nil
}

// ParseCredAuth парсит credential frame и возвращает username, password.
func ParseCredAuth(data []byte) (username, password string, err error) {
	if len(data) < 4 {
		return "", "", fmt.Errorf("credential frame too short: %d bytes", len(data))
	}

	if data[0] != CredAuthVersion {
		return "", "", fmt.Errorf("unsupported auth version: 0x%02x (expected 0x%02x)", data[0], CredAuthVersion)
	}

	usernameLen := int(data[1])
	if usernameLen == 0 || usernameLen > MaxUsernameLen {
		return "", "", fmt.Errorf("invalid username length: %d", usernameLen)
	}

	if len(data) < 2+usernameLen+2 {
		return "", "", fmt.Errorf("credential frame truncated: need %d bytes for username, have %d", 2+usernameLen+2, len(data))
	}

	username = string(data[2 : 2+usernameLen])

	passwordLen := int(binary.BigEndian.Uint16(data[2+usernameLen : 4+usernameLen]))
	if passwordLen == 0 || passwordLen > MaxPasswordLen {
		return "", "", fmt.Errorf("invalid password length: %d", passwordLen)
	}

	if len(data) < 4+usernameLen+passwordLen {
		return "", "", fmt.Errorf("credential frame truncated: need %d bytes for password, have %d", 4+usernameLen+passwordLen, len(data))
	}

	password = string(data[4+usernameLen : 4+usernameLen+passwordLen])

	log.Printf("[tlsdecoy] parsed credential frame: user=%q", username)
	return username, password, nil
}

// ReadCredAuth reads a credential frame from a connection with a timeout.
func ReadCredAuth(conn net.Conn) (username, password string, err error) {
	if err := conn.SetReadDeadline(time.Now().Add(AuthReadTimeout)); err != nil {
		return "", "", fmt.Errorf("set read deadline: %w", err)
	}
	defer conn.SetReadDeadline(time.Time{})

	// Read version + username_len (2 bytes)
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil {
		return "", "", fmt.Errorf("read auth header: %w", err)
	}

	if header[0] != CredAuthVersion {
		return "", "", fmt.Errorf("unsupported auth version: 0x%02x", header[0])
	}

	usernameLen := int(header[1])
	if usernameLen == 0 || usernameLen > MaxUsernameLen {
		return "", "", fmt.Errorf("invalid username length: %d", usernameLen)
	}

	// Read username + password_len
	userAndPwdLen := make([]byte, usernameLen+2)
	if _, err := io.ReadFull(conn, userAndPwdLen); err != nil {
		return "", "", fmt.Errorf("read username+password_len: %w", err)
	}

	username = string(userAndPwdLen[:usernameLen])
	passwordLen := int(binary.BigEndian.Uint16(userAndPwdLen[usernameLen:]))
	if passwordLen == 0 || passwordLen > MaxPasswordLen {
		return "", "", fmt.Errorf("invalid password length: %d", passwordLen)
	}

	// Guard against oversized frames
	totalSize := 2 + usernameLen + 2 + passwordLen
	if totalSize > 4+MaxUsernameLen+2+MaxPasswordLen {
		return "", "", fmt.Errorf("credential frame too large: %d bytes", totalSize)
	}

	// Read password
	pwdBuf := make([]byte, passwordLen)
	if _, err := io.ReadFull(conn, pwdBuf); err != nil {
		return "", "", fmt.Errorf("read password: %w", err)
	}

	password = string(pwdBuf)

	log.Printf("[tlsdecoy] read credential frame from %s: user=%q", conn.RemoteAddr(), username)
	return username, password, nil
}

// DecoyHandler возвращает HTTP handler, имитирующий обычный веб-сервер.
// Используется для ответа на запросы от DPI-систем и сканеров.
func DecoyHandler() http.Handler {
	mux := http.NewServeMux()

	// Главная страница — минималистичный сайт
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Server", "nginx/1.24.0")
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, decoyHTML)
	})

	// robots.txt — делаем сервер более правдоподобным
	mux.HandleFunc("/robots.txt", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprint(w, "User-agent: *\nDisallow: /admin/\n")
	})

	return mux
}

// NewDecoyTLSConfig создаёт TLS-конфиг с самоподписанным сертификатом.
// В продакшне передай настоящий сертификат Let's Encrypt — это значительно
// снижает подозрительность сервера для DPI.
func NewDecoyTLSConfig(certFile, keyFile string) (*tls.Config, error) {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, fmt.Errorf("load TLS cert: %w", err)
	}

	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13, // только TLS 1.3 — современно и безопасно
		// Настройки, характерные для nginx/nginx+:
		NextProtos: []string{"h2", "http/1.1"},
	}, nil
}

// decoyHTML — HTML-страница для имитации веб-сервера.
const decoyHTML = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; color: #333; }
        h1 { color: #666; }
    </style>
</head>
<body>
    <h1>Welcome</h1>
    <p>This server is up and running.</p>
    <hr>
    <small>nginx/1.24.0</small>
</body>
</html>`
