# V6 character notes: refined runner, Shop outfits, Season 1 items, foot lock

V7 changes to the shared character (goggles, ears, eyes, mittens, cuffs and
hems, the portrait cache key) are in [../v7/character_notes.md](../v7/character_notes.md).

Work stream: the shared character asset and rig (brief §5 "Characters"),
the art behind the Shop (§9) and Season 1 · After Hours (§12), and their
tests (§16). Media: [../media/v6/characters/](../media/v6/characters/README.md).

**What these notes can claim.** Everything was measured on a shared
desktop: headless engine frames on a fixed 60 Hz clock for motion, and
Godot 4.7.2's Mobile renderer on Mesa llvmpipe under Xvfb for pictures.
That measures continuity, geometry and relative cost. It says nothing about
frame rate, heat or feel on an iPhone; no phone was available.

## Shipped keys

Every key below has real geometry in `game/assets/characters/runner.glb`,
a catalog entry in `game/src/view/cosmetics.gd` (display name, never-reused
ID, `includes` for outfits, `season: 1` for pass rewards) and is checked by
`game/tests/test_outfits_v6.gd`. Nothing was cut.

| Field | Key | Display name | Part(s) | LOD0 triangles |
|---|---|---|---|---|
| outfit | `moonlight_runner` | Moonlight Runner | `moonlight` | 7,566 |
| outfit | `starry_sleeper` | Starry Sleeper | `starry` + `acc_sleepmask` | 7,868 + 1,956 |
| outfit | `varsity_sprinter` | Varsity Sprinter | `varsity` | 8,588 |
| outfit | `raincoat_explorer` | Raincoat Explorer | `raincoat` (boots included) | 10,476 |
| outfit | `campus_courier` | Campus Courier | `courier` + `acc_courier_cap` | 9,946 + 3,090 |
| outfit | `lantern_scout` | Lantern Scout | `scout` | 10,182 |
| outfit (S1) | `after_hours_hoodie` | After Hours Hoodie | `hoodie` | 7,402 |
| outfit (S1) | `night_owl` | Night Owl Onesie | `owl` (hood) | 11,126 |
| outfit (S1) | `glow_jogger` | Glow Jogger | `jogger` | 5,860 |
| outfit (S1) | `library_cardigan` | Library Cardigan | `cardigan` | 9,090 |
| hat (S1) | `headlamp` | Headlamp | `hat_headlamp` | 1,852 |
| hat (S1) | `pompom_beanie` | Pom-Pom Beanie | `hat_beanie` | 3,452 |
| hat (S1) | `glow_headband` | Glow Headband | `hat_glowband` | 1,150 |
| hat (S1) | `owl_ears` | Owl Ears | `hat_owlears` | 1,448 |
| shoes (S1) | `glow_sneakers` | Glow Sneakers | `shoe_glow` | 2,660 |
| shoes (S1) | `moon_boots` | Moon Boots | `shoe_moonboots` | 2,820 |
| emote (S1) | `stargaze` | Stargaze | clip `emote_stargaze` (1.6 s) | |
| emote (S1) | `victory_lap` | Victory Lap | clip `emote_victory_lap` (1.6 s) | |
| emote (S1) | `shush` | Shush | clip `emote_shush` (1.4 s) | |
| emote (S1) | `moon_shuffle` | Moon Shuffle | clip `emote_moon_shuffle` (1.6 s) | |

The `cost` values in the catalog are placeholders in the V5 coin scale;
pricing, Apple products and the pass table belong to the commerce stream,
which references these keys. Emote wire values are `TC.EMOTES` indices
(appended after the V4 six; catalog `id` = index + 1). A 1.4 client drops
an emote index it does not know (its existing bound check).

### What each outfit includes (the catalog's `includes`, shown to buyers)

- **Moonlight Runner:** midnight track jacket with a stand-up collar and a
  silver zip; track trousers with ribbed ankle cuffs; reflective silver
  piping (double lines down the sleeves and legs, across the back yoke);
  gold crescent-moon emblem with a star on the chest.
- **Starry Sleeper:** indigo pajamas with gold and cream stars (front, back,
  sleeves and legs), cream piping, collar and placket, gold buttons, a
  crescent on the pocket; a lavender sleep mask with embroidered closed eyes
  worn pushed up on the forehead. The mask is worn with no hat, the party
  hat, headphones, crown or owl ears, and hidden under the nightcap, swim
  cap, beanie, headlamp and glow headband (they sit where it does).
