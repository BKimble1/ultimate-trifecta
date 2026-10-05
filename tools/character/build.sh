#!/usr/bin/env bash
# Rebuild game/assets/characters/runner.glb from the Python sources in this folder.
# Needs Blender's bpy module (pip install bpy==4.5.4 in a Python 3.11 venv):
#   python3.11 -m venv tools/.cache/bpyenv && tools/.cache/bpyenv/bin/pip install bpy==4.5.4
# Pass 9: a default build also re-measures garment fit on the new GLB
# (tools/character/fit_check.py, numpy) and rewrites the anchors fixture that
# tests/test_fit_p9.gd re-checks in the game; a fit failure is reported here
# but does not fail the build (the test does).
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=${BPY_PYTHON:-tools/.cache/bpyenv/bin/python}
"$PY" tools/character/build_character.py "$@"
if [ $# -eq 0 ]; then
  "$PY" tools/character/fit_check.py --quiet --anchors game/tests/data/fit_anchors.json || true
fi
