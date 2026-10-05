# Pass 8 notes: movement, match clarity, rotating Shop, Coin packs, challenges (version 1.8)

"Pass eight" is the owner's name for this work. It builds on V8 (version
1.7, build 7) and is additive: V8's evidence and notes are unchanged, and
nothing here re-runs the V8 brief.

Everything here was built and measured on desktop Linux: headless Godot
4.7.2 or the Mobile renderer on Mesa llvmpipe under Xvfb, plus the
service's Node tests. **No iPhone or iPad was available to this work.**
Device feel, frame rate, StoreKit prices, App Store products and the
deployed service are **unverified**; what still needs a device or the
account holder is listed at the end and in What to Test.

Workstream details (each with its own decisions, register, tests and
evidence index):

| Area | Notes | Evidence |
|---|---|---|
| Sprint and dive (§3, §4), results music (§13) | [docs/pass8/movement.md](pass8/movement.md) | [docs/media/pass8/movement/](media/pass8/movement/) |
| Match clarity and map (§5, §6) | [docs/pass8/match.md](pass8/match.md) | [docs/media/pass8/match/](media/pass8/match/) |
| Six skins (§7) | [docs/pass8/skins.md](pass8/skins.md) | [docs/media/pass8/skins/](media/pass8/skins/) |
| Rotating offers and Coin packs (§8, §9) | [docs/pass8/shop.md](pass8/shop.md) | [docs/media/pass8/shop/](media/pass8/shop/README.md) |
| Challenges (§10) | [docs/pass8/challenges.md](pass8/challenges.md) | [docs/media/pass8/challenges/](media/pass8/challenges/README.md) |
| Startup logo edges (§11) | [docs/pass8/logo.md](pass8/logo.md) | [docs/media/pass8/logo/](media/pass8/logo/) |

## Defect register

Owner symptom → reproduction → measured cause → change → evidence.

