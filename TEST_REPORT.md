# Test report: Ultimate Trifecta V1

This report records what was actually run, where, and what each result proves. The evidence comes from four sources, each labelled by what it is:

| Label | What it is | What it can prove |
|---|---|---|
| **Headless sim** | The real `MatchSim`/physics/rules code running headless (Godot 4.7.2, Linux), with scripted inputs or bots | Rules, ordering, validation, routes, bot behaviour |
| **Loopback net** | Host and up to 7 `NetSession` clients in one process, connected through an in-memory transport with simulated latency, jitter, loss and frozen endpoints; each client runs its own `MatchController` prediction | Protocol, prediction/reconciliation, lag compensation, reconnect, host loss |
| **Desktop UDP** | Separate Godot processes (1 host + N clients) on one Linux machine over real UDP (ENet), each shaping its outbound traffic with latency, jitter and loss, playing full rounds with automation input | Multi-process networking across full rounds; *not* iPhones, *not* the Game Center transport |
| **CI iOS** | GitHub Actions `macos-26` runner: Xcode project export, unsigned arm64 device archive, x86_64 Simulator build and run | That the iOS project compiles and links for device, and launches in the Simulator; *not* device performance |

**Not done: no physical iPhone or iPad was available, so nothing has been device-tested.** No two-iPhone Game Center session has been run. See "Not yet verified".

## 1. Automated tests

Run them with `tools/run_tests.sh`. CI runs the same suite on every push (job "Rules, simulation and network tests").

The latest full local run: **51 tests, 799 checks, 0 failures**. That is 48 tests / 758 checks in the full suite at `58436b9`, plus the 3 anti-camping tests / 41 checks added afterwards. CI test job on `58436b9`: success.

| Suite | Tests | What they exercise (behaviour, not constants) |
|---|---|---|
| `test_rules` | 11 | All 20 three-of-six combinations and their 6 orders; route-table fairness; seeded target pick with no immediate repeat; fair role rotation and preferences; respawn pad choice; tag geometry; rewards (unique captures, no idle-survival reward, practice ×0.5); level curve; input wire format; reward ledger paid once per match ID |
| `test_sim` | 19 | Every curated combo × all 6 orders; duplicate and inactive splashes; automatic resurfacing (no hiding in water); 6 s capture timing with stamps kept and role kept; return to the dorm before the first stamp and to the 3rd water after three; ~2 s protection; tag reach, cooldown and walls (no tag through a wall); tag role/state validation; **same-tick finish beats tag**; 4th runner ends the round immediately; timeout and deadline-tick finish; cart seat race and wrong-role entry; cart drive, safe exit and post-exit tag lockout; bump stumble without chain or capture; gadget single use and ownership; splash bomb slows a cart briefly; reconnect resume and reservation expiry; out-of-bounds recovery grants nothing; finished runner out of play; movement numbers; spotted cue needs line of sight |
| `test_camping` | 3 | Two campers at any water's exits/pads cannot cover every exit; the respawn pad is ≥ 15 m from both (worst case measured 20.7 m); an in-play respawn lands away from two campers; dorm doors are ≥ 15 m apart (18 m); carts driven flat out at the dorm from 4 directions are stopped by bollards 17–54 m from the nearest door |
| `test_net` | 13 | Snapshot size and round-trip; lobby join/ready/start; match sync at 100 ms, 150 ms + 5% loss, and 300 ms + 10% loss RTT; capture reaching the client, and client-patrol lag-compensated tags; clean and silent host loss; reconnect resumes slot and progress; late join spectates then plays; rematch cleanup; duplicate/reordered inputs and late snapshots; 8 humans online with no bots |
| `test_routes_bots` | 1 | Six runner bots, using the same movement code and inputs as players, complete every curated route with no pursuit |
| `test_smoke`, `test_compile` | 2 | Campus layout and builder load; every script compiles |

## 2. Route fairness (headless sim, bots)

- **Method.** Six runner bots, using the same input limits as players, run each of the 14 curated combinations with the Night Watch held idle. Raw output: `docs/test-data/route_bot_times_run.txt`.
- **Result.** **84 / 84** bot runs finished.
  - Trip times ranged **103–128 s**, with a median of **116 s**.
  - The per-combination medians are within ±12% of each other.
- **Excluded combinations.** The 6 other combinations were left out because their estimated or measured trips fell outside that band.
- **Expected human times.** Bots take near-optimal lines with sprint management. First-time human players should land in the requested 2–3 minutes: rough estimate 2:10–2:40, which still needs **device playtests** to confirm. That leaves 1–2 minutes of the 4-minute round for chases and captures.

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

## 4. iOS build (CI iOS)

| Step (`.github/workflows/ios.yml`) | Result |
|---|---|
| Godot 4.7.2 export to Xcode project (bundle `com.idlery.ultimatetrifecta`, Game Center entitlement) | ✅ |
| `xcodebuild archive` for `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO` (arm64 compile + link) | ✅ **project compiled** (unsigned) |
| Simulator build (x86_64; Godot 4.7.2's simulator slice is x86_64 only) | ✅ |
| Simulator launch (run 3, iPhone Air simulator, iOS 26.2 runtime, Xcode 26.6) | ✅ The app installs, launches and renders the title screen (Game Center skipped with `--no-gamecenter`, since the runner has no Apple account). During the 4-minute bot-driven practice launch, the screen moved from the splash to a static loading-sized frame and then to large 3D frames after ~3.5 min, but too slowly to confirm play visually (see note). No crash reports were produced. |
| Signed archive / upload | ⏸ not run: no App Store Connect credentials (see TESTFLIGHT_RELEASE.md) |

Godot 4.7.2's simulator slice is x86_64, so the app runs under Rosetta on a virtualised Apple-silicon runner. It also falls back to an OpenGL ES 3.0 context there (the console says "Setting up an OpenGL ES 3.0 context"), while devices use Metal.

As a result, the Simulator produced a new frame only every few seconds: consecutive screenshots 15 s apart were often identical. This run proves that the app launches and that the iOS build of the game code runs. It says nothing about iPhone frame rate.

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

## 6. Visual and audio evidence

Desktop captures are listed in docs/media (added in the following commit).

## 7. Not yet verified (exact remaining device checks)

- [ ] **Two or more iPhones over the internet:**
  - create a code room on one, join with the code on another (Game Center `player_group` matchmaking);
  - Game Center friend invite and accept;
  - a full round with cart entry/exit, chase, tag, splash and finish;
  - rematch; host leaves mid-round.
- [ ] **Performance:** 60 fps on an iPhone 14-class device across 3+ consecutive rounds, plus memory and heat (Xcode Instruments). Also check the "Battery saver" graphics option on an older device.
- [ ] **Touch:** feel of the dynamic stick and the edge-sprint threshold, camera drag ownership, and button sizes on small iPhones. Safe areas on Dynamic Island devices and iPad.
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
