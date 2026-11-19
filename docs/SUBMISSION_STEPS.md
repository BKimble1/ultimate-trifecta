# Ultimate Trifecta 2.2: every step to App Store submission

Written 19 November 2026. Where things stand:
- TestFlight build **2.2 (23)** is uploaded and App Store-eligible (Season 1
  film, new setup). It is **not** the build to submit: the launch build comes
  after the game service is live (Part C).
- The **9 in-app purchase records** exist in App Store Connect, with no
  prices or screenshots.
- The **2 Game Center leaderboards** exist (`ut.season_points`,
  `ut.fastest_run`).
- **Signing is in order** (A2): no certificate renewal needed.
- The **game service and website are not deployed**.

Parts marked **[Claude]** are done in the coding session; tell Claude when
the part before is finished. Everything else is yours. Never paste a
password, key or token into the chat.

Order: A and B can be done now, in parallel with C. D needs C. E and F can
be prepared any time. G is last.

---------------------------------------------------------------------------

## Part A. Apple account and certificate (about 30 minutes, plus waiting)

### A1. Paid Apps Agreement
1. Go to https://appstoreconnect.apple.com and sign in as the **Account
   Holder** (only that person can accept agreements).
2. Click **Business** (on the home page, or in the top menu).
3. Under **Agreements**, find **Paid Apps**. If its status is "New" or
   "Pending User Info", click **View and Agree to Terms**, read, tick the
   box, click **Agree**.
4. Still in Business, open **Tax Forms** › **Set Up Tax Forms** (or
   **View**): fill the **U.S. Form W-9** if you're a US person or business
   (or **W-8BEN** / **W-8BEN-E** if not). Submit.
5. Open **Bank Accounts** › **Add Bank Account**: country, account holder
   name exactly as on the account, routing number, account number, account
   type. Save.
6. Back on Business, check Paid Apps says **Active**. It can take from a
   few minutes to about a day. Until it's Active, the game shows no prices
   and nothing can be bought.

### A2. Distribution certificate: nothing to do (checked 19 Nov 2026)
The GitHub Actions upload doesn't use a stored certificate or profile. It
signs automatically through the App Store Connect API key, and a signing
check on 19 Nov 2026 (workflow input `sign_check`) showed:
- **Signer:** Apple's **Cloud Managed Apple Distribution** certificate
  ("Apple Distribution: Blake Kimble", serial 2BF5DB4C…, valid to 24 Aug
  2027; Apple keeps its private key). Not the legacy **iOS Distribution**
  certificate (serial 7E525A3A…) that expires 26 Nov 2026. Confirmed by
  workflow run #285 (sign_check, passed).
- **Profile:** **iOS Team Store Provisioning Profile:
  com.idlery.ultimatetrifecta**, an App Store profile valid to 12 Sep 2027,
  Game Center on, `get-task-allow` off. Xcode manages and renews it.
- The team's three **Apple Distribution** certificates are valid to Aug–Sep
  2027. When the legacy one expires on 26 Nov, uploads keep working.
- Every signed run now prints this signing report and fails if the signer
  isn't a current distribution certificate (or is the legacy one), or the
  profile isn't a current App Store profile.
- The workflow only ever revokes the temporary development certificates its
  own runs create ("Created via API"); it never touches a distribution
  certificate.

### A3. App price and availability
1. App Store Connect › **Apps** › **Ultimate Trifecta**.
2. Left column › **Pricing and Availability** (under Monetization or
   General, depending on the layout).
3. **Price Schedule** › **Add Pricing**: base country **United States**,
   price **USD 0.00 (Free)** › Next › Confirm.
4. **App Availability** › **Set Up Availability** (or Edit): choose **All
   countries or regions** (or pick yours) › Confirm. Save.

### A4. App Information (one-time fields)
Apps › Ultimate Trifecta › left column › **App Information**:
1. **Name**: `Ultimate Trifecta`
2. **Subtitle**: `Splash three. Race home.`
3. **Category**: Primary **Games**, subcategory **Action**. Secondary
   (optional): **Games › Family**.
