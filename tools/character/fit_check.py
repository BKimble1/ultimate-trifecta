"""Pass 9: garment fit checks on the exported runner.glb (numpy only; no bpy).

    python3 tools/character/fit_check.py [--glb PATH] [--looks a,b] [--json OUT] [--anchors OUT] [--quiet]

Everything is measured on the shipped asset (glb_rig.py reads its skin,
inverse bind matrices, rest pose, the 4 exported influences and the baked
clips), for every outfit as it is worn (the parts Cosmetics shows for it),
through every authored clip sampled at 10 Hz.  The checks look for clothing
that sits away from the body, which outfit_check.py (proxy spheres against
head pieces) cannot see:

  weights   every vertex: weights sum to 1, no unweighted vertex, joints in
            range, at most 4 influences; and vertices split at a seam (same
            position) carry the same weights (different weights open a crack
            in motion).
  normals   per part: unit normals that agree with the face winding (an
            inverted normal reads as a dark, detached piece).
  trims     closed rings round a limb or the torso (hem rings, cuff rolls,
            belts, piping, boot collars): per 15-degree sector, the ring's
            inner radius minus the radius of the outward-facing surface it
            sits on (the garment, a boot, bare skin).  A trim must sit on
            something: > 4 mm in any sector is a floating ring.
  openings  open edges round a limb or the neck (cuffs, hems, ankle and
            neck openings) that are not themselves covered by another piece:
            per sector, the edge's radius minus the outward-facing surface
            that comes out of it (skin, mitten, sock, boot).  Linings
            (inward-facing) do not count as support: a deep cuff with a dark
            lining is the gap it shows.  Bounds per region; loose garments
            (the robe's bell sleeves and skirt, hoods) have their own.
  crossing  a trouser leg must not cross the body's midline into the other
            leg (rest pose).
  seams     pieces of one garment that touch at rest (rings on tubes, cuffs on
            sleeves, collars, patches, pockets): on the same main bone their
            separation may not grow by more than 1.2 cm in any pose; layers
            that overlap across a joint (a shoulder cap over its sleeve, the
            pelvis over a trouser top) by more than 2 cm.
  fitted    garment vertices on a limb: radial distance to the posed limb
            axis minus the rest distance, by region (shoulder, elbow, wrist,
            hip, knee, ankle): how far the garment leaves (+) or sinks into
            (-) the body in the clips.  Reported; the hard bounds are on
            the trims, openings and seams above.

Final sweep (ARTFIX): standoff.  At the Season Pass / Shop / Locker stage's
scale (about 3x the old preview, turned through 360 degrees) a piece that
should lie on the body but stands off it reads as floating (a belly patch as
a disc in profile, a hood's face ring forward of the face, a jacket's front
edges as strips off the shirt, a headlamp strap as a halo).  Measured along
the surface's own normal, in the rest pose, and kept through the clips:

  patches   flat pieces lying on a larger piece (belly panels, badges,
            pockets, lapels, decals, feathers, eyes on a hood): the largest
            gap between the patch and the surface under it (a closed piece:
            its underside at each place; an open piece: its edge, which must
            meet the surface).  A panel (10 cm or more across) must lie
            within 6 mm and not overhang its surface; a smaller piece (a
            button, a buckle, a badge, a collar point) within 3 cm (it may
            be a raised detail).  STANDOFF_ALLOW lists the designed 3D
            pieces.  In every pose, no patch vertex may lift further off the
            plane of the surface face under it than the seam bound (sliding
            along it is fine).
  bands     rings and straps worn on the head (hat bands, straps over the
            crown, a hood's face rim), with every hair style they are worn
            with (Cosmetics' hat and hair rules): per sector, the inner
            side's distance to the hair, head or face under it, toward the
            head's centre.  > 4 mm (the trim bound) floats; a hood's face
            rim, which keeps 4 mm off the skin, > 1 cm.
  edges     the free front edge of an open jacket, cardigan or vest between
            the waist and the collar: its distance to the layer under it
            (the shirt), straight in toward the body.  > 1.2 cm stands off
            the shirt.  The pairs may not part by more than the seam bound
            in any pose.
  silhouette  a top's line in profile: across the upper chest and back it
            may stand at most 6 cm off the torso's own surface (it hangs
            from the shoulders), and the back of a hip-length top may not
            flare out at its hem beyond its waist at all: either
            reads as a slab hanging off the body.

--anchors writes game/tests/data/fit_anchors.json for test_fit_p9.gd (the
same pairs, re-measured in the game on the imported scene in final blended
poses, and the imported-vs-runtime comparison).  Exit status 1 on a failure.
"""
import argparse
import json
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from glb_rig import Glb, skin, gl_to_bl  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
GLB = os.path.join(REPO, 'game', 'assets', 'characters', 'runner.glb')
COSMETICS = os.path.join(REPO, 'game', 'src', 'view', 'cosmetics.gd')

# additive layers are deltas, not poses
ADDITIVE = {'add_zero', 'lead_l', 'lead_r', 'loco_accel', 'loco_brake'}
SAMPLE_HZ = 10.0

GROUP = {'root': 'torso', 'hips': 'torso', 'spine': 'torso', 'chest': 'torso', 'neck': 'torso',
         'head': 'head', 'hat1': 'head', 'hat2': 'head', 'hat3': 'head'}
for _s in ('L', 'R'):
    for _b in ('shoulder', 'upper_arm', 'forearm', 'hand'):
        GROUP['%s.%s' % (_b, _s)] = 'arm' + _s
    for _b in ('thigh', 'shin', 'foot'):
        GROUP['%s.%s' % (_b, _s)] = 'leg' + _s
# rest bone lengths of the chain tips (rig.py)
TIP = {'hand': 0.09, 'foot': 0.1336, 'head': 0.37}

# --------------------------------------------------------------- bounds (m)
TRIM_GAP = 0.004          # a ring may sit on (or sink into) its surface, never float
SEAM_GROW = 0.012         # touching pieces on one bone (a ring on its tube, a patch, a cap over its sleeve) may not part more
JUNCTION_GROW = 0.02      # overlapping layers across a joint (footwear over a cuff, the pelvis over a trouser top)
OVER_SHOE_GROW = 0.03     # in game: a pair across the ankle (a hem over footwear, a shoe collar round the shin)
FLIPPED_MAX = 0.002       # faces against their normals (a pinched tip or fold), as a share of a part's faces
CROSS_MAX = 0.002         # a trouser leg's inner face may reach the midline, not cross it
# visible openings: the largest radial gap between an edge and what comes out of it
OPEN_GAP = {'cuff': 0.016, 'sleeve': 0.016, 'thigh': 0.016, 'knee': 0.016, 'ankle': 0.016, 'waist': 0.016, 'skirt': 1.0,
            'over_shoe': 0.045}
# loose garments: the region keys that may be wider (a bell sleeve, a skirt hem)
LOOSE = {'robe': {'cuff': 0.04, 'thigh': 1.0, 'knee': 1.0}, 'raincoat': {'cuff': 0.025}}   # by outfit part
# final sweep (ARTFIX): standoff
PANEL_SIZE = 0.10         # a patch 10 cm or more across (its second extent) is a panel
PATCH_GAP = 0.006         # a panel's underside / edge off the surface it lies on (and it may not overhang it)
SMALL_GAP = 0.03          # a smaller piece (a button, buckle, badge, collar point, pocket, decal) may be a raised detail
BAND_GAP = TRIM_GAP       # a head band or strap off the hair or head under it
FACE_RIM_GAP = 0.01       # a hood's face rim off the face, toward the head's centre (it keeps 4 mm off the skin: test_outfits_p8)
EDGE_GAP = 0.012          # an open garment's front edge off the layer under it
SHOULDER_OUT = 0.06       # a top across the upper chest and back off the torso (a padded mascot suit: 5.5 cm)
SKIRT_FLARE = 0.0         # the back of a hip-length top at its hem beyond its waist: none (the others taper in 0.6-4 cm)
# designed standoff: (part, centre in rig axes, bound, why).  Each is a 3D
# piece, not a patch or a band, and is matched within 2 cm of its centre.
STANDOFF_ALLOW = [
    ('courier', (0.305, -0.035, 0.505), 9.0, 'the messenger bag hangs at the hip'),
    ('raincoat', (0.0, -0.16, 0.883), 0.09, 'piping round the edge of the folded hood'),
    ('cadet', (0.0, -0.232, 0.715), 9.0, 'the life-support pack is a box worn on the back'),
    ('acc_cadet_cap', (0.002, 0.237, 1.419), 0.03, "the visor's frame: the visor is lifted off the forehead on its arms"),
    ('acc_cadet_cap', (-0.345, -0.005, 1.17), 0.015, 'a comms pad over the ear (the ear stands out under it)'),
    ('acc_cadet_cap', (0.345, -0.005, 1.17), 0.015, 'a comms pad over the ear (the ear stands out under it)'),
]
# body pieces (never patches themselves; what head bands sit on)
HEAD_BODY = ('base', 'rb_head', 'dd_head', 'rb_hair', 'dd_fringe')
NOT_PATCH = HEAD_BODY + ('body_skin', 'freckles', 'mustache')


# --------------------------------------------------------------- looks
def _gd_literal(src, name):
    """The bracketed literal after `const NAME := ` (balanced), comments removed."""
    i = src.index('const %s := ' % name) + len('const %s := ' % name)
    open_c = src[i]
    close_c = {'{': '}', '[': ']'}[open_c]
    depth = 0
    for j in range(i, len(src)):
        if src[j] == open_c:
            depth += 1
        elif src[j] == close_c:
            depth -= 1
            if depth == 0:
                break
    body = re.sub(r'#[^\n]*', '', src[i:j + 1])
    return json.loads(re.sub(r',\s*([}\]])', r'\1', body))


def _gd_dict(src, name):
    return _gd_literal(src, name)


def _gd_list(src, name):
    return _gd_literal(src, name)


# shoes shown with the outfits that do not draw their own (the Shop showcase)
SHOWN_SHOES = {'pj': 'shoe_slippers', 'swim': 'shoe_flippers', 'robe': 'shoe_slippers', 'duck': 'shoe_slippers',
               'frog': 'shoe_slippers', 'moonlight_runner': 'shoe_hightops', 'starry_sleeper': 'shoe_slippers',
               'varsity_sprinter': 'shoe_hightops', 'campus_courier': 'shoe_hightops', 'lantern_scout': 'shoe_hightops',
               'after_hours_hoodie': 'shoe_glow', 'night_owl': 'shoe_slippers', 'glow_jogger': 'shoe_glow',
               'library_cardigan': 'shoe_moonboots'}


