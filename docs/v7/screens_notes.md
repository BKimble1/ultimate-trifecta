# V7 screens workstream: Play with Friends, Settings, and the sweep

Branch `v7-screens` (from `d2d0749`). This workstream covers V7 brief §7's
**Play with Friends** (`src/ui/online_screen.gd`) and **Settings**
(`src/ui/settings_screen.gd`), and the sweep of **home**
(`title_screen.gd`), the **party room** (`lobby_screen.gd`), **results**
(`results_screen.gd`) and **confirmations/dialogs** for overflow,
oversizing and input blockers.

Everything was built and checked on desktop Linux: headless tests, and the
Mobile renderer on llvmpipe under Xvfb for captures, each at a device's
pixel size with its point scale (`--emulate-phone`) and safe area
(`--emulate-safe`). **No iPhone or iPad was available.** The iOS keyboard
is emulated (its usual landscape height, drawn as a labelled grey block);
Game Center is simulated as signed in (`--gc-sim=ready`); the game service
is off. Device touch, the real keyboard and safe areas are unmeasured.

Evidence: [docs/media/v7/screens/](../media/v7/screens/README.md).

## Issue register

Measured in canvas units (the canvas is 720 units tall; on an 844x390 pt
phone 1 pt = 1.85 units and a 44 pt touch target is 81 units). "Before" is
`d2d0749`.

