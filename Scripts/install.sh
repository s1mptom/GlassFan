#!/bin/bash
# Builds the daemon, proves on real hardware that it can move a fan, then installs it
# as a LaunchDaemon. Run as your normal user; it asks for sudo where it needs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/Scripts/sudo-helper.sh"
LABEL="com.macfans.fanctld"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
DEST="/usr/local/libexec/macfans"

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not with sudo - it asks for the password itself."
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
    run_root launchctl bootout system/"$MFC_LABEL" 2>/dev/null || true
    sleep 1
    if pgrep -f "$MFC_LABEL" >/dev/null 2>&1; then
        echo "    Could not stop it. Quit Macs Fan Control and run this again."
        exit 1
    fi
    echo "    Stopped."
fi

echo
echo "==> Hardware self-test (fan 0 will get loud for about 10 seconds)"
if run_root "$BIN" --selftest; then
    echo "Self-test passed."
else
    echo
    echo "Self-test did not pass. Not installing the daemon."
    exit 1
fi

echo
echo "==> Installing to $DEST"
run_root mkdir -p "$DEST"
run_root cp "$BIN" "$DEST/fanctld"
run_root chown root:wheel "$DEST/fanctld"
run_root chmod 755 "$DEST/fanctld"

run_root cp "$ROOT/Scripts/${LABEL}.plist" "$PLIST"
run_root chown root:wheel "$PLIST"
run_root chmod 644 "$PLIST"

echo "==> Loading the daemon"
run_root launchctl bootout system/"$LABEL" 2>/dev/null || true
run_root launchctl bootstrap system "$PLIST"
sleep 2

if run_root launchctl print system/"$LABEL" >/dev/null 2>&1; then
    echo "Daemon is running."
    echo
    echo "Socket: $(ls -l /var/run/macfans.sock 2>/dev/null || echo 'not created yet')"
    echo "Log:    /var/log/macfans.log"
    tail -n 12 /var/log/macfans.log 2>/dev/null || true
else
    echo "Daemon failed to start. Check /var/log/macfans.log"
    exit 1
fi
