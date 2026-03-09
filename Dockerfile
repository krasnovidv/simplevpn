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
FROM alpine:3.19

RUN apk add --no-cache \
    iptables \
    iproute2 \
    ca-certificates

COPY --from=builder /bin/simplevpn-server /usr/local/bin/simplevpn-server
COPY deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default config location
VOLUME ["/etc/simplevpn"]

# VPN port
EXPOSE 443/tcp
# Management API port
EXPOSE 8443/tcp

ENTRYPOINT ["entrypoint.sh"]
CMD ["-config", "/etc/simplevpn/server.yaml"]
