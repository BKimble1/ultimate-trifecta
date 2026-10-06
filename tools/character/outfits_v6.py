"""V6 outfits: the six Shop outfits, their headwear and (below) the Season 1
After Hours outfits, hats and shoes.

Every outfit is one mesh part (one draw call) on the shared rig, built from
the same kit as the V3-V5 outfits (parts.py) plus kit6.py's decals and open
shells.  Palettes are fixed per design (each skin reads as itself), with a
player-colour element where the design invites it (the varsity jacket's
wool, the courier shirt, the jogger's glow).  Names match
Cosmetics.OUTFIT_PARTS / OUTFIT_HEADWEAR in game/src/view/cosmetics.gd.
"""
import math
from mathutils import Vector, Matrix

import rig
from geo import (MeshBuilder, Style, sweep, ellipsoid, lathe, slab, torus_profile, rot_align, rot_x, rot_y, rot_z, smoothstep, lerp,
                 T_NONE, T_SKIN, T_SECOND, T_DARK, T_PRIMARY, MAT_CLOTH, MAT_RUBBER, MAT_GLOSS, MAT_LIT, MAT_EMIT,
                 MAT_SATIN, MAT_METAL)
from rig import torso_w, skirt_w, arm_w, leg_w, rigid, torso_r, shoulder, arm_dir, HEAD_C, TORSO_RY, TORSO_CY
import parts as P
from parts import SKIN, UP, FWD, SIDES, torso_lathe, sleeves, pelvis, collar, placket_and_buttons, _dense_path, _smooth_path
import kit6 as K
from kit6 import decal, strip_decal, place_front, place_back, place_planar, cyl_project, head_project, torso_at


def S(col, tint=T_NONE, rough=0.85, mat=MAT_CLOTH):
    return Style(col, tint, rough, mat)


def hip_rigid(p):
    return {'hips': 1.0}


def sleeve_project(side, grow):
    return cyl_project(shoulder(side), arm_dir(side), lambda s: P.arm_radius(s) + grow)


def arm_point(side, s, ang_deg, r):
    """Point on a straight A-pose arm at distance s from the shoulder, at an
    angle around it (0 = outward/up, 90 = forward), radius r."""
    d = arm_dir(side)
    out = Vector((side * math.cos(math.radians(rig.ARM_DOWN_DEG)), 0.0, math.sin(math.radians(rig.ARM_DOWN_DEG))))
    a = math.radians(ang_deg)
    n = (out * math.cos(a) + FWD * math.sin(a)).normalized()
    return shoulder(side) + d * s + n * r, n


def leg_point(side, z, ang_deg, grow):
    """Point on the trouser leg at height z, angle around it (0 = outward, 90 = front)."""
    pts = rig.leg_path(side, 0.55)
    k, a = pts[1], pts[2]
    p0, p1 = (pts[0], k) if z >= k.z else (k, a)
    t = (p0.z - z) / (p0.z - p1.z)
    c = p0.lerp(p1, t)
    r = P.leg_radius(rig.leg_s(c, side)) + grow
    ang = math.radians(ang_deg)
    n = Vector((side * math.cos(ang), math.sin(ang), 0.0))
    return c + Vector((n.x * r * 0.96, n.y * r, 0.0)), n


def leg_project(side, grow):
    """Projector onto a trouser leg (thigh or shin segment by height)."""
    pts = rig.leg_path(side, 0.55)
    k, a = pts[1], pts[2]

    def f(p):
        p0, p1 = (pts[0], k) if p.z >= k.z else (k, a)
        d = (p1 - p0).normalized()
        q = p - p0
        s = q.dot(d)
        rad = q - d * s
        rn = rad.normalized() if rad.length > 1e-6 else Vector((1, 0, 0))
        c = p0 + d * s
        r = P.leg_radius(rig.leg_s(c, side)) + grow
        return c + rn * r, rn
    return f


def star_at(mb, place, r, style, wfn, rot=0.0, lift=0.0015, thick=0.0035):
    decal(mb, K.star_outline(r, 0.45, 5, rot), place, style, wfn, lift=lift, thick=thick)


def leg_skin_and_socks(mb, top_z, sock_top, sock, stripes=None, rib=None, segs=12):
    """Bare legs from inside the shorts to a sock, and the sock itself."""
    for sx in SIDES:
        K.skin_leg(mb, sx, top_z, sock_top - 0.02, SKIN, segs=segs)
        cf = None
        if stripes:
            cf = lambda p, sv, a, st=stripes: st[1] if any(z0 <= p.z <= z1 for z0, z1 in st[0]) else None
        K.leg_tube(mb, sx, sock_top, 0.09, 0.004, sock, segs=segs, colfn=cf)
        K.ring_on_leg(mb, sx, sock_top - 0.004, 0.006, 0.009, rib or sock, segs=14, n=5)


# ================================================================== MOONLIGHT RUNNER
MID = S('#222c5c', rough=0.5, mat=MAT_SATIN)   # midnight satin track fabric (V8: satin sheen)
MID_RIB = S('#171e42', rough=0.8)
PIPING = S('#e6ebf6', rough=0.25, mat=MAT_LIT)   # reflective: keeps a little light at night
ZIP = S('#c7ccd8', rough=0.25, mat=MAT_METAL)
GOLD = S('#f3cf6a', rough=0.3, mat=MAT_METAL)


def build_moonlight():
    mb = MeshBuilder('moonlight')
    g = 0.015
    torso_lathe(mb, MID, g, 0.52, 0.866, top_open_r=0.09)
    # ribbed hem band, stand-up collar
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3),
          [(0.495, torso_r(0.495) + 0.006), (0.50, torso_r(0.50) + g + 0.006), (0.53, torso_r(0.53) + g + 0.008),
           (0.536, torso_r(0.536) + g + 0.002)], MID_RIB, torso_w, segs=40, ry_scale=TORSO_RY,
          rfn=lambda r, th, z: r + 0.0018 * math.cos(th * 20))
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3),
          [(0.846, 0.112), (0.86, 0.118), (0.893, 0.106), (0.9, 0.099), (0.893, 0.092), (0.87, 0.096)], MID, torso_w, segs=28,
          ry_scale=0.92)
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.895, 0.1, 0.0045, 6), PIPING, torso_w,
          segs=28, closed_profile=True, ry_scale=0.92)
    sleeves(mb, MID, 0.013, cuff_style=MID_RIB, cuff_tube=0.018, lod=1)
    # zip tape and pull
    zp = place_front(0.0, 0.0, g)
    K.surface_tube(mb, [(0.0, z) for z in [0.515 + 0.02 * i for i in range(18)]], zp, 0.0055, ZIP, torso_w, flat=0.45, segs=6)
    p, n = torso_at(0.0, 0.835, g + 0.008)
    ellipsoid(mb, p + Vector((0, 0, -0.012)), (0.008, 0.004, 0.016), ZIP, torso_w, segs=8, rings=6, rot=rot_align(n, UP))
    # gold crescent and a small star on the left chest
    cp = place_front(-0.09, 0.765, g)
    o, i = K.crescent(0.03, 0.8, 0.48, 14, math.radians(25))
    strip_decal(mb, o, i, cp, GOLD, torso_w, thick=0.0035)
    star_at(mb, place_front(-0.055, 0.795, g), 0.009, GOLD, torso_w, rot=0.2)
    # reflective double piping: down the outside of each sleeve and leg
    for sx in SIDES:
        for off in (-0.011, 0.011):
            pts = []
            for k in range(11):
                s = 0.01 + (rig.UPPER_LEN + rig.FORE_LEN - 0.04) * k / 10
                q, nn = K_arm_line(sx, s, off, 0.013)
                pts.append(q)
            K.path_tube(mb, pts, 0.0032, PIPING, lambda q, sx=sx: arm_w(q, sx), segs=5, hint=UP, cap='flat')
        for off in (-0.012, 0.012):
            pts = []
            for k in range(15):
                z = 0.585 - (0.585 - 0.14) * k / 14
                q, nn = leg_point(sx, z, 0.0, 0.018 + 0.0035)
                pts.append(q + Vector((0, off, 0)))
            K.path_tube(mb, pts, 0.0032, PIPING, lambda q, sx=sx: leg_w(q, sx), segs=5, hint=Vector((sx, 0, 0)), cap='flat')
    # piping across the back yoke, sleeve to sleeve
    yoke = [torso_at(lerp(-0.135, 0.135, k / 12), 0.8, g + 0.003, back=True)[0] for k in range(13)]
    K.path_tube(mb, yoke, 0.003, PIPING, torso_w, segs=6, hint=-FWD)
    # track trousers with ribbed ankle cuffs
    pelvis(mb, MID, 0.012, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.085, 0.018, MID, segs=16, flat_end=True)
        K.ring_on_leg(mb, sx, 0.1, 0.02, 0.015, MID_RIB, segs=16, n=7)
    return mb


def K_arm_line(side, s, off, grow):
    """A line along the top-outside of the A-pose sleeve (seam piping),
    offset forward/back by `off` metres."""
    r = P.arm_radius(s) + grow + 0.0035
    q, n = arm_point(side, s, math.degrees(off / max(r, 1e-3)), r)
    return q, n


# ================================================================== STARRY SLEEPER
INDIGO = S('#2d3072', rough=0.85)
CREAM = S('#fbf1d6', rough=0.8)
STAR_GOLD = S('#ffd56b', rough=0.4, mat=MAT_LIT)
STAR_CREAM = S('#fff6dc', rough=0.6, mat=MAT_LIT)
BTN_GOLD = S('#f1c75a', rough=0.3, mat=MAT_METAL)

