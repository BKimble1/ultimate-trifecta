"""Every wearable/body part of the runner, built as MeshBuilders.

Each top-level function returns one MeshBuilder that becomes one glTF mesh
(one draw call in game).  Names must match CharacterView.PART_* in
game/src/view/character_view.gd.
"""
import math
from mathutils import Vector, Matrix
import geo
from geo import (MeshBuilder, Style, sweep, ellipsoid, lathe, slab, torus_profile, rot_align, rot_x, rot_y, rot_z, MAT_LIT,
                 smoothstep, lerp, srgb, T_NONE, T_HAIR, T_SKIN, T_SECOND, T_DARK, T_PRIMARY,
                 MAT_CLOTH, MAT_SKIN, MAT_RUBBER, MAT_GLOSS, MAT_EMIT)
import rig
from rig import (torso_w, skirt_w, arm_w, leg_w, rigid, torso_r, torso_front_y, head_point, head_normal, head_front_y,
                 shoulder, elbow, wrist, arm_dir, hip, knee, ankle, HEAD_C, HEAD_R, HEAD_P, TORSO_RY, TORSO_CY)

UP = Vector((0, 0, 1))
FWD = Vector((0, 1, 0))
SIDES = (-1, 1)

# ------------------------------------------------------------------ styles
SKIN = Style('#ffffff', T_SKIN, 0.78, MAT_SKIN)   # matte, soft sheen (the icon's skin)
CLOTH_P = Style('#ffffff', T_PRIMARY, 0.9, MAT_CLOTH, stripes=True)       # primary cloth, takes stripes
CLOTH_P_PLAIN = Style('#ffffff', T_PRIMARY, 0.9, MAT_CLOTH)
CLOTH_S = Style('#ffffff', T_SECOND, 0.9, MAT_CLOTH)
CLOTH_D = Style('#ffffff', T_DARK, 0.9, MAT_CLOTH)
IVORY = Style('#f4f2ec', T_NONE, 0.5, MAT_GLOSS)
HAIR = Style('#ffffff', T_HAIR, 0.7, MAT_CLOTH)


def _dense_path(points, step=0.02):
    """Resample a polyline with roughly `step` spacing (keeps corners)."""
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        n = max(1, int(math.ceil((b - a).length / step)))
        for i in range(1, n + 1):
            out.append(a.lerp(b, i / n))
    return out


def _arm_path(side, s0=-0.01, s1=None):
    s1 = s1 if s1 is not None else rig.UPPER_LEN + rig.FORE_LEN
    sh = shoulder(side)
    d = arm_dir(side)
    pts = []
    n = int(math.ceil((s1 - s0) / 0.018))
    for i in range(n + 1):
        pts.append(sh + d * (s0 + (s1 - s0) * i / n))
    return pts


def arm_radius(s):
    # shoulder 0.058 -> elbow 0.048 -> wrist 0.04
    e = rig.UPPER_LEN
    if s < e:
        return lerp(0.058, 0.048, smoothstep(0.0, e, s))
    return lerp(0.048, 0.041, smoothstep(e, e + rig.FORE_LEN, s))


def _leg_path(side, top=0.545, bottom_z=None):
    pts = rig.leg_path(side, top)
    if bottom_z is not None:
        k, a = pts[1], pts[2]
        t = (k.z - bottom_z) / (k.z - a.z)
        pts[2] = k.lerp(a, max(0.0, min(1.0, t)))
    return _dense_path(pts, 0.02)


def leg_radius(s):
    kl = (knee(1) - hip(1)).length
    if s < kl:
        return lerp(0.09, 0.07, smoothstep(0.0, kl, s))
    return lerp(0.068, 0.054, smoothstep(kl, kl + 0.22, s))


def _path_s(path):
    s = [0.0]
    for a, b in zip(path, path[1:]):
        s.append(s[-1] + (b - a).length)
    return s


def torso_lathe(mb, style, grow, z0, z1, weightfn=torso_w, extra=None, segs=24, colfn=None, bottom_pole=False,
                top_open_r=None, hem_fold=0.0, flare=0.0):
    """Clothing shell over the torso between z0 and z1 (rest pose)."""
    prof = []
    if hem_fold > 0:
        prof.append((z0 + hem_fold, torso_r(z0 + hem_fold) + grow * 0.3))
    if bottom_pole:
        prof.append((z0 - 0.004, 0.0))
    zs = []
    z = z0
    while z < z1 - 1e-6:
        zs.append(z)
        z += 0.025
    zs.append(z1)
    for i, z in enumerate(zs):
        r = max(torso_r(z), 0.06) + grow
        if flare > 0:
            r += flare * smoothstep(z0 + 0.06, z0, z)
        if extra:
            r += extra(z)
        prof.append((z, r))
    if top_open_r is not None:
        prof.append((z1 + 0.004, top_open_r))
        prof.append((z1 - 0.02, top_open_r - 0.008))
    rot = Matrix.Identity(3)
    return lathe(mb, Vector((0, TORSO_CY, 0)), rot, prof, style, weightfn, segs=segs, ry_scale=TORSO_RY, colfn=colfn)


def _feature(mb, x, z, radii, style, wfn, sink=0.0, grow=0.0, tag='', aux=None, segs=14, rings=10, power=2.0,
             side_tilt=0.0, offset=None):
    """Small ellipsoid sitting on the head surface, oriented along the surface normal."""
    p = head_point(x, z, grow)
    n = head_normal(p, grow)
    R = rot_align(n, UP)
    if side_tilt:
        R = R @ rot_z(side_tilt)
    c = p + n * (-sink)
    if offset is not None:
        c = c + R @ Vector(offset)
    ellipsoid(mb, c, radii, style, wfn, segs=segs, rings=rings, rot=R, power=power, tag=tag, aux=aux, cut_below=-0.35)
    return c, R


