#!/usr/bin/env python3
"""The trailer's end card (1600x900 PNG): the logo on the game's navy.

    python3 tools/website/make_endcard.py OUT.png
"""
import io
import sys

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import os
K = float(os.environ.get("TITLE_SCALE", "1.2"))
W, H = round(1600 * K), round(900 * K)
NAVY = (12, 19, 36)
NIGHT = (7, 11, 22)


def font(path, size, axes):
    tt = TTFont(path)
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


bg = Image.new("RGB", (W, H), NIGHT)
glow = Image.new("RGB", (W, H), NIGHT)
d = ImageDraw.Draw(glow)
d.ellipse([W * 0.18, H * 0.05, W * 0.82, H * 0.95], fill=NAVY)
glow = glow.filter(ImageFilter.GaussianBlur(160))
bg = glow

logo = Image.open("art_src/branding/ultimate-trifecta-lobby-title.png").convert("RGBA")
logo = logo.crop(logo.getbbox())
lw = round(860 * K)
logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
x = (W - lw) // 2
y = round(250 * K)
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sh = Image.new("RGBA", logo.size, (0, 0, 0, 0))
sh.putalpha(logo.split()[3].point(lambda v: int(v * 0.6)))
shadow.alpha_composite(sh, (x, y + round(22 * K)))
shadow = shadow.filter(ImageFilter.GaussianBlur(26))
out = bg.convert("RGBA")
out.alpha_composite(shadow)
out.alpha_composite(logo, (x, y))

d = ImageDraw.Draw(out)
f1 = font("website/assets/fonts/archivo-latin-wdth-italic.woff2", round(44 * K), {"wdth": 125, "wght": 900})
f2 = font("website/assets/fonts/manrope-latin-wght-normal.woff2", round(26 * K), {"wght": 600})
t1 = "SPLASH THREE. RACE HOME."
w1 = d.textlength(t1, font=f1)
tl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(tl).text(((W - w1) / 2, y + logo.height + round(54 * K)), t1, font=f1, fill=(255, 194, 61, 255))
yc = y + logo.height + round(54 * K) + 22
tl = tl.transform((W, H), Image.AFFINE, (1, 0.2, -0.2 * yc, 0, 1, 0), resample=Image.BICUBIC)
out.alpha_composite(tl)
t2 = "On iPhone and iPad  ·  ultimatetrifecta.idlery.com"
w2 = d.textlength(t2, font=f2)
d.text(((W - w2) / 2, y + logo.height + round(128 * K)), t2, font=f2, fill=(246, 243, 236, 200))
out.convert("RGB").save(sys.argv[1])
print("wrote", sys.argv[1])
