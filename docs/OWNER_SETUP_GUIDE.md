# Owner setup guide: from the 2.0 candidate to an App Store submission

Steps only the account holder can take, in dependency order. Each step says
what to do, where, and how to check it worked. Nothing here has been done
on your accounts by the release work: no agreement accepted, no product
created, no service deployed, no purchase made, nothing submitted.
Background: [APP_STORE.md](APP_STORE.md) (copy-ready metadata),
[APP_STORE_READINESS.md](APP_STORE_READINESS.md) (status of every
requirement), [COMMERCE_SETUP.md](COMMERCE_SETUP.md) (service and purchase
details).

Never paste a private key, token or password into chat, the repository or
review notes.

## A. App identity and agreements

1. App Store Connect › Apps › **Ultimate Trifecta** (Apple ID 6818346960,
   bundle `com.idlery.ultimatetrifecta`). Reuse this record, its Game Center
   capability, the API key and the internal testing group. Don't create
   another app.
2. **Business** (account holder): accept the **Paid Apps Agreement** and
   complete tax and banking. Check: Business › Agreements shows "Paid Apps"
   as **Active**. Until then StoreKit returns no products (the Shop shows
   "Not available").
3. Pricing and Availability: choose the app's own price (for example Free)
   and the countries, separately from the in-app purchase prices.

## B. The eight in-app purchases

Apps › Ultimate Trifecta › Monetization › In-App Purchases. First check
what exists (or run the workflow with `iap=list`, read only). On
2026-10-05 none existed. Create each with exactly this type and ID (or run
the workflow once with `iap=create`, which creates the missing records
without prices or screenshots; check its result before running it again):

| Reference name | Type | Product ID | Display name | Description |
|---|---|---|---|---|
| Coins 250 | Consumable | `com.idlery.ultimatetrifecta.coins.250` | 250 Coins | 250 Coins for the Shop. Cosmetic only. |
| Coins 500 | Consumable | `com.idlery.ultimatetrifecta.coins.500` | 500 Coins | 500 Coins for the Shop. Cosmetic only. |
| Coins 1000 | Consumable | `com.idlery.ultimatetrifecta.coins.1000` | 1,000 Coins | 1,000 Coins for the Shop. Cosmetic only. |
| Coins 1500 | Consumable | `com.idlery.ultimatetrifecta.coins.1500` | 1,500 Coins | 1,500 Coins for the Shop. Cosmetic only. |
| Coins 3500 | Consumable | `com.idlery.ultimatetrifecta.coins.3500` | 3,500 Coins | 3,500 Coins for the Shop. Cosmetic only. |
| Coins 7500 | Consumable | `com.idlery.ultimatetrifecta.coins.7500` | 7,500 Coins | 7,500 Coins for the Shop. Cosmetic only. |
| Skin Moonlight Runner | Non-Consumable | `com.idlery.ultimatetrifecta.skin.moonlight_runner` | Moonlight Runner | A permanent outfit. Cosmetic only. |
| Skin Starry Sleeper | Non-Consumable | `com.idlery.ultimatetrifecta.skin.starry_sleeper` | Starry Sleeper | A permanent outfit. Cosmetic only. |

For each: set your price and availability; add the **review screenshot**
(a device screenshot of that product's purchase screen in the game: Shop ›
Coins for a pack, Shop › Featured › Always available › the outfit's page
for an outfit) and the review note from APP_STORE.md; resolve anything
App Store Connect lists as missing. Check: each shows "Ready to Submit".

