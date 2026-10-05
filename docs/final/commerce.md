# FINAL_RELEASE_SWEEP · Commerce: environments, purchases, Shop

Workstream: COMMERCE (brief §5 and §7 in full; §2 items 1, 2 and 4; §10
Commerce evidence). Base: `e3c2cd6` (1.9 (9)). Everything below was built
and verified **locally**: the service test harness (two in-memory
databases standing in for the two deployments, a per-run certificate chain
shaped like Apple's), the game's headless tests with the simulated store and
the test-double service, and desktop renders. **No service was deployed, no
App Store product exists, no sandbox or real purchase was made, nothing ran
on a device.** Those results are listed as pending in §12.

## 1. Environment architecture

One release candidate serves TestFlight, App Review and the App Store. In
words, as a diagram:

```
 iPhone / iPad build 2.0 (one binary)
   │  at launch: UTShare.receipt_kind()  →  Cloud.pick_route()
   │     "sandboxReceipt" (TestFlight, Xcode, simulator) ─────────┐
   │     "receipt" (App Store; App Review: either)  ─────┐       │
   │     unknown / no URL / older library  ──────────────┤       │
   │                                                      ▼       ▼
   │                                   production deployment   sandbox deployment
   │                                   trifecta-service-        trifecta-service
   │                                   production               D1 "trifecta"
   │                                   D1 "trifecta-production" ENVIRONMENT=sandbox
   │                                   ENVIRONMENT=production   APPLE_ENVIRONMENT=Sandbox
   │                                   APPLE_ENVIRONMENT=        credits ONLY Apple Sandbox
   │                                     Production              transactions
   │                                   credits ONLY Apple
   │                                     Production transactions
   │
   │  App Review buys in Apple's sandbox on an App Store build:
   │    production verifies the JWS (Apple chain) → 409 sandbox_purchase,
   │    records and credits nothing
   │    → Cloud.move_to("sandbox"): sign out of production, sign in to the
   │      sandbox as the same Game Center player (same appAccountToken),
   │      remember the move for this install (user://service_route.cfg,
   │      keyed by the receipt kind), wait if a party is open
   │    → Purchases re-delivers the still-unfinished StoreKit transaction to
   │      the sandbox → credited once → finished once
   │  (the reverse: the sandbox answers a Production purchase with
   │   409 production_purchase and the install moves to production)
   │
 App Store Server Notifications V2:  Production URL → production deployment
                                      Sandbox URL    → sandbox deployment
                                      each refuses the other environment
 Apple's App Store Server API host:  per deployment (api.storekit / api.storekit-sandbox)
 Shared secret (identical on both):  APP_ACCOUNT_TOKEN_KEY
   appAccountToken = UUIDv8(HMAC-SHA256(key, "gamecenter:" + teamPlayerID))
```

Rows in both databases also carry `environment`, sessions carry the
deployment's environment in the signed token (a sandbox session is `401`
on production), and the two databases are separate D1 instances.

## 2. Security argument

What has to be true: no one can obtain production Coins, items, Premium or
progress except through a real App Store purchase (or legitimate play on
production), and sandbox value never leaks into production.

1. **Value is minted only from verified Apple transactions of the
   deployment's own environment.** `POST /v1/wallet/apple` verifies the JWS
   up to the pinned Apple Root CA - G3 (marker OIDs, each signature, validity
   at the signed date), checks the bundle, then the environment
   (`environmentMismatch`), optionally replaces the payload with Apple's own
   copy from the App Store Server API for this deployment's host, and checks
   it again before crediting. Only Apple can sign a Production transaction,
   and only a real-money App Store purchase produces one.
2. **The client's route is a hint, never a permission.** A modified client
   can pick either deployment, but each credits only its own environment.
   Choosing the sandbox gains nothing of value (an isolated economy with no
   exit); choosing production gains nothing without real Production
   purchases. That is why an unknown route defaults to production.
3. **The fallback reply records nothing.** `409 sandbox_purchase` /
   `production_purchase` are sent after verification and before any row is
   written or Apple's API is asked (tests: no `apple_transactions` or ledger
   row on the refusing deployment). They are routing hints for the client;
   the receiving deployment verifies everything again.
