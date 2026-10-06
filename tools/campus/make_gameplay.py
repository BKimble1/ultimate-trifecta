"""Write game/data/campus/gameplay.json from the merged campus layers and a
small hand-written spec (tools/campus/gameplay_spec.json).

    python3 tools/campus/make_gameplay.py [--check]

The spec holds what is a design decision: the start dorms (each one's open
interior, its doors at the building's real entrances and the furniture),
the objective pool (which six real waters stand in for the game's six
objective slots, with their names, colours and icons), where the Night
Watch starts, landmark labels.  Everything that follows from the place is
computed here so it can be regenerated whenever the tracing improves:

  boundary       the play area: every campus feature (not the context
                 zone) grown by 30 m, merged, closed back in by 18 m and
                 simplified: it hugs the developed campus and its streets
  coin_spots     candidate coin places along the traced walks, spread out
                 (>= 26 m apart), clear of buildings, water, trunks, doors
  gadget_spots   up to 16 pickup places spread over the walks and plazas
                 (farthest-point order), clear of coin spots
  patrol_spawns  three places 4 m apart on open ground at the spec's anchor
  cart_spawns    two places on the nearest drivable surface to the anchor,
                 facing along it
Needs shapely (pip install shapely).
"""
import argparse
import json
import math
import os
import sys

from shapely.geometry import LineString, Point, Polygon, MultiPolygon
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "game", "data", "campus")
SPEC = os.path.join(HERE, "gameplay_spec.json")
OUT = os.path.join(DATA, "gameplay.json")
BOUNDS = (-720.0, -560.0, 470.0, 440.0)   # CampusLayout.BOUNDS: x0, z0, x1, z1


def layer(name):
    p = os.path.join(DATA, name + ".json")
    return json.load(open(p))["items"] if os.path.exists(p) else []


def water_geom(w):
    if "polygon" in w:
        return poly(w["polygon"])
    (cx, cz), cr = w["circle"]
    return Point(cx, cz).buffer(cr)


def poly(pts):
    pg = Polygon(pts)
    return pg if pg.is_valid else pg.buffer(0)


