#!/usr/bin/env bash
# Runs the automated rule/simulation/network tests headlessly.
# Usage: tools/run_tests.sh [filter]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
# Refresh the global class cache + imports (needed after adding class_name scripts).
"$HERE/gd.sh" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
"$HERE/gd.sh" --headless --fixed-fps 60 --path "$ROOT/game" -s res://tests/run_tests.gd -- "${1:-}"
