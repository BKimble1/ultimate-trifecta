# V7 implementation notes (version 1.6)

V7 is a focused repair and refinement pass on the 1.5 beta: Pause, Resume and
Leave match (priority zero); forward movement wandering left/right on the
touch stick (the owner's "stick drift"); compact Locker, Emotes, Season Pass,
Friends and Settings screens with better reward art; goggles and character
refinement; slightly louder lobby music.

Everything here was measured on desktop Linux (headless, or the Mobile
renderer on Mesa llvmpipe) or in CI, with **emulated touches**: Godot
`InputEventScreenTouch`/`ScreenDrag` events (what iOS delivers) parsed by
`Input` at the controls' rendered coordinates, on phone-shaped canvases.
**No iPhone or iPad was available to this work**; what still needs a device
is listed at the end and in What to Test.

## Defect register

Categories: **UI/input** (taps, ownership, overlays), **touch movement**,
**camera**, **controller arbitration**, **lifecycle**.

### Pause, Resume and Leave (priority zero)

| # | Trigger | Evidence | Category | Cause | Fix | Verification |
|---|---|---|---|---|---|---|
| P1 | Tap Resume, a slider or Leave match in the pause menu | Reproduced with real touches at the buttons' rendered centres (`test_pause_input::test_menu_buttons_take_taps` failed on 1.5): the taps reached the gameplay touch surface, not the menu | UI/input | The menu was a panel on the HUD's CanvasLayer **5**; the full-screen gameplay touch surface is CanvasLayer **6**, so GUI picking gave every tap inside the panel to the stick/camera (the surface only excluded the Pause button, minimap and chat regions) | The menu and its leave confirmation live on their own modal CanvasLayer **8** with a dim backdrop that stops background input (not its own buttons). One owner list for match overlays (`map`, `chat`, `pause`, `confirm`) hides and cancels the touch surface while anything owns input and restores it only when the last overlay closes | All 9 `test_pause_input` tests drive real touches; Resume, sliders, Leave, Stay and Leave-confirm take normal taps |
| P2 | Tap Pause | Owner report ("Pause button often doesn't work"); a touch in a 12-unit ring around the button did nothing (probe) | UI/input | The reserved Pause/minimap regions were the buttons' rects **grown by 12**, measured once from a deferred resize before containers sorted: a touch in the ring missed the button and was refused by the surface, and after a HUD change the reservation could be stale | Regions are the buttons' exact rects, re-measured every frame from the settled layout (HUD and surface layers are untransformed, so the HUD's canvas rects are the surface's local coordinates) | `test_pause_region_matches_the_button_in_every_layout` (standard and mirrored: reserved == button rect, on screen, ≥ 44 pt, taps 3 px inside both corners open the menu) |
| P2b | Hypothesis: a second finger can't press Pause because the engine emulates the mouse from the first finger only | Probe on Godot 4.7.2: a Button takes `InputEventScreenTouch` from any finger index | — | **Refuted**: Buttons press from any finger | None needed for Pause. The **minimap** (a custom Control) did read only the emulated mouse, so a second finger couldn't open the map: it now reads touches from any finger and ignores the first finger's mouse twin | `test_pause_while_another_finger_moves`, `test_map_pause_background` (second-finger minimap tap) |
| P3 | Practice: open the menu | 1.5 menu said the round continues for everyone even offline; nothing stopped | Lifecycle | No offline pause | Practice and the tutorial pause the SceneTree (sim, bots, physics, timers, animation); the HUD, menu, audio, controls and diagnostics run ALWAYS. The tree is unpaused before any scene change (Leave, scene exit). App backgrounding pauses Practice; coming back leaves it paused until you choose | `test_practice_freezes_and_resumes_without_a_jump` (sim tick frozen for 120 frames, nothing moves; Resume continues ≤ 2 ticks/frame, no catch-up) |
| P4 | Online: open the menu | Brief §3 | Lifecycle | — | Never pauses the shared round: "Online match continues.", local input neutral (no movement, no edges), no immunity; host keeps simulating and sending, guests keep receiving | `test_pause_online` (loopback rig: host and guest; host ticks +50 in 60 frames, guest snapshots +30; guest Leave fires once, makes no finish, result or reward; host party carries on; results arriving close the menu and confirmation, Pause stays shut) |
| P5 | Leave | Brief §3 | Lifecycle | — | Asks first with the real consequence (Practice: nothing earned; host: ends the match and the party for everyone; guest: the others play on, nothing earned); fires once; uses the existing quit lifecycle | `test_twenty_cycles_then_leave` (20 × open → slider → Resume and open → Leave → Stay: 40 opens, 40 closes, 0 quits; then Leave twice-tapped quits once; the next match starts unpaused and its Pause works) |
| P6 | Resume while a finger was down / Resume tap itself | Brief §3.7–8 | UI/input | — | Opening and closing cancel every gameplay pointer, queued edge, sprint, throttle and look; a 3-frame input grace after the last overlay closes; a finger held from before the menu never moves the runner; Resume never queues Jump/Tag | `test_no_stale_finger_or_jump_after_resume`, `test_night_watch_cart_and_tag` (Gas held → Pause releases the throttle → after Resume the old finger doesn't drive, a fresh press does; Pause/Resume queue no edges for runner or Night Watch) |
| P7 | Map, chat, Back, pause key | Brief §3.9 | UI/input | 1.5's chat and map each toggled the touch surface directly; closing one could bring controls back under another | Policy: gameplay < map or chat drawer < pause menu < leave confirmation. The top one owns input; Back closes it; the map covers Pause (Close, then Pause); the pause key over the map closes the map first; closing one never restores controls while another owner remains | `test_map_pause_background` |

### Forward movement wandering left/right ("stick drift")

Measured with `tools/stick_probe.sh` (`game/tests/test_stick_probe.gd`): a
Practice round on a 1559×720 canvas (812×375 pt), runner on the longest clear
straight of the campus (nav grid open, physics swept with 0.55 m spheres),
bots idle, scripted touches through TouchControls → Controls → the match
command → sim and the real FollowCamera. The same probe file ran on the
build before the fix (a worktree at `b34566f`) and after. Raw tables:
`docs/v7/stick/probe_before_60.txt`, `probe_after_60.txt`, and after at
30 and 120 fps render (`probe_after_30.txt`, `probe_after_120.txt`, physics
60 Hz; results match 60 fps).

| # | Cause (measured) | Fix |
|---|---|---|
| S1 | **Clamped stick origin.** `touch_down()` stored the dynamic stick's centre clamped on screen (`spawn_center_for`) but read deflection from it, so a thumb landing within ~108 units (~56 pt) of the left or bottom edge started deflected: at the bottom-left corner **full deflection from touchdown alone**, and an exact vertical push ran mostly sideways (31 m off the line in 6 s; the mirrored layout the same). | The **logical origin** is the touchdown point (touchdown is always neutral). The ring is drawn at that origin clamped on screen, and the knob at ring + the real offset (`TouchRouter.knob_pos()`), so what is drawn is what is read. The fixed-stick option keeps its contract: a touch off its fixed centre deflects. |
| S2 | **Camera feedback loop.** On foot the camera turned at a *fixed rate* (~1.4 rad/s × speed factor) toward the travel velocity whenever input was within 22° of forward. Movement is camera-relative, so any lean over ~1.3° made the camera chase the heading and the heading chase the camera: a 6° lean turned the camera **−107° in 6 s** (the runner circled); a 3° lean held 15 s, −81°; even exact forward picked up turns from collision/velocity noise (+17° in one run). With recentering off, the same leans ran straight-ish. | On foot the camera follows the steering the player **intends** — the stick's angle off straight ahead — **in proportion** (gain 0.8 /s), only beyond 4° and inside the 22° band (tapering at its edge), never from velocity (collisions and wall slides are not a new heading). Carts keep heading-based recentering (they steer themselves). Frame-rate independent. |
| S3 | **Thumb lean and wobble.** After S1/S2, a natural lean still steers by its full angle. | A narrow, continuous straight-ahead tolerance around forward and back: within **6°** the direction is exactly on the axis, then it blends linearly back to the thumb's own angle at **16°**; magnitude never changes; no snap, no hysteresis to reset. Diagonals, strafe and reverse untouched. |
| S4 | **Ownership.** `Controls.get_move()` chose touch only when its output was non-zero, so a pad drifting 0.25 walked the runner under a thumb resting in the dead zone; the pad's right stick turned a touch player's camera (−10° in 3 s). | A finger on the stick owns movement even at zero output (`touch_stick_owned`). While touch is the device, controller sticks are not read at all; a deliberate push (≥ 0.55, no fingers down) or any button switches to the controller as before. |
| S5 | **Spare finger.** A second finger landing in the stick zone becomes a camera drag (the existing contract); touch-screen jitter on a resting finger turned the view. | A look pointer that starts in the stick zone must move **24 px (~3 mm) net** from where it landed before it turns the camera; only the travel beyond that counts (no jump). The look side of the screen stays immediate. |
| S6 | **Base follow** (beyond 1.6 R) — checked, not a cause | It moves the origin along the thumb's own direction, so the direction never jumps (largest step < 1°). Kept: compared with no follow (`4c`), a push past the rim eased back to 0.9 R from touchdown stops the runner with follow (the ring visibly followed) and keeps running without; direction is identical either way. |
| S7 | **Online correction** — checked, not a cause | Exactly straight commands from a guest over the loopback rig (30 ms ± 5): host authoritative and guest predicted paths stay within 0.25 m of the line, on both builds (`test_stick_round::test_online_straight_commands_stay_straight`). |

Before → after (60 fps; full rows in the files above):

| Case | Touchdown output | Sideways (peak) | Camera turn, no look | Forward | Travel vs camera | Stop after lift (ticks) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 centre, exact vertical | 0.00 → **0.00** | 0.0 m → **0.0 m** | +0° → **+0°** | 37.3 m → **37.3 m** | +0° → **+0°** | 7 → **7** |
| 1b centre, exact vertical, recenter off | 0.00 → **0.00** | 0.0 m → **0.0 m** | +0° → **+0°** | 37.3 m → **37.3 m** | +0° → **+0°** | 7 → **7** |
| 1c centre, 60% vertical (jog) | 0.00 → **0.00** | 0.0 m → **0.0 m** | +0° → **+0°** | 16.0 m → **16.0 m** | +0° → **+0°** | 4 → **4** |
| 2 bottom-left corner, exact vertical | 1.00 → **0.00** | 31.1 m → **0.0 m** | +0° → **+0°** | 5.3 m → **37.3 m** | -80° → **+0°** | 6 → **7** |
| 2b left edge mid, exact vertical | 0.83 → **0.00** | 24.3 m → **0.0 m** | +0° → **+0°** | 28.4 m → **37.3 m** | -40° → **+0°** | 7 → **7** |
| 3 centre, forward + wobble | 0.00 → **0.00** | 5.5 m → **0.0 m** | -15° → **+0°** | 35.7 m → **37.3 m** | +2° → **+0°** | 7 → **7** |
| 3b centre, forward + 6deg lean + wobble | 0.00 → **0.00** | 8.5 m → **0.8 m** | -107° → **-0°** | 6.2 m → **37.3 m** | +6° → **+1°** | 7 → **7** |
| 3c 6deg lean, recenter off | 0.00 → **0.00** | 3.9 m → **0.8 m** | +0° → **+0°** | 37.0 m → **37.3 m** | +6° → **+1°** | 7 → **7** |
| 4 long push past base-follow, ease back | 0.00 → **0.00** | 7.6 m → **0.0 m** | -39° → **+0°** | 20.0 m → **22.0 m** | -1° → **-0°** | 1 → **1** |
| 4b push along the rim side to side | 0.00 → **0.00** | 11.8 m → **2.0 m** | -17° → **-4°** | 27.3 m → **36.3 m** | +0° → **-0°** | 7 → **7** |
| 5 forward 15 s, 3deg lean, recenter on | 0.00 → **0.00** | 8.6 m → **0.0 m** | -81° → **+0°** | 6.5 m → **88.7 m** | +2° → **+0°** | 7 → **7** |
| 5b forward 15 s, 3deg lean, recenter off | 0.00 → **0.00** | 4.9 m → **0.0 m** | +0° → **+0°** | 88.6 m → **88.7 m** | +3° → **+0°** | 7 → **7** |
| 6 forward + spare finger, jitter, creep 0.05 px/f | 0.00 → **0.00** | 0.6 m → **0.0 m** | -2° → **+0°** | 26.4 m → **26.4 m** | +0° → **+0°** | 7 → **7** |
| 6 forward + spare finger, jitter, creep 0.40 px/f | 0.00 → **0.00** | 5.2 m → **2.4 m** | -22° → **-13°** | 25.6 m → **26.2 m** | -0° → **-0°** | 7 → **7** |
| 4c long push, base never follows (comparison) | n/a → **0.00** | n/a → **0.0 m** | n/a → **+0°** | n/a → **35.5 m** | n/a → **+0°** | n/a → **6** |
| 7 thumb resting in dead zone + drifting pad | 0.00 → **0.00** | 1.4 m → **0.0 m** | -10° → **+0°** | -0.1 m → **0.0 m** | +0° → **+0°** | -1 → **1** |
| 7b forward + drifting pad | 0.00 → **0.00** | 1.8 m → **0.0 m** | -10° → **+0°** | 20.4 m → **20.5 m** | -0° → **+0°** | -1 → **7** |
| 9 dorm start, exact forward out of the door, 8 s | 0.00 → **0.00** | 0.0 m → **0.0 m** | +0° → **+0°** | 49.1 m → **49.1 m** | +0° → **+0°** | 7 → **7** |
| 9b dorm start, forward + 4deg lean, 8 s | 0.00 → **0.00** | 15.4 m → **0.0 m** | -147° → **+0°** | 4.2 m → **49.1 m** | -0° → **+0°** | 7 → **7** |
| 8 deliberate 15 deg (stick angle) | 0.00 → **0.00** | 6.8 m → **6.6 m** | +0° → **+0°** | 25.5 m → **25.5 m** | +15° → **+15°** | 7 → **7** |
| 8 deliberate 45 deg (stick angle) | 0.00 → **0.00** | 18.7 m → **18.7 m** | +0° → **+0°** | 18.7 m → **18.7 m** | +45° → **+45°** | 7 → **7** |
| 8 deliberate 90 deg (stick angle) | 0.00 → **0.00** | 26.3 m → **26.3 m** | +0° → **+0°** | 0.0 m → **0.0 m** | +90° → **+90°** | 1 → **1** |
| 8 deliberate 180 deg (stick angle) | 0.00 → **0.00** | 24.4 m → **24.4 m** | +0° → **+0°** | -2.0 m → **-2.0 m** | -180° → **-180°** | 1 → **1** |
| 8e left-right flicks every 0.5 s | 0.00 → **0.00** | 4.1 m → **4.1 m** | +0° → **+0°** | 0.0 m → **0.0 m** | +1° → **+1°** | 7 → **7** |
| 8f 15 deg held, recenter on (camera follows) | 0.00 → **0.00** | 8.4 m → **13.9 m** | +165° → **-36°** | -2.0 m → **21.9 m** | +65° → **+14°** | 4 → **7** |
| 2m mirrored, bottom-right corner, exact vertical | 1.00 → **0.00** | 26.0 m → **0.0 m** | +0° → **+0°** | 4.3 m → **37.3 m** | +80° → **+0°** | 1 → **7** |
| 1m mirrored, centre, exact vertical | 0.00 → **0.00** | 24.4 m → **0.0 m** | +17° → **+0°** | 43.2 m → **37.3 m** | +0° → **+0°** | 7 → **7** |

The owner's complaint reproduces from the very first run of a round: out of
the home dorm's door with a 4° lean, the pre-fix build turned the camera
−147° in 8 s and the runner circled (row 9b). Rows with "n/a" exist only
after the fix (a comparison the old code can't express).

Release clears movement on the next update in every case (the 7 ticks are
the runner's own deceleration to < 0.3 m/s). Deliberate steering is kept:
stick angle → travel off the camera 15° → 15°, 45° → 45°, 90° → 90°, 180° →
180°, left/right flicks every 0.5 s alternate cleanly; holding 15° lets the
camera follow at ~9°/s instead of spinning 165° in 4 s.

The values (6°/16° tolerance, 4° follow threshold, 0.8 /s gain, 24 px slop)
were chosen from these scripted traces, not from playtesting on a phone:
they absorb the 3–6° leans that produced the curving while keeping a
deliberate 10–15° heading. Settings › Diagnostics now records a bounded stick
trace (last 12 gestures: duration, ring offset, sideways/forward output,
largest lean, camera turn split into follow and look, base moves, travel
sideways/forward; the newest gesture at 10 Hz, ≤ 60 lines; numbers only)
so a device report can confirm or retune them.

Tests: `test_stick_drift` (10 tests: neutral touchdown and exact vertical
everywhere in both layouts, knob drawn at ring + real offset, fixed stick,
base follow continuity, tolerance continuity/monotonic/magnitude, spare
finger slop, pad drift ownership, camera closed loop with leans 0–6° and a
wall slide, deliberate follow at 30/60/120 fps, cart recentering,
diagnostics bounds) and `test_stick_round` (real touches in a round,
written against public state so it also runs on the old build, where it
fails: touchdown 1.00, 17 m sideways in both layouts, a 5° lean swings the
camera −34° in 5 s — `docs/v7/stick/test_stick_round_on_prefix_build.txt`).

## The five screens from the owner's screenshots

The screenshots (IMG_3016–3020) were not attached to this work; each defect
was reproduced from the brief's table on the same screens and states, at
seven landscape shapes (667×375, 812×375, 844×390, 926×428 pt phones, a
1024×768 pt iPad, and the 2048×946 / 1536×710 screenshot aspects), and
measured from the running layout (final allocated rects, never minimum
sizes). Full registers: `docs/v7/menus_notes.md` (M1–M13) and
`docs/v7/screens_notes.md` (S1–S11). Matched before/after captures:
`docs/media/v7/menus/` and `docs/media/v7/screens/` (llvmpipe, emulated
point scale and safe area; service-on states use the labelled test
adapters, service-off is the shipped configuration).

| Screen | Before (measured, 844×390 pt unless noted) | After |
|---|---|---|
| IMG_3016 Emotes | Every emote glyph centred (+88, +88) units off its well, past the card edge; cards 199×291 in a 320-unit list; a 320×90 disabled "Wearing this" and a caption under the panel | Glyphs centred by construction (0, 0 offset at every size) in one redrawn icon set; 5 columns of 149×163 cards, all 10 emotes in view; a small Equipped line; Save look / Undo appear only when the look changed, inside the panel |
| IMG_3017 Season Pass | Service off: the Premium row ran to y 750 on a 720-unit screen and Claim was 65 % visible ("Ready to claim" over a dead button); 812×375 service on: Premium 5 units past the safe bottom; name cards an empty strip | A one-row header; the track takes the height left (the 132-unit cell minimum is gone) so Free and Premium are whole at every size; the detail action sits outside its scroll; "Rewards unavailable right now" and "Earned at Tier N, not claimed yet" with the reason above a visibly disabled Claim; name cards with the player's name and badge, hat/feet/full-body framing, medallion badges, Coin piles, emotes on a small live runner |
| IMG_3018 Locker Outfit | Tall cards cropping the next row; a filler "more in the Shop" card; every outfit thumbnail wearing the player's nightcap and slippers | Columns from the panel's final width with per-type wells; a one-line "N more in the Shop ›" link; outfits pictured with no hat and plain shoes (the runner keeps the real look) |
| IMG_3019 Settings | One panel: a profile paragraph and a strip of 240–300-unit buttons (Delete among them); Sound 2.9 screens down; Sprint choices at the bottom edge | Grouped cards of compact rows under a fixed header: Profile, Controls, Sound (1.5 screens down), Camera & comfort, Graphics, Diagnostics, Privacy, How to play, Credits, then Delete game profile on its own (confirmation unchanged); same saved keys and values |
| IMG_3020 Play with Friends | A 600-unit column: the friends entry cut off on every phone; a 320×88 field and 200×88 Join; with the keyboard open the code row (bottom y 547) sat under the keyboard (top 334) | A header with the player's identity, then Start a party and Join with a code side by side (field and Join one height and type size) and the Game Center friends card, all whole in the first view; the code row ends at y ≈ 253, above typical landscape keyboards, and moves by exactly the overlap if a taller keyboard would cover it; Back never moves |

Also swept: confirmations "Leave this party?" and "End this series now?"
now take Back (it did nothing); with 4+ players the party room no longer
frames a runner behind the roster; results and final standings show their
first table rows in the first view on small phones; long blocked-player and
standings lists scroll inside their sheets; entries fade instead of scaling
(no hit-target shift in the first frames). Shop: the Locker's card system,
one short unavailable line, status right above the action; purchase,
confirmation, Restore and pending flows unchanged. IDs, prices, XP, unlocks
and entitlements are unchanged; nothing is granted or faked.

Tests: `test_menus_layout` (10 tests: Pass rows and detail action at every
size, service off, Free/Premium/claim states, Locker and Shop bounds at every
size, neutral outfit pictures, swipes from glyphs/portraits/labels never
select, one centred emote set, controller focus, entry never moves hit
targets) and `test_v7_screens` (10 tests at seven sizes: Friends first view,
keyboard, code messages, Game Center states, Settings sections, finger
scrolling keeps values, Delete still confirmed, party room 1/4/8 players,
results/standings, long lists); `tools/check_v7_screens.sh` runs the
screens file at each device's real point scale and safe area.

## Characters and goggles

Full notes: `docs/v7/character_notes.md`; before/after renders and a reel in
`docs/media/v7/characters/` (same shots, cameras and light; "before" from an
untouched 1.5 copy).

- **Goggles** (swim cap, the only item with goggles), measured against the
  shared head surface: the 1.5 strap was a flat tilted ring floating 15–61 mm
  off the head and crossing the face at brow height; the lenses were two
  separate ellipsoids with a 7.4 cm gap and no bridge, half buried in the cap;
  the cap's front edge sat below the brows, so brows poked through. Rebuilt on
  the head shell: a smooth cap edge above the brows (raised brows included),
  one mirrored lens cup (symmetric within 1 mm), a bridge, temple clips and a
  strap lying on the cap; tinted lens glass inside the existing shader (no
  new material or draw call).
- **Broader pass:** shallower eye domes, ears with a bowl and rim, mittens
  with a wrist and thumb, tapered forearms, open sleeve/trouser hems with a
  cuff band (every outfit with sleeves), bob hair over the ears.
- **Budgets** (1.5 → 1.6): heaviest look 31,334 → 32,506 triangles (+3.7 %),
  7 draw calls and 2 material variants unchanged, `runner.glb` 11.78 →
  12.12 MB.
- **Thumbnails:** portrait cache keys start with the character art version
  (generation + the GLB's SHA-256, plus a look version), so 1.6 never shows a
  cached 1.5 picture.
- **Tests:** `test_characters_v7` (lens/frame distance from the head, frames on
  the cap, symmetry, lenses facing out, strap closing on the cap, brows under
  the cap edge for every brow/face preset; 15 of its checks fail on the 1.5
  asset), `test_portraits::test_keys_carry_the_art_version`; `clip_check.py`:
  no clip puts an arm > 1 cm into the head or goggles.

## Music: about 3 dB louder

One central trim, `Sfx.MUSIC_TRIM_DB`, moves from −6 dB to **−3 dB**: every
music track (lobby, chase, results) is ~3 dB louder at every Settings › Music
position. Saved slider values and mute are untouched; the slider is not
forced up and the system volume is not touched. Loop points, the no-restart
behaviour, fades and the iOS audio session are unchanged.

Headroom (ffmpeg EBU R128, true peak): lobby −23.4 LUFS / −10.9 dBFS, chase
−22.2 / −5.0, results −22.0 / −5.1. Music now peaks at −8 dBFS at the top of
the slider (−12.4 at the default 0.6). Effects peak at up to −1.3 dBFS
(`splash_big`), so a rare coincidence of both could exceed full scale at
high slider settings (it already could in 1.5, by ~0.5 dB): a hard limiter on
Master (ceiling −0.3 dB) now catches that instead of clipping. `test_lobby_music`
checks the trim, the level at two slider values, mute, and the single limiter.

## Still needs a device

- The owner's own thumb on an iPhone: forward runs, edge starts, long holds
  (What to Test). The tolerance and follow values come from scripted traces.
- Pause with another finger down on real multi-touch hardware.
