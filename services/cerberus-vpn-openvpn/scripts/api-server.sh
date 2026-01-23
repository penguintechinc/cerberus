#!/bin/bash
# Cerberus OpenVPN - Simple Management API

API_PORT="${API_LISTEN_ADDR#:}"
DATA_DIR="/data/openvpn"
PKI_DIR="${DATA_DIR}/pki"
CLIENTS_DIR="${DATA_DIR}/clients"
EASYRSA="${DATA_DIR}/easy-rsa"

export EASYRSA_PKI="${PKI_DIR}"
export EASYRSA_BATCH=1

mkdir -p "${CLIENTS_DIR}"

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

# Function to generate client config
generate_client_config() {
    local client_name="$1"

    local ca_cert
    ca_cert=$(cat "${PKI_DIR}/ca.crt")
    local client_cert
    client_cert=$(cat "${PKI_DIR}/issued/${client_name}.crt" | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/')
    local client_key
    client_key=$(cat "${PKI_DIR}/private/${client_name}.key")
    local ta_key
    ta_key=$(cat "${PKI_DIR}/ta.key")

    cat << EOF
# Cerberus OpenVPN Client Configuration
# Client: ${client_name}
# Generated: $(date -Iseconds)

client
dev tun
proto ${VPN_PROTO}
remote ${VPN_DOMAIN} ${VPN_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher ${VPN_CIPHER}
auth ${VPN_AUTH}
key-direction 1
verb 3

<ca>
${ca_cert}
</ca>

<cert>
${client_cert}
</cert>

<key>
${client_key}
</key>

<tls-auth>
${ta_key}
</tls-auth>
EOF
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
            if pgrep openvpn &>/dev/null; then
                send_response "200 OK" "text/plain" "ok"
            else
                send_response "503 Service Unavailable" "text/plain" "openvpn not running"
            fi
            ;;

        /api/v1/status)
            local status_file="/var/log/openvpn/status.log"
            local connected=0
            if [ -f "${status_file}" ]; then
                connected=$(grep -c "^CLIENT_LIST" "${status_file}" 2>/dev/null || echo "0")
            fi

            send_response "200 OK" "application/json" "{\"status\":\"running\",\"connected_clients\":${connected},\"proto\":\"${VPN_PROTO}\",\"port\":${VPN_PORT}}"
            ;;

        /api/v1/clients)
            local clients_json="["
            local first=true
            for client_json in "${CLIENTS_DIR}"/*.json; do
                if [ -f "${client_json}" ]; then
                    [ "$first" = "false" ] && clients_json+=","
                    clients_json+=$(cat "${client_json}")
                    first=false
                fi
            done
            clients_json+="]"
            send_response "200 OK" "application/json" "{\"clients\":${clients_json}}"
            ;;

        /api/v1/clients/add)
            if [ "$method" != "POST" ]; then
                send_response "405 Method Not Allowed" "application/json" '{"error":"POST required"}'
                return
            fi

            local client_name
            client_name=$(echo "$body" | jq -r '.name // empty')

            if [ -z "$client_name" ]; then
                send_response "400 Bad Request" "application/json" '{"error":"name required"}'
                return
            fi

            # Check if client exists
            if [ -f "${PKI_DIR}/issued/${client_name}.crt" ]; then
                send_response "409 Conflict" "application/json" '{"error":"client already exists"}'
                return
            fi

            # Generate client certificate
            "${EASYRSA}/easyrsa" --batch build-client-full "${client_name}" nopass

            # Generate client config
            local client_config
            client_config=$(generate_client_config "${client_name}")

            # Save config file
            echo "${client_config}" > "${CLIENTS_DIR}/${client_name}.ovpn"

            # Save client info
            cat > "${CLIENTS_DIR}/${client_name}.json" << EOF
{"name":"${client_name}","created":"$(date -Iseconds)"}
EOF

            # Return config as base64
            local config_b64
            config_b64=$(echo "${client_config}" | base64 -w 0)

            send_response "200 OK" "application/json" "{\"status\":\"created\",\"name\":\"${client_name}\",\"config\":\"${config_b64}\"}"
            ;;

        /api/v1/clients/config/*)
            local client_name="${path#/api/v1/clients/config/}"

            if [ ! -f "${CLIENTS_DIR}/${client_name}.ovpn" ]; then
                send_response "404 Not Found" "application/json" '{"error":"client not found"}'
                return
            fi

            local config
            config=$(cat "${CLIENTS_DIR}/${client_name}.ovpn" | base64 -w 0)
            send_response "200 OK" "application/json" "{\"name\":\"${client_name}\",\"config\":\"${config}\"}"
            ;;

        /api/v1/clients/revoke/*)
            if [ "$method" != "DELETE" ] && [ "$method" != "POST" ]; then
                send_response "405 Method Not Allowed" "application/json" '{"error":"DELETE or POST required"}'
                return
            fi

            local client_name="${path#/api/v1/clients/revoke/}"

            if [ ! -f "${PKI_DIR}/issued/${client_name}.crt" ]; then
                send_response "404 Not Found" "application/json" '{"error":"client not found"}'
                return
            fi

            # Revoke certificate
            "${EASYRSA}/easyrsa" --batch revoke "${client_name}"
            "${EASYRSA}/easyrsa" gen-crl

            # Copy CRL to OpenVPN directory
            cp "${PKI_DIR}/crl.pem" /etc/openvpn/server/

            # Remove client files
            rm -f "${CLIENTS_DIR}/${client_name}.ovpn" "${CLIENTS_DIR}/${client_name}.json"

            send_response "200 OK" "application/json" "{\"status\":\"revoked\",\"name\":\"${client_name}\"}"
            ;;

        /api/v1/ca)
            local ca_cert
            ca_cert=$(cat "${PKI_DIR}/ca.crt" | base64 -w 0)
            send_response "200 OK" "application/json" "{\"ca_cert\":\"${ca_cert}\"}"
            ;;

        *)
            send_response "404 Not Found" "application/json" '{"error":"not found"}'
            ;;
    esac
}

echo "OpenVPN API server listening on port ${API_PORT}"

# Simple HTTP server loop
while true; do
    { handle_request; } | nc -l -p ${API_PORT} -q 1 2>/dev/null || sleep 1
done
