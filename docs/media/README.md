# Media evidence

Every file below is a capture of the running game; none of it is concept art or rendered footage. Each one is labelled with the platform and build it came from.

| File | Platform / build | What it shows |
|---|---|---|
| `runner_practice_desktop.mp4` | Desktop Linux, Godot 4.7.2 (Mobile renderer on Mesa's software Vulkan under Xvfb), commit `27e4a68`, Movie Maker capture at 30 fps | 58 s of a practice round as a runner. The local runner is driven by the bot autopilot (`--autoplay=runner --local-bot`). Covers the role reveal, countdown, head start, running and sprinting, the first splash and stamp, HUD, compass, minimap and bot labels. |
| `night_watch_practice_desktop.mp4` | Same | 75 s as the Night Watch, bot-driven (`--autoplay=patrol --local-bot`). Covers the shed start, the head-start wait, cart entry and driving, exiting, chasing and tagging. |
| `full_round_timelapse_4x_desktop.mp4` | Same, played at 4× speed (`--time-scale=4`) | A whole 4-minute round through to the results screen, as a bot-driven runner. |
| `shots/*.jpg` | Same | Stills: campus locations from a free camera (`src/dev_shots.tscn`), the title screen, and frames taken from the clips. |
| `ios_simulator_ci_run5.jpg` | **iOS Simulator** (iPhone Air, iOS 26.2 runtime) on the GitHub `macos-26` runner, unsigned Release build 1.0 (5) of commit `27e4a68`, x86_64 under Rosetta with the OpenGL ES fallback | The boot splash, a loading screen lasting about 2 minutes (the Simulator is extremely slow here), and then the match: role reveal, HUD, minimap and [BOT] players. This is evidence that the iOS build launches and reaches a match, **not** evidence of performance. |

There is **no** footage from a physical iPhone yet; none was available. The desktop captures render through a software rasteriser at about 12% of real time. The game's own clock is fixed by Movie Maker, so the videos play at true speed, but their image quality and frame pacing say nothing about device performance.
