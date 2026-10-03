# App Store submission package (prepared, not submitted)

This pass does not include a public App Store submission. The material
below is ready for the owner to review and paste into App Store Connect.
Every statement describes what the build actually does.

Items only the owner can supply are marked **owner**. Nothing here invents
a contact address, URL or policy promise.

## Identity

| Field | Value |
|---|---|
| Name | Ultimate Trifecta |
| Subtitle (≤30) | Splash three. Race home. |
| Bundle ID | `com.idlery.ultimatetrifecta` |
| Version | 1.2 (V3). The build number comes from App Store Connect (highest + 1). The first upload, 1.2 (1), is in internal TestFlight testing only. |
| Primary category | Games › Action. Secondary: Games › Family. |
| Platforms | iPhone and iPad, iOS 17+, landscape. A12 or newer. |
| Support URL | **owner**: a real, monitored page. Required by App Store Connect. |
| Privacy Policy URL | **owner**: required. It must cover the inventory below. |
| Marketing URL | optional; **owner** |
| Copyright | **owner** (for example "2026 <legal name>") |

## Promotional text (≤170)

> New in 1.2: create your own runner, throw a party with a six-letter code, and splash in style with all-new animation.

## Description

> Ultimate Trifecta is a playful 3 a.m. campus chase.
>
> Runners in pajamas and mascot suits must splash into tonight's three marked waters — fountains, ponds, a lagoon — and race back to the dorm. Two Night Watch players hunt them on foot and in golf carts. Get four runners home before the four-minute clock runs out, or, as the Night Watch, stop them.
>
> • Create your runner: outfits, colours, faces, hair, hats, shoes and a ready move.
> • Play with friends: start a party and share a six-letter code, or invite Game Center friends. Empty spots are filled by bots, clearly marked BOT.
> • Practice anytime: full rounds with bots, offline, plus a short tutorial.
> • Touch controls built for two thumbs, with fixed or floating stick, button size and left-handed layouts; game controllers supported.
> • Friendly by design: Quick Chat phrases and emotes in every party; typed chat only in private parties and only through the game's moderation service; names are checked; mute, report and block from any player's card or message.
>
> A fictional campus, no ads, no tracking. Optional cosmetic in-app purchases (Coins and outfits) never change how anyone plays.

Before using the name-checking, typed-chat and report lines, confirm the
service is deployed (see "Service status at review"). Without it the honest
line is: "Quick Chat phrases and emotes; names in parties are the game's
own; mute and block from any player's card."

## Keywords (≤100)

`party,chase,tag,runners,campus,splash,friends,multiplayer,pajamas,casual,game center,bots`

## What's New (1.2)

> Create Your Runner, a brand-new character look and animation, parties with six-letter codes and a share button, player cards with report and block, better controller support, and lots of polish.

## App Review notes

