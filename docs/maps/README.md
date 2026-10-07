# Two maps

The game ships two playable maps. A party's host picks one for the series; Practice remembers its own
choice. The rules, the motor, the round and everything else are shared.

| Stable id | Title (player-facing) | Tag | What it is |
|---|---|---|---|
| `classic` | Moonbrook College | Classic | The original fictional campus of the 2.0 (10) release, restored: `Rect2(-160,-150,320,300)`, the six waters, three halls, flat ground |
| `reference_campus` | Lakeside Campus | New | The campus rebuilt from the reference campus at real scale, on its measured ground (`docs/campus/`). The default |

The ids are what the network, the settings and the saves carry. Titles can change; ids never do.
Players never see the ids, data hashes or any evidence status.

## The registry (`game/src/map/campus_maps.gd`)

`CampusMaps` holds each map's definition:

- data directory, bounds, the bots' grid cell, minimap span;
- look (`classic` or `campus`), route table, route band;
- title, tag, one-line blurb and preview image.

It hands out one `CampusData` and one `CampusLayout` per map (`data(id)`, `layout(id)`), keyed by
the stable id. `revision(id)` is what a round is checked against: the map id, its data hash
(`CampusData.campus_hash`, which covers every layer and the terrain) and the hall geometry version.
`drop(keep)` releases every map but one.

Everything that used to assume one map takes its map from the layout it is given:

- **Layout and data:** `layout.bounds`, `layout.map_id` and `layout.nav_cell` replace the old
  `CampusLayout.BOUNDS`.
- **Halls:** start halls come from each map's gameplay layer. Hall ids are unique across maps
  (`CampusMaps.map_of_dorm`), so a classic hall id can never resolve to a new-campus hall.
- **Shared caches:** the height grid, ground tiles, collision recipe, nav grid and pace fields are
  keyed by the layout object. A round on the other map builds its own, and `drop_caches` releases
  the old ones.
- **Routes:** `RulesLogic.route_table(map)` reads the map's own table
  (`config/route_table.json`, `config/route_table_classic.json`).
- **Match:** `MatchSim` gets the round's layout; `MatchController` builds that map's look (the
  restored `ClassicBuilder` or `CampusBuilder`) and drops a cached campus of the other map. The
  minimap follows the round's layout (`CampusMap.use`).

## Moonbrook College, restored

The restoration source is the 2.0 (10) commit `66e7575`. Nothing was rolled back except that map's
own art and geometry.

- **Gameplay** runs through the same pipeline as the new campus (CampusLayout, CampusBuilder
  collision, NavGrid, CampusDorms, the rules). Its layers (`game/data/maps/classic/*.json`) are
  exported by `game/tools/classic_export.gd` from 2.0's own layout code, restored as
  `ClassicLayout`.
- **Look:** the restored 2.0 art classes draw it (`game/src/map/classic/`: `ClassicBuilder` visuals,
  `ClassicArchitecture`, `ClassicLandmarks`, `ClassicDormArt`, `ClassicKit`, and the baked
  `ClassicDressing`).
- **Proof** (`test_maps.gd`):
  - the export is current;
  - its six waters and three halls are 2.0's;
  - its colliders match the ones 2.0 built: 116,160 vertical rays across the map, over 99.7% within
    6 cm;
  - `route_analysis.gd --map=classic` gives each hall exactly 2.0's curated target sets.

## Selection

- **Practice:** a Map row on the Practice sheet opens the chooser. The choice is saved locally
  (`practice_map`); an explicit choice beats any default. Older saves start on the default (the new
  campus).
- **Party:** a Map row heads the host's party settings. The map is part of the settings: changing it
  bumps the settings revision and clears everyone's ready state. It is locked once the series starts
  and kept for a rematch until the host changes it between series. The host's last choice is saved
  (`party_map`).
- **Guests** see the host's map in the lobby chip and a read-only sheet ("The host picks the map").
- **The chooser** (`MapSheet`) is a focused sheet with one large card per map:
  - each card has its preview (uncropped 16:9), title, a small Classic/New tag and one line;
  - the selected card is marked by a teal border, a check and the word "Selected", never by colour
    alone;
  - side by side where both fit at a readable width (at least 420 pt each), otherwise stacked in a
    scroll; never two tiny cards;
  - controller: the D-pad moves between cards, A picks, B closes, and the opener gets focus back;
  - every card has an accessibility name.
- **Previews** are captured offline from the finished maps in the game's own look:
  `tools/capture_map_previews.sh` (an oblique aerial per map, a soft fill light), then stored as
  960 × 540 PNGs in `game/assets/maps/`. The UI shows only these static images, never a live campus.
  Re-run the script after any change a preview would show.

## Network (protocol 10)

- **Lobby:** the lobby bytes carry the map id, so guests see it.
- **START:** carries `map: {id, data, dorms}`. A guest refuses a START whose map it doesn't have or
  whose data hash or hall version differs. The session ends with "That party is playing a map this
  version of the game doesn't have yet. Update the game to play it." It never falls back to its own
  default map.
- **Checks:** the round's hall must be a hall of that map; spawns, coins and pads are bounded by that
  map.
- **Reconnect:** a guest who rejoins mid-round gets the same START, map included (`test_maps`).

## Start halls and routes per map

| Map | Halls | Race-start halls |
|---|---|---|
| Moonbrook College | Puddlesworth Hall (default), Lanternfield House, Moonpenny Lodge | all three; 15–16 target sets each, as 2.0 |
| Lakeside Campus | West Hall (default), North Hall | West Hall only: North Hall has no target set that fits the 240 s round (`docs/campus/README.md`) |

The hall is chosen from the round's seed among the race-start halls, never the same twice running
where there is another. Nobody picks it by hand.
