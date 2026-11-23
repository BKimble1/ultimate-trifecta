# Ultimate Trifecta 2.2 (33): submission verification

This is the current record. Older 2.0 checklists and the initial 2.2 setup
instructions contain historical blockers that have since been resolved.

## Verified

| Check | Evidence |
|---|---|
| Build 33 processed and eligible | Apple: `VALID`, `APP_STORE_ELIGIBLE`, encryption declaration false; `apple-status.txt`, workflow #306 rerun |
| Nine IAP records, no missing product | All nine `READY_TO_SUBMIT`; product types and USA prices match the capture fixture |
| Premium Pass price | $4.99; older $9.99 setup instructions corrected |
| Name-change crash and party round | Blake reports both tests pass in TestFlight 2.2 (33), including the two-phone round |
| Original skins and owner-created music | Blake confirms commercial-use clearance, including any people portrayed and creation-tool terms; `../CONTENT_PROVENANCE.md` |
| Contest rules in app | `ChampionPromo.rules_text()` names Idlery Games as sponsor and explicitly states Apple is not involved; a rules action exists in the poster and Rankings |
| Service suite | 116 tests, 116 passes, zero failures; `service-tests.txt` |
| Shipped build game suite | CI #305: 733 tests, 424,013 checks, zero failures; `build33-ci-tests.txt`. The shipped game/native/service source matches the audit baseline; only a test UID was added afterward |
| Age declaration | Apple reports contests `FREQUENT_OR_INTENSE`, user-generated content true, messaging/chat true, gambling false and loot boxes false; `apple-listing-detail.txt` |
| Existing screenshot delivery | Apple reports nine iPhone and nine iPad images, all `COMPLETE`; new replacements still need uploading |

All **24 PNG images pass** the exact size, 8-bit RGB, no-alpha and sRGB
checks (`../media/final/store/check.txt`). The six replacement images were
also inspected visually. Build 33's complete CI game gate is the release
verification above; an additional local repeat was stopped once that gate
and identical shipped source were independently confirmed.

## Screenshot replacement map

The main upload folders are `docs/media/final/store/iphone_6.9/` and
`docs/media/final/store/ipad_13/`. Upload in numeric order, 01 through 09.

| File | Replace in | Reason |
|---|---|---|
| `03_party_in_the_dorm.png` | iPhone and iPad | Build 33 changed Copy code to **Leave party**, added ready checks and requires the leader to ready up |
| `04_basketball_in_the_dorm.png` | iPhone and iPad | Refresh the basketball screen from build 33 after the Dunk/Block and walk-control changes |

| Folder | Resolution | Contents |
|---|---|---|
| `iphone_6.9/` | 2868 × 1320 | Complete nine-image set |
| `ipad_13/` | 2752 × 2064 | Complete nine-image set |
| `iphone_6.1/` | 2622 × 1206 | Only replacements 03 and 04, rendered natively for the existing iPhone slot |

Use the two `iphone_6.1/` files to replace the current iPhone images without
resizing. Keep the other seven currently uploaded iPhone images. If Apple's
validation requires the large-device slot, add the complete nine-image
`iphone_6.9/` set as well. The two-file folder is not a complete store set.
The most recent Apple snapshot has nine images in `APP_IPHONE_61` and
`APP_IPAD_PRO_3GEN_129`; do not assume this proves the large iPhone slot is
covered. Add the complete 6.9-inch set in Media Manager and verify Apple's
submission validation. The public screenshots have no debug overlays.

Captures use the real game and original assets with fictional players and
test-double services. They do not verify Metal performance or live networking.
No gameplay or shipped asset changes are required by this screenshot update.
The iPad basketball capture logged a wait timeout after its staged shot;
the final frame was checked and shows the actual in-game celebration. This
capture is evidence of the screen, not a measurement of shot timing or
network reliability. Capture logs and a checksum manifest are kept here.

## Pending live verification before submission

1. Attach **2.2 (33)**. The latest Apple snapshot says **NONE ATTACHED**.
2. Ensure **all nine IAPs** are attached to the review submission. Their
   `READY_TO_SUBMIT` status alone does not establish attachment.
3. Verify App Privacy is **published**, with the data types in F6 of
   `../SUBMISSION_STEPS.md`. This API report cannot prove that.
4. The age declaration is verified (see the table above). Do not change it
   just because older notes listed it as unknown.
5. Check that both Game Center leaderboards are included, their start time
   matches the intended season, and the app's preview rules are reachable.
6. Check Paid Apps, tax/banking and App Store Server Notifications in the
   account. Product records alone do not prove those are configured.
7. Verify sandbox purchase, cancel, restore, delivery and profile deletion
   on a live-configured device. The name/party confirmation does not cover them.
8. Replace the images, verify all uploads finish, and read Apple's final
   validation screen. Set **Manually release this version** if release-day
   control is wanted; the snapshot currently says `AFTER_APPROVAL`.

The API lists the current iPad filenames in reverse order (09 to 01).
Verify and correct their visible order in Media Manager so gameplay image
01 leads; confirm visually rather than inferring final display order from
filenames alone.

The public website and both config endpoints returned HTTP 403 / error
1010 to the automated checks, including the GitHub runner. This does not
prove they fail on a phone, but it prevents calling live-link verification
complete. Confirm the privacy and support pages in Safari and resolve any
access restriction affecting App Review before submission.

App Store Connect sign-in did not complete in this session. **Nothing was
submitted or released.** Apple makes the final review decision; these checks
reduce known rejection risks but cannot guarantee first-pass approval.

## Repeatable read-only audit

`.github/workflows/submission-audit.yml` runs on this audit branch. It checks
screenshot format, the service suite, public website/config endpoints and
the Apple listing using the existing repository credentials. It makes no
App Store Connect changes and never submits or releases a build. Reports
are uploaded as `submission33-read-only-audit`.