- **Varsity Sprinter:** jacket wool in the player's colour, ivory leather
  sleeves, rib collar/cuffs/waistband with ivory stripes, five snaps, a
  two-layer chenille **T** on the chest and a chenille **3** on the back
  ("Trifecta"); navy track shorts with side stripes and piped hems; crew
  socks striped in the player's colour.
- **Raincoat Explorer:** glossy yellow A-line raincoat with four wooden
  toggles and rope loops, a placket, two flap pockets and a folded hood;
  navy rain trousers; teal rain boots (worn instead of the chosen shoes:
  `Cosmetics.OUTFIT_OWN_SHOES`).
- **Campus Courier:** short-sleeve shirt in the player's colour under an
  open teal utility vest (four flap pockets, mustard trim), a mustard
  messenger bag on the right hip on a cross-body strap, khaki cargo shorts
  with side pockets, crew socks; a teal six-panel courier cap with a mustard
  band and chevron, worn only with no other hat (any chosen hat wins).
- **Lantern Scout:** khaki scout shirt with rolled sleeves and epaulettes,
  an open green vest with five merit badges (moon, star, wave, tree, flame),
  a teal neckerchief with a brass woggle (point down the back), a belt with
  a brass buckle and a small brass lantern with a warm glowing wick on the
  left hip (decoration only: it lights nothing), olive shorts, green knee
  socks.
- **After Hours Hoodie:** violet hoodie with a kangaroo pocket, drawstrings,
  a gold moon-and-stars print and a folded hood with cream lining;
  charcoal joggers with ribbed cuffs and a side stripe.
- **Night Owl Onesie:** tawny owl onesie with a feathered cream belly, wing
  sleeves with feather rows and flight feathers, tail feathers; an owl hood
  with big amber eyes, a beak and ear tufts. Like the duck and frog it
  replaces hat and hair while worn (`HOOD_OUTFITS`).
- **Glow Jogger:** fitted running top and leggings with glowing chevrons,
  seams, bands and wristbands, running shorts. The glow is the player's
  colour (light shade).
- **Library Cardigan:** oatmeal cable-knit cardigan (ribbed geometry) with
  wooden buttons, suede elbow patches and a pencil in the pocket, a white
  collared shirt and green knit tie, brown corduroy trousers.

Hats: **Headlamp** (strap with a reflective line, top strap, lamp with a
chrome ring and a warm emissive lens: no light source, no gameplay effect),
**Pom-Pom Beanie** (knit ribs and a rolled cuff in the player's colours, a
knobbly pompom), **Glow Headband** (sweatband in the player's colour with a
glowing line and star), **Owl Ears** (a headband with feathered ear tufts).
Shoes: **Glow Sneakers** (low runners with glowing sole strip, laces, heel
tab and crescent), **Moon Boots** (puffy quilted boots, chunky sole, gold
crescent, drawcord toggle).

### Hair and hats

Hair under a hat is drawn as a variant so nothing pokes through a band or
shell (`Cosmetics.HAT_HAIR_VARIANT`, now in `runner_parts()` instead of
`CharacterView`): the tuft without its forelock (`hair_hat`), the curly
crop with a smooth band (`hair_curly_hat`, V5) or with curls only below a
cap's edge (`hair_curly_low`, new); space buns' knots are hidden under the
new hats and headwear. `test_profile` checks every outfit × hat × shoe ×
hair combination (15 × 10 × 5 × 4 = 3,000) shows its parts and applies the
rules; `test_outfits_v6` checks the headwear/footwear rules one by one.

## The shared asset (every screen uses it)

- **Face:** an upper lash line hugging each eye white, thicker toward the
  outer corner with a small flick. It carries the eye's frame, so blink,
  squint and the face presets move it with the lid. The mouth is 9 % wider.
- **Ears and nose:** ears ~8 % larger with a deeper inner shade (they now
  read on dark tones and under hair); the nose a touch larger.
- **Hands:** a flatter, longer mitten with the thumb set further out (a hand
  rather than a ball).
- **Normals:** `build_character.py` marks edges sharper than 66° hard
  (`Mesh.set_sharp_from_angle`), so decal and patch rims, flat sleeve ends,
  sole and crown edges keep crisp shading instead of a smear.
- **Hood openings:** the duck, frog and owl hoods cut their face opening by
  dropping whole quads, a stepped edge that showed skin in blocks beside
  the rim. The opening's boundary now lies on the rim's ellipse.
