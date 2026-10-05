# Economy: catalogue, products, earning, wallet, Season XP and claims (V6)

This is the economy as implemented in V6. The numbers live in one file,
[`game/config/catalogue.json`](../game/config/catalogue.json): the game reads
it (`Catalogue`, `Economy`) and the service reads a generated copy
(`service/src/catalogue_data.js`, checked by a test and by `deploy.sh`).
Change a number there, run `node service/tools/sync_catalogue.mjs`, and both
sides agree. Everything bought or earned is cosmetic: no item, Coin or tier
changes speed, reach, stealth, hitboxes or score.

**Status.** Implemented and tested locally (game tests with a test-double
service and a simulated App Store; service tests against an in-memory D1 and
a test certificate chain). **Not deployed**: the game service is not running
for any build yet, and no App Store product exists yet. With no service in
the build the game says so: nothing is bought, spent, claimed or settled.
See [COMMERCE_SETUP.md](COMMERCE_SETUP.md) for the owner's steps.

## 1. One currency: Coins

- **Coins** are the only currency the player sees, for earned and purchased
  Coins alike. Internally every change is a ledger row with its source:
  `round`, `apple`, `season_claim`, `legacy_beta`, `coin_purchase`
  (a spend), `refund`, `admin`.
- Purchased Coins **never expire** and **never become XP**: XP comes only
  from verified play (§4), and no code path turns Coins into XP.
- Spending Coins grants an item and nothing else (no XP, no boost).
- The wallet balance can never go negative (a database `CHECK`); a refund of
  Coins that were already spent becomes **debt**, paid from later grants
  before the balance grows (§6).

## 2. Catalogue and stable IDs

