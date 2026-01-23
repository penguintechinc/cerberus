#!/bin/bash
##############################################################################
# Cerberus Content Filter Test Suite
# Purpose: Test Go content filter API endpoints
# Tests: Health, URL filtering, blocklist/allowlist, categories, stats
##############################################################################

set -euo pipefail

# Configuration
FILTER_URL="${CERBERUS_FILTER_URL:-http://localhost:8080}"
API_VERSION="v1"

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

wait_for_filter() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for Content Filter to be ready at $FILTER_URL..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$FILTER_URL/healthz" >/dev/null 2>&1; then
            log_success "Content Filter is ready"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    log_error "Content Filter failed to become ready after $max_attempts attempts"
    return 1
}

make_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    local url="$FILTER_URL$endpoint"

    if [ -n "$data" ]; then
        curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json"
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
        echo "Response: $(echo "$response" | head -20)"
        return 1
    fi
}

##############################################################################
# Health Check Tests
##############################################################################

test_health() {
    log_test "Health Check Endpoint"

    local response=$(curl -s -w "\n%{http_code}" "$FILTER_URL/healthz")
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

    local response=$(curl -s -w "\n%{http_code}" "$FILTER_URL/readyz")
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
# URL Check Tests
##############################################################################

test_check_allowed_url() {
    log_test "Check Allowed URL"

    local payload=$(cat <<EOF
{
    "url": "https://www.google.com"
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/check" "$payload")
    assert_status "$response" "200" "Check allowed URL"
}

test_check_blocked_url() {
    log_test "Check Blocked URL"

    local payload=$(cat <<EOF
{
    "url": "https://malware.example.com"
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/check" "$payload")
    # Expect 200 status even if blocked (returns blocked=true in body)
    assert_status "$response" "200" "Check blocked URL endpoint"
}

test_check_invalid_url() {
    log_test "Check Invalid URL"

    local payload=$(cat <<EOF
{
    "url": ""
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/check" "$payload")
    assert_status "$response" "400" "Check invalid URL returns 400"
}

test_check_batch_urls() {
    log_test "Check Batch URLs"

    local payload=$(cat <<EOF
{
    "urls": ["https://www.google.com", "https://www.github.com", "https://example.com"]
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/check/batch" "$payload")
    assert_status "$response" "200" "Check batch URLs"
}

test_check_batch_exceeds_limit() {
    log_test "Check Batch Exceeds Limit"

    # Create payload with 101 URLs (assuming default limit is 100)
    local urls=""
    for i in {1..101}; do
        urls="$urls,\"https://example$i.com\""
    done
    urls="${urls:1}"

    local payload="{\"urls\": [$urls]}"

    local response=$(make_request "POST" "/api/$API_VERSION/check/batch" "$payload")
    assert_status "$response" "400" "Batch size exceeds limit"
}

##############################################################################
# Blocklist Management Tests
##############################################################################

test_list_blocklist() {
    log_test "List Blocklist Entries"

    local response=$(make_request "GET" "/api/$API_VERSION/blocklist")
    assert_status "$response" "200" "List blocklist entries"
}

test_add_blocklist_entry() {
    log_test "Add Blocklist Entry"

    local payload=$(cat <<EOF
{
    "domain": "blocked-test.example.com"
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/blocklist" "$payload")
    assert_status "$response" "200" "Add blocklist entry"
}

test_add_blocklist_invalid() {
    log_test "Add Blocklist Invalid Domain"

    local payload=$(cat <<EOF
{
    "domain": ""
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/blocklist" "$payload")
    assert_status "$response" "400" "Add invalid blocklist entry returns 400"
}

test_remove_blocklist_entry() {
    log_test "Remove Blocklist Entry"

    local response=$(make_request "DELETE" "/api/$API_VERSION/blocklist/test-domain.com")
    assert_status "$response" "200" "Remove blocklist entry"
}

test_reload_blocklists() {
    log_test "Reload Blocklists"

    local response=$(make_request "POST" "/api/$API_VERSION/blocklist/reload")
    assert_status "$response" "200" "Reload blocklists"
}

##############################################################################
# Allowlist Management Tests
##############################################################################

test_list_allowlist() {
    log_test "List Allowlist Entries"

    local response=$(make_request "GET" "/api/$API_VERSION/allowlist")
    assert_status "$response" "200" "List allowlist entries"
}

test_add_allowlist_entry() {
    log_test "Add Allowlist Entry"

    local payload=$(cat <<EOF
{
    "domain": "trusted.example.com"
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/allowlist" "$payload")
    assert_status "$response" "200" "Add allowlist entry"
}

test_add_allowlist_invalid() {
    log_test "Add Allowlist Invalid Domain"

    local payload=$(cat <<EOF
{
    "domain": ""
}
EOF
)

    local response=$(make_request "POST" "/api/$API_VERSION/allowlist" "$payload")
    assert_status "$response" "400" "Add invalid allowlist entry returns 400"
}

test_remove_allowlist_entry() {
    log_test "Remove Allowlist Entry"

    local response=$(make_request "DELETE" "/api/$API_VERSION/allowlist/trusted.example.com")
    assert_status "$response" "200" "Remove allowlist entry"
}

##############################################################################
# Category Management Tests
##############################################################################

test_list_categories() {
    log_test "List Categories"

    local response=$(make_request "GET" "/api/$API_VERSION/categories")
    assert_status "$response" "200" "List categories"
}

test_list_category_urls() {
    log_test "List Category URLs"

    local response=$(make_request "GET" "/api/$API_VERSION/categories/social-media/urls")
    # Return 200 if category exists, 404 if not (both acceptable)
    local status=$(echo "$response" | tail -1)
    if [ "$status" = "200" ] || [ "$status" = "404" ]; then
        log_success "List category URLs (HTTP $status)"
        return 0
    else
        log_error "List category URLs (Expected 200 or 404, got $status)"
        return 1
    fi
}

test_block_category() {
    log_test "Block Category"

    local response=$(make_request "POST" "/api/$API_VERSION/categories/gambling/block")
    local status=$(echo "$response" | tail -1)
    if [ "$status" = "200" ] || [ "$status" = "404" ]; then
        log_success "Block category (HTTP $status)"
        return 0
    else
        log_error "Block category (Expected 200 or 404, got $status)"
        return 1
    fi
}

test_allow_category() {
    log_test "Allow Category"

    local response=$(make_request "POST" "/api/$API_VERSION/categories/gambling/allow")
    local status=$(echo "$response" | tail -1)
    if [ "$status" = "200" ] || [ "$status" = "404" ]; then
        log_success "Allow category (HTTP $status)"
        return 0
    else
        log_error "Allow category (Expected 200 or 404, got $status)"
        return 1
    fi
}

##############################################################################
# Stats Tests
##############################################################################

test_get_stats() {
    log_test "Get Filter Statistics"

    local response=$(make_request "GET" "/api/$API_VERSION/stats")
    assert_status "$response" "200" "Get filter statistics"
}

##############################################################################
# Error Handling Tests
##############################################################################

test_invalid_endpoint() {
    log_test "Invalid Endpoint (404 Error)"

    local response=$(make_request "GET" "/api/$API_VERSION/nonexistent")
    assert_status "$response" "404" "Invalid endpoint returns 404"
}

test_malformed_json() {
    log_test "Malformed JSON"

    local response=$(curl -s -w "\n%{http_code}" -X POST "$FILTER_URL/api/$API_VERSION/check" \
        -H "Content-Type: application/json" \
        -d "{invalid json}")

    assert_status "$response" "400" "Malformed JSON returns 400"
}

test_missing_content_type() {
    log_test "Missing Content-Type Header"

    local payload='{"url":"https://example.com"}'

    local response=$(curl -s -w "\n%{http_code}" -X POST "$FILTER_URL/api/$API_VERSION/check" \
        -d "$payload")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "400" ] || [ "$status" = "415" ] || [ "$status" = "200" ]; then
        log_success "Content-Type validation (Status: $status)"
        return 0
    else
        log_error "Content-Type validation (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Metrics Tests
##############################################################################

test_metrics_endpoint() {
    log_test "Prometheus Metrics Endpoint"

    local response=$(curl -s -w "\n%{http_code}" "$FILTER_URL/metrics")
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
# Performance Tests
##############################################################################

test_health_check_latency() {
    log_test "Health Check Latency"

    local start=$(date +%s%N)
    curl -s "$FILTER_URL/healthz" >/dev/null
    local end=$(date +%s%N)
    local latency=$(( (end - start) / 1000000 ))  # Convert to ms

    if [ "$latency" -lt 500 ]; then
        log_success "Health check latency: ${latency}ms (target: <100ms)"
        return 0
    else
        log_error "Health check latency: ${latency}ms exceeds acceptable threshold (500ms)"
        return 1
    fi
}

test_url_check_latency() {
    log_test "URL Check Latency"

    local payload=$(cat <<EOF
{
    "url": "https://www.example.com"
}
EOF
)

    local start=$(date +%s%N)
    curl -s -X POST "$FILTER_URL/api/$API_VERSION/check" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null
    local end=$(date +%s%N)
    local latency=$(( (end - start) / 1000000 ))  # Convert to ms

    if [ "$latency" -lt 2000 ]; then
        log_success "URL check latency: ${latency}ms (target: <500ms)"
        return 0
    else
        log_error "URL check latency: ${latency}ms exceeds acceptable threshold (2000ms)"
        return 1
    fi
}

##############################################################################
# Main Test Runner
##############################################################################

run_all_tests() {
    log_info "Starting Cerberus Content Filter Test Suite"
    log_info "Filter URL: $FILTER_URL"
    echo ""

    # Wait for filter service
    wait_for_filter || return 1

    # Health checks
    test_health
    test_readiness

    # URL checking
    test_check_allowed_url
    test_check_blocked_url
    test_check_invalid_url
    test_check_batch_urls
    test_check_batch_exceeds_limit

    # Blocklist management
    test_list_blocklist
    test_add_blocklist_entry
    test_add_blocklist_invalid
    test_remove_blocklist_entry
    test_reload_blocklists

    # Allowlist management
    test_list_allowlist
    test_add_allowlist_entry
    test_add_allowlist_invalid
    test_remove_allowlist_entry

    # Categories
    test_list_categories
    test_list_category_urls
    test_block_category
    test_allow_category

    # Statistics
    test_get_stats

    # Error handling
    test_invalid_endpoint
    test_malformed_json
    test_missing_content_type

    # Metrics
    test_metrics_endpoint

    # Performance tests
    test_health_check_latency
    test_url_check_latency

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
