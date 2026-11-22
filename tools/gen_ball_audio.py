#!/usr/bin/env python3
"""(build 24) The party room basketball's sounds, synthesised from scratch
(original, no samples).  Its own script and random seed, so the other
effects (tools/gen_audio.py) are untouched.
Usage: python3 tools/gen_ball_audio.py -> game/assets/audio/ball_*.wav
(build 33: ball_block and ball_dunk, appended last so the others are
unchanged when it is run again)
"""
import os, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio")
rng = np.random.default_rng(2424)


def t_(d):
    return np.arange(int(SR * d)) / SR


def save(name, x, vol=0.8):
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * vol
    # 3 ms fades: never a click
    f = int(SR * 0.003)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def onepole_lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def bandpass(x, f0, q):
    # RBJ biquad band-pass
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b0, b1, b2 = al, 0.0, -al
    a0, a1, a2 = 1 + al, -2 * np.cos(w0), 1 - al
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        v = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x[i]
        y2, y1 = y1, v
        y[i] = v
    return y


# --- a bounce on the wooden floor: the ball's hollow "pung" (a pitched
# body that drops a little as it rings), a slap of leather on wood, and the
# boards' low knock under it
d = 0.32
t = t_(d)
f = 175 * (1 + 0.25 * np.exp(-t * 60))
ph = 2 * np.pi * np.cumsum(f) / SR
body = np.sin(ph) * np.exp(-t * 16) + 0.35 * np.sin(2.02 * ph) * np.exp(-t * 26)
slap = onepole_lp(rng.uniform(-1, 1, len(t)), 3800) * np.exp(-t * 140)
knock = np.sin(2 * np.pi * 82 * t) * np.exp(-t * 30)
save("ball_bounce", body * 0.9 + slap * 0.7 + knock * 0.5, 0.85)

# --- off the rim: a bright metal clank (inharmonic partials, a quick
# ring-off) with a dull thump of the ball
d = 0.6
t = t_(d)
partials = [(523, 1.0, 9), (1187, 0.7, 12), (1874, 0.5, 15), (2741, 0.35, 19), (3920, 0.2, 26)]
ring = sum(a * np.sin(2 * np.pi * fr * t + rng.uniform(0, 6.28)) * np.exp(-t * dc) for fr, a, dc in partials)
hit = onepole_lp(rng.uniform(-1, 1, len(t)), 2500) * np.exp(-t * 90)
thump = np.sin(2 * np.pi * 160 * t) * np.exp(-t * 28)
save("ball_rim", ring * 0.8 + hit * 0.5 + thump * 0.6, 0.8)

# --- off the backboard: a flat, hard knock (a board in a frame)
d = 0.3
t = t_(d)
board = np.sin(2 * np.pi * 240 * t) * np.exp(-t * 34) + 0.6 * np.sin(2 * np.pi * 410 * t) * np.exp(-t * 48)
crack = onepole_lp(rng.uniform(-1, 1, len(t)), 5000) * np.exp(-t * 180)
save("ball_board", board + crack * 0.8, 0.8)

# --- into something soft (the couch, a cushion, a friend): a muffled thud
d = 0.22
t = t_(d)
thud = np.sin(2 * np.pi * 110 * t) * np.exp(-t * 30) + 0.6 * onepole_lp(rng.uniform(-1, 1, len(t)), 700) * np.exp(-t * 45)
save("ball_thud", thud, 0.7)

# --- (build 33) a block: a sharp slap of a palm on leather (a bright crack
# and a band of noise around 1.6 kHz), the ball's hollow "pok" knocked off
# pitch, and a short whoosh as it flies away
d = 0.42
t = t_(d)
crack = bandpass(rng.uniform(-1, 1, len(t)), 1600, 1.4) * np.exp(-t * 70)
snap = onepole_lp(rng.uniform(-1, 1, len(t)), 6000) * np.exp(-t * 220)
f = 300 * (1 - 0.3 * (1 - np.exp(-t * 30)))
pok = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 22)
air = bandpass(rng.uniform(-1, 1, len(t)), 900, 0.8) * np.clip(t / 0.06, 0, 1) * np.exp(-np.maximum(t - 0.06, 0) * 14) * 0.35
save("ball_block", crack * 1.0 + snap * 0.6 + pok * 0.55 + air, 0.85)

# --- (build 33) a dunk: the rim slammed (a lower, heavier clank than a
# shot off it, ringing longer, with the hinge's rattle) over a thump
d = 0.9
t = t_(d)
partials = [(392, 1.0, 6), (887, 0.75, 8), (1411, 0.5, 11), (2093, 0.35, 15), (3010, 0.2, 20)]
ring = sum(a * np.sin(2 * np.pi * fr * t + rng.uniform(0, 6.28)) * np.exp(-t * dc) for fr, a, dc in partials)
rattle = bandpass(rng.uniform(-1, 1, len(t)), 2200, 3.0) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 24 * t))) * np.exp(-t * 9)
slam = onepole_lp(rng.uniform(-1, 1, len(t)), 1800) * np.exp(-t * 60)
boom = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 14)
save("ball_dunk", ring * 0.8 + rattle * 0.35 + slam * 0.7 + boom * 0.8, 0.9)
