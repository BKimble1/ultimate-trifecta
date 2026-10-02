# TestFlight release: Ultimate Trifecta

Current version: **1.2 (V3)**. It uses the same app, bundle ID, Game Center capability and lane as 1.0 and 1.1. V3 adds a small native share-sheet framework (UTShare, built from source in CI) and the optional game service (`service/`), which is not deployed.

## App identity

| Field | Value |
|---|---|
| App name | Ultimate Trifecta |
| App icon | The owner's "Pajama Dash" artwork (`Ultimate Trifecta_ Pajama Dash.png`), as `game/assets/icon/icon.png` at 1024×1024, opaque. Godot's export generates every other icon size from it. |
| Bundle ID | `com.idlery.ultimatetrifecta`. It is registered on your team: the App Store Connect app record below uses it. |
| Marketing version | `1.2` for V3 (`MARKETING_VERSION` in `.github/workflows/ios.yml`; also `config/version` in `project.godot` and the export preset). V2 was `1.1`, V1 `1.0`. |
| Build number | Chosen at build time. With App Store Connect access it is the highest existing build for the app + 1 (`tools/asc.py next-build`), so it always increases past anything already uploaded; without it, the GitHub run number (V1's last unsigned build was 10; V2's are 12 and up). It can be overridden with the `build_number` workflow input. |
| Platforms | iPhone and iPad (`UIDeviceFamily` 1,2), iOS 17.0+, arm64, landscape left/right. Godot also adds `UIRequiredDeviceCapabilities` `iphone-ipad-minimum-performance-a12`, which means A12 (iPhone XS/XR) or newer. All verified in the CI archive's Info.plist. |
| Capabilities | Game Center (`com.apple.developer.game-center`) |
| App Store Connect record | **Exists** (seen by the CI lane's API check in run #26): app ID `6818346960`, name "Ultimate Trifecta", bundle `com.idlery.ultimatetrifecta`, SKU `ULTIMATETRIFECTA1`, primary locale en-US. No build had been uploaded before V3: the lane's next-build check returned 1 in runs #26 and #28. |
| Embedded frameworks | `GodotApplePluginsGameCenter`, `SwiftGodotRuntime` (Game Center bindings) and `UTShare` (share sheet; built from `native/ut_share` by `tools/build_native.sh`). All three are embedded and arm64 in the CI archive (run #26). |
| Toolchain | Godot 4.7.2-stable export; Xcode 26.6 (17F113) with the iOS 26 SDK on the `macos-26` GitHub runner (verified in CI run 3). Apple requires the iOS 26 SDK for uploads from April 28, 2026. |

## Current release state

**State: source prepared · project compiled (unsigned).** This is unchanged from V1: V2 (1.1) compiles for device, but no signed archive, upload or TestFlight build exists.

- **Project compiled (unsigned).** CI exports the Xcode project and builds an **unsigned arm64 device archive** with `CODE_SIGNING_ALLOWED=NO`. This proves the project compiles and links for iPhone; it is not installable.
  - **V2 final app code: commit `b56a82a`** (the V2 code from `5505024` plus the owner-supplied app icon), GitHub Actions run #16 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/36934028555).
    - Tests passed and the unsigned device-archive step succeeded. The archive is `com.idlery.ultimatetrifecta` **1.1 (16)**: arm64, Xcode 26.6 (17F113), iOS SDK 26.5, 269 MB `.app`, MinimumOSVersion 17.0, Game Center entitlement, `PrivacyInfo.xcprivacy`.
    - The Simulator build launched and reached a match: boot splash, loading, role reveal and HUD (`docs/media/v2/ios_simulator_ci_run16.jpg`). No crash report.
    - The signed archive and upload steps were skipped because no signing secrets are configured.
  - Run #14 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/36923913263) built `4c89ed0`, which differs from the final code only in the results scoreboard, the lobby bot-count text and the app icon. Tests passed, then the unsigned device archive `com.idlery.ultimatetrifecta` **1.1 (14)**: arm64, Xcode 26.6 (17F113), iOS SDK 26.5, 263 MB `.app`, MinimumOSVersion 17.0, with the Game Center entitlement and `PrivacyInfo.xcprivacy`. The Simulator build launched and reached a match, with no crash report.
  - Earlier V2 runs on the same lane: #12 (`0539d7c`, V2 gameplay/UI) and #13 (`e3d5c85`) passed. Run #12's archive: `com.idlery.ultimatetrifecta` **1.1 (12)**, arm64, Xcode 26.6 (17F113) / iOS SDK 26.5, 263 MB `.app`, Game Center entitlement, `PrivacyInfo.xcprivacy`. Its Simulator run showed the boot splash with the V2 character, the loading screen, then the match's role reveal and 4:00 HUD; no crash report.
  - V1's last unsigned build was 1.0 (10). The unsigned build number is the GitHub run number. The signed lane picks the highest App Store Connect build + 1 instead, so a signed 1.1 upload is always above anything already uploaded.
- **Not done yet:**
  - The app has not been device-tested.
  - No signed archive has been created.
  - Nothing has been uploaded.
  - There is no App Store Connect processing and no TestFlight availability.

The blocker is that this repository has no Apple signing access configured: no App Store Connect API key, team ID or certificates. This environment cannot reach `api.appstoreconnect.apple.com`, so the app record, existing builds and team could not be checked from here.

In every CI run so far the signing check found no secrets, so the signed archive and upload steps were skipped.

## The owner action that unblocks TestFlight

You only need to do this once.

1. **Create an App Store Connect API key.**
   - In App Store Connect, open Users and Access → Integrations → App Store Connect API → Team Keys → (+).
   - Use role **Admin**. Xcode's automatic signing needs to create the cloud-managed distribution certificate and provisioning profile; lower roles may not be allowed to.
   - Download `AuthKey_XXXXXXXXXX.p8` (it can only be downloaded once), and note the Key ID and Issuer ID.
2. **Add four repository secrets** under GitHub → Settings → Secrets and variables → Actions:

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | The Key ID |
   | `ASC_ISSUER_ID` | The Issuer ID |
   | `ASC_KEY_P8_BASE64` | Output of `base64 -i AuthKey_XXXXXXXXXX.p8` (one line) |
   | `APPLE_TEAM_ID` | Your 10-character Team ID, from the Membership page at developer.apple.com |

3. **Create the app record.** The App Store Connect API cannot create apps.
   - Go to App Store Connect → Apps → (+) New App: platform iOS, name **Ultimate Trifecta**, primary language English (U.S.), bundle ID **com.idlery.ultimatetrifecta**, SKU e.g. `ULTIMATETRIFECTA1`, full access.
   - If the bundle ID isn't in the list yet, either register it under Certificates, Identifiers & Profiles → Identifiers (enable **Game Center**), or run the workflow once (step 4). The workflow registers the ID through the API and then stops with an instruction to create the record.
   - If the name "Ultimate Trifecta" is already taken on the App Store, choose the replacement name yourself; the build does not rename the game.
4. **Run the workflow.**
   - In GitHub → Actions → "Build, test and ship (iOS)" → Run workflow, choose branch `claude/ultimate-trifecta-testflight-oie9r7` and tick **upload**.
   - The run tests, exports, signs (automatic signing via the API key), uploads with `testFlightInternalTestingOnly`, waits for processing, and adds the build to your existing **internal** TestFlight groups.
5. **Internal group.** If you have no internal group yet: TestFlight → Internal Testing → (+), add **only your own account**, then re-run step 4 or add the build to the group by hand. Install with the TestFlight app on your iPhone.

Also check that the Apple Developer Program membership is active and that the latest Program License Agreement is accepted under Business. Uploads fail without them, and I could not check either from here.

## What the lane does (reproducible, no secrets in git)

| Step | Script |
|---|---|
| Pinned Godot and export templates | `tools/fetch_godot.sh --templates` |
| Pinned GodotApplePlugins (sha256 checked) | `tools/fetch_deps.sh` |
| Xcode project export (team, version and build stamped into a temporary preset copy) | `tools/export_ios.sh` |
| Signed App Store archive and export/upload | `tools/build_ios.sh signed`: `xcodebuild archive` with `-allowProvisioningUpdates` and API-key auth, then `-exportArchive` with `method=app-store-connect`, `destination=upload` |
| Bundle ID registration, app check, build numbers, processing wait, internal groups, TestFlight state | `tools/asc.py` (ES256 JWT; never prints the key). Adding a build to an internal group reports Apple's answer; groups set to receive every build are left alone. |
| Read-only status check | Run the workflow with **asc_status** ticked: it prints the app record, recent builds with their processing state, and each build's internal/external TestFlight state. It builds and uploads nothing. |

The same steps run locally on a Mac with Xcode 26:

```sh
export APPLE_TEAM_ID=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8
export BUILD_NUMBER=$(python3 tools/asc.py next-build) MARKETING_VERSION=1.2
tools/fetch_godot.sh --templates && tools/fetch_deps.sh && tools/export_ios.sh
EXPORT_DESTINATION=upload INTERNAL_ONLY=true tools/build_ios.sh signed
python3 tools/asc.py wait 1.2 "$BUILD_NUMBER" 2400
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

**What to Test (1.2)**

> 1.2 private beta (V3: new character look and animation, Create Your Runner, parties with codes, controller support). Please try:
> - First launch: Create Your Runner, then pick a name. Later: Settings › Profile (Change name, Edit runner, Blocked players, Delete Game Profile).
> - Movement and animation: walk, run, sprint, sharp turns, jump, dive (jump again in the air), landings. Do the feet match the ground? Anything robotic or sliding?
> - Splash into a marked water by walking in, jumping in and diving in: the splash should look different each time, with one splash sound, and you should come up shaking off water.
> - Play with Friends → Create Party: share the 6-character code with Share (the iOS share sheet should open), Copy or Invite; a friend uses Join on another device. In the party: tap a player for Hide emotes / Report / Block / Remove. Faces should stay visible with 1–8 players.
> - Game controller (if you have one): menus with the d-pad, the code pad for joining, LB/RB in the creator, jump-then-dive quickly, sprint, cart throttle and brake. Do the button prompts match your controller?
> - Touch: move + camera drag + jump at once; Settings → Controls options.
> - Finish rounds both ways, then Rematch and Leave. Tell us about crashes, stuck controls, heat or frame drops, with your iPhone model.

## Release labels

Use these exactly:

**source prepared → project compiled → device-tested → signed archive created → uploaded → processing → available to internal testers** (and **pending external beta review** only if an external group is ever requested).
