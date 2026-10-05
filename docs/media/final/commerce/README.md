# FINAL_RELEASE_SWEEP · Commerce evidence (Shop)

**What these are**: desktop renders of the real game (Linux, llvmpipe,
Mobile renderer) at each device's resolution with its point scale and safe
area emulated, made by `tools/capture_final_shop.sh` (driver
`game/src/dev/capture_shop_final.gd`, excluded from iOS exports). Every
picture carries a visible **DEV FIXTURE** label: the test-double service
(fixed fixture clock, the catalogue's offer schedule, a wallet with 2,650
Coins and Fluffy Robe and Moonlight Runner owned) and the simulated store.

**What they are not**: not a deployed service, not a real App Store price or
purchase ("(test price)" is the simulated store's placeholder; a real build
shows StoreKit's localized price), not a device, not frame-rate evidence.

| Folder | Device shape |
|---|---|
| `se/` | iPhone SE: 1334×750 @2x, no insets |
| `p14/` | iPhone 14: 2532×1170 @3x, safe area 47/0/47/21 pt |
| `ipad/` | iPad: 2048×1536 @2x, safe area 0/24/0/20 pt |

JPEG q85, 1280 px wide (SE: its own 1334 px scaled to 1280).

| Shot | Shows |
|---|---|
| `shop_featured` | four rotating offers with "Leaves in" and "Shop refreshes in" |
| `shop_featured_always` | Always available: both App Store outfits (Moonlight Runner owned) and Season 1 Premium |
| `shop_all_skins_owned_states` | All skins: "15 skins · 2 owned", Hide owned off, "App Store" line, rotating lines |
| `shop_all_skins_hide_owned` | the same with Hide owned on (owned skins gone) |
| `shop_accessories_all_owned_hidden` | every accessory owned and hidden: the explained empty state |
| `shop_detail_app_store_outfit` | Starry Sleeper's sheet: "Outfit · App Store", price, Restore, Buy |
| `shop_coins_simulated_prices` | the six Coin packs with the simulated store's "(test price)" |
| `shop_coins_price_unavailable` | the six packs when the store returns no products: "Not available" |
| `shop_season_tab` | Season 1: Premium and "Open the Season Pass" |
| `shop_featured_after_written_schedule` | service clock 2027-06-01: four offers continued from the rule's cycle |

Notes: [docs/final/commerce.md](../../../final/commerce.md).
