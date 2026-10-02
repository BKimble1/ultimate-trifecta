#!/usr/bin/env bash
# Development evidence: a normal-speed recording of the party lobby filling
# up.  The windowed host records with Godot's movie writer (fixed 30 fps game
# clock, so playback speed is game time; not a performance measurement);
# headless desktop clients join one by one and ready up a few seconds later.
# Usage: tools/record_lobby.sh OUT.avi [players=6] [WxH=1600x740] [seconds=30]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out.avi}; N=${2:-6}; RES=${3:-1600x740}; SECS=${4:-30}
PORT=$((7900 + RANDOM % 90))
W=${RES%x*}; H=${RES#*x}
XDG_DATA_HOME=$(mktemp -d) xvfb-run -a -s "-screen 0 $((W + 64))x$((H + 64))x24" timeout 5400 tools/gd.sh --path game --resolution "$RES" \
  --write-movie "$OUT" --fixed-fps 30 -- --net-host=$PORT --expect=99 --no-gamecenter --random-cosmetic --quit-after="$SECS" > "${OUT%.avi}_host.log" 2>&1 &
HOST=$!
sleep 25   # the recorded host boots slowly on a software renderer
for i in $(seq 2 "$N"); do
  XDG_DATA_HOME=$(mktemp -d) timeout 5400 tools/gd.sh --headless --path game -- --net-join=127.0.0.1:$PORT \
    --no-gamecenter --random-cosmetic --ready-after=$((3 + i % 3)) > "${OUT%.avi}_client$i.log" 2>&1 &
  sleep 20  # recorded time runs ~10x slower than wall time here
done
wait $HOST || true
pkill -P $$ 2>/dev/null || true
ls -la "$OUT"
