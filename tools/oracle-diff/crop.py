#!/usr/bin/env python3
"""Tight-crop oracle renders to their ink bbox (+pad), in place.

Review ask on PR #52: luatex renders arrive as full pages, and every
engine's showcased render should be cropped before comparing and
showcasing. Reuses report.py's PNG codec and crop_pad (ink bbox + 10px
white pad) so the showcase crop is byte-consistent with the report's
own normalization. Idempotent: already-cropped renders rewrite to
(near-)identical bytes. Stdlib only.

Files are independent, so they crop in a process pool (default: every
CPU): same functions per file, byte-identical output, ~N× faster wall
clock on the 2000-file sweep. Log order stays in argv order.

Usage: crop.py [--jobs N] <png> [<png> ...]
"""
import os
import sys
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import report


def default_jobs():
    try:
        return os.cpu_count() or 4
    except NotImplementedError:
        return 4


def crop_one(path):
    if not os.path.exists(path):
        return (path, "missing", "", 0)  # unmatched glob: recorded at render stage
    try:
        w, h, px = report.read_png(path)
    except ValueError as e:
        return (path, "skip", str(e), 1)
    cw, ch, out = report.crop_pad(w, h, px)
    report.write_png(path, cw, ch, out)
    return (path, "crop", "%dx%d -> %dx%d" % (w, h, cw, ch), 0)


def main(argv):
    jobs = int(os.environ.get("ORACLE_DIFF_JOBS", default_jobs()))
    paths = []
    i = 1
    while i < len(argv):
        if argv[i] == "--jobs" and i + 1 < len(argv):
            jobs = int(argv[i + 1])
            i += 2
        else:
            paths.append(argv[i])
            i += 1
    if jobs < 1:
        jobs = 1
    bad = 0
    if jobs == 1 or len(paths) < 2:
        results = [crop_one(p) for p in paths]
    else:
        with Pool(min(jobs, len(paths))) as pool:
            # imap preserves argv order, so the log stays deterministic.
            results = pool.imap(crop_one, paths)
            results = list(results)
    for path, kind, msg, rc in results:
        if kind == "missing":
            continue
        elif kind == "skip":
            print("crop: skip %s (%s)" % (path, msg))
        else:
            print("crop: %s %s" % (path, msg))
        bad = max(bad, rc)
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv))
