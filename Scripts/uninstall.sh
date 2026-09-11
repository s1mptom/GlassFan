#!/bin/bash
# Stops the daemon (which releases the fans back to the system) and removes it.
set -euo pipefail
LABEL="com.macfans.fanctld"

echo "==> Stopping the daemon"
sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sleep 1

echo "==> Removing files"
sudo rm -f "/Library/LaunchDaemons/${LABEL}.plist"
sudo rm -rf /usr/local/libexec/macfans
sudo rm -f /var/run/macfans.sock

echo "==> Making sure the fans are back under system control"
echo "    (config is left at /Library/Application Support/MacFans/config.json;"
echo "     delete it by hand if you want a clean slate)"
echo "Done."
