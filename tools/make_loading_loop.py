#!/usr/bin/env python3
"""Builds the match loading screen's character loop from the owner's clip.

    python3 -m venv tools/.cache/cvenv
    tools/.cache/cvenv/bin/pip install numpy pillow opencv-python-headless
    tools/.cache/cvenv/bin/python tools/make_loading_loop.py      (needs ffmpeg)

Source: art_src/loading/characters_run.mp4 (1280x720, 24 fps, 10 s, supplied
by the owner).  It has ~4.4 s of the three runners running toward the camera,
then they run past it and ~4 s of empty background, so it can't loop whole.

The loop is one stride, source frames 29..47 (19 frames, 0.79 s at 24 fps):
- Seam.  Frame 48 is the stride after 29 for all three runners (searched by
  aligning each runner separately; their strides are 19-21 frames).  No
  blink or wink falls inside (the clip's are at frames 18-26 and 62-66).
- Approach.  The runners come toward the camera at different speeds (the
  middle one fastest), so frame 48 is each runner slightly bigger and lower
  than frame 29.  Each runner's column gets its own gradual scale/shift over
  the loop (none at frame 0, the measured 48->29 alignment at the end), so
  they run in place and the stride closes.  Neighbouring runners meet on a
  per-frame seam through the background between them (the path where both
  warps agree), so an arm reaching across keeps moving with its owner.
- Restart.  The first two loop frames are morphed (optical flow, not a
  crossfade) from the clip's own continuation (48, 49, aligned) into 29, 30,
  so the step from the last frame back to the first is ordinary motion.
Nothing is reversed or retimed.

Crop: 960x720 around the group (x 140..1100 of 1280, full height), never
scaled up, so the runners keep their proportions and all three stay whole.

Writes (game/assets/loading/):
  run_loop_atlas.jpg  frames of 960x720 in a COLS x ROWS grid, row-major
  run_still.jpg       loop frame 0: shown at once, and if the loop can't load
  run_loop.json       frame size, count, fps, grid and background colours
"""
import json, os, subprocess, tempfile
import numpy as np
import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_src", "loading", "characters_run.mp4")
OUT = os.path.join(ROOT, "game", "assets", "loading")
I0, I1 = 29, 48                 # loop = I0 .. I1-1; I1 is the stride after I0
N = I1 - I0
MORPH = 2                       # restart frames morphed from the continuation
CROP = (140, 0, 1100, 720)
COLS = 5
FPS = 24
# Per runner (full-res pixels): the column it owns, the anchor (feet, between
# the shoes) and the alignment that maps frame I1 onto frame I0, measured by
# a scale/shift search per column (scale, dx, dy).
RUNNERS = {
    "frog":   {"cols": (0, 452),     "anchor": (300, 600), "align": (0.97, 4, -12)},
    "blue":   {"cols": (452, 800),   "anchor": (630, 610), "align": (0.94, 4, -20)},
    "orange": {"cols": (800, 1280),  "anchor": (940, 600), "align": (0.97, 4, 20)},
}
BAND = 80                       # seam search either side of a column edge, px
FEATHER = 2.5                   # seam softening (Gaussian sigma), px


def read_frames(first: int, count: int) -> list:
    tmp = tempfile.mkdtemp()
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", SRC, "-vf",
                    f"select='between(n\\,{first}\\,{first + count - 1})'", "-vsync", "0",
                    os.path.join(tmp, "f%03d.png")], check=True)
    return [cv2.imread(os.path.join(tmp, "f%03d.png" % (k + 1))).astype(np.float32) for k in range(count)]


def affine(s: float, dx: float, dy: float, ax: float, ay: float) -> np.ndarray:
    return np.float32([[s, 0, (1 - s) * ax + dx], [0, s, (1 - s) * ay + dy]])


def warp(img: np.ndarray, m: np.ndarray) -> np.ndarray:
    return cv2.warpAffine(img, m, (img.shape[1], img.shape[0]), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)


def seam(a: np.ndarray, b: np.ndarray, x: int) -> np.ndarray:
    """A top-to-bottom path within BAND of column x where images a and b
    agree best (the background between two runners), one x per row."""
    lo, hi = x - BAND, x + BAND
    d = np.abs(a[:, lo:hi] - b[:, lo:hi]).sum(2)
    d = cv2.GaussianBlur(d, (0, 0), 3) + 0.05 * np.abs(np.arange(lo, hi) - x)[None, :]
    h, w = d.shape
    acc = d.copy()
    back = np.zeros((h, w), np.int32)
    for y in range(1, h):
        prev = acc[y - 1]
        opts = np.stack([np.r_[np.inf, prev[:-1]], prev, np.r_[prev[1:], np.inf]])
        k = opts.argmin(0)
        back[y] = np.arange(w) + k - 1
        acc[y] += opts[k, np.arange(w)]
    path = np.zeros(h, np.int32)
    path[-1] = int(acc[-1].argmin())
    for y in range(h - 1, 0, -1):
        path[y - 1] = back[y, path[y]]
    return path + lo


