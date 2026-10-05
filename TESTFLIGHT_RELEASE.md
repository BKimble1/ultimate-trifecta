# TestFlight release: Ultimate Trifecta

Current version: **1.9 (Pass 9)**. It uses the same app, bundle ID, Game Center capability, internal group and lane as 1.0–1.8. Pass 9 removes the sprint meter (one steady full-input speed: runner 6.0 m/s, Night Watch 6.6; protocol 8, so 1.8 and 1.9 can't join each other), adds two complete Season Pass skins (Record Breaker at Premium tier 50, Dr. Doom at Premium tier 100) and extends Season 1 · After Hours from 30 to 100 tiers without a reset, fixes outfits that sat off the body, cleans up animation at the new speeds, and plays the owner's "Soft Bounce Loop" as the round music, blended in from the lobby music on the beat. It adds no module, entitlement, permission or third-party service: the frameworks, entitlements and privacy manifest are the same as 1.8's. The game service stays off and no App Store product exists, so season claims, rotating offers, challenge progress and buying all show as unavailable.

## App identity

| Field | Value |
|---|---|
| App name | Ultimate Trifecta |
| App icon | The owner's "Pajama Dash" artwork (`Ultimate Trifecta_ Pajama Dash.png`), as `game/assets/icon/icon.png` at 1024×1024, opaque. Godot's export generates every other icon size from it. |
| Bundle ID | `com.idlery.ultimatetrifecta`. It is registered on your team: the App Store Connect app record below uses it. |
| Marketing version | `1.9` for Pass 9 (`MARKETING_VERSION` in `.github/workflows/ios.yml`; also `config/version` in `project.godot` and the export preset). Pass 8 was `1.8`, V8 `1.7`, V7 `1.6`, V6 `1.5`, V5 `1.4`, V4 `1.3`, V3 `1.2`, V2 `1.1`, V1 `1.0`. Before uploading it, the read-only status run #117 showed builds 1–8 in App Store Connect (latest 1.8 (8), `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`) and no 1.9. |
| Build number | Chosen at build time. With App Store Connect access it is the highest existing build for the app + 1 (`tools/asc.py next-build`), so it always increases past anything already uploaded; without it, the GitHub run number (V1's last unsigned build was 10; V2's are 12 and up). It can be overridden with the `build_number` workflow input. |
| Platforms | iPhone and iPad (`UIDeviceFamily` 1,2), iOS 17.0+, arm64, landscape left/right. Godot also adds `UIRequiredDeviceCapabilities` `iphone-ipad-minimum-performance-a12`, which means A12 (iPhone XS/XR) or newer. All verified in the CI archive's Info.plist. |
| Capabilities | Game Center (`com.apple.developer.game-center`). In-App Purchase needs no entitlement key; App Store Connect enables it for every app ID. |
| App Store Connect record | **Exists** (seen by the CI lane's API check in run #26): app ID `6818346960`, name "Ultimate Trifecta", bundle `com.idlery.ultimatetrifecta`, SKU `ULTIMATETRIFECTA1`, primary locale en-US. No build had been uploaded before V3: the lane's next-build check returned 1 in runs #26 and #28. |
| Embedded frameworks | `GodotApplePluginsGameCenter`, `SwiftGodotRuntime` (Game Center bindings) and `UTShare` (share sheet; built from `native/ut_share` by `tools/build_native.sh`). All three are embedded and arm64 in the CI archive (run #26). V6 adds `GodotApplePluginsStoreKit` (StoreKit 2, from the same pinned, sha256-checked release); the build facts report whether it is embedded. |
| Toolchain | Godot 4.7.2-stable export; Xcode 26.6 (17F113) with the iOS 26 SDK on the `macos-26` GitHub runner (verified in CI run 3). Apple requires the iOS 26 SDK for uploads from April 28, 2026. |

## Current release state

**State: source prepared · project compiled · signed archive created · uploaded · processed (VALID) · available to internal testers.** Latest build: **1.8 (8)**.

It is **not device-tested**: no install or play on an iPhone or iPad has been observed. No external testing was requested, no testers were added, nothing was submitted for App Store review, and no purchase of any kind was made.

| | |
|---|---|
| Build | `com.idlery.ultimatetrifecta` **1.8 (8)**. App Store Connect build ID `39a7c5ae-4c47-4f82-997c-58b819b44d89`. |
| Build number | **8**: the lane read the highest existing build (1.7 (7)) and added one. Status run #111 had shown builds 1–7 and no 1.8 beforehand, and no other session was working on this app. |
| Source | Commit `406773c`: all Pass 8 code as of `7e9602a` (tested locally in full and by push run #110) plus evidence and documentation. Later commits change only documentation. |
| Uploaded | 2026-10-05 06:11:05 UTC, by GitHub Actions run #112 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37270008174) with `upload=true`. The headless tests gate the build: **482 tests, 102,855 checks, 0 failures**. |
| Apple's processing | `VALID`. The build is `INTERNAL_ONLY` and declares no non-exempt encryption. |
| TestFlight | Internal state `IN_BETA_TESTING`; external state `NOT_APPLICABLE`. What to Test is set from `docs/testflight/what_to_test.txt` (1,772 characters, en-US). |
| Testers | Your existing internal group **"Ultimate Trifecta Internal Testing Group"**, which receives every build. The lane added no one. TestFlight's automatic notification is on. |
| Confirmed by | Apple's API, read by run #112 at 06:25 UTC. |

What run #112 checked besides the upload:
- **Launch and branding audit: PASS.** One black launch storyboard; both launch images **1656²** (Pass 8: rasterised from the owner's vector), opaque, black corners, the Idlery teal mark; the logo's box matches the vector exactly (off by 0.0000), 0 detached glow pixels, 0 inner dip pixels; the boot splash image is the same; 0 "powered by" strings.
- **Shader baking:** the baking export was used and the game data carries **40 `shader_cache` entries**. The baking editor exited with code 250 after the export (1.7's exited 0), and macOS saved a Godot crash report on the runner at that moment (`Godot-2026-10-05-060750.ips`, before the Simulator started). The lane judges this export by what it produced because the editor has crashed while quitting before (run #63): here the project, the game data and the 40 baked entries were all present, and that output is what was signed, uploaded and accepted as `VALID`.
- **Simulator (x86_64, about 1 fps):** the cold launch was still running, no crash report for the app, 0 script errors, 23 screenshots; as with 1.6 and 1.7 the bot round was still preparing (phase 1) when the window closed. Not a phone.

The previous build, **1.7 (7)**, as recorded when it shipped:

| | |
|---|---|
| Build | `com.idlery.ultimatetrifecta` **1.7 (7)**. App Store Connect build ID `3a68fdfb-043d-4e2f-882d-793e09dd7956`. |
| Build number | **7**: the lane read the highest existing build (1.6 (6)) and added one. Status run #98 had shown builds 1–6 and no 1.7 beforehand, and no other session was working on this app. |
| Source | Commit `00dc652`: all V8 code as of `5e96387` (tested by push run #97) plus documentation. Later commits change only documentation and evidence. |
| Uploaded | 2026-10-04 23:00:18 UTC, by GitHub Actions run #99 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37241343086) with `upload=true`. The headless tests gate the build: **418 tests, 99,343 checks, 0 failures**. |
| Apple's processing | `VALID`. The build is `INTERNAL_ONLY` and declares no non-exempt encryption. |
| TestFlight | Internal state `IN_BETA_TESTING`; external state `NOT_APPLICABLE`. What to Test is set from `docs/testflight/what_to_test.txt` (1806 characters, en-US). |
| Testers | Your existing internal group **"Ultimate Trifecta Internal Testing Group"**, which receives every build. The lane added no one. TestFlight's automatic notification is on. |
| Confirmed by | Apple's API, read by run #99 at 23:18 UTC. |

What the signed archive contains (run #99's build facts): arm64, app 297 MB (1.6: 296 MB); Xcode 26.6 (17F113), iOS SDK 26.5; `CFBundleIdentifier` `com.idlery.ultimatetrifecta`, `CFBundleShortVersionString` 1.7, `CFBundleVersion` 7, MinimumOSVersion 17.0, iPhone and iPad, landscape left and right; `ITSAppUsesNonExemptEncryption` false; the Game Center entitlement and friends purpose string; `GodotApplePluginsGameCenter`, `GodotApplePluginsStoreKit`, `SwiftGodotRuntime` and `UTShare` (arm64) embedded; the privacy manifest. What run #99 checked besides the upload: the launch and branding audit **PASS** (one black launch storyboard; both 2048² launch images opaque with black corners and the Idlery teal mark; 0 "powered by" strings); the shader-baking export (exit code 0, **40 `shader_cache` entries**); and the x86_64 Simulator (cold launch still running, no crash report, 0 script errors, 23 screenshots; at about 1 fps it was still preparing the bot round, phase 1, when the window closed, as with 1.6). The Simulator says nothing about device speed.

Earlier builds, all still `VALID` and internal-only:
- **1.6 (6)** (`811b7ee6-…`, run #94, commit `4de97c7`): V7.
- **1.5 (5)** (`3d9ab76f-…`, run #80, commit `434fcd4`): V6.
- **1.4 (4)** (`71dd2161-…`, run #62, commit `0a41d70`): V5.
- **1.3 (3)** and **1.3 (2)**: V4.
- **1.2 (1)**: V3.

## The owner action that remains

The one-time setup is done: the API key and the four repository secrets, the app record, and an internal group. Nothing needs to be set up again.

What only you can do now:
1. **Install 1.8 (8)** from the TestFlight app on your iPhone. If it doesn't appear, check that your Apple Account is in "Ultimate Trifecta Internal Testing Group" (App Store Connect › TestFlight › Internal Testing).
2. **Play it and check the items in What to Test.**
   - Most important: whether holding sprint now feels like one steady burst (and "Sprint empty · ease off to recharge" makes sense), whether jump→dive spam no longer out-runs the Night Watch while a single dive still helps, and whether the goal bar, your next action and "Runner pace" are clear at a glance.
   - The startup: the Idlery Games logo should stay still and crisp from the launch screen until it fades. If it doesn't, send a PNG screenshot (not a screen recording), ideally from more than one iPhone size.
   - The device checks are listed in `TEST_REPORT.md` P8.6.
3. **Purchases, rotating offers and challenges, when you want them live** (`docs/COMMERCE_SETUP.md`):
   1. Accept the Paid Applications agreement and complete tax and banking (account holder).
   2. Run the workflow with **iap = create**: it creates the eight missing products (the five V6 ones and Pass 8's `coins.250`, `coins.1000`, `coins.7500`) and sets no prices.
   3. Choose each product's price and add a review screenshot in App Store Connect.
   4. Deploy the service (migrations 0001–0004: commerce, offers, challenges) and fill in `game/config/service.cfg`.
   5. Upload again.
   6. Test with a Sandbox account (`COMMERCE_SETUP.md` §4), including a rotating offer across 00:00 UTC and a challenge completed in a two-device round.
   7. Extend the offer schedule before **2026-12-28** (`tools/make_offer_schedule.py`, then `node service/tools/sync_catalogue.mjs`, redeploy).
4. **The results track:** when you have the new end-of-match music, add it; the game already has a results-music state waiting for it (see `docs/pass8/movement.md` and `docs/PASS8_GAMEPLAY_COMMERCE_NOTES.md`).
5. **Typed chat, verified names and reports** need the same service deployment. Also choose whether to declare chat as "Emails or Text Messages" (`docs/APP_STORE.md`).

For later uploads, run "Build, test and ship (iOS)" with **upload** ticked. The build number follows the highest one in App Store Connect, and the build goes to internal testing only. **asc_status** reads the current state without building anything.

## What the lane does (reproducible, no secrets in git)

| Step | Script |
|---|---|
| Pinned Godot and export templates | `tools/fetch_godot.sh --templates` |
| Pinned GodotApplePlugins (sha256 checked) | `tools/fetch_deps.sh` |
| Xcode project export (team, version and build stamped into a temporary preset copy) | `tools/export_ios.sh` |
| Signed App Store archive and export/upload | `tools/build_ios.sh signed`: `xcodebuild archive` with `-allowProvisioningUpdates` and API-key auth, then `-exportArchive` with `method=app-store-connect`, `destination=upload` |
| Bundle ID registration, app check, build numbers, processing wait, internal groups, TestFlight state | `tools/asc.py` (ES256 JWT; never prints the key). Adding a build to an internal group reports Apple's answer; groups set to receive every build are left alone. |
| TestFlight "What to Test" (V4) | After processing, `tools/asc.py whats-new BUILD_ID docs/testflight/what_to_test.txt` sets the build's en-US beta notes (App Store Connect beta build localization) for the internal testers. |
| Launch and branding audit (V5; black since V6) | Right after the Xcode export, before any signing or upload, `tools/launch_audit.py` fails the run on: no launch storyboard or more than one; a storyboard background that isn't pure black `#000000` (V5: the startup navy); a launch image that is missing, not opaque, not on black or without the Idlery teal mark; any "powered by" text in the game data or project text. It lists the text files naming Idlery (expected: the bundle ID). The Simulator step then captures six launch frames, and the build facts print the audit and a sheet of those frames. |
| Shader baking (V6) | With `SHADER_BAKE=1` (set in CI) on macOS, `tools/export_ios.sh` first exports with Godot's shader baker running the Mobile renderer on Metal. The result is judged by its output: the project and game data must exist and carry `shader_cache` entries. Otherwise the ordinary export is used. `shader_bake.txt` in the build facts records which, with the count. Runs #66 and #67 baked 40 entries (exit code 0). A bake reduces shader compilation on the phone; it does not replace the driver's own pipeline preparation. |
| In-app purchases (V6, opt-in) | The workflow input **iap** = `list` (read only) or `create` (creates only the missing catalogue products: no prices, screenshots or submission). Default `none`: an ordinary run never touches them. |
| Read-only status check | Run the workflow with **asc_status** ticked: it prints the app record, recent builds with their processing state, and each build's internal/external TestFlight state and What to Test text. It builds and uploads nothing. |

The same steps run locally on a Mac with Xcode 26:

```sh
export APPLE_TEAM_ID=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8
export BUILD_NUMBER=$(python3 tools/asc.py next-build) MARKETING_VERSION=1.5
tools/fetch_godot.sh --templates && tools/fetch_deps.sh && tools/export_ios.sh
EXPORT_DESTINATION=upload INTERNAL_ONLY=true tools/build_ios.sh signed
python3 tools/asc.py wait 1.5 "$BUILD_NUMBER" 2400
```

## In-app purchases (V6, Pass 8): prepared, not set up

The catalogue (`game/config/catalogue.json`, `docs/ECONOMY.md`) names eight App Store products:
- Coin packs (consumable): `com.idlery.ultimatetrifecta.coins.250`, `.coins.500`, `.coins.1000`, `.coins.1500`, `.coins.3500` and `.coins.7500` (Pass 8 added 250, 1,000 and 7,500).
- Outfits (non-consumable): `.skin.moonlight_runner` and `.skin.starry_sleeper`.

Status run #111 read them from App Store Connect: all eight are **MISSING**. This build therefore shows them as **Not available**. No price is set or assumed anywhere in the game: each pack shows StoreKit's own price string once it exists, and "Best value" appears only when StoreKit's numeric prices are in one currency and one pack is strictly cheapest per Coin.

Coins and Season XP are also not added, because the game service isn't deployed, and the Shop says so. The exact setup steps are in `docs/COMMERCE_SETUP.md`:
1. **The account holder** accepts the Paid Applications agreement and completes tax and banking.
2. **Create the products:** run the workflow with **iap = list** (read only), then **iap = create**. It creates only missing products and sets no prices.
3. **In App Store Connect,** set each product's price and add a review screenshot.
4. **Deploy the sandbox service** and fill in `game/config/service.cfg`.
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
- **Permissions.** The only permission the app actually requests is `NSGKFriendListUsageDescription`. It is shown only when the player opens the Game Center friends list to invite someone.
  - The engine binary contains camera, microphone and photo-library code paths that the game never calls. Godot's export would otherwise write empty purpose strings for them, so they carry explicit "does not use" text.
  - There are no requests for contacts, location, camera, microphone, photos or tracking.
  - `NSUserTrackingUsageDescription` is absent, and `privacy/tracking_enabled=false`.
- **Privacy manifest** (confirmed in CI run 4). The archive contains Godot's `PrivacyInfo.xcprivacy`, with `NSPrivacyTracking false` and required-reason API declarations: file timestamp (DDA9.1, C617.1), system boot time (35F9.1) and disk space (E174.1, 85F4.1). It declares no collected data types. The two GodotApplePlugins frameworks carry no manifest of their own: only the app-level file was found in the bundle. They are not on Apple's list of SDKs that require one.
- **Data handling** (for the App Privacy questionnaire, needed before any App Store submission but not for internal TestFlight; full answers and the policy inventory are in `docs/APP_STORE.md`):
  - With the service off (as shipped): no developer server, analytics, ads or crash reporting.
  - With the service deployed: user ID, name, gameplay content (the runner's look) and reports, linked to the player, for app functionality only, never tracking. `tools/export_ios.sh` then declares these in the privacy manifest automatically.
  - **V6, with the service deployed:**
    - **Purchases:** the service keeps purchase history (App Store transaction IDs and what they delivered, never payment details), linked to the player, to deliver each purchase once and restore it. Declared as Purchase History.
    - **Chat:** typed messages pass through the service to be checked and signed, and are **not stored**. A reported message is kept with that report (up to 200 characters, Other User Content) and removed if its sender deletes their profile.
    - Whether to also declare typed chat as "Emails or Text Messages" is your call; `docs/APP_STORE.md` sets out both options.
    - Without the service, chat stays inside the party's Game Center connection as preset phrase IDs.
  - Game Center identity (player ID and display name) is used on-device and shared with the other players in your room through Game Center.
  - Diagnostics (V4): only when the player turns them on in Settings › Diagnostics (beta). They are held in memory, never written to disk or sent to a server. They leave the phone only if the player taps Share summary, which opens the iOS share sheet with plain text that has no names, party codes or Game Center IDs. This adds no collected data type.
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
- **Game Center environment.** TestFlight builds use Game Center's sandbox environment automatically. All players in a room must run TestFlight builds of the app.
- **Review access.** App Review or a tester without Game Center can play **Solo practice** and the tutorial fully offline. No login or demo account is needed.

## TestFlight text

**Beta App Description**

> Ultimate Trifecta is a playful 3 a.m. campus chase. Runners splash into three marked waters around a fictional campus and race back to the dorm; the Night Watch hunts them on foot and in golf carts. Get four runners home before the 4-minute clock runs out — or, as the Night Watch, stop them. Create your runner, play solo with bots, or start a private party with friends through Game Center.

**What to Test (1.5)**. The lane sets this text on the build from `docs/testflight/what_to_test.txt` (1675 characters):

> 1.5 internal beta (V6: steadier play, real dorms, Locker/Shop/Season 1, party room, rankings). Please tell us your iPhone model:
>
> - Smoothness: play several whole rounds, Practice and with friends. 1.4 could run smoothly and then suddenly turn very glitchy. Does that still happen? If anything stutters, turn on Settings > Diagnostics (beta), play, then Share summary (no names or codes).
> - Startup: pure black behind Idlery Games, then home with the new lobby music. Any gap or click when it loops (about every 34 s)? It should fade out when a round starts and come back after.
> - Loading: the three runners should keep moving until you appear inside a dorm. Cancel (Practice) / Leave party works at any point.
> - Dorms: each round starts inside one of three dorms (named on the reveal card). Splash the three waters, then finish by running back in through one of that dorm's doors.
> - Coins: 8 per round on the campus. Pick them up (+1).
> - Finger scrolling: swipe the Locker, Shop, Season Pass, results and settings lists, starting on a card. Lists should move, and lifting your finger should never select, buy or claim. A tap still selects.
> - Locker, Shop and Season Pass: browse the new outfits, hats, shoes and emotes. The game service and App Store products aren't set up in this build, so Coins and Season XP aren't added and purchases say Unavailable. That's expected; please don't try to buy anything.
> - Party room: tap Walk to walk around with friends. Quick Chat, and Mute / Report / Block on a player card. Typed chat is off in this build.
> - Results: each team's rankings, then final standings before you return to the party.
> - Heat and battery after 15-20 minutes.

**What to Test (1.4)**, kept for reference:

> 1.4 internal beta (V5: new look, smoother motion, cleaner menus). Please try, and tell us your iPhone model:
>
> - Startup: Idlery Games should show at once and fade into the dorm. Any white flash, second logo, or a frozen logo over a menu?
> - Home, party and wardrobe: new text, buttons and room. Is everything easy to read? Do buttons react the moment you tap, even when you tap fast?
> - Wardrobe: every item shows a picture of it on your runner, its full name and Equipped / Owned / a price. Try lots of items, switch categories quickly, then Apply or Undo.
> - Party: names should read in full; settings show as "3 rounds", "2 Night Watch", "4 home to win". Tap a player for details. Emote, Try moves, go to the Wardrobe and back, then Start.
> - Match loading: the new title and three runners. Smooth, sharp, no jump at the loop, and straight into the round.
> - Campus: new trees, buildings, props and all six waters. Any spot that looks blocky, cluttered or hard to read, or a prop you snag on?
> - Movement: start, stop, turn around, jump, dive, land, tag, splash, carts. Anything that pops, slides or jitters? Say if it happens only with friends or in Practice too.
> - Map: tap the minimap. Labels shouldn't overlap; the (i) explains the marks.
> - Heat and smoothness after 15 minutes.
> - Optional: Settings > Diagnostics (beta) > on, play a few rounds, Share summary. It has no names, codes or Game Center IDs.

**What to Test (1.3)**, kept for reference:

> 1.3 internal beta (V4: phone polish after the first iPhone playtest). Please try, and tell us your iPhone model:
>
> - Buttons: are Jump/Dive, Tag, Gas, Brake and Exit comfortable for your thumbs? Can you tap Pause and the minimap? Settings > Controls > Edit layout lets you move, resize and mirror them; "Try it" previews.
> - Lobby: Emote (Dance, Wave, Ha!...) and Try moves should play every time, on your runner and for friends.
> - Loading: from the app icon and between rounds. The three runners should loop smoothly, sharp and uncropped, then fade straight into the round. Any frozen screen, jump at the loop point, logo or text that isn't the game's own?
> - Outdoors: trees, buildings, lamps and the six waters. Any spot that still looks blocky, or any stutter?
> - Night Watch: chase and tag runners. Tag glows and a ring appears under a runner when a press would land. Too hard, too easy? Practice has a short "Night Watch training".
> - Getting caught as a runner: "Caught by..., back in 6", your splashes kept, then a short "Protected".
> - With friends: the host picks 1/2/3 Night Watch and 1/3/5 rounds. Roles are random each round. Play a 3-round series: round results, Ready for the next round, final standings.
> - Heat and battery: after 10-15 minutes, is the phone hot? Does it slow down?
> - Optional: Settings > Diagnostics (beta) > turn on, play a few rounds, then Share summary and send it to the developer. It has no names, codes or Game Center IDs.

**What to Test (1.2)**, kept for reference:

> 1.2 private beta (V3: new character look and animation, Create Your Runner, parties with codes, controller support). Please try:
> - First launch: Create Your Runner, then pick a name. Later: Settings › Profile (Change name, Edit runner, Blocked players, Delete Game Profile).
> - Movement and animation: walk, run, sprint, sharp turns, jump, dive (jump again in the air), landings. Do the feet match the ground? Anything robotic or sliding?
> - Splash into a marked water by walking in, jumping in and diving in: the splash should look different each time, with one splash sound, and you should come up shaking off water.
> - Play with Friends → Create Party: share the 6-character code with Share (the iOS share sheet should open), Copy or Invite; a friend uses Join on another device. In the party: tap a player for Hide emotes / Report / Block / Remove. Faces should stay visible with 1–8 players.
> - Game controller (if you have one): menus with the d-pad, the code pad for joining, LB/RB in the creator, jump-then-dive quickly, sprint, cart throttle and brake. Do the button prompts match your controller?
> - Touch: move + camera drag + jump at once; Settings → Controls options.
> - Drive or run under the big trees: the view should stay clear, with no green "porthole".
> - Finish rounds both ways, then Rematch and Leave. Tell us about crashes, stuck controls, heat or frame drops, with your iPhone model.

## Release labels

Use these exactly:

**source prepared → project compiled → device-tested → signed archive created → uploaded → processing → available to internal testers** (and **pending external beta review** only if an external group is ever requested).
