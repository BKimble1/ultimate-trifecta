# Commerce setup: App Store products, the game service, and how to test (V6, Pass 8)

What exists in the repository and what the account holder still has to do,
in order. Nothing here was done on the owner's accounts: no App Store
Connect product was created, no service was deployed, no purchase was made,
no agreement was accepted.

| Piece | State |
|---|---|
| Catalogue, economy, Season 1 table | implemented (`game/config/catalogue.json`) |
| Pass 8 rotating offers | implemented: 12-week written schedule in the catalogue, service authority (`service/src/offers.js`, migration `0003_offers.sql`), client countdowns; **runs only once the service is deployed** (until then the Shop shows the honest service-off state) |
| Shop, Locker, Season Pass, navigation | implemented; tested headless; captured on llvmpipe with test adapters |
| Native StoreKit 2 | the pinned GodotApplePlugins release's StoreKit module (`tools/fetch_deps.sh`), wrapped by `StoreKitAdapter` / `Purchases`; **not yet built for iOS by a CI run of this branch, never run on a device or in a sandbox** |
| Wallet / ledger service | implemented in `service/` with tests (`npm test`); **not deployed** |
| App Store products | **not created**: 8 planned (`tools/asc.py iap-plan`); the read-only `iap-list` shows every one MISSING (the five V6 products were never created either) |
| Real sandbox purchase | **never performed** |

## 1. Paid Applications agreement (account holder)

In-app purchases need the **Paid Applications** agreement, tax and banking
in App Store Connect › Business. Only the account holder can accept it.
Without it, StoreKit returns no products and the Shop shows them as
"Not available" (honestly; nothing breaks).

## 2. Create the eight products

The product IDs, types and texts come from the catalogue:

```sh
python3 tools/asc.py iap-plan      # no credentials needed: what will be created
```

| Product ID | Type | Reference name | Display name |
|---|---|---|---|
| `com.idlery.ultimatetrifecta.coins.250` | Consumable | Coins 250 | 250 Coins (Pass 8) |
| `com.idlery.ultimatetrifecta.coins.500` | Consumable | Coins 500 | 500 Coins |
| `com.idlery.ultimatetrifecta.coins.1000` | Consumable | Coins 1000 | 1,000 Coins (Pass 8) |
| `com.idlery.ultimatetrifecta.coins.1500` | Consumable | Coins 1500 | 1,500 Coins |
| `com.idlery.ultimatetrifecta.coins.3500` | Consumable | Coins 3500 | 3,500 Coins |
| `com.idlery.ultimatetrifecta.coins.7500` | Consumable | Coins 7500 | 7,500 Coins (Pass 8) |
| `com.idlery.ultimatetrifecta.skin.moonlight_runner` | Non-Consumable | Skin Moonlight Runner | Moonlight Runner |
| `com.idlery.ultimatetrifecta.skin.starry_sleeper` | Non-Consumable | Skin Starry Sleeper | Starry Sleeper |

Two ways to create them (the integrator decides; both leave prices to you):

- **Workflow:** run "Build, test and ship (iOS)" with **iap = list** (read
  only: shows MISSING / present / unexpected), then **iap = create**. It
  creates only the missing products with their en-US name, description and
  review note, family sharing off. It never sets a price, never uploads a
  screenshot, never submits anything and never changes an existing product.
  It uses the existing `ASC_*` repository secrets (the key needs App Manager
  or Admin).
- **Locally:** `ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… python3 tools/asc.py iap-list`,
  then `python3 tools/asc.py iap-create --yes`.
- **Check first, without credentials:** `python3 tools/asc.py iap-list --json > have.json`
  (read only) and `python3 tools/asc.py iap-diff have.json` print exactly what
  `iap-create` would create. Against today's App Store Connect (nothing
  created) that is all eight; if the five V6 products are created first, only
  the three new packs. `service/test/offers.test.mjs` runs both cases.

Then, in App Store Connect › the app › In-App Purchases, for each product:

1. **Price**: pick it (the game always shows StoreKit's localized price; no
   price is written in the game). The three new packs (250, 1,000, 7,500)
   need price points too: an owner decision. "Best value" is shown on a pack
   only when the real StoreKit prices make it strictly cheapest per Coin.
2. **Review screenshot**: Apple wants the purchase as the player sees it.
   For every Coin pack: the Shop's Coins section
   (`docs/media/pass8/shop/<device>/shop_coins.png` shows the layout with
   the simulated store's "(test price)" labels: take the real one from a
   TestFlight build once prices exist, since a review screenshot must not
   show a test label). For the skins: the outfit's detail sheet. Re-take
   them on a device; the repository's captures are desktop renders.
