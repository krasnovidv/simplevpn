# Multi-stage build for SimpleVPN server
# Stage 1: Build
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/simplevpn-server ./cmd/server-hardened/

# Stage 2: Runtime
# alpine:3.19 reached EOL in Nov 2025 (no security patches); pin to a supported
# release. Bump this on each Alpine stable cadence.
FROM alpine:3.22

RUN apk add --no-cache \
    iptables \
    iproute2 \
    ca-certificates \
    wget

COPY --from=builder /bin/simplevpn-server /usr/local/bin/simplevpn-server
COPY deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default config location
VOLUME ["/etc/simplevpn"]

# VPN port
EXPOSE 443/tcp
# Management API port (TLS)
EXPOSE 8443/tcp
# Public HTTP port (join page, APK download)
EXPOSE 8080/tcp

# Liveness probe against the unauthenticated /healthz endpoint on the public
# HTTP port. Lets Docker/orchestrators restart a wedged server.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["entrypoint.sh"]
CMD ["-config", "/etc/simplevpn/server.yaml"]
