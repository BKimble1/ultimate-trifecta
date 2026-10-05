# Pass 8 skins: six rotating Shop outfits

Workstream: brief §7 ("Create six complete new rotating skins") and the
new-outfit parts of §12. Branch base: `018b8d0` (1.7 (7)). Media:
[`docs/media/pass8/skins/`](../media/pass8/skins/).

**What these notes can claim.** Geometry and containment were measured on the
generator's output and on the imported `runner.glb`; motion through the real
rig and `CharacterView` at a fixed 60 Hz (headless); pictures and the reel are
Godot 4.7.2's Mobile renderer on Mesa llvmpipe under Xvfb. That shows shape,
colour, fit and timing. It says nothing about frame rate, heat or feel on an
iPhone: no device was available.

## What shipped

Six complete outfits, each real modelled geometry on the shared rig (one
`runner.glb`, one skeleton, every clip shared), registered in
`game/src/view/cosmetics.gd` with new, never-reused wire IDs. The keys and
prices are the ones agreed with the Shop stream (it adds the `catalogue.json`
items and the rotating offers).

| Key | Name | ID | Coins | Part(s) | Triangles (LOD0) | Draws its own | Head |
|---|---|---|---|---|---|---|---|
| `midnight_mechanic` | Midnight Mechanic | 16 | 900 | `mechanic` | 12,562 | work boots | player's hat and hair |
| `moonwalk_cadet` | Moonwalk Cadet | 17 | 1,200 | `cadet` + `acc_cadet_cap` | 12,616 + 3,812 | space boots | cap + lifted visor with no hat; else the chosen hat |
| `pumpkin_pajamas` | Pumpkin Pajamas | 18 | 800 | `pumpkin` + `acc_pumpkin_cap` | 10,066 + 2,796 | striped socks | pumpkin cap with no hat; else the chosen hat |
| `arcade_sprinter` | Arcade Sprinter | 19 | 900 | `arcade` | 11,496 | high-tops | player's hat and hair |
| `cloud_nine` | Cloud Nine | 20 | 1,000 | `cloud` | 11,940 | cloud slippers | hood up (replaces hat and hair) |
| `bedtime_bandit` | Bedtime Bandit | 21 | 1,000 | `bandit` | 11,475 | footed paws | raccoon hood up (replaces hat and hair) |

Names were kept from the brief's table: the finished art fits them.

### Exactly what each one includes (`Cosmetics` `includes`, shown to buyers)

- **Midnight Mechanic:** cobalt work coverall with a metal zip front, a pointed
  collar, a back yoke seam and a webbing belt with a metal buckle; sleeves
  rolled to mid-forearm (a thick double roll) over bare forearms; cream work
  gloves with rolled gauntlets (the mitten's own shape grown 4.5 mm, so they
  follow the hand exactly); stitched patches: an orange wrench patch on the
  chest, a large orange gear patch on the back (what the follow camera sees),
  a round gear patch on the right sleeve (running-stitch thread geometry);
  a flap chest pocket with a snap, darker knee patches and a cargo leg
  pocket; turned-up trouser cuffs over tan lace-up work boots with a welt
  stitch, toe cap, padded collar and pull tab. No tools hang from it.
- **Moonwalk Cadet:** soft quilted ivory space suit (quilting in the
  silhouette, seam lines in colour), a chunky teal metal neck ring and padded
  collar, a teal belt, chest stripes and sleeve piping, a chest control panel
  (three glossy buttons and a slider: no lights), a navy mission patch with a
  gold crescent and star on the left sleeve, a compact life-support pack on
  the back, ivory gloves with teal gauntlets, puffy trousers tucked into
  compact space boots with an instep strap. Headwear (no hat chosen): a
  padded cadet cap with a teal centre stripe, teal ear pads and a curved
  tinted visor flipped up over the forehead on two arms. The visor's lowest
  point is 1.33 m (the brows top out near 1.30 m raised): the face is never
  behind it.
- **Pumpkin Pajamas:** a rust pajama top whose body is eight soft pumpkin
  lobes with darker grooves, cream hem piping, a cream placket with
  stem-brown buttons, a leaf collar (two green leaf points with veins) and a
  cream pocket with a leaf; cream trousers with fine rust pinstripes cut at
  mid-shin with a rust band; soft rust-and-cream striped socks with ribbed
  tops and cream heels and toes (the feet are in socks). Headwear (no hat
  chosen): a knitted pumpkin cap with eight lobes, a ribbed rust band, a
  stem, a leaf and a curl of vine.
