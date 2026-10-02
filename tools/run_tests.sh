#!/usr/bin/env bash
# Runs the automated rule/simulation/network tests headlessly.
# Usage: tools/run_tests.sh [filter]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
# Native extension (UTShare) for this host, if a C compiler is available.
ls "$ROOT"/game/addons/ut_share/bin/libut_share.linux.*.so >/dev/null 2>&1 || \
  { command -v cc >/dev/null && "$HERE/build_native.sh" >/dev/null; } || echo "note: UTShare not built (no C compiler)"
# Refresh the global class cache + imports (needed after adding class_name scripts).
"$HERE/gd.sh" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
"$HERE/gd.sh" --headless --fixed-fps 60 --path "$ROOT/game" -s res://tests/run_tests.gd -- "${1:-}"
