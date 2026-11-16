# 2.2: Season 1 · Winter Break (final pass before the App Store)

What changed in 2.2, how it was checked, and what still needs the owner.
Screenshots are desktop renders (Mobile renderer on llvmpipe under Xvfb, at
iPhone point sizes and safe areas), not device captures.

## 1. The holiday dorm (`game/src/view/holiday_decor.gd`)

The dorm common room behind Home, the Locker, the Shop, the Season Pass and
the party room is dressed for Season 1:

- a decorated tree in the back-right corner, in front of the window's right
  curtain: five tiers of zig-zag branches with drooping tips and a dark
  underside (the home camera sits below the upper tiers), a red tree skirt,
  41 glossy baubles, 104 fairy lights spiralling up it and a gold star;
- wrapped presents under it (seven boxes, ribbons both ways and bows);
- a wreath with berries and a bow where the yellow poster hung, a garland
  swagged along the window head with bows at its pins;
- twinkling multicolour string lights along the back wall (either side of
  the window, low enough for the home framing, and a higher run for the
  party framing) and the left wall;
- snow on the rooftops, trees and lawn outside the window, and snow falling
  past it (150 CPU particles, seen only through the opening).

Cost: the solid pieces join the room's one merged mesh (dorm shader); the
bulbs and star are one more mesh (`festive_lights.gdshader`, unshaded,
each bulb breathing at its own phase carried in its UV); one small omni
light in the tree plus two additive light pools. Reduced Motion: the bulbs
and tree light hold steady and no snow falls. The armchair moved a step
right (`DormStage.ARMCHAIR`) and the tree and presents are a walk-around
obstacle (`HubRoom.CIRCLES`). After the season set `HolidayDecor.ENABLED`
to false: the year-round poster and string lights come back.

| | |
|---|---|
| Home, before (2.1) | `media/p14_home_before.jpg` |
| Home, 2.2 (iPhone 14, 844×390 pt) | `media/p14_home.jpg` |
| Home, 2.2 (iPhone SE, 667×375 pt) | `media/se_home.jpg` |
| Party room, 4 players | `media/p14_lobby_4p.jpg` |
| Season Pass (test service adapter, Premium owned) | `media/p14_season_pass.jpg` |

## 2. Season 1 · Winter Break

- The season's name is "Winter Break" (`catalogue.json` → `seasons.s1.name`,
  the Premium item's name and blurb; the service copy regenerated with
  `service/tools/sync_catalogue.mjs`). Tiers, XP, rewards, item ids and
  claim keys are unchanged; the service tests pass (93).
- **Home** has a Season card (`SeasonCard`; since the second pass it sits
  in the party column of the home lobby, section 9): the
  snowflake, "SEASON 1 · WINTER BREAK", your tier, a bar of Season XP to
  the next tier, and "N to claim" or "Premium"; tap opens the Season Pass.
  With no game service in the build it says "Play online rounds" instead
  of numbers that can't move. It fits the iPhone SE's right column.
- **Season Pass:** the snowflake beside the season name; Premium reward
  cells are a clearly gold lane (warmer card, a gold rim on top).

## 3. The Night Watch starts at GO

`runner_head_start_s` is 0 (it was 6): the Night Watch leaves the Grounds
Shed at GO, together with the runners. The guided tutorial keeps its 30 s
hold (`patrol_release_extra_s`). The HUD's head-start lines only show while
a hold is running, so they no longer appear in ordinary rounds.

Seeded full bot rounds on Moonbrook College (`game/tools/p9_balance.gd`
with `BAL_MAP=classic`, 16 seeds per team size, the same seeds, halls and
waters for both; data in `data/`, tables in `data/balance_summary.md`):

| Night Watch | 6 s head start: runner wins | Together: runner wins | 1st capture |
|---|---|---|---|
| 1 | 16/16 | 16/16 | 65 s → 62 s |
| 2 (default) | 14/16 | 14/16 | 46 s → 40 s |
| 3 | 7/16 | 6/16 | 45 s → 42 s |

The outcome doesn't move (well inside the intervals); the first catch
comes a few seconds sooner. These are bots, not people: the default
(2 Night Watch) favours runners in bot play as it did in 1.9–2.1; re-check
with people on phones before tuning speeds.

## 4. Lakeside Campus: Coming soon