| # | Owner symptom | Reproduction | Measured cause | Change | Evidence |
|---|---|---|---|---|---|
| P1 | Holding sprint feels like repeated fast/slow pulses | `test_p8_movement` probe "sprint held 30 s" (real sim on a clear lane); `test_p8_sprint_touch` (real touches, a thumb parked at the stick's edge); 1.7 (7) clip | `Motor.step_foot` restarted a held sprint whenever the meter refilled to `sprint_min_to_start` (15 %): **22 bursts of ~0.38 s in 30 s** of one hold (trace). Input, collision and camera were ruled out: the stick held at the edge stays above the exit threshold, the follow camera's FOV never depends on sprint, and the speed alternates exactly with the meter | An exhausted latch in the motor state: set when the meter runs dry while sprinting, cleared only when sprint is released (button up / thumb under the edge-sprint exit threshold / finger lifted) **and** the meter is back to 45 %. Serialized (prediction, replay), reset on respawn, respected by bots. HUD: "Sprint empty · ease off to recharge" and a tinted meter while the latch holds sprint off | Probe: 1 burst in 30 s; release-and-repress bursts unchanged (9 → 9, 5.98 m/s); guest prediction agrees on every sample; clips |
| P2 | Repeated jump→dive out-runs the Night Watch | Probe "best jump/dive chain (+ sprint)", "taps 10/s"; `test_dive_loop_does_not_out_run_the_watch` (the `test_pursuit` Watch from 8 m) | A jump pressed during a dive was buffered and fired on the landing tick, skipping the 0.32 s recovery, and the new jump could dive again at once: **8.05–8.45 m/s sustained** at 8.6 m/s per dive; the Watch (6.6 m/s) never closed | One dive per airborne sequence; presses during a dive are dropped; the landing recovery is 0.45 s and can't be skipped (only a press in its last 0.13 s waits for it); dive speed 8.0 m/s; the `dive_land` clip is a three-beat 0.45 s landing | Best loop 5.23 m/s (< sprint bursts 5.98, < Watch 6.6); pursuit: escaped → **caught in 4.5 s**; a single dive still peaks at 8.0 m/s; `test_dive_edges` |
| P3 | (found in testing P2) Guest snaps at dive landings | `test_guest_prediction_of_latch_and_dives` at 50 ± 8 ms and 2 % loss | `move_and_slide` snaps to the floor from engine-internal "was on floor" state that a reconcile can't restore, so a replay crossing a landing snapped differently from the host (paired 0.27 m corrections) | The floor snap length follows the serialized `on_floor` | 8 → **0** corrections over 25 cm in 25 s of dive spam |
| P4 | "How am I doing?" is unclear in a match | Source audit of the V7/V8 HUD, map and results; captures at four device sizes ([match.md](pass8/match.md) M1–M14) | One "Home 2/4" chip for both roles, three equal chips, a "head back" arrow by straight line, no comparison between runners, the series only on results, map opponents as plain dots, sightings from a caught player's own held body, and no freshness check on a guest's sightings | One goal bar and one clock per role ("Team home 2/4 · Need 2 more" / "Runners home 2/4 · Hold until"); a personal card with one next action (route-best water, door by route, caught / protected / home states; the Night Watch's tags and tag state); a live **Runner pace** for runners only (host distance fields built off the main thread, ranked every 30 ticks, places and stamp counts only on the wire); the series line in pause, map and results; results in the order outcome → why → you → series → rewards → tables; map role badges in sight, a frozen hollow last-seen mark with its age for the 5 s TTL, a legend, a "Night Watch in sight · N m" chip; sightings from the followed view and none from snapshots over 0.6 s old | `test_runner_pace` (8), `test_match_hud_pass8` (9), `test_map` (6), `test_v7_screens`; pace update cost p50 105 µs / p95 157 µs, no path search; 72 captures at SE, iPhone 14, Pro Max and iPad with measured rects (no overlaps) |
| P5 | Startup logo edges look rough against black | [logo.md](pass8/logo.md) register: pixel probes of every stage on four device sizes | Not the owner's art: the BootCurtain sat 0.34/0.90 px off the launch image (Godot rounds Control positions to whole canvas units: 1.625 device px on a 2532×1170 phone), drew a 1400-px texture a mip level down, and V5's Lanczos resize had left a halo (5,161 pixels); 2x iPhones shrank the 2048² launch image 2.5–2.7:1 with one bilinear sample | The lockup is rasterised from the owner's vector at the exact device size and sub-pixel position and drawn 1:1 (`BrandMark`), premultiplied; launch image 1656² from the vector; the launch audit checks edges | Curtain error RMS 31.8 → 2.4 on 2532×1170; handoff movement 0.88 → 0.22 px; halo pixels 5,161 → 0 |
| P6 | (found at merge) `test_wardrobe` failed only in the full suite | Bisected with `run_tests.gd -- a,b` | `test_shop_rotation` began twice in one test and restored the window to 1280×720, not the original size | The test keeps the first saved size | Full suite green |
| P7 | (found at integration) With the latch on, the touch stick still looked like it was sprinting | `test_p8_sprint_touch`: a thumb parked at the edge after the meter ran dry | The stick drew its knob and sprint ring from the held edge-sprint input (`Controls.touch_sprint`), not from the motor | The stick shows sprint only while it really runs and draws the latch as coral dashes on its meter ring, matching the HUD's "Sprint empty · ease off to recharge" and hatched meter | `test_p8_sprint_touch`: 0 frames shown as sprinting while latched |
| P8 | (found at integration) Shop layout reports flagged "New" chips off screen | Shop captures at SE and iPhone 14 | The layout checker took only the nearest clipping ancestor (the card art), not the scrolled list around it; the game drew nothing wrong | The checker intersects every clipping ancestor, as the engine does | 33 Shop shots, 0 issues |

## Results

| Brief item | Outcome |
|---|---|
| §3 Sprint | Fixed at the source (P1); 45 % re-arm; no change to speed, acceleration, camera or input latency |
| §4 Dive | Nerfed fairly (P2); a deliberate dive stays a burst |
| §5–§6 Match clarity, map | P4: goal bar and clock, personal next action, Runner pace (ties shared competition style, bots counted, "Not home" at the end, approximate when a route is unknown), series line, results order, map sight cues and legend; no opponent position or next goal is sent to draw any of it |
| §7 Six skins | Midnight Mechanic 900, Moonwalk Cadet 1,200, Pumpkin Pajamas 800, Arcade Sprinter 900, Cloud Nine 1,000, Bedtime Bandit 1,000 Coins; one part each on the shared rig, own footwear, caps or hoods; heaviest look unchanged (32,834 triangles, 7 draw calls); 0 containment failures through every clip |
| §8 Rotating offers | Four featured slots, 48 h offers changing at 00:00 UTC (two slots a day), a 12-week schedule from an explicit rule (`tools/make_offer_schedule.py`, 170 offers to 2026-12-28); the service's clock decides availability at acceptance (`409 offer_changed`, nothing charged); countdowns on a monotonic offset of the service's time; "Owned skins stay in your Locker. Shop skins may return." |
| §9 Coin packs | `coins.250`, `coins.1000`, `coins.7500` added (eight products in all); compact cards with StoreKit's price or "Not available"; "Best value" only from same-currency numeric StoreKit prices; no hardcoded prices |
| §10 Challenges | 3 daily × 50 and 3 weekly × 150 Season XP, role-flexible; active-play check (≥ 60 s or 40 % of the round); UTC day / Monday week with 24 h grace; bonus once per player and challenge instance, settled in the same batch as the round; Challenges page in the Season Pass; results lines |
| §11 Startup logo | P5 |
| §12 Animation | Three-beat 0.45 s dive landing tied to the recovery rule; the six outfits through every clip (action sheet and a 30 s reel of the heaviest look); the sprint latch removes the repeated sprint/run pose switching. Shop and challenge cards use the shared motion layer (refresh feedback respects Reduced Motion) |
| §13 Results music | A central RESULTS state (`Sfx.results`): once per round result, never restarted by reopening results, no flourish for a cancelled round. **The owner's results track has not been supplied**, so this build keeps the V5 results sting and the lobby music under the results screen exactly as before; no placeholder was made |

## Decisions

- **Sprint re-arm at 45 %** (the brief's 40–50 % range): at 3.6 s for a full
  refill after the 0.35 s delay, a released sprint is ready in about 2 s.
  Holding sprint without releasing is now slower than before (5.82 →
  5.18 m/s): the auto-restart was free speed for not playing the meter.
- **No Watch buff.** Pursuit numbers for every non-dive scenario are
  unchanged; the Watch only closes faster on the dive loop.
- **Protocol 7.** The motor's flags carry the latch and RESULTS rows carry
  `active_s`; a 1.7 game and a 1.8 game refuse each other at join.
- **One live 3D preview in the Shop** (the dorm stage behind it) rather than
  a second preview inside the detail panel: two live 3D renders cost more
  than they show.
- **Results track:** the RESULTS state is in place so the owner's track only
  needs its file (`music_results_bed.ogg` with a measured loop offset) and a
  ten-wrap check; see [movement.md](pass8/movement.md) and
  `test_p8_results_music`.

## Open, and not verified

- **Device:** sprint and dive feel with a thumb, the startup on a real phone
  (PNG screenshots, ideally SE / XR and a 13-inch iPad), Shop countdowns
  across sleep, the new Season Pass page and match HUD at real sizes.
- **Service not deployed:** no live rotation, challenge settlement or Coin
  spend; the build shows the honest unavailable states.
- **App Store products:** all eight are MISSING in App Store Connect (Paid
  Applications agreement, then `asc.py iap-create`), with no prices set:
  the owner's decision.
- **Results track:** not supplied.
- **Offer schedule** ends 2026-12-28; extend it before then.
