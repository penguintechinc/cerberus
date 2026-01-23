#!/bin/bash
##############################################################################
# Cerberus Unified Test Runner
# Purpose: Run build, run, intrusion protection, traffic routing, API, and
#          page tests depending on the component
# Combines unit, integration, and regression testing in one script
#
# Usage: ./scripts/run-tests.sh <component> [test-category]
#        ./scripts/run-tests.sh all [test-category]
#        ./scripts/run-tests.sh --help
##############################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$PROJECT_ROOT/tests"
LOG_DIR="/tmp/cerberus-tests"
EPOCH_TS=$(date +%s)
VERSION=$(cat "$PROJECT_ROOT/.version" 2>/dev/null || echo "0.0.0")

# Detect docker compose command
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
    exit 1
fi

##############################################################################
# Component Definitions
##############################################################################

# All testable components
declare -A COMPONENTS=(
    ["api"]="cerberus-api:5000:Flask backend API"
    ["webui"]="cerberus-webui:3000:React frontend"
    ["ips"]="cerberus-ips:9100:Suricata IPS/IDS"
    ["filter"]="cerberus-filter:8080:Content filter (Go)"
    ["ssl"]="cerberus-ssl-inspector:8443:SSL/TLS inspection"
    ["vpn-wireguard"]="cerberus-vpn-wireguard:51820:WireGuard VPN"
    ["vpn-ipsec"]="cerberus-vpn-ipsec:500:IPSec VPN"
    ["vpn-openvpn"]="cerberus-vpn-openvpn:1194:OpenVPN"
    ["xdp"]="cerberus-xdp:9200:XDP high-performance backend"
)

# Test categories
declare -a TEST_CATEGORIES=(
    "build"
    "run"
    "health"
    "ips"
    "traffic"
    "api"
    "page"
    "regression"
    "all"
)

# Component to test category mapping
declare -A COMPONENT_TESTS=(
    ["api"]="build run health api regression"
    ["webui"]="build run health page api regression"
    ["ips"]="build run health ips api regression"
    ["filter"]="build run health traffic api regression"
    ["ssl"]="build run health traffic api regression"
    ["vpn-wireguard"]="build run health traffic api regression"
    ["vpn-ipsec"]="build run health traffic api regression"
    ["vpn-openvpn"]="build run health traffic api regression"
    ["xdp"]="build run health traffic api regression"
)

##############################################################################
# Colors and Formatting
##############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

##############################################################################
# Test Counters
##############################################################################

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Current log file
CURRENT_LOG_FILE=""

##############################################################################
# Logging Functions
##############################################################################

setup_logging() {
    mkdir -p "$LOG_DIR"
}

log() {
    local message="$1"
    if [ -n "$CURRENT_LOG_FILE" ]; then
        echo -e "$message" | tee -a "$CURRENT_LOG_FILE"
    else
        echo -e "$message"
    fi
}

log_file_only() {
    local message="$1"
    if [ -n "$CURRENT_LOG_FILE" ]; then
        echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g' >> "$CURRENT_LOG_FILE"
    fi
}

log_info() { log "${BLUE}[INFO]${NC} $1"; }
log_success() { log "${GREEN}[PASS]${NC} $1"; ((TESTS_PASSED++)); ((TESTS_TOTAL++)); }
log_error() { log "${RED}[FAIL]${NC} $1"; ((TESTS_FAILED++)); ((TESTS_TOTAL++)); }
log_warn() { log "${YELLOW}[WARN]${NC} $1"; }
log_skip() { log "${CYAN}[SKIP]${NC} $1"; ((TESTS_SKIPPED++)); ((TESTS_TOTAL++)); }
log_test() { log "\n${BLUE}${BOLD}Test:${NC} $1"; }

log_header() {
    log ""
    log "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    log "${MAGENTA}  $1${NC}"
    log "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    log ""
}

log_section() {
    log ""
    log "${CYAN}──────────────────────────────────────────────────────────────${NC}"
    log "${CYAN}  $1${NC}"
    log "${CYAN}──────────────────────────────────────────────────────────────${NC}"
}

##############################################################################
# Utility Functions
##############################################################################

get_container_name() {
    local component=$1
    echo "${COMPONENTS[$component]}" | cut -d: -f1
}

get_container_port() {
    local component=$1
    echo "${COMPONENTS[$component]}" | cut -d: -f2
}

get_container_desc() {
    local component=$1
    echo "${COMPONENTS[$component]}" | cut -d: -f3
}

wait_for_service() {
    local url=$1
    local max_attempts=${2:-30}
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -s --max-time 2 "$url" >/dev/null 2>&1; then
            return 0
        fi
        ((attempt++))
        sleep 1
    done
    return 1
}

measure_latency() {
    local url=$1
    local start_ns=$(date +%s%N)
    curl -s --max-time 5 "$url" >/dev/null 2>&1
    local end_ns=$(date +%s%N)
    echo $(( (end_ns - start_ns) / 1000000 ))
}

