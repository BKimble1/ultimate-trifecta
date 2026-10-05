"""Pass 8: containment checks for the rotating Shop outfits (outfits_p8.py),
run with Blender's bpy on the real rig, every clip at 60 Hz:

    tools/.cache/bpyenv/bin/python tools/character/outfit_check.py [--json out.json]

The outfits' risky pieces are rigid on one bone (hoods, ears, caps, visor,
stem and cloud puffs on the head; the raccoon tail on the hips; the cadet's
life-support pack sits on the chest), so each is checked in its bone's rest
space against the moving limbs, sampled as spheres along the bones with the
radius of that outfit's sleeves, gloves and trouser legs:

  * head pieces: arm spheres against every head-rigid vertex of the outfit's
    parts (KD-tree; ears, visor, ear discs, puffs, stem), and against the
    outfit's head shell (the head surface grown to the hood or cap, above its
    edge; a hood's face opening is open) -- the arms entering a hood.
  * tail: the tail as a chain of capsules (outfits_p8.TAIL and its radii)
    against arm and leg capsules; and its lowest point above the ground
    (splash clips are skipped: they sink the body into water).
  * pack: arm spheres against the cadet pack's superellipsoid (rigid on the
    chest, an approximation of its torso skinning).
  * gloves (rest pose): every mitten vertex of the base mesh lies inside its
    glove (nearest glove face, outward normal), so no skin pokes through.

Exit status is non-zero when any piece is entered by more than 1 cm, the
tail goes more than 1 cm into the ground, or a mitten pokes through a glove.
The integrator's clip changes (anims.py) need this re-run after a merge.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402,F401
from mathutils import Vector, kdtree  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import anims  # noqa: E402
import build_character  # noqa: E402
import clip_check  # noqa: E402
import outfits_p8 as O  # noqa: E402
import outfits_v6  # noqa: E402
import parts  # noqa: E402
import rig  # noqa: E402

LIMIT = 0.01
# A hood is worn over the whole head, and some clips bring the hands to the
# head (the splash shake-off, wave, dance, victory lap, shush, a stumble):
# the sleeves meet a hood there.  The shipped hoods (REFERENCE) are met the
# same way, so a Pass 8 hood may not be entered more than they are, plus
# these margins (cm); every other piece keeps the 1 cm limit.
HOOD_SHELL_MARGIN = 0.5
HOOD_FEATURE_MARGIN = 1.0
# per outfit: its parts, sleeve and trouser grow, glove grow (None: bare
# mittens), the head shell (grow, lowest z at the back, hood face opening),
# and its tail / pack
OUTFITS = {
    'midnight_mechanic': {'parts': ['mechanic'], 'sleeve': 0.018, 'legs': 0.02, 'glove': 0.0045},
    'moonwalk_cadet': {'parts': ['cadet', 'acc_cadet_cap'], 'sleeve': 0.03, 'legs': 0.03, 'glove': 0.0045,
                       'shell': (0.046, 1.205, None), 'pack': True},
    'pumpkin_pajamas': {'parts': ['pumpkin', 'acc_pumpkin_cap'], 'sleeve': 0.019, 'legs': 0.026, 'glove': None,
                        'shell': (0.056, 1.215, None)},
    'arcade_sprinter': {'parts': ['arcade'], 'sleeve': 0.017, 'legs': 0.0, 'glove': None},
    'cloud_nine': {'parts': ['cloud'], 'sleeve': 0.03, 'legs': 0.03, 'glove': None, 'shell': (0.035, 0.95, O.HOOD_OPEN), 'hood': True},
    'bedtime_bandit': {'parts': ['bandit'], 'sleeve': 0.03, 'legs': 0.03, 'glove': None, 'shell': (0.035, 0.95, O.HOOD_OPEN),
                       'tail': True, 'hood': True},
}
# the hood outfits that shipped before Pass 8 (same rig, same clips): a
# baseline reported next to the new ones, never a failure
REFERENCE = {
    'night_owl (V6)': {'build': [outfits_v6.build_owl], 'sleeve': 0.03, 'legs': 0.03, 'glove': None, 'shell': (0.035, 0.95, (0.228, 0.19, 1.145))},
    'duck (V2)': {'build': [parts.build_duck], 'sleeve': 0.03, 'legs': 0.03, 'glove': None, 'shell': (0.035, 0.95, (0.228, 0.19, 1.145))},
}
BUILDERS = {'mechanic': O.build_mechanic, 'cadet': O.build_cadet, 'acc_cadet_cap': O.build_cadet_cap, 'pumpkin': O.build_pumpkin,
            'acc_pumpkin_cap': O.build_pumpkin_cap, 'arcade': O.build_arcade, 'cloud': O.build_cloud, 'bandit': O.build_bandit}


def arm_spheres(R, P, side, sleeve, glove):
    """(point, radius) along the arm: sleeve over the upper arm and forearm, the mitten (or glove)."""
    out = []
    for bone, fracs in (('upper_arm', (0.35, 0.7, 1.0)), ('forearm', (0.0, 0.5, 1.0))):
        for f in fracs:
            s = (0.0 if bone == 'upper_arm' else rig.UPPER_LEN) + f * (rig.UPPER_LEN if bone == 'upper_arm' else rig.FORE_LEN)
            out.append((clip_check.bone_point(R, P, bone + side, f), parts.arm_radius(s) + sleeve))
    for f in (0.3, 0.7):
        out.append((clip_check.bone_point(R, P, 'hand' + side, f), 0.045 + (glove or 0.0)))
    return out


def limb_capsules(R, P, side, cfg):
    """Armature-space capsules (a, b, radius) of the arm and the leg on one side."""
    caps = []
    for bone, r in (('upper_arm', parts.arm_radius(0.08) + cfg['sleeve']), ('forearm', parts.arm_radius(0.25) + cfg['sleeve']),
                    ('hand', 0.045 + (cfg['glove'] or 0.0)), ('thigh', parts.leg_radius(0.1) + cfg['legs']),
                    ('shin', parts.leg_radius(0.3) + cfg['legs'])):
        caps.append((bone + side, clip_check.bone_point(R, P, bone + side, 0.0), clip_check.bone_point(R, P, bone + side, 1.0), r))
    return caps


def seg_seg(p1, q1, p2, q2):
    """Closest distance between segments p1q1 and p2q2."""
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = d1.dot(d1), d2.dot(d2), d2.dot(r)
    if a <= 1e-12 and e <= 1e-12:
        return r.length
    if a <= 1e-12:
        s, t = 0.0, max(0.0, min(1.0, f / e))
    else:
        c = d1.dot(r)
        if e <= 1e-12:
            t, s = 0.0, max(0.0, min(1.0, -c / a))
        else:
            b = d1.dot(d2)
            den = a * e - b * b
            s = max(0.0, min(1.0, (b * f - c * e) / den)) if den > 1e-12 else 0.0
            t = (b * s + f) / e
            if t < 0.0:
                t, s = 0.0, max(0.0, min(1.0, -c / a))
            elif t > 1.0:
                t, s = 1.0, max(0.0, min(1.0, (b - c) / a))
    return ((p1 + d1 * s) - (p2 + d2 * t)).length


def tail_chain():
    path = parts._smooth_path(O.TAIL, 0.014)
    radii = O.tail_radii(path)
    return list(zip(path, radii))


def head_vertices(cfg):
    pts = []
    for build in cfg.get('build') or [BUILDERS[n] for n in cfg['parts']]:
        mb = build()
        for i, w in enumerate(mb.w):
            if w.get('head', 0.0) >= 0.999:
                pts.append(mb.v[i].copy())
    kd = kdtree.KDTree(max(1, len(pts)))
    for i, p in enumerate(pts):
        kd.insert(p, i)
    kd.balance()
    return kd, len(pts)


def in_face_opening(p, opening):
    ox, oz, oc = opening
    return p.y > 0.0 and (p.x / ox) ** 2 + ((p.z - oc) / oz) ** 2 < 1.0


def shell_depth(p, r, shell):
    grow, z_min, hood = shell
    if p.z < z_min or (hood and in_face_opening(p, hood)):
        return 0.0
    return clip_check.head_depth(p, r + grow)


def pack_depth(p, r):
    c = O.PACK_C
    ax = [O.PACK_R[i] + r for i in range(3)]
    q = [(p[i] - c[i]) / ax[i] for i in range(3)]
    n = (abs(q[0]) ** O.PACK_P + abs(q[1]) ** O.PACK_P + abs(q[2]) ** O.PACK_P) ** (1.0 / O.PACK_P)
    return max(0.0, (1.0 - n) * min(ax)) if n < 1.0 else 0.0


def glove_check():
    """Mitten vertices of the base mesh (both hands) inside the glove shells."""
    base = parts.build_base()
    out = {}
    for name, build in (('mechanic', O.build_mechanic), ('cadet', O.build_cadet)):
        mb = build()
        # the gloves' faces only (vertices weighted to a hand or forearm near the wrist)
        idx = set()
        for i, w in enumerate(mb.w):
            if any(k.startswith('hand') for k in w) or any(k.startswith('forearm') for k in w) and min(
                    (mb.v[i] - rig.wrist(s)).length for s in (-1, 1)) < 0.12:
                idx.add(i)
        faces = [f for f in mb.f if all(v in idx for v in f)]
        # one BVH per connected piece (palm, thumb, cuff, roll): the pieces
        # overlap (the thumb starts inside the palm), so a vertex is covered
        # when it is inside any one of them
        parent = {}

        def find(a):
            while parent.setdefault(a, a) != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a
        for f in faces:
            for v in f[1:]:
                parent[find(v)] = find(f[0])
        groups = {}
        for f in faces:
            for k in range(1, len(f) - 1):
                groups.setdefault(find(f[0]), []).append((f[0], f[k], f[k + 1]))
        verts = [tuple(v) for v in mb.v]
        bvhs = [BVHTree.FromPolygons(verts, tris) for tris in groups.values()]
        worst = 0.0
        n = 0
        for i, w in enumerate(base.w):
            if not any(k.startswith('hand') for k in w) or w.get('head', 0.0) > 0:
                continue
            p = base.v[i]
            if min((p - rig.wrist(s)).length for s in (-1, 1)) > 0.13:
                continue
            n += 1
            gap = 9.0
            for bvh in bvhs:
                loc, nrm, fi, d = bvh.find_nearest(p)
                if loc is None:
                    continue
                if (p - loc).dot(nrm) <= 0.0:
                    gap = 0.0
                    break
                gap = min(gap, d)
            if gap < 9.0:
                worst = max(worst, gap)
        out[name] = {'mitten_vertices': n, 'outside_glove_mm': round(worst * 1000, 2)}
    return out


def check(fps=60):
    scn = build_character.reset()
    arm_ob = build_character.build_armature(scn)
    R = anims.Rig(arm_ob)
    rest_head, rest_hips, rest_chest = R.rest['head'], R.rest['hips'], R.rest['chest']
    every = dict(OUTFITS)
    every.update(REFERENCE)
    kds = {k: head_vertices(c) for k, c in every.items()}
    tail = tail_chain()
    res = {k: {} for k in every}
    for name, (length, loop, fn) in anims.library().items():
        n = max(2, int(round(length * fps)))
        worst = {k: {'head': (0.0, ''), 'shell': (0.0, ''), 'tail': (0.0, ''), 'ground': 9.0, 'pack': (0.0, '')} for k in every}
        for f in range(n + 1):
            t = min(length, f / fps)
            P = clip_check.armature_matrices(R, R.evaluate(fn(t)))
            to_head = rest_head @ P['head'].inverted()
            to_hips = rest_hips @ P['hips'].inverted()
            to_chest = rest_chest @ P['chest'].inverted()
            hips_world = P['hips'] @ rest_hips.inverted()
            for k, cfg in every.items():
                w = worst[k]
                kd, nv = kds[k]
                for side in ('.L', '.R'):
                    for p, r in arm_spheres(R, P, side, cfg['sleeve'], cfg['glove']):
                        ph = to_head @ p
                        if nv:
                            _, _, d = kd.find(ph)
                            if r - d > w['head'][0]:
                                w['head'] = (r - d, '%s %.2f' % (side, t))
                        if 'shell' in cfg:
                            dd = shell_depth(ph, r, cfg['shell'])
                            if dd > w['shell'][0]:
                                w['shell'] = (dd, '%s %.2f' % (side, t))
                        if cfg.get('pack'):
                            dp = pack_depth(to_chest @ p, r)
                            if dp > w['pack'][0]:
                                w['pack'] = (dp, '%s %.2f' % (side, t))
                if cfg.get('tail'):
                    caps = []
                    for side in ('.L', '.R'):
                        caps += limb_capsules(R, P, side, cfg)
                    for bone, a, b, r in caps:
                        a2, b2 = to_hips @ a, to_hips @ b
                        for (p0, r0), (p1, r1) in zip(tail, tail[1:]):
                            dd = r + max(r0, r1) - seg_seg(p0, p1, a2, b2)
                            if dd > w['tail'][0]:
                                w['tail'] = (dd, '%s %.2f' % (bone, t))
                    for p0, r0 in tail:
                        w['ground'] = min(w['ground'], (hips_world @ p0).z - r0)
        for k in every:
            w = worst[k]
            row = {'head_features_cm': round(w['head'][0] * 100, 1), 'head_at': w['head'][1],
                   'head_shell_cm': round(w['shell'][0] * 100, 1), 'shell_at': w['shell'][1]}
            if every[k].get('pack'):
                row['pack_cm'] = round(w['pack'][0] * 100, 1)
                row['pack_at'] = w['pack'][1]
            if every[k].get('tail'):
                row['tail_cm'] = round(w['tail'][0] * 100, 1)
                row['tail_at'] = w['tail'][1]
                row['tail_ground_cm'] = round(w['ground'] * 100, 1)
            res[k][name] = row
    return res


def main():
    res = check()
    bad = []
    for k, clips in res.items():
        print('==', k)
        for name, v in clips.items():
            lim = {m: LIMIT * 100 for m in ('head_features_cm', 'head_shell_cm', 'pack_cm', 'tail_cm')}
            if OUTFITS.get(k, {}).get('hood'):
                lim['head_shell_cm'] = max(lim['head_shell_cm'], max(res[r][name]['head_shell_cm'] for r in REFERENCE) + HOOD_SHELL_MARGIN)
                lim['head_features_cm'] = max(lim['head_features_cm'],
                                              max(res[r][name]['head_features_cm'] for r in REFERENCE) + HOOD_FEATURE_MARGIN)
            over = [m for m in lim if v.get(m, 0.0) > lim[m] + 1e-6]
            if 'tail_ground_cm' in v and v['tail_ground_cm'] < -LIMIT * 100 and not name.startswith('splash'):
                over.append('tail_ground_cm')
            flag = ' <' if over else ''
            if over and k in OUTFITS:
                bad.append('%s %s %s' % (k, name, ','.join(over)))
            print('  %-18s %s%s' % (name, ' '.join('%s=%s' % kv for kv in v.items()), flag))
    gl = glove_check()
    print('gloves', gl)
    for k, v in gl.items():
        if v['outside_glove_mm'] > 0.5:
            bad.append('%s glove: mitten %.1f mm outside' % (k, v['outside_glove_mm']))
    # Pass 9: the complete skins (skins_p9.py): their layers, attachments and
    # heads against the arms, through every clip (skins_check.py)
    import skins_check
    sk = skins_check.check()
    sk_bad = skins_check.failures(sk)
    print('complete skins (skins_check.py):', len(sk_bad), 'failures')
    bad += ['complete skin: ' + b for b in sk_bad]
    if '--json' in sys.argv:
        with open(sys.argv[sys.argv.index('--json') + 1], 'w') as f:
            json.dump({'clips': res, 'gloves': gl, 'limit_cm': LIMIT * 100, 'failures': bad}, f, indent=1, sort_keys=True)
    print('failures:', len(bad))
    for b in bad:
        print('  ', b)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
