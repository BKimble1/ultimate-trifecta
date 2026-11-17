#!/usr/bin/env python3
"""The link preview image (1200x630): a gameplay frame with the logo.

    python3 tools/website/make_share.py FRAME.jpg website/assets/img/share.jpg
"""
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 1200, 630
frame = Image.open(sys.argv[1]).convert("RGB")
s = max(W / frame.width, H / frame.height)
frame = frame.resize((round(frame.width * s), round(frame.height * s)), Image.LANCZOS)
x = (frame.width - W) // 2
y = (frame.height - H) // 2
bg = frame.crop((x, y, x + W, y + H))

# a soft shade at the bottom so the logo reads on any frame
shade = Image.new("L", (W, H), 0)
d = ImageDraw.Draw(shade)
for i in range(H):
    a = max(0.0, (i - H * 0.35) / (H * 0.65))
    d.line([(0, i), (W, i)], fill=int(210 * a ** 1.4))
navy = Image.new("RGB", (W, H), (12, 19, 36))
bg = Image.composite(navy, bg, shade)

logo = Image.open("art_src/branding/ultimate-trifecta-lobby-title.png").convert("RGBA")
logo = logo.crop(logo.getbbox())
lw = 640
logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
pos = ((W - lw) // 2, H - logo.height - 54)
sh = Image.new("RGBA", logo.size, (0, 0, 0, 0))
sh.putalpha(logo.split()[3].point(lambda v: int(v * 0.55)))
glow.alpha_composite(sh, (pos[0], pos[1] + 14))
glow = glow.filter(ImageFilter.GaussianBlur(18))
out = bg.convert("RGBA")
out.alpha_composite(glow)
out.alpha_composite(logo, pos)
out.convert("RGB").save(sys.argv[2], quality=88, optimize=True, progressive=True)
print("wrote", sys.argv[2])