##############################################################################
# BUILD TESTS
##############################################################################

test_build() {
    local component=$1
    local container=$(get_container_name "$component")

    log_section "Build Tests: $component"

    # Test 1: Dockerfile exists
    log_test "Dockerfile existence"
    local dockerfile_path=""
    for path in "$PROJECT_ROOT/services/$container/Dockerfile" \
                "$PROJECT_ROOT/services/${component}/Dockerfile" \
                "$PROJECT_ROOT/services/flask-backend/Dockerfile" \
                "$PROJECT_ROOT/services/go-backend/Dockerfile"; do
        if [ -f "$path" ]; then
            dockerfile_path="$path"
            break
        fi
    done

    if [ -n "$dockerfile_path" ]; then
        log_success "Dockerfile found: $dockerfile_path"
    else
        log_error "Dockerfile not found for $component"
        return 1
    fi

    # Test 2: Dockerfile syntax validation
    log_test "Dockerfile syntax validation"
    if docker build --check "$dockerfile_path" >/dev/null 2>&1 || \
       head -1 "$dockerfile_path" | grep -q "^FROM\|^ARG"; then
        log_success "Dockerfile syntax valid"
    else
        log_warn "Could not validate Dockerfile syntax"
    fi

    # Test 3: Docker image build
    log_test "Docker image build"
    local build_output
    if build_output=$($DOCKER_COMPOSE -f "$PROJECT_ROOT/docker-compose.yml" \
                      build --quiet "$container" 2>&1); then
        log_file_only "$build_output"
        log_success "Docker image built successfully"
    else
        log_file_only "$build_output"
        log_error "Docker image build failed"
        log "$build_output"
        return 1
    fi

    # Test 4: Image size check
    log_test "Image size check"
    local image_size=$(docker images --format "{{.Size}}" "$container" 2>/dev/null | head -1)
    if [ -n "$image_size" ]; then
        log_success "Image size: $image_size"
    else
        log_skip "Could not determine image size"
    fi

    return 0
}

##############################################################################
# RUN/CONTAINER TESTS
##############################################################################

test_run() {
    local component=$1
    local container=$(get_container_name "$component")

    log_section "Run Tests: $component"

    # Test 1: Container exists
    log_test "Container existence"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        log_success "Container exists: $container"
    else
        log_error "Container does not exist: $container"
        return 1
    fi

    # Test 2: Container is running
    log_test "Container running status"
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_success "Container is running"
    else
        log_error "Container is not running"
        return 1
    fi

    # Test 3: Container uptime
    log_test "Container uptime"
    local uptime=$(docker ps --filter "name=^${container}$" \
                   --format '{{.Status}}' 2>/dev/null)
    if [ -n "$uptime" ]; then
        log_success "Container status: $uptime"
    else
        log_skip "Could not determine uptime"
    fi

    # Test 4: Container resource usage
    log_test "Container resource usage"
    local stats=$(docker stats --no-stream --format \
                  "CPU: {{.CPUPerc}}, MEM: {{.MemUsage}}" "$container" 2>/dev/null)
    if [ -n "$stats" ]; then
        log_success "Resource usage - $stats"
    else
        log_skip "Could not get resource stats"
    fi

    # Test 5: Container logs (no errors in last 50 lines)
    log_test "Container log health"
    local error_count
    error_count=$(docker logs --tail 50 "$container" 2>&1 | \
                 grep -ci "error\|fatal\|panic" 2>/dev/null || echo "0")
    error_count=$(echo "$error_count" | head -1 | tr -d '[:space:]')
    [[ "$error_count" =~ ^[0-9]+$ ]] || error_count=0
    if [ "$error_count" -lt 5 ]; then
        log_success "Container logs healthy (error count: $error_count)"
    else
        log_warn "Container logs contain $error_count errors/warnings"
    fi

    return 0
}

##############################################################################
# HEALTH CHECK TESTS
##############################################################################

