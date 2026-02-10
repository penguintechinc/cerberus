#!/usr/bin/env bash
# Smoke Test: Verify basic API CRUD operations
set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

PASS=0
FAIL=0

API_URL="${API_URL:-http://localhost:5000/api/v1}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-changeme123}"

check() {
    local name="$1"
    local expected_status="$2"
    shift 2
    local actual_status
    actual_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$@")
    if [ "$actual_status" = "$expected_status" ]; then
        echo -e "  ${GREEN}✓${RESET} ${name} (HTTP ${actual_status})"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${name} (expected ${expected_status}, got ${actual_status})"
        ((FAIL++))
    fi
}

echo -e "${YELLOW}Smoke Test: API Operations${RESET}"
echo "─────────────────────────────"

# Login
echo "Authentication:"
LOGIN_RESPONSE=$(curl -s --max-time 10 \
    -X POST "${API_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}")

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -n "$ACCESS_TOKEN" ]; then
    echo -e "  ${GREEN}✓${RESET} Login returns access token"
    ((PASS++))
else
    echo -e "  ${RED}✗${RESET} Login failed to return access token"
    ((FAIL++))
fi

# Auth endpoints
check "GET /auth/me" "200" \
    -X GET "${API_URL}/auth/me" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}"

check "POST /auth/login (bad creds)" "401" \
    -X POST "${API_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"bad@example.com","password":"wrong"}'

# User endpoints (admin only)
echo ""
echo "User Management:"
check "GET /users (admin)" "200" \
    -X GET "${API_URL}/users" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}"

check "GET /users/roles" "200" \
    -X GET "${API_URL}/users/roles" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}"

check "GET /users (no auth)" "401" \
    -X GET "${API_URL}/users"

# Go backend
echo ""
echo "Go Backend:"
GO_URL="${GO_API_URL:-http://localhost:8080}"
check "GET /api/v1/status" "200" \
    -X GET "${GO_URL}/api/v1/status"

check "GET /api/v1/hello" "200" \
    -X GET "${GO_URL}/api/v1/hello"

echo ""
echo "─────────────────────────────"
echo -e "Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}"

[ "$FAIL" -eq 0 ]
