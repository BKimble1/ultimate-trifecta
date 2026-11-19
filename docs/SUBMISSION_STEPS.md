# Ultimate Trifecta 2.2: every step before App Store submission

Status on 2026-11-19: TestFlight build 2.2 (23) is App Store-eligible
(Season 1 premiere, new setup). The nine in-app purchase records exist in
App Store Connect without prices. The game service is not deployed. Steps
marked **(Claude)** are done in the coding session once the step before
them is done; everything else needs the account holder.

## Step 1. Apple account (account holder, about 30 minutes)

1. App Store Connect › **Business** › Agreements: open **Paid Apps**, accept
   it, then complete **Tax Forms** (W-9 or W-8BEN) and **Bank Account**.
   Wait until Paid Apps shows **Active** (can take up to a day). Until then
   StoreKit shows no products and no prices.
2. **Renew the iOS Distribution certificate before 26 November 2026.**
   developer.apple.com › Certificates, Identifiers & Profiles ›
   Certificates › + › Apple Distribution. (Or tell Claude and the upload
   workflow's signing step can create one through the API.) Uploads stop
   working once the old one expires.
3. App Store Connect › the app › **Pricing and Availability**: set the
   app's own price (Free) and the countries.

## Step 2. The nine in-app purchases (account holder, about 1 hour)

App Store Connect › Apps › Ultimate Trifecta › Monetization › In-App
Purchases. All nine records already exist. For each:

1. **Price**: Pricing › Add price (your choice per pack).
2. **Availability**: all the countries the app is in.
3. **Localization** (English): display name and description are filled in;
   check them.
4. **Review screenshot**: a screenshot from the iPhone of that product's
   purchase screen in the game (after Step 4 below, when prices show).
5. **Review note**: paste the line below for its type.
6. Check it says **Ready to Submit**.

| Product | Type | Review note |
|---|---|---|
| coins.250 / 500 / 1000 / 1500 / 3500 / 7500 | Consumable | Ultimate Trifecta is a cosmetic-only party game. This consumable adds N Coins to the player's wallet. Open Shop (top bar) › Coins to see it; it is delivered by the game's service after StoreKit 2 verification. No gameplay advantage. |
| skin.moonlight_runner, skin.starry_sleeper | Non-Consumable | Ultimate Trifecta is a cosmetic-only party game. This non-consumable unlocks the <name> outfit permanently (restorable). Open Shop (top bar) › Featured › Always available to see it; it is delivered by the game's service after StoreKit 2 verification. No gameplay advantage. |
| pass.s1 (Season 1 Premium Pass, USD 9.99) | Non-Consumable | Ultimate Trifecta is a cosmetic-only party game. This non-consumable unlocks the Premium reward track of Season 1 · Winter Break (restorable). Open Season Pass (top bar) to see it. No gameplay advantage, not a subscription. |

Keep in-app purchase **promotion** off.

## Step 3. The game service and website

1. **Cloudflare account** (free): sign up at dash.cloudflare.com.
2. **API token**: My Profile › API Tokens › Create Token › Create Custom
   Token. Permissions:
   - Account · Workers Scripts · Edit
   - Account · D1 · Edit
   - Account · Cloudflare Pages · Edit
   - Account · Account Settings · Read
   - Account · Workers Tail · Read
   - User · User Details · Read
   - User · Memberships · Read
   Account Resources: your account. Create, copy the token.
3. **Give it to the deploy**, either:
   - GitHub › BKimble1/ultimate-trifecta › Settings › Secrets and variables
     › Actions › New repository secret: name `CLOUDFLARE_API_TOKEN`, paste
     the token (recommended), or
   - ask Claude for the secure token form in the session.
   Never paste the token into chat.
4. **Support contact**: confirm that support@idlery.com (on the website) is
   a real inbox you read, or name the address to use. Apple requires a way
   to report players and a support page.
5. **(Claude)** Run "Deploy game service": both deployments (TestFlight /
   App Review sandbox and App Store production), all migrations, the
   secrets, and the website on Cloudflare Pages (Privacy and Support pages).
   Then fill `game/config/service.cfg` and `links.cfg`, and upload a new
   TestFlight build (the launch candidate).
6. App Store Connect › the app › **App Information** › App Store Server
   Notifications › **Version 2**: paste the Production and Sandbox URLs
   Claude gives you (they end in `/v1/appstore/notifications`).

## Step 4. Test on your iPhone with Apple's sandbox

1. App Store Connect › Users and Access › **Sandbox** › Test Accounts › +:
   a new email you control (not your own Apple ID).
2. On the iPhone: Settings › Developer › Sandbox Apple Account › sign in
   with it (don't use it for iCloud).
3. Install the launch candidate from TestFlight and check:
   - the Season 1 film, hold to skip, setup (look, name, Enter the dorm);
   - Shop › Coins shows six prices; buy a small and a large pack: the Coins
     arrive once;
   - buy Moonlight Runner; delete and reinstall the app; Shop › Restore
     Purchases: it comes back;
   - buy the Season 1 Premium Pass; claim an earned reward;
   - buy a Coin outfit; relaunch: everything is still there;
   - cancel a purchase: nothing charged, nothing granted;
   - turn on Airplane Mode right after confirming a purchase, then off:
     it arrives once;
   - play an online round with a second device: Coins, Season XP and the
     daily challenges count;
   - Friends with the second device (different Game Center account): each
     sees the other, invite, accept, same party;
   - Settings › Profile › Delete Game Profile.
   New products can take a few hours to reach the sandbox.
4. Take the nine in-app purchase review screenshots now (Step 2.4).

## Step 5. Rights and decisions

1. **Music**: the lobby albums were made with Suno, and the original
   tracks with mureka.ai. Confirm each was made on a plan that allows
   commercial use (Suno: a paid plan at the time of creation). If any
   wasn't, tell Claude: the game can ship with only the tracks you have
   rights to.
2. **Likenesses**: written permission from the two people Record Breaker
   and Dr. Doom are based on, for commercial use in the game and its
   marketing.
3. **"Dr. Doom"**: decide whether to keep the name (it echoes a
   comic-book trademark) or rename the label (progress and ownership are
   kept).
4. **Season Champion contest**: have `docs/release22/CONTEST_RULES.md`
   reviewed (a prize contest has legal requirements).
5. **Privacy policy**: check that the website's Privacy page (Step 3)
   matches the inventory in `docs/APP_STORE.md` and is in your name.

## Step 6. The version page

App Store Connect › the app › iOS App › **2.2** (or + Version). Copy-ready
text is in `docs/APP_STORE.md` (**(Claude)** can refresh it for 2.2 first:
it was written for 2.0).

1. **Build**: the launch candidate from Step 3.5 (not build 23).
2. Name, subtitle, promotional text, description, keywords.
3. Category: Games › Action (secondary optional).
4. **Screenshots**: iPhone 6.9" and iPad 13" sets in
   `docs/media/final/store/` (or your own). Shots 03, 04, 06 and 08 show
   Record Breaker or Dr. Doom: only with the permission in Step 5.2.
5. Support URL and Privacy Policy URL (from Step 3), Copyright
   ("2026 <your legal name>").
6. **App Privacy**: enter the table in `docs/APP_STORE.md` (not "Data Not
   Collected"); Tracking: No.
7. **Age rating**: answer with the table in `docs/APP_STORE.md`.
8. **Export compliance**: uses only exempt encryption (already declared in
   the build).
9. **Game Center**: add the two leaderboards (`ut.season_points`,
   `ut.fastest_run`).
10. **In-App Purchases**: add all nine to this version.
11. **App Review information**: your name, phone and email; the review
    notes from `docs/APP_STORE.md`; ideally a link to a short two-device
    video of Friends and a party.
12. **Version release**: Manually release this version.

## Step 7. Submit

Add for Review › check the submission lists the 2.2 version **and all
nine in-app purchases** › Submit to App Review. Keep the game service
running for the whole review. If Apple asks questions, the evidence is in
`docs/APP_STORE_READINESS.md`.
