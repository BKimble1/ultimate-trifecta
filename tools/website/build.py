#!/usr/bin/env python3
"""Builds the official Ultimate Trifecta website into website/.

Pages are plain HTML fragments in tools/website/pages/ with a small header
block (key: value lines, then a line with ---).  The layout (head, header,
menu, footer) lives here so every page shares it.  Run:

    python3 tools/website/build.py

Then serve website/ (for example `python3 -m http.server -d website`) or
deploy it as-is to Netlify (website/netlify.toml).
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tools/website/pages"
OUT = ROOT / "website"

SITE = "https://ultimatetrifecta.idlery.com"
APP_STORE = "https://apps.apple.com/app/id6818346960"
SUPPORT_EMAIL = "support@idlery.com"
UPDATED = "November 17, 2026"
YEAR = "2026"

NAV = [("/", "The Game"), ("/season/", "Season 1"), ("/support/", "Support")]

ICON = {
    "play": '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7 4.8v14.4c0 .8.9 1.3 1.6.8l11-7.2c.6-.4.6-1.2 0-1.6l-11-7.2C7.9 3.5 7 4 7 4.8z"/></svg>',
    "pause": '<svg class="i-pause" viewBox="0 0 24 24" aria-hidden="true"><rect fill="currentColor" x="5" y="4" width="5" height="16" rx="1.2"/><rect fill="currentColor" x="14" y="4" width="5" height="16" rx="1.2"/></svg>'
             '<svg class="i-play" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7 4.8v14.4c0 .8.9 1.3 1.6.8l11-7.2c.6-.4.6-1.2 0-1.6l-11-7.2C7.9 3.5 7 4 7 4.8z"/></svg>',
    "close": '<svg viewBox="0 0 24 24" aria-hidden="true"><path stroke="currentColor" stroke-width="2.6" stroke-linecap="round" d="M5 5l14 14M19 5L5 19"/></svg>',
    "snow": '<svg class="snow" viewBox="0 0 24 24" aria-hidden="true"><g stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"><path d="M12 2v20M3.3 7l17.4 10M3.3 17L20.7 7"/><path d="M9.5 3.8L12 6.2l2.5-2.4M9.5 20.2L12 17.8l2.5 2.4M4.3 10.4l3.3-.9-.8-3.3M19.7 13.6l-3.3.9.8 3.3M4.3 13.6l3.3.9-.8 3.3M19.7 10.4l-3.3-.9.8-3.3"/></g></svg>',
}


def waterline(fill: str, where: str = "top", slow: bool = False) -> str:
    """The rippled top edge of a section (two periods, so the drift loops)."""
    path = "M0 22 C 120 6, 240 6, 360 22 S 600 38, 720 22 S 960 6, 1080 22 S 1320 38, 1440 22 S 1680 6, 1800 22 S 2040 38, 2160 22 S 2400 6, 2520 22 S 2760 38, 2880 22 V44 H0 Z"
    return (f'<div class="waterline {where}{" slow" if slow else ""}" aria-hidden="true">'
            f'<svg viewBox="0 0 2880 44" preserveAspectRatio="none"><path fill="{fill}" d="{path}"/></svg></div>')


def store_button(cls: str = "") -> str:
    return (f'<a class="btn store {cls}" href="{APP_STORE}" rel="noopener">'
            f'<small>Download on the</small><span>App Store</span></a>')


def header(path: str) -> str:
    cur = ' aria-current="page"'
    links = "".join(f'<a href="{href}"{cur if href == path else ""}>{label}</a>' for href, label in NAV)
    big = "".join(f'<a class="big" href="{href}"{cur if href == path else ""}>{label}</a>' for href, label in NAV)
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="site-header">
  <div class="wrap">
    <a class="brand" href="/" aria-label="Ultimate Trifecta home">
      <picture><source srcset="/assets/img/logo-360.webp" type="image/webp"><img src="/assets/img/logo-360.png" width="360" height="114" alt="Ultimate Trifecta"></picture>
    </a>
    <nav class="nav" aria-label="Main">{links}</nav>
    <div class="header-cta">
      <a class="btn small" href="{APP_STORE}" rel="noopener">Get it on the App Store</a>
      <button class="menu-btn" type="button" aria-expanded="false" aria-controls="mobile-menu" aria-label="Open menu"><span></span></button>
    </div>
  </div>
</header>
<div class="mobile-menu" id="mobile-menu" aria-hidden="true">
  {big}
  {store_button()}
  <div class="small-links"><a href="/privacy/">Privacy</a><a href="/terms/">Terms</a><a href="/rules/">Official Rules</a><a href="/delete-account/">Delete your profile</a></div>
</div>'''


FOOTER = f'''<footer class="site-footer">
  <div class="wrap">
    <div class="top">
      <div class="studio">
        <img src="/assets/img/idlery-games.svg" width="150" height="81" alt="Idlery Games">
        <p>Ultimate Trifecta is made by Idlery Games.</p>
      </div>
      <div>
        <h4>Game</h4>
        <ul><li><a href="/">The Game</a></li><li><a href="/season/">Season 1</a></li><li><a href="/rules/">Season Champion</a></li><li><a href="{APP_STORE}" rel="noopener">App Store</a></li></ul>
      </div>
      <div>
        <h4>Help</h4>
        <ul><li><a href="/support/">Support</a></li><li><a href="/delete-account/">Delete your profile</a></li><li><a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a></li></ul>
      </div>
      <div>
        <h4>Legal</h4>
        <ul><li><a href="/privacy/">Privacy Policy</a></li><li><a href="/terms/">Terms of Service</a></li><li><a href="/rules/">Official Rules</a></li></ul>
      </div>
    </div>
    <div class="legal">
      <p>&copy; {YEAR} Idlery Games. All rights reserved. Moonbrook College is fictional.</p>
      <p>Apple, iPhone, iPad, App Store and Game Center are trademarks of Apple Inc., registered in the U.S. and other countries and regions.</p>
    </div>
  </div>
</footer>'''

PLAYER = f'''<div class="player" id="player" role="dialog" aria-modal="true" aria-label="Trailer" aria-hidden="true">
  <button class="close" type="button" aria-label="Close trailer">{ICON["close"]}</button>
  <video controls playsinline preload="none" poster="/assets/video/trailer.jpg" data-src="/assets/video/trailer.mp4"></video>
</div>'''


def page(meta: dict, body: str) -> str:
    title = meta["title"]
    full = title if title == "Ultimate Trifecta" else f"{title} | Ultimate Trifecta"
    desc = meta["description"]
    path = meta["path"]
    url = SITE + path
    image = SITE + meta.get("image", "/assets/img/share.jpg")
    robots = '<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    player = PLAYER if meta.get("player") else ""
    preload = meta.get("preload", "")
    ld = ""
    if path == "/":
        ld = ('<script type="application/ld+json">{"@context":"https://schema.org","@type":"VideoGame","name":"Ultimate Trifecta",'
              '"url":"' + SITE + '/","description":' + _json(desc) + ',"gamePlatform":["iPhone","iPad"],'
              '"operatingSystem":"iOS 17 or later","applicationCategory":"Game","genre":["Party","Action"],'
              '"playMode":["MultiPlayer","SinglePlayer"],"numberOfPlayers":{"@type":"QuantitativeValue","minValue":1,"maxValue":8},'
              '"publisher":{"@type":"Organization","name":"Idlery Games"},"image":"' + image + '"}</script>')
    return f'''<!doctype html>
<html lang="en" class="no-js">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{html.escape(full)}</title>
<meta name="description" content="{html.escape(desc)}">
<link rel="canonical" href="{url}">
{robots}
<meta name="theme-color" content="#0c1324">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Ultimate Trifecta">
<meta property="og:title" content="{html.escape(full)}">
<meta property="og:description" content="{html.escape(desc)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{image}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="app-id=6818346960">
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/assets/img/icon-192.png" type="image/png" sizes="192x192">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="preload" href="/assets/fonts/archivo-latin-wdth-italic.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/assets/fonts/manrope-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
{preload}
<link rel="stylesheet" href="/assets/css/site.css?v=1">
{ld}
</head>
<body class="{meta.get("body", "")}">
{header(meta.get("nav", path))}
<main id="main">
{body}
</main>
{FOOTER}
{player}
<script src="/assets/js/site.js?v=1" defer></script>
</body>
</html>
'''


def _json(s: str) -> str:
    import json
    return json.dumps(s)


def render(text: str) -> str:
    """Fills {{NAME}} slots in a page body."""
    slots = {
        "APP_STORE": APP_STORE, "SUPPORT_EMAIL": SUPPORT_EMAIL, "UPDATED": UPDATED, "SITE": SITE,
        "STORE_BUTTON": store_button(), "PLAY": ICON["play"], "PAUSE": ICON["pause"], "SNOW": ICON["snow"],
    }
    def sub(m):
        k = m.group(1)
        if k.startswith("WATER:"):
            parts = k.split(":")
            return waterline(parts[1], "top", len(parts) > 2 and parts[2] == "slow")
        return slots[k]
    return re.sub(r"\{\{([A-Z_]+(?::[^}]+)?)\}\}", sub, text)


def build() -> None:
    n = 0
    for src in sorted(SRC.glob("*.html")):
        raw = src.read_text(encoding="utf-8")
        head, body = raw.split("\n---\n", 1)
        meta = {}
        for line in head.strip().splitlines():
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
        for k in ("player", "noindex"):
            if k in meta:
                meta[k] = meta[k] == "true"
        out_name = meta.pop("out", None)
        dest = OUT / (out_name if out_name else meta["path"].strip("/") + "/index.html" if meta["path"] != "/" else "index.html")
        dest.parent.mkdir(parents=True, exist_ok=True)
        text = page(meta, render(body))
        assert "—" not in text, f"em dash in {src.name}"
        dest.write_text(text, encoding="utf-8")
        n += 1
        print("wrote", dest.relative_to(ROOT))
    print(n, "pages")


if __name__ == "__main__":
    build()