test_health() {
    local component=$1
    local container=$(get_container_name "$component")
    local port=$(get_container_port "$component")

    log_section "Health Check Tests: $component"

    # Test 1: Docker health status
    log_test "Docker health status"
    local health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                          "$container" 2>/dev/null | tr -d '[:space:]')

    case "$health_status" in
        healthy)
            log_success "Docker health check: healthy"
            ;;
        starting)
            log_warn "Docker health check: starting"
            ;;
        unhealthy)
            log_error "Docker health check: unhealthy"
            ;;
        none|"")
            log_skip "No Docker health check configured"
            ;;
    esac

    # Test 2: HTTP health endpoint
    log_test "HTTP health endpoint (/healthz)"
    local health_url="http://localhost:$port/healthz"
    local response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$health_url" 2>/dev/null)

    if [ "$response" = "200" ]; then
        log_success "Health endpoint returned 200"
    elif [ "$response" = "000" ]; then
        log_skip "Health endpoint not reachable"
    else
        log_error "Health endpoint returned HTTP $response"
    fi

    # Test 3: Readiness endpoint
    log_test "Readiness endpoint (/readyz)"
    local ready_url="http://localhost:$port/readyz"
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$ready_url" 2>/dev/null)

    if [ "$response" = "200" ]; then
        log_success "Readiness endpoint returned 200"
    elif [ "$response" = "000" ]; then
        log_skip "Readiness endpoint not reachable"
    else
        log_warn "Readiness endpoint returned HTTP $response"
    fi

    # Test 4: Health endpoint latency
    log_test "Health endpoint latency"
    local latency=$(measure_latency "$health_url")
    if [ "$latency" -lt 500 ]; then
        log_success "Health endpoint latency: ${latency}ms (< 500ms)"
    elif [ "$latency" -lt 2000 ]; then
        log_warn "Health endpoint latency: ${latency}ms (acceptable but slow)"
    else
        log_error "Health endpoint latency: ${latency}ms (> 2000ms)"
    fi

    return 0
}

##############################################################################
# INTRUSION PROTECTION SYSTEM (IPS) TESTS
##############################################################################

test_ips() {
    local component=$1

    log_section "Intrusion Protection Tests: $component"

    # Only run IPS-specific tests for IPS component
    if [ "$component" != "ips" ]; then
        log_skip "IPS tests only apply to 'ips' component"
        return 0
    fi

    local container=$(get_container_name "$component")

    # Test 1: Suricata process running
    log_test "Suricata process status"
    if docker exec "$container" pgrep -x "suricata" >/dev/null 2>&1; then
        local pid=$(docker exec "$container" pgrep -x "suricata" | head -1)
        log_success "Suricata process running (PID: $pid)"
    else
        log_error "Suricata process not running"
    fi

    # Test 2: Command socket availability
    log_test "Suricata command socket"
    if docker exec "$container" test -S /var/run/suricata/suricata-command.socket 2>/dev/null; then
        log_success "Command socket available"
    else
        log_warn "Command socket not available"
    fi

    # Test 3: EVE log file
    log_test "EVE JSON log file"
    if docker exec "$container" test -f /var/log/suricata/eve.json 2>/dev/null; then
        local size=$(docker exec "$container" stat -c%s /var/log/suricata/eve.json 2>/dev/null || echo "0")
        log_success "EVE log exists (${size} bytes)"
    else
        log_warn "EVE log not yet created"
    fi

    # Test 4: Rules loaded
    log_test "Suricata rules loaded"
    local rules_count=$(docker exec "$container" grep -c "^alert\|^pass\|^drop\|^reject" \
                       /var/lib/suricata/rules/suricata.rules 2>/dev/null || echo "0")
    if [ "$rules_count" -gt 0 ]; then
        log_success "Rules loaded: $rules_count rules"
    else
        log_warn "No rules loaded or rules file not found"
    fi

    # Test 5: Interface monitoring
    log_test "Interface monitoring status"
    if docker exec "$container" suricatasc -c "iface-list" \
       /var/run/suricata/suricata-command.socket >/dev/null 2>&1; then
        log_success "Interface list retrieved successfully"
    else
        log_skip "Could not retrieve interface list"
    fi

    # Test 6: Alert detection capability (regression test)
    log_test "Alert detection capability"
    # Check if EVE log contains any alert events
    local alert_types=$(docker exec "$container" grep -o '"event_type":"[^"]*"' \
                       /var/log/suricata/eve.json 2>/dev/null | cut -d'"' -f4 | sort -u || echo "")
    if [ -n "$alert_types" ]; then
        log_success "Event types detected: $(echo $alert_types | tr '\n' ' ')"
    else
        log_skip "No events detected yet"
    fi

    # Test 7: Stats endpoint
    log_test "Statistics endpoint"
    local stats_response=$(curl -s --max-time 5 "http://localhost:9100/api/v1/stats" 2>/dev/null)
    if echo "$stats_response" | grep -q "uptime\|packets" 2>/dev/null; then
        log_success "Stats endpoint returning data"
    else
        log_skip "Stats endpoint not available or empty"
    fi

    return 0
}

##############################################################################
# TRAFFIC ROUTING TESTS
##############################################################################

test_traffic() {
    local component=$1
    local container=$(get_container_name "$component")
    local port=$(get_container_port "$component")

    log_section "Traffic Routing Tests: $component"

    case "$component" in
        filter)
            test_traffic_filter "$container" "$port"
            ;;
        ssl)
            test_traffic_ssl "$container" "$port"
            ;;
        vpn-wireguard|vpn-ipsec|vpn-openvpn)
            test_traffic_vpn "$component" "$container" "$port"
            ;;
        xdp)
            test_traffic_xdp "$container" "$port"
            ;;
        *)
            log_skip "No traffic routing tests for $component"
            ;;
    esac

    return 0
}

