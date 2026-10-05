#!/usr/bin/env bash
# Pass 8 startup-logo evidence (docs/media/pass8/logo/): renders the startup
# stages at phone/iPad pixel sizes with the real game on llvmpipe under Xvfb
# (look and geometry only, never frame rate), then measures them against the
# vector (tools/branding/logo_evidence.py).
#
#   tools/branding/capture_logo_evidence.sh [OUT_DIR] [BEFORE_REV]
#
# OUT_DIR    scratch captures (default build/logo_evidence)
# BEFORE_REV the commit whose launch image and 1400-px runtime PNG are "before"
#            (default 018b8d0, V8 / 1.7 build 7)
#
# Per device: --capture=logo_variants (boot splash emulation for the before and
# after launch images, V8's curtain reproduced from its PNG and import
# settings, the Pass 8 fallback and the real Pass 8 BootCurtain).  At
# 2532x1170 also: the real boot (main scene) frame by frame at a fixed 60 fps
# clock (--capture=logo_startup), and X screenshots of the window during a
# real-time start, which catch Godot's actual boot splash (drawn before the
# main loop, so no in-engine capture can see it).
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-build/logo_evidence}
REV=${2:-018b8d0}
mkdir -p "$OUT/before"
OUT=$(cd "$OUT" && pwd)
git show "$REV:game/assets/icon/launch.png" > "$OUT/before/launch.png"
git show "$REV:game/assets/branding/idlery_games.png" > "$OUT/before/idlery_games.png"
tools/gd.sh --headless --path game --import > /dev/null 2>&1 || true

for res in 2532x1170 2778x1284 1334x750 2732x2048; do
  w=${res%x*}; h=${res#*x}
  d="$OUT/variants_$res"; mkdir -p "$d"
  XDG_DATA_HOME=$(mktemp -d) timeout 600 xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" \
    tools/gd.sh --path game --resolution "$res" -- --no-app --no-gamecenter --capture=logo_variants \
    --capture-dir="$d" --launch="before:$OUT/before/launch.png,after:$PWD/game/assets/icon/launch.png" \
    --old-png="$OUT/before/idlery_games.png" > "$d/log.txt" 2>&1 || true
  grep -E "^LOGO" "$d/log.txt" | tail -1 || echo "no variants for $res"
done

d="$OUT/startup_2532x1170"; mkdir -p "$d"
XDG_DATA_HOME=$(mktemp -d) timeout 900 xvfb-run -a -s "-screen 0 2600x1240x24" \
  tools/gd.sh --path game --resolution 2532x1170 --fixed-fps 60 -- --no-gamecenter --skip-onboarding \
  --capture=logo_startup --capture-dir="$d" > "$d/log.txt" 2>&1 || true
grep -E "^LOGO" "$d/log.txt" || echo "no startup frames"

# real-time start: screenshots of the X screen (the window fills it) while
# Godot shows its boot splash, the curtain and the fade into home
d="$OUT/xshots_2532x1170"; mkdir -p "$d"
cat > "$d/run.sh" <<'EOF'
#!/bin/bash
O=$1; shift
XDG_DATA_HOME=$(mktemp -d) "$@" > "$O/game.log" 2>&1 &
GP=$!
for i in $(seq -w 0 59); do import -window root -depth 8 "$O/x_$i.png" 2>/dev/null; done
kill "$GP" 2>/dev/null
wait
EOF
chmod +x "$d/run.sh"
timeout 600 xvfb-run -a -s "-screen 0 2532x1170x24" "$d/run.sh" "$d" \
  tools/gd.sh --path game --resolution 2532x1170 --position 0,0 -- --skip-onboarding --no-gamecenter || true
ls "$d" | grep -c '^x_' | sed 's/^/x screenshots: /'

python3 tools/branding/logo_evidence.py "$OUT" docs/media/pass8/logo
