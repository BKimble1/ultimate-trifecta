#!/usr/bin/env bash
# Website footage: one real offline practice round, every seat played by the
# game's own bots (--autoplay=runner --local-bot), filmed by
# src/dev/film_director.gd (HUD and name tags hidden, a director's camera
# cutting between the round's moments).  Godot's Movie Maker at a fixed
# 30 fps clock, so playback is game time; Mobile renderer over llvmpipe
# (software Vulkan) under Xvfb: slow to record, not a performance
# measurement.  The cut list and game events are in OUT/film_SEED.log.
# Usage: tools/capture_film.sh OUT_DIR SEED [W] [H] [FILM_ARGS...]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; SEED=${2:?seed}; W=${3:-1920}; H=${4:-1080}
shift 4 2>/dev/null || shift $#
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
# Movie Maker records the window size: a temporary override.cfg (shared by
# parallel recordings of the same size; the last one out removes it)
CFG=game/override.cfg
if [ ! -e "$CFG" ]; then
  printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.92\n' "$W" "$H" > "$CFG"
fi
XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-14400}" xvfb-run -a -s "-screen 0 $((W + 64))x$((H + 64))x24" \
  tools/gd.sh --path game --write-movie "$OUT/film_$SEED.avi" --fixed-fps 30 -- \
  --autoplay=runner --local-bot --capture=film --capture-dir="$OUT/stills_$SEED" --seed="$SEED" \
  --no-gamecenter --skip-onboarding "$@" > "$OUT/film_$SEED.log" 2>&1 || true
pgrep -f "capture=film" >/dev/null || rm -f "$CFG"
grep -E "^FILM" "$OUT/film_$SEED.log" > "$OUT/film_$SEED.cuts" || true
ls -la "$OUT/film_$SEED.avi"
