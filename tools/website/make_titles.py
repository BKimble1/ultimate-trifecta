#!/usr/bin/env python3
"""Trailer title overlays (transparent 1600x900 PNGs) in the site's type.

    python3 tools/website/make_titles.py OUT_DIR
"""
import io
import pathlib
import sys

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import os
K = float(os.environ.get("TITLE_SCALE", "1.2"))   # 1.2: 1920x1080
W, H = round(1600 * K), round(900 * K)
FONTS = pathlib.Path(__file__).resolve().parents[2] / "website/assets/fonts"
IVORY = (246, 243, 236, 255)
AMBER = (255, 194, 61, 255)


def font(name, size, axes):
    tt = TTFont(FONTS / name)
    tt.flavor = None
    buf = io.BytesIO()
    tt.save(buf)
    buf.seek(0)
    f = ImageFont.truetype(buf, size)
    tags = {"weight": "wght", "width": "wdth"}
    vals = []
    for a in f.get_variation_axes():
        n = a["name"].decode() if isinstance(a["name"], bytes) else a["name"]
        vals.append(axes.get(tags.get(n.lower(), n.lower()), a["default"]))
    f.set_variation_by_axes(vals)
    return f


def title(lines, out, size=118, where="center", small=None):
    """lines: [(text, colour)], stacked; small: an optional line under them."""
    size = round(size * K)
    f = font("archivo-latin-wdth-italic.woff2", size, {"wdth": 125, "wght": 900})
    fs = font("manrope-latin-wght-normal.woff2", round(34 * K), {"wght": 700})
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lh = int(size * 0.98)
    block_h = lh * len(lines) + (round(56 * K) if small else 0)
    y0 = (H - block_h) // 2 if where == "center" else H - block_h - round(110 * K)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for i, (text, col) in enumerate(lines):
        w = d.textlength(text, font=f)
        x = (W - w) / 2 if where == "center" else round(110 * K)
        y = y0 + i * lh
        sd.text((x, y + round(8 * K)), text, font=f, fill=(4, 7, 14, 200))
        d.text((x, y), text, font=f, fill=col)
    if small:
        w = d.textlength(small, font=fs)
        x = (W - w) / 2 if where == "center" else round(114 * K)
        sd.text((x, y0 + lh * len(lines) + 18 + 3), small, font=fs, fill=(4, 7, 14, 200))
        d.text((x, y0 + lh * len(lines) + 18), small, font=fs, fill=IVORY)
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(14 * K)))
    shadow.alpha_composite(img)
    # the site's italic: PIL draws this variable font upright, so slant it
    k = 0.2
    yc = y0 + block_h / 2
    shadow = shadow.transform((W, H), Image.AFFINE, (1, k, -k * yc, 0, 1, 0), resample=Image.BICUBIC)
    shadow.save(out)


if __name__ == "__main__":
    o = pathlib.Path(sys.argv[1])
    o.mkdir(parents=True, exist_ok=True)
    title([("3 A.M.", IVORY)], o / "t_3am.png", 150, small="Moonbrook College")
    title([("SPLASH", IVORY), ("THREE.", AMBER)], o / "t_splash.png", 132, "low")
    title([("DON'T GET", IVORY), ("CAUGHT.", AMBER)], o / "t_caught.png", 132, "low")
    title([("RACE", IVORY), ("HOME.", AMBER)], o / "t_home.png", 132, "low")
    title([("UP TO 8", IVORY), ("PLAYERS.", AMBER)], o / "t_players.png", 132, "low")
    title([("SEASON 1", AMBER), ("WINTER BREAK", IVORY)], o / "t_season.png", 112, "low")
    print("wrote titles to", o)
