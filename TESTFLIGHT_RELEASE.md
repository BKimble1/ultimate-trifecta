# TestFlight release: Ultimate Trifecta

Current version: **2.2 (Season 1 · Winter Break), uploaded, processed (VALID), App Store-eligible and available to internal testers.** Build **2.2 (21)** (build 20 had the ninth pass, build 19 the UI audit, build 18 the eighth pass, build 17 the seventh, build 16 the sixth, build 15 the fifth, build 14 the fourth, build 13 the third, build 12 the second). The first pass: the holiday dorm, the Night Watch starting at GO, Lakeside Campus as Coming soon, protocol 11. The second pass: home is your party lobby (playlists: Quick Match, Party vs Bots, Practice; no separate "Play with Friends"), Quick Match on Game Center with bots in empty seats, typed party chat with bad words bleeped, the round-start fix, loading tips, Rankings with two 30-day Game Center leaderboards (created in App Store Connect, open 2026-12-01), run stats after each round, the Season Champion poster and Official Rules, and glossier buttons. The third pass (build 13): a roomier, cleaner UI on every screen, invites from the game's own Friends list through Game Center, and a launch that shows home before the champion poster ([docs/release22/README.md](docs/release22/README.md) sections 15-18). The fourth pass (build 14): hiding in bushes, real power-ups (Speed Sneakers, Squeaky Duck, Pillow Shield) shown as holograms, a tidier home and Shop, a results banner with Coins flying into the counter, the fireplace room, and the doubled-eye import fix ([docs/release22/README.md](docs/release22/README.md) sections 19-24); protocol 12. The fifth pass (build 15): one runner on home after Game Center sign-in (the "three eyes" fix), the daily present, the Season Pass offer poster with Premium also sold directly from Apple (`com.idlery.ultimatetrifecta.pass.s1`, not yet created in App Store Connect), livelier posters, coloured tabs and the bush Hide button ([docs/release22/README.md](docs/release22/README.md) sections 25-30). The sixth pass (build 16): music albums in the Locker, a five-emote loadout, rift portals, a useful Squeaky Duck with power-ups that move after pickup, cart hits that tag, the in-game chat button with chat in the feed, Settings tabs with audio, buying a skin outright, and a full-screen pass track ([docs/release22/README.md](docs/release22/README.md) sections 31-32); protocol 13. The seventh pass (build 17): the Invisibility Cloak power-up, rarer and better-looking rifts at random spots, the round's Emote wheel and a bottom-left Chat button, a messaging-style chat sheet, the Night Watch leaving with the runners in every round, one-tap album changes that crossfade, gradient discs, a clearer Locker emotes page, and the daily present waiting for a slow sign-in ([docs/release22/README.md](docs/release22/README.md) section 33); protocol 14. The eighth pass (build 18): a Night Watch tag knocks the runner out for the round, no Cheer while watching, a new Shop (Spotlight, tinted cards, Coins behind the counter's +, Season 1 banner that fits, Sets, Equip now, Remind me), a Season Pass pill on home, the XP bar filling on results, first-time tips, Locker random and kept looks, new sounds and haptics, better posters, cocoa and cookies, less text, and six new seasonal skins ([docs/release22/README.md](docs/release22/README.md) section 34); protocol 15. Build 19: a UI audit of every screen (Season Pass Free and Premium rows always whole, every Locker tab fits, a clearer pass header, the Settings tab highlight, shorter text; section 35); protocol 15. Build 20 (the ninth pass): a clearer Locker Emotes page, snow past the window and in rounds, a running Boost button, rifts that always take you (carts too), carts with their wheels on the ground, a Night Watch "Nearest cart" arrow, a smooth rise into Walk, things to do in the party room (bounce on the couch, hide in the plant, the lights), more in the room, and Settings tabs up in the header ([docs/release22/README.md](docs/release22/README.md) section 36); protocol 16, so build 20 plays only with build 20. Build 21: snow on things and drifts with footprints that stay all round, the owner's new Season Champion poster with confetti and glow, the party room's pillows and cat fixed, and built with Xcode 27.2 and the iOS 27.2 SDK (section 37); protocol 16 unchanged, so builds 20 and 21 play together. The 403 agreement block of 2026-11-15 is gone: the account holder accepted the pending agreement.

Before it, unsigned 2.2 (first pass) passed CI run #193 (commit `7792b86`); the lane needed two repairs: the pinned GodotApplePlugins release had been deleted upstream (now built from the pinned commit, `tools/fetch_deps.sh`), and App Store Connect's 403 text had become the build number.

The previous version, **2.1 (two maps), an internal TestFlight build**. Same app, bundle ID, Game Center capability, internal group and lane as 1.0–2.0. 2.1 adds a second map: Lakeside Campus (the new default, a large hilly campus with stairs, waters, parked cars and woods) beside Moonbrook College (the 2.0 map). The party host picks the map for the series; Practice remembers its own choice. The network protocol is 10, so 2.0 and 2.1 can't play together. It is **internal only** (`testFlightInternalTestingOnly=true`), so it can't be submitted; 2.0 (10) stays the App Store-eligible build. Like 2.0 it is provisional: the game service isn't deployed, so Coins, purchases, Season rewards and Friends status show as unavailable. See [docs/maps/HANDOFF.md](docs/maps/HANDOFF.md).

The previous version, **2.0 (final release sweep)**, is a provisional App Store-eligible candidate. It uses the same app, bundle ID, Game Center capability, internal group and lane as 1.0–1.9. 2.0 makes the lobby lighter, gives the Season Pass a large rotatable preview and a simpler layout, adds Friends (Game Center friends' in-game status and real invitations to your party), adds Shop filters and offers that never run out, routes purchases to separate sandbox and production services from one build, and is the first build uploaded as **App Store-eligible** (`testFlightInternalTestingOnly=false`) instead of internal-only. Gameplay, movement and the network protocol (8) are unchanged, so 1.9 and 2.0 can play in the same party. **It is provisional:** the game service isn't deployed and `game/config/service.cfg` is empty, so Coins, purchases, Season rewards, challenges, rotating offers, verified names, typed chat, reports and Friends status show as unavailable; the eight App Store products don't exist yet. It is not the launch build: the launch build is the next `distribution=app_store` upload after the owner setup in [docs/OWNER_SETUP_GUIDE.md](docs/OWNER_SETUP_GUIDE.md).

## App identity

| Field | Value |
|---|---|
| App name | Ultimate Trifecta |
| App icon | The owner's "Pajama Dash" artwork (`Ultimate Trifecta_ Pajama Dash.png`), as `game/assets/icon/icon.png` at 1024×1024, opaque. Godot's export generates every other icon size from it. |
| Bundle ID | `com.idlery.ultimatetrifecta`. It is registered on your team: the App Store Connect app record below uses it. |
| Marketing version | `2.2` for Season 1 · Winter Break (2.1 was the two-maps pass) (`MARKETING_VERSION` in `.github/workflows/ios.yml`; also `config/version` in `project.godot` and the export preset; `test_release_config` checks they agree). The final release sweep was `2.0`, Pass 9 `1.9`, Pass 8 `1.8`, V8 `1.7`, V7 `1.6`, V6 `1.5`, V5 `1.4`, V4 `1.3`, V3 `1.2`, V2 `1.1`, V1 `1.0`. Before preparing 2.1, the read-only status run #176 showed builds 1–10 in App Store Connect (latest 2.0 (10), `VALID`, `APP_STORE_ELIGIBLE`, `IN_BETA_TESTING`) and no 2.1. Before uploading 2.0, run #132 had shown builds 1–9 and no 2.0. |
| Build number | **21**: the lane read the highest existing build (2.2 (20)) and added one. Built with **Xcode 27.2 (27B52), iOS SDK 27.2** (`DTSDKName iphoneos27.2`, `DTXcode 2720`) on GitHub's `xcode-27` image; the Game Center / StoreKit plugin frameworks are the binaries built with Xcode 26. |
| Platforms | iPhone and iPad (`UIDeviceFamily` 1,2), iOS 17.0+, arm64, landscape left/right. Godot also adds `UIRequiredDeviceCapabilities` `iphone-ipad-minimum-performance-a12`, which means A12 (iPhone XS/XR) or newer. All verified in the CI archive's Info.plist. |
| Capabilities | Game Center (`com.apple.developer.game-center`). In-App Purchase needs no entitlement key; App Store Connect enables it for every app ID. |
| App Store Connect record | **Exists** (seen by the CI lane's API check in run #26): app ID `6818346960`, name "Ultimate Trifecta", bundle `com.idlery.ultimatetrifecta`, SKU `ULTIMATETRIFECTA1`, primary locale en-US. No build had been uploaded before V3: the lane's next-build check returned 1 in runs #26 and #28. |
| Embedded frameworks | `GodotApplePluginsGameCenter`, `SwiftGodotRuntime` (Game Center bindings) and `UTShare` (share sheet; built from `native/ut_share` by `tools/build_native.sh`). All three are embedded and arm64 in the CI archive (run #26). V6 adds `GodotApplePluginsStoreKit` (StoreKit 2, from the same pinned, sha256-checked release); the build facts report whether it is embedded. |
| Toolchain | Godot 4.7.2-stable export; Xcode 26.6 (17F113) with the iOS 26 SDK on the `macos-26` GitHub runner (verified in CI run 3). Apple requires the iOS 26 SDK for uploads from April 28, 2026. |

## Current release state

**State (2.2): source prepared · project compiled · signed archive created · uploaded · processed (VALID) · available to internal testers.** Latest build: **2.2 (22)**, **App Store-eligible**, provisional (game service not deployed yet; the nine in-app purchase records exist without prices).

It is **not device-tested**: no install or play on an iPhone or iPad has been observed. No external testing was requested, no testers were added, nothing was submitted for App Store review, nothing was released, and no purchase of any kind was made.

| | |
|---|---|
| Build | `com.idlery.ultimatetrifecta` **2.2 (22)**. App Store Connect build ID `afa50521-d322-4bd2-934a-e367f20bbae1`. (2.2 (21) `4b60796f-…`, 2.2 (20) `f6768187-…`, 2.2 (19) `39bbd93c-…`, 2.2 (18) `c56ada6c-…`, 2.2 (17) `48fb4361-…`, 2.2 (16) `cf0a8982-…`, 2.2 (15) `e9a19fe1-…`, 2.2 (14) `bc03f233-…`, 2.2 (13) `54f2dcc4-…` and 2.2 (12) `c50a97e1-…` are the previous ones.) |
| Build number | **22**: the lane read the highest existing build (2.2 (21)) and added one. Built with Xcode 27.2, iOS SDK 27.2. |
| Source | Commit `43ddaf5` on `claude/happy-edison-50dynd`. |
| Uploaded | 2026-11-18 23:26:23 UTC (Apple's upload time), by GitHub Actions run #277 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/44417043951) with `upload=true` and `distribution=app_store`. The headless tests gate the build and passed in that run (the full suite also passed locally: 641 tests, 0 failures). |
| Apple's processing | `VALID`. Audience **`APP_STORE_ELIGIBLE`** (checked by the run with `asc.py audience`). Declares no non-exempt encryption. |
| TestFlight | Internal state `IN_BETA_TESTING`; external state `READY_FOR_BETA_SUBMISSION` (no external group was requested). What to Test is set from `docs/testflight/what_to_test.txt` (705 characters, en-US). TestFlight's automatic notification is on. |
| Game Center | Leaderboards `ut.season_points` and `ut.fastest_run` created by run #201 (`iap=gc-create`): recurring every 30 days (`PT720H`) from 2026-12-01 00:00 UTC. They must be added to the 2.2 version page when it is submitted (App Store Connect › the version › Game Center). |
| Testers | Your existing internal group **"Ultimate Trifecta Internal Testing Group"**, which receives every build. The lane added no one and created no group. |
| In-app purchases | The nine records (six Coin packs, `pass.s1`, two outfits) created by run #279 (`iap=create`) on 2026-11-18, without prices or review screenshots (the owner's step). |
| Confirmed by | Apple's API, read by run #277 at 23:31 UTC (2026-11-18). |
| Can it be submitted? | Yes (App Store-eligible), once the owner steps below are done. |
| Network | Protocol 16: builds 20, 21 and 22 play together; earlier builds refuse them at join ("Update the game to join."). |

Earlier builds (2.1 and before), as recorded when they shipped, are in [docs/release_history.md](docs/release_history.md).

## The owner actions that remain

The one-time lane setup is done: the API key and the four repository secrets, the app record, and an internal group. Nothing there needs to be set up again.

What only you can do, in order (the exact steps are in [docs/OWNER_SETUP_GUIDE.md](docs/OWNER_SETUP_GUIDE.md) A–G):
1. **Install 2.2 (19)** from TestFlight and check What to Test (`docs/testflight/what_to_test.txt`): knock-out tags, the new Shop and Sets, the six new skins, the Season pill, haptics on a phone, the Invisibility Cloak, the rifts, the Emote wheel and Chat button, the chat sheet, the Night Watch leaving with the runners, one-tap album changes, the music albums, the emote loadout, rift portals, the Squeaky Duck, the in-game chat button, Settings › Audio, one runner with two eyes on home, the Shop and the Season Pass after Game Center signs in, the daily present, the Season Pass offer, hiding in a bush, the power-ups, leaving a party, the home lobby and playlists, Quick Match on two devices at once, inviting a Game Center friend, Add friends, typed chat (bad words bleeped), the round start with your thumb on the stick, loading tips, Rankings and the champion poster.
2. **Agreements** (A): the Paid Apps Agreement, tax and banking (account holder).
3. **The nine products** (B; Sets are Coin purchases, no new product): create them (manually or `iap=create`), set prices, review screenshots and notes. New since build 15: **Season 1 Premium** (`com.idlery.ultimatetrifecta.pass.s1`, non-consumable, $9.99), which the Season Pass poster and the Buy button sell.
4. **The service** (C): deploy the sandbox and production deployments, enter the two App Store Server Notification URLs, fill `game/config/service.cfg` and `game/config/links.cfg` with public values only.
5. **Build the configured candidate** (D): run the workflow with **upload** ticked and **distribution = app_store**.
6. **Sandbox test** (E) on that build, including Friends and an online round with two devices and two accounts, and Delete Game Profile.
7. **The 2.2 version page** (F): add the two Game Center leaderboards to the version; fill `support_email` (and `privacy_url`, `support_url`) in `game/config/links.cfg` so a chat report can reach you without the service (Guideline 1.2), and review `docs/release22/CONTEST_RULES.md` (Guideline 5.3); metadata, App Privacy, age rating, screenshots, review notes; and the content decisions (written permission from the two people Record Breaker and Dr. Doom are based on, the music terms, the "Dr. Doom" label). **Music rights check:** the three album songs (Lobby Pluck, Cozy Christmas Lobby, Stardust Reverie) were made with Suno; songs from Suno's free plan may not be used commercially, so confirm they came from a paid plan (or replace them) before submitting.
8. **Submit** (G) the version together with all nine products, with **Manually release this version** selected. Apple decides approval.

For later uploads, run "Build, test and ship (iOS)" with **upload** ticked and choose **distribution**: `internal_only` (the default; TestFlight internal testing only, can't be submitted) or `app_store` (App Store-eligible; internal testers can still install it; nothing is submitted). The build number follows the highest one in App Store Connect. **asc_status** reads the current state without building anything.

## What the lane does (reproducible, no secrets in git)

| Step | Script |
|---|---|
| Pinned Godot and export templates | `tools/fetch_godot.sh --templates` |
| Pinned GodotApplePlugins (sha256 checked) | `tools/fetch_deps.sh` |
| Xcode project export (team, version and build stamped into a temporary preset copy) | `tools/export_ios.sh` |
| Signed App Store archive and export/upload | `tools/build_ios.sh signed`: `xcodebuild archive` with `-allowProvisioningUpdates` and API-key auth, then `-exportArchive` with `method=app-store-connect`, `destination=upload` |
| Upload audience (2.0) | The **distribution** input: `internal_only` (default) writes `testFlightInternalTestingOnly=true`; `app_store` writes `false`. `build_ios.sh` refuses a signed export unless `INTERNAL_ONLY` is exactly `true` or `false`. After processing, `tools/asc.py audience BUILD_ID EXPECTED` reads the audience Apple recorded and fails the run on a mismatch; `FAILED`/`INVALID` processing fails the run; a build still processing is a warning, never reported as available. |
| Game data check (2.0) | `tools/export_ios.sh` fails the export if `config/service.cfg` isn't in the exported game data (1.9 and earlier dropped every `.cfg` file). |
| Bundle ID registration, app check, build numbers, processing wait, internal groups, TestFlight state | `tools/asc.py` (ES256 JWT; never prints the key). Adding a build to an internal group reports Apple's answer; groups set to receive every build are left alone. |
| TestFlight "What to Test" (V4) | After processing, `tools/asc.py whats-new BUILD_ID docs/testflight/what_to_test.txt` sets the build's en-US beta notes (App Store Connect beta build localization) for the internal testers. |
| Launch and branding audit (V5; black since V6) | Right after the Xcode export, before any signing or upload, `tools/launch_audit.py` fails the run on: no launch storyboard or more than one; a storyboard background that isn't pure black `#000000` (V5: the startup navy); a launch image that is missing, not opaque, not on black or without the Idlery teal mark; any "powered by" text in the game data or project text. It lists the text files naming Idlery (expected: the bundle ID). The Simulator step then captures six launch frames, and the build facts print the audit and a sheet of those frames. |
| Shader baking (V6) | With `SHADER_BAKE=1` (set in CI) on macOS, `tools/export_ios.sh` first exports with Godot's shader baker running the Mobile renderer on Metal. The result is judged by its output: the project and game data must exist and carry `shader_cache` entries. Otherwise the ordinary export is used. `shader_bake.txt` in the build facts records which, with the count. Runs #66 and #67 baked 40 entries (exit code 0). A bake reduces shader compilation on the phone; it does not replace the driver's own pipeline preparation. |
| In-app purchases (V6, opt-in) | The workflow input **iap** = `list` (read only) or `create` (creates only the missing catalogue products: no prices, screenshots or submission). Default `none`: an ordinary run never touches them. |
| Read-only status check | Run the workflow with **asc_status** ticked: it prints the app record, recent builds with their processing state, and each build's internal/external TestFlight state and What to Test text, and (2.1) the team's signing certificates (type, name, expiry, serial; never their content). It builds and uploads nothing. |
| Signing certificates (2.1) | Xcode's automatic signing creates an Apple Development certificate ("Created via API") on every fresh runner, and its key leaves with the runner. Uploads 1.2–2.0 left 28 of them, and the 2.1 upload (run #178) stopped at Apple's limit ("Your account has reached the maximum number of certificates"). Since 2.1 every signed run revokes the one it created, in its last step (`tools/asc.py certs-prune --pem`, matched by serial from the runner's keychain). The **prune_ci_certs** input, with the owner's approval, first revokes those earlier runs left (`certs-prune --older-than-hours 3`). Both touch only "Created via API" development certificates: never a distribution certificate, and never one named for a person or a Mac. Builds already uploaded are signed with distribution certificates and are unaffected. |

The same steps run locally on a Mac with Xcode 26:

```sh
export APPLE_TEAM_ID=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8
export BUILD_NUMBER=$(python3 tools/asc.py next-build) MARKETING_VERSION=2.1
tools/fetch_godot.sh --templates && tools/fetch_deps.sh && tools/export_ios.sh
EXPORT_DESTINATION=upload INTERNAL_ONLY=false tools/build_ios.sh signed   # true = internal testing only
python3 tools/asc.py wait 2.1 "$BUILD_NUMBER" 2400
```

## In-app purchases (V6, Pass 8, 2.0): prepared, not set up

The catalogue (`game/config/catalogue.json`, `docs/ECONOMY.md`) names eight App Store products:
- Coin packs (consumable): `com.idlery.ultimatetrifecta.coins.250`, `.coins.500`, `.coins.1000`, `.coins.1500`, `.coins.3500` and `.coins.7500` (Pass 8 added 250, 1,000 and 7,500).
- Outfits (non-consumable): `.skin.moonlight_runner` and `.skin.starry_sleeper`.

Status run #132 (2026-10-05 22:33 UTC) read them from App Store Connect: "8 planned, 0 present, 8 missing". 2.0 therefore shows them as **Not available** (both outfits and all six packs stay listed so a reviewer can reach them once they exist). No price is set or assumed anywhere in the game: each pack shows StoreKit's own price string once it exists, and "Best value" appears only when StoreKit's numeric prices are in one currency and one pack is strictly cheapest per Coin.

Coins and Season XP are also not added, because the game service isn't deployed, and the Shop says so. 2.0 routes purchases to a sandbox deployment (TestFlight, App Review) or a production deployment (App Store) from the same build, so sandbox money never reaches production records (`docs/final/commerce.md`). The exact setup steps are in `docs/OWNER_SETUP_GUIDE.md` B–E and `docs/COMMERCE_SETUP.md`:
1. **The account holder** accepts the Paid Applications agreement and completes tax and banking.
2. **Create the products:** run the workflow with **iap = list** (read only), then **iap = create**. It creates only missing products and sets no prices.
3. **In App Store Connect,** set each product's price and add a review screenshot.
4. **Deploy both service deployments** (sandbox and production) and fill in `game/config/service.cfg`.
5. **Test with a Sandbox account** on a TestFlight build, following `COMMERCE_SETUP.md` §4.

The lane has done none of these. No purchase has been made, in sandbox or otherwise.

## Compliance and privacy answers

These answers are based on what the build actually contains; please confirm them as the account holder.

- **Export compliance.** `ITSAppUsesNonExemptEncryption = false` is set in Info.plist.
  - The app adds no encryption of its own.
  - Online play uses Apple Game Center (GameKit), whose transport security is provided by iOS.
  - The ENet/UDP code path used for desktop LAN testing is not offered on iOS and is unencrypted.
  - V3: with the game service deployed, the app also calls it over HTTPS using Godot's built-in TLS (mbedTLS, standard algorithms), for sign-in and profile requests only. This is standard encryption, which usually still qualifies for the exemption. The account holder confirms the answer in App Store Connect; the build shipped now has the service off.
  - If you do not agree that this qualifies as exempt, change the plist key in `game/export_presets.cfg` before uploading.
- **Permissions.** The only permission the app actually requests is `NSGKFriendListUsageDescription` (2.0 text: "Shows which of your Game Center friends are playing Ultimate Trifecta so you can invite them to your party. Friends only see you when you've both allowed this."). 2.0 asks when the player opens the Friends panel (Home, Play with Friends or the party) or Apple's invite sheet.
  - The engine binary contains camera, microphone and photo-library code paths that the game never calls. Godot's export would otherwise write empty purpose strings for them, so they carry explicit "does not use" text.
  - There are no requests for contacts, location, camera, microphone, photos or tracking.
  - `NSUserTrackingUsageDescription` is absent, and `privacy/tracking_enabled=false`.
- **Privacy manifest** (confirmed in CI run 4). The archive contains Godot's `PrivacyInfo.xcprivacy`, with `NSPrivacyTracking false` and required-reason API declarations: file timestamp (DDA9.1, C617.1), system boot time (35F9.1) and disk space (E174.1, 85F4.1). 1.9 declared no collected data types. Since 2.0, `tools/export_ios.sh` declares them whenever either service endpoint is set in `service.cfg` (user ID, name, gameplay content, other user content, purchase history, contacts, product interaction; linked, app functionality, no tracking); the provisional 2.0 build has no endpoint, so it still declares none. The two GodotApplePlugins frameworks carry no manifest of their own: only the app-level file was found in the bundle. They are not on Apple's list of SDKs that require one.
- **Data handling** (for the App Privacy questionnaire, needed before any App Store submission but not for internal TestFlight; full answers and the policy inventory are in `docs/APP_STORE.md`):
  - With the service off (as shipped): no developer server, analytics, ads or crash reporting.
  - With the service deployed: user ID, name, gameplay content (the runner's look) and reports, linked to the player, for app functionality only, never tracking. `tools/export_ios.sh` then declares these in the privacy manifest automatically.
  - **V6, with the service deployed:**
    - **Purchases:** the service keeps purchase history (App Store transaction IDs and what they delivered, never payment details), linked to the player, to deliver each purchase once and restore it. Declared as Purchase History.
    - **Chat:** typed messages pass through the service to be checked and signed, and are **not stored**. A reported message is kept with that report (up to 200 characters, Other User Content) and removed if its sender deletes their profile.
    - Whether to also declare typed chat as "Emails or Text Messages" is your call; `docs/APP_STORE.md` sets out both options.
    - Without the service, chat stays inside the party's Game Center connection as preset phrase IDs.
  - Game Center identity (player ID and display name) is used on-device and shared with the other players in your room through Game Center.
  - **Friends (2.0), with the service deployed:** the service keeps the player's Game Center friends list only as keyed hashes (it can't read them back as player IDs), shows status only between mutual friends who both allowed friends access, and forgets status about 60 seconds after the last heartbeat. "Show when I'm playing" turns it off. Declared as Contacts and Product Interaction.
  - Diagnostics (V4): only when the player turns them on in Settings › Diagnostics ("Diagnostics (beta)" before 2.0). They are held in memory, never written to disk or sent to a server. They leave the phone only if the player taps Share summary, which opens the iOS share sheet with plain text that has no names, party codes or Game Center IDs. This adds no collected data type.
  - Settings, stats and cosmetics are stored on the device. Settings › Profile › **Delete Game Profile** erases them, and the online profile too when the service is on.
  - You make the final declaration.
- **Content.** Cartoon chase with no violence, nudity or gambling. Communication is private-party only.
  - **Quick Chat** preset phrases are always available.
  - **Typed chat** is available only in parties set up through the game service, and only while it is reachable. Each message is checked on the device, approved and signed by the service, then verified by the host and every receiver.
  - **Names** are checked against the same policy on the device and on the service. Without the service, parties show curated names only.
  - Every player card and message has **Mute, Report and Block**. Reports go to the owner's moderation queue (`docs/MODERATION.md`).
  - **In-app purchases (V6):** cosmetic only. Coin packs and two outfits are App Store products, none set up yet. Everything else costs Coins, earned in online rounds or bought; Coins never buy gameplay advantage.

## Running services

- **Online rooms.** Online rooms use Apple's Game Center matchmaking and `GKMatch` relay.
- **Game service (V3, optional, not deployed).** `service/` adds:
  - verified profiles, moderated names, reports, blocks and party rooms with admission tokens;
  - (V6) the wallet ledger, App Store transaction verification, Season claims, verified round rewards, typed-chat approval and the moderation queue.

  Until the owner deploys it to their Cloudflare account (see `service/README.md` and `docs/COMMERCE_SETUP.md`) and fills in `game/config/service.cfg`:
  - The build ships with the service off.
  - Names stay on the device.
  - Report explains it is unavailable and offers Block.
  - Nothing claims a verified profile.
  - Typed chat says it is unavailable, while Quick Chat works.
  - The Shop and Season Pass say they need the service; no Coins or Season XP are added and nothing can be bought.
- **Friends (2.0).** Status and invitations go through the same service; party codes and Apple's invite sheet work without it.
- **Sandbox and production (2.0).** Two deployments of the service; the build picks one by its App Store receipt (TestFlight: sandbox; App Store: production) and moves to the sandbox if production refuses a sandbox purchase (App Review).
- **Game Center environment.** TestFlight builds use Game Center's sandbox environment automatically. All players in a room must run TestFlight builds of the app.
- **Review access.** App Review or a tester without Game Center can play **Solo practice** and the tutorial fully offline. No login or demo account is needed.

## TestFlight text

**Beta App Description**

> Ultimate Trifecta is a playful 3 a.m. campus chase. Runners splash into three marked waters around a fictional campus and race back to the dorm; the Night Watch hunts them on foot and in golf carts. Get four runners home before the 4-minute clock runs out — or, as the Night Watch, stop them. Create your runner, play solo with bots, or start a private party with friends through Game Center.

The current What to Test text is `docs/testflight/what_to_test.txt` (the lane sets it on every upload). Earlier texts are in [docs/release_history.md](docs/release_history.md).

## Release labels

Use these exactly:

**source prepared → project compiled → device-tested → signed archive created → uploaded → processing → available to internal testers** (and **pending external beta review** only if an external group is ever requested).
