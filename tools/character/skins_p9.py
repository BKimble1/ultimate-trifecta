"""Pass 9: the two complete character skins of Season 1 (premium track).

    record_breaker  'rb_head' + 'rb_hair' + 'rb_body'
    dr_doom         'dd_head' + 'dd_fringe' + 'dd_suit'

A complete skin replaces the whole runner, not only the clothes: each has
its own head (face, eyes with real lids, brows, nose, mouth, ears) with its
own face shape keys, its own hair, and its own body with its footwear and
hands.  CharacterView draws these parts instead of `base` and the player's
hair, hat, shoes and marks (Cosmetics.COMPLETE_SKINS) and drives the
expressions on the head that is shown.

Both are likenesses translated into the game's rounded style: the shared
head surface (rig.HEAD_*) is reshaped by a smooth displacement field
(HeadShape) and every head-fitted piece (features, hair, fringe, ears) is
built on the shared surface and carried by the same field, so they all fit
the reshaped head.  Faces are made of the game's own pieces (domed eye
whites, glossy irises with catch-lights, lash lines, sculpted brows, nose
and mouth forms), never a picture.

Face shape keys (same names and order as build_character.SHAPE_KEYS):
features are *parametric*: each moving vertex keeps a function of a small
parameter set (lid edges, brow offsets, mouth width / lift / opening, cheek
raise), so a key is the same construction with other parameters.  The
eyelids are real lids (a skin shell over the eye white whose edge is a
curve; vertices past the edge gather on it), so blinks, squints and the
resting lid line work on these faces.

Skinning follows the established helpers (torso_w, arm_w, leg_w, the V6
boot weights for footwear, the base mitten's forearm/hand weights); head
parts are rigid on the head; nothing is simulated (the tie is skinned to
the chest and spine, so its motion is the body's, bounded).  One shared
material: classes skin, cloth, satin, rubber/leather, metal, gloss, lit.

Original geometry written for this project.  The likenesses were drawn
from the owner's reference pictures; no picture, texture or scan is used
or shipped (the asset has no textures at all).
"""
import math
from mathutils import Vector, Matrix

import rig
from geo import (MeshBuilder, Style, sweep, ellipsoid, lathe, slab, torus_profile, rot_align, rot_x, rot_z, smoothstep, lerp, srgb,
                 T_NONE, T_SKIN, MAT_CLOTH, MAT_SKIN, MAT_RUBBER, MAT_GLOSS, MAT_LIT, MAT_EMIT, MAT_METAL, MAT_SATIN)
from rig import (torso_w, skirt_w, arm_w, leg_w, rigid, torso_r, shoulder, arm_dir, HEAD_C, HEAD_R, TORSO_RY, TORSO_CY,
                 head_point, head_normal)
import parts as P
from parts import UP, FWD, SIDES, _dense_path, _path_s, _foot_outline
import kit6 as K
import outfits_p8 as P8

# the face shape keys, in build_character.SHAPE_KEYS order (asserted there)
FACE_KEYS = ('blink', 'squint', 'smile', 'open', 'brow_up', 'brow_angry', 'face_bright', 'face_sleepy', 'brow_flat')


def S(col, tint=T_NONE, rough=0.85, mat=MAT_CLOTH):
    return Style(col, tint, rough, mat)


def skin(col='#ffffff', rough=0.78):
    """Skin that takes the skin tint (Cosmetics gives a complete skin its own tone)."""
    return Style(col, T_SKIN, rough, MAT_SKIN)


def hsh(*k):
    """Deterministic hash in [0, 1) (no random module: the build stays byte-identical)."""
    s = 0.0
    for i, v in enumerate(k):
        s += v * (12.9898 + 31.7 * i)
    x = math.sin(s) * 43758.5453
    return x - math.floor(x)


def mark(mb, name, i0):
    """Record the vertex range [i0, now) of a named piece (skins_check.py
    tests the layers of a garment with these: build-time only)."""
    if not hasattr(mb, 'groups'):
        mb.groups = {}
    mb.groups[name] = (i0, len(mb.v))


def neck_w(p):
    return rig.seg_weights(p.z, [('neck', 0.93), ('head', None)], 0.03)


HW = rigid('head')


# ================================================================== head shape
class HeadShape:
    """A smooth displacement of the shared head surface: gaussian bumps over
    the direction from the head centre (in head-normalised space).  A bump is
    (direction, sigma, push): push is metres along the surface normal (a
    float) or a vector.  Everything fitted to the head is carried by the same
    field (disp), so features, hair and ears stay on the reshaped surface."""

    def __init__(self, bumps):
        self.bumps = [(Vector(d).normalized(), s, p) for d, s, p in bumps]

    def disp(self, p):
        d = p - HEAD_C
        q = Vector((d.x / HEAD_R[0], d.y / HEAD_R[1], d.z / HEAD_R[2]))
        if q.length < 1e-6:
            return Vector()
        u = q.normalized()
        out = Vector()
        n = None
        for c, sig, push in self.bumps:
            w = math.exp(-(u - c).length_squared / (2.0 * sig * sig))
            if w < 1e-4:
                continue
            if isinstance(push, (int, float)):
                if n is None:
                    n = head_normal(p)
                out += n * (push * w)
            else:
                out += Vector(push) * w
        # the neck stub and the bottom of the head (over the shoulders, where
        # raised arms pass) stay put
        return out * smoothstep(0.93, 1.01, p.z)


# ================================================================== parametric builder
class HeadBuilder(MeshBuilder):
    """MeshBuilder whose vertices may carry a position function of the face
    parameters (pfn[i](params) -> Vector, rest-space, before the head shape)."""

    def __init__(self, name):
        super().__init__(name)
        self.pfn = []

    def vert(self, *a, **k):
        i = super().vert(*a, **k)
        self.pfn.append(None)
        return i

    def vfn(self, fn, P0, style, wfn=HW, uvz=True):
        p = fn(P0)
        i = self.vert(p, style, (0, p.z), wfn(p))
        self.pfn[i] = fn
        return i

    def bind_curve(self, i0, curve, us, P0):
        """Vertices i0.. ride on curve(params, u): each keeps its offset from
        the nearest of the sample points us (at rest)."""
        pts = [curve(P0, u) for u in us]
        for i in range(i0, len(self.v)):
            v = self.v[i]
            j = min(range(len(us)), key=lambda k: (pts[k] - v).length_squared)
            off = v - pts[j]
            self.pfn[i] = (lambda Pm, u=us[j], off=off: curve(Pm, u) + off)

    def bind_offset(self, i0, fn, P0):
        """Vertices i0.. move by fn(params, rest) - fn(P0, rest)."""
        for i in range(i0, len(self.v)):
            rest = self.v[i].copy()
            base = fn(P0, rest)
            self.pfn[i] = (lambda Pm, rest=rest, base=base: rest + (fn(Pm, rest) - base))


def finish_head(mb, shape, P0, deltas):
    """Shape-key targets for FACE_KEYS (each the construction with its own
    parameters), then the head shape applied to the basis and every target
    (the same offset per vertex, so the keys' deltas are unchanged)."""
    targets = {}
    for key in FACE_KEYS:
        Pm = dict(P0)
        for k, dv in deltas.get(key, {}).items():
            Pm[k] = Pm[k] + dv
        targets[key] = [(f(Pm) if f is not None else mb.v[i].copy()) for i, f in enumerate(mb.pfn)]
    for i, f in enumerate(mb.pfn):
        if f is not None:
            assert (f(P0) - mb.v[i]).length < 1e-6, 'parametric vertex %d is not at its rest position' % i
    offs = [shape.disp(v) for v in mb.v]
    for i in range(len(mb.v)):
        mb.v[i] = mb.v[i] + offs[i]
    for key in FACE_KEYS:
        t = targets[key]
        for i in range(len(t)):
            t[i] = t[i] + offs[i]
    mb.shape_targets = targets
    return mb


def reshape(mb, shape):
    """Carry a head-fitted part (hair, fringe) by the head shape."""
    for i in range(len(mb.v)):
        mb.v[i] = mb.v[i] + shape.disp(mb.v[i])
    return mb


# ================================================================== face pieces
def face_grid(mb, rows):
    """Quads between rows that ascend in z, columns that ascend in x: facing
    forward (+Y), out of the face."""
    for r in range(len(rows) - 1):
        a, b = rows[r], rows[r + 1]
        for k in range(len(a) - 1):
            mb.face(a[k], b[k], b[k + 1], a[k + 1])


def fpt(x, z, h=0.0):
    """The front of the (shared) head surface at x, z, raised h along its normal."""
    p = head_point(x, z)
    return p + head_normal(p) * h if h else p


def _surface_z(c, n, q):
    """Height above c along n of the head surface under the point q (local frame)."""
    lo, hi = -0.06, 0.06
    for _ in range(26):
        m = (lo + hi) * 0.5
        if rig._head_F(q + n * m, 0.0) > 1.0:
            hi = m
        else:
            lo = m
    return (lo + hi) * 0.5


def eye(mb, sx, E, P0):
    """Eye white, iris, pupil, catch-lights and real lids.

    E: ex, ez (centre on the face), a, b (half width / height), D (dome),
    iris (radius), iris_col, iris_off (u, v of the iris centre), lash,
    lash_col, lid_col, low_col.  Params: up, low (lid openness at the centre,
    in units of b), tilt (the corners' height, outer corner +)."""
    a, b, D = E['a'], E['b'], E['D']
    p = head_point(E['ex'] * sx, E['ez'])
    n = head_normal(p)
    R = rot_align(n, UP)
    side_v = R @ Vector((1, 0, 0))
    up_v = R @ Vector((0, 1, 0))
    c = p - n * 0.003
    o = 1.0 if side_v.x * sx > 0 else -1.0       # +u = toward the outer corner

    def loc(x, y, z):
        return c + side_v * x + up_v * y + n * z

    sclera = S('#fdfcf8', rough=0.3, mat=MAT_LIT)
    ellipsoid(mb, c, (a, b, D), sclera, HW, segs=20, rings=10, rot=R, cut_below=-0.35, normals=True)
    iu, iv = E.get('iris_off', (-0.05, -0.04))
    ri = E['iris']
    ic = loc(o * iu * a, iv * b, D - 0.0032)
    ellipsoid(mb, ic, (ri, ri * 1.06, 0.0045), S(E['iris_col'], rough=0.2, mat=MAT_GLOSS), HW, segs=18, rings=7, rot=R,
              cut_below=-0.35, normals=True)
    # a darker iris rim (the limbal ring) reads at a distance and in menus
    ring_col = tuple(x * 0.55 for x in srgb(E['iris_col']))
    rp = []
    for k in range(19):
        t = 2 * math.pi * k / 18
        q = ic + side_v * (math.cos(t) * ri * 0.93) + up_v * (math.sin(t) * ri * 1.06 * 0.93)
        rp.append(q + n * 0.0026)
    K.path_tube(mb, rp[:-1], 0.0016, S(ring_col, rough=0.25, mat=MAT_GLOSS), HW, segs=4, hint=n, flat=0.5, closed=True)
    rpu = ri * E.get('pupil', 0.52)
    ellipsoid(mb, loc(o * iu * a, iv * b - 0.0006, D - 0.0012), (rpu, rpu * 1.06, 0.0028), S('#0e0a0b', rough=0.2, mat=MAT_GLOSS),
              HW, segs=16, rings=6, rot=R, cut_below=-0.35, normals=True)
    shine = S('#ffffff', rough=0.1, mat=MAT_EMIT)
    ellipsoid(mb, loc(o * (iu * a + ri * 0.36), iv * b + ri * 0.46, D + 0.0012), (ri * 0.32, ri * 0.34, 0.0013), shine, HW, segs=12,
              rings=4, rot=R, cut_below=-0.35, normals=True)
    ellipsoid(mb, loc(o * (iu * a - ri * 0.38), iv * b - ri * 0.42, D + 0.0008), (ri * 0.13, ri * 0.13, 0.0010), shine, HW, segs=8,
              rings=3, rot=R, cut_below=-0.35, normals=True)

    # ---- lids: a skin shell over the white whose edge is a curve.  Rows
    # below (upper lid) / above (lower lid) the edge gather on it.
    def up_edge(Pm, u):
        return Pm['up'] * math.sqrt(max(0.0, 1.0 - u * u)) + Pm['tilt'] * u

    def low_edge(Pm, u):
        return -Pm['low'] * math.sqrt(max(0.0, 1.0 - u * u)) + Pm['tilt'] * u

    zcache = {}

    def lid_z(x, y, gap):
        rho = math.sqrt((x / a) ** 2 + (y / b) ** 2)
        dome = D * math.sqrt(max(0.0, 1.0 - rho * rho))
        key = (round(x, 5), round(y, 5))
        zh = zcache.get(key)
        if zh is None:
            zh = _surface_z(c, n, c + side_v * x + up_v * y)
            zcache[key] = zh
        return lerp(dome + gap, zh - 0.0035, smoothstep(0.97, 1.24, rho))

    def lid_pt(Pm, u, v, upper):
        if upper:
            vv = max(v, up_edge(Pm, u))
            gap = 0.0040
        else:
            vv = min(v, low_edge(Pm, u))
            gap = 0.0033
        x, y = o * u * a, vv * b
        return loc(x, y, lid_z(x, y, gap))

    def lid_n(u, v):
        # the lid surface's own normal at its (unclamped) place: a vertex
        # gathered on the edge spreads to there when the lid moves
        x, y = o * u * a, v * b
        e = 0.002
        q0 = loc(x, y, lid_z(x, y, 0.004))
        qx = loc(x + e, y, lid_z(x + e, y, 0.004))
        qy = loc(x, y + e, lid_z(x, y + e, 0.004))
        nn = (side_v * 1.0).cross(up_v)
        g = (qx - q0).cross(qy - q0)
        return g.normalized() if g.length > 1e-12 and g.dot(nn) > 0 else -g.normalized() if g.length > 1e-12 else n

    lid_c = Vector(srgb(E.get('lid_col', '#f4ded6')))
    low_c = Vector(srgb(E.get('low_col', '#f7e6e0')))

    def lid_style(u, v, upper):
        # the lid itself a shade darker, blending to the face's own colour
        # where it meets the skin (no ring round the eye)
        rho = math.sqrt(u * u + v * v)
        c = (lid_c if upper else low_c).lerp(Vector((1.0, 1.0, 1.0)), smoothstep(0.75, 1.2, rho))
        return skin(tuple(c))
    for upper, (v0, v1, nv) in ((True, (-0.72, 1.36, 11)), (False, (-1.36, 0.6, 8))):
        us = [lerp(-1.34, 1.34, i / 12.0) for i in range(13)]
        vs = [lerp(v0, v1, j / float(nv - 1)) for j in range(nv)]
        rows = []
        for v in vs:
            row = []
            for u in us:
                fn = (lambda Pm, u=u, v=v, upper=upper: lid_pt(Pm, u, v, upper))
                i = mb.vfn(fn, P0, lid_style(u, v, upper))
                mb.nrm[i] = lid_n(u, v)
                row.append(i)
            rows.append(row)
        # faces outward (toward n): rows ascend in v; u runs along o * side
        for r in range(nv - 1):
            for k in range(len(us) - 1):
                q = [rows[r][k], rows[r][k + 1], rows[r + 1][k + 1], rows[r + 1][k]]
                if o < 0:
                    q.reverse()
                mb.face(*q)

    # ---- the lash line rides the upper lid's edge (a flick past the outer corner)
    lash_us = [lerp(-1.0, 1.0, i / 12.0) for i in range(13)]

    def lash_curve(Pm, u):
        if u <= 1.0:
            x, y = o * u * a, up_edge(Pm, u) * b
            return loc(x, y, lid_z(x, y, 0.0040) + E['lash'] * 0.4)
        # the flick: past the outer corner, rising a little
        x0, y0 = o * a, up_edge(Pm, 1.0) * b
        t = (u - 1.0) / 0.3
        x, y = x0 + o * a * 0.3 * t, y0 + b * 0.10 * t
        return loc(x, y, lid_z(x0, y0, 0.0040) - 0.001 * t)
    us2 = lash_us + [1.12, 1.24]
    i0 = len(mb.v)
    pts = [lash_curve(P0, u) for u in us2]
    rad = []
    for u in us2:
        outness = smoothstep(-0.6, 1.0, u)
        th = E['lash'] * lerp(0.55, 1.15, outness) * (1.0 if u <= 1.0 else lerp(0.8, 0.35, (u - 1.0) / 0.24))
        rad.append((E['lash'] * 0.75, th))
    sweep(mb, pts, rad, S(E.get('lash_col', '#2a1a16'), rough=0.55), HW, segs=6, twist_hint=n)
    mb.bind_curve(i0, lash_curve, us2, P0)
    # a soft lower-lid rim (skin, a touch darker): the lower lid's edge reads
    lo_us = [lerp(-0.92, 0.92, i / 10.0) for i in range(11)]

    def low_curve(Pm, u):
        x, y = o * u * a, low_edge(Pm, u) * b
        return loc(x, y, lid_z(x, y, 0.0033) + 0.0006)
    i0 = len(mb.v)
    sweep(mb, [low_curve(P0, u) for u in lo_us], [(0.0014, lerp(0.0016, 0.0024, math.sin(math.pi * (u + 1) / 2))) for u in lo_us],
          skin(E.get('low_rim', '#e9c3b8')), HW, segs=5, twist_hint=n)
    mb.bind_curve(i0, low_curve, lo_us, P0)
    return {'c': c, 'n': n, 'side': side_v, 'up': up_v, 'o': o}


