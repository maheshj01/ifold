#!/bin/zsh
# Builds a distributable DMG into dist/ and, optionally, publishes it.
#
#   ./release.sh              → dist/ifold-mac.dmg + dist/SHA256SUMS
#   ./release.sh --publish    → also tag v<version>, push, create/update the GitHub
#                               release with the DMG, then download it back through
#                               the public link and verify the checksum
#   ./release.sh --check      → no build: verify what GitHub currently serves at
#                               releases/latest matches dist/SHA256SUMS
#   ./release.sh --bump 1.2.0 --publish
#                             → first set the version in Resources/Info.plist and the
#                               site's download dialog, commit and push that, then publish
#   add --dry-run to --publish to print the steps without tagging or uploading
#
# The version comes from CFBundleShortVersionString in Resources/Info.plist;
# bump it there (or with --bump) before publishing a new release (tags are immutable).
#
# Signing tiers, picked automatically from what's in your keychain:
#   • "Developer ID Application" identity present   → signed for distribution
#   • ...and a notarytool profile named "ifold-mac"  → also notarized + stapled
#     (create it once: xcrun notarytool store-credentials ifold-mac --key AuthKey.p8 --key-id ID --issuer UUID)
#   • neither                                        → Apple Development / ad-hoc signed;
#     works, but Gatekeeper makes users click "Open Anyway" once (see README).
set -euo pipefail
cd "$(dirname "$0")"

NAME="iFold Mac"          # human-facing name
SLUG="ifold-mac"          # identifiers: executable, DMG, notary profile
APP="build/$NAME.app"
DIST=dist
DMG="$DIST/$SLUG.dmg"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "maheshj01/$SLUG")
LATEST_URL="https://github.com/$REPO/releases/latest/download/$SLUG.dmg"

PUBLISH=0; CHECK=0; DRY=0; BUMP=""
while (( $# )); do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --check)   CHECK=1 ;;
    --dry-run) DRY=1 ;;
    --bump)    shift; BUMP="${1:-}"; [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "--bump needs a version like 1.2.0"; exit 2; } ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
  shift
done

# --- bump: set the version everywhere it is shown, commit, push ----------------
if [[ -n "$BUMP" ]]; then
  current=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
  echo "bumping $current → $BUMP"
  /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $BUMP" Resources/Info.plist
  /usr/libexec/PlistBuddy -c "Set CFBundleVersion $((build + 1))" Resources/Info.plist
  sed -i '' -E "s/Version [0-9]+\.[0-9]+\.[0-9]+ ·/Version $BUMP ·/" site/dist/index.html
  git add Resources/Info.plist site/dist/index.html
  if (( DRY )); then echo "  [dry-run] would commit and push 'Bump version to $BUMP'"; git reset -q; git checkout -- Resources/Info.plist site/dist/index.html
  else git commit -q -m "Bump version to $BUMP" && git push -q origin HEAD && echo "  committed and pushed"; fi
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"

# --- verify: what does the public "latest" link actually serve? -------------
verify_published() {
  local expected="${1:-}"
  echo "verifying $LATEST_URL"
  local latest_tag; latest_tag=$(gh api "repos/$REPO/releases/latest" -q .tag_name 2>/dev/null || echo "?")
  local assets; assets=$(gh api "repos/$REPO/releases/latest" -q '.assets[].name' 2>/dev/null | tr '\n' ' ')
  echo "  latest release: $latest_tag  assets: ${assets:-none}"
  [[ "$assets" == *"$SLUG.dmg"* ]] || { echo "  ✗ $SLUG.dmg is not attached to the latest release"; return 1; }
  local tmp; tmp=$(mktemp)
  curl -sfL --retry 3 --retry-delay 3 "$LATEST_URL" -o "$tmp" || { echo "  ✗ download failed"; rm -f "$tmp"; return 1; }
  local got; got=$(shasum -a 256 "$tmp" | cut -d' ' -f1); rm -f "$tmp"
  echo "  served sha256: $got"
  # The release's own SHA256SUMS must describe the DMG next to it.
  local published; published=$(curl -sfL "https://github.com/$REPO/releases/latest/download/SHA256SUMS" | cut -d' ' -f1)
  if [[ "$got" == "$published" ]]; then echo "  ✓ matches the release's SHA256SUMS"; else echo "  ✗ the DMG and SHA256SUMS on the release disagree"; return 1; fi
  if [[ -n "$expected" ]]; then
    if [[ "$got" == "$expected" ]]; then echo "  ✓ matches the build just published"; else echo "  ✗ MISMATCH — expected $expected"; return 1; fi
  fi
  if [[ -f "$DIST/SHA256SUMS" && "$(cut -d' ' -f1 "$DIST/SHA256SUMS")" != "$got" ]]; then
    echo "  note: local $DMG is a different build than what's published (run --publish to ship it)"
  fi
  if [[ "$latest_tag" != "$TAG" ]]; then
    echo "  note: latest release is $latest_tag, local version is $VERSION"
  fi
}

if (( CHECK )); then
  verify_published; exit $?
fi

