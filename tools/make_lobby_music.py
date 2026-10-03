#!/usr/bin/env python3
"""Builds the lobby music (game/assets/audio/music_menu.ogg) from the owner's
"Night Campus Loop" recording: a one-time intro followed by a seamless
12-bar loop that Godot plays sample-accurately (AudioStreamOggVorbis loop +
loop_offset, set in music_menu.ogg.import by this script).

Source: art_src/audio/night_campus_loop_source.m4a, the AAC audio stream
copied losslessly out of the owner's screen recording (the mureka.ai player,
"Night Campus Loop" by Blake Kimble). Only the .ogg ships in the app.

The track is 84.000 BPM, 4/4 (a bar is exactly 126000 samples at 44.1 kHz).
Its form is a sparse 4-bar intro, an 8-bar main section, then a fuller
4-bar restatement of the intro and the main section again, so the music
repeats with a 12-bar lag. The loop runs from the downbeat of bar 4 of the
first main section (21.91 s in the recording) to the same downbeat 12 bars
later (56.20 s). At the wrap, the last 20 ms before the downbeat cross-fade
(equal power) from the second pass into the first, ending 3 ms before the
downbeat's attack, so every drum hit comes from one pass (nothing doubled)
and the bass is continuous. The 1.7 s of silence before the music and the
recording's fade-out after 58.3 s are not used.

Usage: python3 tools/make_lobby_music.py   (needs numpy and ffmpeg)
"""
import os, re, subprocess, sys, tempfile
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "art_src", "audio", "night_campus_loop_source.m4a")
OUT = os.path.join(ROOT, "game", "assets", "audio", "music_menu.ogg")
SR = 44100
BAR = 126000                   # 84 BPM, 4/4: 4 * 60 / 84 * 44100
SECTION = 588298               # bar line where the main section enters (13.340 s)
LOOP_START = SECTION + 3 * BAR # downbeat of the loop (21.912 s)
LOOP_LEN = 12 * BAR - 4        # second pass sits 4 samples early (transient alignment)
XFADE = 882                    # 20 ms
XFADE_END = -61                # cross-fade ends 61 samples before the downbeat (3 ms before its attack)
TARGET_LUFS = -23.0            # the level of the menu music this replaces (chase/results are -22)
VORBIS_Q = 5


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
            check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)


def write_f32(path, x):
    np.clip(x, -1.0, 1.0).astype("<f4").tofile(path)


RAW_IN = ["-f", "f32le", "-ar", str(SR), "-ac", "2"]


def loudness(path, raw=False):
    err = subprocess.run(["ffmpeg", "-nostats"] + (RAW_IN if raw else []) + ["-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
            capture_output=True, text=True).stderr
    summary = err[err.rfind("Summary:"):]
    lufs = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))
    peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summary).group(1))
    return lufs, peak


def build(y):
    # Start just before the first note (the recording opens with 1.7 s of silence).
    first = int(np.argmax(np.abs(y).max(axis=1) > 10 ** (-60 / 20)))
    start = max(first - 220, 0)
    intro = y[start:LOOP_START].copy()
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, 220))
    intro[:220] *= ramp[:, None]
    body = y[LOOP_START:LOOP_START + LOOP_LEN].copy()
    # Tail: the second pass hands over to the first pass just before the downbeat.
    a = LOOP_LEN + XFADE_END - XFADE
    t = (np.arange(XFADE) + 0.5) / XFADE
    first_pass = y[LOOP_START + XFADE_END - XFADE:LOOP_START + XFADE_END]
    body[a:a + XFADE] = body[a:a + XFADE] * np.cos(t * np.pi / 2)[:, None] + first_pass * np.sin(t * np.pi / 2)[:, None]
    body[LOOP_LEN + XFADE_END:] = y[LOOP_START + XFADE_END:LOOP_START]
    return intro, body


def main():
    if not os.path.exists(SRC):
        sys.exit("missing " + SRC)
    y = decode(SRC)
    intro, body = build(y)
    with tempfile.TemporaryDirectory() as tmp:
        probe = os.path.join(tmp, "probe.f32")
        write_f32(probe, np.concatenate([body, body]))   # the loop as it is heard
        lufs, _ = loudness(probe, raw=True)
        gain = 10 ** ((TARGET_LUFS - lufs) / 20)
        full = np.concatenate([intro, body]) * gain
        pcm = os.path.join(tmp, "lobby.f32")
        write_f32(pcm, full)
        subprocess.run(["ffmpeg", "-v", "error", "-y"] + RAW_IN + ["-i", pcm, "-c:a", "libvorbis", "-q:a", str(VORBIS_Q),
                "-map_metadata", "-1", "-fflags", "+bitexact", OUT], check=True)
        decoded = decode(OUT)
        if len(decoded) != len(full):
            sys.exit("encoded length %d != %d samples" % (len(decoded), len(full)))
        out_lufs, out_peak = loudness(OUT)
    loop_offset = (len(intro) + 0.5) / SR   # mid-sample, so Godot's floor(seconds * rate) lands on len(intro)
    imp = OUT + ".import"
    text = open(imp).read()
    text = re.sub(r"(?m)^loop=.*$", "loop=true", text)
    text = re.sub(r"(?m)^loop_offset=.*$", "loop_offset=%.9f" % loop_offset, text)
    open(imp, "w").write(text)
    print("intro %d samples (%.3f s), loop %d samples (%.3f s), total %.3f s" % (
        len(intro), len(intro) / SR, len(body), len(body) / SR, len(full) / SR))
    print("gain %.2f dB -> %.1f LUFS, peak %.1f dBFS; %s (%d KB)" % (
        20 * np.log10(gain), out_lufs, out_peak, os.path.relpath(OUT, ROOT), os.path.getsize(OUT) // 1024))
    print("loop_offset=%.9f written to %s" % (loop_offset, os.path.relpath(imp, ROOT)))


if __name__ == "__main__":
    main()
