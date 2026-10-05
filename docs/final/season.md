# Final release sweep · Season Pass preview and hierarchy

The SEASON workstream of the final release sweep: owner brief §4 in full,
§5's "keep the large rotatable Shop stage and use it to unify the Season
Pass", §8's UI consistency for the Season Pass and Challenges pages, and
§10's UI / preview evidence. Base: the integrated branch at `e3c2cd6`
(1.9 (9)). Evidence: [`../media/final/season/`](../media/final/season/README.md).

**What these notes can claim.** Everything was built and checked on desktop
Linux: headless Godot 4.7.2 tests, and the real Season Pass rendered by the
Mobile renderer on Mesa llvmpipe under Xvfb at the four device shapes
(layout, look, and scripted input at a fixed clock). Never frame rate,
touch feel or a phone GPU: **no device was used**. Every service-on picture
uses the **test-double service** (`game/src/dev/fake_commerce_service.gd`)
and says so on the picture and in its name (`svcon_test`); the game service
is **not deployed** and 1.9 ships with no service URL, so "service off"
(`svcoff`) is the shipped state. The two likeness skins are only "Record
Breaker" and "Dr. Doom" here; captures use the fictional player "Sleepy
Otter" (name cards show the test double's Game Center alias "Tester").

## Summary

The selected reward now stands on the **dorm stage the Shop and Locker
use**, at the left of the screen: a full figure about **2.9 times** the old
side preview's height on every phone (Record Breaker 70 → 204 pt on the
iPhone SE and 844×390, 80 → 231 pt on 926×428; iPad 206 → 348 pt), lit by
the room, starting in a three-quarter view and turned by one sideways
finger, a quarter-turn button, Reset view or the controller. Next to it the
side panel names the reward (tier and track, a state chip, the
requirements from the account, one action fixed at the bottom, the
description in a finger-scrollable area), with the Challenges page one tab
away. The pass panel on the right holds a compact season header with Claim
all, one restrained status line when claiming can't work, the navigation
chips and the Free / Premium track. Previewing never saves anything; the
saved look is back on the runner whenever the screen goes.

| Brief §4 outcome | Where it stands | Proof |
|---|---|---|
| 1 Larger, correct full model | 2.9× on phones (≥ 2× asserted), 1.7× on iPad (the old iPad panel was already large); head and soles inside the stage column with margins at all four shapes; the real skinned characters | `test_season_stage::test_stage_layout_fits_every_device`, measurements below, `after/*/a02`, `a03`, `a13` |
| 2 Shop/Locker preview language | the Shop/Locker stage and drag rate; three-quarter start; 360° drag about the character's own axis (stable pivot); Turn (a quarter) and Reset view; Run / Idle (an emote reward: Play) | `test_touch_ownership_on_the_season_pass`; clip |
| 3 User-owned rotation, Reduced Motion, controller, no zoom | a slow sway (the Shop's rate, ±0.3 rad, smaller than the Shop's ±0.5) stops for good at the first turn and never runs under Reduced Motion; steps and Reset glide (Reduced Motion: at once); right stick turns, R3 resets, shoulders switch the side pages; Turn / Reset buttons are the non-drag alternative; no zoom exists, so nothing can clip the camera | `test_no_automatic_motion_fights_the_player`, `test_featured_preview_renders_the_real_art_when_present` |
| 4 Touch ownership | `StageTurn`: one finger, sideways past the 10 pt dead zone, owns the turn; taps, vertical drags and second fingers don't turn; the track's finger scrolling (`TouchScroll`) and the description's vertical scroll are separate; release on lift, hide, background, focus loss and a sheet opening | `test_one_sideways_finger_owns_the_turn`, `test_touch_ownership_on_the_season_pass` |
| 5 Real assets, inspection at scale | both pass skins, the tallest and broadest outfits and two accessory-heavy Season looks inspected from four sides at the stage's scale; framing fixed; the skin switch is a clean one-frame swap; four art findings reported (below) | `skins/`, `switch_frames.jpg` |
| 6 App.stage restore, nothing saved | the saved look back on Back, every tab, the hub, a replacing screen and before a round starts; previewing a locked skin changes no look, inventory, Coins or claim | `test_previewing_never_saves_and_every_exit_restores_the_look`; clip's last frames |
| 7 Compact hierarchy, distinct states | "Season 1 · Premium" over "After Hours" and "Tier 43 / 100", the bar and "150 / 350 XP", Claim all beside it; one status line; Locked / Needs Premium / Ready to claim / Earned / Claiming… / Claimed / Equipped / an older service each read differently | `test_reward_states_are_distinct`, `test_earned_pending_and_older_service_read_differently` |
| 8 Name, tier, track near the preview; concise requirements | "TIER 50 · PREMIUM TRACK", "Record Breaker", "15,300 XP to unlock", "Needs Premium · 1,500 Coins", from the account; flavour text lower and scrollable | `a02`, `a13`, `a21` |
| 9 Primary actions | Claim (gold), Claim all, Get Premium / View Premium, Equip, View in Locker, Show Tier N; a locked reward never offers Claim; an earned reward during an outage reads "Earned · It stays earned" over a visibly disabled Claim | `a16`, `a17`, `a24`, `a27`, `a28` |
| 10 Navigation and progress runs | You're at, Next reward, 30 / 50 / 100 on one row that takes a shorter form on narrow panels; progress runs without the repeated "No reward" line; every threshold and claim identity unchanged | `test_navigation_and_milestones_fit_every_device`, `test_season100` |
| 11 Free / Premium legibility | FREE / PREMIUM row labels, the Premium cells' gold edge, the track named (and coloured) in the side panel's overline; names wrap; cell captions step down a size instead of being trimmed | `a10`-`a22` |
| 12 Tabs, scrolling, edges | Reward / Challenges are whole 44 pt targets; the description scrolls by finger; nothing pressable cut by the edges or the home indicator at any shape (`measure.json`: 0 cut off) | `test_season_pass_challenges_fit_with_both_rows_whole`, `measure.json` |

