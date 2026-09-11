#!/bin/zsh
# Builds iFold and assembles build/iFold.app.
#
#   ./build.sh                 release build
#   ./build.sh --run           build, then launch the app
#   ./build.sh --install       build, then copy to /Applications and launch
#   ./build.sh --debug-tools   ALSO compile in the developer snapshot hook (see
#                              DebugSnapshot.swift). Never ship such a build.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP=build/iFold.app
EXTRA=()
ACTION=""
for arg in "$@"; do
  case "$arg" in
    --debug-tools) EXTRA=(-Xswiftc -DIFOLD_DEBUG); echo "!! developer build: snapshot hook enabled" ;;
    *) ACTION="$arg" ;;
  esac
done

swift build -c "$CONFIG" "${EXTRA[@]}" 2>&1 | grep -v "^\[" || true
BIN=".build/$CONFIG/iFold"
[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/iFold"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Prefer a real Apple Development identity so the Screen Recording grant
# survives rebuilds (ad-hoc signatures get a new cdhash every build, which
# makes TCC forget the permission).
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
if [[ -n "${IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
  echo "signed with: $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "signed ad-hoc (Screen Recording permission must be re-granted after each rebuild)"
fi

echo "built $APP"

case "$ACTION" in
  --run)
    pkill -x iFold 2>/dev/null || true
    open "$APP" ;;
  --install)
    pkill -x iFold 2>/dev/null || true
    rm -rf /Applications/iFold.app
    cp -R "$APP" /Applications/iFold.app
    open /Applications/iFold.app
    echo "installed to /Applications/iFold.app" ;;
esac