# --- guards before we spend time building a release we can't publish --------
if (( PUBLISH )); then
  gh auth status >/dev/null 2>&1 || { echo "gh is not logged in (gh auth login)"; exit 1; }
  # Tracked changes anywhere, or untracked files among the build inputs, mean the
  # release wouldn't be reproducible from the tag.
  dirty=$(git status --porcelain --untracked-files=no; git status --porcelain --untracked-files=all -- Sources Resources Package.swift build.sh release.sh)
  [[ -z "$dirty" ]] || { echo "working tree is not clean — commit or stash first:"; echo "$dirty" | sed 's/^/  /'; exit 1; }
  git fetch -q origin
  git merge-base --is-ancestor HEAD origin/main || { echo "HEAD is not pushed to origin/main — git push first"; exit 1; }
  if existing=$(git ls-remote --tags origin "refs/tags/$TAG" | cut -f1) && [[ -n "$existing" ]]; then
    if [[ "$existing" != "$(git rev-parse HEAD)" && "$existing" != "$(git rev-parse "$TAG^{commit}" 2>/dev/null)" ]]; then
      echo "tag $TAG already exists on GitHub and points at another commit."
      echo "bump CFBundleShortVersionString in Resources/Info.plist for a new release."
      (( DRY )) && echo "  [dry-run] continuing anyway to show the steps" || exit 1
    else
      echo "tag $TAG already exists at this commit — release assets will be replaced"
    fi
  fi
fi

./build.sh
rm -rf "$DIST"; mkdir -p "$DIST"

DEVID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
NOTARIZE=0
if [[ -n "$DEVID" ]]; then
  echo "re-signing with: $DEVID"
  codesign --force --deep --options runtime --timestamp --sign "$DEVID" "$APP"
  xcrun notarytool history --keychain-profile "$SLUG" >/dev/null 2>&1 && NOTARIZE=1
fi

if (( NOTARIZE )); then
  echo "notarizing app…"
  ditto -c -k --keepParent "$APP" "$DIST/$SLUG.zip"
  xcrun notarytool submit "$DIST/$SLUG.zip" --keychain-profile "$SLUG" --wait
  xcrun stapler staple "$APP"
  rm "$DIST/$SLUG.zip"
fi

# Finder layout: app on the left, Applications shortcut on the right.
create-dmg \
  --volname "$NAME $VERSION" \
  --volicon Resources/AppIcon.icns \
  --window-pos 200 160 --window-size 560 360 \
  --icon-size 128 --text-size 13 \
  --icon "$NAME.app" 150 150 \
  --app-drop-link 410 150 \
  --hide-extension "$NAME.app" \
  --no-internet-enable \
  "$DMG" "$APP"

if [[ -n "$DEVID" ]]; then
  codesign --sign "$DEVID" --timestamp "$DMG"
fi
if (( NOTARIZE )); then
  echo "notarizing dmg…"
  xcrun notarytool submit "$DMG" --keychain-profile "$SLUG" --wait
  xcrun stapler staple "$DMG"
fi

(cd "$DIST" && shasum -a 256 "$SLUG.dmg" | tee SHA256SUMS)
echo
echo "Gatekeeper assessment:"
if spctl -a -vv -t install "$DMG" 2>&1; then
  echo "→ accepted (notarized)"
else
  echo "→ not notarized: users must use System Settings → Privacy & Security → Open Anyway"
fi
echo
echo "built $DMG (v$VERSION, $(du -h "$DMG" | cut -f1))"

(( PUBLISH )) || exit 0

# --- publish -----------------------------------------------------------------
SHA=$(cut -d' ' -f1 "$DIST/SHA256SUMS")
NOTES=$(mktemp)
cat > "$NOTES" <<'EON'
iPhone Duo's fold, for the MacBook lid you already have. iFold Mac reads the hinge angle from the built-in lid sensor and bends your live desktop as the lid comes down.

## Install

1. Download **ifold-mac.dmg** below, open it, drag iFold Mac to Applications.
2. First launch: macOS says it can't verify the app (signed, not yet notarized). Click **Done**, then **System Settings → Privacy & Security → Open Anyway**. Or: `xattr -d com.apple.quarantine "/Applications/iFold Mac.app"`
3. Grant **Screen Recording** when asked, then click **Relaunch** in the iFold Mac window.

Requires an Apple silicon MacBook with a lid-angle sensor (M2 Air and later, 14"/16" Pro) on macOS 14+. Illustrated steps: https://ifold-mac.vercel.app

iFold Mac is free and open source. If you enjoy it, [sponsoring](https://github.com/sponsors/maheshj01) funds the Apple Developer membership that will make the Gatekeeper step go away.

`SHA-256 ifold-mac.dmg`: `@SHA@`
EON
sed -i '' "s/@SHA@/$SHA/" "$NOTES"

run() { if (( DRY )); then echo "  [dry-run] $*"; else "$@"; fi; }
echo
echo "publishing $TAG to $REPO"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  run git tag -a "$TAG" -m "$NAME $VERSION"
fi
run git push -q origin "$TAG"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "  release $TAG exists — replacing assets"
  run gh release upload "$TAG" "$DMG" "$DIST/SHA256SUMS" --repo "$REPO" --clobber
else
  run gh release create "$TAG" "$DMG" "$DIST/SHA256SUMS" --repo "$REPO" --title "$NAME $VERSION" --notes-file "$NOTES"
fi
rm -f "$NOTES"
(( DRY )) && { echo "  [dry-run] would then verify $LATEST_URL against $SHA"; exit 0; }
sleep 5
verify_published "$SHA"
