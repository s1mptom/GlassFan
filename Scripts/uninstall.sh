#!/bin/bash
# Stops the daemon (which releases the fans back to the system) and removes it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/Scripts/sudo-helper.sh"
LABEL="com.macfans.fanctld"

echo "==> Stopping the daemon"
run_root launchctl bootout system/"$LABEL" 2>/dev/null || true
sleep 1

echo "==> Removing files"
run_root rm -f "/Library/LaunchDaemons/${LABEL}.plist"
run_root rm -rf /usr/local/libexec/macfans
run_root rm -f /var/run/macfans.sock

echo "==> Making sure the fans are back under system control"
echo "    (config is left at /Library/Application Support/MacFans/config.json;"
echo "     delete it by hand if you want a clean slate)"
echo "Done."
