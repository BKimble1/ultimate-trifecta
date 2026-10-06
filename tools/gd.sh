#!/usr/bin/env bash
# Wrapper for the pinned Godot editor binary (downloaded by tools/fetch_godot.sh).
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HERE/.cache/godot/Godot_v4.7.2-stable_linux.x86_64}"
[ -x "$GODOT_BIN" ] || GODOT_BIN=/home/user/tools/Godot_v4.7.2-stable_linux.x86_64
# Desktop renders use Mesa's llvmpipe.  On CPUs with AVX-512 FP16 it
# miscompiles some of the Mobile renderer's half-precision shaders and
# characters lose their directional light (dark faces, navy instead of sky
# blue; docs/final/lobby.md L1).  Limiting llvmpipe to AVX gives the correct
# picture (it matches Forward+).  Headless runs don't render and are
# unaffected.  Override by setting GALLIUM_OVERRIDE_CPU_CAPS yourself.
export GALLIUM_OVERRIDE_CPU_CAPS="${GALLIUM_OVERRIDE_CPU_CAPS:-avx}"
exec "$GODOT_BIN" "$@"