def compensate(img: np.ndarray, u: float) -> np.ndarray:
    """u = 0: unchanged; u = 1: the full I1 -> I0 alignment, per runner.
    Each runner keeps its own warp up to a seam through the background next
    to it, so an arm reaching toward a neighbour moves with its owner."""
    warped = []
    for r in RUNNERS.values():
        s, dx, dy = r["align"]
        warped.append(warp(img, affine(1 + (s - 1) * u, dx * u, dy * u, *r["anchor"])))
    out = warped[0]
    h, w = img.shape[:2]
    xs = np.arange(w)[None, :]
    for i, r in enumerate(list(RUNNERS.values())[1:], 1):
        path = seam(out, warped[i], r["cols"][0])
        right = (xs >= path[:, None]).astype(np.float32)
        right = cv2.GaussianBlur(right, (0, 0), FEATHER)[..., None]
        out = out * (1 - right) + warped[i] * right
    return out


def morph(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    """Optical-flow morph from a (t=0) to b (t=1)."""
    ga = cv2.cvtColor(a.astype(np.uint8), cv2.COLOR_BGR2GRAY)
    gb = cv2.cvtColor(b.astype(np.uint8), cv2.COLOR_BGR2GRAY)
    f_ab = cv2.calcOpticalFlowFarneback(ga, gb, None, 0.5, 4, 25, 4, 7, 1.5, 0)
    f_ba = cv2.calcOpticalFlowFarneback(gb, ga, None, 0.5, 4, 25, 4, 7, 1.5, 0)
    h, w = ga.shape
    gx, gy = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    # sample a part-way along its flow toward b, and b part-way back toward a
    wa = cv2.remap(a, gx + f_ba[..., 0] * (1 - t), gy + f_ba[..., 1] * (1 - t), cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    wb = cv2.remap(b, gx + f_ab[..., 0] * t, gy + f_ab[..., 1] * t, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    return (1 - t) * wa + t * wb


def main() -> None:
    src = read_frames(I0, N + MORPH)            # I0 .. I1 + MORPH - 1
    loop = [compensate(src[k], k / N) for k in range(N)]
    for k in range(MORPH):
        cont = compensate(src[N + k], (N + k) / N)    # the clip's own next frames, aligned
        loop[k] = morph(cont, loop[k], (k + 1) / (MORPH + 1))
    x0, y0, x1, y1 = CROP
    fw, fh = x1 - x0, y1 - y0
    rows = (N + COLS - 1) // COLS
    atlas = np.zeros((fh * rows, fw * COLS, 3), np.uint8)
    for k, f in enumerate(loop):
        atlas[(k // COLS) * fh:(k // COLS + 1) * fh, (k % COLS) * fw:(k % COLS + 1) * fw] = np.clip(f[y0:y1, x0:x1], 0, 255).astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    cv2.imwrite(os.path.join(OUT, "run_loop_atlas.jpg"), atlas, [cv2.IMWRITE_JPEG_QUALITY, 92, cv2.IMWRITE_JPEG_SAMPLING_FACTOR, cv2.IMWRITE_JPEG_SAMPLING_FACTOR_444])
    still = atlas[0:fh, 0:fw]
    cv2.imwrite(os.path.join(OUT, "run_still.jpg"), still, [cv2.IMWRITE_JPEG_QUALITY, 92, cv2.IMWRITE_JPEG_SAMPLING_FACTOR, cv2.IMWRITE_JPEG_SAMPLING_FACTOR_444])
    rgb = still[..., ::-1].astype(np.float32)
    hexc = lambda c: "%02x%02x%02x" % tuple(int(round(v)) for v in c)
    edge = np.concatenate([rgb[:, :24].reshape(-1, 3), rgb[:, -24:].reshape(-1, 3)])
    corner = np.concatenate([rgb[:60, :60].reshape(-1, 3), rgb[:60, -60:].reshape(-1, 3), rgb[-60:, :60].reshape(-1, 3), rgb[-60:, -60:].reshape(-1, 3)])
    # the frame's own side colours row by row (top to bottom), for the
    # screen around it, and its floor colour for below it
    stops = []
    for r in range(9):
        y = min(fh - 8, int(r * (fh - 1) / 8))
        band = np.concatenate([rgb[y:y + 8, :16].reshape(-1, 3), rgb[y:y + 8, -16:].reshape(-1, 3)])
        stops.append(hexc(band.mean(0)))
    floor = hexc(rgb[-10:].reshape(-1, 3).mean(0))
    meta = {"frame_w": fw, "frame_h": fh, "frames": N, "cols": COLS, "rows": rows, "fps": FPS,
            "side_stops": stops, "floor": floor,
            "edge": hexc(edge.mean(0)), "corner": hexc(corner.mean(0)),
            "source": "art_src/loading/characters_run.mp4", "source_frames": [I0, I1 - 1], "morph": MORPH}
    with open(os.path.join(OUT, "run_loop.json"), "w") as fh_:
        json.dump(meta, fh_, indent=2)
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
