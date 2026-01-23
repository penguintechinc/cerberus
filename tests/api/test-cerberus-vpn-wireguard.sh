#!/bin/bash

# Cerberus WireGuard VPN API Tests
# Tests health check, /peers endpoint, /config endpoint, and interface status

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
CONTAINER_NAME="cerberus-vpn-wireguard"
FAILED=0

echo "=== Cerberus WireGuard VPN API Tests ==="
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

# Test 2: /peers Endpoint
echo "[2/4] Testing /peers endpoint..."
if response=$(curl -s -w "\n%{http_code}" "$BASE_URL/peers" 2>/dev/null); then
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "200" ]; then
    echo "✓ /peers endpoint successful (HTTP $http_code)"
    echo "Response preview: $(echo "$body" | head -c 100)..."
  else
    echo "✗ /peers endpoint failed (HTTP $http_code)"
    echo "Response: $body"
    ((FAILED++))
  fi
else
  echo "✗ /peers request failed"
  ((FAILED++))
fi

# Test 3: /config Endpoint
echo "[3/4] Testing /config endpoint..."
if response=$(curl -s -w "\n%{http_code}" "$BASE_URL/config" 2>/dev/null); then
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "200" ]; then
    echo "✓ /config endpoint successful (HTTP $http_code)"
    echo "Response preview: $(echo "$body" | head -c 100)..."
  else
    echo "✗ /config endpoint failed (HTTP $http_code)"
    echo "Response: $body"
    ((FAILED++))
  fi
else
  echo "✗ /config request failed"
  ((FAILED++))
fi

# Test 4: Interface Status Check
echo "[4/4] Testing interface status..."
if docker exec "$CONTAINER_NAME" ip link show wg0 > /dev/null 2>&1; then
  echo "✓ WireGuard interface (wg0) is present"
else
  echo "✗ WireGuard interface (wg0) not found"
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
