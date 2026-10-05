# Commerce setup: App Store products, the game service, and how to test (final release)

What exists in the repository and what the account holder still has to do,
in order. Nothing here was done on the owner's accounts: no App Store
Connect product was created, no service was deployed, no purchase was made,
no agreement was accepted. The design and its evidence are in
[docs/final/commerce.md](final/commerce.md).

| Piece | State |
|---|---|
| Catalogue, economy, Season 1 (100 tiers) | implemented (`game/config/catalogue.json`) |
| Rotating offers | implemented: a 26-week written schedule (to 2027-04-06), then the same rule continued by the service from a generated cycle, so the Shop never runs empty; **runs only once the service is deployed** |
| Shop, Locker, Season Pass | implemented; tested headless; captured on llvmpipe with labelled test adapters |
| Native StoreKit 2 | the pinned GodotApplePlugins release's StoreKit module (`tools/fetch_deps.sh`, build `bfade13`), wrapped by `StoreKitAdapter` / `Purchases`; audited against the plugin source; **never run on a device or in a sandbox** |
| One build for TestFlight, App Review and the App Store | implemented: two service deployments (sandbox, production), launch routing from the App Store receipt kind (new `UTShare.receipt_kind()`), automatic move to the sandbox deployment when production refuses an Apple *sandbox* purchase (App Review); tested with the service harness and the simulated store; **never run on a device** |
| Wallet / ledger service | implemented in `service/` with tests (`npm test`, 80); **not deployed** |
| App Store products | **not created**: 8 planned (`tools/asc.py iap-plan`) |
| Real sandbox purchase | **never performed** |

## 1. Paid Applications agreement (account holder)

In-app purchases need the **Paid Applications** agreement, tax and banking
in App Store Connect › Business. Only the account holder can accept it.
Without it, StoreKit returns no products and the Shop shows each one as
"Not available" (honestly; nothing breaks).

## 2. Create the eight products

The product IDs and types come from the catalogue and must stay exactly as
they are:

| Product ID | Type | Reference name | Display name | Delivers |
|---|---|---|---|---|
| `com.idlery.ultimatetrifecta.coins.250` | Consumable | Coins 250 | 250 Coins | 250 Coins |
| `com.idlery.ultimatetrifecta.coins.500` | Consumable | Coins 500 | 500 Coins | 500 Coins |
| `com.idlery.ultimatetrifecta.coins.1000` | Consumable | Coins 1000 | 1,000 Coins | 1,000 Coins |
| `com.idlery.ultimatetrifecta.coins.1500` | Consumable | Coins 1500 | 1,500 Coins | 1,500 Coins |
| `com.idlery.ultimatetrifecta.coins.3500` | Consumable | Coins 3500 | 3,500 Coins | 3,500 Coins |
| `com.idlery.ultimatetrifecta.coins.7500` | Consumable | Coins 7500 | 7,500 Coins | 7,500 Coins |
| `com.idlery.ultimatetrifecta.skin.moonlight_runner` | Non-Consumable | Skin Moonlight Runner | Moonlight Runner | the outfit, permanently (restorable) |
| `com.idlery.ultimatetrifecta.skin.starry_sleeper` | Non-Consumable | Skin Starry Sleeper | Starry Sleeper | the outfit, permanently (restorable) |

Season 1 Premium is **not** an App Store product: it costs 1,500 Coins.
Record Breaker and Dr. Doom are Season Pass rewards, not products. Do not
create a product for any Coin-priced item.

Two ways to create them (both leave prices to you):

- **Workflow:** run "Build, test and ship (iOS)" with **iap = list** (read
  only: shows MISSING / present / unexpected), then **iap = create** (only
  the missing ones, en-US name, description and review note, family sharing
  off; never a price, a screenshot or a submission). Check the result before
  running create again.
- **Locally:** `ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… python3 tools/asc.py iap-list`,
  then `python3 tools/asc.py iap-create --yes`.

Then, for each product in App Store Connect › the app › Monetization › In-App
Purchases:

1. **Price and availability**: your choice. The game always shows
   StoreKit's localized price and never stores one. "Best value" appears on
   a pack only when the real prices make it strictly cheapest per Coin.
