# Ultimate Trifecta service

A small, dependency-free Cloudflare Worker with a D1 (SQLite) database. It is
the trusted part of online play:

- **Verified sign-in.** The game sends Game Center's identity-verification
  signature (`fetchItems(forIdentityVerificationSignature:)`). The service
  downloads Apple's certificate (only from `https://static.gc.apple.com`),
  checks that it is valid, and verifies the RSA/SHA-256 signature over
  `teamPlayerID ‖ bundleID ‖ timestamp (u64 BE) ‖ salt`. It also checks that
  the timestamp is fresh. A player ID or display name on its own never signs
  anyone in.
- **Sessions.** Signing in issues an HMAC token bound to the profile, bundle,
  environment and audience. Tokens expire after 1 hour, and sign-out revokes
  them.
- **Profiles.** Each profile has an opaque ID, a display name with a
  discriminator (`Name#1234`) and the runner's appearance (schema 2). Players
  can delete their profile; this requires a sign-in from the last 10 minutes.
- **Name moderation.** Names are normalised (NFKC, whitespace) and must be
  3–16 letters, digits, single spaces or underscores. They are checked
  against leetspeak and look-alike forms and against slur, sexual, profanity,
  threat, impersonation and contact lists. An allowlist covers harmless words
  that contain flagged substrings. The service also handles reserved names,
  suggestions, a 24 h rename cooldown and rate limits. Tests cover false
  positives.
- **Safety.** Persistent blocks, and reports with receipts. The owner has a
  moderation queue with dismiss, forced rename, suspend and unsuspend, plus an
  audit log.
- **Typed party chat (V6).** `POST /v1/chat/check` runs the message policy
  (`src/chat_rules.js`) for a signed-in member of a live room and signs the
  approved text into a 5-minute RS256 token (the admission key). The host and
  every receiver verify it before showing anything. Message text isn't
  stored. `POST /v1/reports/message` files a report with the signed message
  as evidence. Policy, limits and the workflow: `docs/MODERATION.md`.
- **Party rooms.**
  - Rooms are created atomically, with 6-character codes from an alphabet
    without look-alikes, and codes are normalised strictly.
  - Rooms move through these states: forming, open, full, loading, in_match,
    results, closing, expired. The host sends heartbeats and rooms expire
    when they stop.
  - Slots are reserved atomically, and a reconnecting player keeps their own
    slot.
  - Blocks and removals deny admission. Errors are distinct (`not_found`,
    `expired`, `full`, `in_match`, `version_mismatch`, ...).
  - **Admission tokens** (RS256, 120 s, single use) are bound to the joiner's
    Game Center player and the room. The host's game verifies them with the
    public key built into the app.

- **Friends (Final).** `src/friends.js`, migration `0006_friends.sql`
  ([docs/final/friends.md](../docs/final/friends.md)). Each game uploads the
  teamPlayerIDs of its own authorised Game Center friends; the service
  stores only keyed hashes (HMAC-SHA256 with `FRIEND_HASH_KEY`) and treats
  two players as friends only while both lists contain each other (a mutual
  claim from two verified sessions), neither has blocked the other and
  neither is suspended. Mutual friends see each other's in-game status
  (online, in a party, in a round, offline; from a 20 s heartbeat that
  expires after 60 s) and can invite each other into the party they are in;
  accepting returns the room code and the game joins through the normal
  `/v1/rooms/<code>/join` admission. Nobody else can be listed, probed or
  invited, and room codes are never shown in status.

Nothing is mocked in the release path. If `game/config/service.cfg` has no
URL, the service is off: practice and local play still work, names stay on
the device, and the game never claims a verified profile.

## Status

**The service is not deployed.** Deploying it needs the owner's Cloudflare
account. Workers and D1 have free tiers, and these scripts create no paid
resources. The code, migrations, tests and deployment scripts are complete.
`npm test` runs the whole API against an in-memory D1 (`node:sqlite`) with a
per-run test certificate. That proves the logic, not a live deployment.

## Deploy (owner, about 20 minutes): two deployments

Prerequisites: Node.js 22.13+ and a Cloudflare account.

The service runs as **two deployments with separate databases**, both from
this folder (FINAL_RELEASE_SWEEP; design in
[docs/final/commerce.md](../docs/final/commerce.md)):

| | sandbox (default) | production (`[env.production]`) |
|---|---|---|
| Worker | `trifecta-service` | `trifecta-service-production` |
| D1 database | `trifecta` | `trifecta-production` |
| `ENVIRONMENT` / `APPLE_ENVIRONMENT` | `sandbox` / `Sandbox` | `production` / `Production` |
| Who | TestFlight, Xcode builds, App Review purchases | App Store customers |
| Credits | only Apple **Sandbox** transactions | only Apple **Production** transactions |

