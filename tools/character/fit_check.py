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
        Q = look.posed_idx(jm, np.concatenate([pairs.reshape(-1), garment]))
        if len(pairs):
            A = Q[:2 * len(pairs)].reshape(-1, 2, 3)
            d = np.linalg.norm(A[:, 0] - A[:, 1], axis=1) - d0
            u = d > grow
            grow[u] = d[u]
            grow_pose[u] = k
        G = Q[2 * len(pairs):]
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
    rep['failures'] = fails
    anchors = None
    if want_anchors:
        anchors = make_anchors(look, trims, opens, pairs, grow, key)
    return rep, anchors


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
            for f in rep['failures']:
                print('    - ' + f)
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(report, f, indent=1, sort_keys=True)
    if a.anchors:
        with open(a.anchors, 'w') as f:
            json.dump({'glb_sha256': g_sha(a.glb), 'looks': anchors}, f, sort_keys=True, separators=(',', ':'))
    print('fit_check: %d looks, %d poses, %d failures' % (len(keys), len(poses), nfail))
    return 1 if nfail else 0


def g_sha(path):
    import hashlib
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


if __name__ == '__main__':
    sys.exit(main())
