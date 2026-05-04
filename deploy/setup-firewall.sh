#!/bin/bash
# Firewall setup for SimpleVPN server
set -euo pipefail

echo "=== Firewall Setup ==="

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf 2>/dev/null || true

# Detect default outbound interface
IFACE=$(ip route | awk '/default/ {print $5; exit}')
IFACE=${IFACE:-eth0}

# NAT for VPN clients
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o "$IFACE" -j MASQUERADE

# MSS clamping — prevents PMTUD black holes (YouTube, large downloads stalling)
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Allow VPN port
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow management API (restrict to localhost or specific IPs in production)
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT

# Allow TUN traffic
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

echo "Firewall configured"
echo "  - NAT: 10.0.0.0/24 -> $IFACE"
echo "  - MSS clamping: enabled"
echo "  - Ports: 443 (VPN), 8443 (API)"
echo "  - TUN forwarding enabled"
