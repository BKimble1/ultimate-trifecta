"""Small mesh-construction kit for the character builder (pure Python + mathutils).

Everything is built as parametric surfaces (ellipsoids, swept tubes, lathes,
rounded slabs) into a MeshBuilder that carries per-vertex colour, UVs, bone
weights and tags.  Blender coordinates: X = character's right, Y = forward,
Z = up (the exported glTF faces -Z in Godot, which is the game's forward).

Vertex data contract (read by game/assets/shaders/character.gdshader):
  COLOR_0.rgb  base albedo, authored in sRGB here (exported linear by glTF)
  COLOR_0.a    tint selector: 0 fixed, 0.2 hair, 0.4 skin, 0.6 secondary
               (light primary), 0.8 dark primary, 1.0 primary; the final albedo
               is base * tint, so a white base takes the tint exactly
  UV0          u = stripe flag, v = stripe coordinate in metres (rest pose)
  UV1          u = roughness, v = material class (see MAT_*)
"""
import math
from mathutils import Vector, Matrix, Quaternion

# material classes (UV1.v)
MAT_CLOTH = 0.0
MAT_SATIN = 0.125   # V8: satin trims/sashes and track fabric: a soft sheen, still cloth
MAT_SKIN = 0.25
MAT_RUBBER = 0.5
MAT_METAL = 0.5625  # V8: buttons, badges, zips, the flashlight: metallic, not plastic gloss
MAT_LENS = 0.6875   # V7: tinted lens (opaque, glossy, a fresnel sheen and a little self-light)
MAT_GLOSS = 0.75
MAT_LIT = 0.875     # gloss with a little self-light (eye whites stay white at night)
MAT_EMIT = 1.0

# tint selectors (COLOR_0.a, decoded in the shader as round(a * 5))
T_NONE = 0.0
T_HAIR = 0.2
T_SKIN = 0.4
T_SECOND = 0.6
T_DARK = 0.8
T_PRIMARY = 1.0


def srgb(h):
    """'#rrggbb' -> (r, g, b) floats in sRGB."""
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0) if e1 != e0 else 0.0))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


class Style:
    """Per-vertex appearance: colour (sRGB), tint selector, roughness, class, stripe flag."""
    def __init__(self, col='#ffffff', tint=T_NONE, rough=0.85, mat=MAT_CLOTH, stripes=False):
        self.col = srgb(col) if isinstance(col, str) else tuple(col)
        self.tint = tint
        self.rough = rough
        self.mat = mat
        self.stripes = stripes

    def with_col(self, col):
        s = Style(col, self.tint, self.rough, self.mat, self.stripes)
        return s


