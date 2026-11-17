#!/usr/bin/env python3
"""Cuts the website's videos from film_director recordings.

Input: one or more recordings made by tools/capture_film.sh (film_SEED.avi +
film_SEED.log, whose "FILM" lines are the director's cuts and the round's
events).  Nothing is staged: every frame is the game playing itself.

    python3 tools/website/edit_footage.py OUT_DIR RAW_DIR [--list]

--list prints the moments found (with scores) and builds nothing.

Builds, into OUT_DIR (website/assets/video):
  hero-1600.mp4, hero-960.mp4, hero.jpg    the homepage montage (silent loop)
  trailer.mp4, trailer.jpg                 the montage with the game's sound
  clips/NAME.mp4, clips/NAME.jpg           short loops for the sections
"""
import json
import pathlib
import re
import subprocess
import sys

FPS = 30
GRADE = "eq=contrast=1.05:saturation=1.07:brightness=0.005"


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-3000:])
        raise SystemExit("ffmpeg failed: " + " ".join(cmd[:6]))
    return r


def parse(log: pathlib.Path):
    cuts, events, go, quit_t = [], [], None, None
    for line in log.read_text(errors="ignore").splitlines():
        if line.startswith("FILM t="):
            m = re.match(r"FILM t=([\d.]+) (\w+)(?: (\w+) subj=(-?\d+) aux=(-?\d+))?", line)
            if not m:
                continue
            t = float(m.group(1))
            if m.group(2) == "go":
                go = t
            elif m.group(2) == "quit":
                quit_t = t
            elif m.group(2) == "cut":
                cuts.append({"t": t, "shot": m.group(3), "subj": int(m.group(4)), "aux": int(m.group(5))})
        elif line.startswith("FILMEV t="):
            m = re.match(r"FILMEV t=([\d.]+) (\w+) a=(-?\d+) b=(-?\d+) v=(-?\d+)", line)
            if m:
                events.append({"t": float(m.group(1)), "type": m.group(2), "a": int(m.group(3)), "b": int(m.group(4)), "v": int(m.group(5))})
    return cuts, events, go, quit_t


def duration(avi: pathlib.Path) -> float:
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(avi)])
    v = r.stdout.strip()
    return float(v) if v and v != "N/A" else 1e9


def moments(avi: pathlib.Path, log: pathlib.Path):
    """Scored [start, end) windows worth showing, from the cut list."""
    cuts, events, go, quit_t = parse(log)
    end_all = quit_t or duration(avi)
    out = []
    for i, c in enumerate(cuts):
        s = c["t"]
        e = cuts[i + 1]["t"] if i + 1 < len(cuts) else end_all
        shot = c["shot"]
        if shot == "skip" or e - s < 1.0:
            continue
        inside = [ev for ev in events if s <= ev["t"] < e]
        m = {"src": str(avi), "shot": shot, "subj": c["subj"], "s": s, "e": e, "score": 1.0, "why": ""}
        if shot == "dorm":
            if go:
                m.update(s=max(s, go - 3.2), e=min(e, go + 1.6), score=3.0, why="crew at GO", kind="crew")
        elif shot == "door_out":
            m.update(s=s + 0.1, e=min(e, s + 3.0), score=3.5, why="out the door", kind="run-out")
        elif shot == "water":
            st = [ev for ev in inside if ev["type"] == "SPLASH_STAMP" and ev["a"] == c["subj"]]
            if st:
                t = st[0]["t"]
                m.update(s=max(s, t - 2.3), e=min(e, t + 1.7), score=6.0, why="splash", kind="splash")
            else:
                m.update(score=1.5, kind="runner")
        elif shot == "home":
            fin = [ev for ev in inside if ev["type"] == "FINISH" and ev["a"] == c["subj"]]
            if fin:
                t = fin[0]["t"]
                m.update(s=max(s, t - 2.8), e=min(e, t + 1.2), score=6.0, why="home", kind="home")
            else:
                m.update(score=1.5, kind="runner")
        elif shot in ("chase", "cart_chase"):
            cap = [ev for ev in inside if ev["type"] in ("CAPTURE", "KNOCKED_OUT", "BUMP") and ev["a"] == c["aux"]]
            if cap:
                t = cap[0]["t"]
                m.update(s=max(s, t - 2.6), e=min(e, t + 1.4), score=7.0, why="tag", kind="chase")
            else:
                m.update(s=s + 0.3, e=min(e, s + 3.6), score=3.0, why="chase", kind="chase" if shot == "chase" else "cart")
        elif shot in ("cart_side", "cart_follow"):
            m.update(s=s + 0.4, e=min(e, s + 3.8), score=2.5, why="cart", kind="cart")
        elif shot == "crane":
            m.update(s=s + 0.6, e=min(e, s + 4.6), score=2.2, why="wide", kind="wide")
        else:
            m.update(s=s + 0.4, e=min(e, s + 3.6), score=2.0, why=shot, kind="runner")
        if any(ev["type"] in ("RIFT", "HIDE", "GADGET_USE", "DAZE") for ev in inside):
            m["score"] += 1.0
            m["why"] += " +" + ",".join(sorted({ev["type"].lower() for ev in inside if ev["type"] in ("RIFT", "HIDE", "GADGET_USE", "DAZE")}))
        if m["e"] - m["s"] >= 1.2:
            out.append(m)
    return out


