#!/bin/bash
# Builds GlassFan.app and packages it for download: a disk image to drag the app
# from, a zip of the app, and their checksums, in dist/.
#
#   Scripts/package-release.sh 0.2.0
#
# Signing and notarisation are used when their settings are present:
#   GLASSFAN_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD   (an app-specific password)
# Without them the app is signed ad hoc and not notarised.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: package-release.sh <version>}"
VERSION="${VERSION#v}"
DIST="$ROOT/dist"
NAME="GlassFan-$VERSION"

cd "$ROOT"
GLASSFAN_VERSION="$VERSION" ./Scripts/build-app.sh release

rm -rf "$DIST"
mkdir -p "$DIST"

notarise() {
    local file="$1"
    if [[ -n "${GLASSFAN_SIGN_IDENTITY:-}" && -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
        echo "==> Notarising $(basename "$file")"
        xcrun notarytool submit "$file" --wait \
            --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
        return 0
    fi
    return 1
}

echo "==> Disk image"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto GlassFan.app "$STAGE/GlassFan.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "GlassFan $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs APFS \
    "$DIST/$NAME.dmg" >/dev/null
if [[ -n "${GLASSFAN_SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$GLASSFAN_SIGN_IDENTITY" "$DIST/$NAME.dmg"
fi
if notarise "$DIST/$NAME.dmg"; then
    xcrun stapler staple "$DIST/$NAME.dmg"
    # The app inside the image is notarised with it; staple the loose app too so
    # the zip carries its ticket.
    xcrun stapler staple GlassFan.app || true
fi

echo "==> Zip"
ditto -c -k --sequesterRsrc --keepParent GlassFan.app "$DIST/$NAME.zip"

echo "==> Checksums"
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)

ls -lh "$DIST"
