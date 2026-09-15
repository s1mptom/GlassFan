#!/bin/bash
# Assembles GlassFan.app from the SwiftPM build. No Xcode project needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/GlassFan.app"
CONFIG="${1:-release}"

# Version and build number go into Info.plist. A release sets them from its tag;
# a local build gets the last tag, or 0.1.0 before there is one.
VERSION="${GLASSFAN_VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
BUILD="${GLASSFAN_BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"

# A Developer ID identity signs for distribution, with the hardened runtime and a
# timestamp, which notarisation requires. Without one the app is signed ad hoc:
# enough to run, but a downloaded copy has to be let through Gatekeeper by hand.
IDENTITY="${GLASSFAN_SIGN_IDENTITY:-}"

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
# The interface's resources: the compiled glass lens shader.
cp -R "$ROOT/.build/$CONFIG/GlassFan_GlassFanUI.bundle" "$APP/Contents/Resources/"
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
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

if [[ -n "$IDENTITY" ]]; then
    echo "==> Signing with $IDENTITY"
    # Inside out: the daemon is a separate executable in Resources, and a bundle's
    # signature only seals it, it does not sign it.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/fanctld"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=1 "$APP"
else
    # Ad-hoc signature: enough to run without a Developer ID.
    codesign --force --sign - --timestamp=none "$APP/Contents/Resources/fanctld" >/dev/null 2>&1 || true
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
        echo "codesign failed (app may still run)"; }
fi

echo "Built $APP ($VERSION, build $BUILD)"
