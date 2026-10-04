# V7 menus notes: layout budget, Locker and Emotes, Season Pass, Shop

The menus workstream of V7 (brief §4, §5, §6 and the Shop part of §7).
Evidence: [../media/v7/menus/](../media/v7/menus/README.md).

**What these notes can claim.** Everything was measured on a shared
desktop Linux machine:

- **Bounds:** the final allocated rects of the running screens, at seven
  landscape device shapes. Headless tests do this with an emulated point
  scale and safe area (`UIKit.emulation`).
- **Pictures:** captures from Godot 4.7.2's Mobile renderer on llvmpipe.
- **Service-on states:** they use the test adapters (the test-double
  service and the simulated App Store), labelled as such.
- **Not covered:** no iPhone or iPad was used, so touch feel and on-device
  rendering are unverified. The owner's screenshots IMG_3016-3020 were not
  available; their defects were reproduced from the brief's table.

## Issue register

All units are canvas units: 720 per screen height on a landscape phone,
about 1.85 per point. "p14" means the 844×390 pt phone layout.

| # | Screen (owner shot) | Symptom | Measured cause | Fix | Verification |
|---|---|---|---|---|---|
| M1 | Locker, Emotes (IMG_3016) | Gold emote glyphs sit past their wells and across card edges | `ItemCard.setup()` put the `IconRect` on a centre anchor, then added a positive `position` of `img * 0.2`. At p14 the glyph's centre was (+88, +88) units from the well's centre, and all 7 emote glyphs extended past their wells (`before/p14/measure.json`) | The glyph fills its well by anchors (full rect, 8-unit inset), so it is centred by construction. The well clips as a guard only. The icon set itself was redrawn (M6) | `test_menus_layout::test_locker_bounds_at_every_device`: glyph centre within 0.6 units of the well's centre at 7 device shapes, and the drawn icon inside the well with padding. Measured offset is (0.0, 0.0) everywhere |
| M2 | Locker (IMG_3016/3018) | Oversized cards; the next row is cropped | V6 used one card for everything (`img + 116`, 3-6 columns), with the column count taken from the panel's requested minimum width. At p14 a card was 199×291 in a 320-unit list | `UIKit.AutoGrid`: columns from the grid's final width. Per-type wells: full-body outfits, close-up hats, faces and hair, feet-framed shoes, short emote cards. Names reserve the grid's line count; a state row sits under the name | p14: 5 columns. Outfit cards 149×242 (2-line names), emote cards 149×163: all 10 emotes visible at once. SE: 4 columns, 168×175. `test_locker_bounds_at_every_device`: columns = the width formula, cells fit the row, state rows aligned |
| M3 | Locker (IMG_3016/3018) | Giant disabled "Wearing this", long footer prose, Save outside the panel | A 320×90 primary button and a caption sat below the panel, at y 576-666 on p14 | The panel's footer row (44 pt) holds the selected item and its state ("Equipped" / "Not saved yet"). Undo and Save look appear there only while the look differs from the saved one. The prose is gone | `test_wardrobe::test_apply_and_undo_say_what_they_do` (updated contract), `test_locker_bounds_at_every_device` (Save look / Undo inside the panel and the safe area, 44 pt) |
| M4 | Locker (IMG_3018) | "N more in the Shop" filler card competing with owned items | A full card per category | One compact link at the end of the list ("2 more in the Shop ›" / "… Season Pass ›"), with the same routes | `test_wardrobe::test_locker_shows_only_owned_items` |
| M5 | Locker (IMG_3018) | Outfit thumbnails show the player's nightcap and bunny slippers | Cards rendered the draft with the outfit swapped in | `CommerceArt.preview_look()`: outfits and patterns are pictured with no hat and plain shoes (High-Tops), hairstyles with no hat. The live runner keeps the real draft. The Shop and Pass use the same looks | `test_menus_layout::test_outfit_pictures_use_a_neutral_look_and_the_runner_keeps_the_draft` |
| M6 | Emote icons (IMG_3016) | Inconsistent glyphs | A hand, notes, faces and arrows at different scales, each off-centre in its own way | One set: the chibi runner in each move's key pose (a round head, a capsule body, limbs of one stroke weight), and the giggle and shush as its face. Data in a unit square, normalised so the drawn bounds (strokes included) are centred and reach the same extent | `test_emote_icons_are_one_centred_set` (centre within 0.01, extent 0.94 ± 0.01, valid polygons); `art_sheet.jpg` |
| M7 | Season Pass (IMG_3017) | Premium row and Claim below the screen | The header, the wrapped service paragraph and the panels took 344 units. `_fit_cells()` clamped cells to a 132-unit minimum, so the track's minimum size pushed its parents past the safe area. p14, service off: the Premium row ran from y 606 to 750 on a 720-unit screen (none whole); Claim was 65% visible (y 665-749) | A one-row header (title, tier, bar, short XP, Claim all). The track sits in `UIKit.region()`: it takes the height the header leaves and can never grow its parent. Cells size from that height (44 pt floor, 240 cap); width follows. The detail action sits outside the detail's scroll | `test_pass_rows_and_detail_action_fit_every_device` at seven shapes (rows below); `test_pass_service_off_is_honest_and_still_fits` |
| M8 | Season Pass (IMG_3017) | Empty colored strip for name cards; rewards hard to tell apart | `CommerceArt.name_card()` received an empty name in the pass; hats used the head framing (tall hats cut); no caption | Name cards drawn as they appear when equipped (the player's name or "Your Name", their badge, the card's motif). Hats use `hat` framing, shoes `feet`, outfits a full-body portrait. Cells carry a short caption ("Outfit", "50 Coins"). Emotes play on one small live runner in the detail. Badges are medallions; Coins carry the crescent and piles grow with the amount | Captures `10`-`16`, `30`-`35`; `art_sheet.jpg` |
| M9 | Season Pass (IMG_3017) | "Ready to claim" over a dead button; a developer paragraph in the browsing area | The cell state comes from progression only; the service-off message was shown as a banner | `display_state()`: a claimable reward is "earned" while claiming is unavailable (no claim mark, "Earned at Tier N, not claimed yet"). The header says "Rewards unavailable right now". The detail gives a short reason directly above the visibly disabled Claim. Premium reads "See Premium in the Shop" | `test_pass_service_off_is_honest_and_still_fits`, `test_pass_free_premium_and_claim_states` (claimable, Premium-locked, locked, blank Free slot, late Premium, idempotent Claim all) |
| M10 | Shop | The same card problems; a long service paragraph; status text far from the action | — | The Locker's card system and AutoGrid. One short unavailable line. The detail's status sits fixed right above its action. Purchase, confirmation, Restore and pending logic are unchanged | `test_shop_ui` (unchanged, passing), `test_shop_bounds_at_every_device` |
| M11 | Season Premium card (found by the new test) | The emblem spilled 2 units past the card | The card's height was fixed while its text block was taller | The card grows with its text (re-fitted when the text's minimum size is known) | `test_shop_bounds_at_every_device` |
| M12 | All menus | Hit targets shift during the entry | `Motion.settle_in` scaled panels from 98.5%, sometimes around a (0, 0) pivot before the first layout | Entries fade only (`UIKit.fade_in`, also the shared `Screen` entry) | `test_entry_never_moves_hit_targets` |
| M13 | Locker and Shop runner | The hat ran under the navigation tabs | The wardrobe framing was fixed vertically | `DormStage.set_wardrobe_region()` takes an optional vertical band; the Locker and Shop pass the stage area's band, and the figure (1.78 m incl. the tallest hat) is fitted inside it | Captures `01`-`07`, `20`-`26` |