Not Apple products (don't create them): Season 1 Premium (1,500 Coins),
Record Breaker and Dr. Doom (Season Pass rewards) and every Coin-priced
outfit or accessory. Keep in-app purchase **promotion off** (the game
doesn't handle promoted purchases).

## C. The game service (needed for Coins, purchases, Season rewards, Friends)

Apple products alone enable nothing in the game: every purchase, claim,
challenge, rotating offer, verified name and Friends status goes through
the game's service. Deploy it to your Cloudflare account, twice (sandbox
for TestFlight and App Review, production for the App Store), following
[COMMERCE_SETUP.md §3](COMMERCE_SETUP.md):

1. `cd service && npm test` (93 pass), `npx wrangler login`.
2. `npx wrangler d1 create trifecta` and `npx wrangler d1 create
   trifecta-production`; put both database IDs in `service/wrangler.toml`.
3. `scripts/gen_keys.sh` once (writes `service/.secrets/`, git-ignored, and
   prints the admission **public** key). It creates
   `app_account_token_key` (must be the same for both deployments and must
   never change once purchases exist) and `friend_hash_key`.
4. Set your real `SUPPORT_EMAIL`, `SUPPORT_URL` and `PRIVACY_URL` in
   `service/wrangler.toml` (both deployments).
5. `scripts/deploy.sh` (sandbox) and `DEPLOY_ENV=production
   scripts/deploy.sh` (production). They apply all migrations
   (0001–0006, Season 100 and Friends included) and upload the secrets.
6. Check: `curl -s https://trifecta-service.<sub>.workers.dev/v1/config`
   says `apple_environment: Sandbox` and lists `friends` in its features;
   the production URL says `Production`; `/v1/shop/offers` shows four
   current offers.
7. App Store Connect › the app › App Information › **App Store Server
   Notifications**, Version 2: Production Server URL
   `https://trifecta-service-production.<sub>.workers.dev/v1/appstore/notifications`,
   Sandbox Server URL
   `https://trifecta-service.<sub>.workers.dev/v1/appstore/notifications`.
8. In the repository, fill **public values only**:
   - `game/config/service.cfg`: `production_url`, `sandbox_url` and both
     `*_admission_public_key` (the key `gen_keys.sh` printed);
   - `game/config/links.cfg`: `privacy_url` and `support_url` (real,
     monitored https pages).
   Commit and push.

Keep the service running for the whole of App Review.

## D. Build the configured candidate

GitHub › Actions › "Build, test and ship (iOS)" › Run workflow on the
release branch with **upload** ticked and **distribution = app_store**.
Check in the run's last step:
- the build is `VALID`;
- its audience is `APP_STORE_ELIGIBLE` (the run fails if it isn't);
- it's available to your internal group (`IN_BETA_TESTING`).
Nothing is submitted by this. The earlier 1.9 (9) is internal-only and
can't be submitted.

## E. Test it with Apple's sandbox (TestFlight)

1. Users and Access › **Sandbox** › create a Sandbox Apple Account (a new
   email address you control; never your own Apple Account).
2. On the test iPhone: install the build from TestFlight. Settings ›
   Developer › Sandbox Apple Account: sign in with it (don't sign in to iCloud with it).
   TestFlight purchases are free sandbox purchases.
3. Minimum test, all must pass before submitting:
   - Shop › Coins shows six localized prices;
   - buy a small and a large pack: the Coins arrive once;
   - buy Moonlight Runner, delete and reinstall the app, Shop › Restore
     Purchases: it comes back;
   - buy a Coin outfit; buy Season 1 Premium; claim an earned Season reward;
   - relaunch: everything is still there;
   - cancel a purchase (nothing charged, nothing granted); turn on airplane
     mode right after confirming a purchase, then back on: it's delivered
     once;
   - Friends with a second device and account: each sees the other online,
     invite, accept, same party (docs/final/friends.md §11);
   - play an online round with the two devices and get the rewards;
   - Settings › Profile › Delete Game Profile.
   New products can take a while to reach the sandbox: check agreement, ID,
   price and availability before treating a missing product as a bug. A
   purchase sheet that succeeds but no Coins arriving is a service problem
   (check `/v1/config` and the service logs).

## F. The 2.0 version page

Apps › Ultimate Trifecta › iOS App › **+ Version: 2.0**. Choose the build
from step D. From APP_STORE.md: name, subtitle, description, promotional
text, keywords, categories, copyright (**yours**), Support URL and Privacy
Policy URL (the pages from C.8), App Privacy answers (the table, **not**
"Data Not Collected"), age-rating answers, export compliance (no
non-exempt encryption), review contact (**yours**) and the review notes
(sign in to Game Center; no password needed; ideally a link to a short
two-device Friends video). Screenshots: the 6.9" iPhone and 13" iPad sets
in `docs/media/final/store/` (or your own device screenshots); shots `03`,
`04`, `06` and `08` show Record Breaker or Dr. Doom, so use them only with
the permission below. Also decide:
written permission from the two people Record Breaker and Dr. Doom are
based on; mureka.ai's terms for the music; whether to keep the "Dr. Doom"
label.

## G. Submit

Add the 2.0 version **and all eight in-app purchases** to one submission
(Apple requires the first purchase of each type with a new version), check
the draft lists all eight, choose **Manually release this version**, then
Submit for Review. If Apple asks questions, the evidence and notes are in
the docs above. Apple decides approval; nothing here guarantees it.
