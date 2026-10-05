# Lobby music: "Night Campus Loop" (V6)

The owner's track "Night Campus Loop" replaces the synthesized menu music. It
plays on home, party, Locker (wardrobe), Shop, Season Pass, settings and
results. It fades in when you
arrive, keeps playing when you move between those screens, fades out when a
round starts, and comes back afterwards.

This change was prepared in its own session and branch
(`claude/wonderful-feynman-uzn7vg`, on top of the TestFlight branch) so that
the V6 session can merge it into the next TestFlight build. See
[Integration](#integration-into-the-next-testflight-build).

## Files

| File | Change |
|---|---|
| `game/assets/audio/music_menu.ogg` | **Replaced.** It now holds the intro and a 12-bar loop: 54.6 s, Ogg Vorbis q5, stereo 44.1 kHz, 829 KB, −23 LUFS. |
| `game/assets/audio/music_menu.ogg.import` | `loop=true`, `loop_offset=20.327426304`. The uid is unchanged. |
| `game/src/autoload/audio_service.gd` | Music section only (sound effects are unchanged): two voices with cross-fades, no restarts, mute and backgrounding. The API is the same (`music()`, `stop_music()`, `set_volumes()`), plus `current_music()` and `fade_out_time()`. |
| `game/tests/test_lobby_music.gd` (+ `.uid`) | **New.** 6 tests, 50 checks. |
| `tools/make_lobby_music.py` | **New.** Builds the `.ogg` from the source and writes the loop point into the `.import` file. The output is deterministic (same bytes on every run). |
| `art_src/audio/night_campus_loop_source.m4a` | **New.** The recording's audio stream, copied losslessly (it decodes bit-identically to the MP4's audio). It is outside `game/`, so it is never exported. |
| `tools/gen_audio.py`, `tools/gen_audio.sh` | They no longer synthesize `music_menu` (otherwise regenerating would overwrite the track). |
| `ASSET_LICENSES.md` | One row narrowed (music loops 3 → 2) and one row added for the owner's track. |
| `docs/LOBBY_MUSIC.md`, `docs/media/v6/lobby_music/loop_verification.png` | **New.** This document and the verification figure. |

No calling code changed: `app.gd` and `match_controller.gd` already call
`Sfx.music("menu")`, `"chase_calm"` and `"results"` in the right places.
Nothing in `project.godot`, the export presets or the CI workflow changed.

## The loop