class MeshBuilder:
    def __init__(self, name):
        self.name = name
        self.v = []        # Vector
        self.col = []      # (r,g,b,a)
        self.uv = []       # (u,v)
        self.uv2 = []      # (rough, mat)
        self.w = []        # {bone: weight}
        self.tag = []      # str tags (for shape keys)
        self.aux = []      # per-vertex aux data (e.g. feature centre)
        self.f = []        # tuples of vertex indices (CCW seen from outside)
        self.nrm = {}      # V8: vertex index -> analytic normal (eyes, lenses); others auto

    # -- low level -------------------------------------------------------
    def vert(self, p, style, uv, weights, tag='', aux=None, col_override=None):
        """col_override may be an (r, g, b) colour or a whole Style for this vertex."""
        self.v.append(Vector(p))
        if isinstance(col_override, Style):
            style = col_override
            col_override = None
        c = col_override if col_override is not None else style.col
        self.col.append((c[0], c[1], c[2], style.tint))
        # UV0: u = stripe flag (1 = this region takes outfit stripes), v = stripe coordinate (m)
        self.uv.append((1.0 if style.stripes else 0.0, uv[1]))
        self.uv2.append((style.rough, style.mat))
        self.w.append(dict(weights))
        self.tag.append(tag)
        self.aux.append(aux)
        return len(self.v) - 1

    def face(self, *idx):
        self.f.append(tuple(idx))

    def merge(self, other):
        base = len(self.v)
        self.v += other.v
        self.col += other.col
        self.uv += other.uv
        self.uv2 += other.uv2
        self.w += other.w
        self.tag += other.tag
        self.aux += other.aux
        self.f += [tuple(i + base for i in fc) for fc in other.f]
        for k, n in other.nrm.items():
            self.nrm[k + base] = n
        return self

    def merge_mirrored_x(self, other, weight_map=None):
        """Append `other` mirrored across x = 0 (V7: paired parts such as the
        goggle cups are built once and mirrored, so the pair is exactly
        symmetric).  Faces are re-wound so they still face outward.
        weight_map renames bones in the weights ('.L' <-> '.R')."""
        base = len(self.v)
        for i in range(len(other.v)):
            p = other.v[i]
            self.v.append(Vector((-p.x, p.y, p.z)))
            self.col.append(other.col[i])
            self.uv.append(other.uv[i])
            self.uv2.append(other.uv2[i])
            w = other.w[i]
            self.w.append({(weight_map or {}).get(k, k): v for k, v in w.items()})
            self.tag.append(other.tag[i])
            self.aux.append(other.aux[i])
        self.f += [tuple(i + base for i in reversed(fc)) for fc in other.f]
        for k, n in other.nrm.items():
            self.nrm[k + base] = Vector((-n.x, n.y, n.z))
        return self

    def face_if(self, keep, *idx):
        if keep is None or all(keep(self.v[i]) for i in idx):
            self.f.append(tuple(idx))

    def grid(self, rows, closed_u=True, pole_start=None, pole_end=None, keep=None, closed_v=False):
        """Connect a ring grid: rows = list of lists of vertex indices (same length).
        Faces wind so that ring order CCW (seen from +axis end) gives outward normals.
        keep(p) drops faces with any vertex failing it; closed_v joins the last
        row back to the first (tori, closed loops)."""
        n = len(rows[0])
        nr = len(rows)
        for r in range(nr if closed_v else nr - 1):
            a, b = rows[r], rows[(r + 1) % nr]
            for i in range(n if closed_u else n - 1):
                j = (i + 1) % n
                self.face_if(keep, a[i], a[j], b[j], b[i])
        if pole_start is not None:
            a = rows[0]
            for i in range(n if closed_u else n - 1):
                j = (i + 1) % n
                self.face_if(keep, pole_start, a[j], a[i])
        if pole_end is not None:
            b = rows[-1]
            for i in range(n if closed_u else n - 1):
                j = (i + 1) % n
                self.face_if(keep, b[i], b[j], pole_end)

    def compact(self):
        """Drop vertices no face uses (left over by keep predicates)."""
        used = sorted({i for f in self.f for i in f})
        remap = {o: n for n, o in enumerate(used)}
        for attr in ('v', 'col', 'uv', 'uv2', 'w', 'tag', 'aux'):
            arr = getattr(self, attr)
            setattr(self, attr, [arr[i] for i in used])
        self.f = [tuple(remap[i] for i in f) for f in self.f]
        self.nrm = {remap[k]: n for k, n in self.nrm.items() if k in remap}
        return self


def frame_from(tangent, up_hint=Vector((0, 1, 0))):
    t = Vector(tangent).normalized()
    if abs(t.dot(up_hint)) > 0.95:
        up_hint = Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))
    n = up_hint - t * t.dot(up_hint)
    n.normalize()
    b = t.cross(n)
    return t, n, b


