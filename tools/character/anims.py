"""Animation clips for the Trifecta runner, authored as code.

Poses are written as FK rotation deltas in *armature axes* (Blender: X right,
Y forward, Z up), applied on top of the rest pose and carried down the chain:
    +X on a limb that hangs down  = swing it forward
    +X on an upward bone (spine)  = lean back   (so forward lean is negative)
    +Y on the left arm            = raise it sideways (right arm: -Y; sym() mirrors
                                    .L values onto .R, so write raises as +Y on .L)
    +Z                            = turn left
Locomotion uses analytic two-bone leg IK so planted feet move backward at
exactly the clip's design speed (no foot sliding when played at
speed / design_speed).  Clips are baked to keys every frame at FPS.

Every locomotion cycle (walk/run/sprint) is exactly 1.0 s long and starts
with the left foot at mid-stance, so CharacterView can blend them in phase
and set the playback rate from the measured ground speed.
"""
import math
from mathutils import Vector, Matrix, Quaternion
from geo import smoothstep, lerp
import rig

FPS = 30

# design speeds: metres per 1.0 s cycle at playback rate 1 (read by the game)
#
# V3 cadence.  The character's legs are 0.44 m (hip joint 0.525 m, ankle
# 0.085 m), so stride lengths are scaled from human gait by leg length:
#   walk    0.70 m/cycle -> 1.9 cycles/s at 1.3 m/s  (3.7 steps/s)
#   run     2.20 m/cycle -> 2.3 cycles/s at 5.0 m/s  (4.5 steps/s, short flight)
#   sprint  2.75 m/cycle -> 2.5 cycles/s at 7.0 m/s  (5.1 steps/s, longer flight)
# (V2 ran at 1.7 m/cycle = 2.9 cycles/s at 5 m/s, which read as scurrying.)
# speed * duty is the planted-foot sweep; the hip drop at the stance extremes
# keeps it reachable with a slightly bent leg (checked by reach_report()).
LOCO = {
    # name: speed = metres per 1.0 s cycle (so playback rate = ground speed / speed),
    #       duty = stance fraction per foot, lift (m), hip drop (m), lean (deg, spine),
    #       arm swing (deg), elbow (deg), bob (m), gait ('walk' = vaulting, highest
    #       at mid-stance; 'run' = bouncing, lowest at mid-stance)
    'walk': dict(speed=0.70, duty=0.58, lift=0.065, drop=0.04, lean=-4.0, arm=20.0, elbow=26.0, bob=0.012, gait='walk'),
    'run': dict(speed=2.20, duty=0.20, lift=0.15, drop=0.06, lean=-11.0, arm=44.0, elbow=86.0, bob=0.024, gait='run'),
    'sprint': dict(speed=2.75, duty=0.165, lift=0.19, drop=0.07, lean=-18.0, arm=58.0, elbow=96.0, bob=0.026, gait='run'),
}
# foot-strike phases (left, right) of each cycle, for footstep timing in the game
def strike_phases(name):
    d = LOCO[name]['duty']
    return ((1.0 - d * 0.5) % 1.0, (0.5 - d * 0.5) % 1.0)


D2R = math.pi / 180.0


def qe(rx=0.0, ry=0.0, rz=0.0):
    """Quaternion from armature-axis Euler degrees (applied X, then Y, then Z)."""
    q = Quaternion((1, 0, 0), rx * D2R)
    q = Quaternion((0, 1, 0), ry * D2R) @ q
    q = Quaternion((0, 0, 1), rz * D2R) @ q
    return q


def mirror(pose):
    """Swap .L/.R and mirror rotations/locations across the YZ plane."""
    out = {}
    for b, v in pose.items():
        nb = b.replace('.L', '.#').replace('.R', '.L').replace('.#', '.R')
        nv = dict(v)
        if 'rot' in v:
            rx, ry, rz = v['rot']
            nv['rot'] = (rx, -ry, -rz)
        if 'loc' in v:
            x, y, z = v['loc']
            nv['loc'] = (-x, y, z)
        out[nb] = nv
    return out


def sym(pose_l):
    """Pose for .L bones (+ centre bones) -> mirrored onto .R too."""
    out = dict(pose_l)
    m = mirror({k: v for k, v in pose_l.items() if k.endswith('.L')})
    out.update(m)
    return out


