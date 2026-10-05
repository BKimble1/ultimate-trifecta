#!/usr/bin/env python3
"""V7 screens evidence: picks matched before/after runtime captures made by
tools/capture_v7_screens.sh, writes them as JPEGs into
docs/media/v7/screens/<device>/<shot>_{before,after}.jpg and prints a
Markdown table of measured layout facts from the <shot>_layout.json files
(final allocated rects, canvas units).

Usage: tools/make_v7_screens_media.py BEFORE_DIR AFTER_DIR [OUT_DIR] > facts.md
"""
import json
import os
import sys

from PIL import Image

DEVICES = {
    "se": "iPhone SE class, 667x375 pt @2x, safe 0,0,0,0",
    "x14": "812x375 pt @3x, safe 44,0,44,21",
    "p14": "844x390 pt @3x, safe 47,0,47,21",
    "max": "926x428 pt @3x, safe 47,0,47,21",
    "ipad": "iPad 1024x768 pt @2x, safe 0,24,0,20",
    "a2048": "2048x946 px (owner screenshot aspect) as an 844x390 pt phone, @2.4265, safe 47,0,47,21",
    "a1536": "1536x710 px (owner screenshot aspect) as an 812x375 pt phone, @1.8916, safe 44,0,44,21",
}
EVERY = ["friends", "friends_keyboard", "settings_top"]
DETAIL = ["friends_invalid", "settings_controls", "settings_sound", "settings_graphics", "settings_diagnostics",
          "settings_end", "confirm_delete", "home", "party_1p", "party_4p", "results_practice", "results_series_round",
          "final_standings", "confirm_leave_party"]
SWEEP = ["results_series_round", "final_standings", "party_4p"]
WIDTH = 1100


def shots_for(dev):
    if dev in ("se", "p14", "ipad"):
        return EVERY + DETAIL
    return EVERY + SWEEP


def jpeg(src, dst):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    if w > WIDTH:
        im = im.resize((WIDTH, round(h * WIDTH / w)), Image.LANCZOS)
    im.save(dst, "JPEG", quality=80, optimize=True)


def layout(d, dev, shot):
    p = os.path.join(d, dev, shot + "_layout.json")
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return json.load(f)


def find(lay, kind, text):
    for c in lay["controls"]:
        if c["kind"] == kind and c["text"].lower().startswith(text.lower()):
            return c
    return None


def whole(c):
    return c is not None and "clipped" not in c and "offscreen" not in c


def friends_fact(lay):
    if lay is None:
        return "-"
    parts = []
    for kind, text, name in [("button", "Create Party", "Create"), ("field", "ACE", "field"), ("button", "Join", "Join"),
                             ("button", "Show Game Center", "friends")]:
        c = find(lay, kind, text)
        parts.append("%s %s" % (name, "whole" if whole(c) else ("cut" if c else "missing")))
    f = find(lay, "field", "ACE")
    j = find(lay, "button", "Join")
    if f and j:
        parts.append("field %dx%d / Join %dx%d" % (f["rect"][2], f["rect"][3], j["rect"][2], j["rect"][3]))
    return ", ".join(parts)


def keyboard_fact(lay):
    if lay is None:
        return "-"
    f = find(lay, "field", "ACE")
    j = find(lay, "button", "Join")
    kb = lay["keyboard_units"]
    top = lay["viewport"][1] - kb
    covered = [n for n, c in (("field", f), ("Join", j)) if c and c.get("under_keyboard")]
    return "keyboard top %.0f; %s; row bottom %.0f" % (top, ("covered: " + ", ".join(covered)) if covered else "field and Join above it",
                                                        max(f["rect"][1] + f["rect"][3], j["rect"][1] + j["rect"][3]) if f and j else -1)


def settings_fact(lay):
    if lay is None:
        return "-"
    vh = lay["viewport"][1]
    shown = []
    sound_y = None
    for c in lay["controls"]:
        if c["kind"] != "label":
            continue
        t = c["text"]
        if t in ("Profile", "Controls", "Sound", "Graphics", "Camera & comfort", "Diagnostics"):
            if "clipped" not in c:
                shown.append(t)
            if t == "Sound":
                sound_y = c["rect"][1]
    sprint = [c for c in lay["controls"] if c["kind"] == "button" and ("stick to" in c["text"] or "Sprint button" in c["text"])]
    if not sprint:
        sp = "Sprint row -"
    elif all(whole(c) for c in sprint):
        sp = "Sprint row fully shown"
    elif any(c.get("clipped") == "partly visible" for c in sprint):
        sp = "Sprint row at the list's bottom edge"
    else:
        sp = "Sprint row below the first view"
    if any(c.get("trimmed") for c in sprint):
        sp += " (option text trimmed)"
    return "sections in the first view: %s; Sound starts %s; %s" % (", ".join(shown) or "-",
        "%.1f screens down" % (sound_y / vh) if sound_y else "-", sp)


def main():
    before, after = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(__file__), "..", "docs", "media", "v7", "screens")
    n = 0
    for dev in DEVICES:
        os.makedirs(os.path.join(out, dev), exist_ok=True)
        for shot in shots_for(dev):
            for tag, d in (("before", before), ("after", after)):
                src = os.path.join(d, dev, shot + ".png")
                if os.path.exists(src):
                    jpeg(src, os.path.join(out, dev, "%s_%s.jpg" % (shot, tag)))
                    n += 1
                else:
                    print("missing %s %s %s" % (tag, dev, shot), file=sys.stderr)
    print("| Device | | Play with Friends, first view | Keyboard open on the code | Settings, first view |")
    print("|---|---|---|---|---|")
    for dev, label in DEVICES.items():
        for tag, d in (("before", before), ("after", after)):
            print("| %s | %s | %s | %s | %s |" % (label if tag == "before" else "", tag, friends_fact(layout(d, dev, "friends")),
                                                  keyboard_fact(layout(d, dev, "friends_keyboard")), settings_fact(layout(d, dev, "settings_top"))))
    print("\n%d images written to %s" % (n, os.path.normpath(out)), file=sys.stderr)


if __name__ == "__main__":
    main()
