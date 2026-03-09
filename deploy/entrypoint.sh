#!/bin/sh
# Set up NAT for VPN clients
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

# Start the VPN server
exec simplevpn-server "$@"
