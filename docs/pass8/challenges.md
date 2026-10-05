# Pass 8 · Challenges: earn Season XP toward the existing pass

The CHALLENGES workstream of pass 8 (brief §10): three daily and three
weekly role-flexible goals that add **Season XP** to the existing 30-tier
Season Pass, settled by the game service with the verified round they come
from. Rules and numbers: [ECONOMY.md §10](../ECONOMY.md) (and §3 "With
challenges" for the earning model). Evidence:
[../media/pass8/challenges/](../media/pass8/challenges/README.md).

**Status.** Implemented and tested locally: service tests against an
in-memory D1, game tests with the test-double service. **Not live**: the
game service is still not deployed (no build has a service URL), so in the
shipped build the Season Pass shows the honest preview state and no round
moves a challenge. Nothing here claims a live settlement.

## What changed

| Area | Change | Files |
|---|---|---|
| Definitions | `economy.challenges` in the catalogue: version 1, 3 daily × 50 XP (Night Shift 2 active rounds, Campus Contribution 6 credits, Team Effort 1 Round Win), 3 weekly × 150 XP (Campus Regular 10, Pull Your Weight 18, Strong Together 4), 24 h grace, 3 credits a round, the active threshold. Synced to the service; the sync test passes | `game/config/catalogue.json` (economy.challenges only), `service/src/catalogue_data.js` (generated) |
| Active-play evidence | `ActivityMeter`: per human slot, seconds of active play counted by the authoritative simulation (fresh changing input, movement under a steady stick, own objective events; capture/splash/home keep an active player active; 5 s window; nothing for neutral input, stale repeats, a key held against a wall, disconnected or bot-covered slots). Rows carry `active_s` (whole seconds) | `game/src/sim/activity_meter.gd` (new), `game/src/sim/match_sim.gd` (3 lines + 1 field), `game/src/net/net_session.gd` (`_fix_results`: 1 line) |
| Report / digest | Report version 2: rows carry `active_s`, bound into the row digest (`v2`) on both sides; the service bounds it (≤ round, not while away). v1 reports settle as before with no challenge progress. Network protocol 6 → 7 | `game/src/core/economy.gd`, `service/src/economy.js`, `game/src/autoload/wallet_service.gd`, `game/src/net/protocol.gd` (VERSION) |
| Settlement | `challenges.js` runs inside `settle()`'s single batch: per-instance progress (UTC day / Monday week of the registered start, 24 h grace), the bonus once per player + instance (`challenge_bonus` primary key), Season XP grows by exactly this round's new bonus rows, a per-round record (duplicate settlement fails the batch). Snapshot + `GET /v1/challenges`; deletion; sweep | `service/src/challenges.js` (new), `service/migrations/0004_challenges.sql` (new), `service/src/commerce.js` (hooks: report check, keep, settle, snapshot, route, deletion, sweep) |
| Client state | Wallet keeps the service's challenge snapshot: `challenge_cards()`, `challenge_status()`, one pin (`pin_challenge`, `pinned_challenge_text(live_row)`), a round's challenge part in `round_summary()["challenges"]` (pending projection, settled result, practice training, none), `challenge_xp`, `xp_after` with the bonus, `challenge_completed` once per fresh completion | `game/src/autoload/wallet_service.gd`, `game/src/core/round_rewards.gd` (pass-through), `game/src/core/challenge_rules.gd` (new) |
| Season Pass | The side panel gets two pages, **Challenges** (opens first) and **Reward** (a tapped reward). "Challenges · Earn Season XP", the role line once, an honest status when progress isn't available, Daily / Weekly with the local reset time, six cards (name, task, bar, "4/6", "+50 Season XP", done check, pin flag), tap to pin (one), a completion toast once. Header and track untouched | `game/src/ui/season_screen.gd` |
| Results | `ResultsScreen.add_challenge_lines()`: a self-contained block in the rewards card, before the tier bar: "Campus Contribution complete · +50 Season XP" (+ "(pending)"), other goals moved, one honest sentence when nothing counted | `game/src/ui/results_screen.gd` (1 call + 1 static function) |
| Test double / evidence | The dev double settles challenges like the service; a capture scene and script | `game/src/dev/fake_commerce_service.gd`, `game/src/dev/challenges_capture.*`, `tools/capture_pass8_challenges.sh` |
| Docs | ECONOMY.md §3 (model with challenges), §5 (bounds, batch), §8 (offline row), §9 (results keys), §10 (new); service README routes | `docs/ECONOMY.md`, `service/README.md` |

## Decisions

- **Where the section lives.** The V7 Season Pass sizes its cells from the
  height the header leaves; a challenge strip above the track would shrink
  every reward. The challenges share the existing side panel instead (two
  pages, one 44 pt switch), so the header, Claim all and both rows keep
  exactly their V7 measurements (SE: Free y 281-481, Premium 489-689, cells
  160×200, identical to the V7 table) and every action stays one tap away.
  The Challenges page opens first; any reward tap shows its detail.
- **Active play** is evidence the host's simulation already has (fresh
  inputs, positions, events), counted per tick with a 5 s window and
  holds for capture/splash/home, then a single bounded integer in the
  confirmed row. Threshold `min(60 s, 40% of the round)`: generous to real
  play (pauses, captures, hiccups), zero for an idle or merely connected
  player. It gates **challenge progress only**; base Coins and Season XP
  keep their V6 eligibility (present ≥ 60%).