def looks():
    """outfit key -> mesh parts worn (Cosmetics.runner_parts with no hat and
    the showcase shoes), plus the Night Watch uniform."""
    src = open(COSMETICS).read()
    parts = _gd_dict(src, 'OUTFIT_PARTS')
    own = _gd_list(src, 'OUTFIT_OWN_SHOES')
    # Pass 9: complete skins (Cosmetics.COMPLETE_SKINS) are the whole runner:
    # their own head, hair and body with footwear, no base and no shoes
    i = src.index('const COMPLETE_SKINS := {')
    skins = set(re.findall(r'^\t"(\w+)": \{"head"', src[i:src.index('\n}', i)], re.M))
    out = {}
    for k, ps in parts.items():
        if k in skins:
            out[k] = list(ps)
            continue
        lk = ['base'] + list(ps)
        if k not in own:
            lk.append(SHOWN_SHOES.get(k, 'shoe_slippers'))
        out[k] = lk
    out['night_watch'] = ['base', 'watch', 'flashlight']
    return out


def head_looks():
    """'hat+hair' -> parts: every hat and outfit headwear on the head with each
    hair style, drawn the way Cosmetics.runner_parts draws them (the hat's
    hidden hair and hair variants).  Only the bands check uses these."""
    src = open(COSMETICS).read()
    hides = _gd_dict(src, 'HAT_HIDES_HAIR')
    variant = _gd_dict(src, 'HAT_HAIR_VARIANT')
    as_hat = _gd_dict(src, 'HEADWEAR_AS_HAT')
    i = src.index('\t"hat": {')
    hats = re.findall(r'"(\w+)": \{"id": \d+, "name": "[^"]*", "cost": \d+,(?: "season": \d+,)? "parts": \[([^\]]*)\]',
                      src[i:src.index('\t"shoes": {', i)])
    i = src.index('\t"hair": {')
    hairs = re.findall(r'"(\w+)": \{"id": \d+, "name": "[^"]*", "cost": \d+, "parts": \[([^\]]*)\]', src[i:src.index('\t},', i)])
    wear = [(k, re.findall(r'"(\w+)"', p), k) for k, p in hats if p.strip()]
    wear += [(p, [p], as_hat[p]) for p in sorted(as_hat)]
    out = {}
    for key, parts, rule in wear:
        for hk, hp in hairs:
            lk = ['base'] + parts
            for p in re.findall(r'"(\w+)"', hp):
                if p not in hides.get(rule, []):
                    lk.append(variant.get(rule, {}).get(p, p))
            out['%s+%s' % (key, hk)] = lk
    return out


# --------------------------------------------------------------- geometry helpers
def weld(pos):
    key = np.round(pos * 1e5).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    return inv.reshape(-1)


def islands_and_boundaries(m):
    """Connected pieces (positions welded) and boundary loops (lists of vertex ids)."""
    w = weld(m['pos'])
    n = w.max() + 1
    F = w[m['faces']]
    par = np.arange(n)

    def find(a):
        r = a
        while par[r] != r:
            r = par[r]
        while par[a] != r:
            par[a], a = r, par[a]
        return r
    for a, b, c in F:
        ra, rb, rc = find(a), find(b), find(c)
        par[rb] = ra
        par[find(rc)] = ra
    roots = np.array([find(i) for i in range(n)])
    isl = roots[w]
    E = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
    uq, cnt = np.unique(E, axis=0, return_counts=True)
    bnd = uq[cnt == 1]
    lp = {}

    def lf(a):
        while lp.setdefault(a, a) != a:
            lp[a] = lp[lp[a]]
            a = lp[a]
        return a
    for a, b in bnd:
        lp[lf(a)] = lf(b)
    groups = {}
    for a, b in bnd:
        groups.setdefault(lf(a), set()).update((int(a), int(b)))
    rep = np.zeros(n, dtype=np.int64)
    rep[w] = np.arange(len(w))
    loops = [rep[np.array(sorted(s))] for s in groups.values() if len(s) >= 6]
    closed = set(np.unique(isl).tolist()) - set(isl[np.concatenate(loops)].tolist() if loops else [])
    return isl, loops, closed, w


class Look:
    """The parts of one look, concatenated (rig axes: x right, y forward, z up)."""

    def __init__(self, g, parts):
        self.g = g
        self.parts = [p for p in parts if p in g.meshes]
        self.meshes = {p: g.mesh(p) for p in self.parts}
        pos, nrm, pid, isl, closed, loops, welds = [], [], [], [], set(), [], []
        base = 0
        ibase = 0
        for k, p in enumerate(self.parts):
            m = self.meshes[p]
            i, lps, cl, w = islands_and_boundaries(m)
            pos.append(gl_to_bl(m['pos']))
            nrm.append(gl_to_bl(m['nrm']))
            pid.append(np.full(len(m['pos']), k))
            isl.append(i + ibase)
            closed |= {c + ibase for c in cl}
            loops += [(p, L + base) for L in lps]
            welds.append(w + ibase)
            base += len(m['pos'])
            ibase += i.max() + 1
        self.pos = np.concatenate(pos)
        self.nrm = np.concatenate(nrm)
        self.pid = np.concatenate(pid)
        self.isl = np.concatenate(isl)
        self.closed = closed
        self.loops = loops
        self.weld = np.concatenate(welds)
        faces = []
        off = 0
        for p in self.parts:
            faces.append(self.meshes[p]['faces'] + off)
            off += len(self.meshes[p]['pos'])
        F = np.concatenate(faces)
        E = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
        self.edges = np.unique(E, axis=0)
        jn = np.concatenate([self.meshes[p]['joints'] for p in self.parts])
        wt = np.concatenate([self.meshes[p]['weights'] for p in self.parts])
        self.joints, self.weights = jn, wt
        dom = jn[np.arange(len(jn)), wt.argmax(1)]
        self.group = np.array([GROUP[g.joint_names[j]] for j in dom])
        # pieces that reach the ground (footwear, a footed suit's soles)
        zmin = {}
        for i, z in zip(self.isl, self.pos[:, 2]):
            if z < zmin.get(i, 9.0):
                zmin[i] = z
        # (a boot shaft or a sock starts within a few cm of the ground)
        self.ground_isl = {int(i): bool(z < 0.06) for i, z in zmin.items()}
        for i, k in zip(self.isl, self.pid):
            if self.parts[k].startswith('shoe_'):
                self.ground_isl[int(i)] = True

    def posed(self, jm):
        return np.concatenate([gl_to_bl(skin(self.meshes[p], jm)) for p in self.parts])

    def posed_idx(self, jm, idx):
        """Skin only the vertices idx (global ids)."""
        out = np.zeros((len(idx), 3))
        offs = np.cumsum([0] + [len(self.meshes[p]['pos']) for p in self.parts])
        for k, p in enumerate(self.parts):
            sel = (idx >= offs[k]) & (idx < offs[k + 1])
            if sel.any():
                out[sel] = gl_to_bl(skin(self.meshes[p], jm, idx[sel] - offs[k]))
        return out


def chain_points(g, jm_globals, group):
    """The posed axis polyline of a body segment (rig axes)."""
    G = jm_globals

    def head(b):
        return gl_to_bl(G[b][:3, 3])

    def tail(b, L):
        return gl_to_bl((G[b] @ np.array([0.0, L, 0.0, 1.0]))[:3])
    if group == 'torso':
        return [head('hips'), head('spine'), head('chest'), head('neck'), head('head')]
    if group == 'head':
        return [head('neck'), head('head'), tail('head', TIP['head'])]
    s = group[-1]
    if group.startswith('arm'):
        return [head('upper_arm.' + s), head('forearm.' + s), head('hand.' + s), tail('hand.' + s, TIP['hand'])]
    return [head('thigh.' + s), head('shin.' + s), head('foot.' + s), tail('foot.' + s, TIP['foot'])]


def joint_globals(g, clip=None, t=0.0):
    gl = g.globals_from_local(g.local_pose(clip, t))
    return {g.nodes[i]['name']: gl[i] for i in g.joints}


def axis_project(P, pts):
    """Nearest point on a polyline: (radial distance, arc length s, unit direction there, foot point)."""
    best = np.full(len(P), np.inf)
    sb = np.zeros(len(P))
    db = np.zeros((len(P), 3))
    fb = np.zeros((len(P), 3))
    acc = 0.0
    for a, b in zip(pts, pts[1:]):
        d = b - a
        L = np.linalg.norm(d)
        if L < 1e-9:
            continue
        u = d / L
        t = np.clip((P - a) @ u, 0.0, L)
        q = a + np.outer(t, u)
        r = np.linalg.norm(P - q, axis=1)
        k = r < best
        best[k] = r[k]
        sb[k] = acc + t[k]
        db[k] = u
        fb[k] = q[k]
        acc += L
    return best, sb, db, fb


def ring_frame(P, pts):
    """Centre and axis direction of a loop/ring of points round a segment axis."""
    c = P.mean(0)
    _, _, d, _ = axis_project(c[None, :], pts)
    a = d[0]
    return c, a


