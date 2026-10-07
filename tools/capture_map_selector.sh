#!/usr/bin/env bash
# The map chooser at device sizes (src/dev/capture_maps_ui.gd): Practice's
# Map row and sheet (each map selected), the controller path (D-pad to the
# other card, Accept picks, Cancel closes with focus back on the row), the
# party settings' Map row and sheet for the host, and the guest's read-only
# view of the host's choice.  The real game on the Mobile renderer over
# llvmpipe under Xvfb, with each device's emulated point scale and safe
# area (as tools/capture_v7_screens.sh).  Layout evidence, not device input.
# Usage: tools/capture_map_selector.sh OUT_DIR [devices...]
#   devices: se p14 ipad (default: all three)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVS=${*:-se p14 ipad}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
spec() {
  case $1 in
    se)   echo "1334x750 2 0,0,0,0";;       # 667x375 pt @2x: the smallest supported landscape phone
    p14)  echo "2532x1170 3 47,0,47,21";;   # 844x390 pt @3x: a modern phone
    ipad) echo "2048x1536 2 0,24,0,20";;    # 1024x768 pt @2x: iPad
    *) echo ""; return 1;;
  esac
}
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
for d in $DEVS; do
  read -r res scale safe < <(spec "$d")
  w=${res%x*}; h=${res#*x}
  dir="$OUT/$d"
  mkdir -p "$dir"
  echo "== $d ($res, @${scale}, safe $safe)"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    nice -n 10 tools/gd.sh --path game --resolution "$res" -- \
    --emulate-phone="$scale" --emulate-safe="$safe" --capture=maps_ui --capture-dir="$dir" \
    --capture-label="desktop Linux llvmpipe, $d $res @$scale safe $safe, emulated" \
    --no-gamecenter --gc-sim=ready --skip-onboarding --name="Comfy Frog" > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |FOCUS|GUEST|SCRIPT ERROR" "$dir/log.txt" | sed "s|$OUT/||" || true
done
