#!/usr/bin/env python3
"""Synthesises every Ultimate Trifecta sound effect and music loop.
All audio is generated from scratch by this script (original, no samples).
Usage: python3 tools/gen_audio.py  -> writes game/assets/audio/*.wav
"""
import os, wave, struct
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio")
rng = np.random.default_rng(3)

def t_(d): return np.linspace(0, d, int(SR * d), endpoint=False)
def env(n, a=0.005, r=0.1, total=None):
    total = total or n / SR
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(a, 1e-4))
    e *= np.clip((total - t) / max(r, 1e-4), 0, 1)
    return e
def adsr(n, a, d, s, r):
    t = np.arange(n) / SR; tot = n / SR
    e = np.where(t < a, t / a, np.where(t < a + d, 1 - (1 - s) * (t - a) / d, s))
    e *= np.clip((tot - t) / r, 0, 1)
    return e
def noise(n): return rng.uniform(-1, 1, n)
def lowpass(x, cutoff):
    # one-pole low pass
    a = np.exp(-2 * np.pi * cutoff / SR); y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y
def highpass(x, cutoff): return x - lowpass(x, cutoff)
def sweep(f0, f1, d, shape="sine"):
    t = t_(d); f = f0 * (f1 / f0) ** (t / d); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if shape == "sine" else (2 * ((ph / (2*np.pi)) % 1) - 1)
def tone(f, d, shape="sine"):
    t = t_(d)
    if shape == "sine": return np.sin(2*np.pi*f*t)
    if shape == "square": return np.sign(np.sin(2*np.pi*f*t)) * 0.6
    if shape == "tri": return 2*np.abs(2*((f*t) % 1) - 1) - 1
    if shape == "saw": return 2*((f*t) % 1) - 1
def save(name, x, vol=0.8, stereo=False):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * vol
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())

# --- UI
save("click", tone(1200, 0.04, "tri") * env(int(SR*0.04), 0.001, 0.03), 0.5)
save("beep", tone(880, 0.16, "tri") * env(int(SR*0.16), 0.003, 0.06), 0.6)
go = np.concatenate([tone(660, 0.09, "tri"), tone(990, 0.25, "tri")]); save("go", go * env(len(go), 0.003, 0.15), 0.7)
save("tick", tone(1500, 0.05, "square") * env(int(SR*0.05), 0.001, 0.04), 0.35)
pop = sweep(300, 900, 0.08) * env(int(SR*0.08), 0.001, 0.05); save("pop", pop, 0.5)

# --- water
n = int(SR*0.9); s = lowpass(noise(n), 2500) * adsr(n, 0.004, 0.25, 0.35, 0.5)
s += 0.5 * lowpass(noise(n), 600) * adsr(n, 0.01, 0.4, 0.2, 0.4)
bl = np.zeros(n)
for i in range(14):
    st = rng.integers(int(SR*0.1), int(SR*0.7)); d = 0.05
    b = sweep(rng.uniform(500, 1200), rng.uniform(1300, 2400), d) * env(int(SR*d), 0.002, 0.04)
    bl[st:st+len(b)] += b * 0.25
save("splash", s * 0.8 + bl, 0.75)
n = int(SR*1.4); s2 = lowpass(noise(n), 3000) * adsr(n, 0.003, 0.35, 0.4, 0.8) + 0.8 * lowpass(noise(n), 400) * adsr(n, 0.01, 0.6, 0.3, 0.6)
bl2 = np.zeros(n)
for i in range(28):
    st = rng.integers(int(SR*0.15), int(SR*1.1)); d = 0.06
    b = sweep(rng.uniform(400, 1000), rng.uniform(1200, 2600), d) * env(int(SR*d), 0.002, 0.05)
    bl2[st:st+len(b)] += b * 0.3
chime = np.zeros(n); c = tone(1320, 0.5, "sine") * env(int(SR*0.5), 0.002, 0.45) + 0.6 * tone(1980, 0.5) * env(int(SR*0.5), 0.002, 0.3)
chime[int(SR*0.12):int(SR*0.12)+len(c)] += c * 0.5
save("splash_big", s2 + bl2 + chime, 0.85)

# --- night watch whistle (trilled pea whistle)
d = 0.7; t = t_(d); f = 2900 + 260 * np.sign(np.sin(2*np.pi*28*t)); ph = 2*np.pi*np.cumsum(f)/SR
w = np.sin(ph) * (0.8 + 0.2*noise(len(t))) * adsr(len(t), 0.01, 0.1, 0.8, 0.12)
save("whistle", lowpass(w, 6000), 0.6)
save("whoosh", highpass(lowpass(noise(int(SR*0.28)), 3000), 300) * adsr(int(SR*0.28), 0.08, 0.1, 0.4, 0.1), 0.5)

# --- cheer / crowd
n = int(SR*1.6); ch = np.zeros(n)
for i in range(18):
    f0 = rng.uniform(220, 520); d = rng.uniform(0.4, 1.2); st = rng.integers(0, int(SR*0.4))
    v = sweep(f0, f0*rng.uniform(1.2, 1.6), d, "saw") * adsr(int(SR*d), 0.05, 0.2, 0.6, 0.3)
    v = lowpass(v, 1800)
    ch[st:st+len(v)] += v[:n-st]
ch += 0.3 * lowpass(noise(n), 2000) * adsr(n, 0.05, 0.5, 0.3, 0.6)
save("cheer", ch, 0.7)

