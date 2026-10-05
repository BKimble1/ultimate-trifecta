#!/usr/bin/env python3
"""Pass 8 Shop evidence: turns the PNGs made by tools/capture_pass8_shop.sh
into JPEGs under docs/media/pass8/shop/<device>/, keeps each shot's
measured layout report (<shot>_layout.json: final control rects in canvas
units, the safe area, touch_min and any clipped/off-screen/trimmed issue)
and writes docs/media/pass8/shop/README.md with a table of those facts.

Every shot is a DEV FIXTURE desktop render (simulated service clock and
schedule, simulated store with "(test price)"), labelled in the image.

Usage: tools/make_pass8_shop_media.py CAPTURE_DIR [OUT_DIR]
"""
import json
import os
import shutil
import sys

from PIL import Image

DEVICES = {
    "se": "iPhone SE class, 667x375 pt @2x, safe 0,0,0,0 (1334x750 px)",
    "p14": "iPhone 12-14 class, 844x390 pt @3x, safe 47,0,47,21 (2532x1170 px)",
    "ipad": "iPad 4:3, 1024x768 pt @2x, safe 0,24,0,20 (2048x1536 px)",
}
SHOTS = [
    ("shop_featured", "Featured: four rotating offers, each 'Leaves in …'; 'Shop refreshes in …' labelled separately; the return note"),
    ("shop_featured_always", "Featured scrolled: the compact Always available block (Apple skins, Season 1 Premium, links)"),
    ("shop_detail_offer", "An offer's sheet: price, countdown and the local departure date/time; one action"),
    ("shop_confirm_offer", "Coin confirmation: skin, price, balance and balance after"),
    ("shop_coins", "The six Coin packs: full quantities, the store's price strings (simulated: '(test price)')"),
    ("shop_all_skins_out_of_rotation", "All skins with a skin out of rotation ('Not in current rotation')"),
    ("shop_detail_not_in_rotation", "That skin's sheet: preview on the runner, no purchase"),
    ("shop_change_before", "Catalogue schedule only: seconds before a 00:00 UTC change"),
    ("shop_change_after", "Catalogue schedule only: after it, two cards replaced in place"),
    ("shop_stale_connect_to_refresh", "No trusted time (fresh run, offline): 'Connect to refresh Shop', last offers previewable only"),
    ("shop_service_off", "No service in the build (today's shipped state): no rotation, the existing unavailable state"),
]
WIDTH = 1280


def main(argv):
    src = argv[1]
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    out = argv[2] if len(argv) > 2 else os.path.join(root, "docs", "media", "pass8", "shop")
    rows = []
    for dev, desc in DEVICES.items():
        d = os.path.join(src, dev)
        if not os.path.isdir(d):
            continue
        od = os.path.join(out, dev)
        os.makedirs(od, exist_ok=True)
        for shot, what in SHOTS:
            png = os.path.join(d, shot + ".png")
            if not os.path.exists(png):
                continue
            im = Image.open(png).convert("RGB")
            if im.width > WIDTH:
                im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
            im.save(os.path.join(od, shot + ".jpg"), quality=86, optimize=True)
            lay = os.path.join(d, shot + "_layout.json")
            facts = ""
            if os.path.exists(lay):
                shutil.copy(lay, os.path.join(od, shot + "_layout.json"))
                js = json.load(open(lay))
                small = [c for c in js["controls"] if c.get("small_target")]
                facts = "%d issues; %d controls measured; touch_min %.1f units; %d small targets%s" % (
                    len(js["issues"]), len(js["controls"]), js["touch_min"], len(small),
                    (": " + "; ".join(js["issues"][:3])) if js["issues"] else "")
            rows.append((dev, shot, what, facts))
    lines = ["# Pass 8 Shop evidence (DEV FIXTURE desktop renders)", "",
             "Made by `tools/capture_pass8_shop.sh OUT se p14 ipad` then `tools/make_pass8_shop_media.py OUT`.",
             "The real game rendered by the Mobile renderer on llvmpipe under Xvfb at each device's pixel size with",
             "its point scale and safe area (the V7 screens approach). **DEV FIXTURE**: the test-double service's clock",
             "(2026-10-06 21:45:51 UTC at the start, then real time) and schedule, and the simulated store, whose prices",
             "read \"(test price)\": every image says so in its bottom label. Before the skins stream's art merges, the",
             "six new outfits have no `Cosmetics` entry, so the fixture uses the rotating skins that have art (the four",
             "V6 Coin outfits) in the schedule's 48 h / 00:00 UTC shape; re-run after the merge for the catalogue's own",
             "schedule (then two extra shots show a 00:00 UTC change before/after). Layout and states only: not frame",
             "rate, not a deployed service, not a real price or purchase. `<shot>_layout.json` holds the measured",
             "control rects (canvas units) and any clipped, off-screen, outside-safe-area or trimmed control.", "",
             "Devices: " + "; ".join("`%s` %s" % kv for kv in DEVICES.items()) + ".", "",
             "| Device | Shot | What it shows | Measured layout |", "|---|---|---|---|"]
    for dev, shot, what, facts in rows:
        lines.append("| %s | [%s](%s/%s.jpg) | %s | %s |" % (dev, shot, dev, shot, what, facts))
    with open(os.path.join(out, "README.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %d shots into %s" % (len(rows), os.path.relpath(out, root)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
