#!/bin/bash
# Cerberus IPS - Health Check Script

# Check if Suricata process is running
if ! pgrep -x "suricata" > /dev/null; then
    echo "Suricata process not running"
    exit 1
fi

# Check if unix socket exists and is responsive
SOCKET="/var/run/suricata/suricata-command.socket"
if [ -S "${SOCKET}" ]; then
    # Try to get interface list via suricatasc
    RESULT=$(suricatasc -c "iface-list" "${SOCKET}" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Suricata healthy: ${RESULT}"
        exit 0
    fi
fi

# Fallback: just check process is running
echo "Suricata process running (socket check skipped)"
exit 0
