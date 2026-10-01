#!/usr/bin/env bash
# Multi-process network soak over real UDP (ENet) on this machine:
# 1 host + N desktop client processes, each with outbound latency/jitter/loss
# shaping, playing full rounds with automation input. Writes JSON reports.
# Usage: [SOAK_OUT=dir] tools/net_soak.sh [clients=7] [one_way_lag_ms=60] [jitter_ms=10] [loss=0.03] [rounds=1]
set -euo pipefail
cd "$(dirname "$0")/.."
N=${1:-7}; LAG=${2:-60}; JIT=${3:-10}; LOSS=${4:-0.03}; ROUNDS=${5:-1}
OUT=${SOAK_OUT:-docs/test-data/net_soak_${N}c_${LAG}ms_${LOSS}}
mkdir -p "$OUT"
PORT=$((7700 + RANDOM % 200))
COMMON="--headless --max-fps 60 --path game"
tools/gd.sh --headless --path game --import >/dev/null 2>&1 || true
# isolate each process' user profile so uids differ
export XDG_DATA_HOME=$(mktemp -d)
tools/gd.sh $COMMON -- --net-host=$PORT --expect=$((N+1)) --local-bot --lag=$LAG --jitter=$JIT --loss=$LOSS --rounds=$ROUNDS --seed=2026 --report=$PWD/$OUT/host.json > "$OUT/host.log" 2>&1 &
HPID=$!
sleep 2
PIDS=()
for i in $(seq 1 $N); do
  XDG_DATA_HOME=$(mktemp -d) tools/gd.sh $COMMON -- --net-join=127.0.0.1:$PORT --local-bot --lag=$LAG --jitter=$JIT --loss=$LOSS --rounds=$ROUNDS --report=$PWD/$OUT/client$i.json > "$OUT/client$i.log" 2>&1 &
  PIDS+=($!)
done
wait $HPID || true
for p in "${PIDS[@]}"; do wait $p || true; done
echo "reports in $OUT"; ls "$OUT"