# ================================================================== BASE: head, face, hands
def build_base():
    mb = MeshBuilder('base')
    hw = rigid('head')

    def head_col(p, lp):
        # soft blush on the cheeks, slightly warmer lips area
        c = Vector((1.0, 1.0, 1.0))
        for sx in SIDES:
            d2 = (p.x - 0.178 * sx) ** 2 + (p.z - 1.095) ** 2
            b = math.exp(-d2 / (2 * 0.048 ** 2)) * (1.0 if p.y > 0.05 else 0.0)
            c = c.lerp(Vector(srgb('#ffb2ae')), b * 0.75)
        return (c.x, c.y, c.z)

    def neck_w(p):
        return rig.seg_weights(p.z, [('neck', 0.93), ('head', None)], 0.03)

    ellipsoid(mb, HEAD_C, HEAD_R, SKIN, neck_w, segs=36, rings=26, power=HEAD_P, colfn=head_col, deform=rig.head_deform(0.0))
    # neck stub (hidden by collars, visible in swim)
    lathe(mb, Vector((0, 0.0, 0)), Matrix.Identity(3), [(0.86, 0.0), (0.865, 0.06), (0.90, 0.066), (0.95, 0.07), (0.97, 0.0)],
          SKIN, neck_w, segs=16, ry_scale=0.9)
    # ears
    for sx in SIDES:
        R = rot_z(-15 * sx)
        ex = rig.head_side_x(1.165, 0.0, -0.005)
        ellipsoid(mb, Vector(((ex - 0.012) * sx, -0.005, 1.165)), (0.036, 0.05, 0.066), SKIN, hw, segs=14, rings=10, rot=R)
        ellipsoid(mb, Vector(((ex + 0.012) * sx, 0.004, 1.165)), (0.012, 0.031, 0.043), SKIN.with_col('#e9b9b1'), hw, segs=12, rings=8, rot=R)
    # nose
    _feature(mb, 0.0, 1.118, (0.031, 0.024, 0.022), SKIN.with_col('#ffe2d9'), hw, sink=0.008)
    # eyes: sclera, pupil, catch-light.  aux carries the eye frame for the shape keys
    sclera = Style('#fdfcf8', T_NONE, 0.3, MAT_LIT)
    iris = Style('#3a2215', T_NONE, 0.2, MAT_GLOSS)
    pupil = Style('#0d0809', T_NONE, 0.2, MAT_GLOSS)
    shine = Style('#ffffff', T_NONE, 0.1, MAT_EMIT)
    for sx in SIDES:
        ex, ez = 0.106 * sx, 1.162
        p = head_point(ex, ez)
        n = head_normal(p)
        R = rot_align(n, UP)
        side_v = R @ Vector((1, 0, 0))
        up_v = R @ Vector((0, 1, 0))
        inward = Vector((-sx, 0, 0))
        c = p - n * 0.004
        aux = (c.copy(), side_v.copy(), up_v.copy(), n.copy(), sx)
        tag = 'eyeL' if sx < 0 else 'eyeR'
        ellipsoid(mb, c, (0.053, 0.067, 0.02), sclera, hw, segs=20, rings=14, rot=R, tag=tag, aux=aux, cut_below=-0.35)
        pc = c + n * 0.0135 - up_v * 0.006 + inward * 0.004
        ellipsoid(mb, pc, (0.041, 0.051, 0.012), iris, hw, segs=18, rings=12, rot=R, tag=tag, aux=aux, cut_below=-0.35)
        ppc = pc + n * 0.006 - up_v * 0.002
        ellipsoid(mb, ppc, (0.027, 0.034, 0.0068), pupil, hw, segs=14, rings=10, rot=R, tag=tag, aux=aux, cut_below=-0.35)
        hc = pc + n * 0.0105 + up_v * 0.017 - inward * 0.012
        ellipsoid(mb, hc, (0.0145, 0.0155, 0.004), shine, hw, segs=10, rings=6, rot=R, tag=tag, aux=aux, cut_below=-0.35)
        hc2 = pc + n * 0.0095 - up_v * 0.019 + inward * 0.011
        ellipsoid(mb, hc2, (0.006, 0.006, 0.003), shine, hw, segs=8, rings=4, rot=R, tag=tag, aux=aux, cut_below=-0.35)
        # brow: short arched bar on the surface
        bpts = []
        for i in range(7):
            t = i / 6.0
            bx = (0.058 + 0.094 * t) * sx
            bz = 1.252 + 0.015 * math.sin(math.pi * t) - 0.006 * t
            bp = head_point(bx, bz)
            bpts.append(bp + head_normal(bp) * 0.006)
        bc = sum(bpts, Vector()) / len(bpts)
        baux = (bc, (bpts[-1] - bpts[0]).normalized(), up_v.copy(), n.copy(), sx)
        bw = [lerp(0.0072, 0.0052, i / 6.0) * (0.75 + 0.25 * math.sin(math.pi * i / 6.0)) for i in range(7)]
        sweep(mb, bpts, [(w, w * 1.8) for w in bw], HAIR.with_col('#c8c8c8'), hw, segs=8,
              tag='browL' if sx < 0 else 'browR', twist_hint=n)
        for i in range(len(mb.aux)):
            if mb.tag[i] in ('browL', 'browR') and mb.aux[i] is None and ((mb.tag[i] == 'browL') == (sx < 0)):
                mb.aux[i] = baux
    # mouth: dark D-shape (basis = closed smile; shape keys open/smile it) + tongue
    mp = head_point(0.0, 1.072)
    mn = head_normal(mp)
    MR = rot_align(mn, UP)
    mside = MR @ Vector((1, 0, 0))
    mup = MR @ Vector((0, 1, 0))
    mc = mp - mn * 0.003
    maux = (mc.copy(), mside.copy(), mup.copy(), mn.copy(), 0)
    ellipsoid(mb, mc, (0.046, 0.025, 0.008), Style('#5c1f2c', T_NONE, 0.4, MAT_GLOSS), hw, segs=20, rings=10, rot=MR,
              tag='mouth', aux=maux, cut_below=-0.35)
    ellipsoid(mb, mc - mup * 0.010, (0.022, 0.010, 0.005), Style('#ff8a96', T_NONE, 0.4, MAT_GLOSS), hw, segs=12, rings=8,
              rot=MR, tag='tongue', aux=maux)
    # hands (mittens with a thumb), skin
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        d = arm_dir(sx)
        w = wrist(sx)
        R = rot_align(d, FWD)
        hwf = lambda p, sfx=sfx, w=w, d=d: rig.seg_weights((p - w).dot(d), [('forearm' + sfx, 0.0), ('hand' + sfx, None)], 0.012)
        ellipsoid(mb, w + d * 0.054, (0.044, 0.054, 0.060), SKIN, hwf, segs=18, rings=14, rot=R, power=2.2)
        tdir = (d + FWD * 0.9).normalized()
        ellipsoid(mb, w + d * 0.036 + FWD * 0.044, (0.023, 0.023, 0.034), SKIN, hwf, segs=12, rings=8, rot=rot_align(tdir, UP))
    return mb


def hair_shell(mb, g, hairline, style, wfn, segs=56, rows=16, tuck=0.014):
    """Hair cap over the (reshaped) head whose lower edge follows `hairline`
    exactly: hairline(ang) -> z, ang 0 = straight back, +pi/2 = the
    character's left, +-pi = the forehead.  Rings run from the hairline up to
    the crown, so the edge is a smooth curve rather than whole mesh triangles
    dropped by a mask (V3: the V2 masks left a stepped hairline).  A row tucked
    under the edge gives the hair some thickness."""
    rz = HEAD_R[2] + g
    ztop = HEAD_C.z + rz * 0.9995
    rows_idx = []
    angs = [-math.pi + 2.0 * math.pi * k / segs for k in range(segs)]
    angs.reverse()   # ring order counter-clockwise seen from above -> outward normals
    edge = [hairline(a) for a in angs]
    # tucked row (under the edge, toward the scalp)
    row = []
    for a, z0 in zip(angs, edge):
        q = _shell_point(a, z0 + 0.004, g - tuck)
        row.append(mb.vert(q, style, (0, q.z), wfn(q)))
    rows_idx.append(row)
    for r in range(rows):
        u = r / float(rows)
        row = []
        for a, z0 in zip(angs, edge):
            # polar spacing: rows bunch where the curvature is (near the edge and crown)
            t0 = math.acos(max(-1.0, min(1.0, (z0 - HEAD_C.z) / rz)))
            t = t0 * (1.0 - u)
            z = HEAD_C.z + rz * math.cos(t)
            q = _shell_point(a, min(z, ztop), g)
            row.append(mb.vert(q, style, (0, q.z), wfn(q)))
        rows_idx.append(row)
    top = Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + rz))
    pole = mb.vert(top, style, (0, top.z), wfn(top))
    mb.grid(rows_idx, True, None, pole)
    return angs, edge


def _front(ang):
    """1 at the forehead (ang +-pi), 0 at the back (ang 0)."""
    return 0.5 - 0.5 * math.cos(ang)


