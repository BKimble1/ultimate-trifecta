#!/usr/bin/env bash
# Renders the static launch image (iOS launch screen + boot splash) from the
# loading screen's drawing code: game/assets/icon/launch.png, 1440x1440.
# Needs a display (xvfb-run on Linux).  Usage: tools/make_launch_art.sh [out.png]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-res://assets/icon/launch.png}
xvfb-run -a -s "-screen 0 1600x1600x24" timeout 120 tools/gd.sh --path game --resolution 1440x1440 \
  res://src/dev/launch_art.tscn -- --out="$OUT"
