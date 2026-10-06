# Campus rebuild: what does not change

The rebuild replaces the place. The game played on it stays the 2.0 release candidate's
(`release/2.0-rc`, commit `b3e5d74`). `game/tests/test_campus_invariants.gd` pins these values.

## Files that stay untouched in this pass

| File | Defines |
|---|---|
| `game/src/sim/motor.gd` | the character capsule, floor rules, movement and cart integration |
| `game/src/config/rules_config.gd`, `game/config/rules_default.tres` | every rule value below |
| `game/src/sim/sim_player.gd`, `sim_cart.gd` | per-player and cart state |
| the shop, wardrobe, season pass, lobby music, purchase and account code | out of scope |

`git diff b3e5d74 -- game/src/sim/motor.gd game/src/config game/config/rules_default.tres` is empty.

`match_sim.gd` changes only where it read the old map's fixed layout. Its rules for splashes,
stamps, tags, captures, finishes and respawn are the same.

## Movement and body

| | Value |
|---|---|
| Runner speed (full input) | 6.0 m/s (fast threshold 0.85 of it) |
| Night Watch speed | 6.6 m/s |
| Ground acceleration / deceleration | 46 / 52 m/s² |
| Air acceleration | 14 m/s² |
| Jump | 6.4 m/s up (Night Watch 6.0), gravity 19 m/s², maximum fall 30 m/s |
| Coyote time / jump buffer | 0.12 s / 0.13 s |
| Dive | 8.0 m/s, 2.4 m/s up, 0.45 s landing |
| Turn rate | 900°/s |
| Capsule | radius 0.35 m, height 1.5 m |
| Floor | slope ≤ 50°, snap 0.35 m, safe margin 0.02 m, 5 slides |

There is no sprint and no stamina (removed in Pass 9, still absent). No swimming system, no
teleport shortcuts.

## Tag, round, carts, gadgets, coins

| | Value |
|---|---|
| Round | 240 s; 3 s countdown; 4 s role reveal; 6 s runner head start |
| Teams | up to 6 runners and 2 Night Watch; 3 targets per round |
| Tag | 0.14 s wind-up, 0.22 s lunge at 9 m/s, reach 1.6 m in a 75° half-angle, 1.5 m vertical; 0.9 s miss cooldown |
| Capture | 6 s penalty, 2 s respawn protection, 1 s bump protection |
| Splash | 1.5 s sequence, 3 s marker for the Night Watch |
| Carts | 2; 11 m/s on roads, 6.5 m/s off road, 6.8 m/s² acceleration |
| Gadgets | turbo ×1.25 capped at 8 m/s, decoy, splash bomb (unchanged) |
| Coins | 8 per round |
| Sight | 34 m view range |

## Network

| | Value |
|---|---|
| Simulation | 60 Hz, a snapshot every 3 ticks, host-authoritative |
| Protocol | version 9: position x/z now 24-bit (range ±131 km at 1/64 m), y unchanged 16-bit. The real campus is ~1.2 km across and overflowed the old ±512 m. Version 8 clients are refused. |
| Round start | carries the campus data hash (`CampusData.campus_hash`), the home dorm's geometry hash and version. A guest whose data differs refuses the round as incompatible (same colliders, waters, pads and doors on every machine). |

## What this pass may change (and does)

- Where things are: buildings, waters, paths, roads, spawns and pads, all from `game/data/campus`.
- Which waters are objectives. There are still six in the pool and three a round, mapped to six real
  waters in `gameplay.json`.
- Navigation grid resolution: 2 m cells, because the campus is larger. Bots and the pace fields read it.
  The players' movement does not.
- Views: the camera far plane and fog stay as they were. The minimap becomes a window centred on the
  player.
