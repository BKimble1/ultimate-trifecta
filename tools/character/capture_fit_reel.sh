#!/usr/bin/env bash
# Pass 9 garment-fit reel: one look through gameplay motion scenarios in
# close-up (src/dev/motion_reel_v8.tscn --views=close,closeback: the motion
# tests' 60 Hz mini-motor -> CharacterView path, the game's night light),
# recorded with Movie Maker at a fixed 30 fps clock (normal speed) on the
# Mobile renderer over llvmpipe under Xvfb, 960x540, encoded to H.264 with a
# label burned in.  Scripted input; desktop rendering, not device footage.
# Usage: tools/character/capture_fit_reel.sh OUT.mp4 LOOK_JSON LABEL [GAME_ROOT] [SCENARIOS] [VIEWS]
#   LABEL: short, e.g. "BEFORE 2fff573: Arcade Sprinter" (the platform note is appended)
#   GAME_ROOT: a checkout to record (default: this one), e.g. the 2fff573
#   "before" tree; the reel scene is copied into it.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?out.mp4}; LOOK=${2:?look json}; LABEL=${3:?label}; ROOT=${4:-$PWD}
SC=${5:-start,reverse,stop,dive}; VIEWS=${6:-close}
mkdir -p "$(dirname "$OUT")"
if [ "$ROOT" != "$PWD" ]; then
  cp game/src/dev/motion_reel_v8.gd game/src/dev/motion_reel_v8.tscn "$ROOT/game/src/dev/"
fi
# (kept short: the burned-in line must fit 960 px with a label like
# "AFTER p9-fit: Arcade Sprinter")
PLAT="desktop render (Godot 4.7.2 Mobile, llvmpipe), 30 fps clock, scripted, not device footage"
TMP=$(mktemp -d)
for i in $(seq 180); do [ -e "$ROOT/game/override.cfg" ] || break; sleep 20; done
[ -e "$ROOT/game/override.cfg" ] && { echo "override.cfg exists in $ROOT/game; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=960\nwindow/size/window_height_override=540\n' > "$ROOT/game/override.cfg"
trap 'rm -f "$ROOT/game/override.cfg"; rm -rf "$TMP"' EXIT
XDG_DATA_HOME="$TMP" timeout "${CAPTURE_TIMEOUT:-3600}" xvfb-run -a -s "-screen 0 1280x720x24" \
  tools/gd.sh --path "$ROOT/game" --write-movie "$TMP/reel.avi" --fixed-fps 30 \
  res://src/dev/motion_reel_v8.tscn -- --no-gamecenter --scenarios="$SC" --views="$VIEWS" --look="$LOOK" > "$TMP/log.txt" 2>&1 || true
tools/label_movie.sh "$TMP/reel.avi" "$OUT" "$LABEL - $PLAT"
