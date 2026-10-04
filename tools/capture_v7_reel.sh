#!/usr/bin/env bash
# V7 evidence clips: a src/dev reel (stick | pause) recorded with Godot's Movie
# Maker at a fixed 30 fps clock on the Mobile renderer over llvmpipe (software
# Vulkan) under Xvfb, in a 1040x480 window (the phone shape: the game's canvas
# is 1560x720 = 812x375 pt, drawn at 2/3 size to keep llvmpipe affordable),
# with the Low quality preset, then encoded
# to H.264 with a label burned in.  Normal speed (no speed-up, no frame
# interpolation); scripted emulated touches; not frame-rate, GPU or device
# evidence.
# Usage: tools/capture_v7_reel.sh OUT_DIR REEL NAME [GAME_ROOT]
#   REEL: stick | pause.   NAME: before | after (goes into the label).
#   GAME_ROOT: a checkout to record (default: this one), e.g. a worktree of
#   the build before the fix; the reel files are copied into it.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; REEL=${2:?reel}; NAME=${3:?name}; ROOT=${4:-$PWD}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
if [ "$ROOT" != "$PWD" ]; then
  cp game/src/dev/${REEL}_reel.gd game/src/dev/${REEL}_reel.tscn "$ROOT/game/src/dev/"
  [ "$REEL" = stick ] && cp game/tests/test_stick_round.gd "$ROOT/game/tests/"
fi
case $REEL in
  stick) WHAT="forward drift";;
  pause) WHAT="Pause, Resume and Leave";;
  *) echo "unknown reel $REEL"; exit 1;;
esac
PLAT="Godot 4.7.2 Mobile renderer (Low preset), desktop Linux llvmpipe, 1040x480 window (812x375 pt phone shape), fixed 30 fps Movie Maker clock, scripted emulated touches, not device footage"
tools/gd.sh --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
# Movie Maker records the window size and ignores --resolution: a temporary
# override.cfg makes the window the phone shape
# (another reel recording from the same checkout holds it: wait, up to an hour)
for i in $(seq 180); do [ -e "$ROOT/game/override.cfg" ] || break; sleep 20; done
[ -e "$ROOT/game/override.cfg" ] && { echo "override.cfg exists in $ROOT/game; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=1040\nwindow/size/window_height_override=480\n' > "$ROOT/game/override.cfg"
trap 'rm -f "$ROOT/game/override.cfg"' EXIT
mkdir -p "$OUT/${REEL}_${NAME}_stills"
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-7200}" xvfb-run -a -s "-screen 0 1700x800x24" \
  tools/gd.sh --path "$ROOT/game" --write-movie "$OUT/${REEL}_$NAME.avi" --fixed-fps 30 \
  res://src/dev/${REEL}_reel.tscn -- --emulate-phone=1.92 --no-gamecenter --reel-stills="$OUT/${REEL}_${NAME}_stills" \
  > "$OUT/${REEL}_$NAME.log" 2>&1 || true
grep -E "^REEL" "$OUT/${REEL}_$NAME.log" > "$OUT/v7_${REEL}_$NAME.txt" || true
tools/label_movie.sh "$OUT/${REEL}_$NAME.avi" "$OUT/v7_${REEL}_$NAME.mp4" "V7 $WHAT, $NAME - $PLAT"
rm -f "$OUT/${REEL}_$NAME.avi"