def brow(mb, sx, B, P0):
    """A sculpted brow on the surface.  B: x0, x1 (inner, outer |x|), z(t)
    (height along it), w(t) (half height), depth, col.  Params: brow_up,
    brow_in (inner end), brow_out (outer end), brow_arch."""
    def curve(Pm, t):
        z = B['z'](t) + Pm['brow_up'] + Pm['brow_in'] * (1.0 - t) ** 1.6 + Pm['brow_out'] * t ** 1.6 \
            + Pm['brow_arch'] * math.sin(math.pi * min(1.0, t * 1.05))
        x = sx * lerp(B['x0'], B['x1'], t)
        return fpt(x, z, B.get('lift', 0.003))
    ts = [i / 10.0 for i in range(11)]
    i0 = len(mb.v)
    pts = [curve(P0, t) for t in ts]
    nn = head_normal(pts[5])
    sweep(mb, pts, [(B['depth'], B['w'](t)) for t in ts], S(B['col'], rough=0.8), HW, segs=8, twist_hint=nn)
    mb.bind_curve(i0, curve, ts, P0)


def nose(mb, N):
    """Bridge, tip and wings (skin, the tip a little warmer)."""
    st = skin(N.get('col', '#ffe6dc'))
    tip = skin(N.get('tip_col', '#ffded2'))
    pts = [fpt(0.0, lerp(N['bridge'][0], N['bridge'][1], i / 6.0), lerp(N['bridge_h'][0], N['bridge_h'][1], i / 6.0)) for i in range(7)]
    sweep(mb, pts, [(lerp(N['bridge_r'][0], N['bridge_r'][1], i / 6.0) * 0.7, lerp(N['bridge_r'][0], N['bridge_r'][1], i / 6.0))
                    for i in range(7)], st, HW, segs=10, twist_hint=FWD, cap_start='round', cap_end='round')
    P._feature(mb, 0.0, N['tip_z'], N['tip_r'], tip, HW, sink=N['tip_sink'], segs=16, rings=10)
    for sx in SIDES:
        P._feature(mb, N['wing_x'] * sx, N['wing_z'], N['wing_r'], st, HW, sink=N['wing_sink'], segs=12, rings=8)
        # the nostril: a small shaded dimple under the wing
        P._feature(mb, N['wing_x'] * 0.62 * sx, N['wing_z'] - N['wing_r'][1] * 0.75, (N['wing_r'][0] * 0.42, N['wing_r'][1] * 0.3, 0.003),
                   skin('#c99486'), HW, sink=0.0, segs=8, rings=4)


def feat(mb, x, z, radii, colfn, sink=0.0, segs=12, rings=6):
    """A small form on the face (under-eye fullness, a chin) whose colour is
    the head's own at each vertex, so it reads as shape, not as a patch."""
    p = head_point(x, z)
    n = head_normal(p)
    ellipsoid(mb, p - n * sink, radii, skin(), HW, segs=segs, rings=rings, rot=rot_align(n, UP), cut_below=-0.35,
              colfn=lambda q, lp: colfn(q, lp) if not isinstance(colfn(q, lp), Style) else colfn(q, lp).col)


def ears(mb, scale=1.0, out_deg=15.0, dz=0.0, inner='#d58f86'):
    """The base ear (parts.build_base), scaled: a body sunk into the head at
    its front edge, its bowl shaded by vertex colour, a helix rim."""
    ear_in = Vector(srgb(inner))
    for sx in SIDES:
        R = rot_z(-out_deg * sx)
        ex = rig.head_side_x(1.165 + dz, 0.0, -0.005)
        ec = Vector(((ex - 0.010 * scale) * sx, -0.007, 1.164 + dz))
        er = (0.036 * scale, 0.053 * scale, 0.07 * scale)

        def ear_col(p, lp, sx=sx, er=er):
            out = smoothstep(0.004, 0.026, lp.x * sx / scale)
            g = math.exp(-((lp.y / scale + 0.004) / 0.03) ** 2 - ((lp.z / scale + 0.004) / 0.044) ** 2) * out
            c = Vector((1.0, 1.0, 1.0)).lerp(ear_in, min(1.0, g * 1.1))
            return (c.x, c.y, c.z)
        ellipsoid(mb, ec, er, skin(), HW, segs=14, rings=10, rot=R, colfn=ear_col)
        hp, hr = [], []
        for i in range(13):
            a = math.radians(lerp(62, 262, i / 12.0))
            ly, lz = er[1] * 0.8 * math.cos(a), er[2] * 0.8 * math.sin(a)
            lx = er[0] * 0.6 * sx
            hp.append(ec + R @ Vector((lx, ly, lz)))
            t = i / 12.0
            hr.append((lerp(0.0075, 0.0105, math.sin(math.pi * min(1.0, t * 1.3))) * scale, 0.0085 * scale))
        sweep(mb, hp, hr, skin(), HW, segs=8, twist_hint=Vector((sx, 0, 0)))


