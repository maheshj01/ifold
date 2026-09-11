#!/bin/zsh
# Records the real app playing its scripted lid demo on the built-in display,
# and encodes it for the website.
#
#   site/record-demo.sh [style] [look] [name]
#     style: fold | curl | genie | notch | cube | scale | fade   (default fold)
#     look:  silk | shade | frost                                (default silk)
#     name:  output basename                                     (default <style>-demo)
#
# Writes build/demo/<name>.mp4, .webm and a poster .jpg (1512 px wide, ~9.8 s).
# Tidy the desktop first — whatever is on the built-in display is the footage.
# Uses the --debug-tools build's demo hook, which drives the lid path in
# Manual mode and makes the overlay visible to screen recorders for the take.
set -euo pipefail
cd "$(dirname "$0")/.."

STYLE=${1:-fold}; LOOK=${2:-silk}; NAME=${3:-$STYLE-demo}
B=com.wml.ifold-mac; APP="build/iFold Mac.app"; EXE=ifold-mac
OUT=build/demo; mkdir -p "$OUT"; RAW="$OUT/$NAME-raw.mov"

./build.sh --debug-tools >/dev/null
pkill -x $EXE 2>/dev/null || true; sleep 1

defaults write $B style "$STYLE"
case "$LOOK" in   # mirrors Settings.apply
  silk)  P=1.0; BEND=0.6; MO=1.0; FR=0;  SH=0.5 ;;
  shade) P=1.1; BEND=0.3; MO=0.8; FR=0;  SH=1.0 ;;
  frost) P=1.0; BEND=0.5; MO=1.2; FR=14; SH=0.5 ;;
  *) echo "unknown look: $LOOK"; exit 2 ;;
esac
defaults write $B perspective -float $P; defaults write $B bend -float $BEND
defaults write $B motion -float $MO;     defaults write $B frost -float $FR
defaults write $B shade -float $SH;      defaults write $B followLid -bool true

open "$APP"; sleep 3
echo "recording $STYLE / $LOOK …"
screencapture -V 11 -x -D 1 "$RAW" &
sleep 1.2; notifyutil -p $B.demo
wait

# Demo starts ~1.2 s in: keep a short lead-in, drop the tail.
ffmpeg -v error -y -ss 0.6 -t 9.8 -i "$RAW" -vf "scale=1512:-2" -an \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart "$OUT/$NAME.mp4"
ffmpeg -v error -y -ss 0.6 -t 9.8 -i "$RAW" -vf "scale=1512:-2" -an \
  -c:v libvpx-vp9 -crf 33 -b:v 0 -row-mt 1 "$OUT/$NAME.webm"
ffmpeg -v error -y -ss 3.6 -i "$OUT/$NAME.mp4" -frames:v 1 -q:v 3 "$OUT/$NAME.jpg"
rm -f "$RAW"

pkill -x $EXE 2>/dev/null || true; sleep 1
./build.sh >/dev/null; open "$APP"   # back to a normal build
ls -la "$OUT/$NAME".{mp4,webm,jpg} | awk '{printf "  %-40s %6.1f MB\n", $9, $5/1048576}'