> **Playing without an account.** From Home, tap Practice → Play as Runner or Night Watch. Full rounds with bots, offline, no sign-in. A tutorial is on the Practice screen.
>
> **Online parties** use Game Center. Sign in under Settings › Game Center on the device. Play with Friends → Create Party gives a six-letter code, and a second device joins with that code (Join), or the host taps Invite to use Game Center's invite sheet. Codes avoid look-alike characters, and typing is checked strictly. Parties are private: there is no public matchmaking with strangers. Empty slots are filled by bots labelled BOT.
>
> **Profiles and names.** On first launch the player creates a runner and picks a name. Names are 3–16 letters, numbers, single spaces or underscores. When the game service is enabled, names are checked server-side: offensive terms, impersonation, contact details, with leet and look-alike handling. Approved names get a #1234 tag to tell duplicates apart. Sign-in to the service is verified with Game Center's identity signature; a player ID alone is never accepted.
>
> **Communication and safety (V6).** Parties are private (a code or a Game Center invite); there is no public or global chat and no voice. Every party has **Quick Chat**: preset phrases sent as IDs, offered by context (the party room; your own team during a round; finished players only to other spectators, so they can't tip off active players; everyone on the results). **Typed chat** exists only in parties set up through the game's service and only while it is reachable: each message is checked on the device and approved and signed by the service (abuse lists with evasions, links, contact details, markup, spam, length, rate limits); the host and every receiver verify the signature before anything is shown. Tap a player (or a message) to **Mute** (chat and emotes), **Report** the player or the message (a reason; a receipt only once the service confirms it) or **Block** them (their chat, emotes and name are hidden; you aren't put in parties together); a host can **Remove** a player. Reports go to the owner's moderation queue (dismiss, forced rename, suspension; audited). Details: `docs/MODERATION.md`.
>
> **Shop and Season Pass (V6, cosmetic only).** Navigation: Play · Locker · Shop · Season Pass. Shop › Coins sells 500 / 1,500 / 3,500 Coins (consumable); Moonlight Runner and Starry Sleeper are permanent outfits bought directly (non-consumable; Shop › Restore Purchases). Other outfits, accessories and Season 1 Premium (1,500 Coins) are bought with Coins after a confirmation showing the balance left. Purchases are delivered by the game's service after StoreKit 2 verification. The Season Pass track is earned by playing online rounds; Premium adds a second reward track and never skips tiers. Nothing bought changes speed, reach or score. Purchases need the game service; a build without it shows them as unavailable.
>
> **Delete Game Profile** is in Settings › Profile. It confirms with Game Center, deletes the online profile from the service, then erases everything on the device.
>
> **Controllers.** MFi, Xbox and PlayStation controllers work in menus and gameplay, with matching button prompts.
>
> **Contact for review:** **owner** (name, phone, email).

### Service status at review

The game service (`service/`) is not deployed yet; see
`service/README.md`. Until it is:

- The shipped build has `game/config/service.cfg` empty.
- Names are kept on the device. Game Center provides the online identity.
  In parties every player is shown under one of the game's curated names
  ("Sleepy Otter 42"), so no unreviewed custom name is broadcast.
- Quick Chat (preset phrases) works; typed chat is unavailable and says so.
- Report sends nothing; it says reports are unavailable and that nothing was
  sent, and offers Mute and Block instead.
- Delete Game Profile erases the device data.

If the owner deploys the service before submission, fill in
`service.cfg`, rebuild, and use the "with service" privacy answers below.
The export script then also declares the collected data in the privacy
manifest.

## Age rating inputs

These are suggested answers for the owner to confirm in App Store
Connect's questionnaire.

| Question area | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | The Night Watch "tags" a runner with a whistle; no harm is depicted. |
| Realistic violence, horror, mature themes | None | |
| Profanity or crude humour | None | Game content has none. Player names and typed chat are user content, filtered and reportable (below). |
| Sexual content, nudity | None | Pajamas and swimwear are cartoon outfits. |
| Alcohol, tobacco, drugs; gambling; contests | None | |
| Medical or treatment information | None | |
| User-generated content | Yes: player names, and typed chat in private parties when the service is on; filtered, with mute, block, report and moderation | Without the service: none is shared (curated names, preset phrases). |
| Messaging and chat | Yes: private-party chat. Quick Chat preset phrases always; typed messages only through the moderation service. No public chat, no voice, no messages to strangers. | |
| Unrestricted web access | No | |
| Advertising | No | |
| In-app purchases | Yes (V6): Coin packs (consumable) and two outfits (non-consumable), cosmetic only; Season 1 Premium is bought with Coins. No loot boxes, no random rewards, no gameplay advantage. | |
| Parental controls | Respects Game Center multiplayer restrictions (Screen Time). | |

Expected result: a low age band, subject to Apple's evaluation of the
user-generated content and messaging answers. App Review Guideline 1.2
(user-generated content) asks for filtering, reporting with timely
responses, blocking and published contact information: the first three are
implemented (`docs/MODERATION.md`); the **owner** must supply the support
contact (`SUPPORT_EMAIL` / `SUPPORT_URL` in the service config, and the
Support URL above) and commit to reviewing the report queue.

## App Privacy ("nutrition label")

**Build without the service** (the current source):

- Data collected by the developer: **none**.
- Game Center (Apple) handles the player's identity and matchmaking.
- Settings, progress and the runner's look stay on the device.

**Build with the service deployed**:

| Data type | Collected | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| User ID: Game Center team player ID, verified, mapped to an opaque profile ID | Yes | Yes | No | App Functionality |
| Name: chosen display name | Yes | Yes | No | App Functionality |
| Gameplay Content: runner appearance (item IDs) | Yes | Yes | No | App Functionality |
| Other User Content: reports you file (reason, optional text, room code, build) and, for a reported chat message, that message (up to 200 characters) | Yes | Yes | No | App Functionality |
| Purchases: Purchase History (V6): App Store transaction IDs, products, what they delivered, the Coins ledger, Season progress and rewarded rounds; never payment details | Yes | Yes | No | App Functionality |

Typed chat (V6): each typed message is sent to the service to be checked
and signed, and is **not stored** unless someone reports it, so ordinary
chat is processed in real time rather than collected. A reported message is
kept with the report (above). Conservative option: if the owner prefers to
declare chat itself, also tick **User Content › Emails or Text Messages**
(linked, not tracking, App Functionality), and add
`emails_or_text_messages` to the data types that `tools/export_ios.sh`
declares when the service is configured.

Not collected: contact info, location, contacts, photos, audio, browsing,
usage analytics, diagnostics, advertising data or device IDs. Payment is
handled by Apple; the developer never sees card or billing details.

### Inventory the privacy policy must cover (owner)

Each item is stored in the service's database (Cloudflare D1, under the
owner's account):

- **Profile.** Opaque profile ID, display name and discriminator, name
  history, runner appearance, status (active or suspended), and timestamps.
- **Identity link.** Game Center team player ID ↔ profile, and bundle ID.
- **Blocks.** Pairs of profile IDs.
- **Reports.** Reporter profile ID, target profile ID and name at report
  time, reason, optional details (≤500 characters), context (room code,
  build; for a message report also the channel and send time), status and
  resolution; for a reported chat message, the message (up to 200
  characters) and its token ID.
- **Typed chat.** Not stored. The service checks and signs each message
  and keeps only short-lived rate-limit counters.
- **Party rooms.** Code, host and member profile IDs, state and
  timestamps. Closed and expired rooms are purged after 24 h.
- **Moderation audit log.** Owner actions; profile deletions are logged
  without the profile ID.
- **Operational.** Short-lived rate-limit counters (purged after 24 h) and
  revoked session IDs (purged when they expire).

What deletion removes: Delete Game Profile removes the profile, its
identity link, name history and blocks, and the quoted text of any reported
messages the player sent. Reports the player filed stay, with the reporter
link removed. Open reports against the player are closed.

## Screenshots

App Store Connect needs screenshots at the current required sizes,
captured from the app, for example 6.9" iPhone landscape 2868 × 1320 and
13" iPad 2752 × 2064.

- Desktop renders of the real game can be produced at those sizes with the
  capture tool (`--resolution 2868x1320 -- --capture=...`), but those are
  renders from Linux.
- Screenshots taken on a device or the Simulator are preferred. **owner**
  to approve the final set.
