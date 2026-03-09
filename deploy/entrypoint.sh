#!/bin/sh
set -e

CONFIG_DIR="/etc/simplevpn"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
USERS_FILE="$CONFIG_DIR/users.yaml"

# Set up NAT for VPN clients
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

# Generate server_key on first run if config doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] First run: generating config..."

    SERVER_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '=+/' | head -c 32)
    API_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=+/' | head -c 32)

    cat > "$CONFIG_FILE" <<EOF
listen: ":443"
server_key: "$SERVER_KEY"
users_file: "$USERS_FILE"
cert: "$CONFIG_DIR/certs/cert.pem"
key: "$CONFIG_DIR/certs/key.pem"
tun_ip: "10.0.0.1/24"
tun_name: "tun0"
mtu: 1380
api:
  enabled: true
  listen: ":8443"
  bearer_token: "$API_TOKEN"
log_level: "info"
EOF

    echo "[entrypoint] Config generated: $CONFIG_FILE"

    # Write secrets to a file with restricted permissions (not to stdout/docker logs)
    SECRETS_FILE="$CONFIG_DIR/.secrets"
    cat > "$SECRETS_FILE" <<SECRETS
server_key=$SERVER_KEY
api_token=$API_TOKEN
SECRETS
    chmod 600 "$SECRETS_FILE"
    echo "[entrypoint] Secrets saved to $SECRETS_FILE (chmod 600)"
    echo "[entrypoint] Read secrets: cat $SECRETS_FILE"
fi

# Create empty users file if it doesn't exist
if [ ! -f "$USERS_FILE" ]; then
    echo "users: []" > "$USERS_FILE"
    echo "[entrypoint] Empty users file created: $USERS_FILE"
    echo "[entrypoint] Add users via API: POST /api/users with {\"username\":\"...\",\"password\":\"...\"}"
fi

# Start the VPN server
exec simplevpn-server -config "$CONFIG_FILE" "$@"