def polar(P, c, a):
    q = P - c
    ax = q @ a
    rad = q - np.outer(ax, a)
    r = np.linalg.norm(rad, axis=1)
    # a stable in-plane basis
    ref = np.array([0.0, 1.0, 0.0]) if abs(a[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    e1 = ref - a * (ref @ a)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(a, e1)
    th = np.arctan2(rad @ e2, rad @ e1)
    return ax, r, th, rad


NSECT = 24


def sectors(th, n=None):
    """Angular sector of each angle; offset by an odd fraction so the spokes
    of a regular ring (every 20 or 22.5 degrees) never sit on a boundary."""
    n = n or NSECT
    return ((th + math.pi + 0.0123) / (2 * math.pi) * n).astype(int) % n


def fill_sectors(v, empty, reach=2):
    """Sectors a coarse cross-section skipped take the larger of their nearest
    filled neighbours (within `reach` sectors either side)."""
    out = v.copy()
    n = len(v)
    for s in np.where(empty)[0]:
        best = None
        for d in range(1, reach + 1):
            for t in ((s - d) % n, (s + d) % n):
                if not empty[t]:
                    best = v[t] if best is None else max(best, v[t])
            if best is not None:
                break
        if best is not None:
            out[s] = best
    return out


# --------------------------------------------------------------- checks
def check_weights(look):
    out = {}
    for p in look.parts:
        m = look.meshes[p]
        s = m['weights'].sum(1)
        w = weld(m['pos'])
        # duplicates at one position must carry the same weights
        J = np.zeros((len(w), len(look.g.joint_names)))
        J[np.arange(len(w))[:, None], m['joints']] += m['weights']
        first = np.zeros(w.max() + 1, dtype=np.int64)
        first[w[::-1]] = np.arange(len(w))[::-1]
        # (coincident vertices of two different pieces, e.g. trouser legs
        # touching at the midline, are not a split: compare within a segment)
        dom = J.argmax(1)
        grp = np.array([GROUP[look.g.joint_names[j]] for j in dom])
        same = grp == grp[first[w]]
        split = float(np.abs(J - J[first[w]]).max(1)[same].max()) if same.any() else 0.0
        out[p] = {'verts': int(len(w)), 'sum_err': float(np.abs(s - 1).max()), 'unweighted': int((s < 1e-6).sum()),
                  'bad_joint': int((m['joints'] >= len(look.g.joint_names)).sum()), 'split_weight_diff': round(split, 5),
                  'max_influences': int((m['weights'] > 1e-4).sum(1).max())}
    return out


def check_normals(look):
    """Per part: faces whose winding disagrees with their vertex normals (an
    inverted or crossed normal shades a piece dark from outside) and normals
    that are not unit length.  (Pass 9: a dark detached-looking cuff was the
    lining's 50% vertex colour seen through the gap, not inverted normals.)"""
    out = {}
    for p in look.parts:
        m = look.meshes[p]
        P, N, F = m['pos'], m['nrm'], m['faces']
        fn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
        area = np.linalg.norm(fn, axis=1)
        ok = area > 1e-10
        vn = N[F].mean(axis=1)
        vn /= np.maximum(np.linalg.norm(vn, axis=1), 1e-9)[:, None]
        d = np.einsum('ij,ij->i', fn[ok] / area[ok][:, None], vn[ok])
        out[p] = {'faces': int(len(F)), 'flipped': int((d < -0.2).sum()),
                  'bad_length': int((np.abs(np.linalg.norm(N, axis=1) - 1.0) > 0.02).sum())}
    return out


def _interp_angle(qa, qv, ang, max_gap=math.radians(40.0)):
    """Value of a closed cross-section (angles qa, values qv) at angle ang, by
    linear interpolation between its neighbouring points (None if the
    section has no points within max_gap either side)."""
    if len(qa) < 2:
        return None
    o = np.argsort(qa)
    t = qa[o]
    v = qv[o]
    t = np.concatenate([t[-1:] - 2 * math.pi, t, t[:1] + 2 * math.pi])
    v = np.concatenate([v[-1:], v, v[:1]])
    j = int(np.searchsorted(t, ang))
    j = min(max(j, 1), len(t) - 1)
    if t[j] - t[j - 1] > max_gap:
        return None
    u = 0.0 if t[j] == t[j - 1] else (ang - t[j - 1]) / (t[j] - t[j - 1])
    return float(v[j - 1] + (v[j] - v[j - 1]) * u)


def crossings(look, P, N, c, a, planes, isl_keep=None, isl_drop=None, with_plane=False):
    """Cut the look's triangles by planes across the axis (axial offsets
    `planes` from c along a): (radius, sector, outwardness, island) of every
    edge crossing.  Cuts the real triangles, so a coarse lathe between its
    rings still counts."""
    ax, r, th, rad = polar(P, c, a)
    with np.errstate(invalid='ignore', divide='ignore'):
        outward = (np.einsum('ij,ij->i', N, rad) / np.maximum(r, 1e-9))
    E = look.edges
    if isl_keep is not None:
        E = E[np.isin(look.isl[E[:, 0]], list(isl_keep))]
    if isl_drop is not None:
        E = E[~np.isin(look.isl[E[:, 0]], list(isl_drop))]
    a0, a1 = ax[E[:, 0]], ax[E[:, 1]]
    out = [[], [], [], [], []]
    groups = {}
    for pl in planes:
        k = ((a0 - pl) * (a1 - pl) <= 0) & (a0 != a1)
        if not k.any():
            continue
        e = E[k]
        t = ((pl - a0[k]) / (a1[k] - a0[k]))[:, None]
        q = P[e[:, 0]] * (1 - t) + P[e[:, 1]] * t
        o = outward[e[:, 0]] * (1 - t[:, 0]) + outward[e[:, 1]] * t[:, 0]
        _, qr, qth, _ = polar(q, c, a)
        out[0].append(qr)
        out[1].append(sectors(qth))
        out[2].append(o)
        out[3].append(look.isl[e[:, 0]])
        out[4].append(qth)
        if with_plane:
            ii = look.isl[e[:, 0]]
            for i2 in np.unique(ii):
                kk = ii == i2
                groups[(int(i2), pl)] = (qth[kk], qr[kk], o[kk])
    if with_plane:
        return groups, None, None, None, None
    if not out[0]:
        return np.zeros(0), np.zeros(0, dtype=int), np.zeros(0), np.zeros(0, dtype=int), np.zeros(0)
    return tuple(np.concatenate(v) for v in out)


def sector_max(rs, ss, iss, keep, n=None, reach=2):
    """Per sector, the largest radius among the kept crossings; each piece's
    cross-section is filled round the circle on its own first (a coarse tube
    crosses only every other sector), so one piece's gaps are never filled
    by another piece deeper inside.  Returns (radius, sector has any)."""
    n = n or NSECT
    out = np.zeros(n)
    got = np.zeros(n, dtype=bool)
    for i in np.unique(iss[keep]) if keep.any() else []:
        k = keep & (iss == i)
        v = np.zeros(n)
        g = np.zeros(n, dtype=bool)
        np.maximum.at(v, ss[k], rs[k])
        g[ss[k]] = True
        v = fill_sectors(v, ~g, reach)
        g = fill_sectors(g.astype(float), ~g, reach) > 0.5
        out = np.maximum(out, np.where(g, v, 0.0))
        got |= g
    return out, got


def pca_frame(Q):
    """Centre and normal (least-variance direction) of a ring of points."""
    c = Q.mean(0)
    _, _, vt = np.linalg.svd(Q - c, full_matrices=False)
    return c, vt[2] / np.linalg.norm(vt[2])


def wraps(Q, c, a, max_gap_deg=60.0):
    """Points go all the way round the axis (no angular gap over max_gap_deg)."""
    ax, r, th, _ = polar(Q, c, a)
    t = np.sort(th)
    gaps = np.diff(np.concatenate([t, t[:1] + 2 * math.pi]))
    return bool(gaps.max() < math.radians(max_gap_deg) and r.min() > 0.3 * r.mean()), ax, r, th


def check_trims(look, P, N, region_of):
    """Closed rings round a limb or the torso: their inner radius minus the
    surface under them (anything not facing inward)."""
    res = []
    for i in sorted(look.closed):
        idx = np.where(look.isl == i)[0]
        if len(idx) < 24:
            continue
        grp = look.group[idx[0]]
        if grp == 'head':
            continue
        c, a = pca_frame(P[idx])
        ok, ax, r, th = wraps(P[idx], c, a, 45.0)
        if not ok or (ax.max() - ax.min()) > 0.8 * r.mean():
            continue            # not a ring round an axis (a button, a puff, a patch)
        # per spoke of the ring (5-degree bins): its inner and outer radius,
        # against the cross-sections of everything else interpolated round
        # the circle at the spoke's angle (a sole's outline is a polygon of
        # ~20 points: its radius between them is not its points' maximum)
        NT = 72
        sec = sectors(th, NT)
        spokes = []
        # (a window of +-7.5 degrees round each bin holds a whole spoke: the
        # ring's inner and outer side; a bin with only part of one is skipped)
        thick = float(np.median([r[sec == s].max() - r[sec == s].min() for s in np.unique(sec)]))
        for s in np.unique(sec):
            k = sec == s
            ang = float(np.arctan2(np.sin(th[k]).mean(), np.cos(th[k]).mean()))
            w = np.abs((th - ang + math.pi) % (2 * math.pi) - math.pi) < math.radians(7.5)
            if r[w].max() - r[w].min() < 0.5 * thick:
                continue
            spokes.append((ang, float(r[w].min()), float(r[w].max())))
        rs, ss, os_, iss, qth = crossings(look, P, N, c, a, np.linspace(ax.min() - 0.006, ax.max() + 0.006, 9), isl_drop=[i],
                                          with_plane=True)
        gaps = []
        for ang, rin, rout in spokes:
            sup = 0.0
            hid = False
            for (isl2, pl), (qa, qr, qo) in rs.items():
                dang = np.abs((qa - ang + math.pi) % (2 * math.pi) - math.pi)
                near = dang < math.radians(7.5)
                # covering from outside (hidden sector)
                if np.any(near & (qr > rout + 1e-4) & (qr <= rout + 0.03) & (qo > 0.15)):
                    hid = True
                # under the ring: the outermost point near the spoke, or the
                # section interpolated at its angle (only from points under it,
                # so a second, outer loop of the same piece is never mixed in)
                inner = qr <= rout + 1e-4
                if np.any(near & inner):
                    sup = max(sup, float(qr[near & inner].max()))
                v = _interp_angle(qa[inner], qr[inner], ang)
                if v is not None and v <= rout + 1e-4:
                    sup = max(sup, v)
            if not hid:
                gaps.append(rin - sup)
        if not gaps:
            continue
        gap = np.array(gaps)
        res.append({'part': look.parts[look.pid[idx[0]]], 'group': grp, 'region': region_of(grp, c),
                    'center': [round(float(v), 3) for v in c], 'radius': round(float(r.mean()), 4),
                    'gap': round(float(gap.max()), 4), 'n': int(len(idx)), 'island': int(i), 'verts': idx})
    return res


def check_openings(look, P, N, region_of, trim_islands=()):
    """The air gap at each visible garment edge round a limb: per sector, the
    innermost radius of the hem assembly (the edge's own piece and any ring
    or band on it) minus the outward-facing surface that comes out of it
    (skin, a mitten, a sock, a boot).  Edges inside another piece (a sleeve
    end under its cuff band, trousers in a boot) are skipped.  Linings face
    inward and never count as what comes out."""
    res = []
    for part, L in look.loops:
        grp = look.group[L[0]]
        if grp == 'head':
            continue
        c, a = pca_frame(P[L])
        ok, ax, r, th = wraps(P[L], c, a)
        if not ok:
            continue
        # an opening round the limb or body itself (a cuff, a hem, a neck),
        # not a pocket mouth or the edge of a patch: centred on the segment's
        # axis and facing along it (a coat's skirt is round the torso axis)
        cd, _, cdir, _ = axis_project(c[None, :], look.axes['torso' if abs(c[0]) < 0.03 else grp])
        if cd[0] > 0.6 * r.mean() or abs(float(cdir[0] @ a)) < 0.7:
            continue
        reg = region_of(grp, c)
        if reg == 'neck':
            continue            # under the head (reported by the seams instead)
        if grp.startswith('leg') and c[2] < 0.07:
            continue            # a shoe upper's edge on its sole
        isl = look.isl[L[0]]
        # the hem assembly: this piece and closed rings touching its edge
        near = np.linalg.norm(P[:, None, :] - P[L[::max(1, len(L) // 24)]][None, :, :], axis=2).min(1) < 0.012
        assembly = {int(isl)} | {int(j) for j in np.unique(look.isl[near]) if int(j) in trim_islands}
        rl = np.zeros(NSECT)
        sec = sectors(th)
        for s in range(NSECT):
            k = sec == s
            rl[s] = r[k].max() if k.any() else r.mean()
        rl = np.where(rl > 0, rl, r.mean())
        # the far side: away from the edge's own piece (where the limb comes out)
        own = np.where(look.isl == isl)[0]
        side = -1.0 if float(np.mean((P[own] - c) @ a)) > 0 else 1.0
        # covered: another piece (not a ring of this hem) round the edge on the far side
        rs, ss, os_, iss, _ = crossings(look, P, N, c, a, [side * 0.004, side * 0.008], isl_drop=assembly)
        cov, _ = sector_max(rs, ss, iss, (rs >= rl[ss] - 0.001) & (rs <= rl[ss] + 0.03) & (os_ > 0.15))
        if (cov > 0).mean() > 0.6:
            continue
        # the hem's innermost radius at the edge
        planes = [side * v for v in (-0.006, -0.003, 0.0, 0.003, 0.006)]
        rs, ss, os_, iss, _ = crossings(look, P, N, c, a, planes, isl_keep=assembly)
        rc = rl.copy()
        for i2 in np.unique(iss):
            k = (iss == i2) & (rs > 0.5 * rl[ss])
            v = np.full(NSECT, np.inf)
            np.minimum.at(v, ss[k], rs[k])
            g = np.isfinite(v)
            v = fill_sectors(np.where(g, v, 0.0), ~g)
            g = fill_sectors(g.astype(float), ~g) > 0.5
            rc = np.where(g, np.minimum(rc, v), rc)
        # what comes out of it, on the far side
        rs, ss, os_, iss, _ = crossings(look, P, N, c, a, [side * v for v in (0.0025, 0.005, 0.009, 0.013, 0.017, 0.021)],
                                     isl_drop=assembly)
        keep = (rs <= rc[ss] + 0.002) & (os_ > 0.15)
        sup, got = sector_max(rs, ss, iss, keep)
        if got.mean() < 0.5:
            continue            # nothing comes out of it (a closed tube end, a skirt over nothing)
        # a hem over footwear (what comes out of it reaches the ground): a
        # trouser over a shoe may hang off it, within its own bound
        if keep.any() and np.mean([look.ground_isl.get(int(j), False) for j in iss[keep]]) > 0.7:
            reg = 'over_shoe'
        sup = fill_sectors(sup, ~got)
        gap = np.maximum(0.0, rc - sup)
        res.append({'part': part, 'group': grp, 'region': reg, 'center': [round(float(v), 3) for v in c],
                    'radius': round(float(rc.mean()), 4), 'gap': round(float(gap.max()), 4),
                    'gap_mean': round(float(gap.mean()), 4), 'n': int(len(L)), 'verts': L, 'support_r': sup})
    return res


def check_crossing(look, P):
    out = {}
    for s, sx in (('L', -1.0), ('R', 1.0)):
        k = (look.group == 'leg' + s) & (P[:, 2] > 0.12) & (P[:, 2] < 0.46)
        if k.any():
            depth = -(P[k, 0] * sx).min()
            out['leg' + s] = round(float(depth), 4)
    return out


# --------------------------------------------------------------- standoff (final sweep)
class Tris:
    """The look's triangles (rest pose): corners, island, body segment and
    unit normal of every face."""
    def __init__(self, look, P):
        faces, off = [], 0
        for p in look.parts:
            faces.append(look.meshes[p]['faces'] + off)
            off += len(look.meshes[p]['pos'])
        self.F = np.concatenate(faces)
        self.isl = look.isl[self.F[:, 0]]
        self.pid = look.pid[self.F[:, 0]]
        self.grp = look.group[self.F[:, 0]]
        self.T = P[self.F]
        fn = np.cross(self.T[:, 1] - self.T[:, 0], self.T[:, 2] - self.T[:, 0])
        self.n = fn / np.maximum(np.linalg.norm(fn, axis=1), 1e-12)[:, None]
        self.lo = self.T.min(1)
        self.hi = self.T.max(1)


def ray_first(O, D, tri, sel, tmax, facing=None):
    """First hit of each ray (origins O, unit directions D) on the faces
    `sel` (indices into tri) within tmax: (t, face) with t = inf, face = -1
    on a miss.  facing: a face only counts when its normal points against
    the ray (n . D < -facing), i.e. it is seen from the ray's side."""
    t_out = np.full(len(O), np.inf)
    f_out = np.full(len(O), -1)
    if len(O) == 0 or len(sel) == 0:
        return t_out, f_out
    for s in range(0, len(O), 128):
        o, d = O[s:s + 128], D[s:s + 128]
        lo = np.minimum(o, o + d * tmax).min(0) - 1e-4
        hi = np.maximum(o, o + d * tmax).max(0) + 1e-4
        k = sel[np.all(tri.hi[sel] >= lo, axis=1) & np.all(tri.lo[sel] <= hi, axis=1)]
        if len(k) == 0:
            continue
        v0 = tri.T[k, 0]
        e1 = tri.T[k, 1] - v0
        e2 = tri.T[k, 2] - v0
        h = np.cross(d[:, None, :], e2[None, :, :])
        a = np.einsum('tk,mtk->mt', e1, h)
        ok = np.abs(a) > 1e-12
        f = np.where(ok, 1.0 / np.where(ok, a, 1.0), 0.0)
        sv = o[:, None, :] - v0[None, :, :]
        u = f * np.einsum('mtk,mtk->mt', sv, h)
        q = np.cross(sv, e1[None, :, :])
        v = f * np.einsum('mk,mtk->mt', d, q)
        t = f * np.einsum('tk,mtk->mt', e2, q)
        hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t >= 0) & (t <= tmax)
        if facing is not None:
            hit &= (d @ tri.n[k].T) < -facing
        t = np.where(hit, t, np.inf)
        j = t.argmin(1)
        tt = t[np.arange(len(o)), j]
        t_out[s:s + 128] = tt
        f_out[s:s + 128] = np.where(np.isfinite(tt), k[j], -1)
    return t_out, f_out


def _island_info(look, P):
    """Per island: vertex ids, majority body segment, part."""
    info = {}
    order = np.argsort(look.isl, kind='stable')
    cuts = np.flatnonzero(np.diff(look.isl[order])) + 1
    for idx in np.split(order, cuts):
        i = int(look.isl[idx[0]])
        g, c = np.unique(look.group[idx], return_counts=True)
        info[i] = {'idx': idx, 'grp': g[c.argmax()], 'part': look.parts[look.pid[idx[0]]]}
    return info


def _boundary_verts(look, idx):
    """Vertices of the island idx on an open edge (welded positions)."""
    sel = set(idx.tolist())
    out = []
    for part, L in look.loops:
        if int(L[0]) in sel:
            out.append(L)
    return np.unique(np.concatenate(out)) if out else np.zeros(0, dtype=np.int64)


def _anchor(tri, f, v, P):
    """A patch vertex v and the face of the surface under it: (v, a, b, c).
    In the clips the patch may slide along that face, not lift off it."""
    a, b, c = tri.F[f]
    return (int(v), int(a), int(b), int(c))


HEAD_CENTRE = np.array([0.0, 0.015, 1.185])   # rig.HEAD_C
TORSO_CY = 0.005                              # rig.TORSO_CY


def outward(look, grp, c):
    """The body's outward direction at point c of a segment: away from the
    head's centre, the torso's vertical axis or the limb's axis."""
    if grp == 'head':
        d = c - HEAD_CENTRE
    elif grp == 'torso':
        d = np.array([c[0], c[1] - TORSO_CY, 0.0])
    else:
        _, _, _, foot = axis_project(c[None, :], look.axes[grp])
        d = c - foot[0]
    return d / max(float(np.linalg.norm(d)), 1e-9)


def _near_groups(grp):
    """Body segments a patch on `grp` may lie across (a hip pocket rides on
    the thighs' weights, a shoulder patch on the torso's)."""
    if grp == 'head':
        return ['head']
    if grp.startswith('arm'):
        return [grp, 'torso']
    # (a patch on the shoulders lies over the sleeve caps' arm weights)
    return ['torso', 'legL', 'legR', 'armL', 'armR']


def signed_standoff(P, vs, n_out, tri, sel, reach=0.1, up_sel=None):
    """Signed distance of each vertex vs[k] from the surface under it along
    -n_out[k]: the first face seen from above (its normal along n_out);
    negative when the vertex is under such a surface already (sunk into it,
    up to 8 cm): the first face of up_sel (default sel) on the way up is one
    the ray leaves.  up_sel is the surface the piece lies on (the hair and
    head for a head band, a patch's own surface), so a trim lying over the
    piece is not taken for that surface.  Returns (d, face) with d = inf
    where nothing is under it."""
    O = P[vs]
    # the first surface on the way up: when the ray leaves it (its normal
    # along the ray) the vertex is inside or under it
    up_t, up_f = ray_first(O, n_out, tri, sel if up_sel is None else up_sel, 0.08)
    ex = np.zeros(len(vs), dtype=bool)
    k = np.isfinite(up_t)
    ex[k] = np.einsum('ij,ij->i', tri.n[up_f[k]], n_out[k]) > 0.0
    # on the way down: the first face seen from above is the gap, unless the
    # vertex is inside another piece (one whose first face along the ray is
    # left, not entered: a stripe sunk into its strap, a feather into its
    # panel), whose surface it is then part of
    dn_t = np.full(len(vs), np.inf)
    dn_f = np.full(len(vs), -1)
    inside = np.zeros(len(vs), dtype=bool)
    in_f = np.full(len(vs), -1)
    seen = [set() for _ in range(len(vs))]
    cur = O.copy()
    gone = np.zeros(len(vs))
    live = np.ones(len(vs), dtype=bool)
    for _ in range(4):
        if not live.any():
            break
        ix = np.where(live)[0]
        t, fh = ray_first(cur[ix], -n_out[ix], tri, sel, reach)
        for j, tt, ff in zip(ix, t, fh):
            if not np.isfinite(tt) or gone[j] + tt > reach:
                live[j] = False
                continue
            isl = int(tri.isl[ff])
            facing = float(tri.n[ff] @ n_out[j])
            if isl not in seen[j]:
                seen[j].add(isl)
                if facing < -0.2:
                    inside[j] = True
                    in_f[j] = ff                # (the piece it is inside: its anchor)
                    live[j] = False
                    continue
            if facing > -0.2 and not np.isfinite(dn_t[j]):
                dn_t[j], dn_f[j] = gone[j] + tt, ff         # the first face it is not inside
            gone[j] += tt + 1e-5
            cur[j] = cur[j] - n_out[j] * (tt + 1e-5)
        # (keep going only to learn whether the vertex is inside a piece
        # it has not reached the far side of yet)
    d = np.where(ex, -up_t, np.where(inside, -0.001, dn_t))
    f = np.where(ex, up_f, np.where(inside, in_f, dn_f))
    return d, f


def check_patches(look, P, N, tri, info):
    """Flat pieces lying on a surface: the gap between each and its surface.
    A patch lies on a larger piece (the suit under a belly panel, the panel
    under a feather, the disc under an eye); flaps of one size lying on each
    other (tail feathers, tufts) are not patches."""
    areas = {}

    def area(i):
        if i not in areas:
            Q = P[info[i]['idx']]
            sv = np.linalg.svd(Q - Q.mean(0), compute_uv=False) / math.sqrt(len(Q))
            areas[i] = float(sv[0] * sv[1])
        return areas[i]
    cand = {}
    for i, it in info.items():
        idx = it['idx']
        if len(idx) < 8 or it['part'] in NOT_PATCH or it['part'].startswith('hair'):
            continue
        Q = P[idx]
        c = Q.mean(0)
        _, _, vt = np.linalg.svd(Q - c, full_matrices=False)
        ext = (Q - c) @ vt.T
        span = ext.max(0) - ext.min(0)
        if span[1] < 0.02 or span[2] > 0.5 * span[1]:
            continue            # not flat (a tube, a shell, a knob; a panel bent round a belly is 0.43)
        if np.linalg.norm(ext[:, :2], axis=1).min() > 0.25 * span[1]:
            continue            # a ring round something (trims and bands check those)
        n_out = vt[2] if float(vt[2] @ outward(look, it['grp'], c)) >= 0 else -vt[2]
        near = np.isin(tri.grp, _near_groups(it['grp'])) & (tri.isl != i)
        a_i = area(i)
        bigger = [int(j) for j in np.unique(tri.isl[near]) if area(int(j)) >= 1.2 * a_i]
        same = np.where(near & np.isin(tri.isl, bigger))[0]
        d, f = signed_standoff(c[None, :], np.array([0]), n_out[None, :], tri, same)
        if not np.isfinite(d[0]) or float(tri.n[f[0]] @ n_out) < 0.8:
            continue            # nothing under it lying the same way (a base layer, a free flap)
        base = c - n_out * d[0]
        if float(((Q - base) @ n_out).max()) > span[2] + 0.02:
            continue            # standing out of the surface (an ear, a tuft, a tail feather)
        cand[i] = {'n': n_out, 'support': int(tri.isl[f[0]]), 'ext': ext[:, :2], 'span': span, 'c': c}
    # pieces lying on a patch (feathers on a belly panel, an eye on its disc)
    # are not its surface
    above = {i: set() for i in cand}
    for i in cand:
        j, seen = cand[i]['support'], {i}
        while j in cand and j not in seen:
            above[j].add(i)
            seen.add(j)
            j = cand[j]['support']
    res = []
    for i, cd in cand.items():
        it = info[i]
        idx = it['idx']
        closed = int(i) in look.closed
        excl = list({i} | above[i])
        sel = np.where(~np.isin(tri.isl, excl) & np.isin(tri.grp, _near_groups(it['grp'])))[0]
        on = np.where(tri.isl == cd['support'])[0]
        # a closed piece: its underside, cell by cell; an open one (a decal,
        # a pad, a lapel): the edge where it must meet the surface
        vs = idx if closed else _boundary_verts(look, idx)
        if len(vs) == 0:
            continue
        d, f = signed_standoff(P, vs, np.repeat(cd['n'][None, :], len(vs), 0), tri, sel, up_sel=on)
        if closed:
            # at each vertex's place on the patch, its underside there: the
            # lowest vertex within 1.5 cm across the patch
            uv = cd['ext']
            hgt = P[vs] @ cd['n']
            D2 = ((uv[:, None, :] - uv[None, :, :]) ** 2).sum(2)
            low = np.where(D2 < 0.015 ** 2, hgt[None, :], np.inf).argmin(1)
            vals = sorted({(float(d[j]), int(vs[j]), int(f[j])) for j in low})
        else:
            vals = list(zip(d, vs, f))
        worst = max(vals, key=lambda x: x[0])
        fin = [x for x in vals if np.isfinite(x[0])]
        gap = float(worst[0])
        anchors = [_anchor(tri, int(ff), int(vv), P) for dv, vv, ff in fin if dv > -0.004 and ff >= 0]
        res.append({'part': it['part'], 'group': it['grp'], 'center': [round(float(v), 3) for v in cd['c']],
                    'size': [round(float(v), 3) for v in cd['span']], 'closed': closed,
                    'on': info[cd['support']]['part'], 'gap': round(gap, 4) if np.isfinite(gap) else 9.0,
                    'gap_seen': round(float(max(x[0] for x in fin)), 4) if fin else None,
                    'overhang': bool(not np.isfinite(gap)), 'at': [round(float(v), 3) for v in P[int(worst[1])]],
                    'anchors': anchors[::max(1, len(anchors) // 12)]})
    return res


def check_bands(look, P, N, tri, info):
    """Bands and straps worn on the head (hat bands, straps over the crown, a
    hood's face rim): per 15-degree sector round the band, its inner side's
    distance to what is under it, toward the head's centre (hair, the head,
    a face, the hat's own shell or strap; a hood's shell is beside its rim,
    not under it).  Sunk counts only into the hair, head or face.  Rings
    round the head or face (not an ear cushion: radius 12 cm or more; not a
    hat's brim or cuff, the trim on its shell's edge) and open straps (a
    tube open at its two ends, 15 cm or longer)."""
    res = []
    loops_of = {}
    for part, L in look.loops:
        loops_of.setdefault(int(look.isl[L[0]]), []).append(L)
    for i, it in info.items():
        idx = it['idx']
        if len(idx) < 24 or it['grp'] != 'head' or it['part'] in NOT_PATCH or it['part'].startswith('hair'):
            continue
        Q = P[idx]
        if int(i) in look.closed:
            c, a = pca_frame(Q)
            ok, ax, r, th = wraps(Q, c, a, 45.0)
            if not ok or (ax.max() - ax.min()) > 0.8 * r.mean() or r.mean() < 0.12:
                continue        # not a ring round the head or face (a lamp, an ear cushion, a puff)
            kind, size = 'ring', float(r.mean())
            if abs(float(a[1])) > 0.7 and c[1] > 0.15:
                kind = 'face rim'       # a hood's rim round the face opening
            else:
                # a hat's brim or cuff: the trim on the lower edge of its
                # shell over the head (a cap's brim, a beanie's cuff, the
                # nightcap's fur) stands where the hat's shape puts it; a
                # band is worn on the hair
                zr = float(Q[:, 2].min())
                if any(o != i and oi['part'] == it['part'] and len(oi['idx']) >= 200 and
                       abs(float(P[oi['idx'], 2].min()) - zr) < 0.04 and float(P[oi['idx'], 2].max()) > zr + 0.08
                       for o, oi in info.items()):
                    continue
        else:
            # (a strap's sectors are taken round the head's centre: round its
            # own centroid, a long arc's sectors over the crown held a
            # vertex or two)
            c, a = pca_frame(Q)
            _, _, th, _ = polar(Q, HEAD_CENTRE, a)
            lp = loops_of.get(int(i), [])
            if len(lp) != 2 or max(float(np.ptp(P[L], axis=0).max()) for L in lp) > 0.04:
                continue        # not a strap (a shell, a decal, a cap)
            size = float(np.linalg.norm(P[lp[0]].mean(0) - P[lp[1]].mean(0)))
            if size < 0.15:
                continue
            kind = 'strap'
        n_out = Q - HEAD_CENTRE[None, :]
        rad = np.linalg.norm(n_out, axis=1)
        n_out /= np.maximum(rad, 1e-9)[:, None]
        body = np.where(np.isin(tri.pid, [k for k, pt in enumerate(look.parts) if pt in HEAD_BODY or pt.startswith('hair')]))[0]
        d, f = signed_standoff(P, idx, n_out, tri, np.where(tri.isl != i)[0], reach=0.15, up_sel=body)
        # per 15-degree sector, its inner side: of the vertices facing the
        # head (or, with none, the innermost few) the one nearest what is
        # under it
        inner = np.einsum('ij,ij->i', N[idx], n_out) < -0.3
        sec = sectors(th)
        gaps = []
        for kk in np.unique(sec):
            k = np.where(sec == kk)[0]
            k = k[inner[k]] if inner[k].any() else k[rad[k] <= rad[k].min() + 0.004]
            j = k[d[k].argmin()]
            gaps.append((float(d[j]), int(idx[j])))
        worst = max(gaps)
        res.append({'part': it['part'], 'kind': kind, 'center': [round(float(v), 3) for v in c], 'size': round(size, 4),
                    'gap': round(worst[0], 4) if np.isfinite(worst[0]) else 9.0, 'at': [round(float(v), 3) for v in P[worst[1]]],
                    'sectors': len(gaps)})
    return res


def check_edges(look, P, N, tri, info):
    """The free front edge of an open garment (jacket, cardigan, vest)
    between the waist and the collar (0.63-0.83 m, where the shirt shows):
    its distance straight in toward the body's axis to the garment layer
    under it (a shirt, a tie, a torso shell: a piece of 300 vertices or
    more; the edge's own trims, facings and lapels are smaller pieces)."""
    res = []
    layers = [i for i, it in info.items() if len(it['idx']) >= 300]
    for part, L in look.loops:
        it = info[int(look.isl[L[0]])]
        if it['grp'] != 'torso' or len(it['idx']) < 300:
            continue            # a garment panel, not a patch or a trim
        # the front, above the waist (where the shirt shows) and below the collar
        k = (P[L, 1] > 0.05) & (P[L, 2] > 0.63) & (P[L, 2] < 0.83)
        if k.sum() < 4:
            continue
        # along a near-vertical run (an open front, not a hem or a neckline):
        # the edge's direction from its neighbours within 2.5 cm
        Lp = P[L]
        keep = []
        for v in L[k]:
            q = Lp[np.linalg.norm(Lp - P[v], axis=1) < 0.025]
            if len(q) < 3:
                continue
            _, _, vt = np.linalg.svd(q - q.mean(0), full_matrices=False)
            if abs(vt[0][2]) > 0.6:
                keep.append(v)
        E = np.array(keep, dtype=np.int64)
        if len(E) < 4:
            continue
        sel = np.where(np.isin(tri.isl, layers) & (tri.isl != look.isl[L[0]]))[0]
        # (straight in toward the body's axis: a rolled edge's own normal
        # leans into the opening)
        n = np.stack([P[E, 0], P[E, 1] - TORSO_CY, np.zeros(len(E))], axis=1)
        n /= np.maximum(np.linalg.norm(n, axis=1), 1e-9)[:, None]
        d, f = signed_standoff(P, E, n, tri, sel)
        fin = np.isfinite(d)
        if fin.sum() < 4:
            continue            # nothing under it (not a layered front)
        w = int(np.argmax(np.where(fin, d, -1.0)))
        res.append({'part': part, 'center': [round(float(v), 3) for v in P[E].mean(0)], 'n': int(len(E)),
                    'gap': round(float(d[w]), 4), 'gap_mean': round(float(d[fin].mean()), 4),
                    'at': [round(float(v), 3) for v in P[E[w]]], 'on': look.parts[int(tri.pid[f[w]])],
                    'anchors': [_anchor(tri, int(ff), int(v), P) for v, ff, ok in zip(E, f, fin) if ok and ff >= 0][::2]})
    return res


# the torso's own profile (rig.TORSO, rig.TORSO_RY): what a top's offset is measured from
TORSO_PROFILE = [(0.455, 0.0), (0.462, 0.07), (0.475, 0.13), (0.50, 0.172), (0.53, 0.196), (0.57, 0.212), (0.62, 0.22), (0.67, 0.216),
                 (0.72, 0.205), (0.77, 0.188), (0.81, 0.168), (0.84, 0.145), (0.865, 0.11), (0.885, 0.072), (0.93, 0.065), (0.96, 0.0)]
TORSO_RY = 0.84


def torso_r(z):
    zs, rs = zip(*TORSO_PROFILE)
    return np.interp(z, zs, rs, left=0.0, right=0.0)


def check_silhouette(look, P, info):
    """A top's line in profile.  shoulders: how far an open top (a jacket,
    a shirt, a suit) stands off the torso's own surface across the upper
    chest and back (0.76-0.85 m, the torso's middle 24 cm), where it hangs
    from the shoulders; skirt_flare: how far the back of a hip-length top
    (its lowest point 0.42-0.56 m) stands further out at its hem than at the
    waist (0.60 m): a back that hangs straight down and flares reads as a
    slab off the body.  Closed pieces (a folded hood, a pack) are not tops."""
    out = {'shoulders': 0.0, 'shoulders_at': None, 'shoulders_part': None, 'skirt_flare': -1.0, 'skirt_at': None, 'skirt_part': None}
    loops_of = {int(look.isl[L[0]]) for part, L in look.loops}
    for i, it in info.items():
        idx = it['idx']
        if it['grp'] != 'torso' or len(idx) < 300 or int(i) not in loops_of or it['part'] in NOT_PATCH or it['part'].startswith('hair'):
            continue
        Q = P[idx]
        rp = np.hypot(Q[:, 0], (Q[:, 1] - TORSO_CY) / TORSO_RY)
        off = rp - torso_r(Q[:, 2])
        k = (Q[:, 2] >= 0.76) & (Q[:, 2] <= 0.85) & (np.abs(Q[:, 0]) < 0.12)
        if k.any():
            j = np.where(k)[0][off[k].argmax()]
            if off[j] > out['shoulders']:
                out.update(shoulders=round(float(off[j]), 4), shoulders_at=[round(float(v), 3) for v in Q[j]], shoulders_part=it['part'])
        zmin = float(Q[:, 2].min())
        if 0.42 <= zmin <= 0.56:
            back = (np.abs(Q[:, 0]) < 0.08) & (Q[:, 1] < TORSO_CY)
            hem = back & (Q[:, 2] < zmin + 0.012)
            waist = back & (np.abs(Q[:, 2] - 0.60) < 0.012)
            if hem.any() and waist.any():
                fl = float(rp[hem].max() - rp[waist].max())
                if fl > out['skirt_flare']:
                    j = np.where(hem)[0][rp[hem].argmax()]
                    out.update(skirt_flare=round(fl, 4), skirt_at=[round(float(v), 3) for v in Q[j]], skirt_part=it['part'])
    return out


def seam_pairs(look):
    """Vertex pairs of different pieces of one garment part on the same body
    segment that touch at rest (<= 6 mm)."""
    pairs = []
    P = look.pos
    for i in np.unique(look.isl):
        a = np.where(look.isl == i)[0]
        if len(a) < 6:
            continue
        b = np.where((look.isl != i) & (look.pid == look.pid[a[0]]))[0]
        if len(b) == 0:
            continue
        sub = a[::max(1, len(a) // 48)]
        for s0 in range(0, len(sub), 64):
            chunk = sub[s0:s0 + 64]
            D = np.linalg.norm(P[chunk, None, :] - P[None, b, :], axis=2)
            j = D.argmin(1)
            d = D[np.arange(len(chunk)), j]
            for va, vb, dd in zip(chunk, b[j], d):
                if dd <= 0.006 and look.group[va] == look.group[vb] and look.weld[va] != look.weld[vb]:
                    pairs.append((int(va), int(vb)))
    return np.array(pairs, dtype=np.int64).reshape(-1, 2)


def region_of_fn():
    def f(grp, c):
        if grp.startswith('arm'):
            sx = -1 if grp.endswith('L') else 1
            sh = np.array([0.17 * sx, 0.0, 0.84])
            s = float(np.linalg.norm(c - sh))
            return 'cuff' if s > 0.24 else 'sleeve'
        if grp.startswith('leg'):
            z = c[2]
            if abs(c[0]) < 0.03:
                return 'skirt'          # a hem round both legs (a coat, the robe)
            return 'ankle' if z < 0.25 else ('knee' if z < 0.36 else 'thigh')
        if grp == 'torso':
            return 'neck' if c[2] > 0.8 else 'waist'
        return grp
    return f


def fitted_region(grp, p):
    if grp.startswith('arm'):
        sx = -1 if grp.endswith('L') else 1
        s = float(np.linalg.norm(p - np.array([0.17 * sx, 0.0, 0.84])))
        return 'shoulder' if s < 0.08 else ('elbow' if abs(s - 0.17) < 0.05 else ('wrist' if s > 0.27 else 'arm'))
    if grp.startswith('leg'):
        z = p[2]
        return 'hip' if z > 0.46 else ('knee' if abs(z - 0.305) < 0.06 else ('ankle' if z < 0.16 else 'leg'))
    return None


# --------------------------------------------------------------- driver
def poses_of(g):
    out = []
    for c in g.clips:
        if c in ADDITIVE:
            continue
        L = g.clip_length(c)
        n = max(2, int(L * SAMPLE_HZ) + 1)
        out += [(c, L * k / (n - 1)) for k in range(n)]
    return out


def analyze(g, key, parts, poses, pose_data, want_anchors=False):  # noqa: C901
    look = Look(g, parts)
    rest_glob = joint_globals(g)
    look.axes = {grp: chain_points(g, rest_glob, grp) for grp in set(look.group)}
    P, N = look.pos, look.nrm
    reg = region_of_fn()
    rep = {'parts': look.parts, 'weights': check_weights(look), 'normals': check_normals(look)}
    trims = check_trims(look, P, N, reg)
    opens = check_openings(look, P, N, reg, {t['island'] for t in trims})
    rep['crossing'] = check_crossing(look, P)
    loose = LOOSE.get(parts[1] if len(parts) > 1 else '', {})
    rep['trims'] = [{k: v for k, v in t.items() if k not in ('verts',)} for t in trims]
    rep['openings'] = [{k: v for k, v in o.items() if k not in ('verts', 'support_r')} for o in opens]
    # standoff (rest pose), and the pairs that keep it through the clips
    tri = Tris(look, P)
    info = _island_info(look, P)
    patches = check_patches(look, P, N, tri, info)
    bands = check_bands(look, P, N, tri, info)
    edges = check_edges(look, P, N, tri, info)
    rep['patches'] = [{k: v for k, v in s.items() if k != 'anchors'} for s in patches]
    rep['bands'] = bands
    rep['edges'] = [{k: v for k, v in s.items() if k != 'anchors'} for s in edges]
    rep['silhouette'] = check_silhouette(look, P, info)
    spairs = np.array([a for s in patches + edges for a in s['anchors']], dtype=np.int64).reshape(-1, 4)
    sd0 = _plane_dist(P[spairs[:, 0]], P[spairs[:, 1]], P[spairs[:, 2]], P[spairs[:, 3]]) if len(spairs) else np.zeros(0)
    sgrow = np.zeros(len(spairs))
    sgrow_pose = np.zeros(len(spairs), dtype=np.int64)
    # seams through the poses, and the fitted-region deformation
    pairs = seam_pairs(look)
    garment = np.where(np.isin(look.group, ['armL', 'armR', 'legL', 'legR']) & (look.pid != look.parts.index('base')))[0] \
        if 'base' in look.parts else np.where(np.isin(look.group, ['armL', 'armR', 'legL', 'legR']))[0]
    garment = garment[::max(1, len(garment) // 1500)]
    r0 = np.zeros(len(garment))
    for grp in ('armL', 'armR', 'legL', 'legR'):
        k = look.group[garment] == grp
        if k.any():
            r0[k] = axis_project(P[garment[k]], look.axes[grp])[0]
    regions = np.array([fitted_region(look.group[v], P[v]) or '' for v in garment])
    d0 = np.linalg.norm(P[pairs[:, 0]] - P[pairs[:, 1]], axis=1) if len(pairs) else np.zeros(0)
    grow = np.zeros(len(pairs))
    grow_pose = np.zeros(len(pairs), dtype=np.int64)
    fit_hi = {}
    fit_lo = {}
    trim_pose = {}
    for k, (jm, glob) in enumerate(pose_data):
        Q = look.posed_idx(jm, np.concatenate([pairs.reshape(-1), garment, spairs.reshape(-1)]))
        if len(pairs):
            A = Q[:2 * len(pairs)].reshape(-1, 2, 3)
            d = np.linalg.norm(A[:, 0] - A[:, 1], axis=1) - d0
            u = d > grow
            grow[u] = d[u]
            grow_pose[u] = k
        if len(spairs):
            A = Q[2 * len(pairs) + len(garment):].reshape(-1, 4, 3)
            # how much further off its surface the piece gets (sliding along it is fine)
            d = np.maximum(_plane_dist(A[:, 0], A[:, 1], A[:, 2], A[:, 3]), 0.0) - np.maximum(sd0, 0.0)
            u = d > sgrow
            sgrow[u] = d[u]
            sgrow_pose[u] = k
        G = Q[2 * len(pairs):2 * len(pairs) + len(garment)]
        for grp in ('armL', 'armR', 'legL', 'legR'):
            kk = look.group[garment] == grp
            if not kk.any():
                continue
            r1 = axis_project(G[kk], chain_points(g, glob, grp))[0]
            dr = r1 - r0[kk]
            for rg in set(regions[kk]):
                if not rg:
                    continue
                sel = regions[kk] == rg
                hi = float(np.percentile(dr[sel], 99))
                lo = float(np.percentile(dr[sel], 1))
                if hi > fit_hi.get(rg, (-1, 0))[0]:
                    fit_hi[rg] = (hi, k)
                if lo < fit_lo.get(rg, (1, 0))[0]:
                    fit_lo[rg] = (lo, k)
    # attached seams: both vertices on the same main bone; junctions: layers
    # that overlap across a joint (different main bones)
    if len(pairs):
        dom = look.joints[np.arange(len(look.joints)), look.weights.argmax(1)]
        junction = dom[pairs[:, 0]] != dom[pairs[:, 1]]
    else:
        junction = np.zeros(0, dtype=bool)
    rep['seams'] = {'pairs': int(len(pairs)), 'junction_pairs': int(junction.sum())}
    for name, sel in (('attached', ~junction), ('junction', junction)):
        gsel = grow[sel] if len(grow) else grow
        rep['seams'][name + '_max_grow'] = round(float(gsel.max()) if len(gsel) else 0.0, 4)
        if len(gsel) and gsel.max() > 0:
            i = int(np.where(sel)[0][gsel.argmax()])
            rep['seams'][name + '_worst'] = {'pose': [poses[grow_pose[i]][0], round(float(poses[grow_pose[i]][1]), 3)],
                                             'at': [round(float(v), 3) for v in P[pairs[i, 0]]],
                                             'parts': [look.parts[look.pid[pairs[i, 0]]], look.parts[look.pid[pairs[i, 1]]]]}
    rep['seams']['max_grow'] = max(rep['seams']['attached_max_grow'], rep['seams']['junction_max_grow'])
    rep['fitted'] = {rg: {'p99_out': round(fit_hi[rg][0], 4), 'pose_out': list(poses[fit_hi[rg][1]]),
                          'p01_in': round(fit_lo[rg][0], 4), 'pose_in': list(poses[fit_lo[rg][1]])} for rg in fit_hi}
    # failures
    fails = []
    for p, w in rep['weights'].items():
        if w['sum_err'] > 1e-3 or w['unweighted'] or w['bad_joint'] or w['split_weight_diff'] > 1e-3 or w['max_influences'] > 4:
            fails.append('weights %s %s' % (p, w))
    for p, n in rep['normals'].items():
        if n['flipped'] > FLIPPED_MAX * n['faces'] or n['bad_length']:
            fails.append('normals %s %s' % (p, n))
    for t in rep['trims']:
        if t['gap'] > TRIM_GAP:
            fails.append('trim %s %s at %s floats %.1f cm off its surface' % (t['part'], t['region'], t['center'], t['gap'] * 100))
    for o in rep['openings']:
        lim = loose.get(o['region'], OPEN_GAP.get(o['region'], 0.016))
        if o['gap'] > lim:
            fails.append('opening %s %s at %s gap %.1f cm (bound %.1f)' % (o['part'], o['region'], o['center'], o['gap'] * 100, lim * 100))
    for s, dpt in rep['crossing'].items():
        if dpt > CROSS_MAX:
            fails.append('crossing %s: the trouser leg crosses the midline by %.1f cm' % (s, dpt * 100))
    if rep['seams']['attached_max_grow'] > SEAM_GROW:
        fails.append('seam separates %.1f cm (%s)' % (rep['seams']['attached_max_grow'] * 100, rep['seams'].get('attached_worst')))
    if rep['seams']['junction_max_grow'] > JUNCTION_GROW:
        fails.append('junction opens %.1f cm (%s)' % (rep['seams']['junction_max_grow'] * 100, rep['seams'].get('junction_worst')))
    # standoff: at rest, and the patch / edge pairs through the clips
    fails += standoff_failures(rep)
    if len(spairs):
        # (a piece whose weights differ from its surface face's (a face
        # spanning a joint's blend, a piece on another bone): the junction
        # bound, as for layers across a joint)
        nj = len(look.g.joint_names)

        def dense(v):
            W = np.zeros((len(v), nj))
            np.add.at(W, (np.repeat(np.arange(len(v)), look.joints.shape[1]), look.joints[v].reshape(-1)), look.weights[v].reshape(-1))
            return W
        Wv = dense(spairs[:, 0])
        wdiff = np.max([np.abs(Wv - dense(spairs[:, c])).sum(1) for c in (1, 2, 3)], axis=0)
        lim = np.where(wdiff <= 0.1, SEAM_GROW, JUNCTION_GROW)
        i = int(np.argmax(sgrow - lim))
        rep['standoff_motion'] = {'pairs': int(len(spairs)), 'max_grow': round(float(sgrow.max()), 4),
                                  'worst': {'pose': [poses[sgrow_pose[i]][0], round(float(poses[sgrow_pose[i]][1]), 3)],
                                            'at': [round(float(v), 3) for v in P[spairs[i, 0]]], 'grow': round(float(sgrow[i]), 4),
                                            'bound': float(lim[i]), 'parts': [look.parts[look.pid[spairs[i, 0]]],
                                                                             look.parts[look.pid[spairs[i, 1]]]]}}
        if sgrow[i] > lim[i]:
            fails.append('standoff pair parts %.1f cm in %s (bound %.1f; %s)' % (sgrow[i] * 100, rep['standoff_motion']['worst']['pose'],
                                                                                 lim[i] * 100, rep['standoff_motion']['worst']['at']))
    else:
        rep['standoff_motion'] = {'pairs': 0, 'max_grow': 0.0}
    rep['failures'] = fails
    anchors = None
    if want_anchors:
        anchors = make_anchors(look, trims, opens, pairs, grow, key)
    return rep, anchors


def _allowed(s):
    for part, c, bound, why in STANDOFF_ALLOW:
        if s['part'] == part and np.linalg.norm(np.array(s['center']) - np.array(c)) < 0.02:
            return bound, why
    return None


def _plane_dist(v, a, b, c):
    """Signed distance of points v from the planes of the faces (a, b, c)."""
    n = np.cross(b - a, c - a)
    n /= np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]
    return np.einsum('ij,ij->i', v - a, n)


def standoff_failures(rep):
    fails = []
    for s in rep.get('patches', []):
        panel = s['size'][1] >= PANEL_SIZE
        lim = PATCH_GAP if panel else SMALL_GAP
        al = _allowed(s)
        if al:
            lim = al[0]
            s['allowed'] = al[1]
        s['bound'] = lim
        if s['overhang'] and panel and not al:
            fails.append('panel %s at %s overhangs the %s under it' % (s['part'], s['center'], s['on']))
        elif s['gap'] > lim and not s['overhang']:
            fails.append('%s %s at %s stands %.1f cm off the %s (at %s; bound %.1f)' % (
                'panel' if panel else 'patch', s['part'], s['center'], s['gap'] * 100, s['on'], s['at'], lim * 100))
    for s in rep.get('bands', []):
        al = _allowed(s)
        lim = al[0] if al else (FACE_RIM_GAP if s['kind'] == 'face rim' else BAND_GAP)
        if al:
            s['allowed'] = al[1]
        if s['gap'] > lim:
            fails.append('%s %s at %s stands %.1f cm off the head (at %s; bound %.1f)' % (s['kind'], s['part'], s['center'], s['gap'] * 100,
                                                                                         s['at'], lim * 100))
    sil = rep.get('silhouette')
    if sil:
        if sil['shoulders'] > SHOULDER_OUT:
            fails.append('top %s stands %.1f cm off the torso across the upper chest and back (at %s; bound %.1f)' % (
                sil['shoulders_part'], sil['shoulders'] * 100, sil['shoulders_at'], SHOULDER_OUT * 100))
        if sil['skirt_flare'] > SKIRT_FLARE:
            fails.append('the back of %s flares %.1f cm out at its hem beyond its waist (at %s; bound %.1f)' % (
                sil['skirt_part'], sil['skirt_flare'] * 100, sil['skirt_at'], SKIRT_FLARE * 100))
    for s in rep.get('edges', []):
        if s['gap'] > EDGE_GAP:
            fails.append('front edge of %s stands %.1f cm off the %s (at %s; mean %.1f; bound %.1f)' % (
                s['part'], s['gap'] * 100, s['on'], s['at'], s['gap_mean'] * 100, EDGE_GAP * 100))
    return fails


def analyze_head(g, key, parts):
    """A hat (or an outfit's headwear) with one hair style, rest pose: head
    pieces are rigid on the head bone, so the rest pose is every pose."""
    look = Look(g, parts)
    P, N = look.pos, look.nrm
    tri = Tris(look, P)
    info = _island_info(look, P)
    rep = {'parts': look.parts, 'bands': check_bands(look, P, N, tri, info),
           'patches': [{k: v for k, v in s.items() if k != 'anchors'} for s in check_patches(look, P, N, tri, info) if s['group'] == 'head']}
    rep['failures'] = standoff_failures(rep)
    return rep


# poses whose skinned anchor positions go into the fixture: the game must
# reproduce them from the imported scene (imported-vs-runtime comparison)
REFERENCE_POSES = [('run', 0.3), ('dive', 0.3), ('emote_cheer', 0.3), ('land_hard', 0.15), ('cart_drive', 0.3)]
REFERENCE_LOOKS = {'pj', 'midnight_mechanic', 'moonwalk_cadet', 'pumpkin_pajamas', 'arcade_sprinter', 'cloud_nine', 'bedtime_bandit',
                   'after_hours_hoodie', 'night_owl', 'glow_jogger', 'library_cardigan', 'record_breaker', 'dr_doom'}


def make_anchors(look, trims, opens, pairs, grow, key):
    """Vertex pairs for the in-game check (tests/test_fit_p9.gd), re-measured
    on the imported scene in final blended poses: a few per trim (a ring
    vertex and the surface vertex under it), per visible opening (an edge
    vertex and the nearest outward surface vertex of the same segment) and
    the seams that moved most in the clips.  Each carries its bound on how
    far the pair may part from its rest distance, and for limb anchors the
    rest distance of `a` from its limb's axis (`axis`: the bones of the
    segment, `r`)."""
    P = look.pos
    N = look.nrm
    g = look.g
    out = []
    dom = look.joints[np.arange(len(look.joints)), look.weights.argmax(1)]
    rest_glob = joint_globals(g)

    def add(kind, a, b, bound):
        grp = look.group[a]
        e = {'kind': kind, 'a': [look.parts[look.pid[a]], [round(float(v), 5) for v in gl_back(P[a])]],
             'b': [look.parts[look.pid[b]], [round(float(v), 5) for v in gl_back(P[b])]],
             'rest': round(float(np.linalg.norm(P[a] - P[b])), 5),
             'bound': bound if dom[a] == dom[b] else max(bound, JUNCTION_GROW), 'group': grp}
        if grp != 'torso' and grp != 'head':
            pts = chain_points(g, rest_glob, grp)
            e['r'] = round(float(axis_project(P[a][None, :], pts)[0][0]), 5)
        out.append(e)

    foot_j = np.array([n.startswith('foot') for n in g.joint_names])
    foot_share = (look.weights * foot_j[look.joints]).sum(1)

    def over_shoe(a, b):
        # a pair across the ankle (a hem over footwear, a shoe collar round
        # the shin): the two ends follow the foot to different extents, and
        # the foot flexes and pivots under the hem, which follows the shin
        return abs(float(foot_share[a]) - float(foot_share[b])) > 0.2

    for t in trims:
        idx = t['verts']
        # (the surface under the ring: another piece on the same segment, so
        # an arm's ring is never paired with the torso it happens to touch)
        others = np.where((look.isl != t['island']) & (look.group == look.group[idx[0]]))[0]
        if len(others) == 0:
            continue
        for v in idx[::max(1, len(idx) // 4)][:4]:
            d = np.linalg.norm(P[others] - P[v], axis=1)
            b = int(others[d.argmin()])
            add('trim', int(v), b, OVER_SHOE_GROW if over_shoe(int(v), b) else SEAM_GROW)
    for o in opens:
        L = o['verts']
        isl = look.isl[L[0]]
        c = P[L].mean(0)
        rad = P - c
        outward = np.einsum('ij,ij->i', N, rad) > 0.0
        others = np.where((look.isl != isl) & (look.group == look.group[L[0]]) & outward)[0]
        if len(others) == 0:
            continue
        for v in L[::max(1, len(L) // 4)][:4]:
            d = np.linalg.norm(P[others] - P[v], axis=1)
            b = int(others[d.argmin()])
            add('opening', int(v), b, OVER_SHOE_GROW if over_shoe(int(v), b) else JUNCTION_GROW)
    if len(pairs):
        # (a stable order on rounded values: left/right twins tie, and the
        # fixture must not depend on the numpy build's tie order)
        for i in np.argsort(-np.round(grow, 5), kind='stable')[:12]:
            add('seam', int(pairs[i, 0]), int(pairs[i, 1]), SEAM_GROW)
    ref = []
    if key in REFERENCE_LOOKS:
        idx_a = []
        for e in out:
            idx_a.append(_find(look, e['a']))
            idx_a.append(_find(look, e['b']))
        idx_a = np.array(idx_a, dtype=np.int64)
        for clip, t in REFERENCE_POSES:
            glob = joint_globals(g, clip, t)
            jm = np.stack([glob[n] for n in g.joint_names]) @ g.ibm
            Q = look.posed_idx(jm, idx_a)
            ref.append({'clip': clip, 't': t, 'pos': [[round(float(v), 5) for v in gl_back(q)] for q in Q]})
    return out, ref


def _find(look, pv):
    part, pos = pv
    k = look.parts.index(part)
    q = np.array([pos[0], -pos[2], pos[1]])
    sel = np.where(look.pid == k)[0]
    return int(sel[np.linalg.norm(look.pos[sel] - q, axis=1).argmin()])


def gl_back(p):
    """rig axes -> glTF / Godot axes."""
    return np.array([p[0], p[2], -p[1]])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--glb', default=GLB)
    ap.add_argument('--looks', default='')
    ap.add_argument('--json', default='')
    ap.add_argument('--anchors', default='')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--heads', default='', help="hat+hair looks for the bands check (default: all, unless --looks is given)")
    a = ap.parse_args()
    g = Glb(a.glb)
    L = looks()
    keys = [k for k in a.looks.split(',') if k] or list(L)
    poses = poses_of(g)
    pose_data = []
    for c, t in poses:
        glob = joint_globals(g, c, t)
        jm = np.stack([glob[n] for n in g.joint_names]) @ g.ibm
        pose_data.append((jm, glob))
    report = {'glb': os.path.relpath(a.glb, REPO), 'poses': len(poses), 'sample_hz': SAMPLE_HZ, 'looks': {}}
    anchors = {}
    nfail = 0
    for k in keys:
        rep, anc = analyze(g, k, L[k], poses, pose_data, bool(a.anchors))
        report['looks'][k] = rep
        if anc is not None:
            anchors[k] = {'parts': L[k], 'pairs': anc[0], 'reference': anc[1]}
        nfail += len(rep['failures'])
        if not a.quiet:
            worst_t = max([t['gap'] for t in rep['trims']] or [0.0])
            worst_o = max([o['gap'] for o in rep['openings']] or [0.0])
            cross = max(rep['crossing'].values() or [0.0])
            print('%-20s trims %2d (worst %4.1f cm)  openings %2d (worst %4.1f cm)  crossing %4.1f cm  seams %4d (grow %4.1f cm)  %s' % (
                k, len(rep['trims']), worst_t * 100, len(rep['openings']), worst_o * 100, cross * 100, rep['seams']['pairs'],
                rep['seams']['max_grow'] * 100, 'FAIL %d' % len(rep['failures']) if rep['failures'] else 'ok'))
            sil = rep['silhouette']
            print('%-20s standoff: patches %2d (worst panel %4.1f cm)  bands %d (worst %4.1f cm)  edges %d (worst %4.1f cm)  '
                  'pairs %d (grow %4.1f cm)  shoulders %4.1f cm  skirt flare %4.1f cm' % (
                      '', len(rep['patches']), _worst([s for s in rep['patches'] if s['size'][1] >= PANEL_SIZE]) * 100,
                      len(rep['bands']), _worst(rep['bands']) * 100, len(rep['edges']), _worst(rep['edges']) * 100,
                      rep['standoff_motion']['pairs'], rep['standoff_motion']['max_grow'] * 100, sil['shoulders'] * 100,
                      max(sil['skirt_flare'], 0.0) * 100))
            for f in rep['failures']:
                print('    - ' + f)
    # head pieces (hats, outfit headwear) with every hair style: bands and patches
    hk = [k for k in a.heads.split(',') if k] if a.heads else (list(head_looks()) if not a.looks else [])
    HL = head_looks()
    for k in hk:
        rep = analyze_head(g, k, HL[k])
        report.setdefault('heads', {})[k] = rep
        nfail += len(rep['failures'])
        if not a.quiet:
            print('%-26s bands %d (worst %4.1f cm)  patches %d (worst %4.1f cm)  %s' % (
                k, len(rep['bands']), _worst(rep['bands']) * 100, len(rep['patches']), _worst(rep['patches']) * 100,
                'FAIL %d' % len(rep['failures']) if rep['failures'] else 'ok'))
            for f in rep['failures']:
                print('    - ' + f)
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(report, f, indent=1, sort_keys=True)
    if a.anchors:
        with open(a.anchors, 'w') as f:
            json.dump({'glb_sha256': g_sha(a.glb), 'looks': anchors}, f, sort_keys=True, separators=(',', ':'))
    print('fit_check: %d looks, %d poses, %d head looks (hat x hair), %d failures' % (len(keys), len(poses), len(hk), nfail))
    return 1 if nfail else 0


def _worst(items):
    return max([min(s['gap'], 9.0) for s in items] or [0.0])


def g_sha(path):
    import hashlib
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


if __name__ == '__main__':
    sys.exit(main())
