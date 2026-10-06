"""Pass 8: the six rotating Shop outfits and their own headwear.

    midnight_mechanic  'mechanic'                      (work boots included)
    moonwalk_cadet     'cadet' + 'acc_cadet_cap'       (boots included; the cap + lifted visor with no hat)
    pumpkin_pajamas    'pumpkin' + 'acc_pumpkin_cap'   (striped socks included; the cap with no hat)
    arcade_sprinter    'arcade'                        (high-tops included)
    cloud_nine         'cloud'                         (hood up, cushioned slippers included)
    bedtime_bandit     'bandit'                        (hood with ears up, footed, ringed tail)

Original designs written for this project.  Every outfit is one mesh part
(one draw call) on the shared rig, built from the same kit as the V6 outfits
(parts.py, kit6.py, outfits_v6.py); headwear is a separate part shown the way
the V6 courier cap is (Cosmetics.OUTFIT_HEADWEAR).  Palettes are fixed per
design.  Nothing is simulated: hoods, ears, visor, stem and tail are rigid on
one bone (head or hips), gloves and footwear follow the hand and foot
exactly as the base mittens and the V6 boots do, so they stay contained
through every clip (tools/character/outfit_check.py measures it).  No part
uses the emissive class (no always-on lights).  Names match
Cosmetics.OUTFIT_PARTS / OUTFIT_HEADWEAR in game/src/view/cosmetics.gd.
"""
import math
from mathutils import Vector, Matrix

import rig
from geo import (MeshBuilder, Style, sweep, ellipsoid, lathe, slab, torus_profile, rot_align, rot_x, rot_y, rot_z, smoothstep, lerp,
                 srgb, T_NONE, MAT_CLOTH, MAT_RUBBER, MAT_GLOSS, MAT_METAL, MAT_SATIN, MAT_LENS)
from rig import torso_w, arm_w, leg_w, rigid, torso_r, shoulder, arm_dir, HEAD_C, HEAD_R, HEAD_P, TORSO_RY, TORSO_CY
import parts as P
from parts import SKIN, UP, FWD, SIDES, torso_lathe, sleeves, pelvis, placket_and_buttons, _dense_path, _smooth_path, _foot_outline
import kit6 as K
from kit6 import decal, strip_decal, place_front, place_back, place_planar, head_project, torso_at
from outfits_v6 import S, sleeve_project, arm_point, leg_point, leg_project, _rib_leg, _rib_band, K_arm_line


# ------------------------------------------------------------------ shared helpers
def foot_w(sx):
    """Footwear weights (the V6 rain boots): the foot below 11 cm, the shin above.
    Pass 9: round the ankle (the collar, a shaft, a paw's cuff), where the
    trouser leg goes in, they turn into the leg's own weights (leg_w) going
    up, so the footwear and the leg in it bend at the ankle together (by
    height alone they parted by up to 2.6 cm in a hard landing); the foot
    in front keeps the height rule."""
    sfx = '.L' if sx < 0 else '.R'
    cx = rig.HIP_X * sx

    def w(p):
        base = rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03)
        m = smoothstep(0.075, 0.12, p.z) * (1.0 - smoothstep(0.07, 0.12, p.y))
        if m <= 0.0:
            return base
        return rig.mix((base, 1.0 - m), (leg_w(Vector((cx + (p.x - cx), p.y, p.z)), sx), m))
    return w


def gloves(mb, style, cuff_style, g=0.0045, cuff=(-0.05, 0.014), cuff_r=(0.047, 0.045), roll=None, segs=16, rings=10):
    """Gloves over the base mittens: the mitten's own palm and thumb (parts.
    build_base) grown by `g`, with the mitten's weights, so they follow the
    hand exactly; a gauntlet cuff round the wrist from cuff[0] to cuff[1]
    (metres along the arm from the wrist) at radii cuff_r; roll: a rolled
    edge (tube radius) at the open end."""
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        d = arm_dir(sx)
        w = rig.wrist(sx)
        R = rot_align(d, FWD)
        X = R @ Vector((1, 0, 0))
        Y = R @ Vector((0, 1, 0))
        hwf = lambda p, sfx=sfx, w=w, d=d: rig.seg_weights((p - w).dot(d), [('forearm' + sfx, 0.0), ('hand' + sfx, None)], 0.012)
        rz = 0.065 + g

        def palm(lp, rz=rz):
            t = lp.z / rz
            narrow = 1.0 - 0.16 * smoothstep(0.1, -1.0, t)
            cup = 0.007 * max(0.0, t) ** 2
            return Vector((lp.x * (1.0 - 0.1 * max(0.0, t)) + cup, lp.y * narrow, lp.z))
        ellipsoid(mb, w + d * 0.058, (0.034 + g, 0.051 + g, rz), style, hwf, segs=segs, rings=rings, rot=R, power=2.3, deform=palm)
        tdir = (d * 0.62 + Y * 0.66 + X * 0.42).normalized()
        t0 = w + d * 0.036 + Y * 0.026 + X * 0.007
        tp = [t0 + tdir * (0.043 * i / 4.0) for i in range(5)]
        sweep(mb, tp, [(lerp(0.0185, 0.0155, i / 4.0) + g,) * 2 for i in range(5)], style, lambda p, sv, i, hwf=hwf: hwf(p), segs=8,
              twist_hint=X, cap_start=None)
        c0, c1 = cuff
        r0, r1 = cuff_r
        prof = [(c0 + 0.002, r0 - 0.006), (c0, r0 - 0.001), (c0 + 0.006, r0), (c1 - 0.004, r1), (c1, r1 - 0.004), (c1 + 0.002, r1 - 0.012)]
        lathe(mb, w, R, prof, cuff_style, hwf, segs=14)
        if roll:
            lathe(mb, w + d * (c0 + roll * 0.4), R, torus_profile(0.0, r0, roll, 5, 1.0), cuff_style, hwf, segs=14, closed_profile=True)


def gear_outline(r, teeth=8, depth=0.26, per=4):
    out = []
    n = teeth * per
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        tooth = 1.0 if (i % per) < per / 2 else 0.0
        rr = r * (1.0 - depth) + r * depth * tooth
        out.append((math.cos(a) * rr, math.sin(a) * rr))
    return out


