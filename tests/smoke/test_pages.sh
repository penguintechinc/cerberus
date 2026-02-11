#!/usr/bin/env bash
# Smoke Test: Verify all WebUI page routes return HTTP 200
# This is a lightweight curl-based check — no browser required.
set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

PASS=0
FAIL=0

WEBUI_URL="${WEBUI_URL:-http://localhost:3000}"

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} ${name}"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${name}"
        ((FAIL++))
    fi
}

check_http_status() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url")
    if [ "$status" = "$expected" ]; then
        echo -e "  ${GREEN}✓${RESET} ${name} (HTTP ${status})"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${name} (HTTP ${status}, expected ${expected})"
        ((FAIL++))
    fi
}

echo -e "${YELLOW}Smoke Test: Page Routes${RESET}"
echo "─────────────────────────────"

# Verify WebUI is reachable first
if ! curl -sf --max-time 5 "${WEBUI_URL}" >/dev/null 2>&1; then
    echo -e "${RED}WebUI is not reachable at ${WEBUI_URL}${RESET}"
    echo -e "${YELLOW}Start services with 'make dev' or 'docker-compose up' first.${RESET}"
    exit 1
fi

echo ""
echo "Public routes:"
check_http_status "GET /login" "${WEBUI_URL}/login"

echo ""
echo "SPA routes (all serve index.html shell):"
check_http_status "GET /" "${WEBUI_URL}/"
check_http_status "GET /firewall" "${WEBUI_URL}/firewall"
check_http_status "GET /ips" "${WEBUI_URL}/ips"
check_http_status "GET /vpn" "${WEBUI_URL}/vpn"
check_http_status "GET /filter" "${WEBUI_URL}/filter"
check_http_status "GET /profile" "${WEBUI_URL}/profile"
check_http_status "GET /settings" "${WEBUI_URL}/settings"
check_http_status "GET /users" "${WEBUI_URL}/users"

echo ""
echo "Health endpoint:"
check_http_status "GET /healthz" "${WEBUI_URL}/healthz"

echo ""
echo "─────────────────────────────"
echo -e "Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}"

[ "$FAIL" -eq 0 ]
