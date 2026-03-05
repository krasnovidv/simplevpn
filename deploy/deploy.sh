#!/bin/bash
# SimpleVPN Server deployment script
# Usage: ./deploy.sh [domain] [email]

set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "Usage: $0 <domain> <email>"
    echo "  domain - your server domain (e.g., vpn.example.com)"
    echo "  email  - email for Let's Encrypt"
    exit 1
fi

echo "=== SimpleVPN Deployment ==="
echo "Domain: $DOMAIN"
echo "Email:  $EMAIL"

# Create config directory
mkdir -p config

# Generate PSK if not exists
if [ ! -f config/server.yaml ]; then
    PSK=$(openssl rand -hex 32)
    API_TOKEN=$(openssl rand -hex 16)

    cat > config/server.yaml <<EOF
listen: ":443"
psk: "${PSK}"
cert: "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
key: "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

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

# Get TLS certificate
echo ""
echo "=== Getting TLS certificate ==="
DOMAIN="$DOMAIN" EMAIL="$EMAIL" docker compose --profile setup run --rm certbot

# Start server
echo ""
echo "=== Starting VPN server ==="
docker compose up -d vpn-server

echo ""
echo "=== Deployment complete ==="
echo "VPN server running on ${DOMAIN}:443"
echo "Management API on ${DOMAIN}:8443"