def blend_pose(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va = a.get(k, {})
        vb = b.get(k, {})
        nv = {}
        ra = va.get('rot', (0, 0, 0))
        rb = vb.get('rot', (0, 0, 0))
        nv['rot'] = tuple(lerp(x, y, t) for x, y in zip(ra, rb))
        if 'loc' in va or 'loc' in vb:
            la = va.get('loc', (0, 0, 0))
            lb = vb.get('loc', (0, 0, 0))
            nv['loc'] = tuple(lerp(x, y, t) for x, y in zip(la, lb))
        if 'ik' in va and 'ik' in vb:
            # V5: interpolate IK targets (V4 switched them at t = 0.5, so a
            # blend between two IK stances jumped the feet ~20 cm mid-clip)
            (ta, xa), (tb, xb) = va['ik'], vb['ik']
            if isinstance(xa, (int, float)):
                nv['ik'] = (Vector(ta).lerp(Vector(tb), t), lerp(xa, xb, t))
            else:
                nv['ik'] = (Vector(ta).lerp(Vector(tb), t), Vector(xa).lerp(Vector(xb), t))
        elif 'ik' in va or 'ik' in vb:
            nv['ik'] = vb.get('ik', va.get('ik')) if t > 0.5 else va.get('ik', vb.get('ik'))
        out[k] = nv
    return out


def add_pose(a, b):
    out = {k: dict(v) for k, v in a.items()}
    for k, v in b.items():
        o = out.setdefault(k, {})
        if 'rot' in v:
            r0 = o.get('rot', (0, 0, 0))
            o['rot'] = tuple(x + y for x, y in zip(r0, v['rot']))
        if 'loc' in v:
            l0 = o.get('loc', (0, 0, 0))
            o['loc'] = tuple(x + y for x, y in zip(l0, v['loc']))
        if 'ik' in v:
            o['ik'] = v['ik']
    return out


def keyed(keys, t, loop_len=None, ease=True):
    """keys: [(time, pose), ...] -> pose at t (smooth interpolation)."""
    if loop_len is not None:
        t = t % loop_len
        keys = keys + [(loop_len, keys[0][1])]
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / max(1e-6, t1 - t0)
            if ease:
                u = u * u * (3 - 2 * u)
            return blend_pose(p0, p1, u)
    return keys[-1][1]


# ------------------------------------------------------------------ evaluator
class Rig:
    def __init__(self, arm_obj):
        self.bones = {}
        self.order = []
        for b in arm_obj.data.bones:
            self.bones[b.name] = b
        # parents first
        def visit(b):
            self.order.append(b.name)
            for c in b.children:
                visit(c)
        for b in arm_obj.data.bones:
            if b.parent is None:
                visit(b)
        self.rest = {n: self.bones[n].matrix_local.copy() for n in self.order}

    def solve(self, pose):
        """pose -> {bone: (local_quat, local_loc)} and armature-space matrices."""
        P = {}
        L = {}
        for n in self.order:
            b = self.bones[n]
            rest = self.rest[n]
            spec = pose.get(n, {})
            if b.parent is None:
                O = rest.copy()
            else:
                pn = b.parent.name
                O = P[pn] @ self.rest[pn].inverted() @ rest
            O3 = O.to_3x3().normalized()
            if 'ik' in spec:
                # handled by the caller (legs); identity here, patched later
                q_local = Quaternion()
            else:
                W = qe(*spec.get('rot', (0, 0, 0))).to_matrix()
                q_local = (O3.inverted() @ W @ O3).to_quaternion()
            loc_local = Vector((0, 0, 0))
            if 'loc' in spec:
                loc_local = O3.inverted() @ Vector(spec['loc'])
            Lm = Matrix.Translation(loc_local) @ q_local.to_matrix().to_4x4()
            P[n] = O @ Lm
            L[n] = [q_local, loc_local]
        return P, L

    def leg_ik(self, P, L, side, ankle_target, foot_pitch_deg=0.0, pole=Vector((0, 1, 0))):
        sfx = '.L' if side < 0 else '.R'
        th, sh, ft = 'thigh' + sfx, 'shin' + sfx, 'foot' + sfx
        hips = self.bones[th].parent.name
        O_th = P[hips] @ self.rest[hips].inverted() @ self.rest[th]
        H = O_th.translation.copy()
        a = (self.bones[th].tail_local - self.bones[th].head_local).length
        b = (self.bones[sh].tail_local - self.bones[sh].head_local).length
        A = Vector(ankle_target)
        d_vec = A - H
        d = d_vec.length
        d = max(abs(a - b) + 1e-4, min(a + b - 1e-4, d))
        u = d_vec.normalized()
        A = H + u * d
        cos_a = (a * a + d * d - b * b) / (2 * a * d)
        sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
        pv = pole - u * pole.dot(u)
        if pv.length < 1e-5:
            pv = Vector((0, 1, 0))
        pv.normalize()
        K = H + u * (a * cos_a) + pv * (a * sin_a)
        # thigh
        O3 = O_th.to_3x3().normalized()
        d0 = O3.col[1].normalized()
        W = d0.rotation_difference((K - H).normalized()).to_matrix()
        q = (O3.inverted() @ W @ O3).to_quaternion()
        L[th] = [q, Vector((0, 0, 0))]
        P[th] = O_th @ q.to_matrix().to_4x4()
        # shin
        O_sh = P[th] @ self.rest[th].inverted() @ self.rest[sh]
        O3 = O_sh.to_3x3().normalized()
        d0 = O3.col[1].normalized()
        W = d0.rotation_difference((A - K).normalized()).to_matrix()
        q = (O3.inverted() @ W @ O3).to_quaternion()
        L[sh] = [q, Vector((0, 0, 0))]
        P[sh] = O_sh @ q.to_matrix().to_4x4()
        # foot: world orientation = rest orientation pitched about X
        O_ft = P[sh] @ self.rest[sh].inverted() @ self.rest[ft]
        O3 = O_ft.to_3x3().normalized()
        Dw = Matrix.Rotation(foot_pitch_deg * D2R, 3, 'X') @ self.rest[ft].to_3x3().normalized()
        q = (O3.inverted() @ Dw).to_quaternion()
        L[ft] = [q, Vector((0, 0, 0))]
        P[ft] = O_ft @ q.to_matrix().to_4x4()

    def arm_ik(self, P, L, side, wrist_target, pole):
        """Two-bone IK for upper_arm/forearm reaching `wrist_target` (armature space)."""
        sfx = '.L' if side < 0 else '.R'
        ua, fa, hd = 'upper_arm' + sfx, 'forearm' + sfx, 'hand' + sfx
        par = self.bones[ua].parent.name
        O_ua = P[par] @ self.rest[par].inverted() @ self.rest[ua]
        S = O_ua.translation.copy()
        a = (self.bones[ua].tail_local - self.bones[ua].head_local).length
        b = (self.bones[fa].tail_local - self.bones[fa].head_local).length
        A = Vector(wrist_target)
        dv = A - S
        d = max(abs(a - b) + 1e-4, min(a + b - 1e-4, dv.length))
        u = dv.normalized()
        A = S + u * d
        cos_a = (a * a + d * d - b * b) / (2 * a * d)
        sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
        pv = Vector(pole) - u * Vector(pole).dot(u)
        pv.normalize()
        E = S + u * (a * cos_a) + pv * (a * sin_a)
        O3 = O_ua.to_3x3().normalized()
        W = O3.col[1].normalized().rotation_difference((E - S).normalized()).to_matrix()
        q = (O3.inverted() @ W @ O3).to_quaternion()
        L[ua] = [q, Vector((0, 0, 0))]
        P[ua] = O_ua @ q.to_matrix().to_4x4()
        O_fa = P[ua] @ self.rest[ua].inverted() @ self.rest[fa]
        O3 = O_fa.to_3x3().normalized()
        W = O3.col[1].normalized().rotation_difference((A - E).normalized()).to_matrix()
        q = (O3.inverted() @ W @ O3).to_quaternion()
        L[fa] = [q, Vector((0, 0, 0))]
        P[fa] = O_fa @ q.to_matrix().to_4x4()
        # hand keeps the forearm's direction (relaxed fist on the rim)
        L[hd] = [Quaternion(), Vector((0, 0, 0))]
        P[hd] = P[fa] @ self.rest[fa].inverted() @ self.rest[hd]

    def evaluate(self, pose):
        P, L = self.solve(pose)
        for side in (-1, 1):
            sfx = '.L' if side < 0 else '.R'
            spec = pose.get('foot' + sfx, {})
            if 'ik' in spec:
                tgt, pitch = spec['ik']
                self.leg_ik(P, L, side, tgt, pitch)
            hs = pose.get('hand' + sfx, {})
            if 'ik' in hs:
                tgt, pole = hs['ik']
                self.arm_ik(P, L, side, tgt, pole)
        return L


# ------------------------------------------------------------------ common poses
REST_ANKLE = {-1: Vector((-rig.HIP_X, 0.0, rig.ANKLE_Z)), 1: Vector((rig.HIP_X, 0.0, rig.ANKLE_Z))}


def stand(hip_dz=0.0, spread=0.0, fwd=(0.0, 0.0)):
    """Feet planted under the hips via IK (keeps feet still while the body moves)."""
    return {
        'hips': {'loc': (0, 0, hip_dz)},
        'foot.L': {'ik': (REST_ANKLE[-1] + Vector((-spread, fwd[0], 0)), 0.0)},
        'foot.R': {'ik': (REST_ANKLE[1] + Vector((spread, fwd[1], 0)), 0.0)},
    }


ARMS_RELAXED = sym({'upper_arm.L': {'rot': (4, -14, 0)}, 'forearm.L': {'rot': (14, 0, 0)}, 'hand.L': {'rot': (0, 0, 0)}})


def with_arms(pose, arms):
    p = dict(pose)
    p.update(arms)
    return p


# ------------------------------------------------------------------ locomotion
def loco_pose(name, phase):
    c = LOCO[name]
    S_total = c['speed']          # metres per cycle (cycle = 1 s at rate 1)
    duty = c['duty']
    sweep = S_total * duty        # foot travel while planted
    walk = c['gait'] == 'walk'
    pose = {}
    # hips: bob twice per cycle.  Walking vaults over the planted leg (highest
    # at mid-stance); running compresses into it (lowest at mid-stance).
    cb = math.cos(4 * math.pi * phase)
    bob = -c['drop'] + c['bob'] * cb if walk else -c['drop'] - c['bob'] * cb
    # pelvis turns toward the leg that is forward; shoulders counter-rotate
    twist = (4.0 if walk else 7.0) * math.sin(2 * math.pi * phase)
    # weight over the stance foot (a little side-to-side sway, more when walking)
    sway = (0.012 if walk else 0.006) * math.cos(2 * math.pi * phase)
    roll = (3.0 if walk else 2.0) * math.cos(2 * math.pi * phase)
    pose['hips'] = {'loc': (-sway, 0, bob), 'rot': (c['lean'] * 0.25, roll, twist)}
    pose['spine'] = {'rot': (c['lean'] * 0.55, -roll * 0.6, -twist * 0.9)}
    pose['chest'] = {'rot': (c['lean'] * 0.3, -roll * 0.3, -twist * 0.8)}
    pose['neck'] = {'rot': (-c['lean'] * 0.5, 0, twist * 0.3)}
    pose['head'] = {'rot': (-c['lean'] * 0.45, -roll * 0.2, twist * 0.25)}
    for side, ph0 in ((-1, 0.0), (1, 0.5)):
        sfx = '.L' if side < 0 else '.R'
        ph = (phase + ph0 + duty * 0.5) % 1.0     # 0 = foot strike, duty = toe-off
        x = rig.HIP_X * side + 0.012 * side
        if ph < duty:
            u = ph / duty
            y = sweep * (0.5 - u)
            # heel strike -> flat -> heel rise: the ankle rides a little higher at
            # both ends of the stance (heel/toe roll), which also keeps it reachable
            z = rig.ANKLE_Z + 0.014 * (1.0 - smoothstep(0.0, 0.3, u)) + 0.022 * smoothstep(0.7, 1.0, u)
            pitch = 8.0 * (1.0 - smoothstep(0.0, 0.25, u)) - 28.0 * smoothstep(0.7, 1.0, u)
        else:
            u = (ph - duty) / (1 - duty)
            if walk:
                e = u * u * (3 - 2 * u)
                y = -sweep * 0.5 + sweep * e + sweep * 0.08 * math.sin(math.pi * u)
                z = rig.ANKLE_Z + lerp(0.022, 0.014, u) + c['lift'] * math.sin(math.pi * u) ** 0.9 * (1.0 - 0.3 * u)
                pitch = lerp(-28.0, 8.0, smoothstep(0.1, 0.8, u))
            else:
                # running swing: heel kicks up behind first, the knee drives
                # forward, the foot reaches out and pulls back a touch before it
                # lands (so it meets the ground moving backward, not skidding)
                e = smoothstep(0.12, 0.82, u)
                reach = sweep * 0.5 + sweep * 0.1 * smoothstep(0.55, 0.85, u) * (1.0 - smoothstep(0.85, 1.0, u))
                y = lerp(-sweep * 0.5, reach, e)
                kick = math.sin(math.pi * min(1.0, u / 0.92) ** 0.65) ** 0.7   # peaks early: heel kicks up behind
                z = rig.ANKLE_Z + lerp(0.022, 0.014, u) + c['lift'] * kick * (1.0 - 0.2 * u)
                pitch = lerp(-28.0, 8.0, smoothstep(0.35, 0.9, u)) - 14.0 * math.sin(math.pi * min(1.0, u / 0.6))
        # IK targets are in armature space; hips twist moves the hip joints,
        # ankles stay where the gait puts them (the solver reaches for them)
        pose['foot' + sfx] = {'ik': (Vector((x, y, z)), pitch)}
        # arms swing opposite to the legs: each arm is at its forward peak when
        # its own leg is furthest back (toe-off) and crosses the middle at mid-stance
        sw = c['arm'] * math.sin(2 * math.pi * (phase + ph0))
        pose['upper_arm' + sfx] = {'rot': (sw, (-10 if walk else -14) * side, 4 * side * max(0.0, sw) / max(1.0, c['arm']))}
        # V5: the forearm and mitten follow the upper arm a beat late
        # (overlapping action), so the arm swing whips instead of hinging
        lagf = math.sin(2 * math.pi * (phase + ph0 - 0.07))
        lagh = math.sin(2 * math.pi * (phase + ph0 - 0.12))
        pose['forearm' + sfx] = {'rot': (c['elbow'] + 0.18 * c['arm'] * lagf + 0.12 * max(0.0, sw), 0, 0)}
        pose['hand' + sfx] = {'rot': (6 + (4 if walk else 7) * lagh, 0, 0)}
        pose['shoulder' + sfx] = {'rot': (0, 0, -3 * side * math.sin(2 * math.pi * (phase + ph0)))}
    # V5: the head gives a little at each foot strike (twice per cycle) and
    # the hips' bob is a touch rounder: bouncy, not stiff
    nod = (1.0 if walk else -2.2) * math.cos(4 * math.pi * (phase - 0.04))   # + = back
    hx, hy, hz = pose['head']['rot']
    pose['head']['rot'] = (hx + nod, hy, hz)
    return pose


def reach_report():
    """Max ankle distance from the hip joint over each gait (must stay < 0.44 m)."""
    out = {}
    leg = 0.44
    for name in LOCO:
        worst = 0.0
        for i in range(200):
            p = loco_pose(name, i / 200.0)
            hz = rig.HIP_Z + p['hips']['loc'][2]
            for sfx in ('.L', '.R'):
                t = p['foot' + sfx]['ik'][0]
                d = math.sqrt(t.y ** 2 + (hz - t.z) ** 2)
                worst = max(worst, d)
        out[name] = round(worst, 4)
    return out, leg


# ------------------------------------------------------------------ clip library
IDLE_L = 4.0


def clip_idle(t):
    """4 s: two slow breaths, one weight shift from foot to foot, a glance."""
    L = IDLE_L
    br = math.sin(2 * math.pi * t / (L * 0.5))           # breathing, 2 per loop
    ws = math.sin(2 * math.pi * t / L)                   # weight shift, 1 per loop
    look = math.sin(2 * math.pi * t / L + 0.9)
    pose = stand(-0.012 + 0.005 * br - 0.006 * abs(ws))
    pose['hips']['loc'] = (0.016 * ws, 0, pose['hips']['loc'][2])
    pose['hips']['rot'] = (0, -2.5 * ws, 1.5 * ws)
    pose['spine'] = {'rot': (-1.2 * br, 2.0 * ws, 0)}
    pose['chest'] = {'rot': (-1.8 * br, 1.0 * ws, -1.0 * ws)}
    pose['neck'] = {'rot': (0.8 * br, -1.5 * ws, 0)}
    pose['head'] = {'rot': (1.5 * br + 2.0, -2.0 * ws, 9.0 * look)}
    pose.update(sym({'upper_arm.L': {'rot': (3 + 1.5 * br, -11 - 1.5 * br, 0)}, 'forearm.L': {'rot': (16 + 2 * br, 0, 0)},
                     'shoulder.L': {'rot': (0, 1.2 * br, 0)}, 'hand.L': {'rot': (4, 0, 0)}}))
    return pose


def clip_fidget_yawn(t):
    """Lobby/idle fidget (2.4 s): a big pajama yawn and stretch.  V5: the
    arms open into a wide V with the fists beside the head (in V4 they went
    straight up into the big head and vanished)."""
    k = smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(1.7, 2.4, t))
    pose = clip_idle(0.0)
    pose['hips']['loc'] = (0, 0, -0.012 + 0.010 * k)
    pose['spine'] = {'rot': (7 * k, 0, 0)}
    pose['chest'] = {'rot': (6 * k, 0, 0)}
    pose['neck'] = {'rot': (7 * k, 0, 0)}
    pose['head'] = {'rot': (13 * k, 0, 0)}
    pose.update(sym({'shoulder.L': {'rot': (0, 12 * k, 0)}, 'upper_arm.L': {'rot': (-6 * k, -11 + 84 * k, 0)},
                     'forearm.L': {'rot': (16 + 62 * k, -30 * k, 0)}, 'hand.L': {'rot': (10 * k, 0, 0)}}))
    return pose


