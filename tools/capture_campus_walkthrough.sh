#!/usr/bin/env bash
# Campus walkthrough: one real Practice round on the rebuilt campus, as a
# runner, the local runner driven by the same BotBrain as the bots
# (--local-bot): out of the home hall, to the round's three waters and back
# inside, seen through the game's own follow camera and HUD.  Recorded with
# Godot's Movie Maker at a fixed clock (normal speed) on the Mobile renderer
# over llvmpipe under Xvfb, then encoded to H.264 with a label burned in.
# Composition evidence: not frame-rate, GPU or device footage.  The capture
# scenario (src/dev/capture.gd, "dorm") also writes stills and ends the run
# after the results.
# Usage: tools/capture_campus_walkthrough.sh OUT_DIR [--seed=N] [--fps=15] [--size=960x540]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
SEED=3; FPS=15; SIZE=960x540
for a in "$@"; do
  case $a in
    --seed=*) SEED=${a#*=};;
    --fps=*) FPS=${a#*=};;
    --size=*) SIZE=${a#*=};;
  esac
done
W=${SIZE%x*}; H=${SIZE#*x}
mkdir -p "$OUT/stills"; OUT=$(cd "$OUT" && pwd)
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
[ -e game/override.cfg ] && { echo "game/override.cfg exists; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$W" "$H" > game/override.cfg
trap 'rm -f game/override.cfg' EXIT
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-10800}" xvfb-run -a -s "-screen 0 $((W + 64))x$((H + 64))x24" \
  tools/gd.sh --path game --write-movie "$OUT/walkthrough.avi" --fixed-fps "$FPS" -- \
  --no-gamecenter --skip-onboarding --capture=dorm --capture-dir="$OUT/stills" --capture-steps=20 \
  --autoplay=runner --local-bot --seed="$SEED" > "$OUT/walkthrough.log" 2>&1 || true
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, ${W}x${H}, fixed ${FPS} fps Movie Maker clock, bot-driven runner, not device footage"
tools/label_movie.sh "$OUT/walkthrough.avi" "$OUT/campus_walkthrough.mp4" "Campus walkthrough (practice round, seed $SEED) - $PLAT"
rm -f "$OUT/walkthrough.avi"
echo "wrote $OUT/campus_walkthrough.mp4"
