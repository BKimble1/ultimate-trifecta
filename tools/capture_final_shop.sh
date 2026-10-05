#!/usr/bin/env bash
# FINAL_RELEASE_SWEEP Shop evidence (filters, App Store outfits, Coin packs
# with simulated and unavailable prices, owned states, the offer cycle) with the V7 screens
# approach: the real game rendered by the Mobile renderer on llvmpipe under
# Xvfb at device sizes, with each device's point scale and safe area
# (src/dev/capture_shop_final.gd).  Each PNG has a render report (.json) and a
# <shot>_layout.json of measured control rects.  DEV FIXTURE: the
# test-double service's clock, schedule and wallet and the simulated store
# ("(test price)"); every shot carries a visible label saying so.  Layout
# and states only: not frame rate, not a deployed service, not a real
# App Store price or purchase.
#
# Usage: tools/capture_final_shop.sh OUT_DIR [devices...]
#   devices: se p14 ipad (default) or any of capture_v7_screens.sh's
#   CAPTURE_TIMEOUT (seconds per device, default 600)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVS=${*:-se p14 ipad}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

spec() {
  case $1 in
    se)    echo "1334x750 2 0,0,0,0";;          # 667x375 pt @2x (iPhone SE)
    x14)   echo "2436x1125 3 44,0,44,21";;      # 812x375 pt @3x
    p14)   echo "2532x1170 3 47,0,47,21";;      # 844x390 pt @3x (iPhone 12-14 class)
    max)   echo "2778x1284 3 47,0,47,21";;      # 926x428 pt @3x
    ipad)  echo "2048x1536 2 0,24,0,20";;       # 1024x768 pt @2x (4:3 iPad)
    *) echo ""; return 1;;
  esac
}

for d in $DEVS; do
  read -r res scale safe < <(spec "$d")
  w=${res%x*}; h=${res#*x}
  dir="$OUT/$d"
  mkdir -p "$dir"
  echo "== $d ($res, @${scale}, safe $safe)"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-600}" xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    nice -n 10 tools/gd.sh --path game --resolution "$res" -- \
    --emulate-phone="$scale" --emulate-safe="$safe" --capture=shop_final --capture-dir="$dir" \
    --capture-label="desktop Linux llvmpipe, $d $res @$scale safe $safe, emulated" \
    --no-gamecenter --gc-sim=ready --skip-onboarding --name="Comfy Frog" ${CAPTURE_ARGS:-} > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |^LAYOUT |SCRIPT ERROR" "$dir/log.txt" | sed "s|$OUT/||" || true
done