def crease(mb, pts, depth, height, col, wfn=HW):
    """A fine modelled crease (forehead line, smile line, crow's foot): a
    thin skin tube a shade darker, mostly sunk into the face."""
    pts = _dense_path(pts, 0.014)
    m = len(pts)
    nn = head_normal(pts[m // 2])
    rad = [(depth, height * (0.35 + 0.65 * math.sin(math.pi * (i + 0.5) / m))) for i in range(m)]
    sweep(mb, pts, rad, skin(col), wfn, segs=4, twist_hint=nn)


def head_shell(mb, colfn, segs=42, rings=28):
    i0 = len(mb.v)
    ellipsoid(mb, HEAD_C, HEAD_R, skin(), neck_w, segs=segs, rings=rings, power=rig.HEAD_P, colfn=colfn, deform=rig.head_deform(0.0))
    lathe(mb, Vector((0, 0.0, 0)), Matrix.Identity(3), [(0.86, 0.0), (0.865, 0.06), (0.90, 0.066), (0.95, 0.07), (0.97, 0.0)],
          skin(), neck_w, segs=16, ry_scale=0.9)
    return i0


def cheeks(mb, i0, i1, centres, P0, push=0.0065):
    """Head-shell vertices near the cheek centres rise with the 'cheeks'
    param (a smile lifts the cheeks)."""
    for i in range(i0, i1):
        v = mb.v[i]
        if v.y < 0.1:
            continue
        w = 0.0
        for cx, cz, r in centres:
            w = max(w, math.exp(-((v.x - cx) ** 2 + (v.z - cz) ** 2) / (2 * r * r)))
        if w < 0.02:
            continue
        nrm = head_normal(v)
        d = (nrm * 0.55 + UP * 0.8) * (push * w)
        rest = v.copy()
        mb.pfn[i] = (lambda Pm, rest=rest, d=d, c0=P0['cheeks']: rest + d * (Pm['cheeks'] - c0))


def mitten_hands(mb, style):
    """The base mittens (parts.build_base, V7): a wrist neck, a palm tapered
    at the wrist and a thumb branching from its side, on the forearm/hand
    weights.  Complete skins draw their own hands (no `base`)."""
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        d = arm_dir(sx)
        w = rig.wrist(sx)
        R = rot_align(d, FWD)
        X = R @ Vector((1, 0, 0))
        Y = R @ Vector((0, 1, 0))
        hwf = lambda p, sfx=sfx, w=w, d=d: rig.seg_weights((p - w).dot(d), [('forearm' + sfx, 0.0), ('hand' + sfx, None)], 0.012)
        neck = [w + d * t for t in (-0.04, -0.02, 0.0, 0.02, 0.035)]
        sweep(mb, neck, [(0.031, 0.029), (0.031, 0.029), (0.030, 0.028), (0.031, 0.029), (0.032, 0.03)], style,
              lambda p, sv, i, hwf=hwf: hwf(p), segs=14, twist_hint=Y, cap_start=None)

        def palm(lp):
            t = lp.z / 0.065
            narrow = 1.0 - 0.16 * smoothstep(0.1, -1.0, t)
            cup = 0.007 * max(0.0, t) ** 2
            return Vector((lp.x * (1.0 - 0.1 * max(0.0, t)) + cup, lp.y * narrow, lp.z))
        ellipsoid(mb, w + d * 0.058, (0.034, 0.051, 0.065), style, hwf, segs=18, rings=12, rot=R, power=2.3, deform=palm)
        tdir = (d * 0.62 + Y * 0.66 + X * 0.42).normalized()
        t0 = w + d * 0.036 + Y * 0.026 + X * 0.007
        tp = [t0 + tdir * (0.042 * i / 4.0) for i in range(5)]
        sweep(mb, tp, [(lerp(0.0185, 0.0155, i / 4.0),) * 2 for i in range(5)], style, lambda p, sv, i, hwf=hwf: hwf(p), segs=12,
              twist_hint=X, cap_start=None)


# ================================================================== RECORD BREAKER: head
RB_SHAPE = HeadShape([
    ((0.0, 0.76, -0.65), 0.20, (0.0, 0.006, -0.009)),     # a longer, rounded chin
    ((0.72, 0.32, -0.62), 0.25, -0.011),                   # a softly defined jaw (narrower lower face)
    ((-0.72, 0.32, -0.62), 0.25, -0.011),
    ((0.58, 0.68, -0.20), 0.20, 0.005),                    # full cheeks
    ((-0.58, 0.68, -0.20), 0.20, 0.005),
    ((0.90, 0.20, 0.36), 0.25, -0.006),                    # temples
    ((-0.90, 0.20, 0.36), 0.25, -0.006),
    ((0.0, 0.70, 0.70), 0.30, 0.004),                      # forehead
])
RB_EYE = {'ex': 0.101, 'ez': 1.170, 'a': 0.045, 'b': 0.047, 'D': 0.011, 'iris': 0.027, 'iris_col': '#6f6a3e',
          'iris_off': (-0.06, -0.02), 'pupil': 0.5, 'lash': 0.0030, 'lash_col': '#3a2518', 'lid_col': '#f5e0d8',
          'low_col': '#f8e8e2', 'low_rim': '#efcfc5'}
RB_P0 = {'up': 0.46, 'low': 0.66, 'tilt': 0.05, 'brow_up': 0.0, 'brow_in': 0.0, 'brow_out': 0.0, 'brow_arch': 0.0,
         'mw': 0.070, 'lift': 0.013, 'depth': 0.026, 'open': 0.0, 'teeth': 0.74, 'cheeks': 0.25}
RB_KEYS = {
    'blink': {'up': -0.86, 'low': -0.20},
    'squint': {'up': -0.36, 'low': -0.48, 'cheeks': 0.5},
    'smile': {'mw': 0.008, 'lift': 0.010, 'depth': 0.006, 'cheeks': 0.75, 'low': -0.12},
    'open': {'open': 0.024, 'mw': -0.007, 'lift': -0.007, 'up': 0.06},
    'brow_up': {'brow_up': 0.020, 'up': 0.10},
    'brow_angry': {'brow_in': -0.013, 'brow_out': 0.004, 'up': -0.06, 'lift': -0.004},
    'face_bright': {'up': 0.22, 'low': 0.10, 'brow_up': 0.010},
    'face_sleepy': {'up': -0.28, 'brow_out': -0.008},
    'brow_flat': {'brow_arch': -0.008},
}


def _rb_mouth(mb, P0):
    """The broad, tooth-showing smile: a wide D whose corners lift, the
    upper teeth across its top, a thin upper lip and a fuller lower lip."""
    zm = 1.058

    def top(Pm, u):
        return zm + 0.004 + Pm['lift'] * u * u

    def bot(Pm, u):
        return top(Pm, u) - (Pm['depth'] + Pm['open']) * (1.0 - u * u) ** 0.75

    def X(Pm, u):
        return u * Pm['mw']
    dark = S('#3d1519', rough=0.9)
    # the mouth's inside (sunk)
    us = [lerp(-1.0, 1.0, i / 18.0) for i in range(19)]
    nv = 6
    rows = []
    for j in range(nv):
        v = j / float(nv - 1)
        row = []
        for u in us:
            fn = (lambda Pm, u=u, v=v: fpt(X(Pm, u), lerp(bot(Pm, u), top(Pm, u), v), 0.0007))
            row.append(mb.vfn(fn, P0, dark))
        rows.append(row)
    face_grid(mb, rows)
    # a tongue low in the mouth (seen when it opens)
    tus = [lerp(-0.55, 0.55, i / 8.0) for i in range(9)]
    rows = []
    for j in range(3):
        v = j / 2.0
        row = []
        for u in tus:
            fn = (lambda Pm, u=u, v=v: fpt(X(Pm, u) * 0.9, lerp(bot(Pm, u * 0.9) + 0.002, lerp(bot(Pm, 0), top(Pm, 0), 0.32), v * 0.9),
                                           0.0011))
            row.append(mb.vfn(fn, P0, S('#d66a72', rough=0.5, mat=MAT_GLOSS)))
        rows.append(row)
    face_grid(mb, rows)
    # upper teeth: a band under the top edge, its own height whatever the jaw does
    tus = [lerp(-0.94, 0.94, i / 16.0) for i in range(17)]
    rows = []
    for j in range(4):
        v = 1.0 - j / 3.0             # rows ascend in z (face_grid)
        row = []
        for u in tus:
            def fn(Pm, u=u, v=v):
                h = Pm['teeth'] * Pm['depth'] * (1.0 - u * u) ** 0.75
                z = top(Pm, u) - 0.0012 - h * v
                return fpt(X(Pm, u) * 0.985, z, 0.0019 - 0.0006 * v)
            col = Vector(srgb('#f1ebdf')).lerp(Vector(srgb('#c9bcaa')), min(1.0, abs(u) ** 3 * 1.2 + v * 0.3))
            row.append(mb.vfn(fn, P0, S(tuple(col), rough=0.4, mat=MAT_LIT)))
        rows.append(row)
    face_grid(mb, rows)
    # lips (skin-toned, rosier)
    lus = [lerp(-1.04, 1.04, i / 16.0) for i in range(17)]

    def ulip(Pm, u):
        uu = max(-1.0, min(1.0, u))
        return fpt(X(Pm, u), top(Pm, uu) + 0.0034 * (1.0 - 0.5 * uu * uu), 0.0012)

    def llip(Pm, u):
        uu = max(-1.0, min(1.0, u))
        return fpt(X(Pm, u) * 0.97, bot(Pm, uu) - 0.0052 * (1.0 - 0.6 * uu * uu), 0.0016)
    for curve, rr, col in ((ulip, (0.0024, 0.0034), '#f3c4ba'), (llip, (0.0036, 0.0058), '#f0b6aa')):
        i0 = len(mb.v)
        pts = [curve(P0, u) for u in lus]
        rad = [(rr[0] * (0.45 + 0.55 * (1.0 - min(1.0, abs(u)) ** 2)), rr[1] * (0.35 + 0.65 * (1.0 - min(1.0, abs(u)) ** 2))) for u in lus]
        sweep(mb, pts, rad, skin(col), HW, segs=8, twist_hint=head_normal(pts[8]))
        mb.bind_curve(i0, curve, lus, P0)
    # smile lines beside the corners (they move out with the smile)
    for sx in SIDES:
        def sl(Pm, t, sx=sx):
            x = sx * (Pm['mw'] + 0.010 + 0.010 * t + 0.004 * Pm['cheeks'])
            z = 1.098 - 0.052 * t + 0.010 * Pm['cheeks'] * (1.0 - t)
            return fpt(x - sx * 0.018 * (1.0 - t) ** 2, z, 0.0008)
        ts = [i / 6.0 for i in range(7)]
        i0 = len(mb.v)
        ts = ts[2:]
        crease(mb, [sl(P0, t) for t in ts], 0.0012, 0.0016, '#f4d8ce')
        mb.bind_curve(i0, sl, ts, P0)


def build_rb_head():
    mb = HeadBuilder('rb_head')
    P0 = RB_P0

    def col(p, lp):
        c = Vector((1.0, 1.0, 1.0))
        for sx in SIDES:
            d2 = (p.x - 0.165 * sx) ** 2 + (p.z - 1.095) ** 2
            bl = math.exp(-d2 / (2 * 0.042 ** 2)) * (1.0 if p.y > 0.05 else 0.0)
            c = c.lerp(Vector(srgb('#ffb5aa')), bl * 0.55)
        # a faint warmth on the nose and chin
        dn = (p.x ** 2 + (p.z - 1.11) ** 2)
        c = c.lerp(Vector(srgb('#ffcfc4')), math.exp(-dn / (2 * 0.03 ** 2)) * 0.4 * (1.0 if p.y > 0.1 else 0.0))
        return (c.x, c.y, c.z)
    i0 = head_shell(mb, col)
    i1 = len(mb.v)
    cheeks(mb, i0, i1, [(0.15, 1.10, 0.040), (-0.15, 1.10, 0.040)], P0)
    ears(mb, scale=1.0, out_deg=13.0)
    for sx in SIDES:
        eye(mb, sx, RB_EYE, P0)
        brow(mb, sx, {'x0': 0.040, 'x1': 0.152, 'z': lambda t: 1.236 + 0.008 * math.sin(math.pi * t * 0.9) - 0.010 * t,
                      'w': lambda t: lerp(0.0100, 0.0062, t) * (0.8 + 0.2 * math.sin(math.pi * min(1.0, t * 1.3))),
                      'depth': 0.0048, 'col': '#5d3d26', 'lift': 0.0026}, P0)
    nose(mb, {'bridge': (1.195, 1.122), 'bridge_h': (-0.004, 0.009), 'bridge_r': (0.010, 0.0155), 'tip_z': 1.112,
              'tip_r': (0.023, 0.021, 0.022), 'tip_sink': 0.004, 'wing_x': 0.021, 'wing_z': 1.103, 'wing_r': (0.0125, 0.011, 0.011),
              'wing_sink': 0.006, 'col': '#ffe6dc', 'tip_col': '#ffdcd0'})
    _rb_mouth(mb, P0)
    return finish_head(mb, RB_SHAPE, P0, RB_KEYS)


# ================================================================== DR. DOOM: head
DD_SHAPE = HeadShape([
    ((0.58, 0.62, -0.42), 0.28, 0.020),                    # broad, full lower cheeks and jowls (forward of the shoulders)
    ((-0.58, 0.62, -0.42), 0.28, 0.020),
    ((0.48, 0.82, -0.16), 0.20, 0.008),                    # the apples of the cheeks (they round the smile)
    ((-0.48, 0.82, -0.16), 0.20, 0.008),
    ((0.84, 0.36, -0.42), 0.24, 0.006),                    # a broader jaw: wider below than at the temples
    ((-0.84, 0.36, -0.42), 0.24, 0.006),
    ((0.0, 0.72, -0.68), 0.20, (0.0, 0.007, -0.004)),      # a soft, rounded chin
    ((0.0, -0.10, 1.0), 0.36, 0.010),                      # a high, rounded crown
    ((0.0, 0.75, 0.62), 0.30, 0.006),                      # a broad forehead
    ((0.90, 0.20, 0.30), 0.25, -0.008),
    ((-0.90, 0.20, 0.30), 0.25, -0.008),
])
DD_EYE = {'ex': 0.100, 'ez': 1.170, 'a': 0.041, 'b': 0.041, 'D': 0.010, 'iris': 0.0235, 'iris_col': '#6d8399',
          'iris_off': (-0.04, -0.01), 'pupil': 0.5, 'lash': 0.0024, 'lash_col': '#3b2a24', 'lid_col': '#f2d9d0',
          'low_col': '#f6e3dc', 'low_rim': '#eac6bb'}
# Warm and amused at rest: open upper lids (up), lower lids lifted by the
# smile (low), level corners; a wide closed smile whose corners turn up.
DD_P0 = {'up': 0.40, 'low': 0.33, 'tilt': 0.03, 'brow_up': 0.0, 'brow_in': 0.0, 'brow_out': 0.0, 'brow_arch': 0.0,
         'mw': 0.082, 'lift': 0.016, 'gap': 0.0, 'asym': 0.003, 'cheeks': 0.35}
DD_KEYS = {
    'blink': {'up': -0.78, 'low': -0.02},
    'squint': {'up': -0.30, 'low': -0.22, 'cheeks': 0.45},
    'smile': {'mw': 0.008, 'lift': 0.009, 'cheeks': 0.65, 'low': -0.12},
    'open': {'gap': 0.020, 'mw': -0.008, 'lift': -0.006, 'up': 0.10},
    'brow_up': {'brow_up': 0.018, 'up': 0.12},
    'brow_angry': {'brow_in': -0.012, 'brow_out': 0.003, 'up': -0.10, 'lift': -0.006},
    'face_bright': {'up': 0.20, 'low': 0.10, 'brow_up': 0.010},
    'face_sleepy': {'up': -0.22, 'brow_out': -0.007},
    'brow_flat': {'brow_arch': -0.006},
}


def _dd_mouth(mb, P0):
    """A warm, closed, slightly knowing smile: a fine dark line whose corners
    lift (one a touch higher), a thin upper lip and a fuller lower lip.  The
    mouth's inside and the upper teeth are folded flat behind the line and
    open with the jaw ('gap')."""
    zm = 1.054

    def line(Pm, u):
        return zm + Pm['lift'] * u * u + Pm['asym'] * (u + 1.0) * 0.5 * u * u

    def top(Pm, u):
        return line(Pm, u) + Pm['gap'] * 0.15 * (1.0 - u * u)

    def bot(Pm, u):
        return line(Pm, u) - Pm['gap'] * (1.0 - u * u) ** 0.8

    def X(Pm, u):
        return u * Pm['mw']
    dark = S('#3d1519', rough=0.9)
    us = [lerp(-1.0, 1.0, i / 16.0) for i in range(17)]
    rows = []
    for j in range(5):
        v = j / 4.0
        row = []
        for u in us:
            fn = (lambda Pm, u=u, v=v: fpt(X(Pm, u), lerp(bot(Pm, u), top(Pm, u), v), 0.0005))
            row.append(mb.vfn(fn, P0, dark))
        rows.append(row)
    face_grid(mb, rows)
    tus = [lerp(-0.8, 0.8, i / 12.0) for i in range(13)]
    rows = []
    for j in range(3):
        v = 1.0 - j / 2.0             # rows ascend in z (face_grid)
        row = []
        for u in tus:
            def fn(Pm, u=u, v=v):
                h = min(0.009, Pm['gap'] * 0.45) * (1.0 - u * u) ** 0.6
                return fpt(X(Pm, u), top(Pm, u) - 0.0008 - h * v, 0.0011)
            row.append(mb.vfn(fn, P0, S('#efe9dc', rough=0.4, mat=MAT_LIT)))
        rows.append(row)
    face_grid(mb, rows)
    lus = [lerp(-1.05, 1.05, i / 16.0) for i in range(17)]

    def cline(Pm, u):
        uu = max(-1.0, min(1.0, u))
        return fpt(X(Pm, u), top(Pm, uu), 0.0002)

    def ulip(Pm, u):
        uu = max(-1.0, min(1.0, u))
        return fpt(X(Pm, u) * 0.97, top(Pm, uu) + 0.0042 * (1.0 - 0.6 * uu * uu), 0.0008)

    def llip(Pm, u):
        uu = max(-1.0, min(1.0, u))
        return fpt(X(Pm, u) * 0.92, bot(Pm, uu) - 0.0060 * (1.0 - 0.6 * uu * uu), 0.0012)
    for curve, rr, col, mat in ((cline, (0.0015, 0.0021), '#7b3b37', 'line'), (ulip, (0.0022, 0.0034), '#f0c2b5', 'skin'),
                                (llip, (0.0038, 0.0056), '#eeb2a4', 'skin')):
        i0 = len(mb.v)
        pts = [curve(P0, u) for u in lus]
        rad = [(rr[0] * (0.45 + 0.55 * (1.0 - min(1.0, abs(u)) ** 2)), rr[1] * (0.4 + 0.6 * (1.0 - min(1.0, abs(u)) ** 2))) for u in lus]
        sweep(mb, pts, rad, S(col, rough=0.6) if mat == 'line' else skin(col), HW, segs=7, twist_hint=head_normal(pts[8]))
        mb.bind_curve(i0, curve, lus, P0)
    # the smile lines (nasolabial folds): from beside each nose wing round
    # the cheek to past the mouth corner, deeper as the cheeks lift; a
    # lighter crest above each (the cheek rolling over the fold)
    for sx in SIDES:
        def sl(Pm, t, sx=sx, h=0.0008):
            x = sx * (0.052 + 0.032 * t + 0.016 * math.sin(math.pi * 0.5 * t) + 0.005 * Pm['cheeks'])
            z = 1.103 - 0.064 * t + 0.008 * Pm['cheeks'] * (1.0 - t)
            return fpt(x, z, h)
        ts = [i / 8.0 for i in range(9)]
        i0 = len(mb.v)
        crease(mb, [sl(P0, t) for t in ts], 0.0026, 0.0036, '#d39e8f')
        mb.bind_curve(i0, sl, ts, P0)

        def crest(Pm, t, sx=sx):
            q = sl(Pm, t, sx, 0.0012)
            return q + Vector((0.0045 * sx, 0.0, 0.0030))
        i0 = len(mb.v)
        crease(mb, [crest(P0, t) for t in ts[1:-1]], 0.0020, 0.0040, '#fff1ec')
        mb.bind_curve(i0, crest, ts[1:-1], P0)

        def cc(Pm, t, sx=sx):
            x = sx * (Pm['mw'] + 0.004 + 0.005 * t)
            z = line(Pm, 1.0) + 0.003 - 0.010 * t
            return fpt(x, z, 0.0006)
        i0 = len(mb.v)
        crease(mb, [cc(P0, t) for t in (0.0, 0.5, 1.0)], 0.0013, 0.0016, '#e6bbad')
        mb.bind_curve(i0, cc, [0.0, 0.5, 1.0], P0)


def build_dd_head():
    mb = HeadBuilder('dd_head')
    P0 = DD_P0

    def col(p, lp):
        c = Vector((1.0, 1.0, 1.0))
        for sx in SIDES:
            d2 = (p.x - 0.17 * sx) ** 2 + (p.z - 1.085) ** 2
            bl = math.exp(-d2 / (2 * 0.05 ** 2)) * (1.0 if p.y > 0.05 else 0.0)
            c = c.lerp(Vector(srgb('#ffaea0')), bl * 0.28)
        # a soft sheen on the bald crown (lower roughness) and a ruddy nose
        if p.z > 1.33:
            return Style(tuple(c), T_SKIN, lerp(0.78, 0.5, smoothstep(1.33, 1.46, p.z)), MAT_SKIN)
        return (c.x, c.y, c.z)
    i0 = head_shell(mb, col)
    i1 = len(mb.v)
    cheeks(mb, i0, i1, [(0.15, 1.085, 0.045), (-0.15, 1.085, 0.045)], P0, push=0.0075)
    ears(mb, scale=1.26, out_deg=24.0, dz=-0.004, inner='#d38377')
    for sx in SIDES:
        eye(mb, sx, DD_EYE, P0)
        # straight, calm, a little heavy, grey-brown; the outer end lifts a
        # touch (no sad inner arch)
        brow(mb, sx, {'x0': 0.040, 'x1': 0.152, 'z': lambda t: 1.229 + 0.006 * math.sin(math.pi * t) + 0.006 * t * t,
                      'w': lambda t: lerp(0.0080, 0.0056, t) * (0.88 + 0.12 * math.sin(math.pi * t)),
                      'depth': 0.0042, 'col': '#94796a', 'lift': 0.0024}, P0)
        # under-eye fullness (the lower lid's smile) and crow's feet
        feat(mb, sx * 0.104, 1.117, (0.032, 0.012, 0.0055), col, sink=0.0025)
        for k, (dz, ang) in enumerate(((0.012, 20.0), (0.0, 0.0), (-0.012, -22.0))):
            x0 = sx * (0.099 + 0.044)
            a = math.radians(ang)
            pts = [fpt(x0 + sx * 0.022 * t * math.cos(a), 1.168 + dz + 0.022 * t * math.sin(a), 0.0006) for t in (0.0, 0.5, 1.0)]
            crease(mb, pts, 0.0011, 0.0015, '#e8bfb1')
    # forehead lines: two long, faint arcs
    for k, z in enumerate((1.318, 1.342)):
        span = 0.090 - 0.012 * k
        pts = [fpt(x, z + 0.009 * (x / span) ** 2, 0.0005) for x in [lerp(-span, span, i / 8.0) for i in range(9)]]
        crease(mb, pts, 0.0010, 0.0015, '#f1d3c8')
    # a large, broad, rounded nose
    nose(mb, {'bridge': (1.185, 1.124), 'bridge_h': (-0.002, 0.013), 'bridge_r': (0.015, 0.025), 'tip_z': 1.106,
              'tip_r': (0.042, 0.035, 0.036), 'tip_sink': 0.005, 'wing_x': 0.040, 'wing_z': 1.094, 'wing_r': (0.024, 0.019, 0.019),
              'wing_sink': 0.006, 'col': '#ffe0d6', 'tip_col': '#ffcdbf'})
    _dd_mouth(mb, P0)
    # a soft chin form
    feat(mb, 0.0, 1.004, (0.034, 0.020, 0.007), col, sink=0.0055, segs=12, rings=6)
    return finish_head(mb, DD_SHAPE, P0, DD_KEYS)


# ================================================================== tables
def table(pts, x):
    """Smooth (cosine-eased) interpolation through (x, y) points."""
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            t = (x - x0) / (x1 - x0)
            t = 0.5 - 0.5 * math.cos(math.pi * t)
            return y0 + (y1 - y0) * t
    return pts[-1][1]


def front(ang):
    """1 at the forehead (ang +-pi), 0 at the back (ang 0)."""
    return 0.5 - 0.5 * math.cos(ang)


# ================================================================== RECORD BREAKER: hair
RB_HAIRLINE = [(0.0, 1.020), (0.8, 1.045), (1.2, 1.100), (1.40, 1.172), (1.55, 1.236), (1.72, 1.226), (1.84, 1.168),
               (1.95, 1.172), (2.05, 1.250), (2.30, 1.330), (2.60, 1.370), (math.pi, 1.386)]
RB_HAIR_ROOT = srgb('#6a4328')
RB_HAIR_MID = srgb('#a67b4e')
RB_HAIR_TIP = srgb('#dcb07a')


def rb_hairline(ang):
    a = abs(ang)
    return table(RB_HAIRLINE, a) + 0.006 * math.sin(7.0 * ang + 0.4) + 0.004 * math.sin(13.0 * ang + 1.0)


def rb_base(a, z):
    """The hair mass's smooth height above the scalp (m), under its clumps
    and locks: fuller on top and at the front, where it is swept up off the
    forehead; full at the sides above the ears; short at the nape.  A
    little fuller on the character's left of the crown (asymmetric)."""
    top = smoothstep(1.21, 1.45, z)
    f = smoothstep(0.30, 0.95, front(a))
    side = math.sin(a) ** 2
    h = 0.005 + 0.024 * top + 0.012 * top * f
    h += 0.022 * side * smoothstep(1.17, 1.30, z) * (1.0 - 0.5 * top)
    h += 0.006 * (1.0 - f) * smoothstep(1.06, 1.26, z) * (1.0 - top)
    h *= 1.0 + 0.12 * smoothstep(0.2, 1.4, a) * top        # a > 0: the character's left
    return h


def rb_fade(a, z):
    """0 at the hairline, 1 where the mass has its full height: a steep rise
    at the front (the swept-up edge), softer at the sides and nape."""
    z0 = rb_hairline(a)
    rise = lerp(0.040, 0.022, smoothstep(0.55, 0.95, front(a)))
    return smoothstep(z0 - 0.002, z0 + rise, z)


def rb_dir(nn, a, z):
    """The direction the mass grows at a scalp point: its normal, turned
    upward and a little back at the front, so the front lifts off the
    forehead instead of jutting over it."""
    f = smoothstep(0.55, 0.95, front(a)) * (1.0 - smoothstep(1.43, 1.48, z))
    return (nn + UP * (1.1 * f) + Vector((0.0, -0.2 * f, 0.0))).normalized()


def _hair_col(t, light, hi=0.0):
    c = Vector(RB_HAIR_ROOT).lerp(Vector(RB_HAIR_MID), smoothstep(0.0, 0.5, t)).lerp(Vector(RB_HAIR_TIP), smoothstep(0.45, 1.0, t) * (0.6 + 0.4 * light))
    c = c.lerp(Vector(RB_HAIR_TIP), 0.25 * hi)
    return (c.x, c.y, c.z)


def _clump(mb, root, nn, tdir, length, width, thick, lift, droop, flick, twist, light, segs=8, npts=7, tip=0.5):
    """One sculpted clump of hair: a wide, flattened lock that leaves the
    scalp at `lift`, follows the head round (`droop`) and flicks its tip up
    and out (`flick`), turning sideways by `twist`; it narrows to a rounded
    tip.  Darker at the root, warm highlights on its upper side and tip."""
    tdir = (tdir - nn * tdir.dot(nn)).normalized()
    side = nn.cross(tdir).normalized()
    # the root sits on the mass (a little sunk), so the clump's body shows
    p = root + nn * (thick * 0.35)
    pts = [root - nn * (thick * 0.6), p.copy()]
    step = length / (npts - 1)
    for i in range(1, npts):
        t = (i - 0.5) / (npts - 1)
        a = lift - droop * t + flick * smoothstep(0.4, 1.0, t) ** 1.4
        d = tdir * math.cos(a) + nn * math.sin(a)
        d = (d + side * math.sin(twist * t) * 0.55).normalized()
        p = p + d * step
        pts.append(p.copy())
    radii = [(thick * 0.8, width * 0.85)]
    for i in range(npts):
        t = i / (npts - 1)
        k = lerp(1.0, tip, smoothstep(0.2, 1.0, t)) * (0.92 + 0.08 * math.sin(math.pi * t))
        radii.append((thick * k, width * k))
    tot = sum((b - a).length for a, b in zip(pts, pts[1:]))

    def colfn(q, sv, a):
        t = max(0.0, min(1.0, sv / max(tot, 1e-6)))
        return _hair_col(t, light, 0.5 + 0.5 * math.cos(a))
    sweep(mb, pts, radii, S('#ffffff', rough=0.62), HW, segs=segs, cap_start=None, cap_end='round', twist_hint=nn, colfn=colfn)


def _rb_flow(q, nn, a, z):
    """Hair flow at q: swept up and back.  Over the top it runs from the
    forehead back toward the crown, at the sides back and down, at the back
    of the head down; a slight lean toward the character's left on top."""
    flow = Vector((0.06, -1.0, -0.15 - 0.85 * (1.0 - smoothstep(1.30, 1.46, z))))
    flow = flow - nn * flow.dot(nn)
    if flow.length < 1e-4:
        flow = Vector((0.0, 0.0, -1.0)) - nn * (-nn.z)
    return flow.normalized()


def _rb_clumps(g):
    """The hair mass's sculpted locks, as a height field: long, overlapping,
    tapering locks laid along the swept-up-and-back flow like shingles
    (each rises from its root, is fullest past its middle and ends in a
    soft point over the next one), larger on top and toward the front,
    smaller at the sides and back.  Each: (root, flow, side, length,
    width, height, bend, wave, light)."""
    out = []
    n = 60
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        zz = 1 - 2 * (i + 0.5) / n
        rr = math.sqrt(max(0.0, 1 - zz * zz))
        th = ga * i
        dv = Vector((rr * math.cos(th), rr * math.sin(th), zz))
        z = HEAD_C.z + dv.z * (HEAD_R[2] + g)
        a = math.atan2(-dv.x, -dv.y)
        if z < rb_hairline(a) - 0.03:
            continue
        q = P._shell_point(a, z, g)
        nn = head_normal(q, g)
        flow = _rb_flow(q, nn, a, z)
        top = smoothstep(1.25, 1.45, z)
        f = smoothstep(0.4, 0.95, front(a))
        sideness = abs(math.sin(a)) * (1.0 - top)
        big = max(top, f * 0.8)
        h = [hsh(i, k) for k in range(11, 19)]
        # each lock turned off the flow and nudged along the scalp (tousled)
        side0 = nn.cross(flow).normalized()
        ang = lerp(-0.45, 0.45, hsh(i, 31))
        flow = (flow * math.cos(ang) + side0 * math.sin(ang)).normalized()
        q = q + side0 * lerp(-0.022, 0.022, hsh(i, 32)) + flow * lerp(-0.022, 0.022, hsh(i, 33))
        ln = lerp(0.115, 0.170, big) * lerp(0.85, 1.15, h[0])
        wd = lerp(0.050, 0.064, big) * lerp(0.85, 1.15, h[1]) * lerp(1.0, 0.85, sideness)
        amp = lerp(0.018, 0.040, big) * lerp(0.8, 1.15, h[2]) * lerp(1.0, 0.75, sideness)
        bend = lerp(-6.0, 6.0, h[3])
        wave = lerp(-0.008, 0.008, h[5])
        side = nn.cross(flow).normalized()
        out.append((q - flow * (ln * 0.45), flow, side, ln, wd, amp, bend, wave, h[4]))
    return out


def build_rb_hair():
    """Full, tousled, wavy medium-brown hair with real volume, swept up and
    back: the hair mass is a shell grown off the scalp (tallest at the
    front, where it lifts off the forehead, full on top and at the sides
    above the ears, short at the nape), sculpted into long wavy clumps that
    lie along the swept-back flow, darker in the hollows and warm on the
    crests.  Lifted clumps along the front edge and over the crown give the
    airy, asymmetric outline, and a few loose locks fall forward over the
    forehead."""
    mb = MeshBuilder('rb_hair')
    g = 0.010
    clumps = []

    def field(q):
        """(extra height, crest 0..1, light) of the clump field at q."""
        acc = 0.0
        crest = 0.0
        light = 0.5
        best = 0.0
        for c, f, sd, ln, wd, amp, bend, wave, lt in clumps:
            d = q - c
            if d.length_squared > 0.045:
                continue
            al = d.dot(f)
            if al < -0.25 * ln or al > ln:
                continue
            u = al / ln
            ac = d.dot(sd) - bend * al * al - wave * math.sin(2.6 * u)
            w = wd * (1.0 - 0.75 * smoothstep(0.35, 1.0, u))          # narrowing to a soft point
            x = ac / max(w, 1e-4)
            if abs(x) >= 1.0:
                continue
            across = (1.0 - x * x) ** 0.6                              # a rounded cross-section
            along = smoothstep(-0.25, 0.35, u) * (1.0 - smoothstep(0.82, 1.0, u)) * (0.7 + 0.3 * u)
            v = amp * across * along
            acc += v ** 8
            if v > best:
                best = v
                crest = (1.0 - abs(x)) ** 0.8 * smoothstep(-0.1, 0.3, u)    # light along the lock's ridge
                light = lt
        return acc ** (1.0 / 8.0), crest, light

    def mass(a, z):
        """(surface point, growth direction, crest, light) of the mass over
        the scalp point at (a, z)."""
        q0 = P._shell_point(a, z, g)
        nn = head_normal(q0, g)
        hgt, crest, light = field(q0)
        fd = rb_fade(a, z)
        dv = rb_dir(nn, a, z)
        return q0 + dv * ((rb_base(a, z) + hgt) * fd), dv, crest * fd, light

    segs, rows = 72, 18
    rz = HEAD_R[2] + g
    ztop = HEAD_C.z + rz * 0.9995
    angs = [-math.pi + 2.0 * math.pi * k / segs for k in range(segs)]
    angs.reverse()
    edge = [rb_hairline(a) for a in angs]
    grid = []
    for r in range(-1, rows):
        row = []
        for a, z0 in zip(angs, edge):
            if r < 0:
                z = z0 + 0.004
                q = P._shell_point(a, z, g - 0.010)
                c = _hair_col(0.05, 0.5)
            else:
                u = r / float(rows)
                t0 = math.acos(max(-1.0, min(1.0, (z0 - HEAD_C.z) / rz)))
                # rows bunch toward the hairline, where the front rises steeply
                uu = u ** 1.25
                z = min(HEAD_C.z + rz * math.cos(t0 * (1.0 - uu)), ztop)
                q, _, crest, light = mass(a, z)
                c = _hair_col(lerp(0.18, 0.42, rb_fade(a, z)), 0.5)
            row.append(mb.vert(q, S('#ffffff', rough=0.66), (0, q.z), HW(q), '', None, c))
        grid.append(row)
    top = Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + rz))
    hgt, crest, light = field(top)
    top = top + Vector((0, 0, rb_base(0.0, top.z) + hgt))
    pole = mb.vert(top, S('#ffffff', rough=0.66), (0, top.z), HW(top), '', None, _hair_col(0.5 + 0.4 * crest, light))
    mb.grid(grid, True, None, pole)

    def scalp_of(p):
        """(a, z) of the scalp point under p (along the ray from the head
        centre), the parameters mass() takes."""
        d = p - HEAD_C
        u = Vector((d.x / HEAD_R[0], d.y / HEAD_R[1], d.z / HEAD_R[2])).normalized()
        return math.atan2(-u.x, -u.y), HEAD_C.z + u.z * (HEAD_R[2] + g)

    def lock(k, a, z, tdir, length, width, thick, rise, flick, twist, npts=7, segs=7, tip=0.25):
        """A sculpted lock laid on the mass from (a, z) along tdir: its
        centreline follows the mass surface, standing `rise` off it in the
        middle, and its tip lifts off by `flick`; it bends sideways by
        `twist` (a wave) and narrows to a soft point."""
        s0, dv0, _, _ = mass(a, z)
        t = tdir - dv0 * tdir.dot(dv0)
        t.normalize()
        step = length / (npts - 1)
        on = [(s0, dv0)]
        p = s0
        for i in range(1, npts):
            u = i / (npts - 1.0)
            side = on[-1][1].cross(t).normalized()
            pn = p + t * step + side * (math.sin(twist * u * math.pi) * 0.35 * step)
            sn, dvn, _, _ = mass(*scalp_of(pn))
            t = sn - p
            t = t - dvn * t.dot(dvn)
            t.normalize()
            p = sn
            on.append((sn, dvn))
        # (the root starts under the mass a step behind the lock and rises
        # out of it at a shallow angle: a root standing straight out of the
        # surface turned through a right angle and folded its inner side)
        t0 = (on[1][0] - s0).normalized()
        path = [s0 - dv0 * (thick * 0.30) - t0 * (step * 0.9)]
        radii = [(thick * 0.6, width * 0.8)]
        for i, (sp, dvp) in enumerate(on):
            u = i / (npts - 1.0)
            hgt = (thick * (0.10 + 0.40 * smoothstep(0.0, 0.35, u)) + rise * smoothstep(0.0, 0.55, u) * (1.0 - 0.45 * smoothstep(0.6, 1.0, u))
                   + flick * smoothstep(0.45, 1.0, u) ** 2)
            path.append(sp + dvp * hgt)
            kk = lerp(1.0, tip, smoothstep(0.2, 1.0, u)) * (0.94 + 0.06 * math.sin(math.pi * u))
            radii.append((thick * kk, width * kk))
        # (two smoothing passes over the centreline: where it follows the
        # mass over the swept-up front edge it turns faster than the lock is
        # thick, and the inside of the turn folded)
        for _ in range(2):
            path = [path[0]] + [path[i] * 0.5 + (path[i - 1] + path[i + 1]) * 0.25 for i in range(1, len(path) - 1)] + [path[-1]]
        tot = sum((q1 - q0).length for q0, q1 in zip(path, path[1:]))
        light = 0.45 + 0.55 * hsh(k, 8)

        def colfn(q, sv, ang):
            # from the mass's colour at the root to warm, lighter tips; the
            # lock's upper side catches more light
            return _hair_col(lerp(0.32, 1.0, max(0.0, min(1.0, sv / max(tot, 1e-6)))), light, 0.5 + 0.5 * math.cos(ang))
        sweep(mb, path, radii, S('#ffffff', rough=0.62), HW, segs=segs, cap_start=None, cap_end='round',
              twist_hint=on[len(on) // 2][1], colfn=colfn)

    def at_x(x):
        a = math.pi - math.asin(max(-0.95, min(0.95, x / 0.30)))
        return a - 2 * math.pi if a > math.pi else a
    BACK = Vector((0.0, -1.0, 0.0))
    S10 = dict(segs=9, npts=8)
    # the swept-up front: chunky locks that rise off the hairline and roll
    # back over the top, their tips lifting
    for k, (x, ln, lean, w) in enumerate(((-0.165, 0.150, -0.45, 0.060), (-0.085, 0.185, -0.20, 0.070), (0.0, 0.195, 0.02, 0.072),
                                          (0.085, 0.185, 0.22, 0.070), (0.165, 0.150, 0.45, 0.060))):
        a = at_x(x)
        h = [hsh(k, j) for j in range(51, 56)]
        lock(k, a, rb_hairline(a) + 0.004, Vector((lean, -1.0, 0.0)), ln * lerp(0.94, 1.06, h[0]), w, 0.032,
             lerp(0.030, 0.040, h[2]), lerp(0.028, 0.040, h[3]), lerp(-0.35, 0.35, h[4]), tip=0.35, **S10)
    # over the top and crown: locks swept back, tips lifting up and out
    for i, (a, z, ln, w) in enumerate(((2.65, 1.455, 0.160, 0.066), (-2.60, 1.452, 0.155, 0.064), (2.05, 1.448, 0.150, 0.064),
                                       (-2.00, 1.445, 0.145, 0.062), (1.40, 1.448, 0.145, 0.064), (-1.35, 1.445, 0.140, 0.062),
                                       (0.75, 1.462, 0.140, 0.064), (-0.75, 1.46, 0.135, 0.062), (0.0, 1.47, 0.135, 0.066))):
        h = [hsh(i, j) for j in range(21, 28)]
        out = Vector((-math.sin(a), -math.cos(a), 0.0)) * 0.30
        lock(20 + i, a, z, BACK + out + Vector((0.0, 0.0, -0.3)), ln * lerp(0.92, 1.08, h[0]), w, 0.029,
             lerp(0.018, 0.026, h[2]), lerp(0.030, 0.044, h[3]), lerp(-0.45, 0.45, h[4]), tip=0.35, **S10)
    # the sides: locks swept back above the ears, tips flicking out
    for i, (a, z, ln) in enumerate(((2.15, 1.345, 0.130), (-2.15, 1.34, 0.125), (1.55, 1.335, 0.125), (-1.55, 1.33, 0.120),
                                    (0.95, 1.335, 0.115), (-0.95, 1.33, 0.115))):
        h = [hsh(i, j) for j in range(61, 68)]
        lock(40 + i, a, z, Vector((0.0, -1.0, -0.55)), ln * lerp(0.92, 1.08, h[0]), lerp(0.054, 0.062, h[1]), 0.025,
             lerp(0.016, 0.022, h[2]), lerp(0.020, 0.030, h[3]), lerp(-0.4, 0.4, h[4]), tip=0.35, segs=8, npts=7)
    # the back: locks falling to the nape, tips turning out
    for i, (a, z) in enumerate(((0.45, 1.37), (-0.45, 1.365), (0.0, 1.30))):
        h = [hsh(i, j) for j in range(71, 78)]
        lock(50 + i, a, z, Vector((0.0, 0.0, -1.0)), lerp(0.110, 0.125, h[0]), lerp(0.058, 0.064, h[1]), 0.024,
             lerp(0.010, 0.014, h[2]), lerp(0.016, 0.024, h[3]), lerp(-0.4, 0.4, h[4]), tip=0.4, segs=8, npts=7)
    # the lower back: shorter locks down to the nape
    for i, a in enumerate((1.30, -1.30, 0.65, -0.65, 0.0)):
        h = [hsh(i, j) for j in range(81, 88)]
        z = 1.255 if abs(a) > 1.0 else 1.22
        lock(55 + i, a, z, Vector((0.0, -0.3, -1.0)), lerp(0.085, 0.100, h[0]), lerp(0.052, 0.060, h[1]), 0.020,
             lerp(0.006, 0.010, h[2]), lerp(0.012, 0.018, h[3]), lerp(-0.4, 0.4, h[4]), tip=0.45, segs=8, npts=6)
    # a loose lock falling forward over the forehead, toward the character's left
    a = at_x(-0.035)
    lock(60, a, rb_hairline(a) + 0.024, Vector((-0.55, 1.0, -1.0)), 0.100, 0.030, 0.014, 0.010, 0.012, 0.5, tip=0.3)
    return reshape(mb, RB_SHAPE)


# ================================================================== DR. DOOM: fringe
DD_LOW = [(0.0, 0.985), (0.7, 1.005), (1.10, 1.075), (1.36, 1.188), (1.60, 1.206), (1.76, 1.170), (1.92, 1.170), (2.06, 1.186),
          (2.16, 1.212), (2.22, 1.250)]
DD_HIGH = [(0.0, 1.250), (0.8, 1.262), (1.2, 1.292), (1.5, 1.322), (1.78, 1.334), (1.98, 1.326), (2.10, 1.306), (2.18, 1.282),
           (2.22, 1.258)]
DD_END = 2.22
FRINGE = [srgb('#a28c78'), srgb('#c3ad97'), srgb('#e6d8c6')]      # warm grey-brown: groove, body, crest


def dd_high(a):
    return table(DD_HIGH, abs(a)) + 0.006 * math.sin(9.0 * a + 0.3) + 0.004 * math.sin(17.0 * a + 1.1)


# The fringe takes the skin's material class (warm wrap light and a little
# transmission, untinted): fine short hair over the scalp.  As cloth, a
# light grey-brown went charcoal in shadow under the scenes' cool light.
FRINGE_STYLE = Style('#ffffff', T_NONE, 0.8, MAT_SKIN)


def dd_comb(a, f):
    """The combed-hair relief at (a, f) in -1..1: strand groups that run the
    way the hair is combed, back above the ears (grooves along the band)
    and down at the back of the head (grooves across it), with a little
    waver so no groove is ruled straight."""
    ws = smoothstep(0.75, 1.45, abs(a))
    g_side = math.sin(2.0 * math.pi * (f * 4.5) + 0.7 * math.sin(3.0 * a) + 0.4 * math.sin(11.0 * a))
    g_back = math.sin(21.0 * a + 1.4 * f + 0.5 * math.sin(5.0 * f + 2.0 * a))
    return lerp(g_back, g_side, ws)


def dd_thick(a, f):
    """How far the fringe stands off the scalp: a sculpted band, thickest
    over the ears and full at the back, thinning to nothing toward the
    temples; it rises from a defined lower edge and thins into the scalp
    toward its upper edge."""
    aa = abs(a)
    T = (lerp(0.011, 0.019, smoothstep(0.55, 1.40, aa)) + 0.004 * math.exp(-((aa - 1.55) / 0.30) ** 2)) \
        * smoothstep(DD_END, DD_END - 0.75, aa) ** 1.3 + 0.0012
    # (a soft edge at the nape, a fuller one round the ears)
    lo_edge = lerp(0.22, 0.45, smoothstep(0.6, 1.3, aa))
    prof = lerp(lo_edge, 1.0, smoothstep(0.0, 0.26, f)) * (1.0 - smoothstep(0.42, 1.0, f)) ** 0.85
    return T * prof


def build_dd_fringe():
    """Short, combed grey-brown hair at the sides and back (the crown and
    the top of the forehead stay bare): a sculpted band from each temple,
    above and around the ears and round the back of the head, thickest over
    the ears and full at the back, thinning toward the temples and into the
    scalp at its upper edge.  Its relief is combed strand groups (back
    above the ears, down at the back), shaded light on their crests and
    dark in the grooves, with fine strand streaks; feathered tufts break
    the upper edge."""
    mb = MeshBuilder('dd_fringe')
    nc = 64
    nr = 14
    angs = [lerp(-DD_END, DD_END, k / float(nc - 1)) for k in range(nc)]
    rows = []
    for r in range(-1, nr):
        row = []
        for k, a in enumerate(angs):
            lo, hi = table(DD_LOW, abs(a)) + 0.004 * math.sin(13.0 * a + 0.7), dd_high(a)
            hi = max(hi, lo + 0.004)
            f = max(0.0, r) / (nr - 1)
            z = lerp(lo, hi, f) + (0.003 if r < 0 else 0.0)
            comb = dd_comb(a, f)
            gr = dd_thick(a, f) * (1.0 + 0.12 * comb)
            if r == nr - 1:
                gr = -0.0015
            if r < 0:
                gr = -0.0035
            q = P._shell_point(a, z, gr)
            # shading: crests light, grooves dark, darker toward the scalp at
            # both edges, and fine strand streaks along the comb
            ws = smoothstep(0.75, 1.45, abs(a))
            fine = math.sin(lerp(a * 61.0, f * 26.0, ws) + 2.0 * hsh(k // 2, r // 3))
            t = 0.55 + 0.30 * comb + 0.10 * fine
            edge = smoothstep(0.0, 0.18, f) * (1.0 - smoothstep(0.80, 1.0, f))
            c = Vector(FRINGE[0]).lerp(Vector(FRINGE[1]), smoothstep(0.0, 0.55, t)).lerp(Vector(FRINGE[2]), smoothstep(0.55, 1.0, t))
            c = Vector(FRINGE[0]).lerp(c, lerp(0.45, 1.0, edge))
            row.append(mb.vert(q, FRINGE_STYLE, (0, q.z), HW(q), '', None, (c.x, c.y, c.z)))
        rows.append(row)
    for r in range(len(rows) - 1):
        a_, b_ = rows[r], rows[r + 1]
        for k in range(nc - 1):
            # columns run from the right temple round the back to the left one
            # (clockwise seen from above): this winding faces out
            mb.face(a_[k], b_[k], b_[k + 1], a_[k + 1])
    # feathered tufts break the upper edge, lying the way the hair is combed
    for k in range(30):
        a = lerp(-DD_END + 0.16, DD_END - 0.16, (k + 0.5) / 30.0) + 0.025 * math.sin(k * 2.7)
        lo = table(DD_LOW, abs(a))
        hi = dd_high(a) - lerp(0.003, 0.012, hsh(k, 2))
        f = (hi - lo) / max(0.004, dd_high(a) - lo)
        gt = dd_thick(a, f) + 0.0006
        q = P._shell_point(a, hi, gt)
        nn = head_normal(q, gt)
        ws = smoothstep(0.75, 1.45, abs(a))
        d = Vector((0.0, -1.0, 0.25 * hsh(k, 5))).lerp(Vector((0.0, -0.3, -1.0)), 1.0 - ws)
        d = (d - nn * d.dot(nn)).normalized()
        L = lerp(0.016, 0.026, hsh(k, 3))
        pts = [q - nn * 0.0025, q + d * L * 0.5 + nn * 0.0020, q + d * L + nn * 0.0006]
        c = Vector(FRINGE[1]).lerp(Vector(FRINGE[2]), 0.35 + 0.5 * hsh(k, 4))
        sweep(mb, pts, [(0.0020, 0.0056), (0.0016, 0.0046), (0.0007, 0.0017)], FRINGE_STYLE.with_col(tuple(c)), HW, segs=4,
              cap_start=None, cap_end='round', twist_hint=nn)
    return reshape(mb, DD_SHAPE)


# ================================================================== bare feet and footwear helpers
SOLE_Z = 0.022
FOOT_W = [(-0.072, 0.012), (-0.066, 0.030), (-0.055, 0.038), (-0.02, 0.043), (0.03, 0.049), (0.08, 0.054), (0.110, 0.055),
          (0.126, 0.048), (0.134, 0.020)]
FOOT_T = [(-0.072, 0.010), (-0.066, 0.023), (-0.055, 0.032), (-0.02, 0.062), (0.01, 0.060), (0.04, 0.049), (0.08, 0.034),
          (0.110, 0.024), (0.126, 0.016), (0.134, 0.008)]


def foot_w(sx):
    """Footwear and foot weights (the V6 boots'): the foot below 11 cm, the shin above."""
    sfx = '.L' if sx < 0 else '.R'
    return lambda p: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03)


def foot_pt(sx, y, phi, lift=0.0):
    """A point on the bare foot's top surface: phi 0 = +x side, pi/2 = top, pi = -x side."""
    cx = rig.HIP_X * sx
    w, t = table(FOOT_W, y), table(FOOT_T, y)
    n = Vector((math.cos(phi) / max(w, 1e-4), 0.0, math.sin(phi) / max(t, 1e-4))).normalized()
    return Vector((cx + w * math.cos(phi), y, SOLE_Z + t * math.sin(phi))) + n * lift, n


def bare_foot(mb, sx, style):
    """A rounded bare foot on a flat sole: a loft (heel to ball, wider at the
    ball, high at the ankle) and five simple toes (the big toe
    on the inside)."""
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    ys = [lerp(-0.068, 0.131, i / 16.0) for i in range(17)]
    nt = 10
    rows = []
    for y in ys:
        ring = []
        for j in range(nt + 1):
            p, _ = foot_pt(sx, y, math.pi * j / nt)
            ring.append(p)
        w = table(FOOT_W, y)
        for j in (1, 2, 3):
            ring.append(Vector((cx - w + 2 * w * j / 4.0, y, SOLE_Z)))
        ring.reverse()
        rows.append([mb.vert(p, style, (0, p.z), fw(p)) for p in ring])
    ps = Vector((cx, -0.074, SOLE_Z + 0.008))
    pe = Vector((cx, 0.136, SOLE_Z + 0.004))
    mb.grid(rows, True, mb.vert(ps, style, (0, ps.z), fw(ps)), mb.vert(pe, style, (0, pe.z), fw(pe)))
    # five simple toes, the big toe on the inside, standing a little proud of the foot's front
    toes = ((-0.033, 0.150, 0.036, (0.0172, 0.022, 0.0145)), (-0.007, 0.147, 0.033, (0.0112, 0.016, 0.0115)),
            (0.011, 0.140, 0.031, (0.0102, 0.015, 0.0105)), (0.027, 0.131, 0.029, (0.0094, 0.0135, 0.0098)),
            (0.041, 0.119, 0.027, (0.0084, 0.012, 0.0088)))
    for dx, y, z, r in toes:
        ellipsoid(mb, Vector((cx + dx * sx, y, z)), r, style, fw, segs=9, rings=6)
    # the big toe's nail, a touch lighter
    ellipsoid(mb, Vector((cx - 0.033 * sx, 0.160, 0.045)), (0.0090, 0.0095, 0.0022), skin('#fff3ee', rough=0.5), fw, segs=8, rings=4,
              rot=rot_x(-35))


# ================================================================== RECORD BREAKER: body
RB_TORSO = [(0.455, 0.0), (0.462, 0.07), (0.475, 0.125), (0.50, 0.160), (0.53, 0.172), (0.57, 0.172), (0.62, 0.165),
            (0.67, 0.168), (0.72, 0.180), (0.77, 0.190), (0.81, 0.178), (0.84, 0.152), (0.865, 0.113), (0.885, 0.074),
            (0.93, 0.066), (0.96, 0.0)]
RB_RY = 0.82
RB_SKIN_LEG = -0.004       # the leaner legs (under the leg radius)
# The shorts are the game's white: the eye whites' and teeth's lit class
# (a little neutral self-light), not the cloth class.  As cloth, a 0.91
# albedo white took only the scenes' cool ambient and moonlight (plus the
# cloth's blue rim sheen) and read grey-blue in every light, like the other
# cloth whites; measured in docs/pass9/skins.md.  A very rough surface keeps
# the class's specular a broad, soft sheen.
SHORTS = S('#f5f4ef', rough=0.92, mat=MAT_LIT)
SHORTS_BAND = S('#eeede8', rough=0.94, mat=MAT_LIT)
SHORTS_SEAM = S('#d9d7cf', rough=0.94, mat=MAT_LIT)
SANDAL_SOLE = S('#3b2a1f', rough=0.7, mat=MAT_RUBBER)
SANDAL_BED = S('#9b6b43', rough=0.62, mat=MAT_RUBBER)
SANDAL_STRAP = S('#7d4c2b', rough=0.5, mat=MAT_RUBBER)
WRISTBAND = S('#2fc24a', rough=0.42, mat=MAT_RUBBER)


def rb_r(z):
    if z <= RB_TORSO[0][0]:
        return 0.0
    for (z0, r0), (z1, r1) in zip(RB_TORSO, RB_TORSO[1:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return 0.0


def rb_pec(th, z):
    """Soft chest and shoulder-blade forms on the lean torso (extra radius),
    and a flatter front and back below the chest (a lean middle)."""
    zc = math.exp(-((z - 0.775) / 0.045) ** 2)
    out = 0.0
    for c in (math.pi / 2 - 0.55, math.pi / 2 + 0.55):
        out += 0.0030 * zc * math.exp(-((th - c) / 0.55) ** 2)
    flat = smoothstep(0.76, 0.67, z) * smoothstep(0.55, 0.60, z)
    out -= 0.024 * flat * math.sin(th) ** 2
    out -= 0.0015 * math.exp(-((th - math.pi / 2) / 0.12) ** 2) * math.exp(-((z - 0.74) / 0.06) ** 2)
    for c in (-math.pi / 2 - 0.62, -math.pi / 2 + 0.62):
        out += 0.0042 * math.exp(-((z - 0.79) / 0.05) ** 2) * math.exp(-((th - c) / 0.4) ** 2)
    return out


def rb_ang(th, z, grow=0.0):
    r = rb_r(z) + grow + rb_pec(th, z)
    p = Vector((math.cos(th) * r, TORSO_CY + math.sin(th) * r * RB_RY, z))
    dz = (rb_r(z + 0.01) - rb_r(z - 0.01)) / 0.02
    n = Vector((math.cos(th) / r, math.sin(th) / (r * RB_RY), -dz / r)).normalized()
    return p, n


def build_rb_body():
    """Bare, lean upper body (a real skin torso with soft chest and shoulder
    forms, shoulders, arms, hands), white athletic boxer-style shorts, bare
    legs and feet in brown thong sandals, and a green wristband on the
    character's right wrist (+X, '.R')."""
    mb = MeshBuilder('rb_body')
    sk = skin()

    # ---- torso
    def tcol(p, z, th):
        c = 1.0
        front = math.exp(-((th - math.pi / 2) / 0.75) ** 2)
        c -= 0.018 * math.exp(-((z - 0.738) / 0.014) ** 2) * front          # a faint line under the chest
        c -= 0.04 * math.exp(-((th - math.pi / 2) / 0.07) ** 2) * smoothstep(0.66, 0.70, z) * smoothstep(0.75, 0.71, z)
        return (c, c * 0.985, c * 0.98)
    prof = []
    z = 0.565
    while z < 0.885:
        prof.append((z, rb_r(z)))
        z += 0.0155
    prof.append((0.885, rb_r(0.885)))
    i0 = len(mb.v)
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, sk, torso_w, segs=32, ry_scale=RB_RY, colfn=tcol,
          rfn=lambda r, th, z: r + rb_pec(th, z))
    mark(mb, 'torso_skin', i0)
    # navel and collarbones
    p, n = rb_ang(math.pi / 2, 0.650)
    ellipsoid(mb, p - n * 0.0012, (0.0055, 0.0075, 0.0022), skin('#d39b86'), torso_w, segs=10, rings=5, rot=rot_align(n, UP))
    for sx in SIDES:
        pts = []
        for i in range(6):
            t = i / 5.0
            th = math.pi / 2 - sx * lerp(0.12, 0.78, t)
            q, nn = rb_ang(th, lerp(0.868, 0.846, t) + 0.006 * math.sin(math.pi * t))
            pts.append(q + nn * 0.0005)
        sweep(mb, pts, [(0.0022, 0.0046 * (0.5 + 0.5 * math.sin(math.pi * (i + 0.5) / 6))) for i in range(6)], skin('#fbeee8'),
              lambda q, sv, i: torso_w(q), segs=5, twist_hint=FWD)
    # ---- shoulders, arms, hands
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        sh = shoulder(sx)
        # (the shoulder ball takes the weights of the surface under it,
        # torso on the body side and the arm's on the arm side, as the
        # shoulder caps do (parts.shoulder_cap_w): with a fixed 55/45 split
        # it parted from the arm by 1.7 cm with the arms raised)
        ellipsoid(mb, sh + Vector((0.006 * sx, 0.0, -0.006)), (0.058, 0.056, 0.050), sk,
                  lambda q, sx=sx: P.shoulder_cap_w(q, sx), segs=16, rings=10)
        path = P._arm_path(sx, -0.02)
        s = _path_s(path)
        sweep(mb, path, [((P.bare_arm_radius(v - 0.02) * 0.97 + 0.003 * math.exp(-((v - 0.10) / 0.045) ** 2)),) * 2 for v in s], sk,
              lambda q, sv, i, sx=sx: arm_w(q, sx), segs=14, cap_start='round', cap_end='round', twist_hint=FWD)
    mitten_hands(mb, sk)
    # ---- the green wristband: the character's right wrist (+X, '.R')
    d = arm_dir(1)
    s_c = rig.UPPER_LEN + rig.FORE_LEN - 0.034
    sr = P.bare_arm_radius(s_c) * 0.97
    prof = [(-0.0115, sr - 0.002), (-0.011, sr + 0.0035), (-0.0085, sr + 0.0062), (0.0085, sr + 0.0062), (0.011, sr + 0.0035),
            (0.0115, sr - 0.002)]
    lathe(mb, shoulder(1) + d * s_c, rot_align(d, FWD), prof, WRISTBAND, lambda q: arm_w(q, 1), segs=22)
    # ---- legs and feet
    for sx in SIDES:
        # (the leg starts inside the shorts' leg, 6 cm above the hem: nothing
        # hidden under the seat that a stride could push through it)
        pts = K._clip_leg(rig.leg_path(sx, 0.55), 0.45, rig.ANKLE_Z)
        k_, a_ = rig.knee(sx), rig.ankle(sx)
        pts.append(a_ + (a_ - k_).normalized() * 0.028)
        pts = _dense_path(pts, 0.024)
        rad = []
        for q in pts:
            ls = rig.leg_s(q, sx)
            r = P.leg_radius(min(ls, 0.43)) + RB_SKIN_LEG
            r += 0.004 * math.exp(-((ls - 0.29) / 0.05) ** 2)                    # calf
            r = lerp(r, 0.040, smoothstep(0.39, 0.45, ls))                       # into the ankle
            rad.append((r, r * 0.95))
        i0 = len(mb.v)
        sweep(mb, pts, rad, sk, lambda q, sv, i, sx=sx: leg_w(q, sx), segs=16, cap_start=None, cap_end='round', twist_hint=FWD)
        mark(mb, 'leg_skin' + ('.L' if sx < 0 else '.R'), i0)
        bare_foot(mb, sx, sk)
        _sandal(mb, sx)
    _boxer_shorts(mb)
    return mb


def _sandal(mb, sx):
    """Brown thong sandal: a dark sole, a lighter footbed, a toe post between
    the big toe and the next, and two raised straps over the foot to the
    sides of the footbed."""
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, heel=-0.088, toe=0.190, w_heel=0.056, w_toe=0.074, n=26), 0.0, 0.011, SANDAL_SOLE, fw, bevel=0.004)
    slab(mb, _foot_outline(sx, heel=-0.085, toe=0.187, w_heel=0.054, w_toe=0.072, n=26), 0.010, SOLE_Z, SANDAL_BED, fw, bevel=0.004)
    xp = cx - 0.0200 * sx
    yp = 0.128
    sweep(mb, [Vector((xp, yp + 0.002, 0.016)), Vector((xp, yp, 0.030)), Vector((xp, yp - 0.003, 0.043))],
          [(0.0040, 0.0040)] * 3, SANDAL_STRAP, lambda q, sv, i: fw(q), segs=8, cap_start=None, cap_end='round', twist_hint=FWD)
    w0 = table(FOOT_W, yp - 0.006)
    phi0 = math.acos(max(-1.0, min(1.0, (xp - cx) / w0)))
    for phi1 in (0.10, math.pi - 0.10):
        pts, nrm = [], []
        for i in range(10):
            s = i / 9.0
            y = lerp(yp - 0.006, 0.046, s)
            phi = lerp(phi0, phi1, smoothstep(0.0, 1.0, s * 1.05))
            q, nn = foot_pt(sx, y, phi, 0.0008)
            pts.append(q)
            nrm.append(nn)
        out = Vector((math.cos(phi1), 0.0, 0.0))
        pts.append(pts[-1] + out * 0.002 + Vector((0, 0, -0.008)))
        nrm.append(nrm[-1])
        K.ribbon(mb, pts, nrm, 0.0095, 0.0030, SANDAL_STRAP, fw, closed=False, segs=6)
    ellipsoid(mb, Vector((xp, yp - 0.004, 0.046)), (0.0075, 0.0085, 0.0052), SANDAL_STRAP, fw, segs=10, rings=6)


def _boxer_shorts(mb):
    """Opaque white athletic boxer-style shorts: a seat that follows the hips,
    legs to mid-thigh that follow the thighs (a little looser toward the
    folded hems), a softly ribbed elastic waistband with a stitched line
    under it, side seams and a front seam."""
    g = 0.016

    prof = [(0.461, 0.0)]
    z = 0.468
    while z < 0.598:
        prof.append((z, rb_r(z) + g))
        z += 0.013
    prof.append((0.598, rb_r(0.598) + g))
    i0 = len(mb.v)
    # (round the torso's real surface: rb_pec flattens the front and back of
    # the lean middle by up to 2.4 cm; on rb_r alone the waist stood 2.6 cm
    # off the belly)
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, SHORTS, torso_w, segs=40, ry_scale=RB_RY,
          rfn=lambda r, th, z: r + rb_pec(th, z))
    mark(mb, 'shorts_seat', i0)
    # the waistband: soft ribs, a rolled top edge and its inside
    zb0, zb1 = 0.590, 0.628
    rbase = lambda z: rb_r(z) + g + 0.002
    prof = [(zb0 - 0.004, rbase(zb0) - 0.003), (zb0, rbase(zb0) + 0.0015), (zb0 + 0.004, rbase(zb0) + 0.0028),
            (zb1 - 0.004, rbase(zb1) + 0.0028), (zb1, rbase(zb1) + 0.0010), (zb1 + 0.0015, rbase(zb1) - 0.003),
            (zb1 - 0.006, rbase(zb1) - 0.0085)]
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, SHORTS_BAND, torso_w, segs=60, ry_scale=RB_RY,
          rfn=lambda r, th, z: r + rb_pec(th, z) + 0.0009 * math.cos(th * 30.0),
          colfn=lambda p, z, th: (0.95, 0.948, 0.94) if math.cos(th * 30.0) < 0 else None)
    # stitched line just under the band
    ring = []
    for k in range(40):
        th = 2 * math.pi * k / 40
        r = rb_r(0.584) + g + 0.0008 + rb_pec(th, 0.584)
        ring.append(Vector((math.cos(th) * r, TORSO_CY + math.sin(th) * r * RB_RY, 0.584)))
    K.path_tube(mb, ring, 0.0011, SHORTS_SEAM, torso_w, segs=3, hint=UP, closed=True)
    # front seam: from the band down and round toward the centre
    pts = []
    for i in range(8):
        t = i / 7.0
        x = 0.014 * (1.0 - t * t)
        z = lerp(0.584, 0.488, t)
        q = Vector((x, TORSO_CY + math.sqrt(max(0.0, (rb_r(z) + g + rb_pec(math.pi / 2, z)) ** 2 - x * x)) * RB_RY + 0.0008, z))
        pts.append(q)
    K.path_tube(mb, pts, 0.0011, SHORTS_SEAM, torso_w, segs=4, hint=FWD)
    # legs, folded hems
    for sx in SIDES:
        # snug at the hip (the leg's top stays inside the seat), easing
        # looser toward the hem
        grow = lambda z: lerp(0.002, 0.013, smoothstep(0.55, 0.47, z)) + 0.007 * smoothstep(0.45, 0.39, z)
        i0 = len(mb.v)
        poly, radii = K.leg_tube(mb, sx, 0.565, 0.384, grow, SHORTS, segs=20)
        mark(mb, 'shorts_leg' + ('.L' if sx < 0 else '.R'), i0)
        # side seam: down the seat's side, then the leg's outside to the hem
        seam = []
        for z in (0.586, 0.572, 0.558):
            r = rb_r(z) + g + 0.0009 + rb_pec(0.0 if sx > 0 else math.pi, z)
            seam.append(Vector((sx * r, TORSO_CY, z)))
        for q, rr in zip(poly, radii):
            if q.z < 0.545 and q.z > 0.398:
                seam.append(q + Vector((sx * (rr[1] + 0.0009), 0.0, 0.0)))
        K.path_tube(mb, seam, 0.0011, SHORTS_SEAM, lambda q, sx=sx: torso_w(q) if q.z > 0.55 else leg_w(q, sx), segs=4, hint=FWD)
        e = poly[-1]
        dd = (poly[-1] - poly[-2]).normalized()
        limb = P.leg_radius(rig.leg_s(e, sx)) + RB_SKIN_LEG
        P._sleeve_hem(mb, e, dd, radii[-1][1], limb * 0.96, SHORTS, SHORTS_BAND, 0.011, lambda q, sx=sx: leg_w(q, sx), 20,
                      ry=1.0 / 0.96)


