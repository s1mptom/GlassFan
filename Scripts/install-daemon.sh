#!/bin/bash
# Installs the fan daemon. Runs as root, launched by the app through the system
# authorisation dialog.
#
# Lives inside the app bundle on purpose: a root script must not sit anywhere the
# user (or anything running as the user) can rewrite between the write and the run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.glassfan.fanctld"
DEST="/usr/local/libexec/glassfan"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
MFC_LABEL="com.crystalidea.macsfancontrol.smcwrite"

# Another utility holding the same SMC keys would fight this daemon.
if pgrep -f "$MFC_LABEL" >/dev/null 2>&1; then
    echo "stopping $MFC_LABEL"
    launchctl bootout system/"$MFC_LABEL" 2>/dev/null || true
fi

# The app used to be MacFans. Take its daemon down and carry its config over,
# so an upgrade is not a second daemon fighting the first over the same fans.
OLD_LABEL="com.macfans.fanctld"
if [[ -f "/Library/LaunchDaemons/${OLD_LABEL}.plist" ]]; then
    echo "removing the MacFans daemon"
    launchctl bootout system/"$OLD_LABEL" 2>/dev/null || true
    rm -f "/Library/LaunchDaemons/${OLD_LABEL}.plist"
    rm -rf /usr/local/libexec/macfans
    rm -f /var/run/macfans.sock
fi
if [[ -f "/Library/Application Support/MacFans/config.json" && ! -f "/Library/Application Support/GlassFan/config.json" ]]; then
    echo "carrying the MacFans config over"
    mkdir -p "/Library/Application Support/GlassFan"
    mv "/Library/Application Support/MacFans/config.json" "/Library/Application Support/GlassFan/config.json"
fi

mkdir -p "$DEST"
# -X leaves the app's extended attributes behind. An app downloaded from a release
# carries the quarantine flag on every file inside it; opening the app clears it for
# the app, not for a copy of its daemon, and a quarantined binary launched by launchd
# is refused. The daemon is installed as a file of our own, not a download.
cp -X "$HERE/fanctld" "$DEST/fanctld"
xattr -c "$DEST/fanctld" 2>/dev/null || true
chown root:wheel "$DEST/fanctld"
chmod 755 "$DEST/fanctld"

cp -X "$HERE/com.glassfan.fanctld.plist" "$PLIST"
xattr -c "$PLIST" 2>/dev/null || true
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootout system/"$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

echo "installed"
