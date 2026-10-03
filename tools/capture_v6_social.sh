#!/usr/bin/env bash
# V6 social evidence: the real game rendered by the Mobile renderer on
# llvmpipe (software Vulkan) under Xvfb at device sizes, in desktop LAN dev
# rooms (iOS parties use Game Center).  Layout and behaviour only: not frame
# rate, pacing, device input or heat.  The game service is not deployed and
# is off in these runs (typed chat and reports say so).
#
# Usage: tools/capture_v6_social.sh OUT_DIR [sets...]
#   sets: hub names results clip service (default: all)
#   CAPTURE_TIMEOUT (seconds per game, default 900): raise it on a busy
#   machine, where software rendering can drop to a frame every few seconds
#   HUB_SIZES (default "1 2 4 8"): party sizes for the hub set
#   hub      party room with 1/2/4/8 players: menu, walk around, bubbles,
#            chat drawer, player card, report sheet (phone size)
#   names    the name sheet refusing names, with suggestions (phone)
#   results  a real bot-driven practice round (headless, recorded), shown as
#            round 3 of a friend series: round page and final standings on
#            phone, iPhone SE and iPad
#   clip     a normal-speed clip of 4 players walking around (Movie Maker,
#            fixed 30 fps game clock: playback speed is game time)
#   service  the real service code run LOCALLY (service/tools/dev_server.mjs,
#            in-memory database, test Game Center key; NOT a deployment):
#            names approved by it, typed chat approved and verified, a
#            refused message, a message report with its receipt (and the
#            owner's queue from tools/admin.mjs), a block
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
SETS=${*:-hub names results clip service}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
PHONE="2532x1170 3 59,0,59,21"
SE="1334x750 2 0,0,0,0"
IPAD="2048x1536 2 0,24,0,20"

game() { # dir res scale safe args...
  local dir=$1 res=$2 scale=$3 safe=$4; shift 4
  local w=${res%x*} h=${res#*x}
  mkdir -p "$dir"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    nice -n 10 tools/gd.sh --path game --resolution "$res" "$@" -- \
    --emulate-phone="$scale" --emulate-safe="$safe" --capture-dir="$dir" --no-gamecenter \
    ${CAPTURE_ARGS:-} > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |SCRIPT ERROR" "$dir/log.txt" | sed "s|$OUT/||" || true
}

hub() { # N
  local n=$1 dir="$OUT/hub/${1}p" port=$((7900 + RANDOM % 90))
  mkdir -p "$dir"
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" xvfb-run -a -s "-screen 0 2600x1240x24" nice -n 10 tools/gd.sh --path game --resolution 2532x1170 -- \
    --emulate-phone=3 --emulate-safe=59,0,59,21 --net-host=$port --capture=social_hub --capture-players="$n" --capture-dir="$dir" \
    --capture-label="desktop Linux llvmpipe, LAN dev room, $n players, service off" --no-gamecenter --random-cosmetic > "$dir/host.log" 2>&1 &
  local host=$!
  local kids=()
  sleep 8
  for i in $(seq 2 "$n"); do
    XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-900}" nice -n 15 tools/gd.sh --headless --path game -- --net-join=127.0.0.1:$port \
      --capture=social_bot --capture-dir="$dir/bot$i" --no-gamecenter --random-cosmetic > "$dir/client$i.log" 2>&1 &
    kids+=($!)
    sleep 0.5
  done
  wait $host || true
  for k in "${kids[@]}"; do kill "$k" 2>/dev/null || true; done
  grep -E "^CAPTURE |SCRIPT ERROR" "$dir/host.log" | sed "s|$OUT/||" || true
}

