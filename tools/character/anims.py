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
LOCO = {
    # name: speed = metres per 1.0 s cycle (so playback rate = ground speed / speed),
    #       duty = stance fraction per foot, lift (m), hip drop (m), lean (deg, spine),
    #       arm swing (deg), elbow (deg), bob (m).  speed * duty is the planted-foot
    #       sweep; with 0.44 m legs it must stay reachable (see README_character.md).
    'walk': dict(speed=0.8, duty=0.58, lift=0.05, drop=0.08, lean=-6.0, arm=18.0, elbow=35.0, bob=0.012, sneak=True),
    'run': dict(speed=1.7, duty=0.24, lift=0.11, drop=0.06, lean=-12.0, arm=48.0, elbow=80.0, bob=0.02, sneak=False),
    'sprint': dict(speed=2.05, duty=0.205, lift=0.14, drop=0.07, lean=-20.0, arm=62.0, elbow=95.0, bob=0.022, sneak=False),
}

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
        for key in ('ik',):
            if key in va or key in vb:
                nv[key] = vb.get(key, va.get(key)) if t > 0.5 else va.get(key, vb.get(key))
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
    pose = {}
    # hips: bob twice per cycle (lowest at each mid-stance)
    bob = -c['drop'] - c['bob'] * math.cos(4 * math.pi * phase)
    if c['sneak']:
        bob = -c['drop'] + c['bob'] * math.cos(4 * math.pi * phase)
    twist = 6.0 * math.sin(2 * math.pi * phase) * (0.5 if c['sneak'] else 1.0)
    pose['hips'] = {'loc': (0, 0, bob), 'rot': (c['lean'] * 0.25, 0, twist)}
    pose['spine'] = {'rot': (c['lean'] * 0.55, 0, -twist * 0.9)}
    pose['chest'] = {'rot': (c['lean'] * 0.3, 0, -twist * 0.8)}
    pose['neck'] = {'rot': (-c['lean'] * 0.5, 0, twist * 0.3)}
    pose['head'] = {'rot': (-c['lean'] * 0.45 + (4 if c['sneak'] else 0), 0, twist * 0.2)}
    for side, ph0 in ((-1, 0.0), (1, 0.5)):
        sfx = '.L' if side < 0 else '.R'
        ph = (phase + ph0 + duty * 0.5) % 1.0     # 0 = foot strike, duty = toe-off
        x = rig.HIP_X * side + (0.012 * side if not c['sneak'] else 0.03 * side)
        if ph < duty:
            u = ph / duty
            y = sweep * (0.5 - u)
            z = rig.ANKLE_Z
            pitch = 0.0 if u < 0.75 else -25.0 * smoothstep(0.75, 1.0, u)
        else:
            u = (ph - duty) / (1 - duty)
            e = u * u * (3 - 2 * u)
            y = -sweep * 0.5 + sweep * e
            # overshoot forward a touch mid-swing for a lively gait
            y += sweep * 0.12 * math.sin(math.pi * u)
            z = rig.ANKLE_Z + c['lift'] * math.sin(math.pi * u) ** 0.8
            pitch = lerp(-30.0, 12.0, smoothstep(0.0, 0.55, u)) * (1.0 - smoothstep(0.8, 1.0, u))
        # IK targets are in armature space; hips twist moves the hip joints,
        # ankles stay where the gait puts them (the solver reaches for them)
        pose['foot' + sfx] = {'ik': (Vector((x, y, z)), pitch)}
        # arms swing opposite to the legs
        sw = c['arm'] * math.sin(2 * math.pi * (phase + ph0 + 0.25))
        sw = -sw
        pose['upper_arm' + sfx] = {'rot': (sw, -12 * side if not c['sneak'] else -22 * side, 0)}
        pose['forearm' + sfx] = {'rot': (c['elbow'] + 0.25 * max(0.0, sw), 0, 0)}
        pose['hand' + sfx] = {'rot': (8, 0, 0)}
        pose['shoulder' + sfx] = {'rot': (0, 0, -3 * side * math.sin(2 * math.pi * (phase + ph0)))}
    if c['sneak']:
        # tiptoe sneak: arms up in front like a cartoon burglar
        for side in (-1, 1):
            sfx = '.L' if side < 0 else '.R'
            sw = 10 * math.sin(2 * math.pi * (phase + (0.0 if side < 0 else 0.5)))
            pose['upper_arm' + sfx] = {'rot': (55 + sw, -18 * side, 0)}
            pose['forearm' + sfx] = {'rot': (65, 0, 0)}
            pose['hand' + sfx] = {'rot': (-25, 0, 0)}
    return pose


