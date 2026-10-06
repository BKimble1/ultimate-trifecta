# App Store screenshots · version 2.0 (proposed sets)

**For the owner to approve, or to replace any of them with device
screenshots.** Every picture is a **desktop render of the release
candidate**: rendered from commit `dcb8209` (this branch merged with the
release branch `claude/ultimate-trifecta-testflight-oie9r7` at `66e7575`:
Season Pass, Friends, Shop, lobby lighting and the ARTFIX outfit fixes),
character art **`v10-49a45748ffed`** (`game/assets/characters/runner_manifest.json`).
They show the game's own screens and a real practice round,
drawn by Godot 4.7.2's **Mobile renderer on llvmpipe** (Mesa software
rendering, limited to AVX by `tools/gd.sh` so characters keep their
directional light) under Xvfb, at the exact store size, with each device's
point scale (44 pt touch targets) and landscape safe area. Nothing is drawn
over the game: no evidence stamp, label, debug overlay or "(test price)"
(the drivers' `--store-shot` mode). Not a device capture; not frame-rate
evidence.

**Fixtures.** Season Pass, Shop, wallet and Locker run on the **test-double
game service** and the **simulated store** (`game/src/dev/fake_commerce_service.gd`,
`game/src/dev/test_store_adapter.gd`); Friends on the **test-double Friends
service and Game Center stand-in** (`game/src/dev/fake_friends.gd`); the
party is eight in-process sessions on the loopback transport (no network);
the results are a three-round series recorded through the game's own
`PartySeries`. **All player names and Game Center nicknames are fictional**
("Comfy Frog" is the player). The two reference skins appear only as
Record Breaker and Dr. Doom. The service is not deployed and no App Store
products exist yet: nothing here is a live price, purchase or friend.

| Set | Size (px) | Device class | Points, scale | Safe area (pt L,T,R,B) |
|---|---|---|---|---|
| [`iphone_6.9/`](iphone_6.9/) | **2868 × 1320** landscape | iPhone 6.9" (16/17 Pro Max class) | 956 × 440 @3x | 62, 0, 62, 21 |
| [`ipad_13/`](ipad_13/) | **2752 × 2064** landscape | iPad 13" | 1376 × 1032 @2x | 0, 24, 0, 20 |

All images: PNG, 8-bit RGB, no alpha, sRGB (`tools/store_shot_check.py`).

## The shots (same order and names in both sets)

| File | What it shows | How it was made |
|---|---|---|
| `01_runner_splash_fountain.png` | **Gameplay, runner: a near miss.** A runner in the striped pajamas and nightcap leaps for Founders' Fountain at night, Bellweather Tower behind, a Night Watch two steps away. HUD: Runner · Practice, 1/3 waters, "Next: Fountain", "Night Watch in sight · 2 m" (with the danger edge glow), "footsteps nearby", the round clock, minimap, stick and Dive (the jump button in the air). | Practice round, seed 2 (the fountain is one of the round's waters), Standard graphics, fixed 20 fps clock. `store_match_capture.gd` places the runner on the central path and the Night Watch on the plaza, then holds both sticks (the runner straight at the fountain, jumping at the rim; the Watch straight at the runner); the simulation, animation and HUD are the game's. Frame `splash_air_0` (0.1 s after the jump). |
| `02_night_watch_golf_cart.png` | **Gameplay, Night Watch.** Driving a golf cart down Library Lane, closing on a runner ("Slipper · BOT") with a second runner further ahead; "footsteps nearby" cue; HUD: Night Watch, tags, "Driving · hop out to tag", the three waters' distances, Gas/Brake/Exit and Steer. | Same round as Night Watch: the driver seats the player in a cart on Library Lane, two runner bots run ahead on their own sticks, the player's stick holds the throttle. Frame `cart_d` (1.8 s in). |
| `03_party_of_eight.png` | A full party of eight in the dorm lobby, everyone ready: party code, Friends, the settings summary (3 rounds · 2 Night Watch · 4 home to win), the roster, Start. Outfits: Varsity Sprinter (you), Record Breaker, Dr. Doom, Moonwalk Cadet, Raincoat Explorer, pink Pajamas, Duck Mascot, Pumpkin Pajamas. | Eight loopback sessions (no network), curated game-style names. |
| `04_season_pass_record_breaker.png` | The Season Pass (Season 1 · After Hours, Premium, Tier 43 / 100, "Claim all (2)") with Tier 50's **Record Breaker** standing large on the stage beside the reward details (Locked · 2,300 XP to unlock). | Test-double service: 13,000 Season XP, Premium, rewards through tier 43 claimed except tier 40. |
| `05_shop_featured.png` | The Shop's Featured page: four rotating skins with **Coin prices only** (800 / 900 / 1,000 / 1,000) and their countdowns; Always available below (on iPad the two App Store outfits show "Owned · App Store", so no store price is on screen). | Test-double service on the fixture service clock (2026-10-06 21:45 UTC), 2,650 Coins; both App Store outfits owned. |
| `06_friends_invite.png` | Friends over a party of four: friends Online, In your party, In a party, In a round, Offline (iPad shows the whole list); one "Invited ✓", Invite buttons, the party code. | Test-double Friends service and Game Center stand-in; fictional nicknames (PillowFortPro, nightowl_88, otterly.fast, quadsprinter, moonbeam.runs, SockSlider, lilnapper). |
| `07_locker.png` | The Locker's Outfit tab: a well-stocked wardrobe (Pajamas, Swim Trunks, Fluffy Robe, Duck Mascot, Frog Onesie, Moonlight Runner, Starry Sleeper, Varsity Sprinter equipped, …) with the runner on the stage. | Test-double wallet: Shop, Season and App Store outfits owned. |
| `08_final_standings.png` | A friend series' Final standings: You 1st with 3 Round Wins, Sleepy Otter and Bouncy Panda tied 2nd, the table, Return to lobby. | A three-round series recorded through `PartySeries` (the real Round Win and shared-place rules). |

