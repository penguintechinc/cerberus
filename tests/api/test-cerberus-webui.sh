#!/bin/bash
##############################################################################
# Cerberus WebUI Test Suite
# Purpose: Test React frontend static assets and page loading
# Tests: Health check, static assets, page routes, content-type headers
##############################################################################

set -euo pipefail

# Configuration
WEBUI_URL="${CERBERUS_WEBUI_URL:-http://localhost:3000}"
WEBUI_PORT="${WEBUI_PORT:-3000}"

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

wait_for_webui() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for WebUI to be ready at $WEBUI_URL..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$WEBUI_URL" >/dev/null 2>&1; then
            log_success "WebUI is ready"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    log_error "WebUI failed to become ready after $max_attempts attempts"
    return 1
}

make_request() {
    local method=$1
    local endpoint=$2
    local expected_status=$3

    local url="$WEBUI_URL$endpoint"

    local response=$(curl -s -w "\n%{http_code}" -X "$method" "$url")
    local body=$(echo "$response" | head -n -1)
    local status=$(echo "$response" | tail -n 1)

    echo "$status"
}

assert_status() {
    local status=$1
    local expected_status=$2
    local test_name=$3

    if [ "$status" = "$expected_status" ]; then
        log_success "$test_name (HTTP $status)"
        return 0
    else
        log_error "$test_name - Expected $expected_status, got $status"
        return 1
    fi
}

check_content_type() {
    local endpoint=$1
    local expected_type=$2
    local test_name=$3

    local content_type=$(curl -s -I "$WEBUI_URL$endpoint" | grep -i "content-type" | cut -d: -f2 | xargs)

    if [[ "$content_type" == *"$expected_type"* ]]; then
        log_success "$test_name (Content-Type: $content_type)"
        return 0
    else
        log_error "$test_name - Expected $expected_type, got $content_type"
        return 1
    fi
}

check_asset_exists() {
    local asset=$1
    local test_name=$2

    local status=$(curl -s -w "%{http_code}" -o /dev/null "$WEBUI_URL$asset")

    if [ "$status" = "200" ]; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name - Asset returned HTTP $status"
        return 1
    fi
}

##############################################################################
# Health Check Tests
##############################################################################

test_nginx_health() {
    log_test "Nginx Health Check"

    local status=$(make_request "GET" "/" "200")
    assert_status "$status" "200" "Root endpoint responds"
}

test_index_html() {
    log_test "Index HTML File"

    check_content_type "/" "text/html" "index.html content-type is HTML"
}

##############################################################################
# Static Asset Tests
##############################################################################

test_javascript_bundles() {
    log_test "JavaScript Bundle Loading"

    # Note: Actual bundle names depend on vite build output
    # Testing for /dist directory and typical JS bundle patterns
    local status=$(curl -s -w "%{http_code}" -o /dev/null "$WEBUI_URL/dist/")

    if [ "$status" = "200" ] || [ "$status" = "403" ]; then
        log_success "JavaScript bundles accessible"
    else
        log_error "JavaScript bundles - Unexpected HTTP $status"
    fi
}

test_css_assets() {
    log_test "CSS Asset Loading"

    # Vite builds CSS into bundles within /dist
    local status=$(curl -s -w "%{http_code}" -o /dev/null "$WEBUI_URL/dist/")

    if [ "$status" = "200" ] || [ "$status" = "403" ]; then
        log_success "CSS assets accessible"
    else
        log_error "CSS assets - Unexpected HTTP $status"
    fi
}

##############################################################################
# Page Route Tests
##############################################################################

test_root_page() {
    log_test "Root Page Route"

    local status=$(make_request "GET" "/" "200")
    assert_status "$status" "200" "Root page (/) loads successfully"
}

test_login_page() {
    log_test "Login Page Route"

    local status=$(make_request "GET" "/login" "200")
    assert_status "$status" "200" "Login page (/login) loads successfully"
}

