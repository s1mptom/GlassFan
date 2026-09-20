#!/bin/zsh
# glass-lab.sh: the glass bench, driven from the shell - no pointer, no window in the way.
#
#   Scripts/glass-lab.sh [-t "knob=value,..."] [-d x,y] [-p track|lines|text] [-s WxH]
#                        [-z x,y,w,h] [-m N] out.png
#
#   -t  knobs for LensTuning (names as in LensTuning.knobs), e.g. "pullStrength=3,flatEnd=5"
#   -d  where the drop is held, in the bench's coordinates (default: over the small track)
#   -p  the ground pattern: track, lines, text, or apple - Activity Monitor's control from a
#       2x screenshot (-g, default Scripts/lab/apple-track.png) at its true size, top-left at (20,200)
#   -s  the drop's size in points (default 120x46)
#   -z  crop the shot to this rectangle of the bench, in points, and magnify it (-m, default 4)
#   -c  compare: also run with the app's own defaults and stack the two crops, defaults on top
#
# Needs GlassFan.app built (Scripts/build-app.sh). Backs up and restores the app's defaults.
# Screenshots are lossless PNG; video recordings are not (chroma subsampling washes the rim out).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TUNE="" DROP="400,224" PATTERN="track" SIZE="120x46" ZOOM="" MAG=4 COMPARE=0 GROUND="$ROOT/Scripts/lab/apple-track.png"
while getopts "t:d:p:s:z:m:cg:" opt; do
  case $opt in
    t) TUNE=$OPTARG ;; d) DROP=$OPTARG ;; p) PATTERN=$OPTARG ;; s) SIZE=$OPTARG ;;
    z) ZOOM=$OPTARG ;; m) MAG=$OPTARG ;; c) COMPARE=1 ;; g) GROUND=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
OUT=${1:?output png}
BIN="$ROOT/.build/lab"; mkdir -p "$BIN"
for tool in winid backdrop; do
  [[ -x "$BIN/$tool" && "$BIN/$tool" -nt "$ROOT/Scripts/lab/$tool.swift" ]] || swiftc -O -o "$BIN/$tool" "$ROOT/Scripts/lab/$tool.swift" 2>/dev/null
done
W=${SIZE%x*}; H=${SIZE#*x}

shoot() { # shoot <tune> <png>
  local tune=$1 png=$2 backup
  # A plain dark window behind the app: its backing is translucent, and whatever is
  # behind it would otherwise show through the shot.
  "$BIN/backdrop" & local bd=$!
  sleep 0.6
  backup=$(mktemp)
  defaults export com.glassfan.app "$backup"
  defaults write com.glassfan.app screen -string overview
  GLASSFAN_DEMO=1 GLASSFAN_DEMO_CURVES=3 GLASSFAN_LAB=1 GLASSFAN_LAB_DROP="$DROP" GLASSFAN_LAB_PATTERN="$PATTERN" GLASSFAN_LAB_GROUND="$GROUND" \
    GLASSFAN_TUNE="dropWidth=$W,dropHeight=$H${tune:+,$tune}" \
    "$ROOT/GlassFan.app/Contents/MacOS/GlassFan" >/dev/null 2>&1 &
  local pid=$!
  sleep 4
  local wid; wid=$("$BIN/winid" $pid)
  screencapture -x -o -l "$wid" "$png"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
  kill $bd 2>/dev/null
  defaults import com.glassfan.app "$backup"; rm -f "$backup"
  if [[ -n "$ZOOM" ]]; then
    # The bench sits 12pt in from the window's left edge and 87pt down (title bar
    # and the pattern picker); shots are 2x.
    local x y w h; IFS=, read x y w h <<<"$ZOOM"
    ffmpeg -loglevel error -y -i "$png" -vf "crop=$((w*2)):$((h*2)):$(((x+12)*2)):$(((y+87)*2)),scale=iw*$MAG:-1:flags=neighbor" "$png.crop.png"
    mv "$png.crop.png" "$png"
  fi
}

if (( COMPARE )); then
  shoot "" "${OUT%.png}-defaults.png"
  shoot "$TUNE" "${OUT%.png}-tuned.png"
  ffmpeg -loglevel error -y -i "${OUT%.png}-defaults.png" -i "${OUT%.png}-tuned.png" -filter_complex "[0][1]vstack" "$OUT"
else
  shoot "$TUNE" "$OUT"
fi
echo "$OUT"
