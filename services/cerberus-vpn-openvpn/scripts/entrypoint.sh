#!/bin/bash
# Cerberus OpenVPN - Entrypoint Script

set -e

DATA_DIR="/data/openvpn"
PKI_DIR="${DATA_DIR}/pki"
CLIENTS_DIR="${DATA_DIR}/clients"
SERVER_CONF="/etc/openvpn/server/server.conf"

echo "Starting Cerberus OpenVPN Server..."

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true

# Create directories
mkdir -p "${PKI_DIR}" "${CLIENTS_DIR}"

# Initialize PKI if it doesn't exist
if [ ! -f "${PKI_DIR}/ca.crt" ]; then
    echo "Initializing PKI..."

    # Set up Easy-RSA
    export EASYRSA="${DATA_DIR}/easy-rsa"
    export EASYRSA_PKI="${PKI_DIR}"
    export EASYRSA_BATCH=1
    export EASYRSA_REQ_CN="Cerberus VPN CA"
    export EASYRSA_REQ_ORG="Cerberus NGFW"
    export EASYRSA_ALGO=ec
    export EASYRSA_CURVE=secp384r1
    export EASYRSA_DIGEST=sha384
    export EASYRSA_CA_EXPIRE=3650
    export EASYRSA_CERT_EXPIRE=730

    # Copy easy-rsa
    cp -r /usr/share/easy-rsa "${EASYRSA}"

    # Initialize PKI
    "${EASYRSA}/easyrsa" init-pki

    # Build CA (non-interactive)
    "${EASYRSA}/easyrsa" --batch build-ca nopass

    # Generate server certificate
    "${EASYRSA}/easyrsa" --batch build-server-full server nopass

    # Generate DH parameters
    "${EASYRSA}/easyrsa" gen-dh

    # Generate TLS auth key
    openvpn --genkey secret "${PKI_DIR}/ta.key"

    echo "PKI initialized successfully"
fi

# Generate server config
cat > "${SERVER_CONF}" << EOF
# Cerberus OpenVPN Server Configuration
port ${VPN_PORT}
proto ${VPN_PROTO}
dev tun
topology subnet

# Certificates
ca ${PKI_DIR}/ca.crt
cert ${PKI_DIR}/issued/server.crt
key ${PKI_DIR}/private/server.key
dh ${PKI_DIR}/dh.pem
tls-auth ${PKI_DIR}/ta.key 0

# Network
server ${VPN_SUBNET} ${VPN_NETMASK}
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $(echo ${VPN_DNS} | cut -d',' -f1)"
push "dhcp-option DNS $(echo ${VPN_DNS} | cut -d',' -f2)"

# Security
cipher ${VPN_CIPHER}
auth ${VPN_AUTH}
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384

# Client configuration directory
client-config-dir /etc/openvpn/ccd

# Logging
status /var/log/openvpn/status.log
log-append /var/log/openvpn/openvpn.log
verb 3

# Performance
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup

# Allow duplicate connections
duplicate-cn

# Management interface
management 127.0.0.1 7505
EOF

# Create log directory
mkdir -p /var/log/openvpn

# Configure NAT
iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}/${VPN_NETMASK} -o eth0 -j MASQUERADE
iptables -A INPUT -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -o tun+ -j ACCEPT

# Start OpenVPN
echo "Starting OpenVPN..."
openvpn --config "${SERVER_CONF}" &
OVPN_PID=$!

sleep 3

# Show status
echo "OpenVPN started with PID ${OVPN_PID}"

# Start API server
/scripts/api-server.sh &

# Handle signals
trap 'echo "Shutting down..."; kill ${OVPN_PID}; exit 0' SIGTERM SIGINT

# Wait for OpenVPN
wait $OVPN_PID
