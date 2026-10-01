"""Skeleton layout, proportions and skin-weight helpers for the Trifecta runner.

Blender coordinates: X = character's right, Y = forward, Z = up, metres.
The armature is exported to glTF (Y-up), where the character faces -Z: the
game's forward convention (TC/MatchSim yaw 0 looks down -Z).
"""
import math
from mathutils import Vector
from geo import smoothstep

# ---------------------------------------------------------------- proportions
HIP_Z = 0.525          # hip joint height
HIP_X = 0.105
KNEE = (0.0, 0.012, 0.305)   # x filled per side
ANKLE_Z = 0.085
TOE = (0.0, 0.12, 0.025)
SHOULDER = Vector((0.17, 0.0, 0.84))     # right side; left mirrors x
ARM_DOWN_DEG = 40.0                      # A-pose: arm 40 degrees from vertical
UPPER_LEN = 0.17
FORE_LEN = 0.15
HAND_LEN = 0.09
HEAD_C = Vector((0.0, 0.015, 1.185))
HEAD_R = (0.31, 0.285, 0.30)
HEAD_P = 2.4

# torso radius profile (z, r); cross-section is elliptical (y radius * TORSO_RY)
TORSO = [(0.455, 0.0), (0.462, 0.07), (0.475, 0.13), (0.50, 0.172), (0.53, 0.196), (0.57, 0.212),
         (0.62, 0.22), (0.67, 0.216), (0.72, 0.205), (0.77, 0.188), (0.81, 0.168), (0.84, 0.145),
         (0.865, 0.11), (0.885, 0.072), (0.93, 0.065), (0.96, 0.0)]
TORSO_RY = 0.84
TORSO_CY = 0.005