def cloud_outline(w, h, n=36, bumps=((-0.55, 0.0, 0.45), (-0.15, 0.25, 0.55), (0.3, 0.2, 0.5), (0.6, -0.05, 0.4), (0.0, -0.2, 0.5))):
    """A cumulus outline (union of circles, in units of w/2 and h/2), star-shaped
    about the centre: the furthest circle boundary along each ray."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        dx, dy = math.cos(a), math.sin(a)
        best = 0.0
        for cx, cy, r in bumps:
            # ray from origin hits circle (cx, cy, r): solve |t d - c| = r
            b = dx * cx + dy * cy
            disc = b * b - (cx * cx + cy * cy - r * r)
            if disc >= 0:
                best = max(best, b + math.sqrt(disc))
        out.append((dx * best * w / 2, dy * best * h / 2))
    return out


def stitches(mb, outline, place, style, wfn, lift, scale=0.82, r=0.0015, dash=0.008, gap=0.0055):
    """A running stitch just inside a patch's edge: short thread dashes along
    the outline (scaled about its centre), lying on the patch top."""
    pts = [Vector((u * scale, v * scale, 0.0)) for u, v in outline]
    pts.append(pts[0])
    lens = [0.0]
    for a, b in zip(pts, pts[1:]):
        lens.append(lens[-1] + (b - a).length)
    total = lens[-1]

    def at(s):
        s = s % total
        for i in range(len(pts) - 1):
            if lens[i] <= s <= lens[i + 1]:
                t = (s - lens[i]) / max(1e-9, lens[i + 1] - lens[i])
                q = pts[i].lerp(pts[i + 1], t)
                return q.x, q.y
        return pts[0].x, pts[0].y
    s = 0.0
    while s + dash <= total - gap * 0.5:
        seg = []
        for k in range(2):
            u, v = at(s + dash * k)
            p, n = place(u, v)
            seg.append(p + n * (lift + r * 0.4))
        K.path_tube(mb, seg, r, style, wfn, segs=4, hint=place(0.0, 0.0)[1], cap='flat')
        s += dash + gap


def shell(mb, g, hairline, style, wfn, segs=48, rows=12, tuck=0.012, bulge=None, colfn=None):
    """parts.hair_shell with a per-vertex colour (ang, z) -> Style/None, for
    caps whose panels or grooves are coloured."""
    rz = HEAD_R[2] + g
    gx = (lambda a, z: g + bulge(a, z)) if bulge is not None else (lambda a, z: g)
    ztop = HEAD_C.z + rz * 0.9995
    angs = [-math.pi + 2.0 * math.pi * k / segs for k in range(segs)]
    angs.reverse()
    edge = [hairline(a) for a in angs]
    rows_idx = []
    row = []
    for a, z0 in zip(angs, edge):
        q = P._shell_point(a, z0 + 0.004, gx(a, z0 + 0.004) - tuck)
        row.append(mb.vert(q, style, (0, q.z), wfn(q), '', None, colfn(a, z0) if colfn else None))
    rows_idx.append(row)
    for r in range(rows):
        u = r / float(rows)
        row = []
        for a, z0 in zip(angs, edge):
            t0 = math.acos(max(-1.0, min(1.0, (z0 - HEAD_C.z) / rz)))
            t = t0 * (1.0 - u)
            z = min(HEAD_C.z + rz * math.cos(t), ztop)
            q = P._shell_point(a, z, gx(a, z))
            row.append(mb.vert(q, style, (0, q.z), wfn(q), '', None, colfn(a, z) if colfn else None))
        rows_idx.append(row)
    top = Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + rz))
    pole = mb.vert(top, style, (0, top.z), wfn(top))
    mb.grid(rows_idx, True, None, pole)
    return angs, edge


def front(ang):
    """1 at the forehead (ang +-pi), 0 at the back (ang 0)."""
    return 0.5 - 0.5 * math.cos(ang)


def leg_tube_stripes(mb, sx, top_z, bottom_z, grow, style, bands, segs=14):
    """A sock/legging tube with horizontal stripes: bands = [(z0, z1, Style)]."""
    cf = lambda p, sv, a: next((st for z0, z1, st in bands if z0 <= p.z <= z1), None)
    K.leg_tube(mb, sx, top_z, bottom_z, grow, style, segs=segs, colfn=cf)


# ================================================================== MIDNIGHT MECHANIC
COBALT = S('#2f5fbf', rough=0.86)
COBALT_D = S('#244b98', rough=0.88)
COBALT_SEAM = S('#1d3d7c', rough=0.9)
TOOL_ORANGE = S('#f0873a', rough=0.75)
THREAD = S('#f6e7c4', rough=0.8)
GLOVE_CREAM = S('#f1e4c3', rough=0.82)
GLOVE_CUFF = S('#e2d0a6', rough=0.85)
ZIP_METAL = S('#c9ced8', rough=0.3, mat=MAT_METAL)
BUCKLE_METAL = S('#d7dbe3', rough=0.28, mat=MAT_METAL)
BOOT_TAN = S('#a8703f', rough=0.5, mat=MAT_RUBBER)
BOOT_TAN_D = S('#8a5a31', rough=0.5, mat=MAT_RUBBER)
BOOT_SOLE = S('#3b2f29', rough=0.7, mat=MAT_RUBBER)
LACE = S('#f2e6cc', rough=0.8)


def _work_boot(mb, sx):
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, toe=0.185, heel=-0.08, w_heel=0.06, w_toe=0.074, n=20), 0.0, 0.038, BOOT_SOLE, fw, bevel=0.011)
    # welt stitching round the sole's top edge
    ring = [Vector((x + (x - cx) * 0.03, y, 0.04)) for x, y in _foot_outline(sx, toe=0.186, heel=-0.081, w_heel=0.06, w_toe=0.074, n=20)]
    K.path_tube(mb, ring, 0.0028, LACE, fw, segs=3, hint=UP, flat=1.3, closed=True)
    # upper with a rounded, darker toe cap
    ellipsoid(mb, Vector((cx, 0.05, 0.034)), (0.066, 0.13, 0.084), BOOT_TAN, fw, segs=18, rings=11, cut_below=-0.06,
              colfn=lambda p, lp: BOOT_TAN_D if (p.y > 0.115 and p.z < 0.1) else None)
    # shaft with a padded collar and a pull tab
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3),
          [(0.05, 0.066), (0.1, 0.064), (0.15, 0.066), (0.172, 0.07), (0.18, 0.066), (0.168, 0.058)], BOOT_TAN, fw, segs=18,
          ry_scale=1.05)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), torus_profile(0.172, 0.069, 0.009, 5, 1.0), BOOT_TAN_D, fw, segs=16,
          closed_profile=True, ry_scale=1.05)
    ellipsoid(mb, Vector((cx, -0.076, 0.168)), (0.013, 0.006, 0.024), BOOT_TAN_D, fw, segs=8, rings=6)
    # tongue laces: four bars with metal eyelets
    for i in range(3):
        y = 0.036 + i * 0.03
        z = 0.034 + 0.084 * math.sqrt(max(0.0, 1.0 - ((y - 0.05) / 0.13) ** 2)) - 0.002 + i * 0.012
        ellipsoid(mb, Vector((cx, y + 0.004 * i, z)), (0.03, 0.006, 0.005), LACE, fw, segs=6, rings=4, rot=rot_x(-30))


def build_mechanic():
    mb = MeshBuilder('mechanic')
    g = 0.02
    torso_lathe(mb, COBALT, g, 0.50, 0.872, top_open_r=0.09)
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.872, 0.086 + g * 0.5, 0.019, 7), COBALT_D,
          torso_w, segs=24, closed_profile=True, ry_scale=0.92)
    for sx in SIDES:
        p, n = P.on_torso(0.05 * sx, 0.836, g + 0.004)
        ellipsoid(mb, p, (0.028, 0.036, 0.006), COBALT_D, torso_w, segs=10, rings=6, rot=rot_align(n, UP) @ rot_z(38 * sx), power=2.4)
    # zip front
    zp = place_front(0.0, 0.0, g)
    K.surface_tube(mb, [(0.0, z) for z in [0.53 + 0.025 * i for i in range(13)]], zp, 0.0052, ZIP_METAL, torso_w, flat=0.45, segs=6)
    p, n = torso_at(0.0, 0.83, g + 0.008)
    ellipsoid(mb, p + Vector((0, 0, -0.012)), (0.008, 0.004, 0.016), ZIP_METAL, torso_w, segs=8, rings=6, rot=rot_align(n, UP))
    # back yoke seam
    yoke = [torso_at(lerp(-0.15, 0.15, k / 10), 0.79 - 0.012 * math.sin(math.pi * k / 10), g + 0.002, back=True)[0] for k in range(11)]
    K.path_tube(mb, yoke, 0.0032, COBALT_SEAM, torso_w, segs=5, hint=-FWD)
    # sleeves rolled to mid-forearm: a thick double roll, bare forearms, cream work gloves
    s_end = 0.205
    sleeves(mb, COBALT, 0.018, s1=s_end, cuff_style=COBALT_D, cuff_tube=0.018, lod=1)
    for sx in SIDES:
        # (Pass 9: the rolls lie on the eased sleeve end, ~0.6 cm off the
        # forearm; at the full sleeve width they were 3.4 cm out, a ring
        # floating round the bare arm)
        for ds, tube, st in ((-0.022, 0.0105, COBALT_D), (-0.004, 0.0095, COBALT)):
            K.ring_on_arm(mb, sx, s_end + ds, 0.0, tube, st, segs=14, squash=1.0, n=5,
                          r=P.sleeve_r(s_end + ds, 0.018, s_end) + tube * 0.55)
        K.skin_arm(mb, sx, s_end - 0.03, SKIN, segs=10)
    gloves(mb, GLOVE_CREAM, GLOVE_CUFF, cuff=(-0.052, 0.012), cuff_r=(0.047, 0.044), roll=0.006)
    # chest: stitched orange wrench patch (left), flap pocket with a snap (right)
    pl = place_front(-0.098, 0.765, g)
    rr = K.rounded_rect(0.082, 0.06, 0.012)
    decal(mb, rr, pl, TOOL_ORANGE, torso_w, thick=0.003)
    stitches(mb, rr, pl, THREAD, torso_w, lift=0.0045)
    top = place_front(-0.098, 0.765, g + 0.0045)
    o, i = K.crescent(0.012, 0.62, 0.62, 10, math.radians(35))
    strip_decal(mb, o, i, lambda u, v: top(u + 0.016, v + 0.01), THREAD, torso_w, thick=0.0016)
    K.surface_tube(mb, [(0.008, 0.002), (-0.022, -0.016)], top, 0.0042, THREAD, torso_w, segs=5, flat=0.45)
    decal(mb, K.rounded_rect(0.07, 0.066, 0.01), place_front(0.1, 0.735, g), COBALT_D, torso_w, thick=0.004)
    decal(mb, K.rounded_rect(0.076, 0.024, 0.009), place_front(0.1, 0.766, g + 0.004), COBALT, torso_w, thick=0.004)
    pp, pn = torso_at(0.1, 0.762, g + 0.009)
    ellipsoid(mb, pp, (0.0075, 0.0075, 0.0035), ZIP_METAL, torso_w, segs=8, rings=4, rot=rot_align(pn, UP))
    # back: a big stitched patch with a gear (reads from the follow camera)
    bp = place_back(0.0, 0.69, g)
    br = K.rounded_rect(0.15, 0.085, 0.016)
    decal(mb, br, bp, TOOL_ORANGE, torso_w, thick=0.003)
    stitches(mb, br, bp, THREAD, torso_w, lift=0.0045, scale=0.88)
    gtop = place_back(0.0, 0.69, g + 0.0045)
    decal(mb, gear_outline(0.027), gtop, THREAD, torso_w, thick=0.0018)
    decal(mb, K.circle_outline(0.009, 10), place_back(0.0, 0.69, g + 0.0065), COBALT_D, torso_w, thick=0.0012)
    # round gear patch on the right upper arm
    prj = sleeve_project(1, 0.018)
    c, nn = arm_point(1, 0.085, 35.0, P.arm_radius(0.085) + 0.018)
    ap = place_planar(c, nn, arm_dir(1), prj)
    circ = K.circle_outline(0.022, 18)
    decal(mb, circ, ap, THREAD, lambda q: arm_w(q, 1), thick=0.003, lift=0.002)
    stitches(mb, circ, ap, TOOL_ORANGE, lambda q: arm_w(q, 1), lift=0.0055, scale=0.86, dash=0.006, gap=0.004)
    decal(mb, gear_outline(0.012, 8, 0.3), place_planar(c + nn * 0.005, nn, arm_dir(1), lambda q: (lambda a: (a[0] + a[1] * 0.005, a[1]))(prj(q))),
          COBALT_SEAM, lambda q: arm_w(q, 1), thick=0.0016)
    # webbing belt with a metal buckle
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.567, torso_r(0.567) + 0.03, 0.017, 6, 0.75), COBALT_SEAM,
          torso_w, segs=28, closed_profile=True, ry_scale=TORSO_RY)
    bp2, bn2 = torso_at(0.0, 0.567, 0.046)
    ellipsoid(mb, bp2, (0.026, 0.02, 0.006), BUCKLE_METAL, torso_w, segs=10, rings=6, rot=rot_align(bn2, UP), power=4.0)
    # trousers: knee patches, a cargo pocket, turned-up cuffs over the boots
    pelvis(mb, COBALT, 0.012, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.15, 0.02, COBALT, segs=14)
        K.ring_on_leg(mb, sx, 0.158, 0.026, 0.012, COBALT_D, segs=14, n=5)
        K.ring_on_leg(mb, sx, 0.182, 0.024, 0.01, COBALT_D, segs=14, n=5)
        prj = leg_project(sx, 0.02)
        c, nn = leg_point(sx, 0.31, 90.0, 0.02)
        kp = place_planar(c, nn, UP, prj)
        kr = K.rounded_rect(0.07, 0.07, 0.014)
        decal(mb, kr, kp, COBALT_D, lambda q, sx=sx: leg_w(q, sx), thick=0.003, lift=0.002)
    prj = leg_project(1, 0.02)
    c, nn = leg_point(1, 0.45, 0.0, 0.02)
    decal(mb, K.rounded_rect(0.062, 0.075, 0.01), place_planar(c, nn, UP, prj), COBALT_D, lambda q: leg_w(q, 1), thick=0.005)
    decal(mb, K.rounded_rect(0.068, 0.024, 0.008), place_planar(c + Vector((0, 0, 0.032)), nn, UP, leg_project(1, 0.025)), COBALT,
          lambda q: leg_w(q, 1), thick=0.004)
    for sx in SIDES:
        _work_boot(mb, sx)
    return mb


# ================================================================== MOONWALK CADET
SUIT = S('#f2eee3', rough=0.72)
SUIT_SEAM = S('#d6d0c1', rough=0.8)
TEAL = S('#26a69e', rough=0.45, mat=MAT_RUBBER)
TEAL_CLOTH = S('#2aa9a1', rough=0.75)
TEAL_METAL = S('#3fb8b0', rough=0.3, mat=MAT_METAL)
PANEL = S('#566073', rough=0.45, mat=MAT_GLOSS)
BTN_CORAL = S('#ff7867', rough=0.3, mat=MAT_GLOSS)
BTN_YELLOW = S('#ffd35a', rough=0.3, mat=MAT_GLOSS)
BTN_TEAL = S('#5fe0d6', rough=0.3, mat=MAT_GLOSS)
PATCH_NAVY = S('#2b3570', rough=0.8)
PATCH_GOLD = S('#f2c75e', rough=0.35, mat=MAT_METAL)
VISOR_LO = srgb('#3f9fae')
VISOR_HI = srgb('#a9e4e6')
VISOR = Style('#ffffff', T_NONE, 0.18, MAT_LENS)
VISOR_IN = S('#2c5f69', rough=0.3, mat=MAT_GLOSS)


def _quilted_profile(z0, z1, grow, period, depth, step=0.016, z_quilt=(0.5, 0.82)):
    prof = []
    z = z0
    while z < z1 - 1e-6:
        q = 0.0
        if z_quilt[0] <= z <= z_quilt[1]:
            q = depth * math.sin(math.pi * (z - z_quilt[0]) / period) ** 2
        prof.append((z, max(torso_r(z), 0.06) + grow + q))
        z += step
    prof.append((z1, max(torso_r(z1), 0.06) + grow))
    return prof


def _space_boot(mb, sx):
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, toe=0.19, heel=-0.085, w_heel=0.066, w_toe=0.08, n=20), 0.0, 0.042, TEAL, fw, bevel=0.013)
    ellipsoid(mb, Vector((cx, 0.052, 0.04)), (0.077, 0.138, 0.085), SUIT, fw, segs=18, rings=11, cut_below=-0.25)
    # compact shaft wide enough to take the suit's legs, a grey cuff ring and an instep strap
    lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3),
          [(0.05, 0.08), (0.1, 0.092), (0.17, 0.098), (0.2, 0.1), (0.207, 0.096), (0.198, 0.088)], SUIT, fw, segs=18, ry_scale=1.04)
    lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3), torus_profile(0.2, 0.099, 0.01, 5, 1.0), PANEL, fw, segs=18,
          closed_profile=True, ry_scale=1.04)
    # an instep strap lying on the upper (its section at y = 0.07, 4 mm proud)
    k = math.sqrt(1.0 - ((0.07 - 0.052) / 0.138) ** 2)
    out = [Vector((cx + (0.077 * k + 0.004) * math.cos(math.radians(a)), 0.07, 0.04 + (0.085 * k + 0.004) * math.sin(math.radians(a))))
           for a in range(5, 176, 15)]
    K.path_tube(mb, out, 0.009, TEAL, fw, segs=6, hint=FWD, flat=0.45, cap='flat')


# the life-support pack (outfit_check.py tests the arms against it)
PACK_C = Vector((0.0, -0.232, 0.715))
PACK_R = (0.105, 0.046, 0.115)
PACK_P = 3.4


def build_cadet():
    mb = MeshBuilder('cadet')
    g = 0.034
    prof = [(0.468, torso_r(0.468) + 0.012)] + _quilted_profile(0.48, 0.872, g, 0.08, 0.007)
    prof += [(0.876, 0.098), (0.86, 0.09)]
    seam = lambda p, z, th: SUIT_SEAM if (0.5 <= z <= 0.82 and math.sin(math.pi * (z - 0.5) / 0.08) ** 2 < 0.06) else None
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, SUIT, torso_w, segs=30, ry_scale=TORSO_RY, colfn=seam)
    # chunky teal neck ring (where a helmet would lock on), padded collar under it
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.872, 0.118, 0.021, 8, 0.9), TEAL_METAL, torso_w,
          segs=28, closed_profile=True, ry_scale=0.92)
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), [(0.85, 0.13), (0.86, 0.134), (0.895, 0.104), (0.9, 0.096)], SUIT,
          torso_w, segs=28, ry_scale=0.92)
    # teal belt and chest stripe, a control panel with three buttons and a slider
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.56, torso_r(0.56) + g + 0.006, 0.015, 6, 0.8), TEAL_CLOTH,
          torso_w, segs=30, closed_profile=True, ry_scale=TORSO_RY)
    p, n = torso_at(0.0, 0.56, g + 0.024)
    ellipsoid(mb, p, (0.03, 0.022, 0.007), TEAL_METAL, torso_w, segs=10, rings=6, rot=rot_align(n, UP), power=4.0)
    for sx in SIDES:
        st = [torso_at(sx * lerp(0.07, 0.165, k / 8), lerp(0.835, 0.79, k / 8), g + 0.0025)[0] for k in range(9)]
        K.path_tube(mb, st, 0.006, TEAL_CLOTH, torso_w, segs=5, hint=FWD, flat=0.5, cap='flat')
    p, n = torso_at(0.0, 0.69, g + 0.012)
    R = rot_align(n, UP)
    ellipsoid(mb, p, (0.07, 0.048, 0.014), PANEL, torso_w, segs=16, rings=8, rot=R, power=4.0)
    up = R @ Vector((0, 1, 0))
    side = R @ Vector((1, 0, 0))
    for k, st in enumerate((BTN_CORAL, BTN_YELLOW, BTN_TEAL)):
        ellipsoid(mb, p + n * 0.012 + side * (0.036 - 0.03 * k) + up * 0.012, (0.0095, 0.0095, 0.006), st, torso_w, segs=10, rings=6,
                  rot=R)
    ellipsoid(mb, p + n * 0.011 - up * 0.02, (0.04, 0.005, 0.004), BTN_TEAL, torso_w, segs=10, rings=4, rot=R)
    ellipsoid(mb, p + n * 0.014 - up * 0.02 + side * 0.012, (0.006, 0.008, 0.006), SUIT, torso_w, segs=8, rings=4, rot=R)
    # puffy sleeves with quilting seams, a mission patch, ivory gloves with teal gauntlets
    sleeves(mb, SUIT, 0.03, cuff_style=None, lod=1)
    for sx in SIDES:
        for s in (0.1, 0.2):
            K.ring_on_arm(mb, sx, s, 0.03, 0.005, SUIT_SEAM, segs=14, squash=1.0, n=4)
        pts = [K_arm_line(sx, 0.02 + 0.25 * k / 8, 0.0, 0.03)[0] for k in range(9)]
        K.path_tube(mb, pts, 0.004, TEAL_CLOTH, lambda q, sx=sx: arm_w(q, sx), segs=4, hint=UP, cap='flat')
    gloves(mb, SUIT, TEAL, cuff=(-0.055, 0.008), cuff_r=(0.078, 0.06), roll=0.009)
    prj = sleeve_project(-1, 0.03)
    c, nn = arm_point(-1, 0.075, 30.0, P.arm_radius(0.075) + 0.03)
    mp = place_planar(c, nn, arm_dir(-1), prj)
    decal(mb, K.circle_outline(0.026, 18), mp, PATCH_NAVY, lambda q: arm_w(q, -1), thick=0.003, lift=0.002)
    rim = [mp(0.0255 * math.cos(2 * math.pi * k / 18), 0.0255 * math.sin(2 * math.pi * k / 18)) for k in range(18)]
    K.path_tube(mb, [q + nq * 0.0048 for q, nq in rim], 0.0024, TEAL_CLOTH, lambda q: arm_w(q, -1), segs=4, hint=nn, closed=True)
    mtop = place_planar(c + nn * 0.005, nn, arm_dir(-1), lambda q: (lambda a: (a[0] + a[1] * 0.005, a[1]))(prj(q)))
    o, i = K.crescent(0.013, 0.78, 0.5, 10, math.radians(20))
    strip_decal(mb, o, i, mtop, PATCH_GOLD, lambda q: arm_w(q, -1), thick=0.0015)
    decal(mb, K.star_outline(0.006), lambda u, v: mtop(u - 0.009, v + 0.008), PATCH_GOLD, lambda q: arm_w(q, -1), thick=0.0015)
    # compact life-support pack on the back (rigid with the torso it sits on)
    pk = PACK_C
    ellipsoid(mb, pk, PACK_R, SUIT, torso_w, segs=16, rings=10, power=PACK_P)
    ellipsoid(mb, pk + Vector((0, -0.004, 0.1)), (0.09, 0.04, 0.03), TEAL, torso_w, segs=14, rings=6, power=3.0)
    ellipsoid(mb, pk + Vector((0.0, -0.043, -0.045)), (0.07, 0.007, 0.03), PANEL, torso_w, segs=12, rings=6, power=3.5)
    for sx in SIDES:
        ellipsoid(mb, pk + Vector((0.062 * sx, -0.012, 0.118)), (0.014, 0.014, 0.012), TEAL_METAL, torso_w, segs=8, rings=6)
    # puffy trousers with knee seams, tucked into compact boots
    pelvis(mb, SUIT, 0.02, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.17, 0.03, SUIT, segs=16)
        for z in (0.375, 0.245):
            K.ring_on_leg(mb, sx, z, 0.031, 0.005, SUIT_SEAM, segs=14, n=4)
        K.ring_on_leg(mb, sx, 0.31, 0.034, 0.008, TEAL_CLOTH, segs=14, n=5)
        _space_boot(mb, sx)
    K.clamp_legs(mb)   # (Pass 9: the boot collars off the midline with the legs)
    return mb


def cadet_cap_edge(ang):
    # forehead 1.30 (above the brows), lower over the ear discs, nape 1.2
    side = math.exp(-((abs(ang) - 1.55) / 0.42) ** 2)
    return 1.2 + 0.1 * front(ang) - 0.045 * side


VISOR_GROW = 0.072
VISOR_HALF = 1.05          # radians either side of the forehead
VISOR_Z = (1.365, 1.505)   # lower and upper edge at the centre (lifted, above the forehead)


def _visor_point(ang, t, grow):
    """Visor surface: around the forehead (ang near +-pi), t 0..1 from the
    lower to the upper edge; the edges dip a little toward the sides."""
    a = abs(abs(ang) - math.pi) / VISOR_HALF
    lo = VISOR_Z[0] - 0.035 * a * a
    hi = VISOR_Z[1] - 0.02 * a * a
    return P._shell_point(ang, lerp(lo, hi, t), grow)


def build_cadet_cap():
    """Padded cadet cap with teal ear discs and a clear visor lifted up over
    the forehead (worn with moonwalk_cadet and no hat).  The face stays open:
    the visor's lowest point is above the brows."""
    mb = MeshBuilder('acc_cadet_cap')
    hw = rigid('head')
    grow = 0.042
    shell(mb, grow, cadet_cap_edge, SUIT, hw, segs=44, rows=11, tuck=0.012)
    # rolled padded edge
    bead, bn = [], []
    for k in range(44):
        ang = -math.pi + 2 * math.pi * k / 44
        q = P._shell_point(ang, cadet_cap_edge(ang) + 0.006, grow)
        bead.append(q)
        bn.append(rig.head_normal(q, grow))
    K.ribbon(mb, bead, bn, 0.0085, 0.0055, SUIT_SEAM, hw, segs=6)
    # teal centre stripe from the forehead over the crown to the nape
    rz = HEAD_R[2] + grow
    th_f = math.acos((cadet_cap_edge(math.pi) + 0.014 - HEAD_C.z) / rz)
    th_b = math.acos((cadet_cap_edge(0.0) + 0.014 - HEAD_C.z) / rz)
    pts, nrm = [], []
    for j in range(21):
        th = lerp(th_f, -th_b, j / 20)
        ang = math.pi if th > 0 else 0.0
        z = HEAD_C.z + rz * math.cos(th)
        q = P._shell_point(ang, z, grow) if abs(th) > 0.02 else Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + rz))
        pts.append(q)
        nrm.append(rig.head_normal(q, grow))
    K.ribbon(mb, pts, nrm, 0.016, 0.003, TEAL_CLOTH, hw, closed=False, segs=6)
    # ear discs (comms pads) over the ears, with a pivot hub each
    hubs = []
    for sx in SIDES:
        Rr = rot_align(Vector((sx, 0, 0)), UP)
        c = Vector(((rig.head_side_x(1.17, 0.0, -0.005) - 0.004) * sx, -0.005, 1.17))
        lathe(mb, c, Rr, [(0.0, 0.0), (0.0, 0.066), (0.008, 0.072), (0.036, 0.072), (0.046, 0.064), (0.05, 0.0)], TEAL, hw, segs=20,
              ry_scale=1.1)
        lathe(mb, c + Vector((0.05 * sx, 0, 0)), Rr, [(-0.002, 0.03), (0.006, 0.028), (0.009, 0.0)], PANEL, hw, segs=14)
        hubs.append(c + Vector((0.054 * sx, 0, 0)))
    # the visor: a curved, slightly thick tinted lens held by two arms from the hubs
    n_a, n_t = 22, 6
    rows_out, rows_in = [], []
    for i in range(n_a + 1):
        ang = math.pi - VISOR_HALF + 2 * VISOR_HALF * i / n_a
        ro, ri = [], []
        for j in range(n_t + 1):
            t = j / n_t
            qo = _visor_point(ang, t, VISOR_GROW)
            qi = _visor_point(ang, t, VISOR_GROW - 0.006)
            tint = Vector(VISOR_LO).lerp(Vector(VISOR_HI), smoothstep(0.0, 1.0, t))
            gl = math.exp(-((t - 0.72) / 0.12) ** 2 - ((i / n_a - 0.36) / 0.08) ** 2) * 0.6
            colv = tint.lerp(Vector((0.94, 0.99, 1.0)), gl)
            vo = mb.vert(qo, VISOR, (0, qo.z), hw(qo), '', None, (colv.x, colv.y, colv.z))
            vi = mb.vert(qi, VISOR_IN, (0, qi.z), hw(qi))
            # V8-style analytic normal on the lens side: the shell's own normal
            mb.nrm[vo] = rig.head_normal(qo, VISOR_GROW)
            ro.append(vo)
            ri.append(vi)
        rows_out.append(ro)
        rows_in.append(ri)
    for i in range(n_a):
        for j in range(n_t):
            a, b, c2, d = rows_out[i][j], rows_out[i + 1][j], rows_out[i + 1][j + 1], rows_out[i][j + 1]
            mb.face(a, d, c2, b)
            a, b, c2, d = rows_in[i][j], rows_in[i + 1][j], rows_in[i + 1][j + 1], rows_in[i][j + 1]
            mb.face(a, b, c2, d)
    # teal frame round the lens (closes its edge)
    rim = []
    for i in range(n_a + 1):
        rim.append(_visor_point(math.pi - VISOR_HALF + 2 * VISOR_HALF * i / n_a, 0.0, VISOR_GROW - 0.003))
    for j in range(1, n_t + 1):
        rim.append(_visor_point(math.pi + VISOR_HALF, j / n_t, VISOR_GROW - 0.003))
    for i in range(n_a - 1, -1, -1):
        rim.append(_visor_point(math.pi - VISOR_HALF + 2 * VISOR_HALF * i / n_a, 1.0, VISOR_GROW - 0.003))
    for j in range(n_t - 1, 0, -1):
        rim.append(_visor_point(math.pi - VISOR_HALF, j / n_t, VISOR_GROW - 0.003))
    K.path_tube(mb, rim, 0.0062, TEAL, hw, segs=5, hint=UP, closed=True)
    # arms: from each hub up the side of the cap to the visor's end
    for sx, hub in zip(SIDES, hubs):
        # (ang +pi/2 is the character's left, -x: the visor's left end is at
        # pi - VISOR_HALF, its right end at -(pi - VISOR_HALF))
        end = _visor_point((math.pi - VISOR_HALF) * (-sx), 0.5, VISOR_GROW - 0.003)
        ctrl = [hub]
        for k in range(1, 6):
            t = k / 6
            ctrl.append(head_project(lerp(0.05, VISOR_GROW - 0.003, t))(hub.lerp(end, t))[0])
        ctrl.append(end)
        K.path_tube(mb, _smooth_path(ctrl, 0.024), 0.0075, TEAL, hw, segs=5, hint=Vector((sx, 0, 0)), flat=0.6)
    return mb


