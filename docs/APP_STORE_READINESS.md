# App Store readiness: version 2.0 release candidate

Status of every meaningful requirement for submitting Ultimate Trifecta 2.0,
with the evidence behind it. Statuses:

- **READY**: implemented and checked, with the evidence named.
- **OWNER SETUP REQUIRED**: the code is ready; an account holder action or
  value is missing (listed in the final handoff and
  [APP_STORE.md](APP_STORE.md)).
- **NOT VERIFIED**: implemented, but only a device, Apple's sandbox or the
  deployed service can prove it; nobody has observed it yet.
- **BLOCKED**: can't be submitted as is.

Apple's rules were rechecked on 2026-10-05 (App Review Guidelines, upload
requirements, screenshot specifications, age-rating questionnaire, IAP
submission). Apple decides approval; nothing here guarantees it.

## Release candidate

| | |
|---|---|
| Version (build) | **2.0 (10)**, App Store Connect build `1730ad62-0823-49a6-a534-1e7bb79e3935` |
| Commit | `66e7575` |
| Upload | GitHub Actions run #145 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37431364875), `upload=true`, `distribution=app_store`; uploaded 2026-10-06 08:02:44 UTC; CI gate 561 tests, 107,273 checks, 0 failures |
| Distribution | Audience **`APP_STORE_ELIGIBLE`** as recorded by Apple (`testFlightInternalTestingOnly=false`); delivered to the existing internal group only |
| Apple processing | **`VALID`**; internal `IN_BETA_TESTING`; external `READY_FOR_BETA_SUBMISSION` (nothing sent); What to Test set (1,813 characters); read from Apple's API by run #145 at 08:20 UTC |
| Label | **Provisional**: the service is off (`service.cfg` empty) and no product exists. Not the launch build; don't submit it. The launch build is the next `distribution=app_store` upload after OWNER_SETUP_GUIDE A–C. |

## Requirements

### Binary and distribution