The same build talks to either: it routes by the App Store receipt kind at
launch and moves to the sandbox deployment by itself when production
answers a verified sandbox purchase with `409 sandbox_purchase` (App
Review). Neither deployment can mint the other's value.

```sh
cd service
npm test                                    # all tests must pass
npx wrangler login                          # or export CLOUDFLARE_API_TOKEN
npx wrangler d1 create trifecta             # database_id -> wrangler.toml [[d1_databases]]
npx wrangler d1 create trifecta-production  # database_id -> wrangler.toml [[env.production.d1_databases]]
scripts/gen_keys.sh                         # writes service/.secrets/ (git-ignored)
#   prints the admission PUBLIC key -> game/config/service.cfg (both *_admission_public_key)
scripts/deploy.sh                           # sandbox: migrations, secrets, deploy
DEPLOY_ENV=production scripts/deploy.sh     # production: the same secrets, its own database
curl -s https://trifecta-service.<your-subdomain>.workers.dev/v1/health
curl -s https://trifecta-service-production.<your-subdomain>.workers.dev/v1/config   # apple_environment: Production
```

Then set the game's `game/config/service.cfg`. Only public values go there.

```ini
[service]
production_url="https://trifecta-service-production.<your-subdomain>.workers.dev"
production_admission_public_key="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
sandbox_url="https://trifecta-service.<your-subdomain>.workers.dev"
sandbox_admission_public_key="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
url=""
admission_public_key=""
```

(`url` / `admission_public_key` remain a single-endpoint fallback for
development, used only when neither pair is set.)

App Store Connect › the app › App Information › App Store Server
Notifications, Version 2: **Production Server URL**
`https://trifecta-service-production.<your-subdomain>.workers.dev/v1/appstore/notifications`,
**Sandbox Server URL**
`https://trifecta-service.<your-subdomain>.workers.dev/v1/appstore/notifications`.
Each deployment refuses the other environment's notifications.

Keep `service/.secrets/` out of git and out of chat. `deploy.sh` reads it
and uploads the secrets with `wrangler secret put`.

### Variables (`wrangler.toml` → `[vars]`)

| Name | Meaning |
|---|---|
| `ENVIRONMENT` | `sandbox` (default deployment) or `production` (`[env.production]`). Bound into session tokens (a token of one deployment is refused by the other) and written on every wallet, ledger and App Store row. |
| `APPLE_ENVIRONMENT` | `Sandbox` or `Production`: the only App Store environment this deployment credits, and its App Store Server API host. |
| `BUNDLE_ID` | Must equal the app's bundle ID (`com.idlery.ultimatetrifecta`). Signatures for other bundles are rejected. |
| `GC_KEY_HOSTS` | Hosts allowed for Apple's public-key URL. Keep `static.gc.apple.com`. |
| `MIN_CLIENT_BUILD` | Older clients are told to update before online play (`App.build_number()`, e.g. 1.1 → 101). |
| `SUPPORT_EMAIL`, `SUPPORT_URL`, `PRIVACY_URL` | The owner's **real, monitored** contact and policy links. Leave them empty until they exist; the game shows no link rather than a placeholder. |

### Secrets (`wrangler secret put`, done by `deploy.sh`)

