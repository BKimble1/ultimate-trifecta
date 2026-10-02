# V6 social media: party room, names and chat, rankings

**How these were made.** Every image is the real game, rendered on desktop
Linux by Godot 4.7.2's **Mobile renderer** on Mesa **llvmpipe** (software
Vulkan) under Xvfb, at device resolutions. They show layout, behaviour and
framing. **They are not evidence of frame rate, smoothness, device input or
heat.** Nothing here was captured on an iPhone or iPad.

**Device sizes.**
- **phone:** 2532×1170, Dynamic Island safe area, point scale 3.
- **SE:** 1334×750, point scale 2.
- **iPad:** 2048×1536 (4:3).

**Parties.** Parties are **desktop LAN dev rooms** (iOS uses Game Center).
The other players are separate headless game processes running the scripted
`social_bot` driver: they walk a loop around their mark and send a Quick
Chat phrase now and then. Their looks are random.

**The game service.** It is **not deployed** and is **off** in the `hub/`,
`names/` and `results/` runs, as in the shipped build. The `service/` run
uses the **real service code run locally**: `service/tools/dev_server.mjs`
with an in-memory database and a test-only Game Center key. That is not a
deployment.

**Regenerate** with `tools/capture_v6_social.sh OUT_DIR [hub names results
service clip]`.

| Folder | What |
|---|---|
| [hub/](hub/) | Party room with 1, 2, 4 and 8 players: menu composition, Walk around, Quick Chat bubbles, chat drawer, player card, report sheet (service off) |
| [names/](names/) | The name sheet refusing names, with suggestions |
| [results/](results/) | Round results and final series standings on phone, SE and iPad |
| [service/](service/) | Typed chat approved by the service code, a refused message, a message report with its receipt and the owner's queue, a block |
