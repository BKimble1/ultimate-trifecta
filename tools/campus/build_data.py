"""Validate the traced zone files and merge them into game/data/campus/.

    python3 tools/campus/build_data.py [--check]     (--check: validate only)

Reads tools/campus/traced/*.json ({"zone": .., "<layer>": [items]}), checks
every item (unique ids, valid polygons, coordinates inside the frame, known
kinds, evidence present, no real names), and writes one file per layer:
game/data/campus/<layer>.json = {"version": 1, "items": [...]}.
"""
import argparse
import glob
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "traced")
OUT = os.path.join(ROOT, "game", "data", "campus")
LAYERS = ["buildings", "water", "roads", "paths", "areas", "barriers", "trees", "props", "changes"]
FRAME = (-1300.0, -1400.0, 800.0, 1300.0)   # x0, z0, x1, z1 (overview window)

KINDS = {
    "buildings": {"academic", "residence", "athletic", "dining", "worship", "service", "house", "context"},
    "water": {"lake", "pond", "pool", "fountain", "channel"},
    "roads": {"street", "campus", "drive", "service", "lot_aisle"},
    "areas": {"parking", "plaza", "field_turf", "field_grass", "track", "court", "infield", "bed",
              "construction", "woods", "farm", "sand", "gravel", "yard", "lawn", "pavement"},
    "barriers": {"wall_low", "wall_retaining", "fence_iron", "fence_chain", "fence_construction",
                 "hedge", "rail", "bollards"},
    "trees": {"deciduous", "conifer", "ornamental", "shrub"},
}

# real-name screening: a private list outside the repository, if present
DENY_FILE = os.environ.get("CAMPUS_DENY", "/home/user/campus_ref/work/denylist.txt")


def deny_words():
    if not os.path.exists(DENY_FILE):
        return []
    return [w.strip().lower() for w in open(DENY_FILE) if len(w.strip()) >= 4]


def poly_area(p):
    a = 0.0
    for i in range(len(p)):
        x1, z1 = p[i]
        x2, z2 = p[(i + 1) % len(p)]
        a += x1 * z2 - x2 * z1
    return a / 2.0


def segs_intersect(a, b, c, d):
    def o(p, q, r):
        v = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        return 0 if abs(v) < 1e-9 else (1 if v > 0 else -1)
    return o(a, b, c) != o(a, b, d) and o(c, d, a) != o(c, d, b) and 0 not in (o(a, b, c), o(a, b, d), o(c, d, a), o(c, d, b))


def check_poly(errs, where, p, min_pts=3):
    if not isinstance(p, list) or len(p) < min_pts:
        errs.append(f"{where}: polygon needs >= {min_pts} points"); return
    for q in p:
        if not (isinstance(q, list) and len(q) == 2 and all(isinstance(v, (int, float)) for v in q)):
            errs.append(f"{where}: bad point {q}"); return
        if not (FRAME[0] <= q[0] <= FRAME[2] and FRAME[1] <= q[1] <= FRAME[3]):
            errs.append(f"{where}: point {q} outside the frame"); return
    if min_pts >= 3:
        if p[0] == p[-1]:
            errs.append(f"{where}: repeated closing point")
        if abs(poly_area(p)) < 0.5:
            errs.append(f"{where}: zero area")
        n = len(p)
        for i in range(n):
            for j in range(i + 2, n):
                if i == 0 and j == n - 1:
                    continue
                if segs_intersect(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]):
                    errs.append(f"{where}: self-intersecting (edges {i} and {j})"); return


def validate(merged):
    errs, warns = [], []
    ids = {}
    deny = deny_words()
    for layer, items in merged.items():
        for it in items:
            iid = it.get("id")
            where = f"{layer}/{iid}"
            if not iid or not re.fullmatch(r"[a-z0-9_]+", iid):
                errs.append(f"{where}: id must be snake_case")
            if iid in ids:
                errs.append(f"{where}: duplicate id (also in {ids[iid]})")
            ids[iid] = layer
            if layer in KINDS and it.get("kind") not in KINDS[layer]:
                errs.append(f"{where}: unknown kind {it.get('kind')!r}")
            if layer not in ("trees", "props", "changes") and "ev" not in it:
                errs.append(f"{where}: no evidence (ev)")
            ev = it.get("ev", {})
            if ev and ev.get("conf") not in (None, "high", "medium", "low"):
                errs.append(f"{where}: ev.conf must be high/medium/low")
            if "footprint" in it:
                check_poly(errs, where, it["footprint"])
            for k, part in enumerate(it.get("parts", [])):
                check_poly(errs, f"{where}/part{k}", part.get("footprint"))
                if not isinstance(part.get("h"), (int, float)):
                    errs.append(f"{where}/part{k}: needs h")
            if layer == "buildings":
                if not isinstance(it.get("h"), (int, float)) and not it.get("parts"):
                    errs.append(f"{where}: needs h")
            for k, ps in enumerate(it.get("passages", [])):
                check_poly(errs, f"{where}/passage{k}", ps.get("polygon"))
            if "polygon" in it:
                check_poly(errs, where, it["polygon"])
            if "pts" in it:
                check_poly(errs, where, it["pts"], 2)
                if layer in ("roads", "paths") and not isinstance(it.get("w"), (int, float)):
                    errs.append(f"{where}: needs w")
            if layer == "water" and "polygon" not in it and "circle" not in it:
                errs.append(f"{where}: needs polygon or circle")
            blob = json.dumps(it).lower()
            for w in deny:
                if re.search(r"\b" + re.escape(w) + r"\b", blob):
                    errs.append(f"{where}: contains a real reference name ({w[:2]}…)")
    return errs, warns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--only", default="", help="validate just tools/campus/traced/<zone>.json")
    a = ap.parse_args()
    merged = {k: [] for k in LAYERS}
    files = [os.path.join(SRC, a.only + ".json")] if a.only else sorted(glob.glob(os.path.join(SRC, "*.json")))
    if a.only:
        a.check = True
    for f in files:
        d = json.load(open(f))
        zone = d.get("zone", os.path.basename(f)[:-5])
        for k in LAYERS:
            for it in d.get(k, []):
                it.setdefault("zone", zone)
                merged[k].append(it)
    errs, warns = validate(merged)
    for w in warns:
        print("warning:", w)
    for e in errs:
        print("ERROR:", e)
    counts = {k: len(v) for k, v in merged.items()}
    print("items:", counts)
    if errs:
        print(f"{len(errs)} error(s)"); sys.exit(1)
    if a.check:
        return
    os.makedirs(OUT, exist_ok=True)
    for k, items in merged.items():
        items.sort(key=lambda it: it["id"])
        with open(os.path.join(OUT, k + ".json"), "w") as fh:
            json.dump({"version": 1, "items": items}, fh, indent=1, sort_keys=True)
            fh.write("\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
