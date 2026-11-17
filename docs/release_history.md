# Release history: Ultimate Trifecta

Moved from TESTFLIGHT_RELEASE.md (2.2 build 18) so that file stays a one-page status. Nothing here is current; see TESTFLIGHT_RELEASE.md for the latest build and the owner steps.

## Earlier builds

The previous build, **2.1 (11)**, internal only, as recorded when it shipped: uploaded 2026-10-07 by run #182 (`distribution=internal_only`, `prune_ci_certs=true`), 584 tests, 0 failures, `VALID`, `INTERNAL_ONLY`, protocol 10.

The first 2.1 attempt, run #178 on `51af064`, passed its tests and stopped at signing. The team had reached Apple's limit on certificates: 28 Apple Development certificates left by earlier CI runs. Nothing was uploaded. With the owner's approval, run #182 first revoked those 28 (`prune_ci_certs`), then revoked its own at the end (serial `29AED01F…`). A read-only status run afterwards (#184) lists 4 certificates on the team, the owner's 3 Apple Distribution and 1 iOS Distribution, and no development certificate.

What run #182 checked besides the upload:
- **Launch and branding audit: PASS**, with the same figures as 2.0:
  - 1656² opaque launch images on black;
  - the logo's box off by 0.0000;
  - 0 detached glow or inner dip pixels;
  - 0 "powered by" strings.
- **Simulator (x86_64, about 1 fps):** 0 script errors and 23 screenshots. As with 1.6–2.0, the bot round was still preparing (phase 1) when the window closed. Not a phone.
  - The run found one crash report on the runner, `Godot-2026-10-07-222044.ips`. By its name it comes from the Godot editor that exported the project (written just after the export step), not from the app.
- **Build number:** 11, from App Store Connect's highest build (10) + 1.

The previous build, **2.0 (10)**, as recorded when it shipped (App Store-eligible; still the build to submit once the owner setup is done):

**State (2.0): source prepared · project compiled · signed archive created · uploaded · processed (VALID) · available to internal testers.** Latest build: **2.0 (10)**, App Store-eligible, **provisional** (service off, no products).

It is **not device-tested**: no install or play on an iPhone or iPad has been observed. No external testing was requested, no testers were added, nothing was submitted for App Store review, nothing was released, and no purchase of any kind was made.

