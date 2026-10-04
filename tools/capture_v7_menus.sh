#!/usr/bin/env bash
# V7 menus evidence: Locker (Outfit, Emotes, Hat, Shoes, Face, Profile), Season
# Pass (first / middle / last tier, Free and Premium selected; service on with
# the TEST ADAPTERS, and the shipped service-off state) and Shop, rendered by
# the Mobile renderer on llvmpipe under Xvfb at phone-shaped landscape sizes.
# Each device directory also gets measure.json: the final allocated rects
# (Pass rows, detail action, cards, art wells, cut-off controls).
# Layout and states only: not frame rate, not a device, not a purchase.
#
# Usage: tools/capture_v7_menus.sh OUT_DIR [devices...]
#   devices: se x p14 pmax ipad s2048 s1536 (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVICES=${*:-se x p14 pmax ipad s2048 s1536}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
for d in $DEVICES; do
  # pixels, point scale, safe area (points L,T,R,B)
  case $d in
    se) res=1334x750 scale=2 safe=0,0,0,0;;              # 667x375 pt, iPhone SE
    x) res=2436x1125 scale=3 safe=44,0,44,21;;           # 812x375 pt, notched
    p14) res=2532x1170 scale=3 safe=47,0,47,21;;         # 844x390 pt
    pmax) res=2778x1284 scale=3 safe=47,0,47,21;;        # 926x428 pt
    ipad) res=2048x1536 scale=2 safe=0,24,0,20;;         # 1024x768 pt
    s2048) res=2048x946 scale=2.426 safe=47,0,47,21;;    # owner screenshot aspect (as 844x390 pt)
    s1536) res=1536x710 scale=1.821 safe=47,0,47,21;;    # owner screenshot aspect (as 844x390 pt)
    *) echo "unknown device $d"; exit 2;;
  esac
  w=${res%x*}; h=${res#*x}
  mkdir -p "$OUT/$d"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-5400}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" res://src/dev/menus_capture.tscn -- \
    --capture-dir="$OUT/$d" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter ${CAPTURE_ARGS:-} > "$OUT/$d/log.txt" 2>&1 || true
  echo "== $d $res @${scale} safe $safe: $(grep -c '^CAPTURE ' "$OUT/$d/log.txt" || true) shots"
  grep -E "SCRIPT ERROR|CAPTURE-DONE" "$OUT/$d/log.txt" | head -5 | sed "s|$OUT/||" || true
done