def hairline_short(base):
    """Short hair: low at the nape, up over the temples, a forehead hairline."""
    def f(ang):
        return base + 0.29 * _front(ang) + 0.06 * math.sin(ang) ** 2
    return f


def hairline_bob(ang):
    """Chin-length bob: down to the jaw at the back and sides, up around the
    eyes and cheeks, straight bangs across the forehead."""
    a = abs(ang)
    bangs = 1.292 + 0.035 * (abs(math.sin(ang)) * 0.3 / 0.22) ** 2
    w = smoothstep(math.radians(98), math.radians(124), a)
    return lerp(0.99, bangs, w)


def build_hair():
    mb = MeshBuilder('hair')
    hw = rigid('head')
    hair_shell(mb, 0.018, hairline_short(1.08), HAIR, hw)
    # forelock swoop (projected onto the hair shell)
    pts = [Vector((0.06, 0.20, 1.43)), Vector((0.02, 0.27, 1.455)), Vector((-0.04, 0.30, 1.44)), Vector((-0.09, 0.29, 1.405)),
           Vector((-0.12, 0.265, 1.37))]
    pts = [Vector((q.x, head_front_y(q.x, q.z, 0.03), q.z)) for q in pts]
    pts = _dense_path(pts, 0.015)
    n = len(pts)
    radii = [(lerp(0.05, 0.012, i / (n - 1)), lerp(0.026, 0.008, i / (n - 1))) for i in range(n)]
    sweep(mb, pts, radii, HAIR, hw, segs=10, twist_hint=UP)
    return mb


def _shell_point(ang, z, grow):
    """Point on the (reshaped) head shell at height z, around the vertical axis
    (ang 0 = straight back, +pi/2 = the character's left)."""
    rx, ry, rz = HEAD_R[0] + grow, HEAD_R[1] + grow, HEAD_R[2] + grow
    zn = (z - HEAD_C.z) / rz
    sx, sy = rig.head_scale(max(-1.0, min(1.0, zn)))
    k = max(1e-6, 1.0 - abs(zn) ** HEAD_P)
    dx, dy = -math.sin(ang), -math.cos(ang)
    t = (k / (abs(dx / (rx * sx)) ** HEAD_P + abs(dy / (ry * sy)) ** HEAD_P)) ** (1.0 / HEAD_P)
    return Vector((HEAD_C.x + dx * t, HEAD_C.y + dy * t, z))


def build_hair_bob():
    """Chin-length bob with straight bangs; the face stays open."""
    mb = MeshBuilder('hair_bob')
    hw = rigid('head')
    g = 0.024
    angs, edge = hair_shell(mb, g, hairline_bob, HAIR, hw, segs=64, rows=18, tuck=0.018)
    # rolled ends: a soft tube along the lower edge (back and sides)
    pts = [_shell_point(math.radians(a), hairline_bob(math.radians(a)) + 0.012, g + 0.002) for a in range(-100, 101, 5)]
    sweep(mb, pts, [(0.017, 0.015)] * len(pts), HAIR, hw, segs=8, twist_hint=UP)
    # bangs edge: a slightly thicker lip so the fringe has thickness
    bp = []
    for i in range(15):
        x = lerp(-0.21, 0.21, i / 14.0)
        z = 1.296 + 0.035 * (abs(x) / 0.22) ** 2
        bp.append(Vector((x, head_front_y(x, z, g) - 0.004, z)))
    sweep(mb, bp, [(0.012, 0.01)] * len(bp), HAIR, hw, segs=8, twist_hint=FWD)
    return mb


def build_hair_curly():
    """Short curly crop: a shell plus soft curls on the sides, back and fringe.
    The crown stays smooth so caps, crowns and headphones sit on it."""
    mb = MeshBuilder('hair_curly')
    hw = rigid('head')
    g = 0.016
    line = hairline_short(1.06)
    hair_shell(mb, g, line, HAIR, hw)
    n = 150
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        zz = 1 - 2 * (i + 0.5) / n
        rr = math.sqrt(max(0.0, 1 - zz * zz))
        ang = ga * i
        d = Vector((rr * math.cos(ang), rr * math.sin(ang), zz))
        z = HEAD_C.z + d.z * (HEAD_R[2] + g)
        if z > 1.43:          # smooth crown (hats sit here)
            continue
        a = math.atan2(-d.x, -d.y)
        if z < line(a) + 0.02 or z < 1.0:
            continue
        q = _shell_point(a, z, g)
        if q.y - HEAD_C.y > 0.08 and q.z < 1.33:
            continue          # keep the face clear
        nrm = head_normal(q, g)
        r = 0.03 + 0.008 * ((i * 7) % 5) / 4.0
        ellipsoid(mb, q + nrm * 0.004, (r, r, r * 0.8), HAIR, hw, segs=10, rings=6, rot=rot_align(nrm, UP))
    return mb


def build_hair_buns():
    """Centre-parted short hair; the two buns are a separate part so they can
    be hidden under headphones and crowns."""
    mb = MeshBuilder('hair_buns')
    hw = rigid('head')
    g = 0.016
    hair_shell(mb, g, hairline_short(1.07), HAIR, hw)
    # centre part: two soft swoops meeting at the middle of the forehead
    for sx in SIDES:
        pts = [Vector((0.005 * sx, 0.0, 1.47)), Vector((0.06 * sx, 0.0, 1.45)), Vector((0.12 * sx, 0.0, 1.40)),
               Vector((0.17 * sx, 0.0, 1.34))]
        pts = [Vector((q.x, head_front_y(q.x, q.z, 0.028), q.z)) for q in pts]
        pts = _dense_path(pts, 0.015)
        m = len(pts)
        sweep(mb, pts, [(lerp(0.03, 0.012, i / (m - 1)), lerp(0.018, 0.008, i / (m - 1))) for i in range(m)], HAIR, hw,
              segs=8, twist_hint=UP)
    return mb


def build_hair_buns_knots():
    mb = MeshBuilder('hair_buns_knots')
    hw = rigid('head')
    tie = Style('#ff8fb1', T_NONE, 0.6, MAT_CLOTH)
    for sx in SIDES:
        c = Vector((0.205 * sx, -0.06, 1.385))
        out = (c - HEAD_C).normalized()
        R = rot_align(out, UP)
        ellipsoid(mb, c + out * 0.07, (0.082, 0.082, 0.072), HAIR, hw, segs=16, rings=12, rot=R)
        lathe(mb, c + out * 0.012, R, torus_profile(0.0, 0.058, 0.014, 8), tie, hw, segs=18, closed_profile=True)
    return mb


def build_freckles():
    mb = MeshBuilder('freckles')
    hw = rigid('head')
    dot = Style('#b9734f', T_NONE, 0.8, MAT_SKIN)
    spots = [(0.14, 1.112), (0.168, 1.122), (0.196, 1.108), (0.155, 1.092), (0.183, 1.088), (0.21, 1.125)]
    for sx in SIDES:
        for (x, z) in spots:
            p = head_point(x * sx, z)
            n = head_normal(p)
            ellipsoid(mb, p - n * 0.0015, (0.0055, 0.0055, 0.0018), dot, hw, segs=8, rings=4, rot=rot_align(n, UP))
    return mb


