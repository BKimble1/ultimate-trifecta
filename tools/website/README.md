# The official website

`website/` is the complete, static site for `ultimatetrifecta.idlery.com`:
the home page, Season 1, Support, the Privacy Policy, the Terms of Service,
account deletion and the Season Champion Official Rules. No build step, no
third-party requests, no cookies or analytics. Fonts (Archivo and Manrope,
SIL OFL) and videos are served from the site.

## Deploy (Netlify)

Drag the `website` folder (or the ZIP of it) onto Netlify's deploy page, or
point a site at this folder with no build command and `website` as the
publish directory. `_headers` (security and caching) and `_redirects` (short
paths like `/delete` and `/contest-rules`) are picked up automatically, and
`404.html` is used for missing pages. Then add the custom domain
`ultimatetrifecta.idlery.com` in Netlify and a CNAME record for it at the
DNS host of `idlery.com`.

## Before it goes live

- `support@idlery.com` is used as the contact address on every page. Create
  that mailbox (or change `SUPPORT_EMAIL` in `build.py` and rebuild).
- The App Store links point to `https://apps.apple.com/app/id6818346960`,
  which works once the app is released.
- In the game, fill `game/config/links.cfg` with
  `privacy_url = "https://ultimatetrifecta.idlery.com/privacy/"`,
  `support_url = "https://ultimatetrifecta.idlery.com/support/"` and the
  same `support_email`, and put the two URLs in App Store Connect.
- The Terms say they're governed by the laws of the place where Idlery Games
  is established. Name the jurisdiction if you prefer.

## Edit the pages

Page bodies are in `tools/website/pages/*.html`; the shared layout (head,
header, menu, footer), the contact address and the App Store link are in
`tools/website/build.py`. After any change:

    python3 tools/website/build.py

## The footage

Every video on the site is the game playing itself. `tools/capture_film.sh`
records a real offline practice round in which the game's bots play every
seat, filmed by `game/src/dev/film_director.gd`: the HUD and name tags are
hidden and a camera cuts between the round's moments (the run out of the
dorm, splashes, chases and tags, runners getting home, carts, wide views),
chosen from the live round. Music is muted (sound effects only), so the
trailer carries the game's own effects.

    tools/capture_film.sh RAW_DIR SEED [W H]          # one round per seed
    python3 tools/website/edit_footage.py website/assets/video RAW_DIR --list
    # pick the moments into RAW_DIR/edit_plan.json, then:
    python3 tools/website/edit_footage.py website/assets/video RAW_DIR

The holiday clip is the character lineup in the real dorm
(`res://src/dev/character_lineup.tscn -- --lineup=b18 --light=dorm --dolly=12`,
recorded with `--write-movie`). Recording uses software rendering here, so a
round takes a few hours; on a Mac with a GPU it's close to real time.
