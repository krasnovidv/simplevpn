// Hardened VPN Server — DPI-resistant
//
// Supports configuration via YAML file and/or CLI flags.
// CLI flags override config file values.
//
// # Usage
//
//	# With config file:
//	sudo ./server-hardened -config server.yaml
//
//	# With CLI flags (backward compatible):
//	sudo ./server-hardened -psk "my-secret" -cert cert.pem -key key.pem
//
//	# Mix: config file + flag overrides:
//	sudo ./server-hardened -config server.yaml -listen :8443
package main

import (
	"crypto/tls"
	"flag"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"simplevpn/pkg/api"
	"simplevpn/pkg/config"
	"simplevpn/pkg/tlsdecoy"
	"simplevpn/pkg/tunnel"
)

func main() {
	// CLI flags
	configFile := flag.String("config", "", "YAML config file path")
	listenAddr := flag.String("listen", "", "TCP listen address (TLS)")
	psk := flag.String("psk", "", "Pre-shared key")
	certFile := flag.String("cert", "", "TLS certificate")
	keyFile := flag.String("key", "", "TLS private key")
	tunIP := flag.String("tun-ip", "", "TUN interface IP (CIDR)")
	tunName := flag.String("tun-name", "", "TUN interface name")
	mtu := flag.Int("mtu", 0, "MTU (reduced for TLS overhead)")
	flag.Parse()

	// Load config: file first, then CLI overrides
	var cfg *config.ServerConfig
	var err error

	if *configFile != "" {
		cfg, err = config.Load(*configFile)
		if err != nil {
			log.Fatalf("Load config: %v", err)
		}
	} else {
		cfg = config.Defaults()
	}

	// CLI flags override config file values
	if *listenAddr != "" {
		cfg.Listen = *listenAddr
	}
	if *psk != "" {
		cfg.PSK = *psk
	}
	if *certFile != "" {
		cfg.CertFile = *certFile
	}
	if *keyFile != "" {
		cfg.KeyFile = *keyFile
	}
	if *tunIP != "" {
		cfg.TunIP = *tunIP
	}
	if *tunName != "" {
		cfg.TunName = *tunName
	}
	if *mtu > 0 {
		cfg.MTU = *mtu
	}

	if err := cfg.Validate(); err != nil {
		log.Fatalf("Config validation: %v", err)
	}

	// -- Derive keys from PSK --
	keys, err := tunnel.DeriveKeys(cfg.PSK)
	if err != nil {
		log.Fatalf("Init crypto: %v", err)
	}
	log.Println("Crypto initialized")

	// -- TUN interface --
	tun, err := tunnel.CreateTUN(cfg.TunName, cfg.TunIP, cfg.MTU)
	if err != nil {
		log.Fatalf("Create TUN: %v", err)
	}
	defer tun.Close()
	log.Printf("TUN %s up: %s", cfg.TunName, cfg.TunIP)

	// -- TLS config --
	tlsCfg, err := tlsdecoy.NewDecoyTLSConfig(cfg.CertFile, cfg.KeyFile)
	if err != nil {
		log.Fatalf("TLS config: %v", err)
	}
	log.Printf("TLS 1.3 configured (cert: %s)", cfg.CertFile)

	// -- TLS listener --
	tlsListener, err := tls.Listen("tcp", cfg.Listen, tlsCfg)
	if err != nil {
		log.Fatalf("Listen %s: %v", cfg.Listen, err)
	}
	defer tlsListener.Close()
	log.Printf("Listening on %s (TLS)", cfg.Listen)

	// -- Management API --
	var apiServer *api.Server
	if cfg.API.Enabled {
		apiServer = api.NewServer(cfg, "0.1.0")
		apiServer.RegisterWebUI()
		go func() {
			if err := apiServer.ListenAndServeTLS(); err != nil {
				log.Printf("API server error: %v", err)
			}
		}()
	}

	// -- Graceful shutdown --
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("\nShutting down...")
		if apiServer != nil {
			apiServer.Shutdown()
		}
		tlsListener.Close()
		os.Exit(0)
	}()

	// Channel for active client tunnel (TUN → client)
	activeTunnel := make(chan *tunnel.Tunnel, 1)
	var current *tunnel.Tunnel

	go func() {
		buf := make([]byte, tunnel.MaxFrameSize)
		for {
			select {
			case t := <-activeTunnel:
				current = t
			default:
			}

			if current == nil {
				select {
				case t := <-activeTunnel:
					current = t
				case <-time.After(100 * time.Millisecond):
					continue
				}
			}

			n, readErr := tun.Read(buf)
			if readErr != nil {
				log.Printf("TUN read: %v", readErr)
				return
			}

			if sendErr := current.Send(buf[:n]); sendErr != nil {
				log.Printf("Send to client: %v", sendErr)
				current = nil
			}
		}
	}()

	// -- Accept loop --
	for {
		conn, err := tlsListener.Accept()
		if err != nil {
			log.Printf("Accept: %v", err)
			return
		}

		go serveConnection(conn, keys, tun, activeTunnel)
	}
}

func serveConnection(
	conn net.Conn,
	keys *tunnel.Keys,
	tun *tunnel.TunDevice,
	activeTunnel chan<- *tunnel.Tunnel,
) {
	defer conn.Close()
	remoteAddr := conn.RemoteAddr().String()

	// Read auth token (56 bytes)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	authBuf := make([]byte, tlsdecoy.AuthTokenSize)
	if _, err := io.ReadFull(conn, authBuf); err != nil {
		log.Printf("Auth timeout from %s -> decoy mode", remoteAddr)
		serveDecoy(conn)
		return
	}
	conn.SetReadDeadline(time.Time{})

	if !tlsdecoy.VerifyAuthToken(keys.Master, authBuf) {
		log.Printf("Auth FAILED from %s -> decoy mode", remoteAddr)
		serveDecoy(conn)
		return
	}

	log.Printf("VPN client authenticated: %s", remoteAddr)
	conn.Write([]byte("OK"))

	tun2 := tunnel.New(keys, conn)
	activeTunnel <- tun2

	// Read packets from client
	for {
		plaintext, err := tun2.Recv()
		if err != nil {
			log.Printf("Client %s disconnected: %v", remoteAddr, err)
			return
		}

		if _, err := tun.Write(plaintext); err != nil {
			log.Printf("TUN write: %v", err)
		}
	}
}

func serveDecoy(conn net.Conn) {
	resp := "HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html; charset=utf-8\r\n" +
		"Server: nginx/1.24.0\r\n" +
		"Connection: close\r\n\r\n" +
		"<html><body><h1>Welcome</h1><p>Service running.</p></body></html>"
	conn.Write([]byte(resp))
}
