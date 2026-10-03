# Character asset pipeline

`game/assets/characters/runner.glb` is **generated**: it is not hand-edited. The Python files in this folder are the editable source.

```sh
python3.11 -m venv tools/.cache/bpyenv
tools/.cache/bpyenv/bin/pip install bpy==4.5.4     # Blender as a Python module, GPL, build-time only
tools/character/build.sh                            # writes runner.glb + runner_manifest.json (about 10 s)
BPY_PYTHON=/other/venv/bin/python tools/character/build.sh [out.glb]   # another venv / output path
tools/.cache/bpyenv/bin/python tools/character/clip_check.py          # clip checks (below); exit 0 = no arm in the head
tools/gd.sh --headless --path game --import                          # re-import after a rebuild
```

The build takes about 40 s on a shared desktop (V5: ~10 s; V6 has 45 parts and 46 clips).

| File | What it holds |
|---|---|
| `geo.py` | Parametric mesh kit: ellipsoids, sweeps, lathes, slabs. Also the vertex-data contract (colour, tint selector, stripe UVs, material class). |
| `rig.py` | Proportions, bone table, skin-weight functions. |
| `parts.py` | Each mesh: base (head, face with lash lines, hands), hair and its hat variants (`hair_hat`, `hair_curly_hat`, `hair_curly_low`), body skin, the V2-V5 outfits, Night Watch uniform with flashlight and mustache, the V2-V5 hats and shoes. `sleeves(..., lod=1)` is the lighter sleeve the V6 outfits use. |
| `outfits_v6.py` | V6: the six Shop outfits and their headwear (`acc_sleepmask`, `acc_courier_cap`), and the Season 1 · After Hours outfits, hats and shoes. One function per part; names match `Cosmetics.OUTFIT_PARTS` / `OUTFIT_HEADWEAR` / item `parts`. |
| `kit6.py` | V6 helpers: decals projected onto the garment (stars, badges, letters, crescents), strips, tubes along surfaces, ribbons lying on the head (straps, bands, cuffs), open shells (vests, cardigans), leg tubes clipped by height, skin limbs, knit ribs, knobbly pompoms. |
| `anims.py` | 46 clips authored as code: FK deltas in armature axes, plus analytic two-bone leg IK for locomotion. `blend_pose` interpolates IK targets (V5). V6: leg IK takes an optional foot yaw, a `_frame` yaw turns every delta with the root (the victory lap), and arm IK takes a target in another bone's rest space (the shush). |
| `plot_foot_trail.py` | V6: top-down plot of planted-foot trails from `src/dev/foot_trail.tscn` (Pillow only). |
| `clip_check.py` | V5: evaluates every clip on the real rig at 60 Hz: sleeves/mittens inside the head shell, mittens inside the torso, IK leg reach (> 0.44 m clamps), the largest in-clip joint jump. |
| `build_character.py` | Builds the armature, meshes, vertex groups and face shape keys. It also bakes the actions and exports the GLB. |

## Conventions

- **Forward.** The character faces Godot −Z at yaw 0, which is the sim's and the camera's forward. In Blender it is built facing +Y. Menu scenes call `CharacterView.face_toward(camera)`.
- **One asset everywhere.** Every role and cosmetic is the same skeleton with mesh parts toggled. `CharacterView` maps the existing cosmetic IDs and the 5-byte network encoding onto parts, so nothing changes in saves or on the wire.
- **Colour path (measured, not assumed).**
  - Blender stores byte colours as sRGB, and the glTF exporter writes `COLOR_0` as linear: sRGB 0.5 becomes 0.216.
  - Godot keeps those linear values, quantised to 8 bits.
  - So `character.gdshader` uses `COLOR.rgb` directly, with no `srgb_to_linear`.
  - glTF flips V, so the shader reads `1 - UV.y` and `1 - UV2.y`.
  - World meshes built in code (`MeshKit`) store sRGB vertex colours and convert in `world_common`.
