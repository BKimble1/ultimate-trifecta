# TestFlight release: Ultimate Trifecta

Current version: **1.1 (V2)**: the same app, bundle ID, Game Center capability, export scripts and signing lane as 1.0, with a higher build number.

## App identity

| Field | Value |
|---|---|
| App name | Ultimate Trifecta |
| Bundle ID | `com.idlery.ultimatetrifecta`: the candidate ID from the brief. Whether it is already registered on your team could not be checked from here. |
| Marketing version | `1.1` for V2 (`MARKETING_VERSION` in `.github/workflows/ios.yml`; also `config/version` in `project.godot` and the export preset). V1 was `1.0`. |
| Build number | Chosen at build time. With App Store Connect access it is the highest existing build for the app + 1 (`tools/asc.py next-build`), so it always increases past anything already uploaded; without it, the GitHub run number (V1's last unsigned build was 10; V2's are 12 and up). It can be overridden with the `build_number` workflow input. |
| Platforms | iPhone and iPad (`UIDeviceFamily` 1,2), iOS 17.0+, arm64, landscape left/right. Godot also adds `UIRequiredDeviceCapabilities` `iphone-ipad-minimum-performance-a12`, which means A12 (iPhone XS/XR) or newer. All verified in the CI archive's Info.plist. |
| Capabilities | Game Center (`com.apple.developer.game-center`) |
| Toolchain | Godot 4.7.2-stable export; Xcode 26.6 (17F113) with the iOS 26 SDK on the `macos-26` GitHub runner (verified in CI run 3). Apple requires the iOS 26 SDK for uploads from April 28, 2026. |

## Current release state

**State: source prepared · project compiled (unsigned).** This is unchanged from V1: V2 (1.1) compiles for device, but no signed archive, upload or TestFlight build exists.

- **Project compiled (unsigned).** CI exports the Xcode project and builds an **unsigned arm64 device archive** with `CODE_SIGNING_ALLOWED=NO`. This proves the project compiles and links for iPhone; it is not installable.
  - V2 final code: commit `5505024`. CI builds it together with these documents in the run after #14. That run's result is added to this file in the following documentation commit.
  - Run #14 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/36923913263) built `4c89ed0`, which differs from the final code only in the results scoreboard and the lobby bot-count text. Tests passed, then the unsigned device archive `com.idlery.ultimatetrifecta` **1.1 (14)**: arm64, Xcode 26.6 (17F113), iOS SDK 26.5, 263 MB `.app`, MinimumOSVersion 17.0, with the Game Center entitlement and `PrivacyInfo.xcprivacy`. The Simulator build launched and reached a match, with no crash report.
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
| Bundle ID registration, app check, build numbers, processing wait, internal groups | `tools/asc.py` (ES256 JWT; never prints the key) |

The same steps run locally on a Mac with Xcode 26:

```sh
export APPLE_TEAM_ID=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8
export BUILD_NUMBER=$(python3 tools/asc.py next-build) MARKETING_VERSION=1.1
tools/fetch_godot.sh --templates && tools/fetch_deps.sh && tools/export_ios.sh
EXPORT_DESTINATION=upload INTERNAL_ONLY=true tools/build_ios.sh signed
python3 tools/asc.py wait 1.1 "$BUILD_NUMBER" 2400
```

## Compliance and privacy answers

These answers are based on what the build actually contains; please confirm them as the account holder.

- **Export compliance.** `ITSAppUsesNonExemptEncryption = false` is set in Info.plist.
  - The app adds no encryption of its own.
  - Online play uses Apple Game Center (GameKit), whose transport security is provided by iOS.
  - The ENet/UDP code path used for desktop LAN testing is not offered on iOS and is unencrypted.
  - If you do not agree that this qualifies as exempt, change the plist key in `game/export_presets.cfg` before uploading.
- **Permissions.** The only permission the app actually requests is `NSGKFriendListUsageDescription`. It is shown only when the player opens the Game Center friends list to invite someone.
  - The engine binary contains camera, microphone and photo-library code paths that the game never calls. Godot's export would otherwise write empty purpose strings for them, so they carry explicit "does not use" text.
  - There are no requests for contacts, location, camera, microphone, photos or tracking.
  - `NSUserTrackingUsageDescription` is absent, and `privacy/tracking_enabled=false`.
- **Privacy manifest** (confirmed in CI run 4). The archive contains Godot's `PrivacyInfo.xcprivacy`, with `NSPrivacyTracking false` and required-reason API declarations: file timestamp (DDA9.1, C617.1), system boot time (35F9.1) and disk space (E174.1, 85F4.1). It declares no collected data types. The two GodotApplePlugins frameworks carry no manifest of their own: only the app-level file was found in the bundle. They are not on Apple's list of SDKs that require one.
- **Data handling** (for the App Privacy questionnaire, needed before any App Store submission but not for internal TestFlight):
  - The game has no developer server, analytics, ads or crash reporting.
  - Game Center identity (player ID and display name) is used on-device and shared with the other players in your room through Game Center.
  - Settings, stats and cosmetics are stored only on the device. Settings → Delete local profile erases them.
  - You make the final declaration.
- **Content.** Cartoon chase with no violence, nudity, gambling, purchases or user-generated text. Names come from Game Center or are generated.

## Running services

- **Online rooms.** Online rooms use Apple's Game Center matchmaking and `GKMatch` relay. There is no developer-operated server, no hosting cost and nothing that must be kept running.
- **Game Center environment.** TestFlight builds use Game Center's sandbox environment automatically. All players in a room must run TestFlight builds of the app.
- **Review access.** App Review or a tester without Game Center can play **Solo practice** and the tutorial fully offline. No login or demo account is needed.

## TestFlight text

**Beta App Description**

> Ultimate Trifecta is a playful 3 a.m. campus chase. Runners splash into three marked waters around a fictional campus and race back to the dorm; the Night Watch hunts them on foot and in golf carts. Get four runners home before the 4-minute clock runs out — or, as the Night Watch, stop them. Play solo with bots or create a private room with friends through Game Center.

**What to Test**

> 1.1 private beta (V2: new characters, home and party lobby, touch controls, camera and water). Please try:
> - Home and lobby: is your character sharp and facing you? Is the next action obvious? In a room, do joins, leaves, Ready and outfit changes update without the party jumping around?
> - Movement: run, sprint (push the stick to the edge), jump, dive (jump again in the air). Starts, stops and turns: precise, and no foot sliding?
> - Touch: move, drag the camera and press Jump at the same time; a second finger on the left side should move the camera, not steal the stick. Try Settings → Controls (fixed stick, hold-to-sprint, button size, mirrored layout) and Try in Practice.
> - Camera: does it follow without lag or circling, and stay out of walls and trees?
> - Night Watch: hop in a golf cart, drive with Gas/Brake, hop out while still holding Gas (nothing should stay pressed), and tag a runner on foot.
> - Runner: splash into all three marked waters (any order), then reach any dorm door. Getting caught costs 6 s and returns you to your last splash.
> - Online: Online → Create room and share the 5-letter code; a friend joins with Join with code on another iPhone. Also try Invite. Empty slots are filled by bots marked BOT.
> - Finish rounds both ways (four runners home, and the time running out), then Rematch and Leave.
> - Settings → Graphics: Standard vs Battery Saver. Tell us about frame drops, heat or battery drain, with your iPhone model.
> - Tell us about any crash, stuck camera, unresponsive control or stuck button.

## Release labels

Use these exactly:

**source prepared → project compiled → device-tested → signed archive created → uploaded → processing → available to internal testers** (and **pending external beta review** only if an external group is ever requested).
