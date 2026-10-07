#!/usr/bin/env python3
"""Elevation and grounding diagnostic of the baked campus ground.

A hillshade of game/data/campus/terrain.bin tinted by height, with:
  * every building pad coloured by how much foundation shows on its low
    side (floor - lowest grade round it: grey < 0.3 m, amber to 1.9 m, red
    beyond: an exposed basement storey);
  * every stair as a white bar from its top edge out, its lead-in and
    run-out marked;
  * waters outlined with their surface level, the play boundary dashed,
    and the footbridge.
Neutral ids only.  Usage: tools/campus/terrain_overlay.py OUT.png
[--x0 -720 --z0 -560 --w 1190 --d 1000] [--ppm 1.5] [--labels]
"""
import argparse
import json
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "game", "data", "campus")


def load(name):
    d = json.load(open(os.path.join(DATA, name + ".json")))
    return d["items"] if isinstance(d, dict) and "items" in d else d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--x0", type=float, default=-720)
    ap.add_argument("--z0", type=float, default=-560)
    ap.add_argument("--w", type=float, default=1190)
    ap.add_argument("--d", type=float, default=1000)
    ap.add_argument("--ppm", type=float, default=1.5)
    ap.add_argument("--labels", action="store_true")
    a = ap.parse_args()
    meta = json.load(open(os.path.join(DATA, "terrain.json")))
    gm = meta["grid"]
    g = np.fromfile(os.path.join(DATA, "terrain.bin"), dtype="<f4").reshape(gm["d"], gm["w"]).astype(float)
    gx0, gz0 = gm["x0"], gm["z0"]
    # the window, resampled at ppm
    W, D = int(a.w * a.ppm), int(a.d * a.ppm)
    xs = a.x0 + (np.arange(W) + 0.5) / a.ppm
    zs = a.z0 + (np.arange(D) + 0.5) / a.ppm
    ix = np.clip(np.round(xs - gx0).astype(int), 0, gm["w"] - 1)
    iz = np.clip(np.round(zs - gz0).astype(int), 0, gm["d"] - 1)
    h = g[np.ix_(iz, ix)]
    # hillshade (light from the north-west)
    gy, gx = np.gradient(h, 1.0 / a.ppm)
    slope = np.pi / 2 - np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    az, alt = np.radians(315), np.radians(45)
    shade = np.sin(alt) * np.sin(slope) + np.cos(alt) * np.cos(slope) * np.cos(az - aspect)
    shade = np.clip(shade, 0, 1)
    t = np.clip((h - h.min()) / max(1e-6, h.max() - h.min()), 0, 1)
    base = np.stack([0.25 + 0.55 * t, 0.45 + 0.35 * t, 0.30 + 0.25 * (1 - t)], -1)
    img = (base * (0.35 + 0.65 * shade[..., None]) * 255).astype(np.uint8)
    im = Image.fromarray(img, "RGB").convert("RGBA")
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    dr = ImageDraw.Draw(ov)

    def px(p):
        return ((p[0] - a.x0) * a.ppm, (p[1] - a.z0) * a.ppm)

    floors = meta.get("floors", {})
    for b in load("buildings"):
        fp = b.get("footprint") or []
        if len(fp) < 3:
            continue
        fl = floors.get(b["id"], {})
        show = fl.get("floor", 0) - fl.get("ground_min", fl.get("floor", 0)) if fl else 0
        if show < 0.3:
            col = (200, 200, 200, 150)
        elif show < 1.9:
            col = (240, 170, 40, 180)
        else:
            col = (230, 50, 40, 200)
        dr.polygon([px(p) for p in fp], fill=col, outline=(30, 30, 30, 255))
        if a.labels and not b.get("background"):
            c = np.mean(np.array(fp), axis=0)
            dr.text(px(c), "%s\n%.1f" % (b["id"], fl.get("floor", 0)), fill=(0, 0, 0, 255))
    for w in load("water"):
        poly = w.get("polygon")
        if poly:
            dr.polygon([px(p) for p in poly], fill=(40, 120, 230, 140), outline=(20, 60, 160, 255))
            lv = meta.get("waters", {}).get(w["id"], {})
            if a.labels and lv.get("surface") is not None:
                c = np.mean(np.array(poly), axis=0)
                dr.text(px(c), "%s %.2f" % (w["id"], lv["surface"]), fill=(255, 255, 255, 255))
        for f in w.get("features", []):
            if f.get("kind") == "bridge" and f.get("pts"):
                dr.line([px(p) for p in f["pts"]], fill=(255, 255, 255, 255), width=max(2, int(3 * a.ppm)))
    for st in meta.get("stairs", []):
        p = np.array(st["p"])
        n = np.array(st["dir"])
        tg = np.array([-n[1], n[0]])
        half = st["w"] * 0.5
        end = st["length"] + st["going"]
        for d0, d1, col in ((-1.0, 0.0, (120, 220, 255, 255)), (0.0, end, (255, 255, 255, 255)), (end, end + 0.6, (255, 230, 90, 255))):
            q = [p + n * d0 + tg * half, p + n * d1 + tg * half, p + n * d1 - tg * half, p + n * d0 - tg * half]
            dr.polygon([px(x) for x in q], fill=col, outline=(0, 0, 0, 255))
    gp = load("gameplay")
    for it in gp:
        if it.get("kind") == "boundary":
            pts = it["polygon"] + [it["polygon"][0]]
            for i in range(len(pts) - 1):
                if i % 2 == 0:
                    dr.line([px(pts[i]), px(pts[i + 1])], fill=(255, 255, 255, 230), width=2)
    out = Image.alpha_composite(im, ov).convert("RGB")
    d2 = ImageDraw.Draw(out)
    d2.rectangle([0, 0, 520, 66], fill=(0, 0, 0))
    d2.text((6, 4), "ground %.1f..%.1f m (NAVD88 - %.2f); pads: grey <0.3 m foundation shows, amber <1.9 m, red more" % (h.min(), h.max(), meta.get("origin", 280.40)), fill=(255, 255, 255))
    d2.text((6, 22), "stairs: cyan lead-in, white flights, yellow run-out; waters blue; play boundary dashed", fill=(255, 255, 255))
    d2.text((6, 40), "source: %s" % str(meta.get("source", ""))[:80], fill=(200, 200, 200))
    out.save(a.out)
    print("wrote", a.out, out.size)


if __name__ == "__main__":
    main()