def clip_fidget_look(t):
    """Lobby/idle fidget (2.0 s): looks over one shoulder, then the other."""
    a = math.sin(2 * math.pi * min(1.0, t / 2.0))
    k = smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(1.7, 2.0, t))
    pose = clip_idle(0.0)
    pose['chest'] = {'rot': (0, 0, 10 * a * k)}
    pose['neck'] = {'rot': (0, 0, 10 * a * k)}
    pose['head'] = {'rot': (4 * k, 4 * a * k, 18 * a * k)}
    pose['hips']['rot'] = (0, 0, 4 * a * k)
    return pose


def clip_fidget_shift(t):
    """Menu idle fidget (2.6 s, V5): settles the weight onto the right leg
    (the hip slides over it, the left knee softens), a small sigh of the
    shoulders and a head tilt, then back to centre.  Feet stay planted."""
    k = smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(1.8, 2.6, t))
    sigh = math.sin(math.pi * smoothstep(0.6, 1.7, t))
    pose = stand(-0.014 - 0.010 * k)
    pose['hips']['loc'] = (0.026 * k, 0, -0.014 - 0.010 * k)
    pose['hips']['rot'] = (0, 3.0 * k, -3.0 * k)
    pose['spine'] = {'rot': (-1.0 * sigh * k, -4.0 * k, 2.0 * k)}
    pose['chest'] = {'rot': (-1.5 * sigh * k, -1.5 * k, 1.0 * k)}
    pose['neck'] = {'rot': (0.8 * sigh, 1.0 * k, 0)}
    pose['head'] = {'rot': (2.0 + 2.5 * sigh * k, 5.0 * k, -5.0 * k)}
    pose.update(sym({'shoulder.L': {'rot': (0, 1.2 + 4.0 * sigh * k, 0)}, 'upper_arm.L': {'rot': (3, -11 - 2.0 * sigh * k, 0)},
                     'forearm.L': {'rot': (16 + 4 * sigh * k, 0, 0)}, 'hand.L': {'rot': (4, 0, 0)}}))
    # the relaxed (left) arm hangs a little looser
    pose['upper_arm.L']['rot'] = (3 - 3 * k, -11 + 2 * k, 0)
    return pose


