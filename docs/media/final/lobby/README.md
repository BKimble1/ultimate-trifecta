# Final sweep · lobby lighting evidence

Notes, defect register, numbers and the full index:
[`docs/final/lobby.md`](../../../final/lobby.md).

Every picture and clip here is a **desktop render on llvmpipe** (Godot 4.7.2,
Mobile renderer, Xvfb, Mesa limited to AVX, see L1 in the notes), with
fictional player names. Before and after use the same camera and the same
poses. None of it is device footage, frame-rate or timing evidence.

- `p14_*`: iPhone 14 shape (2532×1170 @3x, as its 1558×720 canvas, safe area
  47/0/47/21 pt). `se_*`: iPhone SE (1334×750 @2x). `battery_*`: the Battery
  Saver preset at the iPhone 14 shape.
- `*_faces.jpg`: the characters cropped, before left, after right.
- `L1_llvmpipe_fp16_fault.jpg`: the desktop-renderer fault that under-lit
  characters in earlier desktop evidence.
- `match_unchanged.jpg`: a Practice round's campus dorm frames, base vs this
  pass.
- `loadin_before.mp4`, `loadin_after.mp4`: the app opening into Home, fixed
  30 fps Movie Maker clock encoded at 30 fps (real-time speed).
- `data/`: the measurements (`tools/lobby_light_measure.py --compare`).