# --- comedy
save("boing", sweep(180, 520, 0.35) * (1 + 0.5*np.sin(2*np.pi*22*t_(0.35))) * env(int(SR*0.35), 0.003, 0.3), 0.6)
save("hop", sweep(250, 600, 0.12, "tri") * env(int(SR*0.12), 0.002, 0.1), 0.5)
save("jump", sweep(300, 700, 0.14, "tri") * env(int(SR*0.14), 0.002, 0.12), 0.35)
save("land", lowpass(noise(int(SR*0.1)), 500) * env(int(SR*0.1), 0.001, 0.09), 0.5)
save("dive", highpass(lowpass(noise(int(SR*0.35)), 2500), 200) * adsr(int(SR*0.35), 0.02, 0.1, 0.5, 0.2) + 0.3*sweep(500, 220, 0.35, "tri") * env(int(SR*0.35), 0.01, 0.2), 0.5)
save("step", lowpass(noise(int(SR*0.07)), 900) * env(int(SR*0.07), 0.001, 0.06), 0.45)
save("pickup", np.concatenate([tone(988, 0.07, "tri"), tone(1318, 0.07, "tri"), tone(1760, 0.16, "tri")]) * 0.8, 0.55)
sq = sweep(900, 1700, 0.18, "square") * env(int(SR*0.18), 0.003, 0.08); save("squeak", lowpass(np.concatenate([sq, sq[::-1]]), 5000), 0.5)
save("turbo", sweep(200, 1400, 0.45, "saw") * adsr(int(SR*0.45), 0.02, 0.2, 0.6, 0.15), 0.4)
save("toss", highpass(lowpass(noise(int(SR*0.2)), 2000), 400) * adsr(int(SR*0.2), 0.05, 0.05, 0.6, 0.1), 0.4)

# --- carts: start chirp + loopable electric hum
save("cart_start", np.concatenate([sweep(200, 520, 0.25, "saw"), tone(520, 0.15, "saw")]) * env(int(SR*0.4), 0.01, 0.15), 0.35)
d = 1.0; t = t_(d); base = 110
hum = 0.6*np.sin(2*np.pi*base*t) + 0.3*np.sin(2*np.pi*base*2*t) + 0.15*np.sign(np.sin(2*np.pi*base*3*t)) + 0.08*lowpass(noise(len(t)), 800)
save("cart_loop", lowpass(hum, 1600), 0.5)

# --- music: original loops (pizzicato sneak + soft pad), 100 bpm, 8 bars
def music_loop(bpm, prog, melody, bars=8, sneaky=True):
    beat = 60.0 / bpm; total = bars * 4 * beat; n = int(SR * total); out = np.zeros(n)
    notes = {"C":0,"C#":1,"D":2,"D#":3,"E":4,"F":5,"F#":6,"G":7,"G#":8,"A":9,"A#":10,"B":11}
    def hz(name, octave): return 440.0 * 2 ** ((notes[name] + 12*(octave-4) - 9) / 12)
    def pluck(f, d):
        tt = t_(d); x = (np.sin(2*np.pi*f*tt) + 0.4*np.sin(2*np.pi*2*f*tt) + 0.2*np.sin(2*np.pi*3*f*tt))
        return x * np.exp(-tt * 9.0)
    for bar in range(bars):
        root, quality = prog[bar % len(prog)]
        r = hz(root, 2)
        for b in range(4):
            st = int(SR * (bar*4 + b) * beat)
            f = r if b % 2 == 0 else r * (1.5 if b == 1 else 2 ** (7/12))
            p = pluck(f, beat * 0.9) * 0.55
            out[st:st+len(p)] += p[:n-st]
        # pad
        third = 3 if quality == "m" else 4
        chord = [hz(root, 4), hz(root, 4) * 2 ** (third/12), hz(root, 4) * 2 ** (7/12)]
        d = 4 * beat; tt = t_(d); pad = sum(np.sin(2*np.pi*cf*tt + 0.3*np.sin(2*np.pi*0.5*tt)) for cf in chord)
        pad *= adsr(len(tt), 0.4, 0.5, 0.7, 0.6) * 0.12
        st = int(SR * bar * 4 * beat); out[st:st+len(pad)] += pad[:n-st]
        # brushed hat
        for e8 in range(8):
            st = int(SR * (bar*4*beat + e8 * beat / 2)); hh = highpass(noise(int(SR*0.04)), 5000) * env(int(SR*0.04), 0.001, 0.035) * (0.10 if e8 % 2 else 0.05)
            out[st:st+len(hh)] += hh[:n-st]
    # melody (celesta-ish)
    step = beat / 2
    for i, m in enumerate(melody):
        if m is None: continue
        name, octv = m
        st = int(SR * i * step); f = hz(name, octv)
        tt = t_(step * 1.8); x = (np.sin(2*np.pi*f*tt) + 0.3*np.sin(2*np.pi*4*f*tt)) * np.exp(-tt*5.5) * 0.25
        if st < n: out[st:st+len(x)] += x[:n-st]
    # wrap tail into the start for a seamless loop
    return out
prog = [("A","m"),("F","M"),("D","m"),("E","M")]
mel = [("E",5),None,("C",5),None,("A",4),None,("B",4),("C",5), ("D",5),None,("C",5),None,("A",4),None,None,None,
       ("F",5),None,("E",5),None,("D",5),None,("C",5),("D",5), ("E",5),None,("G#",4),None,("B",4),None,None,None]
mel = mel * 2
save("music_chase_calm", music_loop(100, prog, mel), 0.55)  # converted to .ogg by tools/gen_audio.sh
prog2 = [("C","M"),("G","M"),("A","m"),("F","M")]
mel2 = [("C",5),("E",5),("G",5),("C",6),None,("G",5),("E",5),None]*4
save("music_results", music_loop(120, prog2, mel2, bars=4), 0.55)
save("music_menu", music_loop(92, [("F","M"),("A","m"),("D","m"),("C","M")], [("A",4),None,("C",5),None,("F",5),None,("E",5),("D",5)]*8), 0.5)
print("audio written to", os.path.abspath(OUT))
