# Pass 8 match clarity evidence

Rendered by `tools/capture_pass8_match.sh` (driver
`game/src/dev/capture_pass8_match.gd`) on desktop Linux: the Mobile renderer
on Mesa llvmpipe under Xvfb, at each device's pixel size with its point
scale and safe area emulated (`--emulate-phone`, `--emulate-safe`, V7's
point conversion). **Layout and look evidence only**: not frame rate,
device input or a comprehension test.

**Deterministic dev states.** The driver puts a real practice round into
each state: it teleports players, sets stamps, calls the simulation's own
capture and doorway-finish rules, switches the Night Watch bots' brains off
in runner shots (they stand where placed), and shortens the clock. The HUD,
card, pace, map and results are the game's own output for those states.
Results shots for a friend series use rows recorded through `PartySeries`
(real Round Wins, shared places, a late join, an away round); where a shot
shows settled or pending rewards it uses a **simulated wallet summary**
(the service is not deployed), labelled in that shot's `_hud.json`.

Next to each image: `<shot>_hud.json` (viewport, units per point, safe
area, the rects of the goal bar, the personal card, the danger chip, Pause,
the minimap and the thumb clusters in canvas units **and points**, the
card's words, any overlap found). The capture script also writes a
`<shot>.json` render report and the full-size PNG; those stay out of the
repository.

| Folder | Device (points) | Scale | Safe area (pt L,T,R,B) |
|---|---|---|---|
| `se/` | 667×375 | @2 | 0,0,0,0 |
| `p14/` | 844×390 | @3 | 47,0,47,21 |
| `max/` | 926×428 | @3 | 47,0,47,21 |
| `ipad/` | 1024×768 | @2 | 0,24,0,20 |

Rendered at each device's full pixel size; stored as JPEG (quality 80), the
@3 phones (`p14`, `max`) at two thirds of their pixel size (2 px per point).
Runner shots: all four sizes; Night Watch shots: `p14`, `ipad`; series
results: `se`, `max`, `ipad` (`max` has no `results_runner_practice`: that
run hit its time limit before the shortened round ended). Every
`_hud.json` here lists `"overlaps": []` and no clipped card words.

Shots (where present in a folder):

| Shot | Shows |
|---|---|
| `runner_0_waters` | You: 0/3 waters, Next: <water> with arrow and metres, Runner pace, goal bar "Team home 0/4 · Need 4 more" + clock |
| `runner_2_waters` | two checked waters, the remaining one suggested |
| `runner_3_waters_return_inside` | "Return inside <dorm>" (two lines), the doors glowing |
| `runner_watch_in_sight_danger` | a Night Watch in plain sight: danger chip "Night Watch in sight · 15 m", the minimap badge |
| `map_runner_watch_in_sight` | expanded map: live Watch badge with facing, legend, Runner pace standings with BOT labels and the help line |
| `map_runner_last_seen_2s` | the same Watch behind a building: hollow mark frozen where last seen, "2s" (the sighting's age is pinned at 2 s by the driver: llvmpipe frames take seconds here and the sighting clock is wall time) |
| `runner_caught` | "Caught by … · back in 6", waters kept, return place, protection; the card's countdown |
| `runner_protected` | "Protected · 2" after the return |
| `runner_home_waiting_for_team` | "Home · 1st to finish · Waiting for team", tracker 1/4 |
| `runner_home_watching_teammate` | then the view follows a teammate ("Watching …" above the Next/Cheer buttons) |
| `urgent_clock` | under 10 s: coral clock with the alarm-clock shape |
| `results_runner_practice` | a real practice result: "Your team lost · Runners lost · Time expired: 1/4 home", your contribution |
| `watch_on_foot` | Night Watch: "Runners home 1/4 · Hold until" + clock, "You: 2 tags · 2 different runners", Tag state, waters to guard |
| `map_watch_runner_in_sight` | the Watch's map: runner badge, own team diamonds, carts |
| `watch_in_cart` | "Driving · hop out to tag" |
| `watch_urgent_clock` | the Watch's clock under 10 s |
| `results_patrol_practice` | the runners' real finishes: "Your team lost · Night Watch lost · 4 runners home" |
| `results_round2_your_team_won_series_tied` | series round: Your team won, contribution, "Series: tied 1st · 1 Round Win", settled rewards (simulated wallet; its challenge lines appear inside the rewards card only once the challenges stream is merged, so they are not in this shot) |
| `results_round3_your_team_lost_last_round` | last round, Night Watch lost; "Series final" |
| `results_final_standings_ties_late_join_away` | final standings: shared places, joined round 3, away 1 |
| `results_round1_your_team_lost_time_expired` | "Time expired: 2/4 home", pending rewards (simulated wallet) |
| `results_cancelled_round_counts_for_nothing` | cancelled: no win, no loss, no rewards |
