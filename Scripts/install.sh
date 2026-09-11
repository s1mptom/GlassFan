#!/bin/bash
# Builds the daemon, proves on real hardware that it can move a fan, then installs it
# as a LaunchDaemon. Run as your normal user; it asks for sudo where it needs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.macfans.fanctld"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
DEST="/usr/local/libexec/macfans"

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not with sudo - it will ask for the password itself."
    exit 1
fi

echo "==> Building"
cd "$ROOT"
swift build -c release --product fanctld

BIN="$ROOT/.build/release/fanctld"
[[ -x "$BIN" ]] || { echo "build produced no binary"; exit 1; }

# Another fan utility holding the SMC will fight this daemon over the same keys.
MFC_LABEL="com.crystalidea.macsfancontrol.smcwrite"
if pgrep -f "$MFC_LABEL" >/dev/null 2>&1; then
    echo
    echo "==> Macs Fan Control's privileged helper is running and would fight this daemon."
    echo "    Stopping it (its files are left in place, so Macs Fan Control can restore it)."
    sudo launchctl bootout system/"$MFC_LABEL" 2>/dev/null || true
    sleep 1
    if pgrep -f "$MFC_LABEL" >/dev/null 2>&1; then
        echo "    Could not stop it. Quit Macs Fan Control and run this again."
        exit 1
    fi
    echo "    Stopped."
fi

echo
echo "==> Hardware self-test (fan 0 will get loud for about 10 seconds)"
if sudo "$BIN" --selftest; then
    echo "Self-test passed."
else
    echo
    echo "Self-test did not pass. Not installing the daemon."
    exit 1
fi

echo
echo "==> Installing to $DEST"
sudo mkdir -p "$DEST"
sudo cp "$BIN" "$DEST/fanctld"
sudo chown root:wheel "$DEST/fanctld"
sudo chmod 755 "$DEST/fanctld"

sudo cp "$ROOT/Scripts/${LABEL}.plist" "$PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

echo "==> Loading the daemon"
sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
sleep 2

if sudo launchctl print system/"$LABEL" >/dev/null 2>&1; then
    echo "Daemon is running."
    echo
    echo "Socket: $(ls -l /var/run/macfans.sock 2>/dev/null || echo 'not created yet')"
    echo "Log:    /var/log/macfans.log"
    tail -n 12 /var/log/macfans.log 2>/dev/null || true
else
    echo "Daemon failed to start. Check /var/log/macfans.log"
    exit 1
fi
