# Test report: Ultimate Trifecta

This report records what was actually run, where, and what each result proves. Version 2.0 (the final release sweep) is reported first. The Pass 9 (1.9), Pass 8 (1.8), V8 (1.7), V7 (1.6), V6 (1.5), V5 (1.4), V4 (1.3), V3 (1.2), V2 (1.1) and V1 (1.0) reports follow unchanged as the baseline. The evidence comes from these sources, each labelled by what it is:

| Label | What it is | What it can prove |
|---|---|---|
| **Headless sim** | The real `MatchSim`/physics/rules code running headless (Godot 4.7.2, Linux), with scripted inputs or bots | Rules, ordering, validation, routes, bot behaviour |
| **Unit (presentation)** | Headless tests of pure presentation logic: `TouchRouter`, render-state capture/interpolation, camera damping, springs, the dorm stage, profile migration | Touch ownership/cancellation, interpolation and discontinuities, frame-rate independence, in-place lobby updates |
| **Loopback net** | Host and up to 7 `NetSession` clients in one process over an in-memory transport with simulated latency, jitter and loss | Protocol, prediction/reconciliation, lag compensation, reconnect, host loss |
| **Desktop UDP** | Separate Godot processes (1 host + N clients) on one Linux machine over real UDP (ENet), each shaping its outbound traffic, playing full rounds with automation input | Multi-process networking across full rounds; *not* iPhones, *not* the Game Center transport |
| **Desktop render** | The game rendered by Godot's Mobile renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb, at device resolutions, with a fixed frame clock (`--fixed-fps 60`, or Movie Maker) | Layout, framing, art, render-path dimensions (render size vs displayed size, MSAA, scale) and engine counters (draw calls, primitives). **Not** frame rate, frame pacing, GPU cost or device smoothness |
| **CI iOS** | GitHub Actions `macos-26` runner: Xcode project export, unsigned arm64 device archive (or, from V3, a signed archive and TestFlight upload), x86_64 Simulator build and run, App Store Connect API checks | That the iOS project compiles, links, signs and uploads, launches in the Simulator, and what App Store Connect reports for the build; *not* device performance or a device install |

**Not done: no physical iPhone or iPad was available, so nothing in V1–V8, Pass 8, Pass 9 or the final sweep has been device-tested.** Touch feel, frame rate, thermals and Game Center on hardware are unverified; see V5.9. V4 added an in-game diagnostics panel so the owner can measure them (docs/V4_NOTES.md); V5 adds the name of a slow preparation job to it.

# Final release sweep (version 2.0)

The last pass before the App Store (docs/FINAL_RELEASE_SWEEP.md): a lighter
lobby, the Season Pass preview on the large stage, Friends with real status
and lobby invitations, commerce that keeps sandbox and production apart in
one build, an App Store-eligible release lane, and the App Store package
(docs/APP_STORE.md, docs/APP_STORE_READINESS.md). **No iPhone or iPad, no
deployed service and no App Store product was available**: everything below
is desktop Linux, the service's Node tests, and CI iOS.

## FRS.1 Automated tests

Full game suite on the integrated code (local, headless; Commerce, Friends,
Season Pass and Lighting merged): **561 tests, 107,281 checks, 0 failures**
(703 s). Service (`service/`, Node): **93 tests, 93 pass**. The final
gate on the release-candidate commit, and the CI gate of the upload run,
are in FRS.5.

| Suite (new in the sweep) | What it exercises |
|---|---|
| `test_commerce_routing` | receipt kind → deployment; the production refusal of a sandbox purchase moves the install to the sandbox and the still-unfinished transaction is delivered there once; the move is remembered; a cached snapshot from another deployment is never shown |
| `test_shop_filters` | Hide owned on All skins and Accessories, counts, the explained empty state, never hiding Featured, Coin packs or Premium; selection after filtering; App Store labels |
| `test_friends` (13) | panel states and sorting, polling only while open, heartbeat cadence and pause in the background, the invite toast never over the controls in a round, accept → the code-join path, leave-party confirmation, revocation clean-up, layout at four device shapes with long names |
| `test_season_stage` (7) | turn ownership (one finger, dead zone, vertical drags don't turn), no automatic sway after a touch or under Reduced Motion, restore of the saved look on every exit and before a round, distinct reward states, outage copy, layout with the figure ≥ 2× on phones |
| `test_room_failed` (2) | a Game Center matchmaking failure takes a waiting guest home with the reason; a host keeps the party |
| `test_release_config` (3) | `config/*.cfg` ships and dev/test code doesn't; one marketing version everywhere; links bundled https or nothing |
| Service: `environments.test.mjs`, `friends.test.mjs` | sandbox/production crediting, the derived appAccountToken, forged/Xcode/wrong-bundle transactions, notifications per environment; mutual-only presence, enumeration attempts, blocks both ways, presence expiry and session ordering, invite limits/dedup/expiry/accept re-checks, deletion and sweep |

**Desktop UDP soak** (`SOAK_OUT=docs/test-data/final_net_soak_3c_60ms_0.03
tools/net_soak.sh 3 60 10 0.03 3`): a host and 3 client processes over real
UDP (ENet), 60 ms one-way lag, 10 ms jitter, 3 % loss, a 3-round series with
automation input. Every round completed on all four processes with the same
result (runners, 4/4 home); RTT 146–171 ms; 59–60 fps; average correction
0.5–9.6 mm, largest single correction 0.22–1.33 m per client and round (the
same range as earlier soaks: one correction after a loss burst); host
input starvation 707 / 564 skipped ticks over the series (the 3 % loss).
Desktop processes on one Linux machine; not iPhones and not the Game Center
transport.

## FRS.2 Measured (desktop render, labelled)

- **Lobby lighting** (iPhone 14 shape, Mesa limited to AVX): Home room mean
  luma 88 → 97, near-black pixels 17 % → 10 %, the runner +6 luma, nothing
  clipped; every line on the room at 4.97:1 or better (was 3.18).
- **Season Pass figure height** (points): SE 70 → 204, 844×390 70 → 203,
  926×428 80 → 231, iPad 206 → 348.
- **Rendering fault found:** on this machine's CPU (AVX-512 FP16) llvmpipe
  drops the directional light on characters in Mobile-renderer captures;
  `tools/gd.sh` now limits llvmpipe to AVX (matches Forward+). Character
  pictures rendered here before this sweep under-light the characters.

## FRS.3 Evidence

| What | Where |
|---|---|
| Lobby before/after, load-in clips, the L1 fault comparison | `docs/media/final/lobby/` |
| Season Pass before/after at four shapes, skin inspection, a normal-speed clip | `docs/media/final/season/` |
| Friends panel states, toast, entry points at four shapes | `docs/media/final/friends/` |
| Shop filters, App Store outfits, Coin packs, the schedule fallback | `docs/media/final/commerce/` |
| App Store screenshot candidates | `docs/media/final/store/` |

# Pass 9 (version 1.9)

Pass 9 builds on 1.8 (8):
- one steady full-input speed with no stamina (runner 6.0 m/s, Night Watch
  6.6; protocol 8);
- the Record Breaker and Dr. Doom skins;
- garments that sit on the body, and animation at the new speed;
- Season 1 · After Hours extended to 100 tiers;
- the owner's "Soft Bounce Loop" as the round music, blended in from the
  lobby music.

Notes, defect register and owner dependencies:
[docs/PASS9_NOTES.md](docs/PASS9_NOTES.md); per-area details in
[docs/pass9/](docs/pass9/). **No physical iPhone or iPad was available**:
everything below is desktop Linux, the service's Node tests, and CI iOS.

## P9.1 Automated tests

Full game suite on the integrated code (local, headless, commit `995d488`):
**523 tests, 105,357 checks, 0 failures** (718 s). Service (`service/`,
Node): **68 tests, 68 pass**. Character checks on the shipped GLB (art
version `v10-5fd133068d04`): `fit_check.py` (24 looks × 567 poses),
`skins_check.py`, `outfit_check.py` and `clip_check.py`, **0 failures**
each. The gating numbers of the upload run are in P9.5.

| Suite (new in Pass 9) | What it exercises |
|---|---|
| `test_p9_movement` (9) | The movement probe and its contract (60 s of full input at 6.00 m/s with 0 drop ticks; diagonal stick, wobble, jumps; no input pattern beats holding full input except a dive's 8.0 m/s peak); the Night Watch closes on a full-speed runner; dive edges press by press; motor state round trip and resets; bots run steadily (the M2 wall-slide fix); footstep noise follows actual speed; guest prediction of full speed and dives; protocol 7 and 9 refused with "Update the game to join."; a guest holds full speed for a minute online (min 5.97 m/s, corrections ≤ 0.1 cm) |
| `test_p9_full_speed_touch` (1) | Real touches in a Practice round: parked at the stick's rim for 60 s (3,582/3,582 frames at 6.000 m/s), rim jitter, a part push, back to the rim; no sprint control, meter or words anywhere |
| `test_fit_p9` (5) | The imported skinning setup; runtime deformation matches the asset; garments stay on the body in final poses (every look); a cosmetic swap mid-run keeps the gait and the fit; interruptions leave no layer latched |
| `test_skins_p9` (10) | New IDs; the complete-skin override keeps and restores every modular choice; expressions on the active head; wire round trip and unknown IDs; the Night Watch keeps its uniform and the player's face; budgets and the shared material; portraits never show the previous face; every motion scenario with each skin; identical simulation; Locker and Shop copy |
| `test_season100` (13) | A 30-tier account keeps everything; old cached wallets; tiers 50 and 100 need the tier and Premium; claims survive lost replies, offline, reinstall and a second device; a 100-tier Claim all in batches, granted once; an older service and a changed reward never mis-grant; navigation and milestones at four device shapes; the featured preview with the real art; finger swipes never select; the season tier stays apart from the lifetime level; the Shop never advertises 100 rewards |
| `test_match_music` (7) | The round track loops sample for sample (no gap, no click, level across the wrap); level matched to the lobby track; `blend_start` lands a round beat on the lobby beat (200 random positions); the filtered beat blend; back to the lobby mid-blend; no blend from silence or muted; results and lobby transitions unchanged |
| Updated | `test_pursuit`, `test_chase_balance`, `test_net` (anchored 6 s legs), `test_controls`, `test_profile` (Pass 8 sprint settings dropped, the rest kept), `test_touch_input`, `test_match_hud_pass8`, `test_lobby_music`, `test_p8_results_music`, `test_catalogue`, `test_sim`, `test_motion_v5`, `test_stick_probe`, `test_stick_round`, `test_v7_screens`, `test_challenges`, `test_runner_pace`. `test_p8_movement` and `test_p8_sprint_touch` are replaced by the two `test_p9_*` movement suites. |
| Service: `season.test.mjs` (8) | The 100-tier table keeps tiers 1–30 exactly; migration 0005 keeps every row; a 30-tier account keeps XP, claims, items, Premium and Coins; Premium alone never unlocks an unearned tier and XP alone never grants a Premium reward; idempotent claims (repeats, lost reply, two devices, reinstall); an old 30-tier game, a changed reward, unknown tiers; a whole 100-tier Claim all; Season XP keeps counting past tier 30 |

## P9.2 Movement and balance, measured (headless sim)

- **Probe** (`docs/pass9/data/movement_{1.8,1.9}.json`): full input held
  60 s, 5.00 → **5.99 m/s average, slowest settled tick 6.00, 0 drop
  ticks**. The Pass 8 best (sprint release / re-press) averaged 5.98, a
  sawtooth to 7.4; 1.9 has no such pattern. The best jump/dive chain
  is 5.38 m/s, below holding full input. A single dive still peaks at
  8.0.
- **Chases** (`test_pursuit`): the Night Watch catches a full-input runner
  from 8 m in 10.6 s (1.8: 3.8 s against a non-sprinting runner, 11.1 s
  against released sprint bursts). Turbo gives 7.5 m/s for 3 s and opens
  the gap for its duration.
- **Seeded bot-round matrix** (`docs/pass9/data/balance_*.json`, 12 rounds
  per row, desktop headless; bots, not people):

| Runner wins (1 / 2 / 3 Night Watch) | 1 | 2 | 3 |
|---|---|---|---|
| 1.8 | 11/12 | 10/12 | 5/12 |
| 1.9 with 1.8's bot steering | 12/12 | 10/12 | 5/12 |
| **1.9 as shipped** | 12/12 | 12/12 | 8/12 |
| 1.9, Night Watch 6.8 (not adopted) | 12/12 | 11/12 | 5/12 |

  The movement change alone leaves outcomes where they were. The rise in
  runner wins comes from the bot fix (M2: runner bots no longer crawl along
  walls). That is a fix to bots, not a change to the rules, so the Night
  Watch was not buffed to compensate. 6.0 / 6.6 is kept. Details and
  confidence intervals: [docs/pass9/movement.md](docs/pass9/movement.md) §4.

## P9.3 Visual, audio and behavioural evidence (desktop render, labelled)

| What | Where | Shows |
|---|---|---|
| Movement before/after (real Practice round, Movie Maker, normal speed) | `docs/media/pass9/movement/` | 60 s full-input and online traces, the dive chain, 1.8 vs 1.9 side by side |
| Garment fit | `docs/media/pass9/fit/` | Close-ups before/after (cuffs, hems, shoulder caps, hip tops, footwear), the reversal at 6.0 m/s |
| Record Breaker and Dr. Doom | `docs/media/pass9/skins/` | Line-ups in dorm, campus and studio light at thumbnail and gameplay distance; actions; expressions; fit close-ups; the white shorts before/after; thumbnails; concept art beside the engine render; a reel of each skin |
| Season Pass to tier 100 (13 shots × SE / iPhone 14 / Pro Max / iPad) | `docs/media/pass9/season/` | Navigation, milestones 50 and 100 with the skins' real portraits and live preview, claimable/claimed/pending, an older service, service off. Re-captured after the skins merged; every layout measurement unchanged |
| Lobby → round music | `docs/media/pass9/music/` | The spectrogram across the blend and an 11 s excerpt from an engine capture (round beat 1.1 ms from the lobby beat; no click; no level dip) |

## P9.4 Found and fixed during Pass 9 integration

- **Runner bots crawled along tall walls** and never hopped low ones (also
  on 1.8; M2 in the notes). Found by the new steady-speed bot test.
- **22 motion tests failed at 6.0 m/s.** A reversal fired the planted stop
  for one frame. Fixed in the view: the body has to be stopped for 30 ms
  (F2).
- **A lag-compensation test depended on phase** at the smaller 0.6 m/s
  closure. Its legs are now anchored (M3); the tagging rules are
  unchanged.
- **The online 60 s trace dropped when the circle clipped an obstacle**
  that a line-of-sight ray missed. The test now sweeps a sphere; the game
  was not at fault.
- **The garments' fit and the skins' fit** were fixed at the generator
  (F1, S2), and the white shorts' material (S1).
- **The Season Pass featured preview** was measured on a stale page height
  on the iPad; it now refits when the page is shown.

## P9.5 iOS build (CI iOS) and TestFlight

- **Gating CI:** upload run #125
  (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37360488402),
  on commit `1704d9d` (the code of `995d488` plus captures and
  documentation).
  - Headless tests: **523 tests, 105,358 checks, 0 failures**.
  - Xcode project export, launch and branding audit **PASS**: both launch
    images 1656², opaque, black corners; the logo's box matches the vector
    exactly; 0 detached glow and 0 inner dip pixels; 0 "powered by"
    strings.
  - Signed archive and upload, `CFBundleShortVersionString` 1.9,
    `CFBundleVersion` 9, arm64, 302 MB.
  - 40 Metal `shader_cache` entries. As with 1.8, the baking editor exited
    with code 250 after the export (a Godot crash report on the runner).
    The lane judged the export by its output, which was complete.
  - Xcode warned that the four embedded plugin frameworks have no dSYMs.
    The upload succeeded.
- **Simulator (x86_64, ~1 fps):** cold launch running, no crash report for
  the app, 0 script errors, 23 screenshots; still preparing the bot round
  (phase 1) when the window closed. Not a phone.
- **TestFlight:** **1.9 (9)** uploaded 2026-10-05 19:23:26 UTC.
  - App Store Connect build `8a207a62-69de-4c34-95bd-a90e4c8504ec`.
  - Processing `VALID`, `INTERNAL_ONLY`.
  - Internal state `IN_BETA_TESTING`; external `NOT_APPLICABLE`.
  - What to Test set (1,844 characters).
  - The existing internal group receives every build automatically.
  - Read from Apple's API by run #125 at 19:38 UTC.
  - No testers added, nothing submitted, no purchase made.
  - Status run #117 beforehand: builds 1–8, no 1.9.

## P9.6 Not verified (exact remaining checks)

- **On a real iPhone/iPad:**
  - the steady speed with a thumb at the stick's rim, and on a controller;
  - chase length with people;
  - the two skins at play distance on a phone screen;
  - the Season Pass navigation by touch;
  - the lobby → round blend on the device's speaker and headphones;
  - frame rate and heat.
- **Human balance:** the matrix is bots. Who wins with people, and whether
  Turbo is too strong, need playtests.
- **Game Center rounds** between two devices on protocol 8, and 1.8 being
  refused against a 1.9 host.
- **Live service:** season claims at tiers 50 and 100, Premium, Coin
  purchases and challenges. None of it is possible until the account
  holder deploys the service and creates the products (TESTFLIGHT_RELEASE,
  COMMERCE_SETUP).
- **Owner confirmations:**
  - likeness permission for the two skins;
  - mureka.ai's terms for both music tracks.

# Pass 8 (version 1.8)

Pass 8 ("pass eight") builds on 1.7 (7): the sprint exhaustion latch and
the jump→dive nerf, match clarity (goal bar, next action, Runner pace,
series line, results order, map sight cues), six rotating Shop skins on a
real schedule, three more Coin packs, challenges that add Season XP, crisp
startup logo edges and a central RESULTS music state. Notes, defect
register and results: [docs/PASS8_GAMEPLAY_COMMERCE_NOTES.md](docs/PASS8_GAMEPLAY_COMMERCE_NOTES.md);
per-area details in [docs/pass8/](docs/pass8/). **No physical iPhone or
iPad was available**: everything below is desktop Linux, the service's Node
tests, and CI iOS.

## P8.1 Automated tests

Full game suite on the integrated code (local, headless, commit `7e9602a`):
**482 tests, 102,855 checks, 0 failures**. Service (`service/`, Node):
**60 tests, 60 pass**. CI headless tests on the same commit (push run #110)
passed; the gating numbers of the upload run are in P8.5.

| Suite (new in Pass 8) | What it exercises |
|---|---|
| `test_p8_movement` (6) | The movement probe on the campus's longest clear straight and its contract (one sprint burst per hold, re-armed bursts real, no dive pattern at or above the Watch's 6.6 m/s, a dive loop slower than released sprint bursts, a deliberate dive still a burst); the `test_pursuit` Watch catches a dive-looping runner; accepted and rejected jump/dive edges press by press; motor-state round trip and resets; bots re-arm; guest prediction of the latch and dives at 50 ± 8 ms and 2 % loss (0 corrections over 25 cm) |
| `test_p8_sprint_touch` (1) | Real touches in a Practice round: parked at the stick's edge for 6 s gives one burst, then running with the meter empty and the stick showing the latch (never sprint on); easing under the exit threshold re-arms; pushing to the edge again sprints on the next tick |
| `test_p8_results_music` (4) | No results track shipped and no placeholder; without one the sting plays once and the lobby music continues under results; a cancelled round plays no flourish; with a bed (test stand-in only) it starts once per round result and is never restarted by reopening results |
| `test_runner_pace` (8) | Distance fields and route orders against hand enumeration, ordering rules (home by tick, stamps, route; 4 m shared places, anchored), approximate places, caught penalty, bots counted, debounce, the wire block (no positions) |
| `test_match_hud_pass8` (9) | Goal bar from the round's own configuration; runner and Watch cards in every state; series line never fakes a place; sprint-empty hint follows the latch and the hold; pinned challenge line in pause and map; layout at every device size |
| `test_shop_rotation` (12) | Service time as a monotonic offset (a device clock change never adds time); countdowns and local departure wording; in-place swap at expiry; refresh feedback respects Reduced Motion and focus; an expired offer can't be bought from any path; offer changed before acceptance charges nothing; accepted before expiry delivered after a lost reply; owned skins stay owned and return owned; service-off and stale states; compact Coin pack cards with StoreKit prices or "Not available"; "Best value" only from same-currency numeric prices; all six packs deliver their quantity once |
| `test_challenges` (10) | UTC periods and grace, credits and the active-play threshold, the activity evidence rule and the real-simulation meter, service-off and practice add nothing and say so, a settled round completes a goal once and moves the pass, inactive rounds, results lines, the Season Pass page at four device shapes, completion motion once (not under Reduced Motion) |
| `test_outfits_p8` (7) | The six outfits' keys, prices, includes copy and wire round trip; footwear, cap and hood rules; budgets; head pieces clear of the face; concealment against the Night Watch; ten motion scenarios; identical simulation whatever the outfit |
| `test_boot_branding` (extended) | Vector-exact launch image and curtain raster; edge, halo and size checks (fail on 1.7's images) |
| Service: `offers.test.mjs`, `challenges.test.mjs` | Offer windows to the millisecond, replay after expiry, overlapping offers, the schedule rule and tool check, the iap-diff plan; challenge periods, grace, caps, concurrent and duplicate settlement (one bonus), v1 reports, implausible `active_s`, device sync, deletion and sweep |

## P8.2 Movement, measured (headless sim)

The probe (`docs/pass8/data/movement_{before,after}.json`, build 7's code
vs this branch): sprint held 30 s 22 → 1 bursts; the best jump→dive chain
8.05 → 5.23 m/s (released-and-repressed sprint bursts 5.98 both builds;
the Watch 6.6); a single dive still peaks at 8.0 m/s; pursuit from 8 m:
the dive loop escaped → caught after 4.5 s, sprint bursts 11.1 s both
builds. Details, traces and normal-speed clips: [docs/pass8/movement.md](docs/pass8/movement.md).

## P8.3 Visual and behavioural evidence (desktop render, labelled)

| What | Where | Shows |
|---|---|---|
| Movement before/after (real Practice round, Movie Maker 30 fps, normal speed) | `docs/media/pass8/movement/` | Sprint held and jump→dive spam on 1.7 (7) and Pass 8, side by side; speed/meter/latch traces |
| Match HUD, map and results (72 shots, SE / iPhone 14 / Pro Max / iPad) | `docs/media/pass8/match/` | Every runner and Watch card state, pace, map sight and last-seen, results order; measured rects, no overlaps |
| Shop (33 shots, SE / iPhone 14 / iPad) | `docs/media/pass8/shop/` | Featured with countdowns, the 00:00 UTC change, offer sheet and confirmation, Coin packs, out-of-rotation, stale and service-off states; 0 layout issues |
| Challenges (SE / iPhone 14 / Pro Max / iPad) | `docs/media/pass8/challenges/` | The Season Pass Challenges page, settled and pending results lines, practice, service-off preview (test-double service labelled) |
| Six skins | `docs/media/pass8/skins/` | Campus and dorm light at play distance, close-ups, an action sheet, skin tones, thumbnails, a 30 s action reel of the heaviest look |
| Startup logo (lossless PNG) | `docs/media/pass8/logo/` | Every startup stage at four device sizes, 400 % edge crops, handoff difference images, the fade frame by frame |

## P8.4 Found and fixed during Pass 8 integration

- Guest prediction snapped at dive landings (paired 0.27 m corrections):
  the floor snap now follows the serialized `on_floor`.
- The touch stick showed sprint on while the latch kept it off: it now
  follows the motor and draws the latch.
- `test_wardrobe` failed only in the full suite: `test_shop_rotation`
  restored the window to the wrong size; found by running the two together
  (`run_tests.gd -- a,b`, new).
- Two merged streams each added a clock to the fake commerce service; one
  clock now drives offers and challenges.
- The layout checker reported scrolled-out "New" chips as off screen (it
  read only the nearest clip); it now intersects every clip, as the engine.
- The Shop's includes copy said the Locker's shoes stay for outfits that
  bring their own footwear; it now says what each outfit replaces.

## P8.5 iOS build (CI iOS) and TestFlight

- **Gating CI:** push run #110 (commit `7e9602a`, the final game code)
  headless tests passed; upload run #112 (commit `406773c`, the same code
  plus evidence and documentation): **482 tests, 102,855 checks, 0
  failures**; Xcode project export, launch and branding audit **PASS**
  (both launch images 1656², opaque, black corners; the logo's box matches
  the vector exactly; 0 detached glow and 0 inner dip pixels; the boot
  splash identical; 0 "powered by" strings); signed archive and upload,
  `CFBundleShortVersionString` 1.8, `CFBundleVersion` 8; 40 Metal
  `shader_cache` entries. The baking editor exited with code 250 after the
  export (a Godot crash report on the runner, before the Simulator run);
  the lane judged the export by its output, which was complete, and that
  output was signed and uploaded (see TESTFLIGHT_RELEASE).
- **Simulator (x86_64, ~1 fps):** cold launch running, no crash report for
  the app, 0 script errors, 23 screenshots; still preparing the bot round
  (phase 1) when the window closed. Not a phone.
- **TestFlight:** **1.8 (8)** uploaded 2026-10-05 06:11:05 UTC; App Store
  Connect build `39a7c5ae-4c47-4f82-997c-58b819b44d89`, processing `VALID`,
  `INTERNAL_ONLY`, internal state `IN_BETA_TESTING` (external
  `NOT_APPLICABLE`), What to Test set (1,772 characters); the existing
  internal group receives every build automatically. Read from Apple's API
  by run #112 at 06:25 UTC. No testers added, nothing submitted, no
  purchase made. Status run #111 beforehand: builds 1–7, all eight in-app
  products `MISSING`.

## P8.6 Not verified (exact remaining checks)

- Everything on a real iPhone/iPad: sprint and dive feel with a thumb
  (edge sprint, Sprint button, controller), the HUD, card and pace at
  phone scale and whether they read "at a glance" (no comprehension test
  with people was run), the Shop countdowns across sleep, the new Season
  Pass page, the six outfits at play distance, frame rate and heat.
- The startup on a phone: PNG screenshots of the launch screen, the boot
  splash and the curtain, ideally on an SE/XR-class 2x iPhone and a
  13-inch iPad (upscaled 1.24× until the curtain, documented in
  docs/pass8/logo.md).
- Game Center rounds between two devices on protocol 7 (Runner pace on the
  wire, the latch in prediction).
- Live commerce: the service deployed, the eight products created and
  priced, a rotating offer across 00:00 UTC, a Coin pack in Sandbox, a
  challenge completed in a two-device round. None is possible until the
  account holder's steps in TESTFLIGHT_RELEASE are done.
- The results track (not supplied; the RESULTS state is ready for it).

# V8 (version 1.7)

V8 is the smoothness, animation and finish pass on 1.6 (6): bot path
searches off the main thread, one owner of character visibility, a remote
jitter buffer with a monotonic presentation clock, authored starts, stops,
turn leads, run/sprint, jump/landing and Night Watch tag motion, terrain
contact for planted feet, smoother eye and lens shading with satin and metal
materials, and a governor that tells CPU-bound from GPU-bound windows.
Notes, defect register and results: [docs/V8_NOTES.md](docs/V8_NOTES.md);
measurements: [docs/v8/performance.md](docs/v8/performance.md),
[docs/v8/motion.md](docs/v8/motion.md); pictures and clips:
[docs/media/v8/](docs/media/v8/README.md). **No physical iPhone or iPad
was available for V8 either**: every number below is desktop Linux.

## V8.1 Automated tests

**CI gating run #97** (commit `5e96387`, the final game code; later commits
change documentation and evidence only): **418 tests, 99,344 checks, 0
failures**; export, launch and branding audit, unsigned device archive and
Simulator run passed.

| Suite (new or extended in V8) | What it exercises |
|---|---|
| `test_v8_hot_paths` (6) | A network-pruned opponent stays hidden and comes back at its real place (build 6: shown for 119 frames after pruning, then slid 116 m); far characters animate ~20 times a second at 30, 60 and 120 fps, at most 4 of 8 on one frame; effects: bounded warm-up, simultaneous bursts reuse warm emitters, one colour ramp per colour, bounded ramp cache, idle emitters hidden and a runner's drips shown only while dripping; the governor's ring window; the governor's CPU/GPU attribution |
| `test_v8_timing` (6) | The presentation clock never steps back and keeps delay and underruns bounded in three seeded conditions; curves only where safe; start-up hold, bounded extrapolation stopped short of walls, airborne hold, cart start-up/bracket/underrun; **underrun recovery** (fails with the blend off: a 0.82 m one-frame jump); **a loss burst is not a re-seen slot** (fails on the first rule); a correction offset does not turn the body; remote cosmetic beats wait for the drawn time |
| `test_v8_motion` (5) | The V8 clips are in the asset; a stop from a run plants once, after the body has stopped, with the brake first, and a walk does not; a start drives then lets go; reversals and 90° turns are led on one side and ease off; terrain contact on a 20 % ramp halves the planted ankle's error with one ground sample per step |
| `test_path_budget` (extended) | Searches answer on their scheduled tick even with a 400 ms worker; requesting costs under 2 ms |
| `test_diag` (extended) | The governor and remote-presentation lines reach the shareable summary, one line per key, and clear with the rest |
| route bots | 96/96 + 36/36 routes finished with worker searches (an early version lost paths while a search was in flight: 3/6 and 4/6) |

## V8.2 Performance, network presentation and motion (desktop)

Summarised in V8_NOTES "Results"; full tables in performance.md and
motion.md. Headline (gameplay bench, 3 runs each, build 6 → V8): Standard
p99 21.5 → 19.0 ms and frames over 33.3 ms 43 → 5 in 225 s of play;
Battery Saver p99 43.3 → 37.1 ms and frames over 50 ms 42 → 2; bot thinking
in the worst frame 40.9 → 7.9 ms. Network probe: other players drawn ~54 ms
behind on a clean link (build 6 ~117 ms); at 300 ms RTT with 10 % loss,
frames with nothing to draw 117 → 2; 0 backward steps anywhere. Motion
probe: every scenario inside the V5/V6 bounds.

A confirmation on the final code (`5e96387`, two Standard runs) ran
after the session moved to another machine, whose CPU sections all measure
~30 % faster, so it is not compared with the table above. On it: p99 18.1 ms
in both runs; frames over 33.3 ms 1 and 0. The one long frame was 191 ms at
the first frame of the first round, with ~12 ms of instrumented game work;
it was the first run after that machine started and did not recur in the
second run (worst frame 32.8 ms), consistent with a cold disk cache, which
is not proven.

## V8.3 Visual and behavioural evidence (desktop render, labelled)

| What | Where | Shows |
|---|---|---|
| Motion, before/after (Movie Maker, fixed 30 fps, 960×540, normal speed) | `docs/media/v8/motion/` | The motion-test scenarios on both builds; a stop filmstrip |
| Characters, before/after (900² cells, campus and dorm light) | `docs/media/v8/characters/` | Eyes, goggle lenses, satin, metal, Night Watch, gameplay distance |
| Campus, before/after (1280×720, Standard preset) | `docs/media/v8/campus/` | Unchanged layout and lighting; calmer distant paving |

## V8.4 Found and fixed during V8 integration

- Bots dropped their current path while a worker search was in flight
  (route bots 3/6 and 4/6): they now keep it if it leads to the same goal.
- The additive layers first moved the pelvis (planted-foot slide 0.36–0.69
  m/s); they no longer touch it.
- The turn lead flipped sides at 180° (a 38.5 cm pop); its side now comes
  from the turn rate and is kept until it has eased off.
- The drive and brake layers reacted to reconcile noise (frames with a
  > 3 cm pop in the `correction` scenario 70 → 198); they now read a
  filtered, dead-zoned acceleration (84).
- The planted stop could fire during the Night Watch's miss recovery; it
  no longer fires while the tag owns the body.
- The brake layer's release kicked the arms when the stop fired (9.6 cm,
  bound 9); it now hands off from zero slope (8.3).