- **Credits** come from the existing row fields (`stamps` = unique required
  waters, `unique_captures` = different runners tagged), capped at 3 a
  round, so repeat tags and duplicate stamps can't count.
- **Bonus delivery** is part of the settlement batch (not a later claim):
  `INSERT OR IGNORE` into `challenge_bonus` (primary key player +
  instance), then `season_progress.xp += SUM(xp of this match's bonus
  rows)`. Concurrent settlements of two rounds can't both deliver it; a
  duplicate settlement of the same round fails as a whole.
- **Periods** follow the registered start's server timestamp; the 24 h
  grace credits a late settlement to its original period once; a round
  started after a reset can only touch the new period, so expired goals
  never take new rounds. The instance row copies goal/XP/set version when
  first touched.
- **Report versioning.** Report v2 / digest v2 add `active_s`; v1 reports
  still settle (no challenge). Protocol 7 so 6 and 7 games don't share a
  party (their digests differ).
- **Pin** is per device (wallet file), one at a time. Progress itself is
  only the service's (any device shows the same).
- **Service off / offline:** one short status and goal previews with no
  bars, counts, completion marks or claim buttons; offline with a current
  snapshot shows "Offline · progress as of …".

## Defect / risk register

| Symptom or risk | Cause | Fix | Evidence |
|---|---|---|---|
| Connection or presence alone would count as play | V6 eligibility only checks away time | `ActivityMeter` + `active_s` + threshold | `test_challenges::test_activity_*`; service `nothing for: inactive play…` |
| A neutral first input never set a baseline, so camera-only play never counted (found by the new sim test) | the anchor was set only on evidence | the first fresh input becomes the baseline | `test_activity_meter_counts_play_not_idling` (19-20 s of 20 counted) |
| A challenge strip would shrink the pass rows | V7 cells size from the remaining height | side-panel page; rows unchanged | `test_season_pass_challenges_fit_with_both_rows_whole`, `test_menus_layout` (unchanged, passing) |
| Long service-off paragraph pushed the cards out of view on the SE (first SE capture, not kept) | a 4-line status and a wrapped heading | one shorter sentence, single-line heading and role line (they shrink to fit) | `10_svcoff_pass_challenges_preview` (two cards in view on the SE) |
| A goal completed in an earlier round was listed again under "Challenges:" on results (first SE capture) | the service reports every goal the round touched | results skip goals done before the round | `05_svcon_test_results_challenge_settled` |
| The emote preview kept replaying while the Reward page was hidden | `_process` checked the node's own visibility | checks `is_visible_in_tree()` | code review |

## How it was verified

- **Service** (`cd service && npm test`): 48 tests pass (6 new in
  `test/challenges.test.mjs`): the catalogue set, UTC days and Monday weeks
  at the boundary millisecond, credits and the active threshold, the schema
  bound; settlement with role flexibility (runner stamps, Night Watch
  distinct tags), the 3-credit cap, progress capped at the goal, bonus once,
  Season XP only (no challenge Coins in the ledger); repeated reports,
  triple confirmations at once, reopened results, another device, and two
  rounds completing the same goal concurrently (one bonus); Sunday 23:57 →
  Monday settlement credited to Sunday and last week, a post-reset round
  only to Monday, the grace's last millisecond vs 1 ms later (daily closed,
  week counted, round still paid), a round after its week's grace (nothing);
  inactive play, a v1 report, implausible `active_s` (over the round, with
  away time, fractional, missing), cancelled, mismatched, away, solo with
  bots, the daily cap; device sync (same snapshot from a new sign-in and
  `GET /v1/challenges`), deletion and sweep. The existing 42 tests
  (including v1 settlement) still pass.
- **Game** (focused suites, headless): `test_challenges` 9 tests (rules,
  evidence rule, the real simulation's meter, service-off/practice honesty,
  a settled round completing goals once with pass progress, results lines,
  the Season Pass at SE / 844×390 / 926×428 / iPad with viewport-delivered
  taps for the tab, a reward and the pin, and the service-off preview);
  `test_catalogue` (digest v2, base XP model, the new challenge model test);
  `test_wallet`, `test_menus_layout`, `test_trust`, `test_rankings`,
  `test_results_layout`, `test_coins`, `test_shop_ui`, `test_series`,
  `test_focus`, `test_v7_screens`, `test_rules`: all pass. (The whole game
  suite and the benches were not run here, as agreed: the integrator runs
  them after merging.)
