# Economy: catalogue, products, earning, wallet, Season XP and claims (V6, Pass 8 Shop)

This is the economy as implemented in V6, with the Pass 8 Shop changes
(scheduled rotating offers, §2.1; six Coin packs). The numbers live in one file,
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
ID). Pass 8: a `coin_item` with `"rotation": true` is sold **only through a
scheduled rotating offer** (§2.1); its item ID is still the permanent
entitlement. Runner options with no catalogue entry and Cosmetics cost 0 are the free
base options everyone owns. The catalogue is versioned
(`catalogue_version`), and the service checks every Coin price against it
(a stale client gets `price_changed`, never a different charge).

### Shop items

| ID | Kind | Price | Notes |
|---|---|---|---|
| `outfit:moonlight_runner` | apple_skin | App Store (localized) | Always available; permanent; Restore Purchases |
| `outfit:starry_sleeper` | apple_skin | App Store (localized) | Always available; permanent; Restore Purchases |
| `outfit:midnight_mechanic` | coin_item, rotation | 900 Coins | Pass 8, new; rotating offers only |
| `outfit:moonwalk_cadet` | coin_item, rotation | 1,200 Coins | Pass 8, new; rotating offers only |
| `outfit:pumpkin_pajamas` | coin_item, rotation | 800 Coins | Pass 8, new; rotating offers only |
| `outfit:arcade_sprinter` | coin_item, rotation | 900 Coins | Pass 8, new; rotating offers only |
| `outfit:cloud_nine` | coin_item, rotation | 1,000 Coins | Pass 8, new; rotating offers only |
| `outfit:bedtime_bandit` | coin_item, rotation | 1,000 Coins | Pass 8, new; rotating offers only |
| `outfit:lantern_scout` | coin_item, rotation | 1,200 Coins | V6; moved into the rotation in Pass 8 |
| `outfit:campus_courier` | coin_item, rotation | 900 Coins | V6; moved into the rotation in Pass 8 |
| `outfit:raincoat_explorer` | coin_item, rotation | 800 Coins | V6; moved into the rotation in Pass 8 |
| `outfit:varsity_sprinter` | coin_item, rotation | 600 Coins | V6; moved into the rotation in Pass 8 |
| `outfit:frog`, `outfit:duck`, `outfit:robe` | coin_item | 500 / 450 / 300 | pre-V6 outfits; always available |
| pre-V6 accessories (patterns, colours, trims, hair colours, hats, shoes, Wiggle Dance) | coin_item | 20-240 | unchanged V5 prices; always available |
| `coins:250`, `coins:500`, `coins:1000`, `coins:1500`, `coins:3500`, `coins:7500` | coin_pack | App Store (localized) | 250 / 500 / 1,000 / 1,500 / 3,500 / 7,500 Coins (250, 1,000, 7,500 new in Pass 8) |
| `season:s1:premium` | season_premium | 1,500 Coins | not a subscription; no tier skips |

The art for every Shop outfit and the Season rewards comes from the art
workstream (`Cosmetics`). An item whose art isn't in `Cosmetics` is never
offered; `test_catalogue::test_every_referenced_item_exists_in_cosmetics`
lists any that are missing (it fails until the art lands: in the Shop
branch of Pass 8 the six new outfits are listed until the skins stream's
`Cosmetics` entries merge).

### 2.1 Rotating offers (Pass 8)

**Data model.** An offer is separate from the item it sells:

| Field | Meaning |
|---|---|
| `offer_id` | `r<revision>-<YYYYMMDD start>-s<slot>`; unique, never reused |
| `item_id` | the permanent entitlement it sells (e.g. `outfit:cloud_nine`) |
| `slot` | Featured slot 1-4 |
| `starts_at_utc` / `ends_at_utc` | on sale from start (inclusive) to end (exclusive) |
| `price` | Coins; always the item's catalogue price (no sale prices) |
| `revision` | the schedule revision that published it |

The same skin returns later under a new `offer_id`; ownership, the
Locker and the ledger only ever use the `item_id`.

**What rotates, what doesn't (decision).** The rotating pool is the six new
Pass 8 outfits plus the four V6 Coin outfits (Lantern Scout, Campus
Courier, Raincoat Explorer, Varsity Sprinter), which leave the always-on
list. Anyone who owns one keeps it (nothing was sold from a live service
yet, and entitlements never expire). **Always available**, never
expiring: the two direct Apple skins, all six Coin packs, Season 1
Premium, and the cheap pre-V6 items (three outfits and the accessories).
Reasons: Apple non-consumables and Premium are permanent purchases already
described as such; Coin packs must always be buyable; the pre-V6 items are
cheap legacy unlocks that existing players already own on their devices.

**The rule** (catalogue `offers.rule`, `tools/make_offer_schedule.py`):

- 4 Featured slots; every offer lasts exactly 48 h and starts and ends at
  00:00 UTC.
- Staggered: slots 1-2 change on even days from the start date, slots 3-4
  on odd days, so **two offers change every day at 00:00 UTC** (slots 3-4
  open one day before the start so every offer is a full 48 h).
- At each change the slot takes the pool skin that left the Shop longest
  ago (never shown counts as longest; ties in catalogue order) among those
  not on show and not leaving at that moment: no skin twice at once, no
  back-to-back return. With 10 skins this is a 5-day cycle: each skin is
  in the Shop 2 days, away 3, and returns under a new offer.