4. **Account binding stays strict.** The appAccountToken is derived from the
   verified Game Center subject (teamPlayerID), the same in both deployments
   for the same player and different for different players; a transaction
   carrying a token is credited only to the caller whose derived token
   matches (`account_mismatch` otherwise, kept unfinished for its owner). A
   transaction without a token (e.g. an offer code redeemed outside the
   app) is bound to the first verified caller, as before; every in-app
   purchase now carries a token (the client refuses to start one without
   it). The token reveals nothing about the player without the key.
5. **Sessions don't cross.** Session tokens are HMAC-signed with the
   deployment's `ENVIRONMENT` in the payload; a sandbox session can't spend,
   claim or deliver on production (test).
6. **Notifications are per environment.** Each deployment refuses a
   notification whose envelope or inner signed transaction is of the other
   environment, so a mis-set URL changes nothing.
7. **TestFlight → App Store carries nothing over.** Production starts with an
   empty wallet for the same player; the pre-V6 beta-balance import is
   refused on production; a sandbox transaction can't be restored into
   production; and the client never shows or applies a cached snapshot of
   the other deployment.
8. **No reviewer whitelist.** Review accounts are ordinary players; review
   purchases land in the sandbox economy by the same rule as TestFlight.

Known limitation (by design of separate deployments): parties, Friends
presence and profiles are per deployment. A TestFlight player and an App
Store player can't join each other's service parties, and an App Review
device that moved to the sandbox can't join a party hosted on a review
device still on production (see the review-note text in §15).

## 3. Decisions (with reasons)

