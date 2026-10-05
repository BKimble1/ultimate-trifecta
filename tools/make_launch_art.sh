#!/usr/bin/env bash
# The static launch image (iOS launch screen + Godot boot splash):
# game/assets/icon/launch.png.  V5 replaced the old loading-screen render
# (kept below, unreachable) with the Idlery Games lockup; Pass 8 rasterises it
# from the vector (art_src/branding/idlery-games.svg), 1656 x 1656, together
# with the runtime branding assets.  No display needed; needs pillow + numpy.
# Check the result with tools/launch_audit.py (edges and composition).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/branding/make_branding.py
OUT=${1:-res://assets/icon/launch.png}
xvfb-run -a -s "-screen 0 1600x1600x24" timeout 120 tools/gd.sh --path game --resolution 1440x1440 \
  res://src/dev/launch_art.tscn -- --out="$OUT"