### Season Pass rows after the fix

Service on, both rows, every column in view. From
`test_pass_rows_and_detail_action_fit_every_device`:

| Device | Canvas | Free row y | Premium row y | Cell | Safe bottom | Detail action y |
|---|---|---|---|---|---|---|
| SE 667×375 @2x | 1280×720 | 281-481 | 489-689 | 160×200 | 708 | 603-688 |
| 812×375 @3x | 1559×720 | 281-467 | 475-661 | 148×186 | 680 | 575-660 |
| 844×390 @3x | 1558×720 | 275-465 | 473-663 | 152×190 | 681 | 580-662 |
| 926×428 @3x | 1557×720 | 261-459 | 467-665 | 158×198 | 685 | 590-665 |
| iPad 1024×768 @2x | 1280×960 | 265-505 | 513-753 | 192×240 | 935 | 860-915 |
| 2048×946 shot | 1558×720 | 275-465 | 473-663 | 152×190 | 681 | 580-662 |
| 1536×710 shot | 1557×720 | 275-465 | 473-663 | 152×190 | 681 | 580-662 |

With the service off the rows are the same: the "Rewards unavailable right
now" line replaces Claim all inside the header row, so nothing moves.

**Before, measured from `before/*/measure.json`:**

- **812×375, service on:** the Premium row ran from y 541 to 685, 5 units
  past the safe bottom (680).
