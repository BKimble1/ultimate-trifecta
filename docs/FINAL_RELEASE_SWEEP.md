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

## Defect register (release lane and integration)

Each entry: symptom → reproduction → cause → fix → evidence. The per-area
registers are in each area's notes.

| # | Symptom | Reproduction | Cause | Fix | Evidence |
|---|---|---|---|---|---|
| R1 | 1.9 (9) can't be submitted to the App Store | App Store Connect lists it as `INTERNAL_ONLY` | `ios.yml` hard-coded `INTERNAL_ONLY: "true"` and `build_ios.sh` defaulted `testFlightInternalTestingOnly` to true | A `distribution` workflow input (`internal_only` default, `app_store`); `build_ios.sh` refuses a signed export unless `INTERNAL_ONLY` is explicitly `true` or `false`; after processing, `asc.py audience` checks the audience Apple recorded and fails the run on a mismatch | workflow and script diff; the 2.0 upload run's audience line |
| R2 | An upload run could end green when Apple rejected the build | Read the "Wait for App Store Connect processing" step | The step ended with `exit 0` whatever `asc.py wait` returned | FAILED/INVALID fails the job; still-processing is a warning that says "uploaded, not yet available" | workflow diff |
| R3 | A read-only `iap=list` run was cancelled | Run #127 cancelled by the next push | Product runs shared the cancellable "build" concurrency group | Product (`iap`) and status runs have their own, non-cancelling groups | run #127; workflow diff |
| R4 | **The game service could never turn on in an iOS build** | A local `--export-pack "iOS"` of 1.9's code: `config/service.cfg` is not in the pack | `.cfg` files aren't Godot resources; the preset's `include_filter` was empty, so the export dropped them. Filling in the service URL and rebuilding would still have shipped a game with the service off | `include_filter="config/*.cfg"`; `export_ios.sh` fails the export if the pack lacks `config/service.cfg`; `test_release_config` | packs before/after: `config/service.cfg` 0 → 1 occurrence |
| R5 | The privacy manifest would declare nothing once the service has two endpoints, and missed the Friends data | Read `export_ios.sh` | It looked only at `url=` and the pre-Friends data types | Declares when any endpoint is set; adds Contacts (friends list as keyed hashes) and Product Interaction (in-game status); portable `sed -E` for macOS | script diff; APP_STORE.md App Privacy table |
| R6 | Privacy policy and Support links absent whenever the service is off or unreachable | Settings › Privacy without a service | Links came only from the service's `/v1/config` | `config/links.cfg` (owner-filled, https only, ships in every build) with the service as fallback (`AppLinks`) | `test_release_config` |
| R7 | "Diagnostics (beta)" in the release Settings, "beta diagnostics" in the shared summary | Settings | Beta-era wording | "Diagnostics" | `test_v7_screens` |
| R8 | GitHub's Linux runners cancelled every queued job after 15 minutes from about 19:54 UTC on 2026-10-05 | Runs #126–#131 | Outside the repository (runner assignment); no job output | Retried; see the release section | run list |

## Unresolved blockers

_Completed at the end of the sweep._
