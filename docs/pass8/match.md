# Pass 8: match clarity and the map

Workstream MATCH of Pass 8 (brief §5 A–E and §6): one team goal and clock,
one personal next action, a live **Runner pace**, the series standing,
results in the order a player asks about them, and a map that answers
"where are the cops?" without seeing through walls.

Everything here was built and measured on desktop Linux (headless Godot, or
the Mobile renderer on Mesa llvmpipe under Xvfb) with emulated point scales
and safe areas. **No iPhone or iPad, and no people, were available to this
work**: the "first-time observer within ~3 s" goal of §5E is a design
target here, not a measured result (see Open items).

## Defect register

Symptoms are the owner's (brief §2/§5/§6); causes are from the source.

| # | Symptom | Cause (source) | Implementation | Evidence |
|---|---|---|---|---|
| M1 | "How are we doing?" — the top chip said "Home 2/4" for both roles | One label for both teams, no target or role wording; a separate clock pill | One **goal bar**: runners "Team home 2/4 · Need 2 more", the Night Watch "Runners home 2/4 · Hold until" followed by **the one round clock**; a segmented tracker (one segment per required finish, a house in each filled one) counting real finishes only. `required_home` comes from the round's own `RulesConfig` (`PartySeries.rules_for` of START's locked settings). No "winning" claim anywhere | `test_match_hud_pass8::test_goal_bar_follows_the_round_configuration` (1/2/3 Watch: 5/4/4; stamps and catches never fill the tracker; one clock on the HUD) |
| M2 | No clear next step | Three equal chips; the "head back" chip pointed at the nearest door by straight line | A **personal card**: "You: 2/3 waters" with the three waters' own shapes, checked when stamped; one emphasised next action ("Next: Pond" + camera-relative arrow + metres; "Return inside Lanternfield House" pointing at the route-nearest door; "Caught · back in 4"); home: "Home · 2nd to finish" / "Waiting for team". The suggestion is the first water of the host's best route order (any remaining water still counts; the help text says so); the map rings the same water / door | `test_runner_card_in_every_state` (0/2/3 waters, door, caught, protected, home, Not home), map item `next` |
| M3 | No sense of progress against other runners | Nothing compared runners during a round | **Runner pace** (RunnerPace, PaceFields; below): "Runner pace: 3rd/6", ties "tied 2nd/6", "updating" before data, "Not home" at the end | `test_runner_pace` (8 tests) |
| M4 | The Night Watch's contribution unclear | "n catches" counted tags only | "You: 3 tags · 2 different runners" from the reliable CAPTURE events (host and guest alike); Tag state line ("Tag ready", "Tag recharging", "Driving · hop out to tag", "In the shed · out in 4") | `test_watch_card_tags_and_pause_info` |
| M5 | Series standing invisible during a round | Only on results | "Series: tied 1st · 2 Round Wins" (+ "joined round 2", "away 1") in the pause menu, the map panel and results; nothing before the first results; bots never placed | `test_series_line_never_fakes_a_place` |
| M6 | Results led with portraits and tables | V6 order | 1 "Your team won!/lost" + why ("Runners won · 4 runners home · 3:19", "Time expired: 2/4 home"); 2 your contribution; 3 series line + roles context; 4 rewards (settled vs pending as before; the round's challenge lines go inside this card: the challenges stream's `add_challenge_lines`, merged by the integrator); then both teams' tables and the friends' standings. Cancelled: "It doesn't count: no Round Win, no loss and no rewards". Unfinished runners: "Not home" | `test_v7_screens` (first view holds Outcome, Why, Contribution, SeriesLine at all seven device sizes; the table scrolls into view), captures |
| M7 | Map dots didn't say who or how old | Opponents were plain dots / rings; age not shown; team all discs | Team marks by role shape (runner disc, Watch diamond); a seen opponent is a role badge (Watch: diamond + whistle, cart glyph while driving; runner: disc + drop) with a facing tick, an amber ring when a Watch is within 20 m; lost sight: hollow, frozen at the last point, dimming, with "3s" on the expanded map; gone after the existing 5 s TTL. Legend "You · Team · Watch in sight · Last seen" (+ waters, home doors) | `test_map::test_sight_walls_lost_sight_and_expiry` |
| M8 | Home / caught spectators scanned from their own (home or held) body | `_scan_seen` always used the local slot | Sightings come from the character the view follows (the followed-view policy): your own while in play, the watched teammate while caught or home; pure spectators unchanged (nothing) | same test (`sight_slot`) |
| M9 | A guest whose link died could keep a frozen opponent "live" | `_scan_seen` read interpolated buffers with no freshness check | No new sightings from snapshots older than 600 ms (`SEEN_STALE_MS`) | `test_map::test_a_dead_link_adds_no_sightings` (loopback rig) |
| M10 | Long capture sentence; permanent "HOME SAFE!" | V4/V6 overlays | Caught: "Caught by X · back in 6" / "2/3 waters kept · back at Fountain · protected 2 s" (the return place follows the simulation's own rule: the host reads its last stamped water, or "inside <dorm>" before any; a guest uses its latest stamp event and says "your last splash" if it has none, e.g. after a reconnect). Home: "Home · 2nd to finish · Waiting for team" for 3.5 s, then the view follows a teammate | `test_runner_card_in_every_state` |
| M11 | Noise chevrons had no context | — | The loudest close noise (≥ 0.5) gets "footsteps nearby" / "cart nearby" beside its chevron; still a bearing only | code (`DrawLayer`) |
| M12 | (coordinator request) Sprint latch feedback | Integrator's `SimPlayer.sprint_exhausted` (commit 001d16a) | "Sprint empty · ease off to recharge" with a coral, hatched mini meter (and a tick at `sprint_rearm_fraction`) while the local runner is latched **and** still holds sprint; gone as soon as either stops. The controller meter is tinted/hatched while latched. Read defensively (`"sprint_exhausted" in p`); placed above the thumb clusters | `test_sprint_empty_hint_follows_the_latch_and_the_hold`, layout test |

| M13 | (found in the captures) "Watching Sockfoot · next: ⟳" overlapped the Cheer button at 667×375 | Fixed `vs.y − 150` placement, older than this pass | The watching line and the sprint hint are placed above the resolved thumb clusters (`MatchHUD.thumbs_top`) | layout test (watching line vs Next/Cheer at every size) |
| M14 | (challenges stream hand-off) The pinned challenge had no place in a round | `Wallet.pinned_challenge_text(live_row)` exists on the challenges branch, unwired | One line "Challenge: Campus Contribution 4/6 · +50 Season XP" in the pause menu's where-you-stand lines and under the series line on the expanded map, only when a goal is pinned. An online round passes the local row so far (`{role, stamps, unique_captures}`: waters splashed / different runners tagged) for the provisional "+n this round"; practice passes `{}` (never counts). Called through `Wallet.has_method`, so it shows nothing until that stream is merged | `test_watch_card_tags_and_pause_info` (injected source: menu, map, practice vs online row, unpinned) |

Removed: the unused `MatchHUD.Compass` class (dead since V2; it pointed at
waters by straight line and would have contradicted the card).

## Runner pace

**Order** (`RunnerPace.rank`, host only): runners home first by the tick
they crossed a door (two crossings on one tick share a place); then by
unique required waters stamped; then by estimated remaining route; routes
within **TOL_M = 4 m** of the first runner of a group share its place
(anchored, so 10 / 13 / 16 m gives 3rd, 3rd, 5th — no chaining). Slot
order lays rows out but never breaks a tie. Places are shared competition
style (1, 2, 2, 4). Bots are ranked like anyone and counted in the
denominator ("3rd/6" with one bot among six runners); the expanded
standings mark them BOT; series standings never include them.

**Remaining route**: from the runner's grid cell, the best of every visit
order of the remaining waters (≤ 3! = 6), then home:
`W[first](cell) + Σ C[a→b] + X[last]`, where `W[w]` is the route field of
water `w`, `C[a→b]` the best of water a's shore exits into water b's field,
and `X[w]` the best exit of `w` into tonight's home field. A splashing
runner is measured from the shore exit they'll come out at; a caught runner
from the best pad they can return to (last stamp's pads, or inside the dorm
before the first stamp) **plus the hold left × 5 m/s** (a catch costs pace;
stamps stay). With all three stamps the route is just the home field; the
field's per-cell source label is the suggested door.

**Fields** (`PaceFields`): one multi-source Dijkstra per water and per
dorm over the runners' 1 m navigation grid (`NavGrid.foot`: the same
solid cells, low-wall ×4 and fence ×6 costs and corner rule as the bots'
A*), step costs 10 / 14 × the entered cell's weight, a bucket queue (no
heap). Water sources: the water's validated `jump_points` and `exits`
(where a runner really gets in and comes out); home sources: each of
tonight's doors' `approach` point (outside). A position on an inflated
wall cell uses the nearest open cell within 4 m. Routes go round buildings
and in and out through real doorways: `test_routes_are_playable_and_orders_are_optimal`
checks that no route is shorter than the straight line, that obstacles
bend routes (a ≥ 1.3× detour exists), that behind tonight's dorm the way
home goes round to a side door (not through the building), and that the
pace's route equals a hand enumeration of all six orders.

