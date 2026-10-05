# Pass 8 — Idlery Games logo edges through the startup path (§11)

Branch `p8-logo`. Scope: the native launch screen, Godot's boot splash, the
`BootCurtain` and its fade into Home. All measurements are on desktop
renders (Godot 4.7.2, Mobile renderer, llvmpipe under Xvfb) at the phones'
and an iPad's pixel sizes, plus emulations that were checked against the
real Godot output. No iPhone was used: the native launch screen is evaluated
as the generated PNG at device scale (see *Open items*).

## Summary

- **Main defect: the curtain, not the source art.** V8's curtain drew the
  lockup softer than the launch image and boot splash and **0.5–1.2 px away
  from them** (2532×1170: +0.34, +0.90 px). The handoff boot splash → curtain
  therefore *moved and softened* the logo. Measured causes: Godot rounds every
  Control's position to whole **canvas units** (1 unit = 1.625 device px on a
  1170-px-high phone, 2.13 on a 12.9-inch iPad); the 1400×805 texture was
  sampled ~0.95 of a mip level down (trilinear, mostly the half-size mip); and
  805 rows halve to 402, so the mips sat up to half a texel lower.
- **Second defect: ringing halos** from V5's Lanczos resize in both the
  launch image (light glow up to 29 levels outside the contour, dark dip up to
  41 levels inside, a tinted edge colour 26 levels off) and the runtime PNG
  (alpha up to 0.10 where the shape is empty, down to 0.87 inside). Visible at
  1:1 (the 12.9-inch iPad shows the launch image unscaled).
