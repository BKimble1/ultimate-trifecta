#!/usr/bin/env python3
"""Bakes the reference campus's ground from a public bare-earth DEM.

Source: USGS 3D Elevation Program 1 m DEM, tile
USGS_1M_16_x62y448_IN_Indiana_Statewide_LiDAR_2017_B17 (LiDAR acquired
2017-03-03 .. 2020-04-11, published 2021-07-04; NAD83 / UTM 16N, NAVD88
metres; public domain).  Fetch it from the USGS staged products bucket
(StagedProducts/Elevation/1m/Projects/IN_Indiana_Statewide_LiDAR_2017_B17/
TIFF/) into the research area (outside this repository) and crop it with
`--crop`; the crop is the input of the bake.

The ground is the game's frame (x = E - 627300, z = 4479400 - N, metres) at
1 m, over the campus bounds, with y = NAVD88 - ORIGIN (ORIGIN: the grade at
the default start hall's front door, so the default start stands at y = 0).
One metre stays one metre in every direction: nothing is exaggerated.

What the bake does, in order, all deterministic:
 1. samples the DEM at integer game metres (bilinear) and smooths it lightly
    (Gaussian, sigma 0.8 m: the LiDAR's sub-decimetre noise, not the grade);
 2. levels every water: a hydro-flattened pond or lake keeps its measured
    surface; one dug after the survey (flagged by a bed above its banks)
    sits just below its lowest bank; a built basin (fountain, pool) sits on
    its plaza's grade; a sloping channel keeps its slope.  The ground inside
    a water is set to its surface (the game carves the bed below it) and a
    bank lower than the surface is raised to just above it;
 3. gives every building a floor level: the 80th percentile of the grade in
    a 1-3 m ring round its footprint (a building on a slope sits at its high
    side; its low side shows its foundation or basement), unless the data
    gives one (`floor_navd88`); the ground under the footprint is that
    level;
 4. grades each entrance's apron to its floor (within 4 m) where the step is
    under 0.9 m; a larger step needs a stair or ramp in the data and is
    reported.
Writes game/data/campus/terrain.bin (float32 little-endian metres rounded to
the centimetre, rows z then x: the game reads it natively) and terrain.json (the grid, the source, ORIGIN, the water
levels, the floor levels and the report).

Usage:
  tools/campus/terrain.py --crop TILE.tif CROP.npy      (once)
  tools/campus/terrain.py --dem CROP.npy [--data game/data/campus]
"""
import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import geo  # noqa: E402

ORIGIN = 280.40
BOUNDS = (-720, -560, 1190, 1000)      # x0, z0, width, depth (CampusMaps)
CROP = (-760, -600, 1271, 1081)        # the DEM crop: 40 m beyond the bounds
TILE_TIE = (619993.9996661129, 4480006.000312358)   # upper-left of pixel (0, 0)
SOURCE = ("USGS 3DEP 1 m DEM USGS_1M_16_x62y448_IN_Indiana_Statewide_LiDAR_2017_B17 "
          "(acquired 2017-03-03..2020-04-11, published 2021-07-04; NAD83 / UTM 16N; NAVD88 m; public domain)")
NATURAL = ("pond", "lake")
BUILT = ("fountain", "pool")


def crop(tif, out):
    import tifffile
    a = tifffile.imread(tif).astype(np.float64)
    a[a <= -9999] = np.nan
    x0, z0, w, d = CROP
    xs = np.arange(w) + x0
    zs = np.arange(d) + z0
    col = geo.E0 + xs - TILE_TIE[0] - 0.5
    row = TILE_TIE[1] - (geo.N0 - zs) - 0.5
    c0 = np.floor(col).astype(int)
    r0 = np.floor(row).astype(int)
    fc = (col - c0)[None, :]
    fr = (row - r0)[:, None]
    A = a[np.ix_(r0, c0)]
    B = a[np.ix_(r0, c0 + 1)]
    C = a[np.ix_(r0 + 1, c0)]
    D = a[np.ix_(r0 + 1, c0 + 1)]
    h = (A * (1 - fc) + B * fc) * (1 - fr) + (C * (1 - fc) + D * fc) * fr
    if np.isnan(h).any():
        sys.exit("the crop has no-data cells")
    np.save(out, h.astype(np.float32))
    print("cropped %s -> %s: %.2f..%.2f m" % (tif, out, h.min(), h.max()))