# ================================================================== BODY SKIN (swim / robe)
def build_body_skin():
    mb = MeshBuilder('body_skin')
    torso_lathe(mb, SKIN, 0.0, 0.47, 0.88, bottom_pole=True)
    for sx in SIDES:
        path = _arm_path(sx, -0.02)
        s = _path_s(path)
        sweep(mb, path, [(arm_radius(v), arm_radius(v)) for v in s], SKIN, lambda p, sv, i, sx=sx: arm_w(p, sx),
              segs=14, cap_start='round', cap_end='flat', twist_hint=FWD)
        lp = _leg_path(sx)
        ls = _path_s(lp)
        sweep(mb, lp, [(leg_radius(v), leg_radius(v) * 0.95) for v in ls], SKIN, lambda p, sv, i, sx=sx: leg_w(p, sx),
              segs=16, cap_start='round', cap_end='flat', twist_hint=FWD)
    return mb


# ================================================================== shared clothing pieces
def sleeves(mb, style, grow, s1=None, cuff_style=None, bell=0.0, band=None):
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        path = _arm_path(sx, -0.015, s1)
        s = _path_s(path)
        total = s[-1]
        radii = []
        for v in s:
            r = arm_radius(v - 0.015) + grow + bell * smoothstep(total * 0.4, total, v)
            radii.append((r, r))
        colfn = None
        if band:
            colfn = lambda p, sv, a, band=band: band[2] if band[0] <= sv <= band[1] else None
        sweep(mb, path, radii, style, lambda p, sv, i, sx=sx: arm_w(p, sx), segs=14, cap_start=None, cap_end='flat',
              twist_hint=FWD, colfn=colfn)
        # shoulder cap fills the joint
        sh = shoulder(sx)
        # stripes by world height so the cap continues the torso's stripes where
        # they overlap; a little larger than the sleeve so the sleeve leaves it
        # along a clean line instead of a grazing (sawtooth) intersection
        ellipsoid(mb, sh + Vector((0.004 * sx, 0, 0.004)), (0.068 + grow, 0.066 + grow, 0.062 + grow), style,
                  lambda p, sfx=sfx: {'upper_arm' + sfx: 0.55, 'shoulder' + sfx: 0.45}, segs=18, rings=12, world_v=True)
        if cuff_style is not None:
            d = arm_dir(sx)
            end = sh + d * (total - 0.015)
            r = radii[-1][0]
            lathe(mb, end, rot_align(d, FWD), torus_profile(0.0, r + 0.002, 0.014, 8), cuff_style,
                  lambda p, sx=sx: arm_w(p, sx), segs=16, closed_profile=True)


def pant_legs(mb, style, grow, bottom_z=None, cuff_style=None, flat_end=True):
    for sx in SIDES:
        lp = _leg_path(sx, 0.55, bottom_z)
        ls = _path_s(lp)
        radii = [(leg_radius(v) + grow, (leg_radius(v) + grow) * 0.96) for v in ls]
        sweep(mb, lp, radii, style, lambda p, sv, i, sx=sx: leg_w(p, sx), segs=14, cap_start=None,
              cap_end='flat' if flat_end else None, twist_hint=FWD)
        if cuff_style is not None:
            k, e = lp[-2], lp[-1]
            d = (e - k).normalized()
            lathe(mb, e - d * 0.006, rot_align(d, FWD), torus_profile(0.0, radii[-1][0] + 0.002, 0.016, 8), cuff_style,
                  lambda p, sx=sx: leg_w(p, sx), segs=18, closed_profile=True)


def pelvis(mb, style, grow, z_top, extra=None):
    torso_lathe(mb, style, grow, 0.47, z_top, bottom_pole=True, extra=extra)


def on_torso(x, z, grow):
    p = Vector((x, torso_front_y(x, z, grow), z))
    # approximate normal of the elliptical lathe
    r = torso_r(z) + grow
    nx = x / max(r, 1e-3)
    ny = (p.y - TORSO_CY) / max(r * TORSO_RY, 1e-3)
    dz = (torso_r(z + 0.01) - torso_r(z - 0.01)) / 0.02
    n = Vector((nx, ny * TORSO_RY, -dz)).normalized()
    return p, n


def placket_and_buttons(mb, grow, n_buttons=3, style=CLOTH_S, button=IVORY, z0=0.53, z1=0.855):
    pts = []
    z = z0
    while z <= z1 + 1e-6:
        p, n = on_torso(0.0, z, grow + 0.004)
        pts.append(p)
        z += 0.02
    sweep(mb, pts, [(0.004, 0.019)] * len(pts), style, lambda p, sv, i: torso_w(p), segs=8, twist_hint=FWD)
    for i in range(n_buttons):
        bz = z1 - 0.06 - i * (z1 - z0 - 0.1) / max(1, n_buttons - 1)
        p, n = on_torso(0.0, bz, grow + 0.009)
        ellipsoid(mb, p, (0.012, 0.012, 0.0045), button, lambda q: torso_w(q), segs=10, rings=6, rot=rot_align(n, UP))


def collar(mb, grow, style=CLOTH_S, z=0.872):
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(z, 0.086 + grow * 0.5, 0.019, 8), style,
          lambda p: torso_w(p), segs=20, closed_profile=True, ry_scale=0.92)
    for sx in SIDES:
        p, n = on_torso(0.05 * sx, 0.836, grow + 0.004)
        R = rot_align(n, UP) @ rot_z(38 * sx)
        ellipsoid(mb, p, (0.028, 0.036, 0.006), style, lambda q: torso_w(q), segs=12, rings=8, rot=R, power=2.4)


# ================================================================== OUTFITS
def build_pj():
    mb = MeshBuilder('pj')
    g = 0.018
    torso_lathe(mb, CLOTH_P, g, 0.50, 0.872, top_open_r=0.09, hem_fold=0.02, flare=0.012)
    sleeves(mb, CLOTH_P, 0.017, cuff_style=CLOTH_S)
    collar(mb, g)
    placket_and_buttons(mb, g)
    # chest pocket
    p, n = on_torso(-0.095, 0.765, g + 0.004)
    ellipsoid(mb, p, (0.04, 0.036, 0.005), CLOTH_S, lambda q: torso_w(q), segs=12, rings=8, rot=rot_align(n, UP), power=4.0)
    # trousers
    pelvis(mb, CLOTH_P, 0.012, 0.60)
    pant_legs(mb, CLOTH_P, 0.022, cuff_style=CLOTH_S)
    return mb


def build_swim():
    mb = MeshBuilder('swim')

    def stripe(p, z, th):
        if abs(p.x) > 0.17 and abs(p.y - TORSO_CY) < 0.035:
            return CLOTH_S
        return None
    torso_lathe(mb, CLOTH_P_PLAIN, 0.014, 0.47, 0.615, bottom_pole=True, colfn=stripe)
    for sx in SIDES:
        lp = _leg_path(sx, 0.55, 0.40)
        ls = _path_s(lp)
        radii = [(leg_radius(v) + 0.028, (leg_radius(v) + 0.028) * 0.96) for v in ls]
        sweep(mb, lp, radii, CLOTH_P_PLAIN, lambda p, sv, i, sx=sx: leg_w(p, sx), segs=18, cap_start=None, cap_end='flat',
              twist_hint=FWD, colfn=lambda p, sv, a: CLOTH_S if (abs(p.x) > 0.16 and abs(p.y) < 0.03) else None)
    # waistband + drawstring bow
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.612, torso_r(0.612) + 0.016, 0.011, 8),
          Style('#f4f2ec', T_NONE, 0.8, MAT_CLOTH), lambda p: torso_w(p), segs=24, closed_profile=True, ry_scale=TORSO_RY)
    for sx in SIDES:
        p, n = on_torso(0.022 * sx, 0.6, 0.03)
        R = rot_align(n, UP) @ rot_z(-35 * sx)
        ellipsoid(mb, p, (0.022, 0.011, 0.007), IVORY, lambda q: torso_w(q), segs=10, rings=6, rot=R)
    return mb