# ================================================================== PUMPKIN PAJAMAS
RUST = S('#cc6530', rough=0.9)
RUST_D = S('#a24a21', rough=0.92)
P_CREAM = S('#f7ebd3', rough=0.85)
LEAF = S('#5c8f3d', rough=0.8)
LEAF_D = S('#476f2f', rough=0.8)
STEM = S('#6e4a2a', rough=0.7)
STEM_D = S('#53361e', rough=0.75)
P_BTN = S('#6e4a2a', rough=0.35, mat=MAT_GLOSS)


def _lobe(th, n=8):
    """1 on a pumpkin lobe's crown, 0 in its groove."""
    return (0.5 + 0.5 * math.cos(n * th)) ** 0.45


def build_pumpkin():
    mb = MeshBuilder('pumpkin')
    z0, z1 = 0.49, 0.872
    belly = lambda z: 0.022 * math.sin(math.pi * smoothstep(z0, 0.86, z))
    prof = [(0.478, torso_r(0.478) + 0.012)]
    z = z0
    while z < z1 - 1e-6:
        prof.append((z, max(torso_r(z), 0.06) + 0.02 + belly(z)))
        z += 0.02
    prof += [(z1, max(torso_r(z1), 0.06) + 0.02), (z1 + 0.004, 0.09), (z1 - 0.02, 0.082)]
    fade = lambda z: math.sin(math.pi * smoothstep(z0, 0.86, z))
    rfn = lambda r, th, z: r - 0.012 * (1.0 - _lobe(th + math.pi / 2)) * fade(z)
    colf = lambda p, z, th: RUST_D if (_lobe(th + math.pi / 2) < 0.3 and fade(z) > 0.25) else None
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, RUST, torso_w, segs=48, ry_scale=TORSO_RY, rfn=rfn, colfn=colf)
    # cream piping at the hem, a placket with stem-brown buttons
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.488, torso_r(0.488) + 0.02, 0.008, 6), P_CREAM, torso_w,
          segs=36, closed_profile=True, ry_scale=TORSO_RY)
    pk = [P.on_torso(0.0, z, 0.024 + belly(z))[0] for z in [0.53 + 0.02 * i for i in range(17)]]
    sweep(mb, pk, [(0.004, 0.019)] * len(pk), P_CREAM, lambda p, sv, i: torso_w(p), segs=8, twist_hint=FWD)
    for z in (0.79, 0.695, 0.6):
        p, n = P.on_torso(0.0, z, 0.029 + belly(z))
        ellipsoid(mb, p, (0.012, 0.012, 0.0045), P_BTN, torso_w, segs=10, rings=6, rot=rot_align(n, UP))
    # leaf collar: cream neck piping and two green leaf points with veins
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.872, 0.094, 0.013, 8), P_CREAM, torso_w, segs=28,
          closed_profile=True, ry_scale=0.92)
    for sx in SIDES:
        p, n = P.on_torso(0.056 * sx, 0.832, 0.03)
        R = rot_align(n, UP) @ rot_z(42 * sx)
        lf = lambda lp: Vector((lp.x * (1.0 - 0.55 * max(0.0, -lp.y / 0.046) ** 1.4), lp.y, lp.z))
        ellipsoid(mb, p, (0.03, 0.046, 0.006), LEAF, torso_w, segs=12, rings=8, rot=R, deform=lf)
        vein = [p + R @ Vector((0, y, 0.0058)) for y in (0.036, 0.012, -0.012, -0.036)]
        K.path_tube(mb, vein, 0.0018, LEAF_D, torso_w, segs=4, hint=n, cap='flat')
    # cream pocket with an embroidered leaf
    pp = place_front(-0.1, 0.735, 0.021 + belly(0.735))
    decal(mb, K.rounded_rect(0.066, 0.06, 0.014), pp, P_CREAM, torso_w, thick=0.004)
    lo = [(0.0, 0.016), (-0.011, 0.002), (-0.006, -0.012), (0.0, -0.016), (0.006, -0.012), (0.011, 0.002)]
    decal(mb, lo, place_front(-0.1, 0.735, 0.025 + belly(0.735)), LEAF, torso_w, thick=0.0015)
    # sleeves with cream cuffs
    sleeves(mb, RUST, 0.019, cuff_style=P_CREAM, cuff_tube=0.018, lod=1)
    # cream trousers with fine rust stripes, cut at mid-shin with a rust band
    stripe = lambda p, sv, a: RUST if (a / (2 * math.pi) * 14) % 1.0 < 0.16 else None
    pelvis(mb, P_CREAM, 0.012, 0.60)
    for sx in SIDES:
        # (Pass 9: the capri leg narrows to the sock, ~1.4 cm of air; it
        # stood 3.4 cm off the sock under a band wider still)
        K.leg_tube(mb, sx, 0.55, 0.215, lambda z: 0.026 - 0.014 * smoothstep(0.34, 0.215, z), P_CREAM, segs=28, colfn=stripe)
        _rib_leg(mb, sx, 0.205, 0.235, 0.015, RUST_D, segs=16)
    # soft striped socks (worn instead of shoes): rust and cream stripes,
    # ribbed tops, cream heel and toe
    for sx in SIDES:
        fw = foot_w(sx)
        cx = rig.HIP_X * sx
        bands = lambda p, z, th: RUST if (int((z - 0.0) / 0.026) % 2 == 0) else None
        # (Pass 9: the sock's ribbed top ends under the capri hem, below the
        # knee: at the knee it was shin-rigid inside a trouser that bends
        # there, and parted from it by 1.6 cm in a stride)
        lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3),
              [(0.045, 0.06), (0.07, 0.061), (0.1, 0.06), (0.13, 0.059), (0.156, 0.06), (0.182, 0.063), (0.208, 0.065),
               (0.234, 0.066), (0.244, 0.066)], P_CREAM, fw, segs=16, ry_scale=1.04, colfn=bands)
        lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3), [(0.24, 0.06), (0.243, 0.067), (0.262, 0.068), (0.266, 0.061)], P_CREAM,
              fw, segs=16, ry_scale=1.04, rfn=lambda r, th, z: r + 0.0014 * math.cos(th * 8))
        slab(mb, _foot_outline(sx, toe=0.172, heel=-0.074, w_heel=0.054, w_toe=0.066, n=22), 0.0, 0.014, P_CREAM, fw, bevel=0.006)
        ellipsoid(mb, Vector((cx, 0.045, 0.026)), (0.063, 0.128, 0.07), RUST, fw, segs=18, rings=12, cut_below=-0.25,
                  colfn=lambda p, lp: P_CREAM if (p.y > 0.13 or p.y < -0.045) else (RUST if int(p.z / 0.026) % 2 == 0 else P_CREAM))
    return mb


