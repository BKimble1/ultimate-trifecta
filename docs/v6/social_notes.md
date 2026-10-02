# V6 social workstream: walkable party room, names and chat, rankings

Branch `v6-social`. This workstream covers V6 brief §7 (walkable hub and
party UX), §13 (names, chat, moderation), §14 (rankings before returning)
and the related §16 tests and §17 documents.

Everything was built and tested on desktop Linux: headless tests, and the
Mobile renderer on llvmpipe for captures. **No iPhone was available.**
Device touch, keyboard, safe areas, frame cost and Game Center behaviour of
these features are unmeasured. **The game service is not deployed**, so
everything that needs it (server-side name approval, typed chat, report
receipts, service blocks) is implemented and tested, but not live. The
"service" captures run the real service code locally
(`service/tools/dev_server.mjs`) and are labelled as such.

## What changed

### Walk around in the party room (§7)

Files: `view/hub_walk.gd`, `view/hub_room.gd`, `ui/hub_stick.gd`,
`net/hub_sync.gd`, `view/dorm_stage.gd`, `ui/lobby_screen.gd`.

**Modes.**
- **Menu mode** (the default) is V5's composition: everyone on their mark at
  1, 2, 4 or 8 players, faces clear, names in the party panel.
- **Walk** switches to walk mode. A floating stick appears on the left half
  (touch); keys and the left stick work too. Walk mode has:
  - a follow camera;
  - collision with the room's walls and furniture (`HubRoom`, shared with
    the host's checks);
  - nameplates over everyone, with blocked players shown as "Blocked
    player".
- **Done or Back** returns to the menu composition, and the runner strolls
  back to its mark.

**Party members walking.**
- Each device sends its pose at 10 Hz while walking (`HUB_POSE`), and
  reliably when it switches mode.
- **The host is the referee.** It accepts a pose only:
  - from a seated human;
  - in the party room;
  - when newer than the last one (u16 sequence with wrap).

  It clamps each pose to the floor and to walking speed (no teleport,
  nothing inside furniture), then relays everyone at 10 Hz while anyone
  walks (`HUB_STATE`).
- Receivers draw members 150 ms in the past, interpolated.
- There are no avatars for anyone outside the roster.
- There is no jump and no player-to-player collision, so nobody can trap or
  body-block anyone.

**Input ownership (`ui/input_owner.gd`).**
- Menu input never moves the runner: movement is read only in walk mode.
- Movement stops at once while any of these is open: the chat drawer, a
  sheet or dialog, a popover, or the keyboard.
- Taking or releasing ownership clears touch and press state, so nothing
  sticks.
- Leaving the party room screen stops walking for everyone: Wardrobe/Locker,
  Shop, the pass, a round starting.
- A round start (`InputOwner.clear()`, `HubSync.clear()`) cancels walking
  and drops every pose on every device.

**Party UX.**
- The bottom bar holds Wardrobe, Emote (with Try moves inside), Walk and
  Chat (with an unread count). Captions drop on 4:3 screens so the primary
  action keeps its size.
- Notes appear when people join ("Comfy Frog joined") and leave ("… left").
- Chat bubbles appear over heads.
- Mute (chat and emotes), Report and Block on every player card.
- Unchanged from V5:
  - the party code card with Copy and Share, and Invite;
  - settings shown as chips: the host edits them, guests see a lock;
  - host and ready badges, the prominent Start/Ready button, and series
    standings;
  - host-loss behaviour.
- Appearance updates keep their stable identity, with no rebuild
  (`test_lobby_flow` still passes).

**Not done here.** Room detail and lighting in `DormStage._build_room` are
unchanged. The art workstream owns the shared materials. The hub only adds
the walk framing, nameplates and bubbles.

### Names (§13)

Files: `core/name_rules.gd`, `core/moderation_terms.gd` (generated),
`autoload/save_service.gd`, `ui/name_sheet.gd`, `net/net_session.gd`,
`core/party_series.gd`, `service/src/names.js`, `service/tools/*`.

- **The device runs the service's whole policy.** It covers normalisation
  (case, separators, repeats, leet digits, invisible and full-width
  characters, ASCII-only names), the abuse, impersonation and contact lists,
  harmless-word exceptions, reserved names, and suggestions.
- **Parity.** A 476-name / 622-message corpus is decided identically on the
  device and the service (`test_moderation`).