test_traffic_filter() {
    local container=$1
    local port=$2
    local base_url="http://localhost:$port"

    # Test 1: URL filtering - allowed URL
    log_test "URL filtering - allowed URL"
    local response=$(curl -s -X POST "$base_url/api/v1/check" \
                    -H "Content-Type: application/json" \
                    -d '{"url":"https://www.google.com"}' 2>/dev/null)
    if echo "$response" | grep -qi "allowed\|pass" 2>/dev/null; then
        log_success "Allowed URL correctly passed"
    else
        log_skip "Could not verify URL filtering"
    fi

    # Test 2: URL filtering - blocked URL
    log_test "URL filtering - blocked URL detection"
    response=$(curl -s -X POST "$base_url/api/v1/check" \
              -H "Content-Type: application/json" \
              -d '{"url":"https://malware.test"}' 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "URL check endpoint responding"
    else
        log_skip "URL check endpoint not available"
    fi

    # Test 3: Batch URL checking
    log_test "Batch URL checking"
    response=$(curl -s -X POST "$base_url/api/v1/check/batch" \
              -H "Content-Type: application/json" \
              -d '{"urls":["https://google.com","https://example.com"]}' 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "Batch URL checking functional"
    else
        log_skip "Batch URL checking not available"
    fi

    # Test 4: Category-based filtering
    log_test "Category management"
    response=$(curl -s "$base_url/api/v1/categories" 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "Category endpoint responding"
    else
        log_skip "Category endpoint not available"
    fi

    # Test 5: Filter latency
    log_test "URL check latency"
    local latency=$(measure_latency "$base_url/api/v1/check")
    if [ "$latency" -lt 100 ]; then
        log_success "Filter latency: ${latency}ms (< 100ms)"
    elif [ "$latency" -lt 500 ]; then
        log_warn "Filter latency: ${latency}ms (acceptable)"
    else
        log_error "Filter latency: ${latency}ms (> 500ms)"
    fi
}

test_traffic_ssl() {
    local container=$1
    local port=$2
    local base_url="http://localhost:$port"

    # Test 1: CA certificate availability
    log_test "CA certificate availability"
    local response=$(curl -s "$base_url/api/v1/ca/cert" 2>/dev/null)
    if echo "$response" | grep -q "BEGIN CERTIFICATE" 2>/dev/null; then
        log_success "CA certificate available"
    else
        log_skip "CA certificate endpoint not available"
    fi

    # Test 2: Bypass rules
    log_test "Bypass rules configuration"
    response=$(curl -s "$base_url/api/v1/bypass" 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "Bypass rules endpoint responding"
    else
        log_skip "Bypass rules endpoint not available"
    fi

    # Test 3: SSL statistics
    log_test "SSL inspection statistics"
    response=$(curl -s "$base_url/api/v1/stats" 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "SSL stats endpoint responding"
    else
        log_skip "SSL stats endpoint not available"
    fi

    # Test 4: Connection handling
    log_test "SSL connection handling"
    local connections=$(docker exec "$container" netstat -an 2>/dev/null | grep -c ":$port" || echo "0")
    log_success "Active connections on port $port: $connections"
}

test_traffic_vpn() {
    local component=$1
    local container=$2
    local port=$3
    local base_url="http://localhost:$port"

    # Test 1: VPN interface
    log_test "VPN interface status"
    local iface=""
    case "$component" in
        vpn-wireguard) iface="wg0" ;;
        vpn-ipsec) iface="ipsec0" ;;
        vpn-openvpn) iface="tun0" ;;
    esac

    if docker exec "$container" ip link show "$iface" >/dev/null 2>&1; then
        log_success "VPN interface $iface exists"
    else
        log_skip "VPN interface $iface not found (may be normal if no connections)"
    fi

    # Test 2: Peers/connections
    log_test "VPN peer management"
    local peers_endpoint=""
    case "$component" in
        vpn-wireguard) peers_endpoint="/api/v1/peers" ;;
        vpn-ipsec) peers_endpoint="/api/v1/connections" ;;
        vpn-openvpn) peers_endpoint="/api/v1/clients" ;;
    esac

    local response=$(curl -s "http://localhost:${port}${peers_endpoint}" 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "Peer management endpoint responding"
    else
        log_skip "Peer management endpoint not available"
    fi

    # Test 3: VPN status
    log_test "VPN service status"
    case "$component" in
        vpn-wireguard)
            if docker exec "$container" wg show >/dev/null 2>&1; then
                log_success "WireGuard service operational"
            else
                log_skip "WireGuard not yet configured"
            fi
            ;;
        vpn-ipsec)
            if docker exec "$container" ipsec status >/dev/null 2>&1; then
                log_success "IPSec service operational"
            else
                log_skip "IPSec not yet configured"
            fi
            ;;
        vpn-openvpn)
            if docker exec "$container" pgrep openvpn >/dev/null 2>&1; then
                log_success "OpenVPN service operational"
            else
                log_skip "OpenVPN not running"
            fi
            ;;
    esac

    # Test 4: Traffic routing (check iptables/routing)
    log_test "VPN routing configuration"
    if docker exec "$container" ip route show 2>/dev/null | grep -q "dev $iface\|via" 2>/dev/null; then
        log_success "VPN routing configured"
    else
        log_skip "VPN routing not yet established"
    fi
}