2. **Review screenshot**: the purchase as the player sees it, taken on a
   device from a TestFlight build once prices exist (a review screenshot must
   not show the simulated store's "(test price)"):
   - Coin packs: **Shop › Coins** (all six packs with their prices).
   - Outfits: **Shop › Featured › Always available › the outfit** (its
     detail with the Buy button), or **Shop › All skins** (marked
     "App Store").
   The repository's layout references are desktop renders with a test
   store: `docs/media/final/commerce/<device>/shop_coins_simulated_prices.jpg`
   and `shop_detail_app_store_outfit.jpg`.
3. The products reach **Ready to Submit**; that is enough for TestFlight
   sandbox testing. They go to review with the app version (all eight in
   the same submission: the first consumable and non-consumable must
   accompany a new app version).

Both outfits and all six packs are always in the Shop (never only during a
rotation), so App Review can always reach every product the normal way.

## 3. Deploy the game service: two deployments

One build works in TestFlight, in App Review and on the App Store, with
sandbox and real-money value kept apart:

- **sandbox** deployment (wrangler default, `trifecta-service`, database
  `trifecta`, `APPLE_ENVIRONMENT=Sandbox`): TestFlight, Xcode builds and App
  Review purchases. Its Coins and items are worth nothing outside it.
- **production** deployment (`[env.production]`, `trifecta-service-production`,
  database `trifecta-production`, `APPLE_ENVIRONMENT=Production`): App Store
  customers.

Each deployment credits **only its own App Store environment**. The game
picks one at launch (App Store install → production; TestFlight → sandbox)
and, if the production deployment answers a verified Apple *sandbox*
purchase with `409 sandbox_purchase` (App Review), moves that install to
the sandbox deployment as the same Game Center player and delivers the
still-unfinished purchase there, once. Details and the security argument:
[docs/final/commerce.md](final/commerce.md).

```sh
cd service
npm test                                    # all must pass (80)
npx wrangler login                          # or export CLOUDFLARE_API_TOKEN
npx wrangler d1 create trifecta             # id -> wrangler.toml [[d1_databases]] database_id
npx wrangler d1 create trifecta-production  # id -> wrangler.toml [[env.production.d1_databases]] database_id
scripts/gen_keys.sh                         # once: service/.secrets/ (git-ignored); prints the admission PUBLIC key
# optional, recommended: an App Store Connect In-App Purchase key (App Store
# Connect › Users and Access › Integrations › In-App Purchase): save the .p8
# as .secrets/asc_iap_key.p8, its key ID in .secrets/asc_iap_key_id and the
# issuer ID in .secrets/asc_iap_issuer_id (one key serves both deployments)
scripts/deploy.sh                           # sandbox: migrations, secrets, deploy
DEPLOY_ENV=production scripts/deploy.sh     # production: the same, its own database
curl -s https://trifecta-service.<sub>.workers.dev/v1/config              # apple_environment: Sandbox
curl -s https://trifecta-service-production.<sub>.workers.dev/v1/config   # apple_environment: Production
curl -s https://trifecta-service.<sub>.workers.dev/v1/shop/offers         # server_time and four current offers
```

**Secrets** (`deploy.sh` uploads them from `service/.secrets/` with
`wrangler secret put`; never commit or paste them):

| Secret | File | Rule |
|---|---|---|
| `SESSION_KEY` | `session_key` | session tokens (they are bound to their deployment's environment) |
| `ADMIN_TOKEN` | `admin_token` | moderation and support API |
| `ADMISSION_PRIVATE_KEY` | `admission_private.pem` | signs party admission and chat tokens |
| `APP_ACCOUNT_TOKEN_KEY` | `app_account_token_key` | **new**: derives each player's StoreKit appAccountToken. **The same value on both deployments** (deploying both from one `.secrets/` folder does that). Never change it once purchases exist: unfinished purchases carry tokens derived from it. Without it a deployment refuses to deliver purchases (`503`, kept unfinished) and the game offers none. |
| `ASC_IAP_KEY_ID`, `ASC_IAP_ISSUER_ID`, `ASC_IAP_PRIVATE_KEY` | `asc_iap_*` | optional: Apple's App Store Server API copy of each transaction |

**The game's configuration** (`game/config/service.cfg`; public values only):

```ini
[service]
production_url="https://trifecta-service-production.<sub>.workers.dev"
production_admission_public_key="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
sandbox_url="https://trifecta-service.<sub>.workers.dev"
sandbox_admission_public_key="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
url=""
admission_public_key=""
```

With one `.secrets/` folder both deployments share the admission key pair,
so both public keys are the one `gen_keys.sh` printed. `url` /
`admission_public_key` are only a development fallback (used when neither
pair is set). Then build and upload: the export declares the collected data
in the privacy manifest when any URL is set.

**App Store Server Notifications V2** (refunds, revocations): App Store
Connect › the app › App Information › App Store Server Notifications:

- Production Server URL: `https://trifecta-service-production.<sub>.workers.dev/v1/appstore/notifications`
- Sandbox Server URL: `https://trifecta-service.<sub>.workers.dev/v1/appstore/notifications`
- Version 2 for both. Each deployment refuses the other environment's
  notifications (`400 wrong_environment`), so a swapped URL is visible in
  App Store Connect's delivery log and changes nothing.

What the service does with a purchase (`POST /v1/wallet/apple`):

1. Verifies the StoreKit 2 JWS: Apple Root CA - G3 (pinned SHA-256), the
   intermediate and leaf marker OIDs, each ECDSA signature, validity at the
   signed date, the JWS signature (`service/src/appstore.js`).
2. Checks the bundle, then the environment: the other environment's verified
   purchase gets `409 sandbox_purchase` / `production_purchase` (nothing
   recorded or credited; the game moves); anything else (Xcode) is
   `wrong_environment`.
3. With the In-App Purchase key: asks the App Store Server API (this
   deployment's host) for the same transaction and uses Apple's copy.
4. Checks product, type and the `appAccountToken` (derived for the caller's
   Game Center player; another player's purchase is `account_mismatch`).
5. Delivers once per transaction ID (primary key + ledger key), in one batch.
6. The app finishes the StoreKit transaction only after that reply.

## 4. Test procedure (sandbox, TestFlight)

Tester devices need a **Sandbox Apple Account** (App Store Connect › Users
and Access › Sandbox), signed in on the device under Settings › Developer
(or at the App Store sign-in prompt in TestFlight), never as the device's
main Apple Account. TestFlight purchases are free sandbox transactions. A
TestFlight build talks to the **sandbox** deployment by itself.

1. Install the TestFlight build with both URLs configured; sign in to Game
   Center.
2. **Shop › Coins**: six packs with prices in the local currency (no
   "(test price)", no "Not available"). Buy 250 and 7,500 Coins: Apple's
   sheet opens from the tap, the card reads "Adding to your account…",
   then "+250 Coins added"; the Coins chip updates.
3. **Interruption**: buy, then force-quit on Apple's "You're all set"
   sheet; reopen: delivered once. Airplane Mode right after confirming:
   the pack stays "Adding…"; Airplane Mode off: delivered once.
4. **Ask to Buy**: with a sandbox child account (or the sandbox setting),
   the item shows "Waiting for approval"; approve: delivered.
5. **Cancel**: cancel Apple's sheet: "Purchase cancelled. You weren't
   charged."
6. **Outfits**: buy Moonlight Runner and Starry Sleeper (Shop › Featured ›
   Always available); both are in the Locker and Owned in the Shop
   (All skins with Hide owned on: gone). Delete and reinstall (or a second
   device, the same Apple Account and Game Center player): Shop › Restore
   Purchases brings both back; Coins and Coin-bought items come back from
   the account, never as fresh credit.
7. **Refund**: request a refund for a sandbox purchase (Settings ›
   Developer › Sandbox Account › Manage, or App Store Connect's sandbox
   refund testing): the outfit is revoked / the Coins are taken back; other
   items stay.
8. **Spend**: buy a Coin item (the confirmation shows the item, its cost,
   your Coins and what's left) and Season 1 Premium; earned Premium rewards
   become claimable; Claim all twice (second time: nothing more).
9. **Rotating offers**: Shop › Featured shows four skins with "Leaves
   in …" and "Shop refreshes in …". Device clock or time zone changes don't
   move the countdowns or make anything buyable; leave a sheet open across
   00:00 UTC: it says "Not in current rotation" and nothing is charged.
10. **Season to tier 100**: as before (docs/pass9/season.md); to check tier
    50 and 100 sooner, set a sandbox test profile's XP in the **sandbox**
    database only (`npx wrangler d1 execute trifecta --remote --command
    "UPDATE season_progress SET xp = 15300 WHERE profile_id = '<test profile>'
    AND environment = 'sandbox'"`); never on production.
11. **Rounds**: a two-phone party: after a completed round both see
    "+N Coins · +X Season XP" (or the honest reason).
12. Record what you see (screenshots) next to the build number. Keep StoreKit
    success (Apple's sheet) apart from delivery (Coins/item in the game).

**The App Review path (production refuses a sandbox purchase)** can only be
seen with an App Store-signed build; it is covered by tests
(`service/test/environments.test.mjs`, `game/tests/test_commerce_routing.gd`).
After release, an App Store install (receipt "receipt") uses production; a
TestFlight install uses the sandbox. Players on TestFlight and on the App
Store are in separate economies **and separate party directories**: they
can't join each other's parties through the service.

## 5. Local testing without Apple (developers)

- **Game tests** (headless): `tools/gd.sh --headless --fixed-fps 60 --path
  game -s res://tests/run_tests.gd -- test_purchases.gd:,test_wallet.gd:,test_commerce_routing.gd:,test_shop_filters.gd:,test_shop_ui.gd:,test_shop_rotation.gd:`
  use the simulated store (`game/src/dev/test_store_adapter.gd`) and the
  test-double service (`game/src/dev/fake_commerce_service.gd`, which also
  stands in for both deployments). Both live in `src/dev/`, which the iOS
  export excludes.
- **Native library**: `tools/build_native.sh` (CI builds it every run; the
  `bin/` folder isn't committed). `test_native.gd` checks `receipt_kind()`.
- **Service tests**: `cd service && npm test` (a per-run test certificate
  chain shaped like Apple's; the real Apple root stays pinned; two in-memory
  databases stand in for the two deployments).
- **Captures**: `tools/capture_final_shop.sh OUT [se p14 ipad]` (filters,
  App Store outfits, Coin packs with simulated and unavailable prices,
  owned states, the offer cycle; DEV FIXTURE labelled on every shot).
- **Rotation schedule**: `python3 tools/make_offer_schedule.py --check`;
  regenerate as in [ECONOMY.md](ECONOMY.md) §2.1, then `node
  service/tools/sync_catalogue.mjs`.
- **Xcode StoreKit testing**: `native/storekit/UltimateTrifecta.storekit`
  lists the eight products with local test prices. Xcode-signed
  transactions are refused by both deployments (root / `wrong_environment`),
  so this exercises the StoreKit UI and the app's states only.

## 6. Support and reconciliation

Each deployment has its own database; use the one the player is on
(TestFlight → sandbox, App Store → production):

```sh
export TRIFECTA_SERVICE=https://trifecta-service-production.<sub>.workers.dev
curl -s -H "Authorization: Bearer $(cat service/.secrets/admin_token)" "$TRIFECTA_SERVICE/v1/admin/wallets/<profile_id>"
# grant Coins (support) or forgive refund debt, once per key:
curl -s -X POST -H "Authorization: Bearer …" -H 'content-type: application/json' \
  -d '{"amount":500,"note":"support ticket 12","idempotency_key":"ticket-12"}' "$TRIFECTA_SERVICE/v1/admin/wallets/<profile_id>/adjust"
```

Rejected rounds (`round_rejected`), digest mismatches (`round_mismatch`),
legacy imports and refunds are in the audit log (`node tools/admin.mjs audit`).
A purchase kept unfinished because of `account_mismatch` belongs to the
Game Center player it was bought for: signing in with that player delivers it.
