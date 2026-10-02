# V5 (1.4) media

Every image and clip here is the real game rendered on a desktop Linux
machine by Godot 4.7.2's **Mobile renderer** on Mesa **llvmpipe** (software
Vulkan) under Xvfb, at device resolutions. They show layout, type, art,
framing and motion poses. **They are not frame-rate, smoothness, GPU or
heat evidence**, and nothing here was captured on an iPhone or iPad. Clips
run on a fixed game clock (Movie Maker), so their playback speed is game
time, not a measurement.

Device sizes: **phone** = 2532×1170 with a Dynamic Island safe area (59 pt
sides, 21 pt bottom), point scale 3; **SE** = 1334×750, point scale 2;
**iPad** = 2048×1536 (4:3) with a 24 pt status bar and 20 pt home indicator.
In-match shots are 1600×740 (a phone canvas at reduced pixels).

| Folder | What |
|---|---|
| [ui/](ui/) | V5 screens: startup, home, wardrobe (every category), party, match loading, match, results, other menus |
| [compare/](compare/) | V4 (1.3) left, V5 (1.4) right, same size and moment |
| [campus/](campus/README.md) | Campus art: matched V4/V5 renders of the same cameras (route, six waters, overview, landmarks, Battery Saver) |
| [motion/](motion/README.md) | Character motion: V4/V5 reels, transitions, pose sheet, arms, hat × hair, menu idle; raw probe data |

## ui/

| File | Shows |
|---|---|
| `startup_v5.mp4`, `startup_strip.jpg` | A normal boot (1280×720, 16:9 as an iPhone SE, 30 fps game clock): the Idlery Games lockup on the startup navy holds while home and the runner get ready (0.53 s of game time here), dissolves over ~0.27 s into home; no white frame, no second logo. The iOS launch image is the same composition (`compare/launch_image_v4_v5.jpg`) |
| `home_phone.jpg`, `home_se.jpg`, `home_ipad.jpg` | Home: the title upper left, profile chip and Settings upper right, the runner as the focus, Play with Friends (gold) and Practice, Wardrobe and Emote |
| `wardrobe_phone.jpg`, `wardrobe_se.jpg`, `wardrobe_ipad.jpg` | The wardrobe on each device: the runner framed in the free region left of the panel; the category strip fits (SE included) |
| `wardrobe_1_outfit.jpg` … `wardrobe_7_emotes.jpg` | Every category (Outfit, Colors, Face, Hair, Hat, Shoes, Emotes) during a scripted tour: portrait cards with the item on your runner, full names, Equipped / Owned / price with a lock; the footer says what Apply will do |
| `party_1.jpg`, `party_2.jpg`, `party_4.jpg`, `party_8.jpg` | The party room with 1, 2, 4 and 8 people (a desktop LAN room; iOS uses Game Center; the other players are separate headless processes with random looks): code card with Copy and Share, settings chips, roster cards with portraits and full names, open seat, Wardrobe / Emote / Try moves, Start with its status |
| `loading_phone.jpg`, `loading_se.jpg`, `loading_ipad.jpg` | Match loading: the title, the three runners from the game-rig loop, the quiet status and progress line |
| `match_reveal.jpg`, `match_hud.jpg`, `match_map.jpg` | Practice as a runner (bot-driven): the role reveal (two lines and tonight's waters), the HUD (clock pill, Home 0/4, objective chips, minimap), the full map with labels, legend, (i) and team list |
| `match_route.jpg`, `match_fountain_stamp.jpg`, `match_quarry_splash.jpg`, `match_map_grouped.jpg`, `match_caught.jpg`, `match_protected.jpg` | One full bot-driven practice round on the final campus and motion code, at 1280×592 on a fixed 6 fps game clock (llvmpipe draws ~1 frame a second; the clock keeps the round's timing): on the route, the Fountain stamp ("1 of 3 splashes"), a Quarry splash, the full map grouping nearby teammates ("Snooze +1") and marking a stamped water "done", caught ("back in 6", splashes safe) and protected. That run's results frame predates the results-layout fix, so the results shots below come from the fixed code |
| `results_phone.jpg`, `results_se.jpg`, `results_ipad.jpg`, `results_scoreboard.jpg` | Results of a recorded practice round: outcome, your round, rewards, and the actions in one row that never scrolls away; the scoreboard drawer |
| `play_with_friends.jpg`, `practice.jpg`, `settings.jpg`, `how_to_play.jpg` | The other menus in the V5 type and controls |

## compare/

`home`, `wardrobe`, `party8`, `loading`, `reveal`, `map`, `results` (each
`*_v4_v5.jpg`) at phone size, and `launch_image_v4_v5.jpg` (the iOS launch
image: V4's droplet motif, V5's Idlery Games lockup). V4 is commit
`dcebf4e` captured with the same tools at the start of V5.

## Reproduce

```
tools/capture_v5_media.sh OUT_DIR [home screens creator lobby loading runner results startup]
```

The campus and motion folders have their own reproduction notes. The
loading loop itself is rebuilt by `tools/make_loading_loop_rig.sh`.
