#!/usr/bin/env python3
"""Checks App Store screenshot sets: every image in OUT_DIR/iphone_6.9 and
OUT_DIR/ipad_13 (and the labelled references in OUT_DIR/iap) must have the
exact store size, be 8-bit RGB with no alpha (PNG colour type 2, or a
3-component JPEG) and be sRGB (a PNG with no colour-space chunk, which
viewers and App Store Connect read as sRGB, or an sRGB chunk; an embedded
ICC profile, gamma or chromaticity chunk fails).  Reads the files' own
bytes only (no imaging library needed).

What it cannot see: text or overlays drawn into the picture.  The store
drivers draw none (--store-shot); each image is still checked by eye at
full size (docs/media/final/store/README.md).

  python3 tools/store_shot_check.py OUT_DIR
"""
import os
import struct
import sys

SIZES = {"iphone_6.9": (2868, 1320), "ipad_13": (2752, 2064), "iap": (2868, 1320)}


def png_info(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    w, h, depth, ctype = struct.unpack(">IIBB", data[16:26])
    mode = {2: "RGB", 6: "RGBA", 0: "gray", 4: "gray+alpha", 3: "palette"}.get(ctype, str(ctype))
    chunks = set()
    i = 8
    while i + 8 <= len(data):
        n = struct.unpack(">I", data[i:i + 4])[0]
        kind = data[i + 4:i + 8].decode("latin-1")
        chunks.add(kind)
        if kind == "IEND":
            break
        i += 12 + n
    if "tRNS" in chunks:
        mode += "+tRNS"
    space = "sRGB chunk" if "sRGB" in chunks else "ICC/gamma (not plain sRGB)" if chunks & {"iCCP", "gAMA", "cHRM"} else "sRGB (untagged)"
    return w, h, mode, depth, space


def jpeg_info(path):
    with open(path, "rb") as f:
        data = f.read()
    icc = b"ICC_PROFILE" in data[:65536]
    i = 2
    while i < len(data) - 9:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        seg = struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            comps = data[i + 9]
            return w, h, "RGB" if comps == 3 else "%d components" % comps, 8, "ICC profile" if icc else "sRGB (untagged)"
        i += 2 + seg
    return None


def main():
    out = sys.argv[1]
    bad = 0
    seen = 0
    for sub, want in SIZES.items():
        d = os.path.join(out, sub)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            ext = name.lower().rsplit(".", 1)[-1]
            info = png_info(p) if ext == "png" else jpeg_info(p) if ext in ("jpg", "jpeg") else None
            if info is None:
                continue
            seen += 1
            w, h, mode, depth, space = info
            ok = (w, h) == want and mode == "RGB" and depth == 8 and space.startswith("sRGB")
            bad += 0 if ok else 1
            print("%s %s/%s %dx%d %s %d-bit %s %.1f MB" % ("OK " if ok else "BAD", sub, name, w, h, mode, depth, space,
                                                          os.path.getsize(p) / 1e6))
    print("store check: %d image(s), %s" % (seen, "all pass" if bad == 0 else "%d fail" % bad))
    return 1 if bad or seen == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
