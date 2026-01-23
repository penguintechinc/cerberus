#!/bin/bash

# Cerberus OpenVPN API Tests
# Tests health check, /clients endpoint, /status endpoint, and tunnel status

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8082}"
CONTAINER_NAME="cerberus-vpn-openvpn"
FAILED=0

echo "=== Cerberus OpenVPN API Tests ==="
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

# Test 2: /clients Endpoint
echo "[2/4] Testing /clients endpoint..."
if response=$(curl -s -w "\n%{http_code}" "$BASE_URL/clients" 2>/dev/null); then
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "200" ]; then
    echo "✓ /clients endpoint successful (HTTP $http_code)"
    echo "Response preview: $(echo "$body" | head -c 100)..."
  else
    echo "✗ /clients endpoint failed (HTTP $http_code)"
    echo "Response: $body"
    ((FAILED++))
  fi
else
  echo "✗ /clients request failed"
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

# Test 4: OpenVPN Tunnel Status Check
echo "[4/4] Testing OpenVPN tunnel status..."
if docker exec "$CONTAINER_NAME" pgrep -f "openvpn" > /dev/null 2>&1; then
  echo "✓ OpenVPN daemon is running"
else
  echo "✗ OpenVPN daemon is not running"
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