**Outfit art.** The sets include the ARTFIX garment fixes (art
`v10-49a45748ffed`: hooded onesies' belly panels and hood rims, Dr. Doom's
jacket, the headlamp and head bands). Where those outfits appear: Dr. Doom
in `03` and `06` (and a small portrait on the 100 chip in `04`), Duck
Mascot in `03`, `07`; Frog Onesie in `07`; Cloud Nine and Bedtime Bandit
cards in `05`; Starry Sleeper (sleep mask) in `07` and on a runner in `02`.
If character art changes again, re-run the script.

## App Review references (`iap/`, iPhone size, NOT store assets)

| File | What |
|---|---|
| `iap/iap_coin_packs_reference.png` | Shop › Coins: the six Coin packs (consumables) and Restore Purchases |
| `iap/iap_moonlight_runner_reference.png` | Moonlight Runner's detail sheet (non-consumable App Store outfit): Buy, Restore |
| `iap/iap_starry_sleeper_reference.png` | Starry Sleeper's detail sheet (non-consumable App Store outfit): Buy, Restore |

These show the purchase screens **as the game renders them with the
simulated store**, so the price reads "(test price)", and each carries a red
"REFERENCE ONLY" label. Apple's required in-app purchase review screenshots
**must be retaken on a device** once the products exist in App Store
Connect (sandbox account, real localized prices). Never submit these.

## How to re-render

```
tools/capture_store_screenshots.sh OUT_DIR            # both sets + iap
tools/capture_store_screenshots.sh OUT_DIR iphone     # one device
ONLY="menus" tools/capture_store_screenshots.sh OUT_DIR ipad   # one part
python3 tools/store_shot_check.py OUT_DIR             # size / RGB / sRGB
```

Drivers (development only, `game/src/dev`, never exported):
`store_capture.gd/.tscn` (menus, IAP references), `store_match_capture.gd`
(gameplay, via `--capture=store_match`), `store_shot.gd` (the `--store-shot`
flag: no stamps or overlays, RGB PNG). The evidence drivers
`lobby_light_capture.gd`, `season_final_capture.gd`, `friends_capture.gd`,
`capture_shop_p8.gd`/`capture_shop_final.gd` and `capture.gd` also honour
`--store-shot`. Every frame the drivers take stays in `OUT_DIR/raw/` (other
gameplay moments: `splash_air_*`, `splash_in_*` through the splash,
`cart_a…e`); `SPLASH_PICK=` / `CART_PICK=` choose another and `ONLY=none`
re-assembles the sets from `raw/` without rendering. Both sets together
took about 1 h 45 min on this shared 4-core machine.

## Checks done

- `tools/store_shot_check.py` on this folder: **19 images, all pass**
  (exact size, 8-bit RGB, no alpha, sRGB); output in
  [`check.txt`](check.txt). Total size 34 MB.
- By eye, every image at full size (and crops of the HUD, the party and the
  pass detail): text crisp at the store size; nothing cut by the safe areas
  (the iPhone HUD and menus sit inside the 62 pt side insets and above the
  21 pt home-indicator band; the iPad's inside 24/20 pt); characters lit
  (no dark faces); no evidence stamp, debug text, diagnostics overlay or
  "(test price)" on the 16 store images (the `iap/` references carry their
  label and the simulated price on purpose).
