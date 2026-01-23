#!/bin/bash
# Cerberus WireGuard VPN - Entrypoint Script

set -e

CONFIG_FILE="/etc/wireguard/${WG_INTERFACE}.conf"
DATA_DIR="/data/wireguard"
PRIVATE_KEY_FILE="${DATA_DIR}/privatekey"
PUBLIC_KEY_FILE="${DATA_DIR}/publickey"

echo "Starting Cerberus WireGuard VPN Server..."

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true

# Generate server keys if they don't exist
if [ ! -f "${PRIVATE_KEY_FILE}" ]; then
    echo "Generating WireGuard keys..."
    wg genkey | tee "${PRIVATE_KEY_FILE}" | wg pubkey > "${PUBLIC_KEY_FILE}"
    chmod 600 "${PRIVATE_KEY_FILE}"
fi

PRIVATE_KEY=$(cat "${PRIVATE_KEY_FILE}")
PUBLIC_KEY=$(cat "${PUBLIC_KEY_FILE}")

echo "Server Public Key: ${PUBLIC_KEY}"

# Generate config if it doesn't exist
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Generating WireGuard config..."
    cat > "${CONFIG_FILE}" << EOF
[Interface]
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}
PostUp = ${WG_POST_UP}
PostDown = ${WG_POST_DOWN}

# Peers will be added dynamically via API
EOF
    chmod 600 "${CONFIG_FILE}"
fi

# Load peers from data directory
if [ -d "${DATA_DIR}/peers" ]; then
    for peer_file in "${DATA_DIR}/peers"/*.conf; do
        if [ -f "${peer_file}" ]; then
            echo "Loading peer: ${peer_file}"
            cat "${peer_file}" >> "${CONFIG_FILE}"
        fi
    done
fi

# Start WireGuard interface
echo "Starting WireGuard interface ${WG_INTERFACE}..."
wg-quick up "${WG_INTERFACE}"

# Show status
wg show "${WG_INTERFACE}"

# Start simple HTTP API for management
echo "Starting management API on ${API_LISTEN_ADDR}..."
/scripts/api-server.sh &

# Keep container running and handle signals
trap 'echo "Shutting down..."; wg-quick down ${WG_INTERFACE}; exit 0' SIGTERM SIGINT

# Wait forever
while true; do
    sleep 60
    # Log status periodically
    PEERS=$(wg show "${WG_INTERFACE}" peers | wc -l)
    echo "Active peers: ${PEERS}"
done