- **Third: stair steps on 2x iPhones.** The 2048² launch image is minified by
  one bilinear tap (Godot's boot splash: linear sampler, `max_lod 0`; Core
  Animation's default `kCAFilterLinear`) at 2.73:1 on the iPhone SE and 2.47:1
  on the iPhone XR/11, where the tap skips texels.
- **Not a defect:** the owner's raster master. `idlery-games.png` is a faithful
  1.5× raster of `idlery-games.svg` (alpha mean difference 0.00007, the
  colour × alpha within 1 level everywhere); there are no source jaggies and
  no bounding rectangle or matte in any stage (every background pixel is
  exactly 0 in every capture). The black is identical in all stages.
- **Fix:** everything is rasterised **from the vector** with exact area
  coverage, at the size it is shown: the launch image (1656², also Godot's
  boot splash) offline, and the curtain's lockup at run time at the exact
  device-pixel size and sub-pixel position, drawn 1:1 by a control that is not
  snapped, premultiplied with the premultiplied blend. Result at 2532×1170:
  curtain edge RMS vs the vector **31.8 → 2.4 levels**, position error
  **0.96 → 0.07 px**, boot splash → curtain change **RMS 8.3 → 1.5**, no halo
  or fringe anywhere; the audit and tests now check edges, not only black
  corners.

## Defect register

| # | Owner symptom | Reproduction | Measured cause | Implementation | Evidence |
|---|---|---|---|---|---|
| L1 | Logo edges not clean at startup | Real start at 2532×1170: X screenshots of Godot's boot splash, then the curtain's first frame (lab render = V8's real curtain, max difference 0) | Curtain lockup displaced +0.34/+0.90 px vs the launch image (centroid), handoff difference RMS 8.3, max 186 levels. Probe: a quad meant for device x 903 (canvas 555.64) lit from 904, y 376 lit from 375 — `Control::_update_canvas_item_transform` floors `origin + 0.5` in canvas units | `BrandMark` (full-screen control at the origin, nothing to round) draws the picture at an unsnapped fractional rect; the rect is laid out in window pixels exactly as the launch image lays it out (the canvas is whole units, 1558×720, so canvas→window is 1.62516 × 1.625, not uniform) | `handoff_diff_2532x1170.png`, `profile_2532x1170.png`, `metrics.json` `handoff_*`, variants `v8_png_linear` (snapped, no mips: still +0.39/+0.62) |
| L2 | Same | Same | Curtain softer than the splash: 1400-px texture drawn 725 px wide with linear-with-mipmaps → ~lod 0.95; Godot's box mips. V8 curtain edge RMS 31.8 vs the vector | Lockup rasterised at run time from `idlery_games.svg` (ThorVG, `Image.load_svg_from_string`) at exactly the drawn size and sub-pixel phase, drawn 1:1 with a plain linear filter: no mip choice exists | `stages_*.png`, `edges_400pct_*.png`; curtain edge RMS 2.4 at every device |
| L3 | Same (halo) | `tools/launch_audit.py` on V8's launch image; 1:1 iPad emulation | V5's premultiplied **Lanczos** resize rings: 2152 detached glow px + 3009 inner dip px, colour 26 levels off a black/fill blend; runtime PNG alpha 0.10 outside / 0.87 inside | `tools/branding/svg_raster.py`: exact signed-area coverage of the flattened vector (non-zero rule, Wang's bound 1/50 px), validated against 64×64 supersampling (max 1.3 levels, RMS 0.16); no resampling filter at all | audit output below; iPad `launch` halo 5161 → 0 px, purity 26 → 1 |
| L4 | Same (2x phones) | Bilinear emulation, validated: real boot splash X capture vs emulation ≤ 1 level (V8 and Pass 8) | 2048 → 750/828 px is a 2.73/2.47 single-tap minification: alias max 21 (SE) | Launch square 1656 (see the size table): 1.0–2.21:1 on every iPhone, exact 2:1 on 828-px-high iPhones | `metrics.md` SE launch alias 21 → 18; 828: exact |
| L5 | (risk) halo during the curtain's exit settle | Frame-by-frame real boot at a fixed 60 fps clock | A straight-alpha raster scaled 1.03× bilinearly pulls the transparent pixels' black into the contour; `fix_alpha_edges()` cured it but cost 39–203 ms on desktop | Raster premultiplied (`Image.premultiply_alpha`), drawn with `CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA`; the fade scales all four channels (`BrandMark.fade`) because the canvas shader multiplies texture × draw colour and an alpha-only fade would glow under that blend | `fade_frames_2532x1170.png`; settle frames vs the vector at the settled scale and fade: mean 0.29–0.37 levels, colour purity ≤ 2.3 (`settle_frames`) |
| L6 | (fallback only) | Variant `v8_png_unsnapped` | Odd-height mip chain: +0.27 px vertical misregistration | Fallback PNG 1280×736 (both sides divide by 32); `fallback` variant shift −0.01 px | `metrics.json` variants |

## Decisions and the measurements behind them

**Vector vs raster master.** Rasterised the SVG at 1.5× with the exact
rasteriser and compared with the owner's 2400×1380 PNG: alpha mean |Δ| 0.00007,
contour RMS 5.8 levels (two antialiasing implementations), colour × alpha
within 1 level. The vector is the approved mark and the raster faithfully
represents it; the vector is used because it can be rendered exactly at any
size, and resizing any raster needs a filter (Lanczos rang, box/bilinear blur).

**Runtime curtain: what was compared at the displayed size (2532×1170,
edge RMS vs the vector / alias max / centroid shift px):**

| Variant | edge RMS | alias max | shift |
|---|---|---|---|
| V8: 1400 PNG, TextureRect, linear-with-mipmaps | 31.8 | 66 | +0.34, +0.90 |
| V8 PNG, TextureRect, linear (no mips) | 27.8 | 52 | +0.39, +0.62 |
| V8 PNG, unsnapped (BrandMark), mipmaps | 14.6 | 39 | −0.01, +0.27 |
| Pass 8 fallback: exact 1280×736 PNG, unsnapped, mipmaps | 9.0 | 15 | −0.01, −0.01 |
| **Pass 8: exact runtime raster, 1:1, linear** | **2.4** | **8** | **+0.06, +0.03** |

Removing mipmaps alone made it worse in places (aliasing at 1.93:1), so the
choice was measured, not assumed: the decisive fixes are no snapping and no
resampling. ThorVG's coverage differs from exact coverage by ~9 levels RMS on
contour pixels (its own approximation), far below any resampling option.
Cost: 2–2.6 ms per phone size, 4.6–5.4 ms for a 13-inch iPad on this desktop
(device unmeasured); texture 1.16 MB at 2532×1170 (3.55 MB on a 12.9-inch
iPad) instead of V8's 1400×805 + mips (~6 MB). The PNG fallback is not loaded
unless the vector can't be rasterised (it is shipped with `importer="keep"`,
read with `FileAccess`; checked in a local iOS export's `.pck`).

**Launch image size (native launch screen and Godot boot splash: one
bilinear tap, square fitted to the screen height).** Exploration metrics
(scratch: edge RMS with a ±1 px band / alias max), exact vector rasters:

| Screen height px | 750 SE | 828 XR | 1170 | 1284 | 1320 | 1668 iPad 11" | 2048 iPad 12.9" |
|---|---|---|---|---|---|---|---|
| V8 2048 Lanczos | 10.8/21 | 9.3/16 | 4.9/12 | 5.5/14 | 5.1/13 | 8.2/13 | 6.3/8 + halo |
| exact 2048 | 11.2/26 | 9.9/23 | 5.9/15 | 6.0/12 | 5.3/13 | 8.3/11 | 0.2/0 |
| **exact 1656** | **7.7/18** | **0.2/1** | **6.5/11** | **7.3/11** | **8.0/10** | **11.7/12** | **19.3/19** (soft) |
| exact 1320 | 5.4/17 | 5.8/16 | 10.3/10 | 11.5/16 | 0.2/0 | 18.1/21 | 24.9/25 |

1656 keeps every iPhone between 1.25 and 2.21:1 (never upscaled, never past
the point where the tap skips texels), is exact on 828-px-high iPhones and
~1:1 on 11-inch/Air/10th-gen iPads, and decodes faster at boot (1656² RGB
8.2 MB vs 12.6 MB). Trade-off: the 12.9/13-inch iPad's launch screen and boot
splash are 1.24× upscaled — soft, never stepped or haloed — until the exact
curtain replaces them. The boot splash takes one image for every device, so
per-idiom asset-catalog images for the native screen alone were rejected:
they would make native and boot splash differ on the very devices they help.

**Black, matte, size, position.** Pure black in all stages (unchanged). No
stage has any non-zero pixel more than 4 px from the ink. The lockup is
0.62 × screen height wide in all stages; the curtain now places it within
0.07 px of the launch image's geometry (the bilinear boot splash itself sits
within 0.15 px of it).

**Premultiplied alpha** is used only for the runtime raster, paired with the
premultiplied blend and an all-channel fade (above). The fallback PNG stays
straight alpha with the importer's alpha-border fix (it is also bled to the
fill colour by the generator).

## What changed

- `tools/branding/svg_raster.py` (new): exact-coverage rasteriser for the
  branding SVG subset (paths M/L/H/V/C/S/Q/T/Z, nested translate/scale/matrix),
  premultiplied compositing, straight-RGBA export with colour bleed.
- `tools/branding/make_branding.py`: launch image 1656² from the vector;
  `assets/branding/idlery_games.svg` (copy of the master, `importer="keep"`);
  fallback PNG 1280×736 from the vector; writes only files whose pixels change
  (the title PNG is unchanged and not rewritten).
- `game/src/ui/brand.gd`: `studio_svg`, `svg_size`, `studio_raster` (ThorVG at
  an exact rect and sub-pixel phase, premultiplied), `place_studio` (window-
  pixel layout, fallback); `studio()` now returns a `BrandMark`.
- `game/src/ui/brand_mark.gd` (new, `BrandMark`): unsnapped picture rect,
  `settle` scale in the draw call, `fade`, premultiplied material.
- `game/src/ui/boot_curtain.gd`: places the lockup via `Brand.place_studio`
  (re-rasterises only when the window size/scale changes); exit animates
  `fade`/`settle` (Reduced Motion: fade only). Readiness, 0.45 s minimum,
  6 s cap, input blocking: unchanged.
- `tools/launch_audit.py`: per launch image (and Godot's boot splash image,
  from `game/project.godot`, found automatically from the repo root as CI
  runs it): square, ink box where `Brand.LOCKUP_W` puts it (±0.004 of the
  side), aliased crossings ≤ 15 %, no detached glow / inner dip pixels, colour
  purity ≤ 4 levels, and the exported splash images identical to the boot
  splash image. Standard library only; ~15 s.
- `game/tests/test_boot_branding.gd`: launch image size against iPhone
  heights; edge test (purity, no detached glow/dip, antialiased crossings);
  curtain lands on whole device pixels 1:1 at 2532×1170 with the exact,
  premultiplied raster whose ink centroid/area match the vector; fallback and
  vector source checks; fade/settle; Reduced Motion exit.
- Evidence tools: `game/src/dev/logo_capture.gd` (+ a 6-line `logo_*` hook in
  `game/src/dev/capture.gd`), `tools/branding/capture_logo_evidence.sh`,
  `tools/branding/logo_evidence.py`. `tools/make_launch_art.sh` header updated.

## How it was verified

- `test_boot_branding`: 8 tests, 77 checks, 0 failures. The new launch-edge
  and size checks fail on V8's launch image (worst colour 15 levels, 173
  detached/dip pixels on the sampled rows, ratios 2.73/2.47). Also run:
  `test_compile` (146 checks), `test_menus_layout` (4711 checks), all pass.