- **Arcade Sprinter:** a cropped retro track jacket in satin cyan with a
  magenta chevron yoke, white piping along the yoke, a magenta stand collar
  with a white stripe, a white zip, magenta sleeves with cyan forearms and
  white piping, striped knit cuffs and a white rib waistband with magenta
  stripes; yellow pixel lightning bolts on the chest and (large) the back;
  navy track shorts with white side piping and magenta hems; striped tube
  socks; rounded white high-tops with magenta panels, cyan collar and
  midsole stripe, laces and a yellow star.
- **Cloud Nine:** a plush sky-blue hoodie with a cream rib hem, a cloud-shaped
  pocket with its opening, a cloud on the back and on the back of the hood,
  cream cuffs and drawstrings with puff ends; the hood worn up with a rim of
  white cloud puffs round the face and a cloud crown on top; plush joggers
  with cream cuffs; cushioned, lumpy cloud slippers on soft blue soles.
- **Bedtime Bandit:** a charcoal raccoon sleep suit (a mid charcoal: see
  *Concealment*) with a cream belly and a gold moon on the chest; the hood up
  with a cream rim, round ears with light insides and cream tips, a bandit
  mask band above the face opening with two small hood eyes and cream
  brows; a ringed raccoon tail; footed paws with cream soles and dark toe
  beans.

### Decisions

