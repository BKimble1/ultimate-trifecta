#!/usr/bin/env bash
# Final lobby pass: a normal-speed clip of the app opening into the dorm
# (Home): the real main scene and boot (the Idlery Games curtain dissolving
# into the room, the hello wave, a new player's tutorial hint), recorded by
# Godot's Movie Maker on a fixed 30 fps clock and encoded at 30 fps, so it
# plays at real-time speed.  The iPhone 14 shape as its 1558x720 canvas with
# its point scale and safe area (as tools/capture_final_lobby.sh p14).  Mobile
# renderer on llvmpipe under Xvfb with Mesa limited to AVX (see
# capture_final_lobby.sh): look evidence only, not device footage or timing.
# Usage: tools/capture_lobby_loadin.sh OUT_DIR NAME [SECONDS]
#   GAME_ROOT=/path/to/checkout records another checkout (e.g. the base).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; NAME=${2:?name}; SECS=${3:-8}
ROOT=${GAME_ROOT:-$PWD}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
if [ "${GALLIUM_OVERRIDE_CPU_CAPS:-avx}" = native ]; then unset GALLIUM_OVERRIDE_CPU_CAPS; else export GALLIUM_OVERRIDE_CPU_CAPS=${GALLIUM_OVERRIDE_CPU_CAPS:-avx}; fi
# Movie Maker records the project's window size (it ignores --resolution):
# a temporary override.cfg sets the phone canvas, as capture_p9_movement.sh
for i in $(seq 180); do [ -e "$ROOT/game/override.cfg" ] || break; sleep 20; done
[ -e "$ROOT/game/override.cfg" ] && { echo "override.cfg exists in $ROOT/game; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=1558\nwindow/size/window_height_override=720\n' > "$ROOT/game/override.cfg"
trap 'rm -f "$ROOT/game/override.cfg"' EXIT
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-1800}" nice -n 10 xvfb-run -a -s "-screen 0 1640x800x24" \
  tools/gd.sh --path "$ROOT/game" --resolution 1558x720 --write-movie "$OUT/loadin_$NAME.avi" --fixed-fps 30 -- \
  --no-gamecenter --skip-onboarding --name="Comfy Frog" --emulate-phone=1.846 --emulate-safe=47,0,47,21 \
  --quit-after="$SECS" > "$OUT/loadin_$NAME.log" 2>&1 || true
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
LABEL="App opening into the dorm, $NAME - desktop render, llvmpipe (Godot 4.7.2 Mobile renderer, Xvfb), fixed 30 fps Movie Maker clock, real-time speed, not device footage"
ESC=$(printf '%s' "$LABEL" | sed -e "s/:/\\\\:/g" -e "s/'/\\\\'/g" -e "s/,/\\\\,/g")
ffmpeg -loglevel error -y -i "$OUT/loadin_$NAME.avi" -vf "scale=1280:-2,drawbox=y=ih-26:w=iw:h=26:color=black@0.55:t=fill,drawtext=fontfile=$FONT:text='$ESC':fontcolor=white:fontsize=13:x=8:y=h-19" \
  -r 30 -c:v libx264 -preset slow -crf 25 -pix_fmt yuv420p -movflags +faststart -an "$OUT/loadin_$NAME.mp4"
rm -f "$OUT/loadin_$NAME.avi"
ls -la "$OUT/loadin_$NAME.mp4"
