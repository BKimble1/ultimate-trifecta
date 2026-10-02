# V6 commerce and progression notes

The commerce workstream of V6: one catalogue, the navigation shell, the
Locker, the Shop, native App Store purchases, the trusted wallet and ledger
service, the economy and save migration, and Season 1 · After Hours. The
rules and numbers are in [../ECONOMY.md](../ECONOMY.md); the owner's App
Store Connect and service steps in [../COMMERCE_SETUP.md](../COMMERCE_SETUP.md).

**What this can claim.** Everything was implemented and tested on a desktop
Linux machine: the game's headless test suite (with a simulated App Store and
a test-double service, both in `game/src/dev/`, which iOS exports exclude),
the service's Node tests (in-memory D1, a per-run test certificate chain), and
captures on the Mobile renderer (llvmpipe, Xvfb) at phone, SE and iPad sizes
with those test adapters. **No purchase has been made in Apple's sandbox, no
App Store product exists, the service is not deployed, and nothing ran on an
iPhone or iPad.** "Purchases work" is not claimed.

## Architecture

| Piece | Where | Role |
|---|---|---|
| Catalogue | `game/config/catalogue.json`, `src/core/catalogue.gd`, `service/src/catalogue_data.js` (generated, checked) | Stable item IDs, kinds, Coin prices, App Store product IDs, Season tables, economy numbers. One source for previews, ownership, Shop, pass, saves, networking (the wire format is still `Cosmetics`' IDs) and the service |
| Economy | `src/core/economy.gd`, `service/src/economy.js` | Round Coins and Season XP, eligibility, the row digest, tiers, claim states, the legacy import bound: the same functions on both sides (a test checks the canonical form) |
| Wallet | `src/autoload/wallet_service.gd` (autoload `Wallet`) | The last verified snapshot, cached in `user://wallet.json` (atomic write); ownership; the durable outbox (idempotency keys, retries, held per profile); spends, claims, the legacy import, round registration/report/confirmation; `round_summary()` for results |
| Purchases | `src/autoload/purchase_service.gd` (autoload `Purchases`), `src/core/store_adapter.gd`, `src/core/storekit_adapter.gd` | StoreKit 2 through the pinned GodotApplePlugins StoreKit module; per-product honest states; delivery to the service before `finish()`; restore; refunds |
| Service | `service/src/commerce.js`, `appstore.js`, `migrations/0002_commerce.sql` | Wallets, append-only ledger, entitlements, App Store verification (JWS chain + optional App Store Server API + Server Notifications), Season progress/claims, round settlement, admin reconciliation |
| UI | `src/ui/nav_shell.gd`, `wallet_chip.gd`, `creator_screen.gd` (Locker), `shop_screen.gd`, `season_screen.gd`, `commerce_art.gd` | Navigation, Locker, Shop, Season Pass, drawn Coin/badge/name-card art |

### StoreKit: the existing maintained module, not a new bridge

The pinned GodotApplePlugins release (`build-bfade13…`, already sha256-pinned
for Game Center) ships a **StoreKit 2** module, `GodotApplePluginsStoreKit`
(MIT, same author). Its source at that commit was read: `StoreKitManager`
listens to `Transaction.updates`, replays `Transaction.unfinished` in
`start()`, emits only verified transactions (unverified ones on a separate
signal), exposes `jwsRepresentation`, supports `appAccountToken` purchase
options, `AppStore.sync()` and `Transaction.currentEntitlements`, and **never
finishes a transaction itself**. So no new native code was written:
`tools/fetch_deps.sh` now installs that module too, `tools/export_ios.sh`
requires it, and the CI build facts report whether it is embedded. On Linux
the module's stub registers the classes but returns null instances;
`StoreKitAdapter` is used only on iOS. (Upstream HEAD adds a completion
signal for current entitlements; the pin was kept, since it also carries Game
Center, and the restore flow waits for a quiet period instead.)

### Navigation

`NavShell` (Play · Locker · Shop · Season Pass): pill tabs with an icon and
a label, the active one teal, a dot for rewards to claim or a purchase being
delivered. It measures the space its row leaves it and drops to "icons, active
label" and then "icons only" before it would push a row off screen (tested at
SE, iPad and phone widths). Play returns to the hub (the party lobby while in
a party, which stays intact, else home). Leaving the Locker with an unsaved
look asks first. Home shows it as a rail on the left (the runner keeps the
middle of the room) with the Coins chip and Emote; the lobby puts it where the
Wardrobe button was; Locker, Shop and Season Pass show it in their top bar
beside Back and the Coins chip. Edits to `title_screen.gd` and
`lobby_screen.gd` only insert it (the social workstream owns their layouts).

### Locker (the migrated wardrobe)

Same runner, categories, portrait cards, cached thumbnails, full names and
framing as V5, plus a Profile category (name cards, badges). It shows only
what the player owns (free base options, pre-V6 unlocks on this device,
account entitlements, Apple-verified skins); each category ends with a
"N more in the Shop" / "in the Season Pass" card. Save equips; it can't spend
(`Save.apply_appearance` now refuses unowned items and has no debit path;
`Save.buy` and `Save.price_of` are gone). V6 integrator changes (one-pointer
turn, scroll restore) are kept.

### Shop

