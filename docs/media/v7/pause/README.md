# V7 Pause, Resume and Leave: before and after

The same scripted reel (`game/src/dev/pause_reel.gd`) run on 1.5 (`d2d0749`,
"before") and on V7 ("after"), recorded with `tools/capture_v7_reel.sh` at
normal speed: Godot 4.7.2 Mobile renderer (Low preset) on desktop Linux
llvmpipe, a 1040x480 window (the 812x375 pt phone shape; the game's canvas
is 1560x720), Movie Maker's fixed 30 fps clock. Touches are **scripted and
emulated** (`InputEventScreenTouch`/`ScreenDrag` at the controls' rendered
positions, found by their text, so the same reel drives both builds); white
rings mark fingers. Not device footage, not frame-rate evidence.

The readout under the caption shows whether the menu is open, the round
clock and the runner's stored velocity (frozen with the round while
Practice is paused).

| File | Shows |
|---|---|
| `v7_pause_before.mp4` (24 s) | 1.5: a second finger's tap opens the menu, but the gameplay touch surface stays live over it; the slider, Resume and Leave taps never reach the menu; the round clock keeps running in Practice; the menu is still open at the end |
| `v7_pause_after.mp4` (25 s) | V7: the menu opens over a dim backdrop with the touch controls hidden; the round clock stops (Practice); the slider moves; Resume returns to play; Pause → Leave match → Stay → Resume; Pause → Leave match → Leave leaves once |
| `pause_menu_before.jpg` / `pause_menu_after.jpg` | The open menu: 1.5 says "The round keeps running for everyone else." in Practice with the stick and Jump still live; V7 says "The round is paused." |
| `after_tapping_leave_before.jpg` | 1.5 after tapping "Leave match": no confirmation, the menu unchanged, the round clock at 11.4 s and still running |
| `leave_confirm_after.jpg` | V7: "Leave match? This practice round ends. Nothing is earned." with Stay as the primary action |

Reel log lines: before `quits=0 menu_open_at_end=true`; after `quits=1
menu_open_at_end=false`. The automated proof is `game/tests/test_pause_input.gd`
and `test_pause_online.gd` (docs/V7_NOTES.md, P1–P7).