def torso_r(z):
    if z <= TORSO[0][0]:
        return 0.0
    for (z0, r0), (z1, r1) in zip(TORSO, TORSO[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return r0 + (r1 - r0) * t
    return 0.0


def torso_front_y(x, z, grow=0.0):
    r = torso_r(z) + grow
    if r <= abs(x):
        return TORSO_CY
    return TORSO_CY + r * TORSO_RY * math.sqrt(1.0 - (x / r) ** 2)


def arm_dir(side):
    """side: -1 left, +1 right."""
    a = math.radians(ARM_DOWN_DEG)
    return Vector((side * math.sin(a), 0.0, -math.cos(a)))


def shoulder(side):
    return Vector((SHOULDER.x * side, SHOULDER.y, SHOULDER.z))


def elbow(side):
    return shoulder(side) + arm_dir(side) * UPPER_LEN


def wrist(side):
    return elbow(side) + arm_dir(side) * FORE_LEN


def hip(side):
    return Vector((HIP_X * side, 0.0, HIP_Z))


def knee(side):
    return Vector((HIP_X * side, KNEE[1], KNEE[2]))


def ankle(side):
    return Vector((HIP_X * side, 0.0, ANKLE_Z))


# Head shape (V3): a superellipsoid whose cross-section is scaled with height
# so the cheeks and jaw are fuller and the temples a little narrower (the
# friendly baby-face proportions of the app icon).  Every head-fitted part
# (face features, ears, hair, hoods, caps) uses these functions, so they all
# follow the same surface.
def head_scale(zn):
    """(sx, sy) cross-section scale at normalised head height zn in [-1, 1]."""
    cheek = math.exp(-((zn + 0.30) / 0.42) ** 2)
    top = max(0.0, min(1.0, (zn - 0.25) / 0.75))
    top = top * top * (3 - 2 * top)
    return 1.0 + 0.075 * cheek - 0.045 * top, 1.0 + 0.035 * cheek - 0.02 * top


def head_deform(grow=0.0):
    """Local-space deformation for ellipsoid() shells centred on HEAD_C."""
    rz = HEAD_R[2] + grow

    def f(lp):
        sx, sy = head_scale(max(-1.0, min(1.0, lp.z / rz)))
        return Vector((lp.x * sx, lp.y * sy, lp.z))
    return f


def _head_F(p, grow):
    rx, ry, rz = HEAD_R[0] + grow, HEAD_R[1] + grow, HEAD_R[2] + grow
    d = p - HEAD_C
    zn = d.z / rz
    sx, sy = head_scale(max(-1.0, min(1.0, zn)))
    return abs(d.x / (rx * sx)) ** HEAD_P + abs(d.y / (ry * sy)) ** HEAD_P + abs(zn) ** HEAD_P


def head_front_y(x, z, grow=0.0):
    rx, ry, rz = HEAD_R[0] + grow, HEAD_R[1] + grow, HEAD_R[2] + grow
    zn = (z - HEAD_C.z) / rz
    sx, sy = head_scale(max(-1.0, min(1.0, zn)))
    t = 1.0 - abs(x / (rx * sx)) ** HEAD_P - abs(zn) ** HEAD_P
    return HEAD_C.y + ry * sy * max(t, 0.0) ** (1.0 / HEAD_P)


def head_side_x(z, grow=0.0, y=None):
    """|x| of the head surface at height z (on the y = HEAD_C.y plane by default)."""
    rx, ry, rz = HEAD_R[0] + grow, HEAD_R[1] + grow, HEAD_R[2] + grow
    zn = (z - HEAD_C.z) / rz
    sx, sy = head_scale(max(-1.0, min(1.0, zn)))
    yy = 0.0 if y is None else (y - HEAD_C.y) / (ry * sy)
    t = 1.0 - abs(zn) ** HEAD_P - abs(yy) ** HEAD_P
    return rx * sx * max(t, 0.0) ** (1.0 / HEAD_P)


def head_point(x, z, grow=0.0):
    return Vector((x, head_front_y(x, z, grow), z))


def head_normal(p, grow=0.0):
    e = 1e-4
    g = Vector((_head_F(p + Vector((e, 0, 0)), grow) - _head_F(p - Vector((e, 0, 0)), grow),
                _head_F(p + Vector((0, e, 0)), grow) - _head_F(p - Vector((0, e, 0)), grow),
                _head_F(p + Vector((0, 0, e)), grow) - _head_F(p - Vector((0, 0, e)), grow)))
    return g.normalized()


# ---------------------------------------------------------------- bones
def bone_table():
    """name -> (head, tail, parent).  Order matters (parents first)."""
    B = {}
    B['root'] = (Vector((0, 0, 0)), Vector((0, 0.15, 0)), None)
    B['hips'] = (Vector((0, 0, HIP_Z)), Vector((0, 0, 0.62)), 'root')
    B['spine'] = (Vector((0, 0, 0.62)), Vector((0, 0, 0.73)), 'hips')
    B['chest'] = (Vector((0, 0, 0.73)), Vector((0, 0, 0.86)), 'spine')
    B['neck'] = (Vector((0, 0, 0.86)), Vector((0, 0, 0.93)), 'chest')
    B['head'] = (Vector((0, 0, 0.93)), Vector((0, 0, 1.30)), 'neck')
    # nightcap chain (follows the cap's droop to the right side, see parts.build_nightcap)
    B['hat1'] = (Vector((0.012, -0.025, 1.48)), Vector((0.08, -0.058, 1.565)), 'head')
    B['hat2'] = (Vector((0.08, -0.058, 1.565)), Vector((0.20, -0.09, 1.59)), 'hat1')
    B['hat3'] = (Vector((0.20, -0.09, 1.59)), Vector((0.30, -0.09, 1.49)), 'hat2')
    for side, sfx in ((-1, '.L'), (1, '.R')):
        B['shoulder' + sfx] = (Vector((0.05 * side, 0, 0.835)), shoulder(side), 'chest')
        B['upper_arm' + sfx] = (shoulder(side), elbow(side), 'shoulder' + sfx)
        B['forearm' + sfx] = (elbow(side), wrist(side), 'upper_arm' + sfx)
        B['hand' + sfx] = (wrist(side), wrist(side) + arm_dir(side) * HAND_LEN, 'forearm' + sfx)
        B['thigh' + sfx] = (hip(side), knee(side), 'hips')
        B['shin' + sfx] = (knee(side), ankle(side), 'thigh' + sfx)
        B['foot' + sfx] = (ankle(side), Vector((HIP_X * side, TOE[1], TOE[2])), 'shin' + sfx)
    return B


# ---------------------------------------------------------------- weights
def seg_weights(s, segs, blend=0.03):
    """segs: [(bone, s_end), ..., (bone, None)] along a path parameter s."""
    for i in range(len(segs) - 1):
        b, e = segs[i]
        nb = segs[i + 1][0]
        if s < e - blend:
            return {b: 1.0}
        if s <= e + blend:
            t = smoothstep(e - blend, e + blend, s)
            return {b: 1.0 - t, nb: t}
    return {segs[-1][0]: 1.0}


def mix(*pairs):
    """mix((w_dict, factor), ...) -> combined normalised weights."""
    out = {}
    for w, f in pairs:
        for k, v in w.items():
            out[k] = out.get(k, 0.0) + v * f
    tot = sum(out.values())
    return {k: v / tot for k, v in out.items() if v > 1e-4}


def torso_w(p):
    w = seg_weights(p.z, [('hips', 0.60), ('spine', 0.725), ('chest', 0.875), ('neck', None)], 0.04)
    side = '.L' if p.x < 0 else '.R'
    # lower torso follows the thighs a little so the crotch deforms with strides
    f = smoothstep(0.57, 0.47, p.z) * smoothstep(0.02, 0.11, abs(p.x)) * 0.55
    # shoulder region follows the clavicle
    g = smoothstep(0.11, 0.19, abs(p.x)) * smoothstep(0.74, 0.83, p.z) * 0.5
    parts = [(w, 1.0 - f - g)]
    if f > 0:
        parts.append(({'thigh' + side: 1.0}, f))
    if g > 0:
        parts.append(({'shoulder' + side: 1.0}, g))
    return mix(*parts)


def skirt_w(p):
    """Robe skirt below the waist: hips blended toward the thigh on that side."""
    base = torso_w(p)
    f = smoothstep(0.52, 0.30, p.z) * 0.75
    if f <= 0:
        return base
    lx = smoothstep(-0.12, 0.12, p.x)  # 0 = left, 1 = right
    return mix((base, 1.0 - f), ({'thigh.L': 1.0 - lx, 'thigh.R': lx}, f))


def arm_s(p, side):
    """Parameter along the arm (metres from the shoulder joint)."""
    return (p - shoulder(side)).dot(arm_dir(side))


def arm_w(p, side):
    sfx = '.L' if side < 0 else '.R'
    s = arm_s(p, side)
    return seg_weights(s, [('shoulder' + sfx, 0.0), ('upper_arm' + sfx, UPPER_LEN), ('forearm' + sfx, UPPER_LEN + FORE_LEN),
                           ('hand' + sfx, None)], 0.035)


def leg_path(side, top_z=0.545):
    h = Vector((HIP_X * side, 0.0, top_z))
    return [h, knee(side), ankle(side)]


def leg_s(p, side):
    """Parameter along the leg polyline (metres from the hip joint)."""
    k = knee(side)
    hj = hip(side)
    l1 = (k - hj).length
    d1 = (k - hj).normalized()
    s1 = (p - hj).dot(d1)
    if s1 <= l1:
        return s1
    a = ankle(side)
    d2 = (a - k).normalized()
    return l1 + (p - k).dot(d2)


def leg_w(p, side):
    sfx = '.L' if side < 0 else '.R'
    s = leg_s(p, side)
    kl = (knee(side) - hip(side)).length
    al = kl + (ankle(side) - knee(side)).length
    w = seg_weights(s, [('thigh' + sfx, kl), ('shin' + sfx, al), ('foot' + sfx, None)], 0.04)
    # top of the thigh blends into the hips so the pelvis does not crease
    f = smoothstep(0.05, -0.02, s) * 0.5
    if f > 0:
        w = mix((w, 1.0 - f), ({'hips': 1.0}, f))
    return w


def rigid(bone):
    return lambda *a, **k: {bone: 1.0}
