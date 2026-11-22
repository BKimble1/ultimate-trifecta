# App Store submission screenshots · 2.2 (build 29)

**Everything to upload for the 2.2 submission: the public App Store
screenshots (iPhone and iPad) and the review screenshot for each of the
9 in-app purchases.** Rendered on 22 Nov 2026 from the build 29 source
(submit build 29: the build these screens come from), at the exact store sizes, with the App Store
Connect prices (USA) on the purchase screens.

## Upload map

### In-app purchases (App Store Connect › your app › Monetization ›
In-App Purchases › the product › Review Information › Screenshot)

| # | Product (reference name) | Product ID | Price | Upload this file |
|---|---|---|---|---|
| 1 | Coins 250 | `com.idlery.ultimatetrifecta.coins.250` | $0.99 | [`iap/iap_coin_packs.png`](iap/iap_coin_packs.png) |
| 2 | Coins 500 | `com.idlery.ultimatetrifecta.coins.500` | $1.79 | [`iap/iap_coin_packs.png`](iap/iap_coin_packs.png) |
| 3 | Coins 1000 | `com.idlery.ultimatetrifecta.coins.1000` | $2.99 | [`iap/iap_coin_packs.png`](iap/iap_coin_packs.png) |
| 4 | Coins 1500 | `com.idlery.ultimatetrifecta.coins.1500` | $3.99 | [`iap/iap_coin_packs.png`](iap/iap_coin_packs.png) |
| 5 | Coins 3500 | `com.idlery.ultimatetrifecta.coins.3500` | $7.99 | [`iap/iap_coin_packs.png`](iap/iap_coin_packs.png) |
| 6 | Coins 7500 | `com.idlery.ultimatetrifecta.coins.7500` | $14.99 | [`iap/iap_coin_packs.png`](iap/iap_coin_packs.png) |
| 7 | Season 1 Premium Pass | `com.idlery.ultimatetrifecta.pass.s1` | $4.99 | [`iap/iap_premium_pass.png`](iap/iap_premium_pass.png) |
| 8 | Skin Moonlight Runner | `com.idlery.ultimatetrifecta.skin.moonlight_runner` | $1.99 | [`iap/iap_moonlight_runner.png`](iap/iap_moonlight_runner.png) |
| 9 | Skin Starry Sleeper | `com.idlery.ultimatetrifecta.skin.starry_sleeper` | $1.99 | [`iap/iap_starry_sleeper.png`](iap/iap_starry_sleeper.png) |

One Coins screenshot serves all six packs: it is the Shop › Coins page
showing all six packs side by side, each with its price (Apple asks for
a screenshot of the purchase as the user sees it; the same image may be
used for several products).

- `iap_coin_packs.png`: Shop › Coins: the six packs (250 / 500 / 1,000 /
  1,500 / 3,500 / 7,500 Coins) at $0.99 / $1.79 / $2.99 / $3.99 / $7.99 /
  $14.99, "Best value" on 7,500, Restore Purchases.
- `iap_moonlight_runner.png` / `iap_starry_sleeper.png`: the outfit's
  detail sheet from Shop › Featured › Always available: the runner wearing
  it, "Buy for $1.99", Restore Purchases.
- `iap_premium_pass.png`: the Season 1 Premium offer (Season Pass ›
  Premium): the Premium track's outfits and "Get Premium · $4.99" (plus the
  1,500 Coins option the game also offers).

### Public App Store screenshots (the 2.2 version page › Previews and Screenshots)

Upload in this order (01 first), the same nine in both sets.

| Order | File | What it shows |
|---|---|---|
| 1 | `01_runner_splash_fountain.png` | Gameplay as a runner: a leap into Founders' Fountain at night with the Night Watch two steps behind; the round HUD |
| 2 | `02_night_watch_golf_cart.png` | Gameplay as the Night Watch: driving a golf cart down Library Lane after two runners |
| 3 | `03_party_in_the_dorm.png` | A party of eight in the Christmas dorm lobby, everyone ready, Start |
| 4 | `04_basketball_in_the_dorm.png` | Walk mode in the lobby: the runner's shot dropping through the Christmas hoop, confetti |
| 5 | `05_season_pass_winter_break.png` | Season 1 · Winter Break pass: Premium, Tier 43 / 100, a claimed reward on the stage |
| 6 | `06_shop_featured.png` | The Shop's Featured page: rotating skins with Coin prices and countdowns, the two App Store outfits |
| 7 | `07_locker.png` | The Locker's Outfit tab with the runner on the stage |
| 8 | `08_friends_invite.png` | Friends: invite friends to the party, statuses, party code |
| 9 | `09_final_standings.png` | A party series' Final standings |

| Folder | Where in App Store Connect | Size |
|---|---|---|
| [`iphone_6.9/`](iphone_6.9/) | iPhone › **6.9" Display** | 2868 × 1320 (landscape) |
| [`ipad_13/`](ipad_13/) | iPad › **13" Display** | 2752 × 2064 (landscape) |

Only these two sizes are needed: App Store Connect scales the 6.9" set to
every smaller iPhone and the 13" set to every smaller iPad. The app runs
on iPad, so the iPad set is required.

## How they were made (truthful to the app)

Each picture is the real game's screen drawn by the game itself (Godot
4.7.2, Mobile renderer, software rendering on Linux at the device's exact
pixel size, point scale and safe area); nothing is drawn over it: no
mock-up, frame, caption, debug text or "(test price)" (the drivers'
`--store-shot` mode). The gameplay shots are a real practice round (seed 2)
on the game's simulation, with the players steered into the moment; the
menus run on the game's test-double service and store, so the Coins, Season
progress and friends are fixtures. **The prices are the App Store Connect
prices (USA)**, read from App Store Connect on 22 Nov 2026
(`tools/asc.py iap-list`) and applied to the store fixture
(`LIVE_PRICES` in `game/src/dev/store_capture.gd`); the purchase screens
show them exactly as the game formats a StoreKit price.

All player names and Game Center nicknames are fictional ("Comfy Frog" is
the player). No outfit based on a real person appears large in any shot;
only the Season Pass milestone chips (tiers 50 and 100) carry their tiny
portraits, as the game's Season Pass always does.

Not a device capture. On a device the status bar is hidden in the game,
so the frames match what the phone shows.

All images: PNG, 8-bit RGB, no alpha, sRGB (`tools/store_shot_check.py`,
output in [`check.txt`](check.txt)).

## How to re-render

```
tools/capture_store_screenshots.sh OUT_DIR            # both sets + iap
SPLASH_PICK=splash_air_2 ONLY=none tools/capture_store_screenshots.sh OUT_DIR   # re-assemble
python3 tools/store_shot_check.py OUT_DIR             # size / RGB / sRGB
```

Drivers (development only, `game/src/dev`, never exported):
`store_capture.gd/.tscn` (menus, the basketball shot and `--set=iap`),
`store_match_capture.gd` (gameplay, via `--capture=store_match`). Frames
used: splash `splash_air_2`, cart `cart_d`. If prices change in App Store
Connect, update `LIVE_PRICES` and re-render with `ONLY=iap`.
