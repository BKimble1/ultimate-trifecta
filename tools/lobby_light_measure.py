#!/usr/bin/env python3
"""Lobby lighting measurements (final lobby pass) from tools/capture_final_lobby.sh.

For each shot it reads <shot>.png (what the player sees), <shot>_3d.png (UI
hidden), <shot>_room.png (UI and characters hidden) and <shot>.json, and reports:
  room      luma (Rec. 709 Y' of the sRGB pixel, 0-255) of the room frame:
            mean, p10, p50, p90, and the share of pixels under 40 (near black)
            and over 235 (near white)
  seen      the same over the frame the player sees (UI included)
  face/torso  each character's face and torso patch (the pixels inside the
            projected radius that belong to the character: they differ from
            the room frame), mean luma and mean sRGB colour
  refs      fixed room patches (lamp shade, window, wall, furniture, floor)
            from the room frame
  texts     every visible label/button: WCAG contrast of its text against
            its background, measured on the frame the player sees (text =
            the 98th/2nd luminance percentile in the rect, toward the font
            colour; background = the median)
Usage:
  tools/lobby_light_measure.py DIR [--json out.json] [--debug out_dir]
  tools/lobby_light_measure.py --compare BEFORE_DIR AFTER_DIR [--json out.json]
  tools/lobby_light_measure.py --summary DIR [DIR...]
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

SHOTS = ["00_home_new", "01_home", "02_locker", "03_shop", "04_shop_dark", "05_season", "06_lobby_1p", "07_lobby_4p", "08_lobby_8p"]


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


def luma(img):
    return img[..., 0] * 0.2126 + img[..., 1] * 0.7152 + img[..., 2] * 0.0722


def lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def rel_lum(img):
    li = lin(img)
    return li[..., 0] * 0.2126 + li[..., 1] * 0.7152 + li[..., 2] * 0.0722


def stats(y):
    y = y.ravel()
    if y.size == 0:
        return None
    return {"mean": round(float(y.mean()), 1), "p10": round(float(np.percentile(y, 10)), 1),
            "p50": round(float(np.percentile(y, 50)), 1), "p90": round(float(np.percentile(y, 90)), 1),
            "dark_pct": round(float((y < 40).mean() * 100.0), 1), "white_pct": round(float((y > 235).mean() * 100.0), 2)}


def disk(shape, x, y, r):
    h, w = shape[:2]
    yy, xx = np.ogrid[:h, :w]
    return (xx - x) ** 2 + (yy - y) ** 2 <= r * r


def measure_shot(d, shot):
    jp = os.path.join(d, shot + ".json")
    if not os.path.exists(jp):
        return None
    rep = json.load(open(jp))
    seen = load(os.path.join(d, shot + ".png"))
    td = load(os.path.join(d, shot + "_3d.png"))
    room = load(os.path.join(d, shot + "_room.png"))
    s = float(rep.get("px_per_unit", 1.0))
    out = {"screen": rep.get("screen"), "quality": rep.get("quality"), "room": stats(luma(room)), "seen": stats(luma(seen)),
           "scene3d": stats(luma(td))}
    diff = np.abs(td - room).sum(axis=2) > 18.0
    out["char_px_pct"] = round(float(diff.mean() * 100.0), 1)
    chars = []
    for c in rep.get("chars", []):
        e = {"key": c["key"], "local": c["local"], "outfit": c["outfit"], "skin": c["skin"], "color": c["color"]}
        for part in ("face", "torso"):
            p = c.get(part) or {}
            if not p:
                continue
            m = disk(td.shape, p["x"] * s, p["y"] * s, max(2.0, p["r"] * s)) & diff
            if m.sum() < 6:
                continue
            px = td[m]
            e[part] = {"luma": round(float(luma(px).mean()), 1), "rgb": [int(v) for v in px.mean(axis=0)], "n": int(m.sum())}
        chars.append(e)
    out["chars"] = chars
    refs = {}
    for k, p in rep.get("refs", {}).items():
        m = disk(room.shape, p["x"] * s, p["y"] * s, max(2.0, p["r"] * s))
        if m.sum() < 6:
            continue
        px = room[m]
        refs[k] = {"luma": round(float(luma(px).mean()), 1), "max": round(float(luma(px).max()), 1),
                   "rgb": [int(v) for v in px.mean(axis=0)]}
    out["refs"] = refs
    texts = []
    rl = rel_lum(seen)
    for t in rep.get("texts", []):
        x, y, w, h = [v * s for v in t["rect"]]
        if t["kind"] == "button":
            # the caption sits inside the face: leave out the rounded edges
            # and the drop shadow (they read as "text" otherwise)
            x, y, w, h = x + w * 0.15, y + h * 0.2, w * 0.7, h * 0.6
        x0, y0, x1, y1 = int(max(0, x)), int(max(0, y)), int(min(seen.shape[1], x + w)), int(min(seen.shape[0], y + h))
        if x1 - x0 < 4 or y1 - y0 < 4:
            continue
        r = rl[y0:y1, x0:x1].ravel()
        bg = float(np.median(r))
        hi, lo = float(np.percentile(r, 98)), float(np.percentile(r, 2))
        fc = t.get("color", "ffffffff")
        fl = rel_lum(np.array([[[int(fc[0:2], 16), int(fc[2:4], 16), int(fc[4:6], 16)]]], dtype=np.float32))[0, 0]
        if int(fc[6:8] or "ff", 16) < 26:
            # a button whose caption its face draws (no font colour): the
            # extreme farther from the background is the text
            txt = hi if (hi + 0.05) / (bg + 0.05) >= (bg + 0.05) / (lo + 0.05) else lo
        else:
            txt = hi if fl > bg else lo
        cr = (max(txt, bg) + 0.05) / (min(txt, bg) + 0.05)
        texts.append({"text": t["text"], "kind": t["kind"], "contrast": round(cr, 2), "bg_lum": round(bg, 4)})
    out["texts"] = texts
    return out


def shots_in(d):
    names = sorted(f[:-5] for f in os.listdir(d) if f.endswith(".json") and os.path.exists(os.path.join(d, f[:-5] + "_room.png")))
    return [s for s in SHOTS if s in names] + [s for s in names if s not in SHOTS]


def measure_dir(d):
    return {shot: m for shot in shots_in(d) if (m := measure_shot(d, shot)) is not None}


def summary(m):
    """One line per shot: room mean/p10/p50/p90, faces and torsos (local and others), key refs."""
    ch = m["chars"]
    loc = [c for c in ch if c["local"]]
    oth = [c for c in ch if not c["local"]]

    def avg(cs, part):
        v = [c[part]["luma"] for c in cs if part in c]
        return round(sum(v) / len(v), 1) if v else None
    r = m["room"]
    refs = m["refs"]
    pick = ["lamp_shade", "window_sky", "window_sill", "back_wall", "couch", "armchair", "bookshelf_base", "floor_front", "rug"]
    return ("room %5.1f p10 %5.1f p50 %5.1f p90 %5.1f <40 %4.1f%% | face L %s O %s | torso L %s O %s | " % (
        r["mean"], r["p10"], r["p50"], r["p90"], r["dark_pct"], avg(loc, "face"), avg(oth, "face"), avg(loc, "torso"), avg(oth, "torso"))
        + " ".join("%s %s" % (k, refs[k]["luma"]) for k in pick if k in refs))


def debug(d, outd):
    os.makedirs(outd, exist_ok=True)
    for shot in SHOTS:
        jp = os.path.join(d, shot + ".json")
        if not os.path.exists(jp):
            continue
        rep = json.load(open(jp))
        s = float(rep.get("px_per_unit", 1.0))
        im = Image.open(os.path.join(d, shot + "_3d.png")).convert("RGB")
        dr = ImageDraw.Draw(im)
        for c in rep.get("chars", []):
            for part, col in (("face", (255, 60, 60)), ("torso", (60, 255, 60)), ("head_bone", (255, 255, 0))):
                p = c.get(part) or {}
                if p:
                    x, y, r = p["x"] * s, p["y"] * s, max(2.0, p["r"] * s)
                    dr.ellipse([x - r, y - r, x + r, y + r], outline=col, width=2)
        for k, p in rep.get("refs", {}).items():
            x, y, r = p["x"] * s, p["y"] * s, max(2.0, p["r"] * s)
            dr.ellipse([x - r, y - r, x + r, y + r], outline=(0, 200, 255), width=2)
            dr.text((x + r + 2, y - 6), k, fill=(0, 200, 255))
        im.save(os.path.join(outd, shot + "_regions.png"))


def compare(bd, ad):
    b, a = measure_dir(bd), measure_dir(ad)
    rows = []
    for shot in sorted(set(b) & set(a), key=lambda x: (SHOTS.index(x) if x in SHOTS else 99, x)):
        if shot not in b or shot not in a:
            continue
        mb, ma = b[shot], a[shot]
        row = {"shot": shot}
        for k in ("room", "seen"):
            row[k] = {"before": mb[k], "after": ma[k]}
        fb = {c["key"]: c for c in mb["chars"]}
        fa = {c["key"]: c for c in ma["chars"]}
        row["chars"] = []
        for key, cb in fb.items():
            ca = fa.get(key)
            if not ca:
                continue
            row["chars"].append({"key": key, "outfit": cb["outfit"], "local": cb["local"],
                                 "face": [cb.get("face", {}).get("luma"), ca.get("face", {}).get("luma")],
                                 "face_rgb": [cb.get("face", {}).get("rgb"), ca.get("face", {}).get("rgb")],
                                 "torso": [cb.get("torso", {}).get("luma"), ca.get("torso", {}).get("luma")],
                                 "torso_rgb": [cb.get("torso", {}).get("rgb"), ca.get("torso", {}).get("rgb")]})
        row["refs"] = {k: [mb["refs"][k], ma["refs"].get(k)] for k in mb["refs"]}
        tb = {t["text"]: t for t in mb["texts"]}
        row["texts"] = [{"text": t["text"], "before": tb[t["text"]]["contrast"], "after": t["contrast"]} for t in ma["texts"] if t["text"] in tb]
        rows.append(row)
    return rows


def main():
    args = sys.argv[1:]
    out_json = None
    if "--json" in args:
        i = args.index("--json")
        out_json = args[i + 1]
        del args[i:i + 2]
    if args and args[0] == "--compare":
        res = compare(args[1], args[2])
        for r in res:
            print("== %s" % r["shot"])
            for k in ("room", "seen"):
                bb, aa = r[k]["before"], r[k]["after"]
                print("  %-6s mean %5.1f -> %5.1f   p10 %5.1f -> %5.1f   p50 %5.1f -> %5.1f   p90 %5.1f -> %5.1f   <40: %4.1f%% -> %4.1f%%   >235: %4.2f%% -> %4.2f%%" % (
                    k, bb["mean"], aa["mean"], bb["p10"], aa["p10"], bb["p50"], aa["p50"], bb["p90"], aa["p90"],
                    bb["dark_pct"], aa["dark_pct"], bb["white_pct"], aa["white_pct"]))
            for c in r["chars"]:
                print("  %-14s %-18s face %s -> %s %s->%s  torso %s -> %s %s->%s" % (
                    c["key"][:14], c["outfit"], c["face"][0], c["face"][1], c["face_rgb"][0], c["face_rgb"][1],
                    c["torso"][0], c["torso"][1], c["torso_rgb"][0], c["torso_rgb"][1]))
            for k, (rb, ra) in r["refs"].items():
                if ra:
                    print("  ref %-16s %5.1f -> %5.1f (max %5.1f -> %5.1f)" % (k, rb["luma"], ra["luma"], rb["max"], ra["max"]))
        if out_json:
            json.dump(res, open(out_json, "w"), indent=1)
        return
    if args and args[0] == "--summary":
        for d in args[1:]:
            for shot, m in measure_dir(d).items():
                print("%-28s %-14s %s" % (os.path.basename(d.rstrip("/"))[-28:], shot, summary(m)))
        return
    d = args[0]
    if "--debug" in args:
        debug(d, args[args.index("--debug") + 1])
    res = measure_dir(d)
    for shot, m in res.items():
        print("== %s room %s" % (shot, m["room"]))
        for c in m["chars"]:
            print("   %-14s %-18s face %s torso %s" % (c["key"][:14], c["outfit"], c.get("face"), c.get("torso")))
        for k, v in m["refs"].items():
            print("   ref %-16s %s" % (k, v))
    if out_json:
        json.dump(res, open(out_json, "w"), indent=1)


if __name__ == "__main__":
    main()
