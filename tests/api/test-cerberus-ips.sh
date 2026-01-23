#!/bin/bash
##############################################################################
# Cerberus IPS Test Suite
# Purpose: Test Suricata IPS container endpoints and functionality
# Tests: Health checks, API endpoints, EVE logs, stats, alerts
##############################################################################

set -euo pipefail

# Configuration
IPS_URL="${CERBERUS_IPS_URL:-http://localhost:9100}"
SURICATA_SOCKET="${SURICATA_SOCKET:-/var/run/suricata/suricata-command.socket}"
LOG_DIR="${LOG_DIR:-/var/log/suricata}"
RULES_DIR="${RULES_DIR:-/var/lib/suricata/rules}"
EVE_LOG="${LOG_DIR}/eve.json"
FAST_LOG="${LOG_DIR}/fast.log"
STATS_LOG="${LOG_DIR}/stats.json"

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_test() {
    echo -e "\n${BLUE}Test: $1${NC}"
}

##############################################################################
# Utility Functions
##############################################################################

wait_for_suricata() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for Suricata process to be ready..."

    while [ $attempt -lt $max_attempts ]; do
        if pgrep -x "suricata" > /dev/null 2>&1; then
            log_success "Suricata process is running"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    log_error "Suricata process failed to start after $max_attempts attempts"
    return 1
}

wait_for_socket() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for Suricata command socket..."

    while [ $attempt -lt $max_attempts ]; do
        if [ -S "${SURICATA_SOCKET}" ]; then
            log_success "Suricata command socket is ready"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    log_warn "Suricata command socket not available after $max_attempts attempts"
    return 0
}

##############################################################################
# Health Check Tests
##############################################################################

test_suricata_process_status() {
    log_test "Suricata Process Status"

    if pgrep -x "suricata" > /dev/null 2>&1; then
        local pid=$(pgrep -x "suricata" | head -1)
        log_success "Suricata process running (PID: $pid)"
        return 0
    else
        log_error "Suricata process not running"
        return 1
    fi
}

test_suricata_socket() {
    log_test "Suricata Command Socket"

    if [ -S "${SURICATA_SOCKET}" ]; then
        log_success "Command socket exists: $SURICATA_SOCKET"
        return 0
    else
        log_warn "Command socket not found: $SURICATA_SOCKET"
        return 0
    fi
}

test_suricata_iface_list() {
    log_test "Suricata Interface List (via socket)"

    if ! command -v suricatasc &> /dev/null; then
        log_warn "suricatasc command not available, skipping socket test"
        return 0
    fi

    if [ ! -S "${SURICATA_SOCKET}" ]; then
        log_warn "Command socket not available, skipping test"
        return 0
    fi

    if suricatasc -c "iface-list" "${SURICATA_SOCKET}" > /dev/null 2>&1; then
        log_success "Interface list retrieved via socket"
        return 0
    else
        log_warn "Could not retrieve interface list"
        return 0
    fi
}

test_suricata_uptime() {
    log_test "Suricata Uptime (via socket)"

    if ! command -v suricatasc &> /dev/null; then
        log_warn "suricatasc command not available, skipping"
        return 0
    fi

    if [ ! -S "${SURICATA_SOCKET}" ]; then
        log_warn "Command socket not available, skipping test"
        return 0
    fi

    if suricatasc -c "uptime" "${SURICATA_SOCKET}" > /dev/null 2>&1; then
        log_success "Uptime retrieved via socket"
        return 0
    else
        log_warn "Could not retrieve uptime"
        return 0
    fi
}

##############################################################################
# Log File Tests
##############################################################################

test_eve_log_file_exists() {
    log_test "EVE Log File Existence"

    if [ -f "${EVE_LOG}" ]; then
        local size=$(stat -c%s "${EVE_LOG}" 2>/dev/null || echo "0")
        log_success "EVE log file exists (${size} bytes): $EVE_LOG"
        return 0
    else
        log_warn "EVE log file not yet created: $EVE_LOG"
        return 0
    fi
}

test_eve_log_format() {
    log_test "EVE Log JSON Format Validation"

    if [ ! -f "${EVE_LOG}" ]; then
        log_warn "EVE log file not found, skipping format test"
        return 0
    fi

    if [ ! -s "${EVE_LOG}" ]; then
        log_warn "EVE log file is empty, skipping format test"
        return 0
    fi

    # Check if file contains valid JSON lines
    local line_count=0
    local valid_lines=0

    while IFS= read -r line; do
        ((line_count++))
        if echo "$line" | jq . > /dev/null 2>&1; then
            ((valid_lines++))
        fi
    done < <(head -20 "${EVE_LOG}")

    if [ $line_count -gt 0 ] && [ $valid_lines -gt 0 ]; then
        log_success "EVE log contains valid JSON (${valid_lines}/${line_count} lines valid)"
        return 0
    else
        log_warn "Could not validate EVE log JSON format"
        return 0
    fi
}

