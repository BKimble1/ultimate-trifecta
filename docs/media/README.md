# Media evidence

Every file below is a capture of the running game; none of it is concept art or rendered footage. Each one is labelled with the platform and build it came from. The desktop clips also carry that label burned into the bottom of the frame.

| File | Platform / build | What it shows |
|---|---|---|
| `runner_practice_desktop.mp4` | Desktop Linux, Godot 4.7.2 Forward Mobile renderer on Mesa llvmpipe (software Vulkan) under Xvfb, commit `ad58d95`, Movie Maker capture at 30 fps | 58 s of a practice round as a runner. The local runner is driven by the bot autopilot (`--autoplay=runner --local-bot`). Covers the role reveal, countdown, head start, running and sprinting, a splash and stamp at Froggy Pond, HUD, compass, minimap, event feed and [BOT] labels. |
| `night_watch_practice_desktop.mp4` | Same, commit `ad58d95` | 75 s as the Night Watch, bot-driven (`--autoplay=patrol --local-bot`). Covers the shed start, the head-start hold, getting into a golf cart, driving, hopping out near runners, an on-foot chase, and a capture ("… caught Bot Snooze!"). |
| `full_round_timelapse_desktop.mp4` | Same, commit `d89a78a`. Captured at 10 fps with normal game physics, then sped up 4× in ffmpeg. | A whole round as a bot-driven runner, from role reveal through all three splashes, the run home and "HOME SAFE!" spectating, to the results screen (Runners win, contributions, Fastest Trifecta, coins). |
| `shots/campus_*.jpg` | Same, commit `ad58d95`, free camera (`src/dev_shots.tscn`) | The six waters, dorm, cart shed, tower and an overview of the campus. |
| `shots/title.jpg`, `shots/runner_*.jpg`, `shots/night_watch_*.jpg` | Same, commit `ad58d95` | The title screen, plus frames taken from the two clips above. |
| `shots/results_runners_win.jpg` | Same, commit `d89a78a` | The results screen, taken from the time-lapse. |
| `shots/lobby_16x9.jpg`, `shots/lobby_ipad_4x3.jpg` | Same, commit `d89a78a`, desktop LAN room (a development path) rendered at 1280×720 and 1280×960 | The lobby layout at phone 16:9 and iPad 4:3 aspect. |
| `ios_simulator_ci_run10.jpg` | **iOS Simulator** (iPhone Air, iOS 26.2 runtime) on the GitHub `macos-26` runner, unsigned Release build 1.0 (10) of the final code (`b2d4844`, pushed as `f1c7579`), x86_64 under Rosetta with the OpenGL ES fallback | The boot splash, about 5 minutes of loading (the Simulator is extremely slow here), and then the match: role reveal, 4:00 HUD, minimap and [BOT] players, still rendering at the end of the 11-minute window. This is evidence that the iOS build launches and reaches a match, **not** evidence of performance. |

There is **no** footage from a physical iPhone yet; none was available. The desktop captures render through a software rasteriser at about 12% of real time. Movie Maker fixes the game's clock, so the clips play at true game speed (the time-lapse at 4×), but their image quality and frame pacing say nothing about device performance.