## The owner's screenshot, reproduced

IMG_3043 was not supplied; the brief describes it (Season Pass, service
off, "Rewards unavailable right now", Record Breaker selected). The capture
scene reproduces exactly that state on the 1.9 screen (`--set=before`: a
fresh profile, no service, the Tier 50 shortcut) at all four shapes:
`before/<device>/b02_svcoff_tier1_record_breaker`. It shows every point the
brief lists: a 70 pt figure swaying in the right Reward panel above five
lines of state text; "Season 1 · Af…" truncated in a header row that also
holds the tier, "Free track", the XP and the unavailable message; the
description cut at the panel's bottom ("The clock has a new …"); the
navigation chips, two tabs and four "No reward" columns; the dorm's own
runner a shadow behind the track panel.

## Defect register

Visible findings first, then what was found while measuring.

| # | Symptom | Reproduction | Cause (measured) | Fix | Evidence |
|---|---|---|---|---|---|
| S1 | Record Breaker a small figure in the right panel | service off, Tier 50 shortcut (`b02`) | Layout, not render resolution. `_fit_detail()` capped the picture at 30 % of the Reward page (38 % only on pages ≥ 540 units, i.e. the iPad) and `_show_preview()` gave the `Preview3D` that height; `Preview3D` already renders at the displayed pixel size. Measured figure: SE 70.4 pt, 844×390 70.1, 926×428 79.9, iPad 206.3 (Dr. Doom 67.1 / 66.8 / 76.1 / 196.7) | The selected reward on the dorm stage (`App.stage`, "wardrobe" framing) in its own column: 203.8 / 203.1 / 231 / 348 pt | measurements below; `before/` vs `after/` `02` |
| S2 | The figure sways by itself; it can't be turned | any featured skin | `_process()` swayed it ±0.85 rad around its three-quarter view; no input reached it | `StageTurn`: the player's turn, the Shop's sway only until the first touch, none under Reduced Motion | tests 1-3 below; clip |
| S3 | Dense header row; title truncated | `b01`/`b02` at SE, 844×390, iPad: "Season 1 · Af…" | Title, tier, "Free track", the bar, XP and "Rewards unavailable right now" (or Claim all) in one row; the title had stretch 0.01 | Two lines in the pass panel: "Season 1 · Premium" (overline, amber when Premium) over "After Hours" and "Tier 43 / 100", then the bar and "150 / 350 XP"; Claim all beside it | `a01`, `a10` |
| S4 | Requirements compete with flavour; the description runs below the panel | `b02`: five lines of state, then "The clock has a new" cut at the bottom | One state paragraph mixing the requirement, the rule ("No tier skips") and Premium; blurb and includes in the same scroll, under a 30 % picture | Requirement lines from the account ("15,300 XP to unlock", "Needs Premium · 1,500 Coins") under a state chip, always in view; the blurb, includes and the rule ("Season XP comes from online rounds and challenges. Tiers can't be bought.") in a finger-scrollable area; the action fixed at the bottom | `a02`, `a13`, `a21`; `test_premium_lock_reason_fits_the_iphone_se` |
| S5 | The outage said three times, in developer words | service off | Header "Rewards unavailable right now"; detail "This test build has no game service, so rewards can't be claimed yet."; Challenges "Preview: no game service in this build…" | One status line under the header: "Rewards unavailable right now" + "Season rewards and progress aren't available in this version."; the detail says what it means for that reward ("It stays earned"); Challenges: "Preview only. No progress or Season XP is added right now." | `a01`-`a04`; `test_pass_service_off_is_honest_and_still_fits` |
| S6 | The dorm's own runner barely visible behind the panels | any 1.9 Season Pass shot | "home" framing behind the panels and 0.6 shades | It is the preview now: wardrobe framing in the stage column, the Shop's shades (0.45 right, none top-left) | `after/*` |
| S7 | Busy: four "No reward" columns in view | `b01`-`b04` | a "No reward" foot in each of the 14 progress-run columns | dropped; the numbered steps, the missing picture, the run's detail ("Progress tiers · No reward") and its accessibility name say it | `a11` |
| S8 | iPad: the preview's hair cut at the top of its picture | iPad, Tier 50 (`before/ipad/b02`) | the preview's camera was aimed for a square picture; the iPad's taller picture put the head out of its frame | the stage frames the tallest look between the column's top and its tools | `after/ipad/a02` |
| S9 | A failed Game Center sign-in read "You're offline" | identity signature fails | `Wallet.service_state()` maps Cloud's "error" to "offline" | The pass tells them apart (a "connection" error vs any other): "Game Center didn't sign in. Your rewards are kept; try again later." / "You're offline. Claiming comes back when you reconnect." (Wallet unchanged) | `a27`, `a28`; `test_earned_pending_and_older_service_read_differently` |
| S10 | A locked Premium reward hid its purchasing requirement in prose, with no action | free player, a Premium tier not reached | `locked` had no action | "Needs Premium · 1,500 Coins" line and "View Premium" | `test_pass_free_premium_and_claim_states` |
| S11 | "Wear it in the Locker" didn't wear it | a claimed outfit | it only opened the Locker | Equip (the Locker's own rule, `Save.apply_appearance`: owned items only, never spends; the party sees it), then "Equipped" and View in Locker | `a23`, `a24`; `test_reward_states_are_distinct` |
| S12 | Two 3D renders while the pass was open | any featured skin | the dorm stage plus a `Preview3D` SubViewport (MSAA 4×) | one: the stage already behind the menus | code |
| S13 | Jumps left half a column at the track's left edge | any jump; visible in `before/*/b02` (the "44" column cut at the left) | the track scrolled to 35 % of its width with no snapping | the scroll starts at a column's edge | `a01` |
| S14 | "Name ca…" captions on narrow cells | 844×390, service off | fixed 19 px caption | steps down to 15 px before trimming | `a04` |
| S15 | "Rewards unavailable right now" in 1.9 | any build of 1.9 | `game/config/service.cfg` has no URL: `Cloud.configured()` is false, `Wallet.service_state()` is "off". The service is not deployed | **Not faked.** A deployment dependency (owner, COMMERCE_SETUP): once a build has the service URL and admission key, the same screen shows the live states captured here with the test double | `a01` vs `a10` |

