# Final release sweep (version 2.0)

The last pass before the App Store: a lighter lobby, a large rotatable
Season Pass preview with a cleaner hierarchy, Friends with real in-game
status and lobby invitations, commerce that works for TestFlight, App
Review and App Store customers with their money kept apart, a release lane
that produces an App Store-eligible build, and an App Store package and
readiness audit. It builds on 1.9 (9) (commit `e3c2cd6`; App Store Connect
build `8a207a62-69de-4c34-95bd-a90e4c8504ec`, `VALID`, `INTERNAL_ONLY`).

Everything was built and checked on desktop Linux (headless Godot 4.7.2,
the Mobile renderer on llvmpipe for pictures, the service's Node tests) and
in CI on macOS. **No iPhone or iPad, no deployed service and no App Store
product was available**, so nothing here claims a device, live-service or
real-purchase result. What each of those still needs is listed in
"Unresolved blockers" and in [APP_STORE_READINESS.md](APP_STORE_READINESS.md).

Per-area notes:
- [final/lobby.md](final/lobby.md): the lighter lobby.
- [final/season.md](final/season.md): the Season Pass preview and hierarchy.
- [final/friends.md](final/friends.md): Friends, presence and invitations.
- [final/commerce.md](final/commerce.md): environments, the Shop and purchase flows.
- [APP_STORE.md](APP_STORE.md): the submission package.
- [APP_STORE_READINESS.md](APP_STORE_READINESS.md): requirement by requirement.

## What changed (by area)

- **Lobby lighting** ([final/lobby.md](final/lobby.md)): the dorm is a
  little lighter and friendlier at night with the same lights and cost
  (ambient 0.55 → 0.62, cool fill 0.22 → 0.32, lamps up slightly, walls
  lifted); the right-hand menu shade no longer dims the characters; lines
  drawn on the room get a soft halo. Home room mean luma 88 → 97,
  near-black pixels 17 % → 10 %, the runner +6 luma, nothing clipped;
  every line on the room at 4.97:1 contrast or better (was 3.18).
- **Season Pass** ([final/season.md](final/season.md)): the selected reward
  stands on the large dorm stage (about 2.9× the old preview's height on
  phones) with drag, Turn, Reset and right-stick rotation that never fights
  an automatic sway (none under Reduced Motion); a compact season header,
  one status line when claiming is unavailable, requirements from the
  account ("15,300 XP to unlock", "Needs Premium · 1,500 Coins"), one fixed
  action (Claim, View Premium, Equip, View in Locker). Previewing never
  saves; every exit restores the saved look.
- **Friends** ([final/friends.md](final/friends.md)): a Friends panel on
  Home, Play with Friends and in the party shows which Game Center friends
  are online, in a party or in a round, but only mutual friends who both
  play and allowed friends access (keyed hashes on the service; presence
  expires 60 s after the last heartbeat); Invite sends a real invitation to
  your current party, the friend accepts and joins through the same
  admission as a typed code. Party codes and Apple's invite sheet stay.
- **Commerce** ([final/commerce.md](final/commerce.md)): one build routes
  to the sandbox (TestFlight, App Review) or production (App Store) service
  by the App Store receipt kind and moves itself to the sandbox when
  production refuses a sandbox purchase; the appAccountToken is derived
  from the verified Game Center ID and is the same on both; each deployment
  credits only its own Apple environment. Shop: Hide owned, App Store
  labels, both Apple outfits and all six Coin packs always reachable, offers
  that never run out (written to 2027-04-06, then the rule's cycle).
- **Release lane** (this file): an App Store-eligible upload option with an
  audience check, version 2.0, config files that actually ship, privacy and
  support links in every build, the final privacy manifest, Game Center
  matchmaking failures shown to the player, service requests off the main
  thread.

## Defect register (release lane and integration)

Each entry: symptom → reproduction → cause → fix → evidence. The per-area
registers are in each area's notes.

| # | Symptom | Reproduction | Cause | Fix | Evidence |
|---|---|---|---|---|---|
| R1 | 1.9 (9) can't be submitted to the App Store | App Store Connect lists it as `INTERNAL_ONLY` | `ios.yml` hard-coded `INTERNAL_ONLY: "true"` and `build_ios.sh` defaulted `testFlightInternalTestingOnly` to true | A `distribution` workflow input (`internal_only` default, `app_store`); `build_ios.sh` refuses a signed export unless `INTERNAL_ONLY` is explicitly `true` or `false`; after processing, `asc.py audience` checks the audience Apple recorded and fails the run on a mismatch | workflow and script diff; run #145: Apple recorded `APP_STORE_ELIGIBLE` for 2.0 (10) and the audience check passed |
| R2 | An upload run could end green when Apple rejected the build | Read the "Wait for App Store Connect processing" step | The step ended with `exit 0` whatever `asc.py wait` returned | FAILED/INVALID fails the job; still-processing is a warning that says "uploaded, not yet available" | workflow diff |
| R3 | A read-only `iap=list` run was cancelled | Run #127 cancelled by the next push | Product runs shared the cancellable "build" concurrency group | Product (`iap`) and status runs have their own, non-cancelling groups | run #127; workflow diff |
| R4 | **The game service could never turn on in an iOS build** | A local `--export-pack "iOS"` of 1.9's code: `config/service.cfg` is not in the pack | `.cfg` files aren't Godot resources; the preset's `include_filter` was empty, so the export dropped them. Filling in the service URL and rebuilding would still have shipped a game with the service off | `include_filter="config/*.cfg"`; `export_ios.sh` fails the export if the pack lacks `config/service.cfg`; `test_release_config` | packs before/after: `config/service.cfg` 0 → 1 occurrence; run #145: "config files in the game data: OK" |
| R5 | The privacy manifest would declare nothing once the service has two endpoints, and missed the Friends data | Read `export_ios.sh` | It looked only at `url=` and the pre-Friends data types | Declares when any endpoint is set; adds Contacts (friends list as keyed hashes) and Product Interaction (in-game status); portable `sed -E` for macOS | script diff; APP_STORE.md App Privacy table |
| R6 | Privacy policy and Support links absent whenever the service is off or unreachable | Settings › Privacy without a service | Links came only from the service's `/v1/config` | `config/links.cfg` (owner-filled, https only, ships in every build) with the service as fallback (`AppLinks`) | `test_release_config` |
| R7 | "Diagnostics (beta)" in the release Settings, "beta diagnostics" in the shared summary | Settings | Beta-era wording | "Diagnostics" | `test_v7_screens` |
| R8 | GitHub's Linux runners cancelled every queued job after 15 minutes from about 19:54 UTC on 2026-10-05 | Runs #126–#131 | Outside the repository (runner assignment); no job output | Retried; runs from #132 on ran normally | run list |
| R9 | The new pack check failed a good export on CI (push run #139: "config/service.cfg is missing") | Locally: `strings pack | grep -q config/service.cfg` under `pipefail` → exit 141 on a pack that contains it | `grep -q` exits at the first match, `strings` dies of SIGPIPE, and `pipefail` turns that into failure (run #138 passed only because the match came late) | Count matches (`grep -c`, whole stream) instead | same pack: old check "missing" (rc 141), new check count 1 |
| R10 | A 16-character outfit name was cut off on the results team card ("Marigold Moo…") | `tools/capture_v7_screens.sh OUT p14`: results and final standings report `trimmed label 'Marigold Moonpup'` | The portrait card shrank the name to 18 px and then truncated it with an ellipsis | `UIKit.fit_text(..., wrap_last=true)`: below the smallest size the name wraps onto a second line instead | v7 sweep at p14 and SE: 0 layout issues on both results screens |

## Release candidate

**2.0 (10)**, App Store Connect build `1730ad62-0823-49a6-a534-1e7bb79e3935`,
from commit `66e7575`, uploaded 2026-10-06 08:02:44 UTC by run #145
(`distribution=app_store`). Apple's API, read by the run at 08:20 UTC:
processing **`VALID`**, audience **`APP_STORE_ELIGIBLE`**, internal
`IN_BETA_TESTING` for the existing internal group, What to Test set.
CI gate 561 tests, 0 failures; the same commit passed the full suite and the
service tests locally (TEST_REPORT FRS.4–FRS.5).

It is **provisional**: the service is off and no App Store product exists,
so it is not the launch build and shouldn't be submitted. Nothing was
submitted, released, priced or bought, and no tester or group was added.

## Unresolved blockers

### Before the App Store submission (owner; [OWNER_SETUP_GUIDE.md](OWNER_SETUP_GUIDE.md))

These keep the 2.0 candidate **provisional**. The code for each is done
and tested on desktop; the missing piece is an account action, a deployed
service or a device.

| # | Blocker | Why it blocks | Guide step |
|---|---|---|---|
| U1 | The game service isn't deployed; `game/config/service.cfg` is empty | Coins, purchases, Season rewards, challenges, rotating offers, verified names, typed chat, reports and Friends status all show as unavailable; App Review would find the purchases unusable | C |
| U2 | The eight App Store products don't exist (status run #132: 8 planned, 0 present) | Nothing can be bought; the first purchase of each type must be submitted with a version | B, G |
| U3 | Paid Apps Agreement, tax and banking (not readable by the API key) | StoreKit returns no products without it | A |
| U4 | No privacy policy or support URL (`config/links.cfg` and the service variables are empty) | Required in the app and on the version page | C.8, F |
| U5 | Nothing verified on a device or with Apple's sandbox: purchases, restore, Premium, claims, Friends between two accounts, an online round between two devices, Delete Game Profile on the live service | Only a device, a sandbox account and the deployed service can show them | E |
| U6 | Content rights: written permission from the two people Record Breaker and Dr. Doom are based on; mureka.ai's terms for both music loops; whether to keep the "Dr. Doom" label | Guideline 5.2 (intellectual property, likeness) | F |
| U7 | The version page: App Privacy answers, age rating, screenshots, review contact, copyright | Only the account holder can enter them | F |

### Known, not blocking

- **Device-only checks** (APP_STORE_READINESS D1–D5): frame rate and heat,
  lighting on Metal (the desktop renders needed `GALLIUM_OVERRIDE_CPU_CAPS=avx`
  to light characters correctly, [final/lobby.md](final/lobby.md)), the
  Season Pass drag feel, the native Friends permission prompt and
  authorization values, `recipients` pre-selection in Apple's invite sheet,
  GKError codes.
- **Parties don't cross service deployments**: a TestFlight player and an
  App Store player (or a review device before and after its first purchase)
  are in different economies. Written into the review notes.
- **Promoted in-app purchases** aren't handled: keep promotion off.
- **Refund reversals** (`REFUND_REVERSED`) aren't re-granted automatically;
  support can grant through the admin API.
- **Service capacity**: Friends presence is about 4,300 writes per playing
  user per day; the free Cloudflare tiers cover a few dozen concurrent
  players. The owner sizes the plan.
- **The offer schedule** is written to 2027-04-06 and then repeats the
  rule's cycle; extend it with `tools/make_offer_schedule.py` when you want
  new rotations.
- **Turning a model**: the Season Pass has drag, Turn, Reset and the right
  stick; the Shop and the Locker keep their drag-to-turn without Turn and
  Reset buttons. Left as is for this release (both work; changing their
  input this late was the larger risk).
- **No dSYMs** for the four plugin frameworks (crashes inside them won't be
  symbolicated).