# torso stars (x, z, size, rotation): front then back (the placket and pocket stay clear)
STARRY_FRONT = [(0.11, 0.80, 0.022, 0.3), (0.145, 0.63, 0.019, 0.9), (0.065, 0.70, 0.016, 0.1), (-0.14, 0.665, 0.021, 0.5),
                (-0.07, 0.585, 0.017, 1.1), (-0.165, 0.775, 0.014, 0.2), (0.07, 0.545, 0.014, 0.7)]
STARRY_BACK = [(0.1, 0.79, 0.022, 0.2), (-0.08, 0.715, 0.02, 0.8), (0.13, 0.61, 0.019, 1.2), (-0.14, 0.585, 0.017, 0.4),
               (0.0, 0.64, 0.016, 0.9), (-0.05, 0.83, 0.014, 0.6), (0.05, 0.54, 0.015, 0.1)]


def build_starry():
    mb = MeshBuilder('starry')
    g = 0.018
    torso_lathe(mb, INDIGO, g, 0.50, 0.872, top_open_r=0.09, hem_fold=0.02, flare=0.012)
    sleeves(mb, INDIGO, 0.017, cuff_style=CREAM, lod=1)
    collar(mb, g, CREAM)
    placket_and_buttons(mb, g, 3, CREAM, BTN_GOLD)
    # pocket with a crescent
    p, n = torso_at(-0.095, 0.765, g + 0.004)
    ellipsoid(mb, p, (0.04, 0.036, 0.005), CREAM, torso_w, segs=12, rings=8, rot=rot_align(n, UP), power=4.0)
    o, i = K.crescent(0.016, 0.78, 0.5, 10, math.radians(20))
    strip_decal(mb, o, i, place_front(-0.095, 0.765, g + 0.009), STAR_GOLD, torso_w, thick=0.002)
    for k, (x, z, r, a) in enumerate(STARRY_FRONT):
        star_at(mb, place_front(x, z, g + 0.001), r, STAR_GOLD if k % 3 else STAR_CREAM, torso_w, rot=a)
    for k, (x, z, r, a) in enumerate(STARRY_BACK):
        star_at(mb, place_back(x, z, g + 0.001), r, STAR_GOLD if k % 3 else STAR_CREAM, torso_w, rot=a)
    # sleeves: three stars each
    for sx in SIDES:
        prj = sleeve_project(sx, 0.017)
        for k, (s, ang, r) in enumerate(((0.07, 40.0, 0.016), (0.16, 120.0, 0.014), (0.24, 10.0, 0.013), (0.13, -70.0, 0.013))):
            c, nn = arm_point(sx, s, ang, P.arm_radius(s) + 0.017)
            star_at(mb, place_planar(c, nn, arm_dir(sx), prj), r, STAR_CREAM if k % 2 else STAR_GOLD,
                    lambda q, sx=sx: arm_w(q, sx), rot=0.4 * k, lift=0.002)
    # trousers
    pelvis(mb, INDIGO, 0.012, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.085, 0.022, INDIGO, segs=16, flat_end=True)
        K.ring_on_leg(mb, sx, 0.1, 0.024, 0.016, CREAM, segs=16, n=7)
    for sx in SIDES:
        prj = leg_project(sx, 0.022)
        for k, (z, ang, r) in enumerate(((0.47, 60.0, 0.018), (0.38, -20.0, 0.016), (0.27, 100.0, 0.016), (0.2, 20.0, 0.013),
                                         (0.42, 170.0, 0.016), (0.25, 210.0, 0.015))):
            c, nn = leg_point(sx, z, ang, 0.022)
            star_at(mb, place_planar(c, nn, UP, prj), r, STAR_GOLD if k % 2 else STAR_CREAM, lambda q, sx=sx: leg_w(q, sx),
                    rot=0.5 * k, lift=0.002)
    K.clamp_legs(mb)   # (Pass 9: the leg decals off the midline with the legs)
    return mb


MASK = S('#b8a5ec', rough=0.4)
MASK_D = S('#3a2a5e', rough=0.6)


