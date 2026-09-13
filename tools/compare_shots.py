#!/usr/bin/env python3
"""Tolerant screenshot comparison for CI (stdlib only).

Byte-identical renders hold on one machine, but CoreText antialiasing
coverage varies by a few levels across macOS builds, so cross-machine
CI compares decoded pixels instead of bytes:

- dimensions must match exactly (layout is deterministic),
- per-pixel channel delta <= MAX_DELTA (calibrated: worst observed 2),
- fraction of differing pixels <= MAX_FRAC (calibrated: worst 0.45%).

Real regressions (a moved bar or glyph) shift thousands of pixels and
fail loudly. Usage: compare_shots.py <baseline_dir> <fresh_dir>.
"""
import os
import struct
import sys
import zlib

MAX_DELTA = 16
MAX_FRAC = 0.01


def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != bytes([137, 80, 78, 71, 13, 10, 26, 10]):
        raise ValueError("not a PNG: " + path)
    pos, raw, size, ctype, depth, inter = 8, b"", None, 0, 0, 0
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
            size = (w, h)
        elif typ == b"IDAT":
            raw += body
        elif typ == b"IEND":
            break
        pos += 12 + ln
    if size is None or depth != 8 or ctype not in (2, 6) or inter != 0:
        raise ValueError("unsupported PNG format: " + path)
    w, h = size
    ch = 4 if ctype == 6 else 3
    stride = w * ch
    px = zlib.decompress(raw)
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = px[p]
        p += 1
        line = bytearray(px[p:p + stride])
        p += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif f != 0:
            raise ValueError("bad filter %d in %s" % (f, path))
        prev = bytearray(line)
        if ch == 3:
            rgba = bytearray(w * 4)
            rgba[0::4], rgba[1::4], rgba[2::4] = line[0::3], line[1::3], line[2::3]
            rgba[3::4] = b"\xff" * w
            line = rgba
        out[y * w * 4:(y + 1) * w * 4] = line
    return size, bytes(out)


def compare(base_path, fresh_path):
    """Return (ok, detail)."""
    try:
        (bw, bh), bp = read_png(base_path)
    except (OSError, ValueError) as e:
        return False, "unreadable baseline: %s" % e
    try:
        (fw, fh), fp = read_png(fresh_path)
    except (OSError, ValueError) as e:
        return False, "unreadable render: %s" % e
    if (bw, bh) != (fw, fh):
        return False, "size %dx%d vs %dx%d" % (bw, bh, fw, fh)
    ndiff, worst = 0, 0
    for x, y in zip(bp, fp):
        d = abs(x - y)
        if d:
            if d > MAX_DELTA:
                return False, "pixel delta %d exceeds %d" % (d, MAX_DELTA)
            if d > worst:
                worst = d
            ndiff += 1
    frac = ndiff / (bw * bh * 4)
    if frac > MAX_FRAC:
        return False, "%.3f%% pixels differ (cap %.1f%%)" % (frac * 100, MAX_FRAC * 100)
    return True, "%.3f%% px differ, max delta %d" % (frac * 100, worst)


def main():
    base_dir, fresh_dir = sys.argv[1], sys.argv[2]
    base = set(f for f in os.listdir(base_dir) if f.endswith(".png"))
    fresh = set(f for f in os.listdir(fresh_dir) if f.endswith(".png"))
    bad = []
    for name in sorted(base - fresh):
        bad.append((name, "missing from fresh render"))
    for name in sorted(fresh - base):
        bad.append((name, "unexpected extra render"))
    worst_detail, worst_name = "", ""
    for name in sorted(base & fresh):
        ok, detail = compare(os.path.join(base_dir, name),
                             os.path.join(fresh_dir, name))
        if not ok:
            bad.append((name, detail))
        elif detail > worst_detail:
            worst_detail, worst_name = detail, name
    if bad:
        print("SHOT DRIFT (%d):" % len(bad))
        for name, detail in bad:
            print("  %s: %s" % (name, detail))
        return 1
    print("shots match (%d files; noisiest %s: %s)" %
          (len(base & fresh), worst_name, worst_detail))
    return 0


if __name__ == "__main__":
    sys.exit(main())