def piece(m, s=None, e=None, w=1600, h=900, audio=False, tag="p", tmp=None):
    """One graded piece as an intermediate file (all-intra, exact length)."""
    s = m["s"] if s is None else s
    e = m["e"] if e is None else e
    name = tmp / f"{tag}_{pathlib.Path(m['src']).stem}_{s:.2f}_{e:.2f}_{w}{'a' if audio else ''}.mkv"
    if name.exists():
        return name
    vf = f"{GRADE},scale={w}:{h}:flags=lanczos,fps={FPS},format=yuv420p"
    cmd = ["ffmpeg", "-v", "error", "-y", "-ss", f"{s:.3f}", "-i", m["src"], "-t", f"{e - s:.3f}", "-vf", vf,
           "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-g", "1"]
    if audio:
        cmd += ["-af", f"aresample=48000,afade=t=in:d=0.04,afade=t=out:st={max(0.0, e - s - 0.06):.3f}:d=0.06", "-c:a", "pcm_s16le", "-ac", "2"]
    else:
        cmd += ["-an"]
    run(cmd + [str(name)])
    return name


def concat(pieces, out, crf, w, h, audio=False, loop_fade=0.0, extra_vf=""):
    """Joins pieces with hard cuts; loop_fade dissolves the end into the start."""
    inputs = []
    for p in pieces:
        inputs += ["-i", str(p)]
    n = len(pieces)
    fc = "".join(f"[{i}:v]" + (f"[{i}:a]" if audio else "") for i in range(n))
    fc += f"concat=n={n}:v=1:a={1 if audio else 0}[v0]" + ("[a0]" if audio else "") + ";"
    if loop_fade > 0:
        total = sum(float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)]).stdout) for p in pieces)
        fc += (f"[v0]split[x][y];[x]trim={loop_fade}:{total},setpts=PTS-STARTPTS[m];"
               f"[y]trim=0:{loop_fade},setpts=PTS-STARTPTS[hd];"
               f"[m][hd]xfade=transition=fade:duration={loop_fade}:offset={total - 2 * loop_fade:.3f}[v1];")
    else:
        fc += "[v0]null[v1];"
    fc += f"[v1]scale={w}:{h}:flags=lanczos{extra_vf},format=yuv420p[v]"
    cmd = ["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", fc, "-map", "[v]"]
    if audio:
        fc_a = ";[a0]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[a1]"
        cmd[cmd.index("-filter_complex") + 1] += fc_a
        cmd += ["-map", "[a1]", "-c:a", "aac", "-b:a", "160k"]
    else:
        cmd += ["-an"]
    cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", str(crf), "-profile:v", "high", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(out)]
    run(cmd)


def poster(src, t, out, w, h):
    run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", str(src), "-frames:v", "1",
         "-vf", f"{GRADE},scale={w}:{h}:flags=lanczos", "-q:v", "3", str(out)])


def main():
    out = pathlib.Path(sys.argv[1])
    raw = pathlib.Path(sys.argv[2])
    listing = "--list" in sys.argv
    plan_file = raw / "edit_plan.json"
    ms = []
    for log in sorted(raw.glob("film_*.log")):
        avi = log.with_suffix(".avi")
        if avi.exists():
            ms += moments(avi, log)
    ms.sort(key=lambda m: -m["score"])
    for m in ms:
        print(f"{m['score']:4.1f} {m.get('kind', '-'):8s} {pathlib.Path(m['src']).stem:9s} {m['s']:7.2f}-{m['e']:7.2f} {m['shot']:10s} subj={m['subj']} {m['why']}")
    if listing:
        return
    plan = json.loads(plan_file.read_text()) if plan_file.exists() else None
    if plan is None:
        raise SystemExit(f"write {plan_file} (hero/trailer/clips as [src, start, end]) after --list")
    tmp = raw / "_pieces"
    tmp.mkdir(exist_ok=True)
    (out / "clips").mkdir(parents=True, exist_ok=True)

    def M(item):
        src, s, e = item[:3]
        return {"src": str(raw / src), "s": float(s), "e": float(e)}

    # the homepage montage: hard cuts, the end dissolving into the start
    if plan.get("hero"):
        hero = [piece(M(x), w=1600, h=900, tmp=tmp) for x in plan["hero"]]
        concat(hero, out / "hero-1600.mp4", 25, 1600, 900, loop_fade=0.6)
        concat(hero, out / "hero-960.mp4", 27, 960, 540, loop_fade=0.6)
        poster(raw / plan["hero_poster"][0], float(plan["hero_poster"][1]), out / "hero.jpg", 1600, 900)
    # the trailer: the game's own sound effects (music muted at recording)
    if "trailer" in plan:
        tr = [piece(M(x), w=1600, h=900, audio=True, tmp=tmp) for x in plan["trailer"]]
        card = raw / "endcard.png"
        if card.exists():
            end = tmp / "endcard.mkv"
            run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-framerate", str(FPS), "-t", "3.4", "-i", str(card),
                 "-f", "lavfi", "-t", "3.4", "-i", "anullsrc=r=48000:cl=stereo",
                 "-vf", "fade=t=in:st=0:d=0.5,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-g", "1",
                 "-c:a", "pcm_s16le", "-shortest", str(end)])
            tr.append(end)
        concat(tr, out / "trailer.mp4", 23, 1600, 900, audio=True)
        poster(raw / plan["hero_poster"][0], float(plan["hero_poster"][1]), out / "trailer.jpg", 1600, 900)
    for name, item in plan.get("clips", {}).items():
        p = piece(M(item), w=960, h=540, tmp=tmp)
        concat([p], out / "clips" / f"{name}.mp4", 27, 960, 540, loop_fade=0.5)
        pt = float(item[3]) if len(item) > 3 else (float(item[1]) + float(item[2])) / 2
        poster(raw / item[0], pt, out / "clips" / f"{name}.jpg", 960, 540)
    print("built", out)


if __name__ == "__main__":
    main()