def _mask_outline(w=0.25, h=0.085, n=28):
    """Sleep-mask shape: a wide soft superellipse, a little narrower in the middle."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x = math.copysign(abs(math.cos(a)) ** 0.7, math.cos(a)) * w / 2
        y = math.copysign(abs(math.sin(a)) ** 0.8, math.sin(a)) * h / 2
        y *= 1.0 - 0.18 * math.exp(-(x / 0.03) ** 2) * (1 if y > 0 else 0.6)
        out.append((x, y))
    return out


def build_sleepmask():
    """Sleep mask pushed up onto the forehead (worn with starry_sleeper)."""
    mb = MeshBuilder('acc_sleepmask')
    hw = rigid('head')
    # (final sweep: on the hair, a little higher: at 3 cm it rested on the
    # bob's bangs and stood up to 3 cm off the forehead with the other
    # styles, and its strap 0.9-1.1 cm off the hair, a halo from behind)
    grow = HAIR_BAND_G + 0.001
    cz = 1.392
    c = P.head_point(0.0, cz, grow)
    n = rig.head_normal(c, grow)
    prj = head_project(grow)
    place = place_planar(c, n, UP, prj)
    outline = _mask_outline()
    decal(mb, outline, place, MASK, hw, lift=0.0, thick=0.011, sink=0.004)
    # cream frill along the edge
    rim = [place(u, v)[0] + place(u, v)[1] * 0.006 for (u, v) in outline]
    K.path_tube(mb, rim, 0.0045, CREAM, hw, segs=6, hint=n, closed=True)
    # embroidered closed eyes with lashes, on the mask surface
    top = place_planar(c + n * 0.011, n, UP, lambda p: (lambda q: (q[0] + q[1] * 0.0115, q[1]))(prj(p)))
    for sx in SIDES:
        arc = [(sx * 0.058 + 0.032 * math.cos(math.radians(a)), 0.006 - 0.018 * math.sin(math.radians(a)))
               for a in range(10, 171, 16)]
        K.surface_tube(mb, arc, top, 0.0028, MASK_D, hw, segs=6)
        for k, a in enumerate((40, 90, 140)):
            x0 = sx * 0.058 + 0.032 * math.cos(math.radians(a))
            y0 = 0.006 - 0.018 * math.sin(math.radians(a))
            K.surface_tube(mb, [(x0, y0), (x0 + 0.006 * math.cos(math.radians(a)), y0 - 0.011)], top, 0.0018, MASK_D, hw, segs=5)
    # elastic strap around the head at the same height
    # a flat elastic lying on the hair, a little lower at the back; 9 mm
    # thick like the headlamp's strap, so where it presses into a bob it
    # still shows as one band (7 mm showed only in dashes)
    pts, nrm = K.head_band_points(cz, cz - 0.03, HAIR_BAND_G)
    K.ribbon(mb, pts, nrm, 0.012, 0.0045, MASK, hw, segs=6)
    return mb


# ================================================================== VARSITY SPRINTER
WOOL = S('#ffffff', T_PRIMARY, 0.95)
WOOL_D = S('#ffffff', T_DARK, 0.9)
IVORY_LEATHER = S('#f3eee2', rough=0.45, mat=MAT_RUBBER)
IVORY = S('#f6f1e4', rough=0.8)
SNAP = S('#efe7d2', rough=0.3, mat=MAT_METAL)
SHORTS_NAVY = S('#27305e', rough=0.75)
SOCK_WHITE = S('#f7f5ef', rough=0.95)


def _rib_band(mb, z0, z1, grow, style, stripes, wfn=torso_w, segs=48):
    """Knit rib band (vertical ribs) with raised stripe rings at the given heights."""
    prof = [(z0 - 0.004, max(torso_r(z0), 0.06) + grow - 0.008)]
    z = z0
    while z < z1 - 1e-6:
        prof.append((z, max(torso_r(z), 0.06) + grow))
        z += 0.008
    prof.append((z1, max(torso_r(z1), 0.06) + grow))
    prof.append((z1 + 0.004, max(torso_r(z1), 0.06) + grow - 0.008))
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, style, wfn, segs=segs, ry_scale=TORSO_RY,
          rfn=lambda r, th, z: r + 0.0016 * math.cos(th * (segs // 2)))
    for zc in (stripes[0] if stripes else []):
        lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(zc, max(torso_r(zc), 0.06) + grow + 0.0006, 0.0032, 5, 1.0),
              stripes[1], wfn, segs=36, closed_profile=True, ry_scale=TORSO_RY)


def build_varsity():
    mb = MeshBuilder('varsity')
    g = 0.02
    torso_lathe(mb, WOOL, g, 0.54, 0.866, top_open_r=0.09)
    _rib_band(mb, 0.497, 0.548, 0.019, WOOL_D, ([0.512, 0.527], IVORY))
    # knit collar band with two stripes
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3),
          [(0.845, 0.114), (0.86, 0.119), (0.888, 0.108), (0.895, 0.1), (0.888, 0.093), (0.866, 0.097)], WOOL_D, torso_w, segs=30,
          ry_scale=0.92, rfn=lambda r, th, z: r + 0.0012 * math.cos(th * 15))
    for zc, rc in ((0.866, 0.1185), (0.879, 0.1145)):
        lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(zc, rc, 0.003, 6, 1.0), IVORY, torso_w, segs=30,
              closed_profile=True, ry_scale=0.92)
    # ivory leather sleeves, striped knit cuffs
    sleeves(mb, IVORY_LEATHER, 0.016, cuff_style=None, lod=1)
    for sx in SIDES:
        s_end = rig.UPPER_LEN + rig.FORE_LEN - 0.03
        d = arm_dir(sx)
        # (Pass 9: the knit cuff hugs the wrist over the eased sleeve end; it
        # stood 2 cm off the wrist at the old full sleeve width)
        rc = P.sleeve_r(s_end + 0.015, 0.016) + 0.005
        lathe(mb, shoulder(sx) + d * s_end, rot_align(d, FWD), [(-0.004, rc - 0.008), (0.0, rc), (0.026, rc), (0.03, rc - 0.008)],
              WOOL_D, lambda q, sx=sx: arm_w(q, sx), segs=16)
        K.ring_on_arm(mb, sx, s_end + 0.013, 0.0, 0.0032, IVORY, segs=16, squash=1.0, n=5, r=rc + 0.0005)
    # snaps down the front
    for k in range(5):
        z = 0.56 + 0.065 * k
        p, n = torso_at(0.0, z, g + 0.004)
        ellipsoid(mb, p, (0.011, 0.011, 0.004), SNAP, torso_w, segs=10, rings=6, rot=rot_align(n, UP))
    # chenille T on the left chest: ivory felt with the letter in the dark shade
    pts, _ = K.letter_t(0.085, 0.095, 0.03)
    big = [(x * 1.0, y * 1.0) for x, y in pts]
    tp = place_front(-0.092, 0.745, g)
    # felt border = the letter grown by a few mm (a scaled copy about its junction)
    decal(mb, [(x * 1.18, y * 1.15) for x, y in big], tp, IVORY, torso_w, thick=0.003)
    decal(mb, big, place_front(-0.092, 0.745, g + 0.003), WOOL_D, torso_w, thick=0.003)
    # number 3 on the back as a thick chenille stroke
    three = []
    for k in range(9):
        a = math.radians(150 - 230 * k / 8)
        three.append((0.032 * math.cos(a), 0.035 + 0.032 * math.sin(a)))
    for k in range(1, 10):
        a = math.radians(80 - 230 * k / 9)
        three.append((0.036 * math.cos(a), -0.033 + 0.036 * math.sin(a)))
    K.surface_tube(mb, three, place_back(0.0, 0.70, g), 0.0105, IVORY, torso_w, segs=8, flat=0.6)
    # track shorts with side stripes
    pelvis(mb, SHORTS_NAVY, 0.016, 0.60)
    for sx in SIDES:
        # (Pass 9: the hem follows the thigh with ~1.5 cm of air; it flared to
        # 4 cm, a hoop round the leg)
        K.leg_tube(mb, sx, 0.53, 0.41, lambda z: 0.028 - 0.014 * smoothstep(0.5, 0.41, z), SHORTS_NAVY, segs=18,
                   colfn=lambda p, sv, a, sx=sx: IVORY if (abs(p.x) > rig.HIP_X + 0.08 and abs(p.y) < 0.022) else None)
        K.ring_on_leg(mb, sx, 0.413, 0.014, 0.007, IVORY)
    leg_skin_and_socks(mb, 0.45, 0.205, SOCK_WHITE, stripes=([(0.165, 0.175), (0.183, 0.191)], S('#ffffff', T_PRIMARY, 0.9)))
    return mb


# ================================================================== RAINCOAT EXPLORER
COAT = S('#ffc93d', rough=0.32, mat=MAT_RUBBER)
COAT_D = S('#eeb12c', rough=0.38, mat=MAT_RUBBER)
TOGGLE = S('#7a5332', rough=0.35, mat=MAT_GLOSS)
ROPE = S('#f4ead2', rough=0.9)
BOOT = S('#24807d', rough=0.25, mat=MAT_RUBBER)
BOOT_SOLE = S('#efe5cf', rough=0.6, mat=MAT_RUBBER)
RAIN_TROUSER = S('#2a3558', rough=0.7)

COAT_PROF = [(0.36, 0.212), (0.338, 0.244), (0.344, 0.258), (0.38, 0.255), (0.43, 0.249), (0.49, 0.244), (0.53, 0.243)]


def coat_r(z):
    if z < 0.55:
        pts = COAT_PROF[2:] + [(0.55, torso_r(0.55) + 0.036)]
        for (z0, r0), (z1, r1) in zip(pts, pts[1:]):
            if z0 <= z <= z1:
                return lerp(r0, r1, (z - z0) / (z1 - z0))
        return pts[0][1]
    return torso_r(z) + 0.036


def coat_at(x, z, lift=0.0, back=False):
    r = coat_r(z) + lift
    xx = max(-r * 0.999, min(r * 0.999, x))
    y = r * TORSO_RY * math.sqrt(max(0.0, 1.0 - (xx / r) ** 2))
    n = Vector((xx / r, (y / (r * TORSO_RY)) / TORSO_RY, -(coat_r(z + 0.01) - coat_r(z - 0.01)) / 0.02)).normalized()
    if back:
        y, n.y = -y, -n.y
    return Vector((xx, TORSO_CY + y, z)), n


def build_raincoat():
    mb = MeshBuilder('raincoat')
    prof = list(COAT_PROF)
    z = 0.55
    while z <= 0.86:
        prof.append((z, torso_r(z) + 0.036))
        z += 0.025
    prof += [(0.875, 0.105), (0.88, 0.097), (0.86, 0.089)]
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, COAT, skirt_w, segs=40, ry_scale=TORSO_RY)
    sleeves(mb, COAT, 0.024, bell=0.006, cuff_style=COAT_D, cuff_tube=0.02, lod=1, cuff_ease=0.016)
    collar(mb, 0.036, COAT_D)
    # front placket
    pl = lambda u, v: coat_at(-u, v, 0.0)
    K.surface_tube(mb, [(0.0, z) for z in [0.35 + 0.025 * i for i in range(21)]], pl, 0.02, COAT_D, skirt_w, flat=0.18, segs=8,
                   cap='flat')
    # toggles: a wooden peg across the placket with a rope loop each side
    for z in (0.795, 0.705, 0.615, 0.525):
        p, n = coat_at(0.0, z, 0.012)
        R = rot_align(Vector((1, 0, 0)), n)
        ellipsoid(mb, p, (0.009, 0.009, 0.026), TOGGLE, skirt_w, segs=10, rings=8, rot=R)
        for sx in SIDES:
            loop = []
            for k in range(7):
                a = math.pi * k / 6
                x = sx * (0.012 + 0.03 * math.sin(a))
                q, nn = coat_at(x, z + 0.008 * math.cos(a), 0.007)
                loop.append(q)
            K.path_tube(mb, loop, 0.0035, ROPE, skirt_w, segs=4, hint=n, cap='flat')
    # flap pockets on the skirt
    for sx in SIDES:
        x = 0.12 * sx
        decal(mb, K.rounded_rect(0.075, 0.07, 0.012), lambda u, v, x=x: coat_at(x - u, 0.45 + v), COAT_D, skirt_w, thick=0.004)
        decal(mb, K.rounded_rect(0.082, 0.026, 0.01), lambda u, v, x=x: coat_at(x - u, 0.49 + v, 0.004), COAT, skirt_w, thick=0.005)
        p, n = coat_at(x, 0.482, 0.012)
        ellipsoid(mb, p, (0.007, 0.007, 0.003), TOGGLE, skirt_w, segs=8, rings=6, rot=rot_align(n, UP))
    # folded hood resting on the upper back
    hw = lambda p: rig.mix((torso_w(p), 0.7), ({'neck': 1.0}, 0.3))
    ellipsoid(mb, Vector((0.0, -0.118, 0.846)), (0.16, 0.075, 0.085), COAT, hw, segs=24, rings=14, rot=rot_x(18), power=2.3)
    ell = []
    for k in range(17):
        a = math.radians(15 + 150 * k / 16)
        ell.append(Vector((0.15 * math.cos(a), -0.16, 0.85 + 0.062 * math.sin(a))))
    sweep(mb, ell, [(0.012, 0.012)] * len(ell), COAT_D, lambda p, sv, i: hw(p), segs=8, twist_hint=FWD)
    # rain trousers between the hem and the boots
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.4, 0.235, 0.02, RAIN_TROUSER, segs=12)
    # tall rain boots (this outfit's own footwear)
    for sx in SIDES:
        _rain_boot(mb, sx)
    return mb


def _rain_boot(mb, sx):
    sfx = '.L' if sx < 0 else '.R'
    fw = lambda p, sfx=sfx: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03)
    cx = rig.HIP_X * sx
    slab(mb, P._foot_outline(sx, toe=0.175, heel=-0.075, w_heel=0.056, w_toe=0.07), 0.0, 0.03, BOOT_SOLE, fw, bevel=0.01)
    ellipsoid(mb, Vector((cx, 0.046, 0.026)), (0.066, 0.13, 0.078), BOOT, fw, segs=22, rings=14, cut_below=-0.05)
    # (Pass 9: the shaft stops 4 cm under the knee: shin-rigid right up to
    # it, its top and the trouser over it parted by 1.8 cm in a run)
    lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3),
          [(0.04, 0.066), (0.1, 0.063), (0.17, 0.064), (0.225, 0.069), (0.255, 0.074), (0.262, 0.077), (0.265, 0.073),
           (0.257, 0.065), (0.235, 0.061)], BOOT, fw, segs=22, ry_scale=1.04)
    # sole band and a pull tab at the back of the shaft
    lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3), torus_profile(0.042, 0.066, 0.008, 8, 0.9), BOOT_SOLE, fw, segs=22,
          closed_profile=True, ry_scale=1.04)
    ellipsoid(mb, Vector((cx, -0.073, 0.242)), (0.014, 0.006, 0.026), BOOT_SOLE, fw, segs=8, rings=6)


# ================================================================== CAMPUS COURIER
SHIRT = S('#ffffff', T_PRIMARY, 0.9)
SHIRT_S = S('#ffffff', T_SECOND, 0.9)
VEST = S('#2b807b', rough=0.85)
VEST_D = S('#226964', rough=0.85)
MUSTARD = S('#e3aa3f', rough=0.8)
MUSTARD_D = S('#c48c2c', rough=0.8)
CANVAS = S('#d9a441', rough=0.9)
KHAKI_SHORTS = S('#b59c6a', rough=0.9)
KHAKI_SHORTS_D = S('#9c8455', rough=0.9)
BUCKLE = S('#d8dce4', rough=0.25, mat=MAT_GLOSS)


def vest_gap(z, lo=0.24, hi=0.5, z0=0.53, z1=0.86):
    return lerp(lo, hi, smoothstep(z0 + 0.12, z1, z))


def build_vest(mb, style, trim, grow, z0=0.5, z1=0.862, gap=vest_gap, rib=None, wfn=torso_w):
    zs = []
    z = z0
    while z < z1 - 1e-6:
        zs.append(z)
        z += 0.026
    zs.append(z1)
    left, right = K.open_shell(mb, zs, lambda z: grow, gap, style, wfn, segs=32, rib=rib)
    for edge in (left, right):
        K.path_tube(mb, edge, 0.0055, trim, wfn, segs=5, hint=FWD, cap='flat')
    # hem trim (around the back, front edge to front edge)
    hem = []
    g0 = gap(z0)
    for k in range(33):
        th = math.pi * 0.5 + g0 + (2 * math.pi - 2 * g0) * k / 32
        r = max(torso_r(z0), 0.06) + grow
        hem.append(Vector((math.cos(th) * r, TORSO_CY + math.sin(th) * r * TORSO_RY, z0)))
    K.path_tube(mb, hem, 0.0055, trim, wfn, segs=5, hint=UP, cap='flat')
    return left, right


def build_courier():
    mb = MeshBuilder('courier')
    g = 0.016
    torso_lathe(mb, SHIRT, g, 0.50, 0.872, top_open_r=0.09, hem_fold=0.02)
    collar(mb, g, SHIRT_S)
    sleeves(mb, SHIRT, 0.019, s1=0.12, cuff_style=SHIRT_S, cuff_tube=0.012, lod=1)
    for sx in SIDES:
        K.skin_arm(mb, sx, 0.09, SKIN)
    vg = 0.038
    build_vest(mb, VEST, MUSTARD, vg)
    # vest pockets with flaps: chest pair and lower pair
    for sx in SIDES:
        for (z, w, h) in ((0.755, 0.06, 0.05), (0.6, 0.072, 0.06)):
            x = 0.115 * sx
            decal(mb, K.rounded_rect(w, h, 0.01), place_front(x, z, vg), VEST_D, torso_w, thick=0.004)
            decal(mb, K.rounded_rect(w + 0.006, 0.02, 0.008), place_front(x, z + h * 0.5 - 0.004, vg + 0.004), VEST, torso_w,
                  thick=0.004)
    # messenger strap: left shoulder, across the chest and the back, to the bag on the right hip
    sg = vg + 0.012
    front, back = [], []
    for k in range(11):
        t = k / 10
        x = lerp(-0.112, 0.205, t)
        z = lerp(0.862, 0.56, t)
        front.append(torso_at(x, z, sg)[0])
        back.append(torso_at(x, z, sg, back=True)[0])
    # (over the shoulder it runs under the head's overhang, inside the sleeve cap)
    over = [Vector((-0.14, y, 0.893 - 0.01 * (y / 0.07) ** 2)) for y in (0.06, 0.03, 0.0, -0.03, -0.06)]
    strap = list(reversed(front)) + over + back
    strap = _dense_path(strap, 0.03)
    sweep(mb, strap, [(0.0045, 0.017)] * len(strap), MUSTARD_D, lambda p, sv, i: torso_w(p), segs=6, cap_start='flat',
          cap_end='flat', twist_hint=UP)
    # the bag on the right hip
    bc = Vector((0.275, -0.035, 0.475))
    ellipsoid(mb, bc, (0.038, 0.105, 0.078), CANVAS, hip_rigid, segs=20, rings=12, power=4.0)
    ellipsoid(mb, bc + Vector((0.03, 0.0, 0.03)), (0.014, 0.11, 0.06), MUSTARD_D, hip_rigid, segs=18, rings=10, power=4.0)
    ellipsoid(mb, bc + Vector((0.045, 0.0, 0.01)), (0.006, 0.014, 0.05), VEST_D, hip_rigid, segs=8, rings=6, power=3.0)
    ellipsoid(mb, bc + Vector((0.05, 0.0, -0.015)), (0.006, 0.02, 0.014), BUCKLE, hip_rigid, segs=8, rings=6, power=3.0)
    # cargo shorts with side pockets, skin legs and crew socks
    pelvis(mb, KHAKI_SHORTS, 0.016, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.53, 0.37, lambda z: 0.03 - 0.012 * smoothstep(0.5, 0.37, z), KHAKI_SHORTS, segs=16)
        K.ring_on_leg(mb, sx, 0.374, 0.018, 0.009, KHAKI_SHORTS_D)
        prj = leg_project(sx, 0.036)
        c, nn = leg_point(sx, 0.46, 0.0, 0.036)
        decal(mb, K.rounded_rect(0.06, 0.07, 0.01), place_planar(c, nn, UP, prj), KHAKI_SHORTS_D, lambda q, sx=sx: leg_w(q, sx),
              thick=0.005)
        decal(mb, K.rounded_rect(0.066, 0.022, 0.008), place_planar(c + Vector((0, 0, 0.03)), nn, UP, leg_project(sx, 0.041)),
              KHAKI_SHORTS, lambda q, sx=sx: leg_w(q, sx), thick=0.004)
    leg_skin_and_socks(mb, 0.41, 0.2, SOCK_WHITE, stripes=([(0.17, 0.178)], VEST))
    return mb


def build_courier_cap():
    """Six-panel courier cap with a curved brim (worn with campus_courier, no hat)."""
    mb = MeshBuilder('acc_courier_cap')
    hw = rigid('head')
    grow = 0.044

    def edge(ang):
        # forehead 1.30, temples 1.25, nape 1.215
        return 1.215 + 0.085 * K_front(ang) + 0.02 * math.sin(ang) ** 2

    P.hair_shell(mb, grow, edge, VEST, hw, segs=48, rows=12, tuck=0.012)
    # seams: three over the crown, front to back
    for k in range(3):
        ang = -math.pi + math.pi / 3 * (k + 0.5)
        pts = []
        for j in range(12):
            z = lerp(edge(ang) + 0.01, HEAD_C.z + 0.33, j / 11)
            pts.append(P._shell_point(ang, z, grow + 0.002))
        pts2 = []
        for j in range(12):
            z = lerp(HEAD_C.z + 0.33, edge(ang + math.pi) + 0.01, j / 11)
            pts2.append(P._shell_point(ang + math.pi, z, grow + 0.002))
        K.path_tube(mb, pts + pts2[1:], 0.0028, VEST_D, hw, segs=5, hint=UP)
    top = Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + 0.30 + grow + 0.004))
    ellipsoid(mb, top, (0.02, 0.02, 0.011), MUSTARD, hw, segs=10, rings=6)
    # mustard band and a chevron patch on the front panel
    band, bn = [], []
    for k in range(48):
        ang = -math.pi + 2 * math.pi * k / 48
        q = P._shell_point(ang, edge(ang) + 0.012, grow)
        band.append(q)
        bn.append(rig.head_normal(q, grow))
    K.ribbon(mb, band, bn, 0.008, 0.0022, MUSTARD, hw, segs=6)
    c = P.head_point(0.0, 1.405, grow)
    n = rig.head_normal(c, grow)
    strip_decal(mb, [(-0.03, 0.006), (0.0, -0.016), (0.03, 0.006)], [(-0.03, 0.02), (0.0, -0.002), (0.03, 0.02)],
                place_planar(c, n, UP, head_project(grow)), MUSTARD, hw, thick=0.003)
    # brim
    ellipsoid(mb, Vector((0, 0.262, 1.30)), (0.19, 0.17, 0.016), VEST_D, hw, segs=28, rings=10, rot=rot_x(-8),
              keep=lambda p: p.y > 0.228, power=2.2)
    return mb


def K_front(ang):
    return 0.5 - 0.5 * math.cos(ang)


# ================================================================== LANTERN SCOUT
SCOUT_KHAKI = S('#ccb88b', rough=0.9)
SCOUT_KHAKI_D = S('#b39f73', rough=0.9)
SCOUT_GREEN = S('#3f6d52', rough=0.85)
SCOUT_GREEN_D = S('#33583f', rough=0.85)
SCARF = S('#2e9c95', rough=0.85)
BRASS = S('#d9a948', rough=0.3, mat=MAT_GLOSS)
BELT = S('#6b4528', rough=0.45, mat=MAT_RUBBER)
OLIVE = S('#7a7650', rough=0.9)
OLIVE_D = S('#66633f', rough=0.9)
FLAME = S('#ffcf5c', rough=0.2, mat=MAT_EMIT)
GLASS = S('#f7e7b8', rough=0.1, mat=MAT_LIT)
BADGES = [
    # (x, z, base colour, symbol)
    (-0.117, 0.785, '#25335f', 'moon'), (-0.135, 0.69, '#b8433f', 'star'), (-0.098, 0.6, '#2f8f88', 'wave'),
    (0.117, 0.785, '#e0a33a', 'tree'), (0.133, 0.69, '#5a76c8', 'flame'),
]


def _badge(mb, x, z, grow, base, sym):
    pl = place_front(x, z, grow)
    decal(mb, K.circle_outline(0.022, 14), pl, S(base, rough=0.8), torso_w, thick=0.003)
    rim = [pl(0.0215 * math.cos(2 * math.pi * k / 14), 0.0215 * math.sin(2 * math.pi * k / 14)) for k in range(14)]
    K.path_tube(mb, [p + n * 0.0035 for p, n in rim], 0.0022, BRASS, torso_w, segs=4, hint=FWD, closed=True)
    top = place_front(x, z, grow + 0.0032)
    ivory = S('#f6efd9', rough=0.6)
    if sym == 'moon':
        o, i = K.crescent(0.012, 0.8, 0.5, 10, math.radians(30))
        strip_decal(mb, o, i, top, S('#f3cf6a', rough=0.4, mat=MAT_LIT), torso_w, thick=0.0015)
    elif sym == 'star':
        decal(mb, K.star_outline(0.012), top, ivory, torso_w, thick=0.0015)
    elif sym == 'wave':
        K.surface_tube(mb, [(-0.013 + 0.026 * k / 6, 0.003 * math.sin(k / 6 * 3 * math.pi)) for k in range(7)], top, 0.0022,
                       ivory, torso_w, segs=4, cap='flat')
        K.surface_tube(mb, [(-0.011 + 0.022 * k / 6, -0.007 + 0.003 * math.sin(k / 6 * 3 * math.pi)) for k in range(7)], top,
                       0.0018, ivory, torso_w, segs=4, cap='flat')
    elif sym == 'tree':
        decal(mb, [(0.0, 0.014), (-0.012, -0.006), (0.012, -0.006)], top, S('#2f6b45', rough=0.7), torso_w, thick=0.0015)
        decal(mb, K.rounded_rect(0.005, 0.008, 0.001, 1), place_front(x, z - 0.01, grow + 0.0032), S('#6b4528', rough=0.7),
              torso_w, thick=0.0012)
    elif sym == 'flame':
        fl = [(0.0, 0.014), (-0.004, 0.006), (-0.009, -0.002), (-0.007, -0.009), (0.0, -0.012), (0.007, -0.009), (0.009, -0.002),
              (0.004, 0.006)]
        decal(mb, fl, top, S('#ffb347', rough=0.5, mat=MAT_LIT), torso_w, thick=0.0015)


def build_scout():
    mb = MeshBuilder('scout')
    g = 0.016
    torso_lathe(mb, SCOUT_KHAKI, g, 0.50, 0.872, top_open_r=0.09, hem_fold=0.02)
    # (no shirt collar: the neckerchief's roll sits where it would)
    # long sleeves rolled up to the forearm
    sleeves(mb, SCOUT_KHAKI, 0.016, s1=0.245, cuff_style=SCOUT_KHAKI_D, cuff_tube=0.02, lod=1)
    for sx in SIDES:
        K.skin_arm(mb, sx, 0.22, SKIN)
        # epaulette tab
        c = shoulder(sx) + Vector((-0.035 * sx, 0, 0.05))
        # (Pass 9: the epaulette follows the shoulder cap it lies on; rigid on
        # the shoulder bone it lifted off the cap by up to 7 cm with the arm up)
        ellipsoid(mb, c, (0.05, 0.022, 0.008), SCOUT_KHAKI_D, lambda q, sx=sx: P.shoulder_cap_w(q, sx),
                  segs=12, rings=6)
    vg = 0.036
    build_vest(mb, SCOUT_GREEN, S('#efe3c2', rough=0.8), vg, gap=lambda z: vest_gap(z, 0.2, 0.46))
    for (x, z, base, sym) in BADGES:
        _badge(mb, x, z, vg, base, sym)
    # neckerchief: a roll round the collar, a woggle and two tails; the point down the back
    lathe(mb, Vector((0, TORSO_CY - 0.006, 0)), Matrix.Identity(3), torus_profile(0.876, 0.112, 0.018, 8, 1.1), SCARF, torso_w,
          segs=24, closed_profile=True, ry_scale=0.92)
    for sx in SIDES:
        # (Pass 9: the tails meet under the woggle, which gathers them; they
        # passed either side of it and the ring floated between them)
        pts = [torso_at(0.06 * sx, 0.862, g + 0.012)[0], torso_at(0.009 * sx, 0.79, g + 0.012)[0],
               torso_at(0.012 * sx, 0.74, g + 0.01)[0], torso_at(0.022 * sx, 0.70, g + 0.008)[0]]
        pts = _smooth_path(pts, 0.012)
        sweep(mb, pts, [(lerp(0.006, 0.004, i / (len(pts) - 1)), lerp(0.016, 0.012, i / (len(pts) - 1))) for i in range(len(pts))],
              SCARF, lambda p, sv, i: torso_w(p), segs=6, twist_hint=FWD)
    p, n = torso_at(0.0, 0.79, g + 0.02)
    lathe(mb, p, rot_align(UP, n), torus_profile(0.0, 0.02, 0.0055, 8), BRASS, torso_w, segs=14, closed_profile=True, ry_scale=0.55)
    decal(mb, [(0.0, -0.11), (0.07, 0.0), (-0.07, 0.0)], place_back(0.0, 0.85, vg + 0.002), SCARF, torso_w, thick=0.004)
    # belt, buckle and the little lantern on the left hip
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.56, torso_r(0.56) + 0.024, 0.016, 6, 0.75), BELT,
          torso_w, segs=28, closed_profile=True, ry_scale=TORSO_RY)
    p, n = torso_at(0.0, 0.56, 0.042)
    ellipsoid(mb, p, (0.026, 0.02, 0.006), BRASS, torso_w, segs=10, rings=6, rot=rot_align(n, UP), power=4.0)
    _lantern(mb, Vector((-0.262, 0.03, 0.47)))
    # shorts, knee socks
    pelvis(mb, OLIVE, 0.016, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.53, 0.385, lambda z: 0.03 - 0.014 * smoothstep(0.5, 0.385, z), OLIVE, segs=16)
        K.ring_on_leg(mb, sx, 0.388, 0.016, 0.008, OLIVE_D)
    leg_skin_and_socks(mb, 0.42, 0.265, SCOUT_GREEN, stripes=([(0.235, 0.255)], S('#efe3c2', rough=0.9)), rib=SCOUT_GREEN_D)
    return mb


def _lantern(mb, c):
    hw = hip_rigid
    R = Matrix.Identity(3)
    # hook from the belt, brass cap, glass with a glowing wick, brass base
    K.path_tube(mb, [c + Vector((0.0, 0.0, 0.085)), c + Vector((0.006, 0.0, 0.07)), c + Vector((0.0, 0.0, 0.052))], 0.0028, BRASS, hw,
                segs=5, hint=FWD)
    lathe(mb, c, R, [(0.036, 0.0), (0.036, 0.008), (0.042, 0.016), (0.048, 0.022), (0.052, 0.0)], BRASS, hw, segs=14)
    lathe(mb, c, R, [(-0.026, 0.017), (-0.012, 0.02), (0.012, 0.02), (0.026, 0.017)], GLASS, hw, segs=14)
    ellipsoid(mb, c + Vector((0, 0, 0.003)), (0.009, 0.009, 0.014), FLAME, hw, segs=10, rings=6)
    lathe(mb, c, R, [(-0.042, 0.0), (-0.042, 0.022), (-0.034, 0.024), (-0.026, 0.022), (-0.026, 0.0)], BRASS, hw, segs=14)
    for k in range(4):
        a = math.pi * 0.5 * k + math.pi * 0.25
        q0 = c + Vector((math.cos(a) * 0.021, math.sin(a) * 0.021, -0.026))
        q1 = c + Vector((math.cos(a) * 0.021, math.sin(a) * 0.021, 0.036))
        K.path_tube(mb, [q0, q1], 0.0018, BRASS, hw, segs=4, hint=UP, cap=None)


# ================================================================== SEASON 1 · AFTER HOURS: outfits
VIOLET = S('#6b4d9e', rough=0.9)
VIOLET_D = S('#5a3f88', rough=0.9)
VIOLET_RIB = S('#4d3576', rough=0.9)
LINING = S('#efe2c8', rough=0.9)
CHARCOAL = S('#2f3443', rough=0.85)
CHARCOAL_RIB = S('#262a36', rough=0.9)


def build_hoodie():
    mb = MeshBuilder('hoodie')
    g = 0.024
    torso_lathe(mb, VIOLET, g, 0.535, 0.872, top_open_r=0.092)
    _rib_band(mb, 0.497, 0.55, 0.02, VIOLET_RIB, None)
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.872, 0.098, 0.014, 6), VIOLET_RIB, torso_w, segs=24,
          closed_profile=True, ry_scale=0.92)
    sleeves(mb, VIOLET, 0.022, cuff_style=VIOLET_RIB, cuff_tube=0.02, lod=1)
    # kangaroo pocket with slanted openings
    decal(mb, K.rounded_rect(0.2, 0.085, 0.02), place_front(0.0, 0.6, g), VIOLET_D, torso_w, thick=0.004)
    for sx in SIDES:
        K.surface_tube(mb, [(sx * 0.1, 0.04), (sx * 0.085, -0.004), (sx * 0.075, -0.04)], place_front(0.0, 0.6, g + 0.004), 0.0035,
                       VIOLET_RIB, torso_w, segs=5)
    # gold moon print with three stars
    o, i = K.crescent(0.04, 0.8, 0.46, 14, math.radians(20))
    strip_decal(mb, o, i, place_front(0.012, 0.745, g), GOLD, torso_w, thick=0.003)
    for (x, z, r) in ((-0.045, 0.79, 0.011), (-0.06, 0.735, 0.008), (-0.03, 0.705, 0.007)):
        star_at(mb, place_front(x, z, g), r, GOLD, torso_w, rot=x * 20)
    # drawstrings with aglets
    for sx in SIDES:
        pts = [torso_at(0.035 * sx, 0.868, g + 0.006)[0], torso_at(0.037 * sx, 0.8, g + 0.008)[0], torso_at(0.04 * sx, 0.73, g + 0.006)[0]]
        pts = _smooth_path(pts, 0.015)
        K.path_tube(mb, pts, 0.0035, LINING, torso_w, segs=5, hint=FWD, cap='flat')
        p, n = torso_at(0.04 * sx, 0.72, g + 0.008)
        ellipsoid(mb, p, (0.0045, 0.0045, 0.012), GOLD, torso_w, segs=8, rings=6)
    # the hood, folded down on the upper back, lining showing
    hw = lambda p: rig.mix((torso_w(p), 0.7), ({'neck': 1.0}, 0.3))
    ellipsoid(mb, Vector((0.0, -0.122, 0.852)), (0.17, 0.08, 0.09), VIOLET, hw, segs=22, rings=12, rot=rot_x(16), power=2.3)
    ellipsoid(mb, Vector((0.0, -0.112, 0.912)), (0.12, 0.05, 0.022), LINING, hw, segs=18, rings=8, rot=rot_x(10))
    # joggers
    pelvis(mb, CHARCOAL, 0.016, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.11, lambda z: 0.024 - 0.006 * smoothstep(0.35, 0.15, z), CHARCOAL, segs=16)
        _rib_leg(mb, sx, 0.085, 0.13, 0.012, CHARCOAL_RIB)
        stripe = [leg_point(sx, z, 0.0, 0.024 - 0.006 * smoothstep(0.35, 0.15, z) + 0.002)[0] for z in (0.53, 0.42, 0.31, 0.22, 0.14)]
        K.path_tube(mb, stripe, 0.003, LINING, lambda q, sx=sx: leg_w(q, sx), segs=4, hint=Vector((sx, 0, 0)), cap='flat')
    return mb


def _rib_leg(mb, sx, z0, z1, grow, style, segs=16):
    """Ribbed ankle cuff on the leg between two heights."""
    pts = rig.leg_path(sx, 0.55)
    k, a = pts[1], pts[2]
    d = (a - k).normalized()
    c0 = k.lerp(a, (k.z - z0) / (k.z - a.z))
    r0 = P.leg_radius(rig.leg_s(c0, sx)) + grow
    lathe(mb, c0, rot_align(-d, FWD), [(-0.004, r0 - 0.006), (0.0, r0), ((z1 - z0), r0), ((z1 - z0) + 0.004, r0 - 0.006)], style,
          lambda q, sx=sx: leg_w(q, sx), segs=segs, rfn=lambda r, th, z: r + 0.0012 * math.cos(th * (segs // 2)))


TAWNY = S('#9a6b45', rough=0.95)
TAWNY_D = S('#7a5236', rough=0.95)
OWL_BELLY = S('#f3e2c0', rough=0.95)
OWL_SCALE = S('#dec69e', rough=0.95)
AMBER = S('#f2a93b', rough=0.25, mat=MAT_GLOSS)
BEAK = S('#e8a13a', rough=0.4, mat=MAT_GLOSS)
EYE_WHITE = S('#fbfaf6', rough=0.3, mat=MAT_LIT)
PUPIL = S('#1b1d2b', rough=0.2, mat=MAT_GLOSS)
SHINE = S('#ffffff', rough=0.1, mat=MAT_EMIT)


def _feather(w, h, n=10):
    """Pointed feather outline, tip down (v < 0), CCW."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x = math.cos(a) * w / 2
        y = math.sin(a) * h / 2
        if y < 0:
            x *= (1.0 + y / (h / 2)) ** 0.6     # taper to a point at the bottom
        out.append((x, y + h * 0.1))
    return out


