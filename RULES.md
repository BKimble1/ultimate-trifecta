# Trifecta Chase: implemented V1 rules

All values come from one resource, `game/config/rules_default.tres` (`RulesConfig`, `game/src/config/rules_config.gd`). The simulation, bots, HUD text, tutorial and tests all read it. The numbers below are the shipped defaults. The authority is `MatchSim` (`game/src/sim/match_sim.gd`), which runs on the room host, or locally in practice.

**Runner card:** "Splash into all three marked spots. Get back to the dorm. Get four runners home before time runs out."

**Night Watch card:** "Find the runners. Use your cart to cut them off. Hop out and tag them before they get home."

## Round

| Rule | Implemented behavior |
|---|---|
| Roster | 8 slots: 6 runners, 2 Night Watch. Bots fill empty slots. They are named `Bot …` (for example "Bot Snooze") and tagged [BOT] in the lobby, scoreboard and results. |
| Roles | Assigned and shown before play. A 4 s role-reveal card comes first, then a 3 s shared countdown. |
| Role fairness | Patrol seats go in tier order: players who asked for patrol, then "any", then bots, then players who asked to run. Within a tier, those with the fewest previous patrol rounds go first, then those who were not patrol last round, then a seeded tiebreak. Nobody is forced into patrol repeatedly while others are willing. |
| Clock | 240 s round clock starts after the countdown. Server ticks (60 Hz) drive the countdown, penalties and deadline. |
| Head start | Runners leave the dorm immediately. The Night Watch waits 6 s at the Grounds Shed (cart shed) inside the round clock. The tutorial round extends this to 30 s. |
| Targets | 3 distinct waters out of 6, the same for every runner. The pick comes from the match seed, drawn from a curated fair set (below) and avoiding an immediate repeat of the previous round. Targets never move or reroll. |
| Order | Any order, chosen by each runner. |
| Stamp | Entering an active target's water volume (jump, dive or walk in) awards that target's stamp once. Each runner can earn each target's stamp only once. |
| Finish | With all 3 stamps, cross the finish zone of any of the 4 dorm doors (Front, West, East, Back). |
| Runner win | The round ends the tick the 4th distinct runner finishes. A finish on or before the deadline tick counts. |
| Night Watch win | The clock expires with fewer than 4 runners home. |
| Survival | Not being caught never counts toward winning; only finishes do. |

### Same-tick ordering

The fixed per-tick order is: timers → intents → movement → **finish** → **water/stamps** → **tags** → cart bumps → gadgets → out-of-bounds recovery → perception → win/timeout.

- A runner who reaches a finish zone on the same tick as a valid tag is home; the finish takes precedence.
- Results are built once by the host. Clients never declare their own stamps, finishes or captures, so late or duplicated packets cannot change an outcome.

## Water

- **Splash sequence.** Entering any water starts a 1.5 s splash (the runner bobs and loses control). The runner then resurfaces automatically at a validated shore exit nearest to where they were heading.
  - There is no swimming and no way to stay in water.
  - There is no teleport across the water; exits are on that water's own shore.
- **Inactive waters** are visibly dimmer, show no marker, and give a splash with no stamp.
- **Splash marker.** A stamp places a marker over that water for the Night Watch for 3 s. It shows the location, never the runner.
- **Recovery.** Out-of-bounds or fall recovery returns a runner to the nearest pad of their last stamped water, or the dorm. It never grants a stamp or a shortcut home.

## Capture

- **Tag.** The Night Watch on foot presses Tag. There is a 0.14 s visible wind-up (the tagger keeps 60% of its speed), then a 0.22 s lunge at 8.2 m/s.
  - The lunge reaches 1.6 m within ±75° of facing and 1.5 m vertically, and needs line of sight from chest to chest.
  - A miss gives a 0.9 s cooldown; a hit gives a 0.5 s recovery.
  - Tagging is blocked for 0.5 s after leaving a cart, which prevents instant dismount tags.
- **Validation (host).**
  - The host checks role, state, cooldown, geometry and line of sight against the target's position as the tagger saw it, up to 150 ms back (lag compensation).
  - The target must also still be within reach + 0.9 m *now*.
  - Protected, finished, splashing and captured runners cannot be tagged.
- **Penalty.** The runner is held for 6 s with a whistle, a comic flop, and a visible countdown, and can spectate teammates meanwhile.
  - Stamps are kept and the runner stays a runner.
- **Return.** The runner reappears at one of several pads around their **last stamped water**. Before the first stamp it is the dorm area; after three stamps it is the third water, so they still have to run home.
  - The pad farthest from both Night Watch players is chosen.
  - The runner gets 2 s of visible protection.

## Carts (Night Watch only)

- **Fleet.** There are 2 carts.
  - Drivers can enter, accelerate, steer, brake and reverse, stop, and exit.
  - Runners cannot enter carts.
- **Handling.** Top speed is 11 m/s on roads and 6.5 m/s off-road, with 6.8 m/s² acceleration. The turn radius widens with speed (3.2 m to 9.5 m), and reverse is capped at 4 m/s.
- **Where carts can go.** Carts cannot climb stairs, walls or kerbs.
  - Bollard lines (a cart-only collision layer) keep carts out of a zone around every water and around the dorm doors.
  - Footpaths, low walls, hedges and stairs give runners routes carts cannot follow.
- **Seats.** Entry needs ≤ 2.4 m range and a cart moving ≤ 3 m/s.
  - Simultaneous claims are resolved on the host: the nearest player gets the seat, with ties going to the lower slot.
  - Entering takes 0.35 s.
- **Exit.** The cart auto-brakes to ≤ 2.5 m/s first. The exit point is then validated:
  - solid ground, not water;
  - clear capsule space;
  - line of sight from the seat, so you never dismount through a wall.
  - If no side is clear, the driver stays seated.