**When costs are missing** (fields still building, a runner off the
grid): that runner's whole stamp group shares one stamp-based place,
flagged approximate; before any pace exists the HUD says "Runner pace:
updating". Never an invented exact place.

**Change cue**: a place published because a stamp or finish changed the
groups updates at once; a change from route distance alone is published
only after it held for two updates (1 s). The card shows a small ▲ (teal)
or ▼ (muted) beside the pace for 2.5 s after a real change (no fade with
Reduced Motion); no celebration.

**Help line** (map panel and its help card): "Pace follows splashes and
route remaining. Your team wins by getting enough runners home."

**Wire** (protocol 7): the private snapshot block ends with
`u8 next_goal` (the recipient's own suggestion: target index, 16 + door, 255
none) and `u8 n` + per runner `slot, place|tied|approx|home, stamps`
(2 + 3n bytes, 20 bytes for six runners). **Runners only**: the Night Watch
and spectators get an empty block; there are no positions, no other
runner's goal. `test_snapshot_block_is_runners_only_and_positionless`,
`test_pace_reaches_a_guest_runner_not_the_guest_watch` (loopback rig).

### Budget (measured here; desktop, a 4-core machine shared with other sessions)

| What | Where | Cost |
|---|---|---|
| `PaceFields.request` (round preparation, inside the staged "sim" job) | main thread | 0.14 ms (copies source points, starts one worker task) |
| Grid copy (once per layout) | worker | 20–51 ms |
| One field (water or home) | worker | 67–137 ms each (215 ms once under heavy contention); a round needs 3 waters + 1 home, kept for later rounds (≤ 9 fields, ~3.4 MB) |
| Pace update, six runners, all orders | host main thread, 2 Hz | p50 105 µs, p95 157 µs, p99 494 µs, max 4.2 ms over 200 updates (`[pace budget]` in `test_runner_pace`; the machine's load average was ~17 on 4 cores, so the tail is the machine's) |
| Path searches started by pace | — | 0 (`test_budget_and_no_path_search`) |
| HUD refresh (goal bar, card fitting, pace, danger, sprint hint) | every frame | p50 137 µs, p95 373 µs, one 24 ms outlier in 300 calls (`[hud refresh]` in `test_match_hud_pass8`, same load) |

