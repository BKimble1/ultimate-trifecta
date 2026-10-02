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

Nothing is mocked in the release path. If `game/config/service.cfg` has no
URL, the service is off: practice and local play still work, names stay on
the device, and the game never claims a verified profile.

## Status

**The service is not deployed.** Deploying it needs the owner's Cloudflare
account. Workers and D1 have free tiers, and these scripts create no paid
resources. The code, migrations, tests and deployment scripts are complete.
`npm test` runs the whole API against an in-memory D1 (`node:sqlite`) with a
per-run test certificate. That proves the logic, not a live deployment.

## Deploy (owner, about 10 minutes)

Prerequisites: Node.js 22.13+ and a Cloudflare account.

```sh
cd service
npm test                                  # all tests must pass
npx wrangler login                        # or export CLOUDFLARE_API_TOKEN
npx wrangler d1 create trifecta           # copy the printed database_id ...
#   ... into wrangler.toml -> [[d1_databases]] database_id
scripts/gen_keys.sh                       # writes service/.secrets/ (git-ignored)
#   prints the admission PUBLIC key -> game/config/service.cfg admission_public_key
scripts/deploy.sh                         # migrations, secrets, deploy
curl -s https://trifecta-service.<your-subdomain>.workers.dev/v1/health
```

Then set the game's `game/config/service.cfg`. The public key is not secret.

```ini
[service]
url="https://trifecta-service.<your-subdomain>.workers.dev"
admission_public_key="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
```

Keep `service/.secrets/` out of git and out of chat. `deploy.sh` reads it
and uploads the secrets with `wrangler secret put`.

### Variables (`wrangler.toml` → `[vars]`)

| Name | Meaning |
|---|---|
| `ENVIRONMENT` | Label bound into tokens. Use `production` for TestFlight/App Store builds (Game Center has no separate sandbox for them). |
| `BUNDLE_ID` | Must equal the app's bundle ID (`com.idlery.ultimatetrifecta`). Signatures for other bundles are rejected. |
| `GC_KEY_HOSTS` | Hosts allowed for Apple's public-key URL. Keep `static.gc.apple.com`. |
| `MIN_CLIENT_BUILD` | Older clients are told to update before online play (`App.build_number()`, e.g. 1.1 → 101). |
| `SUPPORT_EMAIL`, `SUPPORT_URL`, `PRIVACY_URL` | The owner's **real, monitored** contact and policy links. Leave them empty until they exist; the game shows no link rather than a placeholder. |

### Secrets (`wrangler secret put`, done by `deploy.sh`)

`SESSION_KEY` (HMAC for session tokens), `ADMIN_TOKEN` (moderation API), and
`ADMISSION_PRIVATE_KEY` (PKCS#8 PEM, signs admission tokens).

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
identity link, names, blocks and profile row. The player's own reports stay
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