| # | Screen | Symptom | Source and measured cause | Fix | Verification |
|---|---|---|---|---|---|
| S1 | Play with Friends | Oversized heading, Create Party and help push the friends entry below the first view; the code row is tall | One 600-unit-wide column in a scroll area: a 40-unit heading, Create Party 540x100, a two-line hint, a "Join with a code" heading, the field 320x88 at 44-unit type and Join 200x88. At 844x390 the friends button (y 610-692) was cut by the list's bottom edge (`friends_layout.json`: "partly visible"); the same on every phone | A header row (Back, the title at the type scale's title size, "Playing as …" and Change name), then two cards side by side - **Start a party** (Create Party, one touch target tall) and **Join with a code** (field and Join on one row, the same height and type size, a reserved one-line hint/mistake) - and the Game Center friends card. Narrow screens stack the cards (flow container) | `test_v7_screens::test_friends_first_view_shows_identity_create_join_and_friends` at the seven sizes, in both lanes: Back, identity, Change name, Create, field, Join and friends whole in the first view, inside the safe area, header above the actions, field and Join one height, one top edge, one type size, Join after the field, nothing trimmed, every control reached by a pointer |
| S2 | Play with Friends | With the keyboard open the code field and Join are covered | Before: the code row ended at y 547 (844x390) and 550 (667x375) while a 209/194 pt keyboard starts at 334/348. Nothing read the keyboard | The code row now ends at y ~259 (all phones), above every typical landscape keyboard, so it doesn't move. `UIKit.v7_keyboard_height()` reads `DisplayServer.virtual_keyboard_get_height()` every frame; if a keyboard would cover the code row (field, Join, message) while the field has focus, the list under the header scrolls by exactly the overlap (never past its own top) and scrolls back when it closes; the header and Back never move; the list keeps its scroll-bar room so nothing shifts sideways | `test_friends_keyboard_keeps_field_and_join_reachable`: each device's typical keyboard (no movement at all) and one 40 units taller than the room (moved by the overlap): field and Join above the keyboard and tappable, Back unmoved and uncovered, everything back on close |
| S3 | Play with Friends | Validation text long | The parser's two-sentence messages | First sentence only (`"B" isn't used in party codes.`), amber; otherwise the muted hint "Ask the host for their 6-character code." in the same reserved line (nothing moves while typing). The parser, the six-character rules, Game Center states, Cancel and invites are unchanged | `test_friends_code_is_strict_and_messages_are_short`, `test_friends_states_game_center_off_and_busy`, `test_focus::test_code_entry_never_traps_a_controller` |
| S4 | Settings | A large profile section and an enormous four-button strip push Controls down; the Sprint choices sit at the bottom edge | One panel; Profile = name, a paragraph and a flow of 240/220/280/300x81 buttons (Delete among them); every row with a fixed 300-unit label; switches as full-width CheckButtons; segmented options `clip_text`. Sound started 2.9 screens down (844x390) | Grouped cards of compact labelled rows under a header that never scrolls: **Profile** (player name with where it lives, Runner, Blocked players - one action each, all one width), **Controls**, **Sound** (moved up), **Camera & comfort**, **Graphics**, **Diagnostics (beta)**, **Privacy**, **How to play**, **Credits**, then **Delete game profile** on its own at the end. One label column (30 % of the list, 220-330 units); sliders show their value; choices are sized to their words and move under the label rather than trim; shorter option words ("Push stick to edge" / "Sprint button") and notes; phone-sized switches and slider knobs. Sound now starts 1.5 screens down (667x375) | `test_settings_sections_reachable_aligned_and_whole`: every section scrolls into view; every control in it can be shown whole inside its card; sliders and choices share one column and right edge; Sprint options whole and inside Controls; Back in the fixed header; `_audit` (on screen, safe area, touch size, not trimmed, reached by a pointer) |
| S5 | Settings | Values must survive the redesign | - | Same keys and values (`sensitivity`, `stick_mode`, `sprint_mode`, `haptics`, `invert_y`, `reduced_motion`, `quality`, `sfx`, `music`, diagnostics, touch layout); Reset controls unchanged | `test_settings_scroll_by_finger_keeps_values`: swipes from labels, sliders and choices scroll and change nothing; a tap on Sprint button saves `hold`; reopening shows saved values |
| S6 | Settings | Deletion must stay separate and confirmed | - | Its own last section; the confirmation is unchanged | `test_profile_delete_still_confirmed` (real taps: asks, Cancel keeps, Delete deletes; the screen behind takes no taps), `test_account` (online delete flows) |
| S7 | Confirmations | Back (Escape, controller B) did nothing on "Leave this party?" (party room and results) and "End this series now?" | `Screen.dialog()` maps Back only for "Cancel", "OK", "Done", "Keep editing", "Not now" and "Close"; these use "Stay" / "Keep playing" | `UIKit.v7_back_chooses()` gives those confirmations a Back that takes the safe choice (shared `dialog()` unchanged) | `test_party_room_with_one_four_and_eight_players_fits`: Back opens the confirmation, Back again stays in the party (failed before) |
| S8 | Party room | With 4 or more players a runner stands behind the roster cards | `LobbyScreen._frame_stage` followed only `roster_col.resized`; the roster moves left when it gains its second column (and the first deferred call ran before layout), so the stage kept framing for a roster that wasn't there: free fraction 0.857 instead of 0.526 at 667x375, rightmost runner at x 960 vs the roster at 686 | Follow `item_rect_changed` (position or size) | Same test: every runner's head and shoulders project left of the roster with 1, 4 and 8 players at every size (failed before) |
| S9 | Results, final standings | The summary showed little of the round; final standings showed only the table header on a 667x375 phone | Actions 92 units tall; the summary height subtracted a fixed 120 units (40 more than the SE's margins and padding); a two-line status and subtitle; a tall podium | Actions one touch target tall, the summary's room from the real safe margins and sheet padding, one-line status and subtitle, a tighter podium | `test_home_results_and_standings_fit_every_device`: the round's first table row and the first standings row whole in the first view at every size (failed before at 667x375 and notched phones), plus `_audit` |
| S10 | Settings › Blocked players | A long block list ran off the screen | No scrolling; and the dialog was re-centred after adding rows but its entrance tween then moved it back to where it was centred without them (half off a phone screen) | The rows scroll inside the dialog (`UIKit.v7_capped_list`), and the entrance tween's position is stopped before re-centring | `test_long_lists_stay_inside_their_sheets` (14 blocked players) |
| S11 | Party room › Standings | Eight friends' standings overflowed the sheet | No scrolling | The table scrolls inside the sheet | Same test (eight friends) |
| - | Home | Swept | Nothing off screen, outside the safe area, trimmed or covered at any size | No change | `test_home_results_and_standings_fit_every_device` (`_audit` of Home) |

## Measured layout facts

From the captures (`tools/make_v7_screens_media.py`; canvas units; before = `d2d0749`, after = `v7-screens`). The 844x390 pt "before" party-room leave confirmation was lost to a capture timeout, so that pair is absent.

| Device | | Play with Friends, first view | Keyboard open on the code | Settings, first view |
|---|---|---|---|---|
| iPhone SE class, 667x375 pt @2x, safe 0,0,0,0 | before | Create whole, field whole, Join whole, friends cut, field 320x88 / Join 200x88 | keyboard top 348; covered: field, Join; row bottom 550 | sections in the first view: Profile, Controls; Sound starts 2.9 screens down; Sprint row at the list's bottom edge |
|  | after | Create whole, field whole, Join whole, friends whole, field 432x85 / Join 150x85 | keyboard top 348; field and Join above it; row bottom 259 | sections in the first view: Profile, Controls; Sound starts 1.5 screens down; Sprint row at the list's bottom edge |
| 812x375 pt @3x, safe 44,0,44,21 | before | Create whole, field whole, Join whole, friends cut, field 320x88 / Join 200x88 | keyboard top 319; covered: field, Join; row bottom 550 | sections in the first view: Profile, Controls; Sound starts 2.9 screens down; Sprint row at the list's bottom edge |
|  | after | Create whole, field whole, Join whole, friends whole, field 509x85 / Join 150x85 | keyboard top 319; field and Join above it; row bottom 259 | sections in the first view: Profile, Controls; Sound starts 1.5 screens down; Sprint row below the first view |
| 844x390 pt @3x, safe 47,0,47,21 | before | Create whole, field whole, Join whole, friends cut, field 320x88 / Join 200x88 | keyboard top 334; covered: field, Join; row bottom 547 | sections in the first view: Profile, Controls; Sound starts 2.9 screens down; Sprint row at the list's bottom edge |
|  | after | Create whole, field whole, Join whole, friends whole, field 506x82 / Join 150x82 | keyboard top 334; field and Join above it; row bottom 253 | sections in the first view: Profile, Controls; Sound starts 1.5 screens down; Sprint row at the list's bottom edge |
| 926x428 pt @3x, safe 47,0,47,21 | before | Create whole, field whole, Join whole, friends cut, field 320x88 / Join 200x88 | keyboard top 368; covered: field, Join; row bottom 540 | sections in the first view: Profile, Controls; Sound starts 2.7 screens down; Sprint row fully shown |
|  | after | Create whole, field whole, Join whole, friends whole, field 513x75 / Join 150x75 | keyboard top 368; field and Join above it; row bottom 239 | sections in the first view: Profile, Controls; Sound starts 1.4 screens down; Sprint row at the list's bottom edge |
| iPad 1024x768 pt @2x, safe 0,24,0,20 | before | Create whole, field whole, Join whole, friends whole, field 320x88 / Join 200x88 | keyboard top 463; covered: field, Join; row bottom 543 | sections in the first view: Profile, Controls; Sound starts 1.9 screens down; Sprint row fully shown |
|  | after | Create whole, field whole, Join whole, friends whole, field 432x57 / Join 150x57 | keyboard top 463; field and Join above it; row bottom 219 | sections in the first view: Profile, Controls, Sound; Sound starts 0.8 screens down; Sprint row fully shown |
| 2048x946 px (owner screenshot aspect) as an 844x390 pt phone, @2.4265, safe 47,0,47,21 | before | Create whole, field whole, Join whole, friends cut, field 320x88 / Join 200x88 | keyboard top 334; covered: field, Join; row bottom 547 | sections in the first view: Profile, Controls; Sound starts 2.9 screens down; Sprint row at the list's bottom edge |
|  | after | Create whole, field whole, Join whole, friends whole, field 506x82 / Join 150x82 | keyboard top 334; field and Join above it; row bottom 253 | sections in the first view: Profile, Controls; Sound starts 1.5 screens down; Sprint row at the list's bottom edge |
| 1536x710 px (owner screenshot aspect) as an 812x375 pt phone, @1.8916, safe 44,0,44,21 | before | Create whole, field whole, Join whole, friends cut, field 320x88 / Join 200x88 | keyboard top 319; covered: field, Join; row bottom 550 | sections in the first view: Profile, Controls; Sound starts 2.9 screens down; Sprint row at the list's bottom edge |
|  | after | Create whole, field whole, Join whole, friends whole, field 508x85 / Join 150x85 | keyboard top 319; field and Join above it; row bottom 259 | sections in the first view: Profile, Controls; Sound starts 1.5 screens down; Sprint row below the first view |

## Tests

- `game/tests/test_v7_screens.gd` (10 tests). In the normal lane
  (`tools/run_tests.sh test_v7_screens`) it runs all seven sizes on a
  headless desktop (44-unit touch targets, default margins).
- `tools/check_v7_screens.sh` runs the same file once per device with the
  device's point scale, safe area and size (81-85-unit touch targets on
  phones, 55 on iPad; the notch and home-indicator insets).
- `_audit` (used throughout): every visible control that is shown (not
  scrolled away) is on screen, inside the safe area, at least a touch target,
  not trimmed, and a pointer moved to its centre reaches it (Godot's own GUI
  pick through `Viewport.push_input`), so an invisible node above it fails.

## Tools

- `tools/capture_v7_screens.sh OUT [devices]` with
  `src/dev/capture_v7_screens.gd` (`--capture=v7_screens`, optional
  `--v7-only=friends,settings,confirm,results,party,home`): PNGs plus
  `<shot>_layout.json` (every visible control's final rect, flags).
- `tools/make_v7_screens_media.py BEFORE AFTER [OUT]`: the JPEG pairs and
  the facts table above.

## UIKit additions (append-only "V7 screens" block at the end of `ui_kit.gd`)

- `v7_emulated_keyboard_pt`, `v7_keyboard_height(vp)`: the on-screen
  keyboard's height in canvas units (emulated in captures and tests).
- `v7_text_width(c, text)`, `v7_button_text_fits(b)`: measured text fit.
- `v7_back_chooses(screen, dialog, choice)`: Back on a confirmation takes its
  safe choice.
- `v7_capped_list(content, max_h)`: a list as tall as its content up to a
  cap, then finger-scrolled.

No existing UIKit, Screen or NavShell function was changed.

## Not verified / open

- No device: the real iOS keyboard height, and Godot reporting it in pixels
  (the conversion divides by the root's canvas-to-pixel scale), are
  unmeasured; a hardware keyboard (bar only) or a floating iPad keyboard
  should need no movement. Touch, safe areas and Dynamic Type are emulated.
- Home was swept and left unchanged; its buttons are sized in canvas units,
  so on a 4:3 iPad (a 1280x960 canvas) they are proportionally larger in
  points than on a phone - a shared-layer matter, not changed here.
- Long names in the results celebration cards are still trimmed at their
  smallest size by design (`UIKit.fit_text`); the tables below show them
  whole.
- In a scrolling list some row is always at the bottom edge; Settings
  makes every row reachable and whole by scrolling rather than promising a
  particular row in the first view.