def pumpkin_cap_edge(ang):
    return 1.215 + 0.085 * front(ang) + 0.022 * math.sin(ang) ** 2


def build_pumpkin_cap():
    """Knitted pumpkin cap: eight soft lobes, a ribbed rust band, a stem, a
    leaf and a curl of vine (worn with pumpkin_pajamas and no hat)."""
    mb = MeshBuilder('acc_pumpkin_cap')
    hw = rigid('head')
    grow = 0.044

    def side_t(z):
        rz = HEAD_R[2] + grow
        return math.sqrt(max(0.0, 1.0 - ((z - HEAD_C.z) / rz) ** 2))
    bulge = lambda a, z: 0.013 * _lobe(a) * side_t(z)
    colf = lambda a, z: RUST_D if (_lobe(a) < 0.28 and side_t(z) > 0.3) else None
    shell(mb, grow, pumpkin_cap_edge, RUST, hw, segs=48, rows=12, tuck=0.012, bulge=bulge, colfn=colf)
    band, bn = [], []
    for k in range(48):
        ang = -math.pi + 2 * math.pi * k / 48
        q = P._shell_point(ang, pumpkin_cap_edge(ang) + 0.016, grow + 0.004)
        band.append(q)
        bn.append(rig.head_normal(q, grow))
    K.ribbon(mb, band, bn, 0.016, 0.0065, RUST_D, hw, segs=8, lift=0.003)
    # stem, leaf, vine on the crown
    top = Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + HEAD_R[2] + grow))
    stem = [top + Vector((0, 0, -0.012)), top + Vector((0.004, 0.0, 0.02)), top + Vector((0.012, -0.006, 0.045)),
            top + Vector((0.026, -0.012, 0.058))]
    stem = _smooth_path(stem, 0.008)
    sweep(mb, stem, [(lerp(0.019, 0.012, i / (len(stem) - 1)),) * 2 for i in range(len(stem))], STEM, lambda p, sv, i: hw(p), segs=10,
          twist_hint=FWD, cap_start=None, cap_end='round', colfn=lambda p, sv, a: STEM_D if (int(a / (2 * math.pi) * 10) % 2) else None)
    lc = P._shell_point(-2.4, HEAD_C.z + 0.25, grow + 0.012)
    ln = rig.head_normal(lc, grow)
    R = rot_align(ln, (Vector((0.0, 0.0, 0.0)) - Vector((lc.x, lc.y - HEAD_C.y, 0.0))).normalized())
    lf = lambda lp: Vector((lp.x * (1.0 - 0.6 * max(0.0, -lp.y / 0.06) ** 1.3), lp.y, lp.z + 0.01 * (lp.x / 0.04) ** 2))
    ellipsoid(mb, lc, (0.042, 0.062, 0.005), LEAF, hw, segs=14, rings=8, rot=R, deform=lf)
    K.path_tube(mb, [lc + R @ Vector((0, y, 0.006)) for y in (-0.05, -0.02, 0.01, 0.045)], 0.002, LEAF_D, hw, segs=4, hint=ln, cap='flat')
    vine = []
    for k in range(19):
        a = 1.2 + 4.4 * math.pi * k / 18
        rr = 0.024 * (1.0 - 0.6 * k / 18)
        q = top + Vector((-0.045 + math.cos(a) * rr, 0.03 + math.sin(a) * rr, 0.0))
        vine.append(head_project(grow + 0.006)(q)[0])
    K.path_tube(mb, vine, 0.0028, LEAF_D, hw, segs=5, hint=UP)
    return mb


