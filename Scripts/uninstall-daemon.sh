#!/bin/bash
# Stops and removes the fan daemon. Stopping it hands the fans back to the system.
set -euo pipefail
LABEL="com.macfans.fanctld"

launchctl bootout system/"$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/${LABEL}.plist"
rm -rf /usr/local/libexec/macfans
rm -f /var/run/macfans.sock

echo "removed"
