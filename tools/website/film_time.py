#!/usr/bin/env python3
"""Director log time -> recording time.  The director's clock runs at the
game's speed, so during its slow-motion moments ("FILM t=.. speed 0.45")
the recording advances faster than the log: movie = integral of 1/speed."""
import re
import sys


def mapping(log_path):
    pts = []   # (log_t, speed from here)
    for line in open(log_path, errors="ignore"):
        m = re.match(r"FILM t=([\d.]+) speed ([\d.]+)", line)
        if m:
            pts.append((float(m.group(1)), float(m.group(2))))

    def movie(t):
        out, last, sp = 0.0, 0.0, 1.0
        for (pt, s) in pts:
            if pt >= t:
                break
            out += (pt - last) / sp
            last, sp = pt, s
        return out + (t - last) / sp
    return movie


if __name__ == "__main__":
    mv = mapping(sys.argv[1])
    for a in sys.argv[2:]:
        print(a, round(mv(float(a)), 2))
