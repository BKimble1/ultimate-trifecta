#!/usr/bin/env bash
# V7 screens layout checks at each device's real sizes: runs
# game/tests/test_v7_screens.gd once per device with the device's point
# scale (--emulate-phone: 44 pt touch targets in canvas units), its safe
# area (--emulate-safe, points L,T,R,B) and its pixel size (--v7-size).
# The normal test lane (tools/run_tests.sh) runs the same file on a plain
# headless desktop.  Usage: tools/check_v7_screens.sh [test-name-filter]
set -uo pipefail
cd "$(dirname "$0")/.."
FILTER=${1:-test_v7_screens}
fail=0
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
while read -r name res scale safe; do
  out=$(tools/gd.sh --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd -- "$FILTER" \
    --emulate-phone="$scale" --emulate-safe="$safe" --v7-size="$res" 2>&1)
  summary=$(echo "$out" | grep -E "^[0-9]+ tests," || echo "no summary")
  echo "$name ($res @$scale, safe $safe): $summary"
  echo "$out" | grep -E "^  FAIL" | head -20
  echo "$summary" | grep -q " 0 failures" || fail=1
done <<'EOF'
se 1334x750 2 0,0,0,0
x14 2436x1125 3 44,0,44,21
p14 2532x1170 3 47,0,47,21
max 2778x1284 3 47,0,47,21
ipad 2048x1536 2 0,24,0,20
a2048 2048x946 2.4265 47,0,47,21
a1536 1536x710 1.8916 44,0,44,21
EOF
exit $fail
