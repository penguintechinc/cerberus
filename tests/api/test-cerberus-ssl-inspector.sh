#!/bin/bash
##############################################################################
# Cerberus SSL Inspector Test Suite
# Purpose: Test Go SSL/TLS MITM proxy endpoints
# Tests: Health, CA cert management, bypass rules, settings, stats
##############################################################################

set -euo pipefail

# Configuration
API_URL="${CERBERUS_SSL_INSPECTOR_URL:-http://localhost:8080}"
PROXY_ADDR="${CERBERUS_SSL_PROXY_ADDR:-localhost:8443}"
API_VERSION="v1"
TEST_DOMAIN="example.com"
TEST_DOMAIN_2="test.example.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

##############################################################################
# Logging Functions
##############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_test() {
    echo -e "\n${BLUE}Test: $1${NC}"
}

##############################################################################
# Utility Functions
##############################################################################

wait_for_api() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for SSL Inspector API to be ready at $API_URL..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$API_URL/healthz" >/dev/null 2>&1; then
            log_success "SSL Inspector API is ready"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    log_error "SSL Inspector API failed to become ready after $max_attempts attempts"
    return 1
}

make_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-}
    local headers=${4:-"Content-Type: application/json"}

    local url="$API_URL/api/$API_VERSION$endpoint"

    if [ -n "$data" ]; then
        curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "$headers" \
            -d "$data"
    else
        curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "$headers"
    fi
}

assert_status() {
    local response=$1
    local expected_status=$2
    local test_name=$3

    local actual_status=$(echo "$response" | tail -1)

    if [ "$actual_status" = "$expected_status" ]; then
        log_success "$test_name (HTTP $actual_status)"
        return 0
    else
        log_error "$test_name (Expected $expected_status, got $actual_status)"
        echo "Response: $(echo "$response" | head -1)"
        return 1
    fi
}

extract_json_field() {
    local json=$1
    local field=$2
    echo "$json" | grep -o "\"$field\":\"[^\"]*\"" | cut -d'"' -f4 2>/dev/null || echo ""
}

##############################################################################
# Health Check Tests
##############################################################################

test_health() {
    log_test "Health Check Endpoint"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/healthz")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Health check endpoint"
        return 0
    else
        log_error "Health check endpoint (HTTP $status)"
        return 1
    fi
}

test_readiness() {
    log_test "Readiness Probe"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/readyz")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Readiness probe"
        return 0
    else
        log_error "Readiness probe (HTTP $status)"
        return 1
    fi
}

##############################################################################
# CA Certificate Tests
##############################################################################

test_get_ca_cert() {
    log_test "Get CA Certificate Info"

    local response=$(make_request GET "/ca")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Get CA certificate info"
        return 0
    else
        log_error "Get CA certificate info (HTTP $status)"
        return 1
    fi
}

test_download_ca_cert() {
    log_test "Download CA Certificate"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/api/$API_VERSION/ca/download" \
        -H "Accept: application/x-pem-file")
    local status=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -1)

    if [ "$status" = "200" ] && echo "$body" | grep -q "BEGIN CERTIFICATE"; then
        log_success "Download CA certificate"
        return 0
    else
        log_error "Download CA certificate (HTTP $status)"
        return 1
    fi
}

test_get_ca_fingerprint() {
    log_test "Get CA Fingerprint"

    local response=$(make_request GET "/ca/fingerprint")
    local status=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -1)

    if [ "$status" = "200" ] && echo "$body" | grep -q "fingerprint"; then
        log_success "Get CA fingerprint"
        return 0
    else
        log_error "Get CA fingerprint (HTTP $status)"
        return 1
    fi
}