# ------------------------------------------------------------------ clip library
def clip_idle(t):
    L = 2.4
    br = math.sin(2 * math.pi * t / L)
    sw = math.sin(2 * math.pi * t / L * 0.5)
    pose = stand(-0.006 + 0.006 * br)
    pose['spine'] = {'rot': (-1.0 * br, 0, 0)}
    pose['chest'] = {'rot': (-1.5 * br, 1.0 * sw, 0)}
    pose['head'] = {'rot': (1.5 * br, 2.0 * sw, 6 * math.sin(2 * math.pi * t / L * 0.5 + 0.7))}
    pose.update(sym({'upper_arm.L': {'rot': (3 + 1.5 * br, -12 - 1.5 * br, 0)}, 'forearm.L': {'rot': (16 + 2 * br, 0, 0)},
                     'shoulder.L': {'rot': (0, 1.0 * br, 0)}}))
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


def clip_jump(t):
    u = smoothstep(0.0, 0.3, t)
    tuck = sym({'upper_arm.L': {'rot': (lerp(-20, 30, u), lerp(20, 70, u), 0)}, 'forearm.L': {'rot': (lerp(30, 40, u), 0, 0)},
                'thigh.L': {'rot': (lerp(10, 55, u), 0, 0)}, 'shin.L': {'rot': (lerp(-20, -80, u), 0, 0)},
                'foot.L': {'rot': (lerp(-30, -15, u), 0, 0)}})
    tuck['thigh.R']['rot'] = (lerp(10, 25, u), 0, 0)
    tuck['shin.R']['rot'] = (lerp(-20, -45, u), 0, 0)
    tuck['spine'] = {'rot': (lerp(-10, 4, u), 0, 0)}
    tuck['head'] = {'rot': (lerp(-5, 8, u), 0, 0)}
    tuck['hips'] = {'loc': (0, 0, 0.02)}
    return tuck


def clip_fall(t):
    L = 0.8
    w = math.sin(2 * math.pi * t / L)
    p = sym({'upper_arm.L': {'rot': (10 + 25 * w, 95, 0)}, 'forearm.L': {'rot': (20 + 15 * w, 0, 0)},
             'thigh.L': {'rot': (30 + 20 * w, 0, 0)}, 'shin.L': {'rot': (-35 - 15 * w, 0, 0)}, 'foot.L': {'rot': (-15, 0, 0)}})
    p['upper_arm.R']['rot'] = (10 - 25 * w, -95, 0)
    p['thigh.R']['rot'] = (30 - 20 * w, 0, 0)
    p['shin.R']['rot'] = (-35 + 15 * w, 0, 0)
    p['spine'] = {'rot': (4, 0, 3 * w)}
    p['head'] = {'rot': (8, 0, -3 * w)}
    p['hips'] = {'loc': (0, 0, 0.02)}
    return p


def clip_land(t):
    u = t / 0.28
    squash = math.sin(math.pi * min(1.0, u * 1.4)) * (1.0 - smoothstep(0.6, 1.0, u))
    pose = stand(-0.11 * squash, 0.015 * squash)
    pose['spine'] = {'rot': (-14 * squash, 0, 0)}
    pose['head'] = {'rot': (10 * squash, 0, 0)}
    pose.update(sym({'upper_arm.L': {'rot': (25 * squash, -14 + 45 * squash, 0)}, 'forearm.L': {'rot': (16 + 25 * squash, 0, 0)}}))
    return pose


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


