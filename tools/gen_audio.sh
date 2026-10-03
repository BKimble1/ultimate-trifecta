#!/usr/bin/env bash
# Regenerates all audio (python3 + numpy) and converts music loops to Ogg Vorbis (ffmpeg).
# The lobby music (music_menu.ogg) is not synthesized: see tools/make_lobby_music.py.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/gen_audio.py
for m in music_chase_calm music_results; do
  ffmpeg -y -loglevel error -i game/assets/audio/$m.wav -c:a libvorbis -q:a 4 game/assets/audio/$m.ogg
  rm game/assets/audio/$m.wav
done
