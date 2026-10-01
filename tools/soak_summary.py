#!/usr/bin/env python3
"""Summarise a tools/net_soak.sh run directory as a Markdown table.
Usage: python3 tools/soak_summary.py docs/test-data/net_soak_7c_60ms_0.03
Only completed rounds (rows with snapshot/correction stats) are reported."""
import glob, json, os, sys

d = sys.argv[1]
rows = []
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    name = os.path.basename(f)[:-5]
    try:
        data = json.load(open(f))
    except Exception as e:  # a process that never wrote its report
        rows.append((name, None, str(e)))
        continue
    for r in data:
        if "fps_avg" in r:
            rows.append((name, r, ""))
outcomes = {1: "Runners win", 2: "Night Watch win"}
print(f"| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for name, r, err in rows:
    if r is None:
        print(f"| {name} | - | report missing ({err}) |||||||||")
        continue
    starved = ""
    if "host_starved" in r:
        s = sum(r["host_starved"].values()); k = sum(r["host_skipped"].values())
        starved = f"{s} starved / {k} skipped ticks (all clients)"
    corr_avg = f"{r['corr_avg_m'] * 1000:.1f} mm" if r.get("snapshots") else "host (no prediction)"
    corr_max = f"{r['corr_max_m']:.2f} m" if r.get("snapshots") else ""
    print(f"| {name} | {r['round']} | {outcomes.get(r['outcome'], r['outcome'])} | {r['finished']}/4 | {(str(round(r['rtt_ms'])) + ' ms') if r.get('snapshots') else '-'} | {r.get('snapshots', 0)} | {corr_avg} | {corr_max} | {r.get('fps_avg', 0):.0f} | {r.get('sent', '')} | {r.get('dropped_by_shaper', '')} | {starved} |")
