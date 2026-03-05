// Hardened VPN Client — устойчивый к DPI
//
// # Запуск
//
//	sudo ./client-hardened \
//	  -server yourdomain.com:443 \
//	  -psk "мой-супер-секрет" \
//	  -tun-ip 10.0.0.2/24 \
//	  -sni yourdomain.com        # SNI в TLS handshake (домен сервера)
//
// # Что происходит при подключении
//
//  1. TCP соединение к серверу на порт 443
//  2. TLS 1.3 handshake — выглядит как обычный HTTPS
//  3. Клиент отправляет HMAC-аутентификационный токен (56 байт)
//  4. Сервер проверяет токен, отвечает "OK"
//  5. Туннель активен: IP-пакеты -> шифрование -> обфускация -> TLS -> сервер
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
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
	"simplevpn/pkg/tlsdecoy"
)

const maxFrameSize = 65535

func main() {
	serverAddr := flag.String("server", "", "Server address host:port (required)")
	psk        := flag.String("psk", "", "Pre-shared key (required)")
	sni        := flag.String("sni", "", "SNI for TLS handshake (optional)")
	tunIP      := flag.String("tun-ip", "10.0.0.2/24", "Client TUN IP (CIDR)")
	tunName    := flag.String("tun-name", "tun0", "TUN interface name")
	mtu        := flag.Int("mtu", 1380, "TUN MTU")
	routeAll   := flag.Bool("route-all", false, "Route all traffic through VPN")
	jitterMs   := flag.Int("jitter", 5, "Max timing jitter in milliseconds")
	skipVerify := flag.Bool("skip-verify", false, "Skip TLS certificate verification (testing only!)")
	flag.Parse()

	if *serverAddr == "" {
		log.Fatal("Specify -server")
	}
	if *psk == "" {
		log.Fatal("Specify -psk")
	}

	// ── Derive keys (identical to server!) ───────────────────────────────────
	masterKey := sha256.Sum256([]byte(*psk))
	encKey    := sha256.Sum256(append(masterKey[:], []byte("encryption")...))
	obfsKey   := obfs.DeriveObfsKey(sha256.Sum256(append(masterKey[:], []byte("obfuscation")...)))

	ciph, err := crypto.NewCipherFromKey(encKey)
	if err != nil {
		log.Fatalf("Init cipher: %v", err)
	}
	obfuscator := obfs.New(obfsKey)

	log.Println("Crypto initialized")

	// ── TUN ─────────────────────────────────────────────────────────────────
	tun, err := createTUN(*tunName, *tunIP, *mtu)
	if err != nil {
		log.Fatalf("Create TUN: %v", err)
	}
	defer tun.Close()
	log.Printf("TUN %s: %s", *tunName, *tunIP)

	// ── TLS connection ────────────────────────────────────────────────────────
	host := *sni
	if host == "" {
		h, _, err := net.SplitHostPort(*serverAddr)
		if err == nil {
			host = h
		}
	}

	tlsCfg := &tls.Config{
		ServerName:         host,
		InsecureSkipVerify: *skipVerify,
		MinVersion:         tls.VersionTLS13,
		NextProtos:         []string{"h2", "http/1.1"},
	}

	log.Printf("Connecting to %s (TLS SNI: %s)...", *serverAddr, host)

	rawConn, err := net.DialTimeout("tcp", *serverAddr, 10*time.Second)
	if err != nil {
		log.Fatalf("TCP connect: %v", err)
	}

	tlsConn := tls.Client(rawConn, tlsCfg)
	if err := tlsConn.Handshake(); err != nil {
		tlsConn.Close()
		log.Fatalf("TLS handshake: %v", err)
	}
	log.Printf("TLS 1.3 handshake OK")

	defer tlsConn.Close()

	// ── Authentication ────────────────────────────────────────────────────────
	_, authToken, err := tlsdecoy.GenerateAuthToken(masterKey)
	if err != nil {
		log.Fatalf("Generate auth token: %v", err)
	}

	if _, err := tlsConn.Write(authToken); err != nil {
		log.Fatalf("Send auth token: %v", err)
	}

	okBuf := make([]byte, 2)
	tlsConn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(tlsConn, okBuf); err != nil {
		log.Fatalf("Auth response: %v (wrong PSK or server unavailable)", err)
	}
	tlsConn.SetReadDeadline(time.Time{})

	if string(okBuf) != "OK" {
		log.Fatalf("Server rejected authentication")
	}
	log.Println("Authentication OK")

	// ── Routing ─────────────────────────────────────────────────────────────
	if *routeAll {
		setupRouteAll(*serverAddr, *tunName)
	}

	log.Printf("Tunnel active: %s <-> %s", *tunIP, *serverAddr)

	// ── Graceful shutdown ─────────────────────────────────────────────────────
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("\nShutting down...")
		tlsConn.Close()
		os.Exit(0)
	}()

	// ── TUN -> TLS (send to server) ─────────────────────────────────────────
	go func() {
		buf := make([]byte, maxFrameSize)
		encBuf := make([]byte, 0, maxFrameSize+crypto.Overhead)
		obfsBuf := make([]byte, 0, maxFrameSize+crypto.Overhead+obfs.HeaderSize+obfs.MaxPad)

		for {
			n, err := tun.Read(buf)
			if err != nil {
				log.Printf("TUN read: %v", err)
				return
			}

			if *jitterMs > 0 {
				jitter := obfs.TimingJitter(*jitterMs)
				if jitter > 0 {
					time.Sleep(time.Duration(jitter) * time.Millisecond)
				}
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

			if _, err := tlsConn.Write(frame); err != nil {
				log.Printf("TLS write: %v", err)
				return
			}
		}
	}()

	// ── TLS -> TUN (receive from server) ──────────────────────────────────
	lenBuf := make([]byte, 4)
	frameBuf := make([]byte, maxFrameSize+obfs.HeaderSize+obfs.MaxPad)
	decBuf := make([]byte, 0, maxFrameSize)

	for {
		if _, err := io.ReadFull(tlsConn, lenBuf); err != nil {
			log.Printf("Read frame length: %v", err)
			return
		}
		frameLen := binary.BigEndian.Uint32(lenBuf)
		if frameLen > uint32(len(frameBuf)) {
			log.Printf("Frame too large: %d", frameLen)
			return
		}

		if _, err := io.ReadFull(tlsConn, frameBuf[:frameLen]); err != nil {
			log.Printf("Read frame body: %v", err)
			return
		}

		encrypted, err := obfuscator.Unwrap(frameBuf[:frameLen])
		if err != nil {
			log.Printf("Obfs unwrap: %v", err)
			continue
		}

		plaintext, err := ciph.Decrypt(decBuf[:0], encrypted)
		if err != nil {
			log.Printf("Decrypt: %v", err)
			continue
		}

		if _, err := tun.Write(plaintext); err != nil {
			log.Printf("TUN write: %v", err)
		}
	}
}

func setupRouteAll(serverAddr, tunName string) {
	host, _, err := net.SplitHostPort(serverAddr)
	if err != nil {
		return
	}
	gw := defaultGateway()
	if gw != "" {
		runCmd("ip", "route", "add", host+"/32", "via", gw)
	}
	runCmd("ip", "route", "add", "0.0.0.0/1", "dev", tunName)
	runCmd("ip", "route", "add", "128.0.0.0/1", "dev", tunName)
	log.Println("All traffic -> VPN")
}

func defaultGateway() string {
	out, err := exec.Command("ip", "route", "show", "default").Output()
	if err != nil {
		return ""
	}
	var gw string
	fmt.Sscanf(string(out), "default via %s", &gw)
	return gw
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