def clip_fidget_bounce(t):
    """Menu idle fidget (1.8 s, V5): two small bounces up onto the toes with
    a little arm swing, then settles.  The toes stay on the floor."""
    u = t / 1.8
    k = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.8, 1.0, u))
    b = math.sin(math.pi * ((t / 0.75) % 1.0)) ** 2 if t < 1.5 else 0.0
    lift = 0.03 * b * k
    pose = stand(lift - 0.012 - 0.012 * (1.0 - b) * k)
    for side, sfx in ((-1, '.L'), (1, '.R')):
        pose['foot' + sfx] = {'ik': (REST_ANKLE[side] + Vector((0, -0.012 * b * k, lift)), -22.0 * b * k)}
    sw = math.sin(2 * math.pi * t / 0.75) * k
    pose.update(sym({'upper_arm.L': {'rot': (3 + 9 * sw, -11, 0)}, 'forearm.L': {'rot': (16 + 8 * b * k, 0, 0)},
                     'hand.L': {'rot': (4, 0, 0)}}))
    pose['upper_arm.R']['rot'] = (3 - 9 * sw, 11, 0)
    pose['spine'] = {'rot': (-2 * b * k, 0, 0)}
    pose['head'] = {'rot': (2 + 3 * b * k, 0, 3 * sw)}
    return pose


def clip_ready(t):
    """Lobby ready response (0.9 s): a quick fist pump with a bounce.  V5:
    the fist pumps beside the head, not into it, and the feet leave the
    floor with the bounce instead of being stretched past the leg."""
    u = t / 0.9
    k = smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.7, 1.0, u))
    bounce = math.sin(math.pi * smoothstep(0.1, 0.55, u)) * 0.05
    pose = stand(-0.03 * k + bounce)
    lift = max(0.0, bounce - 0.006)
    for side, sfx in ((-1, '.L'), (1, '.R')):
        pose['foot' + sfx] = {'ik': (REST_ANKLE[side] + Vector((0, 0, lift)), -14.0 * lift / 0.05)}
    pose.update(sym({'upper_arm.L': {'rot': (4, -11, 0)}, 'forearm.L': {'rot': (16, 0, 0)}}))
    pose['upper_arm.R'] = {'rot': (22 * k, -11 - 72 * k, 0)}
    pose['forearm.R'] = {'rot': (16 + 92 * k, 22 * k, 0)}
    pose['hand.R'] = {'rot': (10 * k, 0, 0)}
    pose['chest'] = {'rot': (-4 * k, 0, -6 * k)}
    pose['head'] = {'rot': (8 * k, 0, -8 * k)}
    return pose


def clip_turn(t, direction):
    # quick shuffle step in place: one foot lifts and re-plants, body twists
    u = t / 0.4
    pose = stand(-0.015 * math.sin(math.pi * u))
    lift = 0.05 * math.sin(math.pi * smoothstep(0.0, 0.6, u)) if u < 0.6 else 0.0
    lift2 = 0.05 * math.sin(math.pi * smoothstep(0.4, 1.0, u)) if u > 0.4 else 0.0
    a, b = ('L', 'R') if direction > 0 else ('R', 'L')
    sa = -1 if a == 'L' else 1
    sb = -sa
    pose['foot.' + a] = {'ik': (REST_ANKLE[sa] + Vector((0, 0, lift)), -10 * lift / 0.05)}
    pose['foot.' + b] = {'ik': (REST_ANKLE[sb] + Vector((0, 0, lift2)), -10 * lift2 / 0.05)}
    pose['hips']['rot'] = (0, 0, 8 * direction * math.sin(math.pi * u))
    pose['chest'] = {'rot': (0, 0, 6 * direction * math.sin(math.pi * u))}
    pose['head'] = {'rot': (0, 0, 10 * direction * math.sin(math.pi * u))}
    pose.update(ARMS_RELAXED)
    return pose


def _air(tuck_l, tuck_r, arm_raise, arm_fwd, elbow, spine, head, flap=0.0):
    p = sym({'upper_arm.L': {'rot': (arm_fwd + flap, arm_raise, 0)}, 'forearm.L': {'rot': (elbow, 0, 0)},
             'hand.L': {'rot': (0, 0, 0)}})
    p['upper_arm.R']['rot'] = (arm_fwd - flap, -arm_raise, 0)
    for sfx, (th, sh, ft) in (('.L', tuck_l), ('.R', tuck_r)):
        p['thigh' + sfx] = {'rot': (th, 0, 0)}
        p['shin' + sfx] = {'rot': (sh, 0, 0)}
        p['foot' + sfx] = {'rot': (ft, 0, 0)}
    p['spine'] = {'rot': (spine, 0, 0)}
    p['head'] = {'rot': (head, 0, 0)}
    p['hips'] = {'loc': (0, 0, 0.02)}
    return p


# Air poses form a blend space over vertical velocity (CharacterView): rising
# (+5.5 m/s), apex (0) and falling (-7).  Each is a gentle 1 s loop so the
# blend never pops at the top of the arc.
def clip_air_rise(t):
    w = math.sin(2 * math.pi * t)
    return _air((52, -72, -25), (22, -38, -30), 24 + 3 * w, 38, 55, -6, -6, 3 * w)


def clip_air_apex(t):
    w = math.sin(2 * math.pi * t)
    return _air((40, -62, -18), (30, -50, -18), 78 + 3 * w, 4, 26, 2, 4, 4 * w)


def clip_air_fall(t):
    w = math.sin(2 * math.pi * t)
    # V5: arms up and out (85 deg, not 100) so the flailing forearms stay
    # outside the head
    return _air((16 + 6 * w, -26, -8), (24 - 6 * w, -34, -8), 84 + 5 * w, 16, 30, 5, 9, 12 * w)


