#!/usr/bin/env bash
# Downloads the pinned Godot editor (+ export templates with --templates).
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${GODOT_VERSION:-4.7.2}"
CACHE=tools/.cache/godot
mkdir -p "$CACHE"
BASE="https://github.com/godotengine/godot/releases/download/${VER}-stable"
case "$(uname -s)" in
  Darwin)
    if [ ! -d "$CACHE/Godot.app" ]; then
      curl -fsSL --retry 3 -o "$CACHE/godot_macos.zip" "$BASE/Godot_v${VER}-stable_macos.universal.zip"
      unzip -q -o "$CACHE/godot_macos.zip" -d "$CACHE"
    fi
    echo "$PWD/$CACHE/Godot.app/Contents/MacOS/Godot" > "$CACHE/BIN"
    TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/${VER}.stable"
    ;;
  *)
    if [ ! -x "$CACHE/Godot_v${VER}-stable_linux.x86_64" ]; then
      curl -fsSL --retry 3 -o "$CACHE/godot_linux.zip" "$BASE/Godot_v${VER}-stable_linux.x86_64.zip"
      unzip -q -o "$CACHE/godot_linux.zip" -d "$CACHE"
    fi
    echo "$PWD/$CACHE/Godot_v${VER}-stable_linux.x86_64" > "$CACHE/BIN"
    TPL_DIR="$HOME/.local/share/godot/export_templates/${VER}.stable"
    ;;
esac
if [ "${1:-}" = "--templates" ] && [ ! -f "$TPL_DIR/version.txt" ]; then
  curl -fsSL --retry 3 -o "$CACHE/templates.tpz" "$BASE/Godot_v${VER}-stable_export_templates.tpz"
  mkdir -p "$TPL_DIR"
  unzip -q -o "$CACHE/templates.tpz" -d "$CACHE/tpl"
  cp -R "$CACHE/tpl/templates/." "$TPL_DIR/"
  rm -rf "$CACHE/tpl" "$CACHE/templates.tpz"
fi
cat "$CACHE/BIN"