- **Locomotion clips.**
  - `walk`, `run` and `sprint` are each one 1.0 s cycle that starts with the left foot at mid-stance.
  - `LOCO[*].speed` is the metres travelled per cycle. `CharacterView` plays the blend at `ground speed / speed`, so planted feet move at ground speed and do not slide.
  - Planted-foot sweep is `speed × duty`. It must stay reachable for the 0.44 m legs; otherwise the IK clamps and the foot slides. The current values are chosen for that.
- **Face.**
  - Shape keys on `base`: `blink`, `squint`, `smile`, `open`, `brow_up`, `brow_angry`.
  - The neutral mouth (a closed smile) is baked into the basis.
- **Budgets.**
  - A typical outfit (base + pajamas + nightcap + slippers) is about 24.1k triangles at LOD0 (V5: 23.4k; V3: 19.7k). Godot generates LODs on import. All 45 parts together: 211k triangles (only the worn ones are drawn).
  - V6 outfits: 5.9k-11.1k triangles each; the heaviest look that can be worn with any V6 item stays under the heaviest V5 look (`test_outfits_v6`). Measure a part with `build.sh` (it prints every part's count) and see `docs/v6/character_notes.md`.
  - Each visible part is one draw call with one shared `ShaderMaterial`; per-character colours are instance uniforms. Parts listed in `CharacterView.TWO_SIDED` (the nightcap) use a second, double-sided material with the same shader body (`character.gdshaderinc`).
- **Checking changes.** `src/dev/character_lineup.tscn -- --lineup=parts` renders 12 fixed close-ups (nightcap, collar, cuff and hand, robe hem, each shoe, hair edges, Night Watch cap); `--parts-debug` hides the head to inspect the cap alone. Render it before and after a change and compare.
  - Distant characters advance their AnimationTree at a third of the rate (V5: beyond 48 m, back to full rate inside 42 m).
- **Overhead arms (V5).** The head is 0.31 m wide over shoulders 0.17 m from the centre, so an arm raised much past ~85° from the A-pose goes into the head. Open raises into a V with bent elbows and run `clip_check.py`.
- **Hats and curly hair (V5).** `hair_curly_hat` is the curly crop with a smooth band from z 1.34 m; `CharacterView` shows it instead of `hair_curly` under the crown and headphones. `--lineup=hathair` renders every hat that leaves hair visible × every hair style.
- **Motion checks (V5).** `src/dev/motion_probe.tscn` and `tests/test_motion_v5.gd` measure pose continuity, foot slide and cap motion through gameplay-like scenarios; see `docs/v5/motion_notes.md`. V6: `-- --outfit=<key>` runs them on an outfit; `--bench` also times the foot lock.

## V6: adding an outfit, hat or shoe

1. Write `build_<name>()` in `outfits_v6.py` returning one `MeshBuilder` (one part, one draw call) and add it to `SHOP_PARTS` / `SEASON_PARTS`. Skin with `torso_w`, `skirt_w`, `arm_w`, `leg_w` or a rigid bone; keep LOD0 under ~11k triangles for an outfit (`build.sh` prints the counts).
2. Add the catalog entry in `game/src/view/cosmetics.gd` with a new, never-reused `id`, a display name, `includes` (outfits: exactly what is drawn) and its parts (`OUTFIT_PARTS` for outfits). Outfit headwear goes in `OUTFIT_HEADWEAR` (and the hats it is worn with); outfit footwear in `OUTFIT_OWN_SHOES`; hair rules for a hat in `HAT_HIDES_HAIR` / `HAT_HAIR_VARIANT`.
3. Rebuild, re-import, then check: `tools/run_tests.sh outfits_v6` and `profile`; `src/dev/character_lineup.tscn -- --lineup=shop,season,outfitsheet,newhats,newshoes,hatgrid` (add the key to `V6_OUTFITS` / `SHOWCASE` there), `--light=campus|dorm|studio`; `src/dev/thumb_sheet.tscn` renders the real cached thumbnails through `Portraits`.
4. A new emote: append its name to `TC.EMOTES` (the wire value is the index), add a label, an icon (`Icons`), a lobby time (`DormStage.EMOTE_S`), a `CharacterView.STATES` entry and an expression, a clip in `anims.library()` (`emote_<name>`, looped), then `clip_check.py` must exit 0.