def _land(t, L, depth, lean, arms):
    """V5 landing: it starts from the fall (arms up, legs nearly straight) so
    the overlay can come in fast without snapping the arms down; the knees
    take the impact at once, a second small dip settles it."""
    u = min(1.0, t / L)
    dip = math.sin(math.pi * min(1.0, u / 0.6)) if u < 0.6 else 0.14 * math.sin(math.pi * (u - 0.6) / 0.4)
    drop = smoothstep(0.0, 0.45, u)          # arms come down from the fall
    pose = stand(-depth * dip, 0.012 * dip)
    pose['hips']['rot'] = (-lean * 0.3 * dip, 0, 0)
    pose['spine'] = {'rot': (-lean * dip, 0, 0)}
    pose['neck'] = {'rot': (lean * 0.4 * dip, 0, 0)}
    pose['head'] = {'rot': (lean * 0.5 * dip, 0, 0)}
    raise_ = lerp(arms, -12 + arms * 0.25 * dip, drop)
    pose.update(sym({'upper_arm.L': {'rot': (lerp(14, 20 * dip, drop), raise_, 0)},
                     'forearm.L': {'rot': (lerp(28, 16 + 25 * dip, drop), 0, 0)}}))
    return pose


def clip_land_soft(t):
    return _land(t, 0.3, 0.06, 8, 55)


def clip_land_hard(t):
    return _land(t, 0.45, 0.15, 20, 78)


def clip_dive(t):
    u = smoothstep(0.0, 0.18, t)
    p = sym({'upper_arm.L': {'rot': (lerp(20, 160, u), -8, 0)}, 'forearm.L': {'rot': (lerp(30, 5, u), 0, 0)},
             'hand.L': {'rot': (0, 0, 0)}, 'thigh.L': {'rot': (lerp(10, -12, u), 0, 0)}, 'shin.L': {'rot': (lerp(-20, -18, u), 0, 0)},
             'foot.L': {'rot': (-35 * u, 0, 0)}})
    p['thigh.R']['rot'] = (lerp(10, -4, u), 0, 0)
    p['shin.R']['rot'] = (lerp(-20, -35, u), 0, 0)
    p['hips'] = {'rot': (-78 * u, 0, 0), 'loc': (0, 0.0, -0.18 * u)}
    p['spine'] = {'rot': (6 * u, 0, 0)}
    p['neck'] = {'rot': (18 * u, 0, 0)}
    p['head'] = {'rot': (30 * u, 0, 0)}
    return p


def clip_dive_land(t):
    # belly slide then push back up to standing (0.32 s)
    u = t / 0.32
    up = smoothstep(0.35, 1.0, u)
    p = sym({'upper_arm.L': {'rot': (lerp(150, 10, up), lerp(-8, -20, up), 0)}, 'forearm.L': {'rot': (lerp(10, 30, up), 0, 0)},
             'thigh.L': {'rot': (lerp(-10, 5, up), 0, 0)}, 'shin.L': {'rot': (lerp(-25, -10, up), 0, 0)}})
    p['hips'] = {'rot': (lerp(-80, 0, up), 0, 0), 'loc': (0, 0, lerp(-0.25, 0.0, up))}
    p['neck'] = {'rot': (lerp(20, 0, up), 0, 0)}
    p['head'] = {'rot': (lerp(25, 0, up), 0, 0)}
    return p


SPLASH_L = 1.5   # == RulesConfig.splash_sequence_s (the sim moves the runner to the shore after this)


def _tread(t):
    """Treading water: hips low, slow sculling arms, slow bicycle legs."""
    w = math.sin(2 * math.pi * 1.6 * t)
    c = math.cos(2 * math.pi * 1.6 * t)
    p = sym({'upper_arm.L': {'rot': (12 + 14 * w, 68, 0)}, 'forearm.L': {'rot': (30 + 8 * c, 0, 0)},
             'hand.L': {'rot': (0, 0, 0)}, 'thigh.L': {'rot': (42 + 16 * w, -6, 0)}, 'shin.L': {'rot': (-62 - 14 * c, 0, 0)},
             'foot.L': {'rot': (-20, 0, 0)}})
    p['upper_arm.R']['rot'] = (12 - 14 * w, -68, 0)
    p['thigh.R']['rot'] = (42 - 16 * w, 6, 0)
    p['shin.R']['rot'] = (-62 + 14 * c, 0, 0)
    p['hips'] = {'loc': (0, 0, -0.92 + 0.025 * math.sin(2 * math.pi * 1.6 * t + 0.6)), 'rot': (6, 0, 0)}
    p['spine'] = {'rot': (-4, 0, 0)}
    p['head'] = {'rot': (10, 0, 7 * math.sin(2 * math.pi * 0.6 * t))}
    return p


def _splash_contact(kind, t):
    """First beat: how the body meets the water (walk-in, jump, dive)."""
    if kind == 'walk':
        # tips in: one foot still up behind, arms thrown up and forward
        p = sym({'upper_arm.L': {'rot': (120, 30, 0)}, 'forearm.L': {'rot': (25, 0, 0)}, 'thigh.L': {'rot': (35, 0, 0)},
                 'shin.L': {'rot': (-40, 0, 0)}, 'foot.L': {'rot': (-20, 0, 0)}})
        p['thigh.R'] = {'rot': (-25, 0, 0)}
        p['shin.R'] = {'rot': (-55, 0, 0)}
        p['hips'] = {'loc': (0, 0.05, -0.38), 'rot': (-22, 0, 0)}
        p['head'] = {'rot': (20, 0, 0)}
        return p
    if kind == 'jump':
        # cannonball: knees to chest, arms hug the shins
        p = sym({'upper_arm.L': {'rot': (45, 20, 0)}, 'forearm.L': {'rot': (100, 0, 0)}, 'thigh.L': {'rot': (105, -6, 0)},
                 'shin.L': {'rot': (-125, 0, 0)}, 'foot.L': {'rot': (-30, 0, 0)}})
        p['hips'] = {'loc': (0, 0, -0.55), 'rot': (14, 0, 0)}
        p['spine'] = {'rot': (14, 0, 0)}
        p['head'] = {'rot': (16, 0, 0)}
        return p
    # dive: belly first, arms out front, legs back
    p = sym({'upper_arm.L': {'rot': (150, 14, 0)}, 'forearm.L': {'rot': (10, 0, 0)}, 'thigh.L': {'rot': (-8, -4, 0)},
             'shin.L': {'rot': (-30, 0, 0)}, 'foot.L': {'rot': (-30, 0, 0)}})
    p['hips'] = {'rot': (-70, 0, 0), 'loc': (0, 0.1, -0.5)}
    p['neck'] = {'rot': (22, 0, 0)}
    p['head'] = {'rot': (28, 0, 0)}
    return p


