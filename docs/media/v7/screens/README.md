# V7 screens: matched before/after runtime captures

Play with Friends, Settings, and the sweep of home, the party room, results,
final standings and confirmations. Notes and the issue register:
[docs/v7/screens_notes.md](../../../v7/screens_notes.md).

**How these were made.** The real game, rendered by Godot's Mobile renderer
on llvmpipe (software Vulkan) under Xvfb on desktop Linux, at each device's
pixel size with that device's point scale (`--emulate-phone`, which sets
the 44 pt touch-target size) and safe area (`--emulate-safe`, points
L,T,R,B): `tools/capture_v7_screens.sh` with
`game/src/dev/capture_v7_screens.gd`. No iPhone or iPad, Simulator or real
iOS keyboard was used. **Before** is `d2d0749` (V6 with the lobby music);
**after** is branch `v7-screens`. Each `*_before.jpg` / `*_after.jpg` pair
is the same moment of the same script at the same size.

- Game Center is **simulated as signed in** (`--gc-sim=ready`), as on an
  iPhone; nothing that needs Game Center is invoked. The game service is
  off (as in the shipped build).
- The **iOS keyboard is emulated**: a grey block of a typical landscape
  keyboard's height (QuickType bar included) labelled "iOS keyboard
  (emulated, N pt)": 194 pt on the 667x375 phone, 209 pt on notched phones,
  398 pt on the iPad. In "after" the screen reads it through the same hook
  it reads the real keyboard's height from; "before" had no such reading.
- The **party room** runs on the game's in-process loopback transport (no
  network): this device hosts, guests join with their own looks and tap
  Ready. Without the service, party names are the curated ones
  ("Bouncy Panda 25" …), as in the shipped build.
- Results and final standings are a synthetic eight-player round (four
  bots) and a three-round friend series recorded through `PartySeries`.
- Layout, not performance: frame rate, touch latency and heat are not
  shown.

## Devices

| Folder | Platform (emulated) | Points | Scale | Safe area L,T,R,B (pt) | Pixels |
|---|---|---|---|---|---|
| `se/` | iPhone SE class | 667x375 | @2x | 0,0,0,0 | 1334x750 |
| `x14/` | notched iPhone (X/11 Pro/12-13 mini class) | 812x375 | @3x | 44,0,44,21 | 2436x1125 |
| `p14/` | notched iPhone (12-14 class) | 844x390 | @3x | 47,0,47,21 | 2532x1170 |
| `max/` | large iPhone (Pro Max/Plus class) | 926x428 | @3x | 47,0,47,21 | 2778x1284 |
| `ipad/` | 4:3 iPad | 1024x768 | @2x | 0,24,0,20 | 2048x1536 |
| `a2048/` | the owner's 2048x946 screenshot aspect, as an 844x390 pt phone | 844x390 | @2.4265 | 47,0,47,21 | 2048x946 |
| `a1536/` | the owner's 1536x710 screenshot aspect, as an 812x375 pt phone | 812x375 | @1.8916 | 44,0,44,21 | 1536x710 |

The owner's two screenshot sizes don't identify a device; they are shown
here as the phones whose aspect they match.

## Shots

Every folder: `friends` (Play with Friends at rest), `friends_keyboard`
(the code field focused with "ACE34" typed, keyboard open),
`settings_top` (Settings as it opens).

`se/`, `p14/`, `ipad/` also: `friends_invalid` ("ACE-3B7" typed: the
mistake message), `settings_controls`, `settings_sound`,
`settings_graphics`, `settings_diagnostics` (the list scrolled to each
section), `settings_end` (the end of the list), `confirm_delete` (the
Delete Game Profile confirmation), `home`, `party_1p`, `party_4p`,
`confirm_leave_party` (Back in the party room), `results_practice`,
`results_series_round` (the last round of a friend series, as host),
`final_standings`.

`x14/`, `max/`, `a2048/`, `a1536/` also: `results_series_round`,
`final_standings`, `party_4p`.

## Measured layout facts

From the captures' `<shot>_layout.json` (every visible control's final
allocated rect in canvas units; the canvas is 720 units tall, 960 on the
iPad). "Whole" = inside the screen and not cut by its list.

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

## Reproduce

```
tools/capture_v7_screens.sh OUT_BEFORE            # on d2d0749 (all devices)
tools/capture_v7_screens.sh OUT_AFTER             # on v7-screens
tools/make_v7_screens_media.py OUT_BEFORE OUT_AFTER docs/media/v7/screens
tools/check_v7_screens.sh                         # the layout tests per device
```
