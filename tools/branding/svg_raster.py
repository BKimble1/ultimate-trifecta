"""Exact-coverage rasteriser for the flat-filled branding SVGs (Pass 8).

The Idlery Games lockup (art_src/branding/idlery-games.svg) is two flat
fills: the teal Idlery mark (cubic Beziers) and the ivory outlined "GAMES"
descriptor (TrueType quadratics), under translate/scale transforms.  This
module turns it into antialiased pixels from the vector itself, so the
launch image and the runtime texture are never resampled from a smaller
raster:

  - curves are flattened to within 1/50 px of the true outline (Wang's
    bound), at the output scale and sub-pixel offset;
  - each pixel's alpha is the exact area of the pixel covered by the fill
    (signed-area accumulation, the method of FreeType's smooth rasteriser
    and font-rs; non-zero winding, the SVG default), i.e. a box filter
    over the true shape: no supersampling grid, no stair steps, no
    ringing, no halo;
  - fills are composited premultiplied and stored as straight RGBA whose
    colour is exactly the fill colour wherever alpha > 0 (no dark or light
    edge colour), and fully transparent pixels carry the nearest fill
    colour (alpha bleed) so bilinear or mipmap filtering of the straight
    texture never pulls black or white into the contour.

Supported SVG subset (what the branding sources use, checked, anything else
raises): <svg width height viewBox>, nested <g>/<path> with fill and
transform (translate, scale, matrix), path commands M L H V C S Q T Z in
absolute and relative form.  Standard library + numpy.
"""
import math
import re
import xml.etree.ElementTree as ET

import numpy as np

TOL = 0.02          # max distance of a flattened chord from the curve, px


def _mat_mul(a, b):
    """2x3 affine matrices (a, b, c, d, e, f) as in SVG: a*b."""
    a0, a1, a2, a3, a4, a5 = a
    b0, b1, b2, b3, b4, b5 = b
    return (a0 * b0 + a2 * b1, a1 * b0 + a3 * b1,
            a0 * b2 + a2 * b3, a1 * b2 + a3 * b3,
            a0 * b4 + a2 * b5 + a4, a1 * b4 + a3 * b5 + a5)


IDENT = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def parse_transform(s):
    m = IDENT
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', s or ''):
        v = [float(x) for x in re.split(r'[\s,]+', args.strip()) if x]
        if name == 'translate':
            t = (1.0, 0.0, 0.0, 1.0, v[0], v[1] if len(v) > 1 else 0.0)
        elif name == 'scale':
            t = (v[0], 0.0, 0.0, v[1] if len(v) > 1 else v[0], 0.0, 0.0)
        elif name == 'matrix':
            t = tuple(v)
        else:
            raise ValueError('unsupported transform %s' % name)
        m = _mat_mul(m, t)
    return m


def _apply(m, x, y):
    return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])