# ================================================================== DR. DOOM: suit
def dd_tw(p):
    """The suit's torso weights: rig.torso_w with a wider hips-to-spine blend
    (0.535-0.665 m instead of 0.56-0.64).  Every layer of the suit (shirt,
    tie, trousers, belt, jacket) uses it, so layers a couple of centimetres
    apart that meet the blend at slightly different heights bend together
    instead of crossing in a crouch."""
    w = torso_w(p)
    if p.z >= 0.665 or p.z <= 0.50:
        return w
    soft = rig.seg_weights(p.z, [('hips', 0.60), ('spine', None)], 0.065)
    # keep torso_w's thigh share (below 0.57) and replace its hips/spine split
    th = {k: v for k, v in w.items() if k.startswith('thigh')}
    rest = 1.0 - sum(th.values())
    out = {k: v * rest for k, v in soft.items()}
    out.update(th)
    return out


SUIT = srgb('#93673f')
SUIT_EDGE = S('#6f4a2d', rough=0.85)
SOCK = S('#3d322b', rough=0.92)
SUIT_LINING = S('#6a4a30', rough=0.6, mat=MAT_SATIN)
SHIRT = srgb('#d6e4f3')
SHIRT_STRIPE = srgb('#93b0d6')
SHIRT_COLLAR = S('#d9e6f4', rough=0.85)
TIE_GOLD = srgb('#f1c54c')
TIE_NAVY = srgb('#28356a')
TIE_LIGHT = srgb('#fbe7ad')
BELT = S('#4a2d1a', rough=0.45, mat=MAT_RUBBER)
BUCKLE = S('#b9b4a8', rough=0.3, mat=MAT_METAL)
HORN = S('#3a2619', rough=0.3, mat=MAT_GLOSS)
SHOE = S('#3f2617', rough=0.26, mat=MAT_GLOSS)
SHOE_SOLE = S('#1f150f', rough=0.7, mat=MAT_RUBBER)
SHOE_SEAM = S('#2b190f', rough=0.4, mat=MAT_GLOSS)


