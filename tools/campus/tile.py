"""Tracing tiles: an aerial crop with a labelled local-metre grid.

Grid spacing adapts to the zoom (5 m minor / 10 m major at the default 7 px/m).

    python3 tools/campus/tile.py X Z [SIZE_M] [OUT.png] [--px-per-m 7] [--overview]

X Z is the tile centre in the campus frame (geo.py); SIZE_M the side (default
120).  Thin lines every 5 m, stronger every 10 m, labels every 10 m (or 20 m on
big tiles), so a vertex can be read to about +-0.5 m.  Optional --data draws
the current layer data on top (overlay.py's styles) for checking.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import geo  # noqa: E402


def font(sz):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def make_tile(cx, cz, size, ppm=7.0, overview=False, draw_data=None, grid=True):
    r = geo.Raster("aerial_overview" if overview else "aerial_campus")
    img = r.image()
    x0, z0 = cx - size / 2, cz - size / 2
    p0, q0 = r.px(x0, z0)
    p1, q1 = r.px(x0 + size, z0 + size)
    out_px = int(round(size * ppm))
    crop = img.transform((out_px, out_px), Image.EXTENT, (p0, q0, p1, q1), Image.BICUBIC)
    d = ImageDraw.Draw(crop, "RGBA")

    def to_px(x, z):
        return ((x - x0) * ppm, (z - z0) * ppm)

    if draw_data is not None:
        draw_data(d, to_px, ppm)
    if grid:
        # spacing adapts to zoom: a line every >= 6 px, a label every >= 60 px
        steps = [1, 2, 5, 10, 20, 50, 100, 200, 500]
        minor = next(s for s in steps if s * ppm >= 6)
        major = next(s for s in steps if s >= minor * 2 and s * ppm >= 30)
        lab = next(s for s in steps if s >= major and s * ppm >= 60)
        f = font(max(11, min(16, int(lab * ppm / 5))))
        import math
        for i in range(int(math.floor(x0 / minor)) * minor, int(x0 + size) + 1, minor):
            px, _ = to_px(i, 0)
            strong = i % major == 0
            d.line([(px, 0), (px, out_px)], fill=(255, 255, 0, 150 if strong else 60), width=1)
            if i % lab == 0:
                d.text((px + 2, 2), str(i), fill=(255, 255, 0, 255), font=f, stroke_width=2, stroke_fill=(0, 0, 0))
        for j in range(int(math.floor(z0 / minor)) * minor, int(z0 + size) + 1, minor):
            _, pz = to_px(0, j)
            strong = j % major == 0
            d.line([(0, pz), (out_px, pz)], fill=(0, 255, 255, 150 if strong else 60), width=1)
            if j % lab == 0:
                d.text((2, pz + 2), str(j), fill=(0, 255, 255, 255), font=f, stroke_width=2, stroke_fill=(0, 0, 0))
        d.text((out_px - 260, out_px - 22), "x east (yellow) / z south (cyan), m",
               fill=(255, 255, 255, 255), font=font(13), stroke_width=2, stroke_fill=(0, 0, 0))
    return crop


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("x", type=float)
    ap.add_argument("z", type=float)
    ap.add_argument("size", type=float, nargs="?", default=120.0)
    ap.add_argument("out", nargs="?", default=None)
    ap.add_argument("--px-per-m", type=float, default=7.0)
    ap.add_argument("--overview", action="store_true")
    ap.add_argument("--data", action="store_true", help="draw game/data/campus layers on top")
    ap.add_argument("--src", default="", help="draw one traced zone file on top")
    a = ap.parse_args()
    dd = None
    if a.data or a.src:
        import overlay
        dd = overlay.drawer(overlay.load_layers(None, a.src or None))
    t = make_tile(a.x, a.z, a.size, a.px_per_m, a.overview, dd)
    out = a.out or f"/home/user/campus_ref/work/tiles/t_{int(a.x)}_{int(a.z)}_{int(a.size)}.png"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    t.save(out)
    print(out)
