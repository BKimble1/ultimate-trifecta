# Ultimate Trifecta website
Independent static site for https://ultimatetrifecta.idlery.com. No npm, build step, server, analytics, tracking scripts or external font dependency. All game images are local copies of existing Git blobs from the 2.2 build-19 branch (66e3e9a9bcecaddb704fd93eeba197d568065962). Gameplay/store captures from earlier development passes are illustrative, not device screenshots. Replace them with final approved captures as appropriate. No em dashes or decorative text badges in site copy.

## Deployment
Cloudflare Pages (or another static host): connect this repo, choose the merged main branch (or website/launch-site for preview), set framework None, no build command, output directory website, root repository. Add ultimatetrifecta.idlery.com as a custom domain, configure DNS as directed by host, enable HTTPS and verify all routes on a phone and desktop. Preview locally with `python3 -m http.server 8000 --directory website` from repository root.

App Store Connect:
- Marketing URL: https://ultimatetrifecta.idlery.com/
- Support URL: https://ultimatetrifecta.idlery.com/support/
- Privacy Policy URL: https://ultimatetrifecta.idlery.com/privacy/
- User Privacy Choices URL (optional): https://ultimatetrifecta.idlery.com/privacy-choices/
- Terms: https://ultimatetrifecta.idlery.com/terms/ (Apple standard EULA unless the owner adopts a compliant custom EULA)
- Official contest rules: https://ultimatetrifecta.idlery.com/competition/ (also keep official rules in app)

## Before launch
1. Confirm Idlery Services LLC is the legal publisher and support@idlery.com is monitored, as listed in Idlery-Website. Add any postal address, telephone, trader disclosures or other contact information required in distribution territories. These pages are owner-review drafts, not legal advice. Confirm retention for report, support, security and backup records, processor terms, children/consent rules, contest eligibility (the existing in-game under-13 permission language requires legal review), tie handling and eligible jurisdictions. Keep public and in-game rules identical. Do not run contest until rules are approved; if start date changes, update both.
2. Confirm screenshots, names, music and promotional art rights. Do not promote unapproved content.
3. Game build 2.2 (19) is eligible but provisional, per TESTFLIGHT_RELEASE.md. Deploy sandbox and production game services and create required App Store products including current direct premium pass product if offered. Confirm tax/banking, current product list, final privacy manifest and label against actual deployed behavior. Older docs/APP_STORE.md predates Quick Match, current chat, contest and new direct pass; update its age rating, metadata, data inventory, reviews and IAP list for 2.2.
4. In the active game branch, update game/config/links.cfg: privacy_url="https://ultimatetrifecta.idlery.com/privacy/", support_url="https://ultimatetrifecta.idlery.com/support/", support_email="support@idlery.com". Set the same URLs/contact in both service/wrangler.toml environments. Make terms, privacy choices and competition accessible where appropriate. Ensure in-app deletion, reporting, filtering, blocking, purchase restore, Game Center and moderation workflow work on configured real devices. Support email is not a substitute for the in-app account deletion or moderation flow.
5. Verify all public URLs return 200 without login, support email receives mail, and preview on desktop and phone; run the static check with `python3 website-check.py` from this repository root. Do not enter unverified URLs in App Store Connect. Once the App Store listing is public, replace the prelaunch homepage status and CTA with a genuine download link to https://apps.apple.com/app/id6818346960 and change footer launch strip. No badge or fake store listing before public availability.
6. Announce actual contest winners on support and in-game, after validation; update per-season dates and status.
Sources: game release branch README.md, TESTFLIGHT_RELEASE.md, docs/APP_STORE.md, docs/release22/CONTEST_RULES.md, champion_promo.gd and Idlery-Website support page. Apple references: https://developer.apple.com/app-store/review/guidelines/ ; https://developer.apple.com/support/offering-account-deletion-in-your-app/ ; https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/ .

Assets: campus.jpg from docs/media/v8/campus/overview.jpg; runner.png and watch.png from docs/media/final/store/iphone_6.9/01_runner_splash_fountain.png and 02_night_watch_golf_cart.png; party.jpg from docs/release22/media/v23_party_8p.jpg; season.jpg from v26_pass_full.jpg; competition.jpg from v25_event_poster.jpg; title.png and icon.png from game/assets.
