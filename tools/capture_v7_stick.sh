#!/usr/bin/env bash
# V7 forward-drift clips: game/src/dev/stick_reel.gd (scripted touches, same
# gestures and route) recorded with Godot's Movie Maker at a fixed 30 fps
# clock on the Mobile renderer over llvmpipe (software Vulkan) under Xvfb,
# then encoded to H.264 with a label burned in.  Normal speed; not
# frame-rate, GPU or device evidence.
# Usage: tools/capture_v7_stick.sh OUT_DIR NAME [GAME_ROOT]
#   GAME_ROOT: a checkout to record (default: this one), e.g. a worktree of
#   the build before the fix; the reel files are copied into it.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; NAME=${2:?name (before|after)}; ROOT=${3:-$PWD}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
if [ "$ROOT" != "$PWD" ]; then
  cp game/src/dev/stick_reel.gd game/src/dev/stick_reel.tscn "$ROOT/game/src/dev/"
  cp game/tests/test_stick_round.gd "$ROOT/game/tests/"
fi
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, 1560x720 (812x375 pt phone shape), fixed 30 fps Movie Maker clock, scripted emulated touches, not device footage"
tools/gd.sh --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-7200}" xvfb-run -a -s "-screen 0 1700x800x24" \
  tools/gd.sh --path "$ROOT/game" --resolution 1560x720 --write-movie "$OUT/stick_$NAME.avi" --fixed-fps 30 \
  res://src/dev/stick_reel.tscn -- --emulate-phone=1.92 --no-gamecenter > "$OUT/stick_$NAME.log" 2>&1 || true
grep -E "^REEL" "$OUT/stick_$NAME.log" > "$OUT/v7_stick_$NAME.txt" || true
tools/label_movie.sh "$OUT/stick_$NAME.avi" "$OUT/v7_stick_$NAME.mp4" "V7 forward drift, $NAME the fix - $PLAT"
rm -f "$OUT/stick_$NAME.avi"
