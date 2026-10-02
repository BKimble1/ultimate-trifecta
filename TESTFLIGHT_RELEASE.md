# TestFlight release: Ultimate Trifecta

Current version: **1.3 (V4)**. It uses the same app, bundle ID, Game Center capability, internal group and lane as 1.0–1.2, including the signed-archive fix from `e39c98c`. V4 adds no new frameworks, permissions, network services or data collection. Its opt-in diagnostics stay on the phone unless the player shares a summary through the existing share sheet. V3 added the UTShare share-sheet framework and the optional game service (`service/`), which is still not deployed.

## App identity

| Field | Value |
|---|---|
| App name | Ultimate Trifecta |
| App icon | The owner's "Pajama Dash" artwork (`Ultimate Trifecta_ Pajama Dash.png`), as `game/assets/icon/icon.png` at 1024×1024, opaque. Godot's export generates every other icon size from it. |
| Bundle ID | `com.idlery.ultimatetrifecta`. It is registered on your team: the App Store Connect app record below uses it. |
| Marketing version | `1.3` for V4 (`MARKETING_VERSION` in `.github/workflows/ios.yml`; also `config/version` in `project.godot`, the export preset and `tools/export_ios.sh`). V3 was `1.2`, V2 `1.1`, V1 `1.0`. |
| Build number | Chosen at build time. With App Store Connect access it is the highest existing build for the app + 1 (`tools/asc.py next-build`), so it always increases past anything already uploaded; without it, the GitHub run number (V1's last unsigned build was 10; V2's are 12 and up). It can be overridden with the `build_number` workflow input. |
| Platforms | iPhone and iPad (`UIDeviceFamily` 1,2), iOS 17.0+, arm64, landscape left/right. Godot also adds `UIRequiredDeviceCapabilities` `iphone-ipad-minimum-performance-a12`, which means A12 (iPhone XS/XR) or newer. All verified in the CI archive's Info.plist. |
| Capabilities | Game Center (`com.apple.developer.game-center`) |
| App Store Connect record | **Exists** (seen by the CI lane's API check in run #26): app ID `6818346960`, name "Ultimate Trifecta", bundle `com.idlery.ultimatetrifecta`, SKU `ULTIMATETRIFECTA1`, primary locale en-US. No build had been uploaded before V3: the lane's next-build check returned 1 in runs #26 and #28. |
| Embedded frameworks | `GodotApplePluginsGameCenter`, `SwiftGodotRuntime` (Game Center bindings) and `UTShare` (share sheet; built from `native/ut_share` by `tools/build_native.sh`). All three are embedded and arm64 in the CI archive (run #26). |
| Toolchain | Godot 4.7.2-stable export; Xcode 26.6 (17F113) with the iOS 26 SDK on the `macos-26` GitHub runner (verified in CI run 3). Apple requires the iOS 26 SDK for uploads from April 28, 2026. |

## Current release state

**State: signed archive created · uploaded · processed (VALID) · available to internal testers.**

It is **not device-tested**: no install or play on an iPhone or iPad has been observed. No external testing was requested, no testers were added, and nothing was submitted for App Store review.

| | |
|---|---|
| Build | `com.idlery.ultimatetrifecta` **1.2 (1)**. App Store Connect build ID `16d704eb-e460-4493-97b8-9345653b4589`. |
| Build number | **1**: the lane's check of App Store Connect found no earlier build for the app, so it chose 1. |
| Source | Commit `e39c98c`. Its game, service and native code are identical to `001f274`, the code every test, soak and capture ran on. The later commits change only the lane, docs and media. |
| Uploaded | 2026-10-02 03:39:23 UTC, by GitHub Actions run #32 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/36960504454) with `upload=true`. |
| Apple's processing | `VALID`. The build is `INTERNAL_ONLY` (uploaded with `testFlightInternalTestingOnly`) and declares no non-exempt encryption. |
| TestFlight | Internal state `IN_BETA_TESTING`; external state `NOT_APPLICABLE`. |
| Testers | Your existing internal group **"Ultimate Trifecta Internal Testing Group"**, which is set to receive every build. The lane added no one. TestFlight's automatic notification is on, so that group's members are told the build is ready. |
| Confirmed by | Apple's API, read by run #32 after processing and again by the read-only status runs #34 and #35 (03:51 and 03:53 UTC). Run #35 also shows the marketing version, 1.2. |

What the signed archive contains (run #32's build facts):
- **Binary:** arm64, 270 MB `.app`.
- **Toolchain:** Xcode 26.6 (17F113), iOS SDK 26.5. MinimumOSVersion 17.0; iPhone and iPad; landscape left and right.
- **Plist:** `ITSAppUsesNonExemptEncryption` false.
- **Frameworks:** `GodotApplePluginsGameCenter`, `SwiftGodotRuntime` and `UTShare` are embedded; UTShare is arm64.
- **Entitlements and privacy:** the Game Center entitlement, and `PrivacyInfo.xcprivacy` (no tracking, no collected data, because the game service is off).

How it got there:
- **Run #31** (`7a5325b`) failed at the signed archive, before anything was uploaded. Godot writes "Apple Distribution" into the Release configuration, and Xcode rejects a manually chosen identity under automatic signing ("conflicting provisioning settings").
- **The fix** (`e39c98c`): signed builds archive with the development identity, and the App Store Connect export re-signs the build for distribution.
- **Run #32** archived, exported and uploaded the build in about 2 minutes. The Simulator run followed while Apple processed it.
- **Run #36** (`26cb5fe`) checked that unsigned builds still work with the signing change: unsigned device archive, then the Simulator with no crash report.
- **Earlier unsigned CI builds** of V3 (runs #26, #28, #29 and #30) passed, including the unsigned device archive. Run #28's Simulator log shows a cold launch with no crash report. V2 was never uploaded.

## The owner action that remains

The one-time setup is done: the API key and the four repository secrets, the app record, and an internal group. Apple accepted the upload, so the developer membership and agreements were in order at that point.

What only you can do now:
1. **Install and play 1.2 (1)** from the TestFlight app on your iPhone. If the build doesn't appear, check that your Apple Account is in "Ultimate Trifecta Internal Testing Group" (App Store Connect › TestFlight › Internal Testing). Then work through the device checks in `TEST_REPORT.md` V3.8: frame rate and heat, touch, the share sheet, a controller if you have one, and a Game Center party on two devices.
2. **Optional:** deploy the game service (`service/README.md`) if you want verified profiles and moderated names. Then fill in `game/config/service.cfg` and run the workflow again with **upload**.

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
| Launch audit (V4) | Before the Simulator run, the lane lists the app's launch files and any text file naming Idlery, and counts "powered by" strings in the game data. It then captures six launch frames. The build facts in the log print the audit and a small sheet of those frames. |
| Read-only status check | Run the workflow with **asc_status** ticked: it prints the app record, recent builds with their processing state, and each build's internal/external TestFlight state and What to Test text. It builds and uploads nothing. |

The same steps run locally on a Mac with Xcode 26:

```sh
export APPLE_TEAM_ID=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8
export BUILD_NUMBER=$(python3 tools/asc.py next-build) MARKETING_VERSION=1.3
tools/fetch_godot.sh --templates && tools/fetch_deps.sh && tools/export_ios.sh
EXPORT_DESTINATION=upload INTERNAL_ONLY=true tools/build_ios.sh signed
python3 tools/asc.py wait 1.3 "$BUILD_NUMBER" 2400
```

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
  - Game Center identity (player ID and display name) is used on-device and shared with the other players in your room through Game Center.
  - Diagnostics (V4): only when the player turns them on in Settings › Diagnostics (beta). They are held in memory, never written to disk or sent to a server. They leave the phone only if the player taps Share summary, which opens the iOS share sheet with plain text that has no names, party codes or Game Center IDs. This adds no collected data type.
  - Settings, stats and cosmetics are stored on the device. Settings › Profile › **Delete Game Profile** erases them, and the online profile too when the service is on.
  - You make the final declaration.
- **Content.** Cartoon chase with no violence, nudity, gambling or purchases. Player names are user-generated; they are checked by the service when it is deployed, and every player card has Report and Block. There is no chat, only preset emotes.

## Running services

- **Online rooms.** Online rooms use Apple's Game Center matchmaking and `GKMatch` relay.
- **Game service (V3, optional, not deployed).** `service/` adds verified profiles, moderated names, reports, blocks and party rooms with admission tokens. Until the owner deploys it to their Cloudflare account (see `service/README.md`) and fills in `game/config/service.cfg`:
  - The build ships with the service off.
  - Names stay on the device.
  - Report explains it is unavailable and offers Block.
  - Nothing claims a verified profile.
- **Game Center environment.** TestFlight builds use Game Center's sandbox environment automatically. All players in a room must run TestFlight builds of the app.
- **Review access.** App Review or a tester without Game Center can play **Solo practice** and the tutorial fully offline. No login or demo account is needed.

## TestFlight text

**Beta App Description**

> Ultimate Trifecta is a playful 3 a.m. campus chase. Runners splash into three marked waters around a fictional campus and race back to the dorm; the Night Watch hunts them on foot and in golf carts. Get four runners home before the 4-minute clock runs out — or, as the Night Watch, stop them. Create your runner, play solo with bots, or start a private party with friends through Game Center.

**What to Test (1.3)**. The lane sets this text on the build from `docs/testflight/what_to_test.txt`:

> 1.3 internal beta (V4: phone polish after the first iPhone playtest). Please try, and tell us your iPhone model:
>
> - Buttons: are Jump/Dive, Tag, Gas, Brake and Exit comfortable for your thumbs? Can you tap Pause and the minimap? Settings > Controls > Edit layout lets you move, resize and mirror them; "Try it" previews.
> - Lobby: Emote (Dance, Wave, Ha!...) and Try moves should play every time, on your runner and for friends.
> - Loading: from the app icon and between rounds. Any frozen screen, logo or text that isn't the game's own?
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
