# Pass 8 Shop evidence (DEV FIXTURE desktop renders)

Made by `tools/capture_pass8_shop.sh OUT se p14 ipad` then `tools/make_pass8_shop_media.py OUT`.
The real game rendered by the Mobile renderer on llvmpipe under Xvfb at each device's pixel size with
its point scale and safe area (the V7 screens approach). **DEV FIXTURE**: the test-double service's clock
(2026-10-06 21:45:51 UTC at the start, then real time) and schedule, and the simulated store, whose prices
read "(test price)": every image says so in its bottom label. The schedule is the catalogue's own
(the six Pass 8 outfits and the four V6 Coin outfits in four 48 h slots changing at 00:00 UTC); two shots
show a 00:00 UTC change before and after. Layout and states only: not frame
rate, not a deployed service, not a real price or purchase. `<shot>_layout.json` holds the measured
control rects (canvas units) and any clipped, off-screen, outside-safe-area or trimmed control.

Devices: `se` iPhone SE class, 667x375 pt @2x, safe 0,0,0,0 (1334x750 px); `p14` iPhone 12-14 class, 844x390 pt @3x, safe 47,0,47,21 (2532x1170 px); `ipad` iPad 4:3, 1024x768 pt @2x, safe 0,24,0,20 (2048x1536 px).

| Device | Shot | What it shows | Measured layout |
|---|---|---|---|
| se | [shop_featured](se/shop_featured.jpg) | Featured: four rotating offers, each 'Leaves in …'; 'Shop refreshes in …' labelled separately; the return note | 0 issues; 54 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_featured_always](se/shop_featured_always.jpg) | Featured scrolled: the compact Always available block (Apple skins, Season 1 Premium, links) | 0 issues; 54 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_detail_offer](se/shop_detail_offer.jpg) | An offer's sheet: price, countdown and the local departure date/time; one action | 0 issues; 21 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_confirm_offer](se/shop_confirm_offer.jpg) | Coin confirmation: skin, price, balance and balance after | 0 issues; 33 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_coins](se/shop_coins.jpg) | The six Coin packs: full quantities, the store's price strings (simulated: '(test price)') | 0 issues; 37 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_all_skins_out_of_rotation](se/shop_all_skins_out_of_rotation.jpg) | All skins with a skin out of rotation ('Not in current rotation') | 0 issues; 80 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_detail_not_in_rotation](se/shop_detail_not_in_rotation.jpg) | That skin's sheet: preview on the runner, no purchase | 0 issues; 20 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_change_before](se/shop_change_before.jpg) | Catalogue schedule only: seconds before a 00:00 UTC change | 0 issues; 54 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_change_after](se/shop_change_after.jpg) | Catalogue schedule only: after it, two cards replaced in place | 0 issues; 52 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_stale_connect_to_refresh](se/shop_stale_connect_to_refresh.jpg) | No trusted time (fresh run, offline): 'Connect to refresh Shop', last offers previewable only | 0 issues; 53 controls measured; touch_min 84.5 units; 0 small targets |
| se | [shop_service_off](se/shop_service_off.jpg) | No service in the build (today's shipped state): no rotation, the existing unavailable state | 0 issues; 36 controls measured; touch_min 84.5 units; 0 small targets |
| p14 | [shop_featured](p14/shop_featured.jpg) | Featured: four rotating offers, each 'Leaves in …'; 'Shop refreshes in …' labelled separately; the return note | 0 issues; 54 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_featured_always](p14/shop_featured_always.jpg) | Featured scrolled: the compact Always available block (Apple skins, Season 1 Premium, links) | 0 issues; 54 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_detail_offer](p14/shop_detail_offer.jpg) | An offer's sheet: price, countdown and the local departure date/time; one action | 0 issues; 21 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_confirm_offer](p14/shop_confirm_offer.jpg) | Coin confirmation: skin, price, balance and balance after | 0 issues; 33 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_coins](p14/shop_coins.jpg) | The six Coin packs: full quantities, the store's price strings (simulated: '(test price)') | 0 issues; 37 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_all_skins_out_of_rotation](p14/shop_all_skins_out_of_rotation.jpg) | All skins with a skin out of rotation ('Not in current rotation') | 0 issues; 80 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_detail_not_in_rotation](p14/shop_detail_not_in_rotation.jpg) | That skin's sheet: preview on the runner, no purchase | 0 issues; 20 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_change_before](p14/shop_change_before.jpg) | Catalogue schedule only: seconds before a 00:00 UTC change | 0 issues; 52 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_change_after](p14/shop_change_after.jpg) | Catalogue schedule only: after it, two cards replaced in place | 0 issues; 52 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_stale_connect_to_refresh](p14/shop_stale_connect_to_refresh.jpg) | No trusted time (fresh run, offline): 'Connect to refresh Shop', last offers previewable only | 0 issues; 53 controls measured; touch_min 81.2 units; 0 small targets |
| p14 | [shop_service_off](p14/shop_service_off.jpg) | No service in the build (today's shipped state): no rotation, the existing unavailable state | 0 issues; 36 controls measured; touch_min 81.2 units; 0 small targets |
| ipad | [shop_featured](ipad/shop_featured.jpg) | Featured: four rotating offers, each 'Leaves in …'; 'Shop refreshes in …' labelled separately; the return note | 0 issues; 54 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_featured_always](ipad/shop_featured_always.jpg) | Featured scrolled: the compact Always available block (Apple skins, Season 1 Premium, links) | 0 issues; 54 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_detail_offer](ipad/shop_detail_offer.jpg) | An offer's sheet: price, countdown and the local departure date/time; one action | 0 issues; 21 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_confirm_offer](ipad/shop_confirm_offer.jpg) | Coin confirmation: skin, price, balance and balance after | 0 issues; 33 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_coins](ipad/shop_coins.jpg) | The six Coin packs: full quantities, the store's price strings (simulated: '(test price)') | 0 issues; 37 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_all_skins_out_of_rotation](ipad/shop_all_skins_out_of_rotation.jpg) | All skins with a skin out of rotation ('Not in current rotation') | 0 issues; 80 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_detail_not_in_rotation](ipad/shop_detail_not_in_rotation.jpg) | That skin's sheet: preview on the runner, no purchase | 0 issues; 20 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_change_before](ipad/shop_change_before.jpg) | Catalogue schedule only: seconds before a 00:00 UTC change | 0 issues; 52 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_change_after](ipad/shop_change_after.jpg) | Catalogue schedule only: after it, two cards replaced in place | 0 issues; 52 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_stale_connect_to_refresh](ipad/shop_stale_connect_to_refresh.jpg) | No trusted time (fresh run, offline): 'Connect to refresh Shop', last offers previewable only | 0 issues; 53 controls measured; touch_min 55.0 units; 0 small targets |
| ipad | [shop_service_off](ipad/shop_service_off.jpg) | No service in the build (today's shipped state): no rotation, the existing unavailable state | 0 issues; 36 controls measured; touch_min 55.0 units; 0 small targets |
