// Hardened VPN Client — DPI-resistant
//
// Supports raw TLS and WebSocket transports with uTLS fingerprint mimicry.
//
// # Usage
//
//	# Legacy raw TLS (backward compatible):
//	sudo ./client-hardened \
//	  -server yourdomain.com:443 \
//	  -psk "my-secret"
//
//	# WebSocket + Chrome fingerprint (anti-DPI):
//	sudo ./client-hardened \
//	  -server yourdomain.com:443 \
//	  -psk "my-secret" \
//	  -transport ws \
//	  -fingerprint chrome
//
// # Connection Flow (WebSocket transport)
//
//  1. TCP connection to server on port 443
//  2. uTLS handshake with Chrome/Firefox/Safari fingerprint
//  3. HTTP Upgrade to WebSocket (looks like browser WebSocket)
//  4. Client sends auth token via WS binary frame
//  5. Server replies "OK" via WS binary frame
//  6. Tunnel active: IP packets -> encrypt -> obfuscate -> WS binary -> TLS
package main

import (
	"context"
	"crypto/tls"
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

	"simplevpn/pkg/obfs"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/transport"
	_ "simplevpn/pkg/transport/rawtls"
	_ "simplevpn/pkg/transport/ws"
	"simplevpn/pkg/tunnel"
)

func main() {
	serverAddr := flag.String("server", "", "Server address host:port (required)")
	psk := flag.String("psk", "", "Pre-shared key (required)")
	sni := flag.String("sni", "", "SNI for TLS handshake (optional)")
	tunIP := flag.String("tun-ip", "10.0.0.2/24", "Client TUN IP (CIDR)")
	tunName := flag.String("tun-name", "tun0", "TUN interface name")
	mtu := flag.Int("mtu", 1380, "TUN MTU")
	routeAll := flag.Bool("route-all", false, "Route all traffic through VPN")
	jitterMs := flag.Int("jitter", 5, "Max timing jitter in milliseconds")
	skipVerify := flag.Bool("skip-verify", false, "Skip TLS certificate verification (testing only!)")
	transportType := flag.String("transport", "tls", "Transport type: tls (raw) or ws (WebSocket)")
	fingerprint := flag.String("fingerprint", "none", "TLS fingerprint: none, chrome, firefox, safari")
	flag.Parse()

	if *serverAddr == "" {
		log.Fatal("Specify -server")
	}
	if *psk == "" {
		log.Fatal("Specify -psk")
	}

	// -- Derive keys from PSK --
	keys, err := tunnel.DeriveKeys(*psk)
	if err != nil {
		log.Fatalf("Init crypto: %v", err)
	}
	log.Println("Crypto initialized")

	// -- TUN --
	tun, err := tunnel.CreateTUN(*tunName, *tunIP, *mtu)
	if err != nil {
		log.Fatalf("Create TUN: %v", err)
	}
	defer tun.Close()
	log.Printf("TUN %s: %s", *tunName, *tunIP)

	// -- Resolve SNI --
	host := *sni
	if host == "" {
		h, _, err := net.SplitHostPort(*serverAddr)
		if err == nil {
			host = h
		}
	}

	// -- Transport dial --
	tt := transport.Type(*transportType)
	fp := transport.FingerprintProfile(*fingerprint)

	log.Printf("Transport: type=%s, fingerprint=%s", tt, fp)

	dialer, err := transport.NewDialer(tt, fp)
	if err != nil {
		log.Fatalf("Create transport: %v", err)
	}

	dialCfg := &transport.DialConfig{
		ServerAddr:  *serverAddr,
		SNI:         host,
		Fingerprint: fp,
	}
	if *skipVerify {
		dialCfg.TLSConfig = &tls.Config{
			ServerName:         host,
			InsecureSkipVerify: true,
			MinVersion:         tls.VersionTLS13,
			NextProtos:         []string{"http/1.1"},
		}
	}

	log.Printf("Connecting to %s (transport=%s, SNI=%s) ...", *serverAddr, tt, host)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, err := dialer.Dial(ctx, dialCfg)
	if err != nil {
		log.Fatalf("Transport dial: %v", err)
	}
	defer conn.Close()
	log.Printf("Transport connected to %s", *serverAddr)

	// -- Authentication --
	_, authToken, err := tlsdecoy.GenerateAuthToken(keys.Master)
	if err != nil {
		log.Fatalf("Generate auth token: %v", err)
	}

	if _, err := conn.Write(authToken); err != nil {
		log.Fatalf("Send auth token: %v", err)
	}

	okBuf := make([]byte, 2)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(conn, okBuf); err != nil {
		log.Fatalf("Auth response: %v (wrong PSK or server unavailable)", err)
	}
	conn.SetReadDeadline(time.Time{})

	if string(okBuf) != "OK" {
		log.Fatalf("Server rejected authentication")
	}
	log.Println("Authentication OK")

	// -- Routing --
	if *routeAll {
		setupRouteAll(*serverAddr, *tunName)
	}

	log.Printf("Tunnel active: %s <-> %s", *tunIP, *serverAddr)

	// -- Graceful shutdown --
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("\nShutting down...")
		conn.Close()
		os.Exit(0)
	}()

	// Create tunnel
	tun2 := tunnel.New(keys, conn)

	// -- TUN -> Transport (send to server) --
	go func() {
		buf := make([]byte, tunnel.MaxFrameSize)
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

			if err := tun2.Send(buf[:n]); err != nil {
				log.Printf("Send: %v", err)
				return
			}
		}
	}()

	// -- Transport -> TUN (receive from server) --
	for {
		plaintext, err := tun2.Recv()
		if err != nil {
			log.Printf("Recv: %v", err)
			return
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

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
