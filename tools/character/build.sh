#!/usr/bin/env bash
# Rebuild game/assets/characters/runner.glb from the Python sources in this folder.
# Needs Blender's bpy module (pip install bpy==4.5.4 in a Python 3.11 venv):
#   python3.11 -m venv tools/.cache/bpyenv && tools/.cache/bpyenv/bin/pip install bpy==4.5.4
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=${BPY_PYTHON:-tools/.cache/bpyenv/bin/python}
"$PY" tools/character/build_character.py "$@"
