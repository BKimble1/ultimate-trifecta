#!/usr/bin/env bash
# Final release sweep, Season Pass evidence (docs/final/season.md): the real
# Season Pass at landscape device sizes, with the selected skin's figure
# measured on screen (measure.json).  Service on = the TEST DOUBLE, labelled
# on every picture; svcoff = the shipped state.  Mobile renderer on llvmpipe
# under Xvfb: layout and look only, not frame rate, touch feel or a device.
#
# Usage: tools/capture_final_season.sh OUT_DIR before|after [devices...]
#   devices: se p14 pmax ipad (default: all)
#   ONLY=a03 re-takes the shots whose names start with it.
#   FAST=1 renders 844x390 / 926x428 / iPad at their canvas size with the
#   matching point scale (layout, touch size and safe area are the device's;
#   only the picture has fewer pixels), as tools/capture_pass9_season.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; SET=${2:?before or after}; shift 2
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
    tools/gd.sh --path game --resolution "$res" res://src/dev/season_final_capture.tscn -- \
    --capture-dir="$OUT/$d" --set="$SET" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter ${ONLY:+--only=$ONLY} > "$OUT/$d/log.txt" 2>&1 || true
  echo "== $d $res @${scale} safe $safe: $(grep -c '^CAPTURE ' "$OUT/$d/log.txt" || true) shots"
  grep -E "SCRIPT ERROR|CAPTURE" "$OUT/$d/log.txt" | head -40 | sed "s|$OUT/||" || true
done
