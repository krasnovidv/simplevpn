.PHONY: build test bench cert clean

build:
	GOOS=linux GOARCH=amd64 go build -o simplevpn-server-hardened ./cmd/server-hardened/
	GOOS=linux GOARCH=amd64 go build -o simplevpn-client-hardened ./cmd/client-hardened/

test:
	go test ./pkg/... -v

bench:
	go test ./pkg/... -bench=. -benchmem

cert:
	openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=localhost'

clean:
	rm -f simplevpn-server-hardened simplevpn-client-hardened cert.pem key.pem
