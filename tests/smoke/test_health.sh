#!/usr/bin/env bash
# Smoke Test: Verify /healthz endpoints respond correctly
set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

PASS=0
FAIL=0

FLASK_URL="${FLASK_URL:-http://localhost:5000}"
GO_URL="${GO_URL:-http://localhost:8080}"
WEBUI_URL="${WEBUI_URL:-http://localhost:3000}"

check_health() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"

    if curl -sf --max-time "$timeout" "$url" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} ${name} (${url})"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${name} (${url})"
        ((FAIL++))
    fi
}

echo -e "${YELLOW}Smoke Test: Health Endpoints${RESET}"
echo "─────────────────────────────"

check_health "Flask /healthz" "${FLASK_URL}/healthz"
check_health "Flask /readyz" "${FLASK_URL}/readyz"
check_health "Go /healthz" "${GO_URL}/healthz"
check_health "Go /readyz" "${GO_URL}/readyz"
check_health "WebUI /healthz" "${WEBUI_URL}/healthz"

echo ""
echo "─────────────────────────────"
echo -e "Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}"

[ "$FAIL" -eq 0 ]
