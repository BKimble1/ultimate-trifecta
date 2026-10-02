#!/usr/bin/env bash
# Renders the match loading loop from the game rig and packs it (V5).
# Needs a display (xvfb-run on Linux) and Vulkan (Mesa lavapipe works).
# Usage: tools/make_loading_loop_rig.sh [frames_dir]
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=${1:-$(mktemp -d)}
xvfb-run -a -s "-screen 0 1280x800x24" timeout 600 tools/gd.sh --path game --resolution 1100x640 --fixed-fps 60 \
  res://src/dev/loading_loop_render.tscn -- --out="$DIR" --fps=60 --frames=26 --size=1024x576
python3 tools/make_loading_loop_rig.py "$DIR"