def build_robe():
    mb = MeshBuilder('robe')
    robe = Style('#ffffff', T_SECOND, 0.95, MAT_CLOTH)
    trim = Style('#f4f2ec', T_NONE, 0.95, MAT_CLOTH)
    prof = [(0.33, 0.20), (0.30, 0.255), (0.305, 0.27), (0.34, 0.262), (0.40, 0.252), (0.46, 0.245), (0.52, 0.244)]
    z = 0.55
    while z <= 0.86:
        prof.append((z, torso_r(z) + 0.034))
        z += 0.025
    prof += [(0.875, 0.104), (0.88, 0.096), (0.86, 0.088)]
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, robe, skirt_w, segs=30, ry_scale=TORSO_RY)
    sleeves(mb, robe, 0.03, bell=0.03, cuff_style=trim)
    # shawl lapels: back of the neck, over the shoulders, crossing to the belt
    for sx in SIDES:
        pts = [Vector((0.0, -0.105, 0.885)), Vector((0.07 * sx, -0.07, 0.885)), Vector((0.11 * sx, 0.02, 0.87))]
        for z in (0.83, 0.77, 0.71, 0.65, 0.61):
            t = (0.83 - z) / 0.22
            x = lerp(0.085, -0.02, t) * sx
            p, n = on_torso(x, z, 0.044)
            pts.append(p)
        pts = _dense_path(pts, 0.02)
        sweep(mb, pts, [(0.009, 0.036)] * len(pts), trim, lambda p, sv, i: torso_w(p), segs=10, twist_hint=UP)
    # sash belt + knot + tails
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.6, torso_r(0.6) + 0.042, 0.017, 8),
          CLOTH_P_PLAIN, lambda p: torso_w(p), segs=26, closed_profile=True, ry_scale=TORSO_RY)
    p, n = on_torso(-0.07, 0.6, 0.06)
    ellipsoid(mb, p, (0.03, 0.026, 0.022), CLOTH_P_PLAIN, lambda q: torso_w(q), segs=10, rings=8, rot=rot_align(n, UP))
    for dx in (-0.02, 0.02):
        top, n2 = on_torso(-0.07 + dx, 0.585, 0.058)
        pts = _dense_path([top, top + Vector((dx * 0.8, 0.01, -0.07)), top + Vector((dx * 1.4, 0.005, -0.13))], 0.02)
        sweep(mb, pts, [(0.016, 0.006)] * len(pts), CLOTH_P_PLAIN, lambda p, sv, i: skirt_w(p), segs=8, twist_hint=FWD)
    return mb


def _hood(mb, base, rim_style, extra_grow=0.035):
    """Mascot hood: a shell over the head with a face opening and a rolled rim."""
    def keep(p):
        if p.z < 0.94:
            return False
        if p.y > 0.0:
            e = (p.x / 0.228) ** 2 + ((p.z - 1.145) / 0.19) ** 2
            if e < 1.0:
                return False
        return True
    hw = lambda p: rig.seg_weights(p.z, [('neck', 0.95), ('head', None)], 0.03)
    ellipsoid(mb, HEAD_C, (HEAD_R[0] + extra_grow, HEAD_R[1] + extra_grow, HEAD_R[2] + extra_grow), base, hw,
              segs=36, rings=26, power=HEAD_P, keep=keep, deform=rig.head_deform(extra_grow))
    # rim
    pts = []
    for i in range(32):
        a = 2 * math.pi * i / 32
        x = 0.228 * math.cos(a)
        z = 1.145 + 0.19 * math.sin(a)
        p = head_point(x, z, extra_grow)
        pts.append(p)
    sweep(mb, pts, [(0.02, 0.02)] * len(pts), rim_style, lambda p, sv, i: {'head': 1.0}, segs=10, closed=True,
          twist_hint=FWD)
    # neck skirt of the hood
    lathe(mb, Vector((0, 0.0, 0)), Matrix.Identity(3), [(0.86, 0.14), (0.9, 0.15), (0.95, 0.2), (0.985, 0.24)], base,
          lambda p: rig.seg_weights(p.z, [('chest', 0.89), ('neck', 0.95), ('head', None)], 0.03), segs=24, ry_scale=0.92)


def _mascot_body(mb, style, belly):
    torso_lathe(mb, style, 0.05, 0.46, 0.88, bottom_pole=True, extra=lambda z: 0.025 * math.sin(math.pi * smoothstep(0.46, 0.86, z)))
    p, n = on_torso(0.0, 0.66, 0.085)
    ellipsoid(mb, p - n * 0.012, (0.15, 0.17, 0.03), belly, lambda q: torso_w(q), segs=18, rings=12, rot=rot_align(n, UP))
    sleeves(mb, style, 0.03)
    pant_legs(mb, style, 0.03)


def build_duck():
    mb = MeshBuilder('duck')
    yel = Style('#ffd447', T_NONE, 0.95, MAT_CLOTH)
    belly = Style('#fff1b8', T_NONE, 0.95, MAT_CLOTH)
    orange = Style('#ff9b2e', T_NONE, 0.55, MAT_GLOSS)
    _mascot_body(mb, yel, belly)
    # tail feathers
    for i, a in enumerate((-25, 0, 25)):
        R = rot_x(-55) @ rot_y(a)
        ellipsoid(mb, Vector((0.03 * (i - 1), -0.255, 0.53)), (0.045, 0.02, 0.085), yel, lambda q: {'hips': 1.0}, segs=10,
                  rings=8, rot=R)
    _hood(mb, yel, belly)
    # bill on the hood forehead
    bp = head_point(0.0, 1.37, 0.035)
    R = rot_x(-12)
    ellipsoid(mb, bp + Vector((0, 0.06, -0.005)), (0.12, 0.10, 0.03), orange, rigid('head'), segs=18, rings=10, rot=R, power=2.3)
    # hood eyes
    for sx in SIDES:
        c = head_point(0.095 * sx, 1.43, 0.035)
        n = head_normal(c, 0.035)
        R2 = rot_align(n, UP)
        ellipsoid(mb, c, (0.05, 0.055, 0.03), Style('#fbfaf6', T_NONE, 0.3, MAT_GLOSS), rigid('head'), segs=14, rings=10, rot=R2)
        ellipsoid(mb, c + n * 0.022, (0.022, 0.028, 0.012), Style('#1b1d2b', T_NONE, 0.2, MAT_GLOSS), rigid('head'), segs=10,
                  rings=8, rot=R2)
    # tuft
    for i, a in enumerate((-20, 0, 20)):
        ellipsoid(mb, Vector((0.02 * (i - 1), -0.02, 1.52)), (0.012, 0.03, 0.06), yel, rigid('head'), segs=8, rings=6,
                  rot=rot_y(a) @ rot_x(-15))
    return mb