See `docs/maps/README.md` (top). The chooser keeps its card with the
preview and outline, a lock, a COMING SOON ribbon and tag; a tap says
"Lakeside Campus is coming soon. Stay tuned!" and keeps Moonbrook College
selected (`media/p14_map_coming_soon.jpg`). Parties, practice and every
saved choice play Moonbrook College.

## 5. Network

Protocol 11: no message changes, but the round's rules (release at GO),
the playable map and the party room's obstacles differ, so 2.1 and 2.2
refuse each other at join ("Update the game to join."). A four-process
UDP soak (host + 3 clients, 60 ms ± 10 ms, 3 % loss, two rounds) is in
`data/` when it completed.

## 6. Sweep notes

- CI's full suite caught one real layout bug: with Moonbrook College as
  the map, the party room's settings row ("Moonbrook College · 3 rounds ·
  …") was a point wider than the safe area on iPhone SE and iPad, pushing
  the roster and Start past it. The chip now uses the short name
  ("Moonbrook"). Full suite after the fixes: 585 tests, 359,610 checks,
  0 failures (local and CI).

- Rendered desktop runs log "Too many instances using shader instance
  variables… Maximum items supported by this hardware is: 4096". That cap
  is llvmpipe's 64 KB uniform buffer; Godot 4.7's Metal driver reports the
  device's maximum buffer length for the same limit, so an iPhone gets the
  project's 65,536 slots. Not a device glitch.
- A route test can rewrite `config/route_bot_times.json` (Lakeside timings)
  when its measured times drift; the file was restored, not changed.

## 7. Build lane: the Game Center/StoreKit plugin

The first 2.2 CI run stopped at "Fetch pinned plugins": upstream
GodotApplePlugins deleted its `build-<sha>` releases and tags after 2.1, so
the pinned asset answers 404 and no iOS build could be exported. The pinned
commit (`bfade13`, 2026-09-02) still exists, so `tools/fetch_deps.sh` now
builds exactly that commit from source on macOS with upstream's own release
recipe (two `make split-build` passes, `make split-dist`, unsigned),
verified by commit hash. CI caches the result by commit. Same plugin
version as 1.6–2.1; nothing in the game's use of it changed.

## 8. What 2.2 still needs from the owner

Purchases, Coins, Season XP and rewards, challenges and Friends status run
through the game service, which still isn't deployed, and the eight App
Store products and the Paid Apps Agreement don't exist yet. Until then the
build says so honestly and nothing can be bought. The order is in
`docs/OWNER_SETUP_GUIDE.md` (A agreements, B products, C service, D the
configured build, E sandbox test, F version page, G submit).

---

# Second pass: the lobby is home, Quick Match, chat, Rankings

Asked for after the first 2.2 build: typed party chat with bad words
bleeped, clean names, loading-screen tips, the stuck-at-GO glitch, a
shinier UI, 30-day leaderboards with run stats and a Season Champion
poster, and one home where you are always in your lobby with a playlist
picker instead of a "Play with Friends" button.

## 9. Home is your party lobby

| | |
|---|---|
| Home (a party of one, Quick Match selected) | `media/v22_home.jpg` |
| The playlist picker | `media/v22_playlists.jpg` |

