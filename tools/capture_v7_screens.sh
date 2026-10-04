#!/usr/bin/env bash
# V7 screens evidence: the real game rendered by the Mobile renderer on
# llvmpipe (software Vulkan) under Xvfb at device sizes, with the emulated
# point scale and safe area of each device (src/dev/capture_v7_screens.gd):
# Home, Play with Friends (resting, emulated keyboard, mistyped code),
# Settings (top and each section), the Delete Game Profile confirmation,
# results, final standings, a party room with 1 and 4 players (in-process
# loopback transport) and its leave confirmation.  Each PNG has a
# <shot>_layout.json of measured control rects.  Layout only: not frame
# rate, device input or the real iOS keyboard.  Game Center is simulated as
# signed in (--gc-sim=ready); nothing that needs it is invoked.
#
# Usage: tools/capture_v7_screens.sh OUT_DIR [devices...]
#   devices: se x14 p14 max ipad a2048 a1536 (default: all)
#   CAPTURE_TIMEOUT (seconds per device, default 900)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVS=${*:-se x14 p14 max ipad a2048 a1536}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# name: pixels, point scale, safe area (points L,T,R,B), label
spec() {
  case $1 in
    se)    echo "1334x750 2 0,0,0,0";;          # 667x375 pt @2x (iPhone SE)
    x14)   echo "2436x1125 3 44,0,44,21";;      # 812x375 pt @3x (iPhone X/11 Pro/12 mini class)
    p14)   echo "2532x1170 3 47,0,47,21";;      # 844x390 pt @3x (iPhone 12-14 class)
    max)   echo "2778x1284 3 47,0,47,21";;      # 926x428 pt @3x (Pro Max / Plus class)
    ipad)  echo "2048x1536 2 0,24,0,20";;       # 1024x768 pt @2x (4:3 iPad)
    a2048) echo "2048x946 2.4265 47,0,47,21";;  # owner screenshot aspect, as an 844x390 pt phone
    a1536) echo "1536x710 1.8916 44,0,44,21";;  # owner screenshot aspect, as an 812x375 pt phone
    *) echo ""; return 1;;
  esac
}

for d in $DEVS; do
  read -r res scale safe < <(spec "$d")
  w=${res%x*}; h=${res#*x}
  dir="$OUT/$d"
  mkdir -p "$dir"
  echo "== $d ($res, @${scale}, safe $safe)"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    nice -n 10 tools/gd.sh --path game --resolution "$res" -- \
    --emulate-phone="$scale" --emulate-safe="$safe" --capture=v7_screens --capture-dir="$dir" \
    --capture-label="desktop Linux llvmpipe, $d $res @$scale safe $safe, emulated" \
    --no-gamecenter --gc-sim=ready --skip-onboarding --name="Comfy Frog" ${CAPTURE_ARGS:-} > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |^LAYOUT |SCRIPT ERROR" "$dir/log.txt" | sed "s|$OUT/||" || true
done