_TOKEN = re.compile(r'[MmLlHhVvCcSsQqTtZzAa]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def parse_path(d):
    """-> list of subpaths, each a list of segments in user space:
    ('L', p0, p1) | ('Q', p0, c, p1) | ('C', p0, c1, c2, p1); closed."""
    toks = _TOKEN.findall(d)
    i, cmd = 0, None
    cur = start = (0.0, 0.0)
    last_c = None          # last control point (for S / T reflection)
    last_cmd = ''
    subs, segs = [], []

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def close():
        nonlocal segs, cur
        if segs or cur != start:
            if cur != start:
                segs.append(('L', cur, start))
            subs.append(segs)
        segs = []
        cur = start

    while i < len(toks):
        if re.match(r'[A-Za-z]', toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in 'Aa':
                raise ValueError('arcs are not supported')
            if cmd in 'Zz':
                close()
                last_c, last_cmd = None, 'Z'
                continue
        elif cmd is None:
            raise ValueError('path data does not start with a command')
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = cur if rel else (0.0, 0.0)
        if c == 'M':
            if segs:
                close()
            cur = start = (ox + num(), oy + num())
            cmd = 'l' if rel else 'L'      # implicit lineto after moveto
            last_c, last_cmd = None, 'M'
        elif c == 'L':
            p = (ox + num(), oy + num())
            segs.append(('L', cur, p))
            cur, last_c, last_cmd = p, None, 'L'
        elif c == 'H':
            p = ((cur[0] if rel else 0.0) + num(), cur[1])
            segs.append(('L', cur, p))
            cur, last_c, last_cmd = p, None, 'L'
        elif c == 'V':
            p = (cur[0], (cur[1] if rel else 0.0) + num())
            segs.append(('L', cur, p))
            cur, last_c, last_cmd = p, None, 'L'
        elif c == 'C':
            c1 = (ox + num(), oy + num())
            c2 = (ox + num(), oy + num())
            p = (ox + num(), oy + num())
            segs.append(('C', cur, c1, c2, p))
            cur, last_c, last_cmd = p, c2, 'C'
        elif c == 'S':
            c1 = (2 * cur[0] - last_c[0], 2 * cur[1] - last_c[1]) if last_cmd == 'C' else cur
            c2 = (ox + num(), oy + num())
            p = (ox + num(), oy + num())
            segs.append(('C', cur, c1, c2, p))
            cur, last_c, last_cmd = p, c2, 'C'
        elif c == 'Q':
            q = (ox + num(), oy + num())
            p = (ox + num(), oy + num())
            segs.append(('Q', cur, q, p))
            cur, last_c, last_cmd = p, q, 'Q'
        elif c == 'T':
            q = (2 * cur[0] - last_c[0], 2 * cur[1] - last_c[1]) if last_cmd == 'Q' else cur
            p = (ox + num(), oy + num())
            segs.append(('Q', cur, q, p))
            cur, last_c, last_cmd = p, q, 'Q'
        else:
            raise ValueError('unsupported path command %s' % cmd)
    if segs:
        close()
    return subs


def load(path):
    """-> (width, height, [(rgb, matrix, subpaths)]) in SVG user units, the
    viewBox mapped to [0, width] x [0, height]."""
    root = ET.parse(path).getroot()
    ns = '{http://www.w3.org/2000/svg}'
    vb = [float(v) for v in re.split(r'[\s,]+', root.get('viewBox', '').strip()) if v]
    w = float(root.get('width', vb[2] if vb else 0))
    h = float(root.get('height', vb[3] if vb else 0))
    base = IDENT
    if vb:
        base = (w / vb[2], 0.0, 0.0, h / vb[3], -vb[0] * w / vb[2], -vb[1] * h / vb[3])
    fills = []

    def walk(el, m, fill):
        m = _mat_mul(m, parse_transform(el.get('transform')))
        fill = el.get('fill', fill)
        tag = el.tag.replace(ns, '')
        if tag == 'path':
            if fill in (None, 'none'):
                return
            if el.get('fill-rule', 'nonzero') != 'nonzero' or el.get('stroke') not in (None, 'none'):
                raise ValueError('only non-zero flat fills are supported')
            fills.append((_hex(fill), m, parse_path(el.get('d'))))
        elif tag in ('g', 'svg'):
            for ch in el:
                walk(ch, m, fill)
        elif tag not in ('title', 'desc', 'metadata', 'defs'):
            raise ValueError('unsupported element %s' % tag)

    walk(root, base, 'black')
    return w, h, fills


def _hex(s):
    s = s.strip().lstrip('#')
    if len(s) == 3:
        s = ''.join(ch * 2 for ch in s)
    return tuple(int(s[k:k + 2], 16) for k in (0, 2, 4))


def _flatten(seg, m, scale, ox, oy, out):
    """Append line segments (device px) approximating seg to out."""
    pts = [_apply(m, *p) for p in seg[1:]]
    pts = [(x * scale + ox, y * scale + oy) for x, y in pts]
    kind = seg[0]
    if kind == 'L':
        out.append((pts[0], pts[1]))
        return
    if kind == 'Q':
        p0, c, p1 = pts
        dd = math.hypot(p0[0] - 2 * c[0] + p1[0], p0[1] - 2 * c[1] + p1[1])
        n = max(1, int(math.ceil(math.sqrt(dd / (4.0 * TOL)))))
        prev = p0
        for k in range(1, n + 1):
            t = k / n
            u = 1 - t
            q = (u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
                 u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1])
            out.append((prev, q))
            prev = q
        return
    p0, c1, c2, p1 = pts
    dd = max(math.hypot(p0[0] - 2 * c1[0] + c2[0], p0[1] - 2 * c1[1] + c2[1]),
             math.hypot(c1[0] - 2 * c2[0] + p1[0], c1[1] - 2 * c2[1] + p1[1]))
    n = max(1, int(math.ceil(math.sqrt(0.75 * dd / TOL))))
    prev = p0
    for k in range(1, n + 1):
        t = k / n
        u = 1 - t
        a, b, cc, e = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
        q = (a * p0[0] + b * c1[0] + cc * c2[0] + e * p1[0],
             a * p0[1] + b * c1[1] + cc * c2[1] + e * p1[1])
        out.append((prev, q))
        prev = q


def coverage(lines, w, h):
    """Exact area coverage (0..1) of the non-zero fill bounded by `lines`
    on a w x h pixel grid (pixel (x, y) spans [x, x+1] x [y, y+1])."""
    W = w + 3
    acc = [0.0] * (W * (h + 1))
    for (x0, y0), (x1, y1) in lines:
        if y0 == y1:
            continue
        if y0 < y1:
            d_ir = 1.0
        else:
            d_ir = -1.0
            x0, y0, x1, y1 = x1, y1, x0, y0
        if y1 <= 0 or y0 >= h:
            continue
        dxdy = (x1 - x0) / (y1 - y0)
        x = x0
        ys = y0
        if ys < 0:
            x -= ys * dxdy
            ys = 0.0
        yend = min(float(h), y1)
        y = int(ys)
        while y < yend:
            top = max(float(y), ys)
            bot = min(float(y + 1), yend)
            dy = bot - top
            xn = x + dxdy * dy
            d = dy * d_ir
            xa, xb = (x, xn) if x < xn else (xn, x)
            if xa < -1e-6 or xb > w + 1e-6:
                raise ValueError('the shape leaves the canvas horizontally')
            xa += 1.0      # column -1 is index 0 of the row buffer
            xb += 1.0
            row = y * W
            x0f = math.floor(xa)
            x0i = int(x0f)
            x1c = math.ceil(xb)
            x1i = int(x1c)
            if x1i <= x0i + 1:
                xmf = 0.5 * (xa + xb) - x0f
                acc[row + x0i] += d - d * xmf
                acc[row + x0i + 1] += d * xmf
            else:
                s = 1.0 / (xb - xa)
                fx0 = xa - x0f
                a0 = 0.5 * s * (1.0 - fx0) * (1.0 - fx0)
                fx1 = xb - x1c + 1.0
                am = 0.5 * s * fx1 * fx1
                acc[row + x0i] += d * a0
                if x1i == x0i + 2:
                    acc[row + x0i + 1] += d * (1.0 - a0 - am)
                else:
                    a1 = s * (1.5 - fx0)
                    acc[row + x0i + 1] += d * (a1 - a0)
                    for xi in range(x0i + 2, x1i - 1):
                        acc[row + xi] += d * s
                    a2 = a1 + (x1i - x0i - 3) * s
                    acc[row + x1i - 1] += d * (1.0 - a2 - am)
                acc[row + x1i] += d * am
            x = xn
            y += 1
    a = np.array(acc, dtype=np.float64).reshape(h + 1, W)[:h]
    a = np.cumsum(a, axis=1)[:, 1:w + 1]
    return np.clip(np.abs(a), 0.0, 1.0)


def render(svg_path, scale, size=None, offset=(0.0, 0.0)):
    """Rasterise the SVG at `scale` device px per user unit, its origin at
    `offset` (device px, may be fractional) on a canvas of `size` (default:
    the SVG size times scale, rounded up).  -> (premultiplied float RGB in
    0..255 as an HxWx3 array, alpha 0..1 HxW, [(rgb, coverage)])."""
    w, h, fills = load(svg_path)
    if size is None:
        size = (int(math.ceil(w * scale - 1e-9)), int(math.ceil(h * scale - 1e-9)))
    cw, ch = size
    prem = np.zeros((ch, cw, 3))
    alpha = np.zeros((ch, cw))
    layers = []
    for rgb, m, subs in fills:
        lines = []
        for sp in subs:
            for seg in sp:
                _flatten(seg, m, scale, offset[0], offset[1], lines)
        cov = coverage(lines, cw, ch)
        layers.append((rgb, cov))
        # premultiplied "over", in the encoded (sRGB) values like the GPU
        # and Core Animation blend
        prem = prem * (1.0 - cov[..., None]) + cov[..., None] * np.array(rgb, dtype=np.float64)
        alpha = alpha * (1.0 - cov) + cov
    return prem, alpha, layers


def to_straight_rgba(prem, alpha, bleed=True):
    """Straight 8-bit RGBA: colour = premultiplied / alpha (exactly the fill
    colour for a single fill), alpha rounded; transparent pixels take the
    colour of the nearest covered pixel (alpha bleed) when `bleed`."""
    a8 = np.rint(alpha * 255.0).astype(np.uint8)
    with np.errstate(invalid='ignore', divide='ignore'):
        rgb = np.where(alpha[..., None] > 0, prem / np.maximum(alpha[..., None], 1e-12), 0.0)
    rgb = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    if bleed:
        rgb = _bleed(rgb, a8 > 0)
    return np.dstack([rgb, a8])


def _bleed(rgb, known, rings=16):
    """Give unknown (transparent) pixels the colour of nearby known pixels,
    one ring at a time for `rings` px (enough for bilinear sampling and the
    first four mip levels); anything further gets the mean known colour."""
    rgb = rgb.copy()
    known = known.copy()
    if not known.any():
        return rgb
    mean = rgb[known].mean(0)
    for _ in range(rings):
        if known.all():
            break
        acc = np.zeros(rgb.shape, dtype=np.int64)
        cnt = np.zeros(known.shape, dtype=np.int64)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                k = np.roll(np.roll(known, dy, 0), dx, 1)
                acc += np.roll(np.roll(rgb, dy, 0), dx, 1).astype(np.int64) * k[..., None]
                cnt += k
        new = (~known) & (cnt > 0)
        rgb[new] = (acc[new] // cnt[new][:, None]).astype(np.uint8)
        known |= new
    rgb[~known] = np.rint(mean).astype(np.uint8)
    return rgb