def sweep(mb, path, radii, style, weightfn, segs=16, cap_start='round', cap_end='round',
          v_start=0.0, colfn=None, tag='', twist_hint=Vector((0, 1, 0)), squash=None, closed=False):
    """Tube along a polyline `path` (list of Vector) with elliptical cross-sections.
    radii: list of (rx, ry) per path point; rx along frame 'n' (hint direction),
    ry along the binormal.  Caps: 'round' builds a hemispherical end, 'flat'
    a disc, None leaves it open.  weightfn(p, s_metres, ring_index) -> weights.
    squash(angle)->scale lets a cross-section flatten on one side."""
    npts = len(path)
    # arc length
    s = [0.0]
    for i in range(1, npts):
        s.append(s[-1] + (path[i] - path[i - 1]).length)
    rows = []
    frames = []
    for i in range(npts):
        if closed:
            tng = path[(i + 1) % npts] - path[i - 1]
        elif i == 0:
            tng = path[1] - path[0]
        elif i == npts - 1:
            tng = path[-1] - path[-2]
        else:
            tng = (path[i + 1] - path[i - 1])
        frames.append(frame_from(tng, twist_hint))
    if closed:
        cap_start = cap_end = None

    def ring(c, fr, rx, ry, sv, idx_tag):
        t, n, b = fr
        out = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            sc = squash(a) if squash else 1.0
            p = c + n * (math.cos(a) * rx * sc) + b * (math.sin(a) * ry * sc)
            col = colfn(p, sv, a) if colfn else None
            out.append(mb.vert(p, style, (k / segs, v_start + sv), weightfn(p, sv, idx_tag), tag, None, col))
        return out

    # start cap
    cap_rings = 4
    if cap_start == 'round':
        t, n, b = frames[0]
        rx, ry = radii[0]
        rr = max(rx, ry)
        for j in range(cap_rings, 0, -1):
            ang = (math.pi / 2) * j / (cap_rings + 1)
            off = -t * (math.sin(ang) * rr * 0.9)
            k = math.cos(ang)
            rows.append(ring(path[0] + off, frames[0], rx * k, ry * k, s[0] - math.sin(ang) * rr * 0.9, 0))
        pole_s = mb.vert(path[0] - t * rr * 0.9, style, (0, v_start + s[0] - rr * 0.9), weightfn(path[0] - t * rr * 0.9, s[0], 0), tag,
                         None, colfn(path[0] - t * rr * 0.9, s[0], 0) if colfn else None)
    elif cap_start == 'flat':
        pole_s = mb.vert(path[0], style, (0, v_start + s[0]), weightfn(path[0], s[0], 0), tag, None,
                         colfn(path[0], s[0], 0) if colfn else None)
    else:
        pole_s = None
    for i in range(npts):
        rows.append(ring(path[i], frames[i], radii[i][0], radii[i][1], s[i], i))
    if cap_end == 'round':
        t, n, b = frames[-1]
        rx, ry = radii[-1]
        rr = max(rx, ry)
        for j in range(1, cap_rings + 1):
            ang = (math.pi / 2) * j / (cap_rings + 1)
            off = t * (math.sin(ang) * rr * 0.9)
            k = math.cos(ang)
            rows.append(ring(path[-1] + off, frames[-1], rx * k, ry * k, s[-1] + math.sin(ang) * rr * 0.9, npts - 1))
        pe = path[-1] + t * rr * 0.9
        pole_e = mb.vert(pe, style, (0, v_start + s[-1] + rr * 0.9), weightfn(pe, s[-1], npts - 1), tag, None,
                         colfn(pe, s[-1], 0) if colfn else None)
    elif cap_end == 'flat':
        pole_e = mb.vert(path[-1], style, (0, v_start + s[-1]), weightfn(path[-1], s[-1], npts - 1), tag, None,
                         colfn(path[-1], s[-1], 0) if colfn else None)
    else:
        pole_e = None
    # winding: our ring goes CCW around +t when n x b = t (frame is right-handed),
    # quads (a_i, a_j, b_j, b_i) then face outward.
    mb.grid(rows, True, pole_s, pole_e, closed_v=closed)
    return rows


def ellipsoid(mb, center, radii, style, weightfn, segs=20, rings=14, rot=None, power=2.0,
              colfn=None, tag='', aux=None, uv_scale=1.0, cut_below=None, keep=None, deform=None, world_v=False,
              normals=False):
    """(Super)ellipsoid. power>2 gives a boxier, rounder-cornered shape.
    rot: Matrix(3x3) orientation.  cut_below: optional local-z (unit sphere
    space) under which rings are dropped (makes a dome, open at the bottom).
    deform: optional f(local_point) -> local_point applied before rotation
    (the head shape uses it so shells follow the same surface).
    world_v: stripe coordinate = world height (matches torso lathes, so a
    piece overlapping the torso continues its stripes instead of clashing)."""
    c = Vector(center)
    R = rot if rot is not None else Matrix.Identity(3)
    rows = []

    def spow(x, p):
        return math.copysign(abs(x) ** p, x)

    e = 2.0 / power
    top = None
    bottom = None
    for r in range(1, rings):
        phi = math.pi * r / rings - math.pi / 2  # -pi/2..pi/2
        if cut_below is not None and math.sin(phi) < cut_below:
            continue
        row = []
        for k in range(segs):
            th = 2 * math.pi * k / segs
            x = spow(math.cos(phi), e) * spow(math.cos(th), e)
            y = spow(math.cos(phi), e) * spow(math.sin(th), e)
            z = spow(math.sin(phi), e)
            lp = Vector((x * radii[0], y * radii[1], z * radii[2]))
            if deform is not None:
                lp = deform(lp)
            p = c + R @ lp
            col = colfn(p, lp) if colfn else None
            vi = mb.vert(p, style, (k / segs, p.z if world_v else (z * radii[2]) * uv_scale), weightfn(p), tag, aux, col)
            if normals:
                # V8: the surface's own normal (gradient of the ellipsoid), not
                # one averaged from the faces: a shallow dome's highlight is
                # round instead of following its polygon
                mb.nrm[vi] = (R @ Vector((lp.x / radii[0] ** 2, lp.y / radii[1] ** 2, lp.z / radii[2] ** 2))).normalized()
            row.append(vi)
        rows.append(row)
    pt = c + R @ Vector((0, 0, radii[2]))
    top = mb.vert(pt, style, (0, pt.z if world_v else radii[2]), weightfn(pt), tag, aux, colfn(pt, Vector((0, 0, radii[2]))) if colfn else None)
    if normals:
        mb.nrm[top] = (R @ Vector((0, 0, 1))).normalized()
    if cut_below is None:
        pb = c + R @ Vector((0, 0, -radii[2]))
        bottom = mb.vert(pb, style, (0, pb.z if world_v else -radii[2]), weightfn(pb), tag, aux, colfn(pb, Vector((0, 0, -radii[2]))) if colfn else None)
    # rows go from bottom to top; ring order CCW seen from +z => outward = (a_i, b_i, b_j, a_j)?
    # Our rings: theta increasing CCW around +z.  For outward normals with rows ascending in z
    # the quad must be (a_i, a_j, b_j, b_i).
    mb.grid(rows, True, bottom, top, keep=keep)
    return rows


