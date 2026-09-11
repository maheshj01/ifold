#!/bin/zsh
# Rasterises the brand SVGs into every icon the app and site need.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
sips -s format png -z 1024 1024 brand/ifold-mark-tile.svg --out "$T/tile.png" >/dev/null
cp "$T/tile.png" brand/ifold-avatar-1024.png
mkdir -p "$T/AppIcon.iconset"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  sips -z ${spec%%:*} ${spec%%:*} "$T/tile.png" --out "$T/AppIcon.iconset/icon_${spec#*:}.png" >/dev/null
done
iconutil -c icns "$T/AppIcon.iconset" -o Resources/AppIcon.icns
sips -z 180 180 "$T/tile.png" --out site/dist/assets/apple-touch-icon.png >/dev/null
sips -z 32 32 "$T/tile.png" --out site/dist/assets/favicon-32.png >/dev/null
cp brand/ifold-mark-tile.svg site/dist/assets/icon.svg
rm -rf "$T"
echo "icons regenerated"