| Decision | Reason |
|---|---|
| Two deployments and databases kept (fixed design) | Strongest isolation; each deployment's existing `wrong_environment` rule is the security boundary. |
| Receipt kind as an `int` (`UTShare.receipt_kind()`: 1 receipt, 2 sandboxReceipt, 3 other, 0 no URL, -1 unavailable) instead of returning the string | Reuses the extension's existing, verified int-return path (`thermal_state`); no new String marshalling in plain C that can't be compiled for iOS here. The Objective-C maps `lastPathComponent` exactly as specified. |
| Missing native call or unknown name → **production** | Production only credits Production-signed purchases; a wrongly claimed sandbox only reaches a worthless economy. |
| No receipt URL (0) → **production** (the coordinator's draft said sandbox) | Current iOS returns a URL for every install type (Xcode and simulator builds: `sandboxReceipt`), so 0 only happens if Apple removes the deprecated call; then sandbox would silently park every App Store customer in the sandbox economy. |
| Reverse fallback (`production_purchase` → move to production) | Self-heals a mis-routed real customer (e.g. an old build without the call); can't mint anything (production verifies again). |
| One automatic move per launch; remembered per receipt kind | No ping-pong; a TestFlight→App Store reinstall (receipt kind changes) drops the move. |
| A move waits while a party is open | A room lives in one deployment; moving mid-party would break membership and settlement. The purchase stays unfinished and is shown "Adding…" meanwhile. |
| Name carried over on a move | The sandbox profile is new; the same approved name is submitted (that deployment moderates it again), so a reviewer isn't stopped by a name sheet. |
| Token = UUIDv8(HMAC-SHA256(key, "gamecenter:" + teamPlayerID)); old rows re-keyed on read; placeholder `unbound:<pid>` without a key | Same token on both deployments; the service was never deployed, so no live purchase carries a random token; a deployment without the key delivers nothing (503, kept unfinished) instead of delivering unbound. |
| Production refuses the pre-V6 beta import | Those balances only existed in TestFlight builds (sandbox economy); importing them would carry beta Coins (up to 2,000, client-claimed) into the real economy. |
| Offer schedule: written to 2027-04-06, then a generated cycle | The rule is periodic (10 days); the cycle is checked to equal the rule continued, ids keep the rule's form, so extending the written schedule later changes nothing anyone saw. |
| Shop: one "Hide owned" switch on All skins and Accessories only | The brief's "one toggle"; Featured, Coin packs and Premium are never filtered; tabs already separate kinds. |
| No handler for StoreKit `purchase_intent` (promoted IAP) | Not needed unless the owner promotes products on the App Store page; recommend leaving promotion off for launch (§7). |

## 4. What changed

Service (`service/`): `src/commerce.js` (derived appAccountToken,
`environmentMismatch` and the routing replies, the inner notification
transaction check, production refusing the beta import, race-safe spend
replay), `src/offers.js` (cycle fallback: `cycleBetween`, `offerById`),
`src/catalogue_data.js` (generated), `scripts/gen_keys.sh` and
`scripts/deploy.sh` (`APP_ACCOUNT_TOKEN_KEY`), `wrangler.toml` (comment),
`README.md`; tests: new `test/environments.test.mjs` (10), updated
`test/commerce.test.mjs` (+1), `test/offers.test.mjs` (+1),
`test/helpers.mjs`.

Game: `config/service.cfg` (new keys), `config/catalogue.json` (schedule to
2027-04-06 + cycle), `src/autoload/cloud_service.gd` (routing, `move_to`,
`deployment_changed`, `wallet_environment`, per-deployment test transports),
`src/autoload/purchase_service.gd` (routing replies, token required),
`src/autoload/wallet_service.gd` (per-deployment cache and snapshots),
`src/core/storekit_adapter.gd` (never an unbound purchase),
`src/ui/shop_screen.gd` (Hide owned, App Store line, Season Pass link,
restore on exit, stable rebuilds), `src/dev/fake_commerce_service.gd`
(derived tokens, routing replies, cycle), `src/dev/capture_shop_final.gd`,
`src/dev/capture.gd` (one scenario line); tests: new
`tests/test_commerce_routing.gd` (6), `tests/test_shop_filters.gd` (5),
`tests/test_purchases.gd` (+1), `tests/test_native.gd` (+1).

Native: `native/ut_share/src/ut_share_ios.m` (`ut_platform_receipt_kind`),
`ut_share.c` (binds `receipt_kind`), `ut_share_platform.h`,
`ut_share_stub.c`.

Tools/docs: `tools/make_offer_schedule.py` (cycle), `tools/capture_final_shop.sh`,
`docs/COMMERCE_SETUP.md` (rewritten), `docs/ECONOMY.md` (§2.1 schedule,
§7 beta import), this file, `docs/media/final/commerce/`.

## 5. Defect register

| # | Symptom | Reproduction | Cause | Fix | Evidence |
|---|---|---|---|---|---|
| D1 | Restore Purchases after deleting and recreating the game profile: "This skin is already linked…/belongs to another player profile" for a direct outfit bought in-game | `restore after profile deletion…` (environments.test.mjs) run against the pre-sweep `commerce.js`: **409** (observed) | appAccountToken was a random UUID per wallet: the recreated profile had a new token, and every in-game purchase carries the old one | Token derived from the Game Center player | Same test now 200, `restored: true` |
| D2 | (Brief §2.4, §7) An App Store build would refuse App Review's sandbox purchases forever ("We couldn't add this purchase"), kept unfinished | Production deployment + Sandbox transaction → `wrong_environment` (old `production deployment…` test) | One Apple environment per deployment and one URL in the client | Two-endpoint client routing, `sandbox_purchase` reply, automatic move + redelivery | `App Review fallback…` (service), `test_app_review_fallback_moves_to_sandbox_and_finishes_once` (game) |
| D3 | The Shop's rotating section empty from 2026-12-29 forever | Old `GET /v1/shop/offers` test asserted `current: []` at 2027-06-01 | Bounded 12-week written schedule, no fallback | 26-week schedule + generated cycle | `after the written schedule the rule continues…`, `test_past_the_written_schedule_the_shop_still_rotates`, `shop_featured_after_written_schedule.jpg` |
| D4 | A TestFlight install updated to the App Store build would show, offline, the TestFlight (sandbox) Coins, items and Season XP as its own | `test_testflight_to_app_store_never_shows_the_sandbox_wallet` with the new guard disabled: **got 1500, expected 0**; the sandbox outfit owned (observed) | The wallet cache's offline view is keyed by profile only, and the offline path shows the last snapshot while no profile is signed in | Offline views, `synced()` and `apply_snapshot` require the snapshot's environment to match the current deployment | Same test passes |
| D5 | Production would import up to 2,000 client-claimed "beta" Coins per player (pre-V6 TestFlight balances) into the real economy | `TestFlight to App Store…` (environments.test.mjs) | Legacy import allowed on every deployment | Production answers `409 legacy_not_available` | Same test |
| D6 | A spend retried while its original was committing could answer "You already own this." for a purchase that went through (no double charge) | `concurrent spend, claim, Premium and delivery…` failed before the fix (observed: the second same-key request got `already_owned`) | The owned check ran after the original committed; only the earlier ledger check returned the replay | Re-check the ledger before `already_owned` | Same test, 3 repeated runs pass |
| D7 | A notification's inner signed transaction wasn't checked against the deployment's environment/bundle (only the envelope) | Code reading | Missing check | Checked | `notifications: each deployment applies only its own environment` |
| D8 | An in-app purchase could start without an appAccountToken if the token string didn't parse as a UUID (the plugin returns null; the adapter dropped the option) | Code reading against `StoreProduct.swift` | Fail-open option handling | `StoreKitAdapter.purchase` refuses without a valid option; `Purchases.view` offers no purchase without a token | `test_products_match_the_catalogue` etc. still pass; device check pending |
| D9 | The direct App Store outfits looked like any other item on Shop cards (only the price format differed) | Shop renders (`docs/media/pass8`) | — | An "App Store" line on their cards (where rotating skins show "Leaves in") | `shop_all_skins_owned_states.jpg`, card test |
| D10 | (found in this pass's own change) Hide owned rebuilt the section under the same node names while the old nodes were only queued: lookups found the dying nodes | `test_hide_owned…` (first run) | `queue_free` without `remove_child` | Detach before freeing | Test passes |
| D11 | (found in this pass's render) With Hide owned on, items owned after the grid was built (late wallet sync) stayed listed | `shop_accessories_all_owned_hidden` first render | Filter applied only at build time | Re-applied when ownership changes (not while a sheet is open) | `test_hide_owned…` "a newly owned skin leaves the filtered grid" |
| D13 | On iPhone SE, a Coin pack the App Store doesn't return showed "Not available" in its pill **and** a clipped "Not av…" note beside it (layout report: 6 trimmed labels) | `capture_final_shop.sh … se`, shot `shop_coins_price_unavailable` (first run) | The card repeated the pill's state as a note too long for the compact card | The note is gone for that state (the pill says it; a tap says why) | `test_coin_pack_cards_are_compact_priced_by_storekit_and_honest` ("said once"); the re-rendered shot |
| D12 | (new path) A wallet reply in flight during a deployment move could be applied as the new deployment's | `test_testflight…` (an auto-refresh racing the test) | Snapshots not checked against the deployment | `apply_snapshot` drops another environment's snapshot | Same test: "a late sandbox snapshot is dropped" |

## 6. Flows (brief §7 table)

"Simulated" = game test with the simulated store and the test-double
service; "service" = node test against the real service code with an
in-memory D1 and a test Apple-shaped chain. All listed tests pass on this
branch. Device / sandbox / live columns: not observed (§12).

| Flow | Service tests | Game tests | Result |
|---|---|---|---|
| All six Coin packs (product, localized price, exact Coins, sheet from a tap) | offers: `six Coin packs: every product maps…`; commerce: `Coin pack: verified, delivered exactly once…` | test_shop_rotation: `test_coin_pack_cards_are_compact_priced_by_storekit_and_honest`, `test_all_six_packs_deliver_their_quantity_once`; test_shop_ui: `test_apple_items_open_the_store_sheet_only_from_a_tap`; test_purchases: `test_products_match_the_catalogue` | pass (simulated / service); real prices pending |
| Both direct Apple outfits (entitlement, Locker, restore) | commerce: `direct skin: delivered, restored after deletion…`; environments: `restore after profile deletion…` | test_purchases: `test_both_direct_outfits_deliver_show_in_locker_and_restore` (new), `test_skin_restore_and_refund`; test_shop_filters: `test_both_direct_outfits_and_six_coin_packs_are_always_reachable` | pass |
| Coin skin/accessory with confirmation (item, cost, balance, left) | commerce: `spend: atomic debit + grant…` | test_shop_ui: `test_coin_purchase_is_confirmed_and_charged_once` | pass |
| Premium with Coins; earned Premium rewards claimable | season: `tier 50 and tier 100…`; commerce: `Season: … late unlock…` | test_wallet: `test_season_claims_idempotent_and_late_premium`; test_season100: `test_tier_50_and_100_need_the_tier_and_premium` | pass |
| Season claim / Claim all once across retry/relaunch/second device | season: `claims are idempotent: repeats, a lost reply, two devices at once, a reinstall`, `a whole 100-tier Claim all…` | test_season100: `test_claims_survive_lost_replies_offline_reinstall_and_a_second_device`, `test_a_whole_100_tier_claim_all…` | pass |
| Cancellation | — | test_purchases: `test_cancel_pending_and_errors_are_honest` | pass |
| Pending / Ask to Buy | — | same test (approval delivered later via a transaction update) | pass |
| Interruption after Apple success | commerce: duplicate/racing deliveries | test_purchases: `test_interrupted_before_durable_grant`, `test_interrupted_after_durable_grant_before_finish` | pass |
| Restore / reinstall / new device, no consumable regrant | commerce: replay tests | test_purchases: `test_both_direct_outfits…` ("restore never credits Coins"), `test_skin_restore_and_refund`; test_wallet: `test_offline_cached_ownership_and_account_change` | pass |
| Account switch / mismatch | commerce: `Coin pack: … bound to the account`; environments: App Review fallback (another player) | test_purchases: `test_account_mismatch_and_environment` | pass |
| Refund / revocation | commerce: `refunded Coin pack…`, `App Store Server Notifications: REFUND revokes once`; environments: notifications | test_purchases: `test_skin_restore_and_refund` | pass |
| Offer expires / filter changes; invalid request can't debit | offers: `offer boundaries…`, `price, item and unknown offers…`, cycle test | test_shop_rotation: `test_an_expired_offer_cannot_be_bought_anywhere` (sheet + confirmation close, no charge), `test_offer_changed_before_acceptance_charges_nothing`; test_shop_filters (filter never makes anything buyable) | pass |
| Concurrent spend / claim | commerce: `spend: … never twice` (races), `concurrent spend, claim, Premium and delivery…` (new) | test_wallet: `test_spend_is_atomic_and_never_twice`, `test_lost_reply_retries_without_double_charge` | pass |
| **Environments (§7 Critical)** | environments.test.mjs: all 10 | test_commerce_routing.gd: all 6 | pass |

## 7. StoreKit adapter audit (pinned GodotApplePlugins `bfade13`, source in the scratchpad clone)

| Item | Plugin source | Adapter | Status |
|---|---|---|---|
| Classes and members | `StoreKitManager`, `StoreProduct` (`product_id`, `display_name`, `description_value`, `price`, `display_price`), `StoreTransaction` (`transaction_id` int, `original_id`, `product_id`, `jws_representation`, `purchase_date`, `revocation_date`, `ownership_type`, `finish()`), `StoreProductPurchaseOption.app_account_token(String)` static (doc_classes) | same names via `ClassDB` / `get()` | matches |
| Signals | `products_request_completed(products, status)`, `purchase_completed(transaction, status, message)`, `transaction_updated(transaction)`, `unverified_transaction_updated(transaction, verification_error)`, `restore_completed(status, message)` | connected with matching arity | matches |
| Status codes | `OK 0, INVALID_PRODUCT 1, CANCELLED 2, UNVERIFIED_TRANSACTION 3, USER_CANCELLED 4, PURCHASE_PENDING 5, UNKNOWN_STATUS 6`; thrown purchase errors → `CANCELLED` with the message; product request failure → `CANCELLED` + empty list | `StoreAdapter.Status` same order; `CANCELLED` is treated as "didn't finish, if charged it's added" + `fetch_unfinished`, never as "not charged" | matches |
| appAccountToken | `UUID(uuidString:)`, `nil` if not a UUID | derived UUIDv8 always parses; adapter now refuses to purchase without the option (D8) | fixed |
| Replay at start | `start()` → `Transaction.updates` listener + `PurchaseIntent` listener + `fetch_unfinished_transactions()` | `Purchases.use_adapter` → `start()`, `fetch_entitlements()`; resume → `fetch_unfinished()` | matches |
| Purchases made in-app | delivered by `purchase_completed` (StoreKit doesn't repeat them on `Transaction.updates`) | `_on_purchase_result(OK)` → `_on_transaction` | matches |
| Finishing | the plugin never finishes (comment in `handleTransaction` says so; code doesn't) | `finish()` only after the service's `ok` (delivered, replay or revoked) | matches |
| Restore | `AppStore.sync()` then `restore_completed`; entitlements via `fetch_current_entitlements` (`Transaction.currentEntitlements`) | `restore()` → on OK `fetch_entitlements()`, 3 s quiet period, summary | matches |
| Unverified | emitted separately, with a nil transaction from `purchase_completed` | counted, never delivered or logged | matches |
| Promoted IAP | `purchase_intent(product)` (iOS 17.4+) | **not handled** | leave App Store promotion off for launch, or add a handler later |
| No AppTransaction / environment API | none in this release | environment comes from the service's verification; routing uses `UTShare.receipt_kind()` | by design |

Only a device can prove: the module loads and its classes register in the
signed app; product fetch returns the eight products with real prices;
Apple's sheet; the JWS Apple signs verifies on the deployed service with
Apple's real chain; the appAccountToken round trip; Ask to Buy and
interrupted-purchase replays; refunds and their notifications; the receipt
kind of TestFlight (expected 2), App Store (expected 1) and App Review (1 or
2: both are handled).

## 8. Shop (brief §5)

- **Tabs** kept: Featured · All skins · Accessories · Coins · Season 1.
  **Hide owned**: one switch (44 pt, controller-focusable, kept while the
  game runs) above All skins and Accessories with "15 skins · 2 owned";
  hides exactly what is owned, follows ownership changes, says "You own
  every … here … Turn off Hide owned to see them" instead of an empty grid;
  never on Featured, Coins or Season 1. Filters can't make anything
  buyable: Season rewards aren't listed (the Season tab says they're earned
  in the pass and links there), a rotating skin still needs its live offer.
- **Kinds told apart**: rotating skins carry "Leaves in …"; direct outfits
  an "App Store" line and the App Store's price; permanent Coin items a Coin
  price; owned items "Owned"; Season content lives in the pass (Season 1
  tab: Premium and the link).
- **Every card opens its own item** with its own portrait, name, source and
  price (test over every card of All skins, Accessories and Featured); no
  preview survives a closed sheet, a section change or the filter.
- **Review reachability**: both direct outfits are always in Featured ›
  Always available and All skins, and the six packs always in Coins — live,
  offline and with no service (test).
- **Presentation only**: previewing never writes the save; Back, a section
  change, filtering, and the Shop closing any other way (match start, invite)
  restore the equipped look; a cancelled App Store purchase leaves the save
  untouched (test). A match rebuilds the stage from the save anyway.
- **Prices**: StoreKit's `displayPrice` only; "(test price)" exists only in
  the simulated store and labelled captures; "Not available" when StoreKit
  returns no product; "Best value" only from same-currency numeric prices.

## 9. Offer schedule

Written: 2026-10-04 → 2027-04-06 (366 offers; the first 170, published
since Pass 8, unchanged). Then `offers.cycle` (period 10 days, from
2027-04-05, anchor 2027-03-26) continues the rule on the service's clock
with ids `r1-<YYYYMMDD>-s<slot>`. Tests cover the seam and three years
after it (four distinct skins at every moment, one per slot, 48 h each, no
straight-back returns, ids stable, a computed offer bought and expired on
the service clock). The game's test double serves the same cycle, so
captures and client tests past 2027-04-06 behave like the service.

## 10. How verified

| Command | Result |
|---|---|
| `cd service && npm test` | **80/80 pass** (68 before; +10 environments, +1 cycle, +1 concurrency) |
| `python3 tools/make_offer_schedule.py --check`; `node service/tools/sync_catalogue.mjs --check` | up to date (366 offers); copy up to date |
| `tools/build_native.sh` (Linux, `-Werror`) | builds `libut_share.linux.x86_64.so` with `receipt_kind` |
| `clang -fsyntax-only -fobjc-arc -Wall -Wextra -Werror` on `ut_platform_receipt_kind` with stand-in Foundation declarations | clean (no iOS SDK here: the real compile is CI's) |
| `tools/gd.sh --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd -- test_commerce_routing.gd:,test_purchases.gd:,test_wallet.gd:,test_native.gd:` | 33 tests, 0 failures |
| `… -- test_shop_filters.gd:,test_shop_ui.gd:,test_shop_rotation.gd:,test_menus_layout.gd:` | 33 tests, 6,267 checks, 0 failures |
| `… -- test_shop_ui.gd:,test_shop_rotation.gd:,test_account.gd:,test_report_block.gd:,test_chat.gd:,test_profile.gd:,test_catalogue.gd:,test_season100.gd:` | 74 tests, 4,114 checks, 0 failures |
| `… -- test_menus_layout.gd:,test_screen_cycles.gd:,test_skins_p9.gd:,test_focus.gd:` | 26 tests, 5,764 checks, 0 failures |
| `tools/capture_final_shop.sh build/frs_final se p14 ipad` | the shots in §11 (layout reports: 0 issues) |

The full game suite was not run here (the integrator runs it after merging).

## 11. Evidence index (`docs/media/final/commerce/`)

Every picture: **desktop render (Linux, llvmpipe, Mobile renderer) at the
device's resolution with its point scale and safe area emulated; DEV
FIXTURE test-double service (fixed clock, the catalogue's schedule) and
simulated store**, with that label drawn on the image. Layout and states
only: not a deployed service, not a real App Store price or purchase, not
frame rate. `<device>`: `se` (1334×750 @2), `p14` (2532×1170 @3, safe
47/0/47/21), `ipad` (2048×1536 @2, safe 0/24/0/20). JPEG q85, 1280 px wide.

| Shot | Shows |
|---|---|
| `shop_featured.jpg` | four rotating offers, "Leaves in", "Shop refreshes in" |
| `shop_featured_always.jpg` | Always available: both App Store outfits (one owned) and Season 1 Premium |
| `shop_all_skins_owned_states.jpg` | All skins: "15 skins · 2 owned", Hide owned off, App Store line, rotating lines, Owned |
| `shop_all_skins_hide_owned.jpg` | the same with Hide owned on |
| `shop_accessories_all_owned_hidden.jpg` | every accessory owned and hidden: the explained empty state |
| `shop_detail_app_store_outfit.jpg` | Starry Sleeper's sheet: "Outfit · App Store", price, Restore |
| `shop_coins_simulated_prices.jpg` | six packs with the simulated store's "(test price)" (labelled) |
| `shop_coins_price_unavailable.jpg` | six packs when the store returns no products: "Not available" (labelled) |
| `shop_season_tab.jpg` | Season 1: Premium and "Open the Season Pass" |
| `shop_featured_after_written_schedule.jpg` | service clock 2027-06-01: four offers from the cycle |

Before (same scale, same fixture, `e3c2cd6`): the Pass 8 captures in
`docs/media/pass8/shop/` show the same screens without the filter row and
the App Store line.

## 12. Pending: needs a device, a sandbox account or the deployed service

Highest value first; each line is a pass/fail observation:

1. TestFlight build, sandbox account: Shop › Coins shows six real localized
   prices (no "(test price)", no "Not available").
2. Buy 250 Coins: Apple's sheet from the tap → "+250 Coins added"; the
   sandbox admin wallet shows one `apple` ledger row; StoreKit finished it
   (no replay on relaunch).
3. Force-quit on Apple's success sheet → relaunch → delivered once.
4. Buy and restore both outfits on a reinstall; no Coins added by restore.
5. Coin item, Premium, Claim all; relaunch; a second device: same state.
6. Cancel; Ask to Buy approve; a sandbox refund → revoked via the
   notification (check the sandbox deployment's `apple_notifications`).
7. `receipt_kind()` on the TestFlight build = 2 (diagnostic: the sandbox
   deployment's `/v1/me` works; production has no profile for the tester).
8. After App Store release: an App Store install creates its profile on
   production; a purchase there credits production only.
9. App Review fallback: only observable in review itself (or with an App
   Store-signed build buying in the sandbox); covered by tests.

## 13. Owner dependencies (exact)

1. Paid Applications agreement, tax, banking (account holder).
2. Create the eight products exactly as in COMMERCE_SETUP §2 (IDs and types
   unchanged); prices; review screenshots from a TestFlight device.
3. Cloudflare: `npx wrangler d1 create trifecta` and `… trifecta-production`
   (ids into `service/wrangler.toml`), `service/scripts/gen_keys.sh` (creates
   `.secrets/app_account_token_key` among others), optionally the In-App
   Purchase key files, then `scripts/deploy.sh` and `DEPLOY_ENV=production
   scripts/deploy.sh` (all migrations, including FRIENDS' 0006, are applied
   by `deploy.sh`).
4. `game/config/service.cfg`: `production_url`, `production_admission_public_key`,
   `sandbox_url`, `sandbox_admission_public_key` (both keys = the printed
   admission public key); rebuild and upload.
5. App Store Server Notifications V2: the Production and Sandbox URLs above.
6. Never regenerate `.secrets/app_account_token_key` after purchases exist;
   keep `.secrets/` backed up privately.

## 14. Open items

- Device-only verification (§12).
- Promoted IAP (`purchase_intent`) not handled: keep IAP promotion off.
- Parties/Friends don't cross deployments (TestFlight vs App Store; a review
  device after a purchase vs one before). Documented for review notes.
- `REFUND_REVERSED` notifications aren't re-granted automatically (support
  can grant through the admin API), as before.
- The legacy (pre-V6) import stays on the sandbox deployment only.

## 15. Proposed text for integrator-owned documents

**docs/APP_STORE.md, App Review notes (purchases)** — copy-ready:

> In-app purchases: Shop (top bar) › Coins has six Coin packs; Shop ›
> Featured › Always available (also Shop › All skins, marked "App Store")
> has the two outfits Moonlight Runner and Starry Sleeper; Restore Purchases
> is at the bottom of Featured, All skins and Coins and on each outfit's
> page. Season 1 Premium is bought with Coins (Shop › Season 1). Purchases
> made during review use Apple's sandbox; the game recognises this by itself
> (the first purchase may take a few seconds longer) and keeps review
> purchases in a separate sandbox economy, never mixed with customers'.
> Online parties match players of the same economy: to test a party on two
> devices, test it before making purchases, or make a purchase on both
> devices first.

**TESTFLIGHT_RELEASE.md / docs/testflight/what_to_test.txt** — add:

> Purchases are free sandbox purchases (sign in with a Sandbox Apple
> Account under Settings › Developer). Shop › Coins: check the six prices,
> buy one small and one large pack. Shop › Featured › Always available: buy
> and then restore an outfit. Shop › All skins: try Hide owned. TestFlight
> uses the test economy: Coins and items bought here don't carry over to the
> App Store version.

**docs/APP_STORE_READINESS.md rows**: "IAP environments (TestFlight, App
Review, App Store)": READY in code / NOT VERIFIED on device (evidence: this
file §6, `service/test/environments.test.mjs`, `game/tests/test_commerce_routing.gd`).
"Service deployed (sandbox + production)": OWNER SETUP REQUIRED (§13).
"Eight IAP products": OWNER SETUP REQUIRED. "Real sandbox purchase":
NOT VERIFIED.

**docs/FINAL_RELEASE_SWEEP.md summary line**: "Commerce: one build routes
to the sandbox (TestFlight, App Review) or production (App Store) service by
the App Store receipt kind and moves itself to the sandbox when production
refuses a sandbox purchase; per-player appAccountToken shared by both;
offers never run out (written to 2027-04-06, then the rule's cycle); Shop
Hide owned and App Store labels."

**Privacy inventory (for the integrator's privacy work)**: the client now
stores `user://service_route.cfg` (deployment name, receipt kind number,
reason, time; no personal data) and reads the App Store receipt's file
*name* only (`appStoreReceiptURL.lastPathComponent`; not a required-reason
API; the receipt's contents are never read). The service derives the
appAccountToken (sent to Apple with each purchase; purchase history is
already declared).

## 16. Notes for other streams

- **FRIENDS / presence**: profiles, rooms and presence are per deployment.
  Listen to `Cloud.deployment_changed(from, to)` to drop cached friend
  presence and re-register heartbeats (Cloud signs in again by itself after
  a move). Never cache a profile ID across deployments.
- **Integrator**: run `tools/build_native.sh` after merging (the untracked
  Linux library must be rebuilt for `test_native.gd` and
  `test_commerce_routing.gd`'s binding check; CI builds it every run).
  `tools/export_ios.sh` already declares privacy data when any of `url`,
  `production_url`, `sandbox_url` is set (integrator's change).
