# V5 campus evidence

Matched renders of Moonbrook College before (V4, commit `dcebf4e`) and after
(V5, branch `v5-campus`) the campus art pass. Both were rendered with the same
tool (`game/src/dev_shots.gd`) and identical cameras.

- **Platform:** desktop Linux. Godot 4.7.2's **Mobile renderer** on Mesa **llvmpipe** (software Vulkan) under Xvfb. This is not a phone and not GPU-accelerated.
- **Resolution:** 1558×720 (about an iPhone 14 Pro's landscape canvas), 2× MSAA.
- **Preset:** Standard (quality 1). The `*_battery.jpg` files are Battery Saver (quality 0, 3D at 80% scale).
- **Not performance evidence.** llvmpipe frame rates say nothing about a phone. The engine counters quoted in `docs/v5/campus_notes.md` (draw calls, primitives) are relative measurements only.
- **Objectives:** in the route and overview sets the fountain, pond and Lily Basin are marked active, as in V4's captures. In the water set all six are.

| Folder | Content |
|---|---|
| `before/` | V4 renders (JPEG, quality 80) |
| `after/` | V5 renders (JPEG, quality 80) |
| `compare/` | V4 left, V5 right, half size side by side |

| Set | Views | Flag |
|---|---|---|
| Route | `route_1_dorm_door` … `route_7_return`: the follow camera along dorm → quad path → Froggy Pond → woods → Lily Basin → fountain → home | `--route` |
| Waters | `water_1_fountain` … `water_6_inlet`: each water from a nearby path | `--waters` |
| Overview | `overview`, `quad_fountain`, `dorm_front`, `pool`, `pond`, `quarry`, `garden`, `inlet`, `shed`, `tower` | (none) |
| Landmarks | `hero_*`: follow-camera views at the landmarks and the barren lawns, with a stand-in runner (blue striped capsule, the character's size) to judge readability against the scenery | `--heroes --runner` |
| Battery Saver | `route_*_battery` | `--route --q0` |

Reproduce:

```
xvfb-run -a -s "-screen 0 1700x800x24" tools/gd.sh --path game --resolution 1558x720 res://src/dev_shots.tscn -- OUTDIR [--route|--waters|--heroes --runner] [--q0]
```

Each run prints a `BUILD` line (staged build timing) and a `STATS` line per
view (draw calls, primitives, objects).

## Engine counters for the other sets (llvmpipe, relative only)

| Set | View | V4 draws | V5 draws | V4 prims | V5 prims |
|---|---|---|---|---|---|
| overview | quad_fountain | 82 | 78 | 246,259 | 226,084 |
| overview | dorm_front | 56 | 51 | 159,975 | 129,552 |
| overview | overview | 65 | 66 | 111,577 | 148,496 |
| overview | pool | 55 | 56 | 151,851 | 153,691 |
| overview | pond | 50 | 45 | 223,502 | 129,666 |
| overview | quarry | 44 | 37 | 140,690 | 102,468 |
| overview | garden | 41 | 42 | 105,160 | 90,545 |
| overview | inlet | 40 | 38 | 124,786 | 92,963 |
| overview | shed | 36 | 31 | 99,145 | 77,698 |
| overview | tower | 74 | 68 | 194,191 | 173,024 |
| heroes | hero_pond_exit | 63 | 58 | 241,006 | 149,596 |
| heroes | hero_pond_trail | 60 | 56 | 229,578 | 137,660 |
| heroes | hero_fountain | 82 | 73 | 217,930 | 191,148 |
| heroes | hero_pool_gate | 66 | 56 | 190,532 | 124,626 |
| heroes | hero_quarry | 50 | 48 | 139,829 | 99,839 |
| heroes | hero_garden | 56 | 53 | 133,272 | 104,445 |
| heroes | hero_inlet | 46 | 38 | 131,309 | 90,431 |
| heroes | hero_dorm_west | 84 | 80 | 247,659 | 184,740 |
| heroes | hero_north_lawn | 69 | 60 | 169,388 | 134,018 |
| heroes | hero_east_lawn | 80 | 76 | 213,429 | 178,745 |
| waters_q0 | water_1_fountain | 45 | 48 | 100,549 | 105,731 |
| waters_q0 | water_2_pond | 20 | 32 | 75,688 | 42,210 |
| waters_q0 | water_3_pool | 26 | 27 | 48,150 | 52,826 |
| waters_q0 | water_4_quarry | 19 | 23 | 41,343 | 31,032 |
| waters_q0 | water_5_garden | 20 | 25 | 37,453 | 31,372 |
| waters_q0 | water_6_inlet | 16 | 20 | 36,168 | 34,829 |