def build_owl():
    mb = MeshBuilder('owl')
    g = 0.05
    bulge = lambda z: 0.025 * math.sin(math.pi * smoothstep(0.46, 0.86, z))
    torso_lathe(mb, TAWNY, g, 0.46, 0.88, bottom_pole=True, extra=bulge)
    # feathered belly: a cream patch with rows of scalloped feathers
    # (final sweep: the patch is bent onto the belly, and the feathers lie on
    # its top; the flat patch's rim stood up to 6 cm off the body in profile)
    _, _, top = P.belly_panel(mb, OWL_BELLY, lambda z: g + bulge(z), 0.675, (0.15, 0.16, 0.03))
    for row, z in enumerate((0.75, 0.705, 0.66, 0.615, 0.57)):
        cols = 4 if row % 2 == 0 else 3
        for c in range(cols):
            x = (c - (cols - 1) / 2) * 0.052
            if abs(x) > 0.11:
                continue
            on_patch = (lambda u, v, x=x, z=z: torso_at(x - u, z + v, g + bulge(z + v) + top(x - u, z + v) - 0.001))
            decal(mb, _feather(0.04, 0.034, 9), on_patch, OWL_SCALE, torso_w, thick=0.003)
    # wing sleeves: tawny with darker feather rows on the outside and three
    # flight feathers at each wrist
    sleeves(mb, TAWNY, 0.03, lod=1)
    for sx in SIDES:
        # (final sweep: on the sleeve's own radius, which gathers into the
        # cuff over its last 6 cm: the wrist feathers stood 0.7 cm off it)
        prj = cyl_project(shoulder(sx), arm_dir(sx), lambda s: P.sleeve_r(s, 0.03))
        for k, (s, ang) in enumerate(((0.06, 10.0), (0.1, -25.0), (0.14, 15.0), (0.19, -20.0), (0.23, 10.0), (0.27, -15.0))):
            c, nn = arm_point(sx, s, ang - 40.0, P.sleeve_r(s, 0.03))
            decal(mb, _feather(0.042, 0.05, 9), place_planar(c, nn, -arm_dir(sx), prj), TAWNY_D, lambda q, sx=sx: arm_w(q, sx),
                  thick=0.004, lift=0.002)
        d = arm_dir(sx)
        w = rig.wrist(sx)
        for k in range(3):
            base = w - d * (0.03 + 0.018 * k) + Vector((0, -0.045, 0))
            tip = (d * 0.6 + Vector((0, -0.7, -0.35))).normalized()
            ellipsoid(mb, base + tip * 0.035, (0.012, 0.006, 0.04), TAWNY_D, lambda q, sx=sx: arm_w(q, sx), segs=10, rings=6,
                      rot=rot_align(tip, Vector((sx, 0, 0))))
    P.pant_legs(mb, TAWNY, 0.03)
    # tail feathers
    for i, a in enumerate((-28, 0, 28)):
        R = rot_x(-58) @ rot_y(a)
        ellipsoid(mb, Vector((0.035 * (i - 1), -0.262, 0.52)), (0.05, 0.02, 0.09), TAWNY_D, hip_rigid, segs=10, rings=8, rot=R)
    # the hood: face opening, rim, owl eyes and beak, ear tufts
    P._hood(mb, TAWNY, OWL_BELLY)
    hw = rigid('head')
    hp = P.hood_project()
    for sx in SIDES:
        c, n = P.hood_point(0.105 * sx, 1.415)
        R2 = rot_align(n, UP)
        # (final sweep: each disc bent onto the hood, so its rim meets it;
        # flat, its rim stood off the round hood)
        for off, radii, st, sg, rg in ((0.0, (0.088, 0.08, 0.022), OWL_BELLY, 18, 8), (0.014, (0.058, 0.055, 0.015), EYE_WHITE, 16, 8),
                                       (0.024, (0.04, 0.04, 0.011), AMBER, 16, 8), (0.031, (0.022, 0.023, 0.008), PUPIL, 12, 6)):
            ellipsoid(mb, c + n * off, radii, st, hw, segs=sg, rings=rg, rot=R2, deform=K.conform(c + n * off, R2, hp))
        up = R2 @ Vector((0, 1, 0))
        side = R2 @ Vector((1, 0, 0))
        ellipsoid(mb, c + n * 0.037 + up * 0.014 - side * 0.01 * sx, (0.008, 0.008, 0.003), SHINE, hw, segs=8, rings=4, rot=R2)
        # ear tuft: three feathers fanning up and out
        root = Vector((0.17 * sx, -0.01, 1.46))
        for k, (spread, ln) in enumerate(((-16, 0.11), (0, 0.14), (18, 0.1))):
            dirv = (rot_y(-sx * (22 + spread)) @ Vector((0, 0.1, 1))).normalized()
            ellipsoid(mb, root + dirv * ln * 0.5, (0.03, 0.017, ln * 0.55), TAWNY_D if k == 1 else TAWNY, hw, segs=12, rings=8,
                      rot=rot_align(dirv, FWD))
    # (on the hood's roll above the face opening)
    bp, bn = P.hood_point(0.0, 1.345, lift=0.005)
    lathe(mb, bp, rot_align((bn + Vector((0, 0, -0.6))).normalized(), FWD), [(0.0, 0.0), (0.0, 0.028), (0.025, 0.02), (0.055, 0.0)],
          BEAK, hw, segs=12, ry_scale=0.8)
    return mb


