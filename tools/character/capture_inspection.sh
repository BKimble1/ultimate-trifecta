#!/usr/bin/env bash
# Final sweep (ARTFIX): render the outfit-catalogue inspection sheets
# (tools/character/inspect_shots.py) with the dorm room's own lights, through
# src/dev/character_lineup.tscn --lineup=custom.  Desktop render (Mobile
# renderer on llvmpipe under Xvfb): fit and look evidence only.
#
# Usage: tools/character/capture_inspection.sh OUT_DIR [sheet ...]
#   sheets: outfits_1 .. outfits_6, hats, zoom, bands (default: all)
# Writes OUT_DIR/lineup_<sheet>.png (+ .txt labels).
set -euo pipefail
cd "$(dirname "$0")/../.."
# llvmpipe on this machine's CPU miscompiles some of the Mobile renderer's
# half-precision shaders (characters lose their directional light) unless
# its CPU caps are limited to AVX
export GALLIUM_OVERRIDE_CPU_CAPS=${GALLIUM_OVERRIDE_CPU_CAPS:-avx}
OUT=${1:?out dir}; shift
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
SHOTS="$OUT/shots"
ALL=$(python3 tools/character/inspect_shots.py "$SHOTS")
SHEETS=${*:-$ALL}
for s in $SHEETS; do
  case $s in
    zoom|bands) res=900x900;;
    hats) res=600x600;;
    *) res=600x900;;
  esac
  w=${res%x*}; h=${res#*x}
  mkdir -p "$OUT/tmp_$s"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" nice -n 10 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" res://src/dev/character_lineup.tscn -- \
    --lineup=custom --light=dorm --shots-file="$SHOTS/$s.json" --capture-dir="$OUT/tmp_$s" > "$OUT/tmp_$s/log.txt" 2>&1 || true
  if [ -f "$OUT/tmp_$s/lineup_custom.png" ]; then
    mv "$OUT/tmp_$s/lineup_custom.png" "$OUT/lineup_$s.png"
    mv "$OUT/tmp_$s/lineup_custom.txt" "$OUT/lineup_$s.txt"
    rm -rf "$OUT/tmp_$s"
    echo "== $s: $OUT/lineup_$s.png"
  else
    echo "== $s: FAILED (see $OUT/tmp_$s/log.txt)"
    grep -E "SCRIPT ERROR|ERROR" "$OUT/tmp_$s/log.txt" | head -10 || true
  fi
done