for s in $SETS; do
  echo "== $s"
  case $s in
    hub)
      for n in ${HUB_SIZES:-1 2 4 8}; do hub "$n"; done;;
    names)
      # shellcheck disable=SC2086
      CAPTURE_ARGS="--capture=social_names --skip-onboarding" game "$OUT/names" $PHONE;;
    results)
      rec="$OUT/recorded/runner_results.var"
      if [ ! -f "$rec" ]; then
        mkdir -p "$OUT/recorded"
        XDG_DATA_HOME=$(mktemp -d) timeout 1800 nice -n 10 tools/gd.sh --headless --path game --fixed-fps 60 -- \
          --capture=runner --autoplay=runner --local-bot --skip-onboarding --capture-dir="$OUT/recorded" --no-gamecenter \
          > "$OUT/recorded/log.txt" 2>&1 || true
      fi
      [ -f "$rec" ] || { echo "no recorded round"; continue; }
      for d in phone se ipad; do
        case $d in phone) p=$PHONE;; se) p=$SE;; ipad) p=$IPAD;; esac
        # shellcheck disable=SC2086
        CAPTURE_ARGS="--capture=social_results --capture-results=$rec --skip-onboarding" game "$OUT/results/$d" $p
      done;;
    clip)
      mkdir -p "$OUT/clip"
      port=$((7900 + RANDOM % 90))
      XDG_DATA_HOME=$(mktemp -d) timeout 5400 xvfb-run -a -s "-screen 0 1400x800x24" nice -n 10 tools/gd.sh --path game --resolution 1280x720 \
        --write-movie "$OUT/clip/hub_walk.avi" --fixed-fps 30 -- --emulate-phone=1.92 --net-host=$port --capture=social_hub \
        --capture-players=4 --capture-dir="$OUT/clip/shots" --no-gamecenter --random-cosmetic > "$OUT/clip/host.log" 2>&1 &
      host=$!
      sleep 20
      kids=()
      for i in 2 3 4; do
        XDG_DATA_HOME=$(mktemp -d) timeout 5400 nice -n 15 tools/gd.sh --headless --path game -- --net-join=127.0.0.1:$port \
          --capture=social_bot --capture-dir="$OUT/clip/bot$i" --no-gamecenter --random-cosmetic > "$OUT/clip/client$i.log" 2>&1 &
        kids+=($!)
        sleep 1
      done
      wait $host || true
      for k in "${kids[@]}"; do kill "$k" 2>/dev/null || true; done
      if [ -f "$OUT/clip/hub_walk.avi" ]; then
        tools/label_movie.sh "$OUT/clip/hub_walk.avi" "$OUT/clip/hub_walk_4p.mp4" \
          "desktop Linux llvmpipe · LAN dev room, 4 players (3 scripted headless clients) · Movie Maker 30 fps game clock, not real-time performance" \
          && rm -f "$OUT/clip/hub_walk.avi"
      fi;;
    service)
      dir="$OUT/service"; mkdir -p "$dir/svc"
      sp=$((8700 + RANDOM % 90)); ep=$((7900 + RANDOM % 90))
      (cd service && node tools/dev_server.mjs $sp "$dir/svc") > "$dir/dev_server.log" 2>&1 &
      svc=$!
      sleep 3
      XDG_DATA_HOME=$(mktemp -d) timeout 1800 xvfb-run -a -s "-screen 0 2600x1240x24" nice -n 10 tools/gd.sh --path game --resolution 2532x1170 -- \
        --emulate-phone=3 --emulate-safe=59,0,59,21 --net-host=$ep --capture=social_service_host --capture-dir="$dir" \
        --capture-label="desktop Linux llvmpipe, LAN dev room registered with the service code run locally (not deployed)" \
        --service-url=http://127.0.0.1:$sp --dev-service-dir="$dir/svc" --dev-player=T:dev-host --dev-name="Juniper Moss" \
        --no-gamecenter --random-cosmetic > "$dir/host.log" 2>&1 &
      host=$!
      sleep 5
      XDG_DATA_HOME=$(mktemp -d) timeout 1800 nice -n 15 tools/gd.sh --headless --path game -- --capture=social_service_guest \
        --capture-dir="$dir/guest" --service-url=http://127.0.0.1:$sp --dev-service-dir="$dir/svc" --dev-player=T:dev-guest \
        --dev-name="Rowan Pine" --dev-port=$ep --no-gamecenter --random-cosmetic > "$dir/guest.log" 2>&1 &
      guest=$!
      wait $host || true
      kill $guest 2>/dev/null || true
      TRIFECTA_SERVICE=http://127.0.0.1:$sp TRIFECTA_ADMIN_TOKEN=$(cat "$dir/svc/admin_token.txt") node service/tools/admin.mjs queue > "$dir/admin_queue.txt" 2>&1 || true
      TRIFECTA_SERVICE=http://127.0.0.1:$sp TRIFECTA_ADMIN_TOKEN=$(cat "$dir/svc/admin_token.txt") node service/tools/admin.mjs audit 40 > "$dir/admin_audit.txt" 2>&1 || true
      kill $svc 2>/dev/null || true
      grep -E "^CAPTURE |SCRIPT ERROR|^SOCIAL" "$dir/host.log" "$dir/guest.log" | sed "s|$OUT/||" || true
      cat "$dir/admin_queue.txt";;
    *) echo "unknown set $s";;
  esac
done
