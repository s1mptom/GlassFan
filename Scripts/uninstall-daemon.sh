#!/bin/bash
# Stops and removes the fan daemon. Stopping it hands the fans back to the system.
set -euo pipefail
LABEL="com.glassfan.fanctld"

launchctl bootout system/"$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/${LABEL}.plist"
rm -rf /usr/local/libexec/glassfan
rm -f /var/run/glassfan.sock

# Leftovers of the MacFans-era install, if any.
launchctl bootout system/com.macfans.fanctld 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.macfans.fanctld.plist
rm -rf /usr/local/libexec/macfans
rm -f /var/run/macfans.sock
echo "removed"
