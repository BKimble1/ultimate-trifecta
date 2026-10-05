# Pass 8 · Shop: scheduled rotating offers and three more Coin packs

Workstream SHOP of Pass 8 (brief §8 and §9). Everything here is
implemented and tested locally; nothing is live. The game service is
**not deployed** and **no App Store product exists** (App Store Connect's
read-only list shows all of them MISSING), so in the current build the
Shop shows its honest service-off state and the rotation runs only in tests
and in labelled dev-fixture captures. Owner dependencies are listed at the
end.

## What changed

| Area | Change |
|---|---|
| Catalogue (`game/config/catalogue.json`, version 2) | Six new outfits (`outfit:midnight_mechanic` 900, `outfit:moonwalk_cadet` 1,200, `outfit:pumpkin_pajamas` 800, `outfit:arcade_sprinter` 900, `outfit:cloud_nine` 1,000, `outfit:bedtime_bandit` 1,000 Coins; `added_in: 2`) and the four V6 Coin outfits marked `"rotation": true`: sold only through offers. New `offers` section: the rule, schedule revision 1 and 170 explicit offers (2026-10-05 → 2026-12-28). Coin packs `coins:250`, `coins:1000`, `coins:7500` (`com.idlery.ultimatetrifecta.coins.250/.1000/.7500`); the three existing IDs and quantities unchanged. |
| Schedule tool | `tools/make_offer_schedule.py` generates the schedule from the rule (deterministic; `--check`; refuses to change an offer that already started). |
| Service | `service/src/offers.js`: `GET /v1/shop/offers` (server time, current + next-72 h offers); `checkOffer()` at spend acceptance. `commerce.js` spend path: offer/item/price checked on the service clock, `offer_changed` charges nothing, `offer_sales` row in the same batch, replay returns the accepted result after expiry. `migrations/0003_offers.sql` (`offer_sales`, `CHECK` on the window). `/v1/config` features add `shop_offers`. Profile deletion keeps offer sales anonymised. |
| Client time/cache | `game/src/autoload/offers_service.gd` (autoload `Offers`): monotonic-offset server time, trust rules, 1 Hz boundary detection (only while something shows the Shop), cache for offline previews. `Cloud.public_get()`. |
| Client purchase | `Wallet.spend(item, offer)`: sends `offer_id`, refuses locally without trusted time or an active offer, maps `offer_changed`. |
| Shop UI (`game/src/ui/shop_screen.gd`) | Sections Featured · All skins · Accessories · Coins · Season 1. Featured: 4 rotating cards with "Leaves in …", "Shop refreshes in …", the return note, then **Always available** (Apple skins, Season 1 Premium, links to Coin packs and accessories). Detail: countdown + local departure. In-place card swap at expiry; label-only 1 Hz tick; confirmation closes if its offer leaves; "Not in current rotation" / "Connect to refresh Shop" states; "New" from catalogue data. Coin packs: six compact cards, StoreKit price or "Not available", tap = Apple's sheet, computed "Best value". |
| Locker (`creator_screen.gd`, one line) | The "N more in the Shop" link counts a rotating skin only while it's on sale. Owned skins are unaffected (ownership is the entitlement). |
| Purchases / StoreKit adapter | Numeric StoreKit `price` passed through; `Purchases.best_value_pack()` + `currency_mark()`. Delivery, finishing, recovery and restore untouched. |
| Product tooling | `tools/asc.py`: plan of eight products sorted by quantity, `iap-diff` (no credentials) and `iap-list --json`; API libraries imported only by API commands. `tools/make_storekit_config.py` output regenerated (`native/storekit/UltimateTrifecta.storekit`, eight products). |
| Dev fixture (never exported) | `fake_commerce_service.gd` serves offers on its own clock and applies the same acceptance check; `test_store_adapter.gd` can carry numeric test prices. |
| Evidence | `game/src/dev/capture_shop_p8.gd` (`--capture=shop_p8`), `tools/capture_pass8_shop.sh`, `tools/make_pass8_shop_media.py`. |
| Docs | `docs/ECONOMY.md` §2 / new §2.1 / products / §6 / §8; `docs/COMMERCE_SETUP.md`; `service/README.md` endpoint row. |

