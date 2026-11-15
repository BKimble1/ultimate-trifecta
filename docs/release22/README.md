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
- **Home** has a Season card above Play with Friends (`SeasonCard`): the
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

- Rendered desktop runs log "Too many instances using shader instance
  variables… Maximum items supported by this hardware is: 4096". That cap
  is llvmpipe's 64 KB uniform buffer; Godot 4.7's Metal driver reports the
  device's maximum buffer length for the same limit, so an iPhone gets the
  project's 65,536 slots. Not a device glitch.
- A route test can rewrite `config/route_bot_times.json` (Lakeside timings)
  when its measured times drift; the file was restored, not changed.

## 7. What 2.2 still needs from the owner

Purchases, Coins, Season XP and rewards, challenges and Friends status run
through the game service, which still isn't deployed, and the eight App
Store products and the Paid Apps Agreement don't exist yet. Until then the
build says so honestly and nothing can be bought. The order is in
`docs/OWNER_SETUP_GUIDE.md` (A agreements, B products, C service, D the
configured build, E sandbox test, F version page, G submit).
