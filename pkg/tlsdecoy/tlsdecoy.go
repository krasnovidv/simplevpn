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
// Любой запрос, не содержащий правильного VPN-токена аутентификации,
// получает реальный HTML-ответ (404 страница, redirect и т.д.).
//
// Только клиент, знающий PSK, может доказать серверу свою подлинность
// и получить VPN-соединение. Это называется "port knocking" через TLS.
//
// # Протокол аутентификации
//
// Клиент в первом TLS-сообщении после handshake отправляет:
//
//	[HMAC-SHA256(PSK, "vpn-auth" || timestamp || nonce)]  (32 байта)
//	[timestamp uint64 big-endian]                          (8 байт)
//	[nonce random]                                         (16 байт)
//
// Сервер проверяет HMAC и timestamp (допуск ±5 минут против replay).
// Если проверка провалилась — отвечает как обычный веб-сервер и закрывает соединение.
package tlsdecoy

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	AuthTokenSize = 32 + 8 + 16 // HMAC + timestamp + nonce
	TimeTolerance = 5 * time.Minute
)

// AuthToken — токен аутентификации клиента.
type AuthToken struct {
	HMAC      [32]byte
	Timestamp uint64
	Nonce     [16]byte
}

// GenerateAuthToken создаёт токен аутентификации из PSK.
// Клиент отправляет его сразу после TLS handshake.
func GenerateAuthToken(psk [32]byte) (*AuthToken, []byte, error) {
	tok := &AuthToken{
		Timestamp: uint64(time.Now().Unix()),
	}

	if _, err := io.ReadFull(rand.Reader, tok.Nonce[:]); err != nil {
		return nil, nil, fmt.Errorf("generate nonce: %w", err)
	}

	tok.HMAC = computeHMAC(psk, tok.Timestamp, tok.Nonce)

	// Сериализуем
	buf := make([]byte, AuthTokenSize)
	copy(buf[:32], tok.HMAC[:])
	binary.BigEndian.PutUint64(buf[32:40], tok.Timestamp)
	copy(buf[40:], tok.Nonce[:])

	return tok, buf, nil
}

// VerifyAuthToken проверяет токен аутентификации на сервере.
func VerifyAuthToken(psk [32]byte, data []byte) bool {
	if len(data) < AuthTokenSize {
		return false
	}

	var tok AuthToken
	copy(tok.HMAC[:], data[:32])
	tok.Timestamp = binary.BigEndian.Uint64(data[32:40])
	copy(tok.Nonce[:], data[40:56])

	// Проверяем временну́ю метку (защита от replay)
	now := uint64(time.Now().Unix())
	diff := int64(now) - int64(tok.Timestamp)
	if diff < 0 {
		diff = -diff
	}
	if diff > int64(TimeTolerance.Seconds()) {
		return false
	}

	// Проверяем HMAC
	expected := computeHMAC(psk, tok.Timestamp, tok.Nonce)
	return hmac.Equal(tok.HMAC[:], expected[:])
}

// computeHMAC вычисляет HMAC-SHA256(psk, "vpn-auth" || timestamp || nonce).
func computeHMAC(psk [32]byte, timestamp uint64, nonce [16]byte) [32]byte {
	h := hmac.New(sha256.New, psk[:])
	h.Write([]byte("vpn-auth"))
	var tsBuf [8]byte
	binary.BigEndian.PutUint64(tsBuf[:], timestamp)
	h.Write(tsBuf[:])
	h.Write(nonce[:])
	var result [32]byte
	copy(result[:], h.Sum(nil))
	return result
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
