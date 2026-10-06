#!/usr/bin/env bash
# Rebuilds the V5 campus art kit: Blender (as a Python module) generates the
# vegetation/rock meshes, Godot converts them into game/assets/campus/
# campus_kit.res, and the detail textures are regenerated.
#   tools/campus/build.sh            # everything
#   tools/campus/build.sh tree_oak   # only meshes whose name starts with ...
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BPY="${BPY_PYTHON:-$ROOT/tools/.cache/bpyenv/bin/python}"
[ -x "$BPY" ] || BPY=/home/user/ultimate-trifecta/tools/.cache/bpyenv/bin/python
"$BPY" "$HERE/build_kit.py" "$@"
python3 "$HERE/make_textures.py"
"$ROOT/tools/gd.sh" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
"$ROOT/tools/gd.sh" --headless --path "$ROOT/game" -s "$HERE/import_kit.gd"
"$ROOT/tools/gd.sh" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
