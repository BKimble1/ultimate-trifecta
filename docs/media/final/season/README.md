# Final release sweep · Season Pass evidence

Notes: [../../../final/season.md](../../../final/season.md).

## How these were made

- **Renderer:** the real Season Pass, rendered by Godot 4.7.2's Mobile
  renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb on a shared
  desktop Linux machine: **desktop renders**. Layout, look and scripted
  input only; not frame rate, touch feel or a device. No iPhone or iPad was
  used.
- **Tooling:** `tools/capture_final_season.sh OUT_DIR before|after|skins
  [se p14 pmax ipad]` runs `game/src/dev/season_final_capture.tscn` once
  per device (`--emulate-phone` point scale, `--emulate-safe` insets). The
  SE is rendered at its device pixels; 844×390, 926×428 and the iPad with
  `FAST=1` at their canvas size with the device's point scale (the layout,
  the 44 pt touch size and the safe area are the device's; only the
  picture has fewer pixels), as Pass 9 did. The same scene measures the
  1.9 screen (`before`) and the rebuilt one (`after`).
- **States, labelled on every picture:** `svcoff` is the shipped state (no
  service URL in 1.9). Every `svcon_test` picture uses the **test-double
  service** (`game/src/dev/fake_commerce_service.gd`) and is stamped "Dev
  fixture · test-double service (not the live service) · desktop render";
  the failed sign-in, offline, signed-out and older-service shots say so
  in the stamp too. The game service is not deployed; nothing here is a
  live claim.