3. The products reach **Ready to Submit**; that is enough for TestFlight
   sandbox testing. They go to review with the next App Store submission.

Season 1 Premium is **not** an App Store product: it costs 1,500 Coins.

## 3. Deploy the game service (sandbox first)

TestFlight builds use Apple's **sandbox**; App Store builds production. Each
has its own deployment and database (`APPLE_ENVIRONMENT` decides which
App Store environment a deployment accepts; every row also carries the
environment), so a sandbox credit can never become a production balance.

From `service/README.md`, plus the V6 steps:

```sh
cd service
npm test                                   # all must pass (54 after the Pass 8 Shop work)
npx wrangler login
npx wrangler d1 create trifecta            # id -> wrangler.toml [[d1_databases]]
scripts/gen_keys.sh                        # once; prints the admission public key
# optional but recommended: an App Store Connect In-App Purchase key
#   (App Store Connect › Users and Access › Integrations › In-App Purchase):
#   save the .p8 as .secrets/asc_iap_key.p8, its key ID in .secrets/asc_iap_key_id,
#   the issuer ID in .secrets/asc_iap_issuer_id
scripts/deploy.sh                          # migrations 0001-0003, secrets, deploy
curl -s https://trifecta-service.<sub>.workers.dev/v1/config   # apple_environment: Sandbox, features include shop_offers
curl -s https://trifecta-service.<sub>.workers.dev/v1/shop/offers   # server_time and the four current offers
```

Then put the URL and admission public key in `game/config/service.cfg` and
build (the export then declares user ID, name, gameplay content, other user
content and **purchase history** in the privacy manifest automatically).

