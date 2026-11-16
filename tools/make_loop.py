#!/usr/bin/env python3
"""Make a seamless music loop from a recording (2.2 build 16, lobby albums).

  tools/make_loop.py IN.wav OUT.wav --start S [--search-from T] [--xfade X]

Finds the loop end b (searched from T to the end) whose lead-in sounds most
like the lead-in to the loop start S (log-spectrum frames, cosine
similarity over a 2 s window), then writes audio[S:b] with the last X
seconds crossfaded (equal power) with the X seconds before S, so playing
the file on repeat runs straight on from b into S.  Also levels the
loudness (RMS -18 dBFS, peak under -1 dBFS).  numpy only.
"""
import argparse
import wave

import numpy as np


def read(path):
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, w.getnchannels()).astype(np.float64) / 32768.0
    return x, sr


def write(path, x, sr):
    y = np.clip(x, -1.0, 1.0)
    w = wave.open(path, "wb")
    w.setnchannels(y.shape[1])
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes((y * 32767.0).astype(np.int16).tobytes())
    w.close()


def features(x, sr, hop=1024, n=2048):
    m = x.mean(axis=1)
    frames = []
    win = np.hanning(n)
    for i in range(0, len(m) - n, hop):
        spec = np.abs(np.fft.rfft(m[i:i + n] * win))
        # 48 log-spaced bands from 60 Hz to 8 kHz
        edges = np.geomspace(60, 8000, 49) * n / sr
        b = [spec[int(edges[k]):max(int(edges[k]) + 1, int(edges[k + 1]))].mean() for k in range(48)]
        frames.append(np.log(np.array(b) + 1e-6))
    return np.array(frames), hop


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--search-from", type=float, default=None)
    ap.add_argument("--end-margin", type=float, default=0.3)
    ap.add_argument("--xfade", type=float, default=2.5)
    a = ap.parse_args()
    x, sr = read(a.inp)
    F, hop = features(x, sr)
    fps = sr / hop
    W = int(2.0 * fps)
    s = int(a.start * fps)
    lo = int((a.search_from if a.search_from is not None else len(x) / sr - 12.0) * fps)
    hi = int((len(x) / sr - a.end_margin) * fps)
    ref = F[s - W:s].ravel()
    ref = (ref - ref.mean()) / (ref.std() + 1e-9)
    best, best_b = -9.0, hi
    for b in range(max(lo, W), hi):
        c = F[b - W:b].ravel()
        c = (c - c.mean()) / (c.std() + 1e-9)
        sc = float(np.dot(ref, c) / len(ref))
        if sc > best:
            best, best_b = sc, b
    S = int(a.start * sr)
    B = int(best_b / fps * sr)
    X = int(a.xfade * sr)
    assert S >= X, "start must be at least the crossfade length"
    body = x[S:B].copy()
    t = np.linspace(0.0, 1.0, X)[:, None]
    fade_out = np.cos(t * np.pi / 2)
    fade_in = np.sin(t * np.pi / 2)
    body[-X:] = body[-X:] * fade_out + x[S - X:S] * fade_in
    rms = np.sqrt((body ** 2).mean())
    body *= 10 ** (-18 / 20) / max(rms, 1e-9)
    pk = np.abs(body).max()
    if pk > 10 ** (-1 / 20):
        body *= 10 ** (-1 / 20) / pk
    write(a.out, body, sr)
    print("%s: loop %.2f s -> %.2f s (%.1f s), match %.3f" % (a.out, a.start, B / sr, (B - S) / sr, best))


if __name__ == "__main__":
    main()