- **Defect fixed** in the service's name matcher. Collapsing a term with
  doubled letters could turn it into a common fragment ("…oo…" → "…o…"),
  and digit-only words were read as leetspeak. As a result **Bob, Bacon,
  Iconic, Second, Contact, "Otter 99" and "Frog 10" were refused**. They now
  pass, and each has a test. Evasions are still caught: stretched letters
  are squeezed, and distinctive collapsed terms are still matched.
- **The name sheet** gives the policy's friendly reason and three safe
  suggestions, one tap each. It stays centred as it grows.
- **Saved names** from older versions are checked against the whole policy
  (`Save.fit_name`).
- **Received names** are checked everywhere: LOBBY roster, START, RESULTS
  and the series (`NetSession.shown_name`). A failing name gets a stable
  curated stand-in. Bot names must come from the game's list.
- **Without the service, shared play shows curated names only.** This is
  done by `Save.party_name()`, the host's HELLO handling and every receiver
  (`NameRules.party_display`), so no unreviewed custom name is broadcast. In
  a service-backed party the service-approved names are shown.

### Chat (§13)

Files: `core/quick_chat.gd`, `core/chat_rules.gd`, `net/chat_channel.gd`,
`net/chat_token.gd`, `net/social_net.gd`, `ui/chat_drawer.gd`,
`ui/match_chat.gd`, `ui/report_sheet.gd`, `ui/social_actions.gd`,
`core/social_safety.gd`, `service/src/chat.js`,
`service/src/chat_rules.js`.

The full policy is in [`docs/MODERATION.md`](../MODERATION.md). In short:

- **Quick Chat** works everywhere in parties. Phrase IDs are checked by
  channel and role:
  - Party: the party room;
  - Team: your own role during a round;
  - Spectators: finished runners and watchers, who see the whole campus and
    so are kept away from active players;
  - Everyone: the results.
- **Typed chat** works only with a working service and only in
  service-admitted parties:
  1. the device checks the text;
  2. the service approves it and signs it (`POST /v1/chat/check`);
  3. the host verifies it;
  4. every receiver verifies it again, including re-checking the text.

  Without the service, the drawer says typed chat is unavailable and why.
- **The host as referee:** seated sender, channel by phase and state,
  phrase by channel and role, token for this room, sender and channel, no
  replay, rate limits (a burst of 4, then one every 2 s), and no repeat
  within 3 s.
- **Receiver defences:** host-only, sequence de-duplication and ordering,
  roster check, channel check, phrase check, token check, a per-sender cap
  (8 per 10 s), muted and blocked senders dropped, history bounded to 80,
  and recent party chat for rejoiners.
- **Reports and blocks.**
  - Reports have honest states (a receipt only from the service, Try again
    on failure, and "unavailable, nothing sent" without the service).
  - Message reports carry the signed message as evidence
    (`POST /v1/reports/message`).
  - Block hides name, chat and emotes everywhere, and a host's block also
    removes the player.
- **During a round** the chat button is a reserved touch region, and a
  three-line team feed sits at the top right, clear of the screen centre and
  the thumbs. The drawer owns input: no move, tag or jump, and nothing is
  left pressed after.

### Rankings (§14)

Files: `core/round_ranking.gd`, `core/round_rewards.gd`,
`ui/results_screen.gd` (rewritten), `core/party_series.gd`.

**After a round:**
1. The outcome and its real reason.
2. A portrait celebration of the winning team (cached portraits, people
   before bots, "You" ringed).
3. One table per team, never combined:
   - Runners by home order and time, then splashes, then fewer catches;
   - Night Watch by different runners, then tags;
   - You, BOT and "away (no Round Win)" are marked.
4. Rewards through `RoundRewards`, the adapter for the Wallet.
5. The series so far.

**After the series' last round** the primary action is **Final
standings**:
- a podium where ties share a step;
- Round Wins with shared places shown as "T1", with no alphabetical order
  (`PartySeries.leaderboard_of`: rounds played, then join order, then record
  order);
- late joins and away rounds;
- the role tally and the rounds list.

Only then does **Return to lobby** appear.

**Behaviour:**
- Nothing auto-starts or ejects anyone, and Leave is always available.
- Back from the final page returns to the round.
- A cancelled round shows the cancellation, with no tables and no rewards.
- Clients ignore repeated RESULTS and results for another round.
- Rewards are remembered per round, so reopening shows the same summary and
  never pays twice.
- Phones scroll the summary by finger (`UIKit.scroll_area`). The actions
  never scroll (`test_results_layout`).