def clip_splash(kind, t):
    """1.5 s, played by authoritative elapsed time (CharacterView seeks it to
    the runner's state_t, so a late joiner sees the right beat):
      0.00-0.16  contact  (impact-specific pose, crown of spray from the game FX)
      0.16-0.48  dip      (sinks to the chin, arms come up, cheeks puff)
      0.48-1.12  tread    (controlled bob, sculling arms, slow legs)
      1.12-1.50  duck     (a breath, then a tidy duck under; the runner pops
                           up at the shore exit when the sim resurfaces them)"""
    contact = _splash_contact(kind, t)
    dip = _tread(t)
    dip['hips']['loc'] = (0, 0, -1.04)
    dip.update(sym({'upper_arm.L': {'rot': (40, 86, 0)}, 'forearm.L': {'rot': (30, 0, 0)}}))
    dip['upper_arm.R']['rot'] = (40, -86, 0)
    dip['head'] = {'rot': (14, 0, 0)}
    if t < 0.16:
        return contact
    if t < 0.48:
        return blend_pose(contact, dip, smoothstep(0.16, 0.48, t))
    tread = _tread(t)
    if t < 0.62:
        return blend_pose(dip, tread, smoothstep(0.48, 0.62, t))
    if t < 1.12:
        return tread
    # breath (hips rise a touch, head back) then duck under, arms overhead
    breath = _tread(t)
    breath['hips']['loc'] = (0, 0, -0.84)
    breath['head'] = {'rot': (-6, 0, 0)}
    # V5: arms overhead in a V that clears the big head (V4: 168 deg, through it)
    duck = sym({'upper_arm.L': {'rot': (14, 92, 0)}, 'forearm.L': {'rot': (14, -30, 0)}, 'thigh.L': {'rot': (10, 0, 0)},
                'shin.L': {'rot': (-15, 0, 0)}, 'foot.L': {'rot': (-35, 0, 0)}})
    duck['hips'] = {'loc': (0, 0, -1.75)}
    duck['head'] = {'rot': (-4, 0, 0)}
    if t < 1.26:
        return blend_pose(tread, breath, smoothstep(1.12, 1.26, t))
    return blend_pose(breath, duck, smoothstep(1.26, 1.47, t))


def clip_recover(t):
    """Upper-body overlay after popping out at the shore (1.1 s): a quick
    shake-off from the head down, then a wipe of the face.  CharacterView
    plays it on the upper body only, so the legs keep running."""
    k = (1.0 - smoothstep(0.0, 0.6, t)) * smoothstep(0.0, 0.05, t)
    s = math.sin(t * 2 * math.pi * 6.0) * k
    pose = {}
    pose['spine'] = {'rot': (0, 6 * s, 0)}
    pose['chest'] = {'rot': (0, 8 * s, 0)}
    pose['neck'] = {'rot': (0, -6 * s, 0)}
    pose['head'] = {'rot': (4 * k, -16 * s, 0)}
    pose.update(sym({'shoulder.L': {'rot': (0, 6 * abs(s), 0)}, 'upper_arm.L': {'rot': (10, -4 + 12 * s, 0)},
                     'forearm.L': {'rot': (28 + 18 * s, 0, 0)}}))
    # wipe: right mitten passes over the brow
    w = smoothstep(0.5, 0.72, t) * (1.0 - smoothstep(0.86, 1.1, t))
    if w > 0.0:
        sweep = math.sin(math.pi * smoothstep(0.62, 0.92, t))
        pose['upper_arm.R'] = {'rot': (lerp(10, 95, w), lerp(4, -20, w), 0)}
        pose['forearm.R'] = {'rot': (lerp(28, 120, w), lerp(0, 35 * sweep - 10, w), 0)}
        pose['head']['rot'] = (pose['head']['rot'][0] + 6 * w, pose['head']['rot'][1], -6 * w * sweep)
    return pose