4. **Content Rights**: click **Set Up Content Rights Information** › "Does
   your app contain, show, or access third-party content?" › **Yes**, and
   tick that you have the necessary rights (answer this only after Part E
   is settled).
5. **Age Rating**: click **Set Up Age Rating** (or Edit) and answer with
   the table in Part F5.
6. **App Store Server Notifications**: filled in Part C8.
7. Click **Save** (top right).

---------------------------------------------------------------------------

## Part B. The 9 in-app purchases (about 1 hour; screenshots come in D)

### B1. Open them
App Store Connect › Apps › Ultimate Trifecta › left column ›
**Monetization** › **In-App Purchases**. You'll see 9 rows. Click each one
and do B2 to B7.

### B2. Product details (already filled; check them)
| Reference name | Product ID | Type | Display name | Description |
|---|---|---|---|---|
| Coins 250 | com.idlery.ultimatetrifecta.coins.250 | Consumable | 250 Coins | 250 Coins for the Shop. Cosmetic only. |
| Coins 500 | com.idlery.ultimatetrifecta.coins.500 | Consumable | 500 Coins | 500 Coins for the Shop. Cosmetic only. |
| Coins 1000 | com.idlery.ultimatetrifecta.coins.1000 | Consumable | 1,000 Coins | 1,000 Coins for the Shop. Cosmetic only. |
| Coins 1500 | com.idlery.ultimatetrifecta.coins.1500 | Consumable | 1,500 Coins | 1,500 Coins for the Shop. Cosmetic only. |
| Coins 3500 | com.idlery.ultimatetrifecta.coins.3500 | Consumable | 3,500 Coins | 3,500 Coins for the Shop. Cosmetic only. |
| Coins 7500 | com.idlery.ultimatetrifecta.coins.7500 | Consumable | 7,500 Coins | 7,500 Coins for the Shop. Cosmetic only. |
| Skin Moonlight Runner | com.idlery.ultimatetrifecta.skin.moonlight_runner | Non-Consumable | Moonlight Runner | A permanent outfit. Cosmetic only. |
| Skin Starry Sleeper | com.idlery.ultimatetrifecta.skin.starry_sleeper | Non-Consumable | Starry Sleeper | A permanent outfit. Cosmetic only. |
| Season 1 Premium Pass | com.idlery.ultimatetrifecta.pass.s1 | Non-Consumable | Season 1 Premium Pass | Premium track of Season 1. Cosmetic only. |

In each product: section **App Store Localization** › English (U.S.):
check the Display Name and Description match the table (≤30 and ≤45
characters). Fix if needed and **Save**.

### B3. Price
1. In the product, section **Price Schedule** › **Add Pricing**.
2. Base country **United States**; choose the USD price from the list
   (your choice for the Coin packs and outfits; the Season 1 Premium Pass
   is **USD 9.99**, as decided).
3. Next › let Apple fill the other countries automatically › Confirm.

### B4. Availability
Section **Availability** › **Set Up Availability**: the same countries as
the app › Confirm.

