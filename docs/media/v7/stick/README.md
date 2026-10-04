# V7 forward drift: before and after

The same scripted reel (`game/src/dev/stick_reel.gd`) on the same clear
straight of the campus, run on the build before the fix (`b34566f`) and after
it, recorded with `tools/capture_v7_reel.sh` at normal speed: Godot 4.7.2
Mobile renderer (Low preset) on desktop Linux llvmpipe, a 1040x480 window
(the 812x375 pt phone shape; the game's canvas is 1560x720), Movie Maker's
fixed 30 fps clock. Touches are **scripted and emulated**
(`InputEventScreenTouch`/`ScreenDrag`, as iOS delivers them); the white ring
is the finger, the gold cross where it touched down. Bots stand still and
nothing is parked on the straight. Not device footage, nothing sped up.

Each clip (34 s) runs three cases, with a readout of the stick's output, the
camera's turn since the gesture began, and the runner's sideways and
forward travel from where it started:

| Case | Before (`v7_stick_before.mp4`) | After (`v7_stick_after.mp4`) |
|---|---|---|
| 1. The thumb lands near the bottom-left corner and pushes exactly straight up (5 s) | stick output x −0.77 (it started deflected); 24.8 m sideways, 6.1 m forward | x 0.00, y 1.00; 0.0 m sideways, 31.9 m forward |
| 2. Forward with a 6° thumb lean and a small wobble, held 8 s | the camera turned +94° and the runner circled (−2.0 m forward, 3.0 m sideways) | camera 0°; 49.2 m forward, 1.0 m sideways |
| 3. A long push past the stick's rim, eased back and held | camera −32°, 6.5 m sideways | camera 0°, 0.0 m sideways |

`lean_case_19s_before.jpg` / `_after.jpg`: the same moment of case 2 in
each clip. In case 3 the runner stops in both builds once the thumb eases
back inside the stick's followed base (designed behaviour, unchanged; see
docs/V7_NOTES.md S6).

The causes, fixes, the full probe tables (before and after, including the
round's own start out of the dorm door) and the tests are in
docs/V7_NOTES.md ("Forward movement wandering left/right") and
`docs/v7/stick/`.