- **SE, 812×375 and 844×390, service off:** the Premium row ran from y 609
  to 753, 33 units below a 720-unit screen. The Claim button was cut off.

## Shared layout system (`UIKit`, `Screen`)

- **`UIKit.content_rect(vp)` and `Screen.content_size()`:** the allocated
  safe content rect: the viewport minus the safe area minus a small edge
  padding. Layout derives from it.
- **Screen padding:** V6 put 24/16 units on top of the safe area; V7 uses
  20/12 (`EDGE_X`/`EDGE_Y`). This applies to every `Screen`.
- **Spacing scale:** `SP_XS`…`SP_XL`, `PAD_PANEL`, `GAP_CARD`.
- **`row_h()`:** one row of controls, 44 pt (`touch_min()`). Text keeps the
  type scale; nothing is shrunk to fit.
- **`UIKit.region(child)`:** content that sizes itself to the space left.
  The child's minimum size can never grow the parent past the screen.
- **`UIKit.AutoGrid`:** columns from the final width; children lay out with
  `fit_cell(w, lines)` and `name_lines(w)`. It re-fits only when the width
  changes, never while scrolling.
- **`UIKit.link()`:** a compact link with a full 44 pt hit area.
- **`UIKit.fade_in()`** and **`UIKit.lines_for()`**.
- **`Screen.nav_bar(tab)`:** the commerce screens' top row.
- **Lists:** the Locker and Shop lists reserve their scrollbar's room
  (`SCROLL_MODE_RESERVE`), so the grid width doesn't flip when a list
  becomes scrollable.
- **Wrapping labels:** they get an explicit width from the allocated width,
  so they never report a first-frame height for an unknown width.
- **Kept working:** every existing `UIKit` function signature. `emulation`
  (`{"scale", "safe"}`) is a test seam beside `--emulate-phone` and
  `--emulate-safe`.
- **V6 scrolling is unchanged:** TouchScroll, drag vs tap, category scroll
  restore, controller follow-focus.

## Art and thumbnails

- **Emote icons (`Icons`):**
  - `emote_shapes()` gives the normalised shape lists.
  - `draw_emote()` draws them, and `draw_shape("e_*")` routes to it, so the
    lobby picker, results and HUD use the same set.
  - `shape_bounds()` gives the drawn bounds (for the tests).
- **`CommerceArt`:**
  - `coin()` and `coin_pile()`.
  - `badge(…, dim)`: a medallion.
  - `name_card()`: same signature; draws the name, badge and motif. Its
    motif table is art only, so the catalogue is unchanged.
  - New `glyph()` kinds: `whistle`, `drop`, `lamp`, `quad`, `sun`,
    `track`, `stars`.
  - `preview_look()`, `framing_for()` and `card_name()`.
- **Portrait cache:** the thumbnail looks are built in the screens through
  `preview_look()` and keyed by `Portraits.key_for()` (so by `key_of`, which
  the characters workstream versions). `key_of` is not edited. The cache is
  in memory, so a new look or framing gets a new key; nothing stale can be
  reused.
