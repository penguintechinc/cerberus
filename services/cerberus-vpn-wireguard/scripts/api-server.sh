#!/bin/bash
# Cerberus WireGuard VPN - Simple Management API
# Lightweight HTTP server using socat/nc

API_PORT="${API_LISTEN_ADDR#:}"
DATA_DIR="/data/wireguard"
PEERS_DIR="${DATA_DIR}/peers"
CONFIG_FILE="/etc/wireguard/${WG_INTERFACE}.conf"

mkdir -p "${PEERS_DIR}"

# Function to send HTTP response
send_response() {
    local status="$1"
    local content_type="${2:-application/json}"
    local body="$3"
    local content_length=${#body}

    echo -e "HTTP/1.1 ${status}\r"
    echo -e "Content-Type: ${content_type}\r"
    echo -e "Content-Length: ${content_length}\r"
    echo -e "Connection: close\r"
    echo -e "\r"
    echo -n "${body}"
}

# Function to handle requests
handle_request() {
    local method path version
    read -r method path version

    # Read headers
    while read -r line; do
        line="${line%%$'\r'}"
        [ -z "$line" ] && break
    done

    # Read body for POST
    local body=""
    if [ "$method" = "POST" ]; then
        read -t 1 body || true
    fi

    case "$path" in
        /healthz)
            if wg show "${WG_INTERFACE}" &>/dev/null; then
                send_response "200 OK" "text/plain" "ok"
            else
                send_response "503 Service Unavailable" "text/plain" "wireguard not running"
            fi
            ;;

        /api/v1/status)
            local status
            status=$(wg show "${WG_INTERFACE}" 2>&1 | head -20)
            local peers
            peers=$(wg show "${WG_INTERFACE}" peers 2>/dev/null | wc -l)
            local pubkey
            pubkey=$(cat "${DATA_DIR}/publickey" 2>/dev/null)

            send_response "200 OK" "application/json" "{\"interface\":\"${WG_INTERFACE}\",\"public_key\":\"${pubkey}\",\"peer_count\":${peers}}"
            ;;

        /api/v1/peers)
            local peers_json="["
            local first=true
            for peer_file in "${PEERS_DIR}"/*.json; do
                if [ -f "${peer_file}" ]; then
                    [ "$first" = "false" ] && peers_json+=","
                    peers_json+=$(cat "${peer_file}")
                    first=false
                fi
            done
            peers_json+="]"
            send_response "200 OK" "application/json" "{\"peers\":${peers_json}}"
            ;;

        /api/v1/peers/add)
            if [ "$method" != "POST" ]; then
                send_response "405 Method Not Allowed" "application/json" '{"error":"POST required"}'
                return
            fi

            # Parse JSON body for peer name
            local peer_name
            peer_name=$(echo "$body" | jq -r '.name // empty')
            if [ -z "$peer_name" ]; then
                send_response "400 Bad Request" "application/json" '{"error":"name required"}'
                return
            fi

            # Generate peer keys
            local peer_privkey peer_pubkey
            peer_privkey=$(wg genkey)
            peer_pubkey=$(echo "$peer_privkey" | wg pubkey)

            # Allocate IP (simple increment)
            local base_ip="${WG_ADDRESS%/*}"
            local base_net="${base_ip%.*}"
            local existing_count
            existing_count=$(ls "${PEERS_DIR}"/*.conf 2>/dev/null | wc -l)
            local peer_ip="${base_net}.$((existing_count + 2))"

            # Get server info
            local server_pubkey
            server_pubkey=$(cat "${DATA_DIR}/publickey")
            local server_endpoint="${WG_ENDPOINT:-$(hostname -I | awk '{print $1}'):${WG_PORT}}"

            # Create peer config for server
            local peer_conf="${PEERS_DIR}/${peer_name}.conf"
            cat > "${peer_conf}" << EOF

[Peer]
# ${peer_name}
PublicKey = ${peer_pubkey}
AllowedIPs = ${peer_ip}/32
EOF

            # Create peer JSON info
            cat > "${PEERS_DIR}/${peer_name}.json" << EOF
{"name":"${peer_name}","public_key":"${peer_pubkey}","allowed_ips":"${peer_ip}/32","created":"$(date -Iseconds)"}
EOF

            # Add peer to running config
            wg set "${WG_INTERFACE}" peer "${peer_pubkey}" allowed-ips "${peer_ip}/32"

            # Create client config
            local client_config="[Interface]
PrivateKey = ${peer_privkey}
Address = ${peer_ip}/32
DNS = ${WG_DNS}

[Peer]
PublicKey = ${server_pubkey}
AllowedIPs = ${WG_ALLOWED_IPS}
Endpoint = ${server_endpoint}
PersistentKeepalive = ${WG_PERSISTENT_KEEPALIVE}"

            # Generate QR code as base64
            local qr_base64
            qr_base64=$(echo "${client_config}" | qrencode -t PNG -o - | base64 -w 0)

            send_response "200 OK" "application/json" "{\"name\":\"${peer_name}\",\"public_key\":\"${peer_pubkey}\",\"address\":\"${peer_ip}/32\",\"client_config\":\"$(echo "$client_config" | base64 -w 0)\",\"qr_code\":\"${qr_base64}\"}"
            ;;

        /api/v1/peers/remove/*)
            if [ "$method" != "DELETE" ] && [ "$method" != "POST" ]; then
                send_response "405 Method Not Allowed" "application/json" '{"error":"DELETE or POST required"}'
                return
            fi

            local peer_name="${path#/api/v1/peers/remove/}"
            local peer_json="${PEERS_DIR}/${peer_name}.json"

            if [ ! -f "${peer_json}" ]; then
                send_response "404 Not Found" "application/json" '{"error":"peer not found"}'
                return
            fi

            local peer_pubkey
            peer_pubkey=$(jq -r '.public_key' "${peer_json}")

            # Remove from running config
            wg set "${WG_INTERFACE}" peer "${peer_pubkey}" remove

            # Remove files
            rm -f "${PEERS_DIR}/${peer_name}.conf" "${PEERS_DIR}/${peer_name}.json"

            send_response "200 OK" "application/json" "{\"status\":\"removed\",\"name\":\"${peer_name}\"}"
            ;;

        *)
            send_response "404 Not Found" "application/json" '{"error":"not found"}'
            ;;
    esac
}

echo "WireGuard API server listening on port ${API_PORT}"

# Simple HTTP server using socat
while true; do
    echo "Waiting for connections..."
    socat TCP-LISTEN:${API_PORT},reuseaddr,fork EXEC:"/scripts/api-server.sh handle" 2>/dev/null || {
        # Fallback: use netcat if socat not available
        while true; do
            { handle_request; } | nc -l -p ${API_PORT} -q 1
        done
    }
done
