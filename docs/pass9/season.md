# Pass 9 · Season 1 to tier 100

The PASS100 workstream of Pass 9 (brief §6): the existing **Season 1 · After
Hours** pass extended from 30 to 100 tiers, in the same season with no
reset, with **Record Breaker** at Premium tier 50 and **Dr. Doom** at Premium
tier 100. Rules, tables and the pacing model:
[ECONOMY.md §4](../ECONOMY.md#4-season-1--after-hours). Evidence:
[../media/pass9/season/](../media/pass9/season/README.md).

**Status.** Implemented and tested locally: service tests against an
in-memory D1 (`service/test/season.test.mjs`), game tests through the real
wallet and Season Pass with the test-double service
(`game/tests/test_season100.gd`, `test_catalogue`), captures with the
test-double service, labelled. **Not live**: the game service is still not
deployed and no build has a service URL, so in the shipped configuration the
pass is the honest preview (browse every tier, nothing claimable). Nothing
here claims a live unlock. The two skins' **art** comes from the SKINS9
stream (`Cosmetics` keys `record_breaker`, `dr_doom`): on this branch alone
the pass shows their neutral picture and says "Preview not available in this
build."; with the art merged the same code shows the real portraits and the
live, slowly swaying preview (the path is tested and captured with a stand-in, see
below).

## What changed

| Area | Change | Files |
|---|---|---|
| Catalogue | Version 3. `seasons.s1`: 100 explicit tiers (1-30 byte-for-byte as version 2; 31-100 at 350 Season XP each, each `"added_in": 3`), `milestones` [30, 50, 100], `featured` [50, 100], the `_tiers` note. Items: `outfit:record_breaker` and `outfit:dr_doom` (`season_reward`, `name`, `blurb`, `includes`), 6 name cards and 6 badges (one the tier-100 completion badge `badge:s1_legend`). Service copy regenerated | `game/config/catalogue.json`, `service/src/catalogue_data.js` (generated) |
| Service | Claims: every requested cell answered (`claimed` with `result` and `reward`, `skipped` with a reason); a claim may name the reward its game showed (`reward_changed`, nothing granted, when the table differs); up to every cell of the table per request (was 60); claim rows record the catalogue version. Snapshot: per season `tiers` (the last tier this service grants) and `tier` | `service/src/commerce.js`, `service/src/economy.js` (`maxTier`, `rewardKey`) |
| Migration | `0005_season_100.sql`: `season_claims.catalogue_version` (audit only). No data rewrite is needed (below) | `service/migrations/0005_season_100.sql` |
| Client rules | `Economy.tier_xp`, `tiers_in_version`, `has_reward`, `next_reward_tier`, `progress_runs`, `reward_key`; `claimable(…, upto)`. `Catalogue.season_milestones`, `season_featured`, `tier_added_in`, `includes_text` | `game/src/core/economy.gd`, `game/src/core/catalogue.gd` |
| Wallet | `service_tiers(sid)` (from the snapshot's `tiers`, else an older service's catalogue version); claimable cells stop at it and skip cells whose claim is queued (`claim_pending`); Claim all sent in batches of 60 (each its own outbox operation and key); claims name their reward; `claim_note` explains a service-side mismatch; an older service's reply without `skipped` is understood | `game/src/autoload/wallet_service.gd` |
| Season Pass | Navigation row (You're at Tier N; Next reward · Tier N · XP; milestones 30, 50, 100 with the featured skins' faces); progress runs as one compact column each ("36–39", a step per tier, "No reward"); featured-skin detail (description, includes, live preview swaying around its three-quarter view when the art is in the build, a neutral picture and a plain note when not); progress-run detail with "Show Tier N"; new cell states `pending` ("Claiming…") and `service_update`; jumps glide (Reduced Motion: land at once); "Tier N / 100" with a "Season Pass tier" accessibility name | `game/src/ui/season_screen.gd` |
| Drawing | A stopwatch emblem; a card can name its motif in the catalogue | `game/src/ui/commerce_art.gd` (additive) |
| Shop | "100 tiers you earn by playing"; "44 Premium rewards over 100 tiers: …" (counts from the table) | `game/src/ui/shop_screen.gd` (2 lines) |
| Test double / evidence | The double claims as the service does (answers, `reward_changed`, an "older service" mode, a reward override); a capture scene and script | `game/src/dev/fake_commerce_service.gd`, `game/src/dev/season100_capture.*`, `tools/capture_pass9_season.sh` |
| Tests | Service: 8 new tests. Game: `test_season100.gd` (13 tests), `test_catalogue` (table, extension, boundaries, pacing), `test_shop_ui` (column count) | `service/test/season.test.mjs`, `game/tests/test_season100.gd`, `game/tests/test_catalogue.gd`, `game/tests/test_shop_ui.gd`, `game/tests/data/season_s1_v2.json` |
| Docs | ECONOMY.md §2, §3, §4 (rewritten: both tables, pacing, rules, claim protocol, mismatch, migration), §8, §10; service README; COMMERCE_SETUP 8d | `docs/ECONOMY.md`, `service/README.md`, `docs/COMMERCE_SETUP.md` |

## Pacing model and table

From the actual earning numbers (85.75 base Season XP a typical eligible
round; challenges at most 150 a day and 450 a week) and the three modelled
weeks already used for challenges. A round is 4-6 minutes in all. A model,
not a measurement: no real eligible round has been played.

| Player | Week | Season XP / week | Tier 50 (15,300) | Tier 100 (32,800) |
|---|---|---|---|---|
| Modest | 2 days × 3 rounds | ≈ 715 | 21.4 weeks · 128 rounds · 8.6-12.8 h | 45.9 weeks · 275 rounds · 18.4-27.5 h |
| Regular | 5 days × 4 rounds | ≈ 2,915 | **5.25 weeks · 105 rounds · 7.0-10.5 h** | **11.25 weeks · 225 rounds · 15-22.5 h** |
| Frequent | 7 days × 8 rounds | ≈ 6,302 | 2.4 weeks · 136 rounds · 9.1-13.6 h | 5.2 weeks · 291 rounds · 19.4-29.1 h |
| Base XP only | no challenges | 85.75 / round | 178 rounds | 383 rounds |

**Choice.** Targets: a regular player finishes inside a 12-week horizon (the
written Shop schedule's length; a common season length) with Record Breaker
near the middle; later tiers never cheaper than tiers 21-30 (350); no
multiple of the old cap. Candidates per tier for 31-100: 300 (10.1 regular
weeks, cheaper than 21-30: rejected), **350 (11.25 weeks: chosen)**, 400
(12.45: misses), a +50-per-ten-tiers ramp to 700 (16.1: a late grind), the
old cap × 100/30 (27,667 XP: arbitrary). Modest players are not expected to
finish in one season (tier 30 stays at 11.6 weeks for them); with no season
end date set, nothing expires.

**Rewards.** Tiers 1-30 front-load rewards (one on almost every tier); from
31 a reward pair on every fifth tier (1,750 Season XP apart, about 12
regular rounds), progress tiers between. Free +14 (7 × 50 Coins, 3 name
cards, 4 badges incl. the tier-100 Season 1 Legend); Premium +14 (7 × 75
Coins, 2 skins, 3 name cards, 2 badges). Totals: Free 29 rewards (450
Coins), Premium 44 (1,125 Coins, 75% of the pass price: never pays it back).
No item is granted by two cells; no existing priced Cosmetics item was
available (all are sold in the Shop or granted in tiers 1-30), so the
lightweight additions are new name cards and badges drawn by `CommerceArt`.
`test_catalogue::test_pass_to_tier_100_pacing_model` recomputes the table.

## Migration cases

Nothing is rewritten: `season_progress.xp` was never capped, claims are keyed
by (season, tier, track) and tiers 1-30 are identical in both tables.

| Case | Result | Tested |
|---|---|---|
| 12,000 Season XP (3,700 past the old cap), Premium, every tier 1-30 claimed, 700 Coins | XP 12,000 kept; tier 40 (recomputed); 45 claims, items, Premium, Coins kept; claimable exactly 35 and 40 (both tracks); Claim all grants those once (+125 Coins); old cells answer `already_claimed` | service `a 30-tier-era account…`; game `test_a_30_tier_account_keeps_everything…` |
| Migration 0005 on a database with 30-tier-era rows | every claim row unchanged, the new column NULL; XP and Premium untouched | service `migration 0005 keeps every 30-tier-era row…` |
| A round settled at 8,290 XP | the whole round's XP recorded past 8,300 (no cap), tier 30 → 30/31 by the table | service `a verified round settles Season XP past the old last tier` |
| The wallet cache an older game wrote (catalogue version 2, XP 9,000) read offline | tier 32 shown; nothing past 30 offered from that snapshot; claims kept | game `test_an_old_cached_wallet_is_read_safely` |
| Library Cardigan, Season 1 Finisher | stay at Premium/Free 30, owned; a separate `badge:s1_legend` at Free 100 | both sides |
| Premium entitlement, 1,500-Coin price | unchanged (`season:s1:premium`); buying adds no XP | both sides |

## Idempotency and mismatch cases

| Case | Result | Tested |
|---|---|---|
| Repeat Claim / Claim all | nothing more; `already_claimed`; Coins once (ledger key per cell) | service, game |
| Reply lost after the service applied the claim | the operation stays in the outbox (shown "Claiming…", never queued twice), survives a restart, is retried with the same key, answered `already_claimed`; once on the service | game `test_claims_survive_lost_replies…` |
| Offline, then back | queued, sent on refresh, granted once | game |
| Two devices claiming at once | one grant per cell (primary key; the loser recomputes) | service `claims are idempotent…` (concurrent requests) |
| Reinstall / a second device | claimed cells, items, Premium come back from the snapshot; nothing claimable again | both |
| Whole 100-tier Claim all | game: 73 cells in two requests of ≤ 60 (an older service answers each); service: up to every cell in one request | both |
| Premium, one XP short of tier 50 | Record Breaker `locked`; a forced claim grants nothing | both |
| 40,000 XP without Premium | tier 100 Free badge only; Dr. Doom `premium_required` | both |
| An older (catalogue 2, 30-tier) service | the game knows (no `tiers`, version 2): tiers 31-100 show "Earned" + "the game service hasn't been updated for this tier", Claim all counts what it can grant; a forced claim's silent reply is explained | game `test_an_older_service…` |
| A cell whose reward differs on the service | `reward_changed`, nothing granted, the game says "Update the game to see it" | both |
| An older (30-tier) game against this service | its tier 1-30 claims (no reward names, ≤ 60 cells) get the identical rewards; tiers 31-100 never appear in it; unknown items and claims in its snapshot are ignored (its Locker lists only what it knows) | service `another catalogue…`; game (the double's old-format body) |
| Unknown tier (0, 101) or a progress tier | `no_reward` | service |
| The skin already owned (support grant) | recorded `already_owned`, never granted twice | service |

## UI decisions

- **Navigation row.** A 100-tier strip needs a way to move; the row sits on
  top of the track panel (one 44 pt row). It costs the reward rows some
  height (iPhone SE cells 160×200 → 122×153; 844×390 → 116×145; 926×428 →
  125×157; iPad unchanged at 192×240): every cell stays a whole 44 pt target
  with Free and Premium whole. The Pass 8 decision (challenges in the side
  panel, not a strip) stands; navigation belongs with the track.
- **Progress runs.** 56 progress tiers would be 56 columns of empty cells;
  each run is one narrow column with a step per tier (reached, your tier,
  ahead) and "No reward": 58 columns instead of 100, nothing advertised
  that isn't there, your tier still visible inside a run.
- **Featured preview.** The milestone chips for 50 and 100 show the skin's
  face (Portraits "head" framing) and the detail shows the real skin on the
  existing live preview (the emote preview's runner, framed head to shoes like the
  Locker's outfit pictures, swaying ±49° around its three-quarter view so
  the face stays in the key light; Reduced Motion: still).
  Without the art: a neutral head on the chip, the neutral silhouette in the
  cell and the detail with "Preview not available in this build." drawn in
  the picture: never a fake preview.
- **One Claim.** Claim all stays in the header and the detail has the one
  Claim; navigation never claims; a queued claim shows "Claiming…"
  (disabled), an un-grantable one "Claim" disabled with its reason.
- **Lock reasons in view.** On the SE the detail's state (the lock reason or
  "Reached. Premium (1,500 Coins in the Shop) unlocks it", three lines) is placed before the description and the
  picture is capped to 30% of the page, so it is visible without scrolling;
  the progress-run detail drops its picture on short panels.
- **Season tier vs lifetime level.** "Tier N / 100" (accessibility: "Season
  Pass tier N of 100"); "You're at Tier N" says "Season Pass Tier"; the
  lifetime "Lv" and results' "Level up!" are untouched.

## Defect / risk register

| Symptom | Reproduction | Measured cause | Change | Evidence |
|---|---|---|---|---|
| On the iPhone SE the side panel ran past the screen edge with a long action ("Get Premium in the Shop"), and stayed wide | SE, Premium-locked reward (also in V7's own SE capture `docs/media/v7/menus/after/se/13_…`) | the action's minimum width (318) exceeded the panel's room (291), and the detail labels then took their width from the widened panel, keeping it wide | widths from the region the panel lives in (never grows); the action's label steps down a size instead of widening the panel | `07_…premium_locked` (SE, now inside); `test_season100::test_navigation…` (panel inside the safe area at every jump) |
| The progress overline ("TIERS 41–44 · PROGRESS TIERS") widened the panel | SE, a run's detail | an unwrapped label | shorter text, fit to the width | `02_svcon_test_nav_current_run` |
| "No reward" clipped in the narrow run column | SE first capture | fixed 17 px text in 86 units | fits the size, or two lines | `01`, `02` |
| A featured skin's lock reason was below the fold on the SE | first SE capture | picture + note + description above the state | state before the description, picture capped, note drawn in the picture | `03`, `07` |
| A 100-tier Claim all would be cut at 60 cells by the version 2 service | code audit (`b.claims.slice(0, 60)`) | a 30-tier assumption | service: up to every cell; game: batches of 60 | both suites |
| Claiming tier 50 against a service not yet updated would show a dead "Claim" | audit | the client couldn't know the service's table | `tiers` in the snapshot; catalogue version fallback; `service_update` state | `11_svcon_test_old_service_tier50`; `test_an_older_service…` |
| An expected-reward mismatch could grant something the player wasn't shown | audit | claims named only (tier, track) | the claim names its reward; `reward_changed` | service, game |
| A refresh of the pass read the wallet's Season state a few hundred times | audit | per-cell reads | read once per frame (`season()`) | code review |

## How it was verified

- **Service** (`cd service && npm test`): 68 tests pass (8 new in
  `test/season.test.mjs`); the existing 60 (including the V6 Season test
  with its 30-tier body) unchanged and passing.
- **Game** (focused suites, headless): `test_season100` 13 tests;
  `test_catalogue` (all but `test_every_referenced_item_exists_in_cosmetics`,
  which lists `outfit:record_breaker` and `outfit:dr_doom` until SKINS9's
  Cosmetics entries merge, as expected), `test_wallet`, `test_challenges`,
  `test_menus_layout`, `test_v7_screens`, `test_shop_ui`, `test_purchases`,
  `test_coins`: pass. The whole suite and the benches were not run here
  (the integrator runs them after merging).
- **Captures:** the real Season Pass at four device shapes (below).

## Evidence index

`docs/media/pass9/season/<device>/` (desktop Linux, Mobile renderer on
llvmpipe; layout and states only, not frame rate or touch). Every service-on
picture uses the **test-double service** and says so on the picture and in
its name (`svcon_test`); `svcoff` is the shipped state. See the media README
for the shot list and the measured rows.

## Open items

- **Art.** Until SKINS9 merges, Record Breaker and Dr. Doom show a neutral
  picture and the note; after the merge, re-run
  `tools/capture_pass9_season.sh` to capture the real portraits and the
  live preview (shot 12, the stand-in, then drops out by itself).
- **No live service.** Deploying (owner, COMMERCE_SETUP) applies migration
  0005 with the others; tiers 50 and 100 then need real play (or a sandbox
  database edit for QA, COMMERCE_SETUP 8d). No sandbox claim has happened.
- The pacing is a model; re-tune after real rounds (the per-tier step can
  change only for tiers nobody has reached; never for reached tiers).
- No physical device: the navigation row's touch feel and the live preview
  on a phone GPU are unverified.

## Exact steps for the integrator

1. Merge `p9-pass100`. `game/config/catalogue.json` (version 3) and the
   generated `service/src/catalogue_data.js` are this branch's; if another
   branch touched the catalogue, resolve it and run
   `node service/tools/sync_catalogue.mjs` and
   `python3 tools/make_offer_schedule.py --check`.
2. After SKINS9's `Cosmetics` entries for `record_breaker` and `dr_doom`
   land, `test_catalogue::test_every_referenced_item_exists_in_cosmetics`
   must pass, and `test_season100::test_progress_runs_featured_preview…`
   takes its "art in the build" branch (the live preview).
3. Re-capture: `FAST=1 tools/capture_pass9_season.sh docs/media/pass9/season/raw se p14 pmax ipad`
   and convert as the media README says (the pictures then show the skins).
4. Release notes / what to test (owned by the integrator): "Season Pass now
   has 100 tiers: Record Breaker at Premium 50, Dr. Doom at Premium 100;
   earlier progress, claims and Premium are kept. Try You're at / Next
   reward / 30 · 50 · 100 above the track."