def clip_splash(t):
    # 1.5 s: hop in, flail with arms up while bobbing, then kick back up
    u = t / 1.5
    dip = smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.75, 1.0, u))
    w = math.sin(t * 14.0)
    p = sym({'upper_arm.L': {'rot': (20 + 30 * w, 112 - 18 * w, 0)}, 'forearm.L': {'rot': (35 + 20 * w, 0, 0)},
             'thigh.L': {'rot': (35 + 25 * w, -8, 0)}, 'shin.L': {'rot': (-60 - 20 * w, 0, 0)}, 'foot.L': {'rot': (-20, 0, 0)}})
    p['upper_arm.R']['rot'] = (20 - 30 * w, -112 + 18 * w, 0)
    p['forearm.R']['rot'] = (35 - 20 * w, 0, 0)
    p['thigh.R']['rot'] = (35 - 25 * w, 8, 0)
    p['shin.R']['rot'] = (-60 + 20 * w, 0, 0)
    p['hips'] = {'loc': (0, 0, -0.62 * dip + 0.03 * math.sin(t * 9)), 'rot': (0, 6 * math.sin(t * 7), 0)}
    p['head'] = {'rot': (12, 0, 8 * math.sin(t * 11))}
    return p


def clip_recover(t):
    # shake off the water at the shore: fast body shake that settles
    u = t / 0.6
    k = (1.0 - u) ** 1.5
    s = math.sin(t * 38.0) * k
    pose = stand(-0.03 * k)
    pose['hips']['rot'] = (0, 4 * s, 0)
    pose['spine'] = {'rot': (0, 9 * s, 0)}
    pose['chest'] = {'rot': (0, 9 * s, 0)}
    pose['head'] = {'rot': (0, -14 * s, 0)}
    pose.update(sym({'upper_arm.L': {'rot': (10, 45 + 15 * s, 0)}, 'forearm.L': {'rot': (20 + 20 * s, 0, 0)}}))
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
    u = smoothstep(0.0, 0.14, t)
    p = stand(-0.07 * u, 0.02, (0.06 * u, -0.08 * u))
    p['spine'] = {'rot': (8 * u, 0, -10 * u)}
    p['chest'] = {'rot': (4 * u, 0, -8 * u)}
    p.update(sym({'upper_arm.L': {'rot': (-30 * u, 35 * u - 12, 0)}, 'forearm.L': {'rot': (70 * u + 10, 0, 0)}}))
    return p


