#!/bin/bash

# Cerberus IPSec VPN API Tests
# Tests health check, /connections endpoint, /status endpoint, and charon status

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8081}"
CONTAINER_NAME="cerberus-vpn-ipsec"
FAILED=0

echo "=== Cerberus IPSec VPN API Tests ==="
echo "Base URL: $BASE_URL"
echo "Container: $CONTAINER_NAME"
echo ""

# Test 1: Health Check
echo "[1/4] Testing health check endpoint..."
if response=$(curl -s -w "\n%{http_code}" "$BASE_URL/health" 2>/dev/null); then
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "200" ]; then
    echo "✓ Health check passed (HTTP $http_code)"
  else
    echo "✗ Health check failed (HTTP $http_code)"
    echo "Response: $body"
    ((FAILED++))
  fi
else
  echo "✗ Health check request failed"
  ((FAILED++))
fi

# Test 2: /connections Endpoint
echo "[2/4] Testing /connections endpoint..."
if response=$(curl -s -w "\n%{http_code}" "$BASE_URL/connections" 2>/dev/null); then
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "200" ]; then
    echo "✓ /connections endpoint successful (HTTP $http_code)"
    echo "Response preview: $(echo "$body" | head -c 100)..."
  else
    echo "✗ /connections endpoint failed (HTTP $http_code)"
    echo "Response: $body"
    ((FAILED++))
  fi
else
  echo "✗ /connections request failed"
  ((FAILED++))
fi

# Test 3: /status Endpoint
echo "[3/4] Testing /status endpoint..."
if response=$(curl -s -w "\n%{http_code}" "$BASE_URL/status" 2>/dev/null); then
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "200" ]; then
    echo "✓ /status endpoint successful (HTTP $http_code)"
    echo "Response preview: $(echo "$body" | head -c 100)..."
  else
    echo "✗ /status endpoint failed (HTTP $http_code)"
    echo "Response: $body"
    ((FAILED++))
  fi
else
  echo "✗ /status request failed"
  ((FAILED++))
fi

# Test 4: Charon Daemon Status Check
echo "[4/4] Testing charon daemon status..."
if docker exec "$CONTAINER_NAME" pgrep -f "charon" > /dev/null 2>&1; then
  echo "✓ Charon daemon is running"
else
  echo "✗ Charon daemon is not running"
  ((FAILED++))
fi

echo ""
echo "=== Test Summary ==="
if [ $FAILED -eq 0 ]; then
  echo "All tests passed!"
  exit 0
else
  echo "$FAILED test(s) failed"
  exit 1
fi
