"""V6 construction helpers for outfits, hats and shoes (pure Python + mathutils).

Decals (stars, badges, letters, emblems) are thin raised patches whose
outline is projected onto the garment surface, so a patch on a round torso
or a sleeve hugs it instead of floating or sinking at its edges.  Outlines
are lists of (u, v) in metres as seen from outside the garment (u to the
viewer's right, v up), counter-clockwise, star-shaped about (0, 0).

Open shells (vests, cardigans) are lathes over the torso that leave a front
opening; their edges get a trim tube.
"""
import math
from mathutils import Vector, Matrix

import rig
from geo import MeshBuilder, Style, sweep, ellipsoid, lathe, rot_align, smoothstep, lerp, frame_from  # noqa: F401
from rig import torso_r, TORSO_RY, TORSO_CY, HEAD_C

UP = Vector((0, 0, 1))
FWD = Vector((0, 1, 0))


# ------------------------------------------------------------------ outlines
def star_outline(r, inner=0.45, points=5, rot=0.0):
    out = []
    for i in range(points * 2):
        a = math.pi * 0.5 + rot + math.pi * i / points
        rr = r if i % 2 == 0 else r * inner
        out.append((math.cos(a) * rr, math.sin(a) * rr))
    return out


def circle_outline(r, n=16, ry=None):
    ry = r if ry is None else ry
    return [(math.cos(2 * math.pi * i / n) * r, math.sin(2 * math.pi * i / n) * ry) for i in range(n)]


def rounded_rect(w, h, rad, n=4):
    """Rounded rectangle centred on (0, 0), CCW."""
    out = []
    cs = [(w / 2 - rad, h / 2 - rad, 0.0), (-w / 2 + rad, h / 2 - rad, 0.5 * math.pi), (-w / 2 + rad, -h / 2 + rad, math.pi),
          (w / 2 - rad, -h / 2 + rad, 1.5 * math.pi)]
    for cx, cy, a0 in cs:
        for k in range(n + 1):
            a = a0 + 0.5 * math.pi * k / n
            out.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad))
    return out


def letter_t(w, h, stroke):
    """Block capital T (star-shaped about the centre of its junction)."""
    s = stroke / 2
    top = h / 2
    pts = [(w / 2, top), (-w / 2, top), (-w / 2, top - stroke), (-s, top - stroke), (-s, -h / 2), (s, -h / 2), (s, top - stroke),
           (w / 2, top - stroke)]
    # re-centre on the junction so the fan from (0, 0) stays inside
    cy = top - stroke * 0.5
    return [(x, y - cy) for x, y in pts], cy


def crescent(r, inner=0.8, shift=0.45, n=14, tilt=0.0):
    """Crescent moon (opening to +u before `tilt`) as (outer, inner) arcs
    with matching sample counts, for strip_decal: the outer circle radius r
    minus a circle of radius r*inner shifted by r*shift."""
    ri, d = r * inner, r * shift
    x = (r * r - ri * ri + d * d) / (2 * d)
    y = math.sqrt(max(0.0, r * r - x * x))
    a0 = math.atan2(y, x)
    b0 = math.atan2(y, x - d)
    ca, sa = math.cos(tilt), math.sin(tilt)
    outer, inn = [], []
    for i in range(n + 1):
        t = i / n
        a = a0 + (2 * math.pi - 2 * a0) * t
        b = b0 + (2 * math.pi - 2 * b0) * t
        for (px, py), lst in (((math.cos(a) * r, math.sin(a) * r), outer), ((d + math.cos(b) * ri, math.sin(b) * ri), inn)):
            lst.append((px * ca - py * sa, px * sa + py * ca))
    return outer, inn


