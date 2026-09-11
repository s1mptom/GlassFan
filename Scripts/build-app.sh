#!/bin/bash
# Assembles MacFans.app from the SwiftPM build. No Xcode project needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/MacFans.app"
CONFIG="${1:-release}"

cd "$ROOT"
echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product MacFans

BIN="$ROOT/.build/$CONFIG/MacFans"
[[ -x "$BIN" ]] || { echo "no binary produced"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacFans"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacFans</string>
    <key>CFBundleDisplayName</key><string>MacFans</string>
    <key>CFBundleIdentifier</key><string>com.macfans.app</string>
    <key>CFBundleExecutable</key><string>MacFans</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally without a Developer ID.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "codesign failed (app may still run)"; }

echo "Built $APP"
