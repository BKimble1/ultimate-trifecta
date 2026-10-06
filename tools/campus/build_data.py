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


GATE_KINDS = {"wall_low", "fence_iron", "fence_chain", "hedge", "rail"}


def _cross(a, b, c, d):
    """Intersection parameter (t along a-b, u along c-d) of two segments, or None."""
    rx, rz = b[0] - a[0], b[1] - a[1]
    sx, sz = d[0] - c[0], d[1] - c[1]
    den = rx * sz - rz * sx
    if abs(den) < 1e-9:
        return None
    qx, qz = c[0] - a[0], c[1] - a[1]
    t = (qx * sz - qz * sx) / den
    u = (qx * rz - qz * rx) / den
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return t, u
    return None


def cut_gates(merged):
    """Where a traced walk or road crosses a fence, hedge, rail or low wall
    (at more than 25 degrees), the barrier gets a gap as wide as the walk
    plus 0.8 m: the tracers drew barriers and walks separately, and a real
    walk through a fence line passes a gate.  Construction fences and retaining walls are
    left closed.  Returns the number of gaps cut."""
    walks = list(merged["paths"]) + list(merged["roads"])
    out, cuts = [], 0
    for br in merged["barriers"]:
        pts = br.get("pts") or []
        if br.get("kind") not in GATE_KINDS or len(pts) < 2:
            out.append(br)
            continue
        # cumulative distance along the barrier, and the gaps as [s0, s1]
        acc = [0.0]
        for i in range(1, len(pts)):
            acc.append(acc[-1] + math.dist(pts[i - 1], pts[i]))
        gaps = []
        for w in walks:
            wp = w.get("pts") or []
            hw = float(w.get("w", 2.0)) * 0.5 + 0.4
            for j in range(len(wp) - 1):
                for i in range(len(pts) - 1):
                    r = _cross(pts[i], pts[i + 1], wp[j], wp[j + 1])
                    if r is None:
                        continue
                    bx, bz = pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]
                    wx, wz = wp[j + 1][0] - wp[j][0], wp[j + 1][1] - wp[j][1]
                    lb, lw = math.hypot(bx, bz), math.hypot(wx, wz)
                    if lb < 1e-6 or lw < 1e-6:
                        continue
                    sin_a = abs(bx * wz - bz * wx) / (lb * lw)
                    if sin_a < math.sin(math.radians(25)):
                        continue
                    sc = acc[i] + r[0] * lb
                    half = hw / sin_a
                    gaps.append([sc - half, sc + half])
        if not gaps:
            out.append(br)
            continue
        gaps.sort()
        merged_g = [gaps[0]]
        for g in gaps[1:]:
            if g[0] <= merged_g[-1][1]:
                merged_g[-1][1] = max(merged_g[-1][1], g[1])
            else:
                merged_g.append(g)
        cuts += len(merged_g)

        def at(sv):
            for i in range(1, len(pts)):
                if sv <= acc[i] or i == len(pts) - 1:
                    seg = acc[i] - acc[i - 1]
                    f = 0.0 if seg < 1e-9 else min(1.0, max(0.0, (sv - acc[i - 1]) / seg))
                    return [round(pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f, 2), round(pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f, 2)]
        keep, s0 = [], 0.0
        for g in merged_g + [[acc[-1], acc[-1]]]:
            s1 = min(g[0], acc[-1])
            if s1 - s0 >= 0.4:
                piece = [at(s0)] + [list(pts[i]) for i in range(1, len(pts) - 1) if s0 < acc[i] < s1] + [at(s1)]
                keep.append(piece)
            s0 = max(s0, g[1])
        for n, piece in enumerate(keep):
            nb = dict(br)
            nb["pts"] = piece
            if n:
                nb["id"] = "%s_g%d" % (br["id"], n)
            ev = dict(nb.get("ev") or {})
            note = "gate gap(s) cut where traced walks cross (merge rule)"
            ev["open"] = (ev.get("open", "") + "; " + note).strip("; ") if note not in ev.get("open", "") else ev.get("open", "")
            nb["ev"] = ev
            out.append(nb)
    merged["barriers"] = out
    return cuts


# half sizes (m) of what stands beside a walk: a tree's trunk collider, props
HALF = {"tree": 0.42, "bench": 0.5, "table": 0.9, "planter": 0.6, "sign_blank": 0.8, "bike_rack": 1.0,
        "lamp": 0.14, "light_pole": 0.2, "bin": 0.3}


def _closest(p, a, b):
    ax, az = b[0] - a[0], b[1] - a[1]
    L2 = ax * ax + az * az
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * az) / L2))
    return (a[0] + ax * t, a[1] + az * t), (ax, az)


def _walk_hit(p, half, walks, skip=None):
    """The walk segment whose band (half width + half + 0.1) holds p, as
    (walk, closest point, segment direction, needed distance), or None."""
    for w in walks:
        if w is skip:
            continue
        need = float(w.get("w", 2.0)) * 0.5 + half + 0.1
        wp = w.get("pts") or []
        for a, b in zip(wp, wp[1:]):
            q, d = _closest(p, a, b)
            if math.dist(p, q) < need:
                return w, q, d, need
    return None


def nudge_off_walks(merged):
    """Trunks and props whose traced spot falls on a walk (crowns and
    pole shadows put them a little off) move straight out to the walk's
    edge, unless that lands them on another walk.  Returns (moved, left)."""
    walks = merged["paths"]
    moved = left = 0
    for layer, key in (("trees", "pos"), ("props", "p")):
        for it in merged[layer]:
            half = HALF.get("tree" if layer == "trees" else it.get("kind", ""), 0.0)
            if half <= 0.0 or not it.get(key) or (layer == "trees" and it.get("collide") is False):
                continue
            p = tuple(it[key])
            hit = _walk_hit(p, half, walks)
            if hit is None:
                continue
            w, q, d, need = hit
            nx, nz = p[0] - q[0], p[1] - q[1]
            L = math.hypot(nx, nz)
            if L < 1e-3:
                L2 = math.hypot(d[0], d[1]) or 1.0
                nx, nz, L = -d[1] / L2, d[0] / L2, 1.0
            np_ = (round(q[0] + nx / L * (need + 0.05), 2), round(q[1] + nz / L * (need + 0.05), 2))
            if _walk_hit(np_, half, walks) is not None:
                left += 1
                continue
            it[key] = [np_[0], np_[1]]
            ev = dict(it.get("ev") or {})
            ev["open"] = (ev.get("open", "") + "; nudged %.1f m off a traced walk (merge rule)" % math.dist(p, np_)).strip("; ")
            it["ev"] = ev
            moved += 1
    return moved, left


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
    gates = cut_gates(merged)
    print("gate gaps cut where walks cross barriers:", gates)
    print("trunks/props nudged off walks (moved, left in place):", nudge_off_walks(merged))
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