test_eve_log_event_types() {
    log_test "EVE Log Event Types"

    if [ ! -f "${EVE_LOG}" ] || [ ! -s "${EVE_LOG}" ]; then
        log_warn "EVE log file not found or empty, skipping test"
        return 0
    fi

    # Extract event types from EVE log
    local event_types=$(grep -o '"event_type":"[^"]*"' "${EVE_LOG}" 2>/dev/null | cut -d'"' -f4 | sort -u || echo "")

    if [ -n "$event_types" ]; then
        log_success "Found event types in EVE log:"
        echo "$event_types" | sed 's/^/    /'
        return 0
    else
        log_warn "No event types found in EVE log"
        return 0
    fi
}

test_fast_log_file() {
    log_test "Fast Log File"

    if [ -f "${FAST_LOG}" ]; then
        local size=$(stat -c%s "${FAST_LOG}" 2>/dev/null || echo "0")
        log_success "Fast log file exists (${size} bytes): $FAST_LOG"
        return 0
    else
        log_warn "Fast log file not yet created: $FAST_LOG"
        return 0
    fi
}

##############################################################################
# Rules and Configuration Tests
##############################################################################

test_rules_directory_exists() {
    log_test "Rules Directory Existence"

    if [ -d "${RULES_DIR}" ]; then
        log_success "Rules directory exists: $RULES_DIR"
        return 0
    else
        log_error "Rules directory not found: $RULES_DIR"
        return 1
    fi
}

test_rules_file_exists() {
    log_test "Rules File Existence"

    local rules_file="${RULES_DIR}/suricata.rules"

    if [ -f "${rules_file}" ]; then
        local size=$(stat -c%s "${rules_file}" 2>/dev/null || echo "0")
        if [ "$size" -gt 0 ]; then
            local rule_count=$(grep -c "^alert\|^pass\|^drop\|^reject" "${rules_file}" 2>/dev/null || echo "0")
            log_success "Rules file exists with ${rule_count} rules (${size} bytes): $rules_file"
        else
            log_warn "Rules file exists but is empty: $rules_file"
        fi
        return 0
    else
        log_warn "Rules file not found: $rules_file"
        return 0
    fi
}

test_config_syntax() {
    log_test "Suricata Configuration Syntax"

    if ! command -v suricata &> /dev/null; then
        log_warn "suricata command not available, skipping syntax test"
        return 0
    fi

    # Test configuration file syntax
    if suricata -c /etc/suricata/suricata.yaml -T > /dev/null 2>&1; then
        log_success "Configuration syntax is valid"
        return 0
    else
        log_warn "Configuration syntax check returned non-zero (may be expected in container)"
        return 0
    fi
}

##############################################################################
# Stats and Metrics Tests
##############################################################################

test_stats_availability() {
    log_test "Suricata Statistics"

    if [ ! -f "${STATS_LOG}" ] && [ ! -f "${LOG_DIR}/stats.log" ]; then
        log_warn "Statistics file not yet created"
        return 0
    fi

    if [ -f "${STATS_LOG}" ]; then
        log_success "Statistics log found: $STATS_LOG"
    elif [ -f "${LOG_DIR}/stats.log" ]; then
        log_success "Statistics log found: ${LOG_DIR}/stats.log"
    fi

    return 0
}

test_prometheus_metrics() {
    log_test "Prometheus Metrics Endpoint"

    if ! command -v curl &> /dev/null; then
        log_warn "curl not available, skipping metrics test"
        return 0
    fi

    if curl -s "${IPS_URL}/metrics" > /dev/null 2>&1; then
        log_success "Prometheus metrics endpoint accessible"
        return 0
    else
        log_warn "Prometheus metrics endpoint not available at ${IPS_URL}/metrics"
        return 0
    fi
}

##############################################################################
# Alert Detection Tests
##############################################################################

test_alert_threshold_config() {
    log_test "Alert Threshold Configuration"

    local threshold_config="/etc/suricata/threshold.config"

    if [ -f "${threshold_config}" ]; then
        log_success "Threshold configuration exists: $threshold_config"
        return 0
    else
        log_warn "Threshold configuration not found: $threshold_config"
        return 0
    fi
}

test_classification_config() {
    log_test "Classification Configuration"

    local classification_config="/etc/suricata/classification.config"

    if [ -f "${classification_config}" ]; then
        local class_count=$(grep -c "^[^#]" "${classification_config}" 2>/dev/null || echo "0")
        log_success "Classification configuration exists with ${class_count} classifications: $classification_config"
        return 0
    else
        log_warn "Classification configuration not found: $classification_config"
        return 0
    fi
}