| | |
|---|---|
| Build | `com.idlery.ultimatetrifecta` **2.0 (10)**. App Store Connect build ID `1730ad62-0823-49a6-a534-1e7bb79e3935`. |
| Build number | **10**: the lane read the highest existing build (1.9 (9)) and added one. Status run #132 had shown builds 1–9 and no 2.0 beforehand. |
| Source | Commit `66e7575` (all 2.0 code: the four area merges, ARTFIX's garment fixes and the release-lane fixes; the full suite run locally on it: 561 tests, 0 failures. Later commits change only documentation and store screenshots, which aren't in the app). |
| Uploaded | 2026-10-06 08:02:44 UTC (Apple's upload time), by GitHub Actions run #145 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37431364875) with `upload=true` and **`distribution=app_store`**. The headless tests gate the build: **561 tests, 107,273 checks, 0 failures**. |
| Apple's processing | `VALID`. Audience **`APP_STORE_ELIGIBLE`** (checked by the run with `asc.py audience`; a mismatch fails it). Declares no non-exempt encryption. |
| TestFlight | Internal state `IN_BETA_TESTING`; external state `READY_FOR_BETA_SUBMISSION` (an App Store-eligible build *could* be sent to external beta review; nothing was sent). What to Test is set from `docs/testflight/what_to_test.txt` (1,813 characters, en-US). |
| Testers | Your existing internal group **"Ultimate Trifecta Internal Testing Group"**, which receives every build. The lane added no one and created no group. |
| Confirmed by | Apple's API, read by run #145 at 08:20 UTC. |
| Can it be submitted? | The audience allows it, but **don't submit this build**: with the service off and no products, App Review would find purchases, Season rewards and Friends status unavailable. Submit the configured build from [OWNER_SETUP_GUIDE.md](docs/OWNER_SETUP_GUIDE.md) step D. |

What run #145 checked besides the upload:
- **Game data:** "config files in the game data: OK" (`config/service.cfg` is in the exported data; R4). The privacy manifest step reported "no game service configured; no collected data declared", as expected for the provisional build.
- **Launch and branding audit: PASS.** One black launch storyboard; both launch images and the boot splash **1656²**, opaque, black corners; the logo's box matches the vector exactly (off by 0.0000); 0 detached glow pixels, 0 inner dip pixels; 0 "powered by" strings.
- **Shader baking:** the baking export was used (exit code 0, unlike 1.8 and 1.9's 250) and the game data carries **40 `shader_cache` entries**.
- **Signed archive and upload:** `testFlightInternalTestingOnly: false`; ARCHIVE SUCCEEDED, EXPORT SUCCEEDED, "Upload succeeded".
- **Simulator (iPhone Air, iOS 26.2 runtime, x86_64, about 1 fps):** the cold launch was still running, no crash report for the app, 0 script errors, 23 screenshots; as with 1.6–1.9 the bot round was still preparing (phase 1) when the window closed. Not a phone.
- **Build facts:**
  - arm64, app 302 MB;
  - Xcode 26.6 (17F113), iOS SDK 26.5;
  - `CFBundleShortVersionString` 2.0, `CFBundleVersion` 10, MinimumOSVersion 17.0, iPhone and iPad, landscape left and right;
  - `ITSAppUsesNonExemptEncryption` false;
  - entitlements: Game Center only; the 2.0 friends purpose string;
  - the same four embedded frameworks as 1.9 (`GodotApplePluginsGameCenter`, `GodotApplePluginsStoreKit`, `SwiftGodotRuntime`, `UTShare` arm64);
  - privacy manifest: `NSPrivacyTracking` false, no collected data types (service off), required-reason APIs file timestamp (DDA9.1, C617.1), system boot time (35F9.1), disk space (E174.1, 85F4.1).
- **Symbols warning:** as before, no dSYMs for those four frameworks; the upload succeeded and the app's own symbols were generated.
- **Build number:** 10, from App Store Connect's highest build (9) + 1, not the run-number fallback.

The previous build, **1.9 (9)**, as recorded when it shipped (internal-only: it can't be submitted to the App Store):

| | |
|---|---|
| Build | `com.idlery.ultimatetrifecta` **1.9 (9)**. App Store Connect build ID `8a207a62-69de-4c34-95bd-a90e4c8504ec`. |
| Build number | **9**: the lane read the highest existing build (1.8 (8)) and added one. Status run #117 had shown builds 1–8 and no 1.9 beforehand, and no other session was working on this app. |
| Source | Commit `1704d9d`: all Pass 9 code as of `995d488` (the full suite run locally on it: 523 tests, 0 failures) plus the re-taken Season Pass captures and documentation. Later commits change only documentation. |
| Uploaded | 2026-10-05 19:23:26 UTC (Apple's upload time; `xcodebuild` finished sending at 19:22:36), by GitHub Actions run #125 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37360488402) with `upload=true`. The headless tests gate the build: **523 tests, 105,358 checks, 0 failures**. |
| Apple's processing | `VALID`. The build is `INTERNAL_ONLY` and declares no non-exempt encryption. |
| TestFlight | Internal state `IN_BETA_TESTING`; external state `NOT_APPLICABLE`. What to Test is set from `docs/testflight/what_to_test.txt` (1,844 characters, en-US). |
| Testers | Your existing internal group **"Ultimate Trifecta Internal Testing Group"**, which receives every build. The lane added no one. TestFlight's automatic notification is on. |
| Confirmed by | Apple's API, read by run #125 at 19:38 UTC. |

What run #125 checked besides the upload:
- **Launch and branding audit: PASS.** One black launch storyboard; both launch images **1656²**, opaque, black corners, the Idlery teal mark; the logo's box matches the vector exactly (off by 0.0000), 0 detached glow pixels, 0 inner dip pixels; the boot splash image is the same; 0 "powered by" strings.
- **Shader baking:** the baking export was used and the game data carries **40 `shader_cache` entries**. As with 1.8, the baking editor exited with code 250 after the export and macOS saved a Godot crash report on the runner (`Godot-2026-10-05-192014.ips`). The lane judges this export by its output: the project, the game data and the 40 baked entries were all present, and that output was signed, uploaded and accepted as `VALID`.
- **Simulator (x86_64, about 1 fps):** the cold launch was still running, no crash report for the app, 0 script errors, 23 screenshots; as with 1.6–1.8 the bot round was still preparing (phase 1) when the window closed. Not a phone.
- **Build facts:**
  - arm64, app 302 MB;
  - Xcode 26.6 (17F113), iOS SDK 26.5;
  - `CFBundleShortVersionString` 1.9, `CFBundleVersion` 9, MinimumOSVersion 17.0, iPhone and iPad, landscape left and right;
  - `ITSAppUsesNonExemptEncryption` false;
  - the Game Center entitlement and friends purpose string;
  - the same four embedded frameworks as 1.8 (`GodotApplePluginsGameCenter`, `GodotApplePluginsStoreKit`, `SwiftGodotRuntime`, `UTShare` arm64) and the privacy manifest.
- **Symbols warning:** Xcode warned that the archive has no debug symbols (dSYMs) for those four frameworks. The upload succeeded. Crash reports from inside those frameworks won't be symbolicated. The app's own symbols were generated.

The build before, **1.8 (8)**: build ID `39a7c5ae-4c47-4f82-997c-58b819b44d89`, run #112, commit `406773c`, uploaded 2026-10-05 06:11:05 UTC, `VALID`, `INTERNAL_ONLY` (482 tests, 102,855 checks, 0 failures).

Earlier builds, all still `VALID` and internal-only:
- **1.7 (7)** (`3a68fdfb-…`, run #99, commit `00dc652`): V8.
- **1.6 (6)** (`811b7ee6-…`, run #94, commit `4de97c7`): V7.
- **1.5 (5)** (`3d9ab76f-…`, run #80, commit `434fcd4`): V6.
- **1.4 (4)** (`71dd2161-…`, run #62, commit `0a41d70`): V5.
- **1.3 (3)** and **1.3 (2)**: V4.
- **1.2 (1)**: V3.


## Earlier What to Test texts

**What to Test (2.0)**. The lane sets this text on the build from `docs/testflight/what_to_test.txt` (1,813 characters):

> 2.0 release candidate, provisional: the game service isn't connected in this build yet, so Friends status, invites, purchases, Coins and Season rewards say they're unavailable. That's expected; please don't try to buy anything. Tell us your iPhone or iPad model:
>
> - Home and the party room: the dorm behind the menus is a little lighter. Check that it still feels like night, that your runner stands out, and that the small lines beside Start are easy to read.
> - Season Pass: tap Tier 50 or Tier 100 (or any outfit in the track). It stands large on the left. Drag sideways on it to turn it, or use Turn and Reset; the track still scrolls by finger. Leave the pass: your runner should wear your own look. Tell us if anything is hard to read or tap.
> - Friends: on Home (top right) and in a party. It asks for Game Center friends access, then lists your friends. In this build their status says it's unavailable. Party codes and Invite with Game Center still work. Tell us if the list, the permission prompt or the buttons feel wrong.
> - Outfits up close: the hooded onesies (Night Owl, Bedtime Bandit and others), Dr. Doom's jacket and the Glow Jogger headlamp should now sit on the body in the Season Pass, Shop and Locker previews. Tell us about anything that floats or pokes through.
> - Shop: try Hide owned on All skins and Accessories. The six Coin packs and the two App Store outfits are always listed; buying says it's unavailable in this build.
> - Online parties: create a party and join from a second device with the code, then play a full round. If joining fails, the game should now say why instead of waiting.
> - Running, diving, tagging and the music are unchanged from 1.9. Tell us if anything got worse.
> - Look for any text cut off, overlapping or hidden behind the notch or home bar, on iPhone and iPad.

**What to Test (1.5)**, kept for reference (1.6–1.9 are in git history):

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

