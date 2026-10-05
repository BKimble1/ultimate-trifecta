# Pass 9 notes: two reference skins, outfit fit, steady movement, Season to tier 100, round music (version 1.9)

Pass 9 builds on 1.8 (8) and is additive. Pass 8's evidence and notes are
unchanged.

Everything here was built and measured on desktop Linux: headless Godot
4.7.2, the Mobile renderer on Mesa llvmpipe under Xvfb, Blender as a Python
module for the character asset, and the service's Node tests. **No iPhone or
iPad was available to this work.**

Unverified until someone tests on a device or with the account holder:
- device feel, frame rate, memory and thermals;
- touch feel at the stick's rim;
- human balance;
- StoreKit, App Store products and the deployed service.

## Workstreams

| Area (brief §) | Notes | Evidence |
|---|---|---|
| Steady full-input speed, no stamina, protocol 8, balance (§9, §10) | [pass9/movement.md](pass9/movement.md) | [media/pass9/movement/](media/pass9/movement/), [pass9/data/](pass9/data/) |
| Garment fit and animation (§7, §8) | [pass9/fit.md](pass9/fit.md) | [media/pass9/fit/](media/pass9/fit/) |
| Record Breaker and Dr. Doom complete skins (§3, §4, §5) | [pass9/skins.md](pass9/skins.md) | [media/pass9/skins/](media/pass9/skins/) |
| Season 1 to tier 100 (§6) | [pass9/season.md](pass9/season.md), [ECONOMY.md §4](ECONOMY.md) | [media/pass9/season/](media/pass9/season/README.md) |
| Round music "Soft Bounce Loop" and the lobby → round blend (owner request during the pass) | [pass9/music.md](pass9/music.md) | [media/pass9/music/](media/pass9/music/) |

## What shipped

- **Movement.**
  - One steady full-input speed per role: runner 6.0 m/s, Night Watch 6.6,
    for as long as the input is held, on touch, controller and keyboard.
  - The sprint meter, button, edge sprint, latch, HUD hint and setting are
    gone. Old saved sprint settings are dropped and everything else is kept.
  - "fast" comes from actual speed: footsteps, expressions, bots and the
    view use it.
  - Dive unchanged: 8.0 m/s, the 0.45 s recovery, one dive per jump.
  - Protocol 8: older builds are refused with "Update the game to join."
- **Two complete skins.**
  - **Record Breaker** (`outfit:record_breaker`, Premium tier 50): a toothy
    smile, swept-up tousled curls, a bare torso, white athletic shorts, a
    green wristband on the character's right wrist, and brown sandals.
  - **Dr. Doom** (`outfit:dr_doom`, Premium tier 100): a broad face with a
    knowing smile, a bald crown with a grey-brown fringe, a brown suit, a
    striped shirt, a gold striped tie, and formal shoes.
  - Each brings its own head, face and expressions. Saved modular choices
    are kept and restored. The Night Watch uniform rule stays. Cosmetics
    have no gameplay effect.
- **Garment fit and animation.**
  - Cuffs, hems, shoulder caps, hip tops, footwear and trims now sit on the
    body. The cause was in the generated garments, not the import.
  - New offline (`fit_check.py`) and in-game (`test_fit_p9`) fit checks.
  - The reversal and stop snaps at the new speed are gone.
- **Season 1 · After Hours to tier 100.**
  - Tiers 1–30, all XP, claims and Premium are unchanged; tiers 31–100 cost
    350 Season XP each.
  - Rewards every 5 tiers; a tier-100 badge; the two skins at 50 and 100.
  - Claims are idempotent.
  - Navigation: You're at, Next reward, and the 30, 50 and 100 shortcuts.
  - The service is still not deployed, so nothing is live.
- **Round music.** The owner's "Soft Bounce Loop" replaces the synthesized
  round music, as a sample-exact 16-bar loop. It blends in from the lobby
  music on the beat, with the lobby filtered out underneath.

## Defect register

Each entry runs symptom → reproduction → measured cause → change →
evidence. The full registers are in each area's notes.