test_regenerate_ca() {
    log_test "Regenerate CA Certificate"

    local response=$(make_request POST "/ca/regenerate")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Regenerate CA certificate"
        return 0
    else
        log_error "Regenerate CA certificate (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Bypass Rules Tests
##############################################################################

test_list_bypass_rules() {
    log_test "List Bypass Rules"

    local response=$(make_request GET "/bypass")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "List bypass rules"
        return 0
    else
        log_error "List bypass rules (HTTP $status)"
        return 1
    fi
}

test_add_bypass_rule() {
    log_test "Add Bypass Rule"

    local payload=$(cat <<EOF
{
    "domain": "$TEST_DOMAIN"
}
EOF
)

    local response=$(make_request POST "/bypass" "$payload")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Add bypass rule"
        return 0
    else
        log_error "Add bypass rule (HTTP $status)"
        return 1
    fi
}

test_add_multiple_bypass_rules() {
    log_test "Add Multiple Bypass Rules"

    local payload=$(cat <<EOF
{
    "domain": "$TEST_DOMAIN_2"
}
EOF
)

    local response=$(make_request POST "/bypass" "$payload")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Add multiple bypass rules"
        return 0
    else
        log_error "Add multiple bypass rules (HTTP $status)"
        return 1
    fi
}

test_remove_bypass_rule() {
    log_test "Remove Bypass Rule"

    local response=$(make_request DELETE "/bypass/$TEST_DOMAIN")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Remove bypass rule"
        return 0
    else
        log_error "Remove bypass rule (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Settings Tests
##############################################################################

test_get_settings() {
    log_test "Get Inspection Settings"

    local response=$(make_request GET "/settings")
    local status=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -1)

    if [ "$status" = "200" ] && echo "$body" | grep -q "inspect_https"; then
        log_success "Get inspection settings"
        return 0
    else
        log_error "Get inspection settings (HTTP $status)"
        return 1
    fi
}

test_update_settings() {
    log_test "Update Inspection Settings"

    local payload=$(cat <<EOF
{
    "inspect_https": true,
    "log_connections": true
}
EOF
)

    local response=$(make_request PUT "/settings" "$payload")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Update inspection settings"
        return 0
    else
        log_error "Update inspection settings (HTTP $status)"
        return 1
    fi
}

test_update_settings_partial() {
    log_test "Update Settings (Partial)"

    local payload=$(cat <<EOF
{
    "inspect_https": false
}
EOF
)

    local response=$(make_request PUT "/settings" "$payload")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Update settings partially"
        return 0
    else
        log_error "Update settings partially (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Statistics Tests
##############################################################################

test_get_stats() {
    log_test "Get Proxy Statistics"

    local response=$(make_request GET "/stats")
    local status=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -1)

    if [ "$status" = "200" ] && echo "$body" | grep -q "proxy"; then
        log_success "Get proxy statistics"
        return 0
    else
        log_error "Get proxy statistics (HTTP $status)"
        return 1
    fi
}

test_get_active_connections() {
    log_test "Get Active Connections"

    local response=$(make_request GET "/connections")
    local status=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -1)

    if [ "$status" = "200" ] && echo "$body" | grep -q "connections"; then
        log_success "Get active connections"
        return 0
    else
        log_error "Get active connections (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Metrics Tests
##############################################################################

test_metrics_endpoint() {
    log_test "Prometheus Metrics Endpoint"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/metrics")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Metrics endpoint accessible"
        return 0
    else
        log_error "Metrics endpoint (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Error Handling Tests
##############################################################################

test_invalid_endpoint() {
    log_test "Invalid Endpoint (404 Error)"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/api/$API_VERSION/nonexistent")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "404" ]; then
        log_success "Invalid endpoint returns 404"
        return 0
    else
        log_error "Invalid endpoint (Expected 404, got $status)"
        return 1
    fi
}

test_malformed_json() {
    log_test "Malformed JSON Request"

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/$API_VERSION/bypass" \
        -H "Content-Type: application/json" \
        -d "{invalid json")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "400" ]; then
        log_success "Malformed JSON returns 400"
        return 0
    else
        log_error "Malformed JSON handling (Expected 400, got $status)"
        return 1
    fi
}

test_missing_required_field() {
    log_test "Missing Required Field"

    local payload='{}'

    local response=$(make_request POST "/bypass" "$payload")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "400" ]; then
        log_success "Missing required field returns 400"
        return 0
    else
        log_error "Missing required field (Expected 400, got $status)"
        return 1
    fi
}

##############################################################################
# Performance Benchmark Tests
##############################################################################

test_health_response_time() {
    log_test "Health Check Response Time Benchmark"

    local start=$(date +%s%N)
    curl -s "$API_URL/healthz" >/dev/null 2>&1
    local end=$(date +%s%N)
    local latency=$(( (end - start) / 1000000 ))

    if [ $latency -lt 1000 ]; then
        log_success "Health check latency: ${latency}ms (< 1000ms target)"
        return 0
    else
        log_error "Health check latency: ${latency}ms (exceeded target)"
        return 1
    fi
}

test_stats_response_time() {
    log_test "Stats Endpoint Response Time Benchmark"

    local start=$(date +%s%N)
    curl -s "$API_URL/api/$API_VERSION/stats" >/dev/null 2>&1
    local end=$(date +%s%N)
    local latency=$(( (end - start) / 1000000 ))

    if [ $latency -lt 2000 ]; then
        log_success "Stats endpoint latency: ${latency}ms (< 2000ms target)"
        return 0
    else
        log_error "Stats endpoint latency: ${latency}ms (exceeded target)"
        return 1
    fi
}

##############################################################################
# SSL Proxy Connectivity Test
##############################################################################

test_ssl_proxy_connectivity() {
    log_test "SSL Proxy Connectivity"

    # Try to connect to proxy address (will fail if no tunnel, but tests connectivity)
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/$PROXY_ADDR" 2>/dev/null; then
        log_success "SSL proxy listening on $PROXY_ADDR"
        return 0
    else
        log_error "SSL proxy not reachable at $PROXY_ADDR"
        return 1
    fi
}

##############################################################################
# Main Test Runner
##############################################################################

run_all_tests() {
    log_info "Starting Cerberus SSL Inspector Test Suite"
    log_info "API URL: $API_URL"
    log_info "Proxy Address: $PROXY_ADDR"
    echo ""

    # Wait for API
    wait_for_api || return 1

    # Health checks
    test_health
    test_readiness

    # CA certificate management
    test_get_ca_cert
    test_download_ca_cert
    test_get_ca_fingerprint
    test_regenerate_ca

    # Bypass rules management
    test_list_bypass_rules
    test_add_bypass_rule
    test_add_multiple_bypass_rules
    test_remove_bypass_rule

    # Settings management
    test_get_settings
    test_update_settings
    test_update_settings_partial

    # Statistics
    test_get_stats
    test_get_active_connections

    # Metrics
    test_metrics_endpoint

    # Error handling
    test_invalid_endpoint
    test_malformed_json
    test_missing_required_field

    # Performance benchmarks
    test_health_response_time
    test_stats_response_time

    # SSL proxy connectivity
    test_ssl_proxy_connectivity

    # Summary
    echo ""
    echo "======================================"
    echo "Test Summary"
    echo "======================================"
    log_success "Passed: $TESTS_PASSED"
    log_error "Failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "Some tests failed"
        return 1
    fi
}

##############################################################################
# Entry Point
##############################################################################

main() {
    run_all_tests
    exit $?
}

main "$@"