- `tools/launch_audit.py` on a local Godot 4.7.2 iOS export of this branch:
  **PASS** (splash@2x/@3x 1656², ink box exact, 6.8 % hard crossings, 0 glow,
  0 dip, purity 0.6; boot splash image identical). The same audit **FAILS**
  V8's images (2152 glow, 3009 dip, purity 26), a nearest-neighbour render
  (57 % aliased) and a straight-alpha resize of the owner PNG (purity 27).
- Captures: `tools/branding/capture_logo_evidence.sh` (four devices, ~10 min).
  The real boot splash (X screenshots) equals the emulation within 1 level
  (V8 and Pass 8); the first frame of the real boot equals the lab curtain
  render (max difference 0); the curtain is the exact raster on the first
  frame (`exact: true`), leaves at frame 27 (0.45 s, "ready"), is gone at
  frame 52.

## Evidence index (`docs/media/pass8/logo/`, all lossless PNG)

- `stages_<device>.png`: launch screen / boot splash and curtain first frame,
  V8 vs Pass 8, at the device's pixel size, metrics in the captions.
  `stages/<device>_<stage>_<before|after>.png` and `<device>_ideal.png`: the
  raw crops; `stages/2532x1170_boot_real_xshot_{before,after}_full.png`: the
  real boot splash, full window; `stages/2532x1170_startup_{curtain,home}_full.png`.