`SESSION_KEY` (HMAC for session tokens), `ADMIN_TOKEN` (moderation API),
`ADMISSION_PRIVATE_KEY` (PKCS#8 PEM, signs admission tokens),
`APP_ACCOUNT_TOKEN_KEY` (FINAL_RELEASE_SWEEP: derives each player's StoreKit
appAccountToken as UUID(HMAC-SHA256(key, "gamecenter:" + teamPlayerID));
**it must be the same on both deployments**, which deploying both from one
`.secrets/` folder does, and must never change once purchases exist; a
deployment without it delivers no purchase), and
`FRIEND_HASH_KEY` (Final: the HMAC key for the hashes of friend IDs, at
least 32 characters; `scripts/gen_keys.sh` writes `.secrets/friend_hash_key`
and `deploy.sh` refuses to deploy without it). Without `FRIEND_HASH_KEY` the
service leaves `friends` out of `/v1/config` features and the game shows
Friends with "Status unavailable" (Apple's invite sheet and party codes
still work). Keep the key stable: a new key orphans every stored friend set
until each game uploads its list again (it does at its next launch or
Friends visit). Deploying both deployments from one `.secrets/` folder
uses the same key for both, which is fine: their databases are separate.
Optional: `ASC_IAP_KEY_ID`, `ASC_IAP_ISSUER_ID`, `ASC_IAP_PRIVATE_KEY`
(App Store Server API).

### Friends retention and TTL

| Data | Kept | Removed |
|---|---|---|
| Friend set (keyed hashes of up to 500 friends' teamPlayerIDs, plus the player's own hash) | until replaced by the next upload | whole set replaced on every upload; deleted after 30 days without one (cron), on `DELETE /v1/friends` (friend access revoked) and with the profile |
| Presence (one row per running game: status, verified room, protocol/build) | 60 s after the last heartbeat (every 20 s) | at expiry (cron every 5 min), on background (`DELETE /v1/presence`), sign-out and profile deletion; no history |
| Invites (inviter, invitee, room, state) | 5 minutes pending; resolved rows (accepted, declined, expired, cancelled) for 24 h | cron after 24 h; with either player's profile |

Capacity: every playing, Friends-enabled game writes at most one presence
row per heartbeat (≈3 writes a minute, ≈4,300 a day) and reads status only
while its Friends panel is open. Size the Cloudflare plan from the expected
number of concurrent players (the Workers and D1 free tiers cover a few
dozen concurrent players around the clock).

## Moderation (owner)

```sh
export TRIFECTA_SERVICE=https://trifecta-service.<sub>.workers.dev
export TRIFECTA_ADMIN_TOKEN=$(cat service/.secrets/admin_token)
node tools/admin.mjs queue                 # open reports, oldest first
node tools/admin.mjs show <profile_id>
node tools/admin.mjs rename <receipt> "offensive name"
node tools/admin.mjs suspend <receipt> 72 "harassment"
node tools/admin.mjs dismiss <receipt>
node tools/admin.mjs unsuspend <profile_id>
node tools/admin.mjs reserve <name>
node tools/admin.mjs audit 50
```

Every action is written to the audit log. Deleting a profile removes its
identity link, names, blocks and profile row (Final: and its friend set,
presence and invites). The player's own reports stay
in the queue for moderators, without the reporter's link. Open reports
against the deleted profile are closed as "profile deleted".

## API (summary)

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /v1/health`, `GET /v1/config` | — | Liveness; support/privacy links and minimum build |
| `POST /v1/auth/gamecenter` | Game Center signature | Sign in (creates the profile on first use) |
| `POST /v1/auth/signout` | session | Revoke this session |
| `GET /v1/me`, `DELETE /v1/me` | session (delete: signed in < 10 min ago, `{"confirm":"DELETE"}`) | Profile; delete profile |
| `POST /v1/me/name`, `POST /v1/names/check` | session | Set or check a display name |
| `PUT /v1/me/appearance` | session | Runner look (schema 2 keys) |
| `GET/POST /v1/blocks`, `DELETE /v1/blocks/:id` | session | Block list |
| `POST /v1/reports` | session | Report a player (receipt returned) |
| `POST /v1/chat/check` | session (room member) | V6: check a typed message; returns the approved text and its signed token, or the reason it was refused |
| `POST /v1/reports/message` | session | V6: report a typed message (the signed token is the evidence) |
| `POST /v1/rooms` | session | Create a party (code, host binding) |
| `GET /v1/rooms/:code` | session | Room state |
| `POST /v1/rooms/:code/join` | session | Reserve a slot and get an admission token |
| `POST /v1/rooms/:code/heartbeat` | host session | Keep alive, report state and connected players |
| `POST /v1/rooms/:code/leave`, `/kick`, `DELETE /v1/rooms/:code` | session / host | Leave, remove, close |
| `/v1/admin/*` | `ADMIN_TOKEN` | Reports, profiles, actions, reserved names, audit |
| `GET /v1/wallet` | session | V6: Coins, debt, revision, appAccountToken (derived per Game Center player; `null` without `APP_ACCOUNT_TOKEN_KEY`), entitlements, Season progress/claims, recent round settlements |
| `POST /v1/wallet/spend` | session | V6: buy a Coin item or Season Premium (`item_id`, `price`, `idempotency_key`): atomic debit + entitlement |
| `GET /v1/shop/offers` | none | Pass 8: the service's clock and the Shop's rotating offers on sale now and in the next 72 h (`src/offers.js`); a rotating skin's spend must name an active `offer_id` (checked on this clock at acceptance, `409 offer_changed` otherwise). FINAL_RELEASE_SWEEP: after the written schedule the rule continues from the catalogue's cycle (same id form), so there are always four offers |
| `POST /v1/wallet/apple` | session | V6: deliver a StoreKit 2 transaction (`jws`) once; refunds/revocations. FINAL_RELEASE_SWEEP: a verified transaction of the other App Store environment answers `409 sandbox_purchase` (production deployment) / `production_purchase` (sandbox deployment), recording nothing |
| `POST /v1/wallet/legacy-import` | session | V6: the one-time, bounded import of a pre-V6 device balance (sandbox deployment only; production answers `409 legacy_not_available`) |
| `POST /v1/season/:id/claim` | session | V6: claim Season rewards (idempotent: a cell once, Coins once, an owned item `already_owned`). Pass 9 (100 tiers): `{claims: [{tier, track, reward?}]}`, up to every cell of the table; `reward` names what the game showed (`coins:75`, an item id) and a cell whose reward differs is not granted (`reward_changed`); the reply has `claimed` (`result`, `reward`) and `skipped` (`no_reward`, `already_claimed`, `locked`, `premium_required`, `reward_changed`); the snapshot's season has `tiers` (the last tier this service grants) and `tier` |
| `POST /v1/rounds`, `POST /v1/rounds/:id/report` | room host | V6: register a round's admitted players; report its result (bounds-checked) |
| `POST /v1/rounds/:id/ack`, `GET /v1/rounds/:id/me` | session | V6: confirm the row your game received; settlement status (Pass 8: with the round's challenge result) |
| `PUT /v1/friends`, `DELETE /v1/friends` | session | Final: replace this player's friend set (`ids`: teamPlayerIDs of authorised Game Center friends, ≤ 500; only keyed hashes are kept); forget it (with presence and invites) |
| `GET /v1/friends/presence` | session | Final: mutual friends only, keyed by their teamPlayerID: verified name, profile ID (report/block), `status` online / lobby / match / offline, `in_your_party`, `invited`, `can_invite`, `why` |
| `POST /v1/presence`, `DELETE /v1/presence` | session | Final: heartbeat `{instance, seq, state, room?, protocol, build}` (a lobby counts only for a room you're a verified member of; the newest launch wins; replies with waiting invites); clear this launch's row |
| `POST /v1/invites`, `GET /v1/invites` | session | Final: invite a mutual friend who is playing into the party you're a connected member of (rate limited per inviter and per pair, de-duplicated, 5-minute expiry); invites waiting for you |
| `POST /v1/invites/:id/accept`, `/decline` | session (invitee) | Final: accept re-checks friendship, blocks, removal, room state, capacity and version, then returns the room `code` for the normal join; decline is recorded |
| `GET /v1/challenges` | session | Pass 8: the daily/weekly challenges (also in every wallet snapshot); progress and bonus Season XP come only from round settlement |
| `POST /v1/appstore/notifications` | Apple-signed | V6: App Store Server Notifications V2 (refunds, revocations) |
| `GET /v1/admin/wallets/:id`, `POST …/adjust` | `ADMIN_TOKEN` | V6: wallet, ledger and App Store rows; support grants / forgive debt |

V6 commerce (wallet, ledger, App Store verification, Season 1, round
settlement), Pass 8 challenges (`src/challenges.js`, migration
`0004_challenges.sql`, ECONOMY.md §10) and the Pass 9 Season 1 extension to
100 tiers (migration `0005_season_100.sql`, ECONOMY.md §4,
[docs/pass9/season.md](../docs/pass9/season.md)): see [docs/ECONOMY.md](../docs/ECONOMY.md) and
[docs/COMMERCE_SETUP.md](../docs/COMMERCE_SETUP.md). Vars: `APPLE_ENVIRONMENT`
(`Sandbox` for the default/TestFlight deployment, `Production` in
`[env.production]`). Secret `APP_ACCOUNT_TOKEN_KEY` (identical on both).
Optional secrets: `ASC_IAP_KEY_ID`, `ASC_IAP_ISSUER_ID`,
`ASC_IAP_PRIVATE_KEY` (App Store Server API), uploaded by `deploy.sh` from
`.secrets/` when present. The environment routing, the App Review fallback
and their tests: [docs/final/commerce.md](../docs/final/commerce.md),
`test/environments.test.mjs`.

## Why parties can't form without their host

Game Center matchmaking for a party code puts everyone in the same
`playerGroup`, which is derived from the code. The host requests the match
with `playerAttributes = 0xFFFF0000` and joiners with `0x0000FFFF`. Game
Center only completes a match when its players' attributes OR to
`0xFFFFFFFF`, so two joiners can never form a match on their own: every match
contains the code's host.

The service decides who may join. The joiner's admission token names the
host's Game Center player. Under protocol 4 the client binds to that host
and ignores host-only messages from anyone else. The host checks the token's
signature, audience, expiry, room code and joiner, and accepts each token
only once.