def r2(v):
    return round(float(v), 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="print, do not write")
    a = ap.parse_args()
    spec = json.load(open(SPEC))
    bld = layer("buildings")
    wat = layer("water")
    roads = layer("roads")
    paths = layer("paths")
    areas = layer("areas")
    trees = layer("trees")
    campus = lambda it: it.get("zone") != "context" and not it.get("background", False)

    # ---- the play boundary
    parts = []
    for b in bld:
        if campus(b):
            parts.append(poly(b["footprint"]).buffer(30))
    for w in wat:
        if campus(w):
            if "polygon" in w:
                parts.append(poly(w["polygon"]).buffer(30))
            else:
                (cx, cz), cr = w["circle"]
                parts.append(Point(cx, cz).buffer(cr + 30))
    for r in roads + paths:
        if campus(r) and r.get("kind") != "street":
            parts.append(LineString(r["pts"]).buffer(r.get("w", 3) * 0.5 + 18))
    for ar in areas:
        if campus(ar) and ar["kind"] not in ("farm", "woods"):
            parts.append(poly(ar["polygon"]).buffer(20))
    region = unary_union(parts)
    region = region.buffer(-18).buffer(6)
    if isinstance(region, MultiPolygon):
        region = max(region.geoms, key=lambda g: g.area)
    region = Polygon(region.exterior).simplify(3.0)
    x0, z0, x1, z1 = BOUNDS
    region = region.intersection(Polygon([(x0 + 6, z0 + 6), (x1 - 6, z0 + 6), (x1 - 6, z1 - 6), (x0 + 6, z1 - 6)]))
    if isinstance(region, MultiPolygon):
        region = max(region.geoms, key=lambda g: g.area)
    boundary = [[r2(x), r2(z)] for x, z in list(region.exterior.coords)[:-1]]

    # ---- obstacles for placing things
    solid = []
    for b in bld:
        solid.append(poly(b["footprint"]))
    for w in wat:
        solid.append(water_geom(w))
    solid_u = unary_union(solid)
    trunks = unary_union([Point(t["pos"]).buffer(0.9) for t in trees if t.get("kind") != "shrub"]) if trees else None
    doors = []
    for d in spec["start_dorms"]:
        for dr in d["doors"]:
            doors.append(Point(dr["p"]))
    inner = region.buffer(-8)
    # where runners climb out of each water (CampusLayout: 1.3 m beyond the
    # shore, more over a rim): coins keep 6 m from those exits
    def out_d(w):
        rim = float(w.get("rim_h", {"pool": 0.45, "fountain": 0.5}.get(w.get("kind"), 0.0)))
        return 1.3 + rim * 1.2 + (float(w.get("rim_t", 0.5)) if rim > 0.0 else 0.0)
    exits_zone = unary_union([water_geom(w).buffer(out_d(w)) for w in wat if not w.get("wade")])

    def ok(p, clear, coin=False):
        pt = Point(p)
        if not inner.contains(pt):
            return False
        if solid_u.distance(pt) < clear:
            return False
        if coin and exits_zone.distance(pt) < 6.3:
            return False
        if trunks is not None and trunks.distance(pt) < 1.2:
            return False
        return all(pt.distance(d) >= 16 for d in doors)

    # walk samples (every 2 m along every campus walk wider than 1.5 m)
    samples = []
    for pth in paths:
        if not campus(pth) or pth.get("w", 3) < 1.5:
            continue
        ls = LineString(pth["pts"])
        n = max(1, int(ls.length / 2.0))
        for i in range(n + 1):
            q = ls.interpolate(ls.length * i / n)
            samples.append((q.x, q.y))
    plaza_pts = []
    for ar in areas:
        if campus(ar) and ar["kind"] == "plaza":
            c = poly(ar["polygon"]).representative_point()
            plaza_pts.append((c.x, c.y))

    # ---- coin candidates: greedy spread over the walk samples
    cand = [p for p in samples if ok(p, 2.5, coin=True)]
    cand.sort(key=lambda p: (round(p[0] / 37.0), round(p[1] / 41.0), p[0], p[1]))
    coins = []
    for p in cand:
        if all(math.dist(p, q) >= 26.0 for q in coins):
            coins.append(p)

    # ---- gadget spots: farthest-point sampling over walks and plazas
    pool = [p for p in samples + plaza_pts if ok(p, 2.0) and all(math.dist(p, c) >= 6.0 for c in coins)]
    gadgets = []
    if pool:
        anchor = spec.get("patrol_anchor", [0, 0])
        start = min(pool, key=lambda p: math.dist(p, anchor))
        gadgets.append(start)
        while len(gadgets) < spec.get("gadget_count", 16):
            best = max(pool, key=lambda p: min(math.dist(p, g) for g in gadgets))
            if min(math.dist(best, g) for g in gadgets) < 30.0:
                break
            gadgets.append(best)

    # ---- the Night Watch: three spots on open ground at the anchor
    anchor = spec["patrol_anchor"]
    open_pts = [p for p in samples + plaza_pts if ok(p, 2.0)]
    near = sorted(open_pts, key=lambda p: math.dist(p, anchor))
    patrol = []
    for p in near:
        if all(math.dist(p, q) >= 4.0 for q in patrol):
            patrol.append(p)
        if len(patrol) == 3:
            break

    # ---- carts: on the drivable surface nearest the anchor, facing along it
    carts = []
    drive = [r for r in roads if campus(r) and r.get("kind") in ("campus", "drive", "service", "lot_aisle")]
    best = None
    for r in drive:
        ls = LineString(r["pts"])
        d = ls.distance(Point(anchor))
        if best is None or d < best[0]:
            best = (d, ls, r)
    if best is not None:
        ls = best[1]
        s0 = ls.project(Point(anchor))
        for k, off in enumerate((-6.0, 6.0)):
            s = min(max(s0 + off, 1.0), ls.length - 1.0)
            p = ls.interpolate(s)
            p2 = ls.interpolate(min(s + 1.0, ls.length))
            p1 = ls.interpolate(max(s - 1.0, 0.0))
            dx, dz = p2.x - p1.x, p2.y - p1.y
            yaw = math.degrees(math.atan2(-dx, -dz))   # facing along the road (game yaw)
            side = (best[2].get("w", 6.0) * 0.25) * (1 if k == 0 else -1)
            n = (dz / max(1e-6, math.hypot(dx, dz)), -dx / max(1e-6, math.hypot(dx, dz)))
            carts.append([[r2(p.x + n[0] * side), r2(p.y + n[1] * side)], r2(yaw)])

    items = [{"id": "play_boundary", "kind": "boundary", "polygon": boundary,
              "note": "computed by tools/campus/make_gameplay.py from the campus layers"}]
    for d in spec["start_dorms"]:
        it = dict(d)
        it["kind"] = "start_dorm"
        it["id"] = "start_" + d["dorm"]
        items.append(it)
    items.append({"id": "objective_pool", "kind": "objective_pool", "waters": spec["objective_pool"]})
    items.append({"id": "patrol_spawns", "kind": "patrol_spawns", "pts": [[r2(x), r2(z)] for x, z in patrol]})
    items.append({"id": "cart_spawns", "kind": "cart_spawns", "spots": carts})
    items.append({"id": "gadget_spots", "kind": "gadget_spots", "pts": [[r2(x), r2(z)] for x, z in gadgets]})
    items.append({"id": "coin_spots", "kind": "coin_spots", "pts": [[r2(x), r2(z)] for x, z in coins]})
    by_id = {b["id"]: b for b in bld}
    for bid in spec.get("label_buildings", []):
        b = by_id.get(bid)
        if b is None:
            continue
        c = poly(b["footprint"]).representative_point()
        items.append({"id": "label_" + bid, "kind": "landmark_label", "label": b.get("label", bid), "p": [r2(c.x), r2(c.y)]})
    for lb in spec.get("landmark_labels", []):
        items.append({"id": "label_" + lb["id"], "kind": "landmark_label", "label": lb["label"], "p": lb["p"]})
    out = {"version": 1, "items": items}
    print("boundary %d vertices, area %.0f m2; coins %d, gadgets %d, patrol %d, carts %d, dorms %d" % (
        len(boundary), region.area, len(coins), len(gadgets), len(patrol), len(carts), len(spec["start_dorms"])))
    # every pool water and start dorm must lie inside the play area
    ids = {w["id"]: w for w in wat}
    for e in spec["objective_pool"]:
        for wid in e.get("items", [e["id"]]):
            if wid not in ids:
                print("ERROR: objective water %s is not in the data" % wid)
                sys.exit(1)
            w = ids[wid]
            g = water_geom(w)
            if not region.buffer(-4).contains(g.centroid):
                print("ERROR: objective water %s lies outside the play area" % wid)
                sys.exit(1)
    if a.check:
        return
    with open(OUT, "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