Found and fixed while building the new screen (not in 1.9): the pass panel
could be widened past its column by the navigation chips (they now take a
shorter form and sit in a strip that can't widen the panel); the runner
reappeared behind a 2D picture when the stage re-placed its characters
(the screen keeps it aside every frame, and the tools row keeps its height
so the framing never jumps).

### Art findings at the larger scale (not fixable in SEASON files)

Inspected on the stage at the 844×390 scale, from the three-quarter start,
both profiles and the back (`skins/inspection_p14_*.jpg`, zooms in
`skins/`). The two pass skins frame, light and turn cleanly; Record
Breaker's wristband, smile, hair and sandals read; Dr. Doom's tie, fringe
and shoes read. Visible at this scale, in the generated garments (FIT /
skins art, `tools/character/`), reported for those streams:

| Look | Finding | View |
|---|---|---|
| Night Owl, Bedtime Bandit (onesies) | the belly patch is a flat disc standing off the belly in profile | `skins/zoom_night_owl_profile.jpg` |
| Night Owl, Bedtime Bandit | the hood's face-opening ring reads as a flat ring forward of the face in profile | same |
| Dr. Doom | in profile the jacket's front edges show as thin dark strips off the shirt, and the jacket's back as a flat slab | `skins/zoom_dr_doom_profile.jpg` |
| Glow Jogger + Headlamp | the headlamp band reads as a thin halo above the hair from behind | `skins/inspection_p14_bottom.jpg` |

The tallest look measured (Pumpkin Pajamas with the party hat, 1.75 m in
the rest pose) stays inside the stage's 1.78 m framing. Switching Record
Breaker → Dr. Doom is a clean one-frame swap in the same pose with the
panel's text changing on the same frame (`switch_frames.jpg`, from the
clip); no hop is played (the Shop's arrival hop would hide nothing here).

## Layout decision and why

Worked out from the real layout budget at landscape-phone scale before
choosing (canvas units; 44 pt = 81-85 units on the phones, 55 on the iPad;
the figures for the options not chosen are estimates from that budget, the
chosen one is measured):

| Option | Figure on 844×390 | Cost |
|---|---|---|
| A larger preview in the old side panel | ≤ ~1.6× (the panel is ~300 units wide and its text needs the height) | keeps the ghost runner behind the track |
| A bottom strip for the track, stage above | ~1.4× (the strip needs ~340 of 552 units) | cells at the 44 pt floor |
| Stage column with the reward card under the figure | ~1.7-2.0× | the card ~245 units tall: the description has no room |
| **Stage column + side panel + pass panel (chosen)** | **2.9×** | the pass panel is narrower: the chips take a shorter form; about three reward columns (and the runs between) in view |

The chosen layout is the brief's preferred direction: the Shop/Locker's
large left stage for the selected outfit, the compact name / tier / track /
requirements / actions next to it (the side panel, which keeps its Reward /
Challenges pages), and the Free / Premium track in the remaining space. It
works at the smallest phone (SE 1334×750) without a larger side preview:
both rows stay whole with cells of 127×159 units (100×125 with the service off), the tools are whole 44 pt
targets, nothing is cut. Widths come from the allocated content width
(stage 23 %, side 25 %, the pass panel the rest); the figure is fitted to
the stage column (the tallest look's height between its top and the tools,
and a 1 m wide figure across it).

The Reward page now opens first (Pass 8 opened Challenges first): it names
what the stage shows. Challenges is one tab or one shoulder button away.

## Measurements

Figure height: the visible parts' rest-pose bounds, top to soles, projected
at the model's centre line, in iOS points (`_figure()` in
`season_final_capture.gd` and `test_season_stage.gd`, same method before
and after).