def lathe(mb, base, axis_rot, profile, style, weightfn, segs=20, colfn=None, tag='', ry_scale=1.0,
          closed_profile=False, rfn=None):
    """Surface of revolution: profile = list of (z, r) along local +z (bottom to top).
    r == 0 at an end makes a pole.  ry_scale squashes the y radius (elliptic)."""
    rows = []
    pole_s = pole_e = None
    for i, (z, r) in enumerate(profile):
        if r <= 1e-6 and i in (0, len(profile) - 1):
            p = Vector(base) + axis_rot @ Vector((0, 0, z))
            vi = mb.vert(p, style, (0, z), weightfn(p), tag, None, colfn(p, z, 0) if colfn else None)
            if i == 0:
                pole_s = vi
            else:
                pole_e = vi
            continue
        row = []
        for k in range(segs):
            th = 2 * math.pi * k / segs
            rr = rfn(r, th, z) if rfn else r
            lp = Vector((math.cos(th) * rr, math.sin(th) * rr * ry_scale, z))
            p = Vector(base) + axis_rot @ lp
            row.append(mb.vert(p, style, (k / segs, z), weightfn(p), tag, None, colfn(p, z, th) if colfn else None))
        rows.append(row)
    mb.grid(rows, True, pole_s, pole_e, closed_v=closed_profile)
    return rows


def torus_profile(z, r, tube_r, n=8, squash_z=1.0):
    """Closed circular profile for lathe(..., closed_profile=True) -> a torus.
    Ordered so the generated faces point outward."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n - math.pi / 2
        out.append((z + math.sin(a) * tube_r * squash_z, r + math.cos(a) * tube_r))
    return out


def slab(mb, outline, z0, z1, style, weightfn, bevel=0.01, colfn=None, tag='', top_style=None):
    """Extrude a closed CCW 2D outline (list of (x, y)) between z0 and z1 with a
    small rounded bevel on both edges.  Used for shoe soles."""
    n = len(outline)
    # outward normals of the outline
    pts = [Vector((x, y)) for x, y in outline]
    nors = []
    for i in range(n):
        a = pts[i - 1]
        b = pts[(i + 1) % n]
        t = (b - a).normalized()
        nors.append(Vector((t.y, -t.x)))
    layers = []
    steps = [(z0, -bevel), (z0 + bevel * 0.3, -bevel * 0.3), (z0 + bevel, 0.0), (z1 - bevel, 0.0), (z1 - bevel * 0.3, -bevel * 0.3), (z1, -bevel)]
    for li, (z, inset) in enumerate(steps):
        row = []
        st = top_style if (top_style is not None and li >= 4) else style
        for i in range(n):
            p2 = pts[i] + nors[i] * inset
            p = Vector((p2.x, p2.y, z))
            row.append(mb.vert(p, st, (i / n, z), weightfn(p), tag, None, colfn(p) if colfn else None))
        layers.append(row)
    # side faces (outline CCW seen from +z, rows ascending => (a_i, a_j, b_j, b_i))
    mb.grid(layers, True)
    # caps: fan from centre
    cx = sum(p.x for p in pts) / n
    cy = sum(p.y for p in pts) / n
    cb = mb.vert(Vector((cx, cy, z0)), style, (0, z0), weightfn(Vector((cx, cy, z0))), tag)
    ct = mb.vert(Vector((cx, cy, z1)), top_style or style, (0, z1), weightfn(Vector((cx, cy, z1))), tag)
    bot = layers[0]
    top = layers[-1]
    for i in range(n):
        j = (i + 1) % n
        mb.face(cb, bot[j], bot[i])
        mb.face(ct, top[i], top[j])


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'X')


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Y')


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Z')


def rot_align(z_dir, y_hint=Vector((0, 1, 0))):
    """Rotation whose local +z maps to z_dir (local +y as close to y_hint)."""
    z = Vector(z_dir).normalized()
    y = y_hint - z * z.dot(y_hint)
    if y.length < 1e-6:
        y = Vector((0, 0, 1)) - z * z.z
    y.normalize()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()
