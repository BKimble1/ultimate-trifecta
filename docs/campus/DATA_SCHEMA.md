# Reference-campus layer data (schema v1)

The campus is data. Everything the game builds (meshes, colliders, water,
bot navigation, spawns, the minimap) comes from these files, so geometry,
collision and objectives can't drift apart. Real place names never appear
here or anywhere in the repository: items use neutral ids, the inventory's
neutral codes (`B28`, `W01`, …) and research reference ids (`R093`, `A03`).
The private crosswalk to real names lives outside the repository.

## Frame

Metres. `+x` = grid east, `+z` = grid south (north is `-Z`), `y` up, ground
`y = 0` except where an item says otherwise. The frame is a fixed offset of
NAD83 / UTM zone 16N (EPSG:26916): `x = E − 627300`, `z = 4479400 − N`
(`tools/campus/geo.py`). UTM grid north is the game's north (true north is
under 1° away and ignored). Terrain is treated as flat; local grade changes
(banks, steps, ramps, basins) are explicit items.

## Files

Sources: `tools/campus/traced/<zone>.json` (one file per tracing zone, all
layers). `tools/campus/build_data.py` validates and merges them into
`game/data/campus/<layer>.json`, which the game and every tool read.

Each merged file: `{"version": 1, "items": [...]}`.

## Fields every item may carry

| Field | Meaning |
|---|---|
| `id` | unique, stable, neutral snake_case (`west_hall`, `path_cc_014`) |
| `ref` | inventory code(s), e.g. `"B28"` or `"W01"`; omit for minor items |
| `label` | neutral player-facing label (only where the game shows a name) |
| `zone` | tracing zone (`north`, `ncore`, `ccore`, `south`, `west`, `context`) |
| `ev` | evidence: `{"src": ["aerial2022", "R093", "plan2023p4", "wayfinding2026", "A03"], "date": "2022" / "2025" / "2026", "conf": "high" / "medium" / "low", "note": "...", "open": "unresolved question"}` |

`conf`: **high** = traced from the measured 2022 aerial and unchanged since,
or measured in a dated photo; **medium** = georeferenced plan/diagram
(±5–10 m) or photo-estimated dimensions; **low** = inferred.

## Layers

### buildings
```
{"id", "ref", "label", "zone", "kind": "academic|residence|athletic|dining|worship|service|house|context",
 "status": "existing|construction",
 "footprint": [[x, z], ...],          ground outline, no repeated last point
 "h": 12.0,                           eave/parapet height above ground (m)
 "floors": 3,
 "roof": {"type": "flat|gable|hip|pyramid|dome|shed|complex", "pitch": 30, "ridge": "long|short|<deg>"},
 "parts": [{"footprint": [...], "h": 8.0, "base": 0.0, "roof": {...}}],   optional sub-masses
 "style": {"wall": "brick_red|brick_brown|brick_tan|stone_light|siding_white|siding_grey|glass|metal_light|metal_dark|concrete",
           "trim": "white|stone|dark|none", "roof_mat": "shingle_dark|shingle_grey|metal_grey|metal_dark|membrane|copper",
           "windows": "punched|ribbon|curtain|sparse|none", "notes": "..."},
 "entrances": [{"p": [x, z], "face": <deg, 0 = facing north (-Z), 90 = east>, "w": 3.0, "kind": "door|double|portico|canopy|garage"}],
 "passages": [{"polygon": [...], "floor": 0.0, "clear": 3.0, "note": "..."}],   genuinely open walk-throughs
 "landmark": null | "bell_tower" | "prayer_chapel" | ...,   custom builder key
 "background": false,                 true = outside the play boundary (cheap LOD, no interior)
 "ev": {...}}
```

### water
```
{"id", "ref", "label", "kind": "lake|pond|pool|fountain|channel",
 "polygon": [[x, z], ...] | "circle": [[x, z], r],
 "surface": -0.4, "floor": -2.0,     y of the water surface and basin floor
 "edge": "natural|stone|concrete|rim", "rim_h": 0.0,
 "features": [{"kind": "jet|statue_base|bridge|dock|beach|island", ...}],
 "objective": true|false,            in the round's water pool (see gameplay)
 "ev": {...}}
```

### roads (vehicle routes; centre lines)
`{"id", "kind": "street|campus|drive|service|lot_aisle", "pts": [[x, z], ...], "w": 7.0, "curb": true, "ev"}`

### paths (walks; centre lines)
`{"id", "pts": [[x, z], ...], "w": 3.0, "surface": "concrete|brick|asphalt|gravel|boardwalk", "ev"}`

### areas (surfaces and zones as polygons)
`{"id", "kind": "parking|plaza|field_turf|field_grass|track|court|infield|bed|construction|woods|farm|sand|gravel|yard", "polygon": [...], "ev"}`

### barriers
`{"id", "kind": "wall_low|wall_retaining|fence_iron|fence_chain|fence_construction|hedge|rail|bollards", "pts": [...], "h": 0.6, "ev"}`

### trees
`{"id", "pos": [x, z], "r": 5.0, "h": 12.0, "kind": "deciduous|conifer|ornamental|shrub", "obs": "observed|inferred", "ev"}`

### props
`{"id", "kind": "bench|lamp|bike_rack|bin|bollard|table|planter|pergola|pavilion|sign_blank|flagpole|light_pole|bleachers|goal|dugout", "p": [x, z], "rot": <deg>, "len": 2.0, "ev"}`

### gameplay
Play boundary, start dorms (spawn slots, doors), the water objective pool,
Night Watch and cart spawns, coin and gadget spots. Written by hand in
`tools/campus/traced/gameplay.json`; documented in `docs/campus/GAMEPLAY.md`.

### changes
The change register: features in the 2022 aerial that no longer exist and
later additions, each with evidence:
`{"id", "change": "removed|added|replaced|realigned", "what", "since", "ev"}`.