def build_frog():
    mb = MeshBuilder('frog')
    green = Style('#5fc35a', T_NONE, 0.95, MAT_CLOTH)
    belly = Style('#d9f2a8', T_NONE, 0.95, MAT_CLOTH)
    _mascot_body(mb, green, belly)
    _hood(mb, green, belly)
    for sx in SIDES:
        c = Vector((0.125 * sx, 0.07, 1.45))
        ellipsoid(mb, c, (0.078, 0.075, 0.07), green, rigid('head'), segs=16, rings=12)
        fwd = Vector((0.25 * sx, 1.0, 0.25)).normalized()
        R = rot_align(fwd, UP)
        ellipsoid(mb, c + fwd * 0.052, (0.052, 0.054, 0.026), Style('#fbfaf6', T_NONE, 0.3, MAT_GLOSS), rigid('head'),
                  segs=14, rings=10, rot=R)
        ellipsoid(mb, c + fwd * 0.074, (0.022, 0.03, 0.01), Style('#1b1d2b', T_NONE, 0.2, MAT_GLOSS), rigid('head'),
                  segs=10, rings=8, rot=R)
    # cheek spots on the hood
    for sx in SIDES:
        p = head_point(0.25 * sx, 1.07, 0.04)
        ellipsoid(mb, p, (0.025, 0.025, 0.006), Style('#ff9fb0', T_NONE, 0.9, MAT_CLOTH), rigid('head'), segs=10, rings=6,
                  rot=rot_align(head_normal(p, 0.04), UP))
    return mb


# ================================================================== NIGHT WATCH
NAVY = Style('#2b3a66', T_NONE, 0.88, MAT_CLOTH)
NAVY_D = Style('#1f2a4a', T_NONE, 0.88, MAT_CLOTH)
HIVIS = Style('#ffc93c', T_NONE, 0.35, MAT_GLOSS)
GOLD = Style('#f2c14e', T_NONE, 0.3, MAT_GLOSS)
LEATHER = Style('#22242c', T_NONE, 0.45, MAT_RUBBER)
SOLE_DARK = Style('#141519', T_NONE, 0.7, MAT_RUBBER)
SILVER = Style('#cfd3dc', T_NONE, 0.25, MAT_GLOSS)


def build_watch():
    mb = MeshBuilder('watch')
    g = 0.02

    def bands(p, z, th):
        if 0.728 <= z <= 0.766:
            return HIVIS
        return None
    torso_lathe(mb, NAVY, g, 0.50, 0.872, top_open_r=0.09, hem_fold=0.02, colfn=bands)
    sleeves(mb, NAVY, 0.018, cuff_style=NAVY_D, band=(0.205, 0.235, HIVIS))
    collar(mb, g, NAVY_D)
    placket_and_buttons(mb, g, 4, NAVY_D, SILVER)
    # chest pockets with flaps, badge on the left
    for sx in SIDES:
        p, n = on_torso(0.1 * sx, 0.68, g + 0.004)
        R = rot_align(n, UP)
        ellipsoid(mb, p, (0.042, 0.042, 0.006), NAVY_D, lambda q: torso_w(q), segs=12, rings=8, rot=R, power=4.0)
    p, n = on_torso(-0.1, 0.80, g + 0.008)
    ellipsoid(mb, p, (0.028, 0.034, 0.008), GOLD, lambda q: torso_w(q), segs=12, rings=8, rot=rot_align(n, UP), power=2.5)
    # epaulettes
    for sx in SIDES:
        c = shoulder(sx) + Vector((-0.03 * sx, 0, 0.055))
        ellipsoid(mb, c, (0.06, 0.035, 0.012), NAVY_D, lambda q, sx=sx: {'shoulder' + ('.L' if sx < 0 else '.R'): 1.0},
                  segs=12, rings=8, rot=rot_z(0))
    # trousers + belt
    pelvis(mb, NAVY_D, 0.014, 0.60)
    pant_legs(mb, NAVY_D, 0.022, flat_end=True)
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.565, torso_r(0.565) + 0.03, 0.02, 8, 0.8),
          LEATHER, lambda p: torso_w(p), segs=28, closed_profile=True, ry_scale=TORSO_RY)
    p, n = on_torso(0.0, 0.565, 0.05)
    ellipsoid(mb, p, (0.03, 0.022, 0.008), SILVER, lambda q: torso_w(q), segs=10, rings=6, rot=rot_align(n, UP), power=4.0)
    # lanyard + whistle
    lp = [Vector((0.0, -0.085, 0.885)), Vector((0.075, -0.045, 0.885)), Vector((0.105, 0.05, 0.86))]
    for z, x in ((0.81, 0.07), (0.77, 0.035)):
        q, _ = on_torso(x, z, g + 0.006)
        lp.append(q)
    q, _ = on_torso(0.0, 0.752, g + 0.008)
    lp.append(q)
    for z, x in ((0.77, -0.035), (0.81, -0.07)):
        q, _ = on_torso(x, z, g + 0.006)
        lp.append(q)
    lp += [Vector((-0.105, 0.05, 0.86)), Vector((-0.075, -0.045, 0.885))]
    lp = _dense_path(lp, 0.02)
    sweep(mb, lp, [(0.0055, 0.0055)] * len(lp), Style('#ff8a3d', T_NONE, 0.8, MAT_CLOTH), lambda p, sv, i: torso_w(p),
          segs=6, closed=True)
    q, n = on_torso(0.0, 0.725, g + 0.022)
    lathe(mb, q, rot_align(Vector((0.0, 0.3, -1.0)), FWD), [(0.0, 0.0), (0.0, 0.012), (0.04, 0.012), (0.04, 0.0)], SILVER,
          lambda p: torso_w(p), segs=10)
    # cap: band, crown flaring wider than the band, flat top, visor
    cap = Style('#26325a', T_NONE, 0.85, MAT_CLOTH)
    hw = rigid('head')
    prof = [(1.30, 0.318), (1.36, 0.318), (1.405, 0.336), (1.44, 0.348), (1.462, 0.342), (1.475, 0.31), (1.482, 0.22),
            (1.485, 0.0)]
    lathe(mb, Vector((0, 0.005, 0)), Matrix.Identity(3), prof, cap, hw, segs=32, ry_scale=0.95)
    lathe(mb, Vector((0, 0.005, 0)), Matrix.Identity(3), torus_profile(1.32, 0.322, 0.022, 8, 1.4),
          Style('#161c33', T_NONE, 0.8, MAT_CLOTH), hw, segs=32, closed_profile=True, ry_scale=0.95)
    ellipsoid(mb, Vector((0, 0.27, 1.305)), (0.215, 0.17, 0.02), Style('#121624', T_NONE, 0.35, MAT_GLOSS), hw, segs=26,
              rings=10, rot=rot_x(-16), keep=lambda p: p.y > 0.235)
    ellipsoid(mb, Vector((0, 0.325, 1.40)), (0.036, 0.008, 0.042), GOLD, hw, segs=12, rings=8, rot=rot_x(-10), power=2.5)
    # boots
    for sx in SIDES:
        _shoe_base(mb, sx, SOLE_DARK, LEATHER, LEATHER, shaft_top=0.2)
    return mb


def build_flashlight():
    mb = MeshBuilder('flashlight')
    side = 1
    w = wrist(side)
    d = arm_dir(side)
    c = w + d * 0.052
    R = rot_align(FWD, UP)
    body = Style('#2a2d36', T_NONE, 0.35, MAT_GLOSS)
    prof = [(-0.07, 0.0), (-0.07, 0.019), (0.02, 0.02), (0.05, 0.03), (0.09, 0.032), (0.095, 0.0)]
    lathe(mb, c, R, prof, body, rigid('hand.R'), segs=14)
    lathe(mb, c, R, [(0.096, 0.0), (0.096, 0.026), (0.1, 0.0)], Style('#fff4c8', T_NONE, 0.1, MAT_EMIT), rigid('hand.R'),
          segs=14)
    return mb


