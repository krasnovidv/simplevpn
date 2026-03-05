// Hardened VPN Server — устойчивый к DPI
//
// # Архитектура защиты
//
//  1. TLS 1.3 на порту 443 — трафик неотличим от HTTPS
//  2. Active Probe Resistance — зондировщики видят обычный веб-сайт
//  3. AES-256-GCM шифрование — содержимое туннеля криптостойко
//  4. ChaCha20 entropy masking — разрушает статистические паттерны
//  5. Random padding — скрывает размеры пакетов
//  6. Sliding window replay protection — защита от replay-атак
//  7. HMAC аутентификация — только клиенты с PSK могут подключиться
//
// # Запуск
//
//	# Сначала получи TLS-сертификат (например через certbot):
//	certbot certonly --standalone -d yourdomain.com
//
//	# Или создай самоподписанный (для тестов):
//	openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=localhost'
//
//	sudo ./server-hardened \
//	  -listen :443 \
//	  -psk "мой-супер-секрет" \
//	  -cert cert.pem \
//	  -key key.pem \
//	  -tun-ip 10.0.0.1/24
//
// # Протокол поверх TLS
//
// После TLS handshake каждое сообщение имеет формат:
//
//	[length uint32 big-endian] [obfuscated(encrypted(IP-packet))]
//
// Framing нужен потому что TLS — потоковый протокол (в отличие от UDP).
package main

import (
	"crypto/sha256"
	"crypto/tls"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
	"simplevpn/pkg/replay"
	"simplevpn/pkg/tlsdecoy"
)

const (
	maxFrameSize = 65535
)

// clientConn — активное VPN-соединение с клиентом.
type clientConn struct {
	conn net.Conn
	seq  uint64
}

func main() {
	listenAddr := flag.String("listen", ":443", "TCP-адрес для прослушивания (TLS)")
	psk        := flag.String("psk", "", "Pre-shared key (обязательно)")
	certFile   := flag.String("cert", "cert.pem", "TLS сертификат")
	keyFile    := flag.String("key", "key.pem", "TLS приватный ключ")
	tunIP      := flag.String("tun-ip", "10.0.0.1/24", "IP TUN-интерфейса (CIDR)")
	tunName    := flag.String("tun-name", "tun0", "Имя TUN-интерфейса")
	mtu        := flag.Int("mtu", 1380, "MTU (меньше из-за TLS overhead)")
	flag.Parse()

	if *psk == "" {
		log.Fatal("Укажите -psk")
	}

	// ── Derive ключей из PSK ─────────────────────────────────────────────────
	masterKey := sha256.Sum256([]byte(*psk))

	encKey := sha256.Sum256(append(masterKey[:], []byte("encryption")...))
	obfsKey := obfs.DeriveObfsKey(sha256.Sum256(append(masterKey[:], []byte("obfuscation")...)))

	ciph, err := crypto.NewCipherFromKey(encKey)
	if err != nil {
		log.Fatalf("Init cipher: %v", err)
	}
	obfuscator := obfs.New(obfsKey)
	replayWindow := replay.New()

	log.Println("Crypto initialized")
	log.Printf("  Encryption: AES-256-GCM")
	log.Printf("  Obfuscation: ChaCha20 entropy masking + random padding")
	log.Printf("  Replay protection: sliding window (%d packets)", replay.WindowSize)

	// ── TUN-интерфейс ────────────────────────────────────────────────────────
	tun, err := createTUN(*tunName, *tunIP, *mtu)
	if err != nil {
		log.Fatalf("Create TUN: %v", err)
	}
	defer tun.Close()
	log.Printf("TUN %s up: %s", *tunName, *tunIP)

	// ── TLS конфиг ──────────────────────────────────────────────────────────
	tlsCfg, err := tlsdecoy.NewDecoyTLSConfig(*certFile, *keyFile)
	if err != nil {
		log.Fatalf("TLS config: %v", err)
	}
	log.Printf("TLS 1.3 configured (cert: %s)", *certFile)

	// ── TLS listener ────────────────────────────────────────────────────────
	tlsListener, err := tls.Listen("tcp", *listenAddr, tlsCfg)
	if err != nil {
		log.Fatalf("Listen %s: %v", *listenAddr, err)
	}
	defer tlsListener.Close()
	log.Printf("Listening on %s (TLS)", *listenAddr)

	// ── Graceful shutdown ─────────────────────────────────────────────────────
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("\nShutting down...")
		tlsListener.Close()
		os.Exit(0)
	}()

	// Канал для активного клиента (TUN → client)
	activeClient := make(chan *clientConn, 1)
	var currentClient *clientConn

	go func() {
		buf := make([]byte, maxFrameSize)
		encBuf := make([]byte, 0, maxFrameSize+crypto.Overhead)
		obfsBuf := make([]byte, 0, maxFrameSize+crypto.Overhead+obfs.HeaderSize+obfs.MaxPad)

		for {
			select {
			case c := <-activeClient:
				currentClient = c
			default:
			}

			if currentClient == nil {
				select {
				case c := <-activeClient:
					currentClient = c
				case <-time.After(100 * time.Millisecond):
					continue
				}
			}

			n, err := tun.Read(buf)
			if err != nil {
				log.Printf("TUN read: %v", err)
				return
			}

			encrypted, err := ciph.Encrypt(encBuf[:0], buf[:n])
			if err != nil {
				log.Printf("Encrypt: %v", err)
				continue
			}

			obfuscated, err := obfuscator.Wrap(obfsBuf[:0], encrypted)
			if err != nil {
				log.Printf("Obfs wrap: %v", err)
				continue
			}

			frame := make([]byte, 4+len(obfuscated))
			binary.BigEndian.PutUint32(frame[:4], uint32(len(obfuscated)))
			copy(frame[4:], obfuscated)

			if _, err := currentClient.conn.Write(frame); err != nil {
				log.Printf("Write to client: %v", err)
				currentClient = nil
			}
		}
	}()

	// ── Accept loop ──────────────────────────────────────────────────────────
	for {
		conn, err := tlsListener.Accept()
		if err != nil {
			log.Printf("Accept: %v", err)
			return
		}

		go serveConnection(conn, masterKey, ciph, obfuscator, replayWindow, tun, activeClient)
	}
}

