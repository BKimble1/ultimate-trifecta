#!/usr/bin/env bash
# Pass 8 match clarity evidence: the real game (Mobile renderer, llvmpipe
# under Xvfb) at device sizes with each device's point scale and safe area
# (V7's point conversion: --emulate-phone / --emulate-safe), driven by
# src/dev/capture_pass8_match.gd into the HUD, map and results states the
# brief lists.  The states are deterministic dev states (labelled in each
# shot's JSON); the HUD, pace, map and results are the game's own output.
# Each PNG has <shot>.json (render report) and <shot>_hud.json (measured
# rects in canvas units and points, overlaps).  Layout/look only: not frame
# rate, device input or a comprehension test.
#
# Usage: tools/capture_pass8_match.sh OUT_DIR part [devices...]
#   part: runner | patrol | results
#   devices: se p14 max ipad (default: all four)
#   CAPTURE_TIMEOUT (seconds per device, default 1500)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; PART=${2:?part}; shift 2
DEVS=${*:-se p14 max ipad}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

spec() {
  case $1 in
    se)    echo "1334x750 2 0,0,0,0";;          # 667x375 pt @2x (iPhone SE)
    p14)   echo "2532x1170 3 47,0,47,21";;      # 844x390 pt @3x
    max)   echo "2778x1284 3 47,0,47,21";;      # 926x428 pt @3x
    ipad)  echo "2048x1536 2 0,24,0,20";;       # 1024x768 pt @2x
    *) echo ""; return 1;;
  esac
}

for d in $DEVS; do
  read -r res scale safe < <(spec "$d")
  w=${res%x*}; h=${res#*x}
  dir="$OUT/$d"
  mkdir -p "$dir"
  auto=""
  [ "$PART" = "runner" ] && auto="--autoplay=runner"
  [ "$PART" = "patrol" ] && auto="--autoplay=patrol"
  echo "== $PART $d ($res, @${scale}, safe $safe)"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-1500}" xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    nice -n 10 tools/gd.sh --path game --resolution "$res" -- \
    --emulate-phone="$scale" --emulate-safe="$safe" --capture=pass8_match --p8-part="$PART" $auto --capture-dir="$dir" \
    --capture-label="desktop Linux llvmpipe, $d $res @$scale safe $safe, emulated; deterministic dev states" \
    --no-gamecenter --skip-onboarding --name="Comfy Frog" ${CAPTURE_ARGS:-} > "$dir/log_$PART.txt" 2>&1 || true
  grep -E "^CAPTURE |^HUDJSON |SCRIPT ERROR" "$dir/log_$PART.txt" | sed "s|$OUT/||" || true
done
