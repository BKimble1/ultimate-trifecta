#!/usr/bin/env bash
# Development evidence: renders the party lobby with N players.  The capture
# host is a windowed desktop LAN room (a development path; iOS uses Game
# Center); the other N-1 players are headless desktop clients that join and
# ready up.  Every process gets its own profile and a random look.
# Usage: tools/capture_lobby.sh N OUT_DIR [WxH] [label]
set -euo pipefail
cd "$(dirname "$0")/.."
N=${1:?players}; OUT=${2:?out dir}; RES=${3:-2532x1170}
LABEL=${4:-"desktop Linux llvmpipe, LAN dev room, $N players"}
mkdir -p "$OUT"
PORT=$((7900 + RANDOM % 90))
W=${RES%x*}; H=${RES#*x}
XDG_DATA_HOME=$(mktemp -d) xvfb-run -a -s "-screen 0 $((W + 64))x$((H + 64))x24" timeout 600 tools/gd.sh --path game --resolution "$RES" -- \
  --net-host=$PORT --capture=lobby --capture-players="$N" --capture-dir="$OUT" --capture-label="$LABEL" \
  --no-gamecenter --random-cosmetic > "$OUT/lobby${N}_host.log" 2>&1 &
HOST=$!
sleep 6
for i in $(seq 2 "$N"); do
  XDG_DATA_HOME=$(mktemp -d) timeout 600 tools/gd.sh --headless --path game -- --net-join=127.0.0.1:$PORT \
    --no-gamecenter --random-cosmetic > "$OUT/lobby${N}_client$i.log" 2>&1 &
  sleep 0.5
done
wait $HOST || true
pkill -P $$ 2>/dev/null || true
ls "$OUT" | grep "lobby_${N}p" || echo "no capture"