def tweed(p, k=1.0, base=SUIT):
    """A restrained tweed suggestion: per-vertex mottling and the odd warm
    or cool fleck, in vertex colour (no texture, no fine geometry)."""
    h1 = hsh(round(p.x * 211.0), round(p.y * 197.0), round(p.z * 223.0))
    h2 = hsh(round(p.x * 157.0) + 3, round(p.y * 173.0), round(p.z * 149.0))
    c = Vector(base) * (1.0 + 0.05 * k * (h1 - 0.5))
    if h2 > 0.965:
        c = c.lerp(Vector(srgb('#b08660')), 0.18 * k)
    elif h2 < 0.03:
        c = c.lerp(Vector(srgb('#5a3d26')), 0.15 * k)
    return (c.x, c.y, c.z)


def suit_style(p, k=1.0, base=SUIT, rough=0.9):
    return Style(tweed(p, k, base), T_NONE, rough, MAT_CLOTH)


def dd_belly(th, z):
    """A compact, rounder middle (extra radius, mostly in front)."""
    return 0.017 * max(0.0, math.sin(th)) ** 1.5 * math.exp(-((z - 0.645) / 0.075) ** 2) + 0.006 * math.exp(-((z - 0.62) / 0.09) ** 2)


def dd_at(th, z, grow):
    r = max(torso_r(z), 0.06) + grow + dd_belly(th, z)
    p = Vector((math.cos(th) * r, TORSO_CY + math.sin(th) * r * TORSO_RY, z))
    e = 0.004
    r2 = max(torso_r(z + e), 0.06) + grow + dd_belly(th, z + e)
    r1 = max(torso_r(z - e), 0.06) + grow + dd_belly(th, z - e)
    dz = (r2 - r1) / (2 * e)
    n = Vector((math.cos(th) / r, math.sin(th) / (r * TORSO_RY), -dz / r)).normalized()
    return p, n