JOG_TOP = S('#2a2f3d', rough=0.55)
JOG_SHORTS = S('#1c1f28', rough=0.6)
GLOW = S('#ffffff', T_SECOND, 0.2, MAT_EMIT)      # glows in (a light shade of) the player's colour


def build_jogger():
    mb = MeshBuilder('jogger')
    g = 0.012
    torso_lathe(mb, JOG_TOP, g, 0.5, 0.866, top_open_r=0.088)
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), [(0.846, 0.11), (0.865, 0.114), (0.888, 0.1), (0.892, 0.094),
          (0.875, 0.092)], JOG_TOP, torso_w, segs=24, ry_scale=0.92)
    sleeves(mb, JOG_TOP, 0.011, cuff_style=JOG_TOP, cuff_tube=0.012, lod=1)
    # glowing chevrons across the chest, side seams, forearm bands and wristbands
    for z in (0.76, 0.69):
        strip_decal(mb, [(-0.13, 0.016), (-0.065, -0.008), (0.0, -0.032), (0.065, -0.008), (0.13, 0.016)],
                    [(-0.13, 0.04), (-0.065, 0.016), (0.0, -0.008), (0.065, 0.016), (0.13, 0.04)], place_front(0.0, z, g), GLOW, torso_w,
                    thick=0.0025)
    for sx in SIDES:
        seam = []
        for k in range(9):
            z = lerp(0.52, 0.82, k / 8)
            r = max(torso_r(z), 0.06) + g + 0.002
            seam.append(Vector((sx * r, TORSO_CY, z)))
        K.path_tube(mb, seam, 0.0032, GLOW, torso_w, segs=4, hint=FWD, cap='flat')
        K.ring_on_arm(mb, sx, 0.22, 0.012, 0.0035, GLOW, segs=14, squash=1.0, n=4)
        # (Pass 9: the wristband sits on the eased cuff)
        K.ring_on_arm(mb, sx, 0.302, 0.0, 0.0085, GLOW, segs=14, squash=1.0, n=5, r=P.sleeve_r(0.302, 0.011) + 0.004)
    # running shorts over leggings with glow stripes and ankle bands
    pelvis(mb, JOG_SHORTS, 0.02, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.53, 0.44, lambda z: 0.03 - 0.008 * smoothstep(0.5, 0.44, z), JOG_SHORTS, segs=16)
        K.ring_on_leg(mb, sx, 0.442, 0.022, 0.004, GLOW, segs=16, n=4)
        K.leg_tube(mb, sx, 0.47, 0.09, 0.012, JOG_TOP, segs=14)
        stripe = [leg_point(sx, z, 0.0, 0.014)[0] for z in (0.43, 0.34, 0.26, 0.18)]
        K.path_tube(mb, stripe, 0.003, GLOW, lambda q, sx=sx: leg_w(q, sx), segs=4, hint=Vector((sx, 0, 0)), cap='flat')
        K.ring_on_leg(mb, sx, 0.15, 0.0135, 0.004, GLOW, segs=14, n=4)
    return mb