### B5. Review note
Section **Review Information** › **Review Notes**, paste:
- Coin packs (change N to the pack's number):
  `Ultimate Trifecta is a cosmetic-only party game. This consumable adds N Coins to the player's wallet. Open Shop (top bar) > Coins to see it. It is delivered by the game's service after StoreKit 2 verification. No gameplay advantage.`
- Moonlight Runner / Starry Sleeper:
  `Ultimate Trifecta is a cosmetic-only party game. This non-consumable unlocks the Moonlight Runner outfit permanently (restorable with Restore Purchases). Open Shop (top bar) > Featured > Always available to see it. It is delivered by the game's service after StoreKit 2 verification. No gameplay advantage.`
  (Starry Sleeper: change the name.)
- Season 1 Premium Pass:
  `Ultimate Trifecta is a cosmetic-only party game. This non-consumable unlocks the Premium reward track of Season 1 - Winter Break for good (restorable with Restore Purchases). Open Season Pass (top bar) > Premium to see it. It is not a subscription and gives no gameplay advantage.`

### B6. Review screenshot (do this after Part D)
Section **Review Information** › **Screenshot** › upload a screenshot taken
on your iPhone of that product's purchase screen (Part D6). One per product.

### B7. Promotion and status
- Leave **App Store Promotion** off (the game doesn't handle promoted
  purchases).
- When B2 to B6 are done, the product's status reads **Ready to Submit**.

---------------------------------------------------------------------------

## Part C. Game service and website

### C1. Cloudflare account (free)
1. Go to https://dash.cloudflare.com/sign-up, sign up with an email you
   control, verify the email.
2. No domain or paid plan is needed. Workers, D1 and Pages free tiers are
   enough.

### C2. API token
1. In Cloudflare, top right person icon › **My Profile** › **API Tokens** ›
   **Create Token**.
2. At the bottom, **Create Custom Token** › **Get started**.
3. Token name: `ultimate-trifecta-deploy`.
4. Permissions (click **+ Add more** for each row):
   | Scope | Item | Access |
   |---|---|---|
   | Account | Workers Scripts | Edit |
   | Account | D1 | Edit |
   | Account | Cloudflare Pages | Edit |
   | Account | Account Settings | Read |
   | Account | Workers Tail | Read |
   | User | User Details | Read |
   | User | Memberships | Read |
5. Account Resources: **Include** › your account.
6. Leave Client IP filtering and TTL empty › **Continue to summary** ›
   **Create Token**.
7. Copy the token shown (it's shown once). Don't paste it into chat.

### C3. Put the token in GitHub
1. https://github.com/BKimble1/ultimate-trifecta › **Settings** (top tab).
2. Left: **Secrets and variables** › **Actions**.
3. **New repository secret**: Name `CLOUDFLARE_API_TOKEN`, Secret: paste
   the token › **Add secret**.
4. Tell Claude it's there.

### C4. Support email
Tell Claude which address players should write to. The website and game
currently say **support@idlery.com**: confirm it's a real inbox you read,
or give another. Apple needs a working support contact and a way to report
other players.

### C5. [Claude] Deploy
Claude runs **Deploy game service**: it creates the two databases (one for
TestFlight and App Review, one for the App Store), deploys both services,
creates their secret keys (kept only in Cloudflare), and publishes the
website with its Privacy, Support, Terms, Rules and Delete-account pages.
Claude then gives you:
- the **website address** (something like `https://ultimate-trifecta.pages.dev`),
- the **Support URL** and **Privacy Policy URL**,
- two **notification URLs** (C8).

### C6. Check the website
Open the Privacy page and the Support page on your phone. Check your name
or company name and the support email are right. If anything should
change, tell Claude.

### C7. [Claude] Connect the game and build the launch candidate
Claude fills `game/config/service.cfg` (service addresses and public keys)
and `game/config/links.cfg` (privacy, support, email), runs the tests and
uploads the next TestFlight build: the **launch candidate**.

### C8. App Store Server Notifications
1. App Store Connect › Apps › Ultimate Trifecta › **App Information**.
2. Section **App Store Server Notifications** › **Production Server URL** ›
   paste the production URL from Claude (ends in
   `/v1/appstore/notifications`) › Version **Version 2**.
3. **Sandbox Server URL** › paste the sandbox URL › **Version 2**.
4. **Save**.

---------------------------------------------------------------------------

## Part D. Test everything on your iPhone (about 1 hour)

### D1. Sandbox test account
1. App Store Connect › **Users and Access** › **Sandbox** (tab) › **Test
   Accounts** › **+**.
2. First/last name anything; **email: a real address you control that has
   never been an Apple ID** (e.g. a new alias); password; country United
   States › **Create**.

### D2. Sign in on the iPhone
1. iPhone › **Settings** › **Developer** (if missing: connect the phone to
   a Mac with Xcode once, or Settings › Privacy & Security › Developer Mode
   › On, restart).
2. **Sandbox Apple Account** › sign in with the D1 account. Do **not** sign
   into iCloud or the App Store with it.
3. Make sure Settings › **Game Center** is signed in with your normal
   Apple ID.

### D3. Install the launch candidate
TestFlight app › Ultimate Trifecta › make sure the newest build number
(from C7) is selected › **Update** / **Install**.

### D4. First launch
1. Open the game: Idlery Games logo, then the **Season 1 film**.
2. Note anything that flashes between the logo and the film, or covers the
   film (the Game Center banner).
3. Hold **Hold to skip** once (bottom right) and check it skips into
   setup. Pick a look, Continue, keep or change the name, **Enter the dorm**.

### D5. Purchases (sandbox purchases are free)
For each, the Apple sheet should say **[Environment: Sandbox]**.
1. Top bar **Shop** › **Coins**: six packs, each with a price. Buy **250**
   and **7,500**: the Coins counter goes up by exactly that, once.
2. Shop › **Featured** › **Always available** › **Moonlight Runner** › buy.
   Equip it in the Locker.
3. Delete the app, reinstall from TestFlight, open it, Shop › Featured ›
   **Restore Purchases**: Moonlight Runner comes back.
4. **Season Pass** (top bar) › Premium › buy the **Season 1 Premium Pass**.
   Play a round, then **Claim** a Premium reward.
5. Buy an outfit with Coins in the Shop. Close and reopen the app:
   everything is still there.
6. Start a purchase and tap **Cancel** on Apple's sheet: nothing charged,
   nothing added.
7. Start a purchase, confirm, and immediately turn on **Airplane Mode**;
   wait 10 s, turn it off, open the game: the item arrives once.

### D6. Purchase screenshots (for B6)
On the iPhone, open each product's purchase screen and take a screenshot
(side button + volume up). Nine in total:
- Shop › Coins (one screenshot works for all six packs, or one each),
- Moonlight Runner's page, Starry Sleeper's page,
- Season Pass › Premium.
Upload them in B6.

### D7. Online play (a second iPhone or iPad with a different Game Center account)
1. Both devices: the launch candidate installed, Game Center signed in.
2. Device 1: **Invite friends** in the lobby, invite device 2 (or share the
   **Party code**; device 2 uses **Join with a code**).
3. Play one online round. Afterwards: Coins and Season XP go up, and
   **Season Pass › Challenges** shows today's three challenges counting.
4. **Friends** on both devices: each sees the other online, invite, accept,
   same party.
5. Try **Quick Match** once (random players, empty seats filled with bots).

### D8. Delete profile
Settings (gear) › **Profile** › **Delete Game Profile** › confirm: the game
restarts at setup. (Do this last; it erases that device's progress.)

If anything in D fails, tell Claude what you saw (a screenshot helps).

---------------------------------------------------------------------------

## Part E. Rights and decisions

1. **Music.** The lobby albums ("Lobby Pluck", "Cozy Christmas Lobby",
   "Stardust Reverie") were made with **Suno**: Suno only allows commercial
   use of songs made while on a **paid plan**. "Night Campus Loop" and
   "Soft Bounce Loop" were made with **mureka.ai**: check its terms allow
   use in an app. For each song, confirm or tell Claude to remove it.
2. **Likenesses.** Record Breaker and Dr. Doom are based on two real
   people. Get **written permission** from each for use in the game and
   its marketing (an email saying so is the minimum; a signed release is
   better). Keep them.
3. **"Dr. Doom" name.** It echoes a well-known comic-book character
   (trademark). Decide: keep it, or tell Claude a new display name (players
   keep the outfit and progress).
4. **Season Champion contest.** Because there's a prize, have someone
   check `docs/release22/CONTEST_RULES.md` (eligibility, dates, prize,
   sponsor = you, "Apple is not a sponsor"). Tell Claude any changes.
5. **Privacy policy.** It must be in your (or your company's) name, match
   what the app collects (the App Privacy table in F6), and be reachable
   at the Privacy Policy URL.

---------------------------------------------------------------------------

## Part F. The 2.2 version page

App Store Connect › Apps › Ultimate Trifecta › left column under **iOS
App**: click **2.2 Prepare for Submission**. If there's no 2.2, click the
**+** next to iOS App, type `2.2`, Create.

### F1. Screenshots
Section **Previews and Screenshots**:
1. **iPhone** › **6.9" Display** › drag in the 8 files from
   `docs/media/final/store/iphone_6.9/` (2868 × 1320).
2. **iPad** › **13" Display** › drag in the 8 files from
   `docs/media/final/store/ipad_13/` (2752 × 2064).
3. Shots **03, 04, 06, 08** show Record Breaker or Dr. Doom: upload them
   only with the permission from E2; otherwise use 01, 02, 05, 07.
4. Drag to reorder so 01 is first.

### F2. Text
- **Promotional Text**:
  `A 3 a.m. campus chase: splash into three waters and race home before the Night Watch catches you. Season 1 - Winter Break is here.`
- **Description**: the text in Appendix 1 below.
- **Keywords**:
  `party,chase,tag,runners,campus,splash,friends,multiplayer,pajamas,casual,bots,season pass`
- **Support URL**: from C5.
- **Marketing URL**: the website address from C5 (optional).
- **Version**: `2.2`
- **Copyright**: `2026 ` followed by your legal name or company name.

### F3. Build
Section **Build** › **Add Build** (or the + next to it) › choose the
**launch candidate** from C7 (not 23) › Done. If asked about **encryption**:
"None of the algorithms mentioned above" / exempt (the build already says
it uses no non-exempt encryption).

### F4. Game Center
Section **Game Center** › tick **Game Center** › under **Leaderboards**
click **+** / **Add** › select **Season Points** (`ut.season_points`) and
**Fastest Run** (`ut.fastest_run`) › Done.

### F5. Age rating (App Information › Age Rating › Edit)
| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |
| Contests | **Yes** if the Season Champion prize is live in this version, otherwise None |
| Unrestricted Web Access | No |
| User-Generated Content | Yes (player names and typed party chat, filtered, reportable) |
| Messaging and Chat | Yes |
| Advertising | No |
| Gambling | No |
| Loot boxes | No |
| Parental controls / age assurance | No |
Save. Apple shows the resulting rating.

### F6. App Privacy (left column › App Privacy)
1. **Privacy Policy URL**: from C5. Save.
2. **Get Started** / **Edit** under Data Types › "Do you or your
   third-party partners collect data from this app?" › **Yes**.
3. Tick these data types, then Save:
   - Contact Info › **Name**
   - User Content › **Gameplay Content**, **Other User Content**
   - Identifiers › **User ID**
   - Purchases › **Purchase History**
   - Contacts › **Contacts**
   - Usage Data › **Product Interaction**
4. For **each** ticked type, answer: used for **App Functionality** only;
   **Linked to the user: Yes**; **Used for tracking: No**. Save each.
5. **Publish** the privacy answers.

### F7. In-app purchases
Section **In-App Purchases and Subscriptions** › **+** / **Select** › tick
all **9** › Done.

### F8. App Review Information
- **Sign-in required**: No (Game Center, no separate account).
- **Contact**: your first name, last name, phone, email.
- **Notes**: Appendix 2 below.
- **Attachment** (optional but helpful): a short video of two devices
  inviting each other and playing a party round.

### F9. Version Release
Choose **Manually release this version**.

Click **Save** (top right).

---------------------------------------------------------------------------

## Part G. Submit

1. Top right: **Add for Review**.
2. The draft submission lists: **iOS App 2.2** and the **9 in-app
   purchases**. If a purchase is missing, go to it and check it's Ready to
   Submit, then **Add** it to the submission.
3. Fix anything App Store Connect lists in red.
4. **Submit to App Review**.
5. Keep the game service running for the whole review (it costs nothing
   on the free tier). Answer Apple's messages in App Store Connect ›
   Messages (Resolution Center); Claude can help draft replies.
6. When it's **Pending Developer Release**, click **Release This Version**
   when you're ready.

---------------------------------------------------------------------------

## Appendix 1. Description (paste as is)

```
Ultimate Trifecta is a playful after-hours campus chase for up to eight players.

Runners in pajamas and costumes slip out of the dorm, splash into tonight's three marked waters and race back inside before the clock runs out. The Night Watch hunts them on foot and in golf carts. Get enough runners home to win the round, or, as the Night Watch, stop them.

SEASON 1 - WINTER BREAK
- A snowy campus, a 100-tier Season Pass earned by playing, and daily and weekly challenges that add Season XP.
- A Premium track with two signature outfits at tiers 50 and 100.

PLAY YOUR WAY
- Quick Match with random players, or a private party with friends. Empty spots are filled by bots, always labelled BOT.
- One, two or three Night Watch, and series of one, three or five rounds.
- Practice anytime: full rounds with bots, offline, plus guided tutorials.
- Hide in bushes, grab power-ups, take a rift across campus.

PLAY WITH FRIENDS
- See which Game Center friends are online, in a party or in a round, and invite them straight into your party.
- Or share a party code, or use Game Center's invite sheet.
- No voice chat.

MAKE IT YOURS
- Create your runner: outfits, colors, faces, hair, hats, shoes and emotes.
- A Shop with rotating outfits, permanent favorites and Coin packs.

BUILT FOR PHONES AND TABLETS
- Touch controls for two thumbs, adjustable buttons and left-handed layouts.
- MFi, Xbox and PlayStation controllers.
- Reduced Motion support.

FRIENDLY BY DESIGN
- Quick Chat phrases and emotes; typed chat only in parties set up through the game, checked by its moderation service.
- Names are checked. Mute, report or block anyone from their player card.
- Delete your game profile at any time in Settings.

No ads. No tracking. Optional in-app purchases (Coins, two permanent outfits and the Season 1 Premium Pass) are cosmetic only and never change how anyone plays.
```

## Appendix 2. App Review notes (paste, then fill the contact)

```
Sign-in: the game uses Game Center. Please be signed in to Game Center (Settings > Game Center) on the review device. There is no separate account or password.

First launch: the Season 1 film plays once after the Idlery Games logo (hold "Hold to skip", bottom right, to skip). Then create a runner (look, then name) and tap "Enter the dorm".

Home is your party lobby. The Play button starts the selected mode: Quick Match (random players plus bots), Party vs Bots, or Practice (offline, choose Runner or Night Watch). Practice needs no other players.

Friends and parties: "Invite friends" in the lobby invites Game Center friends; a second device on a different Game Center account can also join with "Join with a code" and the party code. The reviewer's account won't have mutual friends, so a short two-device video is attached.

Purchases (cosmetic only): Shop (top bar) > Coins has six Coin packs (consumable). Shop > Featured > Always available has two permanent outfits, Moonlight Runner and Starry Sleeper (non-consumable). Season Pass (top bar) > Premium sells the Season 1 Premium Pass (non-consumable). Restore Purchases is in the Shop and on each outfit's page. Other outfits are bought with Coins after a confirmation. Every purchase is verified with StoreKit 2 and Apple's signed transaction on our server before delivery. Review purchases use Apple's sandbox; the game detects this and keeps them separate from customers'. Nothing bought changes speed, reach or score.

Season Pass: 100 tiers earned by playing online rounds and daily/weekly challenges. Rewards are claimed with Claim or Claim all.

Safety: Quick Chat phrases and emotes; typed chat only in parties set up through the game's service, filtered and rate-limited. Tap a player or message to Mute, Report or Block. A host can remove a player. Names are checked.

Delete Game Profile: Settings > Profile > Delete Game Profile.

Contact: [your name, phone, email]
```
