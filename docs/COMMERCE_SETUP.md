# Commerce setup: App Store products, the game service, and how to test (V6)

What exists in the repository and what the account holder still has to do,
in order. Nothing here was done on the owner's accounts: no App Store
Connect product was created, no service was deployed, no purchase was made,
no agreement was accepted.

| Piece | State |
|---|---|
| Catalogue, economy, Season 1 table | implemented (`game/config/catalogue.json`) |
| Shop, Locker, Season Pass, navigation | implemented; tested headless; captured on llvmpipe with test adapters |
| Native StoreKit 2 | the pinned GodotApplePlugins release's StoreKit module (`tools/fetch_deps.sh`), wrapped by `StoreKitAdapter` / `Purchases`; **not yet built for iOS by a CI run of this branch, never run on a device or in a sandbox** |
| Wallet / ledger service | implemented in `service/` with tests (`npm test`); **not deployed** |
| App Store products | **not created** (prepared: `tools/asc.py iap-plan`) |
| Real sandbox purchase | **never performed** |

## 1. Paid Applications agreement (account holder)

In-app purchases need the **Paid Applications** agreement, tax and banking
in App Store Connect › Business. Only the account holder can accept it.
Without it, StoreKit returns no products and the Shop shows them as
"Not available" (honestly; nothing breaks).

## 2. Create the five products

The product IDs, types and texts come from the catalogue:

```sh
python3 tools/asc.py iap-plan      # no credentials needed: what will be created
```

| Product ID | Type | Reference name | Display name |
|---|---|---|---|
| `com.idlery.ultimatetrifecta.coins.500` | Consumable | Coins 500 | 500 Coins |
| `com.idlery.ultimatetrifecta.coins.1500` | Consumable | Coins 1500 | 1,500 Coins |
| `com.idlery.ultimatetrifecta.coins.3500` | Consumable | Coins 3500 | 3,500 Coins |
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

Then, in App Store Connect › the app › In-App Purchases, for each product:

1. **Price**: pick it (the game always shows StoreKit's localized price; no
   price is written in the game).
2. **Review screenshot**: from `docs/media/v6/commerce/` (Shop Coins section
   for packs; the outfit's detail sheet for skins, once the art has landed).
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
npm test                                   # 37 tests, all must pass
npx wrangler login
npx wrangler d1 create trifecta            # id -> wrangler.toml [[d1_databases]]
scripts/gen_keys.sh                        # once; prints the admission public key
# optional but recommended: an App Store Connect In-App Purchase key
#   (App Store Connect › Users and Access › Integrations › In-App Purchase):
#   save the .p8 as .secrets/asc_iap_key.p8, its key ID in .secrets/asc_iap_key_id,
#   the issuer ID in .secrets/asc_iap_issuer_id
scripts/deploy.sh                          # migrations 0001 + 0002, secrets, deploy
curl -s https://trifecta-service.<sub>.workers.dev/v1/config   # apple_environment: Sandbox
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
  test adapters).
- **Xcode StoreKit testing**: `native/storekit/UltimateTrifecta.storekit`
  (regenerate with `python3 tools/make_storekit_config.py`) lists the five
  products with local test prices. In the exported Xcode project: Product ›
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
