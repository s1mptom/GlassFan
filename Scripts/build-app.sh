#!/bin/bash
# Assembles GlassFan.app from the SwiftPM build. No Xcode project needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/GlassFan.app"
CONFIG="${1:-release}"

cd "$ROOT"
echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product GlassFan
swift build -c "$CONFIG" --product fanctld

echo "==> Icon"
if [[ ! -f build/AppIcon.icns ]]; then
    swift Scripts/make-icon.swift >/dev/null
    iconutil -c icns build/GlassFan.iconset -o build/AppIcon.icns
fi

BIN="$ROOT/.build/$CONFIG/GlassFan"
[[ -x "$BIN" ]] || { echo "no binary produced"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GlassFan"

# Everything the app needs to install the daemon itself, so there is no separate
# download and no terminal step.
cp "$ROOT/.build/$CONFIG/fanctld"                    "$APP/Contents/Resources/fanctld"
cp "$ROOT/Scripts/install-daemon.sh"                 "$APP/Contents/Resources/"
cp "$ROOT/Scripts/uninstall-daemon.sh"               "$APP/Contents/Resources/"
cp "$ROOT/Scripts/com.glassfan.fanctld.plist"         "$APP/Contents/Resources/"
cp "$ROOT/build/AppIcon.icns"                        "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/fanctld" "$APP/Contents/Resources/"*.sh

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GlassFan</string>
    <key>CFBundleDisplayName</key><string>GlassFan</string>
    <key>CFBundleIdentifier</key><string>com.glassfan.app</string>
    <key>CFBundleExecutable</key><string>GlassFan</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally without a Developer ID.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "codesign failed (app may still run)"; }

echo "Built $APP"
