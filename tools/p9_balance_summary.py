#!/usr/bin/env python3
"""Pass 9 balance matrix summary: one table per team configuration comparing
builds (JSON files written by game/tools/p9_balance.gd).

Usage: tools/p9_balance_summary.py LABEL=file.json [LABEL=file.json ...] [--md]
Prints per configuration (Night Watch count) and build: rounds, runner /
Night Watch wins with a 95 % Wilson interval, runners home, captures, stamps,
round length, route time of runners home, first capture, Tag hit rate,
dives, gadget uses, Turbo escapes, chase outcomes and average runner speed
while moving.  Bot rounds on desktop physics, not people.
"""
import json
import math
import sys

GADGETS = {"1": "turbo", "2": "decoy", "3": "bomb"}


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - r) / d, (c + r) / d)


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else float("nan")


def summarize(rows):
    n = len(rows)
    rw = sum(1 for r in rows if r["outcome"] == "runners")
    ww = sum(1 for r in rows if r["outcome"] == "watch")
    lo, hi = wilson(rw, n)
    tags = sum(r["tags"] for r in rows)
    hits = sum(r["tag_hits"] for r in rows)
    turbo = [t for r in rows for t in r.get("turbo", [])]
    t_esc = sum(1 for t in turbo if not t["caught10"])
    t_gain = [t["gap3"] - t["gap0"] for t in turbo if t["gap3"] > 0 and t["gap0"] < 20]
    ch = sum(r["chases"] for r in rows)
    ch_esc = sum(r["chase_escaped"] for r in rows)
    ch_c = sum(r["chase_caught"] for r in rows)
    g = {}
    for r in rows:
        for k, v in r.get("gadgets", {}).items():
            g[GADGETS.get(k, k)] = g.get(GADGETS.get(k, k), 0) + v
    return {
        "n": n, "runner_wins": rw, "watch_wins": ww, "runner_win_pct": 100.0 * rw / n if n else float("nan"),
        "ci": (100 * lo, 100 * hi),
        "home": mean([r["home"] for r in rows]), "needed": rows[0]["needed"] if rows else 0, "runners": rows[0]["runners"] if rows else 0,
        "captures": mean([r["captures"] for r in rows]), "stamps": mean([r["stamps"] for r in rows]),
        "round_s": mean([r["round_s"] for r in rows]),
        "route_s": mean([r["route_median_s"] for r in rows if r["route_median_s"] > 0]),
        "first_capture_s": mean([r["first_capture_s"] for r in rows if r["first_capture_s"] > 0]),
        "tag_hit_pct": 100.0 * hits / tags if tags else float("nan"), "tags": mean([r["tags"] for r in rows]),
        "dives": mean([r["dives"] for r in rows]),
        "gadgets": {k: v / n for k, v in sorted(g.items())},
        "turbo_n": len(turbo), "turbo_escape_pct": 100.0 * t_esc / len(turbo) if turbo else float("nan"),
        "turbo_gain_m": mean(t_gain),
        "chases": ch / n if n else 0, "chase_escape_pct": 100.0 * ch_esc / ch if ch else float("nan"),
        "chase_caught_pct": 100.0 * ch_c / ch if ch else float("nan"),
        "speed": mean([r["runner_speed_moving"] for r in rows]),
    }


def main():
    md = "--md" in sys.argv
    builds = []
    for a in sys.argv[1:]:
        if a.startswith("--"):
            continue
        label, path = a.split("=", 1)
        builds.append((label, json.load(open(path))))
    watches = sorted({r["watch"] for _, rows in builds for r in rows})
    cols = ["build", "rounds", "runner wins (95% CI)", "home / needed", "captures", "stamps", "round s",
            "route s (home)", "1st capture s", "Tag hits", "dives", "gadget uses", "Turbo: no capture 10 s / gap +3 s",
            "chases: escaped / caught", "runner m/s moving"]
    for w in watches:
        print(f"\n### {w} Night Watch" + (" (default)" if w == 2 else ""))
        if md:
            print("\n| " + " | ".join(cols) + " |")
            print("|" + "---|" * len(cols))
        for label, rows in builds:
            s = summarize([r for r in rows if r["watch"] == w])
            if s["n"] == 0:
                continue
            gad = ", ".join(f"{k} {v:.1f}" for k, v in s["gadgets"].items()) or "-"
            vals = [label, str(s["n"]), f"{s['runner_wins']}/{s['n']} = {s['runner_win_pct']:.0f}% ({s['ci'][0]:.0f}-{s['ci'][1]:.0f})",
                    f"{s['home']:.1f} / {s['needed']} of {s['runners']}", f"{s['captures']:.1f}", f"{s['stamps']:.1f}",
                    f"{s['round_s']:.0f}", f"{s['route_s']:.0f}", f"{s['first_capture_s']:.0f}",
                    f"{s['tag_hit_pct']:.0f}% of {s['tags']:.1f}", f"{s['dives']:.0f}", gad,
                    f"{s['turbo_escape_pct']:.0f}% of {s['turbo_n']} / {s['turbo_gain_m']:+.1f} m",
                    f"{s['chase_escape_pct']:.0f}% / {s['chase_caught_pct']:.0f}% of {s['chases']:.1f}", f"{s['speed']:.2f}"]
            if md:
                print("| " + " | ".join(vals) + " |")
            else:
                print("  " + "  ".join(f"{c}: {v}" for c, v in zip(cols, vals)))


if __name__ == "__main__":
    main()
