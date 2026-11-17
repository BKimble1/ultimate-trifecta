"""Build 18: six more rotating Shop outfits (two Thanksgiving, three Christmas,
one winter), on the Pass 8 kit.

    turkey_trot        'turkey'                   (hood up with a beak, a tail fan of feathers, orange booties)
    harvest_flannel    'flannel'                  (plaid flannel, knit scarf, maple leaves, duck boots)
    reindeer_onesie    'reindeer'                 (hood up with antlers and a red pompom nose, hooves, a bell)
    gingerbread_buddy  'gingerbread'              (icing trim, gumdrop buttons, a red bow, iced booties)
    elf_helper         'elf' + 'acc_elf_cap'      (petal collar, belt, striped stockings, curled shoes; the cap with no hat)
    snow_day           'snowday'                  (quilted parka, fur-rimmed hood up, knit mittens, snow boots)

Original designs written for this project: no brands, no likeness of any
character (no Santa suit, beard or red-and-white coat), no cultural or
religious costume.  Like the Pass 8 outfits, each is one mesh part (one
draw call) on the shared rig and draws its own footwear
(Cosmetics.OUTFIT_OWN_SHOES); the elf cap is outfit headwear shown with no
hat (Cosmetics.OUTFIT_HEADWEAR, hair-ruled as a cap); the three hoods use
the Pass 8 hood (parts._hood with outfits_p8.HOOD_G / HOOD_OPEN), whose rim
clears the brows.  Nothing is simulated: hood features, antlers and the cap
are rigid on the head; the turkey's fan and the reindeer's tail are rigid
on the hips (tools/character/outfit_check.py measures them against the
limbs through every clip); gloves and footwear follow the hand and foot
as the Pass 8 ones do.  No part uses the emissive class.
"""
import math
from mathutils import Vector, Matrix

import rig
from geo import (MeshBuilder, Style, sweep, ellipsoid, lathe, slab, torus_profile, rot_align, rot_x, rot_z, smoothstep, lerp,
                 clamp_midline, MAT_CLOTH, MAT_RUBBER, MAT_GLOSS, MAT_METAL)
from rig import torso_w, arm_w, leg_w, rigid, torso_r, shoulder, arm_dir, HEAD_C, HEAD_R, TORSO_RY, TORSO_CY
import parts as P
from parts import SKIN, UP, FWD, SIDES, torso_lathe, sleeves, pelvis, _smooth_path, _foot_outline
import kit6 as K
from kit6 import decal, place_front, place_back, place_planar, head_project, torso_at, cyl_project
from outfits_v6 import S, sleeve_project, arm_point, leg_point, leg_project, _rib_leg, _rib_band, _feather
from outfits_p8 import foot_w, gloves, shell, front, leg_tube_stripes, HOOD_G, HOOD_OPEN, _puff, _quilted_profile, \
    pumpkin_cap_edge


# ------------------------------------------------------------------ shared helpers
def _fan_dir(a_deg, tilt_deg):
    """A direction in a fan standing up behind the body: a_deg from upright
    (+ toward +x), the fan leaning back by tilt_deg."""
    a, t = math.radians(a_deg), math.radians(tilt_deg)
    return Vector((math.sin(a), -math.cos(a) * math.sin(t), math.cos(a) * math.cos(t))).normalized()


def wavy_ring(mb, centre, axis, radius, amp, waves, tube, style, wfn, n=48, ry=1.0, side=0, segs=5):
    """Piped icing round a body part: a closed tube on a circle round `axis`
    through `centre` (radius `radius`, y scaled by ry), waving `amp` along
    the axis `waves` times.  side (+-1) eases a leg ring off the midline."""
    d = Vector(axis).normalized()
    R = rot_align(d, FWD)
    X, Y = R @ Vector((1, 0, 0)), R @ Vector((0, 1, 0))
    pts = []
    for k in range(n):
        th = 2 * math.pi * k / n
        pts.append(Vector(centre) + X * (math.cos(th) * radius) + Y * (math.sin(th) * radius * ry) + d * (amp * math.sin(waves * th)))
    start = len(mb.v)
    K.path_tube(mb, pts, tube, style, wfn, segs=segs, hint=d, closed=True)
    if side:
        clamp_midline(mb, start, side)


def leg_centre(sx, z):
    """The leg axis at height z (thigh or shin by height), its direction down
    the leg, and the trouser radius base (leg_radius) there."""
    pts = rig.leg_path(sx, 0.55)
    k, a = pts[1], pts[2]
    p0, p1 = (pts[0], k) if z >= k.z else (k, a)
    c = p0.lerp(p1, (p0.z - z) / (p0.z - p1.z))
    return c, (p1 - p0).normalized(), P.leg_radius(rig.leg_s(c, sx))


def maple_outline(r, n=44):
    """A maple leaf (five pointed lobes, the middle one tallest), star-shaped
    about its centre: the radius at each angle is the largest of five
    pointed lobes, never less than the leaf's heart."""
    lobes = ((90.0, 1.0), (35.0, 0.86), (145.0, 0.86), (-15.0, 0.58), (195.0, 0.58))
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        best = 0.36
        for ang, ln in lobes:
            d = math.atan2(math.sin(a - math.radians(ang)), math.cos(a - math.radians(ang)))
            # each lobe is a pointed petal 50 degrees wide, with two small side points
            w = max(0.0, 1.0 - abs(d) / math.radians(26.0))
            side = 0.18 * max(0.0, 1.0 - abs(abs(d) - math.radians(15.0)) / math.radians(5.0))
            best = max(best, ln * (w ** 0.7 * 0.92 + side * w))
        out.append((math.cos(a) * best * r, (math.sin(a) * best + 0.12) * r))
    return out


