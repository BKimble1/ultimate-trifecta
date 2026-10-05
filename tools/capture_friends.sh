#!/usr/bin/env bash
# Friends (FINAL_RELEASE_SWEEP) evidence: the Friends entry points, the
# panel in each state, invites and the toast, rendered by the Mobile
# renderer on llvmpipe under Xvfb at landscape device shapes.  Every
# picture is stamped "desktop render · test-double service": Game Center and
# the game service are the test double in game/src/dev/fake_friends.gd
# (fictional players).  Layout and states only: not a device, not Game
# Center, not a live service, not frame rate.
#
# Usage: tools/capture_friends.sh OUT_DIR [devices...]
#   devices: se p14 pmax ipad (default: all)
#   MODE=before GAME=<checkout>/game renders the baseline's entry points
#   from a checkout of the earlier commit (copy friends_capture.gd/.tscn
#   into its src/dev first); MODE=after (default) this tree.
#   FAST=1 renders each shape at its canvas size with the device's point
#   scale (layout, touch targets and safe area are the device's; the picture
#   has fewer pixels), as tools/capture_pass9_season.sh does.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVICES=${*:-se p14 pmax ipad}
GAME=${GAME:-game}
MODE=${MODE:-after}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
for d in $DEVICES; do
  if [ "${FAST:-0}" != 1 ]; then
    case $d in
      se) res=1334x750 scale=2 safe=0,0,0,0;;              # 667x375 pt, iPhone SE
      p14) res=2532x1170 scale=3 safe=47,0,47,21;;         # 844x390 pt
      pmax) res=2778x1284 scale=3 safe=47,0,47,21;;        # 926x428 pt
      ipad) res=2048x1536 scale=2 safe=0,24,0,20;;         # 1024x768 pt
      *) echo "unknown device $d"; exit 2;;
    esac
  else
    case $d in
      se) res=1334x750 scale=2 safe=0,0,0,0;;
      p14) res=1558x720 scale=1.846 safe=47,0,47,21;;
      pmax) res=1558x720 scale=1.682 safe=47,0,47,21;;
      ipad) res=1280x960 scale=1.25 safe=0,24,0,20;;
      *) echo "unknown device $d"; exit 2;;
    esac
  fi
  w=${res%x*}; h=${res#*x}
  mkdir -p "$OUT/$d"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-1200}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path "$GAME" --resolution "$res" res://src/dev/friends_capture.tscn -- \
    --capture-dir="$OUT/$d" --mode="$MODE" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter ${ONLY:+--only=$ONLY} \
    > "$OUT/$d/log.txt" 2>&1 || true
  echo "== $d $res @${scale} safe $safe: $(grep -c '^CAPTURE ' "$OUT/$d/log.txt" || true) shots"
  grep -E "SCRIPT ERROR|CAPTURE-DONE" "$OUT/$d/log.txt" | head -5 | sed "s|$OUT/||" || true
done