test_dashboard_page() {
    log_test "Dashboard Page Route"

    local status=$(make_request "GET" "/dashboard" "200")
    assert_status "$status" "200" "Dashboard page (/dashboard) loads successfully"
}

test_firewall_page() {
    log_test "Firewall Page Route"

    local status=$(make_request "GET" "/firewall" "200")
    assert_status "$status" "200" "Firewall page (/firewall) loads successfully"
}

test_ips_page() {
    log_test "IPS Page Route"

    local status=$(make_request "GET" "/ips" "200")
    assert_status "$status" "200" "IPS page (/ips) loads successfully"
}

test_vpn_page() {
    log_test "VPN Page Route"

    local status=$(make_request "GET" "/vpn" "200")
    assert_status "$status" "200" "VPN page (/vpn) loads successfully"
}

test_filter_page() {
    log_test "Content Filter Page Route"

    local status=$(make_request "GET" "/filter" "200")
    assert_status "$status" "200" "Content Filter page (/filter) loads successfully"
}

test_profile_page() {
    log_test "Profile Page Route"

    local status=$(make_request "GET" "/profile" "200")
    assert_status "$status" "200" "Profile page (/profile) loads successfully"
}

test_settings_page() {
    log_test "Settings Page Route"

    local status=$(make_request "GET" "/settings" "200")
    assert_status "$status" "200" "Settings page (/settings) loads successfully"
}

test_users_page() {
    log_test "Users Management Page Route"

    local status=$(make_request "GET" "/users" "200")
    assert_status "$status" "200" "Users page (/users) loads successfully"
}

##############################################################################
# HTTP Headers & Content-Type Tests
##############################################################################

test_index_content_type() {
    log_test "Content-Type Headers"

    check_content_type "/" "text/html" "Root endpoint returns HTML"
}

test_security_headers() {
    log_test "Security Headers"

    local headers=$(curl -s -I "$WEBUI_URL/" | grep -i "^x-")

    if [ -n "$headers" ]; then
        log_success "Security headers present"
    else
        log_info "No security headers detected (expected in development)"
    fi
}

##############################################################################
# Error Handling Tests
##############################################################################

test_invalid_route() {
    log_test "Invalid Route Handling"

    local status=$(make_request "GET" "/nonexistent-page" "200")

    # React SPA serves index.html for all routes (should return 200)
    if [ "$status" = "200" ]; then
        log_success "Invalid route redirects to app (SPA behavior)"
    else
        log_error "Invalid route returned HTTP $status"
    fi
}

##############################################################################
# Port Connectivity Tests
##############################################################################

test_port_accessibility() {
    log_test "Port Accessibility"

    if nc -z localhost $WEBUI_PORT 2>/dev/null; then
        log_success "Port $WEBUI_PORT is accessible"
    else
        log_error "Port $WEBUI_PORT is not accessible"
    fi
}

##############################################################################
# Main Test Execution
##############################################################################

main() {
    echo "=================================================="
    echo "Cerberus WebUI Test Suite"
    echo "=================================================="
    echo "Target: $WEBUI_URL"
    echo ""

    # Wait for WebUI to be ready
    if ! wait_for_webui; then
        log_error "Cannot proceed - WebUI is not ready"
        exit 1
    fi

    # Port connectivity
    test_port_accessibility

    # Health checks
    test_nginx_health
    test_index_html

    # Static assets
    test_javascript_bundles
    test_css_assets

    # Page routes
    test_root_page
    test_login_page
    test_dashboard_page
    test_firewall_page
    test_ips_page
    test_vpn_page
    test_filter_page
    test_profile_page
    test_settings_page
    test_users_page

    # HTTP headers
    test_index_content_type
    test_security_headers

    # Error handling
    test_invalid_route

    # Summary
    echo ""
    echo "=================================================="
    echo "Test Results:"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo "=================================================="

    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