OAT = S('#d9c7a2', rough=0.95)
OAT_D = S('#c3ae86', rough=0.95)
SHIRT_WHITE = S('#f5f2ea', rough=0.85)
TIE = S('#2f5a46', rough=0.8)
SUEDE = S('#7a5a3e', rough=0.95)
WOOD_BTN = S('#7a5332', rough=0.35, mat=MAT_GLOSS)
CORD = S('#7a5136', rough=0.95)
CORD_D = S('#694430', rough=0.95)
PENCIL = S('#f2c33d', rough=0.5)
ERASER = S('#f08aa0', rough=0.8)


def build_cardigan():
    mb = MeshBuilder('cardigan')
    g = 0.014
    torso_lathe(mb, SHIRT_WHITE, g, 0.5, 0.872, top_open_r=0.09)
    collar(mb, g, SHIRT_WHITE)
    # knit tie in the V
    tie = [torso_at(0.0, z, g + 0.004)[0] for z in (0.852, 0.80, 0.74, 0.68, 0.635)]
    sweep(mb, _dense_path(tie, 0.03), [(0.004, lerp(0.012, 0.017, k / 6)) for k in range(len(_dense_path(tie, 0.03)))], TIE,
          lambda p, sv, i: torso_w(p), segs=6, cap_start='flat', cap_end='round', twist_hint=FWD)
    p, n = torso_at(0.0, 0.855, g + 0.012)
    ellipsoid(mb, p, (0.016, 0.012, 0.011), TIE, torso_w, segs=10, rings=6, rot=rot_align(n, UP))
    # the cardigan: an open cable-knit shell with a deep V and ribbed edges
    cg = 0.034
    gap = lambda z: lerp(0.16, 0.6, smoothstep(0.6, 0.86, z))
    left, right = build_vest(mb, OAT, OAT_D, cg, z0=0.49, gap=gap, rib=lambda th, z: 0.0022 * math.cos(th * 16))
    sleeves(mb, OAT, 0.026, cuff_style=OAT_D, cuff_tube=0.02, lod=1)
    # shirt cuffs out of the cardigan sleeves
    for sx in SIDES:
        # (Pass 9: the shirt cuff fills the eased cardigan cuff round the wrist)
        K.ring_on_arm(mb, sx, rig.UPPER_LEN + rig.FORE_LEN - 0.004, 0.0, 0.0055, SHIRT_WHITE, segs=14, n=5,
                      r=P.bare_arm_radius(rig.UPPER_LEN + rig.FORE_LEN - 0.004) + 0.0055)
        # suede elbow patches
        prj = sleeve_project(sx, 0.026)
        c, nn = arm_point(sx, rig.UPPER_LEN + 0.005, -110.0, P.arm_radius(rig.UPPER_LEN) + 0.026)
        decal(mb, K.circle_outline(0.024, 12, 0.032), place_planar(c, nn, arm_dir(sx), prj), SUEDE, lambda q, sx=sx: arm_w(q, sx),
              thick=0.003)
    # wooden buttons down the left edge
    for z in (0.53, 0.585, 0.64):
        th = math.pi * 0.5 + gap(z) + 0.09
        pp, nn = K.torso_ang(th, z, cg + 0.004)
        ellipsoid(mb, pp, (0.011, 0.011, 0.004), WOOD_BTN, torso_w, segs=10, rings=6, rot=rot_align(nn, UP))
    # chest pocket with a pencil
    decal(mb, K.rounded_rect(0.06, 0.055, 0.008), place_front(-0.105, 0.735, cg), OAT_D, torso_w, thick=0.004)
    pb, pn = torso_at(-0.115, 0.75, cg + 0.008)
    pd = Vector((0.12, 0.05, 1.0)).normalized()
    lathe(mb, pb, rot_align(pd, FWD), [(0.0, 0.0), (0.0, 0.0065), (0.075, 0.0065), (0.075, 0.0)], PENCIL, torso_w, segs=6)
    lathe(mb, pb + pd * 0.075, rot_align(pd, FWD), [(0.0, 0.0), (0.0, 0.0068), (0.013, 0.0068), (0.016, 0.0)], ERASER, torso_w, segs=8)
    # corduroy trousers (fine wales)
    pelvis(mb, CORD, 0.014, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.085, 0.02, CORD, segs=24, flat_end=True,
                   colfn=lambda p, sv, a: CORD_D if int(round(a / (2 * math.pi) * 24)) % 2 else None)
        K.ring_on_leg(mb, sx, 0.11, 0.024, 0.013, CORD_D, segs=16, n=6)
    return mb


