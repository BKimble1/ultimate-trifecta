"""Builds the beat-locked trailer timeline for cut_trailer.py.

Every shot lasts a whole number of beats of the score (123 bpm), so every
cut lands on the music.  Source times are recording times (film_time.py
converts the director's log times where slow motion ran)."""
import json
import sys

BEAT = 0.4919            # 122 bpm: beats 0.07 .. 55.16 s of the score
M0 = 3.99                # the score starts at this downbeat (cold open)
FINAL_HIT_M = 55.16      # the button hit in the score

# (src, start, beats[, speed])
SHOTS = [
    # cold open: 6 bars, quiet
    ("../raw2/film_11.avi", 55.7, 8),    # the boathouse dock, clock tower  (title: 3 A.M.)
    ("../raw2/film_11.avi", 65.0, 8),    # crane down onto the rock pond
    ("film_27.avi", 4.05, 8),            # the crew on their pads ... GO on the drop
    # groove: SPLASH THREE
    ("film_27.avi", 7.8, 2),             # GO: they sprint past the camera
    ("film_3.avi", 9.6, 4),              # the burst, wide
    ("film_27.avi", 13.2, 4),            # tracking down the road
    ("film_3.avi", 28.5, 8),             # three into the fountain   (title)
    ("SPLASH2", 0, 3),                   # a slow-motion splash (film_11)
    ("BLACK", 0, 3),                     # the music's break: DON'T GET CAUGHT.
    # chase: tighter and tighter
    ("film_27.avi", 23.5, 4),            # carts on the road
    ("film_3.avi", 49.6, 4),             # past the rift
    ("film_3.avi", 43.9, 2),             # the Night Watch closing in
    ("film_27.avi", 52.0, 4),            # cart by the boathouse
    ("film_3.avi", 52.0, 2),             # a tag
    ("film_27.avi", 85.6, 2),            # the Pillow Shield
    ("film_27.avi", 88.0, 4),            # the shield holds
    ("film_3.avi", 60.5, 4),             # chase down the road, tag, ring
    ("film_27.avi", 75.4, 4),            # slow-motion tag on the rocks
    ("film_3.avi", 69.0, 2),             # the last tag
    # race home
    ("HOME1", 0, 4),
    ("HOME2", 0, 4),
    ("HOME3", 0, 6),
    # the season
    ("../lineup/holiday.avi", 1.4, 10),  # Winter Break
]


def build(extra: dict, out: str):
    items, t, marks = [], 0.0, {}
    for i, sh in enumerate(SHOTS):
        src, s, beats = sh[:3]
        # each cut on the frame nearest its beat, counted from the start, so
        # rounding never accumulates
        f0 = round(t * 30)
        f1 = round((t + beats * BEAT) * 30)
        d = (f1 - f0) / 30
        if src == "BLACK":
            items.append({"black": round(d, 4), "frames": f1 - f0})
        else:
            if src in extra:
                src, s = extra[src]
            items.append({"src": src, "s": round(s, 3), "e": round(s + d, 4), "frames": f1 - f0})
        marks[i] = t
        t += beats * BEAT
    hit_t = FINAL_HIT_M - M0
    tail = 4.4
    items.append({"card": "../cut/endcard.png", "dur": round(tail, 3), "fade_in": 0.001})
    print(f"shots end at {t:.2f}s, final hit at {hit_t:.2f}s (gap {hit_t - t:+.2f})")
    titles = [
        {"png": "../cut/t_3am.png", "at": round(marks[0] + 0.6, 3), "dur": 3.0},
        {"png": "../cut/t_splash.png", "at": round(marks[6] + 0.6, 3), "dur": 2.6},
        {"png": "../cut/t_caught.png", "at": round(marks[8] + 0.05, 3), "dur": 3 * BEAT - 0.1},
        {"png": "../cut/t_home.png", "at": round(marks[19] + 0.4, 3), "dur": 2.4},
        {"png": "../cut/t_season.png", "at": round(marks[22] + 0.6, 3), "dur": 3.0},
    ]
    tl = {"root": sys.argv[1], "size": [1920, 1080], "fps": 30, "music": "../music/score_trim.wav",
          "music_gain_db": 0, "sfx_gain_db": -11, "items": items, "titles": titles, "fade_out": 1.2, "crf": 19}
    json.dump(tl, open(out, "w"), indent=1)
    return t, hit_t


if __name__ == "__main__":
    extra = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    build(extra, sys.argv[2])