# ------------------------------------------------------------------ surfaces
def torso_at(x, z, grow, back=False):
    """Point and normal on the torso shell (grown by `grow`) at x, z, front or back."""
    r = max(torso_r(z), 0.06) + grow
    xx = max(-r * 0.999, min(r * 0.999, x))
    y = r * TORSO_RY * math.sqrt(max(0.0, 1.0 - (xx / r) ** 2))
    dz = (torso_r(z + 0.01) - torso_r(z - 0.01)) / 0.02
    n = Vector((xx / r, (y / (r * TORSO_RY)) / TORSO_RY, -dz))
    if back:
        y = -y
        n.y = -n.y
    return Vector((xx, TORSO_CY + y, z)), n.normalized()


def torso_ang(th, z, grow):
    """Point and normal on the elliptic torso shell at angle th (90 deg = front)."""
    r = max(torso_r(z), 0.06) + grow
    p = Vector((math.cos(th) * r, TORSO_CY + math.sin(th) * r * TORSO_RY, z))
    dz = (torso_r(z + 0.01) - torso_r(z - 0.01)) / 0.02
    n = Vector((math.cos(th) / r, math.sin(th) / (r * TORSO_RY), -dz / r)).normalized()
    return p, n


def place_front(cx, cz, grow):
    return lambda u, v: torso_at(cx - u, cz + v, grow)


def place_back(cx, cz, grow):
    return lambda u, v: torso_at(cx + u, cz + v, grow, back=True)


def place_planar(center, normal, up_hint=UP, project=None):
    """Planar frame at `center` facing `normal`; `project(p) -> (p, n)` snaps
    each point onto the real surface (optional)."""
    n = Vector(normal).normalized()
    right = Vector(up_hint).cross(n)
    if right.length < 1e-6:
        right = FWD.cross(n)
    right.normalize()
    up = n.cross(right).normalized()

    def f(u, v):
        p = Vector(center) + right * u + up * v
        if project is not None:
            return project(p)
        return p, n
    return f


def cyl_project(a, d, rfn):
    """Projector onto a limb tube: axis from `a` along unit `d`, radius rfn(s)."""
    a = Vector(a)
    d = Vector(d).normalized()

    def f(p):
        q = p - a
        s = q.dot(d)
        rad = q - d * s
        if rad.length < 1e-6:
            rad = Vector((1, 0, 0))
        rn = rad.normalized()
        return a + d * s + rn * rfn(s), rn
    return f


def head_project(grow):
    """Projector onto the (reshaped) head shell grown by `grow`."""
    def f(p):
        n = rig.head_normal(p, grow)
        # walk along the normal onto the shell (a few Newton steps on F = 1)
        q = Vector(p)
        for _ in range(6):
            fv = rig._head_F(q, grow)
            g = rig.head_normal(q, grow)
            q = q - g * (fv - 1.0) * 0.12
        return q, rig.head_normal(q, grow)
    return f


# ------------------------------------------------------------------ builders
def decal(mb, outline, place, style, wfn, lift=0.0015, thick=0.004, side_style=None, sink=0.002):
    """A raised patch: flat top fan + sides sunk just under the surface."""
    c, nc = place(0.0, 0.0)
    top, bot = [], []
    for (u, v) in outline:
        p, n = place(u, v)
        q = p + n * (lift + thick)
        top.append(mb.vert(q, style, (0, q.z), wfn(q)))
        b = p - n * sink
        bot.append(mb.vert(b, side_style or style, (0, b.z), wfn(b)))
    ct = c + nc * (lift + thick)
    ci = mb.vert(ct, style, (0, ct.z), wfn(ct))
    m = len(outline)
    for i in range(m):
        j = (i + 1) % m
        mb.face(ci, top[i], top[j])
        mb.face(bot[i], bot[j], top[j], top[i])


