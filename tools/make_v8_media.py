#!/usr/bin/env python3
"""V8 evidence: side-by-side before/after JPEGs from matched captures.

For every PNG present (same file name) in both BEFORE_DIR and AFTER_DIR,
writes OUT_DIR/<name>.jpg: the before image on the left, the after image on
the right, each labelled. Images are not retouched, only scaled to the same
height. Prints the names written.

Usage: tools/make_v8_media.py BEFORE_DIR AFTER_DIR OUT_DIR [--height=PX] [--before=LABEL] [--after=LABEL]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              os.path.join(os.path.dirname(__file__), "..", "art_src", "branding", "DejaVuSans-Bold.ttf")):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def scaled(path, h):
    im = Image.open(path).convert("RGB")
    w0, h0 = im.size
    if h0 != h:
        im = im.resize((round(w0 * h / h0), h), Image.LANCZOS)
    return im


def label(im, text):
    d = ImageDraw.Draw(im)
    f = font(max(14, im.size[1] // 28))
    x0, y0, x1, y1 = d.textbbox((0, 0), text, font=f)
    pad = 6
    d.rectangle((0, 0, x1 - x0 + pad * 2, y1 - y0 + pad * 2), fill=(0, 0, 0))
    d.text((pad - x0, pad - y0), text, font=f, fill=(255, 255, 255))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if len(args) != 3:
        print(__doc__)
        sys.exit(2)
    before, after, out = args
    h = int(opts.get("height", 540))
    lb = opts.get("before", "build 6 (1.6)")
    la = opts.get("after", "V8 (1.7)")
    os.makedirs(out, exist_ok=True)
    names = sorted(n for n in os.listdir(after) if n.endswith(".png") and os.path.exists(os.path.join(before, n)))
    for n in names:
        a = scaled(os.path.join(before, n), h)
        b = scaled(os.path.join(after, n), h)
        label(a, lb)
        label(b, la)
        gap = 6
        im = Image.new("RGB", (a.size[0] + gap + b.size[0], h), (255, 255, 255))
        im.paste(a, (0, 0))
        im.paste(b, (a.size[0] + gap, 0))
        dst = os.path.join(out, n[:-4] + ".jpg")
        im.save(dst, "JPEG", quality=84, optimize=True)
        print(dst)


if __name__ == "__main__":
    main()