def build_mustache():
    mb = MeshBuilder('mustache')
    for sx in SIDES:
        pts = []
        for i in range(7):
            t = i / 6.0
            x = (0.004 + 0.075 * t) * sx
            z = 1.094 - 0.012 * math.sin(math.pi * t * 0.9) + 0.016 * t * t
            p = head_point(x, z)
            pts.append(p + head_normal(p) * 0.012)
        radii = [(lerp(0.018, 0.007, i / 6.0), lerp(0.02, 0.008, i / 6.0)) for i in range(7)]
        sweep(mb, pts, radii, HAIR, rigid('head'), segs=8)
    return mb


# ================================================================== HATS
def build_nightcap():
    mb = MeshBuilder('hat_nightcap')
    path = [Vector((0, 0.0, 1.31)), Vector((0, -0.008, 1.40)), Vector((0.012, -0.025, 1.48)), Vector((0.06, -0.05, 1.555)),
            Vector((0.14, -0.08, 1.595)), Vector((0.225, -0.095, 1.575)), Vector((0.285, -0.095, 1.515)),
            Vector((0.315, -0.085, 1.45))]
    path = _dense_path(path, 0.016)
    s = _path_s(path)
    total = s[-1]
    radii = []
    for v in s:
        t = v / total
        r = 0.322 * (1.0 - smoothstep(0.0, 1.0, t)) ** 1.15 + 0.028 * smoothstep(0.0, 1.0, t)
        radii.append((r, r * 0.93))
    bone_s = [('head', 0.18), ('hat1', 0.29), ('hat2', 0.40), ('hat3', None)]
    sweep(mb, path, radii, CLOTH_P_PLAIN, lambda p, sv, i: rig.seg_weights(sv, bone_s, 0.045), segs=18, cap_start=None,
          cap_end='round', twist_hint=FWD)
    lathe(mb, Vector((0, 0.0, 0)), Matrix.Identity(3), torus_profile(1.318, 0.322, 0.044, 12), CLOTH_S, rigid('head'), segs=36,
          closed_profile=True, ry_scale=0.93)
    tip = path[-1] + (path[-1] - path[-2]).normalized() * 0.04
    ellipsoid(mb, tip, (0.068, 0.068, 0.066), Style('#f4f2ec', T_NONE, 1.0, MAT_CLOTH), rigid('hat3'), segs=16, rings=12)
    return mb


def build_swimcap():
    mb = MeshBuilder('hat_swimcap')
    rub = Style('#ffffff', T_PRIMARY, 0.35, MAT_RUBBER)

    def keep(p):
        return p.z > 1.05 + 0.45 * (p.y + 0.27) * 0.6 + 0.04 * (abs(p.x) / 0.3) ** 2 + 0.02
    ellipsoid(mb, HEAD_C, (HEAD_R[0] + 0.012, HEAD_R[1] + 0.012, HEAD_R[2] + 0.014), rub, rigid('head'), segs=36, rings=26,
              power=HEAD_P, keep=keep, deform=rig.head_deform(0.014))
    # goggles pushed up on the forehead
    strap = Style('#2a2d36', T_NONE, 0.6, MAT_RUBBER)
    strap_r = rig.head_side_x(HEAD_C.z + 0.03, 0.014) + 0.006
    lathe(mb, HEAD_C + Vector((0, 0, 0.0)), rot_x(-14), torus_profile(0.13, strap_r, 0.011, 6, 1.6), strap, rigid('head'),
          segs=32, closed_profile=True, ry_scale=0.93)
    for sx in SIDES:
        p = head_point(0.085 * sx, 1.335, 0.02)
        n = head_normal(p, 0.02)
        R = rot_align(n, UP)
        ellipsoid(mb, p + n * 0.008, (0.048, 0.04, 0.016), Style('#6fd8cc', T_NONE, 0.08, MAT_GLOSS), rigid('head'), segs=14,
                  rings=8, rot=R)
        lathe(mb, p + n * 0.006, R, torus_profile(0.0, 0.046, 0.009, 6), strap, rigid('head'), segs=16, closed_profile=True,
              ry_scale=0.85)
    mb.compact()
    return mb


def build_party():
    mb = MeshBuilder('hat_party')
    R = rot_y(12) @ rot_x(-6)
    base = Vector((0.04, 0.0, 1.43))
    prof = [(0.0, 0.0), (0.0, 0.118), (0.01, 0.12)]
    for i in range(1, 9):
        z = 0.03 * i
        prof.append((z, lerp(0.12, 0.012, z / 0.27)))
    prof.append((0.275, 0.0))
    lathe(mb, base, R, prof, Style('#ffffff', T_PRIMARY, 0.7, MAT_CLOTH, stripes=True), rigid('head'), segs=20)
    ellipsoid(mb, base + R @ Vector((0, 0, 0.285)), (0.04, 0.04, 0.04), Style('#ffd85a', T_NONE, 1.0, MAT_CLOTH), rigid('head'),
              segs=12, rings=8)
    return mb


def build_headphones():
    mb = MeshBuilder('hat_headphones')
    band = Style('#2a2d36', T_NONE, 0.4, MAT_GLOSS)
    pts = []
    for i in range(21):
        a = math.radians(-78 + 156 * i / 20)
        pts.append(Vector((0.34 * math.sin(a), -0.01, HEAD_C.z + 0.05 + 0.33 * math.cos(a))))
    sweep(mb, pts, [(0.012, 0.03)] * len(pts), band, rigid('head'), segs=10, twist_hint=FWD)
    for sx in SIDES:
        R = rot_align(Vector((sx, 0, 0)), UP)
        c = Vector(((rig.head_side_x(1.17, 0.0, -0.005) - 0.004) * sx, -0.005, 1.17))
        lathe(mb, c, R, [(0.0, 0.0), (0.0, 0.066), (0.006, 0.072), (0.05, 0.074), (0.062, 0.064), (0.066, 0.0)],
              Style('#ffffff', T_PRIMARY, 0.4, MAT_GLOSS), rigid('head'), segs=20, ry_scale=1.15)
        lathe(mb, c, R, torus_profile(0.0, 0.05, 0.02, 8), Style('#3a3d48', T_NONE, 0.9, MAT_CLOTH), rigid('head'), segs=18,
              closed_profile=True, ry_scale=1.15)
    return mb


def build_crown():
    mb = MeshBuilder('hat_crown')
    gold = Style('#ffc94a', T_NONE, 0.3, MAT_GLOSS)
    segs = 40
    rings = []
    zb = 1.39
    for layer, (r, top) in enumerate(((0.268, False), (0.268, True), (0.256, True), (0.256, False))):
        row = []
        for k in range(segs):
            th = 2 * math.pi * k / segs
            spike = 1.0 - abs(((th * 5 / (2 * math.pi)) % 1.0) * 2 - 1.0)
            z = zb + (0.06 + 0.07 * spike if top else 0.0)
            x = math.cos(th) * r
            y = math.sin(th) * r * 0.93 + 0.005
            row.append(mb.vert(Vector((x, y, z)), gold, (0, z), {'head': 1.0}))
        rings.append(row)
    mb.grid(rings, True)
    mb.grid([rings[3], rings[0]], True)
    for i in range(5):
        th = 2 * math.pi * (i + 0.5) / 5
        p = Vector((math.cos(th) * 0.27, math.sin(th) * 0.27 * 0.93 + 0.005, zb + 0.035))
        n = Vector((math.cos(th), math.sin(th), 0))
        ellipsoid(mb, p, (0.016, 0.016, 0.008), Style('#ff5b6e' if i % 2 else '#6fd8cc', T_NONE, 0.1, MAT_GLOSS),
                  rigid('head'), segs=10, rings=6, rot=rot_align(n, UP))
    return mb