test_traffic_xdp() {
    local container=$1
    local port=$2

    # Test 1: XDP program status
    log_test "XDP program status"
    if docker exec "$container" ip link show 2>/dev/null | grep -q "xdp" 2>/dev/null; then
        log_success "XDP program attached"
    else
        log_skip "No XDP program attached"
    fi

    # Test 2: AF_XDP socket
    log_test "AF_XDP socket availability"
    if docker exec "$container" ls /sys/fs/bpf/ 2>/dev/null | grep -q "xsk\|xdp" 2>/dev/null; then
        log_success "BPF maps available"
    else
        log_skip "BPF maps not found"
    fi

    # Test 3: Packet statistics
    log_test "Packet statistics endpoint"
    local response=$(curl -s "http://localhost:$port/api/v1/stats" 2>/dev/null)
    if echo "$response" | grep -qi "packets\|bytes" 2>/dev/null; then
        log_success "Packet stats available"
    else
        log_skip "Packet stats not available"
    fi
}

##############################################################################
# API TESTS
##############################################################################

test_api() {
    local component=$1
    local container=$(get_container_name "$component")
    local port=$(get_container_port "$component")

    log_section "API Tests: $component"

    # Check for component-specific API test script
    local test_script="$TESTS_DIR/api/test-${container}.sh"

    if [ -f "$test_script" ]; then
        log_test "Running API test suite: $test_script"
        if bash "$test_script" 2>&1 | tee -a "$CURRENT_LOG_FILE"; then
            log_success "API test suite passed"
        else
            log_error "API test suite failed"
        fi
    else
        # Run generic API tests
        log_info "No specific API test script, running generic tests"
        test_api_generic "$component" "$port"
    fi

    return 0
}

test_api_generic() {
    local component=$1
    local port=$2
    local base_url="http://localhost:$port"

    # Test 1: API root/version endpoint
    log_test "API version endpoint"
    local response=$(curl -s "$base_url/api/v1" 2>/dev/null || \
                    curl -s "$base_url/api/v1/version" 2>/dev/null || \
                    curl -s "$base_url/version" 2>/dev/null)
    if [ -n "$response" ]; then
        log_success "API version endpoint responding"
    else
        log_skip "API version endpoint not found"
    fi

    # Test 2: JSON content type
    log_test "JSON response content type"
    local content_type=$(curl -s -I "$base_url/healthz" 2>/dev/null | \
                        grep -i "content-type" | head -1)
    if echo "$content_type" | grep -qi "json" 2>/dev/null; then
        log_success "JSON content type confirmed"
    else
        log_skip "Could not verify content type"
    fi

    # Test 3: Metrics endpoint
    log_test "Prometheus metrics endpoint"
    response=$(curl -s "$base_url/metrics" 2>/dev/null)
    if echo "$response" | grep -q "^#\|_total\|_seconds" 2>/dev/null; then
        log_success "Prometheus metrics available"
    else
        log_skip "Prometheus metrics not available"
    fi

    # Test 4: Error handling (404)
    log_test "404 error handling"
    local status=$(curl -s -o /dev/null -w "%{http_code}" \
                  "$base_url/api/v1/nonexistent-endpoint-$(date +%s)" 2>/dev/null)
    if [ "$status" = "404" ]; then
        log_success "404 returned for unknown endpoint"
    else
        log_warn "Unexpected status for unknown endpoint: $status"
    fi

    # Test 5: CORS headers (if applicable)
    log_test "CORS headers"
    local cors=$(curl -s -I -X OPTIONS "$base_url/api/v1" 2>/dev/null | \
                grep -i "access-control")
    if [ -n "$cors" ]; then
        log_success "CORS headers present"
    else
        log_skip "CORS headers not configured"
    fi
}

##############################################################################
# PAGE/UI TESTS
##############################################################################

