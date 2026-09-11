#!/bin/zsh
# Builds a distributable DMG into dist/.
#
#   ./release.sh            → dist/iFold.dmg + dist/SHA256SUMS
#
# Signing tiers, picked automatically from what's in your keychain:
#   • "Developer ID Application" identity present   → signed for distribution
#   • ...and a notarytool profile named "ifold"      → also notarized + stapled
#     (create it once: xcrun notarytool store-credentials ifold --key AuthKey.p8 --key-id ID --issuer UUID)
#   • neither                                        → Apple Development / ad-hoc signed;
#     works, but Gatekeeper makes users click "Open Anyway" once (see README).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/iFold.app
DIST=dist
DMG="$DIST/iFold.dmg"

./build.sh
rm -rf "$DIST"; mkdir -p "$DIST"

DEVID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
NOTARIZE=0
if [[ -n "$DEVID" ]]; then
  echo "re-signing with: $DEVID"
  codesign --force --deep --options runtime --timestamp --sign "$DEVID" "$APP"
  xcrun notarytool history --keychain-profile ifold >/dev/null 2>&1 && NOTARIZE=1
fi

if (( NOTARIZE )); then
  echo "notarizing app…"
  ditto -c -k --keepParent "$APP" "$DIST/iFold.zip"
  xcrun notarytool submit "$DIST/iFold.zip" --keychain-profile ifold --wait
  xcrun stapler staple "$APP"
  rm "$DIST/iFold.zip"
fi

# Finder layout: app on the left, Applications shortcut on the right.
create-dmg \
  --volname "iFold $VERSION" \
  --volicon Resources/AppIcon.icns \
  --window-pos 200 160 --window-size 560 360 \
  --icon-size 128 --text-size 13 \
  --icon iFold.app 150 150 \
  --app-drop-link 410 150 \
  --hide-extension iFold.app \
  --no-internet-enable \
  "$DMG" "$APP"

if [[ -n "$DEVID" ]]; then
  codesign --sign "$DEVID" --timestamp "$DMG"
fi
if (( NOTARIZE )); then
  echo "notarizing dmg…"
  xcrun notarytool submit "$DMG" --keychain-profile ifold --wait
  xcrun stapler staple "$DMG"
fi

(cd "$DIST" && shasum -a 256 iFold.dmg | tee SHA256SUMS)
echo
echo "Gatekeeper assessment:"
if spctl -a -vv -t install "$DMG" 2>&1; then
  echo "→ accepted (notarized)"
else
  echo "→ not notarized: users must use System Settings → Privacy & Security → Open Anyway"
fi
echo
echo "built $DMG (v$VERSION, $(du -h "$DMG" | cut -f1))"
