# V6 social media: party room, names and chat, rankings

**How these were made.** Every image is the real game, rendered on desktop
Linux by Godot 4.7.2's **Mobile renderer** on Mesa **llvmpipe** (software
Vulkan) under Xvfb, at device resolutions, from the merged v6-social branch
(with the art, commerce and dorms work). They show layout, behaviour and
framing. **They are not evidence of frame rate, smoothness, device input or
heat.** Nothing here was captured on an iPhone or iPad.

**Device sizes.**
- **phone:** 2532×1170, Dynamic Island safe area, point scale 3.
- **SE:** 1334×750, point scale 2.
- **iPad:** 2048×1536 (4:3), point scale 2.

**Parties.** Parties are **desktop LAN dev rooms** (iOS uses Game Center).
The other players are separate headless game processes running the scripted
`social_bot` driver: they walk a loop around their mark and send a Quick
Chat phrase every few seconds (so unread counts climb quickly). Their looks
are random. The machine was shared and busy, so the software-rendered host
drew a frame every few seconds at times; the scripted members were told to
wait for it (a real client gives up on a silent host after 6 s).

**The game service.** It is **not deployed**, and it is **off** in the
`hub/`, `names/` and `results/` runs, as in the shipped build: typed chat
says it is unavailable, reports say nothing was sent, names in parties are
the game's own, and the results say rewards weren't added. The `service/`
run uses the **real service code run locally**
(`service/tools/dev_server.mjs`, an in-memory database and a test-only Game
Center key). That is not a deployment.

**Regenerate** with `tools/capture_v6_social.sh OUT_DIR [hub names results
service clip]` (`CAPTURE_TIMEOUT` and `HUB_SIZES` help on a busy machine).
Images here are JPEG copies, 1600 px wide at most.

## hub/ (phone, service off)

Party rooms with 1, 2, 4 and 8 players (the host plus scripted members).

| File | What it shows |
|---|---|
| `hub_1p_menu.jpg` | Menu mode, alone: the V6 navigation, then Emote, Walk and Chat as icons (the row is measured to fit), the party code with Copy and Share, the settings chips |
| `hub_1p_bubbles.jpg` | Your own Quick Chat phrase as a bubble beside your head |
| `hub_1p_chat.jpg` | The chat drawer with the service off: it says typed chat is unavailable and why; Quick Chat in one sideways strip |
| `hub_2p_menu.jpg` | Two players: the guest walking around on the host's screen with a nameplate and a bubble; the roster with Ready; the unread badge |
| `hub_2p_walk.jpg` | Walk mode: the follow camera, the floating stick on the left, Done, the hint; furniture collision is in `test_hub_walk` |
| `hub_2p_bubbles.jpg` | Quick Chat bubbles in the room |
| `hub_2p_chat.jpg` | The drawer with party chat from the other player |
| `hub_2p_player_card.jpg` | A player card: Mute (chat and emotes), Report…, Block, and the host's Remove from party |
| `hub_2p_report.jpg` | Report with the service off: "Reports aren't available here … Nothing has been sent" (never "Reported") |
| `hub_4p_menu.jpg`, `hub_4p_walk.jpg`, `hub_4p_bubbles.jpg`, `hub_4p_chat.jpg` | Four players, three of them walking |
| `hub_8p_menu.jpg`, `hub_8p_walk.jpg`, `hub_8p_bubbles.jpg`, `hub_8p_chat.jpg` | A full party of eight; with everyone walking at once, nameplates and bubbles crowd each other |

## names/ (phone, service off)

| File | What it shows |
|---|---|
| `name_rejected_impersonation.jpg` | "Tr1fecta Admin" refused with a friendly reason (staff impersonation, leetspeak folded) and three safe suggestions |
| `name_rejected_contact.jpg` | "add me on snap" refused: no handles or contact details |
| `name_suggestion_tapped.jpg` | A suggestion is one tap from a valid name |
| `name_harmless_lookalike_ok.jpg` | "Bob Builder" accepted (a harmless look-alike of a listed word); the sheet says parties show a curated name without the online check |

## results/ (phone, SE, iPad; service off)

A real bot-driven practice round (recorded headless, then shown) presented
as round 3 of a three-round friend series: two bot seats are relabelled as
friends and the earlier rounds are recorded through `PartySeries`. Rewards
go through the real path (`Save.apply_results` and the Wallet), which says
the service isn't set up, so nothing is shown as added.

| File | What it shows |
|---|---|
| `*_results_round.jpg` | Outcome and its reason, the winning team's portraits ("You" ringed, people before bots), the runners' table with You highlighted, the fixed actions: Final standings, Chat, Leave |
| `*_results_round_scrolled.jpg` | Scrolled: bots marked, the Night Watch table on its own, the rewards card with the wallet's sentence |
| `*_results_final.jpg` | Final standings: Round Wins, a podium where a three-way tie shares 2nd, Return to lobby only now |
| `*_results_final_scrolled.jpg` | Shared places as "T2" with no name order, rounds played, the role tally and the rounds list |

## service/ (phone; the service code run locally, not deployed)

A LAN dev room registered as a service room, with one headless guest
admitted by the service.

| File | What it shows |
|---|---|
| `service_lobby_typed_bubble.jpg` | A typed message, approved and signed by the service and verified on the host, as a bubble |
| `service_chat_typed.jpg` | The drawer with typed chat: the text field at the top (clear of the keyboard), the guest's typed and Quick Chat messages |
| `service_chat_refused.jpg` | "add me on snap, my number is …" refused before sending: no links, handles or contact details |
| `service_message_actions.jpg` | A message's actions in view: Mute, Report message, Report player, Block… |
| `service_report_reasons.jpg` | Report this message: the reasons |
| `service_report_sent.jpg` | "Report sent" with the service's receipt (shown only once the service confirms) |
| `service_after_block.jpg` | After Block (by the host): the player is removed and their chat is gone |
| `admin_queue.txt` | The owner's queue from `service/tools/admin.mjs`: the reported message kept as evidence with its room |