# ================================================================== ARCADE SPRINTER
CYAN = S('#21bfe2', rough=0.6, mat=MAT_SATIN)
MAGENTA = S('#e43a9a', rough=0.6, mat=MAT_SATIN)
A_WHITE = S('#f6f5f0', rough=0.7)
A_NAVY = S('#252a52', rough=0.75)
PIXEL_YELLOW = S('#ffd23f', rough=0.55)
SOCK = S('#f7f5ef', rough=0.95)
A_SOLE = S('#f4f2ec', rough=0.6, mat=MAT_RUBBER)
A_UPPER = S('#f8f7f2', rough=0.6, mat=MAT_RUBBER)
A_MAG_LEATHER = S('#e43a9a', rough=0.5, mat=MAT_RUBBER)
A_CYAN_LEATHER = S('#21bfe2', rough=0.5, mat=MAT_RUBBER)

BOLT = [(2, 0), (3, 0), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (3, 2), (1, 3), (2, 3), (0, 4), (1, 4)]


def _pixels(mb, cells, place, px, style, wfn, thick=0.0028):
    """Pixel art: one small square patch per cell (col, row from the top)."""
    cols = max(c for c, _ in cells) + 1
    rows = max(r for _, r in cells) + 1
    sq = K.rounded_rect(px * 0.9, px * 0.9, px * 0.12, 1)
    for c, r in cells:
        u = (c - (cols - 1) / 2) * px
        v = ((rows - 1) / 2 - r) * px
        decal(mb, sq, lambda a, b, u=u, v=v: place(a + u, b + v), style, wfn, thick=thick)


