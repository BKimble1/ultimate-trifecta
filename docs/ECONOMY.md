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

### The calculation (target: Premium in 60-120 eligible rounds)

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
- Season XP: runner 50 + 2.2×10 + 0.6×20 + 0.5×15 = 91.5; Night Watch
  50 + 1.5×15 + 0.5×15 = 80; average **85.8 XP** → tier 30 (8,300 XP) in
  **≈ 97 rounds**.
- Time: a round is up to 4 minutes of play plus reveal, countdown, loading
  and results, about 4-6 minutes in all, so ≈ 98 rounds is roughly 6.5-10
  hours of play for either goal.

`test_catalogue::test_earning_rate_meets_the_pass_target` recomputes this from
the live table and fails if it leaves 60-120. Re-tune `round_coins` /
`season_xp` once real playtests measure pickups and role results.

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
   runner results, away time ≤ round time. Anything else rejects the round
   (`422 implausible`) and writes the audit log for review.
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
row. Re-sent reports, acks and reopened results never pay twice; financial
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
