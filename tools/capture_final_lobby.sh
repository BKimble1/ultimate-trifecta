#!/usr/bin/env bash
# Final lobby lighting pass evidence: src/dev/lobby_light_capture.tscn walks
# Home, Locker, Shop (as opened, and a charcoal outfit tried on), Season
# Pass and a party room with 1, 4 and 8 players (fixed looks, in-process
# loopback transport) at a phone shape, on a fixed 30 fps clock so the poses
# and cameras repeat exactly between runs.  Each shot: <shot>.png (what the
# player sees), <shot>_3d.png (UI hidden), <shot>_room.png (UI and characters
# hidden) and <shot>.json (projected face/torso/reference points and text
# rects) for tools/lobby_light_measure.py.  Mobile renderer on llvmpipe under
# Xvfb (Mesa limited to AVX, below): look and layout evidence only, never
# frame rate.
#
# Usage: tools/capture_final_lobby.sh OUT_DIR NAME [devices...]
#   devices: p14 (2532x1170 @3x shape rendered at its 1558x720 canvas, as
#            FAST=1 in tools/capture_pass9_season.sh), se (1334x750 @2x),
#            p14full (2532x1170 at full pixels).  Default: p14 se.
#   QUALITY=0 renders Battery Saver (default 1, Standard).
#   RENDERER=forward_plus renders with Forward+ instead of the shipped Mobile
#   renderer (a cross-check).
#   GALLIUM_OVERRIDE_CPU_CAPS (default avx): on a host CPU with AVX-512 FP16,
#   llvmpipe's JIT miscompiles some of the Mobile renderer's half-precision
#   shaders and the characters lose all directional light (docs/final/lobby.md,
#   L1).  Limiting Mesa to AVX gives the correct picture; =native keeps the
#   host's features (to show the fault).
#   ONLY=08 re-takes the shots whose names start with 08.
#   GAME_ROOT=/path/to/checkout records another checkout (the driver is
#   copied into it), e.g. the unchanged base for "before" frames.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; NAME=${2:?name}; shift 2
DEVICES=${*:-p14 se}
ROOT=${GAME_ROOT:-$PWD}
if [ "${GALLIUM_OVERRIDE_CPU_CAPS:-avx}" = native ]; then unset GALLIUM_OVERRIDE_CPU_CAPS; else export GALLIUM_OVERRIDE_CPU_CAPS=${GALLIUM_OVERRIDE_CPU_CAPS:-avx}; fi
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
if [ "$ROOT" != "$PWD" ]; then
  cp game/src/dev/lobby_light_capture.gd game/src/dev/lobby_light_capture.tscn "$ROOT/game/src/dev/"
fi
for d in $DEVICES; do
  case $d in
    p14) res=1558x720 scale=1.846 safe=47,0,47,21;;
    se) res=1334x750 scale=2 safe=0,0,0,0;;
    p14full) res=2532x1170 scale=3 safe=47,0,47,21;;
    *) echo "unknown device $d"; exit 2;;
  esac
  w=${res%x*}; h=${res#*x}
  dir="$OUT/${NAME}_${d}_q${QUALITY:-1}${RENDERER:+_$RENDERER}"
  mkdir -p "$dir"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-1800}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path "$ROOT/game" --resolution "$res" --fixed-fps 30 ${RENDERER:+--rendering-method $RENDERER} res://src/dev/lobby_light_capture.tscn -- \
    --capture-dir="$dir" --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter --quality="${QUALITY:-1}" \
    ${ONLY:+--only=$ONLY} > "$dir/log.txt" 2>&1 || true
  echo "== $NAME $d $res @${scale} q${QUALITY:-1} ${RENDERER:-mobile}: $(grep -c '^CAPTURE ' "$dir/log.txt" || true) shots"
  grep -E "SCRIPT ERROR|ERROR:|CAPTURE-DONE" "$dir/log.txt" | head -8 | sed "s|$OUT/||" || true
done