- **measure.json** (per device): the selected skin's figure projected on
  screen (top of the visible parts' rest-pose bounds to the soles at the
  model's centre line: units and points, where it is drawn), the cell size,
  the track, and every pressable control cut off by an edge, a clipping
  parent or the safe area where no scrolling brings it back (0 in every
  shot).
- **Images:** PNG captures converted to JPEG q85, at most 1280 px wide.

| Folder | Points | Device pixels | Rendered at | Point scale | Safe area, pt (L, T, R, B) |
|---|---|---|---|---|---|
| `se` | 667×375 | 1334×750 | 1334×750 | 2 | 0, 0, 0, 0 |
| `p14` | 844×390 | 2532×1170 | 1558×720 | 1.846 | 47, 0, 47, 21 |
| `pmax` | 926×428 | 2778×1284 | 1558×720 | 1.682 | 47, 0, 47, 21 |
| `ipad` | 1024×768 | 2048×1536 | 1280×960 | 1.25 | 0, 24, 0, 20 |

## before/ (the 1.9 Season Pass, `e3c2cd6`)

| File | Shows |
|---|---|
| `b01_svcoff_tier1_open` | Service off, a new player: the pass as it opens ("Season 1 · Af…", "Rewards unavailable right now" in the header row) |
| `b02_svcoff_tier1_record_breaker` | **The owner's screenshot state (IMG_3043):** the Tier 50 shortcut, Record Breaker a small swaying figure above five lines of state text, the description cut at the panel's foot, the dorm's runner a shadow behind the track |
| `b03_svcoff_tier1_dr_doom` | The same for Dr. Doom |
| `b04_svcon_test_tier43_record_breaker` | Test double: a Premium player at Tier 43, Record Breaker selected |

## after/ (the rebuilt Season Pass)

| File | Shows |
|---|---|
| `a01_svcoff_tier1_open` | Service off: the status line said once, the pass opening on the next reward (a hat on the runner) |
| `a02_svcoff_tier1_record_breaker` | The IMG_3043 state rebuilt: Record Breaker on the stage, "TIER 50 · PREMIUM TRACK", Locked, "15,300 XP to unlock", "Needs Premium · 1,500 Coins", View Premium |
| `a03_svcoff_tier1_dr_doom` | Dr. Doom, service off |
| `a04_svcoff_challenges` | The Challenges tab, service off ("Preview only…") |
| `a10_svcon_test_tier43_open` | A regular Premium player at Tier 43: Claim all (2), a name card ready to claim (a big picture: nothing to turn) |
| `a11_svcon_test_progress_run` | "You're at": the 41–44 progress run, its steps in the stage column, "Show Tier 45" |
| `a12_svcon_test_tier30` | The Tier 30 shortcut: a claimed badge, Equip |
| `a13_svcon_test_record_breaker_locked` | Record Breaker locked by XP only ("2,300 XP to unlock") |
| `a14_svcon_test_record_breaker_turned` | The same, turned by the player (its back); Reset available |
| `a15_svcon_test_dr_doom_locked` | Dr. Doom, back at the start pose |
| `a16_svcon_test_tier40_claimable` | Tier 40 Premium badge: Ready to claim, the gold Claim |
| `a17_svcon_test_tier40_claimed` | The same after claiming through the real wallet: Claimed, Equip |
| `a18_svcon_test_challenges` | Challenges with live progress (a completion toast) |
| `a19_svcon_test_emote_reward` | An emote reward playing on the runner; the first tool reads Play |
| `a20_svcon_test_tier1` | Tier 1 Premium (Night Owl Onesie) claimed |
| `a21_svcon_test_free_record_breaker_premium_locked` | A Free player at Tier 52: Record Breaker reached, Needs Premium, Get Premium |
| `a22_svcon_test_free_tier50_badge_claimable` | The same player's Tier 50 Free badge, Ready to claim |
| `a23_svcon_test_dr_doom_claimed` | A finished pass: Dr. Doom claimed, Equip; Nothing to claim |
| `a24_svcon_test_dr_doom_equipped` | After Equip: Equipped, View in Locker |
| `a25_svcon_test_claim_pending` | A claim sent while the network was down: Claiming… |
| `a26_svcon_test_old_service_tier50` | The double acting as an older (30-tier) service: Earned, "Claiming for this tier isn't open yet." |
| `a27_svcon_test_signin_failed_earned` | Game Center sign-in failed: the status line says so; Record Breaker Earned, "It stays earned" over a disabled Claim |
| `a28_svcon_test_offline_earned` | No network at sign-in: "You're offline…" |
| `a29_svcon_test_signed_out` | Signed out of Game Center: "Sign in with Game Center to claim rewards." |

## skins/

| File | Shows |
|---|---|
| `inspection_p14_top.jpg`, `inspection_p14_bottom.jpg` | On the Season Pass stage at 844×390 scale, each from the three-quarter start, one profile, the back, the other profile: Record Breaker, Dr. Doom, the tallest look (Pumpkin Pajamas + party hat), the broadest (Bedtime Bandit), Night Owl + Owl Ears + Glow Sneakers, Glow Jogger + Headlamp + Moon Boots. The looks are put on the stage's runner directly (any outfit, the pass's own framing and light) |
| `zoom_dr_doom_profile.jpg`, `zoom_night_owl_profile.jpg` | The art findings (jacket front edges and back; belly patch and hood ring off the body) |
| `switch_frames.jpg` | Twelve consecutive 30 fps frames of the clip across the Record Breaker → Dr. Doom switch: a one-frame swap in the same pose |
| `measure_p14.json` | Every outfit's and hat's rest-pose bounds; the tallest and broadest picked |

## Clip

`season_pass_clip.mp4`: the real Season Pass driven by scripted pointer
input (the engine turns it into touches, as on desktop), recorded with
Movie Maker at a fixed 30 fps clock, so it plays at **normal speed**; a
1170×540 window (844×390 pt shape: 1560×720 canvas units with the iPhone's
point scale and safe area), test-double service, a dot shows the finger.
Timeline: the pass opens → Tier 50 (Record Breaker) → dragged round both
ways → Turn → Reset → Tier 100 (Dr. Doom) → dragged round → Run, Idle,
Reset → the pass track swiped both ways → Tier 50's badge (a picture) →
Record Breaker again → Challenges → Reward → Back: Home, the runner in the
saved pajamas (the reel's log: "saved look unchanged: true; runner shows it:
true"). Made with `tools/capture_final_season_reel.sh`.