- **Captures:** the real screens rendered at four device shapes (below).

## Evidence index

`docs/media/pass8/challenges/<device>/` (desktop Linux, Mobile renderer on
llvmpipe; layout and states only). Every service-on picture uses the
**test-double service** and says so on the image and in its file name
(`svcon_test`); `svcoff` is the shipped state.

| Shot | Shows |
|---|---|
| `01_svcon_test_pass_challenges` | Challenges page: Night Shift 1/2, Campus Contribution 4/6 (pinned), Team Effort done, local reset times; Free and Premium whole; Claim all |
| `02_svcon_test_pass_challenges_weekly` | scrolled to the weekly goals and the pin hint |
| `03_svcon_test_pass_reward_detail` | a tapped reward: the Reward page; the track unchanged |
| `04_svcon_test_pass_after_round` | after a settled round: three dailies done, tier 17 (the bonus is in the pass) |
| `05_svcon_test_results_challenge_settled` | results: "Night Shift complete · +50 Season XP", "Campus Contribution complete · +50 Season XP", weekly progress, then the Season tier bar |
| `06_svcon_test_results_challenge_pending` | results while the confirmation is unanswered: "… (pending)", expected rewards not added |
| `07_practice_results_training` | practice: "Training only: 3 contribution credits. Practice doesn't count toward challenges." |
| `10_svcoff_pass_challenges_preview` | service off (as shipped): the short preview status, goal previews without progress |

Measured (each folder's `measure.json`, table in the media README): at
667×375, 844×390, 926×428 and iPad the Free and Premium rows are exactly
V7's (SE 281-481 / 489-689, cells 160×200; 844×390 275-465 / 473-663;
926×428 261-459 / 467-665; iPad 265-505 / 513-753), whole and inside the
safe area in every Pass shot; 3 goal cards wholly in view when the page
opens on phones (2 with the service-off status), 5 on iPad; every tab and
card at least 44 pt; no pressable control cut off in any shot. The SE was
rendered at device pixels; the other three at their canvas size with the
matching point scale (`FAST=1`, the V7 `s1536` approach; same layout,
fewer pixels) because the shared machine was saturated.

## Open items

- **No live settlement yet.** Deploying the service (owner, COMMERCE_SETUP)
  is required before any real round moves a challenge; then run a sandbox
  party of two devices and confirm one round end to end (results line →
  Season Pass progress).
- **The pause / expanded-map row is not wired** (owned by the MATCH
  stream / integrator): call `Wallet.pinned_challenge_text(live_row)`.
- The active threshold (60 s / 40%) and the window (5 s) are first values;
  check them against real rounds once the service is live (the
  `challenge_rounds.active_s` column records them).
- No physical device was used: touch feel and on-device rendering of the
  new page are unverified.
- Peer-host trust limit unchanged (ECONOMY.md §5, §10).

## Exact steps for the integrator

1. Merge this branch; the catalogue change is confined to
   `economy.challenges` (SHOP edits items/products/offers). If both
   branches changed `catalogue.json`, run `node service/tools/sync_catalogue.mjs`
   after resolving and commit `service/src/catalogue_data.js`.
2. Migrations: SHOP adds `0003_*`, this adds `0004_challenges.sql` (no
   dependency on 0003).
3. `commerce.js`: SHOP changes the spend path; this branch touches only
   the header import, `snapshot()`, `checkReport()`, `reportRound()`'s
   kept row, `settle()`, `roundMe()`, the new `getChallenges()`, the router
   line, `deletionStmts()` and `sweepCommerce()`. Keep both.
4. `Protocol.VERSION` is 7 here; if MATCH/integrator also bump, keep 7.
5. `results_screen.gd`: keep the one call
   `add_challenge_lines(v, s.get("challenges", {}) …)` in the rewards card
   before the Season tier bar (or wherever the new hierarchy puts "Earned /
   pending Season XP, challenge completions") and the static function.
6. Pause / expanded map: show `Wallet.pinned_challenge_text(live_row)` when
   non-empty (one row; `live_row` = the local player's `{role, stamps,
   unique_captures}` so far, or `{}`).
7. Run `cd service && npm test`, then `test_challenges`, `test_catalogue`,
   `test_wallet`, `test_menus_layout`, `test_results_layout`.
8. RULES.md / What to Test lines (integrator-owned), suggested:
   - RULES: "Challenges: 3 daily (50 Season XP each) and 3 weekly (150)
     goals reset at 00:00 UTC / Monday 00:00 UTC. Only verified online
     rounds you actively play count (at least 60 s, or 40% of a short
     round, of real input or objective play). Contribution credits: each
     water you splash or different runner you tag, at most 3 a round.
     Practice never counts."
   - What to Test: "Season Pass → Challenges: goals, progress and reset
     times show (service off in this build: a preview). Pin one goal."
9. No new third-party assets or licenses.
