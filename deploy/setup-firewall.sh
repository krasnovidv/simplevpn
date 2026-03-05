#!/bin/bash
# Firewall setup for SimpleVPN server
set -euo pipefail

echo "=== Firewall Setup ==="

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf 2>/dev/null || true

# NAT for VPN clients
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

# Allow VPN port
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow management API (restrict to localhost or specific IPs in production)
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT

# Allow TUN traffic
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

echo "Firewall configured"
echo "  - NAT: 10.0.0.0/24 -> eth0"
echo "  - Ports: 443 (VPN), 8443 (API)"
echo "  - TUN forwarding enabled"
