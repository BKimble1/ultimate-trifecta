# Pass 9 Season Pass evidence: 100 tiers, navigation, milestones, Record Breaker and Dr. Doom

Notes: [../../../pass9/season.md](../../../pass9/season.md). Rules and
tables: [ECONOMY.md §4](../../../ECONOMY.md).

## How these were made

- **Renderer:** the real Season Pass screen, rendered by Godot 4.7.2's
  Mobile renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb on a
  shared desktop Linux machine: **desktop renders**, layout and states only.
  Not frame rate, touch feel or a device. No iPhone or iPad was used.
- **Tooling:** `tools/capture_pass9_season.sh OUT_DIR [se p14 pmax ipad]`
  runs `game/src/dev/season100_capture.tscn` once per device
  (`--emulate-phone` point scale, `--emulate-safe` insets; `ONLY=<shot>`
  re-takes one shot). The SE was rendered at its device pixels; the
  844×390, 926×428 and iPad shapes with `FAST=1`, at their canvas size with
  the matching point scale (the Pass 8 / V7 `s1536` approach: the layout in
  canvas units, the 44 pt touch size and the safe area are the device's;
  only the picture has fewer pixels). The headless test
  `test_season100::test_navigation_and_milestones_fit_every_device`
  measures all four shapes at device pixels. Each run writes
  `measure.json` (navigation row and chips, both reward rows, the progress
  runs in view, the side panel, the focused cell and its state, the detail
  texts and action, any pressable control cut off).
- **States, labelled:** every `svcon_test` picture uses the **test-double
  service** (`game/src/dev/fake_commerce_service.gd`) and is stamped
  "Dev fixture · test-double service (not the live service) · desktop
  render". The service is **not deployed**; `svcoff` is the shipped state.
  The fixtures are Season XP, Premium and claims set on the double as
  settled rounds and claims would have left them; claims shown as made
  (06) went through the real wallet and the double.
- **The two skins' art is not in this branch** (it comes from the SKINS9
  stream): Record Breaker and Dr. Doom show the neutral picture, a neutral
  head on their milestone chips, and "Preview not available in this
  build." This is the intended state while the art is absent. Shot 12 shows
  the featured-skin preview path with a **stand-in** (Glow Jogger set as a
  featured tier, labelled on the picture); it drops out by itself once the
  skins' art is in the build. Re-run the tool after the merge for the real
  portraits and the live preview.
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
| `01_svcon_test_pass_open_tier43` | A regular player (Premium, Season XP for Tier 43, tier 40 not yet claimed) opens the pass: "Tier 43 / 100", the navigation row ("You're at Tier 43", "Next reward · Tier 45 · 550 XP", Tier 30 / 50 / 100), progress runs ("36–39", "41–44" with Tier 43 ringed), the claimable tier 40, Claim all (2), the Challenges page |
| `02_svcon_test_nav_current_run` | "You're at" tapped: the 41–44 run selected; its detail ("Progress tiers · No reward on either track", what it counts toward, 550 more Season XP) and "Show Tier 45" |
| `03_svcon_test_milestone_50_record_breaker` | The Tier 50 shortcut: Record Breaker, locked, "Reach Tier 50: 2,300 more Season XP …", description and includes; the neutral picture with "Preview not available in this build." |
| `04_svcon_test_milestone_100_dr_doom` | The Tier 100 shortcut: Dr. Doom (locked, 19,800 more Season XP) beside the Season 1 Legend badge; runs 86–89 … 96–99 |
| `05_svcon_test_tier40_claimable` | Tier 40 Premium (Big Dive badge) ready: the one Claim in the detail, Claim all in the header |
| `06_svcon_test_tier40_claimed` | The same after claiming: claimed mark, "Wear it in the Locker" |
| `07_svcon_test_free_tier52_record_breaker_premium_locked` | A free player at Tier 52: Record Breaker reached but Premium-locked, "Reached. Premium (1,500 Coins in the Shop) unlocks it." whole, "Get Premium in the Shop" |
| `08_svcon_test_free_tier50_badge_claimable` | The same player's tier 50 Free reward (Record Pace badge, the stopwatch) claimable |
| `09_svcon_test_tier100_dr_doom_claimed` | A finished pass: "Tier 100 / 100", "Every tier reached", "Next reward · All reached", Dr. Doom claimed |
| `10_svcon_test_claim_pending` | A claim sent while the network is down: the cell's pending mark, "Your claim is on its way …", "Claiming…" (disabled); Claim all counts only what isn't queued |
| `11_svcon_test_old_service_tier50` | The double acting as an **older (30-tier) service**: tier 50 earned, "Nothing to claim", the reason "The game service hasn't been updated for this tier yet …" and a disabled Claim |
| `12_svcon_test_featured_preview_path_standin` | **Stand-in** (labelled): Glow Jogger as a featured tier: its face on the milestone chip (Portraits) and the live preview swaying around its three-quarter view, the path Record Breaker and Dr. Doom take once their art is in the build |
| `20_svcoff_pass_preview` | Service off (as shipped): "Rewards unavailable right now", the navigation row, tier 1 earned, the Challenges preview |
| `21_svcoff_milestone_100` | Service off: the Tier 100 shortcut still browses Dr. Doom with its lock reason (and "Premium track: needs Premium too.") |

## Measured (from `measure.json`)

| Device | View (canvas units) | 44 pt | Navigation row y (height) | Free / Premium rows y | Cell | Side panel | Chips whole, ≥ 44 pt | Rows whole in every shot | Detail action on screen | Pressables cut off |
|---|---|---|---|---|---|---|---|---|---|---|
| `se` | 1280×720 | 84.5 | 242-327 (85) | 374-527 / 535-688 | 122×153 | 323×575 | yes | yes | yes | 0 |
| `p14` | 1558×720 | 81.2 | 236-318 (82) | 365-510 / 518-663 | 116×145 | 360×552 | yes | yes | yes | 0 |
| `pmax` | 1558×720 | 74.0 | 222-297 (75) | 344-501 / 509-666 | 125×157 | 364×562 | yes | yes | yes | 0 |
| `ipad` | 1280×960 | 55.0 | 226-281 (55) | 328-568 / 576-816 | 192×240 | 323×805 | yes | yes | yes | 0 |

Compared with Pass 8 (the same screen without the navigation row), the
phone cells are shorter (SE 160×200 → 122×153) and still whole 44 pt
targets with Free and Premium whole; the iPad cells are unchanged. The side
panel stays inside the screen in every shot (the V7 SE panel overflowed with
a long action; see the defect register in the notes).
