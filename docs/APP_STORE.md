# App Store submission package, version 2.0 (prepared, not submitted)

Everything here describes what the 2.0 release candidate actually does, and
is ready to paste into App Store Connect. **owner** marks fields that only
the account holder can fill. Nothing here invents a URL, contact,
price or promise. App Store readiness, item by item, is tracked in
[APP_STORE_READINESS.md](APP_STORE_READINESS.md); commerce and service setup
in [COMMERCE_SETUP.md](COMMERCE_SETUP.md) and `service/README.md`.

Two things decide which text applies:
- **The game service must be deployed** (both deployments, sandbox and
  production, `service/README.md`) and its endpoints filled into
  `game/config/service.cfg` before the final build. Coins, purchases, the
  Season Pass rewards, challenges, rotating offers, verified names, typed
  chat, reports and Friends status all need it. The copy below assumes it
  is live. Without it, the game is a preview: see "If the service is not
  live" at the end, and do not submit that build as the launch build.
- **Apple's products must exist** (the eight in-app purchases below) and be
  submitted with this version.

## Identity

| Field | Value |
|---|---|
| Name (≤30) | Ultimate Trifecta |
| Subtitle (≤30) | Splash three. Race home. |
| Bundle ID | `com.idlery.ultimatetrifecta` |
| Apple ID (app) | 6818346960 (the existing app record) |
| SKU | ULTIMATETRIFECTA1 (already set) |
| Version | **2.0**. The build number comes from App Store Connect (highest + 1). Builds 1.0–1.9 were internal TestFlight betas. |
| Primary category | Games › Action. Secondary: Games › Family (optional; the game has no kids' category features). |
| Platforms | iPhone and iPad, iOS 17 or later, landscape. Requires A12 or newer (`iphone-ipad-minimum-performance-a12`). |
| Game Center | Used for sign-in, friends, invitations and party matchmaking. |
| Support URL | **owner**: a real, monitored page. Also put it in `game/config/links.cfg` (`support_url`) so Settings links to it. |
| Privacy Policy URL | **owner**: required. It must cover the inventory below. Also put it in `game/config/links.cfg` (`privacy_url`). |
| Marketing URL | optional; **owner** |
| Copyright | **owner**, for example "2026 <legal name>" |

## Promotional text (≤170)

> A 3 a.m. campus chase with friends: splash into three waters and race home before the Night Watch catches you. New: Friends with live status and invites.

(153 characters.)

## Description (≤4000)

> Ultimate Trifecta is a playful after-hours campus chase for up to eight players.
>
> Runners in pajamas and costumes slip out of the dorm, splash into tonight's three marked waters (fountains, ponds, a lagoon) and race back inside before the clock runs out. The Night Watch hunts them on foot and in golf carts. Get enough runners home to win the round, or, as the Night Watch, stop them.
>
> PLAY YOUR WAY
> • Parties of up to eight, with one, two or three Night Watch and series of one, three or five rounds. Empty spots are filled by bots, always labelled BOT.
> • Three dorms, six waters and a campus full of shortcuts, carts and doorways.
> • Practice anytime: full rounds with bots, offline, plus guided tutorials for runners and the Night Watch.
>
> PLAY WITH FRIENDS
> • Friends shows which of your Game Center friends are online in Ultimate Trifecta, in a party or in a round, and lets you invite them straight into your party.
> • Or share a six-character party code, or use Game Center's invite sheet.
> • Parties are private: there's no matchmaking with strangers and no voice chat.
>
> MAKE IT YOURS
> • Create your runner: outfits, colours, faces, hair, hats, shoes and a ready move.
> • Season 1 · After Hours: a 100-tier Season Pass earned by playing online rounds, with a Premium track and two signature outfits at tiers 50 and 100.
> • Daily and weekly challenges that add Season XP.
> • A Shop with rotating outfits, permanent favourites and Coin packs.
>
> BUILT FOR PHONES AND TABLETS
> • Touch controls for two thumbs with a fixed or floating stick, adjustable button size and left-handed layouts.
> • MFi, Xbox and PlayStation controllers in menus and gameplay.
> • Reduced Motion support, safe-area aware layouts on iPhone and iPad.
>
> FRIENDLY BY DESIGN
> • Quick Chat phrases and emotes in every party; typed chat only in private parties, checked by the game's moderation service.
> • Names are checked. Mute, report or block anyone from their player card.
> • Delete your game profile at any time in Settings.
>
> No ads. No tracking. Optional in-app purchases (Coins, two permanent outfits) are cosmetic only and never change how anyone plays: everyone runs at the same speed. Moonbrook College is fictional.

## Keywords (≤100)

`party,chase,tag,runners,campus,splash,friends,multiplayer,pajamas,casual,bots,season pass`

(89 characters.)

## What's New

Not shown for an app's first App Store version. For later versions, write
it from that version's changes.

## In-app purchases (submit all eight with version 2.0)

Apple requires an app's first in-app purchase of each type to be submitted
with a new app version. This app has both types. In App Store Connect ›
Monetization › In-App Purchases (`iap=list` in the workflow reads them
without changing anything; `iap=create` creates missing records without
prices, screenshots or submission):

| Reference name | Type | Product ID | Display name (≤30) | Description (≤45) | Delivers |
|---|---|---|---|---|---|
| Coins 250 | Consumable | `com.idlery.ultimatetrifecta.coins.250` | 250 Coins | 250 Coins for the Shop. Cosmetic only. | 250 Coins |
| Coins 500 | Consumable | `com.idlery.ultimatetrifecta.coins.500` | 500 Coins | 500 Coins for the Shop. Cosmetic only. | 500 Coins |
| Coins 1000 | Consumable | `com.idlery.ultimatetrifecta.coins.1000` | 1,000 Coins | 1,000 Coins for the Shop. Cosmetic only. | 1,000 Coins |
| Coins 1500 | Consumable | `com.idlery.ultimatetrifecta.coins.1500` | 1,500 Coins | 1,500 Coins for the Shop. Cosmetic only. | 1,500 Coins |
| Coins 3500 | Consumable | `com.idlery.ultimatetrifecta.coins.3500` | 3,500 Coins | 3,500 Coins for the Shop. Cosmetic only. | 3,500 Coins |
| Coins 7500 | Consumable | `com.idlery.ultimatetrifecta.coins.7500` | 7,500 Coins | 7,500 Coins for the Shop. Cosmetic only. | 7,500 Coins |
| Skin Moonlight Runner | Non-Consumable | `com.idlery.ultimatetrifecta.skin.moonlight_runner` | Moonlight Runner | A permanent outfit. Cosmetic only. | the Moonlight Runner outfit, restorable |
| Skin Starry Sleeper | Non-Consumable | `com.idlery.ultimatetrifecta.skin.starry_sleeper` | Starry Sleeper | A permanent outfit. Cosmetic only. | the Starry Sleeper outfit, restorable |

- **Prices and availability: owner.** The game shows only StoreKit's
  localized price; nothing in the app is hard-coded.
- **Review screenshot** for each product: a capture of the real Shop
  purchase screen for that product, from the final build on a device
  (`docs/media/final/store/iap/` holds desktop-render references of the
  same screens; replace them with device captures if Apple asks).
- **Review note** for each product: "Ultimate Trifecta is a cosmetic-only
  party game. This consumable adds N Coins to the player's wallet" (or
  "This non-consumable unlocks the <name> outfit permanently
  (restorable)"). "Open Shop (top bar) to see it; it is delivered by the
  game's service after StoreKit 2 verification. No gameplay advantage."
- **Not Apple products:** Season 1 Premium (1,500 Coins), Record Breaker
  (Season Pass Premium tier 50), Dr. Doom (Premium tier 100) and every
  other outfit or accessory bought with Coins. They are bought with the
  in-game currency or earned, never sold directly.

## App Review notes (copy-ready; fill the **owner** fields)

> **Sign-in.** The game uses Game Center. Please be signed in to Game Center in Settings on the review device. There is no separate account or password. A first launch asks for a player name and lets you create a runner.
>
> **Play without other people.** Home › Practice: full rounds with bots, offline, as Runner, Night Watch or Random, plus a guided tutorial for each role.
>
> **Online parties.** Home › Play with Friends › Create Party gives a six-character code; a second device signed in to a different Game Center account joins with Join and that code. The host can also tap Invite to use Game Center's invite sheet. Parties are private (no matchmaking with strangers). Empty spots are filled by bots labelled BOT. Party settings (host only): 1, 2 or 3 Night Watch; 1, 3 or 5 rounds.
>
> **Friends.** Friends is on Home (top right) and on the Friends button in a party. It lists the reviewer's Game Center friends (it asks for friends access the first time) and shows who is playing Ultimate Trifecta right now: Online, In a party or In a round. Status appears only for friends who also have the game, have allowed friends access and list you as a Game Center friend too; otherwise it says it's unavailable rather than guessing. Invite sends an invitation to your current party (from Home it creates one first); the friend gets a small Accept/Decline card and joins the same party, with the same checks as a typed code. Friends never appears during a round, and "Show when I'm playing" at the end of the list turns your own status off. Party codes and Apple's Game Center invite sheet work without Friends. **owner:** if possible, add a link to a short screen recording of two devices doing this, because the reviewer's account won't have mutual friends.
>
> **Purchases (cosmetic only).** Shop (top bar) › Coins has six Coin packs (250 to 7,500, consumable). Shop › Featured › Always available (also Shop › All skins, marked "App Store") has the two permanent outfits Moonlight Runner and Starry Sleeper (non-consumable); Restore Purchases is at the bottom of Featured, All skins and Coins and on each outfit's page. Other outfits, accessories and Season 1 Premium (Shop › Season 1) are bought with Coins after a confirmation showing the price and the balance left. Every purchase is verified with StoreKit 2 and Apple's signed transaction on our server before anything is delivered. Purchases made during review use Apple's sandbox: the game recognises this by itself (the first purchase may take a few seconds longer) and keeps review purchases in a separate sandbox economy, never mixed with customers'. Online parties match players of the same economy: to test a party on two devices, test it before making purchases, or make a purchase on both devices first. Nothing bought changes speed, reach or score.
>
> **Season Pass.** Season Pass (top bar): 100 tiers earned by playing online rounds and daily/weekly challenges. Premium (1,500 Coins) adds a second reward track; earned rewards are claimed with Claim or Claim all. Record Breaker (tier 50) and Dr. Doom (tier 100) are Premium rewards and can be previewed from the tier shortcuts above the track.
>
> **Safety.** Quick Chat phrases and emotes in every party; typed chat only in private parties and only through our moderation service (filtered, rate-limited, signed). Tap a player or a message to Mute, Report (reason, sent to our moderation queue, with a receipt) or Block. A host can remove a player. Names are checked.
>
> **Delete Game Profile:** Settings › Profile › Delete Game Profile. It confirms, deletes the online profile and its data from our service, then erases the device data.
>
> **Controllers:** MFi, Xbox and PlayStation controllers work in menus and gameplay.
>
> **Contact:** **owner** (name, phone, email).

## Age rating questionnaire (current App Store Connect questions)

Suggested answers for the owner to confirm. Apple calculates the rating; it
isn't guaranteed.

| Area | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | The Night Watch "tags" a runner (a touch and a whistle); a tagged runner waits 6 s and runs again. No harm is shown. |
| Realistic violence; violent themes; horror | None | |
| Profanity or crude humour | None | Game content has none. Names and typed chat are user content, filtered and reportable (below). |
| Sexual content or nudity; mature or suggestive themes | None | Pajamas, swimwear-style and costume outfits are cartoon clothing. Record Breaker's look (shorts, sandals, bare torso) is athletic beachwear. |
| Alcohol, tobacco or drug use | None | |
| Medical or treatment information; wellness topics | None | |
| Simulated gambling; real gambling; contests | None | No random paid rewards (no loot boxes); everything is shown with its price or tier. |
| Unrestricted web access | No | The only links are the owner's privacy and support pages, opened in Safari. |
| User-generated content | Yes | Player names, and typed chat in private parties, filtered by the service, with mute, block, report and moderation. |
| Messaging and chat | Yes | Private-party chat only: Quick Chat phrases and moderated typed messages. No messages to strangers, no voice. |
| Social media (feeds or discovery of user content) | No | No feed, no public profiles, no discovery. Friends shows Game Center friends' in-game status only. |
| Advertising | No | |
| In-app purchases | Yes | Consumable Coins and two non-consumable outfits, cosmetic only. |
| Parental controls / age assurance in the app | No in-app controls | The game respects Screen Time / Game Center restrictions on multiplayer and friends. |

## App Privacy ("nutrition label") for the release with the service

These match the privacy manifest that `tools/export_ios.sh` writes when a
service endpoint is configured. Tracking: **No** for every type. Purpose:
**App Functionality** only. All are **linked to the player** (their game
profile).

| Apple data type | What the game sends and keeps |
|---|---|
| Identifiers › User ID | The Game Center team player ID (verified by Apple's identity signature), mapped to an opaque profile ID. |
| Contact Info › Name | The chosen player name (and its #1234 tag). |
| User Content › Gameplay Content | The runner's look (item IDs), round results, Season progress and challenge progress. |
| User Content › Other User Content | Reports you file (reason, optional text, context) and, for a reported chat message, that message. |
| Purchases › Purchase History | App Store transaction IDs, products and what they delivered; the Coins ledger. Never payment details. |
| Contacts | The Game Center friends list, uploaded as keyed hashes (not readable IDs) so the game can show which mutual friends are online and deliver invites. |
| Usage Data › Product Interaction | Short-lived in-game status (online, in a party, in a round) shown to mutual friends; expires within a minute when you stop playing. |

Typed chat is checked and signed in real time and **not stored** unless it
is reported, so ordinary chat isn't "collected" by Apple's definition. If
the owner prefers the conservative answer, also tick User Content › Emails
or Text Messages and add `emails_or_text_messages` to the types in
`tools/export_ios.sh`.

Not collected: email, phone, address, location, photos, audio, browsing or
search history, advertising data, device IDs, crash or performance data.
On the device only: `user://service_route.cfg` remembers which deployment
(sandbox or production) this install uses; the game reads only the *name*
of the App Store receipt file (TestFlight's is "sandboxReceipt"), never its
contents. The appAccountToken sent to Apple with a purchase is derived by the
service from the player's verified Game Center ID (purchase history, above).
Payment is handled by Apple. The optional Settings › Diagnostics summary
stays on the device unless the player shares it themselves.

### Inventory the privacy policy must cover (owner)

Stored in the service's databases (Cloudflare D1, under the owner's
account; one database for the App Store and a separate one for TestFlight
and App Review's sandbox):

- **Profile:** opaque profile ID, display name and tag, name history, the
  runner's look, status (active or suspended), timestamps.
- **Identity link:** Game Center team player ID ↔ profile, bundle ID.
- **Wallet and purchases:** Coins balance and ledger, entitlements, Season
  progress and claims, challenge progress, settled rounds, App Store
  transaction IDs and products (never payment details).
- **Friends:** keyed hashes (HMAC) of up to 500 of the player's Game
  Center friends' team player IDs, replaced on every upload and deleted
  after 30 days without one or when friends access is revoked;
  **presence:** one row per running game (status, the verified party,
  game version), gone 60 seconds after the last 20-second heartbeat, no
  history; **invitations:** inviter, invitee, party and outcome, pending for
  5 minutes, purged 24 hours after they resolve. Status is shown only to
  mutual friends, never during a round, and can be turned off ("Show when
  I'm playing"). Details: `service/README.md` and `docs/final/friends.md`.
- **Blocks:** pairs of profile IDs.
- **Reports:** reporter, target and their name at the time, reason,
  optional details, context; for a reported chat message, the message.
- **Typed chat:** not stored; only short-lived rate-limit counters.
- **Party rooms:** code, host and member profile IDs, state and
  timestamps; closed rooms purged after 24 h.
- **Moderation audit log:** owner actions; profile deletions are logged
  without the profile ID.
- **Operational:** short-lived rate-limit counters and revoked sessions.
  The hosting provider (Cloudflare) may keep its own request logs under its
  terms.

**What Delete Game Profile removes:** the profile, identity link, name
history, blocks, friends hashes, presence and invitations, wallet,
entitlements, progress and the quoted text of reported messages the player
sent. Records needed to honour App Store purchases and refunds
(transaction ID, product, environment) and the Coins ledger are kept
without the profile link, so a permanent outfit can be restored to a new
profile on the same Apple Account and a spent consumable is never granted
twice. Reports the player
filed stay without the reporter link; open reports against them are closed.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in the build: the game uses only
the encryption built into iOS (HTTPS to the game service, Game Center), which
is exempt. Answer App Store Connect's question accordingly; no documentation
upload is needed.

## Content rights (owner confirms)

- **Likenesses.** Record Breaker and Dr. Doom are stylised likenesses of
  real people made from the owner's photos. **owner:** written permission
  from both people for commercial use in the game and its marketing.
- **"Dr. Doom" name.** "Doctor Doom" is a well-known comic-book character
  and trademark of another company. The skin is an original character and
  its art doesn't reference that character, but the name alone could be
  read as a reference (App Review Guideline 5.2.1, intellectual property).
  **owner decision:** keep the approved name, or rename the skin's display
  name (only the label changes; its ID `outfit:dr_doom` and progress stay).
- **Music.** "Night Campus Loop" (lobby) and "Soft Bounce Loop" (rounds)
  are the owner's tracks made with mureka.ai. **owner:** confirm that
  service's terms allow commercial use in an app.
- **Everything else** is original to the project or under the licences in
  `ASSET_LICENSES.md` (Godot MIT, GodotApplePlugins MIT, Manrope SIL OFL,
  DejaVu Sans, Blender-built original characters, synthesized sound
  effects).
- Nothing in the app or its metadata suggests endorsement by Apple or by
  any real person.

## Screenshots

App Store Connect needs, for an app that runs on iPhone and iPad (Apple's
current specification):
- **iPhone 6.9" display:** 2868 × 1320 (landscape) — or the 6.5" size
  2778 × 1284 if 6.9" isn't provided. Up to 10.
- **iPad 13" display:** 2752 × 2064 (landscape). Up to 10.

Two proposed sets are in `docs/media/final/store/`: `iphone_6.9/` (8 shots,
2868 × 1320) and `ipad_13/` (8 shots, 2752 × 2064), PNG, 8-bit RGB, no
alpha, sRGB, all passing `tools/store_shot_check.py` (see the README for
what each shows and how it was made). They are renders of the release
candidate's code and art (`v10-49a45748ffed`) with fictional player names
and no debug text, not device captures. **Owner:** approve the set, or
replace any with on-device screenshots; re-render with
`tools/capture_store_screenshots.sh` if the art changes.

- **Likeness:** `03_party_of_eight`, `04_season_pass_record_breaker`,
  `06_friends_invite` and `08_final_standings` (a small portrait) show
  Record Breaker or Dr. Doom. Use them only with the written permission
  under "Content rights"; otherwise upload `01`, `02`, `05` and `07`, which
  don't show the two skins.
- **In-app purchase review screenshots** are separate (one per product) and
  must be taken on a device once the products exist: `docs/media/final/store/iap/`
  holds labelled references for what to capture, not uploadable images.

## If the service is not live

Do not submit a build without the service as the launch build: Shop
purchases, Season rewards and Friends status would all show as
unavailable, which App Review may reject as incomplete. Such a build
collects nothing (privacy: Data Not Collected), keeps names on the device
and shows curated names in parties.