**App Store Server Notifications (refunds):** App Store Connect › the app ›
App Information › App Store Server Notifications: Version 2, Sandbox URL
`https://trifecta-service.<sub>.workers.dev/v1/appstore/notifications`.
(Production URL: the production deployment's, below.)

**Production (App Store builds only, later):** `npx wrangler d1 create
trifecta-production`, put its id in `[env.production]` of `wrangler.toml`,
`DEPLOY_ENV=production scripts/deploy.sh`, and point App Store builds at that
deployment. Never point a TestFlight build at it.

What the service does with a purchase (`POST /v1/wallet/apple`):

1. Verifies the StoreKit 2 JWS: Apple Root CA - G3 (pinned SHA-256), the
   intermediate and leaf marker OIDs, each ECDSA signature, validity at the
   signed date, the JWS signature (`service/src/appstore.js`).
2. With the In-App Purchase key: asks the App Store Server API for the same
   transaction (sandbox or production host by deployment) and uses Apple's
   copy.
3. Checks bundle, environment, product, type and the `appAccountToken`
   (the UUID the service issued to this profile; a Coin pack bought for
   another profile is refused with `account_mismatch`).
4. Delivers once per transaction ID (primary key + ledger key), in one batch.
5. The app finishes the StoreKit transaction only after that reply.

## 4. Test procedure (sandbox, TestFlight)

Tester devices need a **Sandbox Apple Account** (App Store Connect › Users
and Access › Sandbox) signed in under Settings › Developer (or the App Store
sign-in prompt in TestFlight). TestFlight purchases are free.

1. Install the TestFlight build with the service URL configured; sign in to
   Game Center.
2. **Shop › Coins**: prices show in the local currency. Buy 500 Coins: Apple's
   sheet opens from the tap, the button reads "Adding…", then "+500 Coins
   added"; the Coins chip updates in place.
3. **Duplicate/interruption**: buy, then force-quit the app on Apple's
   "You're all set" sheet; reopen: delivered once (check the balance).
   Turn on Airplane Mode right after confirming a purchase: the Shop keeps it
   "Adding…"; turn it off: delivered once.
4. **Ask to Buy**: with a sandbox child account (or the sandbox setting
   "Ask to Buy"), the item shows "Waiting for approval"; approve in
   Settings › Developer › Sandbox Account: delivered.
5. **Cancel**: cancel Apple's sheet: "Purchase cancelled. You weren't
   charged."
6. **Skins**: buy Moonlight Runner; it's in the Locker and Owned in the Shop.
   Delete and reinstall (or a second device, same sandbox account): Shop ›
   Restore Purchases brings it back; Coins and Coin-bought items come back
   from the account (Game Center sign-in), never as fresh credit.
7. **Refund**: in Settings › Developer › Sandbox Account › Manage, request
   a refund (or use App Store Connect's sandbox refund testing): the skin is
   revoked / the Coins are taken back; other items stay.
8. **Spend**: buy a Coin item (confirmation shows item, cost, balance left)
   and Season 1 Premium; claim Free and Premium rewards; Claim all twice.
8b. **Rotating offers (Pass 8)**: Shop › Featured shows four skins, each
   "Leaves in …", and "Shop refreshes in …"; the detail shows your local
   departure time. Buy one: it's in the Locker. Change the device clock or
   time zone: the countdowns don't move and nothing new becomes buyable.
   Leave the Shop open across 00:00 UTC (or come back after it): two cards
   change in place; an ended skin's sheet says "Not in current rotation";
   the skin you bought stays in the Locker. Airplane Mode, force-quit,
   reopen: "Connect to refresh Shop", nothing buyable until online.
8c. **Six Coin packs**: 250 / 500 / 1,000 / 1,500 / 3,500 / 7,500 with
   localized prices; buy the 250 and the 7,500 once each.
8d. **Season 1 to tier 100 (Pass 9)**: the deploy applies migration
   `0005_season_100.sql` with the others (`scripts/deploy.sh`). The pass
   shows "Tier N / 100", the navigation row (You're at, Next reward, 30 /
   50 / 100) and progress runs. Reaching tier 50 or 100 takes real play
   (≈105 / ≈225 regular rounds); to check the tier-50 and tier-100 claims
   sooner, set a **sandbox** test profile's Season XP directly in the
   sandbox database only, e.g. `npx wrangler d1 execute trifecta --remote
   --command "UPDATE season_progress SET xp = 15300 WHERE profile_id = '<test
   profile>' AND environment = 'sandbox'"` (never on the production
   database; there is deliberately no API for it). Then: Record Breaker is
   Premium-locked without Premium, claimable with it, claimed once (Claim
   again, a second device, Airplane Mode during the claim: still once).
   [docs/pass9/season.md](pass9/season.md) lists every case.
9. **Rounds**: a two-phone party through the service: after a completed
   round both see "+N Coins · +X Season XP" on results (or the honest
   reason); practice says it doesn't add Coins.
10. Record what you see (screenshots) next to the build number: that is the
    first real purchase evidence. None exists yet.

## 5. Local testing without Apple (developers)

- **Game tests** (headless): `tools/run_tests.sh test_purchases`,
  `test_wallet`, `test_shop_ui`, `test_catalogue` use the simulated store
  (`game/src/dev/test_store_adapter.gd`) and the test-double service
  (`game/src/dev/fake_commerce_service.gd`). Both live in `src/dev/`, which
  the iOS export excludes, so a shipped build can't select them.
- **Service tests**: `cd service && npm test` (a per-run test certificate
  chain shaped like Apple's; the real Apple root stays pinned).
- **Captures**: `tools/capture_v6_commerce.sh OUT [phone se ipad]` (labelled
  test adapters); Pass 8 Shop: `tools/capture_pass8_shop.sh OUT [se p14 ipad]`
  (DEV FIXTURE service clock and schedule, labelled on every shot); Pass 9
  Season Pass: `tools/capture_pass9_season.sh OUT [se p14 pmax ipad]`
  (test-double service, labelled).
- **Rotation schedule**: `python3 tools/make_offer_schedule.py --check`;
  regenerate as in [ECONOMY.md](ECONOMY.md) §2.1.
- **Xcode StoreKit testing**: `native/storekit/UltimateTrifecta.storekit`
  (regenerate with `python3 tools/make_storekit_config.py`) lists the eight
  products with local test prices (identical for every consumable, so the
  computed "Best value" lands on the largest pack there; that is a local
  test value, not a price suggestion). In the exported Xcode project: Product ›
  Scheme › Edit Scheme › Run › Options › StoreKit Configuration. Xcode-signed
  transactions are rejected by the service (`wrong_environment` / root), so
  this exercises the StoreKit UI and the app's states only.

## 6. Support and reconciliation

```sh
export TRIFECTA_SERVICE=https://trifecta-service.<sub>.workers.dev
curl -s -H "Authorization: Bearer $(cat service/.secrets/admin_token)" "$TRIFECTA_SERVICE/v1/admin/wallets/<profile_id>"
# grant Coins (support) or forgive refund debt, once per key:
curl -s -X POST -H "Authorization: Bearer …" -H 'content-type: application/json' \
  -d '{"amount":500,"note":"support ticket 12","idempotency_key":"ticket-12"}' "$TRIFECTA_SERVICE/v1/admin/wallets/<profile_id>/adjust"
```

Rejected rounds (`round_rejected`), digest mismatches (`round_mismatch`),
legacy imports and refunds are in the audit log (`node tools/admin.mjs audit`).
