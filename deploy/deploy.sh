#!/bin/bash
# SimpleVPN Server deployment script
# Usage: ./deploy.sh [domain] [email]

set -euo pipefail

HOST="${1:-}"
MODE="${2:-ip}"  # "ip" or "domain"
EMAIL="${3:-}"

if [ -z "$HOST" ]; then
    echo "Usage: $0 <ip-or-domain> [mode] [email]"
    echo "  mode: 'ip' (self-signed, default) or 'domain' (Let's Encrypt)"
    echo "  email: required for domain mode"
    exit 1
fi

echo "=== SimpleVPN Deployment ==="
echo "Host: $HOST"
echo "Mode: $MODE"

# Create config directory
mkdir -p config certs

# Generate self-signed cert for IP mode
if [ "$MODE" = "ip" ]; then
    if [ ! -f certs/server.crt ]; then
        echo ""
        echo "=== Generating self-signed TLS certificate ==="
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout certs/server.key -out certs/server.crt \
            -days 3650 -nodes \
            -subj "/CN=${HOST}" \
            -addext "subjectAltName=IP:${HOST}"
        echo "Self-signed cert created"
    fi
    CERT_PATH="/etc/simplevpn/certs/server.crt"
    KEY_PATH="/etc/simplevpn/certs/server.key"
else
    if [ -z "$EMAIL" ]; then
        echo "Error: email required for domain mode"
        exit 1
    fi
    CERT_PATH="/etc/letsencrypt/live/${HOST}/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/${HOST}/privkey.pem"
fi

# Generate PSK if not exists
if [ ! -f config/server.yaml ]; then
    PSK=$(openssl rand -hex 32)
    API_TOKEN=$(openssl rand -hex 16)

    cat > config/server.yaml <<EOF
listen: ":443"
psk: "${PSK}"
cert: "${CERT_PATH}"
key: "${KEY_PATH}"

tun_ip: "10.0.0.1/24"
tun_name: "tun0"
mtu: 1380

log_level: "info"

api:
  enabled: true
  listen: ":8443"
  bearer_token: "${API_TOKEN}"
EOF

    echo "Config created: config/server.yaml"
    echo "PSK: ${PSK}"
    echo "API Token: ${API_TOKEN}"
    echo ""
    echo "SAVE THESE VALUES — they won't be shown again!"
else
    echo "Config already exists: config/server.yaml"
fi

# Setup firewall
bash "$(dirname "$0")/setup-firewall.sh"

# Get TLS certificate (domain mode only)
if [ "$MODE" = "domain" ]; then
    echo ""
    echo "=== Getting TLS certificate ==="
    DOMAIN="$HOST" EMAIL="$EMAIL" docker compose --profile setup run --rm certbot
fi

# Start server
echo ""
echo "=== Starting VPN server ==="
docker compose up -d --build vpn-server

echo ""
echo "=== Deployment complete ==="
echo "VPN server running on ${HOST}:443"
echo "Management API on ${HOST}:8443"
