"""Runtime branding textures and the native launch image (V5; Pass 8).

Masters live in art_src/branding/ (owner-supplied, unchanged):
  ultimate-trifecta-lobby-title.png  2172x724, transparent: the game title
  idlery-games.svg                   1600x920: the Idlery Games lockup (vector)
  idlery-games.png                   2400x1380: the same lockup rasterised at
                                     1.5x (alpha within 0.0001 mean of the
                                     vector; kept as the owner's reference)

    python3 tools/branding/make_branding.py      (needs pillow and numpy)

Writes (only files whose pixels or bytes change):
  game/assets/branding/title_ultimate_trifecta.png  1440 wide from the title
      master (premultiplied Lanczos, as V5: the title has no vector source)
  game/assets/branding/idlery_games.svg   the lockup's vector source, as
      shipped: BootCurtain rasterises it at runtime at the exact on-screen
      pixel size and sub-pixel position (Brand.studio_image)
  game/assets/branding/idlery_games.png   1280x736 exact-coverage raster of
      the vector (straight RGBA, fill colour bled into transparent pixels):
      the fallback if the runtime vector rasteriser is unavailable.  Both
      sides divide by 32, so its first five mip levels are exact 2x2
      reductions (V5's 1400x805 halved 805 rows to 402, so its mips sat
      up to half a texel lower than the base level)
  game/assets/icon/launch.png   LAUNCH x LAUNCH opaque: the lockup centred on
      the startup black, rasterised from the vector at that size (exact area
      coverage, composited in the encoded values like the GPU).  The iOS
      launch storyboard (@2x and @3x) and Godot's boot splash both show it
      "scale to fit" (the square fitted to the landscape screen's height);
      BootCurtain draws the same lockup at the same place (Brand.LOCKUP_W),
      so native launch -> boot splash -> curtain match in size and position.

Pass 8: the lockup is rasterised from the vector, never resampled from the
1.5x raster with a ringing (Lanczos) filter: V5's resize left a light halo
outside the contour (alpha up to 0.10 where the shape is empty) and a dark
dip inside it (alpha down to 0.87), visible at 1:1.  LAUNCH is 1656 (was
2048): both the native launch screen and Godot's boot splash minify the
square with a single bilinear tap (Godot: linear sampler, max_lod 0; Core
Animation's default kCAFilterLinear), so the ratio square/screen height
decides the edges.  1656 keeps it between 1.25 and 2.21 on every iPhone
(2048 reached 2.73 on the iPhone SE and 2.47 on the iPhone XR/11, where a
2-tap filter skips source texels: stair steps), is exact 2:1 on 828-px-high
2x iPhones, ~1:1 on 11-inch iPads and is never upscaled on a phone.
See docs/pass8/logo.md for the measurements.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svg_raster  # noqa: E402

ROOT = os.path.join(HERE, '..', '..')
SRC = os.path.join(ROOT, 'art_src', 'branding')
OUT = os.path.join(ROOT, 'game', 'assets', 'branding')
ICON = os.path.join(ROOT, 'game', 'assets', 'icon')
SVG = os.path.join(SRC, 'idlery-games.svg')
BLACK = (0, 0, 0)            # #000000 (V6), project boot_splash/bg_color
LOCKUP_W = 0.62              # lockup canvas width / launch square side (Brand.LOCKUP_W)
LAUNCH = 1656                # launch square side, px (see above)
STUDIO_W = 1280              # fallback runtime texture width, px (x 0.8)


def scaled(im, width):
    """Premultiplied Lanczos (V5), for the title master only."""
    h = round(im.height * width / im.width)
    return im.convert('RGBa').resize((width, h), Image.LANCZOS).convert('RGBA')


def lockup_box(side):
    """(x, y, w, h) of the lockup canvas in a side x side square, px."""
    w = side * LOCKUP_W
    vw, vh, _ = svg_raster.load(SVG)
    h = w * vh / vw
    return (side - w) / 2.0, (side - h) / 2.0, w, h


def launch_image(side=LAUNCH):
    """Opaque RGB: the lockup on black, exact coverage from the vector."""
    vw, _, _ = svg_raster.load(SVG)
    x, y, w, _ = lockup_box(side)
    prem, alpha, _ = svg_raster.render(SVG, w / vw, size=(side, side), offset=(x, y))
    over = prem + np.array(BLACK, dtype=np.float64) * (1.0 - alpha[..., None])
    rgb = np.clip(np.rint(over), 0, 255).astype(np.uint8)
    return Image.fromarray(rgb, 'RGB')


def studio_image(width=STUDIO_W):
    """Straight RGBA lockup (canvas incl. its transparent padding)."""
    vw, vh, _ = svg_raster.load(SVG)
    k = width / vw
    prem, alpha, _ = svg_raster.render(SVG, k, size=(width, int(round(vh * k))))
    return Image.fromarray(svg_raster.to_straight_rgba(prem, alpha), 'RGBA')


def _write_png(im, path):
    """Save unless the file already holds exactly these pixels."""
    if os.path.exists(path):
        old = Image.open(path)
        if old.mode == im.mode and old.size == im.size and np.array_equal(np.asarray(old), np.asarray(im)):
            return False
    im.save(path, optimize=True)
    return True


def _write_bytes(data, path):
    if os.path.exists(path) and open(path, 'rb').read() == data:
        return False
    with open(path, 'wb') as f:
        f.write(data)
    return True


def main():
    os.makedirs(OUT, exist_ok=True)
    title = Image.open(os.path.join(SRC, 'ultimate-trifecta-lobby-title.png')).convert('RGBA')
    jobs = [
        ('title_ultimate_trifecta.png', _write_png(scaled(title, 1440), os.path.join(OUT, 'title_ultimate_trifecta.png'))),
        ('idlery_games.svg', _write_bytes(open(SVG, 'rb').read(), os.path.join(OUT, 'idlery_games.svg'))),
        ('idlery_games.png', _write_png(studio_image(), os.path.join(OUT, 'idlery_games.png'))),
        ('launch.png', _write_png(launch_image(), os.path.join(ICON, 'launch.png'))),
    ]
    for name, changed in jobs:
        path = os.path.join(ICON if name == 'launch.png' else OUT, name)
        size = Image.open(path).size if name.endswith('.png') else '(vector)'
        print('%-28s %-12s %8d bytes  %s' % (name, size, os.path.getsize(path), 'written' if changed else 'unchanged'))


if __name__ == '__main__':
    main()