- Written schedule: **12 weeks** (2026-10-05 to 2026-12-28; 170 offers)
  in `game/config/catalogue.json` → `offers.schedule`. Past its end the
  service has no offers and the Shop says "No rotating skins right now".

**Regenerating / extending** (before the written schedule runs out, or
after the art lands if the pool changes): edit `offers.rule` (raise
`days`, or move `start_utc` to a later 00:00 UTC; or change the pool's
`"rotation"` flags), bump `offers.schedule_revision` if any unpublished
offer changes, then

```sh
python3 tools/make_offer_schedule.py          # refuses to change an offer that already started
node service/tools/sync_catalogue.mjs         # the service's copy
python3 tools/make_offer_schedule.py --check  # and cd service && npm test (both check it)
```

and deploy the service. Raising `days` with the same start is
prefix-stable: published offers keep their ids.

**The service is the authority** (`service/src/offers.js`):

- `GET /v1/shop/offers` (no sign-in): the service's clock, the offers on
  sale now (by slot), those starting in the next 72 h, the next change and
  `known_until`.
- `POST /v1/wallet/spend` with `offer_id` (§6): accepted only if, **at the
  service's own time when it accepts**, the offer exists, sells that item,
  is on sale and has the shown price; otherwise `409 offer_changed`
  (`reason`: not_started, expired, price, item_mismatch, unknown_offer,
  not_in_rotation) and nothing is charged. An item-only spend for a
  rotating skin (an older client, a deep link, a direct request) is
  accepted only while that skin has an active offer.
- Accepted: debit + permanent entitlement + ledger row + an `offer_sales`
  row (migration `0003_offers.sql`; a `CHECK` makes "accepted inside the
  window" part of the schema) in one batch. A replay of the same
  idempotency key returns that result even after the offer ended. Already
  owned stays owned and unbuyable (`already_owned`).
- Coin packs are independent of offers: buying Coins never reserves a skin.

**The game** (`Offers` autoload, `ShopScreen`):

- Keeps the service's time as an offset from the monotonic clock; the
  device clock can only make an offer end *sooner* (the later of the two
  estimates counts, so iOS sleep doesn't extend an offer), never later.
  Time zones don't enter at all (local time is presentation only).
- Trusts its time only after a sync in this app run, within 6 h, inside
  the described window. Otherwise: "Connect to refresh Shop" (cached
  offers stay previewable; nothing can be bought from them).
- Featured: four cards with "Leaves in 1d 04h" / "Leaves in 02:14:09",
  a separate "Shop refreshes in …", the note "Owned skins stay in your
  Locker. Shop skins may return.", then the compact Always available block.
  Countdowns tick once a second by changing label text; an ended offer's
  card is replaced in place by the slot's next offer.
- The detail sheet adds the local departure ("Leaves the Shop Wednesday,
  Oct 7, 12:00 AM (your time)", from the device's current UTC offset).
  All skins, a stale sheet or a deep link to a skin out of rotation say
  "Not in current rotation" (preview still works). "New" marks items added
  in the current catalogue version (`added_in`); no sale, rare or
  last-chance wording.
- Service off (this build): no rotation, the existing unavailable state;
  every skin can still be previewed in All skins.

### App Store products

| Product ID | Type | Delivers |
|---|---|---|
| `com.idlery.ultimatetrifecta.coins.250` | Consumable | 250 Coins (Pass 8) |
| `com.idlery.ultimatetrifecta.coins.500` | Consumable | 500 Coins |
| `com.idlery.ultimatetrifecta.coins.1000` | Consumable | 1,000 Coins (Pass 8) |
| `com.idlery.ultimatetrifecta.coins.1500` | Consumable | 1,500 Coins |
| `com.idlery.ultimatetrifecta.coins.3500` | Consumable | 3,500 Coins |
| `com.idlery.ultimatetrifecta.coins.7500` | Consumable | 7,500 Coins (Pass 8) |
| `com.idlery.ultimatetrifecta.skin.moonlight_runner` | Non-Consumable | `outfit:moonlight_runner` |
| `com.idlery.ultimatetrifecta.skin.starry_sleeper` | Non-Consumable | `outfit:starry_sleeper` |

No real-money price is stored anywhere: the Shop shows StoreKit's localized
`displayPrice`, and a product StoreKit doesn't return shows "Not available",
never a made-up price. Prices are the account holder's choice in App Store
Connect. "Best value" appears on a Coin pack only when StoreKit's own
numeric prices, all in the same currency, make it strictly the cheapest
per Coin (`Purchases.best_value_pack`); otherwise no such label.

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
- **Rotating skins (Pass 8)**: the spend carries `offer_id`; the service
  checks the offer on its own clock at acceptance (§2.1) and charges the
  offer's price, recording `offer_sales` in the same batch. `offer_changed`
  charges nothing and the client drops the operation, refreshes the offers
  and says so ("This offer has left the Shop. Nothing was charged.").
  A queued purchase whose reply was lost is retried with the same key and
  returns the accepted result even after the offer ended. Tested at
  before/at start, last millisecond, exact end, overlapping offers, a spend
  racing a Shop refresh, duplicate retries and an owned skin returning.
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
| Rotating offers (Pass 8) | none ("come from the game service") | last offers previewable, "Connect to refresh Shop", not buyable | live countdowns, buyable while on sale |
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
