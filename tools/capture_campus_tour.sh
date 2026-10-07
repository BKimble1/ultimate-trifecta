#!/usr/bin/env bash
# A walker's-eye camera tour of a map (src/dev/campus_views.tscn --tour):
# out of the home hall through its door, the chapel's atrium, the bell
# tower's gap, North Hall's front stair up and down, a pond's shore exit,
# the footbridge, the lake shore, its dock and a shore exit, a path through
# the woods, and back home inside, along the bots' own foot
# paths (so only real doors, stairs and passages are used).  Movie Maker at
# a fixed clock on the Mobile renderer over llvmpipe under Xvfb, encoded to
# H.264 with a label.  Composition evidence: a camera, not a character,
# not device footage.  The night look with its distance fog.
# On a virtual CPU that traps AVX-512: GALLIVM_PERF=nopt GALLIUM_OVERRIDE_CPU_CAPS=avx.
# Usage: tools/capture_campus_tour.sh OUT_DIR [--map=reference_campus] [--fps=15] [--size=960x540] [--speed=7.5]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
MAP=reference_campus; FPS=15; SIZE=960x540; SPEED=7.5
for a in "$@"; do
  case $a in
    --map=*) MAP=${a#*=};;
    --fps=*) FPS=${a#*=};;
    --size=*) SIZE=${a#*=};;
    --speed=*) SPEED=${a#*=};;
  esac
done
W=${SIZE%x*}; H=${SIZE#*x}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-10800}" xvfb-run -a -s "-screen 0 $((W + 64))x$((H + 64))x24" \
  tools/gd.sh --path game --resolution "${W}x${H}" --write-movie "$OUT/tour_$MAP.avi" --fixed-fps "$FPS" res://src/dev/campus_views.tscn -- \
  --quality=1 --map="$MAP" --tour --tour-speed="$SPEED" > "$OUT/tour_$MAP.log" 2>&1 || true
grep -E "^TOUR" "$OUT/tour_$MAP.log" || true
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, ${W}x${H}, fixed ${FPS} fps, walker's-eye camera at ${SPEED} m/s along the bots' foot paths, not device footage"
tools/label_movie.sh "$OUT/tour_$MAP.avi" "$OUT/tour_$MAP.mp4" "Map tour ($MAP) - $PLAT"
rm -f "$OUT/tour_$MAP.avi"
echo "wrote $OUT/tour_$MAP.mp4"
