#!/usr/bin/env python3
"""Launch and branding audit for the exported iOS project (V5; Pass 8).

    python3 tools/launch_audit.py build/ios [out_dir] [--project game]

(--project defaults to game/ when run from the repository root, as in CI.)

V5 shows the requested Idlery Games lockup at startup (owner's request), so
naming Idlery is no longer a finding.  What this audit still fails on:
  - no launch storyboard, or more than one;
  - a launch image that is missing, not opaque, not on the startup black
    (#000000, V6) or without the Idlery teal mark in its centre;
  - a storyboard background that isn't the same black (white flash, or the
    V5 navy rectangle);
  - any "powered by" text in the game data (.pck) or the project's text files.
Pass 8 adds the logo's edges and composition, for every launch image (and,
with --project, Godot's boot splash image, which must be the same picture):
  - square, with the lockup's ink centred where Brand.LOCKUP_W puts it;
  - an antialiased contour: at most 15% of the contour's row/column
    crossings jump straight from background to full fill (an aliased or
    nearest-neighbour render: ~57%; the exact-coverage render: ~7%, where
    an edge happens to sit on a pixel boundary);
  - no halo: no partly covered pixel detached from the ink (a light ring
    outside the contour) and no dip inside it (a dark ring) - the ringing a
    Lanczos/sharpening resize leaves (V5's launch image: 2152 and 3009);
  - colour purity: every pixel is a blend of the startup black and one fill
    colour (teal or ivory) within 4 levels; a straight-alpha resize of the
    owner's PNG (white in its transparent pixels) leaves a light fringe
    that fails this (27 levels).
It also lists the launch files and the text files naming Idlery (expected:
the bundle ID in build plists) for the build log.  Standard library only.
"""
import os
import re
import struct
import sys
import zlib

BLACK = (0, 0, 0)       # V6: pure black startup (was the V5 navy #0c1324)
TEAL = (57, 165, 171)
IVORY = (229, 235, 245)  # the "GAMES" descriptor
# Where the lockup's ink sits in the launch square (fractions of its side):
# the 1600x920 lockup canvas at Brand.LOCKUP_W = 0.62 of the side, centred;
# its ink spans x 0.2826-0.7174 and y 0.3756-0.6087 of the side.
INK_BOX = (0.2826, 0.3756, 0.7174, 0.6087)
INK_TOL = 0.004
HARD_MAX = 0.15          # aliased crossings allowed (fraction)
PURITY_MAX = 4.0         # levels


def read_png(path):
    """8-bit RGB/RGBA, non-interlaced PNG -> (w, h, channels, rows)."""
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
    pos, idat, w = 8, b'', 0
    while pos < len(data):
        ln, typ = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', body)
            if depth != 8 or ctype not in (2, 6) or inter != 0:
                raise ValueError('unsupported PNG (depth %d, type %d, interlace %d)' % (depth, ctype, inter))
            ch = 3 if ctype == 2 else 4
        elif typ == b'IDAT':
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * ch
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0
            b = prev[x]
            c = prev[x - ch] if x >= ch else 0
            if ft == 1:
                line[x] = (line[x] + a) & 255
            elif ft == 2:
                line[x] = (line[x] + b) & 255
            elif ft == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(line)
        prev = line
    return w, h, ch, rows


def px(img, x, y):
    w, h, ch, rows = img
    r = rows[y]
    return tuple(r[x * ch:x * ch + ch])


def near(c, ref, tol):
    return all(abs(int(a) - int(b)) <= tol for a, b in zip(c[:3], ref))


