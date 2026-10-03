#!/usr/bin/env bash
# V6 clips: the real game, rendered by the Mobile renderer on llvmpipe
# (software Vulkan) under Xvfb, recorded with Godot's Movie Maker at a FIXED
# 30 fps game clock (each frame is rendered and written one by one, however
# long it takes), then encoded to H.264 with a label burned in.  They show
# what happens on screen and in what order at normal speed; they are not
# frame-rate, pacing, GPU-cost or heat evidence.
#
# Usage: tools/capture_v6_media.sh OUT_DIR [sets...]
#   sets: startup loading swipes (default: all)
#   RESULTS_VAR=path adds the Results screen to the swipe reel.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
SETS=${*:-startup loading swipes}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
PLAT="Godot 4.7.2 Mobile renderer, desktop Linux llvmpipe, 1280x720 (16:9 as iPhone SE), fixed 30 fps Movie Maker clock, not device footage"

movie() { # name quit_after extra_args...
  local name=$1; shift
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-5400}" xvfb-run -a -s "-screen 0 1400x800x24" \
    tools/gd.sh --path game --resolution 1280x720 --write-movie "$OUT/$name.avi" --fixed-fps 30 "$@" \
    > "$OUT/$name.log" 2>&1 || true
}

for s in $SETS; do
  echo "== $s"
  case $s in
    startup)
      # cold launch: the black Idlery Games curtain over the first frames, then home
      movie startup -- --emulate-phone=1.92 --skip-onboarding --no-gamecenter --quit-after=5
      tools/label_movie.sh "$OUT/startup.avi" "$OUT/v6_startup_black.mp4" "V6 cold launch (black startup) - $PLAT";;
    loading)
      # bot-driven Practice from home: loading screen (loop, stages, Cancel)
      # all the way into the round inside tonight's home dorm
      CAPTURE_TIMEOUT=7200 movie loading -- --emulate-phone=1.92 --skip-onboarding --no-gamecenter \
        --autoplay=runner --local-bot --quit-after=30
      tools/label_movie.sh "$OUT/loading.avi" "$OUT/v6_loading_into_dorm.mp4" "V6 Practice: loading into the home dorm, bot-driven - $PLAT";;
    swipes)
      movie swipes res://src/dev/swipe_reel.tscn -- --emulate-phone=1.92 --no-gamecenter ${RESULTS_VAR:+--results=$RESULTS_VAR}
      grep -E "^REEL" "$OUT/swipes.log" > "$OUT/v6_finger_swipes.txt" || true
      tools/label_movie.sh "$OUT/swipes.avi" "$OUT/v6_finger_swipes.mp4" "V6 finger swipes (touch events as iOS sends them; test adapters, test prices) - $PLAT";;
    *) echo "unknown set $s";;
  esac
  rm -f "$OUT"/*.avi
done
ls -la "$OUT"