- Reduced Motion turns off the fade, and the animation never holds anything
  back.

## Interface notes (for integration)

### Network messages

These are new message IDs in the reserved range **60–79**
(`net/social_proto.gd`). Existing message formats are unchanged, and
`Protocol.VERSION` was **not** bumped (the dorms workstream bumps it to 6).

| ID | Name | Direction | Reliability |
|---|---|---|---|
| 60 | CHAT_SEND | client → host | reliable |
| 61 | CHAT | host → clients | reliable |
| 62 | CHAT_REJECT | host → sender | reliable |
| 63 | HUB_POSE | client → host | unreliable at 10 Hz; reliable on a mode change |
| 64 | HUB_STATE | host → clients | unreliable at 10 Hz while anyone walks |
| 65 | CHAT_HISTORY | host → one rejoining client | reliable |

Clients accept 61, 62, 64 and 65 only from their bound host.

### Hooks in shared files

Each hook is a few lines; the logic lives in the new files.

**`net/net_session.gd`:**
- `var social: SocialNet`, created in `_init`;
- the range dispatch in `_on_packet` (host and client);
- `social.on_welcome` in `_send_welcome`;
- `social.tick` in `_physics_process`;
- name handling: `shown_name()` and `names_verified()`, used for LOBBY,
  START, RESULTS and the series;
- the HELLO curated-name rule;
- the RESULTS dedupe.

**Other shared files:**
- `match/match_controller.gd`: `InputOwner.menu_owns()` in
  `_build_local_cmd`; roster display copies through
  `SocialSafety.display_entry`.
- `ui/match_hud.gd`: `chat = MatchChat.attach(self)`; chat in
  `_reserve_touch_regions`.
- `autoload/app.gd`: `Save.party_name()` for online sessions;
  `InputOwner.clear()` at match start.
- `autoload/cloud_service.gd`: `has_feature`, `chat_check`,
  `report_message`.
- `view/dorm_stage.gd`: the walk frame and follow camera, `free_roam`,
  `place`, `mark_position`, `show_names`, `say`.
- `ui/icons.gd`: chat, walk, mute, flag, block, medal.
- `dev/capture.gd`: three lines start `dev/capture_social.gd` for
  `--capture=social_*`.

### Wallet adapter (commerce workstream)

`RoundRewards.summary(match_id, local_reward)` asks an autoload named
**`Wallet`** for `round_summary(match_id) -> Dictionary` when it exists:

```
{coins_collected, coins, lines: [[label, amount]],
 season: {xp_gained, tier, xp_in_tier, xp_for_tier, premium},
 pending, away, level_up, level}
```

All fields are optional. Without a Wallet, it shows this device's reward
from `Save.apply_results`, kept per round ID. Tests stub the Wallet with
`RoundRewards.wallet_override`.

### Service

- **New files.** `service/src/chat.js` (routes
  `POST /v1/chat/check` and `POST /v1/reports/message`; helpers are passed
  in as `deps`) and `service/src/chat_rules.js`.
- **`app.js`** gets two route lines, `SOCIAL_DEPS`, an import,
  `features: ['chat', 'message_reports']` in `/v1/config`, and `evidence =
  NULL` on profile deletion.
- **Migration** `service/migrations/0002_social_moderation.sql`: report
  `kind`, `evidence` and `evidence_ref`. Wrangler applies migrations in name
  order, so a commerce `0002_*.sql` with a different name also applies.
- **Word lists.** `service/tools/build_terms.py` also writes
  `game/src/core/moderation_terms.gd`.
  `service/tools/export_policy_fixture.mjs` writes the parity fixture.
- **`service/tools/dev_server.mjs`** is for development only and is never
  deployed: it serves the real code locally with a test Game Center key, for
  evidence runs.

## Proposed TESTFLIGHT_RELEASE text (the integrator edits that file)

**Compliance and privacy answers**, replacing the "Content" bullet and
adding to "Data handling":

> - **Content.** Cartoon chase with no violence, nudity or gambling.
>   Communication is private-party only. Quick Chat preset phrases are always
>   available. Typed chat is available only in parties set up through the
>   game service, and only while it is reachable: each message is checked
>   on the device, then approved and signed by the service, and verified by
>   the host and every receiver. Names are checked against the same policy
>   on the device and on the service. Without the service, parties show
>   curated names only. Every player card and message has Mute, Report and
>   Block. Reports go to the owner's moderation queue (`docs/MODERATION.md`).
> - **Data handling (V6 additions).** With the service deployed, typed chat
>   messages pass through it to be checked and signed, and are **not
>   stored**. A message someone reports is kept with that report (up to 200
>   characters, Other User Content) and removed if its sender deletes their
>   profile. Without the service, chat stays inside the party's Game Center
>   connection as preset phrase IDs.