- The re-seen rule (D2) cut every remote after a burst of lost snapshots
  (15 snap frames): only a slot missing from snapshots that did arrive is
  re-seen now; held runners rejoin their path smoothly (D11, D12).
- The warmed effect pool and runners' drip emitters were drawn while idle
  (41 draw calls at the same view in the render bench; the mean was 18
  above build 6's): idle emitters are hidden, and the final code averages
  236 draw calls against build 6's 243.

## V8.5 iOS build (CI iOS) and TestFlight

- **Gating CI:** push run #97 (commit `5e96387`, the final game code)
  green: 418 tests, 99,344 checks, 0 failures; upload run #99 (commit
  `00dc652`, the same code plus documentation): **418 tests, 99,343 checks,
  0 failures**; signed archive and upload, `CFBundleShortVersionString` 1.7,
  `CFBundleVersion` 7; launch and branding audit **PASS**; 40 Metal
  `shader_cache` entries.
- **Simulator (x86_64, ~1 fps):** cold launch running, no crash report, 0
  script errors, 23 screenshots; the bot round was still preparing
  (phase 1) when the window closed. Not a phone.
- **TestFlight:** **1.7 (7)** uploaded 2026-10-04 23:00:18 UTC; App Store
  Connect build `3a68fdfb-043d-4e2f-882d-793e09dd7956`, processing `VALID`,
  `INTERNAL_ONLY`, internal state `IN_BETA_TESTING` (external
  `NOT_APPLICABLE`), What to Test set (1806 characters); the existing
  internal group receives every build automatically. Read from Apple's API
  by run #99 at 23:18 UTC. No testers added, nothing submitted, no purchase
  made.

## V8.6 Not verified (exact remaining checks)

- Everything on a real iPhone/iPad: frame rate and presentation pacing on
  Standard and Battery Saver, GPU time, heat over 15 minutes, battery,
  touch feel, whether the livelier arms read well at phone scale.
- Game Center between two devices (the jitter buffer was measured on
  seeded loopback conditions only).
- Open items listed in V8_NOTES "Open, and not verified".

# V7 (version 1.6)

V7 is a focused repair and refinement pass on 1.5: Pause, Resume and Leave
match (priority zero); forward runs wandering left/right on the touch stick;
compact Locker, Emotes, Season Pass, Shop, Play with Friends and Settings;
goggles and character refinement; music about 3 dB louder. Notes and the
measured registers: [docs/V7_NOTES.md](docs/V7_NOTES.md),
[docs/v7/menus_notes.md](docs/v7/menus_notes.md),
[docs/v7/screens_notes.md](docs/v7/screens_notes.md),
[docs/v7/character_notes.md](docs/v7/character_notes.md). **No physical iPhone
or iPad was available for V7 either.** Touches in every test and clip below
are **emulated**: `InputEventScreenTouch`/`ScreenDrag` parsed by `Input` at the
controls' rendered coordinates, as iOS delivers them.

## V7.1 Automated tests