JACKET_G = 0.036
SHIRT_G = 0.012


def jacket_grow(z):
    return JACKET_G + 0.004 * smoothstep(0.54, 0.45, z) + 0.004 * smoothstep(0.80, 0.86, z)


def jacket_gap(z):
    """Half-angle of the front opening: a V from the collar to the button
    point, then the cutaway curve to the hem."""
    return table([(0.448, 0.66), (0.50, 0.42), (0.55, 0.25), (0.60, 0.165), (0.645, 0.15), (0.72, 0.29), (0.80, 0.46),
                  (0.86, 0.60), (0.888, 0.66)], z)


def jacket_base(z):
    """The jacket's own line below the waist: it hangs over the hips and
    the tops of the trouser legs (a little flare), never pinched in under
    them like the torso's own profile."""
    return max(torso_r(z), 0.196 + 0.028 * smoothstep(0.57, 0.45, z))


def jacket_at(th, z, lift=0.0):
    return dd_at(th, z, jacket_grow(z) + lift + jacket_base(z) - max(torso_r(z), 0.06))


def lower_w(p):
    """One weight field for everything round the hips under the jacket (the
    trousers' seat, the tops of the trouser legs and the jacket's skirt):
    the torso's at the waist, riding more and more on the thighs toward the
    hem, fully in front and at the sides, less at the back.  The layers lie
    one over the other at different radii, so with the same field they bend
    together and none can push through another (skins_check.py measures it
    in every clip)."""
    w = dd_tw(p)
    k = smoothstep(0.60, 0.45, p.z)
    if k <= 0.0:
        return w
    r = max(1e-6, math.hypot(p.x, (p.y - TORSO_CY) / TORSO_RY))
    ny = (p.y - TORSO_CY) / TORSO_RY / r          # +1 front, -1 back
    k *= lerp(0.4, 0.95, smoothstep(-0.6, 0.4, ny))
    lx = smoothstep(-0.10, 0.10, p.x)
    return rig.mix((w, 1.0 - k), ({'thigh.L': 1.0 - lx, 'thigh.R': lx}, k))


