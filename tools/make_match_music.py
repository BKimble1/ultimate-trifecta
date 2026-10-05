#!/usr/bin/env python3
"""Builds the in-round music (game/assets/audio/music_match.ogg) from the
owner's "Soft Bounce Loop" recording: a one-time intro followed by a seamless
16-bar loop that Godot plays sample-accurately (AudioStreamOggVorbis loop +
loop_offset, set in music_match.ogg.import by this script).

Source: art_src/audio/soft_bounce_loop_source.m4a, the AAC audio stream
copied losslessly out of the owner's screen recording (the mureka.ai player,
"Soft Bounce Loop" by Blake Kimble; 61.8 s, the first minute of the song).
Only the .ogg ships in the app.

The track is 100.000 BPM, 4/4 (a beat is exactly 26460 samples, a bar 105840)
in D major, on a strict grid (no drift over the minute; the per-bar onset
phase is flat to within the measurement noise).  Its first downbeat is at
1.028 s in the source (FIRST_DOWNBEAT), after a pickup.  The form repeats on 8
bars (bars 7-11 return as 15-19); the loop is the 16 bars from bar 5 to bar
20 and wraps at the downbeat of bar 21 back to bar 5: of the candidate seams
that one continues best in the bass, mids and highs both before and after
the downbeat (spectral similarity >= 0.63 in every band; the 8-bar seam at
bar 15 is as smooth but would repeat every 19 s).  At the wrap the last
XFADE samples before the downbeat cross-fade (equal power) from the second
pass into the first, ending XFADE_END samples before the downbeat's attack,
so every drum hit comes from one pass (nothing doubled) and the switch hides
under the attack.

The file starts exactly one beat before the first downbeat (the pickup), so
the game can start it on a beat of the lobby music (audio_service.gd: the
lobby -> round blend).

Usage: python3 tools/make_match_music.py   (needs numpy and ffmpeg)
"""
import os, re, subprocess, sys, tempfile
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "art_src", "audio", "soft_bounce_loop_source.m4a")
OUT = os.path.join(ROOT, "game", "assets", "audio", "music_match.ogg")
SR = 44100
BEAT = 26460                     # 100 BPM: 60 / 100 * 44100
BAR = 4 * BEAT
FIRST_DOWNBEAT = 45329           # bar 0's downbeat in the source (1.028 s)
START = FIRST_DOWNBEAT - BEAT    # the file opens on the pickup beat
LOOP_BAR = 5                     # the loop starts at bar 5's downbeat ...
LOOP_BARS = 16                   # ... and wraps 16 bars later (bar 21 -> bar 5)
LOOP_START = FIRST_DOWNBEAT + LOOP_BAR * BAR
LOOP_LEN = LOOP_BARS * BAR
XFADE = 882                      # 20 ms
XFADE_END = -132                 # cross-fade ends 3 ms before the downbeat's attack
TARGET_LUFS = -23.0              # the lobby track's level, so the blend is level
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


def build(y, xfade=XFADE, xfade_end=XFADE_END):
    intro = y[START:LOOP_START].copy()
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, 220))
    intro[:220] *= ramp[:, None]
    body = y[LOOP_START:LOOP_START + LOOP_LEN].copy()
    # Tail: the second pass hands over to the first pass just before the downbeat.
    a = LOOP_LEN + xfade_end - xfade
    t = (np.arange(xfade) + 0.5) / xfade
    first_pass = y[LOOP_START + xfade_end - xfade:LOOP_START + xfade_end]
    body[a:a + xfade] = body[a:a + xfade] * np.cos(t * np.pi / 2)[:, None] + first_pass * np.sin(t * np.pi / 2)[:, None]
    body[LOOP_LEN + xfade_end:] = y[LOOP_START + xfade_end:LOOP_START]
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
        pcm = os.path.join(tmp, "match.f32")
        write_f32(pcm, full)
        subprocess.run(["ffmpeg", "-v", "error", "-y"] + RAW_IN + ["-i", pcm, "-c:a", "libvorbis", "-q:a", str(VORBIS_Q),
                "-map_metadata", "-1", "-fflags", "+bitexact", OUT], check=True)
        decoded = decode(OUT)
        if len(decoded) != len(full):
            sys.exit("encoded length %d != %d samples" % (len(decoded), len(full)))
        out_lufs, out_peak = loudness(OUT)
    loop_offset = (len(intro) + 0.5) / SR   # mid-sample, so Godot's floor(seconds * rate) lands on len(intro)
    imp = OUT + ".import"
    if os.path.exists(imp):
        text = open(imp).read()
        text = re.sub(r"(?m)^loop=.*$", "loop=true", text)
        text = re.sub(r"(?m)^loop_offset=.*$", "loop_offset=%.9f" % loop_offset, text)
        open(imp, "w").write(text)
    else:
        print("no %s yet: import the project once, then run this again to set the loop" % os.path.relpath(imp, ROOT))
    print("intro %d samples (%.3f s), loop %d samples (%.3f s), total %.3f s" % (
        len(intro), len(intro) / SR, len(body), len(body) / SR, len(full) / SR))
    print("gain %.2f dB -> %.1f LUFS, peak %.1f dBFS; %s (%d KB)" % (
        20 * np.log10(gain), out_lufs, out_peak, os.path.relpath(OUT, ROOT), os.path.getsize(OUT) // 1024))
    print("loop_offset=%.9f" % loop_offset)


if __name__ == "__main__":
    main()