**On this machine, on the fully integrated tree** (`tools/run_tests.sh`):
**399 tests, 99,186 checks, 0 failures** (load average ~14 from captures
running alongside). `tools/check_v7_screens.sh` (the screens file at each
device's real point scale, safe area and pixel size): 10 tests at each of
seven sizes, 0 failures. CI's gating run is in V7.5.

One CI run (#91) failed on a pre-existing race in
`test_loading::test_practice_can_be_cancelled_mid_preparation…`: on the fast
runner the round finished preparing inside the 0.8 s before Cancel enables,
and the loading screen was freed under the test. The test now holds the
controller's preparation step (its worker-pool jobs keep running) so it
always cancels mid-build.

| Suite (new in V7) | What it exercises |
|---|---|
| `test_pause_input` (9) | Real touches: Pause with one finger and with a second finger while the first steers; Resume, slider, Leave, Stay, Leave-confirm take taps; Practice freezes (sim tick frozen 120 frames, nothing moves) and resumes with ≤ 2 ticks/frame; 20 × (open → slider → Resume) and (open → Leave → Stay), 40 opens/40 closes/0 quits, then Leave twice-tapped quits once and the next match pauses normally; a finger held from before never moves the runner, a fresh one does; Night Watch cart throttle released and not resumed; Pause/Resume queue no Jump/Tag; map/back/pause-key/background policy; the Pause region equals the button (standard and mirrored, ≥ 44 pt) |
| `test_pause_online` (2) | Loopback rig: the host's and a guest's menu never pause the round (host +50 ticks / 60 frames, guest snapshots keep arriving), input neutral, no immunity; the honest leave text per role; guest Leave once, no finish/result/reward; results close the menu and confirmation; Pause stays shut over results |
| `test_stick_drift` (11) | Neutral touchdown and exact vertical everywhere in the zone (5 canvases, both notch sides, standard/mirrored/large/custom layouts); knob drawn at ring + real offset; fixed stick contract; base-follow continuity; straight-ahead tolerance continuous, monotonic, magnitude-preserving; spare-finger slop; pad drift ignored under touch; camera closed loop (leans 0–6° held 10 s, a wall slide) ≤ 0.5°; deliberate 15° follow identical at 30/60/120 fps; cart recentering; bounded diagnostics trace |
| `test_stick_round` (3) | Real touches in a Practice round on a clear straight: corner touchdown neutral and straight in both layouts, release stops; a 5° lean doesn't curve; a guest's straight commands stay straight on host and guest. **Run on the pre-fix build it fails 8 checks** (`docs/v7/stick/test_stick_round_on_prefix_build.txt`) |
| `test_menus_layout` (10) | Season Pass rows and detail action whole at seven sizes, service on and off; claim states; Locker and Shop bounds at every size; neutral outfit pictures; swipes from glyphs/portraits/labels never select; one centred emote set; controller focus; entries never move hit targets |
| `test_v7_screens` (10) | Friends first view, keyboard, short messages, Game Center states; Settings sections whole and aligned; finger scrolling keeps values; Delete still confirmed; party room with 1/4/8 players; results/standings first rows; long lists inside their sheets; every visible control on screen, in the safe area, ≥ a touch target, untrimmed and reached by a pointer |
| `test_characters_v7` (4) | Goggles against the head surface, symmetry, lens facing, strap closure, brows under the cap edge for every brow/face preset. **Fails 15 checks on the 1.5 asset** |
| `test_lobby_music` (extended) | One central −3 dB trim, levels at two slider values, mute, one Master limiter |

## V7.2 Forward drift, measured (headless, emulated touches)

`tools/stick_probe.sh`: a Practice round on an 812×375 pt canvas, the runner
on the longest clear straight (nav grid open, physics swept), bots idle,
scripted touches through the real touch → command → sim → camera path; the
same probe file on the pre-fix build and after. Selected rows (all rows in
docs/V7_NOTES.md and `docs/v7/stick/`):

| Case | Before | After |
|---|---|---|
| Bottom-left corner touchdown, exact vertical, 6 s | touchdown output 1.00; 31.1 m sideways, 5.3 m forward | 0.00; 0.0 m sideways, 37.3 m forward |
| 6° lean + wobble, recentering on, 6 s | camera −107°, runner circled (6.2 m forward) | camera 0°, 0.8 m sideways over 37.3 m |
| Dorm start, out of the door, 4° lean, 8 s | camera −147°, 4.2 m forward | camera 0°, 49.1 m forward |
| 3° lean held 15 s | camera −81° | 0° (88.7 m straight) |
| Thumb in dead zone + pad drifting 0.25 | walked 1.4 m, camera −10° | nothing |
| Deliberate 15° / 45° / 90° / 180° | 15 / 45 / 90 / −180° | 15 / 45 / 90 / −180° |

Same results at 30 and 120 fps render (physics 60 Hz).

## V7.3 Visual and behavioural evidence (desktop render, labelled)

All are the real game on desktop Linux with emulated touches, labelled in
the image or file; nothing is sped up or interpolated; none is device
footage or frame-rate evidence.

| What | Where | Shows |
|---|---|---|
| Pause, before/after (Desktop render, Movie Maker 30 fps, 1040×480 phone-shaped window) | `docs/media/v7/pause/` | 1.5: the menu never takes a tap and stays open, the Practice clock runs on; V7: dimmed modal, the clock stops, slider, Resume, Leave → Stay, Leave once |
| Forward drift, before/after (same) | `docs/media/v7/stick/` | Corner touchdown 24.8 m sideways → 0.0; a 6° lean turned the camera +94° → 0°; long push −32° → 0° |
| Locker, Emotes, Season Pass, Shop (Desktop render at seven device shapes, measured rects) | `docs/media/v7/menus/` | Before `d2d0749` / after; service-on with the labelled test adapters, service-off as shipped |
| Friends, Settings, home, party room, results, confirmations (same, emulated keyboard) | `docs/media/v7/screens/` | Matched pairs and measured layout facts at seven sizes |
| Goggles and characters (Desktop render, 900² per cell; reel 1280×720 at 30 fps) | `docs/media/v7/characters/` | Close-ups, views, poses, faces, before/after reel, thumbnails, budgets |

## V7.4 Found and fixed during V7 integration

- The pause and drift clip reels first injected touches in canvas units into
  a smaller movie window (they landed 1.5× too far out); fixed by converting
  to window pixels before any clip used here was recorded.
- `test_loading` cancel race on fast runners (V7.1).

## V7.5 iOS build (CI iOS) and TestFlight

- **Gating CI:** push run #93 (commit `d7c5bd2`) green; upload run #94
  (commit `4de97c7`, the same code plus documentation): headless tests
  **399 tests, 99,188 checks, 0 failures**; Xcode 26.6 (17F113), iOS SDK 26.5;
  signed arm64 archive (app 296 MB), `CFBundleShortVersionString` 1.6,
  `CFBundleVersion` 6, iOS 17.0+, iPhone and iPad, landscape; Game Center,
  StoreKit, SwiftGodotRuntime and UTShare embedded; privacy manifest; launch
  and branding audit **PASS**; 40 Metal `shader_cache` entries.
- **Simulator (x86_64, OpenGL ES, ~1 fps):** cold launch running after 92 s,
  no crash report, 0 script errors, 23 screenshots; the bot-driven round was
  still preparing (phase 1) when the window closed. Not a phone.
- **TestFlight:** **1.6 (6)** uploaded 2026-10-04 17:40:08 UTC; App Store
  Connect build `811b7ee6-9c27-4308-a84f-d33b74a8cdd9`, processing `VALID`,
  `INTERNAL_ONLY`, internal state `IN_BETA_TESTING` (external
  `NOT_APPLICABLE`), What to Test set (1954 characters); the existing internal
  group receives every build automatically. Read from Apple's API by run #94
  at 17:57 UTC. No testers added, nothing submitted, no purchase made.

## V7.6 Not verified (exact remaining checks)

- Everything on a real iPhone/iPad: Pause with another finger on real
  multi-touch, straight runs from the owner's own thumb (the 6°/16°
  tolerance, 4° follow threshold and 24 px slop come from scripted traces),
  the real iOS keyboard over Join, Dynamic Type, touch feel, frame rate and
  heat.
- Game Center sign-in and friends on hardware; the game service and App
  Store products remain off/unconfigured (unchanged).
- The goggles stay pushed up on the forehead (as designed); one head shape.

# V6 (version 1.5)

V6 answers the owner's report on 1.4: play turned suddenly very glitchy after running smoothly, match loading animated and then froze, finger swipes did not scroll the wardrobe, and results looked dated. It also adds:
- three real dorms, with doorway starts and finishes;
- coins;
- Locker, Shop, Season 1 and StoreKit (prepared, not live);
- a walkable party room, name moderation, Quick Chat (typed chat via the service) and report/block;
- rankings;
- the owner's lobby music.

Code is on `claude/ultimate-trifecta-testflight-oie9r7`. Notes and the measured defect register: [docs/V6_NOTES.md](docs/V6_NOTES.md). **No physical iPhone or iPad was available for V6 either.**

## V6.1 Automated tests

**On this machine, after integrating every workstream** (`tools/run_tests.sh`):
- **348 tests, 87,670 checks, 1 failure.** The failure was the `nav` preparation job at 45 ms against a 40 ms limit; it led to D8, which splits the grid into 17 ordered slices (longest 10.3 ms).
- After the fix, every suite touching navigation and loading passes.
- The service's own tests: 42 of 42 pass (`cd service && npm test`).

CI's gating run is in V6.7. V5 had 205 tests and 3,208 checks.

**Contention.** Four workstreams shared this 4-core machine, and wall-clock checks ("no long freeze while loading") failed several times under load averages of 16–23. Each one passed when re-run alone and in CI. They are reported here, not hidden.

| Suite (new or extended in V6) | What it exercises |
|---|---|
| `test_path_budget`, `test_diag`, `test_quality_governor` | D1: at most one path search per tick, reuse within a neighbourhood, unreachable goals remembered. Diagnostics record catch-up spirals, pipeline counts, stall context, counts at each round start, and background/resume (not counted as a stall). The render-scale governor (one hitch changes nothing, a sustained slow pace steps down, back-off, thermal, resume) |
| `test_loading` | Cancel at any point, including mid-build with meshes on the worker pool, three times: flat to the object. "Preparing campus…" and "Waiting for players" with an indeterminate sweep. **Nothing 3D drawn behind the loading screen; three warm frames of the placed start view; held while waiting; restored after the round and after a cancel** (D7). The reveal waits for the warm frames. Adaptive preparation budget |
| `test_trust` | D9: a slow guest that keeps reporting progress is waited for (up to 45 s); a silent or stalled one is not |
| `test_campus_art`, `test_prep_jobs` | The campus builder is freed after a build and after an abort (D5). The nav grid in 17 ordered slices equals the one-shot grid |
| `test_touch_scroll`, `test_stage_drag`, `test_wardrobe`, `test_shop_ui`, `test_screen_cycles` | Real GUI events with touch emulated as on iOS. Swipes from card pictures scroll and select nothing; a tap selects once; nested axes; a sheet opening makes the list behind let go (both checks fail without the fix); one finger owns drag-to-turn; category positions survive rapid switching. Ten tours of Home/Locker/Shop/Season Pass: nodes, orphans, connections and tweens flat, with the service on and off |
| `test_boot_branding` | Pure black `#000000` in the launch image, storyboard, boot splash and curtain |
| Dorms suites (see [docs/v6/dorms_notes.md](docs/v6/dorms_notes.md)) | All dorms and objective combinations. Spawn overlap; doors, collision, nav and bots. No exterior finish; threshold direction, height and high-speed crossing; the three-stamp requirement; finish beats a same-tick tag. Coin contention and de-duplication. Protocol 6 round configuration and incompatible geometry |
| `test_outfits_v6`, `test_motion_v6`, `test_profile` | Every new outfit through start, stop, reversal, turn, jump, capture, splash and emote. Foot lock. All 3,000 outfit × hat × shoe × hair combinations. Cosmetic looks leave the simulation unchanged |
| `test_catalogue`, `test_wallet`, `test_purchases`, `test_shop_ui` + service tests | Product matching and verification; success, cancel, pending and error; duplicate callbacks; interruption before and after a durable grant; transaction finishing; restore; account mismatch; sandbox/production separation; refunds; offline recovery. Atomic concurrent spends, migration twice, Season Free/Premium, Claim all repeated, practice isolation, earning limits, replayed results. **Against test doubles: no real StoreKit or deployed service** |
| `test_moderation`, `test_chat`, `test_hub_sync`, `test_hub_walk`, `test_match_chat`, `test_report_block`, `test_rankings` | Name and chat evasion with harmless exceptions; forged, markup, over-long and rate-limited messages; mute, block and report delivery; reconnect; spectator channels. Hub pose sync and walking. Rankings with ties, partial players and bots, and repeated result delivery |
| `test_lobby_music` | Sample-exact loop, one track across menus, fade out and back for a round, volume, interruptions |

## V6.2 The smooth-to-glitchy spiral (headless sim)

Same profiler (`src/dev/sim_profile.tscn`), same 8-bot round, before and after (`docs/test-data/v6_sim_profile_{before,after}.txt`):

| | V5 code | V6 |
|---|---|---|
| Bot thinking per tick | 11.9 ms (97 % of a tick) | 0.55 ms |
| Tick p50 / p95 / p99 / max | 16.8 / 26.8 / 35.8 / 60.8 ms | 1.36 / 2.24 / 3.70 / 25.6 ms |
| Ticks over 16 ms per round | 3,589 of 6,204 | 10 |

A headless soak on the V5 code showed windows where every frame ran the engine's maximum of 6 ticks (`docs/test-data/v6_soak_before.txt`). These are desktop CPU numbers; an A12 phone is slower, so the old spiral would start sooner there. **Unmeasured on a phone.**

## V6.3 Loading (desktop render, llvmpipe)

A per-frame probe of a rendered practice round (`docs/test-data/v6_loading_probe.txt`) measured the loading screen, step by step.

| Loading phase | Before (V5/V6 up to `139e361`) | After (D7) |
|---|---|---|
| Steps 0–6 (no camera yet) | ~35–40 ms per frame, 9 draw calls | ~35–40 ms per frame, 9 draw calls (no change) |
| From step 7 (the round's camera made current) to prepared | 17.7 s, 3.4 s and 4.8 s frames at 1,803 draw calls / 556k primitives: the whole campus, drawn from an unplaced camera behind the opaque screen | 37 ms and 50 calls while held |
| Once prepared | Same full-campus drawing; online, through the whole wait for other players | 3 warm frames from the placed start view (308 calls), still under the opaque screen, then held until the round is live |

Software-renderer times, not a phone's; the mechanism is the same on Metal.

**Pipeline counters (Vulkan on llvmpipe, not Metal).** During loading, 48 surface, 27 specialization, 7 canvas and 2 mesh pipelines were compiled. **During the round, 0 draw-time pipelines** and 21 specialization pipelines, which the engine compiles in the background (`docs/test-data/v6_beta_diag_llvmpipe_round.txt`).

**Clip.** `docs/media/v6/clips/v6_loading_into_dorm.mp4` (Movie Maker, fixed 30 fps clock) goes from Home through the loading loop into the reveal inside Moonpenny Lodge, then countdown, GO, and out of the door.

## V6.4 Visual and behavioural evidence (desktop render, labelled)

| Set | Where | What |
|---|---|---|
| V6 clips | `docs/media/v6/clips/` | Black cold launch; loading into the home dorm; finger swipes on Locker, Shop and Season Pass using real touch events (the Locker selection was unchanged by swipes, and swipes opened 0 App Store sheets) |
| Dorms | `docs/media/v6/dorms/` (56 JPEGs) | Every dorm's exterior and common room, bot-played rounds, door departures and returns (Moonpenny's runner never got home in its round; fixed views cover it), matched V5/V6 views, Battery Saver |
| Characters | `docs/media/v6/characters/` (18 JPEGs) | Before/after close-ups and skin tones in studio, campus and dorm light; every new item; poses; emotes; cached thumbnails; foot trails before/after |
| Commerce | `docs/media/v6/commerce/{phone,se,ipad}/` (19 each) | Home rail, Locker, Shop sections, detail, Coin confirmation, Season Pass, and the service-off states, **with test adapters ("(test price)")** |
| Social | `docs/media/v6/social/` (40 JPEGs) | Party room at 1, 2, 4 and 8 players; name refusals and harmless look-alikes; results and final standings on phone, SE and iPad; a local run of the real service code (not deployed): approved typed chat, a refusal, a report with receipt, the owner's queue, a block |
| Lobby music | `docs/media/v6/lobby_music/` | Loop-wrap verification |

**Not produced, and why:**
- **The Apple sandbox purchase sheet, delivery, restore and pending/error on StoreKit:** no products exist and no device or Sandbox account was available.
- **Real-device clips:** no device.

## V6.5 Networking on V6

- **Loopback.** The host/guest suites (`test_net`, `test_series`, `test_trust`, `test_lobby_flow`) pass on the integrated branch. Protocol 6 adds the round configuration (dorm, pads, coins, timing) to START; a guest with other dorm geometry is told to update. The social messages use IDs 60–65.
- **Slow host.** The rate budget now scales with real elapsed time, so a host running slower than real time no longer removes its guests as a flood; a real flood is still refused.
- **Game Center on devices:** not tested (no devices).

## V6.6 Found and fixed during V6 integration

- **D5:** the campus builder leaked on every cold build; on a cancelled round it leaked its worker-pool jobs too.
- **D10:** the Locker leaked one connection per visit (a V5 leak).
- **The cancel test** counted objects mid-transition, so it failed intermittently with +17/+18; it now counts once the screen has settled. Reported by the lobby-music session.
- **The Shop** asked for hat thumbnails in the head framing; tall hats were cut off.
- **A committed symlink** to the shared tools cache arrived with a merge and deleted the real cache (the pinned Godot binary). The cache was re-fetched, the link untracked, and `.gitignore` now matches a link as well as a directory.
- **A dorm-art helper and the builder** pointed at each other, so the builder wasn't freed on the dorms branch. Fixed by the dorms workstream.
- **`test_net`'s scripted Night Watch** missed its tag once runners started inside dorms; fixed by the dorms workstream.
- **The party room's new navigation row** pushed Start off screen; the row now measures itself. Fixed by the social workstream.
- **Shader baking:** run #63 shipped 0 baked shaders because the editor crashed while quitting after a finished bake. The script now judges the export by its output; runs #66, #67 and #78 shipped 40 entries.

## V6.7 iOS build (CI iOS) and TestFlight

**Signed and uploaded:** `com.idlery.ultimatetrifecta` **1.5 (5)** from `434fcd4`, the final V6 app code (later commits change only documentation).
- **Uploaded:** to App Store Connect at 17:08 UTC on 3 October 2026, by upload run #80 (https://github.com/BKimble1/ultimate-trifecta/actions/runs/37138538266).
- **Apple's processing:** `VALID`. The build is `INTERNAL_ONLY` and **available to internal testers** (`IN_BETA_TESTING`) in the owner's existing internal group, which receives every build.
- **What to Test:** set by the lane (1,674 characters).
- **Not done:** no tester was added, no external testing was requested, nothing was submitted for review, and **no purchase was made**. Details: `TESTFLIGHT_RELEASE.md`.

| Run | Commit | What happened |
|---|---|---|
| #63 | `c3daf59` | First V6 push build. All stages passed. The black launch audit passed. **The shader-baking export crashed while quitting, so 0 baked shaders shipped** (V6.6). |
| #66, #67 | `662294f`, `139e361` | All stages passed. The baking export was used: 40 `shader_cache` entries. Simulator: the new loading screen with Cancel and "Preparing campus…" renders, and the round was still loading when the window closed (~1 fps). |
| #75 | `8cdddc8` | `asc_status` (read only): builds 1–4 exist (latest 1.4 (4), `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`); no 1.5; all five catalogue in-app purchases are `MISSING`. |
| #78 | `8c93b30` | Push build with art, commerce, dorms and music merged. All stages passed. 1.5 (5) stamped; StoreKit embedded; the bake exited 250 (crash while quitting) but carried 40 entries and was kept (V6.6); Simulator 0 script errors. |
| #80 | `434fcd4` | `upload=true`. Tests: **348 tests, 87,672 checks, 0 failures**. Export, launch audit PASS (black), signed archive and upload of **1.5 (5)**, Simulator run, build facts, then Apple's processing: `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, What to Test set. Build facts below. |

**Run #80's build facts:**
- Xcode 26.6 (17F113), iOS SDK 26.5, arm64; 296 MB app; MinimumOSVersion 17.0; iPhone and iPad; landscape left and right; `ITSAppUsesNonExemptEncryption` false.
- Frameworks: Game Center, **StoreKit** (new), SwiftGodotRuntime and UTShare (arm64) are embedded. Xcode warned that the StoreKit framework has no dSYM, so its symbols were not uploaded.
- 40 baked Metal shaders.

**The Simulator, read honestly.** The CI Simulator is an x86_64 runner on the OpenGL ES fallback, not a phone's Metal path. In run #80:
- The cold launch's frames show the Idlery Games lockup on black.
- The app was still running with no crash report and 0 script errors.
- **For the first time since V4, the bot-driven round finished preparing on that Simulator.**
  - The session's status line reads phase `REVEAL` (2) at t = 5 s of game time; runs #62 (V5) and #67 read `LOADING` (1).
  - The last screenshots show the loading screen at **"Starting…"**: prepared, and drawing the start view's warm frames under it. Each 3D frame takes seconds on that path, so the window closed before the reveal appeared.
  - Earlier runs never left "Placing players…".

This fits D7 (no campus drawn behind the screen during preparation), D8 (nav grid in slices) and the adaptive budget. It is still not phone evidence. A desktop render of the same flow goes from loading into the round inside the dorm (`docs/media/v6/clips/v6_loading_into_dorm.mp4`).

## V6.8 Not verified (exact remaining checks)

**On an iPhone (none was available):**
- frame rate, pacing and heat over 20–30 minutes;
- whether play still turns glitchy (Diagnostics' Simulation and Pipelines sections answer this);
- loading from a cold start into a dorm without the loop pausing;
- finger swipes on Locker, Shop, Season Pass and results;
- the party room on 2–8 devices with Game Center;
- keyboard and notch on the name and chat sheets;
- the lobby music loop on device speakers.

**Shader baking on Metal:** whether the 40 baked entries are used on a device, and how many draw-time pipelines remain (Diagnostics).

**Purchases:** StoreKit purchase sheet, delivery, restore, pending/Ask to Buy, refunds, and sandbox/production behaviour. Nothing can be checked until the products exist, the service is deployed and a Sandbox account is used (`docs/COMMERCE_SETUP.md` §4).

**The service:** wallet, Season claims, verified rewards, typed chat, the moderation queue and server-side names. Its code passes 42 tests locally and has not been deployed.

**Remaining object growth:** about 41 small objects per full Home → Locker → Shop → Season Pass tour. Bounded by test; source not isolated.

# V5 (version 1.4)

V5 answers the owner's feedback on 1.3 and adds the owner's new branding
(Idlery Games at startup, the Ultimate Trifecta title). Code is on
`claude/ultimate-trifecta-testflight-oie9r7`; the build that was uploaded
is named in V5.7. Implementation notes and the issue register:
[docs/V5_NOTES.md](docs/V5_NOTES.md). Media index:
[docs/media/v5/README.md](docs/media/v5/README.md).

Evidence sources are labelled as in the table at the top of this report.
**No physical iPhone or iPad was available for V5 either**: nothing below
is a device measurement. V5 changes no rules, simulation or network
protocol (protocol 5, as V4); the rules copy and the party settings summary
are shorter.

## V5.1 Automated tests

On the final app code `0a41d70`: **205 tests, 3208 checks, 0 failures**, both
in CI (upload run #62's headless test job, Ubuntu 24.04, 157 s, which gates
the signed build) and on this machine (`tools/run_tests.sh`, 258 s:
`docs/test-data/v5_full_test_run.txt`). V4 had 159 tests and 2742 checks.

| Suite (new in V5) | Tests | What they exercise |
|---|---|---|
| `test_motion_layer` | 7 | **Reproduces the V4 press bug** (a release spring outliving the next press) with V4's exact code, then shows the V5 layer holds the pressed scale with at most one tween running; only the face scales, never the hit region; a button hidden while held resets, and one freed mid-animation is clean; a retarget cancels the old animation's callback; Reduced Motion keeps state feedback only; the focus ring and disabled state stay readable; tabular digits |
| `test_boot_branding` | 4 | The launch image, Godot's boot splash and the curtain's first frame agree (the Idlery Games lockup on the startup navy at the same place); the curtain waits for readiness, not a frame count (a hitch resets the steady count, a steadily slow device counts as steady), and frees itself; the brand marks import cleanly (lossless, mipmapped); no unwanted branding copy ("powered by") in the project |
| `test_map` | 3 | The baked map and the live markers share one transform; full-map labels never overlap each other or a marker; the map shows only the opponents the rules permit (host-sent last-seen cues) |
| `test_prep_jobs` | 2 | The nav grid built in slices equals the one-shot grid cell by cell; every preparation job is timed and named, and one over 25 ms marks the diagnostics timeline |
| `test_wardrobe` | 5 | Every item name fits two lines at the narrowest card with no shrinking or ellipsis (the eight names trimmed in the owner's screenshot by name); one finished picture lands on every card showing that look and a stale one on none (V4 left the equipped card on a placeholder); rapid category switching leaves no stale queued pictures; Apply / Undo say what they will do (Wearing this, Need N more coins, Buy & apply, Apply); the category strip fits a narrow panel with every word whole and every tab a full touch target |
| `test_lobby_flow` | 1 | Over the loopback network: eight rapid emotes all start and the newest owns the runner; a press storm leaves one animation on the button face; to the wardrobe and back keeps the same character nodes (no rebuild); a guest's outfit change lands on the guest only, in place; Start stops a Try-moves preview at once |
| `test_loading` | 8 | Rewritten for the game-rig loop: the bundled atlas matches its build data (26 frames at 60 fps, 4×7 grid, 920×540, premultiplied); the layout keeps the runners' feet clear of the status on phone, SE and iPad (never stretched); still first, background load, progress never ahead of preparation, closes when the round is live, releases its textures, hands an unfinished load to `App`; Reduced Motion shows the still; bounded preparation steps; ten rounds stay flat |
| `test_motion_v5` | 14 | Twelve motion scenarios against V4's measured snaps (start, stop, reversal, kerb, flicker, jump landing, tag miss, cart, correction…); a one-tick floor flicker never shows the air pose; landings and jumps fire once; hitches and teleports don't fling the nightcap; teleports cut and reset history; secondary motion bounded under irregular frames; gait cadence matches ground travel; starts and stops land on a step; LOD hysteresis keeps time; the menu idle API; the V5 clips are in the asset; the camera ignores posts but not walls; a run on the spot keeps its facing; **a new view's first frame faces the sim yaw** (found in integration, V5.8) |
| `test_results_layout` | 1 | The results actions (Play again, Scoreboard, Menu / Leave) sit outside the scrolling summary and on screen on phone, SE and iPad; on iPad the whole summary shows |
| `test_campus_art` | 8 | **Collision, nav and layout identical to V4**: 525 collision shapes (type, size, transform, layers, height field), both nav grids cell by cell, and the gameplay layout, against values computed on the V4 commit; the visual build adds no physics; the baked dressing is fresh and visual only; it keeps out of paths, roads, plazas, exits, jump points, pads, doors and gates; 40+ real bot routes and the swim lines into each water are clear; staged build steps are short; the art kit loads with its LODs; Battery Saver is lighter than Standard |

Existing suites still pass, with two deliberate updates from the motion
work: `test_motion` expects the filtered acceleration (and still guards the
old always-zero bug), and `test_profile` accepts the curly-hair variant
drawn under the crown and headphones.

## V5.2 Character motion, before and after (headless sim and desktop render)

The same measuring code ran on the V4 commit and on V5
(`docs/v5/motion_register.md`, `docs/media/v5/motion/data/`). Largest
single-frame upper-body snap (cm):

| Scenario | V4 | V5 |
|---|---|---|
| Start running | 35.1 | 5.3 |
| Stop | 25.2 | 3.5 |
| 180° reversal | 28.6 | 6.8 |
| Running-jump landing | 56.8 | 9.9 |
| Kerb drop | 51.3 | 6.8 |
| One-tick floor-contact flicker | 102.7 | 3.5 |
| Cart in / out | 35.1 | 5.3 |
| Prediction-correction stress run | 23.1 | 6.8 |

Also measured: 11 clips with arms 1.4–30 cm inside the head → none over
1 cm (`tools/character/clip_check.py` in Blender on the real rig); nightcap
tip 32–41 cm in one frame after a hitch, respawn or jump → ≤ 7.3 cm; camera
pulled ~3 m closer for one frame by a trunk or lamp post → 0.03 m;
planted-foot slide in a reversal 1.23 → 0.92 m/s (90° turns 0.69 → 0.78:
not fixed). The side-by-side reels (`runner_v4_v5.mp4`, `watch_v4_v5.mp4`)
run on a fixed 30 fps clock: they show poses, not frame rate.

## V5.3 Campus: budgets and gameplay safety (desktop render, headless)

Engine counters on llvmpipe at 1558×720 for the same cameras on V4 and V5
(`docs/v5/campus_notes.md`): Standard draw calls 43–94 on the seven route
views (V4 44–86) and 31–83 on the six water views (V4 32–88); visible
primitives 0.53–1.02× V4. Battery Saver is lighter than Standard
everywhere. Counters say nothing about GPU time on a phone.

Collision and navigation are proven identical to V4 by `test_campus_art`
(V5.1); `campus_layout.gd`, `nav_grid.gd`'s output and the collision code
are unchanged.

## V5.4 Preparation and frame work (desktop CPU; not device numbers)

| Measurement | V4 | V5 |
|---|---|---|
| Longest campus build step, rendering (llvmpipe) | 81–83 ms | 30–37 ms (first-use shader compiles, one step each); otherwise 13–14 ms |
| Campus steps over 16 ms, rendering | 18–22 of 126 | 3 |
| Longest frame of round preparation, headless | 62–77 ms | 16.4–21.4 ms |
| Longest non-campus job, headless | ~50 ms (nav grid) | 7.5–9.8 ms (nav grid in 7 slices, longest 9.2–10.2 ms) |
| Ten rounds in a row | flat | flat (nodes / objects / orphans 45 / 3140 / 190 after rounds 2 and 10; no session connections left) |

A job over 25 ms on a phone is named in the diagnostics timeline
(`prep_slow:<job>`). The shader compiles can't move off the main thread
here (it deadlocked the renderer); their phone cost is unknown.

## V5.5 Visual evidence (desktop render)

All renders are the real game on Mesa llvmpipe under Xvfb at device
resolutions (iPhone 14 Pro class 2532×1170 with its safe area, iPhone SE
1334×750, 4:3 iPad 2048×1536), made by `tools/capture_v5_media.sh`. They
show layout, type, art and framing; they are not frame-rate evidence.
Index: [docs/media/v5/README.md](docs/media/v5/README.md).

- **Startup:** Movie Maker frames of a normal boot (fixed 30 fps game clock):
  the Idlery Games lockup holds while the home screen and runner get ready,
  then dissolves into home with no flash and no second logo.
- **Home, party (1, 2, 4 and 8 players), wardrobe (every category), match
  loading, Settings, Practice, Play with Friends, How to play** on phone,
  and home, wardrobe, loading and results on SE and iPad.
- **Match:** role reveal, HUD, minimap, full map with labels and the side
  panel, a water entry, results.
- **Before/after:** V4 and V5 at the same moments (home, party, wardrobe,
  loading; campus route and waters from the campus work; motion reels).

## V5.6 Networking on V5

The protocol, simulation and rules are unchanged from V4 (protocol 5), so
the V4 network results (V4.5) still describe the wire. V5 adds a
presentation-level classification (`src/dev/net_motion_probe.tscn`, host
plus a predicting client over the shaped in-process link, 720 client frames
per condition):

| | 0 ms | 120 ms RTT, 3 % loss | 300 ms RTT, 10 % loss |
|---|---|---|---|
| Visible correction frames | 0 | 0 | 0 |
| Reconcile mean / over 25 cm | 0 mm / 0 | 4 mm / 0 | 3 mm / 0 |
| Terrain/collision deviation frames | 46 | 45 | 45 |
| Remote characters extrapolating (of ~5,000) | 0 | 25 | 310 |
| Host ticks without client input | 0 | 0 | 0 |

Terrain and camera counts don't change with the link, so they are not
network effects. A real-UDP soak between processes (`tools/net_soak.sh`,
host + 2 bot clients, full rounds) averaged 2.4–2.6 mm corrections
unshaped and 10.7–11.8 mm at 60 ± 10 ms one way with 3 % loss; the largest
was about 1 m in both conditions and was not traced (open, M14). `test_lobby_flow`
(V5.1) runs the new party screen over the loopback network.

## V5.7 iOS build (CI iOS) and TestFlight

**Signed and uploaded:** `com.idlery.ultimatetrifecta` **1.4 (4)**, from
`0a41d70` (the final V5 app code), went to App Store Connect at 16:18 UTC on
2 October 2026 (upload run #62,
https://github.com/BKimble1/ultimate-trifecta/actions/runs/37031634671).
Apple processed it to `VALID`; it is `INTERNAL_ONLY` and **available to
internal testers** (`IN_BETA_TESTING`) in the owner's existing internal
group, which receives every build. The lane set What to Test (1404
characters). No tester was added, no external testing was requested and
nothing was submitted for review. Details: `TESTFLIGHT_RELEASE.md`.

| Run | Commit | What happened |
|---|---|---|
| #56 | `5eaed77` | Mid-V5 push build: tests, export, the new launch and branding audit (PASS), unsigned device archive, Simulator cold launch (no crash, 0 script errors). |
| #58 | `49abda2` | Push build after the motion merge: all stages passed. |
| #62 | `0a41d70` | `upload=true`. Tests passed (205 tests, 3208 checks), export, launch audit PASS (one storyboard on the startup navy; both splash images 2048², opaque, navy corners, the Idlery teal mark; 0 "powered by" strings; the only text files naming Idlery carry the bundle ID), signed archive and upload of **1.4 (4)**, Simulator run, build facts, then Apple's processing: `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, What to Test set. Build facts: Xcode 26.6 (17F113), iOS SDK 26.5, arm64, 285 MB app, MinimumOSVersion 17.0, iPhone and iPad, landscape left/right, `ITSAppUsesNonExemptEncryption` false, the three frameworks embedded (UTShare arm64), Game Center entitlement, privacy manifest. |

**The Simulator run, read honestly.** The CI Simulator is an x86_64 runner
on the OpenGL ES fallback, not a phone's Metal path. Its first screenshot
took 223.5 s to return; the cold-launch frames (223–290 s) all show the
Idlery Games lockup on navy, which is the launch screen, the boot splash and
the curtain alike by design, so they cannot tell which stage was showing.
In the bot-driven run the screenshots show the V5 match loading screen
rendering on iOS (title, three runners, "Getting campus ready…", then
"Placing players…"), but the app ran at about 1 fps and the round was still
preparing when the 8-minute window closed (status lines: phase LOADING at
t = 5, 10 and 15 s of game time). V4's run #52 ran at about 5 fps and
reached its role reveal near the end of the same window. A desktop check on
Godot's OpenGL (Compatibility) renderer prepared the round and went
through reveal, countdown and play, so this is slowness on that Simulator
path, not a stall in the code. It does mean V5's loading is heavier on a
software GL path than V4's, and it is a device check (V5.9): the owner's V6
brief reports the loading loop animating and then freezing on a phone.

## V5.8 Found and fixed during V5 validation

- **Press feedback springing back mid-press** (U1): reproduced with V4's
  code in a test, fixed by the motion layer's single owner per property.
- **Equipped wardrobe card stuck on a placeholder** (U2), **pictures never
  arriving** (U3), **trimmed item names** (U4) and **trimmed party names**
  (U5): see V5_NOTES.
- **Startup curtain waiting for its 6 s cap** under slow rendering: the
  first steadiness rule was absolute; now relative to the previous frame.
- **Full map side panel at the top left for one frame:** laid out in
  `_ready` now.
- **iPad wardrobe:** the runner was too large and behind the item panel;
  the stage now frames the free region.
- **Emote name bubbles** clipped above the screen on home and results: only
  in the group lobby now.
- **Wardrobe teardown** could create the portrait renderer while the screen
  was closing (cancelling queued pictures): it no longer does.
- **iPhone SE wardrobe:** the category strip ran off the panel ("Emote:"),
  and a fitted tab then trimmed "Outfit" inside its own face. The strip
  fits its panel and a face pads its text by at most its button's padding
  (test added).
- **Results on a phone:** Menu / Leave party sat under Play again inside the
  scrolling summary, so it was only found by scrolling; on iPad a fixed
  scroll height cut the sheet off with room to spare. The actions are now
  one row outside the scroll and the summary fits its content
  (`test_results_layout`, captures on all three sizes).
- **Found while merging the motion work:** a character view's first frame
  away from the world origin counted the jump from the origin as travel and
  started up to 57° off its facing (M19; test added, 0.99 rad without the
  fix). The same merge would have put two of the three loading-loop
  runners in step (a start from standing snaps the gait to a step); the
  loop renderer now starts them moving, and the loop was re-rendered and
  re-checked (closes exactly).
- **Found while merging the campus work:** the new name boards preloaded
  the Fredoka font, which V5 no longer ships, which would have failed to
  load the campus script; they use Manrope Bold.
- **Tooling:** `tools/net_soak.sh` wrote no reports for an absolute output
  directory.

## V5.9 Not verified (exact remaining checks)

- Everything that needs a phone: frame interval, stalls, GPU time and heat
  after 15 minutes (Settings › Diagnostics (beta) › Share summary), the
  cost of the three first-use shader compiles, and whether any device
  sustains 60 fps. No claim is made that every A12 device does.
- The startup sequence as iOS draws it on a device: launch screen →
  Godot's boot splash → the curtain → home, with no white flash (the
  Simulator run and desktop frames are the closest evidence).
- Touch feel of the new press feedback, the 44 pt targets and the safe
  areas on real notched and home-button phones; a game controller on the
  new screens.
- The game-rig loading loop at the phone's scale and refresh rate.
- The campus at night on a phone screen (contrast, readability of the
  water landmarks and the name boards, Battery Saver).
- Remote players under heavy loss, and the rare ~1 m correction (M14);
  turn foot slide (M8); slopes and stairs (M18).
- A friend party and series over Game Center between devices.

# V4 (version 1.3)

V4 answers the owner's first iPhone playtest of 1.2. Code is on
`claude/ultimate-trifecta-testflight-oie9r7`; the final app code is named in
V4.6. Implementation notes and the issue register:
[docs/V4_NOTES.md](docs/V4_NOTES.md). Media index:
[docs/media/v4/README.md](docs/media/v4/README.md).

Evidence sources are labelled as in the table at the top of this report.
**No physical iPhone or iPad was available for V4 either**: nothing below is
a device measurement. V4 adds the opt-in diagnostics panel that measures
the device (V4_NOTES, "Five-minute diagnostics check").

## V4.1 Automated tests

On the final app code `6677eb2`: **159 tests, 2742 checks, 0 failures** in 162 s
(CI run #52's headless test job, Ubuntu 24.04, which gates the iOS build).
The same suite on this machine (`tools/run_tests.sh`, 214 s):
`docs/test-data/v4_full_test_run.txt`. That local run includes a later fix
to one of the new loading tests: under the runner's fixed frame clock, a
wait counted frames while the atlas loads in wall-clock time, and it failed
once locally. The waits are now wall-clock bounded; the app code is
unchanged. V3 had 117 tests and 1254 checks.

| Suite (new in V4) | Tests | What they exercise |
|---|---|---|
| `test_touch_layout` | 14 | Targets ≥ 44 pt and the same physical size on iPhone SE, 14 Pro, Pro Max and iPad; everything inside the safe area, standard and mirrored; hit padding never overlaps and never shrinks a target; mirrored hit testing matches the drawn controls; a custom anchor is used, and clamped on another device; an action cluster dropped on the stick is pushed clear; contextual buttons never shuffle the others; role transitions release holds but keep movement; repeated taps each count once, in order; a vanished gadget button releases its finger; the layout is not rebuilt every frame; saved layouts migrate and garbage is rejected; tiny views never hang; HUD regions (Pause, map) fall through the touch surface |
| `test_pursuit` | 4 | Real sim and physics with a human-like Night Watch (camera lag, presses at a "looks close" 2.6 m or on the cue): the 11-scenario report with targets (V4.2); cart interception; a sprint is still an escape burst; untaggable states and the cart-exit lockout |
| `test_series` | 9 | Every 1/2/3 Night Watch × 1/3/5 rounds combination and its per-round rules copy; role counts and human/bot constraints; round 1 an equal draw, later rounds rotate; the one-human policy; round recording, scores and shared places; the series view is sanitised; settings and series over the loopback network; **a full three-round friend series end to end over the loopback network** (Round x of 3, ready gating, fair Night Watch rotation 2/2/2, repeated results counted once, drop and rejoin keeps one standing, Play again starts a fresh series); reward eligibility (short drop keeps the reward, most-of-the-round away gets none, no double payment) |
| `test_emotes` | 2 | Every emote from the host and from a guest, picker → session → host event → the right character → visible animation → clean return; rapid reselection, repeats, the ready response, an outfit change, the picker sheet and the stage going away mid-emote |
| `test_loading` | 7 | A round is prepared in bounded steps under the loading screen (no step a long freeze); the campus is reused between rounds with clean per-round water state; ten rounds in a row leave scene nodes, objects, orphans and signal connections flat. **Loading animation:** the bundled loop matches its build data (frames, grid, fps, aspect, background colours; atlas and still at full size); the still shows at once, then the loop starts from that frame; preparation progress only moves forward and the bar never runs ahead of it; the screen closes as soon as the round is live; its textures are let go and no background load is left behind; a screen closed mid-load hands the load to `App` and the next screen picks it up; Reduced Motion shows only the still |
| `test_portraits` | 3 | A newer request from the same party cell replaces its queued one; the queue is bounded; headless gets a placeholder without work |
| `test_diag` | 2 | Frame-interval ring, histogram percentiles and stall attribution to markers; **the shared summary contains no names, room codes or Game Center IDs** |

Existing suites still pass unchanged: rules, sim, routes, net (protocol 5),
trust, controls, focus, lobby, animation, profile, account and native.

## V4.2 Night Watch pursuit, before and after (headless sim)

The same harness ran on the V3 values (a worktree of the V4 code with the
old rules and no assist) and on the final V4 values:
`docs/v4/pursuit_before.txt`, `docs/v4/pursuit_after.txt`.

| Scenario | V3 | V4 |
|---|---|---|
| Jogging runner from 4 m | 2.7 s, 2 presses | 1.3 s, 1 press |
| Jogging runner from 8 m | 6.1 s, 2 presses | 3.8 s, 1 press |
| Jogging runner from 12 m | 9.4 s, 2 presses | 6.3 s, 1 press |
| Pressing only when Tag lights up (8 m) | no cue: escaped | 3.8 s, 1 press |
| Runner cycling sprint (8 m) | 17.8 s | 10.8 s |
| Close rear tag, both running (2.2 m) | 0.3 s | 0.2 s |
| Weaving runner (6 m) | 3.5 s, 2 presses | 1.9 s, 1 press |
| 100 ms input delay ±33 ms (8 m) | 5.9 s, 2 presses | 5.0 s, 3 presses |
| 250 ms hitch at 2 s (8 m) | 6.1 s | 3.8 s |
| Cart from 21 m, hop out, tag | 14.1 s | 11.8 s |
| 2 s sprint burst (gap gained) | +1.6 m | +1.5 m |

These are measured scenario values, not playtests with people.

## V4.3 Loading and frame-time work (desktop CPU; not device numbers)

| Measurement | V3 code | V4 code |
|---|---|---|
| Round preparation | the whole campus, collision and characters built inside one frame in `MatchController._ready` (~650 ms), every round including rematches | first round 688 ms of work over 42 frames under the loading screen, longest frame of work 57 ms (headless test run); rematch / next round **17 ms** (campus kept) |
| Ground collision | 161 ms (Jolt mesh fallback for a 321×301 map) | 6 ms (square 321×321 height field) |
| Collision bodies | 45 ms | 4 ms |
| Visible primitives, Night Watch capture scenario (llvmpipe engine counters) | 179–253k | 238–307k |

The windowed llvmpipe runs took longer (for example 2.2–2.5 s of
preparation over 47 frames), because the software rasteriser also uploads
and draws. Neither figure is a phone measurement.

## V4.4 Visual evidence (desktop render)

All of it was rendered by the Mobile renderer on llvmpipe under Xvfb and is
labelled in [docs/media/v4/README.md](docs/media/v4/README.md):
- **Campus:** seven matched route cameras and all six waters on the V3 art
  and the V4 art, plus side-by-side comparisons.
- **Characters:** 12 matched close-ups of the refined parts, the hero
  framing, skin tones under campus light, the outfits and a group.
- **Screens:** V3 (`e39c98c`) and V4 (`6677eb2`) stills from the same
  capture scenarios and seeds: home, wardrobe, the creator, the touch HUD
  as runner and Night Watch, a cart, the role reveals, a splash and
  recovery, home safe, round results and the 8-player lobby. V4 alone: the
  layout editor, the full maps, Night Watch results, the capture moment
  ("Caught by …", then "Protected") and a friend series' final results.
- **Clips:** normal-speed Movie Maker clips (fixed 30 fps game clock) on
  `6677eb2`: runner practice with a splash, Night Watch practice with the
  cart, an on-foot chase and a lunge, lobby emotes and Try moves, and the
  change from round 1 to round 2 of a series. None is frame-interpolated or
  sped up.
- **Match loading animation** (`media/v4/loading/`): the screen at iPhone
  (1561×720), iPhone SE (1334×750) and iPad (1024×768) aspects at two loop
  times; the previous droplet screen for comparison; the bundled loop frames
  played six times at 24 fps; and a Movie Maker clip of Practice from the
  title through loading into the round. The loop frames come from the
  owner's clip. The two restart frames are optical-flow morphs of the
  clip's own next frames (see V4_NOTES); no frames were added to make
  playback look smoother.

## V4.5 Networking on V4 (protocol 5)

- **Loopback net:** `test_series` runs settings, START snapshots, SERIES
  standings, ready gating, a drop and rejoin between rounds and Play again
  across three rounds; `test_net` and `test_trust` pass unchanged on
  protocol 5.
- **Desktop UDP soak** (`tools/net_soak.sh 7 60 10 0.03 3`, protocol 5,
  `6677eb2` app code). Eight separate Godot processes on this machine (one
  host and seven clients) play **three rounds in a row** over real UDP
  (ENet). Each process adds 60 ms one-way latency, 10 ms jitter and 3% loss
  to its own outbound traffic, for about 150 ms of round-trip time. Reports:
  `docs/test-data/v4_net_soak_7c_60ms_0.03/`.

  | Round | Outcome (all 8 agree) | Clients' RTT est. | Snapshots per client | Corrections avg / max (per client) | Host packets sent / shaper drops |
  |---|---|---|---|---|---|
  | 1 | Night Watch win, 0/4 home | 154–162 ms | 4799–4839 | 1.2–3.7 mm / 0.19–1.43 m | 42362 / 1149 |
  | 2 | Night Watch win, 1/4 home | 152–163 ms | 4813–4841 | 0.6–2.2 mm / 0.08–0.96 m | 42605 / 1101 |
  | 3 | Night Watch win, 0/4 home | 150–162 ms | 4814–4829 | 1.2–6.6 mm / 0.30–1.59 m | 42253 / 1142 |

  - **All eight processes** played the three 4:00 rounds together at 60 fps,
    returning to the room between rounds, with the same outcome each round.
  - **Logs:** no script errors and no transport errors in any of the
    eight. The only errors are the engine's exit-time notices; they now
    include the campus kept for the next round, which is still held when
    the process quits.
  - **Host input buffers** (totals over the three rounds and seven
    clients): it ran short of a client's input on 191 of about
    302,000 client-ticks (it repeats the last input), and merged inputs 228 times,
    keeping button presses. The one-round V3 soak had 0 and 46.
  - **Conditions:** this soak shared the machine's four cores with a
    low-priority desktop video recording (the series transition clip).
    Starved and merged ticks depend on how the processes share the CPU, so
    the counts are not comparable run to run.
  - **Large corrections:** the maximum is each client's single largest
    correction in a round; the averages stay in millimetres.

  What this does **not** show: Game Center's transport (GKMatch), real
  devices, mobile radios or internet paths.

## V4.6 iOS build (CI iOS) and TestFlight

**Signed and uploaded:** `com.idlery.ultimatetrifecta` **1.3 (3)**, from
`6677eb2` (the final app code, with the loading animation), went to App
Store Connect at 08:44 UTC on 2 October 2026. Apple processed it to `VALID`,
and it is **available to internal testers** (`IN_BETA_TESTING`) in the
owner's existing internal group, which receives every build. The lane set
its What to Test text (1455 characters). It was uploaded as internal-only;
there is no external testing and no App Store submission. Details:
`TESTFLIGHT_RELEASE.md`, "Current release state".

| Run | Commit | What happened |
|---|---|---|
| #50 | `4e828da` | Tests passed, then signed archive and upload of **1.3 (2)**: `VALID`, internal group, What to Test set. It predates the loading animation; 1.3 (3) replaces it for testing. Simulator: cold launch, no crash report, 0 script errors. |
| #51 | `6677eb2` | The push build; cancelled in favour of #52, which runs the same steps and also signs and uploads. |
| #52 | `6677eb2` | Tests passed (159 tests, 2742 checks), then signed archive and upload of **1.3 (3)**: `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, What to Test set. Build facts: Xcode 26.6, iOS SDK 26.5, arm64, the three frameworks embedded, Game Center entitlement, privacy manifest. Launch audit: no launch file other than the storyboard; the only text files naming Idlery are build plists carrying the bundle ID; 0 "powered by" strings in the game data. Simulator: cold launch still running, no crash report, 0 script errors, 23 screenshots. |

The Simulator in run #52 answered slowly. The first launch screenshot came
back 152.8 s after the launch command, against 6.9 s in run #50, and each
later screenshot command took 1–63 s. These times include the `simctl`
commands on a shared x86_64 runner, so they say nothing about launch time
on a phone. Launch time is one of the device checks in V4.8.

## V4.7 Found and fixed during V4 validation

- **HUD Pause (and map) could not be tapped:** the full-screen touch surface
  on the layer above swallowed those taps. Found by a real-window check
  (`src/dev/input_fallthrough_check.tscn`): the V3 surface blocked the tap,
  V4 passes it.
- **Emotes cut short:** a stale emote timer could cancel a newer emote.
- **Grey portraits:** a new rig's first render (and parts just shown)
  missed their per-instance tints; fixed with an unseen warm-up render.
- **Orphan leak:** a dead HUD node leaked one orphan per round.
- **Touch layout recursion:** the fallback could recurse on tiny views.
- **Nightcap:** the scalp showed beside the fold in close-ups, because the
  spring chain sagged the cap into the head and the fold crosses itself.
  The polyline path also creased the cap.
- **Robe sleeves:** read as a flat disc inside a thin hoop.
- **Night skin readability:** dark skin tones lost facial detail under
  campus night light.
- **Loading loop ghosting:** the first loop build gave each runner a fixed
  screen column. An arm reaching into a neighbour's column was warped with
  the neighbour and showed twice. The columns are now joined on a
  per-frame seam through the background.
- **Loading fade:** the runner picture's shader replaced the colour it was
  given, so it ignored the screen's fade. On a desktop clip it stayed fully
  opaque over the round for 0.25 s, then vanished. It now multiplies by the
  incoming colour and fades with the screen.

## V4.8 Not verified (exact remaining checks)

- Frame interval, stalls, GPU time and thermals on an iPhone: use
  **Settings › Diagnostics (beta)** and Share summary (V4_NOTES).
- Touch comfort and the layout editor on a real phone, in both landscape
  orientations.
- The Night Watch tuning with people, as opposed to the pursuit harness.
- A friend series over Game Center between two devices.
- The launch screen as iOS draws it on a device, and how long a cold launch
  takes to reach the title (the Simulator run on CI is the closest evidence,
  and its timings are not device timings).
- The match loading animation on an iPhone: smooth 24 fps playback,
  sharpness at the phone's scale, nothing cropped, no jump at the loop
  point, and the fade into the round (checked here on desktop renders and
  a Movie Maker clip only).

# V3 (version 1.2)

Code on `claude/ultimate-trifecta-testflight-oie9r7`, final app code
`001f274` (later commits change only documentation, media and the release lane). Implementation notes: [docs/V3_NOTES.md](docs/V3_NOTES.md).
Media index: [docs/media/v3/README.md](docs/media/v3/README.md).

Evidence sources are labelled as in the table at the top of this report.
V3 adds two more:

| Label | What it is | What it can prove |
|---|---|---|
| **Service (node)** | The service's whole HTTP API (`service/src`) running under Node 22's built-in test runner. It uses an in-memory D1 shim on `node:sqlite` and a per-run self-signed certificate standing in for Apple's key. | Sign-in verification logic, tokens, names, moderation, deletion, room lifecycle and admission. It does **not** prove a Cloudflare deployment or Apple's real certificate chain. |
| **Native (Linux)** | The UTShare GDExtension built from source with gcc and loaded by the pinned engine | Class registration, method binding, argument marshalling and the clipboard fallback. It does **not** prove the iOS share sheet. |

**Not done: no physical iPhone, iPad or game controller was available, and
the service is not deployed.** See V3.8.

## V3.1 Automated tests

`tools/run_tests.sh` on the final code: **117 tests, 1254 checks, 0 failures** in 207 s
(`docs/test-data/v3_full_test_run.txt`). V2 had 76 tests and 914 checks.

The runner now also **fails a test when any script error is raised during
it**: freed-instance access, bad calls and the like. Before, these were
printed and ignored. Turning that on found nothing else in the suite; two
real instances had already been found and fixed during V3 (V3.7).

| Suite | Tests | What they exercise |
|---|---|---|
| `test_animation` | 7 | Gait cadence matches the asset's measured stride; footsteps follow the gait phase; distant (throttled) characters keep real time; visual yaw never turns the long way; landing sounds survive floor-contact flicker; the splash sequence plays from authoritative time, including late joins; the impact class comes from the sim |
| `test_profile` | 8 | V1 and V2 saves migrate (progress, owned items, the same look in schema 2); generated and migrated default names always fit the 3–16-character rule; every appearance maps onto the character's parts with the hair/hat rules; the versioned wire format round-trips every value and rejects junk; catalog IDs are explicit, unique and pinned; Apply is atomic and idempotent |
| `test_trust` | 6 | The bound host can't be replaced and nobody else can send host messages; the expected host identity is enforced; admission tokens are verified, bound to the sender and single use; junk and floods are contained (flooders removed); the round waits for load acks (15 s cap); names from the network are sanitised |
| `test_controls` | 9 | Rapid jump-then-dive is two presses on keyboard, controller and touch; mixed sources keep arrival order; the queue is bounded and stale presses expire; text fields and pause don't leak presses; drift can't fight touch or flip prompts, and a button switches device at once; stick curves (radial dead zones, expo, boost); controller-family prompts; disconnect and backgrounding clear presses; HUD splash-feed coalescing survives freed lines |
| `test_focus` | 3 | Home, Play with Friends, Practice, Settings, How to play and Create Your Runner each open focused, and every visible button is reachable with the d-pad (Settings: 22 buttons; creator: 19); the code field never traps a controller (code pad); dialogs trap focus, Back closes them, and focus returns to the opener |
| `test_account` | 7 | First launch: Create Your Runner, then the name; Delete Game Profile signs in again, deletes online first and wipes the device only after success; a failure keeps everything; with no service it deletes on the device only; the Profile section has Change name and Delete; the session is reused and renewed once when it expires; report and block requests match the service contract (paths, bounded details, every lobby reason accepted) |
| `test_lobby` | 3 | Incremental stage updates through drop and rejoin; **1, 2, 4 and 8 players at 2532×1170, 1334×750 and 2048×1536, with tall hats: distinct marks, every body (both shoulders) in frame, no face behind a nearer head or hat**; slot-cell contents stay inside the cell |
| `test_native` | 1 | The UTShare extension registers an abstract class with static `share(text, url)` and `available()` with the right flags and types; UTF-8 crosses the boundary; desktop reports no sheet and Share falls back to the clipboard |
| `test_net` (updated) | 14 | As in V2. The reconnect test now also checks that an impostor without the slot's rejoin key is refused (`in_use`). New: over real UDP on localhost, packets for a peer that has left are dropped without engine errors (fails on the old transport) |

**Service (node)** (`cd service && npm test`, `docs/test-data/v3_service_tests.txt`):
**21 tests, 0 failures**.

- **Sign-in:** a verified signature creates an opaque profile; a claimed ID
  without Apple's signature gets nothing; tokens are bound to environment,
  bundle, audience and expiry; sign-out revokes; per-address rate limit.
- **Names:** character rules; slurs, sexual content, profanity, threats,
  impersonation and contact info are rejected, including disguised
  spellings; **false positives**: ordinary names containing blocked letters
  pass; suggestions; discriminators; cooldown; reserved names and forced
  renames.
- **Safety:**
  - Reports reach the queue with a receipt.
  - Admin actions (forced rename, suspension) work and are audited.
  - Blocks persist.
  - Deletion needs confirmation and a fresh sign-in and removes personal
    data.
- **Rooms:**
  - Codes are 6 unambiguous characters, with strict normalisation.
  - Create and join with admission and version sync.
  - Distinct errors.
  - Only the host updates the room, following the lifecycle.
  - A reconnect keeps its own slot.
  - Blocked or removed players can't get in.
  - One live party per host; unconnected reservations lapse.

## V3.2 Visual evidence (desktop render)

Everything is listed in [docs/media/v3/README.md](docs/media/v3/README.md),
with the build each file came from. All of it is **desktop render**; none
is device footage.

- **Party lobby**:
  - 1, 2, 4 and 8 players at 2532×1170;
  - eight players at iPhone SE 1334×750 and iPad 2048×1536;
  - all with random looks including tall hats.
  Every face and body is in frame. These captures found three layout bugs
  (V3.7), now covered by `test_lobby`.
- **Screens**: Home, Create Your Runner (also as the first launch, with no
  Back), the name sheet, Settings › Profile, the Delete Game Profile
  confirmation, Play with Friends, Practice, How to play and Results.
- **Character art sheets**: faces, views, looks, hair, poses, gait
  transitions and the cart drivers.
- **Gameplay stills**:
  - the Quarry splash sequence;
  - a Night Watch tag;
  - the cart;
  - the canopy before and after on identical frames;
  - controller hints with PlayStation glyphs (simulated pad).
- **Normal-speed clips** (30 fps Movie Maker, labelled in the frame):
  - a full runner round (75 s) and a Night Watch round (80 s) on
    `cf53155`;
  - the canopy before/after side by side;
  - the lobby filling up;
  - the creator.
- **iOS Simulator** (CI, V3.5): a cold launch through the boot splash and
  the loading screen to a practice match's role reveal, driven by the
  CI's automation flags.

## V3.3 Worst-scene budget (engine counters)

Engine counters from the in-game diagnostics. Draw calls and primitives
don't depend on the GPU, so they are comparable across runs. They are
**not** frame times. Preset Standard.

| Scene | Size | V2 draw calls / primitives | V3 draw calls / primitives |
|---|---|---|---|
| Home | 2532×1170 | 34 / 40.6k | 78 / 46.3k |
| Lobby, 1 player | 2532×1170 | 82 / 44.6k | 91 / 46.0k |
| Lobby, 4 players | 2532×1170 | — | 131 / 172.7k |
| **Lobby, 8 players** | 2532×1170 | 166 / 272.6k | **194 / 349.9k** |
| Lobby, 8 players (iPhone SE) | 1334×750 | — | 190 / 233.9k |
| Lobby, 8 players (iPad) | 2048×1536 | — | 179 / 249.4k |
| Results | 2532×1170 | 27 / 40.9k | 27 / 45.8k |
| **Gameplay, role reveal** (8 characters by the dorm) | 1600×740 | — | **233 / 351.1k** |
| Gameplay, running | 1600×740 | 158 / 246.7k (`runner_outdoors`) | 196 / 312.7k |
| Water entry / mid-splash / recovery (seed 11) | 1280×720 | — | 124–128 / 161–232k |

**Budget used for V3: at most 250 draw calls and 400k primitives in any
frame at Standard.** The worst scenes are the gameplay role reveal
(233 / 351k) and the full lobby (194 / 350k), so both are inside it. The
increase over V2 comes from the new head, hair shells and face detail. Going
from 1 to 8 players adds about 43k primitives per character in that frame,
counting every pass that draws it (depth, shadow and colour). Distant
characters use the imported LODs.

These counters say nothing about GPU time. Whether 350k primitives with
2× MSAA fits an iPhone XS (A12, the minimum) at 60 fps, or needs Battery
Saver there, can only be measured on the device (V3.8).


## V3.4 Networking on V3 (protocol 4)

Protocol version 4 adds:
- host binding and host-only messages;
- admission tokens and rejoin keys;
- load acknowledgements before the countdown;
- per-peer rate limits that remove flooders;
- bounds checks on incoming messages.
`test_trust` covers these. The V2 network tests pass unchanged on top.

**Loopback net** (the final test run; host and clients in one process over
the in-memory transport):

| Run | RTT / jitter / loss | Corrections avg / max | Over 25 cm | Missing reliable events |
|---|---|---|---|---|
| `rtt100` | 100 ms / 8 ms / 0 | 4 mm / 0.228 m | 0 | 0 |
| `rtt150_loss5` | 150 ms / 15 ms / 5% | 2 mm / 0.098 m | 0 | 0 |
| `rtt300_loss10` | 300 ms / 30 ms / 10% | 2 mm / 0.098 m | 0 | 0 |
| 8 players, 7 clients | 120 ms / 3% | worst client average 3 mm | not reported | not reported |

A client Night Watch's tag still lands at 150 ms, with 9 ticks of lag
compensation.

**Desktop UDP soak** (`tools/net_soak.sh 7 60 10 0.03`). Eight separate
Godot processes on this machine (one host and seven clients) play one full
round over real UDP (ENet). Each process adds 60 ms one-way latency, 10 ms
jitter and 3% loss to its own outbound traffic, for about 150 ms of
round-trip time. Final code, `docs/test-data/v3_net_soak_7c_60ms_0.03/`:

| Process | Outcome | RTT est. | Snapshots | Corrections avg / max | Packets sent | Shaper drops |
|---|---|---|---|---|---|---|
| client1 | Night Watch win, 0/4 home | 154 ms | 4837 | 0.9 mm / 0.71 m | 15422 | 461 |
| client2 | same | 153 ms | 4829 | 1.5 mm / 1.11 m | 15440 | 470 |
| client3 | same | 162 ms | 4833 | 1.9 mm / 0.65 m | 15437 | 430 |
| client4 | same | 151 ms | 4798 | 1.4 mm / 0.91 m | 15429 | 459 |
| client5 | same | 157 ms | 4842 | 2.4 mm / 1.31 m | 15439 | 471 |
| client6 | same | 156 ms | 4810 | 1.5 mm / 0.32 m | 15429 | 481 |
| client7 | same | 153 ms | 4822 | 1.2 mm / 0.91 m | 15420 | 470 |
| host | same | — | — | host (no prediction) | 42060 | 1095 |

- **All eight processes** finished the 4:00 round together, with the same
  outcome, at 60 fps.
- **Logs:** no script errors and no transport errors in any of the eight;
  only the engine's exit-time leak notices.
- **Host input buffers:**
  - The host never ran short of a client's input (0 starved ticks).
  - It merged inputs 46 times across all clients, keeping button presses,
    to stay near real time.
- **Comparison with earlier soaks:**
  - The V2 soak under the same conditions: corrections 0.9–2.0 mm average,
    1.56 m worst; 11 merged inputs.
  - The first V3 soak, before the splash-feed fix: 105 merged inputs and
    13 script errors from the feed.
  - Merging depends on how eight processes share four CPU cores, so the
    count varies from run to run.
- **Large corrections:** the maximum (0.3–1.3 m) is each client's single
  largest correction in the round. The averages stay in millimetres.
  Individual large corrections were not traced to a cause.

What this does **not** show: Game Center's transport (GKMatch), real
devices, mobile radios or internet paths. The UDP soak shares one CPU
between eight processes. The service's room API (create, join, admission,
heartbeats) is covered by the service tests only; it is not deployed.

## V3.5 iOS build (CI iOS) and TestFlight

**Signed and uploaded:** `com.idlery.ultimatetrifecta` **1.2 (1)** went to
App Store Connect at 03:39 UTC on 2 October 2026. Apple processed it to
`VALID`, and it is **available to internal testers** (`IN_BETA_TESTING`). It
is in the owner's existing internal group, which receives every build. It
was uploaded as internal-only; there is no external testing and no App
Store submission. Details and evidence: `TESTFLIGHT_RELEASE.md`, "Current
release state".

| Run | Commit | What happened |
|---|---|---|
| #26, #28 | `cff7edb`, `d2fd2f3` | Unsigned device archive with the UTShare framework embedded (arm64). Run #28's Simulator log: a cold launch with no crash report; the contact sheet shows the boot splash, loading and the role reveal. |
| #29, #30 | `cf53155`, `7a5325b` | Passed, including the unsigned device archive. |
| #31 | `7a5325b`, upload | Tests and export passed, and the Simulator steps ran. The **signed archive failed**: Godot's "Apple Distribution" identity conflicts with automatic signing. Nothing was uploaded. |
| **#32** | `e39c98c`, upload | Tests passed. Signed archive, export and upload in 2 min 19 s. The Simulator ran meanwhile. Apple reported `VALID` and `IN_BETA_TESTING`. |
| #34, #35 | read only | App Store Connect state: 1.2 (1), `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`. |
| #36 | `26cb5fe` | An ordinary push build on the final lane. The unsigned device archive still builds with the development identity stamped in; it was numbered 2 and not uploaded. Simulator: the app was still running 45 s after a cold launch, with no crash report then or after the bot-driven round, and 17 screenshots were taken. The app's status lines did not reach the Simulator's unified log, so the log neither confirms the match's progress nor rules out script errors. |

The signed archive in run #32:
- **Binary:** arm64, 270 MB `.app`.
- **Toolchain:** Xcode 26.6 (17F113), iOS SDK 26.5, MinimumOSVersion 17.0.
- **Devices:** iPhone and iPad, landscape.
- **Plist:** `ITSAppUsesNonExemptEncryption` false.
- **Frameworks:** Game Center bindings and UTShare, embedded, arm64.
- **Entitlements and privacy:** the Game Center entitlement; the privacy manifest with no tracking and no collected data.

The game, service and native code of `e39c98c` are identical to
`001f274`, the code the tests, soak and captures ran on.

A Simulator run proves only that the app launches and plays under x86_64
emulation. It says nothing about device performance.

## V3.6 Functional checks from the brief

Checked against the brief, with the evidence used for each:

| Requirement | Result | Evidence |
|---|---|---|
| Rules unchanged (6 vs 2, 3 of 6 waters, 4:00, 4 home, stamps kept, 6 s capture) | ✅ | `test_rules`, `test_sim` and the route and chase suites pass unchanged. Animation never feeds the sim; the impact class goes sim → view only. |
| Real cadence, phase-continuous blends, footsteps from phase | ✅ | `test_animation`; `art/lineup_transitions.png` |
| Splash sequence from authoritative time; impact class in the event; one sound; pooled FX; concurrent ripples; Reduced Motion | ✅ | `test_animation` (late join, resync, impact class); movie `runner_v3_desktop.mp4` |
| Faces visible at 1/2/4/8; steady camera; one primary action | ✅ | `test_lobby` at three aspects; `lobby/*.png` |
| Create Party / Join Code; Copy / Share / Invite; native share sheet | ✅ code; ⚠ share sheet on device unverified | `screens/online.png`, `lobby/*`; UTShare built, linked and embedded (CI #26; the signed TestFlight build #32); `test_native` |
| Portraits, host badge, player sheet (Hide/Report/Block/Remove), bot fill once | ✅ | `lobby/*.png`; `test_account` (report/block contract) |
| Real static weights, wordmark, button depth/spring, 150–250 ms transitions | ✅ | measured ink (V3 notes); `screens/home.png` |
| Create Your Runner; versioned appearance schema | ✅ | `test_profile`; `screens/creator.png`, movie `creator_v3_desktop.mp4` |
| Verified Game Center sign-in; bound tokens; rename; sign-out; deletion | ✅ logic; ⚠ live Apple signature unverified | service tests 1–3, 8; `test_account` |
| Name moderation incl. false positives | ✅ | service tests 9–14 |
| Reports, blocks, owner queue, forced rename, suspension, audit | ✅ logic; ⚠ not deployed | service tests 5–7; `service/tools/admin.mjs` |
| Rooms: atomic create, strict codes, states, heartbeat/expiry, atomic slots, admission, distinct errors | ✅ logic; ⚠ not deployed | service tests 15–21 |
| No orphan matches (host/joiner attributes); party switch; host loss; rematch | ✅ design + loopback; ⚠ live Game Center unverified | `test_net` (host loss, rematch, reconnect); the attribute rule is documented in `service/README.md` |
| Protocol hardening: host binding, host-only messages, bounds, no slot theft, rate limits, version 4 | ✅ | `test_trust`, `test_net` |
| Load acks, then one countdown | ✅ | `test_trust::test_round_waits_for_load_acks` |
| Controller: ordered edges, glyph families, focus navigation, code entry, arbitration, curves | ✅ desktop; ⚠ physical controllers unverified | `test_controls`, `test_focus`; `gameplay/controller_hints_playstation_simulated.png` (simulated) |
| Delete Game Profile; privacy re-audit; store text; age rating; real URLs only | ✅ prepared | `docs/APP_STORE.md`; links appear only when the owner configures them |
| Signed archive, upload to the existing internal TestFlight destination, Apple's processing and availability verified | ✅ 1.2 (1) `VALID`, `IN_BETA_TESTING`; ⚠ not installed on a device yet | V3.5; `TESTFLIGHT_RELEASE.md` |


## V3.7 Found and fixed during V3 validation

Found by the new tests, the captures and the soak, then fixed:
- **Every service call signed in twice.** A successful sign-in ended in the
  error state, because the state was computed from itself. Found by
  `test_account`.
- **Controller jump-then-dive merged into one press.** The bit
  accumulator; now one ordered queue for all devices (`test_controls` fails
  on the old code).
- **Script errors in two new UI paths:**
  - The splash feed could put a freed line into a typed variable. Found by
    the 8-process soak: 13 errors.
  - Modal focus restore read a freed opener.
  The test runner now fails any test that raises a script error.
- **Lobby layout.** All found in the 2532×1170 captures, each with a test
  that fails on the old code:
  - Slot badges drew outside their cells.
  - A back-row face sat behind a crown, then an eye behind a nightcap.
  - A wing player was clipped at the screen edge.
  The old framing test had effectively run at the headless window size; it
  now renders in SubViewports at phone, SE and iPad sizes.
- **Content-sized buttons were empty pills** (creator tabs, name
  suggestions). Ellipsis trimming made their minimum width ignore the
  text.
- **Settings and Play with Friends opened scrolled to the bottom.** Wrapped
  labels had no width yet when the initial focus scrolled. The old focus
  test missed it because the headless window is a 1280×1280 square, where
  nothing scrolls; `test_focus` now resizes to phone size and checks the
  scroll position.
- **The code pad's Delete key read "De…".** Its width now comes from the
  text.
- **Default names over 16 characters.** V2 could generate names like
  "Splashy Walrus 56" (17 characters), which V3's name rule displayed as
  "Player". Names are now generated to fit, and saved ones are migrated
  (`test_profile`).
- **The iPad lobby saw past the room.** At 4:3 the camera saw beyond the
  back wall's edge; the dorm is now built larger than any framing.
- **The desktop ENet transport raised engine errors when several clients
  dropped at once.** It sent to peers that had left, or to zombie peers
  still waiting for their disconnect. Seen in the iPad lobby capture's log.
  This is the desktop/LAN development path only; iOS uses Game Center.
  Packets for those peers are now dropped (`test_net`).
- **The canopy "porthole".** In a large tree, the follow camera saw the
  inside of a green bubble with only a circle around the character open:
  up to 90% of the frame. Foliage within 3.2 m of the camera is now cut
  away. On the same seeded round, the average coverage fell from 26.9% to
  4.6% of the frame, and no sampled frame is more than 25% covered (16 of
  45 were before). Stills: `gameplay/canopy_*`.
- **CI.**
  - Once signing secrets were added, the signing step failed because
    Homebrew Python refuses system-wide `pip` (PEP 668); it now uses a
    venv.
  - The UTShare framework needed CoreGraphics.
  - Its Info.plist now carries the toolchain keys an Xcode-built framework
    has.
- **Scoreboard order.** Runners now list in the order they got home.


## V3.8 Not verified (exact remaining checks)

Nothing below can be established here. Each needs hardware, an account or a deployment.
- [ ] **Device play** on an iPhone (and iPad) from TestFlight:
  - frame rate and pacing with Instruments, thermals and memory;
  - the lobby's 350k-primitive worst case and the gameplay reveal (V3.3);
  - touch on glass;
  - safe areas.
- [ ] **The native share sheet** on device: it opens, the iPad popover is
  anchored, the message and code arrive in Messages.
- [ ] **Physical controllers** on iOS (Xbox, DualSense, MFi, Switch Pro):
  - family detection from the names iOS reports;
  - prompts;
  - connect and disconnect mid-match;
  - the code pad;
  - jump-then-dive.
- [ ] **Game Center on two or more devices:**
  - parties by code and invite;
  - host and joiner attributes forming only host-containing matches;
  - a full round, rematch and host loss.
- [ ] **The service deployed** on the owner's Cloudflare account, then:
  - sign-in with a real Game Center signature (Apple's real certificate);
  - names, reports, blocks and deletion against it;
  - rooms and admission across devices;
  - moderation with `admin.mjs`.
- [ ] **TestFlight install** of 1.2 (1) on the owner's iPhone. It is
  uploaded, processed and available to the internal group (V3.5), but
  nobody has been observed installing it.

# V2 (version 1.1)

Code commits `e628130` … `5505024`, then the owner's app icon (`b56a82a`; the final app code) and documentation-only commits on `claude/ultimate-trifecta-testflight-oie9r7`. Implementation notes: [docs/V2_NOTES.md](docs/V2_NOTES.md). Media index: [docs/media/v2/README.md](docs/media/v2/README.md).

## V2.1 Automated tests

`tools/run_tests.sh` on the final code (`5505024`): **76 tests, 914 checks, 0 failures** (`docs/test-data/full_test_run.txt`). V1 had 53 tests and 802 checks. CI runs the same suite on every push. All V1 suites still pass unchanged: the rules, simulation, camping, chase-balance, route and network tests did not need edits, which is the regression check that movement speeds, timers, tag reach, routes and win conditions were not changed.

New V2 suites (behaviour, not style constants):

| Suite | Tests | What they exercise |
|---|---|---|
| `test_touch_input` | 13 | Walk + camera drag + jump with three fingers at once; a second finger in the stick zone never moves the player (it becomes a camera drag); a finger that slides off its button keeps it; jump then dive within one tick become two queued presses; leaving the cart while holding Gas releases it; pause while moving cancels everything and stale drags are ignored; a fresh touch after an interruption works; radial dead zone with sneak magnitude kept and no diagonal boost; sprint hysteresis (on 0.88, off 0.76); dynamic stick spawn clamped on screen, fixed-stick option; reserved HUD regions (pause, minimap) never start a stick or camera; camera drag is a displacement in unscaled pixels converted to points, never multiplied by frame time; a controller taking over, or focus loss, releases stick, gas and sprint, and touch works again afterwards |
| `test_motion` | 6 | Render state is interpolated between the last two sim ticks (position and yaw); a respawn after capture is not interpolated (no slide across the map); splash resurfacing, cart entry/exit and a large reconnect jump snap and reset history; camera damping reaches the same value after 1 s at 30 and at 120 fps; the head spring stays finite, bounded by its maximum lag and settles on target for steps from 1/120 s up to a 0.5 s hitch; character acceleration uses the previous frame's velocity (the V1 `prev_vel` bug) |
| `test_lobby` | 2 | Real lobby traffic over the loopback rig: the dorm stage is updated by player identity through a guest dropping and rejoining (everyone else keeps the same character instance and mark); an outfit change is applied in place; eight players get eight distinct marks, are all inside the camera frustum, and no face is covered on screen by a nearer character's head or cap |
| `test_profile` | 2 | A V1-era profile keeps uid, coins, level, stats, paid match IDs, wardrobe, equipped outfit and old settings, and new settings get defaults; all 108 outfit × hat × shoe combinations map onto parts of the new character, show the right parts (hoods hide hats, the Night Watch always wears the uniform) and round-trip the 5-byte network encoding |

## V2.2 Render path, measured (G1)

`game/src/dev/diag.gd` (`--diag`, `--diag-report=path`; excluded from iOS exports) records what reaches the screen. Every capture PNG has the snapshot next to it as JSON. Desktop render, llvmpipe; window at phone resolution 2532×1170 (canvas 1558×720, 1.625 px per canvas unit) or 1600×740 for gameplay.

| View | Build | 3D rendered at | SubViewport render → displayed | MSAA | Draw calls | Primitives |
|---|---|---|---|---|---|---|
| Home | V1 `654b0a8` | 2532×1170 (root) | none | 2× | 179 | 140 103 |
| Home | V2 `14475d3` | 2532×1170 (root) | none | 2× | 34 | 40 569 |
| Wardrobe / character preview | V1 | **400×470 shown at 650×764 (0.615×: a 1.63× upscale)** | stretched `SubViewportContainer` | 2× in root, **off in the preview** | 182 | 153 539 |
| Wardrobe | V2 `14475d3` | 2532×1170 (root, the character is in the dorm stage) | none | 2× | 48 | 42 326 |
| Lobby, 1 player | V1 | **990×436 shown at 1609×708 (1.63× upscale)** | stretched `SubViewportContainer` | off in the preview | 54 | 12 712 |
| Lobby, 1 player | V2 `4c89ed0` | 2532×1170 (root) | none | 2× | 82 | 44 566 |
| Lobby, 8 players | V1 | 990×436 shown at 1609×708 | stretched `SubViewportContainer` | off in the preview | 291 | 87 982 |
| Lobby, 8 players | V2 `4c89ed0` | 2532×1170 (root) | none | 2× | 166 | 272 632 |
| Runner outdoors (play shot 2) | V1 | 1600×740 (root) | none | 2× | 267 | 212 115 |
| Runner outdoors (play shot 2) | V2 `8e61029` | 1600×740 (root) | none | 2× | 158 | 246 658 |
| Cart driving | V1 | 1600×740 (root) | none | 2× | 525 | 323 870 |
| Cart driving | V2 `babee2a` | 1600×740 (root) | none | 2× | 234 | 261 019 |

What this established:
- **The V1 blur was a sizing bug, measured.** The `Preview3D.new(Vector2i(480, 300))` size in the source was never used: the stretched container sized the SubViewport in canvas units, so on a 3× phone the character preview rendered at 61.5% of its displayed size, upscaled bilinearly and without MSAA. V2 renders every menu character in the root viewport at native resolution. The inline `Preview3D` that remains renders at displayed pixel size and is drawn 1:1.
- **The main game view was already native** in V1 (root render = window, scale 1.0). Its softness came from content: flat-shaded low-poly characters, washed-out sRGB vertex colours (fixed late in V1) and the canopy dither. V2 changes the content (authored character, materials, water, foliage) rather than the render size.
- **Draw calls and geometry.** Home and wardrobe dropped from 179 and 182 draw calls to 34 and 48, because the campus fly-over and the stretched preview were replaced by one merged room. The one-player lobby draws more than V1's small preview card (54 → 82). The full lobby draws fewer calls (291 → 166) but more triangles (88k → 273k), because eight detailed characters replace primitives. In gameplay, draw calls fell from 267 to 158 (runner) and from 525 to 234 (cart view, where each rebuilt cart is about 7 calls instead of about 25), with similar geometry: 212k → 247k triangles for the runner view and 324k → 261k for the cart view. Distant characters use the imported LODs. Whether 273k triangles in the full lobby is comfortable on an iPhone 14-class GPU still needs a device measurement.
- **Frame times in these JSON files are not measurements.** Under `--fixed-fps 60` and Movie Maker the engine advances exactly 16.67 ms per frame regardless of how long llvmpipe takes, so the `frame_ms` percentiles are always 16.67. They are recorded only to show that the capture clock was fixed.

Presets (Settings → Graphics; never switched automatically), measured from the diag JSON of two captures: same seed, same moment (t = 20.03 s), commit `4c89ed0`, window 1600×740 (`docs/media/v2/standard_runner_same_moment.*` and `battery_saver_runner.*`):

| Measured in the diag JSON | Standard | Battery Saver |
|---|---|---|
| 3D render size | 1600×740 (100%) | 1280×592 (80%, bilinear; UI stays native) |
| MSAA | 2× | 2× |
| Moon shadow | 2 splits to 70 m, 2048 atlas | 1 orthographic split to 30 m, 1024 atlas |
| Campus meshes casting shadows | 49 of 56 | 0 of 56 (characters and carts still cast) |
| Glow | on | off |
| Mesh LOD threshold | 1.0 | 3.0 |
| Draw calls / primitives in that frame | 175 / 279 798 | 147 / 110 383 |
| Frame cap | 60 fps on iOS | 30 fps on iOS |

The frame cap is applied only on iOS (`OS.has_feature("mobile")`), so it cannot be observed on desktop. The preset is stored in the profile and applied at startup and whenever it changes.

## V2.3 Visual evidence

Index with platform, commit and settings for every file: [docs/media/v2/README.md](docs/media/v2/README.md). Before/after pairs are lossless PNGs at the size they were rendered; **art evidence** (the character lineup sheets) is kept separate from **gameplay evidence** (the running game). There is no device evidence.

| Before (V1 `654b0a8`) | After (V2) | What changed |
|---|---|---|
| `before/home.png` | `after/home.png` | Campus fly-over behind a column of five equally loud buttons, no character → your character standing front three-quarter in a native-resolution dorm common room; one primary action (Play with Friends), Practice as a quiet second, Outfit and Settings as icons |
| `before/wardrobe.png` | `after/wardrobe.png` (+ `art/closeup.png`) | 1.63×-upscaled preview → the same character rendered natively; close-up shows eyes, brows, nose, mouth, cap, collar, buttons and cuffs |
| `before/lobby_1p.png`, `before/lobby_8p.png` | `after/lobby_1p.png`, `after/lobby_8p.png` | Static roster beside a blurry preview → party on the stage, compact party list, one primary action; 8 players readable with a 34-character name |
| `before/runner_outdoors.png` | `after/runner_outdoors.png` | Primitive runner, compass strip, large labels → authored runner, timer/home chip, objective chips with bearing and distance, compact minimap |
| `before/water_entry.png`, `before/water_recovery.png` | `after/water_entry.png`, `after/water_recovery.png` | Glowing, washed-out surface → blue/teal water with a slim active ring, splash ripple and foam shoreline |
| `before/cart_drive.png` | `after/cart_drive.png` | Boxy cart half hidden by a canopy → merged-mesh cart with tyres, seat and a steering wheel the driver holds; the canopy in front of your cart is cut away cleanly |
| `before/foliage_near_camera.png` | `after/foliage_near_camera.png` | A canopy beside the camera drawn with the speckled 4×4 screen-door dither → the same canopy solid, parted away from the camera, no dither |
| (no tag shot in the V1 capture round) | `after/tag_lunge.png` | On-foot tag lunge |
| `before/results.png` | `after/results.png`, `after/results_drawer.png` | Full-screen eight-row table and reward list over a flat background → outcome, your round, rewards and one primary action on a sheet beside your character (cheering or shrugging); the full scoreboard is a drawer |

Layout checks at other device aspects (`docs/media/v2/layout/`): iPhone 19.5:9 @3x (2532×1170), iPhone SE 16:9 @2x (1334×750) and iPad 4:3 @2x (2048×1536) for home, Play with Friends, Settings, lobby with 8 players and a long name, results with the scoreboard drawer open, and the match HUD with touch controls. Each layout check was reviewed by eye. Problems found and fixed are in V2.7: the Play with Friends sheet overflowing, How to Play over the room, the scoreboard covering the results sheet, and a face hidden in the full lobby.

**Normal-speed recordings.** All are desktop renders recorded with Movie Maker at 60 fps, so one frame is 1/60 s of game time and the clips play at true game speed. The local player is bot-driven, and each clip says so in a burned-in label:
- `docs/media/v2/night_watch_v2_desktop.mp4`: V2 `4c89ed0`, 82 s, 1280×720, seed 12. Release, cart entry, driving, hopping out, an on-foot chase (the runner dives away) and a tag at 1:16.
- `docs/media/v2/runner_v2_desktop.mp4`: V2 `4c89ed0`, 50 s, 1280×720, seed 11. Countdown and head start, running and turns along paths and a road, the splash into Old Quarry Lagoon at 0:44 and the recovery.
- `docs/media/v2/runner_v1_baseline_desktop.mp4`: V1 `654b0a8`, 35.9 s, seed 11. The recording was stopped by a task time limit, and the HUD edges are cropped by the recorder (1600×740 window, 1280×720 movie).

These clips show animation, camera behaviour and the art in motion. **They cannot show device smoothness**: llvmpipe takes far longer than 16.7 ms per frame, and Movie Maker hides that. There is no recording of real touch input; that needs a device.

## V2.4 Functional checks from the brief

| Check | How | Result |
|---|---|---|
| No lost stick ownership, stuck gas/brake, stolen action touches, camera gestures firing actions | `test_touch_input` (13 cases above) | Pass (unit). Feel on glass unverified |
| Touch ↔ controller switching in play | `test_touch_input::test_controller_takeover_and_focus_loss_release_touch_intent`; prompts switch via `Controls.device_changed` (V1 behaviour kept) | Pass (unit). Needs a real controller on device |
| No progress loss, duplicate stamps/rewards, invalid captures, changed win conditions, rematch leaks | V1 `test_sim`, `test_rules`, `test_net` suites, unchanged and passing | Pass |
| Event feedback once (no duplicate splashes, haptics, stamp toasts after reconciliation) | Splash/capture feedback is driven only by host events, deduplicated by event ID (`NetSession`, V1 `test_duplicate_reordered_inputs_and_late_snapshots`); footsteps are generated by the render-time animation phase, never by prediction replay; splash and capture haptics are called only from those event handlers (button-press haptics are local input feedback) | Pass by construction + V1 tests; not separately measured on device |
| Lobby ready/outfit updates keep animation; all eight readable | `test_lobby`; lobby captures at three aspects | Pass |
| Safe areas, long names, drawers, controls on small phones and iPad | Layout captures at 19.5:9, 16:9 and 4:3 (above); safe margins come from `DisplayServer.get_display_safe_area()` | Pass on desktop renders at the three aspects after the V2.7 fixes. Names longer than the cell are shortened with an ellipsis (e.g. "Bartholomew Sn…"). Safe-area insets on a Dynamic Island device are unverified (desktop has none) |
| Standard and Battery Saver persist and match behaviour | Setting saved in the profile and applied at startup (`Save._apply_settings`); Battery Saver diag above | Pass on desktop: the measured settings differ as listed in V2.2. On device, the effect on frame time and battery is unmeasured. |
| Existing cosmetics and saves still load | `test_profile` | Pass |
| Routes, timers, speeds, tag reach unchanged | No rule, simulation, bot, network or map-layout code changed (`git diff 654b0a8 -- game/src/config game/src/core game/src/sim game/src/bots game/src/net game/src/map/campus_layout.gd game/src/map/nav_grid.gd` is empty); route and chase tests pass unchanged | Pass |

## V2.5 Networking on V2

V2 changed no simulation, protocol or network code (`git diff 654b0a8 -- game/src/net game/src/sim game/src/core game/src/bots game/src/config` is empty). What changed is presentation: render-time interpolation of the tick states the client already had, and explicit snaps on discontinuities. The network tests therefore check that the presentation work did not disturb prediction, reconciliation or events.

**Loopback net** (`test_net`, from the final test run on `5505024`, `docs/test-data/full_test_run.txt`). RTT is the simulated round trip. "Client RTT est." is the client's own smoothed estimate, which varies between runs: the 300 ms case read 309 ms in an earlier run of the same test.

| Case | Simulated network | Client RTT est. | Snapshots | Correction avg / max | Corrections > 25 cm | Teammate interpolation error | Missing reliable events |
|---|---|---|---|---|---|---|---|
| `rtt100` | 100 ms RTT, ±8 ms jitter | 97 ms | 379 | 3 mm / 0.18 m | 0 | 0.03 m | 0 |
| `rtt150_loss5` | 150 ms RTT, ±15 ms, 5% loss | 148 ms | 361 | 3 mm / 0.23 m | 0 | 0.02 m | 0 |
| `rtt300_loss10` | 300 ms RTT, ±30 ms, 10% loss | 231 ms | 332 | 4 mm / 0.34 m | 1 | 0.03 m | 0 |
| 8 humans (host + 7 clients) | 120 ms RTT, 3% loss | n/a | 2038 total | worst client avg 2 mm | n/a | n/a | 0 |
| Client Night Watch tag | 150 ms RTT | n/a | n/a | n/a | n/a | n/a | Tag **captured** with 9 ticks (150 ms) of lag |

**Desktop UDP soak on V2** (`tools/net_soak.sh`, final code `5505024`): separate Godot processes on one Linux machine over real UDP (ENet). Each process shapes its own outbound traffic, and every human slot is a separate process playing with automation input (`--local-bot`). Reports are in `docs/test-data/v2_net_soak_*`.

**8 humans: host + 7 clients, 60 ms ±10 ms one-way, 3% loss each way (about 150 ms RTT).** One complete 240 s round; the Night Watch won with 0/4 runners home.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 0/4 | 156 ms | 4768 | 1.3 mm | 0.30 m | 60 | 15341 | 454 |  |
| client2 | 1 | Night Watch win | 0/4 | 159 ms | 4794 | 1.7 mm | 0.54 m | 60 | 15359 | 460 |  |
| client3 | 1 | Night Watch win | 0/4 | 153 ms | 4778 | 2.0 mm | 0.80 m | 60 | 15337 | 468 |  |
| client4 | 1 | Night Watch win | 0/4 | 152 ms | 4794 | 1.7 mm | 1.56 m | 60 | 15341 | 501 |  |
| client5 | 1 | Night Watch win | 0/4 | 153 ms | 4799 | 1.5 mm | 0.67 m | 60 | 15349 | 447 |  |
| client6 | 1 | Night Watch win | 0/4 | 156 ms | 4774 | 1.3 mm | 0.26 m | 60 | 15351 | 449 |  |
| client7 | 1 | Night Watch win | 0/4 | 154 ms | 4811 | 0.9 mm | 0.30 m | 60 | 15355 | 483 |  |
| host | 1 | Night Watch win | 0/4 | - | 0 | host (no prediction) |  | 60 | 38859 | 1137 | 0 starved / 11 skipped ticks (all clients) |

**High latency: host + 3 clients, 130 ms ±25 ms one-way, 8% loss each way (about 300 ms RTT).** One complete round; the Night Watch won with 3/4 home.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 3/4 | 298 ms | 4552 | 2.3 mm | 0.31 m | 60 | 15357 | 1193 |  |
| client2 | 1 | Night Watch win | 3/4 | 285 ms | 4510 | 2.5 mm | 2.07 m | 60 | 15366 | 1250 |  |
| client3 | 1 | Night Watch win | 3/4 | 299 ms | 4539 | 4.2 mm | 1.86 m | 60 | 15369 | 1162 |  |
| host | 1 | Night Watch win | 3/4 | - | 0 | host (no prediction) |  | 60 | 16725 | 1296 | 55 starved / 4 skipped ticks (all clients) |

These match V1 under the same conditions (V1: average corrections of 0.4–2.5 mm, worst single correction 2.15 m at about 300 ms, host starved ≤ 0.3% of ticks), so the presentation changes did not degrade prediction or reconciliation. The round outcomes differ from V1's runs because the client processes' timing differs from run to run. The column meanings are explained under 3b below.

What these runs do **not** cover: iPhones, the Game Center (`GKMatch`) transport, cellular networks, and reconnect on a device. They remain on the device checklist (V2.8).


## V2.6 iOS build (CI iOS)

Same lane as V1 (`.github/workflows/ios.yml`, GitHub Actions `macos-26`, Xcode 26.6 (17F113), iOS SDK 26.5). `MARKETING_VERSION` is now **1.1**. Without App Store Connect access, the unsigned build number is the run number, so it is above V1's last build, 1.0 (10).

| Run | Commit | Tests | Unsigned arm64 device archive | Simulator (iPhone Air, iOS 26.2) | Signed archive / upload |
|---|---|---|---|---|---|
| #11 | `e628130` (character asset) | ✅ | ✅ | ✅ | ⏸ skipped (no secrets) |
| #12 | `0539d7c` (V2 UI, controls, motion, world) | ✅ | ✅ `1.1 (12)`, 263 MB `.app` | ✅ boot splash with the V2 character, loading, match role reveal and HUD; no crash report | ⏸ skipped |
| #13 | `e3d5c85` | ✅ | ✅ | ✅ | ⏸ skipped |
| #14 | `4c89ed0` | ✅ | ✅ `1.1 (14)`, arm64, 263 MB, `com.apple.developer.game-center`, `PrivacyInfo.xcprivacy` | ✅ same sequence (`docs/media/v2/ios_simulator_ci_run14.jpg`); cold launch still running at the check; "no crash report" | ⏸ skipped |
| #15 | `36f4cea` (docs) | cancelled when #16 was pushed (the workflow cancels in-progress runs on the same branch) | | | |
| #16 | `b56a82a` (final app code: `5505024` + owner-supplied app icon) | ✅ | ✅ `1.1 (16)`, arm64, 269 MB, Game Center entitlement, `PrivacyInfo.xcprivacy` | ✅ boot splash, loading, match reveal and HUD (`docs/media/v2/ios_simulator_ci_run16.jpg`); no crash report | ⏸ skipped (no secrets) |

As in V1, the Simulator runs the x86_64 slice under Rosetta with an OpenGL ES fallback and produces roughly one frame every several seconds. These runs show that the build installs, launches and reaches a match. They say nothing about load time or frame rate on an iPhone.


## V2.7 Fixed during V2 validation

Found by reviewing captures and tests, then fixed:
- **Steering sign.** The steer-left/right clips, the wheel rotation and the sim's steering sign disagreed, so the driver could turn the wheel against the cart. One convention now: positive steer is a right turn, the wheel rotates −50° × steer, and the clips are mapped to match (`art/cart.png`).
- **Arm raises had the wrong sign** in the clip authoring convention, so raise poses (jump, fall, splash, celebrate, wave, cheer and others) moved the arms the wrong way. Fixed in `tools/character/anims.py`, over-rotation reduced, and re-baked (`art/posesheet.png`).
- **Animation loop seam.** Clips were 1.033 s instead of 1.0 s because keys started at frame 1, which made locomotion hitch at the loop. Keys now start at frame 0.
- **Foot IK out of reach.** Locomotion foot targets were further than the legs could reach. Stride sweep and stance timing were reduced and the pelvis drop raised; playback rate still comes from the clip's metres per cycle, so feet do not slide.
- **Inside-out and misrotated geometry.** The cart steering wheel was mirrored with a negative scale and rendered inside out; it is now wound correctly. The new dorm doors were placed with a wrong yaw formula; corrected.
- **Lobby framing.** On a square or 4:3 viewport only 7 of 8 characters were in view (`test_lobby` failed). The lobby camera now frames the group in the space left of the party panel for any aspect.
- **A hidden face in the full lobby.** The 2532×1170 eight-player capture showed the back-centre player directly behind the local player, with their face covered by the local player's nightcap. The lobby camera is now 3.1 m up instead of 2.5 m, and the back mark is 0.2 m further back. `test_lobby` now checks on screen that no face is behind a nearer head or cap; on the old layout it fails with "p7 behind p0".
- **Scoreboard over the results sheet.** In the 16:9 and 4:3 captures, the scoreboard drawer opened at the left edge at its natural width and covered "Your round" and Play again. It is now a centred sheet over a dimmed backdrop, sized to the screen, with its own Close button; Back closes it first. Also fixed in the lobby: "1 bots" now reads "1 bot".
- **Name labels over the HUD.** A bot right next to the camera had its fixed-size name label float up over the timer (water-entry capture). Labels are now hidden within 3.5 m of the camera.
- **A canopy hid the player's own cart.** With the dither gone, the V2 cart capture showed a tree fully covering the cart, because the camera correctly ignores canopies and the parting only reaches 2.6 m. Canopy between the camera and the followed character is now cut away in a circle around it, with a clean edge and in the camera pass only (`after/cart_drive.png`, same moment as `before/cart_drive.png`).
- **Menu layout.** The wardrobe sheet slid with its container on entry (transitions are now fade + scale only); lobby labels overlapped and "(you)" was truncated; icon buttons stretched; the Play with Friends sheet ran off the bottom when the Game Center card was shown (now scrolls, inert controls hidden); How to Play drew text straight over the 3D room (now on a sheet with "Got it" in the header).

## V2.8 Not verified (exact remaining device checks)

Nothing below can be established on this machine. Each needs a signed build on hardware.
- [ ] **Frame rate and pacing.** A 15–20 minute session (several rounds) on an iPhone 14-class device at Standard, with Xcode Instruments (Game Performance / Metal System Trace): frame-time distribution, missed presentation intervals, hitches, memory growth, thermal state. Repeat for Battery Saver on an A12/A13 device. Profile the host with the full roster and bots, and a client, separating CPU (sim + bots) from GPU.
- [ ] **Touch on glass.** Dynamic and fixed stick feel, the 0.88/0.76 edge-sprint thresholds, camera drag speed (0.0065 rad per point), three-finger play, button sizes at Small/Medium/Large on a small iPhone, mirrored layout, haptics.
- [ ] **Safe areas** on Dynamic Island iPhones and iPad (insets are zero on desktop).
- [ ] **4× MSAA.** Standard uses 2×; whether 4× fits the frame budget needs GPU measurements on device.
- [ ] **Game Center on two or more iPhones** (unchanged from V1): code room, friend invite, full round with cart, chase, tag, splash and finish, rematch, host leaving.
- [ ] **Controllers on device**, connecting and disconnecting mid-match.
- [ ] **TestFlight install** of a signed build (blocked on App Store Connect access; see TESTFLIGHT_RELEASE.md).

## V2.9 Known limitations

- **iOS share sheet.** The room code has a Copy button; a native share sheet is not implemented.
- **World polish is partial.** Dorm doors (with trim, transom and step), benches, lamps, tree canopies, carts and water were refined. Window frames, roof edges, curbs and path edges, the fountain, the pool edge and the cart shed are unchanged from V1.
- **Canopy see-through inside a large tree.** When the follow camera ends up inside a big canopy (Night Watch movie, about 0:30), the see-through shows as a round window around the cart. The player stays visible, but it reads like a porthole. A softer treatment needs tuning on a device.
- **Overlapping distant labels.** Two characters at similar distance can still have overlapping name labels; there is no label decluttering.
- **Character LODs** are Godot's automatic import LODs and have not been checked on device.
- All V1 limitations below still apply (host trust, code-room timing, desktop LAN for development only, lighting needing a real-screen check, plugin export log noise, A12 minimum).

# V1 (version 1.0), kept as the baseline

The sections below are the V1 report as written for commit `b2d4844` / `f1c7579`. Where V2 changed behaviour, the V2 sections above take precedence.

## 1. Automated tests

Run them with `tools/run_tests.sh`. CI runs the same suite on every push (job "Rules, simulation and network tests").

The latest full local run, on the final commit `b2d4844`: **53 tests, 802 checks, 0 failures** (`docs/test-data/full_test_run.txt`). The CI test job runs the same suite on every push.

| Suite | Tests | What they exercise (behaviour, not constants) |
|---|---|---|
| `test_rules` | 11 | All 20 three-of-six combinations and their 6 orders; route-table fairness; seeded target pick with no immediate repeat; fair role rotation and preferences; respawn pad choice; tag geometry; rewards (unique captures, no idle-survival reward, practice ×0.5); level curve; input wire format; reward ledger paid once per match ID |
| `test_sim` | 19 | Every curated combo × all 6 orders; duplicate and inactive splashes; automatic resurfacing (no hiding in water); 6 s capture timing with stamps kept and role kept; return to the dorm before the first stamp and to the 3rd water after three; ~2 s protection; tag reach, cooldown and walls (no tag through a wall); tag role/state validation; **same-tick finish beats tag**; 4th runner ends the round immediately; timeout and deadline-tick finish; cart seat race and wrong-role entry; cart drive, safe exit and post-exit tag lockout; bump stumble without chain or capture; gadget single use and ownership; splash bomb slows a cart briefly; reconnect resume and reservation expiry; out-of-bounds recovery grants nothing; finished runner out of play; movement numbers; spotted cue needs line of sight |
| `test_camping` | 3 | Two campers at any water's exits/pads cannot cover every exit; the respawn pad is ≥ 15 m from both (worst case measured 20.7 m); an in-play respawn lands away from two campers; dorm doors are ≥ 15 m apart (18 m); carts driven flat out at the dorm from 4 directions are stopped by bollards 17–54 m from the nearest door |
| `test_net` | 13 | Snapshot size and round-trip; lobby join/ready/start; match sync at 100 ms, 150 ms + 5% loss, and 300 ms + 10% loss RTT; capture reaching the client, and client-patrol lag-compensated tags; clean and silent host loss; reconnect resumes slot and progress; late join spectates then plays; rematch cleanup; duplicate/reordered inputs and late snapshots; 8 humans online with no bots |
| `test_routes_bots` | 1 | Six runner bots, using the same movement code and inputs as players, complete every curated route with no pursuit |
| `test_chase_balance` | 2 | On open ground a Night Watch bot runs down a fleeing runner bot from 8 m (at least 3 of 4 trials within 25 s); a runner sprint still opens the gap and the Night Watch closes it again afterwards |
| `test_smoke`, `test_compile` | 2 | Campus layout and builder load; every script compiles |

## 2. Route fairness (headless sim, bots)

- **Method.** Six runner bots, using the same input limits as players, run each of the 14 curated combinations with the Night Watch held idle. Raw output: `docs/test-data/route_bot_times_run.txt`.
- **Result.** **84 / 84** bot runs finished.
  - Trip times ranged **103–132 s**, with a median of **117.5 s** (final run).
  - The per-combination medians are within ±12% of each other.
- **Excluded combinations.** The 6 other combinations were left out because their estimated or measured trips fell outside that band.
- **Expected human times.** Bots take near-optimal lines with sprint management. First-time human players should land in the requested 2–3 minutes: rough estimate 2:10–2:40, which still needs **device playtests** to confirm. That leaves 1–2 minutes of the 4-minute round for chases and captures.
- **With pursuit.** In the full-round capture, bot runners played against both Night Watch bots on the final tuning. The first runner got home at 2:03 and the fourth at 2:36; along the way the Night Watch caught three runners once each, and one runner ended the round with only 2/3 stamps (`docs/media/shots/results_runners_win.jpg`).

## 3. Networking

### 3a. Loopback net (in-process clients, simulated network)

The in-process network tests produce `NETSTAT` lines. Raw output: `docs/test-data/net_tests.txt`.

| Case | Simulated network | Client RTT estimate | Snapshots | Correction avg / max | Corrections > 25 cm | Teammate interpolation error | Missing reliable events |
|---|---|---|---|---|---|---|---|
| `rtt100` | 100 ms RTT, ±8 ms jitter | 139 ms | 379 | 2 mm / 0.15 m | 0 | 0.05 m | 0 |
| `rtt150_loss5` | 150 ms RTT, ±15 ms, 5% loss | 168 ms | 359 | 3 mm / 0.31 m | 2 | 0.01 m | 0 |
| `rtt300_loss10` | 300 ms RTT, ±30 ms, 10% loss | 302 ms | 336 | 3 mm / 0.15 m | 0 | 0.03 m | 0 |
| 8 humans (host + 7 clients) | 120 ms RTT, ±10 ms, 3% loss | n/a | 2038 total | worst client avg 3 mm; largest single correction 0.22 m | 0 | n/a | 0 |
| Client Night Watch tag | 150 ms RTT | n/a | n/a | n/a | n/a | n/a | Tag **captured** with 13 ticks (217 ms) of measured lag; compensation is capped at 150 ms |

- **Correction** is the distance the client's predicted position moves when a server snapshot is reconciled. Legitimate teleports (respawn, resurfacing, cart exit) are excluded.
- **Lag compensation.** A client playing Night Watch at 150 ms RTT tagged a running runner, and the host validated the tag against the runner's position as that client saw it.
- **Reliable events.** No reliable event went missing.
- **Snapshot size.** Snapshots are under 900 bytes for an 8-player room.

### 3b. Desktop UDP (separate processes, real sockets)

`tools/net_soak.sh` starts one host and N client processes, each with its own profile, outbound latency/jitter/loss shaping, and automation input. Every human slot is a separate process; no bots fill human slots. The rows below are copied from the JSON reports in `docs/test-data/`.

**Gameplay code `d89a78a` (the last gameplay commit; the final commit `b2d4844` only defers the title background): host + 3 clients, 60 ms ±10 ms one-way, 3% loss each way (≈150 ms RTT).** `docs/test-data/net_soak_3c_60ms_0.03/`. A complete round; runners won 4/4.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Runners win | 4/4 | 154 ms | 4665 | 1.2 mm | 0.41 m | 60 | 14874 | 472 |  |
| client2 | 1 | Runners win | 4/4 | 154 ms | 4668 | 2.1 mm | 1.19 m | 60 | 14877 | 451 |  |
| client3 | 1 | Runners win | 4/4 | 152 ms | 4676 | 1.7 mm | 0.36 m | 60 | 14879 | 454 |  |
| host | 1 | Runners win | 4/4 | - | 0 | host (no prediction) |  | 60 | 16135 | 437 | 24 starved / 3 skipped ticks (all clients) |

**8 humans: host + 7 clients, 60 ms ±10 ms one-way per direction, 3% loss each way (≈150 ms RTT).** `docs/test-data/net_soak_7c_60ms_0.03/`. One complete 240 s round; the Night Watch won with 1 runner home.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 1/4 | 151 ms | 4810 | 0.6 mm | 0.08 m | 60 | 15298 | 500 |  |
| client2 | 1 | Night Watch win | 1/4 | 153 ms | 4791 | 1.3 mm | 0.32 m | 60 | 15303 | 445 |  |
| client3 | 1 | Night Watch win | 1/4 | 150 ms | 4780 | 0.4 mm | 0.27 m | 60 | 15285 | 441 |  |
| client4 | 1 | Night Watch win | 1/4 | 159 ms | 4808 | 1.0 mm | 0.31 m | 60 | 15300 | 482 |  |
| client5 | 1 | Night Watch win | 1/4 | 154 ms | 4764 | 0.7 mm | 0.31 m | 60 | 15339 | 458 |  |
| client6 | 1 | Night Watch win | 1/4 | 159 ms | 4813 | 1.5 mm | 0.63 m | 60 | 15317 | 465 |  |
| client7 | 1 | Night Watch win | 1/4 | 156 ms | 4778 | 1.7 mm | 0.63 m | 60 | 15290 | 427 |  |
| host | 1 | Night Watch win | 1/4 | - | 0 | host (no prediction) |  | 60 | 39709 | 1114 | 37 starved / 5 skipped ticks (all clients) |

**High latency: host + 3 clients, 130 ms ±25 ms one-way, 8% loss each way (≈300 ms RTT).** `docs/test-data/net_soak_3c_130ms_0.08/`. Runners won 4/4 before time ran out.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Runners win | 4/4 | 299 ms | 2612 | 1.3 mm | 0.30 m | 60 | 8689 | 692 |  |
| client2 | 1 | Runners win | 4/4 | 278 ms | 2532 | 2.5 mm | 2.05 m | 60 | 8681 | 689 |  |
| client3 | 1 | Runners win | 4/4 | 312 ms | 2544 | 2.0 mm | 2.15 m | 60 | 8678 | 678 |  |
| host | 1 | Runners win | 4/4 | - | 0 | host (no prediction) |  | 60 | 9466 | 733 | 61 starved / 7 skipped ticks (all clients) |

**Baseline: host + 2 clients, 40 ms one-way, no loss.** `docs/test-data/net_soak_2c_40ms_0.0/` (earlier build). One complete 240 s round.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 3/4 | 117 ms | 4970 | 0.6 mm | 0.93 m | 60 | 15369 | 0 |  |
| client2 | 1 | Night Watch win | 3/4 | 117 ms | 4967 | 3.9 mm | 5.57 m | 60 | 15367 | 0 |  |
| host | 1 | Night Watch win | 3/4 | - | 0 | host (no prediction) |  | 60 | 11019 | 0 | 31 starved / 4 skipped ticks (all clients) |

How to read these tables:
- "Corr. avg" is the mean distance the client's own predicted position moved when reconciled, so lower is better. "Corr. max" is the single worst correction in the round.
- Rare large corrections (≈2 m at 300 ms RTT with 8% loss) happen when several consecutive snapshots are lost while the runner is turning sharply. Corrections under 3 m are blended out visually over a few frames instead of snapping the camera.
- "Host starved" counts ticks where the host had no new input from a client and repeated its last held input. The counts seen are ≤ 0.3% of ticks.

These are **8 independent desktop clients on one Linux machine over UDP**. They are not iPhones and not the Game Center transport.

The 7- and 3-client soaks ran on commit `23004fe`, before the bot and chase-tuning changes. Those changes alter gameplay balance, not the network code, so the networking numbers carry over.

## 4. iOS build (CI iOS)

| Step (`.github/workflows/ios.yml`) | Result |
|---|---|
| Godot 4.7.2 export to Xcode project (bundle `com.idlery.ultimatetrifecta`, Game Center entitlement) | ✅ |
| `xcodebuild archive` for `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO` (arm64 compile + link) | ✅ **project compiled** (unsigned) |
| Simulator build (x86_64; Godot 4.7.2's simulator slice is x86_64 only) | ✅ |
| Simulator launch (runs 3–10, iPhone Air simulator, iOS 26.2 runtime) | ✅ **Installs, launches and reaches a match** (runs 4, 5, 8, 9 and 10; runs 6 and 7 used a shorter window and were still loading when it closed).<br>Run 10 is on the final code (`docs/media/ios_simulator_ci_run10.jpg`): boot splash, about 5 minutes of loading, then the role-reveal card, 4:00 HUD, target list, minimap and [BOT] players, still rendering at the end of the window. The Simulator here produces roughly one frame every 30 s, so game time advances very slowly and the round never got past the reveal.<br>**Crash reports:** run 8 produced one `UltimateTrifecta-…-111659.ips` report. CI printed only its file name, and the cold-launch app was no longer in the foreground at 45 s in that run, so the report most likely belongs to that cold launch. Its contents were not captured, so the cause is **unknown**. CI now summarises any report (`tools/ips_summary.py`). Runs 3–7, 9 and 10 produced none, and in runs 9 and 10 the cold launch was still alive at 45 s.<br>A cold launch never reached the title screen within the 45 s window. |
| Archive facts (runs 4–10) | Xcode 26.6 (17F113), iphoneos SDK 26.5, `arm64` binary, `.app` 261 MB uncompressed. Runs 5–6 have no purpose-string warnings.<br>Info.plist: `CFBundleIdentifier com.idlery.ultimatetrifecta`, `1.0 (10)` in run 10 (final code), `MinimumOSVersion 17.0`, `UIDeviceFamily 1,2`, landscape left/right, `ITSAppUsesNonExemptEncryption false`.<br>Entitlement: `com.apple.developer.game-center`.<br>Frameworks: `GodotApplePluginsGameCenter`, `SwiftGodotRuntime`. `PrivacyInfo.xcprivacy` declares file-timestamp, boot-time and disk-space API reasons. |
| Signed archive / upload | ⏸ not run: no App Store Connect credentials (see TESTFLIGHT_RELEASE.md) |

Godot 4.7.2's simulator slice is x86_64, so the app runs under Rosetta on a virtualised Apple-silicon runner. It also falls back to an OpenGL ES 3.0 context there (the console says "Setting up an OpenGL ES 3.0 context"), while devices use Metal.

As a result, the Simulator is orders of magnitude slower than a device. Loading took minutes there, against about 1 s for the whole map generation on the Linux desktop (layout 68 ms, nav grid 54 ms, collision 242 ms, visuals 591 ms), and screenshots 15–20 s apart were often identical. These runs prove that the iOS build installs, launches and runs the game code into a match. They say nothing about iPhone load time or frame rate.

Evidence: the GitHub Actions artifact `ios-simulator-evidence-<build>`, holding screenshots, a screen recording, `app-console.log` and `export.log`.

The archive build also showed that Godot's export writes **empty** camera, microphone and photo-library purpose strings, which Xcode warns about. They are now filled with honest "not used" text, so App Store validation does not trip on empty strings. The app bundle contains `PrivacyInfo.xcprivacy`.

## 5. Exploit attempts and fixes

| Attempt | How tested | Result |
|---|---|---|
| Camp a water's exits | `test_camping` (geometry for all six waters, plus a live respawn with two campers) | Cannot cover every exit; respawn ≥ 20 m from two campers |
| Camp the dorm with a cart | `test_camping`: cart driven at the dorm from 4 sides | Bollards stop it 17–54 m out; 4 doors 18+ m apart |
| Hide indefinitely in water | `test_water_resurfaces_automatically` | Forced resurfacing after 1.5 s at a shore exit |
| Hide anywhere | Rules | Survival never counts; only finishes win, so the clock favours the Night Watch |
| Chain-bump a runner with a cart | `test_bump_stumbles_without_chain_or_capture` | One stumble, then 1 s bump protection and a per-cart cooldown; never a capture |
| Tag through a wall | `test_tag_reach_cooldown_and_walls` | Rejected (line of sight is checked on the host) |
| Tag from a cart or right after dismount | `test_cart_drive_exit_safely_and_lockout`, `test_tag_validation_roles_and_states` | Rejected (on-foot only; 0.5 s lockout after exit) |
| Take a cart as a runner, or two patrols racing for one seat | `test_cart_seat_race_and_roles` | Runners cannot enter; exactly one patrol gets the seat |
| Double-use a gadget, or use one you don't own | `test_gadget_single_use_and_ownership` | Consumed once; ownership and cooldown checked on the host |
| Reconnect for an advantage (reset, free protection, duplicate gadget) | `test_reconnect_resumes_and_reservation_expires`, `test_reconnect_resumes_slot_and_progress` | Same state and progress resumed; no reset, no protection, no duplicates |
| Re-splash for extra stamps; inactive water | `test_duplicate_and_inactive_splash` | Rejected |
| Out-of-bounds or fall shortcut | `test_out_of_bounds_recovery_grants_nothing` | Recovers to the last pad; no stamps, no shortcut |
| Late or duplicate packets changing results | `test_duplicate_reordered_inputs_and_late_snapshots`, `test_same_tick_finish_beats_tag` | The host is the only authority; events are deduplicated by ID |
| Farm one runner for capture coins | `test_rewards_unique_captures_no_idle_survival` | Only distinct runners pay |

**Fixed during testing.**
- **Client prediction drift** (≈ cm-level corrections, occasionally more):
  - Floor contact is now serialized at the end of each step, and the floor is snapped after a reconcile.
  - An off-by-one in the client's process-tick gating was corrected.
  - The Night Watch now holds a WAITING state from setup on both host and client.
  - Average corrections dropped to a few millimetres.
- **Clients reporting "finished" twice:** now guarded, and the host remains the only authority.
- **Rendering:**
  - Back-facing generated meshes (cylinders, cones, roofs, door glows) fixed.
  - Washed-out vertex colours fixed with an sRGB→linear conversion.
  - Pool water was hidden under the plaza paving; fixed.
- **Route test overwrote bot timings:** it replaced the measured times for non-curated combinations; it now merges them.
- **Foot chases could not be won.** Seen in the Night Watch capture, where the bot followed a runner at 1–2 m for 20 s without a tag. The Night Watch foot speed is now 6.2 m/s, the wind-up keeps 60% speed, and the bot waits for a closer gap against sprinting runners. Details are in RULES.md, and `test_chase_balance` covers it.
- **Tree canopies could fill the screen** when the follow camera passed through a tree. Seen in the runner capture. Canopies now dissolve near the camera through a foliage-only shader variant.
- **Bots ran stacked in single file** on shared nav paths, and one got pinned on the pool's west gate post for over 3 minutes during the route test. Bots now have stable route preferences, steer apart from nearby teammates, and back off sideways when a hop doesn't free them.
- **Broken time-lapse captures.** A `--time-scale` capture flag made runners move 4× per simulation tick: a trifecta "in 0:36" in a captured results screen. The flag scaled the engine physics delta while the simulation counts fixed ticks. Normal play never used it; it has been removed.
- **Screen overflow at 16:9 and iPad 4:3.** The results, Play with Friends and lobby screens overflowed at 1280×720 and 1280×960; the lobby's Start button was partly off-screen. Found by rendering every menu screen at both aspects. Layouts were tightened and re-checked at 16:9, 4:3 and 19.5:9.
- **Empty purpose strings in Info.plist.** Godot's export wrote empty camera, microphone and photo-library strings; Xcode warned about them in CI run 3. They are now filled.

## 6. Visual and audio evidence

Index: `docs/media/README.md`. Every file is labelled by platform and commit.

- **Desktop clips** (Linux, Godot Movie Maker, software Vulkan):
  - a 58 s runner clip: reveal, head start, splash and stamp;
  - a 75 s Night Watch clip: cart in, drive, hop out, chase, capture;
  - a full-round time-lapse through to the results screen.

  The local player in each is bot-driven automation (`--local-bot`), and each clip says so.
- **Stills:** the title screen, the six waters and other campus locations, and key moments from the clips.
- **iOS Simulator contact sheet** from CI run 10, on the final code (see section 4).
- **Visual review findings.** Reviewing these captures found the canopy-camera, bot-stacking and foot-chase problems listed under "Fixed during testing", and the time-scale capture bug. All are fixed; the clips were re-recorded afterwards.
- **No physical-device footage.**

## 7. Not yet verified (exact remaining device checks)

- [ ] **Two or more iPhones over the internet:**
  - create a code room on one, join with the code on another (Game Center `player_group` matchmaking);
  - Game Center friend invite and accept;
  - a full round with cart entry/exit, chase, tag, splash and finish;
  - rematch; host leaves mid-round.
- [ ] **Performance:** 60 fps on an iPhone 14-class device across 3+ consecutive rounds, plus memory and heat (Xcode Instruments). Also check the "Battery saver" graphics option on an older device.
- [ ] **Touch:** feel of the dynamic stick and the edge-sprint threshold, camera drag ownership, and button sizes on small iPhones. Safe areas on Dynamic Island devices and iPad (menu layouts were render-checked at 16:9, 4:3 and 19.5:9 on desktop only).
- [ ] **Controllers:** an MFi/Xbox/PlayStation controller on device, plus connect and disconnect mid-match with prompt switching.
- [ ] **System behaviour:**
  - The silent switch mutes the game (Godot's default *Ambient* audio session); check that the visual cues carry play.
  - Airplane mode: online is disabled with an explanation and practice works.
  - Background/foreground during a round.
  - Declined or interrupted Game Center sign-in.
- [ ] **TestFlight install** of a signed build: blocked on App Store Connect access (TESTFLIGHT_RELEASE.md).

## 8. Known limitations

- **Host trust.** The online host is a player's device. Results are host-authoritative but **not cheat-proof**, and host migration is not implemented: if the host leaves, the round ends without rewards.
- **Code rooms.** Code rooms use Game Center matchmaking with a `player_group` derived from the code. Players with the same code are matched together, but Game Center decides timing, which can take a few seconds. This has only been reasoned about from Apple's API documentation and has not been run on devices.
- **Desktop LAN.** Desktop LAN (ENet) exists for development and testing only and is not shown in iOS builds.
- **Lighting.** Night lighting was tuned on desktop screenshots, and brightness needs a check on a real iPhone screen.
- **Plugin export errors.** When Godot exports, GodotApplePlugins' extension logs about 76 "Class 'GK…' already has constant …" errors (duplicate enum constants). They are harmless duplicates and the build succeeds, but they will also appear in the device console.
- **Minimum device.** Godot's export marks the app `iphone-ipad-minimum-performance-a12`, so it installs on A12-class devices (iPhone XS/XR) and newer.
- **One unexplained Simulator crash report** (run 8, see section 4). It was not reproduced in run 9, and it needs watching in the first TestFlight sessions.
