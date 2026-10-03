#!/usr/bin/env bash
# V6 commerce evidence: Home with the navigation bar, Locker, Shop (sections,
# detail sheet, Coin confirmation), Season Pass and the service-off states,
# rendered by the Mobile renderer on llvmpipe under Xvfb at device sizes.
# TEST ADAPTERS: the test-double service and the simulated App Store (prices
# read "(test price)").  Layout and states only: not frame rate, not a real
# purchase.  Re-run after the art merge to show the new outfits.
#
# Usage: tools/capture_v6_commerce.sh OUT_DIR [phone se ipad]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVICES=${*:-phone se ipad}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
for d in $DEVICES; do
  case $d in
    phone) res=2532x1170 scale=3 safe=59,0,59,21;;
    se) res=1334x750 scale=2 safe=0,0,0,0;;
    ipad) res=2048x1536 scale=2 safe=0,24,0,20;;
    *) echo "unknown device $d"; exit 2;;
  esac
  w=${res%x*}; h=${res#*x}
  mkdir -p "$OUT/$d"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" res://src/dev/commerce_capture.tscn -- \
    --capture-dir="$OUT/$d" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter ${CAPTURE_ARGS:-} > "$OUT/$d/log.txt" 2>&1 || true
  grep -E "^CAPTURE|SCRIPT ERROR" "$OUT/$d/log.txt" | sed "s|$OUT/||" || true
done