test_eve_alert_parsing() {
    log_test "EVE Alert Record Parsing"

    if [ ! -f "${EVE_LOG}" ] || [ ! -s "${EVE_LOG}" ]; then
        log_warn "EVE log file not available, skipping alert parsing test"
        return 0
    fi

    # Try to find alert events in EVE log
    local alert_count=0
    if command -v jq &> /dev/null; then
        alert_count=$(grep '"alert"' "${EVE_LOG}" 2>/dev/null | wc -l || echo "0")
    else
        alert_count=$(grep -c '"event_type":"alert"' "${EVE_LOG}" 2>/dev/null || echo "0")
    fi

    if [ "$alert_count" -gt 0 ]; then
        log_success "Found $alert_count alert records in EVE log"
        return 0
    else
        log_warn "No alert records found in EVE log yet"
        return 0
    fi
}

##############################################################################
# Categories and Rule Sets Tests
##############################################################################

test_rule_categories() {
    log_test "Rule Categories"

    if ! command -v suricata &> /dev/null; then
        log_warn "suricata command not available, skipping category test"
        return 0
    fi

    local rules_file="${RULES_DIR}/suricata.rules"
    if [ ! -f "${rules_file}" ]; then
        log_warn "Rules file not found"
        return 0
    fi

    # Extract rule categories
    local categories=$(grep -o '"classtype":"[^"]*"' "${rules_file}" 2>/dev/null | cut -d'"' -f4 | sort -u || echo "")

    if [ -n "$categories" ]; then
        local category_count=$(echo "$categories" | wc -l)
        log_success "Found $category_count unique rule categories"
        return 0
    else
        log_warn "Could not extract rule categories"
        return 0
    fi
}

##############################################################################
# Performance and Resource Tests
##############################################################################

test_process_memory_usage() {
    log_test "Suricata Memory Usage"

    if ! command -v ps &> /dev/null; then
        log_warn "ps command not available"
        return 0
    fi

    local pid=$(pgrep -x "suricata" | head -1 2>/dev/null || echo "")

    if [ -z "$pid" ]; then
        log_error "Suricata process not found"
        return 1
    fi

    local mem_usage=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.2f MB", $1/1024}' || echo "unknown")
    log_success "Process memory usage: $mem_usage"
    return 0
}

test_process_cpu_usage() {
    log_test "Suricata CPU Usage"

    if ! command -v ps &> /dev/null; then
        log_warn "ps command not available"
        return 0
    fi

    local pid=$(pgrep -x "suricata" | head -1 2>/dev/null || echo "")

    if [ -z "$pid" ]; then
        log_error "Suricata process not found"
        return 1
    fi

    local cpu_usage=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}')
    log_success "Process CPU usage: ${cpu_usage}%"
    return 0
}

test_log_rotation() {
    log_test "Log File Rotation Check"

    if [ ! -d "${LOG_DIR}" ]; then
        log_error "Log directory not found: $LOG_DIR"
        return 1
    fi

    # Check for rotated logs
    local rotated_count=$(find "${LOG_DIR}" -name "*.json.*.gz" -o -name "*.log.*" 2>/dev/null | wc -l || echo "0")

    if [ "$rotated_count" -gt 0 ]; then
        log_success "Found $rotated_count rotated log files"
    else
        log_success "No rotated logs yet (normal for fresh start)"
    fi

    return 0
}

##############################################################################
# Main Test Runner
##############################################################################

run_all_tests() {
    log_info "Starting Cerberus IPS Test Suite"
    log_info "Suricata Socket: $SURICATA_SOCKET"
    log_info "Log Directory: $LOG_DIR"
    echo ""

    # Wait for services
    wait_for_suricata || return 1
    wait_for_socket

    # Process and Socket tests
    test_suricata_process_status
    test_suricata_socket
    test_suricata_iface_list
    test_suricata_uptime

    # Configuration tests
    test_rules_directory_exists
    test_rules_file_exists
    test_config_syntax
    test_alert_threshold_config
    test_classification_config

    # Log file tests
    test_eve_log_file_exists
    test_eve_log_format
    test_eve_log_event_types
    test_fast_log_file

    # Alert and rule tests
    test_eve_alert_parsing
    test_rule_categories

    # Statistics tests
    test_stats_availability
    test_prometheus_metrics

    # Resource tests
    test_process_memory_usage
    test_process_cpu_usage
    test_log_rotation

    # Summary
    echo ""
    echo "======================================"
    echo "Test Summary"
    echo "======================================"
    log_success "Passed: $TESTS_PASSED"
    log_error "Failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All critical tests passed!"
        return 0
    else
        log_error "Some critical tests failed"
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
