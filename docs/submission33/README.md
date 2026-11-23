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

The game suite and final screenshot checks are in progress; their final
results will be added before this audit is marked complete.

## Screenshot replacement map

The main upload folders are `docs/media/final/store/iphone_6.9/` and
`docs/media/final/store/ipad_13/`. Upload in numeric order, 01 through 09.

| File | Replace in | Reason |
|---|---|---|
| `03_party_in_the_dorm.png` | iPhone and iPad | Build 33 changed Copy code to **Leave party**, added ready checks and requires the leader to ready up |
| `04_basketball_in_the_dorm.png` | iPhone and iPad | Refresh the basketball screen from build 33 after the Dunk/Block and walk-control changes |

The 6.9-inch set is 2868 × 1320. The 13-inch iPad set is 2752 × 2064.
The most recent Apple snapshot has nine images in `APP_IPHONE_61` and
`APP_IPAD_PRO_3GEN_129`; do not assume this proves the large iPhone slot is
covered. Add the complete 6.9-inch set in Media Manager and verify Apple's
submission validation. The public screenshots have no debug overlays.

Captures use the real game and original assets with fictional players and
test-double services. They do not verify Metal performance or live networking.
No gameplay or shipped asset changes are required by this screenshot update.

## Pending live verification before submission

1. Attach **2.2 (33)**. The latest Apple snapshot says **NONE ATTACHED**.
2. Ensure **all nine IAPs** are attached to the review submission. Their
   `READY_TO_SUBMIT` status alone does not establish attachment.
3. Verify App Privacy is **published**, with the data types in F6 of
   `../SUBMISSION_STEPS.md`. This API report cannot prove that.
4. Verify the age declaration includes the contest, user-generated content
   and messaging/chat. Merely having a 12+ rating does not prove each answer.
5. Check that both Game Center leaderboards are included, their start time
   matches the intended season, and the app's preview rules are reachable.
6. Check Paid Apps, tax/banking and App Store Server Notifications in the
   account. Product records alone do not prove those are configured.
7. Verify sandbox purchase, cancel, restore, delivery and profile deletion
   on a live-configured device. The name/party confirmation does not cover them.
8. Replace the images, verify all uploads finish, and read Apple's final
   validation screen. Set **Manually release this version** if release-day
   control is wanted; the snapshot currently says `AFTER_APPROVAL`.

App Store Connect sign-in did not complete in this session. **Nothing was
submitted or released.** Apple makes the final review decision; these checks
reduce known rejection risks but cannot guarantee first-pass approval.

## Repeatable read-only audit

`.github/workflows/submission-audit.yml` runs on this audit branch. It checks
screenshot format, the service suite, public website/config endpoints and
the Apple listing using the existing repository credentials. It makes no
App Store Connect changes and never submits or releases a build. Reports
are uploaded as `submission33-read-only-audit`.