| Device | Record Breaker before → after | Dr. Doom before → after | Figure on screen (units, 720-unit-high view; iPad 960) | Cells, service off: before → after | Cells, test double: after | Pressables cut off (24 after shots) |
|---|---|---|---|---|---|---|
| SE 667×375 | 70.4 → **203.8 pt (2.89×)** | 67.1 → 194.2 pt (2.89×) | top 194, soles 585 (top row ends 109) | 122×153 → 100×125 | 127×159 | 0 |
| 844×390 | 70.1 → **203.1 pt (2.90×)** | 66.8 → 193.5 pt (2.90×) | top 188, soles 563 | 116×145 → 92×115 | 119×149 | 0 |
| 926×428 | 79.9 → **231.3 pt (2.89×)** | 76.1 → 220.3 pt (2.89×) | top 183, soles 572 | 125×157 → 99×124 | 126×158 | 0 |
| iPad 1024×768 | 206.3 → **348.2 pt (1.69×)** | 196.7 → 331.9 pt (1.69×) | top 302, soles 737 | 192×240 → 133×240 | 133×240 | 0 |

(`before/*/measure.json` `b02`/`b03`, `after/*/measure.json` `a02`/`a03`/
`a13`; the projection measures the bounds' centre line, so it reads a few
points under the drawn silhouette with the hair: on the SE's `b02` the
drawn figure is ~74 pt for the measured 70.4.) The iPad's old picture
already took 38 % of a tall panel; there the figure is fitted to a 1 m wide
column so its head stays inside it. Cells with the test double are the old
size or larger; with the service off they are smaller because the status
line now has its own row (still whole 44 pt targets with both rows whole).
About three reward columns plus progress runs are in view (four before);
the navigation chips take their one-line form on the phones. Every
measured shot keeps the figure's head below the top row and its soles
above the tools, and the stage, side and pass columns inside the safe area
(`test_stage_layout_fits_every_device`).

