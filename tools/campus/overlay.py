"""Draw the campus layer data (game/data/campus/*.json) over the aerial.

    python3 tools/campus/overlay.py OUT.png [--x0 -780 --z0 -490 --size 1240]
                                    [--ppm 1.6] [--layers buildings,water,...]

Used for every layout check: footprints, water, roads, paths and areas drawn
in fixed colours over the 2022 aerial so misalignment is obvious.  tile.py
--data uses the same drawer on tracing tiles.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import geo  # noqa: E402

DATA = os.path.join(os.path.dirname(__file__), "..", "..", "game", "data", "campus")

STYLE = {
    "buildings": ((255, 80, 60, 70), (255, 80, 60, 255)),
    "water": ((40, 160, 255, 90), (40, 200, 255, 255)),
    "areas": ((255, 255, 255, 30), (255, 220, 120, 220)),
    "roads": (None, (255, 140, 0, 230)),
    "paths": (None, (255, 255, 255, 230)),
    "trees": ((40, 255, 80, 60), (40, 255, 80, 200)),
}


def load_layers(names=None, src=None):
    """Merged game data, or (src) one traced zone file: {"<layer>": [items]}."""
    if src:
        d = json.load(open(src))
        return {k: {"items": d.get(k, [])} for k in (names or STYLE.keys())}
    out = {}
    for n in names or ["areas", "water", "roads", "paths", "buildings", "trees"]:
        p = os.path.join(DATA, n + ".json")
        if os.path.exists(p):
            out[n] = json.load(open(p))
    return out


def _poly(d, to_px, pts, fill, line, w=2):
    xy = [to_px(x, z) for x, z in pts]
    if len(xy) >= 3:
        d.polygon(xy, fill=fill, outline=line)
        d.line(xy + [xy[0]], fill=line, width=w)


def drawer(layers):
    def draw(d, to_px, ppm):
        for name in ["areas", "water", "roads", "paths", "buildings", "trees"]:
            items = layers.get(name, {}).get("items", [])
            fill, line = STYLE[name]
            for it in items:
                if "polygon" in it:
                    _poly(d, to_px, it["polygon"], fill, line)
                if "footprint" in it:
                    _poly(d, to_px, it["footprint"], fill, line)
                for part in it.get("parts", []):
                    _poly(d, to_px, part["footprint"], None, (255, 200, 0, 200), 1)
                if "circle" in it:
                    (cx, cz), r = it["circle"]
                    x, z = to_px(cx, cz)
                    d.ellipse((x - r * ppm, z - r * ppm, x + r * ppm, z + r * ppm), fill=fill, outline=line, width=2)
                if "pts" in it and name in ("roads", "paths"):
                    xy = [to_px(x, z) for x, z in it["pts"]]
                    wpx = max(1, int(float(it.get("w", 3.0)) * ppm))
                    d.line(xy, fill=line[:3] + (110,), width=wpx)
                    d.line(xy, fill=line, width=1)
                if name == "trees" and "pos" in it:
                    x, z = to_px(*it["pos"])
                    r = float(it.get("r", 4.0)) * ppm
                    d.ellipse((x - r, z - r, x + r, z + r), outline=line, width=1)
            # ids at the centroid of polygons
            for it in items:
                pts = it.get("footprint") or it.get("polygon")
                if pts and ppm >= 1.0:
                    cx = sum(p[0] for p in pts) / len(pts)
                    cz = sum(p[1] for p in pts) / len(pts)
                    x, z = to_px(cx, cz)
                    d.text((x - 12, z - 5), it.get("id", "")[:18], fill=(255, 255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0))
    return draw


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--x0", type=float, default=-780)
    ap.add_argument("--z0", type=float, default=-490)
    ap.add_argument("--size", type=float, default=1240)
    ap.add_argument("--ppm", type=float, default=1.6)
    ap.add_argument("--layers", default="")
    ap.add_argument("--nogrid", action="store_true")
    ap.add_argument("--src", default="", help="a traced zone file instead of the merged game data")
    a = ap.parse_args()
    import tile
    layers = load_layers(a.layers.split(",") if a.layers else None, a.src or None)
    t = tile.make_tile(a.x0 + a.size / 2, a.z0 + a.size / 2, a.size, a.ppm, False, drawer(layers), grid=not a.nogrid)
    t.save(a.out)
    print(a.out)
