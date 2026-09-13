#!/usr/bin/env python3
"""Exact PNG dimension equality between two render dirs (stdlib only).

Layout is deterministic: two backends rendering the same corpus from
the same tree must produce identical canvas sizes for every case.
Pixels are out of scope here (see tools/compare_shots.py, which is
calibrated same-rasterizer). Usage: dim_equal.py <dirA> <dirB>.
"""
import os
import struct
import sys


def dims(path):
    with open(path, "rb") as f:
        data = f.read(33)
    if data[:8] != bytes([137, 80, 78, 71, 13, 10, 26, 10]):
        raise ValueError("not a PNG: " + path)
    return struct.unpack(">II", data[16:24])


def main():
    a, b = sys.argv[1], sys.argv[2]
    names = sorted(f for f in os.listdir(a) if f.endswith(".png"))
    bad = 0
    for f in names:
        q = os.path.join(b, f)
        if not os.path.exists(q):
            print("missing in %s: %s" % (b, f))
            bad += 1
        elif dims(os.path.join(a, f)) != dims(q):
            print("dim mismatch: %s %s vs %s" % (f, dims(os.path.join(a, f)), dims(q)))
            bad += 1
    print("%d cases, %d mismatches" % (len(names), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
