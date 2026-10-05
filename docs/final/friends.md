# Friends: in-game status and party invites (FINAL_RELEASE_SWEEP)

Branch `worktree-agent-ada04fe08199e8933` (FRIENDS workstream), from the
integrated commit `e3c2cd6`. Brief §6, with §2 item 5, §9 (privacy, deletion,
moderation) and §10 (Friends evidence).

**What is and isn't proven.** Everything here was built and verified on
desktop Linux: the service logic against its whole API on the in-memory D1
(`node --test`), the game's side headless against a labelled test double,
and rendered layouts on llvmpipe. **No device, no Game Center session and no
deployed service were available.** The two-device proof (§11) is written out
for the owner and is **not done**.

## 1. What a player gets

- **Friends** on Home (top right, next to the profile chip), in the party
  room (top bar, where Invite was; every member of an online party has it)
  and on Play with Friends. A badge counts invites waiting.
- **The Friends drawer** (right side, Close/Back/tap outside/ui_cancel close
  it, input is released afterwards): each Game Center friend with a status
  in words and a dot (Online, In a party, In a round, Offline; "Status
  unknown" for a friend the service can't match, "Status unavailable" when
  the service can't answer: never a guessed green dot), sorted Online →
  In a party → In a round → Offline → unknown, then by name. The verified
  game name is shown first, the Game Center name beside it.
- **Invite** sends a real invitation for your current party ("Invited ✓"
  only after the service confirmed it). From Home it starts a party first
  (there is none to replace) and reopens Friends in the new party room.
- **Incoming invites** appear as a small card in the right half under the
  top row ("Comfy Frog invited you · to their party · 4:38 left", Decline /
  Accept), never during a round or its loading screen (they wait for the
  results or the lobby), and fold into the badge after 15 s; the drawer lists
  them until they expire (5 minutes).
- **Accept** asks first when you're in a party ("Leave this party to join
  Comfy Frog?", and for a host with others: "Your party ends for everyone in
  it."), then the service re-checks the invite and the game joins **through
  the same path as a typed code** (Play with Friends' progress, Cancel and
  error messages).
- Tap a friend: **Invite with Game Center** (Apple's sheet with that friend
  pre-selected; the host of a Game Center party), **Report…** and **Block…**
  where a verified profile is shown.
- Footer: the party code with **Copy code** and **Invite with Game Center**
  in a party; **Party codes** (Play with Friends) from Home. **Show when I'm
  playing: On/Off** ends the list.
- States: checking, asking for friends-list access (Apple's sheet), access
  off, restricted (Screen Time), multiplayer off (Screen Time), Game Center
  signed out, no Game Center on this device, no friends, network failure,
  service unavailable.

## 2. Identity: the ID domains, reconciled

| ID | Where it comes from | Used for |
|---|---|---|
| **teamPlayerID** (`GKPlayer.team_player_id`) | Game Center; for the local player it is signed by `fetchItemsForIdentityVerificationSignature` and verified by the service (`identities.subject`) | the **only** ID Friends uses: uploaded friend sets, presence keys, invite targets. Same team-scoped value on the friend's own device and in our friends list |
| gamePlayerID (`game_player_id`) | Game Center, game-scoped | kept on the device only; Apple's UI and `GameKitTransport` peer mapping (unchanged) |
| GKPlayer object | `GKLocalPlayer.load_friends` | `GKMatchRequest.recipients` (pre-selecting a friend in Apple's sheet) |
| display name | Game Center | shown on this player's own list beside the verified name; checked against the game's abuse lists (accents and emoji allowed) |
| profile ID (`p_…`) | the service, opaque | Report / Block from a friend's row; never accepted from a client as authority |

Before this pass `Social.load_friends()` returned `game_player_id` while the
service verifies teamPlayerID (brief §2 item 5), so nothing could have been
matched. It now returns `{tid, gid, name, player}` and drops a friend with no
team-scoped ID. Every native name was checked against the pinned
GodotApplePlugins source (`bfade13`, `Sources/GodotGameCenter`) and the
shipped iOS binary's symbol strings: `GKLocalPlayer.load_friends(callback)`,
`load_friends_authorization_status(callback)` (raw `GKFriendsAuthorizationStatus`:
0 not determined, 1 restricted, 2 denied, 3 authorized), `GKPlayer`
`team_player_id`, `game_player_id`, `display_name`, `GKMatchRequest`
`recipients` (Array of GKPlayer) and `invite_message`, and errors arrive as a
`GKError` object (`code`, `message`; 26 friend list restricted, 27 denied,
14 not authenticated), not a string.

## 3. Relationship and security model

**A relationship is a mutual claim from two verified sessions.** Each game
uploads its own authorised Game Center friends (`PUT /v1/friends`, ≤ 500
teamPlayerIDs). The service stores **only keyed hashes**
(HMAC-SHA256(`FRIEND_HASH_KEY`, `gc-team:<environment>:<id>`), 128 bits) and
the player's own hash. A and B are friends here only while A's current set
contains B's verified ID **and** B's contains A's, both sets were refreshed in
the last 30 days, **neither has blocked the other** (the existing `blocks`
table, both directions) and **neither is suspended or deleted**.

| Threat | Answer |
|---|---|
| Claiming arbitrary IDs to see who plays or what they do | A one-sided claim shows nothing. Presence lists only mutual friends (the other side must have listed your *verified* ID). The upload reply counts what was stored, never who matched (`enumeration` test: 500 guessed IDs, nothing) |
| Probing with invites | Unknown, one-sided, blocked and suspended targets all get the same `404 not_friend` and message; every attempt counts toward the inviter's rate limit |
| Learning room codes | Never in presence or the invite inbox; only the invitee who accepts a live invite gets the code (as from a friend sharing it) |
| Impersonating the host / inviting beyond the party | Any **connected** member may invite (decision below); the invite names the inviter and, for a guest, "to Host Otter's party". Capacity, version, blocks with the host or any member, removals (kicked), suspensions and reservations are enforced by the normal join |
| Bypassing admission | Accept returns only the code; the game calls `POST /v1/rooms/<code>/join` like a typed code. A block added between accept and join still stops it (test) |
| Spoofing someone's presence | Presence is written only for the session's own profile; "in a party" only for a room the profile is a verified member of; a launch's late heartbeat (lower `seq`) is ignored; an obsolete device never outranks the newest launch |
| Flooding | Unchanged heartbeats are written at most every 4 s per launch, changes at most once a second, ≤ 4 launches per profile; invites 20 per 10 min per inviter and 3 per 10 min per pair; friend uploads 30 per hour; accepts 20 per minute |
| Storing non-players' data | Only keyed hashes of friends' IDs; without the secret they can't be reversed or joined to anything |

## 4. Service API (`service/src/friends.js`, migration `0006_friends.sql`)

| Route | What it does |
|---|---|
| `PUT /v1/friends {ids}` | Replace this player's whole set (a removed or de-authorised friend disappears at once). 413 above 500. |
| `DELETE /v1/friends` | Friend access revoked or turned off: delete the set, this player's presence, cancel their pending invites. |
| `GET /v1/friends/presence` | `{server_time, poll_s: 10, shared, party: {joinable, why, members, capacity, host} \| null, friends: [{id (their teamPlayerID), profile_id, name, discriminator, status: online \| lobby \| match \| offline, in_your_party, invited, can_invite, why}]}`; `why` ∈ offline, in_your_party, invited, party_full, party_busy, update. |
| `POST /v1/presence {instance, seq, state, room?, protocol, build}` | Heartbeat (20 s; expiry 60 s). `lobby` without verified membership is stored as `online`. Reply: accepted status, `interval_s`, `ttl_s`, and **the invites waiting** (so the game needs no separate inbox poll). |
| `DELETE /v1/presence {instance}` | This launch went to the background / sharing off. Sign-out also deletes the rows that session wrote. |
| `POST /v1/invites {to}` | The inviter must be a connected member of a live joinable room (forming, open, results; space left); target must be a mutual friend with live presence and the same protocol. Repeated taps return the same pending invite (`duplicate: true`). 5-minute expiry. |
| `GET /v1/invites` | Pending, unexpired invites to me whose inviter is still a member of a live room and still a mutual, unblocked, active friend. |
| `POST /v1/invites/<id>/accept {build, protocol}` | Re-checks expiry, friendship, room alive, inviter still in it, protocol, blocks with any member, removal, round in progress, capacity; returns `{code, host_name, from_name}`; idempotent while unexpired (a retry after a lost reply). |
| `POST /v1/invites/<id>/decline` | Recorded (`declined`; or `expired` if late). |

`/v1/config` lists `friends` only when `FRIEND_HASH_KEY` is set (≥ 32
chars); without it Friends shows "Status unavailable" and the fallbacks.
Hooks in `app.js` are additive: one route line, profile deletion, sign-out,
cron sweep, the feature flag.

## 5. The game's side

- `game/src/autoload/friends_service.gd` (autoload **Friends**, added after
  App in `project.godot`): access, friends list, upload, heartbeat,
  polling, invites, accept/decline, toast. Timers only: a 20 s heartbeat, a
  10 s poll while a panel is open (backoff to 60 s on failure; heartbeat
  backoff to 120 s), a 1 s state check (compares a small dictionary; no
  per-frame work, nothing in the simulation). Requests go only through
  `Cloud.api` (so COMMERCE's deployment routing applies).
- State reported from the real game: `match` while `App.match_ctrl` exists
  or the loading screen is up (Practice included, without a room), `lobby`
  in an online party with its room code (results between rounds count as
  the lobby), else `online`. A change goes out within ~3 s.
- Background (`NOTIFICATION_APPLICATION_PAUSED`): `DELETE /v1/presence` for
  this launch, timers stop; resume re-checks friend access (it may have been
  turned off in Settings meanwhile), then heartbeats again.
- Revoked access (denied / restricted at open or resume): the list, statuses,
  sent invites and toasts are dropped on the device and `DELETE /v1/friends`
  clears the service's copy. Friend data is never written to disk.
- Sign-out, profile deletion or a different profile: everything is forgotten
  (`Cloud.changed`). Integration: if Cloud has `deployment_changed(from, to)`
  (COMMERCE), Friends drops presence/invites/sync state and starts again on
  the new deployment (guarded connection; the old row expires in 60 s).
- `game/src/ui/friends_panel.gd` (drawer, rows updated in place by
  teamPlayerID, nothing rebuilt per poll), `game/src/ui/invite_toast.gd`.
- `Social`: `load_friends()` (teamPlayerIDs), `friends_access()`,
  `error_text()/error_code()`, `invite_friends(t, code, recipients)`, and no
  crash where GameKit classes can't be instantiated.
- `App.join_room_gamekit(code, confirmed := false)`: the one-line addition so
  an accepted invite (already confirmed) isn't asked twice.
- Apple's own invites (`GKInvite`, unchanged): `App._on_invite_ready` already
  holds HELLO until the host announces its code and then joins that code
  through the service (`admission_needed` → `Cloud.join_room`), so the
  Game Center path also goes through admission (read from source; not
  exercised on a device).

### Decisions

1. **Any connected member may invite** (not host-only). Parties are small
   friend groups; the invite names who sent it and whose party it is, and
   the host's blocks, removals and capacity still decide at the join. Apple's
   sheet stays host-only (a GameKit constraint).
2. **No badge on the match HUD** (adjustment of the integrator's "small
   badge" with a reason): the HUD's top band is fully used (goal bar, danger
   chip, team chat feed, minimap/pause, the personal card) and on SE no spot
   is free without covering a gameplay cue. During a round nothing is drawn;
   the invite waits and is shown (toast + badge) on the results screen or in
   the lobby while it is still valid. Accept is refused while a round runs.
3. **Toast in the right half, under the top row**: never over the walk
   stick (left half) or the bottom row; it covers the top of the roster for
   at most 15 s; no controller focus (the drawer has the same actions).
4. **Show when I'm playing** (default on once friend access is given):
   off clears this launch's row and stops heartbeats; friends see you as
   Offline and can't invite you. You still see them.
5. **Quiet start**: if friend access was already given, the game uploads its
   friend set and starts heartbeats at sign-in without opening anything (no
   prompt). If it wasn't, nothing about friends leaves the device until the
   player opens Friends and allows access.
6. **Results screen = lobby** for status and invites (between rounds the room
   is in `results`, which a code join also accepts).

## 6. Defect register

| # | Symptom | Reproduction | Cause | Fix | Evidence |
|---|---|---|---|---|---|
| F1 | Friends were plain names; no status, no invite | Play with Friends → Show Game Center friends (`b03_*`) | `online_screen.gd::_on_friends` listed `display_name` only | Friends drawer with status, invites, toast | `a02`/`a17` captures, `test_friends` |
| F2 | Status could never be matched to the service | read `social_service.gd::load_friends` at `e3c2cd6` | it returned `game_player_id`; the service verifies teamPlayerID | returns `team_player_id` (+ gid, name, GKPlayer) | `test_states…`: "teamPlayerIDs, never gamePlayerIDs" |
| F3 | GameKit errors would show as `<GKError#…>` (friends list, identity, room) | source: binding passes a `GKError` object (`GKError.swift`), code did `str(err)` | wrong type assumption | `Social.error_text()/error_code()`; friend-list denied/restricted mapped to their own states | source; not observed on a device |
| F4 | Script error "Cannot call method 'set' on a null value" (`social_service.gd:177 _request`) | create a party where `GKMatchRequest` can't be instantiated (desktop; seen in `test_friends`) | no null check | `_request()` returns null; host/join/invite report "Game Center matchmaking isn't available" | `test_heartbeat…` passes the party path |
| F5 | Guests had no way to invite; the lobby's Invite only opened Apple's sheet, host only | party room as a guest | `invite_btn.visible = hosting and …` | Friends in the top bar for every member; open seat opens Friends | `a16`, `test_invite…` |
| F6 | Service test failed once a newer migration existed | `npm test` with `0006_friends.sql` | `season.test.mjs` asserted 0005 is the last file | asserts 0005 is present | `npm test` 81/81 |
| F7 | (new code, found during this work) state change heartbeat never sent under fixed-step timing | `test_heartbeat…` | debounce restarted its timer every second from the wall clock | never pushes back a beat already due | test |
| F8 | (new code) invite toast collapsed at once in a slow first frame; 1,472-unit tall card | lobby capture; `test_incoming…` | wall-clock 15 s; wrapped labels measured before their width | 15 s counted in 1 s game ticks; labels get their width, card shrink-wraps after layout | `a14`/`a18`, `test_toast_folds…`, layout test height check |

Observed, not fixed (outside this stream): `Social.room_failed` has no
listener anywhere, so a Game Center matchmaking failure after a successful
service join is never shown to the player (pre-existing).

## 7. Retention, TTL and privacy inventory

| Data (service) | Kept | Removed |
|---|---|---|
| Friend set: keyed hashes of ≤ 500 friends' teamPlayerIDs + own hash, linked to the profile | until the next upload replaces it | 30 days without an upload (cron); `DELETE /v1/friends` (access revoked/off); `DELETE /v1/me` |
| Presence: status (online / lobby / match), verified room ID (never shown), protocol, build, per app launch | 60 s after the last heartbeat (20 s cadence) | expiry + cron (5 min); background; sign-out (that session's rows); sharing off; `DELETE /v1/me`; no history |
| Invites: inviter, invitee, room, state, times | 5 min pending; resolved rows 24 h | cron; `DELETE /v1/me` (either side) |
| On the device | friends list, statuses, invites in memory only | revoke, sign-out, profile change/deletion, deployment move |

**Proposed App Privacy additions** (integrator; service-enabled build):

| Apple data type | What | Linked | Purpose | Tracking |
|---|---|---|---|---|
| **Contacts** ("social graph") | Game Center friends' team player IDs, sent so the service can match mutual friends; stored only as keyed hashes for up to 30 days | Yes | App Functionality | No |
| **Product Interaction** | whether you're playing, in a party or in a round, shown to mutual friends for up to 60 s; party invites (5 min, records 24 h) | Yes | App Functionality | No |
| (already declared) User ID, Name, Gameplay Content | profile, verified name, party membership | Yes | App Functionality | No |

PrivacyInfo: add `contacts` and `product_interaction` to the service-on list
in `tools/export_ios.sh` (`privacy/collected_data/<type>/collected=true,
linked_to_user=true, used_for_tracking=false, collection_purposes=2`). The
`NSPrivacyCollectedDataTypeContacts` / `…ProductInteraction` types and the
`product_interaction` key are in the pinned Godot 4.7.2 binary; confirm the
`contacts` key name in the export dialog (its string is merged in the binary).

**NSGKFriendListUsageDescription** (proposed; `export_presets.cfg` is left
to the integrator): *"Shows which of your Game Center friends are playing
Ultimate Trifecta so you can invite them to your party. Friends only see you
when you've both allowed this."* (current: "Show your Game Center friends who
play Ultimate Trifecta so you can invite them to a private room.")

## 8. How it was verified (all on desktop Linux)

| Command | Result |
|---|---|
| `cd service && npm test` | **81 tests, 0 failures** (the 68 before, one of them adjusted, + 13 in `friends.test.mjs`) |
| `node --test test/friends.test.mjs` | 13/13: features flag; mutual-only; enumeration with 500 guessed IDs, identical invite errors, hashes only, cap/validation; blocks both ways (and a block after an invite); suspended (via the moderation queue) and deleted, suspension lapse; presence expiry, background, sign-out, lobby membership check, sweep; several devices, late `seq`, write throttle, launch cap; invites dedup, decline, expiry recorded, per-pair and per-inviter limits, sweep; accept re-checks (version, started, full, member block, guest inviter left, removed, host left); accept → normal join (RS256 admission, block between accept and join still refused); **two players end to end in one process**; revoke/delete/30-day age-out; stale sets |
| `tools/gd.sh --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd -- test_friends.gd:` | **13 tests, 253 checks, 0 failures** |
| same runner, `test_v7_screens, test_lobby, test_lobby_flow, test_hub_walk, test_menus_layout, test_focus, test_account, test_report_block, test_screen_cycles, test_compile, test_trust` | **51 tests, 12,635 checks, 0 failures** |
| `tools/check_v7_screens.sh` (SE, X/14, 14, Pro Max, iPad, two owner aspects; real 44 pt targets and safe areas) | 7 × 10 tests, **0 failures** (Home with the new Friends button, party room) |
| `tools/check_v7_screens.sh test_friends.gd:test_layout` | 7 devices × 26 checks, **0 failures** (panel inside the safe area, rows, Invite targets, toast right half, small, clear of the bottom row, long names) |

Two-account logic is shown by the service test with two in-process
verified sessions and by the client tests against the test double — **test
harness evidence, not a device or Game Center**.

## 9. Evidence

[`docs/media/final/friends/`](../media/final/friends/README.md): **96
pictures**, 4 before (baseline `e3c2cd6`, rendered from a copy of that commit)
and 20 after per device, at the same scale per device (`FAST=1`: each
device's canvas, point scale and safe area) for SE, iPhone 14, Pro Max and
iPad. Every picture is stamped **"desktop render · test-double service"**
(fictional players). The party room in the "after" set is a real
`App.host_room_gamekit` against the test double, with Game Center simulated
as signed in (so Apple's "Invite with Game Center" button shows; the sheet
itself can't open on Linux).

Headline pairs: `b01_home` → `a01_home` (Friends entry);
`b03_play_with_friends_list` → `a02_panel_home_list` (names only → status,
sorting, Invite); `b04_lobby` → `a16_lobby` / `a17_panel_lobby_invited`
(host-only Apple sheet → Friends for every member, Invited ✓, party code);
states `a04`–`a13`; invites `a14`, `a18`–`a20`.

Reproduce: `FAST=1 tools/capture_friends.sh OUT se p14 pmax ipad`. The
baseline: extract commit `e3c2cd6`'s `game/` folder (an archive of that
commit), copy in the addons, `.godot` and
`game/src/dev/friends_capture.gd/.tscn`, import, then
`FAST=1 MODE=before GAME=<that>/game tools/capture_friends.sh OUT …`.

## 10. Open items and owner dependencies

- **Deploy**: migration `0006_friends.sql` on both D1 databases
  (`deploy.sh` applies it); new secret **`FRIEND_HASH_KEY`** per deployment
  (`scripts/gen_keys.sh` then `deploy.sh`; deploy refuses without it).
- **Device proof** (§11) on two accounts/devices: not done here.
- **Native unverified**: friends-list prompt and its text, the authorization
  status values, `recipients` pre-selection in Apple's sheet, GKError codes,
  callback threads (handled with `call_deferred`).
- **HTTP on the main thread**: `Cloud._http` creates `HTTPRequest` without
  `use_threads`, so each request's TLS handshake is polled on the main thread;
  presence adds one request per 20 s (fewer than typed chat can). Suggest
  `h.use_threads = true` in `Cloud._http` (COMMERCE-owned); unmeasured on a
  device.
- **Capacity**: ≈4,300 presence writes per playing user per day; the free
  Workers/D1 tiers cover a few dozen concurrent players. Owner to size the
  plan.
- `room_failed` has no listener (F-note above).
- Friend sets need both players to open Friends once (consent); until then a
  friend shows "Status unknown" — expected, explained in the drawer.

## 11. Two-device procedure (owner; brief §6 Proof)

Needs: the service deployed with `0006` and `FRIEND_HASH_KEY`; a build whose
`service.cfg` has the URL and admission key; **two iPhones/iPads with two
different Apple Accounts** signed into Game Center that are **Game Center
friends**; both on the same TestFlight build. Record pass/fail for each.

1. Both: launch, sign in to Game Center, set names (A "Comfy Frog", B
   "Snoozy Gecko").
2. B: Home → **Friends**. *Pass:* Apple's friends-list sheet appears with the
   usage text; after Allow, A is listed ("Status unknown" until A also
   allows).
3. A: Home → Friends → Allow. *Pass:* within ~10 s B's drawer shows **Comfy
   Frog · Online** (green dot). No green dot anywhere before that.
4. A: Play with Friends → Create Party, then start a round with bots. *Pass:*
   B sees **In a party**, then **In a round** within ~20 s; after the round,
   A back in the party room → **In a party**.
5. A: Friends (top bar) → B → **Invite**. *Pass:* "Invited ✓" on A only after
   the tap is confirmed; a second tap sends nothing new.
6. B (on Home): *Pass:* within ~20 s a card "Comfy Frog invited you · to
   their party · m:ss left" in the right half; Accept → "Joining Comfy
   Frog's party…" → B is in A's party room; A sees "Snoozy Gecko joined"; A's
   drawer shows B **In your party**.
7. Party sync: B changes outfit in the Locker and taps Ready; A starts a
   round. *Pass:* skin, name, ready and roles match on both; both drawers (after
   the round) show the right status.
8. Decline/expiry: A invites B again from a new party; B taps Decline.
   *Pass:* gone on B; A can invite again. A invites; B waits 5 minutes.
   *Pass:* the card and drawer entry disappear; nothing to accept.
9. In another party / in a round: B hosts its own party; A invites B; B
   Accept → *Pass:* "Leave this party to join Comfy Frog? Your party ends for
   everyone in it." (host with others) — Not now keeps B's party. B in a
   round: A invites → *Pass:* nothing appears during the round; the card
   appears on B's results screen if still valid.
10. Background / disconnect: B presses Home. *Pass:* A sees B **Offline**
    within ~10 s (or ≤ 70 s if the request didn't leave the phone). B
    returns → Online within ~20 s. B turns on Airplane Mode in the
    foreground → A sees Offline within ~70 s; off again → Online.
11. Block: B taps A's row → Block… → Block. *Pass:* both drawers drop each
    other within ~10 s; A's earlier invite can't be accepted; B joining A's
    party by code → "You can't join this party."
12. Access revoked: B turns friends-list access off for the game (Settings ›
    Game Center › Friends List). *Pass:* B's Friends says access is off; A no
    longer sees B.
13. Apple's sheet: A (host) → Friends → tap B's row → Invite with Game
    Center. *Pass:* Apple's sheet opens with B pre-selected (optional extra:
    if not pre-selected, note it); B accepts Apple's notification and joins
    through admission (same party).
14. B: Settings → Profile → Delete Game Profile. *Pass:* A no longer sees B.

## 12. Proposed text for integrator-owned files

**docs/APP_STORE.md / description bullet:** *"See which Game Center friends
are playing and invite them straight into your party — or share a 6-character
party code."*

**App Review notes (Friends):** *"Friends (Home, top right; or the Friends
button in a party) lists the reviewer's Game Center friends and shows who is
playing Ultimate Trifecta right now. Status appears for friends who have also
opened Friends and allowed friend-list access. Invite sends an invitation to
your current party (from Home it creates one first); the friend gets a small
Accept/Decline card and joins the same party. Party codes (Play with Friends →
Create Party / Join with a code) and Apple's Game Center invite sheet work
without friends status. Friends never appears during a round. Blocking a
player from their row hides you from each other."*

**What to Test (TestFlight):** *"Friends: open Friends on Home, allow
friends-list access, check that a friend who also has the game shows Online /
In a party / In a round correctly, invite them from your party, accept on the
other device and confirm you land in the same party. Try Decline, letting an
invite expire (5 min), backgrounding the app (friend goes Offline), and
Block."*

**TESTFLIGHT_RELEASE / privacy section:** *"With the service on, Friends sends
your Game Center friends' team player IDs so the service can match friends
who also play; it keeps only keyed hashes (30 days without a refresh at
most) and shows your status (playing / in a party / in a round) only to
friends who list you too, for 60 seconds after your last heartbeat. Turning
off friend access or Delete Game Profile removes it."*

## 13. Files outside this stream's ownership

- `game/src/autoload/app.gd`: `join_room_gamekit(code, confirmed := false)`
  (2 lines + comment).
- `service/scripts/deploy.sh`, `service/scripts/gen_keys.sh`,
  `service/README.md` (additive: the new secret, a Friends section, API rows,
  retention, deletion note), `service/tools/dev_server.mjs` (a dev-only key).
- `service/test/season.test.mjs`: the "0005 is the last migration" assertion
  became "0005 is present" (needed by any later migration, including
  COMMERCE's 0007).
- New: `tools/capture_friends.sh`, `game/src/dev/friends_capture.gd/.tscn`,
  `game/src/dev/fake_friends.gd` (dev only, not exported).
