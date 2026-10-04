#!/usr/bin/env bash
# V8 motion clips: src/dev/motion_reel_v8.tscn (motion-test scenarios on the
# game's night lighting, from behind and from the side) recorded with Godot's
# Movie Maker at a fixed 30 fps clock on the Mobile renderer over llvmpipe
# (software Vulkan) under Xvfb, 960x540, then encoded to H.264 with a label
# burned in.  Normal speed (no speed-up, no frame interpolation); scripted
# input; not frame-rate, GPU or device evidence.
# Usage: tools/capture_v8_motion.sh OUT_DIR NAME [GAME_ROOT] [--scenarios=a,b] [--views=game,side]
#   NAME: before | after (goes into the label and file names).
#   GAME_ROOT: a checkout to record (default: this one), e.g. a worktree of
#   build 6; the reel files are copied into it.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; NAME=${2:?name}; ROOT=${3:-$PWD}; shift 3 || shift $#
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
if [ "$ROOT" != "$PWD" ]; then
  cp game/src/dev/motion_reel_v8.gd game/src/dev/motion_reel_v8.tscn "$ROOT/game/src/dev/"
fi
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, 960x540, fixed 30 fps Movie Maker clock, scripted input, not device footage"
tools/gd.sh --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
for i in $(seq 180); do [ -e "$ROOT/game/override.cfg" ] || break; sleep 20; done
[ -e "$ROOT/game/override.cfg" ] && { echo "override.cfg exists in $ROOT/game; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=960\nwindow/size/window_height_override=540\n' > "$ROOT/game/override.cfg"
trap 'rm -f "$ROOT/game/override.cfg"' EXIT
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-7200}" xvfb-run -a -s "-screen 0 1280x720x24" \
  tools/gd.sh --path "$ROOT/game" --write-movie "$OUT/motion_$NAME.avi" --fixed-fps 30 \
  res://src/dev/motion_reel_v8.tscn -- --no-gamecenter "$@" > "$OUT/motion_$NAME.log" 2>&1 || true
tools/label_movie.sh "$OUT/motion_$NAME.avi" "$OUT/v8_motion_$NAME.mp4" "V8 motion, $NAME - $PLAT"
rm -f "$OUT/motion_$NAME.avi"