- **Skin at night:** the character shader adds a small warm self-light on
  skin (instance uniform `skin_warm`: 0.15 outdoors, 0.03 under the dorm's
  warm light). Forehead colour of the lightest tone under the campus moon,
  same camera: RGB 192,180,210 (hue 262°, grey-lavender) → 219,196,214
  (hue 312°, pink); the darkest: 78,50,48 → 91,55,49. Dorm light is
  essentially unchanged (≤ 7 per channel).
- **Triangles:** base 7,298 → 8,034 (lash lines, ears, mittens).

Not done in this pass (honest list): the head's silhouette and proportions
are unchanged (the round icon head was kept); shoulders and elbows are not
re-skinned (V5 kept arms out of the head through the clips instead);
clothing/body intersections were reviewed for the new outfits through the
pose sheets and close-ups, not by an automatic mesh test.

## Planted-foot lock (V5 register M8)

`game/src/view/character_foot_lock.gd` (`CharacterFootLock`), a skeleton
modifier after the pose fade and secondary motion. In ground locomotion
CharacterView passes the gait phase and duty of the pose shown. While a foot
is in its stance and near the floor its ankle is pinned where it touched
down (world space); thigh and shin are re-solved by two-bone IK keeping the
animated knee plane; the foot keeps its orientation, turned back by the
body's yaw since touch-down (≤ 0.6 rad). At toe-off the pull returns in the
air with a critically damped spring starting from its own velocity. A pull
beyond 0.26 m lets the foot go. Off for runs on the spot (the lobby's Try
moves, after 0.25 s), in the air, in every non-ground state, during the tag
action layer and for animation-LOD characters; a teleport resets it.

Planted-foot slide, mean (m/s), `src/dev/motion_probe.tscn`, three starting
phases, same rig before and after (`docs/media/v6/characters/data/`):

| Scenario | V5 | V6 |
|---|---|---|
| 90° turn | 0.780 | **0.040** |
| 180° reversal | 0.919 | **0.113** |
| start / stop | 0.089 / 0.180 | 0.023 / 0.137 |
| speed changes | 0.164 | 0.008 |
| steady sprint | 0.455 | 0.051 |
| Night Watch run | 0.668 | 0.036 |
| prediction-correction stress | 0.657 | 0.110 |
| emote, walk away, emote | 0.409 | 0.365 |
| tag miss (lunge is a leap) | 0.987 | 0.651 |

Upper-body continuity is unchanged (largest snap per scenario within
0.15 cm of V5 in every scenario; `test_motion_v6` bounds it at 0.5 cm).
`foot_trail.tscn` + `tools/character/plot_foot_trail.py` draw the trails
(`foot_trail.jpg`).

**Cost (measured budget):** 20-29 µs per character and frame for the
modifier itself on this desktop (`motion_probe --bench` times it: 5,280
calls, three runs under load average ~15-20): two two-bone solves, no
physics queries. Whole-frame bench numbers on this contended machine varied
more between runs than with/without the lock, so no whole-frame claim is
made. Slopes and stairs keep the V5 behaviour (feet follow the origin's
plane).

## Emotes

Four looping clips, authored as code in `anims.py`:

- **Stargaze:** leans back and looks up, the right arm points up and out
  (the cheer's V, which clears the head) and traces a loop of stars, the
  other mitten on the chest; wonder face.
- **Victory Lap:** a jog round a 12 cm circle to the left (one lap, six
  steps) with the right fist pumping in a V. The root carries and turns the
  body; a new turning frame turns every FK delta with the root, and leg IK
  takes a foot yaw, so planted feet stay put. The circle is small enough for
  the lobby's marks.
- **Shush:** the face turns right and dips, the right mitten comes up 5 cm
  in front of the lips (arm IK with the target in head space: the short
  chibi arm only reaches a face turned toward it), a glance either way from
  the spine (head and mitten move together); sly face.
- **Moon Shuffle:** a smooth backslide in place: one foot flat and gliding
  back while the other rises on its toes, four glides per loop, bobbing on
  the beat with rolling shoulders and swaying bent arms; cool face.

`clip_check.py`: all 46 clips, no arm more than 1 cm inside the head (worst
0.9 cm: shush; victory lap 0.6; stargaze and moon shuffle 0.0); no mitten
inside the torso. Also new: `TC.EMOTE_LABELS`, emote icons in `Icons`,
`DormStage.EMOTE_S` (two passes), `CharacterView` states and expressions.
The lobby emote picker lists a Season 1 emote only once the player owns it
(`screen.gd`; the V4 six are unchanged).

## Thumbnails and preview

The Locker/Shop cards and the preview use the same `Portraits` renderer and
`CharacterView` as before. The `head` framing cut off tall hats (V5's party
hat and crown too, and the new pompom and owl ears), so `Portraits.FRAMINGS`
has a new `hat` framing and the wardrobe's `THUMB_FRAMING` uses it for
hats (the Shop/Locker should request hats with `"hat"`); `body` (outfits)
and `feet` (shoes) fit every new item unchanged. `src/dev/thumb_sheet.tscn`
renders the real cached thumbnails through `Portraits` for every outfit,
hat and shoe (`thumbnails.jpg`). The interactive preview is the dorm
stage's character; the outfit sheet shows each new outfit in idle, run,
sprint and an emote, and the motion test runs every new outfit through
start, stop, reversal, turn, running jump and landing, capture and
respawn, splash and emote. Tag lunges and carts are Night Watch states,
where the uniform replaces every outfit (tested).

## Fairness

- Cosmetics are presentation only: `test_appearance_changes_nothing_in_the_sim`
  runs the same inputs with the default look, a raincoat + headlamp + moon
  boots and an owl onesie and gets identical positions.
- The capsule, speed, reach and the gameplay camera are untouched; the
  victory lap's travel is the emote's drawn body only.
- Night-time visibility: the darkest outfit (Moonlight Runner) carries
  self-lit silver piping; the glow items make a runner *more* visible. No
  pixel-luminance study at gameplay distance was made (limit).

## Budgets

| | V5 | V6 |
|---|---|---|
| Typical look (base + pajamas + nightcap + slippers), LOD0 triangles | 23,366 | 24,102 |
| V6 outfits (part only) | | 5,860-11,126 |
| Showcase looks (the Shop pictures: outfit + its hair/hat/shoes) | | 19,552-27,492 |
| Heaviest look that can be worn with any V6 item | (heaviest V5 look 28,890) | ≤ that (`test_outfits_v6`) |
| All parts in the GLB (only the worn ones are drawn) | 99,170 (25 parts) | 210,734 (45 parts) |
| Clips | 42 | 46 |
| Materials | 1 shared + 1 two-sided (nightcap) | unchanged: every new part uses the shared material; per-character colours are instance uniforms |
| Draw calls per character | 4-5 | 3-6 (an outfit's own headwear adds one) |
| Skeleton modifiers per character | 3 | 4 (+ foot lock) |
| `runner.glb` size | 5.9 MB | 11.8 MB |

Godot generates LODs on import as before; no LOD was disabled.

## Tests

- `game/tests/test_outfits_v6.gd` (new, 6 tests): keys, names, costs and
  parts in the GLB; headwear/footwear/hood rules; emotes (wire order, clips,
  loops, states, lobby time, labels, icons, play and return to idle);
  triangle budgets; every new outfit through the motion scenarios with its
  parts shown throughout; appearance-independent simulation.
- `game/tests/test_motion_v6.gd` (new, 3 tests): turn and reversal slide
  with/without the lock, straight running untouched, the lock off on the
  spot, in the air and across a teleport.
- `test_profile` (every outfit × hat × shoe × hair, hair variants) and
  `test_emotes` (waits for the last emote's lobby time) follow the larger
  catalog. `test_motion_v5`, `test_motion` and `test_animation` pass
  unchanged.

## Rebuilding

See `tools/character/README.md` ("V6: adding an outfit, hat or shoe").

```sh
tools/character/build.sh                                  # ~40 s, prints every part's triangles
tools/.cache/bpyenv/bin/python tools/character/clip_check.py
tools/gd.sh --headless --path game --import
tools/run_tests.sh outfits_v6 && tools/run_tests.sh motion_v6
```

## Limits

- No phone measurements: frame cost, thermal effect and feel on device are
  unmeasured. The foot lock's cost was timed on a contended desktop.
- `runner.glb` doubled (5.9 → 11.8 MB of source; the exported, imported
  size was not measured in an iOS build).
- The `cost` values are placeholders for the commerce stream; which two
  outfits become direct Apple purchases is its decision.
- The emote picker hides unowned Season 1 emotes; the sim still accepts any
  known emote index from a peer (cosmetic only, as V4's paid dance).
- Head silhouette, shoulders and elbows were not reworked (see above).
- Foot lock: flat ground only; the residual slide is in the emote walk-away
  and tag-miss scenarios, where the legs blend in and out of a gait.
