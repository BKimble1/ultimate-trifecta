# Ultimate Trifecta V5 branding assets

Copy these into the existing Ultimate Trifecta project and supply the companion V5 Claude prompt. These are branding assets, not a completed game update.

| File | Intended use |
| --- | --- |
| idlery-wordmark-original.svg | Original Idlery mark, preserved from the website source |
| idlery-games.svg | Editable vector lockup for dark startup backgrounds; lettering is outlined |
| idlery-games.png | Transparent 2400 x 1380 PNG of the startup lockup |
| ultimate-trifecta-lobby-title.png | Transparent 2172 x 724 PNG game title for the lobby and match loading |
| DejaVu-license.txt | Attribution/license for the outlined Games descriptor |

The Idlery mark is copied without changing its path or teal color from BKimble1/Idlery-Website, src-assets/brand/idlery-wordmark.svg, commit 1ce08aa05f5716e01274931b1636f5b9868edba6. The Games descriptor uses outlined DejaVu Sans regular with wider tracking. The new Ultimate Trifecta title was generated using the built-in image-generation tool and checked visually for spelling and transparency.

Use Idlery Games at app startup and Ultimate Trifecta in the game lobby/match loading. The Games descriptor is ivory and intended for a deep navy background such as #0c1324. Preserve alpha, scale proportionately, and keep touch/layout padding around the title. The revised title removes all water drops and reduces the glossy finish. Preserve the softer satin appearance unless actual runtime captures demonstrate that additional shine matches the game. Test phone-size sharpness before choosing runtime texture import settings. Keep the existing game icon.

The generation prompt requested an original modern athletic two-line game title: gold ULTIMATE, much larger ivory TRIFECTA with subtle teal depth and a navy edge, no water drops, a softer satin-matte finish, a transparent background, and no character art or background panel. The built-in generation path was used.

Suggested repo locations: editable originals under art_src/branding; runtime SVG/PNG assets under game/assets/branding. Claude should connect them to the actual startup, title, party, and loading code as specified in the companion prompt.