| ID form | Meaning | Example |
|---|---|---|
| `<field>:<key>` | a runner item (Cosmetics field and key; the same strings the save's `owned` list has used since V3) | `hat:crown`, `outfit:lantern_scout` |
| `card:<key>`, `badge:<key>` | UI-only profile cosmetics (name card plate, badge emblem) | `card:after_hours` |
| `coins:<n>` | a Coin pack | `coins:1500` |
| `season:<id>:premium` | Season Premium access | `season:s1:premium` |

Kinds: `coin_item` (Shop, Coins), `apple_skin` (Shop, permanent App Store
non-consumable), `coin_pack` (Shop, App Store consumable), `season_premium`
(Shop, Coins), `season_reward` (earned in the pass; never sold under any
ID). Runner options with no catalogue entry and Cosmetics cost 0 are the free
base options everyone owns. The catalogue is versioned
(`catalogue_version`), and the service checks every Coin price against it
(a stale client gets `price_changed`, never a different charge).

### Shop items

| ID | Kind | Price | Notes |
|---|---|---|---|
| `outfit:moonlight_runner` | apple_skin | App Store (localized) | Featured; permanent; Restore Purchases |
| `outfit:starry_sleeper` | apple_skin | App Store (localized) | Featured; permanent; Restore Purchases |
| `outfit:lantern_scout` | coin_item | 1,200 Coins | Featured |
| `outfit:campus_courier` | coin_item | 900 Coins | |
| `outfit:raincoat_explorer` | coin_item | 800 Coins | |
| `outfit:varsity_sprinter` | coin_item | 600 Coins | |
| `outfit:frog`, `outfit:duck`, `outfit:robe` | coin_item | 500 / 450 / 300 | pre-V6 outfits, re-priced into the 300-1,200 band |
| pre-V6 accessories (patterns, colours, trims, hair colours, hats, shoes, Wiggle Dance) | coin_item | 20-240 | unchanged V5 prices |
| `coins:500`, `coins:1500`, `coins:3500` | coin_pack | App Store (localized) | 500 / 1,500 / 3,500 Coins |
| `season:s1:premium` | season_premium | 1,500 Coins | not a subscription; no tier skips |

The art for the six Shop outfits and the Season rewards comes from the art
workstream (`Cosmetics`). An item whose art isn't in `Cosmetics` is never
offered; `test_catalogue::test_every_referenced_item_exists_in_cosmetics`
lists any that are missing (it fails until the art lands).

### App Store products

| Product ID | Type | Delivers |
|---|---|---|
| `com.idlery.ultimatetrifecta.coins.500` | Consumable | 500 Coins |
| `com.idlery.ultimatetrifecta.coins.1500` | Consumable | 1,500 Coins |
| `com.idlery.ultimatetrifecta.coins.3500` | Consumable | 3,500 Coins |
| `com.idlery.ultimatetrifecta.skin.moonlight_runner` | Non-Consumable | `outfit:moonlight_runner` |
| `com.idlery.ultimatetrifecta.skin.starry_sleeper` | Non-Consumable | `outfit:starry_sleeper` |

No real-money price is stored anywhere: the Shop shows StoreKit's localized
`displayPrice`, and a product StoreKit doesn't return shows "Not available",
never a made-up price. Prices are the account holder's choice in App Store
Connect.

## 3. What a round pays

Coins and Season XP are paid only for an **eligible, completed, verified
online round** (§5). The client projects them with the same function the
service settles with.

| Coins | Value |
|---|---|
| Completed the round | 10 |
| Each coin picked up in the round (`coins_picked`, 1 Coin each) | 1 (at most the round's spawns, ≤ 10) |
| Team win | 4 |
| Runner made it home | 3 |
| First runner home | 2 |
| Night Watch: each *different* runner tagged | 1 (at most 3) |

| Season XP | Value |
|---|---|
| Completed the round | 50 |
| Runner: each splash (stamp) | 10 (at most 3) |
| Runner: made it home | 20 |
| Night Watch: each *different* runner tagged | 15 (at most 3) |
| Team win | 15 |

Tagging the same runner again earns nothing more, distinct tags stop counting
after three, and idle survival earns nothing. A round pays at most
10 + 4 + 5 + 10 = 29 Coins and 115 Season XP (`Economy.max_round_coins`).

Lifetime level XP (the "Lv" on the profile chip) stays local and separate:
it keeps the V5 performance values (`RulesConfig` "Rewards" group, practice
x0.5) and never comes from Coins (`RulesLogic.lifetime_xp`).

### The calculation (Premium in 60-120 eligible rounds; Season XP with challenges below)

This is a tuning model, **not a measured rate**: no real eligible rounds have
been played with the service. Assumptions for typical active play (half the
rounds as a runner, half as Night Watch): team wins 50%, runners home 60%,
first home in 1 of 6 runner rounds, 1.5 coins picked up per round (6-10
spawns shared by 8 players, bots included), 1.5 different runners tagged as
Night Watch, 2.2 splashes as a runner.

- Runner round: 10 + 0.5×4 + 0.6×3 + 2/6 + 1.5 = **15.6 Coins**
- Night Watch round: 10 + 0.5×4 + 1.5×1 + 1.5 = **15.0 Coins**
- Average **15.3 Coins** → Premium (1,500) in **≈ 98 rounds**. A strong
  player (wins, home, 3 pickups: ~22) needs ≈ 68; a player who only
  completes rounds (~11) ≈ 136.
- Season XP from the rounds themselves (base): runner 50 + 2.2×10 +
  0.6×20 + 0.5×15 = 91.5; Night Watch 50 + 1.5×15 + 0.5×15 = 80; average
  **85.75 XP** → tier 30 (8,300 XP) in **≈ 97 rounds without challenges**.
- Time: a round is up to 4 minutes of play plus reveal, countdown, loading
  and results, about 4-6 minutes in all, so ≈ 98 rounds is roughly 6.5-10
  hours of play for Premium.

### With challenges (Pass 8)

Challenges (§10) add Season XP to the same pass: at most **150 a day**
(three daily goals × 50) and **450 a week** (three weekly goals × 150).
They change nothing above: not the base table, not the 30 tiers or their
thresholds, not Coins. The Coins → Premium model above is separate and
unchanged (challenges never pay Coins).

The model uses the same assumptions, with every round eligible and actively
played. Per round: 1 active round, **1.85 contribution credits** (half the
rounds 2.2 splashes as a runner, half 1.5 different runners tagged as Night
Watch, never more than 3) and **0.5 Round Wins**. A goal counts as completed
in its period when that period's expected amount reaches it.

| Week | Rounds | Base XP | Daily goals | Weekly goals | Season XP a week | Tier 30 in |
|---|---|---|---|---|---|---|
| Light: 2 days × 3 rounds | 6 | 515 | 200 (Night Shift and Team Effort; 5.6 credits a day is short of 6) | 0 | **≈ 715** | ≈ 11.6 weeks (16.1 without challenges) |
| Typical, the brief's sample: 5 days × 4 rounds | 20 | 1,715 | 750 | 450 | **≈ 2,915** | **≈ 2.85 weeks, ≈ 57 rounds** (97 without) |
| Heavy: 7 days × 8 rounds | 56 | 4,802 | 1,050 | 450 | **≈ 6,302** | ≈ 1.3 weeks, ≈ 74 rounds |

- The brief's illustrative 1,716 + 750 + 450 = 2,916 used 85.8 XP a round;
  the table uses the unrounded 85.75.
- Real weeks vary. With 3 rounds a day, Team Effort completes on 87.5% of
  days (1 − 0.5³); in the light week Strong Together (4 wins in 6 rounds)
  completes in about 34% of weeks (≈ +50 XP on average). Rounds that are not
  active, not eligible or not settled add nothing (§10).
- Challenges are about 28% (light), 41% (typical) and 24% (heavy) of a
  modelled week's Season XP: they speed up the pass most for regular,
  moderate play, and base earning stays the larger part.
- This is a model, not a measured result: no real eligible rounds have been
  played with the service.

`test_catalogue::test_earning_rate_meets_the_pass_target` recomputes the
Coins → Premium rounds (target 60-120) and the base Season XP (85.75 a
round; tier 30 in 70-130 rounds without challenges) from the live table.
`test_catalogue::test_challenges_accelerate_the_pass_as_documented`
recomputes the challenge table above from the live catalogue (150/450 caps,
the light/typical/heavy totals and weeks) and fails if it drifts: the old
"tier 30 in ≈ 97 rounds" now describes base XP only. Re-tune `round_coins`
/ `season_xp` / `challenges` once real playtests measure pickups, role
results and how often goals complete.

## 4. Season 1 · After Hours

30 tiers, a Free and a Premium track. Tier 1 is reached at 0 XP; tiers 2-10
cost 200 XP each, 11-20 cost 300, 21-30 cost 350 (8,300 XP for tier 30).
Premium costs 1,500 Coins in the Shop, is permanent for Season 1, and is
never a subscription. Buying it never adds XP and there are no paid tier
skips.

| Tier | XP | Free | Premium |
|---|---|---|---|
| 1 | 0 | Name card: After Hours | Outfit: Night Owl |
| 2 | 200 | — | 50 Coins |
| 3 | 400 | Hat: Pompom Beanie | Badge: Lantern |
| 4 | 600 | — | Emote: Shush |
| 5 | 800 | 25 Coins | Name card: Lantern Glow |
| 6 | 1,000 | — | 50 Coins |
| 7 | 1,200 | Badge: First Splash | Hat: Headlamp |
| 8 | 1,400 | — | Badge: Crescent Moon |
| 9 | 1,600 | Emote: Stargaze | 50 Coins |
| 10 | 1,800 | — | Shoes: Glow Sneakers |
| 11 | 2,100 | 25 Coins | Name card: Starfield |
| 12 | 2,400 | — | 50 Coins |
| 13 | 2,700 | Name card: Moonlit Quad | Badge: Night Owl |
| 14 | 3,000 | — | Hat: Owl Ears |
| 15 | 3,300 | Outfit: After Hours Hoodie | Outfit: Glow Jogger |
| 16 | 3,600 | — | 50 Coins |
| 17 | 3,900 | Badge: Night Shift | Name card: Library Lamp |
| 18 | 4,200 | — | Emote: Moon Shuffle |
| 19 | 4,500 | Shoes: Moon Boots | 50 Coins |
| 20 | 4,800 | — | Badge: Gold Lantern |
| 21 | 5,150 | 50 Coins | Name card: Glow Track |
| 22 | 5,500 | — | 50 Coins |
| 23 | 5,850 | Hat: Glow Headband | Badge: Trifecta Star |
| 24 | 6,200 | — | 50 Coins |
| 25 | 6,550 | Name card: Dawn Patrol | Name card: Night Sky |
| 26 | 6,900 | — | 50 Coins |
| 27 | 7,250 | Emote: Victory Lap | 50 Coins |
| 28 | 7,600 | — | 50 Coins |
| 29 | 7,950 | — | 50 Coins |
| 30 | 8,300 | Badge: Season 1 Finisher | Outfit: Library Cardigan |

- **Free** (15 rewards): an outfit, 2 hats, 1 pair of shoes, 2 emotes, 3 name
  cards, 3 badges, 100 Coins. **Premium** (30 rewards): 3 outfits, 2 hats,
  1 pair of shoes, 2 emotes, 5 name cards, 5 badges, 600 Coins. Premium
  Coins never pay back the 1,500-Coin pass (tested).
- Outfit, hat, shoe and emote names and meshes come from the art workstream
  (`Cosmetics`); name cards and badges are drawn by the UI
  (`CommerceArt`), shown in the Locker's Profile category and on the profile
  chip. Every reward has art or is tested to need it.
- Rules (service-enforced; mirrored by `Economy.cell_state`):
  - A cell is **locked** until its tier is reached, **Premium-locked** when
    reached without Premium, **claimable**, or **claimed**.
  - Free players progress and claim the Free track without buying.
  - Buying Premium later makes every Premium reward already earned
    claimable at once.
  - Claim and Claim all are idempotent: each (season, tier, track) can be
    claimed once (primary key); repeating does nothing.
  - A reward item already owned (e.g. granted by support) is marked claimed
    with result `already_owned` and is not granted twice.
  - Coins go to the wallet, items to the Locker, permanently.
- Dates: `starts_at` / `ends_at` are server-UTC fields, deliberately `null`
  for this beta: no countdown is shown and purchased access never expires.
  When a later season arrives, Season 1 claims and items stay (they're
  entitlements and claim rows, not season state). The policy for any
  time-limited access must be written before it is sold.

## 5. Eligible rounds and settlement (trust model)

A round pays only when all of this holds (service `commerce.js`):

1. **Registered by the room host at start** (`POST /v1/rounds`): the caller
   is the host of a live service room, the match ID is that room's
   (`<code>-<round>-<seed>`), every participant is a profile admitted to the
   room (admission tokens) and not removed, at most one round per room per
   minute.
2. **Reported by the same host** (`POST /v1/rounds/:id/report`) between 60 s
   and 20 min after the start, with plausible numbers: outcome known; round
   time ≤ 15 min; ≤ 10 coin spawns; per player stamps 0-3, distinct tags
   0-7, coins picked ≤ spawns, the sum of coins picked ≤ spawns, a finish
   only with three stamps, at most one first-home, Night Watch rows without
   runner results, away time ≤ round time; (Pass 8, report version 2) a
   whole number of active seconds no longer than the round and not while
   away (`active_s ≤ round time − away + 2`). Anything else rejects the
   round (`422 implausible`) and writes the audit log for review.
3. **Confirmed by each player's own game** (`POST /v1/rounds/:id/ack`): a
   SHA-256 digest of the row that player's game received
   (`Economy.row_digest` = `economy.js rowDigest`); the service pays a player
   only when it equals the digest of the host's reported row.
4. The player was present (away ≤ 40% of the round) and **at least two
   present humans** took part (bots have no wallets; a host alone with bots
   can't farm).
5. Not cancelled (a cancelled round settles nothing; host loss cancels).
6. **At most 40 rewarded rounds per player per UTC day** (a `CHECK` on
   `daily_rounds`); past it the round is recorded as `capped`.

Settlement is a single D1 batch: the daily count, the ledger grant (key
`round:<match>:<profile>`, unique), the wallet, the Season XP and the round
row, and (Pass 8) the round's challenge progress and any challenge bonus
XP (§10). Re-sent reports, acks and reopened results never pay twice; financial
idempotency lives in the service ledger and is never truncated (the old local
200-entry list is now a stats ledger only).

**Practice and service-off.** Practice never settles into the wallet or the
pass (isolation: an offline simulation can't be verified). Online rooms
without the service ("unverified rooms") can't be settled either. In both
cases results say so; coins picked up are still shown.

**The remaining trust limit (peer-hosted play).** The host's device runs the
simulation. A modified host can report any *plausible* numbers for its round:
for example, every player picking up every coin, or always winning. The
service can't see the match. What bounds it: rows must be possible; two
present, admitted, verified humans must play; each player's own game must
confirm the same numbers; one round per minute per room; 40 rewarded rounds
a day; at most 29 Coins a round. Two colluding accounts on two devices could
therefore earn up to about 40 × 29 = 1,160 Coins a day each, against about
15/round in honest play. That is accepted for a cosmetic-only beta, recorded
in the audit log, and reviewable; it is **not** anti-cheat. A dedicated
server simulation would be the real fix.

## 6. Wallet, ledger and transactions

- **Wallet** per verified profile and deployment environment: balance
  (`CHECK >= 0`), refund debt, a revision bumped by every change, and the
  StoreKit `appAccountToken` (UUID). The app shows the last snapshot it
  received; an older revision never replaces a newer one.
- **Ledger** append-only, one row per grant/spend/revoke with a unique
  idempotency key per environment and the balance and revision after it.
  Rows are never updated or deleted (profile deletion clears only the
  profile link).
- **Spend** (`POST /v1/wallet/spend`): one batch debits, writes the ledger
  and inserts the entitlement (Season Premium also sets the season's
  Premium flag). An overdraw violates the `CHECK`, an owned item violates
  the primary key, a repeated key violates the ledger's unique index: in
  each case the whole batch rolls back. A replay of the same key returns the
  first result. Concurrent purchases are tested.
- **Client outbox**: every operation is written to `user://wallet.json`
  with its idempotency key *before* it's sent. No answer (a timeout is not a
  "no") keeps it queued and retried on sign-in, resume and every 20 s, so it
  completes once. Operations of another profile wait for that profile.
- **App Store delivery**: see [COMMERCE_SETUP.md](COMMERCE_SETUP.md) §3.
- **Refunds and revocations** (from the transaction or an App Store Server
  Notification): a refunded Coin pack takes back its Coins, as much as the
  balance holds, the rest becoming debt; a refunded direct skin is revoked.
  Nothing else changes: Coin-bought items, earned items and claims stay.
  Support can forgive debt (`/v1/admin/wallets/:id/adjust`).

## 7. Migration of pre-V6 saves

- Save version 4 freezes the V5 balance, unlocks and round counts in
  `legacy` once (migrating again changes nothing; tested twice). The
  appearance and all unlocks are kept and stay usable offline as "this
  device's" unlocks.
- Once signed in, the wallet asks the service to **import it once per
  account** (and once per Game Center player, even after deleting and
  recreating a profile): Coins bounded by what the local round counts could
  have earned (75 per online round, 38 per practice round) and capped at
  **2,000**; items only from the pre-V6 Coin catalogue (never Shop skins or
  Season rewards). Source `legacy_beta`, audited. An edited local save can't
  mint more than that cap, and only once.
- Until then the Coins chip shows the device's pre-V6 balance ("on this
  device"); it can't be spent without the service.
- Lifetime level and stats stay separate from Season 1.

## 8. Offline and service-off behaviour

| | Service off (this build) | Configured, offline | Online |
|---|---|---|---|
| Play, practice, Locker | yes | yes | yes |
| Owned items | free + pre-V6 + verified App Store skins | + last account snapshot | account |
| Coins shown | pre-V6 balance (this device) | last verified balance | live |
| Spend, claim, buy | unavailable, says why | unavailable, says why | yes |
| Round rewards | not added (said on results) | queued confirmation, settled later | settled |
| Challenges (Pass 8) | goal previews, no progress, "Preview" status | last known progress for the current period ("Offline · progress as of …"), else previews | live |

## 9. Results interface

`Wallet.round_summary(match_id)` (also returned by `Save.apply_results` as
`reward["wallet"]`, and refreshed through `Wallet.round_updated(match_id)`):

| Key | Meaning |
|---|---|
| `state` | `settled`, `pending`, `practice`, `cancelled`, `not_eligible`, `no_service`, `unverified_room`, `capped`, `mismatch`, `rejected`, `unknown` |
| `reason` | for `not_eligible`: `away`, `few_humans`, `bot`, … |
| `message` | one honest sentence for the results screen |
| `coins_collected` | coins picked up this round (always shown) |
| `coins`, `coins_projected` | settled Coins (0 until settled), projection |
| `season_xp`, `season_xp_projected` | settled XP, projection |
| `xp_before`, `xp_after`, `tier_before`, `tier_after`, `frac_before`, `frac_after` | Season progress for the bar |
| `lines`, `season_lines` | the breakdown ([label, amount]) |
| `final` | false while pending |
| `challenge_xp` | Pass 8: challenge bonus Season XP this round added (0 until settled; `xp_after` includes it) |
| `challenges` | Pass 8: the round's part in challenges: `state` (`settled`, `pending`, `practice`, `none`), `result` (`applied`, `inactive`, `no_evidence`, `closed`), `xp`, `lines` ([{id, name, period, progress, goal, inc, completed_now, xp}]), `message` (§10) |

## 10. Challenges (Pass 8)

Three daily and three weekly goals that add **Season XP to the existing
pass**. No new currency, no boost, no claim button, nothing to buy; Premium,
Coins and purchases never advance a goal. Definitions:
`economy.challenges` in the catalogue (copied to the service like every
other number). Rules: `service/src/challenges.js` (the authority) and
`game/src/core/challenge_rules.gd` (the same rules for display).

| Period | Goal | Requirement | Metric | Reward |
|---|---|---|---|---|
| Daily | Night Shift | Play 2 online rounds (active) | active rounds | 50 Season XP |
| Daily | Campus Contribution | Earn 6 contribution credits | credits | 50 Season XP |
| Daily | Team Effort | Win 1 round, either role | Round Wins | 50 Season XP |
| Weekly | Campus Regular | Play 10 online rounds (active) | active rounds | 150 Season XP |
| Weekly | Pull Your Weight | Earn 18 contribution credits | credits | 150 Season XP |
| Weekly | Strong Together | Win 4 rounds, either role | Round Wins | 150 Season XP |

Every player gets the same six goals; all are role-flexible ("Splash
waters or tag different runners."), so nobody has to quit or re-roll to
become the Night Watch. There are no distance, near-miss, spam or
repeat-tag goals.

### What a round adds

Only an **eligible, verified, completed online round** (§5: registered by
the host, reported plausibly, confirmed by the player's own game, present,
two humans, not cancelled, under the daily cap) that the player **actively
played**. It then adds, to each goal of its day and week:

- **1 active round**;
- **contribution credits**: each unique required-water stamp and the first
  valid tag of each different runner (the row's `stamps` +
  `unique_captures`), **at most 3 a round**. Tagging the same runner again,
  a duplicate stamp, a repeated report or confirmation adds nothing;
- **1 Round Win** when the player's team won (either role).

Progress stops at the goal; a completed goal takes nothing more.

**Nothing** from practice, the tutorial, service-off builds, unverified
rooms, cancelled rounds (host loss cancels), mismatched or rejected rows,
away or bot-only rounds, capped rounds, or a round without active play.
Practice results may show labelled training feedback ("Training only: 2
contribution credits. Practice doesn't count toward challenges."); it is
never imported later.

### Active participation (report version 2)

A connection, or being "present", doesn't prove play. The host's
simulation counts each human slot's **active seconds** (`ActivityMeter`,
`game/src/sim/activity_meter.gd`) and reports them in the row as
`active_s`:

- **Evidence**, per playing tick, for a slot a person controls (connected,
  no bot covering it): a fresh input (one that arrived for that tick, never
  the host's repeat of the last one) with a button press, a stick, steering
  or pedal change of more than 0.12, or a camera turn of more than about
  2° since the last evidence; or a steady stick that actually moves the
  player at 1 m/s or more; or one of their own objective events (a water
  stamp, a home finish, a tag on a runner, a coin).
- A tick is **active within 5 s** (`active.window_s`) of evidence, which
  absorbs packet gaps. Being **captured, splashing or home** keeps an
  active player active (they can't act then). A pause menu, idling, a
  neutral input every tick, a key held against a wall, a stale repeated
  input or a bare connection gather nothing; a disconnected or bot-covered
  slot counts nothing until fresh evidence after it returns.
- **Threshold:** a round counts when `active_s ≥ min(60 s, 40% of the round
  time)` (`active.min_s`, `active.min_share`): 60 s of a 4-minute round;
  40 s of a 100 s round. A real player clears it easily while tolerating
  captures, splashes, a short pause and network hiccups.
- **Bounded and confirmed:** `active_s` is a whole number of seconds; the
  service refuses a row with more than the round or with active plus away
  time over the round (`422 implausible`, audited). It is part of the row
  digest (`Economy.row_canonical` = `economy.js rowCanonical`, version
  `v2`), so each player's own game confirms it.
- **Compatibility:** the host reports `report_version: 2`. A version 1
  report (an older game) still settles Coins and Season XP as before but
  moves no challenge (`no_evidence`). The network protocol is 7: a 6 and a 7
  game can't share a party, because their row digests differ.

### Periods, resets and the grace

- A round belongs to the **UTC day** (reset 00:00 UTC) and the **UTC week**
  (reset Monday 00:00 UTC) of its **registered start**, the service's own
  timestamp (`rounds.started_at`). The device's clock, time zone or date
  never decide anything; the local reset time on screen is presentation
  only.
- **Grace: 24 h** (`grace_s`). A round that started before a reset and
  settles after it (a late confirmation, an offline queue) is credited to
  its **original** period, once, until 24 h after that period ended. Later,
  that period takes nothing (`closed`; the round still pays its Coins and
  Season XP, and an open week still counts).
- A round that starts after a reset belongs to the new period, so an
  **expired goal never takes a new round**.
- A completed goal's bonus is delivered in the settlement that completed
  it; an accepted reward is never undone by a refresh, a reset or a new
  device, and goals still within their grace stay visible ("recent").

### Settlement, idempotency and storage

The challenge statements run inside the round's settlement batch (§5), so
Coins, Season XP, challenge progress and the bonus land together or not at
all (`service/migrations/0004_challenges.sql`):

- `challenge_progress`: one row per player and **challenge instance**
  (`d:2026-10-05:campus_contribution`, `w:2026-10-05:pull_your_weight`, the
  week by its Monday), with the period, the goal, XP and set version copied
  when first touched (a later catalogue change never rewrites a running
  goal), the progress (`CHECK 0 ≤ progress ≤ goal`) and completion time.
- `challenge_bonus`: the bonus, **primary key player + instance**: inserted
  once (`INSERT OR IGNORE`) when the instance reaches its goal; the batch
  then adds exactly the bonus rows this round created to `season_progress`.
  Two rounds settling at once can't both deliver it.
- `challenge_rounds`: what each settled round did (primary key player +
  match: a duplicate settlement fails its whole batch), plus the round's
  result on `round_players` for its results screen.
- Repeated reports, confirmations, reconnects, reopened results and service
  retries replay the first result; tests cover each.
- The snapshot (`GET /v1/wallet` and `GET /v1/challenges`) carries the
  current instances (untouched ones at 0), recent ones in their grace, the
  server time and the next resets: any device signed in to the profile
  (reinstall, a second device) shows the same progress. Deleting the
  profile deletes its challenges; the sweep drops instances 30 days after
  their grace.

### In the game

- **Season Pass:** the side panel has two pages, **Challenges** and
  **Reward**. "Challenges · Earn Season XP" opens first: the role line,
  Daily and Weekly with their local reset time, one card per goal (name,
  task, progress bar and "4/6", "+50 Season XP", a check when done) and one
  optional pin (tap a goal; one at a time, kept on this device). Tapping a
  reward shows its detail. The header and the track are unchanged: Free
  and Premium stay whole, Claim all stays where it was.
- **Service unavailable:** one short status ("Preview: no game service in
  this build. No progress or Season XP is added.", or signed out /
  offline / checking) and readable goal previews without progress bars,
  counts, completion marks or claim buttons.
- **Results:** "Campus Contribution complete · +50 Season XP" (marked
  "(pending)" until the service settles the round), the other goals the
  round moved, an honest line when it didn't count, then the Season tier
  bar including the bonus (`Wallet.round_summary(match_id)["challenges"]`,
  §9).
- **Pinned goal:** `Wallet.pinned_challenge_text(live_row)` returns one line
  for the pause / expanded map ("Campus Contribution 4/6 · +50 Season XP",
  with "· +2 this round (provisional)" during a round when the player's row
  so far is passed; "" when nothing is pinned).
- A completion the service reports is announced once (a short toast on the
  Season Pass), never every frame.

### The trust limit

Unchanged from §5: the host's device runs the simulation, so a modified or
colluding host can report plausible activity, stamps, tags and wins. What
bounds challenges: everything in §5, at most 3 credits a round, the active
time can't exceed the round or overlap away time, and challenges add at most
150 Season XP a day and 450 a week, never Coins. It is not anti-cheat.