def strip_decal(mb, outer, inner, place, style, wfn, lift=0.0015, thick=0.004, sink=0.002):
    """A raised strip between two polylines of equal length (crescents, bands).
    `outer` must run so that outer -> inner is to the left (CCW seen from outside)."""
    n = len(outer)
    to, ti, bo, bi = [], [], [], []
    for (uo, vo), (ui, vi) in zip(outer, inner):
        po, no = place(uo, vo)
        pi_, ni = place(ui, vi)
        to.append(mb.vert(po + no * (lift + thick), style, (0, po.z), wfn(po)))
        ti.append(mb.vert(pi_ + ni * (lift + thick), style, (0, pi_.z), wfn(pi_)))
        bo.append(mb.vert(po - no * sink, style, (0, po.z), wfn(po)))
        bi.append(mb.vert(pi_ - ni * sink, style, (0, pi_.z), wfn(pi_)))
    for k in range(n - 1):
        mb.face(to[k], to[k + 1], ti[k + 1], ti[k])
        mb.face(bo[k], bo[k + 1], to[k + 1], to[k])      # outer wall
        mb.face(bi[k + 1], bi[k], ti[k], ti[k + 1])      # inner wall
    mb.face(to[0], ti[0], bi[0], bo[0])
    mb.face(ti[-1], to[-1], bo[-1], bi[-1])


def surface_tube(mb, uv_path, place, radius, style, wfn, lift=0.0, segs=8, flat=1.0, closed=False, cap='round'):
    """A tube (piping, chenille stroke, strap) following a (u, v) path on a surface."""
    pts = []
    nrm = []
    for (u, v) in uv_path:
        p, n = place(u, v)
        pts.append(p + n * (lift + radius * flat * 0.6))
        nrm.append(n)
    hint = sum(nrm, Vector()).normalized()
    sweep(mb, pts, [(radius * flat, radius)] * len(pts), style, lambda p, sv, i: wfn(p), segs=segs, cap_start=None if closed else cap,
          cap_end=None if closed else cap, twist_hint=hint, closed=closed)


def path_tube(mb, pts, radius, style, wfn, segs=8, hint=FWD, flat=1.0, cap='round', closed=False):
    sweep(mb, list(pts), [(radius * flat, radius)] * len(pts), style, lambda p, sv, i: wfn(p), segs=segs,
          cap_start=None if closed else cap, cap_end=None if closed else cap, twist_hint=hint, closed=closed)


def open_shell(mb, zs, grow_fn, gap_fn, style, wfn, segs=36, colfn=None, rib=None):
    """Torso shell between heights `zs` (ascending) that leaves a front
    opening: at height z the shell spans the angles 90deg + gap_fn(z) ..
    450deg - gap_fn(z) around the back (gap in radians, 0 = closed).
    rib(th, z) -> extra radius (knit ribs).  Returns (left_edge, right_edge)
    vertex positions (character's left = +th side of the front)."""
    rows = []
    left, right = [], []
    for z in zs:
        g = gap_fn(z)
        row = []
        for k in range(segs + 1):
            th = math.pi * 0.5 + g + (2 * math.pi - 2 * g) * k / segs
            r = max(torso_r(z), 0.06) + grow_fn(z) + (rib(th, z) if rib else 0.0)
            p = Vector((math.cos(th) * r, TORSO_CY + math.sin(th) * r * TORSO_RY, z))
            col = colfn(p, z, th) if colfn else None
            row.append(mb.vert(p, style, (k / segs, z), wfn(p), '', None, col))
        rows.append(row)
        left.append(Vector(mb.v[row[0]]))
        right.append(Vector(mb.v[row[-1]]))
    mb.grid(rows, closed_u=False)
    return left, right


def skin_arm(mb, side, s0, skin_style, segs=12):
    """Bare arm from s0 (m from the shoulder) to the wrist (hands are on base)."""
    from parts import _arm_path, _path_s, arm_radius
    path = _arm_path(side, s0, rig.UPPER_LEN + rig.FORE_LEN - 0.005)
    s = _path_s(path)
    sweep(mb, path, [(arm_radius(s0 + v) - 0.002, arm_radius(s0 + v) - 0.002) for v in s], skin_style,
          lambda p, sv, i: rig.arm_w(p, side), segs=segs, cap_start=None, cap_end=None, twist_hint=FWD)


