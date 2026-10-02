"""Detail textures for the V5 campus shaders (original, generated with numpy).

Two tileable 512 x 512 RGBA masks; the world shaders sample them in world
space by material id (see game/assets/shaders/world_common.gdshaderinc).
They hold shape, not colour: every colour still comes from vertex colours,
so one small pair of textures dresses the whole campus.

  campus_detail_a.png  R grass/organic noise   G flagstone height (0 = joint)
                       B flagstone cell tint   A gravel / pebble height
  campus_detail_b.png  R brick height          G brick cell tint
                       B roof shingle height   A wood plank height

Run: python3 tools/campus/make_textures.py (also part of tools/campus/build.sh)
"""
import os
import numpy as np
from PIL import Image

N = 512
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "campus")
rng = np.random.default_rng(5)

yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N   # 0..1, tileable domain


def value_noise(freq, seed):
    """Tileable smooth value noise (bicubic-ish) at an integer frequency."""
    r = np.random.default_rng(seed).random((freq, freq)).astype(np.float32)
    fx = xx * freq
    fy = yy * freq
    x0 = np.floor(fx).astype(int) % freq
    y0 = np.floor(fy).astype(int) % freq
    x1 = (x0 + 1) % freq
    y1 = (y0 + 1) % freq
    tx = fx - np.floor(fx)
    ty = fy - np.floor(fy)
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = r[y0, x0] * (1 - tx) + r[y0, x1] * tx
    b = r[y1, x0] * (1 - tx) + r[y1, x1] * tx
    return a * (1 - ty) + b * ty


def fbm(octaves, base, seed, gain=0.5):
    out = np.zeros((N, N), np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        out += value_noise(base * (2 ** o), seed + o) * amp
        tot += amp
        amp *= gain
    return out / tot


def voronoi(points, jitter_seed):
    """Tileable Voronoi: distance to nearest and second nearest, cell id."""
    d1 = np.full((N, N), 9.0, np.float32)
    d2 = np.full((N, N), 9.0, np.float32)
    cid = np.zeros((N, N), np.int32)
    for i, (px, py) in enumerate(points):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, 1 - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, 1 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        cid = np.where(closer, i, cid)
        d1 = np.where(closer, d, d1)
    return d1, d2, cid


def jittered_grid(n, jit, seed):
    r = np.random.default_rng(seed)
    pts = []
    for j in range(n):
        for i in range(n):
            pts.append(((i + 0.5 + r.uniform(-jit, jit)) / n, (j + 0.5 + r.uniform(-jit, jit)) / n))
    return pts


def to8(a):
    return np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# --- texture A ------------------------------------------------------------
# R: grass - broad clumps, fine blades (anisotropic streaks), a few dark gaps
clumps = fbm(4, 4, 11)
fine = fbm(3, 32, 21)
streak = value_noise(64, 31)
grass = 0.5 + (clumps - 0.5) * 0.9 + (fine - 0.5) * 0.6 + (streak - 0.5) * 0.25
grass = np.clip(grass, 0, 1)

# G/B: irregular flagstones (8 x 8 per tile), soft bevel, joint = 0
pts = jittered_grid(8, 0.32, 41)
d1, d2, cid = voronoi(pts, 41)
edge = (d2 - d1) * 8.0          # ~0 at joints, ~1 in stone centres
warp = (fbm(3, 16, 51) - 0.5) * 0.18
stone = smooth(0.06, 0.32, edge + warp)
stone *= 0.9 + 0.1 * fbm(2, 24, 61)
tint = np.random.default_rng(71).random(len(pts)).astype(np.float32)[cid]

# A: gravel / pebbles (dense small cells) over fine noise
gpts = jittered_grid(40, 0.45, 81)
g1, g2, gid = voronoi(gpts, 81)
peb = smooth(0.0, 0.5, (g2 - g1) * 40.0) * (0.55 + 0.45 * np.random.default_rng(91).random(len(gpts)).astype(np.float32)[gid])
gravel = np.clip(peb * 0.75 + fine * 0.25, 0, 1)

img_a = np.dstack([to8(grass), to8(stone), to8(tint), to8(gravel)])

# --- texture B ------------------------------------------------------------
# R/G: running-bond bricks, 4 per row, 8 rows per tile (stretched in world
# space by the shader to ~0.5 x 0.2 m), mortar = 0, cell tint
rows = 8
cols = 4
ry = yy * rows
row = np.floor(ry).astype(int)
fy = ry - row
rx = xx * cols + 0.5 * (row % 2)
col = np.floor(rx).astype(int) % cols
fxb = rx - np.floor(rx)
mort_x = smooth(0.0, 0.04, fxb) * smooth(0.0, 0.04, 1 - fxb)
mort_y = smooth(0.0, 0.08, fy) * smooth(0.0, 0.08, 1 - fy)
brick = mort_x * mort_y * (0.82 + 0.18 * fbm(3, 32, 101))
btint = np.random.default_rng(111).random((rows, cols)).astype(np.float32)[row % rows, col]

# B: roof shingles - 10 courses, staggered tabs with rounded lower edges
courses = 10
cy = yy * courses
crow = np.floor(cy).astype(int)
cfy = cy - crow
tabs = 6
cx = xx * tabs + 0.5 * (crow % 2)
cfx = cx - np.floor(cx)
round_edge = 0.18 * (1 - np.cos((cfx - 0.5) * np.pi * 2)) * 0.5
shingle = smooth(0.0, 0.25, cfy - round_edge) * (0.55 + 0.45 * cfy)
shingle *= smooth(0.0, 0.03, cfx) * smooth(0.0, 0.03, 1 - cfx) * 0.25 + 0.75
shingle = np.clip(shingle * (0.85 + 0.15 * np.random.default_rng(121).random((courses, tabs)).astype(np.float32)[crow % courses, np.floor(cx).astype(int) % tabs]), 0, 1)

# A: wood planks - 6 boards per tile with grain and small gaps
boards = 6
by = yy * boards
brow = np.floor(by).astype(int)
bfy = by - brow
grain = value_noise(4, 131)
grain_lines = 0.5 + 0.5 * np.sin((xx * 3.0 + grain * 2.0 + brow * 0.37) * np.pi * 2 * 6)
plank = smooth(0.0, 0.06, bfy) * smooth(0.0, 0.06, 1 - bfy)
plank = plank * (0.78 + 0.12 * grain_lines + 0.1 * np.random.default_rng(141).random(boards).astype(np.float32)[brow % boards])

img_b = np.dstack([to8(brick), to8(btint), to8(shingle), to8(plank)])

os.makedirs(OUT, exist_ok=True)
Image.fromarray(img_a, "RGBA").save(os.path.join(OUT, "campus_detail_a.png"), optimize=True)
Image.fromarray(img_b, "RGBA").save(os.path.join(OUT, "campus_detail_b.png"), optimize=True)
print("wrote campus_detail_a.png, campus_detail_b.png to", OUT)
