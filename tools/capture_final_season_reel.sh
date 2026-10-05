#!/usr/bin/env bash
# Final release sweep, Season Pass clip (docs/final/season.md): the real
# Season Pass driven by scripted pointer input (src/dev/season_reel.tscn),
# recorded with Godot's Movie Maker at a fixed 30 fps clock (normal speed),
# Mobile renderer on llvmpipe under Xvfb, a 1170x540 window (an 844x390 pt
# iPhone's 19.5:9 shape: 1560x720 canvas units, 44 pt touch size and safe
# area as on the device), encoded to H.264 with a label burned in.
# Test-double service; scripted input; not device footage or frame rate.
# Usage: tools/capture_final_season_reel.sh OUT.mp4
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out.mp4}
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp -d)
PLAT="Season Pass, final sweep - test-double service, scripted touch, Godot 4.7.2 Mobile renderer on desktop llvmpipe, 30 fps Movie Maker clock, normal speed, not device footage"
for i in $(seq 180); do [ -e game/override.cfg ] || break; sleep 20; done
[ -e game/override.cfg ] && { echo "game/override.cfg exists; not touching it"; exit 1; }
printf '[display]\n\nwindow/size/window_width_override=1170\nwindow/size/window_height_override=540\n' > game/override.cfg
trap 'rm -f game/override.cfg; rm -rf "$TMP"' EXIT
XDG_DATA_HOME="$TMP" timeout "${CAPTURE_TIMEOUT:-3600}" xvfb-run -a -s "-screen 0 1280x720x24" \
  tools/gd.sh --path game --write-movie "$TMP/reel.avi" --fixed-fps 30 \
  res://src/dev/season_reel.tscn -- --no-gamecenter --emulate-phone=1.385 --emulate-safe=47,0,47,21 > "$TMP/log.txt" 2>&1 || true
grep -E "REEL|SCRIPT ERROR" "$TMP/log.txt" | head -40 || true
F=$(grep -m1 -o 'REEL start frame [0-9]*' "$TMP/log.txt" | awk '{print $4}')
SS=$(python3 -c "print(max(0.0, ${F:-0}/30.0 - 0.3))")
ffmpeg -loglevel error -y -ss "$SS" -i "$TMP/reel.avi" -c:v rawvideo -an "$TMP/trim.avi"
tools/label_movie.sh "$TMP/trim.avi" "$OUT" "$PLAT"
cp "$TMP/log.txt" "${OUT%.mp4}.log"