def items(data, name):
    d = json.load(open(os.path.join(data, name + ".json")))
    return d["items"] if isinstance(d, dict) else d


def mask(poly, w, d, x0, z0):
    im = Image.new("L", (w, d), 0)
    ImageDraw.Draw(im).polygon([(q[0] - x0, q[1] - z0) for q in poly], fill=1)
    return np.array(im) > 0


def disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= r * r


def water_poly(it):
    if "polygon" in it:
        return it["polygon"]
    if "circle" in it:
        (cx, cz), r = it["circle"]
        a = np.linspace(0, 2 * np.pi, 48, endpoint=False)
        return list(zip(cx + r * np.cos(a), cz + r * np.sin(a)))
    return None


def bake(dem_path, data, out_dir):
    raw = np.load(dem_path).astype(np.float64)
    x0, z0, w, d = BOUNDS
    ox, oz = x0 - CROP[0], z0 - CROP[1]
    g = raw[oz:oz + d + 1, ox:ox + w + 1] - ORIGIN        # (d+1) x (w+1) samples
    W, D = w + 1, d + 1
    g = ndimage.gaussian_filter(g, 0.8, mode="nearest")
    measured = g.copy()
    report = []
    # ---- waters
    levels = {}
    for it in items(data, "water"):
        poly = water_poly(it)
        if not poly:
            continue
        kind = it.get("kind", "pond")
        ins = mask(poly, W, D, x0, z0)
        if not ins.any():
            continue
        ring = ndimage.binary_dilation(ins, disk(4)) & ~ndimage.binary_dilation(ins, disk(1))
        vi, vr = measured[ins], measured[ring]
        depth = float(it.get("surface", -0.5)) - float(it.get("floor", -2.0))
        if kind in BUILT:
            grade = float(np.median(vr))
            surf = grade + float(it.get("surface", 0.2))
            flo = grade + float(it.get("floor", -1.0))
            how = "built basin on its plaza grade (ring median)"
            g[ins] = grade
        elif kind in NATURAL:
            flat = float(np.std(vi)) < 0.3 and np.median(vi) <= np.percentile(vr, 10) + 0.15
            if flat:
                surf = float(np.median(vi))
                how = "hydro-flattened surface measured by the survey"
            else:
                surf = float(np.percentile(vr, 10)) - 0.12
                how = "after the survey (its bed was dry ground then): just below its lowest bank"
            flo = surf - depth
            g[ins] = np.minimum(g[ins], surf)
            low = ring & (g < surf + 0.12)
            g[low] = surf + 0.12
        else:
            # a sloping channel: its bed follows the ground, a few decimetres down
            surf = None
            flo = None
            how = "sloping channel: bed 0.3 m below the ground along its course"
            g[ins] = g[ins] - 0.3
        levels[it["id"]] = {"kind": kind, "surface": None if surf is None else round(surf, 3),
                            "floor": None if flo is None else round(flo, 3), "how": how,
                            "bed_measured": round(float(np.median(vi)), 2), "bank_low": round(float(np.percentile(vr, 10)), 2)}
    # ---- buildings
    pads = {}
    blds = [b for b in items(data, "buildings") if not b.get("background") and len(b.get("footprint", [])) >= 3]
    masks = {}
    for b in blds:
        ins = mask(b["footprint"], W, D, x0, z0)
        if not ins.any():
            continue
        masks[b["id"]] = ins
        ring = ndimage.binary_dilation(ins, disk(3)) & ~ndimage.binary_dilation(ins, disk(1))
        vr = measured[ring]
        if "floor_navd88" in b:
            fl = float(b["floor_navd88"]) - ORIGIN
            how = "floor from the data"
        else:
            fl = float(np.percentile(vr, 80))
            how = "80th percentile of the grade round it"
        pads[b["id"]] = {"floor": round(fl, 3), "ground_min": round(float(np.percentile(vr, 5)), 3),
                         "ground_max": round(float(np.percentile(vr, 98)), 3), "how": how}
    for bid, ins in masks.items():
        g[ins] = pads[bid]["floor"]
    # ---- entrance aprons
    gp = items(data, "gameplay")
    doors = []
    for it in gp:
        if it.get("kind") == "start_dorm":
            for dr in it.get("doors", []):
                doors.append((it["building"], dr["p"], dr.get("id", "")))
    for b in blds:
        for e in b.get("entrances", []):
            p = e.get("p") if isinstance(e, dict) else None
            if p:
                doors.append((b["id"], p, e.get("id", "entrance")))
    xs = np.arange(W) + x0
    zs = np.arange(D) + z0
    X, Z = np.meshgrid(xs, zs)
    for bid, p, did in doors:
        if bid not in pads:
            continue
        fl = pads[bid]["floor"]
        r = np.hypot(X - p[0], Z - p[1])
        near = (r < 4.0) & ~masks[bid]
        if not near.any():
            continue
        step = float(np.median(g[near]) - fl)
        if abs(step) > 0.9:
            report.append("%s %s: the grade outside is %+.2f m from the floor: needs a stair or ramp" % (bid, did, step))
            continue
        t = np.clip((4.0 - r) / 3.0, 0.0, 1.0)
        t = t * t * (3 - 2 * t)
        g[near] = g[near] * (1 - t[near]) + fl * t[near]
    # ---- steep ground, on the bots' 2 m navigation cells (NavGrid._r_slopes)
    dx = np.abs(np.diff(g, axis=1))
    dz = np.abs(np.diff(g, axis=0))
    step = np.zeros_like(g)
    step[:, :-1] = np.maximum(step[:, :-1], dx)
    step[:, 1:] = np.maximum(step[:, 1:], dx)
    step[:-1, :] = np.maximum(step[:-1, :], dz)
    step[1:, :] = np.maximum(step[1:, :], dz)
    nx, nz = int(np.ceil(w / 2.0)), int(np.ceil(d / 2.0))
    # cell (i, j) covers samples 2i..2i+2 x 2j..2j+2: a 3 x 3 max round 2i+1
    big = np.pad(step, ((0, 2 * nz + 1 - D), (0, 2 * nx + 1 - W)), mode="edge")
    cellmax = ndimage.maximum_filter(big, size=3, mode="nearest")[1::2, 1::2][:nz, :nx]
    steep = {"cell": 2.0, "foot_tan": 0.9, "cart_tan": 0.55}
    for key, lim in (("foot", 0.9), ("cart", 0.55)):
        jj, ii = np.nonzero(cellmax > lim)
        steep[key] = [int(v) for pair in zip(ii, jj) for v in pair]
    # ---- write
    blob = (np.round(g * 100.0) / 100.0).astype("<f4").tobytes()
    os.makedirs(out_dir, exist_ok=True)
    open(os.path.join(out_dir, "terrain.bin"), "wb").write(blob)
    meta = {
        "about": "The reference campus's ground: game frame metres, 1 m samples, y = NAVD88 - origin. Baked by tools/campus/terrain.py.",
        "source": SOURCE,
        "frame": "x = E - %.1f, z = %.1f - N (EPSG:26916)" % (geo.E0, geo.N0),
        "origin_navd88": ORIGIN,
        "origin_is": "the grade at the default start hall's front door",
        "grid": {"x0": x0, "z0": z0, "w": W, "d": D, "step": 1.0, "format": "float32 LE metres (centimetre steps), rows z then x"},
        "smoothing_sigma_m": 0.8,
        "sha256": hashlib.sha256(blob).hexdigest(),
        "range_m": [round(float(g.min()), 2), round(float(g.max()), 2)],
        "waters": levels,
        "floors": pads,
        "report": report,
        "steep": steep,
    }
    json.dump(meta, open(os.path.join(out_dir, "terrain.json"), "w"), indent=1, sort_keys=True)
    print("terrain %dx%d, %.2f..%.2f m; %d waters, %d floors; %d entrances need a stair or ramp; steep cells: %d on foot, %d for carts" % (
        W, D, g.min(), g.max(), len(levels), len(pads), len(report), len(steep["foot"]) // 2, len(steep["cart"]) // 2))
    for r in report:
        print("  " + r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crop", nargs=2, metavar=("TIF", "NPY"))
    ap.add_argument("--dem")
    ap.add_argument("--data", default=os.path.join(ROOT, "game", "data", "campus"))
    a = ap.parse_args()
    if a.crop:
        crop(a.crop[0], a.crop[1])
    if a.dem:
        bake(a.dem, a.data, a.data)


if __name__ == "__main__":
    main()