- **Emote preview in the Pass:** one bounded live preview (`Preview3D`, the
  main view's MSAA). It is created on the first emote selection, hidden
  (not rendered) otherwise, and freed with the screen. It replays its clip
  every few seconds; with Reduced Motion it plays once.

## Unchanged

IDs, prices, XP thresholds, unlock positions, quantities and entitlements
are unchanged; `catalogue.json` and `economy.gd` are untouched. So are:

- Apple purchase sheets, the Coin confirmation, Restore Purchases,
  cancellation, and pending and error handling;
- Claim and Claim all idempotency, and late Premium;
- the Locker's explicit save flow, and Save never spending;
- leave-with-unsaved-changes confirmation;
- one-finger drag-to-turn;
- category scroll restore.

No debug grant ships: the test adapters live in `src/dev`, which exports
exclude.

## Tests

New, `game/tests/test_menus_layout.gd` (10 tests, about 5,500 checks):

- `test_pass_rows_and_detail_action_fit_every_device`
- `test_pass_service_off_is_honest_and_still_fits`
- `test_pass_free_premium_and_claim_states`
- `test_locker_bounds_at_every_device` (every category, every item granted,
  "many items")
- `test_shop_bounds_at_every_device`
- `test_outfit_pictures_use_a_neutral_look_and_the_runner_keeps_the_draft`
- `test_swipes_from_glyphs_portraits_labels_and_blank_card_areas_never_select`
  (Locker outfit portrait, label, blank corner, face portrait, emote glyph;
  the Pass track; Shop pictures; then a tap selects and plays the emote)
- `test_emote_icons_are_one_centred_set`
- `test_controller_focus_lands_in_each_screen` (service on and off)
- `test_entry_never_moves_hit_targets`

Updated: `test_wardrobe::test_apply_and_undo_say_what_they_do`, for the new
contract (no "Wearing this"; Save look / Undo only for a change).

Passing on this branch:

- `test_menus_layout`
- `test_wardrobe`
- `test_shop_ui`
- `test_touch_scroll`
- `test_stage_drag`
- `test_screen_cycles` (nodes, orphans, connections flat; objects about 41
  per tour, as in V6)
- `test_catalogue`
- `test_wallet`
- `test_purchases`
- `test_lobby_music`
- `test_account`
- `test_emotes`
- `test_results_layout`
- `test_profile`
- `test_portraits`
- `test_focus`

## Shared-file changes (for the integrator)

- **`src/ui/ui_kit.gd`:**
  - A V7 block inserted before `class Face`, not at the end, so the screens
    workstream's appended block merges cleanly.
  - `emulated_point_scale()` and `emulated_safe_points()` consult
    `UIKit.emulation` first.
- **`src/ui/screen.gd`:**
  - Smaller edge padding (affects every screen: 4 units more room on each
    side, 4 more top and bottom).
  - The entry is a fade only.
  - New `content_size()` and `nav_bar()`.
- **`src/ui/icons.gd`:** every `e_*` glyph changed (the lobby emote
  picker, results and HUD show the new set).
- **`src/view/dorm_stage.gd`:** `set_wardrobe_region()` takes optional
  `top_frac` and `bottom_frac`; the defaults keep V6 behaviour.
- **Dev only, not exported:**
  - `src/dev/menus_capture.*`, `src/dev/menus_art_sheet.*`;
  - `tools/capture_v7_menus.sh`.

## Limits

- **No device.** Real touch, real safe areas, rendering cost and the live
  preview's cost on a phone are unmeasured.
- **Service-on is test adapters only.** Nothing was claimed or bought
  against a real service or the App Store.
- **"Earned" in service-off.** With the service off there is no XP
  snapshot, so only tier 1 reads "earned"; the rest are locked.
- **Name-card fitting.** The name on a card is set a little smaller to fit
  a long name with a badge, and trimmed only beyond that. It is a picture
  of the card, not UI text.
