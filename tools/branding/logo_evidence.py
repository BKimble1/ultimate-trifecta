"""Pass 8 startup-logo evidence: measurements, crops and plots.

    python3 tools/branding/logo_evidence.py CAPTURES OUT
    (CAPTURES from tools/branding/capture_logo_evidence.sh; needs pillow, numpy)

Every stage is compared with the ideal: the vector rasterised by exact area
coverage (svg_raster) at the device's own geometry - the lockup 0.62 of the
screen height wide, centred, at its fractional position - on black.

Stages, per device (window pixel sizes):
  launch  the launch image as the native launch screen and Godot's boot
          splash show it: one bilinear tap per pixel, no mipmaps, the square
          fitted to the screen height (Godot: linear sampler, max_lod 0;
          Core Animation's default kCAFilterLinear).  Emulated here; checked
          against Godot's real boot splash caught by X screenshots at
          2532x1170 (see "boot_real" in metrics.json).
  curtain the first frame of the BootCurtain (real Godot render, llvmpipe).
          Before: V8's curtain reproduced from its PNG and import settings
          (the lab render equals V8's real curtain capture).
Metrics (8-bit levels; the lockup's crop):
  edge_rms   RMS difference from the ideal over the contour band (+-2 px)
  alias_max  largest difference left after a 1-px Gaussian blur: what a
             viewer sees as a misplaced or stair-stepped edge, not softness
  glow, dips partly covered pixels detached from the contour outside it (a
             light halo ring) or dipping inside it (a dark ring)
  purity     largest colour error from black-blended-with-fill (a fringe)
  shift      ink centroid minus the ideal's, device px (a position jump)
All images written are lossless PNG at the device's pixel size, or nearest-
neighbour enlargements of those pixels (labelled 400 %).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..'))
import svg_raster  # noqa: E402
import launch_audit  # noqa: E402

ROOT = os.path.join(HERE, '..', '..')
SVG = os.path.join(ROOT, 'art_src', 'branding', 'idlery-games.svg')
LAUNCH = os.path.join(ROOT, 'game', 'assets', 'icon', 'launch.png')
LOCKUP_W = 0.62
PAD = 8
DEVICES = [
    (2532, 1170, 'iPhone 12-14, 16e (3x)'),
    (2778, 1284, 'iPhone 12/13 Pro Max, 14 Plus (3x)'),
    (1334, 750, 'iPhone SE 2nd/3rd gen (2x)'),
    (2732, 2048, 'iPad Pro 12.9-inch (2x)'),
]
# enlargement regions, in the lockup's vector units (1600 x 920 canvas)
REGIONS = [('i, d', (232, 150, 420, 300)), ('e', (700, 230, 900, 360)), ('GAMES', (585, 655, 830, 765))]
# chart tokens (light surface)
SURFACE = (252, 252, 251)
INK = (11, 11, 11)
INK2 = (82, 81, 78)
GRID = (226, 225, 220)
S_AFTER = (42, 120, 214)    # blue
S_BEFORE = (235, 104, 52)   # orange
S_BOOT = (27, 175, 122)     # aqua


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def lockup(W, H):
    side = min(W, H)
    w = side * LOCKUP_W
    h = w * 920.0 / 1600.0
    return (W - w) / 2.0, (H - h) / 2.0, w, h


def ideal(W, H):
    """((cx, cy), premultiplied RGB float, alpha) for the lockup crop."""
    x0, y0, w, h = lockup(W, H)
    cx, cy = math.floor(x0) - PAD, math.floor(y0) - PAD
    cw, ch = math.ceil(x0 + w) + PAD - cx, math.ceil(y0 + h) + PAD - cy
    prem, a, _ = svg_raster.render(SVG, w / 1600.0, size=(cw, ch), offset=(x0 - cx, y0 - cy))
    return (cx, cy), prem, a


def bilinear(src, sx0, sy0, scale, cx, cy, cw, ch):
    xs = (np.arange(cx, cx + cw) + 0.5 - sx0) * scale - 0.5
    ys = (np.arange(cy, cy + ch) + 0.5 - sy0) * scale - 0.5
    hs, ws = src.shape[:2]
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = (xs - x0)[None, :, None]
    fy = (ys - y0)[:, None, None]
    xa, xb = np.clip(x0, 0, ws - 1), np.clip(x0 + 1, 0, ws - 1)
    ya, yb = np.clip(y0, 0, hs - 1), np.clip(y0 + 1, 0, hs - 1)
    return ((src[ya][:, xa] * (1 - fx) + src[ya][:, xb] * fx) * (1 - fy)
            + (src[yb][:, xa] * (1 - fx) + src[yb][:, xb] * fx) * fy)


def launch_on_screen(path, W, H, crop):
    """The launch square fitted to the screen height, one bilinear tap."""
    src = np.asarray(Image.open(path).convert('RGB')).astype(float)
    side = min(W, H)
    (cx, cy), cw, ch = crop
    return np.clip(np.rint(bilinear(src, (W - side) / 2.0, (H - side) / 2.0, src.shape[0] / side, cx, cy, cw, ch)), 0, 255)


def gblur(x, s=1.0):
    r = int(3 * s + 0.5)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    k /= k.sum()
    y = np.apply_along_axis(lambda v: np.convolve(v, k, mode='same'), 0, x)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode='same'), 1, y)


def centroid(img):
    lum = img.mean(-1)
    ys, xs = np.mgrid[0:lum.shape[0], 0:lum.shape[1]]
    return np.array([(lum * xs).sum() / lum.sum(), (lum * ys).sum() / lum.sum()])


def measure(img, prem, a):
    d = img - prem
    edge = (a > 0.002) & (a < 0.998)
    band = edge.copy()
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            band |= np.roll(np.roll(edge, dy, 0), dx, 1)
    lp = gblur(d.mean(-1), 1.0)
    u8 = np.clip(np.rint(img), 0, 255).astype(np.uint8)
    q = launch_audit.edge_quality((u8.shape[1], u8.shape[0], 3, [bytearray(r.tobytes()) for r in u8]))
    sh = centroid(img) - centroid(prem)
    return {
        'edge_rms': round(float(np.sqrt((d[band] ** 2).mean())), 2),
        'alias_max': round(float(np.abs(lp[band]).max()), 1),
        'glow': q['glow'], 'dips': q['dips'], 'purity': round(q['purity'], 1),
        'aliased_crossings': round(q['hard'], 3),
        'shift': [round(float(sh[0]), 3), round(float(sh[1]), 3)],
    }


def load_crop(path, crop):
    (cx, cy), cw, ch = crop
    full = np.asarray(Image.open(path).convert('RGB')).astype(float)
    return full[cy:cy + ch, cx:cx + cw], full


def u8(a):
    return Image.fromarray(np.clip(np.rint(a), 0, 255).astype(np.uint8))


def label_tile(img, text, sub=''):
    f, f2 = font(22), font(16)
    t = Image.new('RGB', (img.width, img.height + 52), SURFACE)
    t.paste(img, (0, 52))
    dr = ImageDraw.Draw(t)
    dr.text((6, 4), text, fill=INK, font=f)
    if sub:
        dr.text((6, 30), sub, fill=INK2, font=f2)
    return t


def grid(tiles, cols, gap=12, bg=SURFACE):
    rows = [tiles[i:i + cols] for i in range(0, len(tiles), cols)]
    cw = max(t.width for t in tiles)
    rh = [max(t.height for t in r) for r in rows]
    out = Image.new('RGB', (cols * cw + (cols + 1) * gap, sum(rh) + (len(rows) + 1) * gap), bg)
    y = gap
    for r, h in zip(rows, rh):
        x = gap
        for t in r:
            out.paste(t, (x, y))
            x += cw + gap
        y += h + gap
    return out


def region_box(W, H, crop, reg):
    x0, y0, w, _ = lockup(W, H)
    k = w / 1600.0
    (cx, cy), _, _ = crop
    a, b, c, d = reg
    return (int(math.floor(x0 + a * k - cx)), int(math.floor(y0 + b * k - cy)),
            int(math.ceil(x0 + c * k - cx)), int(math.ceil(y0 + d * k - cy)))


def enlarge(img, box, z=4):
    x0, y0, x1, y1 = box
    return u8(img[y0:y1, x0:x1]).resize(((x1 - x0) * z, (y1 - y0) * z), Image.NEAREST)


def line_chart(path, title, xlabel, ylabel, series, xs, size=(1100, 600)):
    """Static line chart: thin 2-px lines, recessive grid, one legend row."""
    W, H = size
    L, R, T, B = 80, 40, 110, 70
    img = Image.new('RGB', (W, H), SURFACE)
    dr = ImageDraw.Draw(img)
    f, fs = font(22), font(16)
    dr.text((L, 14), title, fill=INK, font=f)
    ymin, ymax = 0.0, 160.0
    xmin, xmax = min(xs), max(xs)
    px = lambda x: L + (x - xmin) / float(xmax - xmin) * (W - L - R)
    py = lambda y: T + (1 - (min(y, ymax) - ymin) / (ymax - ymin)) * (H - T - B)
    for yv in range(0, 161, 40):
        dr.line([(L, py(yv)), (W - R, py(yv))], fill=GRID, width=1)
        dr.text((L - 40, py(yv) - 9), '%d' % yv, fill=INK2, font=fs)
    for xv in xs:
        dr.text((px(xv) - 10, H - B + 8), '%d' % xv, fill=INK2, font=fs)
    dr.line([(L, H - B), (W - R, H - B)], fill=INK2, width=1)
    dr.text((L, H - 30), xlabel, fill=INK2, font=fs)
    dr.text((L - 40, T - 26), ylabel, fill=INK2, font=fs)
    for name, ys, col, dash in series:
        pts = [(px(x), py(y)) for x, y in zip(xs, ys)]
        if dash:
            for (a, b) in zip(pts[:-1], pts[1:]):
                for k in range(6):
                    if k % 2 == 0:
                        dr.line([(a[0] + (b[0] - a[0]) * k / 6, a[1] + (b[1] - a[1]) * k / 6),
                                 (a[0] + (b[0] - a[0]) * (k + 1) / 6, a[1] + (b[1] - a[1]) * (k + 1) / 6)], fill=col, width=2)
        else:
            dr.line(pts, fill=col, width=2)
        for p in pts:
            dr.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=col, outline=SURFACE, width=2)
    lx = L
    for name, _, col, _ in series:
        dr.line([(lx, 62), (lx + 24, 62)], fill=col, width=3)
        dr.text((lx + 30, 53), name, fill=INK, font=fs)
        lx += 60 + int(dr.textlength(name, font=fs))
    img.save(path, optimize=True)


def main():
    cap, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, 'stages'), exist_ok=True)
    before_launch = os.path.join(cap, 'before', 'launch.png')
    report = {'devices': {}, 'notes': {}}
    for W, H, name in DEVICES:
        res = '%dx%d' % (W, H)
        var = os.path.join(cap, 'variants_' + res)
        if not os.path.isdir(var):
            continue
        (cx, cy), prem, a = ideal(W, H)
        ch, cw = a.shape
        crop = ((cx, cy), cw, ch)
        st = {
            ('launch', 'before'): launch_on_screen(before_launch, W, H, crop),
            ('launch', 'after'): launch_on_screen(LAUNCH, W, H, crop),
            ('curtain', 'before'): load_crop(os.path.join(var, 'v8_curtain.png'), crop)[0],
            ('curtain', 'after'): load_crop(os.path.join(var, 'curtain.png'), crop)[0],
        }
        dev = {'name': name, 'lockup_px': [round(v, 3) for v in lockup(W, H)], 'crop': [cx, cy, cw, ch], 'stages': {}}
        for (stage, when), img in st.items():
            dev['stages']['%s_%s' % (stage, when)] = measure(img, prem, a)
            u8(img).save(os.path.join(out, 'stages', '%s_%s_%s.png' % (res, stage, when)), optimize=True)
        u8(prem).save(os.path.join(out, 'stages', '%s_ideal.png' % res), optimize=True)
        # handoff: what changes on screen when the curtain replaces the splash
        for when in ('before', 'after'):
            d = st[('curtain', when)] - st[('launch', when)]
            dev['handoff_%s' % when] = {
                'rms': round(float(np.sqrt((d ** 2).mean())), 2), 'max': round(float(np.abs(d).max()), 1),
                'shift': [round(float(v), 3) for v in centroid(st[('curtain', when)]) - centroid(st[('launch', when)])]}
        # diagnosis variants (which part of V8's curtain moved/softened it)
        diag = {}
        for v in ('v8_png_linear', 'v8_png_unsnapped', 'fallback', 'boot_before', 'boot_after'):
            p = os.path.join(var, v + '.png')
            if os.path.exists(p):
                diag[v] = measure(load_crop(p, crop)[0], prem, a)
        dev['variants'] = diag
        # stage sheet at the device's pixel size
        tiles = []
        for stage, title in (('launch', 'launch screen / boot splash'), ('curtain', 'BootCurtain, first frame')):
            for when in ('before', 'after'):
                m = dev['stages']['%s_%s' % (stage, when)]
                tiles.append(label_tile(u8(st[(stage, when)]), '%s - %s (V8)' % (title, when) if when == 'before' else '%s - %s (Pass 8)' % (title, when),
                                        'edge rms %.1f, alias max %.0f, halo %d+%d px, shift %+.2f,%+.2f px' % (
                                            m['edge_rms'], m['alias_max'], m['glow'], m['dips'], m['shift'][0], m['shift'][1])))
        grid(tiles, 2).save(os.path.join(out, 'stages_%s.png' % res), optimize=True)
        # 400 % enlargements
        rows = []
        for rname, reg in REGIONS:
            box = region_box(W, H, crop, reg)
            for key, img in (('launch/boot V8', st[('launch', 'before')]), ('launch/boot Pass 8', st[('launch', 'after')]),
                             ('curtain V8', st[('curtain', 'before')]), ('curtain Pass 8', st[('curtain', 'after')]), ('ideal (vector)', prem)):
                rows.append(label_tile(enlarge(img, box), '%s: %s' % (rname, key)))
        sheet = grid(rows, 5)
        head = Image.new('RGB', (sheet.width, 44), SURFACE)
        ImageDraw.Draw(head).text((12, 10), '%s %s: device pixels enlarged 400 %% (nearest neighbour), lossless' % (res, name), fill=INK, font=font(22))
        both = Image.new('RGB', (sheet.width, sheet.height + 44), SURFACE)
        both.paste(head, (0, 0))
        both.paste(sheet, (0, 44))
        both.save(os.path.join(out, 'edges_400pct_%s.png' % res), optimize=True)
        report['devices'][res] = dev
        print(res, json.dumps({k: v for k, v in dev['stages'].items()}))

    # 2532 x 1170 extras: the real boot splash, the handoff, the fade, profiles
    W, H = 2532, 1170
    res = '2532x1170'
    if res in report['devices']:
        (cx, cy), prem, a = ideal(W, H)
        ch, cw = a.shape
        crop = ((cx, cy), cw, ch)
        xs_dir = {'after': os.path.join(cap, 'xshots_2532x1170'), 'before': os.path.join(cap, 'xshots_before_2532x1170')}
        boot_real = {}
        for when, d in xs_dir.items():
            if not os.path.isdir(d):
                continue
            emu = launch_on_screen(LAUNCH if when == 'after' else before_launch, W, H, crop)
            shots = sorted(f for f in os.listdir(d) if f.startswith('x_') and f.endswith('.png'))
            best = None
            for f in shots:
                c, full = load_crop(os.path.join(d, f), crop)
                if full.sum() - c.sum() > 0 or c.sum() == 0:
                    continue   # not a startup-black frame
                diff = float(np.abs(c - emu).max())
                if best is None or diff < best[0]:
                    best = (diff, f, c, full)
            if best:
                boot_real[when] = {'frame': best[1], 'max_diff_vs_emulation': round(best[0], 1),
                                   'metrics': measure(best[2], prem, a)}
                u8(best[3]).save(os.path.join(out, 'stages', '2532x1170_boot_real_xshot_%s_full.png' % when), optimize=True)
        report['devices'][res]['boot_real'] = boot_real
        # handoff difference images (x4)
        tiles = []
        for when in ('before', 'after'):
            c = report['devices'][res]['stages']
            cur = load_crop(os.path.join(cap, 'variants_' + res, 'v8_curtain.png' if when == 'before' else 'curtain.png'), crop)[0]
            lau = launch_on_screen(before_launch if when == 'before' else LAUNCH, W, H, crop)
            h = report['devices'][res]['handoff_%s' % when]
            tiles.append(label_tile(u8(np.abs(cur - lau) * 4), 'curtain minus boot splash, x4 - %s' % when,
                                    'rms %.1f, max %.0f levels; centroid moves %+.2f, %+.2f px' % (h['rms'], h['max'], h['shift'][0], h['shift'][1])))
        grid(tiles, 2).save(os.path.join(out, 'handoff_diff_2532x1170.png'), optimize=True)
        # edge profile: a row through the middle of the wordmark, a window
        # around its third falling (fill -> black) edge
        prof_y = int(round(lockup(W, H)[1] + 360 * lockup(W, H)[2] / 1600.0 - cy))
        row = a[prof_y]
        falls = [x for x in range(1, len(row)) if row[x - 1] >= 0.5 > row[x]]
        e = falls[min(2, len(falls) - 1)]
        xs = list(range(e - 7, e + 9))
        lum = lambda img: [float(img[prof_y, x].mean()) for x in xs]
        cur_b = load_crop(os.path.join(cap, 'variants_' + res, 'v8_curtain.png'), crop)[0]
        cur_a = load_crop(os.path.join(cap, 'variants_' + res, 'curtain.png'), crop)[0]
        line_chart(os.path.join(out, 'profile_2532x1170.png'),
                   'One edge of the wordmark, row %d of the lockup crop, 2532 x 1170 (device pixels)' % prof_y,
                   'x, device pixels in the lockup crop', 'mean RGB level',
                   [('ideal (vector)', lum(prem), INK2, True), ('boot splash, V8', lum(launch_on_screen(before_launch, W, H, crop)), S_BOOT, False),
                    ('curtain, V8', lum(cur_b), S_BEFORE, False), ('curtain, Pass 8', lum(cur_a), S_AFTER, False)],
                   xs)
        report['notes']['profile'] = {'row': prof_y, 'x': [xs[0], xs[-1]]}
        # the fade, frame by frame (fixed 60 fps clock)
        sd = os.path.join(cap, 'startup_2532x1170')
        tl = os.path.join(sd, 'timeline.json')
        if os.path.exists(tl):
            t = json.load(open(tl))
            frames = {r['frame']: r for r in t['frames']}
            leave = t['full'].get('leave', 27)
            gone = t['full'].get('gone', leave + 25)
            pick = [0, leave - 1, leave + 3, leave + 7, leave + 11, leave + 15, gone - 1, gone]
            tiles = []
            for fr in pick:
                p = os.path.join(sd, 'crop_%03d.png' % fr)
                if not os.path.exists(p):
                    continue
                r = frames.get(fr, {})
                sub = ('curtain gone: home' if not r.get('curtain') else
                       'logo a %.2f, settle %.3f, black a %.2f' % (r.get('logo_alpha', 1), r.get('settle', 1), r.get('bg_alpha', 1)))
                tiles.append(label_tile(Image.open(p).convert('RGB'), 'frame %d (%.3f s)' % (fr, fr / 60.0), sub))
            grid(tiles, 4).save(os.path.join(out, 'fade_frames_2532x1170.png'), optimize=True)
            first = Image.open(os.path.join(sd, 'crop_000.png')).convert('RGB')
            # the curtain's first real-boot frame is the lab's curtain render
            c0 = np.asarray(first).astype(float)
            ox, oy = t['crop'][0], t['crop'][1]
            lab = load_crop(os.path.join(cap, 'variants_' + res, 'curtain.png'), crop)[1][oy:oy + c0.shape[0], ox:ox + c0.shape[1]]
            report['devices'][res]['startup'] = {
                'frames': len(t['frames']), 'leave_frame': leave, 'gone_frame': gone,
                'first_frame_vs_lab_curtain_max_diff': round(float(np.abs(c0 - lab).max()), 1),
                'exact_raster': bool(t['frames'][0].get('exact', False))}
            # the settle (scale 1 -> 1.03 in BrandMark's draw call) while the
            # black is still opaque: each frame against the vector at that
            # scale and fade (premultiplied: no fringe pulled in by the scaling)
            settle = []
            x0, y0, w, h = t['lockup_px']
            ox, oy, ow, oh = t['crop']
            for fr in range(leave, gone):
                r = frames.get(fr, {})
                if r.get('bg_alpha', 0) < 1.0 or not r.get('curtain'):
                    continue
                sc, fa = r['settle'], r['logo_alpha']
                mx, my = x0 + w / 2, y0 + h / 2
                pr, _, _ = svg_raster.render(SVG, w * sc / 1600.0, size=(ow, oh), offset=(mx + (x0 - mx) * sc - ox, my + (y0 - my) * sc - oy))
                c = np.asarray(Image.open(os.path.join(sd, 'crop_%03d.png' % fr)).convert('RGB')).astype(float)
                q = launch_audit.edge_quality((ow, oh, 3, [bytearray(rr.tobytes()) for rr in np.clip(np.rint(c / max(fa, 1e-3)), 0, 255).astype(np.uint8)]))
                settle.append({'frame': fr, 'settle': sc, 'fade': fa, 'mean_abs_vs_vector': round(float(np.abs(c - pr * fa).mean()), 2),
                               'purity': round(q['purity'], 1)})
            report['devices'][res]['settle_frames'] = settle
            for k, fr in t['full'].items():
                p = os.path.join(sd, 'full_%s_%03d.png' % (k, fr))
                if os.path.exists(p) and k in ('first', 'gone'):
                    Image.open(p).save(os.path.join(out, 'stages', '2532x1170_startup_%s_full.png' % ('curtain' if k == 'first' else 'home')), optimize=True)
        # compression: what a JPEG screenshot/recording adds (not rendering)
        box = region_box(W, H, crop, REGIONS[2][1])
        after = u8(cur_a)
        m0 = measure(cur_a, prem, a)
        tiles = [label_tile(enlarge(cur_a, box), 'Pass 8 curtain, lossless PNG (400 %)',
                            'edge rms %.1f, halo px %d (rendering)' % (m0['edge_rms'], m0['glow'] + m0['dips']))]
        comp = {}
        for qv in (85, 60):
            p = os.path.join(out, '_tmp.jpg')
            after.save(p, quality=qv)
            j = np.asarray(Image.open(p).convert('RGB')).astype(float)
            os.remove(p)
            comp['jpeg_q%d' % qv] = measure(j, prem, a)
            tiles.append(label_tile(enlarge(j, box), 'same frame saved as JPEG q%d (400 %%)' % qv,
                                    'edge rms %.1f, halo px %d (JPEG artefacts)' % (
                                        comp['jpeg_q%d' % qv]['edge_rms'], comp['jpeg_q%d' % qv]['glow'] + comp['jpeg_q%d' % qv]['dips'])))
        grid(tiles, 3).save(os.path.join(out, 'compression_vs_rendering_2532x1170.png'), optimize=True)
        report['devices'][res]['compression'] = comp
    json.dump(report, open(os.path.join(out, 'metrics.json'), 'w'), indent=1)
    # markdown table
    lines = ['| Device | Stage | edge rms (V8 -> P8) | alias max | halo px (glow+dip) | purity | shift px |', '|---|---|---|---|---|---|---|']
    for res, dev in report['devices'].items():
        for stage in ('launch', 'curtain'):
            b, a2 = dev['stages'][stage + '_before'], dev['stages'][stage + '_after']
            lines.append('| %s %s | %s | %.1f -> %.1f | %.0f -> %.0f | %d -> %d | %.0f -> %.0f | %+.2f,%+.2f -> %+.2f,%+.2f |' % (
                res, dev['name'], stage, b['edge_rms'], a2['edge_rms'], b['alias_max'], a2['alias_max'],
                b['glow'] + b['dips'], a2['glow'] + a2['dips'], b['purity'], a2['purity'],
                b['shift'][0], b['shift'][1], a2['shift'][0], a2['shift'][1]))
        hb, ha = dev['handoff_before'], dev['handoff_after']
        lines.append('| %s | boot splash -> curtain | rms %.1f -> %.1f, max %.0f -> %.0f | | | | moves %+.2f,%+.2f -> %+.2f,%+.2f |' % (
            res, hb['rms'], ha['rms'], hb['max'], ha['max'], hb['shift'][0], hb['shift'][1], ha['shift'][0], ha['shift'][1]))
    open(os.path.join(out, 'metrics.md'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
