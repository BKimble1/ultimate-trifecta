#!/usr/bin/env bash
# The map chooser's previews, captured in-engine from the finished maps
# (src/dev/campus_views.tscn --preview: each map's own look, the night
# environment with a soft fill, an oblique aerial framed per map), rendered
# at 1600x900 and written as 960x540 PNGs to game/assets/maps/.  Run after
# any change a preview would show; test_maps checks both exist.
# Software rendering (llvmpipe under Xvfb): composition evidence only.
# On a virtual CPU that traps AVX-512, run with
# GALLIVM_PERF=nopt GALLIUM_OVERRIDE_CPU_CAPS=avx.
# Usage: tools/capture_map_previews.sh [map_id ...]   (default: every map)
set -euo pipefail
cd "$(dirname "$0")/.."
MAPS=("$@")
[ ${#MAPS[@]} -eq 0 ] && MAPS=(classic reference_campus)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
for m in "${MAPS[@]}"; do
  XDG_DATA_HOME="$TMP/xdg" timeout "${CAPTURE_TIMEOUT:-3600}" xvfb-run -a -s "-screen 0 1664x964x24" \
    tools/gd.sh --path game --resolution 1600x900 res://src/dev/campus_views.tscn -- \
    --out="$TMP" --quality=1 --map="$m" --preview > "$TMP/$m.log" 2>&1 || true
  if [ ! -s "$TMP/preview_$m.png" ]; then
    echo "no preview for $m"; tail -20 "$TMP/$m.log"; exit 1
  fi
  python3 -I - "$TMP/preview_$m.png" "game/assets/maps/preview_$m.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB').resize((960, 540), Image.LANCZOS)
im.save(sys.argv[2], optimize=True)
PY
  echo "wrote game/assets/maps/preview_$m.png"
done
