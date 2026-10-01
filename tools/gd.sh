#!/usr/bin/env bash
# Wrapper for the pinned Godot editor binary (downloaded by tools/fetch_godot.sh).
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HERE/.cache/godot/Godot_v4.7.2-stable_linux.x86_64}"
[ -x "$GODOT_BIN" ] || GODOT_BIN=/home/user/tools/Godot_v4.7.2-stable_linux.x86_64
exec "$GODOT_BIN" "$@"
