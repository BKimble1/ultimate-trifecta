# V5 implementation notes (version 1.4)

V5 answers the owner's feedback on 1.3: loading still looked unfinished,
gameplay occasionally glitched, and the largest request was a substantial
improvement to map graphics, character animation, lobby presentation,
wardrobe graphics and typography, with the polish of top mobile party games
while keeping Trifecta's own campus chase, pajama characters and cozy night.
The owner also supplied new branding: **Idlery Games** at app startup and a
new **Ultimate Trifecta** title graphic for the lobby and match loading.

The implemented rules are in [RULES.md](../RULES.md) (unchanged in V5). What
was verified, and how, is in [TEST_REPORT.md](../TEST_REPORT.md). The release
state is in [TESTFLIGHT_RELEASE.md](../TESTFLIGHT_RELEASE.md), licences in
[ASSET_LICENSES.md](../ASSET_LICENSES.md), media in
[media/v5/](media/v5/README.md).

**What this document can and cannot claim.** Everything below was measured
on a desktop Linux machine (headless, or the Mobile renderer on Mesa
llvmpipe under Xvfb) or in CI. None of it is a phone measurement: **no
iPhone or iPad was available to this work**. Device numbers come from
Settings › Diagnostics (beta), which V4 added and V5 extends.


## Defect and issue register