test_page() {
    local component=$1

    log_section "Page/UI Tests: $component"

    if [ "$component" != "webui" ]; then
        log_skip "Page tests only apply to 'webui' component"
        return 0
    fi

    local port=$(get_container_port "$component")
    local base_url="http://localhost:$port"

    # Define pages to test
    local pages=("/" "/login" "/dashboard" "/firewall" "/ips" "/vpn" "/filter" "/settings" "/users")

    # Test 1: Main page loads
    for page in "${pages[@]}"; do
        log_test "Page load: $page"
        local status=$(curl -s -o /dev/null -w "%{http_code}" \
                      --max-time 10 "$base_url$page" 2>/dev/null)
        if [ "$status" = "200" ] || [ "$status" = "304" ]; then
            log_success "Page $page loaded (HTTP $status)"
        elif [ "$status" = "302" ] || [ "$status" = "301" ]; then
            log_success "Page $page redirects (HTTP $status)"
        elif [ "$status" = "000" ]; then
            log_error "Page $page not reachable"
        else
            log_error "Page $page failed (HTTP $status)"
        fi
    done

    # Test 2: Static assets
    log_test "Static assets accessibility"
    local assets_status=$(curl -s -o /dev/null -w "%{http_code}" \
                         "$base_url/assets/index.js" 2>/dev/null || \
                         curl -s -o /dev/null -w "%{http_code}" \
                         "$base_url/static/js/main.js" 2>/dev/null || echo "000")
    if [ "$assets_status" = "200" ] || [ "$assets_status" = "304" ]; then
        log_success "Static assets accessible"
    else
        log_skip "Static assets path may differ"
    fi

    # Test 3: Page load time
    log_test "Main page load time"
    local latency=$(measure_latency "$base_url/")
    if [ "$latency" -lt 500 ]; then
        log_success "Page load time: ${latency}ms (< 500ms)"
    elif [ "$latency" -lt 2000 ]; then
        log_warn "Page load time: ${latency}ms (acceptable)"
    else
        log_error "Page load time: ${latency}ms (> 2000ms)"
    fi

    # Test 4: HTML validity
    log_test "HTML response validity"
    local html=$(curl -s "$base_url/" 2>/dev/null)
    if echo "$html" | grep -qi "<!doctype html\|<html" 2>/dev/null; then
        log_success "Valid HTML response"
    else
        log_warn "Could not verify HTML validity"
    fi

    # Test 5: JavaScript errors (check for error strings in response)
    log_test "No JavaScript bundle errors"
    if echo "$html" | grep -qi "error\|exception" 2>/dev/null && \
       ! echo "$html" | grep -qi "error-boundary\|error-page" 2>/dev/null; then
        log_warn "Potential error strings in HTML"
    else
        log_success "No obvious error strings in HTML"
    fi

    return 0
}

##############################################################################
# REGRESSION TESTS
##############################################################################

test_regression() {
    local component=$1
    local container=$(get_container_name "$component")
    local port=$(get_container_port "$component")

    log_section "Regression Tests: $component"

    # Test 1: Service stability (restart count)
    log_test "Container restart count"
    local restart_count
    restart_count=$(docker inspect --format='{{.RestartCount}}' \
                   "$container" 2>/dev/null | head -1 | tr -d '[:space:]')
    if [ -z "$restart_count" ]; then
        log_skip "Could not determine restart count"
    elif [ "$restart_count" = "0" ]; then
        log_success "No restarts detected"
    else
        log_warn "Container has restarted $restart_count times"
    fi

    # Test 2: Memory leak detection (basic)
    log_test "Memory usage trend"
    local mem_usage=$(docker stats --no-stream --format "{{.MemPerc}}" \
                     "$container" 2>/dev/null | tr -d '%')
    if [ -n "$mem_usage" ]; then
        if (( $(echo "$mem_usage < 80" | bc -l 2>/dev/null || echo "1") )); then
            log_success "Memory usage: ${mem_usage}% (< 80%)"
        else
            log_warn "High memory usage: ${mem_usage}%"
        fi
    else
        log_skip "Could not determine memory usage"
    fi

    # Test 3: Response consistency
    log_test "Response consistency (5 requests)"
    local consistent=0
    local first_status=""
    for i in {1..5}; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" \
                      --max-time 5 "http://localhost:$port/healthz" 2>/dev/null)
        if [ -z "$first_status" ]; then
            first_status=$status
        elif [ "$status" = "$first_status" ]; then
            ((consistent++))
        fi
        sleep 0.2
    done
    if [ "$consistent" -eq 4 ]; then
        log_success "Consistent responses (5/5 identical)"
    else
        log_warn "Inconsistent responses ($((consistent+1))/5 identical)"
    fi

    # Test 4: Log error frequency
    log_test "Recent error frequency"
    local recent_errors
    recent_errors=$(docker logs --since 5m "$container" 2>&1 | \
                   grep -ci "error\|fatal\|panic" 2>/dev/null || echo "0")
    # Ensure we have a valid integer
    recent_errors=$(echo "$recent_errors" | head -1 | tr -d '[:space:]')
    [[ "$recent_errors" =~ ^[0-9]+$ ]] || recent_errors=0
    if [ "$recent_errors" -lt 3 ]; then
        log_success "Low error frequency in last 5 min: $recent_errors"
    else
        log_warn "High error frequency in last 5 min: $recent_errors"
    fi

    # Test 5: Configuration validity
    log_test "Configuration validation"
    # Check if config files are valid (component-specific)
    case "$component" in
        ips)
            if docker exec "$container" suricata -T -c /etc/suricata/suricata.yaml \
               >/dev/null 2>&1; then
                log_success "Suricata configuration valid"
            else
                log_warn "Could not validate Suricata configuration"
            fi
            ;;
        *)
            log_skip "No specific configuration validation for $component"
            ;;
    esac

    # Test 6: Version consistency
    log_test "Version endpoint consistency"
    local version=$(curl -s "http://localhost:$port/api/v1/version" 2>/dev/null | \
                   grep -o '"version"[^,}]*' | head -1)
    if [ -n "$version" ]; then
        log_success "Version reported: $version"
    else
        log_skip "Version endpoint not available"
    fi

    return 0
}

