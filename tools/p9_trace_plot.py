#!/usr/bin/env python3
"""Pass 9 movement trace charts (PIL only) from the movement probe JSON
(tests/test_p9_movement.gd with P9_MOVE_TRACE=1 P9_MOVE_OUT=...) and the
online 60 s trace (P9_NET_TRACE=...).

Usage: tools/p9_trace_plot.py P8_TRACE.json P9_TRACE.json NET60_P9.json OUT_DIR
Writes full_input_60s.png, dive_chain.png and online_60s.png.  Desktop
headless simulation traces (60 Hz), not device measurements.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1400, 660
L, R, T, B = 90, 30, 128, 90
BG = (250, 248, 242)
INK = (32, 36, 48)
GRID = (214, 210, 200)
COLORS = {"p8": (150, 150, 158), "p8b": (226, 128, 40), "p9": (22, 150, 140), "guest": (90, 110, 220), "corr": (205, 60, 80)}


def font(sz):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"]:
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def chart(title, sub, t_max, y_max, series, refs, path, y_label="horizontal speed (m/s)"):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    f, fs, ft = font(18), font(15), font(24)
    d.text((L, 16), title, fill=INK, font=ft)
    words, lines, cur = sub.split(" "), [], ""
    for w in words:
        if d.textlength(cur + " " + w, font=fs) > W - L - R and cur:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    lines.append(cur)
    for i, ln in enumerate(lines[:3]):
        d.text((L, 50 + i * 20), ln, fill=(90, 92, 100), font=fs)
    pw, ph = W - L - R, H - T - B

    def xy(t, v):
        return (L + pw * t / t_max, T + ph * (1 - v / y_max))
    for k in range(0, int(y_max) + 1):
        y = xy(0, k)[1]
        d.line([(L, y), (L + pw, y)], fill=GRID, width=1)
        d.text((L - 30, y - 9), str(k), fill=INK, font=fs)
    step = 5 if t_max <= 30 else 10
    for s in range(0, int(t_max) + 1, step):
        x = xy(s, 0)[0]
        d.line([(x, T), (x, T + ph)], fill=GRID, width=1)
        d.text((x - 8, T + ph + 6), f"{s}", fill=INK, font=fs)
    d.text((L + pw / 2 - 40, T + ph + 28), "time (s)", fill=INK, font=fs)
    d.text((L, T - 22), y_label, fill=INK, font=fs)
    for v, lab, col in refs:
        y = xy(0, v)[1]
        for x0 in range(L, L + pw, 14):
            d.line([(x0, y), (min(x0 + 7, L + pw), y)], fill=col, width=2)
        d.text((L + pw - 230, y - 20), lab, fill=col, font=fs)
    ly = H - 30
    lx = L
    for label, col, pts, width in series:
        line = [xy(t, v) for t, v in pts if t <= t_max]
        if len(line) > 1:
            d.line(line, fill=col, width=width)
        d.rectangle([lx, ly + 4, lx + 18, ly + 14], fill=col)
        d.text((lx + 24, ly), label, fill=INK, font=fs)
        lx += 34 + d.textlength(label, font=fs) + 30
    im.save(path)


def trace(rows, label):
    for r in rows:
        if r["label"] == label:
            return [(e["t"], e["speed"]) for e in r["trace"]]
    raise KeyError(label)


def main():
    p8 = json.load(open(sys.argv[1]))
    p9 = json.load(open(sys.argv[2]))
    net = json.load(open(sys.argv[3]))
    out = sys.argv[4]
    refs = [(6.6, "Night Watch full speed 6.6", (120, 60, 160)), (6.0, "runner full speed (1.9) 6.0", COLORS["p9"])]
    chart("Full stick input held for 60 s: 1.8 vs 1.9",
          "Simulated (headless 60 Hz, real motor and physics, open straight). 1.8: Sprint held (one 2.5 s burst, then 5.0) and the Pass 8 best: release / re-press at 50 %. 1.9: one steady speed.",
          60, 8.5,
          [("1.8 Sprint held", COLORS["p8"], trace(p8, "full input + Sprint held 60 s"), 3),
           ("1.8 Sprint release / re-press", COLORS["p8b"], trace(p8, "Sprint release / re-press at 50 %"), 2),
           ("1.9 full input (+ old Sprint held)", COLORS["p9"], trace(p9, "full input + Sprint held 60 s"), 3)],
          refs, f"{out}/full_input_60s.png")
    chart("Best jump / dive chain, 10 s: 1.8 vs 1.9",
          "Simulated. One dive per jump and the 0.45 s landing recovery (Pass 8) kept: average 5.23 (1.8) and 5.38 m/s (1.9), both below a plain 1.9 run and the Night Watch.",
          10, 8.5,
          [("1.8 jump/dive chain", COLORS["p8"], trace(p8, "best jump/dive chain"), 2),
           ("1.9 jump/dive chain", COLORS["p9"], trace(p9, "best jump/dive chain"), 2)],
          refs + [(8.0, "dive burst 8.0", (60, 60, 60))], f"{out}/dive_chain.png")
    host = [(e["t"], e["host"]) for e in net]
    guest = [(e["t"], e["guest"]) for e in net]
    corr = [(e["t"], e["corr"] * 100.0 / 5.0) for e in net]   # cm, scaled: 5 cm per unit
    chart("Online, 60 s of full input: host and guest prediction (1.9)",
          "Simulated loopback: 50 ms +-8 ms latency, 2 % loss, guest runner circling open lawn. Red: reconciliation correction per snapshot (1 grid unit = 5 cm).",
          62, 8.5,
          [("host (authoritative)", COLORS["p9"], host, 3), ("guest prediction", COLORS["guest"], guest, 1),
           ("correction (x 5 cm)", COLORS["corr"], corr, 1)],
          refs, f"{out}/online_60s.png")


if __name__ == "__main__":
    main()
