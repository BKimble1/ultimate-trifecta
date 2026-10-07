#!/usr/bin/env python3
"""The coverage matrix: one row per inventory code (B01-B49, W01-W07,
A01-A07, C01-C06) and per traced structure under a grouped code, from the
data itself (what is built, its evidence, confidence and open questions),
the terrain bake (floor level, exposed foundation, stairs, entrance levels)
and the hand-written record of this pass's work (coverage_notes.json).

Writes docs/campus/COVERAGE_MATRIX.md (B-codes and neutral ids only).
With --private CSV OUT it also writes a copy that adds each code's real
reference name from the private inventory (outside the repository).

Usage: tools/campus/coverage_matrix.py [--private INVENTORY.csv OUT.md]
"""
import argparse
import csv
import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "game", "data", "campus")
LAYERS = ["buildings", "water", "roads", "paths", "areas", "barriers", "trees", "props"]
CODES = (["B%02d" % i for i in range(1, 50)] + ["W%02d" % i for i in range(1, 8)]
         + ["A%02d" % i for i in range(1, 8)] + ["C%02d" % i for i in range(1, 7)])


def load(name):
    d = json.load(open(os.path.join(DATA, name + ".json")))
    return d["items"] if isinstance(d, dict) else d


def codes_of(ref):
    out = []
    for c in str(ref or "").replace(" ", "").split(","):
        # "B30C03": a record under two codes
        while len(c) >= 3:
            out.append(c[:3])
            c = c[3:]
    return out


def labels():
    """code -> neutral label (NEUTRAL_NAMES.md)."""
    out = {}
    for line in open(os.path.join(ROOT, "docs", "campus", "NEUTRAL_NAMES.md")):
        if line.startswith("| ") and len(line.split("|")) > 4:
            cells = [c.strip() for c in line.split("|")[1:-1]]
            if len(cells[0]) == 3 and cells[0][0] in "BWAC" and cells[0][1:].isdigit():
                out[cells[0]] = cells[2]
    return out


def roof_of(b):
    kinds = []
    for p in b.get("parts", []) or [b]:
        r = p.get("roof", {})
        k = r.get("type", "flat")
        if r.get("vent"):
            k += "+vent"
        if r.get("pediment"):
            k += "+pediment"
        kinds.append(k)
    seen = []
    for k in kinds:
        if k not in seen:
            seen.append(k)
    return ", ".join(seen)


def esc(s):
    return str(s).replace("|", "/").replace("\n", " ")


def build():
    items = defaultdict(list)
    for layer in LAYERS:
        for it in load(layer):
            for c in codes_of(it.get("ref")):
                items[c].append((layer, it))
    terrain = json.load(open(os.path.join(DATA, "terrain.json")))
    stairs = defaultdict(list)
    for st in terrain.get("stairs", []):
        stairs[st["building"]].append(st)
    notes = json.load(open(os.path.join(HERE, "coverage_notes.json")))
    return items, terrain, stairs, notes


def building_cells(b, terrain, stairs):
    ev = b.get("ev", {})
    fl = terrain["floors"].get(b["id"], {})
    floor = fl.get("floor")
    show = (floor - fl["ground_min"]) if floor is not None else None
    ents = b.get("entrances", [])
    lv = terrain.get("entrances", {}).get(b["id"], {})
    walkout = sum(1 for e in lv.values() if "lower-level" in e.get("how", ""))
    st = stairs.get(b["id"], [])
    ent = "%d (%s)" % (len(ents), ", ".join(sorted(set(e.get("kind", "door") for e in ents)))) if ents else "none traced"
    if st:
        ent += "; %d stair%s (%s risers)" % (len(st), "s" if len(st) > 1 else "", "/".join(str(s["risers"]) for s in st))
    if walkout:
        ent += "; %d lower-level door%s at grade" % (walkout, "s" if walkout > 1 else "")
    style = b.get("style", {})
    mat = "/".join(x for x in [style.get("wall", ""), style.get("trim", ""), style.get("roof_mat", "")] if x)
    lvl = "-" if floor is None else "%.2f m%s" % (floor, ("; foundation shows %.1f m" % show) if show and show > 0.3 else "")
    return {
        "conf": ev.get("conf", "?"),
        "src": " ".join(ev.get("src", [])[:6]) + (" …" if len(ev.get("src", [])) > 6 else ""),
        "storeys": "%s / %.1f m" % (b.get("floors") or "-", float(b.get("h", 0))),
        "floor": lvl,
        "entrances": ent,
        "roof": roof_of(b),
        "materials": mat or "-",
        "open": ev.get("open", ""),
        "status": b.get("status", "existing"),
        "passages": len(b.get("passages", [])),
    }


