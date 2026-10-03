# V6 clips

All clips are the real game rendered by Godot 4.7.2's Mobile renderer on
**desktop Linux llvmpipe** (software Vulkan) under Xvfb at 1280×720 (16:9,
as an iPhone SE), recorded with Godot's **Movie Maker at a fixed 30 fps game
clock**: every frame is rendered and written one by one however long it
takes, so the clips play at normal game speed but are **not** frame-rate,
pacing, GPU-cost or heat evidence. Each MP4 has its label burned in.
Recreate with `tools/capture_v6_media.sh OUT [startup loading swipes]`.

| Clip | What it shows | Notes |
|---|---|---|
| `v6_startup_black.mp4` (5 s) | Cold launch: the Idlery Games lockup on pure black, then Home | `_sheet.jpg`: 3 frames a second |
| `v6_loading_into_dorm.mp4` (30 s) | Bot-driven Practice from Home: loading screen (runner loop, "Preparing campus…", Cancel) → fade into the role reveal inside tonight's home dorm ("Home tonight: Moonpenny Lodge") → 3-2-1 in the common room → GO → out through the door onto the campus | The round prepared over 37 rendered frames (13 s of wall time on llvmpipe; `v6_loading_into_dorm.txt`). Autopilot input |
| `v6_finger_swipes.mp4` (21.5 s) | Real `InputEventScreenTouch`/`ScreenDrag` events (what iOS sends; the engine emulates the mouse from them) on the Locker (Face list), Shop (Outfits) and Season Pass track. Each swipe starts on a card; a ring marks the finger | Test adapters: test-double service, simulated store ("(test price)"). `v6_finger_swipes.txt`: the Locker selection was unchanged by the swipes, 0 App Store sheets were opened by them, the tap selected/opened |