## Decisions

1. **Pool and Always available.** Rotating pool = the six new outfits +
   the four V6 Coin outfits (Lantern Scout, Campus Courier, Raincoat
   Explorer, Varsity Sprinter), per the integrator's instruction; their
   prices are unchanged. Always available: both direct Apple skins, all
   six Coin packs, Season 1 Premium and the cheap pre-V6 items (three
   outfits and the accessories). Nothing anyone owns or could have bought
   becomes an expiring entitlement: offers only gate *buying*.
2. **Schedule rule.** 4 slots, 48 h offers, every change at 00:00 UTC,
   slots 1-2 / 3-4 staggered by a day so exactly two change daily; each
   change takes the skin that left longest ago and is not on show or
   leaving. With 10 skins that is a 5-day cycle (2 days in, 3 away), no
   skin twice at once, no back-to-back return. Written for 12 weeks; the
   rule, the regeneration step and the end date are in ECONOMY.md §2.1.
   Recheck variety once the art lands (the brief's proposal for a small
   catalogue).
3. **Offer IDs** `r<rev>-<YYYYMMDD>-s<slot>`; a regenerated schedule keeps
   the ids of identical offers and the tool refuses to alter an offer that
   already started.
4. **Service time on the client.** Server time + (monotonic ticks since
   the sync); the device wall clock is also tracked and the *later*
   estimate wins, so a device clock change can only end offers sooner and
   iOS's paused-in-sleep monotonic clock can't extend an offer after the
   app sleeps. Trusted only after a sync in this run, within 6 h, inside
   the window the service described (72 h); a sync is re-requested at every
   change, on resume/focus, when the clocks disagree by > 90 s, and every
   15 min while the Shop is open. Untrusted → "Connect to refresh Shop".
5. **The one live 3D preview.** The Shop already had exactly one bounded
   live preview with rotate/idle/run (and emote) controls: the dorm stage
   (`App.stage`, wardrobe framing) beside the panel; every card is a
   static cached portrait (the existing Portraits path). I kept that rather
   than adding a `Preview3D` SubViewport: the stage keeps rendering behind
   the Shop either way, so a Preview3D would make two live 3D renders and
   double the menu's 3D cost. If the integrator wants the preview inside
   the panel instead, `Preview3D` can replace the stage framing; the
   rotation code doesn't depend on it.
6. **Coin pack cards** are a compact row (pile, full quantity, price pill),
   two per row on a landscape phone, and the tap is the purchase (Apple's
   own sheet is the confirmation, as before; the sheet is never opened
   without a tap). The detail sheet for a pack still exists for deep links.