def ink_bbox(img, level=8):
    """Bounding box (x0, y0, x1, y1) of pixels brighter than `level`."""
    w, h, ch, rows = img
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        r = rows[y]
        if max(r) <= level:
            continue
        lit = [i // ch for i in range(0, w * ch, ch) if max(r[i:i + 3]) > level]
        x0, x1 = min(x0, lit[0]), max(x1, lit[-1])
        y0, y1 = min(y0, y), max(y1, y)
    return x0, y0, x1, y1


def edge_quality(img):
    """Edges of the lockup on black (see the module notes).  Returns a dict."""
    w, h, ch, rows = img
    x0, y0, x1, y1 = ink_bbox(img)
    if x1 < 0:
        return {'ink': None}
    bx0, by0, bx1, by1 = max(0, x0 - 3), max(0, y0 - 3), min(w - 1, x1 + 3), min(h - 1, y1 + 3)
    fills = [(c, sum(v * v for v in c)) for c in (TEAL, IVORY)]
    cov, purity = [], 0.0
    for y in range(by0, by1 + 1):
        r = rows[y]
        line = []
        for x in range(bx0, bx1 + 1):
            i = x * ch
            p0, p1, p2 = r[i], r[i + 1], r[i + 2]
            if p0 == 0 and p1 == 0 and p2 == 0:
                line.append(0.0)
                continue
            best = None
            for c, cc in fills:
                t = min(1.0, max(0.0, (p0 * c[0] + p1 * c[1] + p2 * c[2]) / cc))
                res = max(abs(p0 - t * c[0]), abs(p1 - t * c[1]), abs(p2 - t * c[2]))
                if best is None or res < best[0]:
                    best = (res, t)
            purity = max(purity, best[0])
            line.append(best[1])
        cov.append(line)
    H, W = len(cov), len(cov[0])

    def crossings(seq):
        n = hard = 0
        last = None
        for i, t in enumerate(seq):
            cls = 0 if t <= 0.06 else (1 if t >= 0.94 else None)
            if cls is None:
                continue
            if last is not None and last[0] != cls:
                n += 1
                hard += (i - last[1] == 1)
            last = (cls, i)
        return n, hard

    n = hard = 0
    for line in cov:
        a, b = crossings(line)
        n, hard = n + a, hard + b
    for x in range(W):
        a, b = crossings([cov[y][x] for y in range(H)])
        n, hard = n + a, hard + b
    # a partly covered pixel is part of a contour when a neighbour holds more
    # of the fill (towards the ink) and, inside, when one holds less (towards
    # the background); otherwise it is a detached glow or a dip (ringing)
    tol = 1.0 / 255
    glow = dips = 0
    for y in range(1, H - 1):
        up, mid, dn = cov[y - 1], cov[y], cov[y + 1]
        for x in range(1, W - 1):
            t = mid[x]
            if t <= 2.0 / 255 or t >= 0.99:
                continue
            nb = (up[x - 1], up[x], up[x + 1], mid[x - 1], mid[x + 1], dn[x - 1], dn[x], dn[x + 1])
            if t < 0.5 and max(nb) <= t + tol:
                glow += 1
            elif t >= 0.5 and min(nb) >= t - tol:
                dips += 1
    side = float(w)
    box = (x0 / side, y0 / side, (x1 + 1) / side, (y1 + 1) / side)
    return {'ink': box, 'crossings': n, 'hard': hard / float(max(1, n)), 'glow': glow, 'dips': dips, 'purity': purity}


def check_launch_image(name, img, lines, fails):
    """The Pass 8 composition and edge checks for one launch image."""
    w, h = img[0], img[1]
    if w != h:
        fails.append('%s is not square (%dx%d): "scale to fit" would not match the curtain' % (name, w, h))
        return
    q = edge_quality(img)
    if q['ink'] is None:
        fails.append('%s has no lockup' % name)
        return
    off = max(abs(a - b) for a, b in zip(q['ink'], INK_BOX))
    lines.append('%s edges: ink box %s (expected %s, off by %.4f), contour crossings %d, aliased %.1f%%, '
                 'detached glow px %d, inner dip px %d, colour purity %.1f levels'
                 % (name, ', '.join('%.4f' % v for v in q['ink']), ', '.join('%.4f' % v for v in INK_BOX), off,
                    q['crossings'], 100 * q['hard'], q['glow'], q['dips'], q['purity']))
    if off > INK_TOL:
        fails.append('%s: the lockup is not where Brand.LOCKUP_W puts it (off by %.4f of the side)' % (name, off))
    if q['hard'] > HARD_MAX:
        fails.append('%s: aliased contour (%.0f%% hard steps)' % (name, 100 * q['hard']))
    if q['glow'] + q['dips'] > max(8, q['crossings'] // 500):
        fails.append('%s: ringing halo around the logo (%d glow, %d dip pixels)' % (name, q['glow'], q['dips']))
    if q['purity'] > PURITY_MAX:
        fails.append('%s: edge colour is not a blend of the fill and black (%.0f levels off: a light or tinted fringe)' % (name, q['purity']))


def main():
    args = [a for a in sys.argv[1:]]
    # the Godot project (for the boot splash image): --project DIR, or the
    # checkout's game/ when run from the repository root (as CI does)
    project = 'game' if os.path.isfile(os.path.join('game', 'project.godot')) else None
    if '--project' in args:
        k = args.index('--project')
        project = args[k + 1]
        del args[k:k + 2]
    root = args[0] if args else 'build/ios'
    out = args[1] if len(args) > 1 else None
    lines, fails = [], []
    boards, images, pcks, texts = [], [], [], []
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f)
            lf = f.lower()
            if lf.endswith('.storyboard') and 'launch' in lf:
                boards.append(p)
            elif lf.endswith('.png') and ('splash' in lf or 'launch' in lf):
                images.append(p)
            elif lf.endswith('.pck'):
                pcks.append(p)
            elif lf.endswith(('.plist', '.storyboard', '.json', '.strings', '.xml', '.pbxproj', '.entitlements', '.xcprivacy')):
                texts.append(p)
    lines.append('launch storyboards: %s' % ', '.join(os.path.relpath(b, root) for b in boards))
    if len(boards) != 1:
        fails.append('expected exactly one launch storyboard, found %d' % len(boards))
    for b in boards:
        s = open(b, encoding='utf-8', errors='replace').read()
        cols = re.findall(r'<color[^>]*key="backgroundColor"[^>]*>', s)
        ok = False
        for c in cols:
            vals = {k: float(v) for k, v in re.findall(r'(red|green|blue)="([0-9.]+)"', c)}
            if vals and near(tuple(round(vals[k] * 255) for k in ('red', 'green', 'blue')), BLACK, 3):
                ok = True
        lines.append('storyboard background black: %s' % ('yes' if ok else 'NO (%s)' % (cols[:1] or 'none')))
        if not ok:
            fails.append('launch storyboard background is not the startup black (white flash or navy risk)')
    lines.append('launch images: %s' % ', '.join(os.path.relpath(i, root) for i in images))
    if not images:
        fails.append('no launch image in the exported project')
    for i in images:
        try:
            img = read_png(i)
        except Exception as e:  # noqa: BLE001 - report any decoding problem
            fails.append('%s: unreadable (%s)' % (os.path.basename(i), e))
            continue
        w, h, ch, rows = img
        corners = [px(img, 2, 2), px(img, w - 3, 2), px(img, 2, h - 3), px(img, w - 3, h - 3)]
        opaque = ch == 3 or all(c[3] == 255 for c in corners)
        black = all(near(c, BLACK, 6) for c in corners)
        teal = 0
        for y in range(h // 3, 2 * h // 3, max(1, h // 120)):
            for x in range(w // 4, 3 * w // 4, max(1, w // 160)):
                if near(px(img, x, y), TEAL, 40):
                    teal += 1
        lines.append('%s: %dx%d, opaque %s, black corners %s, Idlery teal samples %d' % (os.path.basename(i), w, h, opaque, black, teal))
        if not (opaque and black and teal > 20):
            fails.append('%s is not the Idlery Games launch composition on black' % os.path.basename(i))
        else:
            check_launch_image(os.path.basename(i), img, lines, fails)
    if project:
        # Godot's boot splash shows project boot_splash/image between the
        # launch screen and the first frame: it must be the same picture
        cfg = open(os.path.join(project, 'project.godot'), encoding='utf-8').read()
        m = re.search(r'^boot_splash/image="res://([^"]+)"', cfg, re.M)
        if not m:
            fails.append('project has no boot splash image')
        else:
            boot = read_png(os.path.join(project, m.group(1)))
            lines.append('boot splash %s: %dx%d' % (m.group(1), boot[0], boot[1]))
            check_launch_image('boot splash', boot, lines, fails)
            for i in images:
                try:
                    if read_png(i)[3] != boot[3]:
                        fails.append('%s differs from the boot splash image (a visible change at the handoff)' % os.path.basename(i))
                except Exception:  # noqa: BLE001 - reported above
                    pass
    powered = 0
    for p in pcks:
        with open(p, 'rb') as f:
            powered += len(re.findall(rb'powered\s+by', f.read(), re.I))
    for p in texts:
        try:
            powered += len(re.findall(r'powered\s+by', open(p, encoding='utf-8', errors='ignore').read(), re.I))
        except OSError:
            pass
    lines.append('"powered by" strings in game data and project text: %d' % powered)
    if powered:
        fails.append('"powered by" copy found (%d)' % powered)
    naming = [os.path.relpath(p, root) for p in texts if 'idlery' in open(p, encoding='utf-8', errors='ignore').read().lower()]
    lines.append('text files naming Idlery (expected: bundle ID in build plists): %s' % (', '.join(naming[:12]) or 'none'))
    lines.append('RESULT: %s' % ('PASS' if not fails else 'FAIL: ' + '; '.join(fails)))
    report = '\n'.join(lines)
    print(report)
    if out:
        os.makedirs(out, exist_ok=True)
        open(os.path.join(out, 'launch_audit.txt'), 'w').write(report + '\n')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