def _yoke(x, front_side):
    return 0.738 + 0.07 * min(1.0, abs(x) / 0.2) if front_side else 0.808


def _hightop(mb, sx):
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    outline = _foot_outline(sx, toe=0.185, heel=-0.08, w_heel=0.062, w_toe=0.076, n=20)
    slab(mb, outline, 0.0, 0.042, A_SOLE, fw, bevel=0.014)
    ring = [Vector((x + (x - cx) * 0.04, y, 0.026)) for x, y in outline]
    K.path_tube(mb, ring, 0.0055, A_CYAN_LEATHER, fw, segs=4, hint=UP, flat=1.6, closed=True)
    col = lambda p, lp: A_MAG_LEATHER if (p.y < 0.075 and p.z > 0.062 and abs(p.x - cx) > 0.035) else None
    ellipsoid(mb, Vector((cx, 0.05, 0.036)), (0.069, 0.134, 0.084), A_UPPER, fw, segs=18, rings=11, cut_below=-0.08, colfn=col)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), [(0.05, 0.068), (0.1, 0.066), (0.17, 0.066), (0.19, 0.07), (0.196, 0.066),
          (0.184, 0.056)], A_MAG_LEATHER, fw, segs=18, ry_scale=1.05)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), torus_profile(0.188, 0.07, 0.011, 6, 1.0), A_CYAN_LEATHER, fw, segs=18,
          closed_profile=True, ry_scale=1.05)
    for i in range(3):
        y = 0.034 + i * 0.03
        z = 0.036 + 0.084 * math.sqrt(max(0.0, 1.0 - ((y - 0.05) / 0.134) ** 2)) - 0.002 + i * 0.016
        ellipsoid(mb, Vector((cx, y + 0.004 * i, z)), (0.032, 0.006, 0.005), A_WHITE, fw, segs=6, rings=4, rot=rot_x(-30))
    # a yellow star on the outer ankle
    c = Vector((cx + 0.069 * sx, -0.012, 0.13))
    decal(mb, K.star_outline(0.017), place_planar(c, Vector((sx, 0, 0)), UP), PIXEL_YELLOW, fw, thick=0.002)


