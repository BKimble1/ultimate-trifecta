#!/usr/bin/env bash
# Encodes a Movie Maker AVI to H.264 MP4 with a label burned into the bottom
# of the frame, so a clip can't be mistaken for device footage.
# Usage: tools/label_movie.sh in.avi out.mp4 "label text"
set -euo pipefail
IN=${1:?in.avi}; OUT=${2:?out.mp4}; LABEL=${3:?label}
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
ESC=$(printf '%s' "$LABEL" | sed -e "s/\\\\/\\\\\\\\/g" -e "s/:/\\\\:/g" -e "s/'/\\\\'/g" -e "s/%/\\\\%/g")
ffmpeg -loglevel error -y -i "$IN" -vf "drawbox=y=ih-30:w=iw:h=30:color=black@0.55:t=fill,drawtext=fontfile=$FONT:text='$ESC':fontcolor=white:fontsize=15:x=10:y=h-22" \
  -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an "$OUT"
ls -la "$OUT"
