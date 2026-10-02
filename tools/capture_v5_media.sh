#!/usr/bin/env bash
# V5 evidence: the real game rendered by the Mobile renderer on llvmpipe
# (software Vulkan) under Xvfb at device sizes.  Layout, art and framing
# only: not frame rate, pacing, GPU cost or heat.
#
# Usage: tools/capture_v5_media.sh OUT_DIR [sets...]
#   sets: home screens creator lobby loading runner results startup (default: all)
# Each set writes PNGs plus a .json render report per shot into OUT_DIR/<set>/.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
SETS=${*:-home screens creator lobby loading runner results startup}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# device presets: resolution, point scale, safe area (points L,T,R,B)
PHONE="2532x1170 3 59,0,59,21"     # iPhone 14 Pro class, landscape
SE="1334x750 2 0,0,0,0"            # iPhone SE (2nd/3rd gen), landscape
IPAD="2048x1536 2 0,24,0,20"       # 4:3 iPad, landscape

game() { # dir res scale safe args...
  local dir=$1 res=$2 scale=$3 safe=$4; shift 4
  local w=${res%x*} h=${res#*x}
  mkdir -p "$dir"
  XDG_DATA_HOME=$(mktemp -d) timeout 900 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" "$@" -- \
    --emulate-phone="$scale" --emulate-safe="$safe" --capture-dir="$dir" --no-gamecenter \
    ${CAPTURE_ARGS:-} > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |SCRIPT ERROR" "$dir/log.txt" | sed "s|$OUT/||" || true
}

for s in $SETS; do
  echo "== $s"
  case $s in
    home)
      for d in phone se ipad; do
        case $d in phone) p=$PHONE;; se) p=$SE;; ipad) p=$IPAD;; esac
        # shellcheck disable=SC2086
        CAPTURE_ARGS="--capture=home --skip-onboarding" game "$OUT/home/$d" $p
      done;;
    screens)
      # shellcheck disable=SC2086
      CAPTURE_ARGS="--capture=screens --skip-onboarding" game "$OUT/screens" $PHONE;;
    creator)
      # shellcheck disable=SC2086
      CAPTURE_ARGS="--capture=creator --skip-onboarding" game "$OUT/wardrobe" $PHONE;;
    lobby)
      for n in 1 2 4 8; do
        tools/capture_lobby.sh "$n" "$OUT/lobby" 2532x1170 "desktop Linux llvmpipe, LAN dev room, $n players" | tail -1
      done;;
    loading)
      for d in phone se ipad; do
        case $d in phone) res=2532x1170;; se) res=1334x750;; ipad) res=2048x1536;; esac
        mkdir -p "$OUT/loading"
        timeout 600 xvfb-run -a -s "-screen 0 3000x2000x24" tools/gd.sh --path game --resolution "$res" \
          res://src/dev/launch_art.tscn -- --out="$OUT/loading/$d.png" --loading=0.0,0.2 > "$OUT/loading/$d.log" 2>&1 || true
        ls "$OUT/loading" | grep "^$d" | grep png || echo "no loading capture for $d"
      done;;
    runner)
      # bot-driven Practice as a runner: reveal, play, waters, map, results
      CAPTURE_ARGS="--capture=runner --autoplay=runner --local-bot --skip-onboarding" \
        game "$OUT/runner" 1600x740 1.896 59,0,59,21;;
    results)
      rec="$OUT/runner/runner_results.var"
      [ -f "$rec" ] || { echo "run the runner set first"; continue; }
      for d in se ipad; do
        case $d in se) p=$SE;; ipad) p=$IPAD;; esac
        # shellcheck disable=SC2086
        CAPTURE_ARGS="--capture=results --capture-results=$rec --skip-onboarding" game "$OUT/results/$d" $p
      done;;
    startup)
      # Movie Maker frames of a normal boot: the Idlery Games curtain over the
      # first frames, then home (fixed 30 fps game clock; not real time)
      mkdir -p "$OUT/startup"
      XDG_DATA_HOME=$(mktemp -d) timeout 900 xvfb-run -a -s "-screen 0 1400x700x24" tools/gd.sh --path game \
        --resolution 1280x592 --write-movie "$OUT/startup/f.png" --fixed-fps 30 -- \
        --skip-onboarding --no-gamecenter --quit-after=4 > "$OUT/startup/log.txt" 2>&1 || true
      ls "$OUT/startup" | grep -c png | sed 's/^/frames: /';;
    *) echo "unknown set $s";;
  esac
done