Featured (Season 1 Premium first, then featured outfits), Outfits,
Accessories, Coins, Season 1. Cards are cached `Portraits` of your runner
wearing the item (swatches for colours, icons for emotes, drawn Coins), never
a live viewport; the one interactive preview is the dorm runner on the left
(drag to turn with one finger; Idle / Run / Emote). A card opens a detail
sheet: type, name, price (Coins or StoreKit's string), exactly what it
includes (its catalogue grants; hood outfits say the hood covers hair and
hat), its state and one action, plus Back. Coin purchases go through a
confirmation (item, price, balance, left after); App Store items open Apple's
sheet straight from the tap. Wallet and store updates refresh labels in
place. Restore Purchases is in Featured, Outfits, Coins and on skin sheets.
No sales, timers, scarcity, loot boxes or pop-ups.

### Season Pass

Header: season, exact tier, XP to the next tier with a bar and the next
reward, Premium status, Claim all (n). Track: 30 tier columns (Free above,
Premium below) on a horizontal `UIKit.scroll_area(true)`; a swipe never
claims (tested through the real input path). Detail panel: the focused
reward's picture, name, type, tier/track, state and one action (Claim, Get
Premium in the Shop, Wear it in the Locker). No countdown.

## Tests

| Suite | What it covers |
|---|---|
| `game/tests/test_catalogue.gd` | IDs, products (no stored prices), Shop outfits and price band, pass rewards never sold, Season table complete (30 tiers, ascending XP, every tier Premium, 15 Free, no end date, Premium Coins < price), tier boundaries and claim states, round Coins/XP (repeat captures capped, cancelled pays nothing), eligibility (practice, bots, away, few humans), canonical digest, compute_rewards decoupled, the 60-120 round target, legacy bound; **and** every referenced runner item exists in `Cosmetics` (fails until the art merge) |
| `game/tests/test_wallet.gd` | Save v3→v4 migration twice, pre-V6 items offline, service-off honesty, legacy import once per account, atomic spend, lost reply retried without double charge (and across a restart), offline cached ownership, account change, another profile's queued spend held, Season claims (repeat Claim all, late Premium), duplicate-owned reward, round settlement with matching confirmation, mismatch unpaid, practice/cancelled/service-off, apply_results routing |
| `game/tests/test_purchases.gd` | Product matching, success → delivered then finished, cancel / Ask to Buy / error / unverified, duplicate callbacks, interruption before and after the durable grant, skin restore and refund, account mismatch, sandbox vs production, no service → no sheet, StoreKit adapter inert off iOS, `src/dev` excluded from exports |
| `game/tests/test_shop_ui.gd` | Swipe on a Shop card scrolls and opens nothing, tap opens once; Coin confirmation and one charge; wallet updates in place; Apple sheet only from a tap; Season track swipe vs claim, Claim all, Premium → Shop; tabs on screen and full-size at SE/iPad/16:9; service-off Shop |
| `game/tests/test_wardrobe.gd` (updated) | Locker: Save never spends; only owned items; View in Shop links; Profile category |
| `game/tests/test_profile.gd`, `test_rules.gd` (updated) | Equip-only apply; Coins vs lifetime XP |
| `service/test/commerce.test.mjs` | Catalogue copy current, economy parity, JWS chain (untrusted root, missing marker, tampering, future date), Coin delivery once (duplicates, races, account mismatch), bundle/environment/product/type checks, production separation, skins (other profile, restore after deletion, refund), refund debt, Server Notifications, App Store Server API, atomic spends (races, overdraw), legacy import (bound, once per account and Game Center player), Season claims, round registration/report/confirmation/settlement, implausible/mismatch/cancelled/away/few-humans/daily cap, deletion, request bounds |

Results of the final runs are in the workstream report; the art-dependent
check is the only expected failure before the merge.

## Evidence

[`../media/v6/commerce/`](../media/v6/commerce/README.md): Home with the
navigation rail, Locker (owned items, View in Shop, Profile), Shop sections,
detail sheet (preview, Run), Coin confirmation, Coin pack and Premium
sheets, Season Pass (claimable, Premium-locked, tier 30), and the service-off
Shop and Season Pass, at phone, SE and iPad sizes. Rendered on llvmpipe with
the **test adapters** (simulated store prices read "(test price)"). The six
new Shop outfits and Season art were not merged into this branch, so those
items are hidden (Shop) or drawn as a placeholder silhouette (Season track);
re-run `tools/capture_v6_commerce.sh` after the art merge.

## Limits and open items

- **No real purchase evidence.** Needs the Paid Applications agreement, the
  five products (prices, review screenshots), the sandbox service deployment
  and a TestFlight build with `service.cfg` filled in
  ([COMMERCE_SETUP.md](../COMMERCE_SETUP.md) §1-4).
- The StoreKit module is the pinned upstream one; its iOS behaviour was read
  from source, not observed. Restore waits 3 s of quiet after
  `AppStore.sync()` (the pinned build has no entitlement-completion signal).
- Peer-hosted results remain the host's (bounded, confirmed, capped, audited,
  not anti-cheat): [ECONOMY.md](../ECONOMY.md) §5.
- Service-off builds (the current state) settle no Coins or Season XP; the
  results say so. A V5 tester's balance shows as "on this device" until the
  first signed-in import.
- No OCSP revocation check of Apple's certificates (chain, pin, markers and
  validity are checked; the optional App Store Server API lookup is the
  second source).
- Profile cosmetics (name cards, badges) are local display only: shown on
  your own profile and Locker, not sent to other players.
- `coins_picked` (the match's coin pickups) and `coin_spawns` come from the
  dorms workstream; until they merge, rounds report 0 pickups.
