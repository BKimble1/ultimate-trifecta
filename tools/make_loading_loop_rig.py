"""Packs the game-rig loading loop (V5) into the runtime assets.

    tools/make_loading_loop_rig.sh            (renders with Godot, then runs this)
    python3 tools/make_loading_loop_rig.py FRAMES_DIR

FRAMES_DIR holds f_000.png .. f_NNN.png from src/dev/loading_loop_render.tscn:
premultiplied RGBA (transparent background), frame N repeating frame 0.
Checks that the loop closes (f_N == f_0 and the f_{N-1} -> f_0 step is an
ordinary step), crops every frame to the union of their content (+ margin),
and writes:
  game/assets/loading/rig_loop_atlas.png   frames 0..N-1 in a grid
  game/assets/loading/rig_loop_still.png   frame 0 (shown at once)
  game/assets/loading/rig_loop.json        frames, fps, grid, frame size, checks
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = os.path.join(ROOT, 'game', 'assets', 'loading')
FPS = 60
MARGIN = 10


def main(src):
    names = sorted(f for f in os.listdir(src) if f.startswith('f_') and f.endswith('.png'))
    fr = [np.asarray(Image.open(os.path.join(src, n)).convert('RGBA')) for n in names]
    n = len(fr) - 1                      # the last frame repeats the first
    f32 = [f.astype(np.float32) for f in fr]
    step = [float(np.abs(f32[i] - f32[i + 1]).mean()) for i in range(n - 1)]
    closes = float(np.abs(f32[n] - f32[0]).mean())
    seam = float(np.abs(f32[n - 1] - f32[0]).mean())
    assert closes < 0.05, 'loop does not close: f_%d differs from f_0 by %.3f' % (n, closes)
    assert seam <= max(step) * 1.15, 'seam step %.3f is larger than ordinary steps (max %.3f)' % (seam, max(step))
    alpha = np.max(np.stack([f[..., 3] for f in fr[:n]]), axis=0)
    ys, xs = np.where(alpha > 2)
    h0, w0 = alpha.shape
    x0, x1 = max(0, xs.min() - MARGIN), min(w0, xs.max() + 1 + MARGIN)
    y0, y1 = max(0, ys.min() - MARGIN), min(h0, ys.max() + 1 + MARGIN)
    # sizes on a multiple of 4 (ASTC/BPTC blocks never straddle two frames)
    w = (x1 - x0 + 3) // 4 * 4
    h = (y1 - y0 + 3) // 4 * 4
    x1, y1 = min(w0, x0 + w), min(h0, y0 + h)
    x0, y0 = x1 - w, y1 - h
    cols = int(np.ceil(np.sqrt(n * h / w)))
    rows = int(np.ceil(n / cols))
    atlas = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    for i in range(n):
        crop = Image.fromarray(fr[i][y0:y1, x0:x1])
        atlas.paste(crop, ((i % cols) * w, (i // cols) * h))
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, 'rig_loop_atlas.png'), optimize=True)
    Image.fromarray(fr[0][y0:y1, x0:x1]).save(os.path.join(OUT, 'rig_loop_still.png'), optimize=True)
    meta = {"frames": int(n), "fps": FPS, "cols": int(cols), "rows": int(rows), "frame_w": int(w), "frame_h": int(h),
            "premultiplied": True, "loop_closes_mad": round(closes, 4), "seam_step_mad": round(seam, 3),
            "step_mad_min": round(min(step), 3), "step_mad_max": round(max(step), 3),
            "source": "src/dev/loading_loop_render.tscn (game rig: runner.glb, character shader, animation graph)"}
    with open(os.path.join(OUT, 'rig_loop.json'), 'w') as f:
        json.dump(meta, f, indent=2)
    print(json.dumps(meta))
    print('atlas', atlas.size, os.path.getsize(os.path.join(OUT, 'rig_loop_atlas.png')), 'bytes')


if __name__ == '__main__':
    main(sys.argv[1])