def build_arcade():
    mb = MeshBuilder('arcade')
    g = 0.02
    colf = lambda p, z, th: MAGENTA if z > _yoke(p.x, p.y > TORSO_CY) else None
    torso_lathe(mb, CYAN, g, 0.575, 0.866, top_open_r=0.09, segs=40, colfn=colf)
    _rib_band(mb, 0.535, 0.588, 0.019, A_WHITE, ([0.551, 0.569], MAGENTA), segs=40)
    # white piping along the yoke line (front V, back straight)
    fr = [torso_at(x, _yoke(x, True), g + 0.002)[0] for x in [lerp(-0.23, 0.23, k / 20) for k in range(21)]]
    K.path_tube(mb, fr, 0.0042, A_WHITE, torso_w, segs=5, hint=FWD, cap='flat')
    bk = [torso_at(x, 0.808, g + 0.002, back=True)[0] for x in [lerp(-0.23, 0.23, k / 14) for k in range(15)]]
    K.path_tube(mb, bk, 0.0042, A_WHITE, torso_w, segs=5, hint=-FWD, cap='flat')
    # stand collar with a cyan stripe, white zip
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3),
          [(0.846, 0.112), (0.86, 0.118), (0.893, 0.106), (0.9, 0.099), (0.893, 0.092), (0.87, 0.096)], MAGENTA, torso_w, segs=28,
          ry_scale=0.92)
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.882, 0.112, 0.004, 6), A_WHITE, torso_w, segs=28,
          closed_profile=True, ry_scale=0.92)
    zp = place_front(0.0, 0.0, g)
    K.surface_tube(mb, [(0.0, z) for z in [0.555 + 0.025 * i for i in range(13)]], zp, 0.005, A_WHITE, torso_w, flat=0.45, segs=6)
    p, n = torso_at(0.0, 0.835, g + 0.008)
    ellipsoid(mb, p + Vector((0, 0, -0.012)), (0.008, 0.004, 0.016), ZIP_METAL, torso_w, segs=8, rings=6, rot=rot_align(n, UP))
    # pixel bolts: small on the chest, big on the back (the follow camera's view)
    _pixels(mb, BOLT, place_front(-0.098, 0.69, g), 0.0135, PIXEL_YELLOW, torso_w)
    _pixels(mb, BOLT, place_back(0.0, 0.69, g), 0.019, PIXEL_YELLOW, torso_w)
    # magenta sleeves with cyan forearms, white piping, striped knit cuffs
    sleeves(mb, MAGENTA, 0.017, cuff_style=None, band=(0.15, 0.5, CYAN), lod=1)
    for sx in SIDES:
        K.ring_on_arm(mb, sx, 0.15, 0.0185, 0.0038, A_WHITE, segs=16, squash=1.0, n=4)
        s_end = rig.UPPER_LEN + rig.FORE_LEN - 0.03
        d = arm_dir(sx)
        # (Pass 9: the knit cuff hugs the wrist over the eased sleeve end)
        r = P.sleeve_r(s_end + 0.015, 0.017) - 0.015
        cuffc = lambda q, z, th: (MAGENTA if 0.008 <= z <= 0.013 else (CYAN if 0.017 <= z <= 0.022 else None))
        lathe(mb, shoulder(sx) + d * s_end, rot_align(d, FWD), [(-0.004, r + 0.008), (0.0, r + 0.02), (0.006, r + 0.02), (0.012, r + 0.02),
              (0.018, r + 0.02), (0.024, r + 0.02), (0.03, r + 0.02), (0.034, r + 0.008)], A_WHITE, lambda q, sx=sx: arm_w(q, sx),
              segs=16, colfn=cuffc, rfn=lambda rr, th, z: rr + 0.0012 * math.cos(th * 8))
    # navy track shorts: white side piping, magenta hems
    pelvis(mb, A_NAVY, 0.016, 0.60)
    for sx in SIDES:
        # (Pass 9: the hem follows the thigh with ~1 cm of air under its
        # ring; it flared to 4 cm, a magenta hoop round each leg)
        K.leg_tube(mb, sx, 0.53, 0.415, lambda z: 0.028 - 0.014 * smoothstep(0.5, 0.415, z), A_NAVY, segs=18,
                   colfn=lambda p, sv, a, sx=sx: A_WHITE if (abs(p.x) > rig.HIP_X + 0.08 and abs(p.y) < 0.012) else None)
        K.ring_on_leg(mb, sx, 0.418, 0.014, 0.007, MAGENTA)
    # bare legs, tube socks with cyan and magenta stripes
    for sx in SIDES:
        K.skin_leg(mb, sx, 0.45, 0.2, SKIN, segs=12)
        leg_tube_stripes(mb, sx, 0.215, 0.09, 0.004, SOCK, [(0.17, 0.18, CYAN), (0.186, 0.196, MAGENTA)], segs=12)
        K.ring_on_leg(mb, sx, 0.211, 0.006, 0.009, SOCK, segs=14, n=5)
        _hightop(mb, sx)
    return mb


# ================================================================== CLOUD NINE
SKY = S('#8fc9f0', rough=0.96)
SKY_D = S('#71aee0', rough=0.96)
CLOUD = S('#fbfbf5', rough=0.97)
C_CREAM = S('#f4e9d2', rough=0.95)
C_SOLE = S('#a8bfdc', rough=0.8, mat=MAT_RUBBER)


# both Pass 8 hoods sit where the shipped Night Owl / Duck / Frog hoods do
# (parts._hood's default grow): the clips' hands-to-head gestures meet them
# exactly as they meet those (tools/character/outfit_check.py)
HOOD_G = 0.035
# their face opening (half-width, half-height, centre height): wider than the
# shipped hoods' (0.228, 0.19, 1.145), so the rim stays clear of the brows
HOOD_OPEN = (0.242, 0.205, 1.148)


def _puff(mb, c, r, n, style, wfn, segs=10, rings=7, flat=0.7):
    ellipsoid(mb, c, (r, r, r * flat), style, wfn, segs=segs, rings=rings, rot=rot_align(n, UP))


def build_cloud():
    mb = MeshBuilder('cloud')
    g = 0.036
    plush = lambda z: 0.014 * math.sin(math.pi * smoothstep(0.5, 0.86, z))
    torso_lathe(mb, SKY, g, 0.535, 0.875, extra=plush, top_open_r=0.13)
    _rib_band(mb, 0.49, 0.545, g - 0.002, C_CREAM, None, segs=40)
    # cloud pocket on the belly with its opening, a cloud on the back
    co = cloud_outline(0.2, 0.1)
    gz = g + plush(0.62)
    decal(mb, co, place_front(0.0, 0.615, gz), CLOUD, torso_w, thick=0.005)
    K.surface_tube(mb, [(-0.06 + 0.12 * k / 8, 0.022 + 0.006 * math.sin(math.pi * k / 8)) for k in range(9)],
                   place_front(0.0, 0.615, gz + 0.005), 0.003, SKY_D, torso_w, segs=4)
    decal(mb, cloud_outline(0.24, 0.13), place_back(0.0, 0.69, g + plush(0.69)), CLOUD, torso_w, thick=0.005)
    decal(mb, cloud_outline(0.09, 0.05), place_back(0.08, 0.79, g + plush(0.79)), CLOUD, torso_w, thick=0.004)
    # plush sleeves with cream cuffs
    sleeves(mb, SKY, 0.03, cuff_style=C_CREAM, cuff_tube=0.022, lod=1)
    # the hood, up: a cloud rim of puffs round the face and two cloud tufts on top
    P._hood(mb, SKY, CLOUD, extra_grow=HOOD_G, opening=HOOD_OPEN)
    hw = rigid('head')
    n_p = 14
    for i in range(n_p):
        a = 2 * math.pi * (i + 0.5) / n_p
        x = (HOOD_OPEN[0] + 0.008) * math.cos(a)
        z = HOOD_OPEN[2] + (HOOD_OPEN[1] + 0.008) * math.sin(a)
        # (final sweep: on the hood's roll into the face, round the rim, and
        # 9 mm lower, so the shush hand meets them no more than it meets the
        # shipped hoods, whose rims also came in: outfit_check)
        q, nq = P.hood_point(x, z, HOOD_G, HOOD_OPEN)
        out = Vector((math.cos(a) * 0.012, 0.0, math.sin(a) * 0.012))
        r = 0.027 if i % 2 == 0 else 0.022
        _puff(mb, q + out, r, nq, CLOUD, hw, segs=9, rings=6)
    for x, y, z, r in ((0.0, -0.035, 1.53, 0.058), (0.095, 0.01, 1.49, 0.046), (-0.095, 0.01, 1.49, 0.046), (0.06, -0.115, 1.46, 0.044),
                       (-0.06, -0.115, 1.46, 0.044)):
        rp, rn = head_project(HOOD_G)(Vector((x, y, z)))
        _puff(mb, rp + rn * (r * 0.45), r, rn, CLOUD, hw, segs=12, rings=8, flat=0.8)
    hb = P._shell_point(0.0, 1.22, HOOD_G)
    decal(mb, cloud_outline(0.2, 0.11), place_planar(hb, rig.head_normal(hb, HOOD_G), UP, head_project(HOOD_G)), CLOUD, hw, thick=0.005)
    # drawstrings with puff ends
    for sx in SIDES:
        pts = [Vector((0.05 * sx, 0.2, 0.93)), torso_at(0.045 * sx, 0.85, g + 0.012)[0], torso_at(0.048 * sx, 0.78, g + 0.016)[0]]
        pts = _smooth_path(pts, 0.015)
        K.path_tube(mb, pts, 0.004, C_CREAM, torso_w, segs=5, hint=FWD, cap='flat')
        p, n = torso_at(0.048 * sx, 0.77, g + 0.02)
        _puff(mb, p, 0.011, n, CLOUD, torso_w, segs=8, rings=6, flat=0.9)
    # plush joggers with cream cuffs
    pelvis(mb, SKY, 0.022, 0.60)
    for sx in SIDES:
        # (Pass 9: the cuff gathers onto the ankle and tucks into the slipper's
        # collar; it ended 3 cm off the ankle above a collar ring round nothing)
        K.leg_tube(mb, sx, 0.55, 0.11, lambda z: 0.03 - 0.014 * smoothstep(0.35, 0.12, z), SKY, segs=16)
        _rib_leg(mb, sx, 0.088, 0.135, 0.015, C_CREAM)
    # cushioned cloud slippers (worn instead of shoes)
    for sx in SIDES:
        fw = foot_w(sx)
        cx = rig.HIP_X * sx
        slab(mb, _foot_outline(sx, toe=0.195, heel=-0.085, w_heel=0.064, w_toe=0.08, n=24), 0.0, 0.03, C_SOLE, fw, bevel=0.012)

        def bumps(lp):
            n = lp.normalized() if lp.length > 1e-9 else Vector((0, 0, 1))
            b = math.sin(9 * n.x + 1) * math.sin(9 * n.y + 2) * math.sin(7 * n.z + 3)
            return lp * (1.0 + 0.075 * b * smoothstep(-0.2, 0.3, n.z))
        ellipsoid(mb, Vector((cx, 0.055, 0.03)), (0.082, 0.142, 0.088), CLOUD, fw, segs=18, rings=12, cut_below=-0.2, deform=bumps)
        # (Pass 9: the collar wraps the ankle: it bends with the leg in it)
        lathe(mb, Vector((cx, -0.008, 0)), Matrix.Identity(3), torus_profile(0.105, 0.066, 0.02, 8), C_CREAM,
              lambda p, fw=fw, sx=sx: rig.mix((fw(p), 0.35), (leg_w(p, sx), 0.65)), segs=18, closed_profile=True)
    return mb


