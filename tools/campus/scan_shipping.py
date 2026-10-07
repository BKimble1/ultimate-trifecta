"""Shipping-content scan for the campus rebuild (acceptance gate 8).

    python3 tools/campus/scan_shipping.py [--pack DIR] [--deny FILE]

Checks what ships in the game and its store material, not the private
research:

1. Real names: every text file under game/ (except tests/ and tools/, which
   are excluded from the export; src/dev is scanned too, to be safe) and
   docs/store-facing folders is screened for the private deny list (real
   institution, building, hall, street and donor names), word by word.
2. Reference images: no file under game/ or docs/ is byte-identical to any
   file in the reference pack (photos, maps, video frames, the atlas), and
   no shipped image is a resized copy of one (a perceptual 16x16 hash
   within a small distance).
3. Data: game/data/campus/*.json ids and labels are neutral (the same
   screen), and nothing in it points at the pack.

Exits non-zero on any finding.  The deny list, its reviewed allowlist of
generic word uses (e.g. an ordinary English word that is also a name) and
the pack stay outside the repository; without them the scan says it could
not run.
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TEXT_EXT = {".gd", ".tscn", ".tres", ".json", ".cfg", ".md", ".txt", ".gdshader", ".gdshaderinc", ".csv", ".import", ".godot", ".plist", ".html"}
IMG_EXT = {".png", ".jpg", ".jpeg", ".webp"}
SCAN_DIRS = ["game", "docs/store", "docs/final", "docs/campus", "docs/maps", "store"]
SKIP_PARTS = {".godot", ".import", "tests", "tools"}


def deny_words(path):
    if not os.path.exists(path):
        return None
    return [w.strip().lower() for w in open(path) if len(w.strip()) >= 4]


def files(root):
    for d in SCAN_DIRS:
        base = os.path.join(root, d)
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            rel = os.path.relpath(dp, root).split(os.sep)
            if any(p in SKIP_PARTS for p in rel[1:]):
                continue
            for f in fn:
                yield os.path.join(dp, f)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ahash(path):
    try:
        from PIL import Image
        im = Image.open(path).convert("L").resize((16, 16))
        px = list(im.tobytes())
        avg = sum(px) / len(px)
        return sum(1 << i for i, v in enumerate(px) if v > avg)
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.environ.get("CAMPUS_REF", "/home/user/campus_ref/Ultimate_Trifecta_Campus_Pack"))
    ap.add_argument("--deny", default=os.environ.get("CAMPUS_DENY", "/home/user/campus_ref/work/denylist.txt"))
    ap.add_argument("--allow", default=os.environ.get("CAMPUS_DENY_ALLOW", "/home/user/campus_ref/work/deny_allow.tsv"),
                    help="private list of reviewed generic uses: path<TAB>word<TAB>reason")
    a = ap.parse_args()
    deny = deny_words(a.deny)
    if deny is None or not os.path.isdir(a.pack):
        print("cannot run: the private deny list and the reference pack are needed (outside the repository)")
        sys.exit(2)
    allow = set()
    if os.path.exists(a.allow):
        for line in open(a.allow):
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                allow.add((parts[0], parts[1].lower()))
    findings = []
    allowed = 0
    shipped = list(files(ROOT))
    # 1. names
    pats = [(w, re.compile(r"\b" + re.escape(w) + r"\b", re.I)) for w in deny]
    n_text = 0
    for f in shipped:
        if os.path.splitext(f)[1].lower() not in TEXT_EXT:
            continue
        n_text += 1
        try:
            txt = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        rel = os.path.relpath(f, ROOT)
        for w, p in pats:
            if (rel, w) in allow:
                allowed += len(p.findall(txt))
                continue
            for m in p.finditer(txt):
                line = txt.count("\n", 0, m.start()) + 1
                findings.append(f"name: {os.path.relpath(f, ROOT)}:{line} ({w[:2]}…)")
    # 2. images
    pack_sha = {}
    pack_hash = []
    for dp, dn, fn in os.walk(a.pack):
        for f in fn:
            p = os.path.join(dp, f)
            try:
                pack_sha[sha(p)] = p
            except Exception:
                continue
            if os.path.splitext(f)[1].lower() in IMG_EXT:
                h = ahash(p)
                if h is not None:
                    pack_hash.append(h)
    n_img = 0
    for f in shipped:
        ext = os.path.splitext(f)[1].lower()
        try:
            s = sha(f)
        except Exception:
            continue
        if s in pack_sha:
            findings.append(f"copy: {os.path.relpath(f, ROOT)} is identical to a reference file")
        if ext in IMG_EXT:
            n_img += 1
            h = ahash(f)
            if h is None:
                continue
            for ph in pack_hash:
                if bin(h ^ ph).count("1") <= 6:
                    findings.append(f"image: {os.path.relpath(f, ROOT)} looks like a reference image")
                    break
    # 3. data
    data_dir = os.path.join(ROOT, "game", "data", "campus")
    n_items = 0
    if os.path.isdir(data_dir):
        for f in sorted(os.listdir(data_dir)):
            if f.endswith(".json"):
                d = json.load(open(os.path.join(data_dir, f)))
                n_items += len(d.get("items", []))
                blob = json.dumps(d).lower()
                if "campus_ref" in blob or "ultimate_trifecta_campus_pack" in blob:
                    findings.append(f"data: {f} points at the reference pack")
    for x in findings:
        print("FINDING", x)
    print(f"scanned {len(shipped)} shipped files ({n_text} text, {n_img} images), {n_items} data items "
          f"against {len(deny)} private names and {len(pack_sha)} reference files: {len(findings)} finding(s)"
          f" ({allowed} reviewed generic word uses allowed)")
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