## Service states

| State | How it arises | Pass | Captured |
|---|---|---|---|
| Off (1.9 as shipped) | no service URL | status "Rewards unavailable right now · Season rewards and progress aren't available in this version."; no Claim all; earned rewards "Earned · It stays earned"; Premium "View Premium" with "Premium can't be bought right now."; the whole pass and both skins browsable | `a01`-`a04` |
| Signed out | Game Center not signed in | "Sign in with Game Center to claim rewards." | `a29` |
| Failed sign-in | Game Center's identity fails | "Game Center didn't sign in. Your rewards are kept; try again later." over the last snapshot (earned stays earned) | `a27` |
| Offline | no network at sign-in | "You're offline. Claiming comes back when you reconnect." | `a28` |
| Claim in flight | the network drops while a claim is sent | "Claiming…" chip and disabled action; Claim all counts only what isn't queued | `a25` |
| Older (30-tier) service | a service still on catalogue version 2 | "Earned", Claim disabled, "Claiming for this tier isn't open yet." | `a26` |
| Live (test double) | signed in, synced | Claim / Claim all / Get Premium / Equip work through the real wallet | `a10`-`a24` |

The live states use the existing test double only; **no claim against a real
service has been made** (none is deployed).

## How verified

All on desktop Linux, headless, `--fixed-fps 60`:

```
tools/gd.sh --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd -- \
  test_season100.gd:,test_menus_layout.gd:,test_challenges.gd:,test_shop_ui.gd:,test_season_stage.gd:,\
  test_screen_cycles.gd:,test_stage_drag.gd:,test_catalogue.gd:,test_lobby_music.gd:
  -> 70 tests, 8587 checks, 0 failures
tools/gd.sh --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd -- test_v7_screens.gd:,test_wallet.gd:,test_lobby.gd:
  -> 27 tests, 6573 checks, 0 failures
```

New: `game/tests/test_season_stage.gd` (7 tests): StageTurn ownership on its
own (tap, dead zone, vertical drag, second finger, leaving the area, lift,
hide, background, disabled); no automatic motion against the player
(sway, Reduced Motion, Turn, Reset); ownership on the real screen at SE
(stage drag turns and selects nothing, track swipe scrolls and never turns,
the description scrolls by finger, Turn, R3, shoulders, a sheet opening
mid-drag releases it); previewing never saves and five exits plus a
practice round restore the look; the reward states read differently and
Equip works; earned / claiming / older service read differently with the
failed sign-in and offline copy; the layout at four shapes with the figure
≥ 2× the old height on phones. Updated (geometry and copy that legitimately
changed): `test_season100` (chips' short form, requirement above the
description, the stage instead of `Preview3D`, Equip, the new reason copy),
`test_menus_layout` (status line said once, View / Get Premium, a locked
Premium reward shows View Premium), `test_challenges` (Reward opens first;
no developer wording), `test_shop_ui` (Get Premium). Every tier/XP
threshold, claim key and wallet rule is untouched (`economy.gd`,
`wallet_service.gd`, the catalogue and the service are not changed).