Each item: what triggers it, what was observed, its category, the cause (or,
where unproven, the hypothesis), the fix, and how the fix was verified.
Categories distinguish **render stall**, **camera jitter**, **pose popping**,
**collision error**, **input loss**, **network correction** and plain
**UI/presentation defects**. Character-motion items found by the motion work
are in [Character motion](#character-motion); campus build items in
[Campus art](#campus-art).

| # | Trigger | Observed evidence | Category | Cause | Fix | Verification |
|---|---|---|---|---|---|---|
| U1 | Tap, release and tap again quickly on any V4 button | Reproduced in a test with V4's exact code: the held button springs back to full size while the finger is still down | Input feedback / animation ownership | `UIKit._scale_to` started a new tween per press and release and never stopped the previous one; the 0.2 s release spring outlived the 0.08 s press | One owner per animated property (`src/ui/motion.gd`): a new animation kills the running one; tweens are bound to the node; only a child Face scales, never the hit region | `test_motion_layer` (the V4 reproduction fails as expected, the V5 path holds 0.955, at most one tween ever running) |
| U2 | Open the wardrobe | The equipped outfit card showed a blue placeholder sphere (owner's screenshot; reproduced in the V4 capture) | Presentation | Thumbnails were mapped key → one tile; the equipped outfit card and the selected pattern card request the same look, so the second overwrote the first | Every card keeps its own key and takes any finished picture for it | `test_wardrobe` (one finished picture lands on both cards; a stale one lands on none) |
| U3 | A wardrobe category with many items, or fast category changes | Pictures never arrived on some cards (code path) | Presentation | The portrait queue held 12 requests and silently dropped the oldest | Queue of 24; a category change cancels the previous category's queued requests; only visible cards ask | `test_wardrobe` (no stale queued work after rapid switching), `test_portraits` |
| U4 | Wardrobe on a phone | "Swim T…", "Frog On…", "Wide B…" (owner's screenshot) | Presentation | Three columns of 190-unit horizontal tiles with an 80-unit picture and a trimmed one-line name | Portrait cards: the picture above the full name (two lines reserved), a state row; column count from the panel width | `test_wardrobe` (every item name fits in two lines at the narrowest card at 20 units, no ellipsis) |
| U5 | Party lobby with long names | "Sneaky Badg…" (V4 capture) | Presentation | A fixed name column next to a status badge | Name gets the card's width (badge moved into the status line); the size steps down 22 → 20 → 18 before any trim; the full name is in the tap-for-details card | 8-player capture (all 16-character names whole) |
| U6 | App start | V4 left the startup curtain after six process frames, whatever was ready | Render stall over the menu (risk) | A frame count is not a readiness test | `BootCurtain` waits for the home screen and the player's runner, then three steady frames (a hitch resets the count; a steadily slow device counts as steady), minimum 0.45 s, cap 6 s | `test_boot_branding` (stays with no screen; leaves on readiness; frees itself) |
| U7 | Under slow rendering (llvmpipe; plausibly a slow device) | The curtain waited for its 6 s cap | Startup | The first V5 steadiness rule was absolute (< 100 ms per frame) | Steady = quick, or no slower than the frame before | `test_boot_branding` (`steady()` cases); captures |
| U8 | Open the full map | For one frame the side panel sat at the top left (seen in a capture) | Presentation | The map was laid out in `_process`, after its first frame | Laid out in `_ready` | Map captures |
| U9 | Wardrobe on a 4:3 iPad | The runner was too large and partly behind the item panel | Presentation | The wardrobe camera used fixed fractions whatever width the panel left | The stage frames the runner in the free region the panel actually leaves | iPad capture |
| U10 | Home / results | An emote's name bubble sat above the top of the screen | Presentation | The lobby's group bubble was also drawn on single-character framings | Bubbles only in the group lobby | Results capture; `test_emotes` |
| U11 | The match loading screen | A 4:3 movie at 80% of the screen with a synthesized surround and small status; 24 fps stride against a 60 fps UI | Loading presentation | V4 used a crop of the owner's 24 fps clip | Replaced (see [Match loading](#match-loading)) | `test_loading`; loading captures |
| P1 | First round of a session | Longest single preparation job ~50 ms outside the campus build (the bots' navigation grid) | Render stall (loading frame) | The grid was rasterised in one call | Built in six slices with an identical grid; every job is timed and named; a job over 25 ms marks the diagnostics timeline (`prep_slow:<job>`) | `test_prep_jobs` (staged grid = one-shot grid; longest non-campus job 13 ms on this machine) |
| P2 | Round preparation | V4's HUD and touch controls built in one job (16 ms) | Render stall (loading frame) | One job | Separate jobs | `test_prep_jobs` |
| P3 | First map open | The campus map drew every road and building every frame | CPU per frame | Live drawing of static geometry | The static map is drawn once per session into an off-screen canvas during preparation | `test_map` |

Glitches the owner reported but that could not be reproduced here without a
device (frame hitches on the phone itself) are not claimed as fixed; the
diagnostics panel attributes any remaining stall to the marker before it,
now including the name of a slow preparation job.

## Branding

- **Idlery Games at startup.** The owner's lockup (`art_src/branding/`) is
  centred on the startup navy `#0C1324`. `tools/branding/make_branding.py`
  builds `game/assets/icon/launch.png` (2048², opaque), which the iOS launch
  storyboard and Godot's boot splash both show "scale to fit". `BootCurtain`
  then draws the same lockup at the same place (`Brand.lockup_rect`, a test
  checks the launch image against it), so launch → boot splash → first
  runtime frame is one picture. It leaves on readiness (U6/U7) with a
  0.3 s fade and a slight settle of the mark (Reduced Motion: a 0.15 s fade).
  The V4 droplet launch art and the unused V2 `splash.png` are gone.
- **Ultimate Trifecta title.** The owner's graphic is drawn once as a
  `TextureRect` (never traced into per-frame text), proportional with its
  own transparent padding, mipmapped and lossless (1440 wide, from the
  2172-wide master), with the accessibility name "Ultimate Trifecta". It
  replaces the V4 Fredoka wordmark on home and on match loading. The softer
  satin master is used as supplied; no extra shine was added.
- **CI audit.** The lane now runs `tools/launch_audit.py` right after the
  Xcode export, before any signing or upload. It fails on: no or several
  launch storyboards, a launch background that isn't the startup navy, a
  launch image that is missing, not opaque, not on navy or without the
  Idlery teal mark, and any "powered by" text in the game data or project
  text. Naming Idlery is now expected (the requested mark, and the bundle
  ID in plists) and is listed for the log. Verified on a real Godot 4.7.2
  iOS export on Linux and on the macOS CI export (run #56).

## Type, theme and motion

- **Manrope** (SIL OFL) replaces Fredoka for everything except the title
  graphic: static Medium / SemiBold / Bold / ExtraBold instances made by
  `tools/fonts/make_manrope.py` (Godot draws a variable font at its default
  instance). Tabular digits (`tnum`) for the timer, counters, coins, the
  countdown and the party code. System font fallback stays on for
  characters Manrope lacks.
- **Scale** (canvas units of a 720-unit-high screen, ~1.85 per point on an
  iPhone): display 44 ExtraBold, title 34, headline 27, body 23, label 22,
  caption 20 (~11 pt), overline 17 bold tracked capitals.
- **Controls** are cards: radius 16–22, a thin lighter rim along the top
  edge, a soft shadow, no lower lip. Gold for the one primary action, teal
  for selection, readiness and progress. Selection is a tinted fill with a
  teal edge and a check, never a solid teal slab. A distinct teal focus
  ring sits outside the control; on touch it stays hidden until a
  controller or keyboard moves focus (`grab_focus(hide_focus)`). Disabled
  controls stay solid and say why ("Need 40 more coins", "Wearing this").
- **Text over the 3D world** has a thin edge and a soft shadow instead of
  V4's thick outline; the clock sits on a soft pill.
- **Motion layer** (`src/ui/motion.gd`): press in 85 ms, release 190 ms with
  a very small overshoot, panels and tabs 220 ms fades (at most 10 units of
  movement), dorm camera moves 320 ms eased in and out. One owner per
  property (U1). Every pressable is a still `Button` (the hit region and
  layout box) with a `Face` child that draws and scales, so containers
  never fight the animation and touch targets never move. Reduced Motion:
  no scale, movement, bounce, camera drift or sheen; colour and state
  still change at once. Gameplay cues that pulse (spotted edge, splash
  marker, tag-ready ring) hold steady with Reduced Motion. Targets stay at
  least 44 pt.

## Home, party lobby and wardrobe

- **Home:** the title graphic upper left; a compact profile chip (name,
  level, coins) and Settings upper right; the player's runner as the
  focus; Play with Friends (gold) and Practice lower right; Wardrobe and
  Emote lower left. No store, pass, news or extra currency.
- **Dorm room:** a real window opening onto a moonlit campus skyline (the
  clock tower, rooftops, lit windows, trees, a moon with a smooth halo;
  unshaded, one draw call); the poster moved off the upper left so the
  title has calm space; an upholstered armchair and floor cushions in the
  middle distance; warm light pools from the floor lamp and table lamp and
  cool moonlight across the floor (additive quads, no extra shadowed
  lights); a soft front fill so faces, hands and shoes read for every skin
  tone without overexposure; the key light's shadow range tightened for
  softer, less jagged contact shadows; per-plank floor tints instead of
  alternating stripes; no constant lamp pulsing. Camera moves between home,
  wardrobe and party take 320 ms, eased.
- **Party:** a party-code card with Copy and Share, Invite; the settings as
  three short chips ("3 rounds", "2 Night Watch", "4 home to win") that the
  host taps to change and guests see with a lock; roster cards with round
  portraits on the player's colour, full names (U5), host/ready/bot status
  with an icon, the local player outlined in gold, and one open seat. Tap a
  card for details (full name, status, actions); your own card offers your
  move and the wardrobe. The primary action and its status stay in place.
  Emotes keep V4's ownership rules (newest wins, predicted local start, the
  host's echo skipped, the ready response never over an emote), and Try
  moves yields to Start at once (`test_lobby_flow`).
- **Wardrobe:** the runner on the left (head to shoes, framed in the free
  region on any aspect, U9); on the right a category strip (Outfit, Colors,
  Face, Hair, Hat, Shoes, Emotes) over portrait item cards (U2–U4): the item
  on your runner in the draft's colours, the full name, and Equipped /
  Owned / price with a lock when you can't afford it. The draft's choice
  has a teal edge, a check and a one-shot sheen. Colours are swatches with
  the chosen name and its state above them. Each category keeps its scroll
  position; a change is a 150 ms fade. Picking an item updates the runner
  at once with a short hop. The footer says what Apply will do; Undo
  returns to the saved look; leaving with changes asks first.

## Match loading

The V4 screen played a crop of the owner's 24 fps clip at 80% of the
screen height. V5 renders the loop from the game itself:

- `src/dev/loading_loop_render.tscn` renders three fully clothed runners
  (the shared character asset, the game's character shader and animation
  graph) running in place under a stable long-lens camera, with a warm key,
  a cool moonlit rim, a soft fill and soft contact shadows, on a
  transparent background (premultiplied by coverage).
- **Exact loop:** the run speed is solved (5.21 m/s) so one gait cycle is
  exactly 26 frames at 60 fps; the runners are offset by fractions of that
  cycle; blinks and fidgets are off; hat springs are pre-rolled. Frame 26
  equals frame 0 (mean absolute difference 0.0), and the step from the
  last frame back to the first is an ordinary rendered step (5.77 against
  4.22–5.64 between other frames). It was re-rendered from the V5 rig after
  the motion work (new clips and pose fades). `tools/make_loading_loop_rig.py` refuses a loop
  that doesn't close.
- **Cost:** 26 frames of 920×540 in one 4×7 atlas: ASTC 4×4 on iOS
  ≈ 12.9 MB of GPU memory (V4: 13.8 MB for 19 frames at 24 fps). The still
  (frame 0) shows at once; the atlas loads on a background thread.
- **Composition:** the title on top, the runners standing on moonlit ground
  in the middle, a quiet status at the bottom (the real stage, a thin teal
  bar that follows the preparation steps actually done and never runs
  ahead, "Waiting for players · a/b ready"). The background is a static
  shader (night gradient, a soft glow behind the group, a faint horizon,
  still stars, dither): no box, seam or 4:3 picture on any width. The
  picture is never drawn larger than 1.25× its pixels (sharp on iPad).
- **Comparison with the supplied clip:** the clip's runners are lovely but
  it is a 24 fps stride inside a 4:3 frame with its own lighting and a
  slightly different character look; the loop had to be stitched from
  per-runner alignments. The game-rig loop matches the game's own
  characters, closes exactly at 60 fps, composes over any screen width, and
  costs slightly less memory. The clip stays in `art_src/loading/`.
- Behaviour kept from V4: still first, background load, adoption by `App`
  if the screen closes early, Leave party after 25 s, close the moment the
  round is live (never waiting for the loop), release on close, Reduced
  Motion shows the still.

## Map, HUD and results

- **Map picture:** drawn once per session from `CampusLayout` into an
  off-screen canvas (`src/ui/campus_map.gd`): soft building footprints with
  a drop shadow (the dorm warm), roads with a kerb, footpaths in a warm
  stone tone, groves as soft regions, water shapes with a light rim,
  plazas, hedges and calm ground. Regenerated from the layout every
  session, so it can't drift; live markers use the same transform
  (`CampusMap.to_map`, tested).
- **Live markers** (`MatchHUD.MapPainter.items` → `paint`): your arrow and
  a soft wedge for the camera's view; tonight's three waters as round
  badges in their colours (a check when done); the dorm; your team, with
  close teammates grouped into one dot with a count; carts and fading
  splash rings for the Night Watch; opponents only as host-sent last-seen
  cues (solid while in sight, then a fading ring). No pulsing markers.
- **Labels** on the full map are placed greedily around their markers and
  never overlap each other or a marker; what doesn't fit is in the side
  panel (`test_map`).
- **Side panel:** Home n/N and how many are still out, a five-item legend
  with the same marks, your team in a scrolling list, and an (i) button
  for the longer explanation. The map still blocks movement and look, and
  closes with Close, Back or the map key.
- **HUD:** tabular clock on a pill, a "Home n/N" chip, role and "Round x
  of y", objective chips, the baked minimap, sentence-case banners ("All
  three splashed · Run home!"). The role reveal is two short lines plus
  one rule instead of a paragraph.
- **Results:** the outcome as a display line, the reason, your round in a
  card (role, team result, your contribution, the fastest Trifecta),
  rewards with tabular coins, the series, and the actions. Captions are
  shorter.
- **Settings:** an opaque sheet over a dimmed room, overline sections with
  dividers, choice buttons with the restrained selection.

## Character motion

The full register (M1–M19) with the V4 → V5 numbers is in
[v5/motion_register.md](v5/motion_register.md); the implementation, the
asset rebuild, budgets and limits in [v5/motion_notes.md](v5/motion_notes.md);
media in [media/v5/motion/](media/v5/motion/README.md). Every before/after
number comes from the same measuring code run on the V4 commit and on V5
(headless or llvmpipe on a desktop, fixed clock): it measures continuity,
not phone smoothness.

- **No snaps between states.** Every state change fades from the pose on
  screen (`CharacterPoseFade`, a skeleton modifier that extrapolates the
  shown pose and decays it). Largest single-frame upper-body snap, V4 → V5:
  start 35 → 5 cm, stop 25 → 3.5, 180° reversal 29 → 7, running-jump
  landing 57 → 10, kerb drop 51 → 7, one-tick floor-contact flicker 103 →
  3.5, cart in/out 35 → 5, prediction-correction stress run 23 → 7.
  Teleports (respawn, resurfacing, cart seat) cut instead of fading.
- **Gait phase and foot contact.** A start begins on a step, a stop
  finishes the step it is in and holds a planted pose; stride rate follows
  ground speed at the rule speeds (1.3–8 m/s); the drawn body aims along
  its actual travel in turns, so it no longer runs sideways for 0.2 s.
  Planted-foot slide in a reversal 1.23 → 0.92 m/s; 90° turns still slide
  about as in V4 (no foot locking yet: Partial).
- **Clips.** Eleven clips had arms 1–30 cm inside the head (yawn,
  celebrate, cheer, wave, splash…); none over 1 cm now
  (`tools/character/clip_check.py`). Baked ~22 cm foot jumps in tag
  recover/miss removed; new cart hop-in and hop-out. The Night Watch
  wind-up and recovery play on the upper body while the legs keep running;
  the lunge is a leap instead of a planted stance sliding at 9 m/s.
- **Secondary impulses.** Springs take the derivative of a filtered
  velocity, bounded at 55 m/s², so a short frame or a correction can't
  kick them; the nightcap is simulated in the character's space (hitch,
  respawn or jump: 32–41 cm whip → ≤ 8 cm); landing squash is a damped
  spring (≤ 15 %).
- **Camera.** A tree trunk or lamp post crossing the camera line no longer
  yanks the camera ~3 m closer for a frame (now 0.03 m); walls still pull
  it in at once. Dorm camera moves are the UI motion layer's 320 ms.
- **Resets.** Respawn, teleport, cart seat, reconnect and spectator switch
  reset all motion history; a new view's first frame doesn't count the jump
  from the world origin as travel (M19, found in integration).
- **LOD thresholds.** Distant characters animate at a reduced rate beyond
  48 m and return to full rate inside 42 m (hysteresis), keeping exact
  elapsed time; your own character never throttles.
- **Menus.** A calmer idle in the dorm (slower breathing, a small fidget
  every 7–12 s, softer blinks, a calmer cap), automatic for indoor
  lighting; emotes, arrivals, ready responses and Try moves unchanged.
- **Network classification** (M14): on the shaped in-process link (0, 120
  and 300 ms round trip) visible correction frames were 0; terrain and
  camera-collision counts didn't change with the link, so they are not
  network effects. On real UDP between processes, mean corrections were
  2.5 mm unshaped and ~11 mm at 60 ± 10 ms / 3 % loss. Still open: remote
  players extrapolate on ~6 % of frames under heavy loss (300 ms, 10 %),
  and rare ~1 m corrections in the UDP soak were not traced.

<!-- V5_MERGED_SECTIONS -->

