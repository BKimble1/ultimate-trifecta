"""Moonbrook campus art kit (V5): original, procedural vegetation and rock
meshes built with Blender's Python module.

    tools/campus/build.sh            # this script, then the Godot import

Every asset is generated from the parameters in this file (no scanned or
third-party data).  Crowns, shrubs and rocks are metaball volumes, polygonised
and decimated to fixed triangle budgets per LOD; trunks and branches are
tubes along hand-placed curves with a root flare.  Vertex colours carry the
look: a species palette, soft sky-facing gradients, hue drift between leaf
clusters and ambient occlusion ray-cast against the asset itself and the
ground (Blender's BVH).  No textures are needed for these meshes.

Output: art_src/campus/raw/<name>.utm (one per mesh and LOD) and
art_src/campus/raw/manifest.json, converted by tools/campus/import_kit.gd
into game/assets/campus/campus_kit.res.  Optionally (--blend) the generated
objects are saved to art_src/campus/campus_kit.blend for inspection/editing.

UTM layout (little-endian): b"UTM1", u32 vertex count, u32 index count,
then float32 positions (3), float32 normals (3), uint8 sRGB colours (4),
float32 uv (2: material id, parameter), float32 custom (2: emission, sway),
uint32 indices (triangles, clockwise front faces as Godot expects).
"""

import bpy
import bmesh
import json
import math
import os
import random
import struct
import sys
from mathutils import Vector, Matrix, Quaternion, noise
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "art_src", "campus", "raw")

# material ids read by the world shaders (UV.x); keep in sync with
# game/assets/shaders/world_common.gdshaderinc
M_PLAIN, M_LEAF, M_BARK, M_ROCK, M_PETAL = 0.0, 10.0, 11.0, 12.0, 13.0