def snowflake_outline(r, n=36):
    """A six-armed snowflake, star-shaped about its centre."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        arm = max(0.0, 1.0 - abs(math.sin(3 * a)) / 0.22)
        branch = 0.55 * max(0.0, 1.0 - abs(abs(math.sin(3 * a)) - 0.42) / 0.12)
        rr = 0.24 + 0.76 * max(arm, branch * 0.8)
        out.append((math.cos(a) * rr * r, math.sin(a) * rr * r))
    return out


def heart_path(w, h, n=26):
    """A heart outline (u, v), open at the top notch, for piped icing."""
    pts = []
    for k in range(n + 1):
        t = math.pi * 2 * k / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 32.0 * w, y / 32.0 * h))
    return pts


def _booties(mb, sx, sole, upper, collar, toe=0.19, heel=-0.084, rz=0.092, collar_top=0.125, upper_col=None):
    """Footed-suit booties (the bandit's paws): a sole, a round upper, an ankle
    collar the suit leg goes into."""
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, toe=toe, heel=heel, w_heel=0.062, w_toe=0.078, n=24), 0.0, 0.022, sole, fw, bevel=0.009)
    ellipsoid(mb, Vector((cx, 0.05, 0.026)), (0.076, 0.138, rz), upper, fw, segs=16, rings=11, cut_below=-0.18, colfn=upper_col)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), [(0.05, 0.072), (0.09, 0.076), (collar_top, 0.078)], collar, fw,
          segs=18, ry_scale=1.04)


# ================================================================== TURKEY TROT
TK_BROWN = S('#91603d', rough=0.95)
TK_BROWN_D = S('#714a30', rough=0.95)
TK_TAN = S('#f0d8ae', rough=0.95)
TK_RUST = S('#c9572c', rough=0.92)
TK_ORANGE = S('#ec9234', rough=0.92)
TK_GOLD = S('#f3c552', rough=0.9)
TK_CREAM = S('#fbefd6', rough=0.95)
TK_BEAK = S('#f2a43a', rough=0.4, mat=MAT_GLOSS)
TK_FOOT = S('#ef9a3c', rough=0.7)
TK_SOLE = S('#c86f24', rough=0.7, mat=MAT_RUBBER)
EYE_W = S('#fbfaf4', rough=0.3, mat=MAT_GLOSS)
EYE_D = S('#22232b', rough=0.25, mat=MAT_GLOSS)

# the tail fan, rigid on the hips: a root inside the suit above the seat and
# feathers (angle from upright, length) leaning back behind the body, so it
# reads from the follow camera and stays clear of the swinging arms
FAN_ROOT = Vector((0.0, -0.236, 0.575))
FAN_TILT = 26.0
FAN = [(-50.0, 0.25), (-33.0, 0.3), (-16.0, 0.335), (0.0, 0.35), (16.0, 0.335), (33.0, 0.3), (50.0, 0.25)]
FAN_W = 0.047          # a feather's half-width
FAN_START = 0.03       # where a feather starts along its direction from the root


def fan_capsules():
    """(base, tip, radius) of every feather (outfit_check.py)."""
    out = []
    for a, ln in FAN:
        d = _fan_dir(a, FAN_TILT)
        out.append((FAN_ROOT + d * FAN_START, FAN_ROOT + d * (FAN_START + ln), FAN_W))
    return out


def _eyes(mb, x, z, hw, r=(0.021, 0.025)):
    """Two glossy hood eyes on the hood shell at (+-x, z), with catch-lights."""
    hp = P.hood_project(HOOD_G, HOOD_OPEN)
    for sx in SIDES:
        e, en = P.hood_point(sx * x, z, HOOD_G, HOOD_OPEN, lift=0.002)
        Re = rot_align(en, UP)
        ellipsoid(mb, e, (r[0], r[1], 0.006), EYE_W, hw, segs=12, rings=6, rot=Re, deform=K.conform(e, Re, hp))
        ellipsoid(mb, e + en * 0.005, (r[0] * 0.58, r[1] * 0.58, 0.004), EYE_D, hw, segs=10, rings=5, rot=Re)
        ellipsoid(mb, e + en * 0.008 + Re @ Vector((-0.004 * sx, 0.006, 0)), (0.004, 0.004, 0.0015), EYE_W, hw, segs=6, rings=4, rot=Re)


def build_turkey():
    mb = MeshBuilder('turkey')
    g = 0.045
    belly = lambda z: 0.022 * math.sin(math.pi * smoothstep(0.46, 0.86, z))
    torso_lathe(mb, TK_BROWN, g, 0.46, 0.88, bottom_pole=True, extra=belly)
    # a cream-tan breast panel bent onto the suit, with three rows of scalloped feathers
    _, _, top = P.belly_panel(mb, TK_TAN, lambda z: g + belly(z), 0.675, (0.14, 0.165, 0.028))
    for row, z in enumerate((0.74, 0.69, 0.64)):
        cols = 3 if row % 2 == 0 else 2
        for c in range(cols):
            x = (c - (cols - 1) / 2) * 0.056
            on_patch = (lambda u, v, x=x, z=z: torso_at(x - u, z + v, g + belly(z + v) + top(x - u, z + v) - 0.001))
            decal(mb, _feather(0.042, 0.036, 9), on_patch, TK_GOLD if row == 1 else TK_CREAM, torso_w, thick=0.003)
    # sleeves with darker cuffs, wing feathers along the back of each arm
    sleeves(mb, TK_BROWN, 0.03, cuff_style=TK_BROWN_D, cuff_tube=0.02, lod=1)
    for sx in SIDES:
        prj = cyl_project(shoulder(sx), arm_dir(sx), lambda s: P.sleeve_r(s, 0.03))
        for k, (s, ang) in enumerate(((0.07, 5.0), (0.12, -22.0), (0.17, 8.0), (0.22, -18.0))):
            c, nn = arm_point(sx, s, ang - 40.0, P.sleeve_r(s, 0.03))
            decal(mb, _feather(0.046, 0.056, 9), place_planar(c, nn, -arm_dir(sx), prj), TK_RUST if k % 2 == 0 else TK_ORANGE,
                  lambda q, sx=sx: arm_w(q, sx), thick=0.004, lift=0.002)
    P.pant_legs(mb, TK_BROWN, 0.03, bottom_z=0.1, flat_end=False)
    # footed: orange booties with three toe ridges
    for sx in SIDES:
        fw = foot_w(sx)
        cx = rig.HIP_X * sx
        _booties(mb, sx, TK_SOLE, TK_FOOT, TK_FOOT)
        for dx, ang in ((-0.03, -14.0), (0.0, 0.0), (0.03, 14.0)):
            y = 0.13
            z = 0.026 + 0.092 * math.sqrt(max(0.0, 1.0 - ((y - 0.05) / 0.138) ** 2 - (dx / 0.076) ** 2)) - 0.003
            q = Vector((cx + dx, y, z))
            nn = Vector((dx / 0.076 ** 2, (y - 0.05) / 0.138 ** 2, (z - 0.026) / 0.092 ** 2)).normalized()
            ellipsoid(mb, q, (0.011, 0.036, 0.007), TK_SOLE, fw, segs=6, rings=4, rot=rot_align(nn, FWD) @ rot_z(ang))
    # the hood: tan rim, two eyes, a little beak, a tuft of three feathers
    P._hood(mb, TK_BROWN, TK_TAN, extra_grow=HOOD_G, opening=HOOD_OPEN)
    hw = rigid('head')
    _eyes(mb, 0.085, 1.425, hw)
    bp, bn = P.hood_point(0.0, 1.372, HOOD_G, HOOD_OPEN, lift=0.004)
    lathe(mb, bp, rot_align((bn + Vector((0, 0, -0.75))).normalized(), FWD), [(0.0, 0.0), (0.0, 0.024), (0.018, 0.018), (0.042, 0.0)],
          TK_BEAK, hw, segs=12, ry_scale=0.75)
    for i, a in enumerate((-22, 0, 22)):
        ellipsoid(mb, Vector((0.022 * (i - 1), -0.03, 1.565)), (0.013, 0.032, 0.062), TK_RUST if i == 1 else TK_BROWN_D, hw, segs=8,
                  rings=6, rot=rot_x(-18) @ Matrix.Rotation(math.radians(a), 3, 'Y'))
    # the tail fan: banded feathers (brown, rust, orange, a gold and cream tip),
    # rigid on the hips, with a round base over their roots
    hipw = lambda p: {'hips': 1.0}
    nrm = Vector((0.0, -math.cos(math.radians(FAN_TILT)), -math.sin(math.radians(FAN_TILT))))   # the fan's back face
    mid = (len(FAN) - 1) / 2.0
    for i, (a, ln) in enumerate(FAN):
        d = _fan_dir(a, FAN_TILT)
        # (outer feathers a little in front of the inner ones: no two share a plane)
        c = FAN_ROOT + d * (FAN_START + ln * 0.5) - nrm * (0.006 * abs(i - mid))
        hl = ln * 0.5
        alt = i % 2 == 0

        def band(p, lp, hl=hl, alt=alt):
            t = lp.z / hl
            if t > 0.78:
                return TK_CREAM
            if t > 0.5:
                return TK_GOLD
            if t > 0.05:
                return TK_RUST if alt else TK_ORANGE
            return TK_BROWN_D
        R = rot_align(d, nrm)
        ellipsoid(mb, c, (FAN_W, 0.011, hl), TK_BROWN, hipw, segs=10, rings=11, rot=R, colfn=band,
                  deform=lambda lp, hl=hl: Vector((lp.x * (1.0 - 0.35 * smoothstep(0.2, 1.0, -lp.z / hl)), lp.y, lp.z)))
    ellipsoid(mb, FAN_ROOT + Vector((0.0, -0.035, 0.05)), (0.06, 0.03, 0.055), TK_BROWN, hipw, segs=12, rings=8)
    return mb


# ================================================================== HARVEST FLANNEL
PLAID_BASE = (0.76, 0.27, 0.18)      # sRGB, a warm brick red
PLAID_MID = (0.47, 0.17, 0.13)
PLAID_DARK = (0.22, 0.11, 0.10)
PLAID_LINE = (0.93, 0.70, 0.30)      # a fine mustard thread
FL_RED = S('#c2452e', rough=0.92)
FL_DARK = S('#5a2a22', rough=0.92)
FL_BTN = S('#e9dcc0', rough=0.35, mat=MAT_GLOSS)
SCARF = S('#e8b23e', rough=0.97)
SCARF_D = S('#c98f24', rough=0.97)
SCARF_CREAM = S('#f6ecd6', rough=0.97)
LEAF_ORANGE = S('#e9792c', rough=0.8)
LEAF_GOLD = S('#f2b33b', rough=0.8)
DENIM = S('#3d5786', rough=0.9)
DENIM_D = S('#2f4570', rough=0.9)
DENIM_SEAM = S('#d8a24a', rough=0.8)
DB_RUBBER = S('#5b3d29', rough=0.45, mat=MAT_RUBBER)
DB_SOLE = S('#3a2a20', rough=0.7, mat=MAT_RUBBER)
DB_TAN = S('#c49056', rough=0.55, mat=MAT_RUBBER)
DB_LACE = S('#b03a2c', rough=0.8)
PLAID_CHECK = 0.05


def _cov(x, period, width, h):
    """Box-filtered coverage of a band [0, width) repeating every `period`
    over [x - h, x + h] (anti-aliased vertex colours)."""
    def F(t):
        n = math.floor(t / period)
        return n * width + min(width, t - n * period)
    return (F(x + h) - F(x - h)) / (2 * h)


def plaid_col(u, v, hu, hv):
    """Buffalo-check flannel at surface coordinates (u around, v up, m), with
    a fine mustard thread through the light squares."""
    cu = _cov(u, PLAID_CHECK * 2, PLAID_CHECK, hu)
    cv = _cov(v, PLAID_CHECK * 2, PLAID_CHECK, hv)
    lu = _cov(u + PLAID_CHECK * 1.5, PLAID_CHECK * 2, 0.004, hu) * (1 - cu)
    lv = _cov(v + PLAID_CHECK * 1.5, PLAID_CHECK * 2, 0.004, hv) * (1 - cv)
    both, one = cu * cv, cu * (1 - cv) + cv * (1 - cu)
    none = 1.0 - both - one
    line = min(1.0, (lu + lv) * 0.9) * none
    return tuple(PLAID_BASE[i] * (none - line) + PLAID_MID[i] * one + PLAID_DARK[i] * both + PLAID_LINE[i] * line for i in range(3))


def plaid_torso(mb, grow, z0, z1, segs=44, step=0.0145):
    """The shirt body with the check in its vertex colours (a denser lathe than
    torso_lathe so the squares read)."""
    prof = []
    z = z0
    while z < z1 - 1e-6:
        prof.append((z, max(torso_r(z), 0.06) + grow))
        z += step
    prof.append((z1, max(torso_r(z1), 0.06) + grow))
    prof += [(z1 + 0.004, 0.09), (z1 - 0.02, 0.082)]
    circ = 2 * math.pi * 0.2
    col = lambda p, z, th: plaid_col(th / (2 * math.pi) * circ, z, circ / segs * 0.5, step * 0.5)
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, FL_RED, torso_w, segs=segs, ry_scale=TORSO_RY, colfn=col)


def _duck_boot(mb, sx):
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, toe=0.19, heel=-0.082, w_heel=0.062, w_toe=0.077, n=22), 0.0, 0.03, DB_SOLE, fw, bevel=0.01)
    # rubber lower shell up to the welt line, tan leather above it
    col = lambda p, lp: DB_RUBBER if p.z < 0.074 + 0.02 * smoothstep(0.02, 0.15, p.y) else None
    ellipsoid(mb, Vector((cx, 0.05, 0.03)), (0.07, 0.136, 0.084), DB_TAN, fw, segs=18, rings=11, cut_below=-0.1, colfn=col)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3),
          [(0.04, 0.068), (0.075, 0.068), (0.1, 0.066), (0.15, 0.067), (0.19, 0.07), (0.198, 0.067), (0.188, 0.058)], DB_TAN, fw, segs=18,
          ry_scale=1.05, colfn=lambda p, z, th: DB_RUBBER if z < 0.078 else None)
    for i in range(4):
        y = 0.03 + i * 0.026
        z = 0.03 + 0.084 * math.sqrt(max(0.0, 1.0 - ((y - 0.05) / 0.136) ** 2)) - 0.002 + i * 0.016
        ellipsoid(mb, Vector((cx, y + 0.004 * i, z)), (0.03, 0.005, 0.005), DB_LACE, fw, segs=6, rings=4, rot=rot_x(-30))


def build_flannel():
    mb = MeshBuilder('flannel')
    g = 0.022
    plaid_torso(mb, g, 0.5, 0.872)
    _rib_band(mb, 0.49, 0.51, g + 0.001, FL_DARK, None, segs=36)
    # a pointed collar, placket and buttons
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.872, 0.086 + g * 0.5, 0.017, 7), FL_DARK, torso_w,
          segs=24, closed_profile=True, ry_scale=0.92)
    for sx in SIDES:
        p, n = P.on_torso(0.05 * sx, 0.836, g + 0.004)
        ellipsoid(mb, p, (0.028, 0.036, 0.006), FL_DARK, torso_w, segs=10, rings=6, rot=rot_align(n, UP) @ rot_z(38 * sx), power=2.4)
    pk = [P.on_torso(0.0, z, g + 0.004)[0] for z in [0.53 + 0.02 * i for i in range(16)]]
    sweep(mb, pk, [(0.004, 0.016)] * len(pk), FL_DARK, lambda p, sv, i: torso_w(p), segs=8, twist_hint=FWD)
    for z in (0.79, 0.71, 0.63, 0.55):
        p, n = P.on_torso(0.0, z, g + 0.009)
        ellipsoid(mb, p, (0.009, 0.009, 0.004), FL_BTN, torso_w, segs=8, rings=5, rot=rot_align(n, UP))
    # a chest pocket with a flap and an embroidered maple leaf
    decal(mb, K.rounded_rect(0.062, 0.062, 0.01), place_front(0.095, 0.72, g), FL_DARK, torso_w, thick=0.003)
    decal(mb, K.rounded_rect(0.068, 0.022, 0.008), place_front(0.095, 0.752, g + 0.003), FL_DARK, torso_w, thick=0.004)
    decal(mb, maple_outline(0.02), place_front(0.095, 0.712, g + 0.003), LEAF_ORANGE, torso_w, thick=0.0018)
    # back: a big embroidered maple leaf patch (the follow camera's view)
    decal(mb, K.circle_outline(0.088, 32), place_back(0.0, 0.69, g), FL_DARK, torso_w, thick=0.003)
    decal(mb, maple_outline(0.078), place_back(0.0, 0.686, g + 0.003), LEAF_ORANGE, torso_w, thick=0.002)
    decal(mb, maple_outline(0.044), place_back(0.0, 0.688, g + 0.005), LEAF_GOLD, torso_w, thick=0.0015)
    # plaid sleeves with dark button cuffs
    sl_g = 0.02
    sleeves(mb, FL_RED, sl_g, cuff_style=FL_DARK, cuff_tube=0.018, lod=1)
    # (re-colour the sleeve tubes just built with the check, by arm length and angle round the arm)
    for i in range(len(mb.v)):
        if tuple(mb.col[i][:3]) != tuple(FL_RED.col) or not any(k.startswith(('upper_arm', 'forearm')) for k in mb.w[i]):
            continue
        p = mb.v[i]
        sx = 1 if p.x > 0 else -1
        d = arm_dir(sx)
        x0 = (UP - d * UP.dot(d)).normalized()
        y0 = d.cross(x0)
        q = p - shoulder(sx)
        s = q.dot(d)
        rad = q - d * s
        ang = math.atan2(rad.dot(y0), rad.dot(x0))
        c = plaid_col(ang * 0.07, s, 0.0045, 0.006)
        mb.col[i] = (c[0], c[1], c[2], mb.col[i][3])
    # a chunky knit scarf: a wrap round the neck and one end down the chest, fringed
    rib = lambda r, th, z: r + 0.0022 * math.cos(th * 18)
    lathe(mb, Vector((0, TORSO_CY - 0.006, 0)), Matrix.Identity(3), torus_profile(0.888, 0.104, 0.03, 8, 0.85), SCARF, torso_w, segs=28,
          closed_profile=True, ry_scale=0.95, rfn=rib,
          colfn=lambda p, z, th: SCARF_CREAM if (0.018 < (th % 0.7) < 0.09) else None)
    prj = K.torso_project(lambda z: g + 0.006)
    c, n = prj(Vector((-0.058, 1.0, 0.765)))
    R = rot_align(n, UP) @ rot_z(-8)
    ellipsoid(mb, c, (0.04, 0.105, 0.012), SCARF, torso_w, segs=12, rings=14, rot=R, deform=K.conform(c, R, prj),
              colfn=lambda p, lp: SCARF_CREAM if (lp.y + 0.2) % 0.06 < 0.012 else (SCARF_D if abs(lp.x) > 0.034 else None))
    for k in range(5):
        u = -0.028 + 0.014 * k
        q0 = c + R @ Vector((u, -0.1, 0.004))
        q1 = q0 + R @ Vector((0.0, -0.028, 0.0))
        K.path_tube(mb, [q0, q1], 0.0045, SCARF_D, torso_w, segs=5, hint=n, cap='round')
    # denim jeans with turned-up cuffs over the duck boots
    pelvis(mb, DENIM, 0.014, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.17, 0.022, DENIM, segs=14)
        K.ring_on_leg(mb, sx, 0.178, 0.028, 0.013, DENIM_D, segs=14, n=5)
        stitch = [leg_point(sx, z, 0.0, 0.0235)[0] for z in (0.53, 0.42, 0.31, 0.22)]
        K.path_tube(mb, stitch, 0.0018, DENIM_SEAM, lambda q, sx=sx: leg_w(q, sx), segs=3, hint=Vector((sx, 0, 0)), cap='flat')
        _duck_boot(mb, sx)
    K.clamp_legs(mb)
    return mb


# ================================================================== REINDEER ONESIE
RD_BROWN = S('#a57349', rough=0.95)
RD_BROWN_D = S('#80583a', rough=0.95)
RD_CREAM = S('#f4e6cb', rough=0.95)
RD_ANTLER = S('#ddb98a', rough=0.9)
RD_ANTLER_D = S('#c49a68', rough=0.9)
RD_NOSE = S('#e2313b', rough=0.97)
RD_HOOF = S('#4e3626', rough=0.5, mat=MAT_RUBBER)
RD_PINK = S('#efc1b4', rough=0.95)
RD_RIBBON = S('#d6303a', rough=0.6)
BELL_GOLD = S('#f2c75e', rough=0.3, mat=MAT_METAL)
BELL_SLOT = S('#5a4520', rough=0.5, mat=MAT_RUBBER)

# the cream tail puff, rigid on the hips (outfit_check.py)
RD_TAIL = (Vector((0.0, -0.262, 0.585)), 0.042)
# antlers (one side, x > 0; mirrored): the beam and two tines, points in head space
ANTLER_BEAM = [(0.108, 0.0, 1.5), (0.13, -0.008, 1.535), (0.165, -0.02, 1.575), (0.2, -0.04, 1.612), (0.23, -0.06, 1.628)]
ANTLER_TINES = [[(0.146, -0.012, 1.548), (0.15, 0.022, 1.59), (0.148, 0.036, 1.622)],
                [(0.19, -0.034, 1.603), (0.198, -0.012, 1.645), (0.196, -0.004, 1.672)]]
ANTLER_R = (0.019, 0.012)


def antler_paths():
    """Every antler stroke (both sides) as (points, radius at start, at end)."""
    out = []
    for sx in SIDES:
        f = lambda pts, sx=sx: [Vector((x * sx, y, z)) for x, y, z in pts]
        out.append((f(ANTLER_BEAM), ANTLER_R[0], ANTLER_R[1]))
        for t in ANTLER_TINES:
            out.append((f(t), 0.013, 0.009))
    return out


def build_reindeer():
    mb = MeshBuilder('reindeer')
    g = 0.045
    belly = lambda z: 0.022 * math.sin(math.pi * smoothstep(0.46, 0.86, z))
    torso_lathe(mb, RD_BROWN, g, 0.46, 0.88, bottom_pole=True, extra=belly)
    P.belly_panel(mb, RD_CREAM, lambda z: g + belly(z), 0.675, (0.14, 0.165, 0.028))
    # a red ribbon bow and a gold bell on the chest
    pb, nb = torso_at(0.0, 0.81, g + belly(0.81) + 0.004)
    Rb = rot_align(nb, UP)
    for sx in SIDES:
        ellipsoid(mb, pb + Rb @ Vector((0.022 * sx, 0.004, 0.004)), (0.022, 0.013, 0.006), RD_RIBBON, torso_w, segs=10, rings=6,
                  rot=Rb @ rot_z(-12 * sx))
    ellipsoid(mb, pb + Rb @ Vector((0.0, 0.0, 0.006)), (0.008, 0.009, 0.006), RD_RIBBON, torso_w, segs=8, rings=5, rot=Rb)
    bc = pb + Rb @ Vector((0.0, -0.026, 0.012))
    ellipsoid(mb, bc, (0.017, 0.017, 0.016), BELL_GOLD, torso_w, segs=12, rings=8, rot=Rb)
    ellipsoid(mb, bc + Rb @ Vector((0.0, -0.004, 0.0135)), (0.011, 0.0022, 0.0035), BELL_SLOT, torso_w, segs=8, rings=4, rot=Rb)
    sleeves(mb, RD_BROWN, 0.03, cuff_style=RD_CREAM, cuff_tube=0.02, lod=1)
    P.pant_legs(mb, RD_BROWN, 0.03, bottom_z=0.1, flat_end=False)
    # footed: brown booties on dark hooves split down the front
    for sx in SIDES:
        fw = foot_w(sx)
        cx = rig.HIP_X * sx
        _booties(mb, sx, RD_HOOF, RD_BROWN, RD_BROWN, upper_col=lambda p, lp: RD_HOOF if (p.y > 0.06 and p.z < 0.075) else None)
        K.path_tube(mb, [Vector((cx, 0.2, 0.024)), Vector((cx, 0.198, 0.05)), Vector((cx, 0.185, 0.07))], 0.003, RD_BROWN_D, fw, segs=4,
                    hint=Vector((1, 0, 0)), cap='flat')
    # the tail puff
    # (skinned with the suit it sits on, so the two never part)
    K.bumpy(mb, RD_TAIL[0], (RD_TAIL[1],) * 3, RD_CREAM, torso_w, segs=12, rings=8, amp=0.12, freq=7)
    # the hood: cream rim, eyes, a red pompom nose, ears with pink insides, antlers
    P._hood(mb, RD_BROWN, RD_CREAM, extra_grow=HOOD_G, opening=HOOD_OPEN)
    hw = rigid('head')
    _eyes(mb, 0.088, 1.445, hw)
    npt, nn = P.hood_point(0.0, 1.385, HOOD_G, HOOD_OPEN, lift=0.016)
    K.bumpy(mb, npt, (0.031, 0.031, 0.029), RD_NOSE, hw, segs=14, rings=10, amp=0.07, freq=9)
    for sx in SIDES:
        ec = P._shell_point(-sx * (math.pi / 2 + 0.05), 1.33, HOOD_G)
        en = rig.head_normal(ec, HOOD_G)
        out = (en + Vector((0, -0.25, -0.15))).normalized()
        R = rot_align(out, UP)
        ellipsoid(mb, ec + out * 0.045, (0.03, 0.017, 0.062), RD_BROWN, hw, segs=12, rings=10, rot=R,
                  deform=lambda lp: Vector((lp.x * (1.0 - 0.5 * smoothstep(0.0, 1.0, lp.z / 0.062)), lp.y, lp.z)))
        ellipsoid(mb, ec + out * 0.05 + R @ Vector((0, 0.009, 0)), (0.019, 0.01, 0.045), RD_PINK, hw, segs=10, rings=8, rot=R,
                  deform=lambda lp: Vector((lp.x * (1.0 - 0.5 * smoothstep(0.0, 1.0, lp.z / 0.045)), lp.y, lp.z)))
    for pts, r0, r1 in antler_paths():
        path = _smooth_path(pts, 0.018)
        n = len(path)
        sweep(mb, path, [(lerp(r0, r1, i / max(1, n - 1)),) * 2 for i in range(n)], RD_ANTLER, lambda p, sv, i: hw(p), segs=7,
              cap_start=None, cap_end='round', twist_hint=FWD,
              colfn=lambda p, sv, a: RD_ANTLER_D if p.z < 1.49 else None)
    return mb


# ================================================================== GINGERBREAD BUDDY
GB_BROWN = S('#b9733a', rough=0.9)
GB_BROWN_D = S('#9a5c2c', rough=0.9)
ICING = S('#fbf8f1', rough=0.55)
GUM_RED = S('#e2393f', rough=0.5)
GUM_GREEN = S('#3fae4f', rough=0.5)
GUM_YELLOW = S('#f6c932', rough=0.5)
GB_BOW = S('#d22f3a', rough=0.6)


def _gumdrop(mb, p, n, style, wfn, r=0.017):
    lathe(mb, p - n * 0.002, rot_align(n, FWD), [(0.0, r), (0.004, r * 1.04), (0.011, r * 0.86), (0.017, r * 0.55), (0.0205, r * 0.2),
                                                 (0.021, 0.0)], style, wfn, segs=12, rfn=lambda rr, th, z: rr * (1.0 + 0.06 * math.cos(th * 6)))


def build_gingerbread():
    mb = MeshBuilder('gingerbread')
    g = 0.032
    puff = lambda z: 0.01 * math.sin(math.pi * smoothstep(0.5, 0.86, z))
    torso_lathe(mb, GB_BROWN, g, 0.47, 0.875, bottom_pole=True, extra=puff, top_open_r=0.1)
    # piped icing: a wavy line round the neck and round the hem
    for z, amp, waves in ((0.842, 0.008, 9), (0.53, 0.009, 11)):
        r = max(torso_r(z), 0.06) + g + puff(z)
        wavy_ring(mb, Vector((0, TORSO_CY, z)), UP, r + 0.002, amp, waves, 0.0055, ICING, torso_w, n=60, ry=TORSO_RY)
    # three gumdrop buttons
    for z, st in ((0.775, GUM_RED), (0.69, GUM_GREEN), (0.605, GUM_YELLOW)):
        p, n = torso_at(0.0, z, g + puff(z))
        _gumdrop(mb, p, n, st, torso_w)
    # a red bow at the collar
    pb, nb = torso_at(0.0, 0.858, g + puff(0.858) + 0.003)
    Rb = rot_align(nb, UP)
    for sx in SIDES:
        ellipsoid(mb, pb + Rb @ Vector((0.024 * sx, 0.0, 0.006)), (0.024, 0.015, 0.008), GB_BOW, torso_w, segs=10, rings=6,
                  rot=Rb @ rot_z(-10 * sx))
    ellipsoid(mb, pb + Rb @ Vector((0.0, 0.0, 0.009)), (0.009, 0.011, 0.008), GB_BOW, torso_w, segs=8, rings=5, rot=Rb)
    # back: a piped icing heart (the follow camera's view)
    K.surface_tube(mb, heart_path(0.15, 0.13), place_back(0.0, 0.69, g + puff(0.69)), 0.0055, ICING, torso_w, segs=6)
    # sleeves with iced cuffs and a wavy line above them
    sleeves(mb, GB_BROWN, 0.026, cuff_style=ICING, cuff_tube=0.016, lod=1)
    for sx in SIDES:
        s = 0.205
        d = arm_dir(sx)
        wavy_ring(mb, shoulder(sx) + d * s, d, P.sleeve_r(s, 0.026) + 0.002, 0.007, 7, 0.005, ICING, lambda q, sx=sx: arm_w(q, sx), n=36)
    P.pant_legs(mb, GB_BROWN, 0.03, bottom_z=0.1, flat_end=False)
    for sx in SIDES:
        for z in (0.2, 0.37):
            c, d, lr = leg_centre(sx, z)
            wavy_ring(mb, c, d, lr + 0.03 + 0.002, 0.007, 8, 0.005, ICING, lambda q, sx=sx: leg_w(q, sx), n=40, ry=0.96, side=sx)
        # footed: brown booties with an icing swirl on the toe
        fw = foot_w(sx)
        cx = rig.HIP_X * sx
        _booties(mb, sx, GB_BROWN_D, GB_BROWN, GB_BROWN)
        tp = Vector((cx, 0.15, 0.026 + 0.092 * math.sqrt(max(0.0, 1.0 - ((0.15 - 0.05) / 0.138) ** 2))))
        tn = Vector((0.0, (0.15 - 0.05) / 0.138 ** 2, (tp.z - 0.026) / 0.092 ** 2)).normalized()
        sw = []
        for k in range(22):
            a = 0.5 + 2.6 * math.pi * k / 21
            rr = 0.024 * (1.0 - 0.75 * k / 21)
            sw.append((math.cos(a) * rr, math.sin(a) * rr))
        K.surface_tube(mb, sw, place_planar(tp, tn, FWD), 0.004, ICING, fw, segs=5)
    return mb


# ================================================================== ELF HELPER
ELF_GREEN = S('#2f9b55', rough=0.9)
ELF_GREEN_D = S('#237a42', rough=0.9)
ELF_RED = S('#d7353e', rough=0.9)
ELF_WHITE = S('#f8f4ea', rough=0.9)
ELF_BELT = S('#3b2a22', rough=0.45, mat=MAT_RUBBER)
ELF_GOLD = S('#f2c75e', rough=0.3, mat=MAT_METAL)
ELF_SHOE = S('#26774a', rough=0.85)
ELF_SOLE = S('#4a3424', rough=0.6, mat=MAT_RUBBER)
HOLLY = S('#2d7a3c', rough=0.6)
BERRY = S('#d42a33', rough=0.35, mat=MAT_GLOSS)


def _petal(lp, ln):
    """A collar petal: a leaf pointed toward -y."""
    return Vector((lp.x * (1.0 - 0.7 * max(0.0, -lp.y / ln) ** 1.3), lp.y, lp.z))


def _elf_shoe(mb, sx):
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    slab(mb, _foot_outline(sx, toe=0.2, heel=-0.08, w_heel=0.058, w_toe=0.07, n=22), 0.0, 0.022, ELF_SOLE, fw, bevel=0.008)
    ellipsoid(mb, Vector((cx, 0.06, 0.024)), (0.068, 0.15, 0.078), ELF_SHOE, fw, segs=18, rings=11, cut_below=-0.2,
              deform=lambda lp: Vector((lp.x * (1.0 - 0.35 * smoothstep(0.3, 1.0, lp.y / 0.15)), lp.y, lp.z)))
    # a red cuff round the ankle
    # (narrow round the stocking: it comes out of the collar with no gap)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), [(0.05, 0.064), (0.085, 0.06), (0.115, 0.058)], ELF_SHOE, fw, segs=18,
          ry_scale=1.04)
    lathe(mb, Vector((cx, -0.006, 0)), Matrix.Identity(3), torus_profile(0.113, 0.06, 0.01, 6, 1.0), ELF_RED, fw, segs=18,
          closed_profile=True, ry_scale=1.04)
    # the toe rises into a curl with a little gold bell
    curl = [Vector((cx, 0.17, 0.05)), Vector((cx, 0.205, 0.06)), Vector((cx, 0.232, 0.08)), Vector((cx, 0.243, 0.105)),
            Vector((cx, 0.234, 0.126)), Vector((cx, 0.215, 0.128))]
    curl = _smooth_path(curl, 0.008)
    n = len(curl)
    # (the curl and bell are rigid on the foot: by height alone their tops took the shin's weights)
    footw = {('foot.L' if sx < 0 else 'foot.R'): 1.0}
    sweep(mb, curl, [(lerp(0.03, 0.009, (i / (n - 1)) ** 0.8),) * 2 for i in range(n)], ELF_SHOE, lambda p, sv, i: footw, segs=10,
          cap_start=None, cap_end='round', twist_hint=Vector((1, 0, 0)))
    ellipsoid(mb, Vector((cx, 0.204, 0.122)), (0.011, 0.011, 0.011), ELF_GOLD, lambda p: footw, segs=10, rings=7)


def build_elf():
    mb = MeshBuilder('elf')
    g = 0.024
    torso_lathe(mb, ELF_GREEN, g, 0.52, 0.872, top_open_r=0.092, colfn=lambda p, z, th: ELF_RED if z < 0.55 else None)
    _rib_band(mb, 0.5, 0.53, g + 0.002, ELF_WHITE, None, segs=40)
    # a pointed petal collar in red, all the way round
    lathe(mb, Vector((0, TORSO_CY - 0.004, 0)), Matrix.Identity(3), torus_profile(0.872, 0.094, 0.013, 8), ELF_RED, torso_w, segs=28,
          closed_profile=True, ry_scale=0.92)
    for th_deg in (60.0, 90.0, 120.0, 245.0, 270.0, 295.0):
        th = math.radians(th_deg)
        p, n = K.torso_ang(th, 0.828, g + 0.006)
        R = rot_align(n, UP)
        ellipsoid(mb, p, (0.028, 0.044, 0.006), ELF_RED, torso_w, segs=12, rings=8, rot=R, deform=lambda lp: _petal(lp, 0.044))
    # belt with a gold buckle, two gold buttons
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), torus_profile(0.567, torso_r(0.567) + g + 0.008, 0.017, 6, 0.75), ELF_BELT,
          torso_w, segs=32, closed_profile=True, ry_scale=TORSO_RY)
    bp, bn = torso_at(0.0, 0.567, g + 0.026)
    Rb = rot_align(bn, UP)
    ellipsoid(mb, bp, (0.03, 0.024, 0.006), ELF_GOLD, torso_w, segs=12, rings=6, rot=Rb, power=4.0)
    ellipsoid(mb, bp + bn * 0.004, (0.018, 0.012, 0.004), ELF_BELT, torso_w, segs=10, rings=5, rot=Rb, power=4.0)
    for z in (0.7, 0.635):
        p, n = torso_at(0.0, z, g + 0.004)
        ellipsoid(mb, p, (0.011, 0.011, 0.0045), ELF_GOLD, torso_w, segs=10, rings=6, rot=rot_align(n, UP))
    # sleeves with red cuffs over white
    sleeves(mb, ELF_GREEN, 0.022, cuff_style=ELF_RED, cuff_tube=0.02, lod=1)
    # green breeches under the tunic, red-and-white striped stockings
    pelvis(mb, ELF_GREEN_D, 0.012, 0.60)
    for sx in SIDES:
        # (a finer tube than leg_tube_stripes' so the stripes stay level)
        K.leg_tube(mb, sx, 0.55, 0.1, 0.012, ELF_WHITE, segs=12, step=0.01,
                   colfn=lambda p, sv, a: ELF_RED if int((p.z - 0.1) / 0.032) % 2 == 0 else None)
        _elf_shoe(mb, sx)
    K.clamp_legs(mb)
    return mb


ELF_CAP_GROW = 0.044
# the cone's spine (head space): from inside the crown up, leaning back and to the right, flopping at the tip
ELF_CONE = [(0.0, -0.02, 1.475), (0.0, -0.035, 1.54), (0.01, -0.07, 1.6), (0.035, -0.12, 1.655), (0.07, -0.17, 1.67),
            (0.1, -0.205, 1.645)]
ELF_BELL = (Vector((0.112, -0.218, 1.622)), 0.022)


def build_elf_cap():
    """A green elf cap: a shell over the crown with a red band, a cone that
    leans back and flops to one side with a gold bell at its tip, and a holly
    sprig on the band (worn with elf_helper and no hat)."""
    mb = MeshBuilder('acc_elf_cap')
    hw = rigid('head')
    grow = ELF_CAP_GROW
    shell(mb, grow, pumpkin_cap_edge, ELF_GREEN, hw, segs=44, rows=11, tuck=0.012)
    band, bn = [], []
    for k in range(44):
        ang = -math.pi + 2 * math.pi * k / 44
        q = P._shell_point(ang, pumpkin_cap_edge(ang) + 0.018, grow + 0.003)
        band.append(q)
        bn.append(rig.head_normal(q, grow))
    K.ribbon(mb, band, bn, 0.019, 0.007, ELF_RED, hw, segs=8, lift=0.003)
    # the cone
    path = _smooth_path([Vector(v) for v in ELF_CONE], 0.014)
    s = P._path_s(path)
    tot = s[-1]
    radii = []
    for v in s:
        t = v / tot
        r = lerp(0.092, 0.012, t ** 0.75)
        radii.append((r, r * 0.92))
    sweep(mb, path, radii, ELF_GREEN, lambda p, sv, i: hw(p), segs=16, cap_start=None, cap_end='round', twist_hint=FWD,
          colfn=lambda p, sv, a: ELF_GREEN_D if (int(a / (2 * math.pi) * 8 + 0.5) % 2 and sv > tot * 0.15) else None)
    ellipsoid(mb, ELF_BELL[0], (ELF_BELL[1],) * 3, ELF_GOLD, hw, segs=12, rings=9)
    ellipsoid(mb, ELF_BELL[0] + Vector((0.0, 0.0, -ELF_BELL[1] * 0.75)), (0.012, 0.012, 0.004), ELF_BELT, hw, segs=8, rings=4)
    # holly: two leaves and three berries on the band, over the left ear
    # (each leaf bent onto the band's curve, so its tips lie on it)
    lg = grow + 0.016
    hc = P._shell_point(2.2, pumpkin_cap_edge(2.2) + 0.022, lg)
    hn = rig.head_normal(hc, lg)
    for k, rot in enumerate((-35.0, 35.0)):
        R = rot_align(hn, UP) @ rot_z(rot + 90.0)
        lc = head_project(lg)(hc + R @ Vector((0.0, 0.022, 0.0)))[0]
        Rl = rot_align(rig.head_normal(lc, lg), R @ Vector((0, 1, 0)))
        bend = K.conform(lc, Rl, head_project(lg))
        ellipsoid(mb, lc, (0.012, 0.024, 0.004), HOLLY, hw, segs=10, rings=6, rot=Rl,
                  deform=lambda lp, bend=bend: bend(Vector((lp.x * (1.0 + 0.25 * math.cos(lp.y / 0.024 * 7.0)), lp.y, lp.z))))
    for k in range(3):
        a = 2 * math.pi * k / 3
        R = rot_align(hn, UP)
        ellipsoid(mb, hc + hn * 0.006 + R @ Vector((math.cos(a) * 0.008, math.sin(a) * 0.008 - 0.004, 0.0)), (0.0065,) * 3, BERRY, hw,
                  segs=8, rings=6)
    return mb


# ================================================================== SNOW DAY
SD_YELLOW = S('#f2b632', rough=0.6)
SD_SEAM = S('#d79a1f', rough=0.7)
SD_FUR = S('#efe4d2', rough=1.0)
SD_FUR_D = S('#d9cab2', rough=1.0)
SD_NAVY = S('#2c3a6e', rough=0.75)
SD_NAVY_D = S('#22305c', rough=0.8)
SD_MITT = S('#d93a40', rough=0.97)
SD_MITT_CUFF = S('#f3ecdf', rough=0.97)
SD_ZIP = S('#cfd4dc', rough=0.3, mat=MAT_METAL)
SD_BOOT = S('#4a5263', rough=0.5, mat=MAT_RUBBER)
SD_BOOT_SOLE = S('#272b33', rough=0.7, mat=MAT_RUBBER)
SD_BOOT_UP = S('#5d6b8c', rough=0.75)
SD_FLAKE = S('#f8fbff', rough=0.6)


def _snow_boot(mb, sx):
    fw = foot_w(sx)
    cx = rig.HIP_X * sx
    outline = _foot_outline(sx, toe=0.195, heel=-0.088, w_heel=0.068, w_toe=0.082, n=22)
    slab(mb, outline, 0.0, 0.04, SD_BOOT_SOLE, fw, bevel=0.012)
    ellipsoid(mb, Vector((cx, 0.052, 0.04)), (0.078, 0.14, 0.088), SD_BOOT, fw, segs=16, rings=10, cut_below=-0.25,
              colfn=lambda p, lp: SD_BOOT_UP if p.z > 0.09 else None)
    lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3), [(0.05, 0.082), (0.1, 0.088), (0.15, 0.09), (0.18, 0.092), (0.186, 0.088)],
          SD_BOOT_UP, fw, segs=18, ry_scale=1.04)
    # a faux-fur cuff on the shaft's top
    lathe(mb, Vector((cx, -0.004, 0)), Matrix.Identity(3), torus_profile(0.186, 0.092, 0.019, 6, 0.9), SD_FUR, fw, segs=16,
          closed_profile=True, ry_scale=1.04, rfn=lambda r, th, z: r + 0.003 * math.sin(th * 7) * math.cos(z * 300))
    # toggle laces up the front
    for i in range(3):
        y = 0.04 + i * 0.03
        z = 0.04 + 0.088 * math.sqrt(max(0.0, 1.0 - ((y - 0.052) / 0.14) ** 2)) - 0.002 + i * 0.012
        ellipsoid(mb, Vector((cx, y + 0.004 * i, z)), (0.03, 0.005, 0.005), SD_NAVY_D, fw, segs=6, rings=4, rot=rot_x(-30))


def build_snowday():
    mb = MeshBuilder('snowday')
    g = 0.04
    # the quilted parka: horizontal baffles, darker seams between them
    prof = [(0.478, torso_r(0.478) + 0.014)] + _quilted_profile(0.49, 0.872, g, 0.075, 0.009, step=0.019, z_quilt=(0.5, 0.85))
    prof += [(0.876, 0.11), (0.86, 0.1)]
    seam = lambda p, z, th: SD_SEAM if (0.5 <= z <= 0.85 and math.sin(math.pi * (z - 0.5) / 0.075) ** 2 < 0.06) else None
    lathe(mb, Vector((0, TORSO_CY, 0)), Matrix.Identity(3), prof, SD_YELLOW, torso_w, segs=28, ry_scale=TORSO_RY, colfn=seam)
    _rib_band(mb, 0.47, 0.5, g - 0.004, SD_NAVY, None, segs=36)
    # zip front with a pull, a flap pocket either side
    zp = place_front(0.0, 0.0, g)
    K.surface_tube(mb, [(0.0, z) for z in [0.515 + 0.025 * i for i in range(14)]], zp, 0.0055, SD_NAVY_D, torso_w, flat=0.45, segs=6)
    p, n = torso_at(0.0, 0.83, g + 0.01)
    ellipsoid(mb, p + Vector((0, 0, -0.012)), (0.008, 0.004, 0.017), SD_ZIP, torso_w, segs=8, rings=6, rot=rot_align(n, UP))
    for sx in SIDES:
        decal(mb, K.rounded_rect(0.07, 0.024, 0.008), place_front(0.105 * sx, 0.6, g + 0.004), SD_SEAM, torso_w, thick=0.004)
    # a snowflake on the back (the follow camera's view) and on the left sleeve
    decal(mb, K.circle_outline(0.066, 28), place_back(0.0, 0.72, g + 0.006), SD_NAVY, torso_w, thick=0.003)
    decal(mb, snowflake_outline(0.055), place_back(0.0, 0.72, g + 0.009), SD_FLAKE, torso_w, thick=0.002)
    # puffy quilted sleeves, knit mittens with cream cuffs
    sleeves(mb, SD_YELLOW, 0.032, cuff_style=SD_NAVY, cuff_tube=0.018, lod=1)
    for sx in SIDES:
        for s in (0.1, 0.2):
            K.ring_on_arm(mb, sx, s, 0.032, 0.0045, SD_SEAM, segs=12, squash=1.0, n=4)
    prj = sleeve_project(-1, 0.032)
    c, nn = arm_point(-1, 0.07, 30.0, P.arm_radius(0.07) + 0.032)
    decal(mb, snowflake_outline(0.026), place_planar(c, nn, arm_dir(-1), prj), SD_FLAKE, lambda q: arm_w(q, -1), thick=0.0025, lift=0.002)
    gloves(mb, SD_MITT, SD_MITT_CUFF, g=0.006, cuff=(-0.055, 0.01), cuff_r=(0.056, 0.05), roll=0.008, segs=10, rings=7)
    # the hood up with a faux-fur rim of tufts
    # (a lighter shell than the default: the fur rim hides its edge)
    P._hood(mb, SD_YELLOW, SD_FUR, extra_grow=HOOD_G, opening=HOOD_OPEN, segs=28, rings=20)
    hw = rigid('head')
    n_p = 13
    for i in range(n_p):
        a = 2 * math.pi * (i + 0.5) / n_p
        x = (HOOD_OPEN[0] + 0.008) * math.cos(a)
        z = HOOD_OPEN[2] + (HOOD_OPEN[1] + 0.008) * math.sin(a)
        q, nq = P.hood_point(x, z, HOOD_G, HOOD_OPEN)
        out = Vector((math.cos(a) * 0.012, 0.0, math.sin(a) * 0.012))
        r = 0.029 if i % 2 == 0 else 0.025
        K.bumpy(mb, q + out, (r, r, r * 0.7), SD_FUR if i % 3 else SD_FUR_D, hw, segs=7, rings=5, amp=0.14, freq=8, seed=i + 1,
                rot=rot_align(nq, UP))
    # a quilted seam over the hood's crown
    pts, nrm = [], []
    for j in range(17):
        th = lerp(-1.25, 1.35, j / 16)
        z = HEAD_C.z + (HEAD_R[2] + HOOD_G) * math.cos(th)
        ang = math.pi if th < 0 else 0.0
        q = P._shell_point(ang, z, HOOD_G) if abs(th) > 0.02 else Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z + HEAD_R[2] + HOOD_G))
        pts.append(q)
        nrm.append(rig.head_normal(q, HOOD_G))
    K.ribbon(mb, pts, nrm, 0.004, 0.002, SD_SEAM, hw, closed=False, segs=4)
    # puffy snow pants into the boots
    pelvis(mb, SD_NAVY, 0.02, 0.60)
    for sx in SIDES:
        K.leg_tube(mb, sx, 0.55, 0.17, 0.034, SD_NAVY, segs=14)
        _snow_boot(mb, sx)
    K.clamp_legs(mb)
    return mb


B18_PARTS = [build_turkey, build_flannel, build_reindeer, build_gingerbread, build_elf, build_elf_cap, build_snowday]
ALL = B18_PARTS
