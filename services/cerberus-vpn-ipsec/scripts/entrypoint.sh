#!/bin/bash
# Cerberus IPSec VPN - Entrypoint Script

set -e

DATA_DIR="/data/ipsec"
CERTS_DIR="${DATA_DIR}/certs"
CA_CERT="${CERTS_DIR}/ca-cert.pem"
CA_KEY="${CERTS_DIR}/ca-key.pem"
SERVER_CERT="${CERTS_DIR}/server-cert.pem"
SERVER_KEY="${CERTS_DIR}/server-key.pem"

echo "Starting Cerberus IPSec VPN Server (StrongSwan)..."

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true

# Create directories
mkdir -p "${CERTS_DIR}" "${DATA_DIR}/users"

# Generate CA and server certificates if they don't exist
if [ ! -f "${CA_CERT}" ]; then
    echo "Generating CA certificate..."

    # Generate CA key
    ipsec pki --gen --type rsa --size 4096 --outform pem > "${CA_KEY}"
    chmod 600 "${CA_KEY}"

    # Generate CA certificate
    ipsec pki --self --ca --lifetime 3650 \
        --in "${CA_KEY}" \
        --type rsa \
        --dn "CN=Cerberus VPN CA, O=Cerberus NGFW" \
        --outform pem > "${CA_CERT}"

    # Copy to StrongSwan directories
    cp "${CA_CERT}" /etc/ipsec.d/cacerts/
fi

if [ ! -f "${SERVER_CERT}" ]; then
    echo "Generating server certificate..."

    # Generate server key
    ipsec pki --gen --type rsa --size 4096 --outform pem > "${SERVER_KEY}"
    chmod 600 "${SERVER_KEY}"

    # Generate server certificate
    ipsec pki --pub --in "${SERVER_KEY}" --type rsa |
        ipsec pki --issue --lifetime 730 \
            --cacert "${CA_CERT}" \
            --cakey "${CA_KEY}" \
            --dn "CN=${VPN_DOMAIN}, O=Cerberus NGFW" \
            --san "${VPN_DOMAIN}" \
            --san "@${VPN_DOMAIN}" \
            --flag serverAuth --flag ikeIntermediate \
            --outform pem > "${SERVER_CERT}"

    # Copy to StrongSwan directories
    cp "${SERVER_CERT}" /etc/ipsec.d/certs/
    cp "${SERVER_KEY}" /etc/ipsec.d/private/
fi

# Generate ipsec.conf
cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=@${VPN_DOMAIN}
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=${VPN_SUBNET}
    rightdns=${VPN_DNS}
    rightsendcert=never
    eap_identity=%identity
    ike=chacha20poly1305-sha512-curve25519-prfsha512,aes256gcm16-sha384-prfsha384-ecp384,aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=chacha20poly1305-sha512,aes256gcm16-ecp384,aes256-sha256,aes256-sha1,3des-sha1!
EOF

# Generate ipsec.secrets with users
cat > /etc/ipsec.secrets << EOF
: RSA "server-key.pem"
EOF

# Load existing users
if [ -d "${DATA_DIR}/users" ]; then
    for user_file in "${DATA_DIR}/users"/*.secret; do
        if [ -f "${user_file}" ]; then
            cat "${user_file}" >> /etc/ipsec.secrets
        fi
    done
fi

chmod 600 /etc/ipsec.secrets

# Configure NAT
iptables -t nat -A POSTROUTING -s ${VPN_SUBNET} -o eth0 -m policy --dir out --pol ipsec -j ACCEPT
iptables -t nat -A POSTROUTING -s ${VPN_SUBNET} -o eth0 -j MASQUERADE

# Start StrongSwan
echo "Starting StrongSwan..."
ipsec start --nofork &
IPSEC_PID=$!

sleep 3

# Show status
ipsec statusall

# Start simple API server
/scripts/api-server.sh &

# Handle signals
trap 'echo "Shutting down..."; ipsec stop; exit 0' SIGTERM SIGINT

# Wait for StrongSwan
wait $IPSEC_PID
