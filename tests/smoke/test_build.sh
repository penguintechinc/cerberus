#!/usr/bin/env bash
# Smoke Test: Verify all containers build successfully
set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

PASS=0
FAIL=0

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

echo -e "${YELLOW}Smoke Test: Container Builds${RESET}"
echo "─────────────────────────────"

cd "$(git rev-parse --show-toplevel)"

check "Flask backend image builds" \
    docker build -t cerberus-api:smoke-test services/flask-backend/

check "Go backend image builds" \
    docker build -t cerberus-xdp:smoke-test services/go-backend/

check "WebUI image builds" \
    docker build -t cerberus-webui:smoke-test services/webui/

echo ""
echo "─────────────────────────────"
echo -e "Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}"

# Cleanup test images
docker rmi cerberus-api:smoke-test cerberus-xdp:smoke-test cerberus-webui:smoke-test 2>/dev/null || true

[ "$FAIL" -eq 0 ]