**Running services**, adding to the "Game service" bullet:

> - Typed chat is unavailable, and says so. Quick Chat works. Reports say
>   that nothing was sent.

## Privacy manifest decision

The data types that `tools/export_ios.sh` declares when the service is
configured (user ID, name, gameplay content, other user content) already
cover reported messages, which count as other user content. Typed chat is
processed in real time and not stored, so no new type is declared.

If the owner prefers the conservative answer, add `emails_or_text_messages`
to that list, and tick User Content › Emails or Text Messages in App Store
Connect. The key exists in the pinned Godot 4.7.2. `docs/APP_STORE.md`
records both options. This is left to the integrator because commerce
changes the same line (purchases).

Stale text replaced in `docs/APP_STORE.md`: "no chat, just emotes", the age
rating's "Messaging and chat: No" and the UGC answer. "No in-app purchases"
in the description and age table is left for commerce.

## Tests

The new suites and what they cover:

| Suite | What it covers |
|---|---|
| `test_moderation` (8 tests) | Parity with the service on 476 names and 622 messages; harmless look-alikes; reasons and suggestions; safe display of received names; curated names (all combinations, including the "Sneaky Seal" case); saved-name revalidation; the name sheet |
| `test_chat` (8 tests) | Delivery, order and duplicates; the host's channel, phrase, rate and repeat limits; forged and junk packets; flood caps on receivers; signed, replayed, borrowed, other-room, edited and wrong-channel tokens; a bad host's unsigned and abusive relays; `send_text` showing only approved, normalised text; mute and block suppression; rejoin history; round channels (team only, finished runners only to spectators, everyone after results) |
| `test_hub_sync` (4 tests) | Walkers seen by everyone; teleport, furniture and bounds clamping; stale, forged and stranger poses ignored; start clears everyone |
| `test_hub_walk` (2 tests) | Menu input never moves anyone; walking and sync on the real stage; the chat drawer and sheets own input and clear stuck touches; a guest's walk on the host's stage with a nameplate and the stroll back; Back leaves walk mode first; leaving the screen and starting a round end walking everywhere |
| `test_match_chat` (2 tests) | The team-only feed and its placement; the drawer owns input (no move, tag or jump, no stale edges); practice has no chat |
| `test_report_block` (2 tests) | Honest report states with retry; the service-off sheet; blocks by a guest and by a host |
| `test_rankings` (4 tests) | Per-team order with no combined score; bots, away and you; a cancelled round with no tables; shared places without name order; the podium; the full results flow (final standings before Return to lobby, no ejection, the same rewards on reopen, wallet summary, cancelled round); repeated and stale RESULTS packets |
| Service `npm test` (26 tests) | Including the new `chat.test.mjs`: policy, approval, membership, flood, message reports, forgery, deletion |

Updated: `test_trust`, where names in a service-off party are curated.
`test_lobby`, `test_lobby_flow`, `test_emotes`, `test_focus`,
`test_results_layout`, `test_series`, `test_touch_scroll` and `test_net`
pass unchanged.

Full suite: see the commit message of the final commit.

## Evidence

See [`docs/media/v6/social/README.md`](../media/v6/social/README.md).

## Limits and dependencies

- **Everything live depends on the undeployed service:** server-side name
  approval, typed chat, report delivery and receipts, the moderation queue,
  and service blocks. The owner needs to deploy it, set real
  `SUPPORT_EMAIL` / `SUPPORT_URL`, fill in `game/config/service.cfg`, and
  staff the queue (`docs/MODERATION.md` § Owner setup).
- **No device testing.** The iOS keyboard over the drawer, safe areas with
  a real notch, Game Center relay timing of hub poses, and the touch stick
  under real fingers are untested on hardware.
- **Word lists** are English-centred. Filtering can't catch everything, and
  reports and moderators cover the rest.
- **The walk room is the existing DormStage common room.** Its furniture
  collision is a hand-made 2D layout (`HubRoom`). If the art workstream
  moves furniture, that table needs the same change.
- **Hub poses go through the host** (peer-hosted). A modified host could
  misplace avatars within the room, but can't create avatars for
  non-members or push players outside the floor on other devices.
