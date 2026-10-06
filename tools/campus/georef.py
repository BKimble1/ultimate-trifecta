"""Georeference a planning figure or diagram to the campus frame.

    python3 tools/campus/georef.py grid FIG.jpg OUT.png [--x0 --y0 --w --h --scale]
        a crop of the figure with a labelled PIXEL grid (to read control points)
    python3 tools/campus/georef.py fit POINTS.json
        least-squares affine fit figure-px -> campus metres; prints residuals
    python3 tools/campus/georef.py warp POINTS.json OUT.png [--x0 --z0 --size --ppm --alpha]
        the figure resampled into the campus frame and blended over the aerial

POINTS.json: {"figure": path, "points": [{"id": .., "px": [u, v], "xz": [x, z]}]}
A diagram is not a survey: the fit's residuals are the honest measure of how
far its positions can be trusted.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import geo  # noqa: E402
import tile  # noqa: E402


def fit(points):
    A, B = [], []
    for p in points:
        u, v = p["px"]
        x, z = p["xz"]
        A.append([u, v, 1, 0, 0, 0]); B.append(x)
        A.append([0, 0, 0, u, v, 1]); B.append(z)
    A = np.array(A, float); B = np.array(B, float)
    m, *_ = np.linalg.lstsq(A, B, rcond=None)
    M = np.array([[m[0], m[1], m[2]], [m[3], m[4], m[5]]])
    res = []
    for p in points:
        u, v = p["px"]
        x, z = M @ np.array([u, v, 1.0])
        res.append((p["id"], float(x - p["xz"][0]), float(z - p["xz"][1])))
    return M, res


def cmd_grid(a):
    im = Image.open(a.fig).convert("RGB")
    x0, y0 = a.x0, a.y0
    w = a.w or im.width - x0
    h = a.h or im.height - y0
    crop = im.crop((x0, y0, x0 + w, y0 + h)).resize((int(w * a.scale), int(h * a.scale)), Image.BICUBIC)
    d = ImageDraw.Draw(crop, "RGBA")
    step = 20 if a.scale >= 2 else 50
    f = tile.font(12)
    for u in range((x0 // step) * step, x0 + w, step):
        X = (u - x0) * a.scale
        d.line([(X, 0), (X, crop.height)], fill=(255, 0, 255, 140 if u % (step * 5) == 0 else 50))
        if u % (step * 5) == 0:
            d.text((X + 2, 2), str(u), fill=(255, 0, 255), font=f, stroke_width=2, stroke_fill=(255, 255, 255))
    for v in range((y0 // step) * step, y0 + h, step):
        Y = (v - y0) * a.scale
        d.line([(0, Y), (crop.width, Y)], fill=(0, 120, 255, 140 if v % (step * 5) == 0 else 50))
        if v % (step * 5) == 0:
            d.text((2, Y + 2), str(v), fill=(0, 120, 255), font=f, stroke_width=2, stroke_fill=(255, 255, 255))
    crop.save(a.out)
    print(a.out)


def cmd_fit(a):
    P = json.load(open(a.points))
    M, res = fit(P["points"])
    s = np.sqrt(abs(np.linalg.det(M[:, :2])))
    print("metres per figure px ~ %.3f" % s)
    rms = np.sqrt(np.mean([dx * dx + dz * dz for _, dx, dz in res]))
    for i, dx, dz in res:
        print("  %-24s residual %6.1f m (%5.1f, %5.1f)" % (i, (dx * dx + dz * dz) ** 0.5, dx, dz))
    print("RMS %.1f m over %d points" % (rms, len(res)))
    return M


def cmd_warp(a):
    P = json.load(open(a.points))
    M, _ = fit(P["points"])
    fig = Image.open(P["figure"]).convert("RGB")
    # inverse: campus (x,z) -> figure px
    Mi = np.linalg.inv(np.vstack([M, [0, 0, 1]]))
    n = int(a.size * a.ppm)
    base = tile.make_tile(a.x0 + a.size / 2, a.z0 + a.size / 2, a.size, a.ppm, grid=False)
    # PIL affine maps output px -> input px: out (i,j) -> campus (x0+i/ppm, z0+j/ppm) -> fig
    T = Mi @ np.array([[1 / a.ppm, 0, a.x0], [0, 1 / a.ppm, a.z0], [0, 0, 1]])
    warped = fig.transform((n, n), Image.AFFINE, tuple(T[:2].reshape(-1)), Image.BICUBIC)
    out = Image.blend(base, warped, a.alpha)
    tile_draw = tile.make_tile  # grid on top for reading
    g = tile.make_tile(a.x0 + a.size / 2, a.z0 + a.size / 2, a.size, a.ppm)
    out = Image.blend(out, g, 0.25)
    out.save(a.out)
    print(a.out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd")
    g = sp.add_parser("grid"); g.add_argument("fig"); g.add_argument("out")
    g.add_argument("--x0", type=int, default=0); g.add_argument("--y0", type=int, default=0)
    g.add_argument("--w", type=int, default=0); g.add_argument("--h", type=int, default=0)
    g.add_argument("--scale", type=float, default=1.0)
    f = sp.add_parser("fit"); f.add_argument("points")
    w = sp.add_parser("warp"); w.add_argument("points"); w.add_argument("out")
    w.add_argument("--x0", type=float, default=-780); w.add_argument("--z0", type=float, default=-490)
    w.add_argument("--size", type=float, default=1240); w.add_argument("--ppm", type=float, default=1.0)
    w.add_argument("--alpha", type=float, default=0.5)
    a = ap.parse_args()
    {"grid": cmd_grid, "fit": cmd_fit, "warp": cmd_warp}[a.cmd](a)