REF_H = 8.0   # trees are authored 8 m tall and scaled per instance


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def reset():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for mb in list(bpy.data.metaballs):
        bpy.data.metaballs.remove(mb)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def mix3(a, b, t):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def mul3(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


class Part:
    """Triangle mesh being assembled: positions, normals, colours (sRGB 0..1),
    uv (material id, param), custom (emission, sway)."""

    def __init__(self):
        self.v, self.n, self.c, self.uv, self.cu, self.idx = [], [], [], [], [], []

    def add(self, other):
        base = len(self.v)
        self.v += other.v
        self.n += other.n
        self.c += other.c
        self.uv += other.uv
        self.cu += other.cu
        self.idx += [i + base for i in other.idx]

    def tris(self):
        return len(self.idx) // 3


def mesh_to_part(me, mat_id):
    """Blender mesh (any polygons) -> Part with smooth vertex normals."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    p = Part()
    bm.verts.index_update()
    for v in bm.verts:
        p.v.append(v.co.copy())
        p.n.append(v.normal.copy())
        p.c.append((1.0, 1.0, 1.0, 1.0))
        p.uv.append((mat_id, 0.0))
        p.cu.append((0.0, 0.0))
    for f in bm.faces:
        a, b, c = (f.verts[0].index, f.verts[1].index, f.verts[2].index)
        # Blender is counter-clockwise front; Godot wants clockwise
        p.idx += [a, c, b]
    bm.free()
    return p


def metaball_part(elements, resolution, threshold=0.6, target_tris=None, mat_id=M_LEAF):
    """elements: dicts {co, r, type, size(x,y,z), rot(Quaternion), stiff}."""
    for ob in list(bpy.data.objects):
        if ob.type == 'META':
            bpy.data.objects.remove(ob, do_unlink=True)
    mb = bpy.data.metaballs.new("kitmb")
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = threshold
    ob = bpy.data.objects.new("kitmb", mb)
    bpy.context.scene.collection.objects.link(ob)
    for e in elements:
        el = mb.elements.new()
        el.co = e["co"]
        el.radius = e.get("r", 1.0)
        el.stiffness = e.get("stiff", 2.0)
        t = e.get("type", "BALL")
        el.type = t
        if t == "ELLIPSOID":
            sx, sy, sz = e["size"]
            el.size_x, el.size_y, el.size_z = sx, sy, sz
        if "rot" in e:
            el.rotation = e["rot"]
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.metaballs.remove(mb)
    if target_tris:
        me = decimate(me, target_tris)
    return mesh_to_part(me, mat_id)


def decimate(me, target_tris):
    ob = bpy.data.objects.new("dec", me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
    n = len(bm.faces)
    bm.to_mesh(me)
    bm.free()
    if n > target_tris:
        mod = ob.modifiers.new("d", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = target_tris / float(n)
        mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    else:
        me2 = me.copy()
    bpy.data.objects.remove(ob, do_unlink=True)
    return me2


def tube(path, radii, sides, mat_id=M_BARK, flare=None, cap_top=True, twist=0.0):
    """A tube through `path` (list of Vector) with a radius per point; smooth
    normals; optional root flare: (amount, lobes) bulges the first rings."""
    p = Part()
    n = len(path)
    # parallel-transport frames
    tangents = []
    for i in range(n):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    up = Vector((1, 0, 0)) if abs(tangents[0].z) > 0.9 else Vector((0, 0, 1))
    normal = tangents[0].cross(up).normalized()
    frames = []
    for i in range(n):
        if i > 0:
            axis = tangents[i - 1].cross(tangents[i])
            if axis.length > 1e-6:
                ang = tangents[i - 1].angle(tangents[i])
                normal = (Matrix.Rotation(ang, 3, axis.normalized()) @ normal).normalized()
        binorm = tangents[i].cross(normal).normalized()
        frames.append((normal.copy(), binorm))
    rings = []
    for i in range(n):
        nm, bn = frames[i]
        ring = []
        for s in range(sides):
            a = 2 * math.pi * s / sides + twist * i
            d = nm * math.cos(a) + bn * math.sin(a)
            r = radii[i]
            if flare and i < flare[2]:
                k = (1.0 - i / float(flare[2])) ** 2
                r *= 1.0 + flare[0] * k * (0.6 + 0.4 * math.cos(a * flare[1]))
            ring.append(len(p.v))
            p.v.append(path[i] + d * r)
            p.n.append(d.copy())
            p.c.append((1, 1, 1, 1))
            p.uv.append((mat_id, i / float(n - 1)))
            p.cu.append((0.0, 0.0))
        rings.append(ring)
    for i in range(n - 1):
        for s in range(sides):
            a = rings[i][s]
            b = rings[i][(s + 1) % sides]
            c = rings[i + 1][(s + 1) % sides]
            d = rings[i + 1][s]
            # outward faces, clockwise seen from outside (Godot)
            p.idx += [a, c, b, a, d, c]
    if cap_top:
        tip = len(p.v)
        p.v.append(path[-1] + tangents[-1] * radii[-1] * 0.6)
        p.n.append(tangents[-1].copy())
        p.c.append((1, 1, 1, 1))
        p.uv.append((mat_id, 1.0))
        p.cu.append((0.0, 0.0))
        for s in range(sides):
            p.idx += [rings[-1][s], tip, rings[-1][(s + 1) % sides]]
    return p


def bvh_of(parts, ground=True):
    verts, polys = [], []
    for pt in parts:
        base = len(verts)
        verts += [tuple(v) for v in pt.v]
        for i in range(0, len(pt.idx), 3):
            polys.append((pt.idx[i] + base, pt.idx[i + 1] + base, pt.idx[i + 2] + base))
    if ground:
        base = len(verts)
        G = 40.0
        verts += [(-G, -G, 0.0), (G, -G, 0.0), (G, G, 0.0), (-G, G, 0.0)]
        polys += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return BVHTree.FromPolygons(verts, polys, all_triangles=True)


_DIRS = []


def _hemi_dirs(k=28):
    if _DIRS:
        return _DIRS
    rng = random.Random(7)
    for i in range(k):
        # cosine-weighted (Fibonacci-ish, jittered)
        u = (i + rng.random()) / k
        phi = 2 * math.pi * ((i * 0.61803398875) % 1.0)
        r = math.sqrt(u)
        _DIRS.append(Vector((r * math.cos(phi), r * math.sin(phi), math.sqrt(max(0.0, 1 - u)))))
    return _DIRS


def ambient_occlusion(part, bvh, max_d=2.5, bias=0.03):
    """Per-vertex AO (1 = open) by ray casting a cosine hemisphere."""
    dirs = _hemi_dirs()
    out = []
    for v, n in zip(part.v, part.n):
        nn = n.normalized()
        t = Vector((0, 0, 1)) if abs(nn.z) < 0.9 else Vector((1, 0, 0))
        tx = nn.cross(t).normalized()
        ty = nn.cross(tx)
        o = v + nn * bias
        hit = 0.0
        for d in dirs:
            w = tx * d.x + ty * d.y + nn * d.z
            loc, _, _, dist = bvh.ray_cast(o, w, max_d)
            if loc is not None:
                hit += 1.0 - 0.5 * (dist / max_d)
        out.append(1.0 - hit / len(dirs))
    return out


def jitter_noise(v, scale, seed):
    return noise.noise(v * scale + Vector((seed * 1.7, seed * 3.1, seed * 0.9)))


# ---------------------------------------------------------------------------
# trees
# ---------------------------------------------------------------------------
def crown_elements(center, radii, count, cl_r, seed, top_bias=0.35, core=0.85):
    """Cloud-like crown: a soft core plus leaf clusters spread over the upper
    part of an ellipsoid (fewer underneath, so the canopy reads lit-from-above
    with a shadowed belly)."""
    rng = random.Random(seed)
    els = [{"co": center, "type": "ELLIPSOID", "r": 1.0, "size": (radii[0] * core, radii[1] * core, radii[2] * core), "stiff": 2.0}]
    clusters = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(count):
        y = 1.0 - (i + 0.5) / count * (2.0 - top_bias * 0.8)
        y = max(-0.78, min(0.95, y))
        rr = math.sqrt(max(0.0, 1.0 - y * y))
        th = golden * i + rng.uniform(-0.35, 0.35)
        d = Vector((math.cos(th) * rr, math.sin(th) * rr, y))
        pos = center + Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2])) * rng.uniform(0.62, 0.8)
        r = cl_r * rng.uniform(0.8, 1.2) * (1.0 - 0.12 * max(0.0, -y))
        els.append({"co": pos, "r": r, "type": "BALL", "stiff": 2.0})
        clusters.append((pos, r))
    return els, clusters


def color_leaves(part, crown_c, crown_r, pal, ao, seed, petal_mix=None):
    """Leaf colours: sky-facing light, shaded belly, cluster hue drift, AO."""
    dark, mid, light = pal["dark"], pal["mid"], pal["light"]
    for i, (v, n) in enumerate(zip(part.v, part.n)):
        d = v - crown_c
        e = Vector((d.x / crown_r[0], d.y / crown_r[1], d.z / crown_r[2]))
        sph = Vector((e.x / crown_r[0], e.y / crown_r[1], e.z / crown_r[2])).normalized()
        # soften the shading normal toward the crown's ellipsoid normal
        sn = (n.normalized() * 0.45 + sph * 0.55).normalized()
        part.n[i] = sn
        sky = smoothstep(-0.65, 0.95, sn.z)
        col = mix3(dark, mid, smoothstep(0.0, 0.55, sky))
        col = mix3(col, light, smoothstep(0.55, 1.0, sky))
        # cluster-scale hue drift (some clumps warmer, some cooler)
        h = jitter_noise(v, 0.55, seed)
        col = mix3(col, pal.get("warm", light), max(0.0, h) * 0.35)
        col = mix3(col, pal.get("cool", dark), max(0.0, -h) * 0.25)
        if petal_mix is not None:
            pm = smoothstep(0.1, 0.5, jitter_noise(v, 1.6, seed + 5)) * smoothstep(-0.2, 0.6, sn.z)
            col = mix3(col, petal_mix, pm * 0.85)
        a = ao[i]
        k = lerp(0.42, 1.0, a ** 0.8)
        # belly: the underside of the crown is darker still
        k *= lerp(0.72, 1.0, smoothstep(-0.9, 0.2, e.z))
        part.c[i] = (col[0] * k, col[1] * k, col[2] * k, 1.0)
        # sway grows away from the trunk and with height
        sw = smoothstep(0.3, 1.0, (v.z) / REF_H) * (0.55 + 0.45 * min(1.0, Vector((v.x, v.y)).length / 3.0))
        part.cu[i] = (0.0, sw)


def color_bark(part, pal, ao, birch=False, seed=0):
    for i, v in enumerate(part.v):
        base = pal["bark"]
        if birch:
            # white bark with dark lenticel bands
            band = noise.noise(Vector((v.x * 3.0, v.y * 3.0, v.z * 2.6 + seed)))
            base = mix3((0.86, 0.85, 0.80), (0.20, 0.19, 0.18), smoothstep(0.35, 0.55, band))
        else:
            g = noise.noise(Vector((v.x * 4.0, v.y * 4.0, v.z * 1.2 + seed)))
            base = mix3(base, mul3(base, 0.72), smoothstep(-0.2, 0.6, g))
        # darker at the root, a little moss on the north-ish flare
        k = lerp(0.55, 1.0, ao[i] ** 0.9) * lerp(0.75, 1.0, smoothstep(0.0, 1.2, v.z))
        if v.z < 0.9 and not birch:
            base = mix3(base, (0.24, 0.32, 0.18), 0.35 * (1.0 - v.z / 0.9))
        part.c[i] = (base[0] * k, base[1] * k, base[2] * k, 1.0)
        part.cu[i] = (0.0, smoothstep(2.5, REF_H, v.z) * 0.35)


def trunk_with_branches(spec, lod, clusters, rng):
    h = spec["trunk_h"]
    r0 = spec["trunk_r"]
    lean = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 0.0)) * spec.get("lean", 1.0)
    steps = [0.0, 0.08, 0.22, 0.45, 0.7, 1.0] if lod == 0 else ([0.0, 0.2, 0.6, 1.0] if lod == 1 else [0.0, 1.0])
    path, radii = [], []
    for t in steps:
        wob = Vector((math.sin(t * 5.1 + rng.random()) * 0.08, math.cos(t * 4.3) * 0.08, 0.0)) if lod == 0 else Vector()
        path.append(Vector((0, 0, h * t)) + lean * (t * t) + wob * t)
        radii.append(lerp(r0, r0 * spec.get("taper", 0.45), t ** 0.8))
    sides = [9, 6, 4][lod]
    flare = (spec.get("flare", 0.55), 5, 3 if lod == 0 else 2) if lod < 2 else None
    p = tube(path, radii, sides, M_BARK, flare=flare)
    if lod < 2:
        nb = spec.get("branches", 4) if lod == 0 else min(2, spec.get("branches", 4))
        cl = sorted(clusters, key=lambda c: -c[0].z)
        picks = [cl[int(i * len(cl) / max(nb, 1)) % len(cl)] for i in range(nb)]
        for bi, (cp, cr) in enumerate(picks):
            start_t = rng.uniform(0.55, 0.85)
            st = Vector((0, 0, h * start_t)) + lean * start_t * start_t
            end = st.lerp(cp, 0.82)
            mid = st.lerp(end, 0.5) + Vector((0, 0, 0.35))
            br = r0 * 0.42
            bpts = [st, mid, end]
            p.add(tube(bpts, [br, br * 0.7, br * 0.35], 5 if lod == 0 else 4, M_BARK, cap_top=True))
    return p


def build_broad(name, spec, lod):
    rng = random.Random(spec["seed"])
    c = Vector(spec["crown_c"])
    r = spec["crown_r"]
    els, clusters = crown_elements(c, r, spec["clusters"], spec["cl_r"], spec["seed"], spec.get("top_bias", 0.35))
    if spec.get("extra"):
        for (co, rad) in spec["extra"]:
            els.append({"co": Vector(co), "r": rad, "type": "BALL"})
            clusters.append((Vector(co), rad))
    budget = spec["tris"][lod]
    res = [0.16, 0.28, 0.5][lod]
    crown = metaball_part(els, res, 0.6, budget, M_LEAF)
    # gentle organic irregularity (not on the far LOD)
    if lod < 2:
        for i, v in enumerate(crown.v):
            k = jitter_noise(v, 0.9, spec["seed"]) * 0.14
            crown.v[i] = v + crown.n[i] * k
    trunk = trunk_with_branches(spec, lod, clusters, rng)
    bvh = bvh_of([crown, trunk])
    color_leaves(crown, c, r, spec["pal"], ambient_occlusion(crown, bvh, 3.0), spec["seed"], spec.get("petals"))
    color_bark(trunk, spec["pal"], ambient_occlusion(trunk, bvh, 2.0), spec.get("birch", False), spec["seed"])
    trunk.add(crown)
    return trunk


def build_pine(name, spec, lod):
    """Rounded, irregular conifer: each tier is a puffy skirt (a ring of
    overlapping balls drooping outward around a soft core), tiers shrink
    toward an attached rounded tip; the union is one smooth volume."""
    rng = random.Random(spec["seed"])
    H = REF_H
    tiers = spec["tiers"] if lod < 2 else max(3, spec["tiers"] - 2)
    els = []
    y0 = spec["base"]
    top = H * 0.97
    R = spec["radius"]
    for i in range(tiers):
        f = i / float(tiers)
        y = lerp(y0, top - 1.5, f)
        rr = R * (1.0 - f) ** spec.get("curve", 0.85) + 0.25
        els.append({"co": Vector((0, 0, y + 0.45)), "r": rr * 0.62 + 0.25, "type": "BALL", "stiff": 2.0})
        n = max(6, int(2 * math.pi * rr * 0.72 / spec.get("lobe_w", 0.95)))
        off = rng.uniform(0, math.pi)
        for k in range(n):
            a = off + 2 * math.pi * k / n + rng.uniform(-0.12, 0.12)
            rad = rr * rng.uniform(0.66, 0.8)
            co = Vector((math.cos(a) * rad, math.sin(a) * rad, y - 0.08 * rr + rng.uniform(-0.1, 0.1)))
            els.append({"co": co, "r": 0.38 + 0.22 * rr * rng.uniform(0.85, 1.1), "type": "BALL", "stiff": 2.0})
    # rounded tip, joined to the top tier
    els.append({"co": Vector((0, 0, top - 1.1)), "r": 0.72, "type": "BALL"})
    els.append({"co": Vector((0, 0, top - 0.45)), "r": 0.48, "type": "BALL"})
    budget = spec["tris"][lod]
    res = [0.11, 0.2, 0.36][lod]
    crown = metaball_part(els, res, 0.6, budget, M_LEAF)
    if lod < 2:
        for i, v in enumerate(crown.v):
            crown.v[i] = v + crown.n[i] * jitter_noise(v, 1.1, spec["seed"]) * 0.06
    spec_t = {"trunk_h": H * 0.62, "trunk_r": spec.get("trunk_r", 0.3), "taper": 0.3, "flare": 0.5, "branches": 0, "lean": 0.35}
    trunk = trunk_with_branches(spec_t, lod, [(Vector((0, 0, H * 0.5)), 1.0)], rng)
    bvh = bvh_of([crown, trunk])
    cc = Vector((0, 0, (y0 + top) * 0.5))
    cr = (R * 0.85, R * 0.85, (top - y0) * 0.55)
    color_leaves(crown, cc, cr, spec["pal"], ambient_occlusion(crown, bvh, 2.6), spec["seed"])
    color_bark(trunk, spec["pal"], ambient_occlusion(trunk, bvh, 2.0), False, spec["seed"])
    trunk.add(crown)
    return trunk


# palettes are sRGB (the shader converts to linear)
PAL_OAK = {"dark": (0.10, 0.22, 0.17), "mid": (0.23, 0.44, 0.24), "light": (0.47, 0.64, 0.30), "warm": (0.50, 0.58, 0.24), "cool": (0.12, 0.30, 0.28), "bark": (0.33, 0.24, 0.19)}
PAL_LINDEN = {"dark": (0.11, 0.24, 0.16), "mid": (0.27, 0.49, 0.25), "light": (0.55, 0.70, 0.33), "warm": (0.58, 0.64, 0.28), "cool": (0.14, 0.33, 0.27), "bark": (0.30, 0.23, 0.20)}
PAL_MAPLE = {"dark": (0.24, 0.10, 0.08), "mid": (0.62, 0.27, 0.12), "light": (0.92, 0.56, 0.20), "warm": (0.95, 0.70, 0.26), "cool": (0.48, 0.14, 0.12), "bark": (0.28, 0.21, 0.19)}
PAL_BIRCH = {"dark": (0.14, 0.26, 0.16), "mid": (0.36, 0.55, 0.26), "light": (0.66, 0.76, 0.36), "warm": (0.70, 0.72, 0.30), "cool": (0.20, 0.38, 0.26), "bark": (0.80, 0.79, 0.74)}
PAL_BLOSSOM = {"dark": (0.34, 0.15, 0.22), "mid": (0.86, 0.48, 0.60), "light": (1.0, 0.80, 0.84), "warm": (1.0, 0.84, 0.76), "cool": (0.70, 0.40, 0.56), "bark": (0.27, 0.20, 0.20)}
PAL_FIR = {"dark": (0.06, 0.17, 0.15), "mid": (0.15, 0.34, 0.25), "light": (0.32, 0.52, 0.30), "warm": (0.34, 0.48, 0.26), "cool": (0.08, 0.26, 0.26), "bark": (0.30, 0.22, 0.18)}
PAL_SPRUCE = {"dark": (0.06, 0.15, 0.18), "mid": (0.15, 0.32, 0.32), "light": (0.34, 0.52, 0.46), "warm": (0.30, 0.46, 0.34), "cool": (0.10, 0.26, 0.34), "bark": (0.28, 0.21, 0.18)}
PAL_PINE = {"dark": (0.08, 0.19, 0.14), "mid": (0.20, 0.40, 0.24), "light": (0.40, 0.58, 0.30), "warm": (0.44, 0.54, 0.26), "cool": (0.10, 0.28, 0.24), "bark": (0.40, 0.25, 0.17)}

BROAD = {
    # wide round shade tree: the pond woods and lawns
    "oak": {"seed": 11, "crown_c": (0, 0, 5.0), "crown_r": (2.9, 2.9, 2.5), "clusters": 14, "cl_r": 1.35,
            "trunk_h": 3.9, "trunk_r": 0.34, "branches": 4, "pal": PAL_OAK, "tris": (820, 230, 64)},
    # tall oval street tree: avenues along the College Loop
    "linden": {"seed": 23, "crown_c": (0, 0, 5.1), "crown_r": (2.2, 2.2, 2.9), "clusters": 13, "cl_r": 1.15,
               "trunk_h": 3.6, "trunk_r": 0.3, "branches": 3, "pal": PAL_LINDEN, "tris": (760, 220, 60), "top_bias": 0.45},
    # spreading autumn maple: warm colour accents on the quad
    "maple": {"seed": 37, "crown_c": (0, 0, 4.8), "crown_r": (3.1, 3.1, 2.3), "clusters": 15, "cl_r": 1.25,
              "trunk_h": 3.6, "trunk_r": 0.32, "branches": 5, "pal": PAL_MAPLE, "tris": (820, 230, 64)},
    # slender white-barked birch: airy clumps along the trunk
    "birch": {"seed": 41, "crown_c": (0, 0, 5.6), "crown_r": (1.6, 1.6, 2.4), "clusters": 10, "cl_r": 0.95,
              "trunk_h": 6.4, "trunk_r": 0.2, "taper": 0.4, "branches": 3, "birch": True, "pal": PAL_BIRCH, "tris": (640, 190, 56), "lean": 1.6, "top_bias": 0.2},
    # small flowering tree: Lily Basin and the dorm lawns
    "blossom": {"seed": 53, "crown_c": (0, 0, 4.4), "crown_r": (2.9, 2.9, 2.1), "clusters": 14, "cl_r": 1.15,
                "trunk_h": 3.0, "trunk_r": 0.27, "branches": 5, "pal": PAL_BLOSSOM, "tris": (760, 220, 60), "lean": 1.3},
}
PINES = {
    # tall layered fir with soft drooping tiers
    "fir": {"seed": 61, "tiers": 5, "base": 1.4, "radius": 2.5, "lobe_w": 0.95, "curve": 0.9, "pal": PAL_FIR, "tris": (820, 230, 60)},
    # narrow blue spruce
    "spruce": {"seed": 67, "tiers": 6, "base": 1.1, "radius": 2.0, "lobe_w": 0.85, "curve": 1.0, "pal": PAL_SPRUCE, "tris": (820, 230, 60)},
    # stout rounded pine, broad shoulders, warm bark
    "pine": {"seed": 71, "tiers": 4, "base": 2.4, "radius": 2.7, "lobe_w": 1.1, "curve": 0.55, "pal": PAL_PINE, "tris": (760, 220, 56), "trunk_r": 0.33},
}


# ---------------------------------------------------------------------------
# shrubs, flowers, grass, reeds, lilies, rocks
# ---------------------------------------------------------------------------
def build_shrub(seed, size, pal, tris, flowers=None):
    rng = random.Random(seed)
    els = []
    c = Vector((0, 0, size[2] * 0.48))
    els.append({"co": c, "type": "ELLIPSOID", "r": 1.0, "size": (size[0] * 0.42, size[1] * 0.42, size[2] * 0.38)})
    n = 7
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.28, 0.36)
        co = c + Vector((math.cos(a) * size[0] * rr, math.sin(a) * size[1] * rr, rng.uniform(-0.05, 0.22) * size[2]))
        els.append({"co": co, "r": min(size[0], size[2]) * rng.uniform(0.34, 0.44), "type": "BALL"})
    els.append({"co": c + Vector((0, 0, size[2] * 0.3)), "r": min(size[0], size[2]) * 0.42, "type": "BALL"})
    part = metaball_part(els, 0.05 * max(size), 0.6, tris, M_LEAF)
    for i, v in enumerate(part.v):
        part.v[i] = v + part.n[i] * jitter_noise(v, 4.0, seed) * 0.03 * max(size)
        if part.v[i].z < 0.02:
            part.v[i].z = max(part.v[i].z, -0.05)
    bvh = bvh_of([part])
    ao = ambient_occlusion(part, bvh, 0.6 * max(size), 0.01)
    color_leaves(part, c, (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5), pal, ao, seed)
    for i, v in enumerate(part.v):
        part.cu[i] = (0.0, smoothstep(0.1, size[2], v.z) * 0.25)
    if flowers:
        # flower heads: white petals the shader tints per instance (M_PETAL)
        heads = Part()
        golden = math.pi * (3.0 - math.sqrt(5.0))
        for k in range(flowers):
            y = 1.0 - (k + 0.5) / flowers * 1.2
            rr = math.sqrt(max(0.0, 1 - y * y))
            th = golden * k
            d = Vector((math.cos(th) * rr, math.sin(th) * rr, max(y, -0.1)))
            loc, nrm, _, _ = bvh.ray_cast(c + d * max(size) * 1.5, -d, max(size) * 2)
            if loc is None:
                continue
            hr = 0.13 * max(size) * rng.uniform(0.8, 1.2)
            hp = petal_head(loc + nrm * 0.03, hr)
            for i in range(len(hp.v)):
                hp.cu[i] = (0.0, 0.2)
            heads.add(hp)
        part.add(heads)
    return part


def build_grass(seed, tris_hint=40):
    """A tuft of blades as slim three-sided spikes (solid from every side, so
    no double-sided material is needed)."""
    rng = random.Random(seed)
    p = Part()
    n = 9
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.4, 0.4)
        base = Vector((math.cos(a) * rng.uniform(0.02, 0.1), math.sin(a) * rng.uniform(0.02, 0.1), 0.0))
        h = rng.uniform(0.22, 0.42)
        lean = Vector((math.cos(a), math.sin(a), 0.0)) * rng.uniform(0.06, 0.16)
        tip = base + lean + Vector((0, 0, h))
        w = 0.028
        corners = []
        for j in range(3):
            b = 2 * math.pi * j / 3 + a
            corners.append(base + Vector((math.cos(b) * w, math.sin(b) * w, 0.0)))
        i0 = len(p.v)
        for cpos in corners + [tip]:
            p.v.append(cpos)
            d = (cpos - base)
            d.z = 0.35
            p.n.append(d.normalized())
            t = cpos.z / 0.42
            col = mix3((0.13, 0.28, 0.16), (0.42, 0.60, 0.30), smoothstep(0.0, 1.0, t))
            p.c.append((col[0], col[1], col[2], 1.0))
            p.uv.append((M_LEAF, 0.0))
            p.cu.append((0.0, smoothstep(0.0, 0.4, cpos.z) * 0.9))
        for j in range(3):
            p.idx += [i0 + j, i0 + 3, i0 + (j + 1) % 3]
    return p


def build_flowers(seed):
    """A low clump of leaves with a few flower heads the shader tints."""
    rng = random.Random(seed)
    leaves = metaball_part([{"co": Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 0.08)), "r": rng.uniform(0.13, 0.17), "type": "BALL"} for _ in range(6)]
                           + [{"co": Vector((0, 0, 0.1)), "type": "ELLIPSOID", "r": 1.0, "size": (0.2, 0.2, 0.08)}], 0.04, 0.6, 36, M_LEAF)
    for i, v in enumerate(leaves.v):
        sky = smoothstep(-0.4, 1.0, leaves.n[i].z)
        col = mix3((0.10, 0.22, 0.14), (0.30, 0.50, 0.26), sky)
        leaves.c[i] = (col[0], col[1], col[2], 1.0)
        leaves.cu[i] = (0.0, 0.15)
    for k in range(6):
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.06, 0.2)
        co = Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(0.2, 0.32)))
        hp = petal_head(co, 0.07)
        for i in range(len(hp.v)):
            g = lerp(0.7, 1.0, smoothstep(-0.5, 1.0, hp.n[i].z))
            hp.c[i] = (g, g, g, 1.0)
            hp.cu[i] = (0.0, 0.4)
        leaves.add(hp)

    return leaves


def petal_head(co, r):
    """A five-petal star flower head as a low pyramid fan (10 triangles),
    white so the shader can tint it per instance."""
    p = Part()
    p.v.append(co + Vector((0, 0, 0.025)))
    p.n.append(Vector((0, 0, 1)))
    p.c.append((1.0, 0.95, 0.75, 1.0))
    p.uv.append((M_PETAL, 0.0))
    p.cu.append((0.0, 0.4))
    for k in range(10):
        a = 2 * math.pi * k / 10
        rr = r if k % 2 == 0 else r * 0.45
        p.v.append(co + Vector((math.cos(a) * rr, math.sin(a) * rr, -0.01 if k % 2 == 0 else 0.0)))
        p.n.append(Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, 1)).normalized())
        p.c.append((1.0, 1.0, 1.0, 1.0) if k % 2 == 0 else (0.85, 0.85, 0.85, 1.0))
        p.uv.append((M_PETAL, 0.0))
        p.cu.append((0.0, 0.4))
    for k in range(10):
        p.idx += [0, 1 + (k + 1) % 10, 1 + k]
    return p


def build_reeds(seed):
    """Reeds and cattails for the pond banks."""
    rng = random.Random(seed)
    p = Part()
    for k in range(11):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.32)
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.15))
        h = rng.uniform(0.9, 1.55)
        lean = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.05, 0.25)
        blade = Part()
        w = 0.03
        corners = [base + Vector((math.cos(2 * math.pi * j / 3 + a) * w, math.sin(2 * math.pi * j / 3 + a) * w, 0)) for j in range(3)]
        tip = base + lean + Vector((0, 0, h))
        for cpos in corners + [tip]:
            blade.v.append(cpos)
            d = cpos - base
            d.z = 0.25
            blade.n.append(d.normalized())
            col = mix3((0.16, 0.26, 0.14), (0.52, 0.58, 0.30), smoothstep(0.0, h, cpos.z))
            blade.c.append((col[0], col[1], col[2], 1.0))
            blade.uv.append((M_LEAF, 0.0))
            blade.cu.append((0.0, smoothstep(0.0, h, cpos.z)))
        for j in range(3):
            blade.idx += [j, 3, (j + 1) % 3]
        p.add(blade)
    for k in range(3):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.05, 0.25)
        h = rng.uniform(1.1, 1.5)
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.15))
        top = base + Vector((math.cos(a) * 0.08, math.sin(a) * 0.08, h))
        st = tube([base, top], [0.014, 0.01], 4, M_LEAF, cap_top=True)
        for i, v in enumerate(st.v):
            st.c[i] = (0.30, 0.38, 0.18, 1.0)
            st.cu[i] = (0.0, smoothstep(0.0, h, v.z - base.z))
        p.add(st)
        head = tube([top - Vector((0, 0, 0.32)), top - Vector((0, 0, 0.06))], [0.045, 0.045], 6, M_LEAF, cap_top=True)
        for i, v in enumerate(head.v):
            head.c[i] = (0.36, 0.20, 0.11, 1.0)
            head.cu[i] = (0.0, 0.9)
        p.add(head)
    return p


def build_lilies(seed):
    """Three to five notched pads and one cup flower, lying flat (y = 0)."""
    rng = random.Random(seed)
    p = Part()
    pads = rng.randint(3, 5)
    for k in range(pads):
        c = Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0.0))
        r = rng.uniform(0.22, 0.38)
        notch = rng.uniform(0, 2 * math.pi)
        seg = 11
        i0 = len(p.v)
        p.v.append(c + Vector((0, 0, 0.03)))
        p.n.append(Vector((0, 0, 1)))
        g = rng.uniform(0.85, 1.1)
        p.c.append((0.22 * g, 0.42 * g, 0.20 * g, 1.0))
        p.uv.append((M_LEAF, 0.0))
        p.cu.append((0.0, 0.0))
        for s in range(seg + 1):
            a = notch + 0.35 + (2 * math.pi - 0.7) * s / seg
            p.v.append(c + Vector((math.cos(a) * r, math.sin(a) * r, 0.0)))
            p.n.append(Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, 1)).normalized())
            p.c.append((0.14 * g, 0.30 * g, 0.16 * g, 1.0))
            p.uv.append((M_LEAF, 0.0))
            p.cu.append((0.0, 0.0))
        for s in range(seg):
            p.idx += [i0, i0 + 1 + s + 1, i0 + 1 + s]
    # one flower: a little cup of petals (tinted per instance)
    fc = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0.02))
    for k in range(7):
        a = 2 * math.pi * k / 7
        tip = fc + Vector((math.cos(a) * 0.13, math.sin(a) * 0.13, 0.12))
        l = fc + Vector((math.cos(a - 0.4) * 0.05, math.sin(a - 0.4) * 0.05, 0.02))
        r = fc + Vector((math.cos(a + 0.4) * 0.05, math.sin(a + 0.4) * 0.05, 0.02))
        i0 = len(p.v)
        for q in (l, tip, r):
            p.v.append(q)
            p.n.append((Vector((math.cos(a), math.sin(a), 1.2))).normalized())
            p.c.append((1.0, 1.0, 1.0, 1.0))
            p.uv.append((M_PETAL, 0.0))
            p.cu.append((0.0, 0.0))
        p.idx += [i0, i0 + 2, i0 + 1, i0, i0 + 1, i0 + 2]
    i0 = len(p.v)
    p.v.append(fc + Vector((0, 0, 0.07)))
    p.n.append(Vector((0, 0, 1)))
    p.c.append((1.0, 0.85, 0.35, 1.0))
    p.uv.append((M_PLAIN, 0.0))
    p.cu.append((0.6, 0.0))
    return p


def build_rock(seed, kind, tris):
    """Boulders normalised to a 1 x 1 x 1 box (scaled to each collider):
    'round' a soft boulder, 'layer' stacked quarry ledges, 'flat' a slab."""
    rng = random.Random(seed)
    els = []
    if kind == "layer":
        # one massive block with stepped ledges (strata), not a stack of
        # separate slabs: a core plus offset shelves merged together
        els.append({"co": Vector((0, 0, 0.4)), "type": "ELLIPSOID", "r": 1.0, "size": (0.42, 0.38, 0.36), "stiff": 2.0})
        y = 0.08
        for i in range(4):
            th = rng.uniform(0.18, 0.24)
            s = 1.0 - 0.16 * i
            ox, oy = rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1)
            els.append({"co": Vector((ox, oy, y + th * 0.5)), "type": "ELLIPSOID", "r": 1.0, "size": (0.5 * s, 0.46 * s, th * 0.9), "stiff": 2.5})
            y += th * 0.82
        res = 0.04
    elif kind == "flat":
        els.append({"co": Vector((0, 0, 0.25)), "type": "ELLIPSOID", "r": 1.0, "size": (0.5, 0.45, 0.22), "stiff": 3.0})
        els.append({"co": Vector((0.15, -0.1, 0.32)), "type": "ELLIPSOID", "r": 1.0, "size": (0.3, 0.28, 0.15), "stiff": 3.0})
        res = 0.04
    else:
        els.append({"co": Vector((0, 0, 0.42)), "type": "ELLIPSOID", "r": 1.0, "size": (0.5, 0.46, 0.42), "stiff": 2.5})
        for k in range(4):
            a = rng.uniform(0, 2 * math.pi)
            els.append({"co": Vector((math.cos(a) * 0.22, math.sin(a) * 0.2, rng.uniform(0.3, 0.6))), "r": rng.uniform(0.3, 0.38), "type": "BALL", "stiff": 3.0})
        res = 0.05
    part = metaball_part(els, res, 0.6, tris, M_ROCK)
    # chisel: faceted noise for stone, flatten the base
    for i, v in enumerate(part.v):
        d = noise.noise(v * 3.2 + Vector((seed, 0, 0))) * 0.06 + noise.noise(v * 9.0) * 0.015
        nv = v + part.n[i] * d
        if kind == "layer":
            # crisp horizontal strata
            nv.x *= 1.0 + 0.05 * math.sin(nv.z * 26.0)
            nv.y *= 1.0 + 0.05 * math.sin(nv.z * 26.0)
        nv.z = max(nv.z, 0.0)
        part.v[i] = nv
    # normalise to a unit box resting on y = 0
    mn = Vector((min(v.x for v in part.v), min(v.y for v in part.v), min(v.z for v in part.v)))
    mx = Vector((max(v.x for v in part.v), max(v.y for v in part.v), max(v.z for v in part.v)))
    sz = mx - mn
    for i, v in enumerate(part.v):
        part.v[i] = Vector(((v.x - (mn.x + mx.x) * 0.5) / sz.x, (v.y - (mn.y + mx.y) * 0.5) / sz.y, (v.z - mn.z) / sz.z))
    # recompute normals after the edits
    recompute_normals(part)
    bvh = bvh_of([part])
    ao = ambient_occlusion(part, bvh, 0.7, 0.005)
    base = {"round": (0.50, 0.48, 0.47), "layer": (0.58, 0.50, 0.44), "flat": (0.52, 0.50, 0.48)}[kind]
    for i, v in enumerate(part.v):
        n = part.n[i]
        g = noise.noise(v * 4.0 + Vector((0, seed, 0)))
        col = mix3(base, mul3(base, 0.78), smoothstep(-0.3, 0.5, g))
        if kind == "layer":
            col = mix3(col, (0.66, 0.56, 0.46), 0.5 * smoothstep(0.3, 0.9, math.sin(v.z * 26.0)))
        # moss and lichen on top faces
        moss = smoothstep(0.55, 0.95, n.z) * smoothstep(-0.1, 0.4, noise.noise(v * 2.3 + Vector((seed, seed, 0))))
        col = mix3(col, (0.26, 0.38, 0.20), moss * (0.7 if kind != "layer" else 0.35))
        k = lerp(0.5, 1.0, ao[i])
        part.c[i] = (col[0] * k, col[1] * k, col[2] * k, 1.0)
    return part


def recompute_normals(part):
    acc = [Vector((0, 0, 0)) for _ in part.v]
    for i in range(0, len(part.idx), 3):
        a, b, c = part.idx[i], part.idx[i + 1], part.idx[i + 2]
        # Godot clockwise: front normal = (c - a) x (b - a)
        fn = (part.v[c] - part.v[a]).cross(part.v[b] - part.v[a])
        acc[a] += fn
        acc[b] += fn
        acc[c] += fn
    for i in range(len(part.v)):
        part.n[i] = acc[i].normalized() if acc[i].length > 1e-9 else Vector((0, 0, 1))


# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------
def to_godot(v):
    # Blender Z-up (x, y, z) -> Godot Y-up (x, z, -y)
    return (v.x, v.z, -v.y)


def write_part(name, part, manifest):
    path = os.path.join(RAW, name + ".utm")
    nv = len(part.v)
    with open(path, "wb") as f:
        f.write(b"UTM1")
        f.write(struct.pack("<II", nv, len(part.idx)))
        f.write(struct.pack("<%df" % (nv * 3), *[c for v in part.v for c in to_godot(v)]))
        f.write(struct.pack("<%df" % (nv * 3), *[c for n in part.n for c in to_godot(n.normalized())]))
        f.write(struct.pack("<%dB" % (nv * 4), *[max(0, min(255, int(round(x * 255)))) for c in part.c for x in c]))
        f.write(struct.pack("<%df" % (nv * 2), *[x for uv in part.uv for x in uv]))
        f.write(struct.pack("<%df" % (nv * 2), *[x for cu in part.cu for x in cu]))
        f.write(struct.pack("<%dI" % len(part.idx), *part.idx))
    xs = [to_godot(v) for v in part.v]
    manifest[name] = {"verts": nv, "tris": part.tris(),
                      "aabb": [min(p[0] for p in xs), min(p[1] for p in xs), min(p[2] for p in xs), max(p[0] for p in xs), max(p[1] for p in xs), max(p[2] for p in xs)]}
    print("  %-22s %5d tris %5d verts" % (name, part.tris(), nv))


def main():
    os.makedirs(RAW, exist_ok=True)
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    manifest = {}
    reset()
    jobs = []
    for nm, sp in BROAD.items():
        for lod in range(3):
            jobs.append(("tree_%s_%d" % (nm, lod), lambda sp=sp, lod=lod, nm=nm: build_broad(nm, sp, lod)))
    for nm, sp in PINES.items():
        for lod in range(3):
            jobs.append(("tree_%s_%d" % (nm, lod), lambda sp=sp, lod=lod, nm=nm: build_pine(nm, sp, lod)))
    jobs += [
        ("shrub_round_0", lambda: build_shrub(101, (1.1, 1.0, 0.85), PAL_OAK, 190)),
        ("shrub_round_1", lambda: build_shrub(101, (1.1, 1.0, 0.85), PAL_OAK, 60)),
        ("shrub_tall_0", lambda: build_shrub(103, (1.0, 0.9, 1.45), PAL_LINDEN, 200)),
        ("shrub_tall_1", lambda: build_shrub(103, (1.0, 0.9, 1.45), PAL_LINDEN, 64)),
        ("shrub_bloom_0", lambda: build_shrub(107, (1.2, 1.1, 0.9), PAL_OAK, 170, flowers=9)),
        ("shrub_bloom_1", lambda: build_shrub(107, (1.2, 1.1, 0.9), PAL_OAK, 60, flowers=5)),
        ("grass_tuft_0", lambda: build_grass(201)),
        ("flowers_0", lambda: build_flowers(301)),
        ("reeds_0", lambda: build_reeds(401)),
        ("lilies_0", lambda: build_lilies(501)),
        ("rock_round_0", lambda: build_rock(601, "round", 300)),
        ("rock_round_1", lambda: build_rock(601, "round", 90)),
        ("rock_layer_0", lambda: build_rock(607, "layer", 360)),
        ("rock_layer_1", lambda: build_rock(607, "layer", 110)),
        ("rock_flat_0", lambda: build_rock(613, "flat", 160)),
        ("rock_flat_1", lambda: build_rock(613, "flat", 50)),
    ]
    for name, fn in jobs:
        if only and not any(name.startswith(o) for o in only):
            continue
        part = fn()
        write_part(name, part, manifest)
        reset()
    mpath = os.path.join(RAW, "manifest.json")
    if only and os.path.exists(mpath):
        old = json.load(open(mpath))
        old.update(manifest)
        manifest = old
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("wrote %d meshes to %s" % (len(manifest), RAW))


if __name__ == "__main__":
    main()