| # | Requirement | Status | Evidence | Owner action |
|---|---|---|---|---|
| B1 | Built with Xcode 26+ and the iOS 26 SDK (Apple's upload requirement since 2026-04-28) | READY | 2.0 (10) build facts (run #145): Xcode 26.6 (17F113), iOS SDK 26.5 | – |
| B2 | Deployment target, architecture, devices, orientations | READY | iOS 17.0+, arm64, iPhone and iPad, landscape left/right, `iphone-ipad-minimum-performance-a12` (build facts, Info.plist) | – |
| B3 | An App Store-eligible build (not "TestFlight internal testing only") | READY | 2.0 (10): Apple recorded `APP_STORE_ELIGIBLE` (run #145's audience check); `build_ios.sh` refuses an unset audience (R1) | Choose the **configured** rebuild (not 2.0 (10)) in the version page |
| B4 | Version and build numbers increase | READY | 2.0 (build = highest + 1); one marketing version everywhere (`test_release_config`) | – |
| B5 | Entitlements and capabilities | READY | Game Center entitlement only; In-App Purchase needs none; Game Center enabled on the app ID (existing) | – |
| B6 | Embedded frameworks are device slices | READY | run #145 build facts: GodotApplePluginsGameCenter, GodotApplePluginsStoreKit, SwiftGodotRuntime and UTShare embedded in the signed iphoneos archive; the app binary and UTShare checked arm64; Apple processed the build `VALID` | – |
| B7 | No development or test code, fixtures or grants in the build | READY | export preset excludes `tests/`, `tools/`, `src/dev/`; a local iOS pack contains none of them; dev flags need a command line iOS doesn't have (`test_release_config`) | – |
| B8 | Config files the game needs actually ship | READY | `config/*.cfg` in the preset; `export_ios.sh` fails without `config/service.cfg` in the pack (R4) | – |
| B9 | A green job can't hide a failed upload or rejected build | READY | FAILED/INVALID fails the run; audience mismatch fails the run; still-processing is a warning, never reported as available (R2) | – |
| B10 | Launch screen and branding | READY | run #145 launch and branding audit PASS (one black storyboard, 1656² launch images, logo box off by 0.0000, no "powered by") | – |
| B11 | Symbols | READY (warning) | Xcode notes no dSYMs for the four plugin frameworks; the app's own symbols upload | – |

### Services and commerce

| # | Requirement | Status | Evidence | Owner action |
|---|---|---|---|---|
| S1 | The game service is deployed (sandbox and production) and the build points at it | **OWNER SETUP REQUIRED** (blocks a launch build) | `game/config/service.cfg` is empty in the provisional candidate: Coins, purchases, Season rewards, challenges, rotating offers, verified names, typed chat, reports and Friends status show as unavailable | Deploy both deployments (`service/README.md`), fill the four `service.cfg` keys, rebuild with `distribution=app_store` |
| S2 | Eight in-app purchase products exist with prices, metadata and review screenshots | **OWNER SETUP REQUIRED** | read-only status run #132 (2026-10-05 22:33 UTC): 8 planned, 0 present | Create them (manually or `iap=create`), price them, add review screenshots |
| S3 | Paid Apps Agreement, tax and banking | **OWNER SETUP REQUIRED** | not readable by the API key | Account holder: Business › Agreements |
| S4 | Purchases work in TestFlight, App Review and the App Store with sandbox and production kept apart | READY in code · NOT VERIFIED live | `service/test/environments.test.mjs`, `game/tests/test_commerce_routing.gd`, docs/final/commerce.md §1–§2 | Run the sandbox checklist (COMMERCE_SETUP) on the configured build |
| S5 | Every purchase flow (packs, outfits, Coin items, Premium, claims, cancel, pending, interruption, restore, account mismatch, refund, offer expiry, concurrency) | READY in code · NOT VERIFIED live | docs/final/commerce.md §6 (tests per flow), service 93/93 | Device checklist |
| S6 | App Store Server Notifications V2 | READY in code · OWNER SETUP REQUIRED | each deployment verifies the signed payload and its environment | Enter the two notification URLs (COMMERCE_SETUP) |
| S7 | Reviewers can reach every submitted product | READY | both outfits and all six packs always listed (Featured › Always available, All skins, Coins), offline and service-off included | – |
| S8 | Promoted in-app purchases | NOT SUPPORTED (keep off) | the StoreKit wrapper doesn't handle purchase intents | Don't enable promotion for these products |
| S9 | Prices from StoreKit only; no test prices | READY | localized `displayPrice`; "Not available" when StoreKit returns nothing | – |

### Privacy, accounts and safety

| # | Requirement | Status | Evidence | Owner action |
|---|---|---|---|---|
| P1 | Privacy policy and support links in the app and the metadata | **OWNER SETUP REQUIRED** | `config/links.cfg` (shipped, https only) and the service's config are both empty | Publish the pages; fill `links.cfg` and the service vars; rebuild |
| P2 | App Privacy answers match the app | READY (drafted) · OWNER enters them | APP_STORE.md "App Privacy" = the generated privacy manifest (user ID, name, gameplay content, other user content, purchase history, contacts, product interaction; linked, app functionality, no tracking) | Enter in App Store Connect |
| P3 | Privacy manifest and required-reason APIs | READY | Godot's PrivacyInfo.xcprivacy (file timestamp DDA9.1/C617.1, system boot time) in the build facts; collected data declared when a service endpoint is configured (R5) | – |
| P4 | Tracking / ATT | READY (not needed) | no tracking, no advertising SDKs, `tracking_enabled=false` | – |
| P5 | Account deletion in the app | READY in code · NOT VERIFIED live | Settings › Profile › Delete Game Profile; service deletion incl. friends, presence, invites, wallet (service tests); local data erased; a failed request is reported as failed | Try it on the configured build |
| P6 | Sign-in requirements | READY (n/a) | Game Center is the only sign-in; no third-party login, so Sign in with Apple isn't required | – |
| P7 | User-generated content: filter, report, block, contact, timely response | READY in code · OWNER SETUP REQUIRED | names and typed chat filtered by the service; report with receipt; block; host remove (docs/MODERATION.md) | Support contact; watch the report queue |
| P8 | Friends permission and data | READY · NOT VERIFIED on device | updated NSGKFriendListUsageDescription; mutual-only status, keyed hashes, 60 s presence, "Show when I'm playing" (docs/final/friends.md) | Two-device test (friends.md §11) |

### Content and metadata

| # | Requirement | Status | Evidence | Owner action |
|---|---|---|---|---|
| M1 | Name, subtitle, description, keywords, promotional text within limits and accurate | READY (drafted) | APP_STORE.md (counts checked) | Paste; adjust if you wish |
| M2 | Screenshots: 6.9" iPhone and 13" iPad | READY as candidates | `docs/media/final/store/`: 8 iPhone shots at 2868 × 1320 and 8 iPad shots at 2752 × 2064, rendered from the release art, `store_shot_check.py` 19/19 pass, fictional names, no debug text; desktop renders, not device captures | Approve or replace with device shots; `03`, `04`, `06`, `08` show the likeness skins (M6) |
| M3 | Review notes, contact, demo | READY (drafted) · OWNER fields | APP_STORE.md review notes | Contact details; optional two-device video |
| M4 | Age rating questionnaire | READY (answers drafted) · OWNER enters | APP_STORE.md table | Answer in App Store Connect |
| M5 | Export compliance | READY | `ITSAppUsesNonExemptEncryption=false` (HTTPS only) | Confirm the answer |
| M6 | Content rights: likenesses, music, the "Dr. Doom" name | **OWNER DECISION** | APP_STORE.md "Content rights" | Written permissions; music terms; keep or rename the label |
| M7 | Submit the app and all eight products together | **OWNER** | Apple requires an app's first IAP of each type with a new version | Add all eight to the 2.0 submission |

### Device and live verification (nobody has observed these)

| # | Requirement | Status | Owner action |
|---|---|---|---|
| D1 | Frame rate, memory, load times, heat on a real iPhone/iPad | NOT VERIFIED | TestFlight checklist (TESTFLIGHT_RELEASE) |
| D2 | Two devices on different networks: party, rounds, results, rewards | NOT VERIFIED (desktop UDP soak only) | Device checklist |
| D3 | Friends status and invites between two accounts | NOT VERIFIED (service tests, test double) | friends.md §11 |
| D4 | Real sandbox purchases, restore, Premium, claims | NOT VERIFIED | COMMERCE_SETUP sandbox checklist |
| D5 | Lighting and skins on an iPhone screen (Metal) | NOT VERIFIED (desktop renders) | Look at Home, the party and the Season Pass |
