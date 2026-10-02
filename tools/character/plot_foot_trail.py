"""Top-down plot of planted-foot trails (V6 foot-lock evidence).

    tools/gd.sh --headless --fixed-fps 60 --path game res://src/dev/foot_trail.tscn -- --out=trail.json
    python3 tools/character/plot_foot_trail.py trail.json out.png

For the motion rig's 90-degree turn and 180-degree reversal, with and
without CharacterFootLock: the character's path (grey) and, for every frame,
the lower foot while it is on the floor (below MotionRig.PLANT_H): white when
it holds still, orange above 0.3 m/s and red above 1.5 m/s.  A planted foot
that pivots with the body draws a coloured streak; a locked foot a white dot.
Needs Pillow only.
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

PLANT_H = 0.095
PANEL = 520
# the time window round the turn / reversal that each panel shows
WINDOW = {'turn90': (0.6, 1.5), 'reverse': (0.75, 1.65)}


def panel(data, title, window):
    im = Image.new('RGB', (PANEL, PANEL + 70), (27, 36, 64))
    dr = ImageDraw.Draw(im)
    fr = [f for f in data['frames'] if window[0] <= f['t'] <= window[1]]
    xs = [f['root'][0] for f in fr] + [f['l'][0] for f in fr] + [f['r'][0] for f in fr]
    zs = [f['root'][1] for f in fr] + [f['l'][2] for f in fr] + [f['r'][2] for f in fr]
    cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    SCALE = 0.8 * PANEL / max(0.8, max(xs) - min(xs), max(zs) - min(zs))

    def px(x, z):
        return (PANEL / 2 + (x - cx) * SCALE, PANEL / 2 + (z - cz) * SCALE)
    # grid every metre
    for k in range(-6, 7):
        gx, gz = math.floor(cx) + k, math.floor(cz) + k
        dr.line([px(gx, cz - 6), px(gx, cz + 6)], fill=(40, 52, 86))
        dr.line([px(cx - 6, gz), px(cx + 6, gz)], fill=(40, 52, 86))
    dr.line([px(f['root'][0], f['root'][1]) for f in fr], fill=(120, 130, 160), width=2)
    slides = []
    for a, b in zip(fr, fr[1:]):
        if b['mode'] != 'ground' or b['dt'] <= 0:
            continue
        k = 'l' if b['l'][1] <= b['r'][1] else 'r'
        if a[k][1] < PLANT_H and b[k][1] < PLANT_H:
            v = math.hypot(b[k][0] - a[k][0], b[k][2] - a[k][2]) / b['dt']
            slides.append(v)
            col = (245, 245, 240) if v < 0.3 else ((255, 160, 60) if v < 1.5 else (255, 70, 60))
            x, y = px(b[k][0], b[k][2])
            dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=col)
    m = data['metrics']
    try:
        font = ImageFont.truetype('DejaVuSans.ttf', 16)
    except OSError:
        font = ImageFont.load_default()
    dr.text((10, PANEL + 8), title, fill=(240, 240, 240), font=font)
    dr.text((10, PANEL + 34), 'whole run: planted-foot slide mean %.3f m/s, p95 %.2f m/s' % (
        m['slide_mean'], m['slide_p95']), fill=(200, 205, 220), font=font)
    dr.text((10, 8), '%.2f-%.2f s, grid 1 m' % window, fill=(160, 170, 200), font=font)
    return im


def main():
    d = json.load(open(sys.argv[1]))
    order = [('turn90_nolock', '90-degree turn, V5 (no foot lock)'), ('turn90_lock', '90-degree turn, V6 foot lock'),
             ('reverse_nolock', '180-degree reversal, V5 (no foot lock)'), ('reverse_lock', '180-degree reversal, V6 foot lock')]
    ims = [panel(d[k], t, WINDOW[k.split('_')[0]]) for k, t in order]
    out = Image.new('RGB', (PANEL * 2, (PANEL + 70) * 2))
    for i, im in enumerate(ims):
        out.paste(im, ((i % 2) * PANEL, (i // 2) * (PANEL + 70)))
    out.save(sys.argv[2])
    print('saved', sys.argv[2])


if __name__ == '__main__':
    main()
