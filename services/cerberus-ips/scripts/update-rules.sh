#!/bin/bash
# Cerberus IPS - Rule Update Script

set -e

RULES_DIR=/var/lib/suricata/rules
SURICATA_UPDATE_CONF=/etc/suricata/update.yaml

echo "=== Updating Suricata Rules ==="

# Run suricata-update
suricata-update update \
    --suricata-conf /etc/suricata/suricata.yaml \
    --output-dir ${RULES_DIR} \
    --no-test \
    --no-reload

# If suricata is running, reload rules
if [ -S /var/run/suricata/suricata-command.socket ]; then
    echo "Reloading Suricata rules..."
    suricatasc -c reload-rules /var/run/suricata/suricata-command.socket || true
fi

echo "Rule update complete"
echo "Rules directory: ${RULES_DIR}"
ls -la ${RULES_DIR}/*.rules 2>/dev/null || echo "No rules files found"
