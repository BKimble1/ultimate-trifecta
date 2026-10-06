#!/usr/bin/env bash
# App Store screenshots for version 2.0, rendered from the real game: the
# release candidate's own screens and a staged practice round, rendered by
# the Mobile renderer on llvmpipe under Xvfb (Mesa limited to AVX by
# tools/gd.sh) at each store size, with nothing stamped on them
# (--store-shot).  Desktop renders: the owner approves them or replaces any
# with device screenshots (docs/media/final/store/README.md).
#
#   iphone  2868x1320  iPhone 6.9" (956x440 pt @3x), safe area 62/0/62/21 pt
#   ipad    2752x2064  iPad 13" (1376x1032 pt @2x), safe area 0/24/0/20 pt
#
# Drivers (src/dev: never exported):
#   src/dev/store_capture.tscn    menus: party, Season Pass, Shop, Friends,
#       Locker, Final standings; --set=iap the App Review references.
#       Fixtures: the TEST-DOUBLE game service and simulated store
#       (fake_commerce_service.gd, test_store_adapter.gd), the TEST-DOUBLE
#       Friends side (fake_friends.gd), an in-process loopback party;
#       fictional players only.
#   --capture=store_match (src/dev/store_match_capture.gd): a practice round
#       (seed 2: the fountain is one of the round's waters) staged into a
#       splash at Founders' Fountain with a Night Watch closing in, and a
#       Night Watch golf cart closing on two runners.
#
# Usage: tools/capture_store_screenshots.sh OUT_DIR [iphone] [ipad]
#   OUT_DIR/raw/<device>/   every frame the drivers took, with their logs
#   OUT_DIR/iphone_6.9/, OUT_DIR/ipad_13/   the sets (NN_name.png)
#   OUT_DIR/iap/            App Review references (iPhone size; labelled)
#   ONLY="menus splash cart iap"  the parts to (re)render (default: all;
#       ONLY=none re-assembles the sets from OUT_DIR/raw only);
#       parts not rendered are taken from OUT_DIR/raw if already there
#   SPLASH_PICK / CART_PICK   the gameplay frame for each set (defaults
#       below: the frames chosen at review; the round is deterministic on
#       the fixed 20 fps clock, so the same frames repeat)
#   FAST=1   framing check: each device at its point size (@1), quick; the
#       images are then NOT store sizes and the size check fails
#   CAPTURE_TIMEOUT  seconds per run (default 3600)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
DEVICES=${*:-iphone ipad}
ONLY=${ONLY:-menus splash cart iap}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

spec() {   # device -> "res scale safe set_dir"
  if [ "${FAST:-0}" = 1 ]; then
    case $1 in
      iphone) echo "956x440 1 62,0,62,21 iphone_6.9";;
      ipad)   echo "1376x1032 1 0,24,0,20 ipad_13";;
    esac
  else
    case $1 in
      iphone) echo "2868x1320 3 62,0,62,21 iphone_6.9";;
      ipad)   echo "2752x2064 2 0,24,0,20 ipad_13";;
    esac
  fi
}

want() { [[ " $ONLY " == *" $1 "* ]]; }

xrun() {   # res, then godot args
  local res=$1; shift
  local w=${res%x*} h=${res#*x}
  XDG_DATA_HOME=$(mktemp -d) timeout "${CAPTURE_TIMEOUT:-3600}" nice -n 10 \
    xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" tools/gd.sh --path game --resolution "$res" "$@"
}

menus() {   # device set
  local d=$1 set=$2
  read -r res scale safe _ < <(spec "$d")
  local dir="$OUT/raw/$d/$set"
  mkdir -p "$dir"
  echo "== $d $set ($res @$scale, safe $safe)"
  xrun "$res" res://src/dev/store_capture.tscn -- --capture-dir="$dir" --set="$set" --store-shot \
    --emulate-phone="$scale" --emulate-safe="$safe" --no-gamecenter > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |SCRIPT ERROR|STORE " "$dir/log.txt" | sed "s|$OUT/||" || true
}

match() {   # device part role
  local d=$1 part=$2 role=$3
  read -r res scale safe _ < <(spec "$d")
  local dir="$OUT/raw/$d/$part"
  mkdir -p "$dir"
  echo "== $d $part ($res @$scale, safe $safe)"
  xrun "$res" --fixed-fps 20 -- --emulate-phone="$scale" --emulate-safe="$safe" --capture=store_match --store-part="$part" \
    --autoplay="$role" --seed=2 --capture-dir="$dir" --store-shot --quality=1 --no-gamecenter --skip-onboarding \
    --name="Comfy Frog" > "$dir/log.txt" 2>&1 || true
  grep -E "^CAPTURE |SCRIPT ERROR" "$dir/log.txt" | sed "s|$OUT/||" || true
}

# the gameplay frame picked for each set (see the README)
pick_splash() { case $1 in iphone) echo "${SPLASH_PICK:-splash_air_0}";; ipad) echo "${SPLASH_PICK:-splash_air_0}";; esac; }
pick_cart() { case $1 in iphone) echo "${CART_PICK:-cart_d}";; ipad) echo "${CART_PICK:-cart_d}";; esac; }

for d in $DEVICES; do
  read -r res scale safe setdir < <(spec "$d")
  want menus && menus "$d" store
  want splash && match "$d" splash runner
  want cart && match "$d" cart patrol
  [ "$d" = iphone ] && want iap && menus "$d" iap
  # ---- assemble the set
  raw="$OUT/raw/$d"
  mkdir -p "$OUT/$setdir"
  while read -r name src; do
    if [ -f "$raw/$src.png" ]; then
      cp "$raw/$src.png" "$OUT/$setdir/$name.png"
    else
      echo "MISSING $d $src"
    fi
  done <<EOF
01_runner_splash_fountain splash/$(pick_splash "$d")
02_night_watch_golf_cart cart/$(pick_cart "$d")
03_party_of_eight store/s03_party
04_season_pass_record_breaker store/s04_season
05_shop_featured store/s05_shop
06_friends_invite store/s06_friends
07_locker store/s07_locker
08_final_standings store/s08_results
EOF
  if [ "$d" = iphone ] && [ -d "$raw/iap" ]; then
    mkdir -p "$OUT/iap"
    for f in "$raw"/iap/iap_*.png; do
      [ -f "$f" ] && cp "$f" "$OUT/iap/$(basename "${f%.png}")_reference.png"
    done
  fi
done

# ---- every image: exact store size, RGB with no alpha
python3 tools/store_shot_check.py "$OUT" || true