- Opening the app puts you in your own party lobby in the holiday dorm
  (`App.goto_title` starts a party of one on `SoloTransport`): walk around,
  emote, change your look, Shop and Season Pass, all without a separate
  "online lobby". Friends (online friends, invites, **Add friends** =
  Game Center's friend-request sheet, "Join with a code"), Share and the
  party list are always there.
- Inviting a friend or sharing the party opens it on Game Center in place
  (`App.open_party`): the same room, settings and look; friends land next
  to you.
- One **PLAY** button and a **playlist** card (tap Change):
  **Quick Match** (random players online, bots fill the empty seats),
  **Party vs Bots** (your map and rounds) and **Practice** (offline, pick
  your role). With friends in the party, PLAY starts the party's round.
- **Quick Match** (`Social.quick_match_start`): Game Center automatch in a
  per-protocol player group; every device elects the lowest player id as
  host; the round starts by itself 8 s after the match forms, bots in
  empty seats; nobody in 25 s (or Game Center unavailable) and it starts
  with bots. After the round everyone goes back to their own lobby.
- **Rankings** (gold, top right) and Settings sit in the top bar.

## 10. Party chat, bleeped

| | |
|---|---|
| A bubble over the speaker's head | `media/v22_chat_bubble.jpg` |
| The chat drawer | `media/v22_chat_drawer.jpg` |

Typed chat works in any party (`ChatRules.bleep`): profanity, sexual words
and slurs become `#%&*` whatever the disguise (l33t, s-p-a-c-e-d,
stretched, doubled, split across words); threats, links, handles, phone
numbers and spam are refused outright. The sender, the host and every
receiver run the same filter (`SocialProto.Kind.MOD_TEXT`), so a modified
client can't push words past it. Report message / Report player / Block
stay on every message (Guideline 1.2), with "Report by email" when the
game service isn't reachable (needs `support_email` in `config/links.cfg`).
Names: typed names go through the full name policy (`NameRules`, reserved
names included); a rejected name falls back to a generated one.

## 11. Round start: no more frozen thumb

The fading loading screen's layout containers (and the role card) passed
touches up their own branch, so a thumb already on the stick was captured
and the runner didn't move at GO. Now the closing screen ignores input
(`UIKit.ignore_input_tree`), the touch surface adopts a finger that is
already down in the stick zone (`TouchSurface._input`), and the role card
is a compact banner under the top bar that waits for the loading screen to
go. Measured with `src/dev/start_probe.gd` (a held thumb from before GO):
old build never moved; 2.2 moves 46 ms after GO.

| | |
|---|---|
| Loading with a rotating tip | `media/v22_loading_tip.jpg` |
| The first frames of the round | `media/v22_round_start.jpg` |

Tips (`LoadingTips`) change every 5.5 s: role strategy, controller and
keyboard controls (for the device in use) and general play.

## 12. Rankings, run stats and the Season Champion

| | |
|---|---|
| Rankings (development sample rows) | `media/v22_rankings.jpg` |
| After a round: your run, best and Season Points | `media/v22_results_run.jpg` |
| The Season Champion poster (on launch, at most every 20 h) | `media/v22_champion_poster.jpg` |
| Official Rules (Guideline 5.3) | `media/v22_rules.jpg` |

- Two Game Center leaderboards, **created in App Store Connect** (workflow
  `iap=gc-create`, run #201): `ut.season_points` (best total, " pts") and
  `ut.fastest_run` (centiseconds, lowest first), recurring every 30 days
  (`PT720H`, Game Center's longest) from **2026-12-01**, Season 1 · Winter
  Break. App Store Connect refuses a recurring board that starts in the
  past, so the November preseason has no boards: its rounds count toward
  your own stats only, and Rankings says when the boards open.
- Season Points (`Rankings.round_points`): 10 played, 15 team win, 5 per
  splash (max 3), 10 home, 5 first home, 10 per distinct tag (max 3); at
  most 70 a round and 40 counted rounds a day; only online rounds with at
  least one other real player count. No divisions, no hidden rating, no
  gameplay rewards.
- The results card shows your run time, a NEW PERSONAL BEST chip, Season
  Points with the breakdown, or why the round didn't count.
- The Season Champion: #1 in Season Points designs (concept + name) a
  tier 100 skin of a following Season Pass. The poster pops up on launch
  at most every 20 h (never during the tutorial), X to close, and sits
  small on Rankings. Rules in the game and in `CONTEST_RULES.md`.
  (The results capture uses a practice fixture marked as an online round
  to show the points; a real practice round says it doesn't count.)

## 13. Candy UI

Solid buttons got a darker 3D base, a gloss band and a label shadow, and
sink when pressed; gold and teal are punchier (`UIKit.Face.shine`). All
screens use it, so every button changed together.

## 14. Checks for the second pass

- Full headless suite: see the commit message of the final 2.2 commit.
- New tests: `test_rankings` (points, caps, 30-day seasons, preseason,
  Guideline 5.3 statements), `test_chat` (bleeping in every disguise,
  device chat end to end), `test_loading::test_loading_tips_rotate`,
  `test_trust` (typed names), `test_pause_input` (stale fingers).
- Not verified on a device: Quick Match between two phones, Game Center
  leaderboards (they open on 1 Dec), the friend-request sheet. These need
  TestFlight testers; see `docs/testflight/what_to_test.txt`.