def skin_leg(mb, side, top_z, bottom_z, skin_style, segs=14, grow=0.0):
    """Bare leg between two heights (the shoe or sock covers the rest)."""
    from parts import _dense_path, _path_s, leg_radius
    pts = rig.leg_path(side, 0.55)
    k, a = pts[1], pts[2]
    # clip the hip -> knee -> ankle polyline to [bottom_z, top_z]
    poly = []
    for p0, p1 in ((pts[0], k), (k, a)):
        for i in range(21):
            q = p0.lerp(p1, i / 20.0)
            if bottom_z <= q.z <= top_z and (not poly or (q - poly[-1]).length > 1e-5):
                poly.append(q)
    poly = _dense_path(poly, 0.02)
    s_hip = []
    for q in poly:
        s_hip.append(rig.leg_s(q, side))
    sweep(mb, poly, [(leg_radius(v) + grow, (leg_radius(v) + grow) * 0.95) for v in s_hip], skin_style,
          lambda p, sv, i: rig.leg_w(p, side), segs=segs, cap_start=None, cap_end=None, twist_hint=FWD)


def leg_tube(mb, side, top_z, bottom_z, grow, style, segs=16, colfn=None, flat_end=False, rfn=None):
    """A trouser/sock tube between two heights along the leg."""
    from parts import _dense_path, leg_radius
    pts = rig.leg_path(side, 0.55)
    k, a = pts[1], pts[2]
    poly = []
    for p0, p1 in ((pts[0], k), (k, a)):
        for i in range(31):
            q = p0.lerp(p1, i / 30.0)
            if bottom_z - 1e-6 <= q.z <= top_z + 1e-6 and (not poly or (q - poly[-1]).length > 1e-5):
                poly.append(q)
    poly = _dense_path(poly, 0.02)
    radii = []
    for q in poly:
        r = leg_radius(rig.leg_s(q, side)) + (grow(q.z) if callable(grow) else grow)
        radii.append((r, r * 0.96))
    sweep(mb, poly, radii, style, lambda p, sv, i: rig.leg_w(p, side), segs=segs, cap_start=None,
          cap_end='flat' if flat_end else None, twist_hint=FWD, colfn=colfn)
    return poly, radii


def ring_on_leg(mb, side, z, grow, tube, style, segs=20, squash=0.85):
    from parts import leg_radius
    from geo import torus_profile
    pts = rig.leg_path(side, 0.55)
    k, a = pts[1], pts[2]
    if z >= k.z:
        p0, p1 = pts[0], k
    else:
        p0, p1 = k, a
    t = (p0.z - z) / (p0.z - p1.z)
    c = p0.lerp(p1, t)
    d = (p1 - p0).normalized()
    r = leg_radius(rig.leg_s(c, side)) + grow
    lathe(mb, c, rot_align(-d, FWD), torus_profile(0.0, r, tube, 10, squash), style, lambda p: rig.leg_w(p, side), segs=segs,
          closed_profile=True)


def ring_on_arm(mb, side, s, grow, tube, style, segs=20, squash=0.85):
    from parts import arm_radius
    from geo import torus_profile
    d = rig.arm_dir(side)
    c = rig.shoulder(side) + d * s
    lathe(mb, c, rot_align(d, FWD), torus_profile(0.0, arm_radius(s) + grow, tube, 10, squash), style,
          lambda p: rig.arm_w(p, side), segs=segs, closed_profile=True)


def bumpy(mb, center, radii, style, wfn, segs=16, rings=12, amp=0.12, freq=7, rot=None, seed=1):
    """A soft, knobbly sphere (pompoms, fluff): an ellipsoid with a
    deterministic bump field on its radius."""
    def deform(lp):
        n = lp.normalized() if lp.length > 1e-9 else Vector((0, 0, 1))
        b = (math.sin(freq * n.x + seed) * math.sin(freq * n.y + 2 * seed) * math.sin(freq * n.z + 3 * seed))
        return lp * (1.0 + amp * b)
    ellipsoid(mb, center, radii, style, wfn, segs=segs, rings=rings, rot=rot, deform=deform)