| # | Symptom | Measured cause | Change | Evidence |
|---|---|---|---|---|
| M1 | Running speed cycles with stamina | A 2.5 s meter to 7.4 m/s over a 5.0 m/s run. The Pass 8 best was release / re-press at 50 %: a sawtooth averaging 5.98 m/s | Removed. One steady 6.0 m/s at full input, sustainable indefinitely | 60 s probe: min 6.00, 0 drop ticks. Real touches at the rim: 3582/3582 frames at 6.000. Online 60 s: min 5.97, corrections ≤ 0.1 cm |
| M2 | Runner bots crawl along walls (found while testing M1, also on 1.8) | A path segment grazing a tall wall made bots slide at cos(angle) of their speed, 4.6 → 0.8 m/s. Runners never hopped low walls on their way to a water | Bots run along tall walls; runners hop low walls (both roles' bots) | `test_bots_run_steadily`. Routes 96/96, median 111.5 s |
| M3 | A lag-compensation test failed after the speed change | With 0.6 m/s closure, a client Watch that misses a head-on pass at 150 ms round-trip can't catch back up inside a 3 s zig-zag leg (one phase: 13 misses in 40 s). The test's phase also depended on which tests ran before it | The test uses 6 s legs anchored to the moment the two are placed. No tag change | All phases catch in 2.7–7.5 s |
| F1 | Costumes appear off the body | In the generated garments: cuffs stood 4.2 cm off the wrist with a dark lining; shorts hems flared 8 cm and crossed the midline; shoulder caps and hip tops parted by up to 8.8 cm in motion; footwear was weighted to the foot alone. The import was sound: skeleton paths, Skin, binds and normals were all checked | Fixed in the generator (`parts`, `rig`, `geo`, `kit6`, `outfits_v6`, `outfits_p8`) | `fit_check` 120 → 0 failures (24 looks × 567 poses); `test_fit_p9` 14 → 0; close-ups before/after |
| F2 | Snaps at the new 6.0 m/s (22 tests) | A reversal passes through zero speed for a tick and fired the planted stop for one frame: a 24.8 cm hand snap and a 1.09 m/s foot slide | The planted stop needs the body stopped for 30 ms over two frames, and fades from the pose shown | Snap 4.5 cm, slide 0.04 m/s; all 22 pass |
| S1 | White shorts read blue or grey | Cloth material class: no self-light, plus a blue rim sheen | The lit white class used by eye whites, rough | Mean front-panel RGB in the dorm 99,93,107 → 174,171,174 (eye white 172,171,176) |
| S2 | Skins' fit (found by F1's new check) | Shorts built on the base torso profile; the suit's pieces used different weight fields; trouser hems were weighted apart from the shoes | They follow the real surface and share weight fields | `fit_check` 0 failures; in game, worst 0.8 cm |

## Verification summary

See `TEST_REPORT.md` (Pass 9) for the full gate.

- **Game suite:** 516 tests, 104,884 checks, 0 failures on the integrated
  branch before the last skin and music commits. The final gate is recorded
  in TEST_REPORT.
- **Service:** 68/68.
- **Character checks:** `fit_check`, `skins_check`, `outfit_check` and
  `clip_check` all 0 failures.
- **Balance:** a seeded bot-round matrix, 12 rounds per team size, on 1.8,
  on 1.9 with 1.8 bot steering, on 1.9 as shipped, and on a Night Watch
  6.8 m/s experiment (not adopted). Details in `pass9/movement.md` §4.

## Owner dependencies

- **Likeness consent.** Record Breaker and Dr. Doom are stylised likenesses
  of real people, made from the owner's photos. Confirm their permission
  before any wider distribution.
- **Music rights.** "Soft Bounce Loop" and "Night Campus Loop" are the
  owner's tracks from mureka.ai. Confirm that service's terms for commercial
  use.
- **The economy service** is not deployed and no App Store products exist.
  Season claims, Coin purchases and challenge progress stay previews until it
  is deployed (`docs/COMMERCE_SETUP.md`). Migration 0005 is applied by
  `scripts/deploy.sh`.
- **Device and human playtest steps** are in each area's notes and in What to
  Test.
