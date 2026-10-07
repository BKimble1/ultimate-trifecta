#!/usr/bin/env python3
"""Summarise V8 gameplay-bench runs (tools/match_bench.sh JSON) into a table.

    tools/bench_summary.py docs/v8/data before_std60 after_std60 [before_bat30 after_bat30 ...]

Each name is a run-set prefix: every <dir>/<prefix>_run*.json is one run.
Per set it prints the median and range over its runs of the engine-loop
interval percentiles, the long-frame counts (all frames of the PLAYING
context), the longest cluster of frames over 33.3 ms, the mean / p99 / max
of the main CPU sections, slow bot path searches, and the frames whose
cost no instrumented section explains.  Desktop numbers, never a phone's.
"""
import glob
import json
import os
import statistics
import sys

KEYS = [("p50", lambda d: d["interval"]["p50"]), ("p95", lambda d: d["interval"]["p95"]),
        ("p99", lambda d: d["interval"]["p99"]), ("max", lambda d: d["interval"]["max"]),
        (">33.3", lambda d: d["interval"]["over33"]), (">50", lambda d: d["interval"]["over50"]),
        (">100", lambda d: d["interval"]["over100"]),
        ("clusters", lambda d: d["interval"]["clusters"]["runs"]),
        ("longest cluster ms", lambda d: d["interval"]["clusters"]["longest_ms"])]
SECTIONS = ["tick", "sim_bots", "sim_move", "sim_carts", "sim_rules", "views", "anim_advance", "mod_footlock",
            "mod_secondary", "mod_posefade", "mc_apply", "mc_events", "mc_world", "mc_camera", "hud_refresh", "fx", "governor"]


def load(d, prefix):
    out = []
    for p in sorted(glob.glob(os.path.join(d, prefix + "_run*.json"))):
        with open(p) as f:
            out.append(json.load(f))
    return out


def fmt(vals):
    if not vals:
        return "-"
    med = statistics.median(vals)
    lo, hi = min(vals), max(vals)
    if isinstance(vals[0], int) and all(isinstance(v, int) for v in vals):
        return "%d (%d-%d)" % (med, lo, hi) if lo != hi else "%d" % med
    return "%.2f (%.2f-%.2f)" % (med, lo, hi) if abs(hi - lo) > 1e-9 else "%.2f" % med


def unexplained(d, gap_ms=25.0):
    """Long frames (> 33.3 ms) where the instrumented sections explain less
    than (interval - gap_ms): something outside them (the engine, the OS)."""
    n = 0
    for w in d.get("worst_frames", []):
        acc = sum(float(w.get(k, 0.0)) for k in ("tick", "views", "mc_apply", "mc_events", "mc_world", "mc_camera",
                                                 "hud_refresh", "fx", "governor", "hud_process"))
        if w["iv"] > 33.3 and w["iv"] - acc > gap_ms + 16.7:
            n += 1
    return n


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    d = sys.argv[1]
    sets = sys.argv[2:]
    data = {s: load(d, s) for s in sets}
    print("| metric | " + " | ".join("%s (%d runs)" % (s, len(data[s])) for s in sets) + " |")
    print("|---|" + "---|" * len(sets))
    for name, fn in KEYS:
        print("| %s | %s |" % (name, " | ".join(fmt([fn(r) for r in data[s]]) for s in sets)))
    print("| frames | %s |" % " | ".join(fmt([r["frames"] for r in data[s]]) for s in sets))
    for sec in SECTIONS:
        for stat in ("mean", "p99", "max"):
            row = []
            for s in sets:
                vals = [r["sections"][sec][stat] for r in data[s] if sec in r["sections"]]
                row.append(fmt(vals))
            if any(x != "-" for x in row):
                print("| %s %s ms | %s |" % (sec, stat, " | ".join(row)))
    row = []
    for s in sets:
        vals = []
        for r in data[s]:
            vals.append(len(r.get("slow_searches", [])))
        row.append(fmt(vals))
    print("| path searches > 8 ms (build 6: on the main thread; V8: on a worker) | %s |" % " | ".join(row))
    row = []
    for s in sets:
        vals = [r["nav"]["waits"] for r in data[s] if r.get("nav", {}).get("waits") is not None]
        ms = [r["nav"]["waited_ms"] for r in data[s] if r.get("nav", {}).get("waited_ms") is not None]
        row.append(("%s waits, %s ms" % (fmt(vals), fmt(ms))) if vals else "(searched on the main thread)")
    print("| main thread waited for a worker search | %s |" % " | ".join(row))
    print("| worst-15 frames not explained by any section | %s |" % " | ".join(fmt([unexplained(r) for r in data[s]]) for s in sets))
    # each round's start: the scene's size and its loading (every round of every run)
    for key, label in (("nodes", "nodes in a round"), ("static_mb", "static memory MB"),
                       ("collision_shapes", "host collision shapes"), ("prepare_ms", "round prepares in ms"),
                       ("prep_frames", "loading frames"), ("prep_longest", "longest loading job ms")):
        row = []
        for s in sets:
            vals = [float(rs[key]) for r in data[s] for rs in r.get("round_starts", []) if rs.get(key) is not None]
            row.append(fmt(vals))
        if any(x != "-" for x in row):
            print("| %s | %s |" % (label, " | ".join(row)))
    # RENDER=1 runs: one sample a second while playing (software rendered: counts, not timing)
    for key, label in (("draw", "draw calls a frame (llvmpipe)"), ("prims", "primitives a frame (llvmpipe)")):
        row = []
        for s in sets:
            vals = [float(x[key]) for r in data[s] for x in r.get("render", [])]
            row.append(("%.0f (p95 %.0f)" % (statistics.median(vals), sorted(vals)[int(0.95 * (len(vals) - 1))])) if vals else "-")
        if any(x != "-" for x in row):
            print("| %s | %s |" % (label, " | ".join(row)))


if __name__ == "__main__":
    main()
