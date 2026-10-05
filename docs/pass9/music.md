# Pass 9 round music: "Soft Bounce Loop", and the lobby → round blend

The owner asked for their track "Soft Bounce Loop" to become the in-game
soundtrack, with a seamless, good blend from the lobby music into it. It
replaces the synthesized round music (`music_chase_calm.ogg`, removed). The
lobby keeps the owner's "Night Campus Loop".

## Source

- **What was supplied:** a screen recording of the mureka.ai player,
  `ScreenRecording_10-05-2026 07-56-54_1.MP4`. It is 61.8 s of AAC-LC audio
  at 122 kb/s, stereo, 44.1 kHz, showing "Soft Bounce Loop" by Blake Kimble.
  The recording is the first minute of the song. No higher-quality copy was
  available.
- **What was kept:** `art_src/audio/soft_bounce_loop_source.m4a`, the audio
  stream copied losslessly. It decodes to the MP4's samples exactly; the MP4
  starts its audio 1250 samples late through its edit list, and the copy
  keeps those first samples, which are silence. It is outside `game/`, so it
  is never exported. The video is not kept.

## Analysis

All analysis is numerical, with numpy and ffmpeg, done offline.

- **Tempo:** exactly **100.000 BPM** in 4/4. A beat is 26 460 samples and a
  bar 105 840. A grid fit at 100.000 scored highest, against ±0.005 BPM. The
  per-bar onset phase is flat across the whole minute, so there is no drift.
- **Key:** D major. The lobby track is G major, its neighbour on the circle
  of fifths: the two keys share six of seven notes.
- **Form:**
  - a pickup;
  - the first downbeat at 1.028 s;
  - phrases of 8 bars;
  - bars 7–11 return almost unchanged as bars 15–19 (bar-to-bar similarity
    up to 0.69);
  - low-bass breakdown bars at 4, 11 and 20.

## The file (`tools/make_match_music.py`)

- **Intro:** played once. It runs from the pickup beat, one beat before the
  first downbeat, to the downbeat of bar 5. That is 12.60 s.
- **Loop:** the 16 bars from bar 5 to bar 20, 38.40 s. It wraps at the
  downbeat of bar 21 back to bar 5. I ranked candidate seams by how well the
  music continues in the bass, mids and highs, both in the beat before the
  downbeat and in the beat after it:
  - **Chosen, 21 → 5:** similarity ≥ 0.63 in every band (bass 0.94 / 0.78,
    mids 0.80 / 0.63, highs 0.94 / 0.98).
  - **Rejected, the 8-bar seam 15 → 7:** just as smooth, but it would repeat
    every 19 s through a 4-minute round.
  - **Rejected, 20 → 4:** its mids don't continue (−0.51 after the downbeat).
- **Seam:** a 20 ms equal-power cross-fade from the second pass into the
  first, ending 3 ms before the downbeat's attack, so no drum hit is doubled.
  Its sharpness at the wrap (largest second difference 0.150 before, 0.183
  after) equals the song's own bar 5 downbeat (0.150 / 0.183). The
  spectrogram across the wrap matches the natural 20 → 21 and 4 → 5
  transitions.
- **Level:** −23 LUFS integrated over the loop, the lobby track's level, so
  the blend is level. The round music was −22 before. True peak is
  −10.5 dBFS.
- **Encoding:** Ogg Vorbis q5, 805 KB, `loop=true`,
  `loop_offset=12.600011338`. The script writes the loop point into
  `music_match.ogg.import`, and the output is deterministic.

## The blend (`audio_service.gd`)

- **Trigger:** a round is prepared and `MatchController` asks for "match", as
  it asked for "chase_calm" before.
- **Starting on the beat:** both owner tracks have known beat grids
  (`MUSIC_GRID`). The round track starts at once. `blend_start()` picks the
  point in its pickup that makes one of its beats land on the lobby music's
  next beat, so the pulse carries straight through. At most one beat of the
  pickup is skipped, and nothing waits on a timer.
- **The round music** fades in over 1.2 s, two of its beats, on an
  equal-power curve.
- **The lobby music** fades out over 2.0 s. Its voice has its own bus with a
  low-pass filter. During the blend the filter closes from 20 kHz to 260 Hz
  over 1.4 s (smoothstep, exponential in frequency). Its drums and its 84 BPM
  pulse leave first, and a warm G-major pad is left under the round's D-major
  groove. The filter is bypassed at all other times, and reset whenever a
  voice is reused or the lobby music is brought back mid-blend.
- **No blend** when there is no lobby music sounding: muted, backgrounded, or
  a round started from silence. The round music then simply starts.
- **Unchanged:** the round → results change (0.4 s, the sting starts at full
  level) and the → lobby change (a 2.5 s fade-in from the intro).

## Verification

Run on Linux with Godot 4.7.2. Nothing was heard on a device.

- **Engine capture** (`src/dev/music_blend_capture.tscn`, Movie Maker audio,
  the real `AudioService` and mixer). The lobby track played from its start,
  and the round track was requested 18.30 s in.
  - **Beat alignment:** locating both files in the captured mix by
    cross-correlation (r = 1.000 and 0.999), the round track's beat lands
    **1.1 ms** from the lobby's beat at 18.90 s.
  - **Level:** 250 ms RMS stays between −24 and −32 dB before, during and
    after, with no dip or bump.
  - **No click:** the largest second difference around the switch is 0.014.
    The lobby music before it peaks at 0.013, and the round music after it at
    0.062.
- **Evidence:**
  - [blend_spectrogram.png](../media/pass9/music/blend_spectrogram.png);
  - an 11 s excerpt to listen to:
    [blend_lobby_to_round.ogg](../media/pass9/music/blend_lobby_to_round.ogg).
- **Tests:**
  - `test_match_music` (7 tests): the loop, the level match, `blend_start` on
    200 random lobby positions, the filtered blend, bringing the lobby back
    mid-blend, no blend when muted or from silence, and the results change.
    - The loop: one lap later the mixer plays the same samples (difference
      < 1e-6) by looping the stream; no gap; no click; level continuous
      across the wrap.
  - `test_lobby_music` and `test_p8_results_music`, updated for the new track.

## Rebuilding

Run `python3 tools/make_match_music.py` (it needs numpy and ffmpeg). If a
download of the full song becomes available, put its audio in
`art_src/audio/`, re-check the grid constants at the top of the script (the
first downbeat, the loop bars), and re-run the tests.

## Rights

The track is the owner's. It was made with the mureka.ai generation service,
and its provenance and rights, including that service's terms for commercial
use, are the owner's to confirm. See `ASSET_LICENSES.md`.
