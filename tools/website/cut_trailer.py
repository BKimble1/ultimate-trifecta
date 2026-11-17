#!/usr/bin/env python3
"""Cuts the trailer from a timeline (JSON) of real gameplay shots.

    python3 tools/website/cut_trailer.py TIMELINE.json OUT.mp4

TIMELINE.json:
{
  "root": "/path/to/recordings",          # sources are relative to this
  "size": [1600, 900], "fps": 30,
  "music": "music.mp3",                    # optional bed; the game's sound
  "music_gain_db": 0, "sfx_gain_db": -9,   #   effects sit under it
  "items": [
    {"src": "film_11.avi", "s": 12.3, "e": 15.1},          # a shot
    {"src": "film_11.avi", "s": 40.0, "e": 42.0, "speed": 0.5},   # slowed further
    {"card": "card_3am.png", "dur": 1.2},                  # a full-screen card
    {"black": 0.4}                                         # a beat of black
  ],
  "titles": [                                             # text over the cut
    {"png": "t_splash.png", "at": 8.2, "dur": 1.6}
  ],
  "fade_out": 0.8
}
Shots are joined with hard cuts (2-frame audio fades so nothing clicks).
"""
import json
import pathlib
import subprocess
import sys

GRADE = "eq=contrast=1.06:saturation=1.08:brightness=0.004"


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-4000:])
        raise SystemExit("ffmpeg failed")
    return r


def dur(p):
    return float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)]).stdout)


def main():
    tl = json.loads(pathlib.Path(sys.argv[1]).read_text())
    out = pathlib.Path(sys.argv[2])
    root = pathlib.Path(tl.get("root", "."))
    W, H = tl.get("size", [1600, 900])
    fps = tl.get("fps", 30)
    tmp = root / "_trailer"
    tmp.mkdir(exist_ok=True)
    parts = []
    import hashlib
    for i, it in enumerate(tl["items"]):
        key = hashlib.sha1(json.dumps([it, W, H, fps, GRADE]).encode()).hexdigest()[:12]
        p = tmp / f"{i:03d}_{key}.mkv"
        parts.append(p)
        if p.exists():
            continue
        common = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-g", "1", "-pix_fmt", "yuv420p",
                  "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2"]
        if "src" in it:
            s, e = float(it["s"]), float(it["e"])
            sp = float(it.get("speed", 1.0))
            vf = f"{GRADE},scale={W}:{H}:flags=lanczos,unsharp=5:5:0.35:5:5:0.0,setpts={1 / sp:.4f}*PTS,fps={fps}"
            n = (e - s) / sp
            af = f"atempo={max(0.5, sp):.3f}," if sp != 1.0 else ""
            af += f"afade=t=in:d=0.04,afade=t=out:st={max(0.0, n - 0.06):.3f}:d=0.06"
            run(["ffmpeg", "-v", "error", "-y", "-ss", f"{s:.3f}", "-t", f"{e - s:.3f}", "-i", str(root / it["src"]),
                 "-vf", vf, "-af", af, "-t", f"{n:.3f}", *common, str(p)])
        elif "card" in it:
            d = float(it["dur"])
            fi = float(it.get("fade_in", 0.25))
            run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-framerate", str(fps), "-t", f"{d:.3f}", "-i", str(root / it["card"]),
                 "-f", "lavfi", "-t", f"{d:.3f}", "-i", "anullsrc=r=48000:cl=stereo",
                 "-vf", f"scale={W}:{H},fade=t=in:st=0:d={fi},format=yuv420p", "-shortest", *common, str(p)])
        elif "black" in it:
            d = float(it["black"])
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-t", f"{d:.3f}", "-i", f"color=c=0x070b16:s={W}x{H}:r={fps}",
                 "-f", "lavfi", "-t", f"{d:.3f}", "-i", "anullsrc=r=48000:cl=stereo", "-shortest", *common, str(p)])
    # join
    lst = tmp / "list.txt"
    lst.write_text("".join(f"file '{p.name}'\n" for p in parts))
    joined = tmp / "joined.mkv"
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(joined)])
    total = dur(joined)
    # titles over the cut, then the music bed under / over the effects
    inputs = ["-i", str(joined)]
    fc = "[0:v]null[v0];"
    cur = "v0"
    for k, t in enumerate(tl.get("titles", [])):
        inputs += ["-loop", "1", "-framerate", str(fps), "-t", f"{total:.3f}", "-i", str(root / t["png"])]
        a, d = float(t["at"]), float(t["dur"])
        f = 0.22
        fc += (f"[{k + 1}:v]format=rgba,fade=t=in:st={a:.3f}:d={f}:alpha=1,fade=t=out:st={a + d - f:.3f}:d={f}:alpha=1[t{k}];"
               f"[{cur}][t{k}]overlay=0:0:enable='between(t,{a:.3f},{a + d:.3f})'[v{k + 1}];")
        cur = f"v{k + 1}"
    fo = float(tl.get("fade_out", 0.8))
    fc += f"[{cur}]fade=t=out:st={total - fo:.3f}:d={fo},format=yuv420p[v];"
    sfx_db = float(tl.get("sfx_gain_db", -9))
    if tl.get("music"):
        mi = inputs.count("-i")
        inputs += ["-i", str(root / tl["music"])]
        mdb = float(tl.get("music_gain_db", 0))
        fc += (f"[0:a]volume={sfx_db}dB[sfx];[{mi}:a]atrim=0:{total:.3f},asetpts=PTS-STARTPTS,volume={mdb}dB,"
               f"afade=t=out:st={total - fo - 0.4:.3f}:d={fo + 0.4}[mus];[sfx][mus]amix=inputs=2:normalize=0:duration=first,"
               f"loudnorm=I=-15:TP=-1.2:LRA=9,aresample=48000[a]")
    else:
        fc += f"[0:a]afade=t=out:st={total - fo:.3f}:d={fo},loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[a]"
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", fc, "-map", "[v]", "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", str(tl.get("crf", 21)), "-profile:v", "high", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", f"{total:.3f}", str(out)])
    print("wrote", out, f"{total:.2f}s")


if __name__ == "__main__":
    main()
