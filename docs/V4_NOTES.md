# V4 implementation notes (version 1.3)

V4 follows the owner's first iPhone playtest of 1.2 (1). It answers nine
complaints: awkward touch buttons, occasional glitches, a blocky campus, a
lobby Emote/Dance that didn't seem to work, a poor loading screen with Idlery
branding, a Night Watch that was too hard, unclear capture/progress/winner
feedback, fixed roles in friend parties, and no host choice of Night Watch
count or rounds.

The implemented rules are in [RULES.md](../RULES.md). What was verified, and
how, is in [TEST_REPORT.md](../TEST_REPORT.md). The release state is in
[TESTFLIGHT_RELEASE.md](../TESTFLIGHT_RELEASE.md), and licences are in
[ASSET_LICENSES.md](../ASSET_LICENSES.md). Captures are in
[media/v4/](media/v4/README.md).

**What this document can and cannot claim.** Everything below was measured on
a desktop Linux machine, either headless or rendering through Mesa llvmpipe
(a software rasteriser), or in the iOS Simulator on CI. None of it says how
smooth the game is on an iPhone. Device numbers come from the in-game
diagnostics panel (see [Five-minute diagnostics check](#five-minute-diagnostics-check-owner)),
and no device measurement exists yet.

## Issue register

| # | Owner's complaint | Root cause found | Fix | Evidence |
|---|---|---|---|---|
| 1 | Touch buttons felt awkward | V3 sized buttons in canvas units, not points, so their physical size changed with the device. Night Watch: Jump was the big primary button and Tag was a smaller button 272 units from the edge. Tag disappeared whenever it was unusable, and Drive and the gadget button popped in and moved the others. The layout was rebuilt every frame. A full-screen touch surface on the layer above the HUD **swallowed taps on Pause** (a real bug). | `TouchLayout`: sizes in iOS points (≥ 44 pt), two clusters anchored to the safe area and kept below the HUD band. Fixed slots per context: Tag is the Night Watch's primary and is greyed, not hidden. Hit padding never overlaps. HUD regions fall through to the HUD. **Settings › Controls › Edit layout**: drag, size, opacity, Mirrored, Reset, Try it. | `test_touch_layout` (14 tests). `src/dev/input_fallthrough_check.tscn` in a real window: the V3 surface blocked the Pause tap; the V4 surface passes it. Captures: `media/v4/touch/`. |
| 2 | Occasional glitches | Each round built the whole campus, collision and every character inside one frame (`MatchController._ready`, ~650 ms), at the first round and **every rematch**. Jolt only builds a real height field from a square map, so the 321×301 ground fell back to a ~190k-triangle mesh (161 ms). Each shape added to a body already in the tree rebuilt it (45 ms). Portraits used `get_image()` readback (a GPU→CPU sync). Effects compiled on first use (first splash or tag). An emote timer bug (see 4). A dead HUD node leaked one orphan per round. | Staged preparation under the loading screen (9 ms budget per frame); the campus is kept between rounds; square cached height field (6 ms); bodies get their shapes before entering the tree (4 ms); portraits copied on the GPU into an atlas; `Fx.warm` fires every effect once while loading; the leak was removed. The diagnostics panel attributes any remaining stall to a marker. | `test_loading` (bounded steps, campus reuse, ten rounds flat), `test_portraits`, `test_diag`. [Performance](#performance) table. |
| 3 | Blocky campus | V3 pines were three stacked 7-sided cones and broadleaf crowns were low-poly blobs, both on 6-sided trunks. Lamps and bollards had 6–8 sides. The ground had one colour per 2 m quad, with no light or shade from nearby objects. | New campus art kit: rounded broadleaf and layered pine trees (2+2 variants, near/far LOD, MultiMesh per region), baked AO and warm lamp light, smooth lit ground, framed windows, quoins, cornices, bracketed porches, turned lamps and bollards, chamfered benches, rounded fountain and dome, flower beds, soft hedges and rocks. Colliders unchanged. | Matched V3/V4 route captures from 7 identical cameras: `media/v4/campus_before/`, `campus_after/`, `campus_compare/`. |
| 4 | Lobby Emote/Dance didn't seem to work | An emote's 1.8 s reset timer could cancel a **newer** emote started inside that window, so Dance after Wave was cut short. A guest's emote waited for the host's echo, then restarted. The ready response could play over the chosen emote, and re-selecting the same emote did nothing. | Emotes are owned by expiry (a stale timer can't cancel a newer one). Reselection restarts the emote. A guest's own emote plays at once, and the host's echo is skipped. The ready response plays once and never over an emote. Added an emote picker with icons and **Try moves** (local only). | `test_emotes`: every emote from host and guest, reselection, repeat, ready, outfit change, picker, teardown. |
| 5 | Loading looked bad; Idlery logos and "Powered by Idlery" | The repository and the built app contain no Idlery logo or text: only the bundle ID `com.idlery.…` and a reserved-name list. The CI audit greps the built `.app` and finds none. V3 launched with a character render (`splash.png`), then a loading card that froze while the round was built in one frame. TestFlight's own install and launch pages show the developer/seller name of the account; the app cannot change those. | A launch image rendered from the loading screen's own drawing code (Trifecta droplet motif and wordmark, scale-to-fit, same background), a boot curtain over the title's first frames, and an animated loading screen showing real stages and "Waiting for players · a/b ready" that fades out when the round is live. | CI launch audit (`launch_assets.txt`, `branding_text.txt`, early launch frames). Captures: `media/v4/loading/`. |
| 6 | Night Watch too hard | In V3 the first close-looking press at 2.6 m **always missed**: the wind-up cost 40% speed and the lunge kept its facing while the runner moved on. A runner cycling sprint averaged ~5.8 m/s against the Night Watch's 6.2 m/s, so straight chases lasted ~18 s. | Target assist (≤ 40° snap within a ±50° cone and 4 m, then tracking at 240°/s; reach and the hit test unchanged). Wind-up keeps 90% speed; lunge 9.0 m/s; Night Watch 6.6 m/s; runner sprint 7.4 m/s. Tag-ready cue (glowing button, amber ring). Guided Night Watch practice. | `test_pursuit`: 11 scenarios on V3 and V4 values with the same harness (`docs/v4/pursuit_before.txt`, `pursuit_after.txt`). The table is in RULES.md. |
| 7 | Unclear capture, progress and winner feedback | V3 showed "CAUGHT! 6" with "Your splashes are safe" and a "0 / 4 home" counter. It didn't say who caught you or that you were protected after returning, and the tagger got a short toast plus a feed line. The Night Watch had no objective in its own terms (how many it must stop, how many are still out). Nothing showed the round or series, and results had no series standings. | One capture contract: "Caught by … · back in 6…", "Your splashes are safe", where you return, and "Protected · 2"; the tagger gets one "Tagged …! · N catches". The HUD shows a role badge with Round x of y, "Home n/N" and the Night Watch objective "Stop N home · X out". Results give the outcome and the reason, your contribution and the series standings. Tappable full map. | Captures `media/v4/match/`; `test_series`. |
| 8 | Friend-party roles should be random; solo should let you choose | V3 used saved role preferences. | Fair random rotation on the host: round 1 is an equal draw, later rounds favour fewer Night Watch turns, and at least one human stays a runner. One human: Night Watch with probability (watch ÷ 8). Practice: Runner, Night Watch or Random. | `test_series` (equal draw, rotation, constraints, one-human policy). |
| 9 | Host picks Night Watch count and multiple rounds | Not implemented. | Party settings: Night Watch 1/2/3 and rounds 1/3/5, with required home = ceil(2 × runners / 3). Settings are locked per series, with an immutable `RulesConfig` per round. The series flow covers round results, ready for the next round and final standings by Round Wins. Rewards are paid once per identity and round. | `test_series`, including a full 3-round series over the loopback network and reward eligibility. |

## Smoothness and diagnostics

**Settings › Diagnostics (beta)** is off by default (`game/src/core/beta_diag.gd`).
When on, it keeps in memory only:

- **Frame intervals** per context (menu, lobby, loading, match, results): histograms and p50/p95/p99. Stalls over 50 ms are attributed to the marker in the 2 s before them (`load_begin`, `campus_built`/`cached`/`prepared`, `countdown`, `splash`, `tag`, `tag_miss`, `correction`, …).
- **Renderer measurements**: the renderer's own GPU and CPU time for the main viewport, reported as "unavailable" when the driver gives nothing. Also draw calls, primitives and memory.
- **Network**: round-trip time and prediction corrections (average, max, count over 25 cm).
- **Device state**: thermal state (current and worst) and Low Power Mode, read through `UTShare` from iOS `ProcessInfo`.

"Share summary" opens the share sheet with plain text. It contains no player
names, room codes or Game Center identifiers (`test_diag` checks this).
Nothing is written to disk or sent anywhere else. An optional small readout
shows the frame interval live.

What each number means is written in the file header. Notably, the
**frame interval** is CPU time between engine loop iterations: at the 60 fps
cap (Standard) the ideal is 16.7 ms, at 30 (Battery Saver) 33.3 ms. It is not
GPU time and not the display's present time.

### Performance

All numbers below were measured on the desktop test machine's CPU or on
llvmpipe engine counters. They show relative change in this code, **not
device smoothness**. Device rows are empty until measured.

| Measurement | V3 code | V4 code | Where |
|---|---|---|---|
| Round preparation, first round | Built in **one frame** in `MatchController._ready`, ~650 ms on V3 art | 688 ms of work over 42 frames under the loading screen; longest single frame of work 57 ms (V4 art) | Headless test run (`test_loading`) |
| Round preparation, rematch / next series round | The same one-frame freeze every round | **17 ms** total: the campus look is kept between rounds | Test machine CPU |
| Ground collision shape | 161 ms (Jolt mesh fallback, ~190k triangles) | 6 ms (square 321×321 height field, cached) | Test machine CPU |
| Collision bodies | 45 ms | 4 ms | Test machine CPU |
| Campus visual build | — | 620–690 ms total, staged across frames, once per session | Test machine CPU |
| Portrait updates | `get_image()` readback per portrait (GPU→CPU sync) | GPU copy into an atlas, no readback; queue bounded; MSAA matches the main view | Code path |
| Visible primitives in a Night Watch round | 179–253k (V3 art) | 238–307k (V4 art) | llvmpipe engine counters, capture scenario |
| Draw calls in the same scenario | similar | similar (trees are MultiMesh per region) | llvmpipe engine counters |
| Nodes / objects after 10 rounds | — | flat (no growth from round 2 to 10) | `test_loading` |
| **iPhone frame interval p50/p95/p99, stalls, GPU time, thermal** | not measured | **awaiting measurement** | Settings › Diagnostics on a device |

Desktop llvmpipe frame rates are meaningless for a phone and are not quoted.
No video in `media/` is frame-interpolated.

## Touch controls (detail)

- **Units:** points, converted per device (`units per point = screen scale ÷ pixels per canvas unit`). `--emulate-phone=1.85` and `--emulate-safe=L,T,R,B` reproduce an iPhone 14 Pro (notch insets) on the desktop.
- **Slots per context:**
  - Runner: Jump/Dive primary, Gadget, hold-Sprint.
  - Night Watch: Tag primary, Jump, and a reserved Drive slot.
  - Cart: Gas, Brake, and a small separate Exit.
  - Spectating: Next, Cheer.

  Contextual buttons appear in their own reserved slots, so nothing shuffles.
- **Feedback:**
  - A ring on the stick shows the sprint threshold.
  - Tag glows when ready, and an arc shows its cooldown or cart-exit lockout. A Tag press while not active is ignored.
  - An arc shows the gadget cooldown.
- **Layout editor:**
  - Drag the stick or the action cluster (per role).
  - Size 0.85–1.25 and opacity 0.45–1.0.
  - Mirrored flips the anchors; Reset; Try it shows a live multi-touch preview and sends nothing to a game.
  - Layouts are saved as normalized anchors (`touch_layout_v2`). V3 size and mirror settings migrate. A layout loaded on another device is clamped into its safe area, and an impossible one falls back to the default.

## Campus art (detail)

- **MeshKit** (`game/src/map/mesh_kit.gd`): raw arrays with per-vertex normals and colours, plus smooth primitives (`revolve`, `lobe`, `soft_blob`, `chamfer_box`). Emission and sway moved from UV2 to `CUSTOM0`, which resolves V3's UV2 conflict.
- **CampusKit** (`campus_kit.gd`): the tree variants and a 2 m light field. The field holds AO around trunks, walls, buildings and hedges, plus warm light from lamps, door lights and lit windows. It is baked into vertex colours, with **no runtime lights added**.
- **Draw cost control:**
  - Trees are drawn as MultiMesh per 128×120 m region. Near trees (≤ 80 m) cast shadows; far trees use a lighter mesh without shadows.
  - Small props and window frames live in per-chunk detail meshes drawn within 100 m.
- Comparison captures are taken from the same seven cameras on V3 (`654b0a8`) and V4: the dorm door, quad path, pond, grove, garden, fountain and return.

## Characters (detail)

- Dark skin tones read poorly under night lighting. The character shader adds a small, luminance-weighted self-light to skin, so darker tones keep facial detail. The lift fades out as tone lightens and is zero for the lightest tones. Lineup captures before and after under campus lighting: `media/v4/characters/`.
- **Mesh refinement** in the generated asset (`tools/character/parts.py`, rebuilt with Blender's `bpy` 4.5.4; the unchanged sources first reproduced the 1.2 `runner.glb` byte for byte). The rig, weights, clips and appearance catalog are unchanged, so saves and the network encoding are unaffected.
  - **Nightcap.** V3 swept the cap along a polyline, so it creased at every control point. It is now a smooth curve through the same points, with a denser brim. Close-ups also showed the scalp beside the fold, for two reasons:
    - The tip's spring chain was rooted at `hat1`, and with gravity the wide middle of the cap sagged into the head. The chain now starts at `hat2` (gravity 0.2, stiffness 1.8), so only the tip swings.
    - The fold crosses itself, because the cap is wider than its fold is tight. The cap's rings are kept 3 cm outside the head shell, and the part is drawn double-sided (`character_two_sided.gdshader`, sharing `character.gdshaderinc`), so the fold reads as a fabric crease.
  - **Cuffs, collars, belts and rims:** 10-sided round cross-sections (were 8), with more segments around. The plush cuffs sit on the sleeve ends.
  - **Sleeves and legs** have 16 sides (were 14) and the torso 28 (were 24). Hands and thumbs are rounder. The shoulder caps sit a little lower and flatter, so they round into the sleeve instead of standing up like pads.
  - **Robe:** a softer bell and an open sleeve, with a shaded inner face down to the wrist and a rolled cuff. Before, it was a flat end disc inside a thin 20 cm hoop.
  - **Hair:** the bob's rolled hem is tucked into the hair (no helmet lip). The space-buns centre-part swoops lie on the hair instead of standing off it like wires.
  - **Budget:** a typical outfit (base, pajamas, nightcap, slippers) is 23.4k triangles, up from 19.7k. The Night Watch (uniform, base, mustache) is 20.5k, up from 18.3k.
  - **Evidence:** `media/v4/characters/parts_before.jpg` and `parts_after.jpg` (12 matched close-ups: same cameras and pose), `hero_before|after.jpg`, `group_after.jpg`, `outfits_after.jpg`.
- **Not changed:** animation timing. Gait, contact timing and the splash sequence are as in V3. The Night Watch's new foot speed (6.6 m/s) plays through the same speed-matched gait blend (playback rate = ground speed ÷ metres per cycle).

## Lobby and emotes (detail)

- **Roster:** compact, with a ready count. A host settings sheet (Night Watch 1/2/3, rounds Single/3/5, Reset to recommended); guests see it read-only, with one summary line.
- **Emotes:** picker with icons. **Try moves** (Idle, Run, Sprint, Jump, Dive, your move) is local only. Tap your runner to play your move.
- Results have host and guest flows; see the issue register.

## Night Watch (detail)

The pursuit harness is `game/tests/test_pursuit.gd`. It uses the real
simulation and physics, and a human-like chaser: 0.25 s camera lag, pressing
Tag at a "looks close" 2.6 m, or only on the cue. It also covers input delay,
a 250 ms hitch, a cart interception and a sprint burst. The same harness ran
on the V3 values (`pursuit_before.txt`) and on V4 (`pursuit_after.txt`).

Two of the before-scenarios fail the V4 expectations, by design:
- Pressing on the cue escaped, because V3 had no cue.
- The 8 m jog needed more than one press.

Order of fixes: control and aim first, then speed. A 2 s sprint still gains
about 1.5 m, so the runner keeps real escapes.

**Assist and cue are host-side.** The client sends the press. The host
picks the runner, turns at most 40°, tracks it and validates the hit with the
unchanged reach, line-of-sight and lag-compensation rules. The tag-ready cue
is the host's prediction, sent only to that Night Watch.

## HUD and map (detail)

- **Top left:** role badge (icon and role) with "Round 2 of 3" (or Practice).
  - Night Watch: an objective chip, "Stop 4 home · 5 out", with their catches.
  - Runners holding all three stamps see "Return to the dorm".
- **Top centre:** "Home n/N" from the round's settings.
- **Maps:** the minimap is tappable (or Map: M / View / Select / Create / −). The full map has:
  - a legend;
  - your team (state, stamps);
  - Home n/N and the number still out;
  - Close / Back.
- **While the map is open:** touch controls are set aside, and the map closes itself when the round ends.
- **Opponents:** shown only as **last seen**, as defined in RULES.md.

## Creator thumbnails (detail)

Item tiles show a cached picture of that item on your runner, in the draft's
colours. Each uses a body, head or feet framing and is rendered a few frames
apart through the portrait atlas, so there is no live 3D view per tile. A
newer draft supersedes a tile's queued render, and a finished render lands
only on a tile still showing that exact look. Categories sit in one row that
scrolls sideways.

## Startup and loading (detail)

- **Launch image:** `game/assets/icon/launch.png`, rendered by `tools/make_launch_art.sh` from `src/ui/loading_screen.gd`'s own motif drawing.
  - The Godot boot splash and the generated iOS launch storyboard both use it, scaled to fit on the same background colour.
  - `BootCurtain` holds that frame over the title screen's first frames, so there is no flash.
- **Loading screen:**
  - Animated Trifecta motif (three droplets) and wordmark.
  - Real stage text ("Building the campus", …), then "Waiting for players · a/b ready".
  - It fades out when the round is live: on the host when every load is complete, on a guest at the first snapshot.
- **CI** (`ios.yml`) audits the launch assets and records the paths of any text file in the built app that names Idlery (`branding_text.txt`). It also captures early launch frames in the Simulator.

## Information and network audit

- **Maps and HUD** show opponents only as last seen (line of sight and view range from your own head, then 5 s fading).
- **The network still carries more:** opponents within 45 m, or 90 m in line of sight, for smooth movement. This is presentation policy, not anti-cheat secrecy, as RULES.md states.
- **Night Watch private snapshot:** carries its own tag-ready flag and the assist's chosen runner, who is always already in its line of sight.
- **Protocol 5** adds:
  - party settings in LOBBY;
  - settings and series state in START;
  - SERIES standings;
  - load-ready flags;
  - the tag cue.

  A version mismatch shows "Update the game to join".
- **Shared diagnostics** never contain names, room codes or Game Center identifiers (`test_diag`).
- **Rewards and Round Wins** are keyed by match ID and player identity, and are paid at most once.

## Protocol, settings and save migration

- **Protocol 5** (was 4). It carries:
  - party settings in LOBBY;
  - the locked settings and series state in START;
  - SERIES standings;
  - load-ready flags;
  - the Night Watch's tag-ready flag and aimed runner in the private snapshot block.

  1.2 and 1.3 cannot share a party: the older side sees "Update the game to join". Everyone in a friend party needs 1.3.
- **Saves** keep the same schema; nothing is migrated destructively.
  - `touch_layout_v2` (new) holds the touch layout as normalized anchors. On first load it is built from the V3 settings `button_size` and `touch_layout` (mirror), which are left in place.
  - A garbled or impossible saved layout falls back to the default (`test_touch_layout`).
  - New settings: `practice_role` (Runner / Night Watch / Random, practice only), `diagnostics` and `diag_overlay` (both off by default).
  - `role_pref` stays in saves and in the protocol hello for compatibility, but the role draw ignores it, and its menu is gone.
- **Rewards** are applied once per match ID and player identity. A round the player was mostly away from is recorded as seen and pays nothing. A round with an unknown length never takes a reward away.
- **Party settings** are not saved between app launches. A new party starts at the recommended 3 rounds with 2 Night Watch, and Play again keeps the current party's settings.

## Five-minute diagnostics check (owner)

1. On the iPhone: **Settings › Diagnostics (beta)** → turn on **Collect performance diagnostics**. Optionally turn on the small frame-time readout.
2. **Solo practice as a Runner**: play about two minutes, including a splash.
3. **Solo practice as the Night Watch**: chase a runner and tag, and drive a cart once.
4. If a second phone is available, **Play with Friends**: open a party, try an emote, start a 3-round series and play into round 2.
5. Back in **Settings › Diagnostics (beta)** → **Share summary** → send it to yourself (Notes or Messages). The live line shows minutes collected, stalls over 50 ms and the in-play p95.

What the summary answers:
- **In-play frame interval.** p95 near 16.7 ms on Standard means steady 60 fps; near 33.3 ms on Battery Saver means steady 30.
- **Hitches.** Each stall over 50 ms is listed with what was happening just before it.
- **Heat.** Whether the phone got hot (thermal state).
- **Network.** Round trip and corrections in a party.

## What to Test (TestFlight 1.3)

- **Startup:** the launch screen and loading screen show the Trifecta motif, with no stretched art and no text other than the game's own. (TestFlight's own pages show the developer account's name; the app doesn't.)
- **Touch:** Jump/Dive, Tag, Gas, Brake and Exit are all reachable with thumbs. Pause is tappable. **Settings › Controls › Edit layout** lets you move and resize, and Try it previews the result.
- **Night Watch:** tag runners. Tag glows and an amber ring appears when a press would land. Try the guided Night Watch practice.
- **Getting caught as a runner:** "Caught by … · back in 6…", your splashes kept, then "Protected".
- **HUD:** role and "Round x of y", "Home n/N", and the map (tap the minimap). It shows last-seen markers only.
- **Lobby (host):** choose 1/2/3 Night Watch and 1/3/5 rounds. Roles are random each round. Emotes and Try moves play every time.
- **A 3-round series:** round results, Ready for round N, final standings by Round Wins.
- **Campus look:** trees, buildings and lights. Report any spot that still looks blocky or any slowdown.
- **Creator:** pictures on item tiles.
- **Optional:** the five-minute diagnostics check above, and share the summary.

## Not done / limits

- **Device performance is unmeasured.** No iPhone or iPad was available. The diagnostics panel exists to measure it.
- **TestFlight's seller name.** The app cannot change how TestFlight and the App Store display the developer account's name.
- **Bots** play the new rules, but bot difficulty was not retuned beyond the guided Night Watch practice, where runner bots are gentler.