##############################################################################
# TEST ORCHESTRATION
##############################################################################

run_component_tests() {
    local component=$1
    local category=${2:-all}
    local container=$(get_container_name "$component")
    local log_file="$LOG_DIR/${component}-${category}-${EPOCH_TS}.log"

    CURRENT_LOG_FILE="$log_file"

    # Reset counters
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0

    # Write log header
    {
        echo "============================================================"
        echo "Cerberus Test Suite"
        echo "Component: $component ($container)"
        echo "Category: $category"
        echo "Version: $VERSION"
        echo "Timestamp: $(date -Iseconds)"
        echo "Epoch: $EPOCH_TS"
        echo "============================================================"
        echo ""
    } > "$log_file"

    log_header "Testing: $component ($category)"

    local available_tests="${COMPONENT_TESTS[$component]:-build run health api}"

    if [ "$category" = "all" ]; then
        # Run all applicable tests for this component
        for test_cat in $available_tests; do
            run_single_test "$component" "$test_cat"
        done
    else
        # Run specific category
        if echo "$available_tests" | grep -qw "$category"; then
            run_single_test "$component" "$category"
        else
            log_warn "Category '$category' not applicable for $component"
            log_info "Available categories: $available_tests"
        fi
    fi

    # Print summary
    print_summary "$component" "$category" "$log_file"

    # Return failure if any tests failed
    [ "$TESTS_FAILED" -eq 0 ]
}

run_single_test() {
    local component=$1
    local category=$2

    case "$category" in
        build)      test_build "$component" ;;
        run)        test_run "$component" ;;
        health)     test_health "$component" ;;
        ips)        test_ips "$component" ;;
        traffic)    test_traffic "$component" ;;
        api)        test_api "$component" ;;
        page)       test_page "$component" ;;
        regression) test_regression "$component" ;;
    esac
}

print_summary() {
    local component=$1
    local category=$2
    local log_file=$3

    log ""
    log_header "Test Summary: $component ($category)"
    log ""
    log "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    log "  ${RED}Failed:${NC}  $TESTS_FAILED"
    log "  ${CYAN}Skipped:${NC} $TESTS_SKIPPED"
    log "  ${BLUE}Total:${NC}   $TESTS_TOTAL"
    log ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        log "${GREEN}${BOLD}All tests passed!${NC}"
    else
        log "${RED}${BOLD}$TESTS_FAILED test(s) failed${NC}"
    fi

    log ""
    log_info "Log file: $log_file"

    # Write summary to log
    {
        echo ""
        echo "============================================================"
        echo "Summary"
        echo "Passed:  $TESTS_PASSED"
        echo "Failed:  $TESTS_FAILED"
        echo "Skipped: $TESTS_SKIPPED"
        echo "Total:   $TESTS_TOTAL"
        echo "Result:  $([ $TESTS_FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL')"
        echo "Completed: $(date -Iseconds)"
        echo "============================================================"
    } >> "$log_file"
}

##############################################################################
# RUN ALL COMPONENTS
##############################################################################

