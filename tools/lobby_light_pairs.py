#!/usr/bin/env python3
"""Before/after evidence pictures for the final lobby pass.

  tools/lobby_light_pairs.py BEFORE_DIR AFTER_DIR OUT_DIR PREFIX "label" [shot ...]

For each shot: OUT_DIR/PREFIX_<shot>.jpg, the before frame above the after
frame (same camera), each tagged BEFORE / AFTER, scaled to 1280 px wide, JPEG
q85, with the label as a caption.  With --faces, also a side-by-side crop of
the party's faces (from <shot>.json's projected head points).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def tag(im, text, font):
    d = ImageDraw.Draw(im)
    w = d.textlength(text, font=font)
    d.rectangle([0, 0, w + 16, font.size + 10], fill=(0, 0, 0))
    d.text((8, 4), text, font=font, fill=(255, 255, 255))


def caption(im, text, font):
    w, h = im.size
    out = Image.new("RGB", (w, h + 26), (12, 19, 36))
    out.paste(im, (0, 0))
    ImageDraw.Draw(out).text((8, h + 5), text, font=font, fill=(240, 240, 240))
    return out


def pair(bp, ap, label, width=1280):
    b, a = Image.open(bp).convert("RGB"), Image.open(ap).convert("RGB")
    s = width / b.width
    b = b.resize((width, round(b.height * s)), Image.LANCZOS)
    a = a.resize((width, round(a.height * s)), Image.LANCZOS)
    ft = ImageFont.truetype(FONT_B, 20)
    tag(b, "BEFORE", ft)
    tag(a, "AFTER", ft)
    out = Image.new("RGB", (width, b.height + a.height + 4), (255, 255, 255))
    out.paste(b, (0, 0))
    out.paste(a, (0, b.height + 4))
    return caption(out, label, ImageFont.truetype(FONT, 14))


def faces(bd, ad, shot, label, width=1280):
    rep = json.load(open(os.path.join(bd, shot + ".json")))
    s = float(rep.get("px_per_unit", 1.0))
    pts = [(c["head_bone"]["x"] * s, c["head_bone"]["y"] * s, c["head_bone"]["r"] * s) for c in rep["chars"] if c.get("head_bone")]
    if not pts:
        return None
    x0 = max(0, min(p[0] - p[2] * 4.5 for p in pts))
    x1 = max(p[0] + p[2] * 4.5 for p in pts)
    y0 = max(0, min(p[1] - p[2] * 6.0 for p in pts))
    y1 = max(p[1] + p[2] * 4.0 for p in pts)
    box = tuple(int(v) for v in (x0, y0, x1, y1))
    b = Image.open(os.path.join(bd, shot + ".png")).convert("RGB").crop(box)
    a = Image.open(os.path.join(ad, shot + ".png")).convert("RGB").crop(box)
    half = (width - 4) // 2
    sc = half / b.width
    b = b.resize((half, round(b.height * sc)), Image.LANCZOS)
    a = a.resize((half, round(a.height * sc)), Image.LANCZOS)
    ft = ImageFont.truetype(FONT_B, 18)
    tag(b, "BEFORE", ft)
    tag(a, "AFTER", ft)
    out = Image.new("RGB", (half * 2 + 4, b.height), (255, 255, 255))
    out.paste(b, (0, 0))
    out.paste(a, (half + 4, 0))
    return caption(out, label, ImageFont.truetype(FONT, 14))


def main():
    args = sys.argv[1:]
    want_faces = "--faces" in args
    args = [a for a in args if a != "--faces"]
    bd, ad, od, prefix, label = args[:5]
    shots = args[5:]
    os.makedirs(od, exist_ok=True)
    for shot in shots:
        p = os.path.join(od, "%s_%s.jpg" % (prefix, shot))
        pair(os.path.join(bd, shot + ".png"), os.path.join(ad, shot + ".png"), label + " - " + shot).save(p, quality=85)
        print(p)
        if want_faces:
            f = faces(bd, ad, shot, label + " - " + shot + ", faces (crop)")
            if f is not None:
                fp = os.path.join(od, "%s_%s_faces.jpg" % (prefix, shot))
                f.save(fp, quality=85)
                print(fp)


if __name__ == "__main__":
    main()
