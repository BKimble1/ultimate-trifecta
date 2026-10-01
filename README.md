# Ultimate Trifecta

A playful third-person campus chase at a fictional 3:00 a.m. Runners in pajamas
and mascot suits splash into three marked waters and race home to the dorm. Two
Night Watch players hunt them on foot and in golf carts.

- **Engine:** Godot 4.7.2-stable (GDScript, Mobile renderer, Jolt physics).
- **Platform:** iOS 17+ for iPhone and iPad, landscape.
- **Online play:** private rooms over Apple Game Center. One player's device is the host and runs the authoritative simulation.

| Doc | What it covers |
|---|---|
| [RULES.md](RULES.md) | The implemented Trifecta Chase rules and tuning |
| [TEST_REPORT.md](TEST_REPORT.md) | What was tested, how, and what is still unverified |
| [TESTFLIGHT_RELEASE.md](TESTFLIGHT_RELEASE.md) | Release status, signing lane, owner handoff and beta notes |
| [ASSET_LICENSES.md](ASSET_LICENSES.md) | Where every asset and dependency comes from |

## What's in V1

- **Main mode, Trifecta Chase:** a 6-runner vs 2-Night-Watch round on one campus with six waters. Every round picks three shared targets, and four runners home wins. Both roles are playable.
- **Online private rooms:** up to eight humans.
  - Create a room and get a 5-character code; others join with the code over the internet through Game Center matchmaking.
  - You can also invite Game Center friends.
  - Empty slots are filled by bots labelled `Bot …`.
- **Solo practice:** the same rules, simulation and controls against bots, played as runner or Night Watch. There is also a guided tutorial round.
- **Lobby:** a 3D common room plus a static roster. It has ready-up, role preference, preset emotes, an outfit preview, mute, host remove, and invite or code sharing.
- **Full flow:** title → practice or online → lobby → role reveal → countdown → match → results → rematch or leave.
- **Controls:** touch (dynamic stick, drag camera, context buttons, cart gas and brake) and MFi/extended game controllers. Prompts switch when a controller connects or disconnects.
- **Persistence:** versioned local save with settings, outfit, level, coins, a small wardrobe, and separate online and practice stats. Each match pays rewards once, keyed by its match ID.

## Why Godot rather than Unity

The brief preferred Unity with Netcode and Relay. That stack could not be used here, for three reasons:
- **No access from the build environment.** The repository started empty, and the build environment could not reach Unity's download, CDN or package servers (`download.unity3d.com`, `public-cdn.cloud.unity3d.com` and `packages.unity.com` were refused).
- **Licensing.** The Unity Editor needs an activated license.
- **Paid hosting.** Unity Relay and Lobby need a Unity Cloud project, which this task was not allowed to set up as paid hosting.

What V1 uses instead:
- **Engine:** Godot 4.7.2, which is MIT-licensed and needs no account. It exports a native iOS Xcode project that builds with Xcode 26.
- **Online play:** Apple Game Center (`GKMatch` matchmaking and relay), reached through the MIT-licensed GodotApplePlugins. It is free, needs no server, and provides the friends and invites UI.
- **Netcode:** prediction, reconciliation, lag compensation, reconnection and lobby logic are implemented in this repository (`game/src/net`, `game/src/match`). They do not come from a package.

## Repository layout

```
game/                 Godot project (open game/project.godot)
  src/config/         RulesConfig: the single rule/balance source
  config/             rules_default.tres (tuning), route tables
  src/core|sim|bots/  deterministic simulation, rules logic, bots
  src/net/            protocol, NetSession (host/client), transports
  src/match/          MatchController (world, prediction, presentation)
  src/view|ui/        characters, camera, FX, HUD, touch, screens
  src/autoload/       Rules, Controls, Sfx, Social, Save, App
  assets/             shaders, audio, font, icon/splash
  tests/              headless rule/sim/network/route tests
tools/                fetch, test, soak, export, build, App Store Connect scripts
.github/workflows/    ios.yml: tests → iOS export → device archive → simulator → TestFlight
docs/                 test data, screenshots and recordings
```

## Setup

On Linux or macOS:

```sh
tools/fetch_godot.sh              # pinned Godot 4.7.2 editor into tools/.cache (add --templates for iOS export templates)
tools/run_tests.sh                # all headless tests (about 4 min; route test is slow)
tools/run_tests.sh test_rules     # one suite
tools/gd.sh --path game           # run the game on desktop (keyboard + mouse or controller)
```

Desktop keys are for testing only:

| Key | Action |
|---|---|
| WASD | Move |
| Mouse or IJKL | Camera |
| Space | Jump; press again in the air to dive |
| Shift | Sprint |
| F | Tag |
| E | Cart in or out |
| Q | Gadget |
| 1 to 4 | Emotes |
| Tab | Spectate next |
| Esc | Pause |

Development flags go after `--`:

```sh
tools/gd.sh --path game -- --autoplay=runner --local-bot          # bot-driven practice round
tools/gd.sh --path game -- --autoplay=tutorial --shots=/tmp/s     # screenshots every 4 s
tools/net_soak.sh 7 60 10 0.03 1                                  # 1 host + 7 UDP client processes with lag/jitter/loss
python3 tools/soak_summary.py docs/test-data/net_soak_7c_60ms_0.03 # soak reports as a table
```

Other automation flags:

| Flag | Effect |
|---|---|
| `--no-gamecenter` | Skips the Game Center sign-in sheet. Used for Simulator runs. |
| `--seed=N` | Fixes the match seed. |
| `--quit-after=S` | Quits after S seconds. |
| `--report=path` | Writes per-round JSON stats and prints status lines every 5 s. |

Release builds only act on these flags when they are passed on the command line, which a TestFlight install never does.

### iOS build

This needs macOS with Xcode 26 or later, since App Store uploads require the iOS 26 SDK.

```sh
tools/fetch_godot.sh --templates
tools/fetch_deps.sh               # pinned GodotApplePlugins (Game Center), sha256-checked
tools/export_ios.sh               # Xcode project into build/ios
tools/build_ios.sh device         # unsigned device archive (compile/link proof)
tools/build_ios.sh signed         # signed archive + export (needs App Store Connect API key)
```

The CI lane in `.github/workflows/ios.yml` runs the same steps on `macos-26`.
- Run it manually with `upload=true` to sign and upload to TestFlight.
- It needs four repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and `APPLE_TEAM_ID`.
- See [TESTFLIGHT_RELEASE.md](TESTFLIGHT_RELEASE.md) for details.

No credentials, keys or provisioning files belong in git; `.gitignore` excludes them.

## Online architecture (honest summary)

- **Host authority.** The room host's device runs the authoritative 60 Hz simulation. Clients send inputs only, never results.
- **Validation.** Stamps, finishes, tags, cart seats and gadgets are validated on the host.
- **Client smoothness.**
  - Clients predict their own movement with the same deterministic motor and reconcile against per-recipient snapshots (20 Hz).
  - Other players are interpolated.
  - Tags use bounded lag compensation (≤150 ms).
- **Trust limits.** A player host is **not** a dedicated server, and its results are **not** cheat-proof. That is acceptable for private rooms among friends; there are no rankings.
- **Host loss.** If the host leaves, the round ends for everyone, no rewards are granted for it, and clients return to the menu.
- **Disconnects and late joins.**
  - A disconnected player's slot is held for 20 s while a bot takes over, and a reconnect resumes the same progress.
  - Newcomers mid-round spectate until the next round.
- **Hosting cost.** Transport and matchmaking are Apple Game Center (`GKMatch`). There is no developer-run server and no hosting cost.