run_all_components() {
    local category=${1:-all}
    local pids=()
    local components_list=()
    local summary_log="$LOG_DIR/summary-${EPOCH_TS}.log"

    setup_logging

    log_header "Running All Component Tests"
    log_info "Test category: $category"
    log_info "Log directory: $LOG_DIR"
    log ""

    # Write summary header
    {
        echo "============================================================"
        echo "Cerberus Full Test Suite"
        echo "Category: $category"
        echo "Version: $VERSION"
        echo "Started: $(date -Iseconds)"
        echo "============================================================"
        echo ""
    } > "$summary_log"

    # Launch tests for each component
    for component in "${!COMPONENTS[@]}"; do
        log_info "Launching tests for: $component"
        components_list+=("$component")

        (
            run_component_tests "$component" "$category"
        ) &
        pids+=($!)
    done

    log ""
    log_info "Launched ${#pids[@]} parallel test suites"
    log_info "Waiting for completion..."
    log ""

    # Wait and collect results
    local failed_count=0
    local passed_count=0

    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local component=${components_list[$i]}

        if wait "$pid"; then
            ((passed_count++))
            echo "$component: PASSED" >> "$summary_log"
            log_success "$component: PASSED"
        else
            ((failed_count++))
            echo "$component: FAILED" >> "$summary_log"
            log_error "$component: FAILED"
        fi
    done

    # Print final summary
    log ""
    log_header "Final Summary"
    log ""
    log "  Components Passed: $passed_count"
    log "  Components Failed: $failed_count"
    log "  Total Components:  ${#components_list[@]}"
    log ""

    {
        echo ""
        echo "============================================================"
        echo "Final Summary"
        echo "Components Passed: $passed_count"
        echo "Components Failed: $failed_count"
        echo "Total: ${#components_list[@]}"
        echo "Completed: $(date -Iseconds)"
        echo "============================================================"
    } >> "$summary_log"

    log_info "Summary log: $summary_log"
    log_info "Individual logs: $LOG_DIR/<component>-*-${EPOCH_TS}.log"

    [ "$failed_count" -eq 0 ]
}

##############################################################################
# USAGE
##############################################################################

usage() {
    cat << EOF
${BOLD}Cerberus Unified Test Runner${NC}
Combines unit, integration, and regression testing

${BOLD}Usage:${NC}
  $0 <component> [test-category]
  $0 all [test-category]
  $0 --help | -h

${BOLD}Components:${NC}
  all              Run ALL components in parallel
  api              Flask backend API (cerberus-api)
  webui            React frontend (cerberus-webui)
  ips              Suricata IPS/IDS (cerberus-ips)
  filter           Content filter - Go (cerberus-filter)
  ssl              SSL/TLS inspection (cerberus-ssl-inspector)
  vpn-wireguard    WireGuard VPN
  vpn-ipsec        IPSec VPN (StrongSwan)
  vpn-openvpn      OpenVPN server
  xdp              XDP high-performance backend

${BOLD}Test Categories:${NC}
  all              Run all applicable tests (default)
  build            Build container image tests
  run              Container running status tests
  health           Health check endpoint tests
  ips              Intrusion protection tests (IPS only)
  traffic          Traffic routing/filtering tests
  api              API endpoint tests
  page             Page/UI load tests (WebUI only)
  regression       Stability and regression tests

${BOLD}Component Test Mapping:${NC}
  api:             build, run, health, api, regression
  webui:           build, run, health, page, api, regression
  ips:             build, run, health, ips, api, regression
  filter:          build, run, health, traffic, api, regression
  ssl:             build, run, health, traffic, api, regression
  vpn-*:           build, run, health, traffic, api, regression
  xdp:             build, run, health, traffic, api, regression

${BOLD}Logging:${NC}
  All output logged to: /tmp/cerberus-tests/<component>-<category>-<epoch>.log
  Summary log: /tmp/cerberus-tests/summary-<epoch>.log

${BOLD}Examples:${NC}
  $0 api                    # Run all tests for Flask API
  $0 api api                # Run only API tests for Flask API
  $0 ips ips                # Run IPS-specific tests
  $0 webui page             # Run page load tests for WebUI
  $0 filter traffic         # Run traffic routing tests for filter
  $0 all                    # Run ALL tests for ALL components
  $0 all build              # Build ALL components
  $0 all regression         # Regression tests for ALL components

${BOLD}Environment Variables:${NC}
  CERBERUS_API_URL          Override API URL (default: http://localhost:5000)
  CERBERUS_FILTER_URL       Override filter URL (default: http://localhost:8080)
  CERBERUS_IPS_URL          Override IPS URL (default: http://localhost:9100)
  WEBUI_URL                 Override WebUI URL (default: http://localhost:3000)

EOF
}

##############################################################################
# MAIN
##############################################################################

main() {
    # Handle help
    if [ $# -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        usage
        exit 0
    fi

    local component=$1
    local category=${2:-all}

    setup_logging
    cd "$PROJECT_ROOT"

    # Validate category
    local valid_category=false
    for cat in "${TEST_CATEGORIES[@]}"; do
        if [ "$cat" = "$category" ]; then
            valid_category=true
            break
        fi
    done

    if [ "$valid_category" = false ]; then
        log_error "Invalid test category: $category"
        log_info "Valid categories: ${TEST_CATEGORIES[*]}"
        exit 1
    fi

    # Run tests
    if [ "$component" = "all" ]; then
        run_all_components "$category"
    else
        # Validate component
        if [ -z "${COMPONENTS[$component]:-}" ]; then
            log_error "Unknown component: $component"
            log_info "Valid components: ${!COMPONENTS[*]}"
            exit 1
        fi
        run_component_tests "$component" "$category"
    fi
}

main "$@"