- **Bumps.** A cart moving ≥ 2.5 m/s that hits a runner causes a short controlled stumble (0.55 s) with knockback capped at 6 m/s.
  - **Never a capture.**
  - The runner gets 1 s of bump protection, against both further bumps and follow-up tags.
  - Each cart has a per-runner cooldown, so there are no stun loops.
  - The cart loses 45% of its speed.

## Runner movement

| Move | Value |
|---|---|
| Run | 5 m/s |
| Sprint | 7 m/s, from a meter of 2.5 s that regenerates fully in 3.6 s after a 0.35 s delay (no wait after small actions) |
| Jump | Jump with 0.12 s coyote time and a 0.13 s jump buffer |
| Dive | Press jump again in the air: an 8.6 m/s forward dive with a short landing |
| Night Watch on foot | 6.2 m/s (see the tuning note below) |

Ground acceleration is high and turning is fast, so movement stays precise while the animation is silly.

**Tuning note: Night Watch foot speed went from 5.6 to 6.2 m/s, and wind-up speed from 25% to 60%.** Bot playtests showed the old values made foot chases unwinnable.
- **Why 5.6 failed.** A runner who manages the sprint meter averages about 5.8 m/s: 2.5 s at 7 m/s, then about 4 s at 5 m/s while it refills. That is faster than 5.6.
- **What the bots showed.** In a recorded practice round the Night Watch bot followed a runner at 1–2 m for over 20 s without ever landing a tag. The heavy wind-up slowdown made every lunge from behind fall short.
- **Headless trials.** A Night Watch bot chased a fleeing runner bot from 8 m on open lawn. The old tuning caught the runner in 1 of 5 valid trials; the new tuning caught it in 5 of 5, in 6–17 s.
- **Escape is still possible.** A sprint still out-runs the Night Watch for its duration (`test_chase_balance`). Corners, walls, hedges, dives, water and the cart-free zones remain the runner's ways out.
- **Not final.** These are prototype values to re-check in device playtests.

## Gadgets (runners)

- **Pickups.** There are 9 pickup spots, set slightly off the fastest lines. Each respawns 25 s after it is taken.
- **Holding and use.** A runner holds one gadget at a time. Use has a 1 s cooldown, and the host validates ownership and consumption.
- **Reconnect.** Gadget state lives only on the host, so a reconnect cannot duplicate a gadget. The covering bot may use a held gadget.

| Gadget | Effect |
|---|---|
| Turbo Sneakers | ×1.25 speed for 3 s. Combined with sprint, speed is capped at 8 m/s. |
| Squeaky Decoy | Assisted toss up to 9 m, camera-relative. It wanders and emits runner-like footstep noise and the matching visual cue for 5 s. |
| Splash Bomb | Toss up to 11 m, with assist toward a cart within a 35° cone and 15 m. A hit caps a cart at 4 m/s for 2 s; the cart is then immune for 2.5 s. No screen blinding, no stun on players. |

## Information

- **Night Watch sight.** The Night Watch sees runners with line of sight within 34 m and a ±62° view cone; within 4 m the cone is ignored. Buildings, walls and carts block sight.
- **Spotted cue.** A spotted runner gets a restrained "spotted" vignette and icon for 2.2 s. It comes from the host's actual detection.
- **Noise.** Each side receives anonymous noise directions, shown as on-screen chevrons and sound:

  | Noise source | Range |
  |---|---|
  | Runner sprint | 24 m |
  | Runner jog | 14 m (walking softly is silent) |
  | Night Watch steps | 12 m |
  | Carts | 45 m |

- **Splashes.** A splash plays positional sound at the water, and stamps appear in the event feed.
- **No omniscient map.** Runners do not see the Night Watch on the map. The Night Watch sees only splash markers.
- **Bots.** Bots read the same `can_see`, `noises_for` and splash-marker data and nothing else.

## Fair target combinations

`game/tools/route_analysis.gd` builds a route graph from the campus layout and pathfinding grid. `game/config/route_table.json` keeps the combinations whose estimated trip lies within ±12% of the median, and `game/config/route_bot_times.json` adds the measured times of runner bots using the real movement code. 14 of the 20 combinations are curated. The headless route test confirms that runner bots finish every curated combination with no pursuit, with a median of about 2 minutes (see TEST_REPORT.md).

## Rewards (cosmetic coins only)

- **Coin awards.**

  | Source | Coins |
  |---|---|
  | Taking part | 20 |
  | Each stamp | 5 |
  | Finishing | 15 |
  | Team win | 15 |
  | Each *distinct* runner captured | 10 (the same runner twice pays once) |
  | Fastest Trifecta (first runner home) | 10 |

- **Scaling and limits.**
  - Practice pays ×0.5.
  - There is nothing for idle survival time.
  - Rewards are paid once per match ID.
  - An interrupted round, such as one ended by host loss, pays nothing.
- **What coins buy.** Coins buy outfits only. Everyone has identical abilities.

## Disconnects

- **Reserved slot.** A disconnected player's slot is reserved for 20 s while a bot plays it; the event feed announces this. Reconnecting resumes the same authoritative progress and state, with no reset and no free protection.
- **Late joiners.** Someone joining mid-round spectates until the next round.
- **Host loss.** If the host leaves, or goes silent for 6 s, the round ends for everyone with no rewards, and clients return to a recoverable menu screen.

## Deferred: After Hours (not in V1)

After Hours is recorded for a later version and not implemented:

- One player starts as patrol, and captured runners convert to patrol.
- The two carts are shared, and extra patrol players chase on foot.
- The first runner to splash all three targets and get home wins.
- If everyone is captured, or nobody finishes by the deadline, patrol wins.
- It needs its own snowball and camping playtests.
