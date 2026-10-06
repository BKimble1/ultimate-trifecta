# Final release sweep · App Store screenshots (STORE)

Brief §9, "Content and metadata": final in-app iPhone and iPad screenshots
at currently accepted sizes, actual gameplay and polished UI, fictional
players, real enabled features. Evidence and the sets:
[`../media/final/store/`](../media/final/store/) (its README lists every
file).

**Status.** Two proposed sets rendered from the release candidate at the
exact store sizes, 8 shots each: iPhone 6.9" **2868 × 1320** and iPad 13"
**2752 × 2064**, landscape, PNG 8-bit RGB, no alpha, sRGB, nothing stamped.
Plus three labelled App Review references (`iap/`). They are **desktop
renders** (Mobile renderer on llvmpipe, Mesa limited to AVX), not device
captures: the owner approves them or replaces any with device screenshots.
No game code changed; everything new is under `game/src/dev` (never
exported) and `tools/`.

## What was built

- `game/src/dev/store_shot.gd`: the `--store-shot` mode. Drivers that read
  it draw no evidence stamp/label, switch the beta diagnostics overlay off
  and save RGB PNGs (App Store Connect rejects alpha). Honoured by
  `capture.gd` (its `snap`), `lobby_light_capture.gd`,
  `season_final_capture.gd`, `friends_capture.gd` and `capture_shop_p8.gd`
  (so `capture_shop_final.gd`); a few additive lines each.
- `game/src/dev/store_capture.gd` + `.tscn`: the menu shots. It extends
  `season_final_capture.gd` (profile, test-double service, Season states,
  snap + figure measure) and reuses `fake_commerce_service.gd`,
  `test_store_adapter.gd`, `fake_friends.gd`, the loopback party of
  `lobby_light_capture.gd` and a `PartySeries` series like
  `capture_pass8_match.gd`. Waits that depend on the loopback transport
  count frames, not seconds (a full-size software frame can outlast a
  timer). `--set=iap` renders the App Review references with a visible
  REFERENCE label.
- `game/src/dev/store_match_capture.gd` (`--capture=store_match`, routed by
  `capture.gd`): extends `capture_pass8_match.gd`. A practice round on
  Standard graphics and a fixed 20 fps clock; the driver places players and
  holds sticks through `MatchController.input_source` (the local player)
  and a scripted brain (bots): the same `InputCmd`s a thumb, a pad or
  `BotBrain` produce. The simulation, animation, splash, HUD and danger cue
  are the game's. Night Watch bots that took a cart at the shed are seated
  out of it first (state IN_CART otherwise pins them to the cart).
- `tools/capture_store_screenshots.sh OUT_DIR [iphone] [ipad]`: renders both
  sets at the real pixel size (no FAST canvas trick), assembles
  `iphone_6.9/`, `ipad_13/`, `iap/`, keeps every raw frame, then runs
  `tools/store_shot_check.py` (size, RGB, 8-bit, sRGB from the files'
  headers).

## Decisions

- **Fixtures, honestly.** The service is not deployed and no products
  exist, so Season, Shop, Locker and Friends run on the test-double service
  and simulated store, as every earlier evidence pass did; the README says
  so. The store frames show only what the game draws in those states.
- **No Apple prices on store frames.** The Shop shot shows Featured (Coin
  prices); the fixture player owns both App Store outfits, so their cards
  read "Owned · App Store" where the iPad shows them. The IAP references
  show "(test price)" as the game renders it with the simulated store and
  are labelled REFERENCE ONLY; no fake "real-looking" price anywhere.
- **Gameplay moments are staged, not invented.** Seed 2 makes the fountain
  one of the round's waters; the chase and the cart frames are chosen from
  several taken through each moment (all kept in `raw/`).
- **Names.** Game-style fictional names ("Comfy Frog", "Sleepy Otter", …),
  fictional Game Center nicknames; no real person's name.

## How verified

- Renders: `tools/capture_store_screenshots.sh build/store_v10 iphone ipad`
  (Xvfb, `GALLIUM_OVERRIDE_CPU_CAPS=avx` via `tools/gd.sh`) at commit
  `dcb8209` (the release branch at `66e7575` merged in; character art
  `v10-49a45748ffed`). A first full render before the ARTFIX merge
  confirmed every frame; its iPad splash put the Night Watch at the 4:3
  frame's edge, so the Watch now starts nearer the fountain.
  Framing was iterated first with `FAST=1` (point-size renders) and
  headless runs of the gameplay driver (player positions logged per frame).
- `python3 tools/store_shot_check.py docs/media/final/store`: all images
  pass (output in [`../media/final/store/check.txt`](../media/final/store/check.txt)).
- Every image inspected at full size (crops of the HUD, the party, the pass
  detail): crisp text, safe areas respected, characters lit.

## Open items

- **Device captures**: the owner approves these or retakes any on a
  device (an iPhone 16/17 Pro Max class phone gives 2868 × 1320 natively;
  an iPad Pro 13" gives 2752 × 2064).
- **IAP review screenshots** must be taken on a device once the eight
  products exist (sandbox prices).
- **ARTFIX**: merged before the final render (release branch `66e7575`,
  art `v10-49a45748ffed`); every shot of both sets was re-rendered from it.
  Re-run the script if character art changes again.
- Outside this stream (FRIENDS): the Friends evidence fixture
  (`game/src/dev/friends_capture.gd`, and its pictures in
  `docs/media/final/friends/`) uses a famous historical composer's full name
  as its long Game Center nickname. Not a store asset, but the privacy rule
  asks for fictional names only; worth swapping for an invented long name.
- Not part of the sets: the per-round results card in this fixture shows
  "No rewards for this round" (no wallet result in a dev series), so the
  set uses Final standings instead.

## For the integrator

- Merge as is; files outside `game/src/dev`, `tools/` and docs: none.
- Proposed line for `docs/APP_STORE.md` (screenshots section): "Proposed
  2.0 screenshot sets (iPhone 6.9" 2868 × 1320, iPad 13" 2752 × 2064) and
  IAP review references are in `docs/media/final/store/`; re-render with
  `tools/capture_store_screenshots.sh`. Desktop renders: approve or replace
  with device captures; retake IAP review screenshots on a device."
