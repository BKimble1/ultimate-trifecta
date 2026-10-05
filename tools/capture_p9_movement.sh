#!/usr/bin/env bash
# Pass 9 movement clips: src/dev/movement_reel_p9.tscn (a real offline
# Practice round as a runner: the real motor, CharacterView, follow camera and
# HUD; scripted full-input (old Sprint button held) and jump->dive-spam input on the campus's longest
# clear straight) recorded with Godot's Movie Maker at a fixed 30 fps clock on
# the Mobile renderer over llvmpipe (software Vulkan) under Xvfb, 960x540,
# trimmed to the scripted part and encoded to H.264 with a label burned in.
# Normal speed (no speed-up, no frame interpolation); not frame-rate, GPU or
# device evidence.
# Usage: tools/capture_p9_movement.sh OUT_DIR NAME [GAME_ROOT] [--scenarios=full,dive]
#   NAME: before | after (goes into the label and file names).
#   GAME_ROOT: a checkout to record (default: this one), e.g. a worktree of
#   build 8; the reel files are copied into it (it needs a
#   tests/test_p9_movement.gd with the input scripts: the 1.8 run used a
#   copy without the 1.9-only tests).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; NAME=${2:?name}; ROOT=${3:-$PWD}; shift 3 || shift $#
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
if [ "$ROOT" != "$PWD" ]; then
  cp game/src/dev/movement_reel_p9.gd game/src/dev/movement_reel_p9.tscn "$ROOT/game/src/dev/"
  [ -e "$ROOT/game/tests/test_p9_movement.gd" ] || { echo "$ROOT needs tests/test_p9_movement.gd"; exit 1; }
fi
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, 960x540, fixed 30 fps Movie Maker clock, scripted input, not device footage"
tools/gd.sh --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
for i in $(seq 180); do [ -e "$ROOT/game/override.cfg" ] || break; sleep 20; done
[ -e "$ROOT/game/override.cfg" ] && { echo "override.cfg exists in $ROOT/game; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=960\nwindow/size/window_height_override=540\n' > "$ROOT/game/override.cfg"
trap 'rm -f "$ROOT/game/override.cfg"' EXIT
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-7200}" xvfb-run -a -s "-screen 0 1280x720x24" \
  tools/gd.sh --path "$ROOT/game" --write-movie "$OUT/movement_$NAME.avi" --fixed-fps 30 \
  res://src/dev/movement_reel_p9.tscn -- --no-gamecenter "$@" > "$OUT/movement_$NAME.log" 2>&1 || true
# from just before the first scripted scenario (the round's load and reveal cut)
F=$(grep -m1 -o 'REEL_SCENARIO [a-z]* frame [0-9]*' "$OUT/movement_$NAME.log" | awk '{print $4}')
SS=$(python3 -c "print(max(0.0, ${F:-0}/30.0 - 0.5))")
ffmpeg -loglevel error -y -ss "$SS" -i "$OUT/movement_$NAME.avi" -c:v rawvideo -an "$OUT/movement_${NAME}_trim.avi"
tools/label_movie.sh "$OUT/movement_${NAME}_trim.avi" "$OUT/p9_movement_$NAME.mp4" "Pass 9 movement, $NAME - $PLAT"
rm -f "$OUT/movement_$NAME.avi" "$OUT/movement_${NAME}_trim.avi"
