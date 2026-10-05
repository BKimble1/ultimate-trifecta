# Pass 8 challenges evidence: Season Pass "Challenges · Earn Season XP" and results lines

Notes: [../../../pass8/challenges.md](../../../pass8/challenges.md). Rules:
[ECONOMY.md §10](../../../ECONOMY.md).

## How these were made

- **Renderer:** the real game screens, rendered by Godot 4.7.2's Mobile
  renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb on a shared
  desktop Linux machine. Layout and states only: **not** frame rate, touch
  feel or a device. No iPhone or iPad was used.
- **Tooling:** `tools/capture_pass8_challenges.sh OUT_DIR [se p14 pmax ipad]`
  runs `game/src/dev/challenges_capture.tscn` once per device (the V7
  approach: `--emulate-phone` point scale and `--emulate-safe` insets).
  The SE was rendered at its device pixels. The machine was heavily shared,
  so the 844×390, 926×428 and iPad shapes were rendered with `FAST=1`: at
  their canvas size (720 or 960 units high) with the matching point scale,
  exactly as V7's `s1536` shots were. Layout in canvas units, the 44 pt
  touch size and the safe area are the device's; only the picture has fewer
  pixels (for device pixels, run without `FAST=1`; the headless layout test
  `test_challenges::test_season_pass_challenges_fit_with_both_rows_whole`
  measures all four shapes at device pixels). Each run writes
  `measure.json` with the final allocated rects (pass rows, side panel,
  tabs, Challenges page and cards, results challenge lines, any pressable
  control cut off).
- **States, labelled:** every `svcon_test` picture uses the **test-double
  service** (`game/src/dev/fake_commerce_service.gd`), stamped bottom-left
  "Dev fixture · test-double service (not the live service)". The service
  is **not deployed**; `svcoff` is the shipped state. The challenge
  progress is a fixture (Night Shift 1/2, Campus Contribution 4/6 and
  pinned, Team Effort done, Campus Regular 6/10, Pull Your Weight 11/18,
  Strong Together 2/4) as settled rounds would have left it; the results
  shots then settle real rounds through the double.
- **Local time:** the capture machine runs in UTC, so "Resets 12:00 AM" is
  the real local reset time there; a player in New York sees "Resets 8:00
  PM" (tested in `test_challenges`).
- **Images:** PNG captures converted to JPEG (q85), at most 1280 px wide.

### Devices (landscape)

| Folder | Points | Device pixels | Rendered at | Emulated point scale | Safe area, points (L, T, R, B) |
|---|---|---|---|---|---|
| `se` | 667×375 | 1334×750 | 1334×750 | 2 | 0, 0, 0, 0 |
| `p14` | 844×390 | 2532×1170 | 1558×720 | 1.846 (= 3 × 720/1170) | 47, 0, 47, 21 |
| `pmax` | 926×428 | 2778×1284 | 1558×720 | 1.682 (= 3 × 720/1284) | 47, 0, 47, 21 |
| `ipad` | 1024×768 | 2048×1536 | 1280×960 | 1.25 (= 2 × 960/1536) | 0, 24, 0, 20 |

## Shots

| File | Shows |
|---|---|
| `01_svcon_test_pass_challenges.jpg` | The Season Pass opens on the Challenges page: heading, the role line once, Daily with the local reset time, cards with task, bar, "4/6", "+50 Season XP", a done check (Team Effort) and the pin flag (Campus Contribution). Header, Claim all and both pass rows exactly as in V7 |
| `02_svcon_test_pass_challenges_weekly.jpg` | The list scrolled (finger scroll) to Weekly ("Resets Mon …"), +150 Season XP, and the pin hint |
| `03_svcon_test_pass_reward_detail.jpg` | A tapped reward: the Reward page with its action; the track unchanged |
| `04_svcon_test_pass_after_round.jpg` | After a settled round: the dailies complete, the pass at tier 17 (the challenge bonus is in the Season XP) |
| `05_svcon_test_results_challenge_settled.jpg` | Results, settled: "Night Shift complete · +50 Season XP", "Campus Contribution complete · +50 Season XP", the weekly goals the round moved, then "Season tier 16 · tier up!" and its bar |
| `06_svcon_test_results_challenge_pending.jpg` | Results while the confirmation is unanswered: expected rewards "not added yet" and "Strong Together complete · +150 Season XP (pending)" |
| `07_practice_results_training.jpg` | Practice: "Training only: 3 contribution credits. Practice doesn't count toward challenges." |
| `10_svcoff_pass_challenges_preview.jpg` | Service off (as shipped): "Preview: no game service in this build. No progress or Season XP is added." and goal previews without bars, counts or completion |

## Measured (from `measure.json`)

| Device | View (canvas units) | Free / Premium rows y | Safe bottom | Rows whole in every Pass shot | Side panel | Tab height | Cards wholly in view at open | Card height (min) | Pressables cut off (all shots) |
|---|---|---|---|---|---|---|---|---|---|
| `se` | 1280×720 | 281-481 / 489-689 (cell h 200) | 708 | yes | 323×575 | 85 | 3 (2 service off) | 108 | 0 |
| `p14` | 1558×720 | 275-465 / 473-663 (cell h 190) | 681 | yes | 360×552 | 82 | 3 (2 service off) | 108 | 0 |
| `pmax` | 1558×720 | 261-459 / 467-665 (cell h 198) | 685 | yes | 364×562 | 75 | 3 (2 service off) | 108 | 0 |
| `ipad` | 1280×960 | 265-505 / 513-753 (cell h 240) | 935 | yes | 323×805 | 55 | 5 (4 service off) | 108 | 0 |

44 pt in canvas units (`touch_min` in each measure.json): SE 84.5, 844×390 81.2, 926×428 74.0, iPad 55.0; every tab and card is at least that tall. The pass rows are exactly the V7 measurements (docs/v7/menus_notes.md): the Challenges page takes no height from the track.