- `edges_400pct_<device>.png`: i/d, e and GAMES enlarged 400 % (nearest),
  launch/boot and curtain V8 vs Pass 8 vs the vector.
- `handoff_diff_2532x1170.png`: |curtain − boot splash| ×4, V8 vs Pass 8.
- `profile_2532x1170.png`: one edge's profile: vector, V8 boot splash, V8
  curtain (shifted, widened), Pass 8 curtain (on the vector).
- `fade_frames_2532x1170.png`: frames 0–52 of the real boot (fixed 60 fps clock).
- `compression_vs_rendering_2532x1170.png`: the same Pass 8 frame as lossless
  PNG and as JPEG q85/q60: JPEG alone adds edge RMS 8–12 and thousands of
  halo pixels — any phone screenshot/recording judged for edges must be
  lossless.
- `metrics.json`, `metrics.md`: all numbers above.

Devices: 2532×1170 (iPhone 12–14, 16e), 2778×1284 (12/13 Pro Max, 14 Plus),
1334×750 (SE 2nd/3rd gen), 2732×2048 (iPad Pro 12.9-inch).

## Open items / dependencies

- **On a device (owner/tester):** confirm on an iPhone that the launch screen
  → boot splash → curtain shows no visible change, and compare an iPhone SE/XR
  if one is available. The native stage was evaluated as the PNG under a
  linear filter (Apple documents `kCAFilterLinear` as the CALayer default;
  the system's launch snapshot pipeline is not observable here). Use lossless
  screenshots (PNG), not screen recordings.
- iPad 12.9/13-inch: launch/boot splash slightly soft (1.24× upscale) before
  the curtain; `LAUNCH = 2048` in `make_branding.py` would make it exact there
  at the cost of stair steps on 2x iPhones (data above).
- ThorVG is part of Godot's official iOS templates (SVG module on by default);
  if a custom template ever drops it, the curtain falls back to the mipmapped
  PNG (tested), softer but in the right place.
- Runtime raster cost was measured on desktop only (2–5 ms).

## Integrator notes

- Files outside LOGO ownership: `game/src/dev/capture.gd` (6-line additive
  `logo_*` delegation and its doc line), `tools/make_launch_art.sh` (header
  comment). `.github/workflows/ios.yml` is unchanged: the audit picks up
  `game/project.godot` by itself when run from the repository root.
- ASSET_LICENSES.md (integrator copies): Idlery Games startup lockup row —
  "the runtime lockup is rasterised at run time from
  `game/assets/branding/idlery_games.svg` (an unchanged copy of the owner's
  `idlery-games.svg`); the 1280×736 fallback PNG and the launch image are
  rasterised from the same vector by `tools/branding/make_branding.py`
  (`tools/branding/svg_raster.py`)", files column add
  `game/assets/branding/idlery_games.svg`. Launch image row — "The Idlery Games
  lockup centred on the startup black #000000, 1656², rasterised from the
  owner's vector by `tools/branding/make_branding.py`."
- TESTFLIGHT_RELEASE / What to Test: the next audit lines will read 1656²
  launch images with edge results; suggested tester note: "Startup: the Idlery
  Games logo should stay perfectly still and crisp from the launch screen
  until it fades into the room."
- After merging, run `tools/gd.sh --headless --path game --import` (new
  `class_name BrandMark`, new keep-imported SVG).
