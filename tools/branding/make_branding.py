"""Runtime branding textures and the native launch image (V5).

Masters (owner-supplied, unchanged) live in art_src/branding/:
  ultimate-trifecta-lobby-title.png  2172x724, transparent: the game title
  idlery-games.png                   2400x1380, transparent: startup lockup
  idlery-games.svg, idlery-wordmark-original.svg: editable vector sources

    python3 tools/branding/make_branding.py      (needs pillow)

Writes:
  game/assets/branding/title_ultimate_trifecta.png  1440 wide, same padding
  game/assets/branding/idlery_games.png             1400 wide, same padding
  game/assets/icon/launch.png   2048x2048 opaque: the Idlery Games lockup
      centred on the startup black.  The iOS launch storyboard and Godot's
      boot splash both show it "scale to fit" (a square fitted to the
      landscape screen's height); BootCurtain draws the same lockup at the
      same place (Brand.LOCKUP_W), so launch -> boot -> first frame match.

Scaling is done in premultiplied alpha (no light fringes from the
transparent pixels), proportional, never cropped: the masters' own
transparent padding is kept as layout padding.
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
SRC = os.path.join(ROOT, 'art_src', 'branding')
OUT = os.path.join(ROOT, 'game', 'assets', 'branding')
ICON = os.path.join(ROOT, 'game', 'assets', 'icon')
BLACK = (0, 0, 0)            # #000000 (V6), project boot_splash/bg_color
LOCKUP_W = 0.62              # lockup canvas width / launch square side (Brand.LOCKUP_W)
LAUNCH = 2048


def scaled(im, width):
    h = round(im.height * width / im.width)
    return im.convert('RGBa').resize((width, h), Image.LANCZOS).convert('RGBA')


def main():
    os.makedirs(OUT, exist_ok=True)
    title = Image.open(os.path.join(SRC, 'ultimate-trifecta-lobby-title.png')).convert('RGBA')
    scaled(title, 1440).save(os.path.join(OUT, 'title_ultimate_trifecta.png'), optimize=True)
    lock = Image.open(os.path.join(SRC, 'idlery-games.png')).convert('RGBA')
    scaled(lock, 1400).save(os.path.join(OUT, 'idlery_games.png'), optimize=True)
    # the launch image: lockup centred on black, opaque
    w = round(LAUNCH * LOCKUP_W)
    lk = scaled(lock, w)
    canvas = Image.new('RGBA', (LAUNCH, LAUNCH), BLACK + (255,))
    canvas.alpha_composite(lk, ((LAUNCH - lk.width) // 2, (LAUNCH - lk.height) // 2))
    canvas.convert('RGB').save(os.path.join(ICON, 'launch.png'), optimize=True)
    for f in ['title_ultimate_trifecta.png', 'idlery_games.png']:
        im = Image.open(os.path.join(OUT, f))
        print(f, im.size, os.path.getsize(os.path.join(OUT, f)))
    print('launch.png', LAUNCH, os.path.getsize(os.path.join(ICON, 'launch.png')))


if __name__ == '__main__':
    main()