Nothing waits for the worker: until the fields are in, pace is
stamp-based. The field task is queued as a *high-priority* worker task on
purpose: Godot runs low-priority tasks on a small share of the pool (one
thread on a 4–6 core phone), and that share is where the V8 bot path
searches run with their fixed delivery ticks, so a field build there could
make a delivery wait; as one high-priority task it takes another thread.
The grid copy holds the foot grid's search lock (bots search only after
GO; the copy happens during loading). Leaving a round never waits for a
field build (the next round's request picks it up); only quitting the
game does, once, at engine shutdown — found here because a worker still
running at exit aborted the test process (exit 134 after passing). On a phone the worker time will be several times longer; the
4 s reveal + 3 s countdown cover it, and it is skipped entirely on later
rounds with the same waters/dorm. Not measured on a device.

## Map information policy (unchanged in substance)

Personal sight as before: line of sight from the viewer's head within the
34 m view range through campus collision (`TC.L_WORLD`: buildings, walls,
dorms); "not on screen" is not "not in sight". Opponents are recorded only
while seen and expire 5 s after the last sighting; the mark never moves
while out of sight. Runners' maps never list carts (an occupied Watch cart
appears only as the Watch's own cart badge while that driver is seen). The
Night Watch keeps seeing its own carts and splash markers. Team-shared
spotting was **not** added. What the network carries is unchanged (RULES
"What the network actually carries"); the pace block adds no coordinates.

## Readability (§5E)

`test_match_hud_pass8::test_layout_at_phone_and_ipad_sizes` runs a real
practice round at 667×375 (@2), 844×390 (@3, insets 47/0/47/21), 926×428
(@3), iPad 1024×768 (@2, 0/24/0/20) and 844×390 with an asymmetric inset
(the other landscape orientation's notch side), runner standard and
mirrored and Night Watch: the goal bar, badge row, personal card and
danger chip stay inside the safe area and the top HUD band
(`TouchLayout.TOP_BAND`), clear of Pause (≥ 44 pt), the minimap, the
resolved thumb clusters and each other; no word on the card is clipped
(long lines take two: "Return inside" / "Lanternfield House"; splits
after the first "·"); the sprint hint sits above the thumb clusters.
Colour always comes with a shape (water icons and checks, tracker houses,
role-shaped marks, the alarm-clock icon under 10 s, hatched latched
meter). Reduced Motion: no clock breathing, no pace-arrow fade. The HUD
has no focusable controls; the map and pause keep their V7 focus.

## Evidence

`docs/media/pass8/match/<device>/` (se 667×375 pt, p14 844×390 pt, max
926×428 pt, ipad 1024×768 pt), rendered by `tools/capture_pass8_match.sh`
(driver `src/dev/capture_pass8_match.gd`): **deterministic dev states** (the
driver teleports players, sets stamps, calls the simulation's own capture
and doorway-finish rules, shortens the clock; results shots use rows
recorded through `PartySeries` and, where named, a **simulated wallet**
summary). Each image has `<shot>_hud.json` with the measured rects in canvas
units and points and the overlaps found (none expected). Desktop llvmpipe
renders: layout and look only, not frame rate or device input.

See `docs/media/pass8/match/README.md` for the shot list.

## Tests

| File | What |
|---|---|
| `tests/test_runner_pace.gd` (new) | order rules, shared places, unknown routes, enumeration, playable routes vs straight lines, optimal order, in-round pace with a bot, caught cost, debounce, budget/no path search, snapshot block, guest runner vs guest Watch over loopback |
| `tests/test_match_hud_pass8.gd` (new) | goal bar for 1/2/3 Watch, clock urgency, runner card in every state, Watch card and pause info (and the pinned challenge line), sprint hint, series line, HUD refresh cost, layout at four sizes × orientations × roles |
| `tests/test_map.gd` (extended) | walls, live badge, lost sight frozen and aged, TTL, danger chip, followed view, carts, a dead link |
| `tests/test_v7_screens.gd` (one check updated) | V7's "first table row in the first view" → Pass 8's first view (outcome, why, contribution, series line); the table still scrolls into view. Changed transparently because §5D reorders the page |

Run here (all passing): test_runner_pace, test_match_hud_pass8, test_map,
test_pause_input, test_pause_online, test_results_layout, test_rankings,
test_series, test_v7_screens::test_home_results_and_standings, test_net,
test_trust.

## Open items

- **People**: no comprehension test was run (§5E's 3-second goal is not
  measured). Suggested: show three stills (runner 2/3, runner 3/3, Night
  Watch) to five first-time viewers for 3 s each and ask role / next task /
  team target / time / own progress.
- **Device**: pace worker time, HUD refresh and legibility on a phone.
- **Touch sprint meter**: the stick's own meter lives in
  `touch_controls.gd` (integrator). `local_info()` now carries
  `sprint_exhausted` and `sprint_held`; tinting the stick meter with
  `MatchHUD.SprintMeter.paint(ci, rect, value, latched, rearm)` would
  match the HUD's.
- **Challenges in results**: this branch no longer has its own results
  slot (its assumed list shape didn't match the challenges stream's
  `{state, result, xp, lines, message}`); the challenges stream's
  `add_challenge_lines` in `_fill_rewards` is the one place, inside the
  rewards card (step 4 of the hierarchy). The capture driver's simulated
  wallet already carries that shape: re-run
  `tools/capture_pass8_match.sh <dir> results se max ipad` after the merge
  to show the lines.

## For the integrator

- Merging into `p8-integ` (a trial merge-tree against 9eb6390, nothing
  written) conflicts in three places, all "keep both":
  - `game/src/net/protocol.gd` header: keep both Protocol 7 comment
    paragraphs (motor flags / active_s, then the pace block); one
    `const VERSION := 7`.
  - `game/src/sim/match_sim.gd` members: keep both `var activity :=
    ActivityMeter.new()` and `var pace: RunnerPace = null` with their
    comments.
  - `game/src/dev/capture.gd`: keep both `elif` branches (`"shop_p8"` and
    `"pass8_match"`). Each declares its own local `p8`; the two lines after
    the markers (`p8.set("cap", self)` / `add_child(p8)`) are shared, so
    repeat them at the end of the first branch.
  - `results_screen.gd` and `match_controller.gd` merge cleanly; keep the
    challenges stream's `add_challenge_lines` call in `_fill_rewards`.
- After merging, run: test_runner_pace, test_match_hud_pass8, test_map,
  test_pause_input, test_home_results_and_standings_fit_every_device,
  test_results_layout, test_challenges, and re-capture the results part
  (above).
- `RULES.md` (yours): update "Protocol 6" mentions to 7 and add:
  - Information › Maps: "Opponents appear only while you see them, as a
    role badge with a facing tick; when sight is lost the mark stays where
    they were last seen, hollow, with its age on the full map, for 5 s.
    Caught or home, sightings come from the teammate you are watching. A
    guest's sightings stop when its snapshots are more than 0.6 s old."
  - New "Runner pace" paragraph: the order above (home by finish tick,
    stamps, remaining route through every remaining water in the best
    order then a door, 4 m shared places, caught = hold × 5 m/s,
    approximate when unknown), runners only, bots counted, "Not home" at
    the end, no reward.
  - HUD: "Team home n/N · Need k more" / "Runners home n/N · Hold until
    m:ss"; "You: 3 tags · 2 different runners".
- Files outside the MATCH ownership list touched (small, additive):
  `game/src/sim/match_sim.gd` (a `pace` member, created in `setup`,
  updated every 30 ticks and at the round's end — output only),
  `game/src/match/match_controller.gd` (local info, sightings, events),
  `game/src/core/round_ranking.gd` (series line, short reason),
  `game/src/dev/capture.gd` (scenario hook), `game/tests/test_v7_screens.gd`.