Captures: `tools/capture_final_season.sh OUT before|after|skins [devices]`
(`FAST=1` for 844×390, 926×428 and the iPad at their canvas size with the
device's point scale and safe area); the clip:
`tools/capture_final_season_reel.sh OUT.mp4`.

## Evidence index

[`../media/final/season/README.md`](../media/final/season/README.md) lists
every picture. In short: `before/<device>/` (the 1.9 screen, 4 shots),
`after/<device>/` (the rebuilt screen, 24 shots: service off, a regular
Premium player, a Free player, a finished pass, a claim in flight, an older
service, failed sign-in, offline, signed out), `skins/` (the inspection
sheets and zooms), `season_pass_clip.mp4` (normal speed) and each folder's
`measure.json`.

## Owner and integrator dependencies

- **The game service (owner).** "Rewards unavailable right now" in 1.9 is
  the honest service-off state: `game/config/service.cfg` has no `url` or
  `admission_public_key`. The live claim, Premium and Equip-after-claim
  paths need the deployed service and a build that carries its public URL
  and admission key (COMMERCE_SETUP; the COMMERCE stream owns the endpoint
  routing). Nothing in the Season Pass needs another change for that: the
  same screen shows the live states captured here with the test double.
- **Merge (integrator).** No shared code file conflicts are expected:
  `dorm_stage.gd` (LIGHT), `app.gd`, `shop_screen.gd`, `creator_screen.gd`
  and `wallet_service.gd` are untouched. Re-run the focused suites above
  after merging LIGHT, since the figure is lit by the dorm stage.

## Open items

- **No device.** Drag feel (rate, dead zone), the stage's frame time with
  the pass open on an A12 phone, and Reduced Motion on iOS are unverified.
  Highest-value device checks: open the pass on an iPhone SE-size phone and
  a 6.1" phone; tap Tier 50 and Tier 100; drag each round once; scroll the
  track; switch to Challenges and back; leave with Back. Pass: the figure
  turns only with a sideways drag, the track scrolls only on the track, the
  runner on Home wears the saved look.
- **No live service.** Every service-on state was seen with the test
  double only; the real states need the deployed service (S15).
- **Art findings** above go to the FIT / skins streams.
- The Shop and the Locker still use `CreatorScreen.StageDrag` (any drag
  turns, no Reset); adopting `StageTurn` there is a few lines each, left
  for their owners.
- LIGHT's dorm lighting changes (merged separately) will change how the
  figure is lit here; the framing doesn't depend on them.

## Files

SEASON-owned: `game/src/ui/season_screen.gd` (rebuilt layout, stage
preview, states and copy), `game/src/ui/stage_turn.gd` (new, the shared
turn control). Tests: `game/tests/test_season_stage.gd` (new),
`test_season100.gd`, `test_menus_layout.gd`, `test_challenges.gd`,
`test_shop_ui.gd` (Season assertions only). Dev only (`src/dev` is not
exported): `game/src/dev/season_final_capture.*`,
`game/src/dev/season_reel.*`; tools: `tools/capture_final_season.sh`,
`tools/capture_final_season_reel.sh`. Outside the list: one bullet of
`docs/ECONOMY.md` ("In the game · Season Pass / Service unavailable").
`app.gd`, `dorm_stage.gd`, `shop_screen.gd`, `creator_screen.gd` and
`wallet_service.gd` are **not** changed: the restore lives in the screen
(`restore_stage()` on Back, any navigation and `_exit_tree`), and the stage
is driven through its existing `set_mode` / `set_wardrobe_region` /
`local_character` API.

## Proposed text for integrator-owned docs

**TEST_REPORT.md (final sweep, Season Pass):** "Season Pass rebuilt around
the dorm stage (docs/final/season.md): `test_season_stage` (7 tests, new)
plus the updated `test_season100`, `test_menus_layout`, `test_challenges`,
`test_shop_ui`: 70 tests / 8,587 checks in the focused run, 0 failures.
Desktop captures at SE, 844×390, 926×428 and iPad with the test-double
service; a normal-speed Movie Maker clip. No device, no live service."

**docs/testflight/what_to_test.txt:** "Season Pass: tap Tier 50 or Tier 100
(or any outfit): it stands large on the left. Drag sideways on it to turn
it (Turn and Reset do it without dragging); the pass track still scrolls
by finger. Leave the pass: your runner wears your own look."

**docs/FINAL_RELEASE_SWEEP.md (Season Pass line):** "The selected reward is
shown on the large dorm stage (about 2.9× the old preview on phones), with
drag/Turn/Reset/controller rotation that never fights an automatic sway,
a compact season header, one status line when claiming is unavailable,
concise requirements and fixed actions. Previewing never saves. Remaining:
device feel; the live service (service.cfg has no URL); four garment
findings for the FIT/skins streams."