def jw(p):
    """Jacket weights: the torso's above the waist, the hips' field (lower_w)
    below (lower_w is dd_tw above 0.60 m, so this is lower_w).  Pass 9 fit:
    every piece of the suit (shirt, tie, belt, buttons, jacket, trousers)
    uses this one field, so pieces that touch at the waist (the shirt's
    tucked hem in the trousers, a button on the jacket's edge) cannot part:
    on dd_tw they parted by up to 2.2 cm in a splash jump (fit_check)."""
    return lower_w(p)


def ankle_w(sx):
    """The shoes and the trouser hems over them share one field round the
    ankle (the V6 boots' foot weights, which turn into the leg's at the back
    of the ankle: outfits_p8.foot_w), so the hem resting on the shoe and the
    shoe under it move together: with the hem on the leg's weights and the
    shoe on the foot's they parted by 3.5 cm in a hard landing (fit_check)."""
    return P8.foot_w(sx)


def build_dd_suit():
    """Warm brown two-piece suit (shaped jacket with lapels, collar, an open
    front over the shirt, two buttons, flap pockets, a breast pocket and
    cuffs; matching trousers), a pale blue striped shirt with a point
    collar and cuffs, a gold tie with diagonal navy and light stripes, a
    brown belt with a small buckle, polished dark-brown shoes, and hands."""
    mb = MeshBuilder('dd_suit')
    _dd_shirt(mb)
    _dd_tie(mb)
    _dd_trousers(mb)
    _dd_jacket(mb)
    for sx in SIDES:
        _dd_shoe(mb, sx)
    mitten_hands(mb, skin())
    return mb


def _dd_shirt(mb):
    """The shirt where the jacket's opening shows it (its sides are under the
    jacket): crisp vertical pinstripes (each stripe its own band of faces,
    analytic normals so the bands shade as one surface), the point collar
    and the cuffs."""
    span = 0.78
    unit = 0.034
    edges = []
    th = math.pi / 2 - span
    k = 0
    while th < math.pi / 2 + span:
        w = unit * (2.0 if k % 2 == 0 else 0.7)
        edges.append((th, min(th + w, math.pi / 2 + span), k % 2 == 1))
        th += w
        k += 1
    zs = [0.575 + 0.0235 * i for i in range(13)] + [0.876]
    i0 = len(mb.v)
    for th0, th1, stripe in edges:
        col = SHIRT_STRIPE if stripe else SHIRT
        st = Style(col, T_NONE, 0.85, MAT_CLOTH)
        cols = [th0, th1]
        rows = []
        for z in zs:
            row = []
            for t in cols:
                p, n = dd_at(t, z, SHIRT_G - 0.012 * smoothstep(0.84, 0.876, z))
                i = mb.vert(p, st, (0, p.z), lower_w(p))
                mb.nrm[i] = n
                row.append(i)
            rows.append(row)
        for r in range(len(rows) - 1):
            for c in range(len(cols) - 1):
                # th ascends toward -x: seen from the front this winding faces out
                mb.face(rows[r][c], rows[r][c + 1], rows[r + 1][c + 1], rows[r + 1][c])
    mark(mb, 'shirt', i0)
    # the collar band round the neck, and two pointed collar tips over the knot
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.874, 0.092, 0.019, 10), SHIRT_COLLAR,
          lambda p: lower_w(p), segs=26, closed_profile=True, ry_scale=0.92)
    for sx in SIDES:
        cx, cz = 0.042 * sx, 0.846

        def cplace(u, v, cx=cx, cz=cz):
            x = cx + u
            return dd_at(math.pi / 2 - math.atan2(x, 0.24), cz + v, SHIRT_G + 0.0075 + 0.004 * smoothstep(-0.03, 0.03, v))
        tip = [(-0.030 * sx, 0.024), (0.026 * sx, 0.020), (0.022 * sx, -0.004), (0.010 * sx, -0.033), (-0.016 * sx, 0.000)]
        if sx < 0:
            tip.reverse()
        K.decal(mb, tip, cplace, SHIRT_COLLAR, lower_w, lift=0.0, thick=0.003, side_style=S('#b9cbe0', rough=0.85))
    # a placket line and two small buttons below the knot
    for z in (0.79, 0.73):
        p, n = dd_at(math.pi / 2 + 0.035, z, SHIRT_G + 0.001)
        ellipsoid(mb, p, (0.0055, 0.0055, 0.0022), S('#f2f5f8', rough=0.3, mat=MAT_GLOSS), lower_w, segs=8, rings=4, rot=rot_align(n, UP))
    # cuffs out of the jacket sleeves
    for sx in SIDES:
        d = arm_dir(sx)
        s0 = rig.UPPER_LEN + rig.FORE_LEN
        # wide enough to fill the jacket sleeve's opening (seen down the sleeve
        # the cuff shows, not the sleeve's dark lining)
        r = P.arm_radius(s0) + 0.016
        prof = [(-0.060, r - 0.004), (-0.056, r), (-0.004, r + 0.0005), (0.0, r - 0.001), (0.002, r - 0.007), (-0.006, 0.031)]
        lathe(mb, shoulder(sx) + d * (s0 - 0.004), rot_align(d, FWD), prof, SHIRT_COLLAR, lambda q, sx=sx: arm_w(q, sx), segs=18)


def _tie_colour(q):
    """Stripe colour along the tie's diagonal coordinate q (stripe periods)."""
    f = q - math.floor(q)
    if f < 0.56:
        return TIE_GOLD
    if f < 0.74:
        return TIE_NAVY
    if f < 0.83:
        return TIE_GOLD
    return TIE_LIGHT


def _dd_tie(mb):
    """Gold tie with diagonal navy and light stripes.  The blade is built in
    diagonal bands (each stripe its own faces, so its edges are crisp at any
    distance) lying on the shirt; the knot is the same fabric.  Skinned to
    the chest and spine like the shirt under it: it moves with the body and
    nowhere else."""
    z0, L = 0.836, 0.218
    period = 0.027
    slope = 0.95

    def half_w(v):
        return lerp(0.0155, 0.0295, smoothstep(0.0, 0.85, v))

    def v_end(u):
        return 1.0 - 0.11 * abs(u)

    def pos(u, v, lift=0.0050):
        v = max(0.0, min(v_end(u), v))
        x = u * half_w(v)
        z = z0 - v * L
        th = math.pi / 2 - math.atan2(x, 0.24)
        p, n = dd_at(th, z, SHIRT_G + lift)
        return p, n
    us = [lerp(-1.0, 1.0, i / 6.0) for i in range(7)]
    qmin = (0.0 - half_w(1.0) * slope) / period
    qmax = (L + half_w(1.0) * slope) / period
    bounds = []
    q = math.floor(qmin)
    while q < qmax:
        for f in (0.0, 0.56, 0.74, 0.83):
            if qmin <= q + f <= qmax:
                bounds.append(q + f)
        q += 1.0
    bounds = [qmin] + bounds + [qmax]
    i0 = len(mb.v)
    for b0, b1 in zip(bounds, bounds[1:]):
        if b1 - b0 < 1e-6:
            continue
        col = _tie_colour((b0 + b1) * 0.5)
        st = Style(col, T_NONE, 0.5, MAT_SATIN)
        rows = []
        for qq in (b0, b1):
            row = []
            for u in us:
                v = (qq * period - u * half_w(0.6) * slope) / L
                p, n = pos(u, v)
                i = mb.vert(p, st, (0, p.z), lower_w(p))
                mb.nrm[i] = n
                row.append(i)
            rows.append(row)
        for c in range(len(us) - 1):
            mb.face(rows[0][c], rows[0][c + 1], rows[1][c + 1], rows[1][c])
    mark(mb, 'tie_blade', i0)
    # the blade's edges: a thin wall down to the shirt
    for side in (-1.0, 1.0):
        vs = [i / 30.0 for i in range(31)]
        top = [pos(side, v)[0] for v in vs]
        bot = [pos(side, v, 0.0005)[0] for v in vs]
        ti = [mb.vert(p, Style(_tie_colour((v * L + side * half_w(v) * slope) / period), T_NONE, 0.5, MAT_SATIN), (0, p.z), lower_w(p))
              for p, v in zip(top, vs)]
        bi = [mb.vert(p, Style(TIE_GOLD, T_NONE, 0.5, MAT_SATIN), (0, p.z), lower_w(p)) for p in bot]
        for k in range(30):
            if side > 0:
                mb.face(ti[k], bi[k], bi[k + 1], ti[k + 1])
            else:
                mb.face(ti[k], ti[k + 1], bi[k + 1], bi[k])
    # the knot: a tapered block of the same fabric, stripes running across it
    p, n = dd_at(math.pi / 2, 0.851, SHIRT_G + 0.006)
    R = rot_align(n, UP)

    def kd(lp):
        t = (lp.z + 0.016) / 0.032
        return Vector((lp.x * lerp(1.0, 0.62, t), lp.y, lp.z))
    def knot_col(q, lp):
        d = (q.z - 0.851) + q.x * 0.9
        if abs(d) < 0.0035:
            return TIE_NAVY
        if 0.0035 <= d < 0.0065:
            return TIE_LIGHT
        return TIE_GOLD
    ellipsoid(mb, p, (0.023, 0.012, 0.0185), S('#ffffff', rough=0.5, mat=MAT_SATIN), lower_w, segs=16, rings=10, rot=R @ rot_x(90.0),
              power=2.6, deform=kd, colfn=knot_col)


def _dd_trousers(mb):
    """Matching trousers: a seat over the hips, straight legs with a soft
    front crease that break over the shoes, a belt with loops and a small
    buckle (seen in the jacket's opening)."""
    g = 0.022
    prof = [(0.462, 0.0)]
    z = 0.47
    while z < 0.612:
        # (slimmer under the jacket's skirt, which rides on the thighs: room
        # for a stride; full at the waist, where the opening shows it)
        prof.append((z, max(torso_r(z), 0.06) + g - 0.008 * smoothstep(0.585, 0.53, z)))
        z += 0.0125
    prof.append((0.612, torso_r(0.612) + g))
    i0 = len(mb.v)
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, Style(SUIT, T_NONE, 0.9, MAT_CLOTH), lower_w, segs=30, ry_scale=TORSO_RY,
          colfn=lambda p, z, th: suit_style(p), rfn=lambda r, th, z: r + 0.6 * dd_belly(th, z))
    mark(mb, 'trousers_seat', i0)
    # fly seam
    pts = []
    for i in range(7):
        t = i / 6.0
        x = 0.016 * (1.0 - t * t)
        z = lerp(0.594, 0.50, t)
        th = math.pi / 2 - math.atan2(x, 0.2)
        q, n = dd_at(th, z, g + 0.0009 - 0.4 * dd_belly(th, z))     # on the seat (0.6 of the belly)
        pts.append(q)
    K.path_tube(mb, pts, 0.0012, SUIT_EDGE, lower_w, segs=4, hint=FWD)
    for sx in SIDES:
        def crease(p, sv, a):
            c = suit_style(p, 0.8)
            k = math.exp(-(a / 0.22) ** 2) if a < math.pi else math.exp(-((a - 2 * math.pi) / 0.22) ** 2)
            return Style(tuple(min(1.0, x * (1.0 + 0.07 * k)) for x in c.col), T_NONE, 0.9, MAT_CLOTH)
        grow = lambda z: lerp(0.005, 0.024, smoothstep(0.48, 0.40, z)) - 0.002 * smoothstep(0.30, 0.12, z)
        i0 = len(mb.v)
        # (the legs leave the seat just above the crotch, under the jacket's
        # skirt, which rides on the thighs there: a leg tube reaching up
        # inside the seat would push through it, and the jacket, in a stride)
        poly, radii = K.leg_tube(mb, sx, 0.50, 0.088, grow, Style(SUIT, T_NONE, 0.9, MAT_CLOTH), segs=18, colfn=crease, step=0.03)
        mark(mb, 'trousers_leg' + ('.L' if sx < 0 else '.R'), i0)
        # the leg's top, under the seat and the jacket, joins the hips' field
        for i in range(i0, len(mb.v)):
            k = smoothstep(0.445, 0.475, mb.v[i].z)
            if k > 0.0:
                mb.w[i] = rig.mix((mb.w[i], 1.0 - k), (lower_w(mb.v[i]), k))
        e = poly[-1]
        dd = (poly[-1] - poly[-2]).normalized()
        P._sleeve_hem(mb, e, dd, radii[-1][1], P.leg_radius(rig.leg_s(e, sx)) * 0.96, Style(SUIT, T_NONE, 0.9, MAT_CLOTH), None, 0.012,
                      lambda q, sx=sx: leg_w(q, sx), 18, ry=1.0 / 0.96)
        # a dark sock round the ankle, from inside the shoe to inside the
        # trouser leg: what shows under the hem (the trousers have no leg in
        # them; without it the hem opened onto nothing, 5 cm round the back
        # of the shoe's low heel counter: fit_check "over_shoe")
        K.leg_tube(mb, sx, 0.175, 0.045, -0.001, SOCK, segs=12, step=0.03)
        # the bottom of the leg, its hem and the sock join the ankle's field
        aw = ankle_w(sx)
        for i in range(i0, len(mb.v)):
            k = smoothstep(0.16, 0.12, mb.v[i].z)
            if k > 0.0:
                mb.w[i] = rig.mix((mb.w[i], 1.0 - k), (aw(mb.v[i]), k))
    # belt and buckle
    zb0, zb1 = 0.594, 0.616
    rb = lambda z: max(torso_r(z), 0.06) + g + 0.0035
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), [(zb0 - 0.002, rb(zb0) - 0.004), (zb0, rb(zb0)), (zb1, rb(zb1)),
                                                           (zb1 + 0.002, rb(zb1) - 0.004)], BELT, lower_w, segs=40, ry_scale=TORSO_RY,
          rfn=lambda r, th, z: r + 0.6 * dd_belly(th, z))
    p, n = dd_at(math.pi / 2, 0.605, g + 0.007 + 0.6 * dd_belly(math.pi / 2, 0.605) - dd_belly(math.pi / 2, 0.605))
    R = rot_align(n, UP)
    outer = K.rounded_rect(0.036, 0.026, 0.004)
    inner = K.rounded_rect(0.026, 0.016, 0.003)
    place = K.place_planar(p, n, UP)
    K.decal(mb, outer, place, BUCKLE, lower_w, lift=0.0, thick=0.0035)
    K.decal(mb, inner, place, BELT, lower_w, lift=0.0032, thick=0.0012)
    K.path_tube(mb, [p + R @ Vector((-0.0005, -0.009, 0.0)) + n * 0.005, p + R @ Vector((0.0015, 0.009, 0.0)) + n * 0.005], 0.0016, BUCKLE,
                lower_w, segs=5, hint=n)
    for th in (math.pi / 2 - 0.62, math.pi / 2 + 0.62, -math.pi / 2 - 0.45, -math.pi / 2 + 0.45):
        q0, nn = dd_at(th, 0.590, g + 0.0035 + 0.6 * dd_belly(th, 0.59) - dd_belly(th, 0.59))
        q1, _ = dd_at(th, 0.620, g + 0.0035 + 0.6 * dd_belly(th, 0.62) - dd_belly(th, 0.62))
        K.path_tube(mb, [q0 + nn * 0.004, q1 + nn * 0.004], 0.0038, Style(SUIT, T_NONE, 0.9, MAT_CLOTH), lower_w, segs=6, hint=nn, flat=0.5)


