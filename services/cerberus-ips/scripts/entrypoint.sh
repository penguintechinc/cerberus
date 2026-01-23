#!/bin/bash
# Cerberus IPS - Entrypoint Script

set -e

# Configuration from environment
SURICATA_MODE=${SURICATA_MODE:-ips}
SURICATA_INTERFACE=${SURICATA_INTERFACE:-eth0}
SURICATA_HOME_NET=${SURICATA_HOME_NET:-"[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"}
LOG_LEVEL=${LOG_LEVEL:-info}
NFQ_QUEUE=${NFQ_QUEUE:-0}

echo "=== Cerberus IPS Starting ==="
echo "Mode: ${SURICATA_MODE}"
echo "Interface: ${SURICATA_INTERFACE}"
echo "Home Net: ${SURICATA_HOME_NET}"

# Update HOME_NET in configuration
sed -i "s|HOME_NET:.*|HOME_NET: \"${SURICATA_HOME_NET}\"|" /etc/suricata/suricata.yaml

# Create required directories
mkdir -p /var/log/suricata
mkdir -p /var/run/suricata
mkdir -p /var/lib/suricata/rules

# Check if rules exist, if not download them
if [ ! -f /var/lib/suricata/rules/suricata.rules ] || [ ! -s /var/lib/suricata/rules/suricata.rules ]; then
    echo "Downloading initial ruleset..."
    /usr/local/bin/update-rules.sh || echo "Warning: Could not download rules, starting with empty ruleset"

    # Create empty rules file if download failed
    if [ ! -f /var/lib/suricata/rules/suricata.rules ]; then
        echo "# Empty ruleset - update rules to enable detection" > /var/lib/suricata/rules/suricata.rules
    fi
fi

# Set interface to promiscuous mode
ip link set ${SURICATA_INTERFACE} promisc on 2>/dev/null || echo "Warning: Could not set promiscuous mode"

# Disable offloading features for accurate packet capture
ethtool -K ${SURICATA_INTERFACE} gro off gso off tso off lro off 2>/dev/null || echo "Warning: Could not disable offloading"

# Build Suricata command based on mode
SURICATA_CMD="suricata -c /etc/suricata/suricata.yaml"

case ${SURICATA_MODE} in
    "ips")
        echo "Starting in IPS mode (inline) with AF_PACKET..."
        SURICATA_CMD="${SURICATA_CMD} --af-packet=${SURICATA_INTERFACE}"
        ;;
    "ips-nfq")
        echo "Starting in IPS mode (inline) with NFQUEUE..."
        SURICATA_CMD="${SURICATA_CMD} -q ${NFQ_QUEUE}"
        ;;
    "ids")
        echo "Starting in IDS mode (passive)..."
        SURICATA_CMD="${SURICATA_CMD} -i ${SURICATA_INTERFACE}"
        ;;
    *)
        echo "Unknown mode: ${SURICATA_MODE}, defaulting to IDS"
        SURICATA_CMD="${SURICATA_CMD} -i ${SURICATA_INTERFACE}"
        ;;
esac

# Add verbosity based on log level
case ${LOG_LEVEL} in
    "debug")
        SURICATA_CMD="${SURICATA_CMD} -v"
        ;;
    "info")
        # Default verbosity
        ;;
    "notice"|"warning"|"error")
        # Less verbose
        ;;
esac

# Start Suricata
echo "Executing: ${SURICATA_CMD}"
exec ${SURICATA_CMD}