def clip_tag_lunge(t):
    u = smoothstep(0.0, 0.1, t)
    p = stand(-0.1 * u, 0.02, (0.2 * u, -0.12 * u))
    p['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0.22 * u, 0.0)), 0.0)}
    p['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0, -0.16 * u, 0.02 * u)), -30 * u)}
    p['hips']['rot'] = (-12 * u, 0, 0)
    p['spine'] = {'rot': (-20 * u, 0, 0)}
    p['head'] = {'rot': (18 * u, 0, 0)}
    p.update(sym({'upper_arm.L': {'rot': (lerp(-30, 95, u), -8, 0)}, 'forearm.L': {'rot': (lerp(70, 5, u), 0, 0)},
                  'hand.L': {'rot': (-10, 0, 0)}}))
    return p


def clip_tag_recover(t):
    u = smoothstep(0.0, 0.5, t)
    return blend_pose(clip_tag_lunge(0.22), clip_idle(0.0), u)


# steering wheel, relative to the character origin (Blender axes: x right,
# y forward, z up).  CartView places its wheel at the same spot (Godot:
# SEAT + (0, 0.50, -0.27)) and turns it by steer * STEER_DEG.
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
    u = smoothstep(0.0, 0.35, t)
    hop = math.sin(math.pi * u) * 0.12
    p = blend_pose(clip_idle(0.0), _seated(0.0), u)
    p['hips']['loc'] = (0, lerp(0.0, -0.06, u), lerp(0.0, -0.33, u) + hop)
    return p


def clip_cart_exit(t):
    u = smoothstep(0.0, 0.35, t)
    hop = math.sin(math.pi * u) * 0.14
    p = blend_pose(_seated(0.0), clip_idle(0.0), u)
    p['hips']['loc'] = (0, lerp(-0.06, 0.0, u), lerp(-0.33, 0.0, u) + hop)
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
    p.update(sym({'upper_arm.L': {'rot': (6, 118 - 10 * pump, 0)}, 'forearm.L': {'rot': (25 + 20 * pump, 0, 0)}}))
    p['head'] = {'rot': (12, 0, 6 * pump)}
    p['spine'] = {'rot': (6, 0, 0)}
    return p


def emote(name, t):
    pose = clip_idle(t)
    if name == 'wave':
        w = math.sin(t * 13.0)
        pose['upper_arm.R'] = {'rot': (8, -118, 0)}
        pose['forearm.R'] = {'rot': (0, 0, 0)}
        pose['forearm.R'] = {'rot': (10, 30 + 30 * w, 0)}
        pose['head']['rot'] = (6, 0, -6)
        pose['chest'] = {'rot': (0, 4, 0)}
    elif name == 'cheer':
        b = abs(math.sin(t * 7.0))
        pose = stand(0.0)
        if b > 0.5:
            pass
        pose['hips'] = {'loc': (0, 0, -0.05 + 0.1 * b)}
        pose['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0, max(0.0, 0.1 * b - 0.05))), 0.0)}
        pose['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0, 0, max(0.0, 0.1 * b - 0.05))), 0.0)}
        pose.update(sym({'upper_arm.L': {'rot': (4, 122, 0)}, 'forearm.L': {'rot': (10 + 20 * b, 0, 0)}}))
        pose['head'] = {'rot': (14, 0, 0)}
    elif name == 'laugh':
        s = math.sin(t * 20.0)
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
        pose.update(sym({'upper_arm.L': {'rot': (40 + 40 * s, 70, 0)}, 'forearm.L': {'rot': (80, 0, 0)}}))
        pose['upper_arm.R'] = {'rot': (40 - 40 * s, -70, 0)}
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
        lift = max(0.0, h - 0.02)
        p['foot.L'] = {'ik': (REST_ANKLE[-1] + Vector((0, 0, lift)), -20)}
        p['foot.R'] = {'ik': (REST_ANKLE[1] + Vector((0, 0, lift)), -20)}
        p.update(sym({'upper_arm.L': {'rot': (10, 110 * math.sin(math.pi * u) - 14, 0)}, 'forearm.L': {'rot': (20, 0, 0)}}))
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
        'idle': (2.4, True, clip_idle),
        'walk': (1.0, True, lambda t: loco_pose('walk', t)),
        'run': (1.0, True, lambda t: loco_pose('run', t)),
        'sprint': (1.0, True, lambda t: loco_pose('sprint', t)),
        'turn_l': (0.4, False, lambda t: clip_turn(t, 1)),
        'turn_r': (0.4, False, lambda t: clip_turn(t, -1)),
        'jump': (0.3, False, clip_jump),
        'fall': (0.8, True, clip_fall),
        'land': (0.28, False, clip_land),
        'dive': (0.6, False, clip_dive),
        'dive_land': (0.32, False, clip_dive_land),
        'splash': (1.5, False, clip_splash),
        'recover': (0.6, False, clip_recover),
        'stumble': (0.55, False, clip_stumble),
        'flop': (0.9, False, clip_flop),
        'dizzy': (2.0, True, clip_dizzy),
        'tag_windup': (0.14, False, clip_tag_windup),
        'tag_lunge': (0.22, False, clip_tag_lunge),
        'tag_recover': (0.5, False, clip_tag_recover),
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
