.PHONY: build test test-all vet lint cover bench cert check clean

build:
	GOOS=linux GOARCH=amd64 go build -o simplevpn-server-hardened ./cmd/server-hardened/
	GOOS=linux GOARCH=amd64 go build -o simplevpn-client-hardened ./cmd/client-hardened/

# Full module test run — includes cmd/ and mobile/vpnlib, not just pkg/.
test-all:
	go test ./...

test:
	go test ./pkg/... -v

vet:
	go vet ./...

# Requires golangci-lint (https://golangci-lint.run). Non-fatal if absent.
lint:
	@command -v golangci-lint >/dev/null 2>&1 && golangci-lint run ./... || echo "golangci-lint not installed; skipping"

cover:
	go test ./... -coverprofile=coverage.out
	go tool cover -func=coverage.out | tail -1

bench:
	go test ./pkg/... -bench=. -benchmem

cert:
	openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=localhost'

# Aggregate quality gate — run before pushing / in CI.
check: vet test-all lint

clean:
	rm -f simplevpn-server-hardened simplevpn-client-hardened cert.pem key.pem coverage.out