# ================================================================== BEDTIME BANDIT
CHAR = S('#8a8d99', rough=0.95)      # a mid charcoal: lighter than the V6 night outfits (no concealment)
CHAR_D = S('#5c606c', rough=0.95)
B_CREAM = S('#efe5d2', rough=0.95)
B_RING = S('#3d4049', rough=0.95)
B_LIGHT = S('#c9c4b8', rough=0.95)
MOON = S('#f3d27a', rough=0.5, mat=MAT_SATIN)

# the tail's axis (rest pose, rigid on the hips): out of the seat, back, then
# up and to the right, so it reads from the follow camera behind
EYE_W = S('#fbfaf4', rough=0.3, mat=MAT_GLOSS)
EYE_D = S('#22232b', rough=0.25, mat=MAT_GLOSS)


def _mask_bump(u):
    return math.exp(-((abs(u) - 0.085) / 0.05) ** 2)


def mask_top(u):
    """A bandit mask band (hood surface units): pointed ends, deeper over the
    two hood eyes, narrow at the bridge: its top edge ..."""
    return 0.016 - 0.014 * (u / 0.2) ** 2 + 0.02 * _mask_bump(u)


def mask_bottom(u):
    """... and its bottom edge."""
    return -0.01 + 0.008 * (u / 0.2) ** 2 - 0.02 * _mask_bump(u) + 0.008 * math.exp(-(u / 0.03) ** 2)


def mask_outline(n=13):
    """The mask's outline, CCW, star-shaped about its centre."""
    us = [lerp(0.2, -0.2, i / (n - 1)) for i in range(n)]
    top = [(u, mask_top(u)) for u in us]
    bot = [(u, mask_bottom(u)) for u in reversed(us)]
    return top[:-1] + [(-0.205, 0.002)] + bot[1:-1] + [(0.205, 0.002)]


TAIL = [Vector((0.0, -0.215, 0.535)), Vector((0.015, -0.28, 0.548)), Vector((0.05, -0.335, 0.58)), Vector((0.09, -0.365, 0.635)),
        Vector((0.118, -0.375, 0.7)), Vector((0.128, -0.365, 0.765))]


def tail_radii(path):
    s = P._path_s(path)
    tot = s[-1]
    return [0.03 + 0.032 * math.sin(math.pi * min(1.0, v / tot * 1.15)) ** 0.8 for v in s]


def build_bandit():
    mb = MeshBuilder('bandit')
    g = 0.045
    belly = lambda z: 0.022 * math.sin(math.pi * smoothstep(0.46, 0.86, z))
    torso_lathe(mb, CHAR, g, 0.46, 0.88, bottom_pole=True, extra=belly)
    # (final sweep: the cream belly panel bent onto the suit; it was a flat
    # disc 2 cm proud of the belly, so in profile it stood off as an oval)
    P.belly_panel(mb, B_CREAM, lambda z: g + belly(z), 0.675, (0.14, 0.165, 0.028))
    # a little moon on the chest (bedtime), a darker zip line
    o, i = K.crescent(0.022, 0.78, 0.48, 12, math.radians(25))
    strip_decal(mb, o, i, place_front(-0.105, 0.79, g + belly(0.79)), MOON, torso_w, thick=0.003)
    sleeves(mb, CHAR, 0.03, cuff_style=CHAR_D, cuff_tube=0.02, lod=1)
    P.pant_legs(mb, CHAR, 0.03, bottom_z=0.1, flat_end=False)
    # footed: charcoal paws with cream soles and dark toe beans
    for sx in SIDES:
        fw = foot_w(sx)
        cx = rig.HIP_X * sx
        slab(mb, _foot_outline(sx, toe=0.19, heel=-0.084, w_heel=0.062, w_toe=0.078, n=24), 0.0, 0.022, B_CREAM, fw, bevel=0.009)
        ellipsoid(mb, Vector((cx, 0.05, 0.026)), (0.076, 0.138, 0.092), CHAR, fw, segs=18, rings=12, cut_below=-0.18)
        lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), [(0.05, 0.072), (0.09, 0.076), (0.125, 0.078)], CHAR, fw,
              segs=18, ry_scale=1.04)
        for k, dx in enumerate((-0.036, -0.012, 0.012, 0.036)):
            y = 0.165 - 0.012 * abs(dx) / 0.036
            z = 0.026 + 0.092 * math.sqrt(max(0.0, 1.0 - ((y - 0.05) / 0.138) ** 2 - (dx / 0.076) ** 2)) - 0.004
            q = Vector((cx + dx, y, z))
            nn = Vector((dx / 0.076 ** 2, (y - 0.05) / 0.138 ** 2, (z - 0.026) / 0.092 ** 2)).normalized()
            ellipsoid(mb, q, (0.012, 0.012, 0.006), CHAR_D, fw, segs=8, rings=5, rot=rot_align(nn, UP))
    # the hood: raccoon mask band above the face opening, cream brows, round ears
    P._hood(mb, CHAR, B_CREAM, extra_grow=HOOD_G, opening=HOOD_OPEN)
    hw = rigid('head')
    # (final sweep: everything on the hood follows its roll into the face
    # opening; the mask is a strip between its top and bottom edges, so it
    # lies on the round hood across its whole width (as one fan from its
    # centre its middle sank into the hood and its eyes stood 8 mm off it)
    hp = P.hood_project(HOOD_G, HOOD_OPEN)
    mc, mn = P.hood_point(0.0, 1.395, HOOD_G, HOOD_OPEN)
    mpl = place_planar(mc, mn, UP, hp)
    us = [lerp(0.2, -0.2, i / 11.0) for i in range(12)]
    K.strip_decal(mb, [(u, mask_top(u)) for u in us], [(u, mask_bottom(u)) for u in us], mpl, B_RING, hw, thick=0.0035, lift=0.001)
    top = place_planar(mc, mn, UP, lambda q: (lambda a: (a[0] + a[1] * 0.0045, a[1]))(hp(q)))
    for sx in SIDES:
        bpts = [(sx * (0.04 + 0.1 * k / 6), 0.052 + 0.016 * math.sin(math.pi * k / 6) - 0.01 * k / 6) for k in range(7)]
        K.surface_tube(mb, bpts, mpl, 0.0085, B_CREAM, hw, segs=6, flat=0.7, lift=0.003)
        e, en = top(sx * 0.085, 0.004)
        Re = rot_align(en, UP)
        ellipsoid(mb, e, (0.021, 0.025, 0.006), EYE_W, hw, segs=12, rings=6, rot=Re)
        ellipsoid(mb, e + en * 0.005, (0.012, 0.014, 0.004), EYE_D, hw, segs=10, rings=5, rot=Re)
        ellipsoid(mb, e + en * 0.008 + Re @ Vector((-0.004 * sx, 0.006, 0)), (0.004, 0.004, 0.0015), EYE_W, hw, segs=6, rings=4, rot=Re)
    for sx in SIDES:
        ec = P._shell_point(-sx * (math.pi / 2 + 0.2), 1.46, HOOD_G)
        en = rig.head_normal(ec, HOOD_G)
        out = (en + Vector((0, 0, 0.4))).normalized()
        R = rot_align(out, FWD)
        ellipsoid(mb, ec + out * 0.034, (0.064, 0.022, 0.06), CHAR, hw, segs=14, rings=10, rot=R, power=2.2)
        ellipsoid(mb, ec + out * 0.04 + (R @ Vector((0, 0.013, 0))), (0.042, 0.011, 0.04), B_LIGHT, hw, segs=12, rings=8, rot=R)
        ellipsoid(mb, ec + out * 0.08, (0.034, 0.019, 0.014), B_CREAM, hw, segs=10, rings=6, rot=R)
    # ringed tail, rigid on the hips, curving up behind (clear of the legs and the ground)
    path = _smooth_path(TAIL, 0.014)
    tot = P._path_s(path)[-1]
    radii = [(r, r * 0.92) for r in tail_radii(path)]
    ring = lambda p, sv, a: B_RING if (int(sv / tot * 6.0 + 0.35) % 2 == 1 or sv > tot * 0.9) else None
    sweep(mb, path, radii, B_LIGHT, lambda p, sv, i: {'hips': 1.0}, segs=12, cap_start='round', cap_end='round', twist_hint=Vector((1, 0, 0)),
          colfn=ring)
    return mb


PASS8_PARTS = [build_mechanic, build_cadet, build_cadet_cap, build_pumpkin, build_pumpkin_cap, build_arcade, build_cloud, build_bandit]
ALL = PASS8_PARTS
