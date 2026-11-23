#!/usr/bin/env bash
# (build 34) Series evidence: the between-rounds results with the countdown, the
# final standings and the clean lobby after a series
# (src/dev/series_flow_capture.tscn: a party of three on the in-process
# loopback transport).  Each shot as in tools/capture_final_lobby.sh:
# <shot>.png, <shot>_3d.png (UI hidden), <shot>_room.png, <shot>.json.
# Mobile renderer on llvmpipe under Xvfb: look and layout evidence only.
#
# Usage: tools/capture_party_holo.sh OUT_DIR [devices...]
#   devices: max (956x440 pt @2x, default), se (667x375 pt @2x),
#            ipad (1024x768 pt @2x)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVICES=${*:-max}
export GALLIUM_OVERRIDE_CPU_CAPS=${GALLIUM_OVERRIDE_CPU_CAPS:-avx}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
for d in $DEVICES; do
  case $d in
    max) res=1912x880 scale=2 safe=62,0,62,21;;
    se) res=1334x750 scale=2 safe=0,0,0,0;;
    ipad) res=2048x1536 scale=2 safe=0,0,0,20;;
    *) echo "unknown device $d"; exit 2;;
  esac
  w=${res%x*}; h=${res#*x}
  dir="$OUT/$d"
  mkdir -p "$dir"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" --fixed-fps 30 res://src/dev/series_flow_capture.tscn -- \
    --capture-dir="$dir" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter --quality="${QUALITY:-1}" > "$dir/log.txt" 2>&1 || true
  echo "== $d $res @${scale}: $(grep -c '^CAPTURE ' "$dir/log.txt" || true) shots"
  grep -E "SCRIPT ERROR|ERROR:|CAPTURE-DONE" "$dir/log.txt" | head -8 || true
done
