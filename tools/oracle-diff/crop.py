#!/usr/bin/env python3
"""Tight-crop oracle renders to their ink bbox (+pad), in place.

Review ask on PR #52: luatex renders arrive as full pages, and every
engine's showcased render should be cropped before comparing and
showcasing. Reuses report.py's PNG codec and crop_pad (ink bbox + 10px
white pad) so the showcase crop is byte-consistent with the report's
own normalization. Idempotent: already-cropped renders rewrite to
(near-)identical bytes. Stdlib only.

Usage: crop.py <png> [<png> ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import report


def main(argv):
    bad = 0
    for path in argv[1:]:
        if not os.path.exists(path):
            continue  # unmatched glob: the render stage already recorded it
        try:
            w, h, px = report.read_png(path)
        except ValueError as e:
            print("crop: skip %s (%s)" % (path, e))
            bad = 1
            continue
        cw, ch, out = report.crop_pad(w, h, px)
        report.write_png(path, cw, ch, out)
        print("crop: %s %dx%d -> %dx%d" % (path, w, h, cw, ch))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv))