def rows():
    items, terrain, stairs, notes = build()
    lab = labels()
    out = []
    for code in CODES:
        n = notes.get(code, {})
        its = items.get(code, [])
        kinds = defaultdict(int)
        for layer, it in its:
            kinds[layer] += 1
        what = ", ".join("%d %s" % (v, k) for k, v in sorted(kinds.items())) or "nothing traced"
        out.append({"code": code, "label": lab.get(code, ""), "what": what, "items": its, "note": n})
    return out, terrain, stairs


def write(path, real=None):
    rs, terrain, stairs = rows()
    L = []
    L.append("# Coverage matrix")
    L.append("")
    L.append("One row per inventory code of the reference campus, and one per traced structure under a code. "
             "Generated by `tools/campus/coverage_matrix.py` from the data (what is built, its evidence, "
             "confidence and open questions), the terrain bake (floor level, exposed foundation, stairs, "
             "entrance levels) and `tools/campus/coverage_notes.json` (this pass's work and limits, written "
             "by hand). Neutral names only" + ("; this private copy adds the reference names." if real else
             "; the reference names are in the private copy, outside the repository.") + " Regenerate after "
             "any data change.")
    L.append("")
    L.append("Order of work (the brief's): big forms, then facade rhythm and materials, then entries, terrain "
             "and landscape, then small detail. **Pass** says what this pass did to the row; "
             "**Remaining** is what the evidence still leaves open. Neither column claims a survey.")
    L.append("")
    for sect, prefix in [("Buildings", "B"), ("Waters", "W"), ("Sports", "A"), ("Context", "C")]:
        L.append("## " + sect)
        L.append("")
        for r in [r for r in rs if r["code"].startswith(prefix)]:
            name = r["label"] + ((" — " + real[r["code"]]) if real and r["code"] in real else "")
            L.append("### %s %s" % (r["code"], name))
            L.append("")
            n = r["note"]
            L.append("- **Traced:** %s." % r["what"])
            if n.get("state"):
                L.append("- **State (October 2026):** %s" % n["state"])
            L.append("- **Pass:** %s" % (n.get("work") or "Grounded on the measured terrain (floor level, foundation, entrance levels); no other change this pass."))
            L.append("- **Remaining:** %s" % (n.get("limits") or "See the open questions below."))
            if n.get("views"):
                L.append("- **Views:** %s" % n["views"])
            bl = [it for layer, it in r["items"] if layer == "buildings"]
            if bl:
                L.append("")
                L.append("| Structure | Status | Footprint conf. | Sources | Storeys / height | Floor level | Entrances / stairs | Roof | Wall / trim / roof | Open questions |")
                L.append("|---|---|---|---|---|---|---|---|---|---|")
                for b in bl:
                    c = building_cells(b, terrain, stairs)
                    L.append("| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                        b["id"], c["status"], c["conf"], esc(c["src"]), c["storeys"], c["floor"], esc(c["entrances"]),
                        esc(c["roof"]), esc(c["materials"]), esc(c["open"]) or "-"))
            wl = [it for layer, it in r["items"] if layer == "water"]
            if wl:
                L.append("")
                L.append("| Water | Kind | Surface (m) | Level from | Features | Open questions |")
                L.append("|---|---|---|---|---|---|")
                for w in wl:
                    lv = terrain["waters"].get(w["id"], {})
                    feats = ", ".join(sorted(set(f.get("kind", "") for f in w.get("features", [])))) or "-"
                    surf = lv.get("surface")
                    L.append("| `%s` | %s | %s | %s | %s | %s |" % (w["id"], w.get("kind", ""), "-" if surf is None else "%.2f" % surf,
                                                              esc(lv.get("how", "-")), feats, esc(w.get("ev", {}).get("open", "")) or "-"))
            L.append("")
    open(path, "w").write("\n".join(L) + "\n")
    print("wrote", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--private", nargs=2, metavar=("INVENTORY_CSV", "OUT"))
    a = ap.parse_args()
    write(os.path.join(ROOT, "docs", "campus", "COVERAGE_MATRIX.md"))
    if a.private:
        real = {}
        for row in csv.DictReader(open(a.private[0])):
            real[row["feature_id"]] = row["real_reference_name"]
        write(a.private[1], real)


if __name__ == "__main__":
    main()
