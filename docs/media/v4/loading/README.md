# Match loading screen: the runners loop (V4)

All of this was captured on desktop Linux: Godot 4.7.2, the Mobile renderer
on Mesa llvmpipe under Xvfb. It shows layout, framing, sharpness at these
sizes and the order of events. It does **not** show phone frame rate or
smoothness, and there is no iPhone footage (no device was available).

| File | What it shows |
|---|---|
| `before_droplets_1280x720.jpg` | The loading screen this replaces: the droplet motif and wordmark. Frame at 5.0 s of `../clips/startup_loading_v4_desktop.mp4`, recorded from `4e828da`. |
| `after_iphone_1561x720_t0.00.jpg`, `…_t0.40.jpg` | The new screen at an iPhone 14/15 Pro aspect (2556×1179, 720 canvas units high), at the start of the loop and 0.4 s in. |
| `after_iphone_se_1334x750_t0.00.jpg`, `…_t0.40.jpg` | iPhone SE (16:9). |
| `after_ipad_1024x768_t0.00.jpg`, `…_t0.40.jpg` | iPad (4:3). The picture is limited by the width, so it is smaller. All three runners stay whole and unstretched. |
| `loading_loop_6x.mp4` | The 19 bundled loop frames played six times at 24 fps (4.75 s). This is how to judge the loop point: the step from the last frame to the first should read as ordinary running. |
| `loading_into_round_desktop.mp4` | Practice from the title. The still shows, the loop runs while the round is prepared (stage text and bar), then a 0.25 s fade into the role reveal. The Movie Maker clock is fixed at 30 fps, so the ~1.6 s of loading here is 48 frames of desktop preparation, not a phone timing. |

The stills were rendered by `src/dev/launch_art.tscn -- --loading=0.0,0.4`
at each window size, with no match running (bar empty, first stage). The
loop is built by `tools/make_loading_loop.py` from the owner's clip
(`art_src/loading/characters_run.mp4`); see `docs/V4_NOTES.md`, "Startup and
loading".