def clip_stumble(t):
    u = t / 0.55
    k = math.sin(math.pi * u)
    w = math.sin(t * 26.0)
    p = sym({'upper_arm.L': {'rot': (60 * w * k + 20 * k, 70 * k - 10, 0)}, 'forearm.L': {'rot': (20 + 20 * k, 0, 0)}})
    p['upper_arm.R']['rot'] = (-60 * w * k + 20 * k, -70 * k + 10, 0)
    p.update(stand(-0.05 * k))
    p['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0.12 * k, 0.1 * k)), 20 * k)}
    p['hips']['rot'] = (-14 * k, 10 * k * math.sin(t * 12), 0)
    p['spine'] = {'rot': (-12 * k, 0, 0)}
    p['head'] = {'rot': (14 * k, 0, 10 * k * math.sin(t * 20))}
    return p


def _sit(depth=1.0):
    p = sym({'thigh.L': {'rot': (88 * depth, -10, 0)}, 'shin.L': {'rot': (-20 * depth, 0, 0)}, 'foot.L': {'rot': (20, 0, 0)}})
    p['hips'] = {'loc': (0, -0.05 * depth, -0.37 * depth)}
    return p


def clip_flop(t):
    u = smoothstep(0.0, 0.5, t)
    bounce = math.sin(math.pi * smoothstep(0.35, 0.75, t)) * 0.05
    p = _sit(u)
    p['hips']['loc'] = (0, -0.05 * u, -0.37 * u + bounce)
    p['hips']['rot'] = (14 * u, 0, 0)
    p['spine'] = {'rot': (8 * u, 0, 0)}
    p['head'] = {'rot': (10 * u, 0, 0)}
    p.update(sym({'upper_arm.L': {'rot': (-35 * u, 40 * u - 10, 0)}, 'forearm.L': {'rot': (20, 0, 0)},
                  'thigh.L': {'rot': (88 * u, -16 * u, 0)}}))
    return p


def clip_dizzy(t):
    L = 2.0
    a = 2 * math.pi * t / L
    p = _sit(1.0)
    p['hips']['rot'] = (14, 4 * math.sin(a), 0)
    p['spine'] = {'rot': (8 + 4 * math.cos(a), 5 * math.sin(a), 0)}
    p['head'] = {'rot': (8 + 8 * math.cos(a * 2), 10 * math.sin(a * 2), 6 * math.sin(a))}
    p.update(sym({'upper_arm.L': {'rot': (-35, 38, 0)}, 'forearm.L': {'rot': (20, 0, 0)},
                  'thigh.L': {'rot': (88, -16, 0)}}))
    return p


def clip_tag_windup(t):
    """Night Watch tag wind-up (0.14 s, V5): a quick coil.  The tagging hand
    (left; the right holds the flashlight) cocks back, the torso turns into
    it and the body drops.  Also played on the upper body alone while the
    Night Watch keeps running."""
    u = smoothstep(0.0, 0.12, t)
    p = stand(-0.06 * u, 0.02 * u, (0.05 * u, -0.07 * u))
    p['hips']['rot'] = (-4 * u, 0, -6 * u)
    p['spine'] = {'rot': (-6 * u, 0, -12 * u)}
    p['chest'] = {'rot': (-3 * u, 0, -9 * u)}
    p['head'] = {'rot': (8 * u, 0, 14 * u)}
    p['upper_arm.L'] = {'rot': (lerp(4, -38, u), lerp(-11, 22, u), 0)}
    p['forearm.L'] = {'rot': (lerp(16, 92, u), 0, 0)}
    p['hand.L'] = {'rot': (-12 * u, 0, 0)}
    p['upper_arm.R'] = {'rot': (lerp(4, 30, u), 11, 0)}
    p['forearm.R'] = {'rot': (lerp(16, 50, u), 0, 0)}
    return p


def clip_tag_lunge(t):
    """Night Watch lunge (0.22 s, V5): a leaping reach.  The sim carries the
    body 2 m at 9 m/s, so the feet leave the floor (V4 slid a planted lunge
    stance across the ground).  Ease-out: full reach almost at once."""
    v = min(1.0, t / 0.11)
    u = 1.0 - (1.0 - v) ** 2
    p = {'hips': {'loc': (0, 0.03 * u, -0.05 * u + 0.03 * u), 'rot': (-14 * u, 0, 8 * u)}}
    # right leg drives forward (knee up), left leg trails extended
    p['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0.0, 0.20 * u, 0.10 * u)), lerp(0, 18, u))}
    p['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0.0, -0.26 * u, 0.13 * u)), lerp(0, -48, u))}
    p['spine'] = {'rot': (-16 * u, 0, 8 * u)}
    p['chest'] = {'rot': (-8 * u, 0, 6 * u)}
    p['neck'] = {'rot': (10 * u, 0, 0)}
    p['head'] = {'rot': (14 * u, 0, -10 * u)}
    p['upper_arm.L'] = {'rot': (lerp(-38, 98, u), lerp(22, -4, u), 0)}
    p['forearm.L'] = {'rot': (lerp(92, 6, u), 0, 0)}
    p['hand.L'] = {'rot': (lerp(-12, -14, u), 0, 0)}
    p['upper_arm.R'] = {'rot': (lerp(30, -42, u), lerp(11, 16, u), 0)}
    p['forearm.R'] = {'rot': (lerp(50, 34, u), 0, 0)}
    return p


def clip_tag_recover(t):
    """After a lunge (0.5 s, V5): lands from the leap with a dip and comes
    back to neutral; IK targets interpolate (V4 jumped the feet mid-clip)."""
    u = smoothstep(0.0, 0.42, t)
    p = blend_pose(clip_tag_lunge(0.22), clip_idle(0.0), u)
    dip = math.sin(math.pi * min(1.0, t / 0.3)) * 0.05
    hl = p['hips'].get('loc', (0, 0, 0))
    p['hips']['loc'] = (hl[0], hl[1], hl[2] - dip)
    return p


def clip_tag_miss(t):
    """Lunge that finds nobody (0.5 s, same window as tag_recover): the arm
    sweeps through empty air and the body wobbles back to balance."""
    u = smoothstep(0.0, 0.45, t)
    over = math.sin(math.pi * min(1.0, t / 0.3))
    p = blend_pose(clip_tag_lunge(0.22), clip_idle(0.0), u)
    dip = math.sin(math.pi * min(1.0, t / 0.3)) * 0.05
    hl = p['hips'].get('loc', (0, 0, 0))
    p['hips']['loc'] = (hl[0], hl[1], hl[2] - dip)
    p['upper_arm.L'] = {'rot': (lerp(98, 4, u) - 24 * over, lerp(-4, -11, u) + 34 * over, 0)}
    p['forearm.L'] = {'rot': (lerp(6, 16, u) + 30 * over, 0, 0)}
    p['upper_arm.R'] = {'rot': (lerp(-42, 4, u) + 18 * over, lerp(16, 11, u) - 30 * over, 0)}
    p['spine'] = {'rot': (lerp(-16, 0, u), 0, 10 * over)}
    p['head'] = {'rot': (lerp(14, 0, u), 0, -14 * over)}
    return p


WHEEL_C = Vector((0.0, 0.27, 0.50))
WHEEL_R = 0.17
WHEEL_U = Vector((0.0, 0.8, 0.6)).normalized()     # in the wheel plane, up/forward
STEER_DEG = 50.0


def _wheel_grip(side, steer):
    a = math.radians(-steer * STEER_DEG)
    x = side * WHEEL_R * 0.92
    v = -WHEEL_R * 0.25
    # rotate the grip point about the wheel axis (n = x̂ cross u)
    xr = x * math.cos(a) - v * math.sin(a)
    vr = x * math.sin(a) + v * math.cos(a)
    return WHEEL_C + Vector((xr, 0, 0)) + WHEEL_U * vr


def _seated(steer=0.0):
    p = _sit(1.0)
    p['hips']['loc'] = (0, -0.06, -0.33)
    p['hips']['rot'] = (6, 0, 0)
    # steer +1 = right turn: lean and look into the turn (+Z turns left)
    p['spine'] = {'rot': (-8, steer * 4, -steer * 3)}
    p['head'] = {'rot': (2, steer * 3, -steer * 10)}
    p.update(sym({'thigh.L': {'rot': (82, -6, 0)}, 'shin.L': {'rot': (-75, 0, 0)}, 'foot.L': {'rot': (12, 0, 0)}}))
    for side in (-1, 1):
        sfx = '.L' if side < 0 else '.R'
        p['hand' + sfx] = {'ik': (_wheel_grip(side, steer), (side * 0.6, -0.2, -1.0))}
    return p


def clip_cart_drive(t, steer=0.0):
    b = math.sin(2 * math.pi * t) * 0.006
    p = _seated(steer)
    p['hips']['loc'] = (0, -0.06, -0.33 + b)
    return p


def clip_cart_enter(t):
    """Hop into the seat (0.35 s, V5).  The character is drawn at the seat
    from the first frame (the sim puts it there), so the clip starts in the
    air above the cushion, knees tucked, hands reaching for the wheel, and
    lands seated.  V4 stood up on the seat and blended standing IK legs into
    seated FK legs, which jumped half-way through."""
    u = smoothstep(0.0, 0.33, t)
    hop = math.sin(math.pi * min(1.0, 0.35 + t / 0.5)) * 0.16 * (1.0 - u)
    tuck = sym({'thigh.L': {'rot': (70, -8, 0)}, 'shin.L': {'rot': (-105, 0, 0)}, 'foot.L': {'rot': (20, 0, 0)}})
    tuck['hips'] = {'loc': (0, -0.04, -0.2), 'rot': (8, 0, 0)}
    tuck['spine'] = {'rot': (-12, 0, 0)}
    tuck['head'] = {'rot': (6, 0, 0)}
    for side in (-1, 1):
        sfx = '.L' if side < 0 else '.R'
        tuck['hand' + sfx] = {'ik': (_wheel_grip(side, 0.0) + Vector((side * 0.06, -0.08, 0.1)), (side * 0.6, -0.2, -1.0))}
    p = blend_pose(tuck, _seated(0.0), u)
    hl = p['hips']['loc']
    p['hips']['loc'] = (hl[0], hl[1], hl[2] + hop)
    return p


def clip_cart_exit(t):
    """Hop out (0.3 s, the sim's cart_exit_s, V5).  The character is drawn at
    the exit point beside the cart from the first frame, so the clip is a
    landing: knees bent, arms out for balance, then up to standing.  V4
    started seated on the ground there and hopped up through the leg IK."""
    u = min(1.0, t / 0.3)
    k = 1.0 - smoothstep(0.0, 1.0, u)
    p = stand(-0.12 * k, 0.03 * k)
    p['hips']['rot'] = (-6 * k, 0, 0)
    p['spine'] = {'rot': (-10 * k, 0, 0)}
    p['head'] = {'rot': (8 * k, 0, 0)}
    p.update(sym({'upper_arm.L': {'rot': (14 * k, -11 + 46 * k, 0)}, 'forearm.L': {'rot': (16 + 18 * k, 0, 0)}}))
    return p


def clip_celebrate(t):
    L = 1.0
    ph = (t % L) / L
    jump = max(0.0, math.sin(2 * math.pi * ph)) * 0.16
    crouch = max(0.0, -math.sin(2 * math.pi * ph)) * 0.07
    pump = math.sin(4 * math.pi * ph)
    p = stand(jump - crouch)
    if jump > 0.0:
        p['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0, jump)), -20 * jump / 0.16)}
        p['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0, 0, jump)), -20 * jump / 0.16)}
    # V5: a wide V with bent elbows (V4: 118 deg, hands inside the head)
    p.update(sym({'upper_arm.L': {'rot': (8, 82 - 6 * pump, 0)}, 'forearm.L': {'rot': (36 + 18 * pump, -22, 0)}}))
    p['head'] = {'rot': (12, 0, 6 * pump)}
    p['spine'] = {'rot': (6, 0, 0)}
    return p


def emote(name, t):
    pose = clip_idle(0.0)   # static base: emote loops must not carry the 4 s idle cycle
    if name == 'wave':
        w = math.sin(2 * math.pi * 3.0 * t / 1.2)     # 3 waves per 1.2 s loop (seamless)
        # V5: elbow out, the waving hand by the cheek but outside the head
        # (V4 swung the forearm into the head; the chibi head leaves no room
        # for a hand above it)
        pose['upper_arm.R'] = {'rot': (10, -82, 0)}
        pose['forearm.R'] = {'rot': (10, -2 + 24 * w, 0)}
        pose['head']['rot'] = (6, 0, -6)
        pose['chest'] = {'rot': (0, 4, 0)}
    elif name == 'cheer':
        b = abs(math.sin(2 * math.pi * t / 0.8))      # 3 bounces per 1.2 s loop
        pose = stand(0.0)
        if b > 0.5:
            pass
        pose['hips'] = {'loc': (0, 0, -0.05 + 0.1 * b)}
        pose['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0, max(0.0, 0.1 * b - 0.05))), 0.0)}
        pose['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0, 0, max(0.0, 0.1 * b - 0.05))), 0.0)}
        pose.update(sym({'upper_arm.L': {'rot': (8, 92, 0)}, 'forearm.L': {'rot': (26 + 20 * b, -24, 0)}}))
        pose['head'] = {'rot': (14, 0, 0)}
    elif name == 'laugh':
        s = math.sin(2 * math.pi * 4.0 * t / 1.2)     # 4 chuckles per 1.2 s loop
        pose['spine'] = {'rot': (-10 + 4 * s, 0, 0)}
        pose['chest'] = {'rot': (-6 + 3 * s, 0, 0)}
        pose['head'] = {'rot': (10 + 6 * s, 0, 0)}
        pose.update(sym({'upper_arm.L': {'rot': (35, -18, 0)}, 'forearm.L': {'rot': (85, 0, 0)}}))
    elif name == 'shrug':
        k = smoothstep(0.0, 0.25, t % 1.4) * (1.0 - smoothstep(1.0, 1.4, t % 1.4))
        pose.update(sym({'shoulder.L': {'rot': (0, 18 * k, 0)}, 'upper_arm.L': {'rot': (12 * k, 30 * k - 10, 0)},
                         'forearm.L': {'rot': (70 * k + 10, -40 * k, 0)}}))
        pose['head'] = {'rot': (0, 14 * k, 6 * k)}
    elif name == 'dance':
        ph = t * 2 * math.pi * 1.6
        s = math.sin(ph)
        pose = stand(-0.04 + 0.03 * abs(s), 0.02)
        pose['hips']['rot'] = (0, 10 * s, 12 * s)
        pose['spine'] = {'rot': (0, -8 * s, -10 * s)}
        pose['head'] = {'rot': (0, 8 * s, 0)}
        pose.update(sym({'upper_arm.L': {'rot': (40 + 40 * s, 62, 0)}, 'forearm.L': {'rot': (72, 0, 0)}}))
        pose['upper_arm.R'] = {'rot': (40 - 40 * s, -62, 0)}
    elif name == 'point':
        pose['upper_arm.R'] = {'rot': (85, 18, 0)}
        pose['forearm.R'] = {'rot': (5, 0, 0)}
        pose['hand.R'] = {'rot': (0, 0, 0)}
        pose['upper_arm.L'] = {'rot': (0, -12, 0)}
        pose['forearm.L'] = {'rot': (60, 0, 0)}
        pose['chest'] = {'rot': (0, 0, -10)}
        pose['head'] = {'rot': (6, 0, -8)}
    return pose


def clip_arrive(t):
    # lobby arrival: crouch, hop, land with a little ta-da (0.9 s)
    if t < 0.15:
        u = t / 0.15
        p = stand(-0.08 * u)
        p.update(sym({'upper_arm.L': {'rot': (-20 * u, -14, 0)}, 'forearm.L': {'rot': (20, 0, 0)}}))
        return p
    if t < 0.5:
        u = (t - 0.15) / 0.35
        h = math.sin(math.pi * u) * 0.28
        p = stand(-0.08 + 0.08 * smoothstep(0.0, 0.3, u) + h)
        lift = max(0.0, h - 0.004)
        p['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0, lift)), -20 * smoothstep(0.0, 0.04, h))}
        p['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0, 0, lift)), -20 * smoothstep(0.0, 0.04, h))}
        # (V5: the arms' forward swing continues from the crouch instead of
        # jumping 30 degrees at 0.15 s)
        p.update(sym({'upper_arm.L': {'rot': (lerp(-20, 10, smoothstep(0.0, 0.35, u)), 92 * math.sin(math.pi * u) - 14, 0)},
                      'forearm.L': {'rot': (20 + 14 * math.sin(math.pi * u), -14 * math.sin(math.pi * u), 0)}}))
        return p
    u = (t - 0.5) / 0.4
    sq = math.sin(math.pi * min(1.0, u * 2.0)) * (1.0 - u)
    p = stand(-0.09 * sq)
    k = smoothstep(0.2, 1.0, u)
    p.update(sym({'upper_arm.L': {'rot': (10 * k, -14 + 50 * k, 0)}, 'forearm.L': {'rot': (20 + 20 * k, 0, 0)}}))
    p['head'] = {'rot': (8 * k, 0, 0)}
    return p


def library():
    """name -> (length_s, loop, fn(t) -> pose)"""
    lib = {
        'idle': (IDLE_L, True, clip_idle),
        'fidget_yawn': (2.4, False, clip_fidget_yawn),
        'fidget_look': (2.0, False, clip_fidget_look),
        'fidget_shift': (2.6, False, clip_fidget_shift),
        'fidget_bounce': (1.8, False, clip_fidget_bounce),
        'ready': (0.9, False, clip_ready),
        'walk': (1.0, True, lambda t: loco_pose('walk', t)),
        'run': (1.0, True, lambda t: loco_pose('run', t)),
        'sprint': (1.0, True, lambda t: loco_pose('sprint', t)),
        'turn_l': (0.4, False, lambda t: clip_turn(t, 1)),
        'turn_r': (0.4, False, lambda t: clip_turn(t, -1)),
        'air_rise': (1.0, True, clip_air_rise),
        'air_apex': (1.0, True, clip_air_apex),
        'air_fall': (1.0, True, clip_air_fall),
        'land_soft': (0.3, False, clip_land_soft),
        'land_hard': (0.45, False, clip_land_hard),
        'dive': (0.6, False, clip_dive),
        'dive_land': (0.32, False, clip_dive_land),
        'splash_walk': (SPLASH_L, False, lambda t: clip_splash('walk', t)),
        'splash_jump': (SPLASH_L, False, lambda t: clip_splash('jump', t)),
        'splash_dive': (SPLASH_L, False, lambda t: clip_splash('dive', t)),
        'recover': (1.1, False, clip_recover),
        'stumble': (0.55, False, clip_stumble),
        'flop': (0.9, False, clip_flop),
        'dizzy': (2.0, True, clip_dizzy),
        'tag_windup': (0.14, False, clip_tag_windup),
        'tag_lunge': (0.22, False, clip_tag_lunge),
        'tag_recover': (0.5, False, clip_tag_recover),
        'tag_miss': (0.5, False, clip_tag_miss),
        'cart_enter': (0.35, False, clip_cart_enter),
        'cart_drive': (1.0, True, lambda t: clip_cart_drive(t, 0.0)),
        # steer follows the sim's sign: +1 = turning right
        'cart_steer_l': (1.0, True, lambda t: clip_cart_drive(t, -1.0)),
        'cart_steer_r': (1.0, True, lambda t: clip_cart_drive(t, 1.0)),
        'cart_exit': (0.35, False, clip_cart_exit),
        'celebrate': (1.0, True, clip_celebrate),
        'arrive': (0.9, False, clip_arrive),
    }
    for e, L in (('wave', 1.2), ('cheer', 1.2), ('laugh', 1.2), ('shrug', 1.4), ('dance', 1.25), ('point', 1.2)):
        lib['emote_' + e] = (L, True, (lambda name: (lambda t: emote(name, t)))(e))
    return lib