- **Footwear is part of every outfit** (`Cosmetics.OUTFIT_OWN_SHOES`, as the
  V6 raincoat's boots). Each design's legs end over or into its footwear
  (turn-ups over boot shafts, suit legs tucked into boots, capri trousers
  over socks, a footed suit); a chosen shoe would leave a gap or poke through,
  and one grant per Shop item keeps the offer exact. The copy says
  "worn instead of your shoes with this outfit".
- **Head pieces.** The cadet and pumpkin caps are outfit headwear
  (`OUTFIT_HEADWEAR`, shown only with no hat, like the V6 courier cap, and
  hair-ruled as a cap: the tuft without its forelock, curls only below the
  edge, bun knots hidden). Any chosen hat wins. Cloud Nine and Bedtime
  Bandit are hoods (`HOOD_OUTFITS`, like the duck, frog and owl). Their face
  opening is a little wider than the shipped hoods'
  (`parts._hood(..., opening=HOOD_OPEN)`; the shipped hoods are unchanged), so
  the rim clears the brows.
- **No simulation.** Hoods, ears, caps, visor, ear pads, stem, vine, puffs
  and pack are rigid on one bone; the tail is rigid on the hips and shaped to
  stay clear of the legs and the ground. No spring bone was added, so there
  is no secondary-motion cost and nothing can swing into the body.
- **No lights, particles or capes**: no part uses the emissive class; the visor
  is the existing tinted-lens class (opaque, in the shared shader).
- **Role identity.** The mechanic is cobalt (not the Watch's navy), with no
  cap, badge, hi-vis band or flashlight; every new outfit is measurably
  lighter than the uniform (below). The Night Watch always wears its uniform
  (tested for all six).
- **Nothing changes the simulation**: capsule, speed, reach, tags and stamina
  are untouched (tested: identical traces with a tail and a visor).

## Materials, skinning, normals

One shared `ShaderMaterial` for every new part (no new material, no
two-sided variant); classes used: cloth, V8 satin (the arcade jacket),
rubber/leather (soles, boots, high-tops, the cadet's teal trim), V8 metal
(zips, buckles, snaps, the neck ring, valves, the mission patch's gold),
gloss (buttons, the hood eyes), tinted lens (the visor, with analytic
normals as V8's goggles). Skinning follows the established helpers: torso
garments `torso_w`, sleeves `arm_w`, legs `leg_w`, footwear the V6 boot
weights (foot below 11 cm, shin above), gloves the base mitten's own
forearm/hand weights, head pieces rigid on the head, the tail rigid on the
hips. Normals: the build's 66° sharp-edge rule (patch and sole rims stay
crisp) and analytic normals on the visor.

## Containment through every clip

`tools/character/outfit_check.py` (new) evaluates every clip (53) at 60 Hz on
the real rig. Data: [`data/outfit_check.json`](../media/pass8/skins/data/outfit_check.json).

| Check | Result |
|---|---|
| Arms (sleeve and glove radii) against the caps, visor, ear pads, stem, vine | 0.0 cm in every clip (cadet, pumpkin) |
| Arms against the cadet's pack | 0.0 cm in every clip |
| Tail against arm and leg capsules (suit radii) | 0.0 cm in every clip |
| Tail above the ground (splash clips excluded: they sink the body into water) | ≥ 5.4 cm (sitting in `dizzy`/`flop`) |
| Mittens inside the gloves (rest pose, 1,080 mitten vertices) | 0.0 mm outside (mechanic, cadet) |
| Arms against the two hoods | equal to the shipped Night Owl and Duck hoods in every clip (worst 7.5 cm in the splash shake-off, 6.9 victory lap, 5.9 dance, 4.9 wave, 6.4 cm features in the shush); stargaze 0.8 cm against a cloud puff |

The hood row needs saying plainly: several existing clips (owned by the
animation stream) bring the hands to the head (splash shake-off, wave, dance,
victory lap, shush, stumble, hard landing). On a bare head that clears; any
hood worn over the head is touched there, and the shipped hoods are met the
same way. The new hoods were made exactly as large as those (3.5 cm), so they
are no worse; the checker fails a new hood that is entered more than the
shipped hoods plus 0.5 cm (shell) / 1 cm (features), and every other piece
at 1 cm. Making a hand rest *on* a hood in those gestures needs a clip or
pose change (open item 3).

Face: the new head pieces lie outside the head (hoods ≥ 4 mm, caps' ear pads
seated like the headphones' cups) and cover none of the eyes, brows or mouth
seen from the front (`test_outfits_p8`).

## Budgets

`src/dev/char_budget.tscn` on both trees ([before](../media/pass8/skins/data/budget_before.json),
[after](../media/pass8/skins/data/budget_after.json)); LOD0 triangles.

| | Before (`018b8d0`) | After |
|---|---|---|
| Heaviest look (robe + body + bob + beanie + slippers + freckles) | 32,834 | 32,834 (unchanged) |
| Heaviest look with a Pass 8 outfit (cadet + cap + bob + freckles) | – | 30,186 |
| Heaviest look per outfit: mechanic / cadet / pumpkin / arcade / cloud / bandit | – | 29,772 / 30,186 / 27,276 / 28,706 / 21,602 / 21,137 |
| Draw calls, heaviest look | 7 | 7 |
| Draw calls, any Pass 8 look | – | ≤ 6 (hooded: 3) |
| Materials on the heaviest look / variants in the asset | 1 / 2 | 1 / 2 |
| Parts in the asset | 45 | 53 |
| All parts (only worn ones are drawn) | 217,010 | 293,773 |
| Default look | 24,850 | 24,850 |
| `runner.glb` | 12,316,044 B | 16,064,992 B (+30 %) |
| Imported scene (what an export ships) | 5,095,346 B | 6,547,981 B (+28.5 %) |
| Runner looks enumerated | 6,000 | 8,400 |

Each outfit part, footwear included, is under 13,000 triangles and each
headwear under 4,500 (tested). The first builds were heavier (mechanic
16.1k, cadet 14.3k); stitches, gloves, rings, boots and puffs were simplified
until every outfit fit. The asset grows because the one shared GLB carries
every part (all parts are loaded once and shared by every runner; only the
worn ones draw); that growth is the cost of six complete outfits and is the
number to watch on device.

## Art version and thumbnails

`build_character.py` `ART_GEN` 9; `CharacterArt.VERSION` is regenerated with
the GLB (`v9-` + its SHA-256 prefix), so every `Portraits` key changes and no
thumbnail of the previous asset can be reused. Thumbnails are rendered at run
time through the existing cache path; `thumb_sheet.tscn` renders the real
cached pictures ([`thumbnails_portraits.jpg`](../media/pass8/skins/thumbnails_portraits.jpg)).

## Concealment and role readability

Area-weighted mean albedo (linear luminance) of each outfit's fixed colours:
mechanic 0.164, cadet 0.712, pumpkin 0.456, arcade 0.397, cloud 0.613,
bandit 0.327; the darkest outfit already sold is Moonlight Runner (0.062) and
the Night Watch uniform 0.047. `test_outfits_p8` requires every new outfit
to be no darker than the darkest Shop outfit before it and at least 1.5x the
uniform. The Bedtime Bandit's charcoal was lightened twice during the pass
for this.

## Tests

- `game/tests/test_outfits_p8.gd` (new, 7 tests, 422 checks): keys, IDs,
  prices, names, includes copy against the rules, wire round trip, owned-key
  migration; footwear/headwear/hood rules for every hat, shoe and hair; the
  Night Watch never wears them; budgets against the heaviest earlier look,
  ≤ 7 draw calls, one surface per part, the shared material; head pieces
  outside the head and off the face, the visor above the brows; concealment;
  every outfit through start, stop, reverse, turn, sprint, jump, dive,
  tagged/respawn, splash and emote with its parts shown (and only they) and
  the same pose as the default look; identical simulation traces.
- Passing after the change: `test_outfits_p8`, `test_outfits_v6`,
  `test_characters_v7`, `test_portraits`, `test_profile` (all 4,200 outfit × hat × shoe × hair combinations),
  `test_purchases`, `test_emotes`, `test_wardrobe`, `test_shop_ui`.
- `test_catalogue::test_every_referenced_item_exists_in_cosmetics` fails on
  this branch alone ("every priced Cosmetics item has a catalogue entry": the
  six `outfit:*` ids). It passes once the Shop stream's `catalogue.json`
  items are merged.
- `tools/character/outfit_check.py`: 0 failures. `clip_check.py` is
  unaffected (no clip or rig change).

## Evidence (`docs/media/pass8/skins/`)

| File | What |
|---|---|
| `campus_gameplay_front.jpg`, `campus_gameplay_back.jpg` | All six at the follow camera's distance (6.2 m, fov 66) on the campus at night, facing and from behind, with the default runner and a Night Watch |
| `dorm_lobby_front.jpg`, `dorm_lobby_back.jpg` | All six on the lobby's marks in the dorm light |
| `closeups_campus.jpg`, `closeups_dorm.jpg` | Each outfit: body, back, head, feet |
| `actions_campus.jpg` | Each outfit through run, sprint, air rise/fall, dive, dive land, hard land, tagged sit, splash, cheer, wave, stargaze |
| `skintones_campus.jpg`, `skintones_dorm.jpg` | Tones 1, 3, 6, 8 on every outfit |
| `thumbnails_portraits.jpg` | The real cached Shop/Locker thumbnails |
| `reel_moonwalk_cadet_actions.mp4` | The heaviest new look (cadet + cap and visor) through start, sprint, jump, dive, tagged and respawn, splash; behind and side; Movie Maker fixed 30 fps, normal speed, labelled |
| `data/` | budget before/after, containment data |

Reproduce: `character_lineup.tscn -- --lineup=pass8,pass8back --light=campus|dorm`,
`--lineup=custom --shots-file=...`, `thumb_sheet.tscn -- --fields=outfit --keys=...`,
`tools/character/capture_skin_reel.sh OUT.mp4 moonwalk_cadet`.

## Provenance and licences (for ASSET_LICENSES.md)

- Midnight Mechanic, Moonwalk Cadet, Pumpkin Pajamas, Arcade Sprinter, Cloud
  Nine and Bedtime Bandit (outfits, caps, visor, footwear, hoods, tail,
  patches, pixel bolts, cloud and gear outlines): original designs written
  for this project, generated by `tools/character/outfits_p8.py` (with
  `parts.py`, `kit6.py`, `outfits_v6.py`, `rig.py`, `geo.py`) into
  `game/assets/characters/runner.glb`. Same licence and ownership as the
  rest of the generated character asset; no third-party meshes, textures or
  references were used, and no protected character was copied.
- Build tool: Blender as a Python module (bpy 4.5.4, GPL), build time only,
  not shipped (unchanged).

## Open items and owner dependencies

1. **Shop stream:** the six `catalogue.json` items (`outfit:<key>`, Coin prices
   as above, rotating offers). Until merged, `test_catalogue` reports the six
   as orphans and the Shop cannot sell them.
2. **Shop copy:** `shop_screen.gd` `_includes_text` appends "Your colours,
   hair, hat and shoes stay as you set them in the Locker" to every non-hood
   outfit and "your shoes stay as you set them" to hoods; that is wrong for
   outfits with their own footwear (the raincoat already, and all six new
   ones). `Cosmetics.outfit_replaces(key)` (new) returns `["hat", "hair",
   "shoes"]` subsets for that copy. Not changed here (Shop-owned file).
3. **Animation stream:** the hands-to-head gestures listed above meet any
   hood (shipped and new alike). A hood-aware arm offset or clip tweak would
   make the hands rest on the hood.
4. **Bots** pick any outfit key (`Cosmetics.bot_cosmetic`, unchanged), so bots
   can wear rotating outfits as they already wear the V6 Shop outfits. If
   the Shop wants rotating skins kept off bots, that is a one-line filter.
5. **Device:** no phone was available. Draw calls and triangles are within
   the earlier heaviest look; the shared asset's memory grew (table above)
   and should be watched in the next device profile.

## Integrator steps at merge

1. Merge this branch; resolve `runner.glb`, `runner_manifest.json` and
   `game/src/view/character_art.gd` by rebuilding, not by picking a side:
   `tools/character/build.sh` (it includes the merged `anims.py` and these
   outfits), then `tools/gd.sh --headless --path game --import`.
2. Re-run `tools/.cache/bpyenv/bin/python tools/character/outfit_check.py` and
   `clip_check.py` (the dive-land and other clip changes must keep the
   tail, caps, visor and pack clear: exit 0), then `test_outfits_p8`,
   `test_outfits_v6`, `test_characters_v7`, `test_portraits`, `test_profile`
   and, with the Shop stream merged, `test_catalogue`.
3. Copy the licence lines above into `ASSET_LICENSES.md`.
