#!/usr/bin/env bash
# V8 gameplay bench: whole Practice rounds (8 slots, every slot bot-driven,
# real App flow with loading, results and the menu between rounds) on the
# real clock with a frame cap; per-frame engine-loop interval and CPU time
# per section (game/src/dev/match_bench.gd).  Headless by default (CPU side
# only, dummy renderer); RENDER=1 runs windowed on llvmpipe under Xvfb to
# read draw calls and primitives (software rendering: not timing evidence).
# This machine's numbers, never a phone's.
# Usage: tools/match_bench.sh OUT.json [--fps=60] [--rounds=3] [--round-secs=75] [--seed=7] [--quality=1] [--map=reference_campus|classic]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out.json}; shift
OUT=$(realpath -m "$OUT")
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
if [ "${RENDER:-0}" = 1 ]; then
  XDG_DATA_HOME=$(mktemp -d) timeout "${BENCH_TIMEOUT:-3600}" xvfb-run -a -s "-screen 0 1400x800x24" \
    tools/gd.sh --path game --resolution 1280x720 res://src/dev/match_bench.tscn -- --no-gamecenter --out="$OUT" "$@" 2>&1 | grep -E "^BENCH|SCRIPT ERROR"
else
  XDG_DATA_HOME=$(mktemp -d) timeout "${BENCH_TIMEOUT:-3600}" \
    tools/gd.sh --headless --path game res://src/dev/match_bench.tscn -- --no-gamecenter --out="$OUT" "$@" 2>&1 | grep -E "^BENCH|SCRIPT ERROR"
fi