7. **"Best value"** only when every compared pack has a StoreKit numeric
   price > 0 in the same currency (the currency text around the digits of
   `displayPrice` must match; StoreKit returns one storefront's currency)
   and one pack is cheaper per Coin than every other by more than 0.1 %.
   The simulated store's "(test price)" has no number: no label in the
   captures.
8. **Narrow cards.** The card's rotation line steps 17 → 14 px for its
   shape (every digit as its widest, so a ticking countdown never changes
   size) and, only if even 14 px can't fit, uses a short form ("Refresh
   needed", "Not in rotation"); the status line and the sheet always carry
   the full "Connect to refresh Shop" / "Not in current rotation".
9. **Local departure** uses the device's current UTC offset ("Leaves the
   Shop Wednesday, Oct 7, 12:00 AM (your time)"): presentation only. Godot
   exposes only the current offset, so a daylight-saving change between
   now and the departure would show it an hour off; the countdown and the
   purchase rule are unaffected.
10. **"New"** marks items whose `added_in` equals the catalogue version (a
    real catalogue fact). No sale prices, "rare", "last chance" or return
    dates.
11. `catalogue_version` bumped once, to 2. Protocol `VERSION` unchanged.

## Defect / requirement register

| Owner symptom / request | Reproduction | Cause | Implementation | Evidence |
|---|---|---|---|---|
| Skins should cycle in and out with a clear countdown | V7 Shop: Featured was a fixed list (Apple skins + Lantern Scout), no time anywhere | No offer model; "featured" was a static catalogue flag | Offer model + written schedule + service authority + client countdowns (above) | `service/test/offers.test.mjs`, `game/tests/test_shop_rotation.gd`, captures `shop_featured*` |
| An expired skin must not stay buyable | — (new) | — | Service checks offer on its clock; client refuses without an active trusted offer; stale sheet / All skins / deep link / confirmation all disabled | tests: boundaries, `test_an_expired_offer_cannot_be_bought_anywhere` |
| A few more Apple Coin-pack sizes | Catalogue had 500 / 1,500 / 3,500 | — | 250 / 1,000 / 7,500 added end to end | six-mapping tests (service + client), `shop_coins` captures |
| `tools/asc.py iap-plan` "needs no credentials" but needed `pyjwt`/`requests` installed | `python3 tools/asc.py iap-plan` on a machine without them → ImportError at import | Top-level imports | Imports moved into the API helpers | `iap-plan` / `iap-diff` run in the service test without them |
| Coin piles: a 7,500 pack drew the same pile as 3,500 at the same size | V6 coin art tiers stop at > 1,500 | Fixed tiers | Pile radius grows with the pack (80 → 100 % of the well) | `shop_coins` captures |
| Six coin cards would not fit a phone as V6 slabs | V6 coins grid: min 190-unit cells, 0.62 wells | Slab layout | Compact two-per-row cards (`pack_h` ≈ 1.2 touch targets) | test asserts compact height; `shop_coins` (se) shows all six at once |

## How it was verified

- **Service** (`cd service && npm test`): 54 tests pass (42 before; the
  existing spend/refund tests now use non-rotating items because the V6
  outfits moved into the rotation). New `test/offers.test.mjs`: the
  written schedule follows its rule (≥ 48 h, 00:00 UTC, 4 on sale every
  6 h of the window, 2 changes daily, no duplicate on show, no
  back-to-back return, even cycling); the file equals the tool's output;
  `GET /v1/shop/offers` at a fixed time and exactly at a boundary and past
  the end; boundaries (1 ms before start, at start, last millisecond, exact
  end); price / item / unknown offer refused without a charge; item-only
  spend accepted only while on offer; overlapping offers; lost reply and
  duplicate retries after expiry → replay; a spend racing a Shop refresh
  at the boundary charges once; an owned skin returning stays
  `already_owned`; all six Coin packs delivered once each with no offer on
  sale; the product-plan diff (none existing → 8 missing; five existing →
  only the three new); profile deletion anonymises offer sales; the
  schema `CHECK` refuses an out-of-window acceptance.
- **Game** (focused suites, headless): `test_shop_rotation` 12 tests
  (countdown and local-time wording; monotonic offset vs device clock
  rollback/forward, sleep across expiry, fresh offline run; Featured
  label-only ticks with no node created, in-place swap keeping the grid,
  the other cards, the scroll position and the live preview, hit region
  unscaled; Reduced Motion and controller focus at a refresh; no purchase
  from a stale sheet / confirmation / All skins / deep link / wallet /
  direct endpoint; offer changed before acceptance charges nothing; lost
  reply replays after expiry; owned skin stays in the Locker and returns
  Owned; service-off and stale states; six compact pack cards with
  StoreKit prices, "Not available", best value only for same-currency
  numbers; all six packs delivered once), `test_shop_ui`, `test_purchases`,
  `test_wallet`, `test_catalogue` (pack and rotation checks; see below),
  `test_menus_layout`, `test_focus`, `test_coins`, `test_outfits_v6`,
  `test_wardrobe`, `test_profile`, `test_screen_cycles`, `test_compile`:
  all pass except the expected one below.
- **Expected failure until the SKINS stream merges:**
  `test_catalogue::test_every_referenced_item_exists_in_cosmetics` lists
  the six new outfit IDs (no `Cosmetics` entries on this branch). No
  placeholder entries were added. Until then the Shop never shows those
  six (it only offers items with art).
- **Captures** (DEV FIXTURE, desktop llvmpipe, V7 screens approach with
  layout reports): `docs/media/pass8/shop/` (index in its README).

## Evidence index

`docs/media/pass8/shop/README.md` lists every image with what it shows and
its measured layout facts. Devices: `se` (667×375 pt), `p14` (844×390 pt),
`ipad` (1024×768 pt). Shots per device: `shop_featured`,
`shop_featured_always`, `shop_detail_offer`, `shop_confirm_offer`,
`shop_coins`, `shop_all_skins_out_of_rotation`,
`shop_detail_not_in_rotation`, `shop_stale_connect_to_refresh`,
`shop_service_off` (+ `shop_change_before/after` once every rotating skin
has art and the catalogue schedule drives the fixture).

## Open items

- (Done at integration) The six outfits' art merged; `test_catalogue` is
  green and the captures were re-run on the catalogue's own schedule,
  including the 00:00 UTC before/after shots (33 shots, 0 layout issues).
- The written schedule ends 2026-12-28; extend it before then (ECONOMY.md
  §2.1) and redeploy the service.
- Real-device checks not possible here: iOS monotonic clock behaviour
  across sleep (handled conservatively by design), StoreKit numeric
  `price` values for "Best value", and the real look of localized prices
  in the compact pills.
- Review screenshots for the three new packs need real prices (a
  TestFlight build); the repository captures show "(test price)".

## Owner / account-holder dependencies (exact)

1. Deploy the service (`service/scripts/deploy.sh`, migrations 0001-0003)
   and set `game/config/service.cfg`: until then no rotation is live.
2. Paid Applications agreement, then create the products:
   `python3 tools/asc.py iap-list` (expect 8 MISSING today), then
   `iap-create --yes` (or the workflow's iap=create): creates only missing
   products, never prices.
3. Choose price points for all eight products (three new packs: 250,
   1,000, 7,500), add review screenshots from a TestFlight build.
4. Sandbox test per COMMERCE_SETUP §4 (steps 8b, 8c added).

## Integrator: merge steps

1. Merge this branch; `game/project.godot` gains one autoload line
   (`Offers="*res://src/autoload/offers_service.gd"` after `Wallet`).
2. `game/config/catalogue.json`: the CHALLENGES stream edits
   `economy.challenges`; my sections are `products`, `items` and the new
   top-level `offers` (placed between `seasons` and `economy`). If both
   bump `catalogue_version`, keep 2. Then run
   `python3 tools/make_offer_schedule.py --check` and
   `node service/tools/sync_catalogue.mjs` (the service copy must match
   the merged JSON), then `cd service && npm test`.
3. `service/src/commerce.js`: I changed `spend()` (and added
   `spendReplay()`), the router (one `GET /v1/shop/offers` line),
   `deletionStmts` (one line) and the header comment; CHALLENGES adds a
   settlement hook in `settle()`: different functions. `service/src/app.js`:
   `features` list gains `shop_offers` (CHALLENGES may add its own).
4. `docs/ECONOMY.md`: I edited §2 (+ new §2.1), the products table, §6
   and the §8 table; CHALLENGES edits §3.
5. After the SKINS merge: `test_catalogue` should be fully green; re-run
   the Shop captures (step above) and replace `docs/media/pass8/shop/`
   with `tools/make_pass8_shop_media.py OUT`.
6. No new assets, so no ASSET_LICENSES lines.
