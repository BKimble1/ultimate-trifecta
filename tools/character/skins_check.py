"""Pass 9: fit and containment checks for the complete skins (skins_p9.py),
run with Blender's bpy on the real rig, every clip:

    tools/.cache/bpyenv/bin/python tools/character/skins_check.py [--json out.json] [--fps 20]

The parts are deformed the way the game deforms them: linear blend skinning
with the generator's own weights, kept to the 4 strongest influences and
renormalised exactly as build_character.make_mesh exports them, by the
bone matrices of each clip sample (anims.Rig, the baker's own evaluation).
Every check compares real deformed vertices with real deformed faces:

  * layers: each inner-layer vertex is anchored at rest to the outer layer
    straight out from it (a ray along its normal, within 6 cm) and keeps that
    cover's own patch (its faces within 6 cm).  In every sample the inner
    vertex must stay under its patch: the signed distance to the patch's
    nearest deformed face (outward faces).  Reported: how far the worst
    vertex comes through (cm) and where.  Testing against the vertex's own
    cover, not the whole garment, keeps folds and openings elsewhere from
    confusing it.
      record_breaker  bare thighs and hips inside the shorts (seat, legs)
      dr_doom         the shirt inside the jacket where the jacket covers it;
                      the trousers' seat and thighs inside the jacket's skirt;
                      the hip crease (in front of each hip joint) on its own,
                      where a raised thigh folds both layers (a looser bound)
  * tie: the tie blade's distance from the shirt under it (it must neither
    lift away nor sink in: min and max over every sample).
  * attachments: the wristband, the sandals and every foot vertex keep their
    rest distance to the limb they sit on (they share its weights, so any
    drift is a weighting fault).
  * arms: the arms (sleeve or bare-arm radius, the mitten) against every
    head-rigid vertex of the skin's head and hair, through every clip
    (outfit_check.arm_spheres), next to the same arms against the stock head
    with the curly crop (the baseline: some clips bring the hands to the
    head on purpose).  A skin fails when it is entered more than the
    baseline plus 1 cm.

Exit status is non-zero on any failure.  outfit_check.py runs these too.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402,F401
from mathutils import Vector, kdtree, geometry  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import anims  # noqa: E402
import build_character  # noqa: E402
import clip_check  # noqa: E402
import outfit_check  # noqa: E402
import parts  # noqa: E402
import skins_p9 as S  # noqa: E402

LIMIT_CM = 1.0          # a layer may not come out of its cover by more than this
CREASE_CM = 4.5         # ... except in the hip crease's fold (reported separately; see docs/pass9/skins.md)
HEAD_MARGIN_CM = 1.0    # arms vs the skin's head pieces: at most baseline + this
# clips whose hand meets the face by design: the shush lays the mitten on
# the lips (anims.SHUSH_WRIST), so a face with a fuller nose and lips meets
# it a little sooner than the stock face does
CONTACT_MARGIN_CM = {'emote_shush': 1.5}
TIE_GAP_CM = (0.0, 1.6)  # the tie blade's distance from the shirt, every sample (a 0.5 mm graze tolerated)

# per skin: (inner group(s), outer group(s), rest-space filter for the inner vertices)
LAYERS = {
    'record_breaker': [
        ('skin inside the shorts', ['leg_skin.L', 'leg_skin.R', 'torso_skin'], ['shorts_seat', 'shorts_leg.L', 'shorts_leg.R'],
         lambda p: 0.425 <= p.z <= 0.580),
    ],
    'dr_doom': [
        ('shirt inside the jacket', ['shirt'], ['jacket_shell'],
         lambda p: 0.60 <= p.z <= 0.82 and _covered_by_jacket(p, 0.10)),
        ('trousers inside the jacket skirt', ['trousers_seat', 'trousers_leg.L', 'trousers_leg.R'], ['jacket_shell'],
         lambda p: 0.48 <= p.z <= 0.60 and _covered_by_jacket(p, 0.12) and not _hip_crease(p)),
        ('hip crease (jacket over trousers)', ['trousers_seat', 'trousers_leg.L', 'trousers_leg.R'], ['jacket_shell'],
         lambda p: 0.48 <= p.z <= 0.60 and _covered_by_jacket(p, 0.12) and _hip_crease(p)),
    ],
}
BUILD = {'record_breaker': S.build_rb_body, 'dr_doom': S.build_dd_suit}
HEADS = {'record_breaker': [S.build_rb_head, S.build_rb_hair], 'dr_doom': [S.build_dd_head, S.build_dd_fringe]}
ARMS = {'record_breaker': {'sleeve': -0.002, 'glove': None}, 'dr_doom': {'sleeve': 0.026, 'glove': None}}


def _hip_crease(p):
    """In front of a hip joint, where a raised thigh folds the body: linear
    blend skinning folds both layers there (same fabric over same fabric)."""
    return 0.46 <= p.z <= 0.585 and p.y > -0.04 and 0.05 <= abs(p.x) <= 0.26


def _covered_by_jacket(p, margin):
    """At rest, the jacket covers this point (outside its front opening by `margin` rad)."""
    th = math.atan2((p.y - S.TORSO_CY) / S.TORSO_RY, p.x)
    d = abs(((th - math.pi / 2) + math.pi) % (2 * math.pi) - math.pi)
    return d > S.jacket_gap(p.z) + margin


def lbs(mb):
    """Per-vertex [(bone, weight)]: the 4 strongest, renormalised (make_mesh)."""
    out = []
    for w in mb.w:
        items = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(v for _, v in items) or 1.0
        out.append([(b, v / tot) for b, v in items if v / tot >= 1e-3])
    return out


def skin_mats(R, P):
    return {b: P[b] @ R.rest[b].inverted() for b in R.order}


def deform(idx, verts, weights, M):
    out = {}
    for i in idx:
        p = verts[i]
        acc = Vector()
        for b, w in weights[i]:
            acc += (M[b] @ p) * w
        out[i] = acc
    return out


def components(faces):
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
        groups.setdefault(find(f[0]), []).append(f)
    return list(groups.values())


def group_idx(mb, names):
    out = set()
    for n in names:
        a, b = mb.groups[n]
        out.update(range(a, b))
    return out


REACH = 0.06   # how far out along its normal an inner vertex looks for its cover at rest


def vertex_normals(mb, idx):
    """Area-weighted normals of the vertices in idx from the faces among them."""
    acc = {i: Vector() for i in idx}
    for f in mb.f:
        if all(v in idx for v in f):
            for k in range(1, len(f) - 1):
                a, b, c = mb.v[f[0]], mb.v[f[k]], mb.v[f[k + 1]]
                n = (b - a).cross(c - a)
                for v in (f[0], f[k], f[k + 1]):
                    acc[v] += n
    return {i: (n.normalized() if n.length > 1e-12 else Vector((0, 0, 1))) for i, n in acc.items()}


LOCAL = 0.06   # the cover's own patch: its faces within this of the anchor at rest


def layer_setup(mb, inner, outer, keep):
    """Anchor each inner vertex to the outer layer straight out from it at
    rest (a ray along its normal, within REACH), and keep the patch of the
    outer layer round that anchor (faces within LOCAL).  Vertices whose
    cover is not there at rest (an opening) are not tested.
    Returns (anchors [(vertex, patch)], outer triangles, outer vertices)."""
    oi = group_idx(mb, outer)
    tris = []
    for f in mb.f:
        if all(v in oi for v in f):
            for k in range(1, len(f) - 1):
                tris.append((f[0], f[k], f[k + 1]))
    bvh = BVHTree.FromPolygons([tuple(v) for v in mb.v], tris)
    ii = sorted(i for i in group_idx(mb, inner) if keep(mb.v[i]))
    nrm = vertex_normals(mb, set(group_idx(mb, inner)))
    # the connected piece of each triangle (seat, a leg, the jacket shell):
    # a cover's patch stays on its own piece
    comp = {}
    for ci, piece in enumerate(components(tris)):
        for t in piece:
            comp[t] = ci
    cent = [(mb.v[a] + mb.v[b] + mb.v[c]) / 3.0 for a, b, c in tris]
    ckd = kdtree.KDTree(len(cent))
    for j, c in enumerate(cent):
        ckd.insert(c, j)
    ckd.balance()
    anchors = []
    for i in ii:
        loc, n, ti, d = bvh.ray_cast(mb.v[i] + nrm[i] * 0.0005, nrm[i], REACH)
        if loc is None:
            continue
        patch = {j for _, j, _ in ckd.find_range(loc, LOCAL) if comp[tris[j]] == comp[tris[ti]]}
        patch.add(ti)
        anchors.append((i, patch))
    used = sorted({v for t in tris for v in t})
    return anchors, tris, used


def layer_depth(anchors, tris, mb, dv):
    """Worst (depth m, vertex) of the inner vertices through their cover's
    patch in this pose: the signed distance to the nearest face of the
    patch (outward faces), > 0 = through."""
    verts = [tuple(dv.get(i, mb.v[i])) for i in range(len(mb.v))]
    bvh = BVHTree.FromPolygons(verts, tris)
    worst = (0.0, -1)
    for i, patch in anchors:
        p = dv[i]
        best = None
        for loc, n, ti, d in bvh.find_nearest_range(p, LOCAL + 0.04):
            if ti in patch and (best is None or d < best[0]):
                best = (d, (p - loc).dot(n))
        if best is not None and best[1] > worst[0]:
            worst = (best[1], i)
    return worst


def check(fps=20):
    scn = build_character.reset()
    arm_ob = build_character.build_armature(scn)
    R = anims.Rig(arm_ob)
    lib = anims.library()
    res = {'fps': fps, 'skins': {}}
    bodies = {k: f() for k, f in BUILD.items()}
    W = {k: lbs(mb) for k, mb in bodies.items()}
    setups = {k: [(name, layer_setup(bodies[k], inn, out, keep)) for name, inn, out, keep in LAYERS[k]] for k in LAYERS}
    res['anchors'] = {'%s: %s' % (k, name): len(a[0]) for k, lays in setups.items() for name, a in lays}
    # the tie blade and the shirt under it
    dd = bodies['dr_doom']
    tie_i = sorted(group_idx(dd, ['tie_blade']))
    shirt_i = group_idx(dd, ['shirt'])
    shirt_f = [f for f in dd.f if all(v in shirt_i for v in f)]
    shirt_used = sorted({v for f in shirt_f for v in f})
    # attachments: wristband, sandals/shoes, toes: their rest distance to the limb skin they ride on
    rb = bodies['record_breaker']
    band = [i for i in range(len(rb.v)) if rb.col[i][:3] == S.WRISTBAND.col]
    arm_skin = [i for i in range(len(rb.v)) if any(b.startswith('forearm') for b, _ in W['record_breaker'][i]) and rb.col[i][3] == S.T_SKIN]
    sandal = [i for i in range(len(rb.v)) if rb.col[i][:3] in (S.SANDAL_STRAP.col, S.SANDAL_BED.col, S.SANDAL_SOLE.col)]
    foot_skin = [i for i in range(len(rb.v)) if rb.v[i].z < 0.07 and rb.col[i][3] == S.T_SKIN]
    att = {'wristband': (band, arm_skin), 'sandals': (sandal, foot_skin)}
    att_rest = {}
    for name, (a, b) in att.items():
        kd = kdtree.KDTree(len(b))
        for j, i in enumerate(b):
            kd.insert(rb.v[i], j)
        kd.balance()
        att_rest[name] = [(i, b[kd.find(rb.v[i])[1]]) for i in a]
    # arms against the head pieces (and the stock baseline): the nearest point
    # of their real surfaces (a BVH of the head-rigid faces, so the result
    # does not depend on how finely each piece is tessellated)
    def head_faces(mbs):
        verts, polys = [], []
        for mb in mbs:
            base_i = len(verts)
            verts += [tuple(v) for v in mb.v]
            for f in mb.f:
                if all(mb.w[v].get('head', 0.0) >= 0.5 for v in f):
                    polys.append(tuple(base_i + v for v in f))
        return BVHTree.FromPolygons(verts, polys)
    kds = {}
    for k, fns in HEADS.items():
        kds[k] = head_faces([fn() for fn in fns])
    stock = head_faces([parts.build_base(), parts.build_hair_curly()])
    for k in HEADS:
        kds[k + ' baseline'] = stock
    # the baseline: the stock head with the curly crop, met by the same arms
    arms = dict(ARMS)
    for k in HEADS:
        arms[k + ' baseline'] = ARMS[k]
    for k in list(LAYERS) + ['tie', 'attach', 'arms']:
        res['skins'].setdefault(k, {})
    clips = {}
    for cname, (length, loop, fn) in lib.items():
        n = max(2, int(round(length * fps)))
        row = {}
        worst = {}
        tie_lo, tie_hi = 9.0, 0.0
        att_worst = {name: 0.0 for name in att}
        arm_worst = {k: (0.0, '') for k in kds}
        for f in range(n + 1):
            t = min(length, f / fps)
            P = clip_check.armature_matrices(R, R.evaluate(fn(t)))
            M = skin_mats(R, P)
            for k, lays in setups.items():
                mb = bodies[k]
                for name, (anchors, tris, used) in lays:
                    dv = deform(set(used) | {i for i, _ in anchors}, mb.v, W[k], M)
                    w, i = layer_depth(anchors, tris, mb, dv)
                    if w > worst.get((k, name), (0.0, ''))[0]:
                        worst[(k, name)] = (w, 'rest z %.2f x %.2f y %.2f at %.2f s' % (mb.v[i].z, mb.v[i].x, mb.v[i].y, t))
            # the tie on the shirt
            dvs = deform(set(tie_i) | set(shirt_used), dd.v, W['dr_doom'], M)
            remap = {v: j for j, v in enumerate(shirt_used)}
            bvh = BVHTree.FromPolygons([tuple(dvs[v]) for v in shirt_used], [tuple(remap[v] for v in fc) for fc in shirt_f])
            for i in tie_i:
                loc, nrm, fi, d = bvh.find_nearest(dvs[i])
                if loc is None or d > 0.05:
                    continue
                s = (dvs[i] - loc).dot(nrm)
                tie_lo, tie_hi = min(tie_lo, s), max(tie_hi, s)
            # attachments
            for name, pairs in att_rest.items():
                ids = {i for pr in pairs for i in pr}
                dv = deform(ids, rb.v, W['record_breaker'], M)
                for a, b in pairs:
                    drift = abs((dv[a] - dv[b]).length - (rb.v[a] - rb.v[b]).length)
                    att_worst[name] = max(att_worst[name], drift)
            # arms against the heads
            to_head = R.rest['head'] @ P['head'].inverted()
            for k, kd in kds.items():
                cfg = arms[k]
                for side in ('.L', '.R'):
                    for p, r in outfit_check.arm_spheres(R, P, side, cfg['sleeve'], cfg['glove']):
                        loc, _, _, d = kd.find_nearest(to_head @ p)
                        if loc is None:
                            continue
                        if r - d > arm_worst[k][0]:
                            arm_worst[k] = (r - d, '%s %.2f s' % (side, t))
        for (k, name), (w, at) in worst.items():
            row['%s: %s' % (k, name)] = {'out_cm': round(w * 100, 2), 'at': at}
        for k, lays in setups.items():
            for name, *_ in lays:
                row.setdefault('%s: %s' % (k, name), {'out_cm': 0.0, 'at': ''})
        row['dr_doom: tie gap cm'] = [round(tie_lo * 100, 2), round(tie_hi * 100, 2)]
        for name, v in att_worst.items():
            row['record_breaker: %s drift cm' % name] = round(v * 100, 3)
        for k, (v, at) in arm_worst.items():
            row['arms vs %s cm' % k] = round(v * 100, 1)
            row['arms vs %s at' % k] = at
        clips[cname] = row
    res['clips'] = clips
    return res


def failures(res):
    bad = []
    for cname, row in res['clips'].items():
        for k, v in row.items():
            if k.endswith('(jacket over trousers)'):
                if v['out_cm'] > CREASE_CM:
                    bad.append('%s %s %.2f cm (%s)' % (cname, k, v['out_cm'], v['at']))
            elif k.endswith(': skin inside the shorts') or 'inside the jacket' in k:
                if v['out_cm'] > LIMIT_CM:
                    bad.append('%s %s %.2f cm (%s)' % (cname, k, v['out_cm'], v['at']))
            elif k == 'dr_doom: tie gap cm':
                if v[0] < TIE_GAP_CM[0] - 0.05 or v[1] > TIE_GAP_CM[1]:
                    bad.append('%s tie %s' % (cname, v))
            elif k.endswith('drift cm'):
                if v > 0.2:
                    bad.append('%s %s %.3f' % (cname, k, v))
            elif k.startswith('arms vs ') and k.endswith(' cm') and 'baseline' not in k:
                base = row[k[:-3] + ' baseline cm']
                if v > max(LIMIT_CM, base + CONTACT_MARGIN_CM.get(cname, HEAD_MARGIN_CM)):
                    bad.append('%s %s %.1f cm (stock head + curls with the same arms: %.1f)' % (cname, k, v, base))
    return bad


def main():
    fps = 20
    if '--fps' in sys.argv:
        fps = int(sys.argv[sys.argv.index('--fps') + 1])
    res = check(fps)
    for cname, row in res['clips'].items():
        print('%-18s %s' % (cname, ' '.join('%s=%s' % (k.split(': ')[-1][:18], v['out_cm'] if isinstance(v, dict) else v)
                                            for k, v in row.items() if not k.endswith(' at'))))
    bad = failures(res)
    res['failures'] = bad
    if '--json' in sys.argv:
        with open(sys.argv[sys.argv.index('--json') + 1], 'w') as f:
            json.dump(res, f, indent=1, sort_keys=True)
    print('failures:', len(bad))
    for b in bad:
        print('  ', b)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