def _dd_jacket(mb):
    """The jacket: a shell over the chest, middle and hips that leaves the
    front open (a V to the button point, then the cutaway to the hem),
    lapels and a collar, a finished front edge and hem with a dark lining
    showing inside, flap pockets, a breast pocket, two horn buttons, and
    sleeves with cuff buttons over the shirt cuffs."""
    # rows every 2 cm, every 1 cm through the hips-to-spine blend (so the faces
    # follow the weights the shirt under them has)
    zs = sorted(set([round(0.448 + 0.0205 * i, 4) for i in range(20)] + [0.4585, 0.4795, 0.4995, 0.52, 0.54, 0.56, 0.575, 0.585, 0.595,
                                                                          0.605, 0.6155, 0.625, 0.645])) + [0.858, 0.872, 0.884]
    segs = 40
    rows = []
    i0 = len(mb.v)
    for z in zs:
        g = jacket_gap(z)
        row = []
        for k in range(segs + 1):
            th = math.pi / 2 + g + (2 * math.pi - 2 * g) * k / segs
            p, n = jacket_at(th, z)
            row.append(mb.vert(p, suit_style(p), (0, p.z), jw(p)))
        rows.append(row)
    mb.grid(rows, closed_u=False)
    mark(mb, 'jacket_shell', i0)
    # facing and lining: the inside of the front edges and of the hem, in shadow
    for side in (0, 1):
        strip = []
        for z in zs[:-2]:
            g = jacket_gap(z)
            th0 = math.pi / 2 + g if side == 0 else math.pi / 2 - g + 2 * math.pi
            th1 = th0 + (0.16 if side == 0 else -0.16)
            a, _ = jacket_at(th0, z, -0.003)
            b, _ = jacket_at(th1, z, -0.006)
            strip.append((mb.vert(a, SUIT_LINING, (0, a.z), jw(a)), mb.vert(b, SUIT_LINING, (0, b.z), jw(b))))
        for k in range(len(strip) - 1):
            (a0, b0), (a1, b1) = strip[k], strip[k + 1]
            if side == 0:
                mb.face(a0, a1, b1, b0)
            else:
                mb.face(a0, b0, b1, a1)
    hem = []
    for k in range(segs + 1):
        g = jacket_gap(zs[0])
        th = math.pi / 2 + g + (2 * math.pi - 2 * g) * k / segs
        a, _ = jacket_at(th, zs[0], -0.003)
        b, _ = jacket_at(th, zs[0] + 0.028, -0.007)
        hem.append((mb.vert(a, SUIT_LINING, (0, a.z), jw(a)), mb.vert(b, SUIT_LINING, (0, b.z), jw(b))))
    for k in range(segs):
        (a0, b0), (a1, b1) = hem[k], hem[k + 1]
        mb.face(a0, b0, b1, a1)
    # a rolled, finished edge round the front opening and the hem
    for side in (1.0, -1.0):
        pts = []
        for z in [zs[0] + 0.002] + zs[1:-2]:
            g = jacket_gap(z)
            p, n = jacket_at(math.pi / 2 + side * g, z, -0.0015)
            pts.append(p)
        K.path_tube(mb, pts, 0.0032, SUIT_EDGE, jw, segs=6, hint=FWD, cap='round')
    pts = []
    for k in range(segs + 1):
        g = jacket_gap(zs[0])
        th = math.pi / 2 + g + (2 * math.pi - 2 * g) * k / segs
        p, n = jacket_at(th, zs[0] + 0.002, -0.0015)
        pts.append(p)
    K.path_tube(mb, pts, 0.0032, SUIT_EDGE, jw, segs=6, hint=UP, cap='round')
    # lapels: from the gorge down to the roll at the top button, notched
    # under the collar, lying on the jacket
    def lapel_place(u, v):
        return jacket_at(u, v, 0.001)
    for side in (1.0, -1.0):
        inner, outer = [], []
        for i in range(13):
            t = i / 12.0
            z = lerp(0.655, 0.852, t)
            g = jacket_gap(z)
            w = 0.052 * math.sin(math.pi * min(1.0, t * 1.15) * 0.92) * (1.0 - 0.45 * smoothstep(0.80, 1.0, t))
            if 0.80 < t < 0.88:
                w *= 0.55       # the notch
            r = jacket_base(z) + jacket_grow(z)
            th_in = math.pi / 2 + side * g
            th_out = th_in + side * (w / r)
            inner.append((th_in, z))
            outer.append((th_out, z))
        o, i_ = (outer, inner) if side > 0 else (list(reversed(outer)), list(reversed(inner)))
        K.strip_decal(mb, o, i_, lapel_place, suit_style(Vector((side, 0.5, 0.7)), 0.6, srgb('#875d38')), lower_w, lift=0.0005,
                      thick=0.0045, sink=0.001)
        # the lapel's edge
        pts = [jacket_at(th, z, 0.0052)[0] for th, z in outer]
        K.path_tube(mb, pts, 0.0024, SUIT_EDGE, lower_w, segs=5, hint=FWD)
    # collar round the back of the neck, folded down
    pts, nrm = [], []
    for k in range(25):
        a = lerp(math.pi / 2 + 0.60, math.pi / 2 - 0.60 + 2 * math.pi, k / 24.0)
        z = 0.883 + 0.006 * math.cos(a - math.pi / 2)
        r = 0.121 + 0.004 * math.cos(a - math.pi / 2)
        p = Vector((math.cos(a) * r, TORSO_CY + math.sin(a) * r * 0.95, z))
        out = Vector((math.cos(a), math.sin(a), 0.0))
        pts.append(p)
        nrm.append((out * 0.75 + UP * 0.66).normalized())
    K.ribbon(mb, pts, nrm, 0.020, 0.0042, S('#875d38', rough=0.9), lower_w, closed=False, segs=8)
    # pockets: flaps at the hips, a breast welt on the left chest
    for side in (1.0, -1.0):
        th = math.pi / 2 + side * 0.80
        place = (lambda u, v, th=th: jacket_at(th + u / 0.27, 0.535 + v, 0.0008))
        K.decal(mb, K.rounded_rect(0.080, 0.028, 0.004), place, suit_style(Vector((side, 0.3, 0.5)), 0.6, srgb('#875d38')), jw, lift=0.0,
                thick=0.004, side_style=SUIT_EDGE)
    place = (lambda u, v: jacket_at(math.pi / 2 + 0.80 + u / 0.25, 0.765 + v, 0.0008))
    K.decal(mb, K.rounded_rect(0.056, 0.011, 0.002), place, suit_style(Vector((0.1, 0.2, 0.3)), 0.6, srgb('#875d38')), lower_w, lift=0.0,
            thick=0.0035, side_style=SUIT_EDGE)
    # two horn buttons on the left front edge
    for z in (0.645, 0.585):
        th = math.pi / 2 + jacket_gap(z) + 0.075
        p, n = jacket_at(th, z, 0.003)
        ellipsoid(mb, p, (0.0105, 0.0105, 0.0035), HORN, jw, segs=12, rings=5, rot=rot_align(n, UP),
                  colfn=lambda q, lp: S('#22160e', rough=0.5) if abs(abs(lp.x) - 0.003) < 0.0016 and abs(abs(lp.y) - 0.003) < 0.0016 else None)
    # sleeves (shoulders fitted by their caps), ending above the shirt cuffs
    P.sleeves(mb, Style(SUIT, T_NONE, 0.9, MAT_CLOTH), 0.026, s1=rig.UPPER_LEN + rig.FORE_LEN - 0.020, cuff_style=None, lod=1)
    _tweed_recolour(mb)
    for sx in SIDES:
        for k in range(2):
            s = rig.UPPER_LEN + rig.FORE_LEN - 0.050 - k * 0.017
            d = arm_dir(sx)
            c = shoulder(sx) + d * s
            out = Vector((sx * 0.4, -0.92, 0.0)).normalized()
            out = (out - d * out.dot(d)).normalized()
            p = c + out * (P.arm_radius(s) + 0.026 + 0.0015)
            ellipsoid(mb, p, (0.0052, 0.0052, 0.0022), HORN, lambda q, sx=sx: arm_w(q, sx), segs=7, rings=3, rot=rot_align(out, d))


def _tweed_recolour(mb):
    """Give the sleeves (built by parts.sleeves in one colour) the tweed."""
    sv = Vector(SUIT)
    for i in range(len(mb.v)):
        c = mb.col[i]
        if c[3] == T_NONE and abs(c[0] - sv.x) < 1e-6 and abs(c[1] - sv.y) < 1e-6 and abs(c[2] - sv.z) < 1e-6:
            t = tweed(mb.v[i])
            mb.col[i] = (t[0], t[1], t[2], c[3])


def _dd_shoe(mb, sx):
    """Polished dark-brown formal shoe: a sleek rounded upper, a darker sole
    with a raised heel, a toe-cap seam, a lacing panel with laces."""
    fw = ankle_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, heel=-0.082, toe=0.192, w_heel=0.053, w_toe=0.064, n=28), 0.0, 0.014, SHOE_SOLE, fw, bevel=0.004)
    heel = [(x, y) for x, y in _foot_outline(sx, heel=-0.080, toe=0.10, w_heel=0.051, w_toe=0.056, n=20) if y < -0.02]
    if len(heel) > 3:
        slab(mb, heel, 0.0, 0.022, SHOE_SOLE, fw, bevel=0.004)

    def upper(lp):
        t = (lp.y + 0.135) / 0.27       # 0 heel .. 1 toe
        hz = lerp(1.0, 0.46, smoothstep(0.35, 1.0, t))
        wx = lerp(0.9, 1.0, smoothstep(0.0, 0.6, t)) * lerp(1.0, 0.86, smoothstep(0.85, 1.0, t))
        return Vector((lp.x * wx, lp.y, lp.z * hz))
    ellipsoid(mb, Vector((cx, 0.054, 0.012)), (0.059, 0.135, 0.090), SHOE, fw, segs=20, rings=12, cut_below=-0.02, deform=upper,
              colfn=lambda p, lp: SHOE.with_col('#4a2d1b') if lp.z > 0.05 and abs(lp.y) < 0.06 else None)
    # toe-cap seam and the lacing panel
    pts = []
    for i in range(11):
        a = math.radians(lerp(20, 160, i / 10.0))
        x = cx + math.cos(a) * 0.058
        y = 0.128
        q = Vector((x, y, 0.012))
        # project onto the upper (search down from above)
        top = 0.0
        for zz in [0.012 + 0.002 * k for k in range(40)]:
            lp = Vector(((x - cx) / 0.059, (y - 0.054) / 0.135, (zz - 0.012) / 0.09))
            t = (y - 0.054 + 0.135) / 0.27
            hz = lerp(1.0, 0.46, smoothstep(0.35, 1.0, t))
            wx = lerp(0.9, 1.0, smoothstep(0.0, 0.6, t)) * lerp(1.0, 0.86, smoothstep(0.85, 1.0, t))
            if ((x - cx) / (0.059 * wx)) ** 2 + ((y - 0.054) / 0.135) ** 2 + ((zz - 0.012) / (0.09 * hz)) ** 2 <= 1.0:
                top = zz
        pts.append(Vector((x, y, top + 0.0012)))
    K.path_tube(mb, pts, 0.0016, SHOE_SEAM, fw, segs=4, hint=UP)
    for k in range(3):
        y = 0.022 + 0.022 * k
        z = 0.012 + 0.090 * math.sqrt(max(0.0, 1.0 - ((y - 0.054) / 0.135) ** 2)) * lerp(1.0, 0.46, smoothstep(0.35, 1.0, (y + 0.081) / 0.27)) + 0.001
        K.path_tube(mb, [Vector((cx - 0.016, y, z - 0.002)), Vector((cx + 0.016, y + 0.003, z - 0.002))], 0.0022, SHOE_SEAM, fw, segs=5,
                    hint=UP, flat=0.6)


# ================================================================== registry
RB_PARTS = [build_rb_head, build_rb_hair, build_rb_body]
DD_PARTS = [build_dd_head, build_dd_fringe, build_dd_suit]
ALL = RB_PARTS + DD_PARTS
## parts whose face shape keys come from their own construction (finish_head)
HEADS = ('rb_head', 'dd_head')


def apply_shape_keys(ob, mb, names):
    """Basis + one key per name, from mb.shape_targets (build_character calls
    this for the HEADS after make_mesh)."""
    assert tuple(names) == FACE_KEYS, 'the heads carry exactly build_character.SHAPE_KEYS'
    assert len(ob.data.vertices) == len(mb.v), 'the mesh kept every vertex (shape keys index them)'
    ob.shape_key_add(name='Basis', from_mix=False)
    for name in names:
        sk = ob.shape_key_add(name=name, from_mix=False)
        t = mb.shape_targets[name]
        for vi in range(len(t)):
            sk.data[vi].co = t[vi]
