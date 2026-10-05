#!/usr/bin/env bash
# Pass 8: a normal-speed action reel of one outfit through the gameplay
# motion scenarios (src/dev/motion_reel_v8.tscn --look=..., the motion
# tests' 60 Hz mini-motor -> CharacterView path on the game's night light),
# recorded with Movie Maker at a fixed 30 fps clock on the Mobile renderer
# over llvmpipe under Xvfb, 960x540, then encoded to H.264 with a label
# burned in.  Scripted input; not frame-rate, GPU or device evidence.
# Usage: tools/character/capture_skin_reel.sh OUT.mp4 OUTFIT_KEY [SCENARIOS] [VIEWS]
#   SCENARIOS default: start,sprint,jump_run,dive,respawn,splash
#   (respawn = tagged by the Night Watch and back; the tag lunge itself is the
#   Watch's clip, and runners never ride carts)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?out.mp4}; KEY=${2:?outfit key}
SC=${3:-start,sprint,jump_run,dive,respawn,splash}; VIEWS=${4:-game,side}
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp -d)
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, 960x540, fixed 30 fps Movie Maker clock, normal speed, scripted input, not device footage"
for i in $(seq 180); do [ -e game/override.cfg ] || break; sleep 20; done
[ -e game/override.cfg ] && { echo "game/override.cfg exists; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=960\nwindow/size/window_height_override=540\n' > game/override.cfg
trap 'rm -f game/override.cfg; rm -rf "$TMP"' EXIT
XDG_DATA_HOME="$TMP" timeout "${CAPTURE_TIMEOUT:-3600}" xvfb-run -a -s "-screen 0 1280x720x24" \
  tools/gd.sh --path game --write-movie "$TMP/reel.avi" --fixed-fps 30 \
  res://src/dev/motion_reel_v8.tscn -- --no-gamecenter --scenarios="$SC" --views="$VIEWS" \
  --look="{\"outfit\":\"$KEY\",\"hat\":\"none\",\"hair\":\"bob\",\"skin\":\"tone5\"}" > "$TMP/log.txt" 2>&1 || true
tools/label_movie.sh "$TMP/reel.avi" "$OUT" "Pass 8 skin reel: $KEY - $PLAT"