The source is the owner's screen recording of the mureka.ai player
(`ScreenRecording_10-02-2026 10-12-46_1.MP4`): 61.07 s, AAC-LC 125 kb/s,
stereo. No higher-quality copy of this track was available. The recording
appears to be the service's one-minute preview (the player shows
"Upgrade for full song"). If a download of the full song becomes available,
see [Rebuilding](#rebuilding-or-replacing-the-track).

What the analysis found:
- **Tempo:** exactly **84.000 BPM** in 4/4 (8th-note hats, 16th-note
  subdivisions). A bar is exactly 126 000 samples. A grid fit at 84.000 BPM
  scored 3× higher than at ±0.05 BPM.
- **Form:** about 1.7 s of recording silence, then a sparse 4-bar intro
  (1.72–13.34 s), an 8-bar main section with a one-bar breakdown at its end,
  a fuller 4-bar restatement of the intro, and the main section again. At
  58.3 s the preview fades out. So the music repeats with a **12-bar lag**.
- **The repeat** is a separate rendering, not a copy (waveform correlation
  0.1–0.4). Its drum hits line up with the first pass: median offset 0.4 ms,
  ±2 ms.

How the loop is built:
- **Intro:** the file plays from the first note (silence removed) up to the
  loop point once, on lobby entry. It is the sparse intro plus three bars of
  the main section, 20.33 s.
- **Loop:** from the **downbeat of bar 4 of the main section** (21.912 s in
  the recording) to the same downbeat 12 bars later (56.197 s). That is
  1 511 996 samples (34.286 s). The second pass sits 4 samples early, and the
  loop length takes that into account.
- **Seam:** a 20 ms equal-power cross-fade from the second pass into the
  first. It ends 3 ms before the downbeat's attack, so every drum hit comes
  from one pass only. Nothing is doubled, and the attack masks the switch.
- **Rejected seams:**
  - The section start (13.34 s): the sparse intro before it has no bass
    (−66 dB), which would leave a 10–20 ms bass hole before every loop.
  - Long cross-fades (0.7–2.9 s): the two passes' pads and bass are not in
    phase, which caused level dips up to 4–7 dB.
- **Not used:** the leading silence, the preview's fade-out, and the video.
- **Level:** the loop is set to −23 LUFS, the same as the menu music it
  replaces (chase and results are −22). The in-game balance against sound
  effects and the central music trim (`MUSIC_TRIM_DB`, −6 dB in 1.5, **−3 dB from V7**) applies to every track.

## How it plays (`audio_service.gd`)

- **Gapless loop.** Godot loops the Ogg Vorbis stream in the mixer
  (`loop` + `loop_offset`) with sample accuracy. There is no timer and no
  restart.
- **One track, two voices.** Music uses two `AudioStreamPlayer`s that are
  created once, so changing track is a cross-fade. `music(name)` behaves like
  this:
  - Asking for the track that is already playing does nothing (no restart).
    Home → wardrobe → settings → party never restarts it.
  - Asking for a track that is still fading out brings it back from where it
    is. Leaving a round within the fade picks up the same playback.
- **Fades:**

  | Moment | What happens |
  |---|---|
  | Entering the lobby | The lobby track starts from its intro and fades in over 2.5 s (equal-power curve). |
  | A round starts | `match_controller` starts the round music when the round is prepared. Pass 9: the owner's "Soft Bounce Loop" (`match`) starts on the lobby music's beat and the lobby track fades out over 2 s under a closing low-pass filter (docs/pass9/music.md); before, `chase_calm` with a 1.2 s fade. During loading the lobby track keeps playing. |
  | Back to the lobby (results, party) | The lobby track starts from its intro again and fades in over 2.5 s. The outgoing track fades out under it. |
  | Chase music leaving | 0.4 s, close to the old cut but without a click. The results sting still starts at full level. |

- **Volume and mute:** the level follows Settings › Music, as before
  (`linear_to_db(music) + MUSIC_TRIM_DB`; −3 dB from V7, about 3 dB louder than 1.5 at every slider position; saved slider values and mute are untouched). Headroom: true peaks are −10.9 dBFS (lobby) and −5.0 (chase, results), so music peaks at −8 dBFS at the top of the slider; a hard limiter on Master (ceiling −0.3 dB) catches a rare music + effect (−1.3 dBFS) coincidence instead of clipping. At 0 the stream pauses instead of decoding
  silence. Raising the slider continues the same playback.
- **Backgrounding and interruptions** (`APPLICATION_PAUSED`/`FOCUS_OUT`,
  which Godot's iOS layer also sends for audio-session interruptions such as
  calls and Siri, and for Control Center): the music pauses where it is, and
  a fade that was in progress finishes. On return the same playback continues
  and fades in over 0.8 s, so it never resumes at full volume. Mute is kept
  through the trip.
- **iOS silent switch:** the project uses Godot's default audio session
  (Ambient), so the Ring/Silent switch mutes the music, as it already did.
  Nothing was changed here.

## Verification (what was actually run)

All of this ran on Linux with the pinned Godot 4.7.2 and ffmpeg. Nothing was
heard on a device: "listening" here means numerical analysis of the engine's
own output, described below.

- **Engine render, 12 wraps:** `AudioStreamPlayback.mix_audio()` decoded the
  imported asset through Godot's own Ogg playback path, in irregular buffer
  sizes (127–2048 frames), for the intro plus 12 wraps (432.7 s):
  - The output matches the ideal sequence (intro, then the loop repeated) to
    within 1e-7 at every point checked. The offset is a constant 2 samples
    from the first frame to the 12th wrap: the mixer's resampler emits 2
    silent frames when a playback starts, and a wrap doesn't. So the loop
    period is exact and nothing drifts.
  - Every one of the 11 fully analysed wraps has no gap (longest
    near-silent run 0) and no click (largest second difference 0.0047, where
    the music itself has a p99 of 0.0106 and a maximum of 0.0226).
  - The level is identical at each wrap: +0.20 dB from the 2 s before to the
    2 s after. The original song steps +0.14 dB (second pass) and +0.65 dB
    (first pass) at the same downbeat.
  - The rhythm is continuous: the onset interval across each wrap is 2.015
    sixteenths. Inside the loop, intervals vary by ±0.08 sixteenths.
  - There is no recurring fade: over 10 laps the 400 ms level never drops
    below −31.3 dB (the song's own breakdown bar; median −24.4 dB).
  - See `docs/media/v6/lobby_music/loop_verification.png`.
- **iOS export:** an export with the real iOS preset (`--export-pack "iOS"`)
  contains `music_menu` with `loop=true` and `loop_offset=20.327`. Played
  from the packaged data, one lap later the samples are identical (max
  difference 0.0). The source `.m4a`, the build script and the tests are not
  in the package.
- **Tests:** `test_lobby_music` (6 tests, 50 checks), on the TestFlight
  branch head:
  - The loop is exact sample for sample, with no gap or click at the wrap.
  - One playback runs through the real tab bar (home → Locker → Shop →
    Season Pass → home), then settings and the party room.
  - A real practice round: the lobby music carries on while the round
    prepares, the chase music takes over and the lobby fades out, the lobby
    fades back in on return, and a quick return picks up the same playback.
  - Volume and mute.
  - Backgrounding and interruption, including mid-cross-fade and while muted.
  - Rapid switching creates no players and never doubles up.
- **Full suite** on `139e361` plus this change: **230 tests, 3381 checks,
  0 failures**. `tools/check.sh` is clean.

## Not verified here (device checks)

These need an iPhone or iPad with the TestFlight build:
1. Listen through at least ten loop wraps on the device speaker and on
   headphones (about 6 minutes in the lobby). The first wrap comes 54.6 s
   after the music starts, then every 34.3 s, on a downbeat just after a
   bright cymbal swell.
2. Home → Locker → Shop → Season Pass → settings → party → home: the music
   never restarts or dips.
3. Start a practice round: the music carries on through loading and fades
   as the round appears. Finish or leave: it fades back in from the intro.
4. Settings › Music: drag to 0 (silence, paused), then back up (it continues).
5. Lock the phone or switch apps, then return (it fades back in where it
   was). Take a call or trigger Siri in the lobby (the same). Pull down
   Control Center (it pauses, then fades back).
6. Ring/Silent switch on silent: the music is muted (Ambient session,
   unchanged).

## Integration into the next TestFlight build

For the session that owns the TestFlight archive and upload:

1. Merge `origin/claude/wonderful-feynman-uzn7vg` into the TestFlight branch
   (a merge commit; the branch is based on the TestFlight head).
   - The only shared file this change edits is `ASSET_LICENSES.md` (the
     "Sound effects (22) and music loops" row, and a new row after it). If
     that conflicts, keep both sides.
   - `audio_service.gd`, the audio assets and `tools/gen_audio.*` had not
     been touched since V1.
2. Run `tools/gd.sh --headless --path game --import` (it re-imports
   `music_menu.ogg` with the new loop point), then run
   `tools/run_tests.sh test_lobby_music` and the full suite.
3. Archive and upload as usual. No settings, presets, signing or workflow
   changes are needed. The app grows by about 0.7 MB (the old menu music was
   110 KB).
4. A possible What to Test line: "New lobby music (Night Campus Loop): it
   fades in on home, plays on through wardrobe and settings, fades out when a
   round starts and comes back after. Listen for any gap or click when it
   loops (about every 34 s)."
5. Please don't call `Sfx.music()` from new menu screens. The lobby track
   keeps playing by itself through the Shop and Season Pass. A screen that
   should have its own music can call `Sfx.music(name)`, and it will
   cross-fade.

## Rebuilding or replacing the track

`python3 tools/make_lobby_music.py` rebuilds `music_menu.ogg` and its loop
point from `art_src/audio/night_campus_loop_source.m4a` (numpy and ffmpeg).
The cut points (`SECTION`, `LOOP_START`, `LOOP_LEN`, `XFADE*`) were measured
on this recording.

A different master of the same song (for example a full-length download) can
be dropped in as the source, but the section start and the pass offset must
be re-measured, because a full song has a different length and form. The
level target (`TARGET_LUFS`) is one constant.

Provenance and rights are the owner's, including the generation service's
terms for commercial use. The recording shows the free-plan player, so
please confirm the plan covers App Store release before the game ships
beyond TestFlight.