# ================================================================== SEASON 1 · hats
def head_ring(z_front, z_back, grow):
    """Closed loop round the head at a height that eases from front to back."""
    pts = []
    for k in range(40):
        ang = -math.pi + 2 * math.pi * k / 40
        z = lerp(z_back, z_front, 0.5 - 0.5 * math.cos(ang))
        pts.append(P._shell_point(ang, z, grow))
    return pts


STRAP = S('#2d313c', rough=0.6)
REFLECT = S('#dfe4ee', rough=0.25, mat=MAT_LIT)
LAMP = S('#3a3f4c', rough=0.35, mat=MAT_GLOSS)
LENS = S('#fff1c4', rough=0.1, mat=MAT_EMIT)
CHROME = S('#cfd5e0', rough=0.2, mat=MAT_GLOSS)


# Final sweep: bands and straps worn round the head lie on the hair.  At a
# fixed 2.5-2.7 cm off the head they rested on the bob (2.4 cm) and stood
# 0.8-1.1 cm off the thinner tuft, curls and buns (1.6-1.8 cm), so from
# behind on the large preview stage the band read as a halo round the head
# (fit_check "bands").  Their inner side now lies on the thinner styles and
# presses a few millimetres into the bob, and the straps are thick enough to
# stay in view on it.
HAIR_BAND_G = 0.0175        # a band's inner side on the hair (tuft 1.8, curls and buns 1.6, bob 2.4 cm)
FOREHEAD_G = 0.0015         # a band's inner side on the bare forehead


def _band_ring(z_front, z_back, z_hair, front_g, n=40, dip=(150.0, 170.0)):
    """Points and normals of a headlamp's band: on the hair round the back,
    the sides and the temples (at z_hair, above the short styles' hairline,
    1.34-1.37 m), dipping onto the bare forehead (front_g, z_front) between
    the temples, under the lamp (the short styles' hairline crossed the old
    band at different places, 122-139 degrees, so its temples stood off the
    skin with one style or sank into the hair with another)."""
    pts, nrm = [], []
    for k in range(n):
        ang = -math.pi + 2 * math.pi * k / n
        f = 0.5 - 0.5 * math.cos(ang)
        dz = smoothstep(math.radians(dip[0]), math.radians(dip[1]), abs(ang))
        dg = smoothstep(math.radians(dip[0] + 2.0), math.radians(dip[0] + 10.0), abs(ang))
        z = lerp(lerp(z_back, z_hair, f), z_front, dz)
        g = lerp(HAIR_BAND_G, front_g, dg)
        p = P._shell_point(ang, z, g)
        pts.append(p)
        nrm.append(rig.head_normal(p, g))
    return pts, nrm


