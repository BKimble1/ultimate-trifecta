#!/usr/bin/env bash
# V7 stick-drift probe: scripted touches on a phone-shaped canvas through the
# real touch -> command -> sim -> camera path in a Practice round (see
# game/tests/test_stick_probe.gd for the cases and columns).  Emulated
# touches on desktop Linux, not device input.
# Usage: tools/stick_probe.sh [render_fps]   (physics stays at 60 Hz)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
"$HERE/gd.sh" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
STICK_PROBE=1 "$HERE/gd.sh" --headless --fixed-fps "${1:-60}" --path "$ROOT/game" -s res://tests/run_tests.gd -- test_stick_probe 2>&1 \
  | grep -E "^STICKPROBE|SCRIPT ERROR" | sed 's/^STICKPROBE //'
