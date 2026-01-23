#!/bin/bash
# Cerberus IPSec VPN - Simple Management API

API_PORT="${API_LISTEN_ADDR#:}"
DATA_DIR="/data/ipsec"
USERS_DIR="${DATA_DIR}/users"

mkdir -p "${USERS_DIR}"

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
            if ipsec status &>/dev/null; then
                send_response "200 OK" "text/plain" "ok"
            else
                send_response "503 Service Unavailable" "text/plain" "ipsec not running"
            fi
            ;;

        /api/v1/status)
            local status
            status=$(ipsec statusall 2>&1 | head -30)
            local connections
            connections=$(ipsec status 2>/dev/null | grep -c "ESTABLISHED" || echo "0")

            send_response "200 OK" "application/json" "{\"status\":\"running\",\"active_connections\":${connections},\"domain\":\"${VPN_DOMAIN}\"}"
            ;;

        /api/v1/users)
            local users_json="["
            local first=true
            for user_file in "${USERS_DIR}"/*.json; do
                if [ -f "${user_file}" ]; then
                    [ "$first" = "false" ] && users_json+=","
                    users_json+=$(cat "${user_file}")
                    first=false
                fi
            done
            users_json+="]"
            send_response "200 OK" "application/json" "{\"users\":${users_json}}"
            ;;

        /api/v1/users/add)
            if [ "$method" != "POST" ]; then
                send_response "405 Method Not Allowed" "application/json" '{"error":"POST required"}'
                return
            fi

            local username password
            username=$(echo "$body" | jq -r '.username // empty')
            password=$(echo "$body" | jq -r '.password // empty')

            if [ -z "$username" ] || [ -z "$password" ]; then
                send_response "400 Bad Request" "application/json" '{"error":"username and password required"}'
                return
            fi

            # Add to secrets file
            echo "${username} : EAP \"${password}\"" > "${USERS_DIR}/${username}.secret"
            echo "${username} : EAP \"${password}\"" >> /etc/ipsec.secrets

            # Save user info (without password)
            cat > "${USERS_DIR}/${username}.json" << EOF
{"username":"${username}","created":"$(date -Iseconds)"}
EOF

            # Reload StrongSwan
            ipsec rereadsecrets

            send_response "200 OK" "application/json" "{\"status\":\"added\",\"username\":\"${username}\"}"
            ;;

        /api/v1/users/remove/*)
            if [ "$method" != "DELETE" ] && [ "$method" != "POST" ]; then
                send_response "405 Method Not Allowed" "application/json" '{"error":"DELETE or POST required"}'
                return
            fi

            local username="${path#/api/v1/users/remove/}"

            if [ ! -f "${USERS_DIR}/${username}.json" ]; then
                send_response "404 Not Found" "application/json" '{"error":"user not found"}'
                return
            fi

            # Remove user files
            rm -f "${USERS_DIR}/${username}.secret" "${USERS_DIR}/${username}.json"

            # Regenerate secrets file
            cat > /etc/ipsec.secrets << EOF
: RSA "server-key.pem"
EOF
            for secret_file in "${USERS_DIR}"/*.secret; do
                [ -f "${secret_file}" ] && cat "${secret_file}" >> /etc/ipsec.secrets
            done

            # Reload StrongSwan
            ipsec rereadsecrets

            send_response "200 OK" "application/json" "{\"status\":\"removed\",\"username\":\"${username}\"}"
            ;;

        /api/v1/ca)
            local ca_cert
            ca_cert=$(cat "${DATA_DIR}/certs/ca-cert.pem" | base64 -w 0)
            send_response "200 OK" "application/json" "{\"ca_cert\":\"${ca_cert}\"}"
            ;;

        *)
            send_response "404 Not Found" "application/json" '{"error":"not found"}'
            ;;
    esac
}

echo "IPSec API server listening on port ${API_PORT}"

# Simple HTTP server loop
while true; do
    { handle_request; } | nc -l -p ${API_PORT} -q 1 2>/dev/null || sleep 1
done
