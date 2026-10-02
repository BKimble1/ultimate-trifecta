"""Offline clip checks for the Trifecta runner (V5), run with Blender's bpy:

    tools/.cache/bpyenv/bin/python tools/character/clip_check.py [--json out.json]

For every clip in anims.library(), sampled at 60 Hz on the real rig
(build_character.build_armature + anims.Rig, the same evaluation the baker
uses), it reports:

  * head: deepest penetration (m) of the sleeves and mittens into the head
    shell (the head's own superellipsoid, rig._head_F, grown by the limb
    radius).  Overhead arms in a chibi rig go straight into the big head.
  * torso: deepest penetration of the mittens into the torso (rig.torso_r).
  * reach: the furthest ankle-to-hip distance of IK legs (> 0.44 m clamps:
    the foot cannot reach its target and slides).
  * step: the largest per-sample move of any joint (cm at 60 Hz) inside a
    clip, a check for pops baked into a clip itself.

Exit status is non-zero when a clip penetrates the head by more than 1 cm.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402,F401
from mathutils import Matrix, Vector  # noqa: E402

import anims  # noqa: E402
import build_character  # noqa: E402
import rig  # noqa: E402

ARM_POINTS = [  # (bone, fraction along the bone, limb radius)
    ('forearm', 0.0, 0.045), ('forearm', 0.5, 0.045), ('hand', 0.0, 0.045), ('hand', 0.6, 0.05),
    ('upper_arm', 0.6, 0.05),
]
JOINTS = ['hips', 'chest', 'head', 'forearm.L', 'forearm.R', 'hand.L', 'hand.R', 'shin.L', 'shin.R', 'foot.L', 'foot.R']


def armature_matrices(R, L):
    P = {}
    for n in R.order:
        b = R.bones[n]
        q, loc = L.get(n, [None, Vector()])
        Lm = Matrix.Translation(loc) @ (q.to_matrix().to_4x4() if q is not None else Matrix.Identity(4))
        if b.parent is None:
            P[n] = R.rest[n] @ Lm
        else:
            pn = b.parent.name
            P[n] = P[pn] @ R.rest[pn].inverted() @ R.rest[n] @ Lm
    return P


def bone_point(R, P, name, frac):
    b = R.bones[name]
    length = (b.tail_local - b.head_local).length
    return P[name] @ Vector((0.0, length * frac, 0.0))


def head_depth(p_rest, radius):
    """> 0 when a limb of `radius` centred at p_rest (head rest space) enters the head."""
    if rig._head_F(p_rest, radius) >= 1.0:
        return 0.0
    # depth: shrink the grown shell until the point is outside
    lo, hi = 0.0, radius + 0.25
    for _ in range(20):
        mid = (lo + hi) * 0.5
        if rig._head_F(p_rest, radius - mid) < 1.0:
            lo = mid
        else:
            hi = mid
    return lo


def torso_depth(p_rest, radius):
    r = rig.torso_r(p_rest.z)
    if r <= 0.0:
        return 0.0
    ry = r * rig.TORSO_RY
    dx = p_rest.x / (r + radius)
    dy = (p_rest.y - rig.TORSO_CY) / (ry + radius)
    d = math.sqrt(dx * dx + dy * dy)
    return max(0.0, (1.0 - d) * (r + radius)) if d < 1.0 else 0.0


def check(fps=60):
    scn = build_character.reset()
    arm_ob = build_character.build_armature(scn)
    R = anims.Rig(arm_ob)
    head_inv = R.rest['head']
    out = {}
    for name, (length, loop, fn) in anims.library().items():
        n = max(2, int(round(length * fps)))
        worst_head = (0.0, 0.0, '')
        worst_torso = (0.0, 0.0, '')
        worst_step = (0.0, 0.0, '')
        reach = 0.0
        prev = None
        for f in range(n + 1):
            t = min(length, f / fps)
            pose = fn(t)
            L = R.evaluate(pose)
            P = armature_matrices(R, L)
            to_head = head_inv @ P['head'].inverted()
            to_chest = R.rest['chest'] @ P['chest'].inverted()
            for side in ('.L', '.R'):
                for bone, frac, rad in ARM_POINTS:
                    p = bone_point(R, P, bone + side, frac)
                    d = head_depth(to_head @ p, rad)
                    if d > worst_head[0]:
                        worst_head = (d, t, bone + side)
                    if bone == 'hand':
                        dt_ = torso_depth(to_chest @ p, rad)
                        if dt_ > worst_torso[0]:
                            worst_torso = (dt_, t, bone + side)
                if 'ik' in pose.get('foot' + side, {}):
                    hipj = P['thigh' + side].translation
                    ank = P['foot' + side].translation
                    tgt = pose['foot' + side]['ik'][0]
                    reach = max(reach, (Vector(tgt) - hipj).length)
            pts = {j: P[j].translation.copy() for j in JOINTS}
            if prev is not None:
                for j in JOINTS:
                    d = (pts[j] - prev[j]).length * 100.0
                    if d > worst_step[0]:
                        worst_step = (d, t, j)
            prev = pts
        out[name] = {
            'head_cm': round(worst_head[0] * 100, 1), 'head_at': round(worst_head[1], 3), 'head_part': worst_head[2],
            'torso_cm': round(worst_torso[0] * 100, 1), 'torso_part': worst_torso[2],
            'reach_m': round(reach, 3), 'step_cm': round(worst_step[0], 1), 'step_at': round(worst_step[1], 3),
            'step_joint': worst_step[2],
        }
    return out


def main():
    res = check()
    bad = 0
    print('%-16s %7s %-12s %8s %8s %8s' % ('clip', 'head cm', 'part', 'torso cm', 'reach m', 'step cm'))
    for k, v in res.items():
        flag = ' <' if v['head_cm'] > 1.0 else ''
        bad += 1 if v['head_cm'] > 1.0 else 0
        print('%-16s %7.1f %-12s %8.1f %8.3f %8.1f%s' % (k, v['head_cm'], v['head_part'], v['torso_cm'], v['reach_m'], v['step_cm'], flag))
    if '--json' in sys.argv:
        with open(sys.argv[sys.argv.index('--json') + 1], 'w') as f:
            json.dump(res, f, indent=1, sort_keys=True)
    print('clips with the arms > 1 cm inside the head:', bad)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