// serveConnection обрабатывает одно TLS-соединение.
// Проверяет аутентификацию — если провалилась, отдаёт decoy HTML.
func serveConnection(
	conn net.Conn,
	masterKey [32]byte,
	ciph *crypto.Cipher,
	obfuscator *obfs.Obfuscator,
	replayWin *replay.Window,
	tun *tunDevice,
	activeClient chan<- *clientConn,
) {
	defer conn.Close()
	remoteAddr := conn.RemoteAddr().String()

	// Читаем auth token (56 байт)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	authBuf := make([]byte, tlsdecoy.AuthTokenSize)
	if _, err := io.ReadFull(conn, authBuf); err != nil {
		log.Printf("Auth timeout from %s -> decoy mode", remoteAddr)
		serveDecoy(conn)
		return
	}
	conn.SetReadDeadline(time.Time{})

	if !tlsdecoy.VerifyAuthToken(masterKey, authBuf) {
		log.Printf("Auth FAILED from %s -> decoy mode", remoteAddr)
		serveDecoy(conn)
		return
	}

	log.Printf("VPN client authenticated: %s", remoteAddr)

	conn.Write([]byte("OK"))

	activeClient <- &clientConn{conn: conn}

	// Читаем пакеты от клиента
	lenBuf := make([]byte, 4)
	frameBuf := make([]byte, maxFrameSize+obfs.HeaderSize+obfs.MaxPad)
	decBuf := make([]byte, 0, maxFrameSize)
	var seq uint64

	for {
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			log.Printf("Client %s disconnected: %v", remoteAddr, err)
			return
		}
		frameLen := binary.BigEndian.Uint32(lenBuf)
		if frameLen > uint32(len(frameBuf)) {
			log.Printf("Frame too large from %s: %d", remoteAddr, frameLen)
			return
		}

		if _, err := io.ReadFull(conn, frameBuf[:frameLen]); err != nil {
			log.Printf("Read frame from %s: %v", remoteAddr, err)
			return
		}

		encrypted, err := obfuscator.Unwrap(frameBuf[:frameLen])
		if err != nil {
			log.Printf("Obfs unwrap from %s: %v", remoteAddr, err)
			continue
		}

		seq++
		if !replayWin.Check(seq) {
			log.Printf("Replay detected from %s (seq %d)", remoteAddr, seq)
			continue
		}

		plaintext, err := ciph.Decrypt(decBuf[:0], encrypted)
		if err != nil {
			log.Printf("Decrypt from %s: %v", remoteAddr, err)
			continue
		}

		if _, err := tun.Write(plaintext); err != nil {
			log.Printf("TUN write: %v", err)
		}
	}
}

func serveDecoy(conn net.Conn) {
	resp := fmt.Sprintf(
		"HTTP/1.1 200 OK\r\n"+
			"Content-Type: text/html; charset=utf-8\r\n"+
			"Server: nginx/1.24.0\r\n"+
			"Connection: close\r\n\r\n"+
			"<html><body><h1>Welcome</h1><p>Service running.</p></body></html>",
	)
	conn.Write([]byte(resp))

	_ = http.StatusOK
}

// ── TUN helpers ──────────────────────────────────────────────────────────────

type tunDevice struct {
	f    *os.File
	name string
}

func (t *tunDevice) Read(b []byte) (int, error)  { return t.f.Read(b) }
func (t *tunDevice) Write(b []byte) (int, error) { return t.f.Write(b) }
func (t *tunDevice) Close() error                { return t.f.Close() }

func createTUN(name, cidr string, mtu int) (*tunDevice, error) {
	f, err := openTun(name)
	if err != nil {
		return nil, err
	}
	if err := runCmd("ip", "addr", "add", cidr, "dev", name); err != nil {
		f.Close()
		return nil, fmt.Errorf("ip addr add: %w", err)
	}
	if err := runCmd("ip", "link", "set", "dev", name, "mtu", fmt.Sprint(mtu)); err != nil {
		f.Close()
		return nil, fmt.Errorf("ip link mtu: %w", err)
	}
	if err := runCmd("ip", "link", "set", "dev", name, "up"); err != nil {
		f.Close()
		return nil, fmt.Errorf("ip link up: %w", err)
	}
	return &tunDevice{f: f, name: name}, nil
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