# ================================================================== SHOES
def _foot_outline(sx, heel=-0.07, toe=0.17, w_heel=0.05, w_toe=0.064, n=28, toe_len=None):
    pts = []
    cx = rig.HIP_X * sx
    for i in range(n):
        a = 2 * math.pi * i / n
        # rounded foot: an ellipse whose front half is wider
        y_c = (heel + toe) * 0.5
        ry = (toe - heel) * 0.5
        y = y_c + ry * math.sin(a)
        f = smoothstep(heel, toe, y)
        w = lerp(w_heel, w_toe, min(1.0, f * 1.6))
        x = cx + math.cos(a) * w
        pts.append((x, y))
    return pts


def _shoe_base(mb, sx, sole, upper, collar_style, shaft_top=0.12, toe=0.17, upper_h=0.08, laces=None, toe_cap=None):
    sfx = '.L' if sx < 0 else '.R'
    fw = lambda p, sfx=sfx: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03)
    slab(mb, _foot_outline(sx, toe=toe), 0.0, 0.034, sole, fw, bevel=0.01)
    cx = rig.HIP_X * sx
    c = Vector((cx, (toe - 0.07) * 0.5 - 0.005, 0.03))
    ellipsoid(mb, c, (0.06, (toe + 0.07) * 0.5 - 0.004, upper_h), upper, fw, segs=22, rings=14, cut_below=-0.05,
              colfn=(lambda p, lp: toe_cap if (toe_cap is not None and p.y > toe - 0.06) else None))
    # ankle shaft
    lathe(mb, Vector((cx, -0.005, 0)), Matrix.Identity(3), [(0.05, 0.062), (0.1, 0.06), (shaft_top - 0.01, 0.058),
                                                             (shaft_top, 0.062), (shaft_top - 0.012, 0.05)],
          collar_style, fw, segs=18, ry_scale=1.05)
    if laces is not None:
        for i in range(3):
            y = 0.035 + i * 0.03
            z = 0.03 + upper_h * math.sqrt(max(0.0, 1 - ((y - c.y) / ((toe + 0.07) * 0.5)) ** 2)) - 0.004
            ellipsoid(mb, Vector((cx, y, z)), (0.032, 0.008, 0.006), laces, fw, segs=8, rings=6, rot=rot_x(-25))


def build_slippers():
    mb = MeshBuilder('shoe_slippers')
    fluff = Style('#ffd6e4', T_NONE, 1.0, MAT_CLOTH)
    sole = Style('#f3a6c0', T_NONE, 0.8, MAT_RUBBER)
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        fw = rigid('foot' + sfx)
        slab(mb, _foot_outline(sx, toe=0.195, heel=-0.08, w_heel=0.06, w_toe=0.078), 0.0, 0.028, sole, fw, bevel=0.01)
        cx = rig.HIP_X * sx
        ellipsoid(mb, Vector((cx, 0.055, 0.026)), (0.08, 0.142, 0.094), fluff, fw, segs=20, rings=12, cut_below=-0.1)
        lathe(mb, Vector((cx, -0.01, 0)), Matrix.Identity(3), torus_profile(0.1, 0.064, 0.02, 8), fluff,
              lambda p, sfx=sfx: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03), segs=18,
              closed_profile=True)
        for ex in (-0.032, 0.032):
            R = rot_x(-22) @ rot_y(ex * 300)
            ellipsoid(mb, Vector((cx + ex, 0.128, 0.145)), (0.021, 0.014, 0.066), fluff, fw, segs=12, rings=8, rot=R)
            ellipsoid(mb, Vector((cx + ex, 0.136, 0.145)), (0.011, 0.007, 0.048), Style('#ff9fbe', T_NONE, 1.0, MAT_CLOTH), fw,
                      segs=8, rings=6, rot=R)
            ellipsoid(mb, Vector((cx + ex * 0.8, 0.181, 0.083)), (0.009, 0.007, 0.010), Style('#1b1d2b', T_NONE, 0.2, MAT_GLOSS),
                      fw, segs=8, rings=6)
        ellipsoid(mb, Vector((cx, 0.199, 0.063)), (0.013, 0.009, 0.009), Style('#ff7aa2', T_NONE, 0.5, MAT_GLOSS), fw, segs=8,
                  rings=6)
    return mb


def build_hightops():
    mb = MeshBuilder('shoe_hightops')
    sole = Style('#f4f2ec', T_NONE, 0.65, MAT_RUBBER)
    upper = Style('#ffffff', T_DARK, 0.75, MAT_CLOTH)
    for sx in SIDES:
        _shoe_base(mb, sx, sole, upper, upper, shaft_top=0.17, laces=Style('#f4f2ec', T_NONE, 0.8, MAT_CLOTH),
                   toe_cap=Style('#f4f2ec', T_NONE, 0.6, MAT_RUBBER))
        # side star patch
        cx = rig.HIP_X * sx
        R = rot_align(Vector((sx, 0, 0)), UP)
        ellipsoid(mb, Vector((cx + 0.058 * sx, -0.01, 0.11)), (0.022, 0.022, 0.005), Style('#ffffff', T_SECOND, 0.7, MAT_CLOTH),
                  lambda p, sx=sx: rig.seg_weights(p.z, [('foot' + ('.L' if sx < 0 else '.R'), 0.11),
                                                          ('shin' + ('.L' if sx < 0 else '.R'), None)], 0.03),
                  segs=10, rings=6, rot=R, power=1.4)
    return mb


def build_flippers():
    mb = MeshBuilder('shoe_flippers')
    blue = Style('#3bb3e0', T_NONE, 0.45, MAT_RUBBER)
    fin = Style('#2b8fc4', T_NONE, 0.45, MAT_RUBBER)
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        fw = rigid('foot' + sfx)
        cx = rig.HIP_X * sx
        ellipsoid(mb, Vector((cx, 0.03, 0.03)), (0.068, 0.12, 0.08), blue, fw, segs=20, rings=12, cut_below=-0.3)
        outline = []
        for i in range(24):
            a = 2 * math.pi * i / 24
            y = 0.2 + 0.2 * math.sin(a)
            w = lerp(0.06, 0.1, smoothstep(0.02, 0.4, y))
            outline.append((cx + math.cos(a) * w, y))
        slab(mb, outline, 0.004, 0.018, fin, fw, bevel=0.006)
        lathe(mb, Vector((cx, -0.005, 0)), Matrix.Identity(3), torus_profile(0.1, 0.062, 0.016, 8), blue,
              lambda p, sfx=sfx: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03), segs=18,
              closed_profile=True)
    return mb


ALL_PARTS = [
    build_base, build_hair, build_hair_bob, build_hair_curly, build_hair_buns, build_hair_buns_knots, build_freckles,
    build_body_skin, build_pj, build_swim, build_robe, build_duck, build_frog,
    build_watch, build_flashlight, build_mustache,
    build_nightcap, build_swimcap, build_party, build_headphones, build_crown,
    build_slippers, build_hightops, build_flippers,
]
