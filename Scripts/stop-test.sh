#!/bin/bash
# Hardware experiment: can a fan be told to go below its SMC minimum, or to 0?
#
# Stops the daemon so it cannot argue with the test, asks each fan for 1000,
# 500 and 0 rpm in turn (five seconds each), prints what the fan actually did
# and what the SMC kept as the target, releases every fan back to the system,
# and restarts the daemon - on any exit, including a failure or Ctrl-C.
#
# Needs root for the SMC:  sudo Scripts/stop-test.sh            (targets 1000/500/0, 5 s each)
#                          sudo Scripts/stop-test.sh --stall-test  (hold 1300/1000/600 for 40 s each, per second)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.build/debug/fanctld"
PLIST=/Library/LaunchDaemons/com.glassfan.fanctld.plist
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
[[ -x "$BIN" ]] || { echo "build first: swift build --product fanctld"; exit 1; }

restore() {
    launchctl bootstrap system "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null
    sleep 1
    echo "daemon restarted: $(pgrep -x fanctld | head -1)"
}
trap restore EXIT

launchctl bootout system/com.glassfan.fanctld 2>/dev/null; sleep 1
echo "daemon stopped (fanctld running: $(pgrep -x fanctld | tr '\n' ' ')none)"
"$BIN" "${1:---stop-test}"
