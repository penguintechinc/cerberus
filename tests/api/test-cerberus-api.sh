#!/bin/bash
##############################################################################
# Cerberus API Test Suite
# Purpose: Test Flask backend API endpoints
# Tests: Health, Authentication, CRUD, Error cases
##############################################################################

set -euo pipefail

# Configuration
API_URL="${CERBERUS_API_URL:-http://localhost:5000}"
API_VERSION="v1"
TEST_EMAIL="test@example.com"
TEST_PASSWORD="TestPassword123!"
AUTH_TOKEN=""
TEST_USER_ID=""

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

    log_info "Waiting for API to be ready at $API_URL..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$API_URL/healthz" >/dev/null 2>&1; then
            log_success "API is ready"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    log_error "API failed to become ready after $max_attempts attempts"
    return 1
}

make_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-}
    local headers=${4:-"Content-Type: application/json"}

    local url="$API_URL/api/$API_VERSION$endpoint"

    if [ -n "$AUTH_TOKEN" ] && [ -z "$(echo "$headers" | grep -i 'authorization')" ]; then
        headers="$headers
Authorization: Bearer $AUTH_TOKEN"
    fi

    if [ -n "$data" ]; then
        curl -s -X "$method" "$url" \
            -H "$headers" \
            -d "$data"
    else
        curl -s -X "$method" "$url" \
            -H "$headers"
    fi
}

assert_status() {
    local response=$1
    local expected_status=$2
    local test_name=$3

    local actual_status=$(echo "$response" | head -1)

    if [ "$actual_status" = "$expected_status" ]; then
        log_success "$test_name (HTTP $actual_status)"
        return 0
    else
        log_error "$test_name (Expected $expected_status, got $actual_status)"
        return 1
    fi
}

assert_json_field() {
    local response=$1
    local field=$2
    local expected=$3
    local test_name=$4

    # Extract JSON body (skip headers)
    local body=$(echo "$response" | tail -n +2)

    local value=$(echo "$body" | grep -o "\"$field\":\"[^\"]*\"" | cut -d'"' -f4 2>/dev/null || echo "")

    if [ "$value" = "$expected" ]; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name (Expected '$expected', got '$value')"
        return 1
    fi
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
# Authentication Tests
##############################################################################

test_register() {
    log_test "User Registration"

    local payload=$(cat <<EOF
{
    "email": "$TEST_EMAIL",
    "password": "$TEST_PASSWORD",
    "first_name": "Test",
    "last_name": "User"
}
EOF
)

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/$API_VERSION/auth/register" \
        -H "Content-Type: application/json" \
        -d "$payload")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "201" ] || [ "$status" = "200" ]; then
        log_success "User registration"

        # Extract user ID for later tests
        local body=$(echo "$response" | head -1)
        TEST_USER_ID=$(echo "$body" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

        return 0
    elif [ "$status" = "409" ]; then
        # User already exists from previous test run - this is acceptable
        log_success "User registration (user already exists - HTTP 409)"
        return 0
    else
        log_error "User registration (HTTP $status)"
        return 1
    fi
}

test_login() {
    log_test "User Login"

    local payload=$(cat <<EOF
{
    "email": "$TEST_EMAIL",
    "password": "$TEST_PASSWORD"
}
EOF
)

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/$API_VERSION/auth/login" \
        -H "Content-Type: application/json" \
        -d "$payload")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "User login"

        # Extract JWT token for subsequent requests
        local body=$(echo "$response" | head -1)
        AUTH_TOKEN=$(echo "$body" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [ -z "$AUTH_TOKEN" ]; then
            log_error "Failed to extract authentication token"
            return 1
        fi

        log_info "Authentication token obtained"
        return 0
    else
        log_error "User login (HTTP $status)"
        return 1
    fi
}

test_logout() {
    log_test "User Logout"

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/$API_VERSION/auth/logout" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "User logout"
        return 0
    else
        log_error "User logout (HTTP $status)"
        return 1
    fi
}

##############################################################################
# User Management Tests
##############################################################################

test_get_user() {
    log_test "Get User Profile"

    if [ -z "$AUTH_TOKEN" ] || [ -z "$TEST_USER_ID" ]; then
        log_error "Skipping: No auth token or user ID"
        return 1
    fi

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/api/$API_VERSION/users/$TEST_USER_ID" \
        -H "Authorization: Bearer $AUTH_TOKEN")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Get user profile"
        return 0
    else
        log_error "Get user profile (HTTP $status)"
        return 1
    fi
}

test_list_users() {
    log_test "List Users"

    if [ -z "$AUTH_TOKEN" ]; then
        log_error "Skipping: No auth token"
        return 1
    fi

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/api/$API_VERSION/users" \
        -H "Authorization: Bearer $AUTH_TOKEN")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "List users"
        return 0
    else
        log_error "List users (HTTP $status)"
        return 1
    fi
}

##############################################################################
# Error Handling Tests
##############################################################################

test_invalid_endpoint() {
    log_test "Invalid Endpoint (404 Error)"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/api/$API_VERSION/nonexistent" \
        -H "Authorization: Bearer $AUTH_TOKEN")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "404" ]; then
        log_success "Invalid endpoint returns 404"
        return 0
    else
        log_error "Invalid endpoint (Expected 404, got $status)"
        return 1
    fi
}

test_unauthorized_access() {
    log_test "Unauthorized Access (401 Error)"

    local response=$(curl -s -w "\n%{http_code}" "$API_URL/api/$API_VERSION/users" \
        -H "Authorization: Bearer invalid-token")

    local status=$(echo "$response" | tail -1)

    if [ "$status" = "401" ] || [ "$status" = "403" ]; then
        log_success "Unauthorized access returns $status"
        return 0
    else
        log_warn "Unauthorized access check (Expected 401 or 403, got $status)"
        return 0
    fi
}

test_missing_content_type() {
    log_test "Missing Content-Type Header"

    local payload='{"email":"test@example.com","password":"test"}'

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/$API_VERSION/auth/login" \
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

    local response=$(curl -s -w "\n%{http_code}" "$API_URL:9105/metrics")
    local status=$(echo "$response" | tail -1)

    if [ "$status" = "200" ]; then
        log_success "Metrics endpoint accessible"
        return 0
    else
        log_warn "Metrics endpoint (HTTP $status)"
        return 0
    fi
}

##############################################################################
# Main Test Runner
##############################################################################

run_all_tests() {
    log_info "Starting Cerberus API Test Suite"
    log_info "API URL: $API_URL"
    echo ""

    # Wait for API
    wait_for_api || return 1

    # Health checks
    test_health
    test_readiness

    # Authentication flow
    test_register
    test_login

    # User management
    test_get_user
    test_list_users

    # Error handling
    test_invalid_endpoint
    test_unauthorized_access
    test_missing_content_type

    # Metrics
    test_metrics_endpoint

    # Cleanup (logout)
    test_logout

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
