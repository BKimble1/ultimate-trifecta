# Trifecta Chase: implemented rules (V4, V6 dorms and coins)

All values come from one resource, `game/config/rules_default.tres` (`RulesConfig`, `game/src/config/rules_config.gd`). The party's settings derive each round's own copy (`PartySeries.rules_for`), which the simulation, bots, HUD, tutorial, How to Play and results all read; the global default is never changed while a round uses it. The authority is `MatchSim` (`game/src/sim/match_sim.gd`), which runs on the room host, or locally in practice.

**Runner card** (`TC.role_lines`, values filled in from the round; V6 names tonight's dorm): "Run out, splash into the three marked waters, then run back inside Lanternfield House through one of its doors. 4 home wins it for every runner. Caught? You keep your splashes and you're back in 6 s."

**Night Watch card**: "Stop 4 runners getting back inside Lanternfield House before time runs out: cut them off in a cart, hop out and tag. A tag sends a runner out for 6 s; they keep their splashes. Nobody can be tagged inside the dorm."

## Party settings (host, before a series)

| Night Watch | Runners | Home to win |
|---|---|---|
| 1 | 7 | 5 |
| 2 (recommended) | 6 | 4 |
| 3 ("a tougher runner challenge") | 5 | 4 |

- Eight gameplay slots; bots fill empty seats and stay labelled. `runners = 8 − Night Watch`, `home to win = ceil(2 × runners / 3)` (`PartySeries.required_home`).
- **Rounds:** 1, 3 (recommended for friends) or 5. The lobby shows one summary line, e.g. "3 rounds · 2 Night Watch · 6 runners · 4 home to win", and Reset to recommended.
- Only the host can change them, only in the lobby before a series starts. A change bumps a revision, clears guests' Ready and tells them why. Settings lock when the series starts; ending the series (with confirmation) unlocks them. Guests see the host's values read-only.
- Each round starts from an immutable snapshot of the locked settings carried in START; incompatible clients are refused with "Update the game to join." (protocol 8 since Pass 9, when sprint was removed; protocol 7 was Pass 8; a guest whose dorm geometry differs from the round's is refused the same way).

## Roles

- **Friend parties:** drawn on the host at each round from a seeded random draw. Round 1 gives every human an equal chance; later rounds prefer whoever has had fewer Night Watch turns, ties broken at random. With two or more humans at least one human stays a runner and up to min(Night Watch, humans − 1) humans go on the Night Watch; bots take the remaining Night Watch seats. Saved role preferences play no part.
- **One human in a party:** Night Watch with probability (Night Watch count ÷ 8), otherwise runner. Solo practice is the way to pick a role.
- **Solo practice:** Runner, Night Watch or Random, plus a guided runner tutorial and a guided Night Watch exercise (find a runner, wait for Tag to light, tag, the capture and protection rules, a cart and a hop-out tag; runner bots jog slower there). The choice is stored for practice only.
- A reconnecting player keeps the same seat and role for the current round. Spectators and newcomers join at a round boundary and never inherit anyone's score.

## Series

- A round is one campus chase; a series is the chosen 1/3/5 completed rounds in the same party. Lifecycle: party setup → role reveal → shared loading and countdown → round → round results → ready for the next round → … → final series results → play another series or back to the lobby.
- The HUD and results say "Round 2 of 3". The host starts the next round when connected humans are ready (bots are always ready); nothing starts on its own. Guests see "Ready for round N" / "Waiting for host", not a Rematch button.
- **Round Win:** every eligible participant whose role's team won the round gets one. Personal contribution is shown separately (runners: splashes, home order, times caught; Night Watch: tags and different runners tagged) and never ranked against the other role's numbers.
- **Final leaderboard:** by Round Wins; ties share a place; "You" highlighted; rounds played shown; late joiners and partial participation marked; bots kept out of the standings. The role-team tally ("Runners won 2, Night Watch won 1") is a tally of roles, not a fixed team's score.
- **Eligibility:** a human counts as present when connected at the end and away (a bot covering) for no more than 40% of the round; otherwise no Round Win and no coins for that round (it is still recorded so it can't pay later).
- Results are applied once per series, round and player identity (match ID + uid), so repeated packets, reopened results and reconnects can't pay twice. A cancelled round counts for nothing and doesn't use up a round.
- The host can end a series early (confirmation); completed rounds stand. Host loss ends the party as before.

## Round

| Rule | Implemented behavior |
|---|---|
| Roster | 8 slots; runners and Night Watch per the party settings. Bots fill empty slots, named `Bot …` and tagged BOT in the lobby, scoreboard and results. |
| Home dorm (V6) | One of three dorms — Puddlesworth Hall, Lanternfield House, Moonpenny Lodge — chosen by the host from the round's seed, never the same as the previous round when another is available (the guided tutorial always uses Puddlesworth Hall). Published in the round configuration with its geometry version and fingerprint, the slot → pad mapping, the targets, the coins and the start timing; reconnects and replays keep it. |
| Roles | Shown before play, inside the home dorm: a 4 s role-reveal card naming tonight's dorm (with "Round x of y"), then a 3 s shared countdown. Nobody can tag or be tagged during the reveal or the countdown (the simulation runs no intents before GO). |
| Start | Runners stand on their own pads inside the home dorm's common room, facing one of its three doors, and run out at GO. The Night Watch starts outdoors at the Grounds Shed. |
| Clock | 240 s round clock starts after the countdown. Server ticks (60 Hz) drive the countdown, penalties and deadline. |
| Head start | The Night Watch waits 6 s at the Grounds Shed inside the round clock (30 s in the tutorial). |
| Targets | 3 distinct waters out of 6, the same for every runner, from a curated fair set, avoiding an immediate repeat. Targets never move or reroll. |
| Order | Any order, chosen by each runner. |
| Stamp | Entering an active target's water volume (jump, dive or walk in) awards that target's stamp once. |
| Finish (V6) | With all 3 stamps, run back **inside the home dorm through one of its doors**: the host sees the runner's centre cross the door's threshold (the line across the opening at the wall's inner face) from outside to inside during a tick — within the 3 m opening, at feet height (−0.5…1.6 m), on a move shorter than 3 m, with a clear line between the start and end of the move. Starting inside, running out, coming back without all three stamps, another dorm's door, standing against a wall or tunnelling through it never finish; a finish counts once. Approaching the old exterior finish box does nothing (it no longer exists). |
| Home is safe (V6) | Nobody can be tagged inside the home dorm's common room (the Night Watch may walk in). Other dorms are ordinary buildings. |
| Runner win | The round ends the tick the required number of runners (see Party settings) are home. A finish on or before the deadline tick counts. |
| Night Watch win | The clock expires with fewer runners home than required. Tags never eliminate anyone or win by themselves. |
| Survival | Not being caught never counts toward winning; only finishes do. |

### Same-tick ordering

The fixed per-tick order is: timers → intents → movement → **finish** → **water/stamps** → **tags** → cart bumps → gadgets → out-of-bounds recovery → perception → win/timeout.

- A runner who crosses a home threshold on the same tick as a valid tag is home; the finish takes precedence.
- Coins (step 8, with the gadgets) are decided after tags, before recovery.
- Results are built once by the host. Clients never declare their own stamps, finishes or captures, so late or duplicated packets cannot change an outcome.

## Water

- **Splash sequence.** Entering any water starts a 1.5 s splash (the runner bobs and loses control). The runner then resurfaces automatically at a validated shore exit nearest to where they were heading.
  - There is no swimming and no way to stay in water.
  - There is no teleport across the water; exits are on that water's own shore.
- **Inactive waters** are visibly dimmer, show no marker, and give a splash with no stamp.
- **Splash marker.** A stamp places a marker over that water for the Night Watch for 3 s. It shows the location, never the runner.
- **Recovery.** Out-of-bounds or fall recovery returns a runner to the nearest pad of their last stamped water, or the dorm. It never grants a stamp or a shortcut home.

## Capture

One explicit contract, shown with the same values on the role reveal, in How to Play, the tutorials, the HUD and results.

- **Tag.** The Night Watch on foot presses Tag. There is a 0.14 s visible wind-up (the Night Watch keeps 90% of its speed), then a 0.22 s lunge at 9.0 m/s.
  - **Target assist (V4).** At the press, the host picks an eligible runner in line of sight within 4 m inside a ±50° cone of the camera (or the Night Watch's facing). The Night Watch turns toward it by at most 40° at once, then tracks it through the wind-up and lunge at up to 240°/s. No suction, no teleport, no lock-on: speed and reach are unchanged.
  - The lunge reaches 1.6 m within ±75° of facing and 1.5 m vertically, and needs line of sight from chest to chest.
  - A miss gives a 0.9 s cooldown; a hit gives a 0.5 s recovery. Tagging is blocked for 0.5 s after leaving a cart.
- **Tag-ready cue.** The host predicts where the lunge would end if the runner keeps going; when that gap is inside the reach (with a 0.2 m margin) the Night Watch's Tag button glows and a ring under that runner turns amber. The cue and the aimed runner travel in the Night Watch's private snapshot block. The Tag button shows the cooldown or cart-exit lockout as an arc.
- **Validation (host).** Role, state, cooldown, geometry and line of sight, against the target's position as the tagger saw it up to 150 ms back (lag compensation); the target must also still be within reach + 0.9 m *now*. Protected, finished, splashing and captured runners cannot be tagged; a finish on the same tick wins (finish is resolved before tags).
- **Penalty.** The runner is held for 6 s and stays a runner with every stamp kept. On screen: "Caught by <name> · back in 6…", then "Back in 5…", with "Your splashes are safe." and where they will return. They can watch teammates meanwhile.
- **Tagger.** One confirmation: "Tagged <name>! · 2 catches" (their count this round).
- **Return.** The runner reappears at a pad around their **last stamped water** — before the first stamp, on one of the pads just inside each door of the **home dorm** — the pad farthest from the Night Watch, with 2 s of visible protection ("Protected · 2"). Out-of-bounds recovery before the first stamp uses the same home-dorm pads.

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
| Sprint | 7.4 m/s, from a meter of 2.5 s that regenerates fully in 3.6 s after a 0.35 s delay. Running the meter dry leaves sprint off ("Sprint empty · ease off to recharge") until sprint is released (button up, or the thumb eased back from the stick's edge) and the meter is back to 45 %; the next press sprints at once |
| Jump | Jump with 0.12 s coyote time and a 0.13 s jump buffer |
| Dive | Press jump again in the air: an 8.0 m/s forward dive, one per jump, then a 0.45 s landing recovery before the next jump (a press in its last 0.13 s jumps as it ends) |
| Night Watch on foot | 6.6 m/s (see the tuning note) |

Ground acceleration is high and turning is fast, so movement stays precise while the animation is silly.

**V4 tuning note (Night Watch too hard in the owner's playtest).** Measured with deterministic pursuit scenarios (`game/tests/test_pursuit.gd`: real sim and physics, a human-like Night Watch with a 0.25 s camera lag that presses Tag at a "looks close" 2.6 m or on the cue). The same harness ran on the V3 values and the V4 values (`docs/v4/pursuit_before.txt`, `pursuit_after.txt`):

| Scenario | V3 values | V4 values |
|---|---|---|
| Jogging runner from 4 m | 2.7 s, 2 presses | 1.3 s, 1 press |
| Jogging runner from 8 m | 6.1 s, 2 presses | 3.8 s, 1 press |
| Jogging runner from 12 m | 9.4 s, 2 presses | 6.3 s, 1 press |
| Pressing only when Tag lights up (8 m) | no cue (escaped) | 3.8 s, 1 press |
| Runner sprinting whenever the meter is full (8 m) | 17.8 s | 10.8 s |
| Close rear tag, both running (2.2 m) | 0.3 s | 0.2 s |
| Weaving runner (6 m) | 3.5 s, 2 presses | 1.9 s, 1 press |
| 100 ms input delay ±33 ms (8 m) | 5.9 s | 5.0 s |
| 250 ms hitch at 2 s (8 m) | 6.1 s | 3.8 s |
| Cart from 21 m, hop out, finish on foot | 14.1 s | 11.8 s |
| A 2 s sprint (gap gained) | +1.6 m | +1.5 m |

- **Control/aim first.** In V3 the first "close-looking" press at 2.6 m missed every time: the wind-up cost 40% speed and the lunge kept its facing while the runner moved on. The assist and tracking, the faster wind-up and lunge and the tag-ready cue fixed the misses before any speed change.
- **Then speed.** A runner cycling the sprint meter averaged ~5.8 m/s against 6.2 m/s, so straight pursuits took ~18 s. Night Watch foot speed went to 6.6 m/s and runner sprint to 7.4 m/s so a sprint is still a real burst (still slower than sprint, dive 8.6, now 8.0, and Turbo 8.0). Corners, walls, hedges, dives, water and the cart-free zones remain the runner's ways out.
- These are measured scenario values, not device playtests; re-check with people on phones.

**Pass 8 note (sprint pulsing and the dive loop).** Holding sprint used to restart it on every 15 % of refill, and a jump pressed during a dive fired on the landing tick and could dive again, so chained jump→dives held 8.05–8.45 m/s and out-ran the Night Watch. Now a held sprint stays off once the meter runs dry until it is released and back to 45 %, a dive is one per jump at 8.0 m/s, and its 0.45 s landing recovery can't be skipped. On flat ground the best dive loop averages 5.2 m/s, below sprinting in released-and-repressed bursts (6.0 m/s) and the Watch (6.6 m/s); in the pursuit scenario the Watch catches a dive-looping runner from 8 m in 4.5 s (it escaped before). Details and traces: `docs/pass8/movement.md`.

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

- **Night Watch sight.** Line of sight within 34 m and a ±62° view cone (cone ignored within 4 m). Buildings, walls and carts block sight.
- **Spotted cue.** A spotted runner gets a restrained vignette and icon for 2.2 s, from the host's actual detection.
- **Noise.** Each side receives anonymous noise directions (chevrons and sound): runner sprint 24 m, jog 14 m (walking softly is silent), Night Watch steps 12 m, carts 45 m.
- **Splashes.** A stamp marks that water for the Night Watch for 3 s: the place, never the runner.
- **Maps (V4).** The minimap and the full map (tap the minimap, or Map on a controller / M) show your own team openly, tonight's waters, the dorm and, for the Night Watch, carts and splash markers. Opponents appear only as **last seen**: solid while actually in line of sight and view range from your own head, then a fading ring labelled with its age for 5 s, then gone. Losing sight stops tracking; there are no live dots through walls. Spectating follows the same rules. Pass 8: an opponent in sight shows as a role badge with a facing tick; when sight is lost the mark stays where they were last seen, hollow, with its age on the full map, for 5 s. Caught or home, sightings come from the teammate you are watching. A guest's sightings stop when its snapshots are more than 0.6 s old. The full map's legend reads You · Team · Watch in sight · Last seen; while the Night Watch is in sight a runner's HUD says "Night Watch in sight · N m".
- **Match HUD (Pass 8).** One goal line and one clock: runners see "Team home n/N · Need k more", the Night Watch "Runners home n/N · Hold until m:ss" (amber under 30 s, coral under 10 s). Below it one personal next action: the waters still to stamp and "Next: <water>" with its direction and distance, "Return inside <dorm>", "Caught by X · back in 6", "Protected", or "Home · 2nd to finish · Waiting for team"; the Night Watch reads "You: 3 tags · 2 different runners". A pinned challenge shows in the pause menu and the expanded map.
- **Runner pace (Pass 8).** Runners (only) see "Runner pace: 3rd/6": home runners first by the tick they crossed a door, then by unique waters stamped, then by the estimated remaining route (through every remaining water in its best order, then to a door, over the same walking grid the bots use; routes within 4 m share a place, competition style 1, 2, 2, 4; a caught runner adds the hold left × 5 m/s). Bots are ranked and counted; "Not home" at the end. While routes are still being measured it says "updating", and a runner whose route can't be measured is placed by stamps and marked approximate. The host computes it every half second from precomputed route fields (no per-player path search) and sends each runner only places and stamp counts, never a position or another runner's next goal. Pace earns no reward.
- **What the network actually carries.** For smooth movement the host sends each player the positions of opponents within 45 m, or within 90 m in line of sight, whether or not they are visible on screen. The maps and HUD only present what was seen, but a modified client could read more: this is presentation policy, **not anti-cheat secrecy**. The Night Watch's private snapshot block also carries its own tag-ready flag and the runner the assist would pick (always someone already in its line of sight).
- **Bots** read the same `can_see`, `noises_for` and splash-marker data and nothing else.

## Fair target combinations

`game/tools/route_analysis.gd` builds a route graph from the campus layout and pathfinding grid. V6 measures every trip from inside each dorm (out through its nearest door, round the three waters, back in through the door nearest the last water). `game/config/route_table.json` keeps, **per home dorm**, the combinations whose estimated trip lies within ±16% of the median of all dorms' trips and whose measured bot time (`game/config/route_bot_times.json`, from `game/tools/dorm_balance.gd`) is within ±12% of the median; the host picks the targets from tonight's dorm's set. Route lengths, first-contact and first-objective timings per dorm × combination are in `docs/v6/dorms_notes.md`. The headless route test confirms that runner bots finish every curated combination with no pursuit (see TEST_REPORT.md).

## Rewards (V6: Coins and Season XP, cosmetic only)

Full tables, the earning calculation and the trust model: [docs/ECONOMY.md](docs/ECONOMY.md).

- **Coins** (one currency for earned and purchased Coins) and **Season XP**
  are paid only for an eligible, completed online round that the game
  service has verified: registered by the room's host with its admitted
  players, a plausible result reported by the host and confirmed by each
  player's own game, at least two present human players, and at most 40
  rewarded rounds per player per day.

  | Coins | | Season XP | |
  |---|---|---|---|
  | Completed the round | 10 | Completed the round | 50 |
  | Each coin picked up | 1 | Runner: each splash | 10 (max 3) |
  | Team win | 4 | Runner: home | 20 |
  | Runner: home | 3 | Night Watch: each *different* runner tagged | 15 (max 3) |
  | First runner home | 2 | Team win | 15 |
  | Night Watch: each *different* runner tagged | 1 (max 3) | | |

- **Not paid:** practice (isolated: it settles nothing into the wallet or
  the Season), cancelled or interrupted rounds (host loss included), a round
  you were mostly away from, rounds with you and bots only, rooms made
  without the game service, and any round when the build has no service (the
  results say which). Idle survival earns nothing; tagging the same runner
  again earns nothing more.
- **Once:** each round pays each player once (by match ID and profile, on the
  service), whatever packets are repeated or results reopened.
- **Lifetime level** (the "Lv" on your profile) still comes from the V4/V5
  performance values, practice ×0.5, kept on this device; it never comes
  from Coins and is separate from Season 1.
- **What Coins buy:** outfits and accessories in the Shop, and Season 1
  Premium (1,500 Coins). Everyone has identical abilities.
- **Rotating skins (Pass 8).** Ten Shop outfits (the six Pass 8 outfits and
  the four V6 Coin outfits) are sold only while their offer is on: four
  featured slots, each offer 48 h, changing at 00:00 UTC (two slots a day),
  on a published schedule; each card says when it leaves. The game service's
  clock decides: a purchase it accepts before the offer ends is delivered,
  one it receives after is refused with nothing charged. A bought skin is
  yours to keep; Shop skins may return.
- **Challenges (Pass 8).** 3 daily (50 Season XP each) and 3 weekly (150)
  goals, reset at 00:00 UTC and Monday 00:00 UTC (a round counts for the
  period it started in, settled up to 24 h late). Only verified online
  rounds you actively play count (at least 60 s, or 40 % of a short round,
  of real input or objective play); contribution goals credit each water
  you splash or different runner you tag, at most 3 a round; either role
  can complete them. Practice never counts. Each goal's bonus is paid once,
  with the round's settlement; Season XP only (no Coins, no tier skips).

### Gold coins in the round (V6)

- **Where.** The host picks 8 of the campus's candidate spots from the round's seed: on footpaths and walks (runner routes), at least 28 m apart where possible, at least 14 m from tonight's home doors and 8 m from the active waters' exits, jump-in points and pads; every candidate is reachable on foot from every dorm (tested). Each has a round-scoped id published in the round configuration.
- **Who.** Anyone on foot — runner or Night Watch, human or bot — who comes within 1.1 m. Not while caught, splashing, home, waiting in the shed or driving a cart. Two on the same tick: the nearer one, then the lower slot.
- **Worth.** Exactly 1 Coin each, once: a taken coin never comes back that round. The host decides and replicates the pickup (reliable event, plus the coins still out and your own count in every snapshot), so a replayed packet, a second client, a reconnect or reopening results can't add one.
- **Results.** Every results row carries `coins_picked` (humans and bots; bots own no wallet) and the round's `coin_log`; settling them into a wallet is done once per match id and player identity by the economy code.
- **Cancelled rounds** (host loss, ended early, abandoned): no settlement — coins picked up in a cancelled round are not paid (the row still records them for the audit).

## Disconnects

- **Reserved slot.** A disconnected player's slot is reserved for 20 s while a bot plays it; the feed announces this. Reconnecting (with the host's rejoin key) resumes the same authoritative progress, with no reset and no free protection. Time away is counted for series eligibility.
- **Between rounds.** A disconnected player's seat frees up between rounds; their series standing is kept by identity, so rejoining later continues it.
- **Late joiners.** Someone joining mid-round spectates until the next round and starts their own standing from that round.
- **Loading.** A round starts when every connected human has loaded, or after the load timeout, so one slow device can't hold everyone.
- **Host loss.** If the host leaves, or goes silent for 6 s, the round ends for everyone with no rewards, and clients return to a recoverable menu screen.

## Deferred: After Hours (not in V1)

After Hours is recorded for a later version and not implemented:

- One player starts as patrol, and captured runners convert to patrol.
- The two carts are shared, and extra patrol players chase on foot.
- The first runner to splash all three targets and get home wins.
- If everyone is captured, or nobody finishes by the deadline, patrol wins.
- It needs its own snowball and camping playtests.
