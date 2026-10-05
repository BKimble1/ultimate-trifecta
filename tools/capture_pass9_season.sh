#!/usr/bin/env bash
# Pass 9 Season Pass evidence (100 tiers): the navigation row, the progress
# runs, the tier-50 and tier-100 rewards, lock and claim states (service on
# with the TEST DOUBLE, labelled on every picture; and the shipped
# service-off preview), rendered by the Mobile renderer on llvmpipe under
# Xvfb at landscape device sizes, with measure.json per device.  Layout and
# states only: not frame rate, not a device, not a live service.
#
# Usage: tools/capture_pass9_season.sh OUT_DIR [devices...]
#   devices: se p14 pmax ipad (default: all)
#   ONLY=12 re-takes one shot per device (the others' measurements stay).
#   FAST=1 renders each shape at its canvas size with the matching point
#   scale (layout, touch_min and the safe area are the device's; only the
#   picture has fewer pixels), as tools/capture_pass8_challenges.sh does.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVICES=${*:-se p14 pmax ipad}
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
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-2400}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" res://src/dev/season100_capture.tscn -- \
    --capture-dir="$OUT/$d" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter ${ONLY:+--only=$ONLY} > "$OUT/$d/log.txt" 2>&1 || true
  echo "== $d $res @${scale} safe $safe: $(grep -c '^CAPTURE ' "$OUT/$d/log.txt" || true) shots"
  grep -E "SCRIPT ERROR|CAPTURE-DONE" "$OUT/$d/log.txt" | head -5 | sed "s|$OUT/||" || true
done
