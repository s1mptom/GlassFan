#!/bin/bash
# Installs the fan daemon. Runs as root, launched by the app through the system
# authorisation dialog.
#
# Lives inside the app bundle on purpose: a root script must not sit anywhere the
# user (or anything running as the user) can rewrite between the write and the run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.macfans.fanctld"
DEST="/usr/local/libexec/macfans"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
MFC_LABEL="com.crystalidea.macsfancontrol.smcwrite"

# Another utility holding the same SMC keys would fight this daemon.
if pgrep -f "$MFC_LABEL" >/dev/null 2>&1; then
    echo "stopping $MFC_LABEL"
    launchctl bootout system/"$MFC_LABEL" 2>/dev/null || true
fi

mkdir -p "$DEST"
cp "$HERE/fanctld" "$DEST/fanctld"
chown root:wheel "$DEST/fanctld"
chmod 755 "$DEST/fanctld"

cp "$HERE/com.macfans.fanctld.plist" "$PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootout system/"$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

echo "installed"
