#!/bin/zsh
# Builds iFold Mac and assembles "build/iFold Mac.app".
#
#   ./build.sh                 release build
#   ./build.sh --run           build, then launch the app
#   ./build.sh --install       build, then copy to /Applications and launch
#   ./build.sh --debug-tools   ALSO compile in the developer snapshot hook (see
#                              DebugSnapshot.swift). Never ship such a build.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP="build/iFold Mac.app"
EXTRA=()
ACTION=""
DEBUG_TOOLS=0
# The developer variant builds in its own scratch directory: SwiftPM caches
# -Xswiftc flags in the build description and does not drop them when they
# disappear from the command line, so sharing .build would leak the hooks
# into every later "normal" build.
SCRATCH=.build
for arg in "$@"; do
  case "$arg" in
    --debug-tools) DEBUG_TOOLS=1; EXTRA=(-Xswiftc -DIFOLD_DEBUG); SCRATCH=.build-debug-tools
                   echo "!! developer build: snapshot + demo hooks enabled" ;;
    *) ACTION="$arg" ;;
  esac
done

swift build -c "$CONFIG" --scratch-path "$SCRATCH" "${EXTRA[@]}" 2>&1 | grep -v "^\[" || true
BIN="$SCRATCH/$CONFIG/ifold-mac"
[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }

# Belt and braces: a shipping binary must not contain the developer hooks.
if [[ $DEBUG_TOOLS -eq 0 ]] && strings "$BIN" | grep -q "ifold-mac\.snapshot\|ifold-mac\.demo\|DEBUG BUILD"; then
  echo "REFUSING: developer hooks found in a normal build (stale scratch dir? rm -rf .build)"; exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ifold-mac"
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
    pkill -x ifold-mac 2>/dev/null || true
    open "$APP" ;;
  --install)
    pkill -x ifold-mac 2>/dev/null || true
    rm -rf "/Applications/iFold Mac.app"
    cp -R "$APP" "/Applications/iFold Mac.app"
    open "/Applications/iFold Mac.app"
    echo "installed to /Applications/iFold Mac.app" ;;
esac
