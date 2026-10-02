#!/usr/bin/env python3
"""Launch and branding audit for the exported iOS project (V5).

    python3 tools/launch_audit.py build/ios [out_dir]

V5 shows the requested Idlery Games lockup at startup (owner's request), so
naming Idlery is no longer a finding.  What this audit still fails on:
  - no launch storyboard, or more than one;
  - a launch image that is missing, not opaque, not on the startup navy
    (#0c1324) or without the Idlery teal mark in its centre;
  - a storyboard background that isn't the same navy (white flash);
  - any "powered by" text in the game data (.pck) or the project's text files.
It also lists the launch files and the text files naming Idlery (expected:
the bundle ID in build plists) for the build log.  Standard library only.
"""
import os
import re
import struct
import sys
import zlib

NAVY = (12, 19, 36)
TEAL = (57, 165, 171)


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


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'build/ios'
    out = sys.argv[2] if len(sys.argv) > 2 else None
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
            if vals and near(tuple(round(vals[k] * 255) for k in ('red', 'green', 'blue')), NAVY, 3):
                ok = True
        lines.append('storyboard background navy: %s' % ('yes' if ok else 'NO (%s)' % (cols[:1] or 'none')))
        if not ok:
            fails.append('launch storyboard background is not the startup navy (white flash risk)')
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
        navy = all(near(c, NAVY, 6) for c in corners)
        teal = 0
        for y in range(h // 3, 2 * h // 3, max(1, h // 120)):
            for x in range(w // 4, 3 * w // 4, max(1, w // 160)):
                if near(px(img, x, y), TEAL, 40):
                    teal += 1
        lines.append('%s: %dx%d, opaque %s, navy corners %s, Idlery teal samples %d' % (os.path.basename(i), w, h, opaque, navy, teal))
        if not (opaque and navy and teal > 20):
            fails.append('%s is not the Idlery Games launch composition on navy' % os.path.basename(i))
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
