# V6 commerce media: navigation, Locker, Shop, Season Pass

**How these were made.** The real game, rendered by Godot 4.7.2's Mobile
renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb on a desktop Linux
machine, by `tools/capture_v6_commerce.sh` (`game/src/dev/commerce_capture.gd`).
Layout, states and art only: **not** frame rate, smoothness or a device.
**Test adapters in use:** the test-double service
(`game/src/dev/fake_commerce_service.gd`: wallet with 1,995 Coins, Season 1 at
tier 8, tier 1 Free claimed) and the simulated App Store
(`game/src/dev/test_store_adapter.gd`: its prices read "(test price)"). No real
service, App Store product or purchase is shown; none exists yet.

The profile is a V5 tester's save migrated to V6 (Fluffy Robe, Paper Crown,
Midnight-class colours owned on the device). **The art workstream's outfits
and Season items were not merged into this branch**, so the six new Shop
outfits are hidden ("2 more in the Shop" counts only what has art) and Season
reward items show a silhouette placeholder. Re-run the script after the art
merge.

Devices: **phone** 2532×1170 (Dynamic Island safe area, point scale 3), **se**
1334×750 (iPhone SE, point scale 2), **ipad** 2048×1536 (4:3, point scale 2).
Phone and iPad images are scaled to 1600 px wide (JPEG).

| File (in phone/, se/, ipad/) | Shows |
|---|---|
| `01_home_nav` | Home: the navigation rail (Play · Locker · Shop · Season Pass; the dot = rewards to claim), the Coins chip and Emote on the left, the runner unobstructed |
| `02_locker_outfit` | Locker: only owned outfits (free + pre-V6 unlocks), Equipped / Owned, no prices; the last card links to the Shop |
| `03_locker_hat_view_in_shop` | Locker hats: owned only, "View in Shop" for the rest |
| `04_locker_profile` | Locker Profile: name card (After Hours, earned at Season tier 1) previewed with the player's name; "in the Season Pass" link |
| `05_shop_featured` | Shop Featured: the Season 1 Premium offer with its exact contents (counted from the Season table) and price; Restore Purchases |
| `06_shop_outfits`, `07_shop_accessories` | Shop sections: cached portrait cards of your runner wearing each item, full names, exact Coin prices; owned items sort last and read Owned |
| `08_shop_coins_test_store` | Coin packs with the simulated store's price strings |
| `09_shop_season_offer` | Season 1 section |
| `10_shop_detail_preview`, `11_shop_detail_run` | Detail sheet: the dorm runner previews the item (the one interactive 3D preview; drag to turn, Idle / Run / Emote), type, exact price, what it includes (the hood note for hood outfits), balance, one purchase action, Back to Shop |
| `12_shop_coin_confirmation` | Coin purchase confirmation: item, price, your Coins, left after; Cancel / Buy |
| `13_shop_detail_coin_pack_test_store` | A Coin pack sheet: consumable, delivered once to the signed-in account; the button carries the store's price string |
| `14_shop_detail_season_premium` | Season 1 Premium sheet: permanent for the season, late unlock, no skips, not a subscription, 1,500 Coins |
| `15_season_pass` | Season Pass: tier 8/30, XP to the next tier and the next reward, Claim all (3), the horizontal track (Free above, Premium below: claimed ✓, claimable +, Premium-locked padlock), the detail panel |
| `16_season_pass_premium_locked` | A reached-but-locked Premium reward: "Get Premium in the Shop" |
| `17_season_pass_tier30` | The end of the track (tier 30) |
| `18_shop_service_off`, `19_season_service_off` | The shipped state today (no service in the build): the reason shown, every purchase unavailable, the pre-V6 balance (345) shown as this device's |

Before (V5) for comparison: the wardrobe that showed prices and bought on Apply ("Buy & apply")
(`../../v5/ui/wardrobe_phone.jpg`) and the home without
navigation (`../../v5/ui/home_phone.jpg`).