def build_headlamp():
    mb = MeshBuilder('hat_headlamp')
    hw = rigid('head')
    # worn tilted, as a headlamp sits: low on the forehead, high at the back
    # (over the curly crop's smooth band); final sweep: on the hair round the
    # back, sides and temples, down onto the forehead under the lamp (under
    # a bob's bangs there), 9 mm thick (6) so it shows where it presses into
    # a bob
    pts, nrm = _band_ring(1.335, 1.378, 1.376, FOREHEAD_G)
    K.ribbon(mb, pts, nrm, 0.014, 0.0045, STRAP, hw, segs=8)
    K.ribbon(mb, pts, nrm, 0.0035, 0.0014, REFLECT, hw, segs=4, lift=0.0095)
    # (the strap over the crown ends under the band at the sides: past it,
    # down to 78 degrees, it hung over the bare temples above the ears)
    top, tn = [], []
    for k in range(17):
        a = math.radians(-66 + 132 * k / 16)
        q, n = head_project(HAIR_BAND_G)(Vector((math.sin(a) * 0.4, -0.02, HEAD_C.z + math.cos(a) * 0.4)))
        top.append(q)
        tn.append(n)
    K.ribbon(mb, top, tn, 0.01, 0.0045, STRAP, hw, closed=False, segs=6)
    # (the lamp on the strap's front: the strap's outer face is 1 cm off the forehead)
    c = P.head_point(0.0, 1.335, FOREHEAD_G + 0.011)
    n = rig.head_normal(c, FOREHEAD_G + 0.011)
    R = rot_align(n, UP)
    ellipsoid(mb, c + n * 0.026, (0.056, 0.04, 0.034), LAMP, hw, segs=16, rings=10, rot=R, power=3.0)
    lathe(mb, c + n * 0.057, R, torus_profile(0.0, 0.027, 0.006, 6), CHROME, hw, segs=16, closed_profile=True)
    ellipsoid(mb, c + n * 0.058, (0.025, 0.025, 0.007), LENS, hw, segs=14, rings=6, rot=R)
    up = R @ Vector((0, 1, 0))
    ellipsoid(mb, c + n * 0.034 + up * 0.04, (0.009, 0.007, 0.007), S('#ff8a3d', rough=0.4, mat=MAT_GLOSS), hw, segs=8, rings=6, rot=R)
    return mb


def build_beanie():
    mb = MeshBuilder('hat_beanie')
    hw = rigid('head')
    grow = 0.052

    def edge(ang):
        return 1.18 + 0.115 * K_front(ang) + 0.03 * math.sin(ang) ** 2

    P.hair_shell(mb, grow, edge, S('#ffffff', T_PRIMARY, 0.97), hw, segs=48, rows=12, tuck=0.012)
    # a few knit ribs running up the crown
    for k in range(16):
        ang = -math.pi + 2 * math.pi * (k + 0.5) / 16
        pts = [P._shell_point(ang, lerp(edge(ang) + 0.04, HEAD_C.z + 0.27, j / 6), grow + 0.001) for j in range(7)]
        K.path_tube(mb, pts, 0.004, S('#ffffff', T_DARK, 0.97), hw, segs=4, hint=UP, flat=0.5, cap='flat')
    # rolled cuff
    cuff, cn = [], []
    for k in range(48):
        ang = -math.pi + 2 * math.pi * k / 48
        q = P._shell_point(ang, edge(ang) + 0.026, grow)
        cuff.append(q)
        cn.append(rig.head_normal(q, grow))
    K.ribbon(mb, cuff, cn, 0.028, 0.01, S('#ffffff', T_SECOND, 0.97), hw, segs=10, lift=0.004)
    # pompom
    top = Vector((HEAD_C.x, HEAD_C.y - 0.01, HEAD_C.z + HEAD_R[2] + grow + 0.05))
    K.bumpy(mb, top, (0.068, 0.068, 0.062), S('#f6efe0', rough=1.0), hw, segs=18, rings=12, amp=0.1, freq=9)
    return mb


HEAD_R = rig.HEAD_R


def build_glowband():
    mb = MeshBuilder('hat_glowband')
    hw = rigid('head')
    # (final sweep: on the hair all round, just above the short styles'
    # hairline in front; it stood 1.1-1.3 cm off the tuft, curls and buns.
    # The star is smaller so its points stay on the band's crown)
    zf = 1.392
    pts, nrm = K.head_band_points(zf, 1.36, HAIR_BAND_G)
    K.ribbon(mb, pts, nrm, 0.02, 0.0065, S('#ffffff', T_PRIMARY, 1.0), hw, segs=10)
    K.ribbon(mb, pts, nrm, 0.0045, 0.002, GLOW, hw, segs=4, lift=0.012)
    gs = HAIR_BAND_G + 0.0135
    c = P.head_point(0.0, zf, gs)
    n = rig.head_normal(c, gs)
    decal(mb, K.star_outline(0.015), place_planar(c, n, UP, head_project(gs)), GLOW, hw, thick=0.003)
    return mb


def build_owlears():
    mb = MeshBuilder('hat_owlears')
    hw = rigid('head')
    band, bn = [], []
    for k in range(21):
        # (final sweep: on the hair, and ending at the short styles'
        # hairline above the ears; at 2.6 cm and down to 82 degrees it stood
        # 1.2 cm off the tuft and 1.9 cm off the bare temples)
        a = math.radians(-74 + 148 * k / 20)
        q, n = head_project(HAIR_BAND_G)(Vector((math.sin(a) * 0.45, 0.01, HEAD_C.z + 0.02 + math.cos(a) * 0.45)))
        band.append(q)
        bn.append(n)
    K.ribbon(mb, band, bn, 0.007, 0.0035, S('#6b4a30', rough=0.6), hw, closed=False, segs=6)
    for sx in SIDES:
        root = head_project(0.03)(Vector((0.165 * sx, 0.01, 1.455)))[0]
        for k, (spread, ln, st) in enumerate(((-18, 0.11, TAWNY), (0, 0.14, TAWNY_D), (19, 0.1, TAWNY))):
            dirv = (rot_y(-sx * (20 + spread)) @ Vector((0, 0.15, 1))).normalized()
            ellipsoid(mb, root + dirv * ln * 0.5, (0.03, 0.016, ln * 0.55), st, hw, segs=12, rings=8, rot=rot_align(dirv, FWD))
        ellipsoid(mb, root + Vector((0, 0.016, 0.05)), (0.02, 0.008, 0.045), OWL_BELLY, hw, segs=10, rings=6,
                  rot=rot_y(-sx * 20))
    return mb


# ================================================================== SEASON 1 · shoes
def build_glow_sneakers():
    mb = MeshBuilder('shoe_glow')
    sole = S('#f4f2ec', rough=0.6, mat=MAT_RUBBER)
    upper = S('#2c303c', rough=0.6)
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        fw = lambda p, sfx=sfx: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03)
        P._shoe_base(mb, sx, sole, upper, upper, shaft_top=0.115, laces=GLOW, toe_cap=S('#3a3f4d', rough=0.5))
        # glowing strip round the sole
        outline = P._foot_outline(sx, n=24)
        ring = [Vector((x, y, 0.036)) for x, y in outline]
        ring = [Vector((q.x + (q.x - rig.HIP_X * sx) * 0.02, q.y, q.z)) for q in ring]
        K.path_tube(mb, ring, 0.0045, GLOW, fw, segs=4, hint=UP, flat=1.4, closed=True)
        # a small crescent on the outer side and a glowing heel tab
        cx = rig.HIP_X * sx
        c = Vector((cx + 0.062 * sx, 0.04, 0.07))
        o, i = K.crescent(0.016, 0.78, 0.5, 8, math.radians(10))
        strip_decal(mb, o, i, place_planar(c, Vector((sx, 0, 0)), UP), GLOW, fw, thick=0.002)
        ellipsoid(mb, Vector((cx, -0.075, 0.1)), (0.012, 0.006, 0.02), GLOW, fw, segs=8, rings=6)
    return mb


MOON_BOOT = S('#cfd1ea', rough=0.38, mat=MAT_RUBBER)
MOON_BOOT_D = S('#b3b6d6', rough=0.4, mat=MAT_RUBBER)
MOON_SOLE = S('#7f86a3', rough=0.7, mat=MAT_RUBBER)


def build_moonboots():
    mb = MeshBuilder('shoe_moonboots')
    for sx in SIDES:
        sfx = '.L' if sx < 0 else '.R'
        fw = lambda p, sfx=sfx: rig.seg_weights(p.z, [('foot' + sfx, 0.11), ('shin' + sfx, None)], 0.03)
        cx = rig.HIP_X * sx
        slab(mb, P._foot_outline(sx, toe=0.19, heel=-0.085, w_heel=0.066, w_toe=0.082), 0.0, 0.042, MOON_SOLE, fw, bevel=0.012)
        ellipsoid(mb, Vector((cx, 0.05, 0.05)), (0.08, 0.14, 0.085), MOON_BOOT, fw, segs=22, rings=14, cut_below=-0.3)
        # puffy quilted shaft
        prof = [(0.06, 0.07)]
        for k in range(4):
            z0 = 0.08 + 0.04 * k
            prof += [(z0, 0.072), (z0 + 0.02, 0.081), (z0 + 0.04, 0.072)]
        prof += [(0.245, 0.074), (0.252, 0.068), (0.24, 0.062)]
        lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), prof, MOON_BOOT, fw, segs=20, ry_scale=1.05)
        # gold crescent on the outer side, a drawcord toggle at the top
        c = Vector((cx + 0.083 * sx, -0.004, 0.16))
        o, i = K.crescent(0.022, 0.78, 0.5, 10, math.radians(15))
        strip_decal(mb, o, i, place_planar(c, Vector((sx, 0, 0)), UP), GOLD, fw, thick=0.003)
        ellipsoid(mb, Vector((cx, 0.07, 0.235)), (0.008, 0.008, 0.016), MOON_BOOT_D, fw, segs=8, rings=6)
    return mb


SHOP_PARTS = [build_moonlight, build_starry, build_sleepmask, build_varsity, build_raincoat, build_courier, build_courier_cap,
              build_scout]
SEASON_PARTS = [build_hoodie, build_owl, build_jogger, build_cardigan, build_headlamp, build_beanie, build_glowband, build_owlears,
                build_glow_sneakers, build_moonboots]
ALL = SHOP_PARTS + SEASON_PARTS
