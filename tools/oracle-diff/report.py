#!/usr/bin/env python3
"""Oracle-diff report generator (issue #39 triage tool, informational only).

Reads one raw PNG per engine per case, normalizes (tight-crop ink bbox +
white pad + uniform rescale to a common height + translation alignment
by ink centroid on the union canvas), compares with block SSIM, scores

    score(c) = max_i sim(ZaTeX_c, Oracle_i_c)

and writes a markdown report sorted worst-first plus the normalized PNGs.

Usage:
    report.py --raw <rawdir> --out <outdir> [--corpus corpus.json]
              [--jobs N, default all CPUs]
    report.py --selfcheck   # SSIM math unit checks + synthetic fixture report

Raw layout: <rawdir>/<case-id>.<engine>.png with engines
zatex | katex | mathjax | luatex. Output: <outdir>/report.md + <outdir>/png/.

Not a gate and not an oracle over pinned KaTeX: see docs/oracle-diff.md.
Stdlib only.
"""
import json
import math
import os
import struct
import sys
import zlib

ENGINES = ("zatex", "katex", "luatex", "mathjax")
# Oracle order (issue #59): MathJax renders last — it is the most
# different engine, so its column closes the row.
ORACLES = ("katex", "luatex", "mathjax")
PAD_PX = 10
NORM_H = 128
INK_THRESH = 240  # channel value below this counts as ink on white
AMBIGUOUS_SPREAD = 0.90  # oracle-oracle min-sim below this tags spec-ambiguous
# Triage tripwire for issue #60: flag rows where ZaTeX-vs-pinned-KaTeX sits
# this far below the oracle-oracle floor (spread). There is deliberately NO
# absolute floor: cross-font spread dominates (even trivial agreement rows
# score ~0.55-0.68, and a fully blank render outscores a real one at 0.66
# vs 0.65 on agree-sum), so an absolute bar either fires on everything or
# blesses blank output. Margin calibration on real 128px-high renders
# (post centroid alignment, which zeroes pure-offset cost): a 6px
# structural shift still costs ~0.06; the one visually confirmed
# structural bug in the 2026-09-13 sweep (space-kern, `I\kern-2.5pt R`)
# sits 0.109 below spread. 0.10 clears noise by an order of magnitude
# while catching it. Triage attention only, never a gate (AGENTS.md
# section 4).
KATEX_OUTLIER_MARGIN = 0.10


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
        raise ValueError("unsupported PNG (want 8-bit RGB/RGBA): " + path)
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
                q = a + b - c
                pa, pb, pc = abs(q - a), abs(q - b), abs(q - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif f != 0:
            raise ValueError("bad PNG filter: " + path)
        prev = line
        for x in range(w):
            o = (y * w + x) * 4
            q = x * ch
            out[o] = line[q]
            out[o + 1] = line[q + 1]
            out[o + 2] = line[q + 2]
            out[o + 3] = line[q + 3] if ch == 4 else 255
    return w, h, out


def write_png(path, w, h, rgba):
    def chunk(typ, body):
        c = struct.pack(">I", len(body)) + typ + body
        return c + struct.pack(">I", zlib.crc32(typ + body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgba[y * w * 4:(y + 1) * w * 4]
    out = bytes([137, 80, 78, 71, 13, 10, 26, 10])
    out += chunk(b"IHDR", ihdr)
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    out += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


def luminance(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def ink_bbox(w, h, px):
    # Fast path: an all-white-opaque row holds no ink (white luminance 255
    # >= INK_THRESH, alpha 255 >= 128), so memcmp it away in C instead of
    # scanning every pixel in Python. Identical bbox; full-page renders
    # are mostly white rows.
    white = bytes([255, 255, 255, 255]) * w
    lum = luminance
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        o0 = y * w * 4
        if px[o0:o0 + w * 4] == white:
            continue
        for x in range(w):
            o = o0 + x * 4
            if px[o + 3] < 128 or lum(px[o], px[o + 1], px[o + 2]) < INK_THRESH:
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    if x1 < 0:
        return (0, 0, w - 1, h - 1)  # blank: keep whole canvas
    return (x0, y0, x1, y1)


def crop_pad(w, h, px):
    x0, y0, x1, y1 = ink_bbox(w, h, px)
    x0 = max(0, x0 - PAD_PX)
    y0 = max(0, y0 - PAD_PX)
    x1 = min(w - 1, x1 + PAD_PX)
    y1 = min(h - 1, y1 + PAD_PX)
    cw, chh = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(cw * chh * 4)
    for y in range(chh):
        for x in range(cw):
            s = ((y0 + y) * w + (x0 + x)) * 4
            o = (y * cw + x) * 4
            out[o:o + 4] = px[s:s + 4]
    return cw, chh, out


def to_gray(w, h, px):
    g = [0.0] * (w * h)
    for i in range(w * h):
        o = i * 4
        a = px[o + 3] / 255.0
        lum = luminance(px[o], px[o + 1], px[o + 2])
        g[i] = 255.0 + (lum - 255.0) * a  # composite over white
    return g


def rescale_gray(w, h, g, new_h):
    if h == 0:
        return 1, [255.0]
    scale = new_h / h
    nw = max(1, int(round(w * scale)))
    out = [255.0] * (nw * new_h)
    for y in range(new_h):
        sy = min(h - 1, int(y / scale))
        for x in range(nw):
            sx = min(w - 1, int(x / scale))
            out[y * nw + x] = g[sy * w + sx]
    return nw, out


def block_ssim(wa, a, wb, b):
    # Both canvases share dims at call time; mean SSIM over 8x8 blocks.
    assert len(a) == len(b)
    n = len(a)
    stride = 8
    K1, K2, L = 0.01, 0.03, 255.0
    C1, C2 = (K1 * L) ** 2, (K2 * L) ** 2
    tot, cnt = 0.0, 0
    for lo in range(0, n, stride * stride):
        blk_a = a[lo:lo + stride * stride]
        blk_b = b[lo:lo + stride * stride]
        m = len(blk_a)
        if m == 0:
            continue
        ma = sum(blk_a) / m
        mb = sum(blk_b) / m
        va = sum((v - ma) ** 2 for v in blk_a) / m
        vb = sum((v - mb) ** 2 for v in blk_b) / m
        cab = sum((x - ma) * (y - mb) for x, y in zip(blk_a, blk_b)) / m
        tot += ((2 * ma * mb + C1) * (2 * cab + C2) /
                ((ma * ma + mb * mb + C1) * (va + vb + C2)))
        cnt += 1
    return tot / cnt if cnt else 1.0


def ink_centroid(nw, nh, g):
    """Ink center of mass in canvas coords; canvas center when blank
    (two blank canvases then align to each other, never drift)."""
    sx = sy = n = 0
    for y in range(nh):
        row = y * nw
        for x in range(nw):
            if g[row + x] < INK_THRESH:
                sx += x
                sy += y
                n += 1
    if n == 0:
        return nw / 2.0, nh / 2.0
    return sx / n, sy / n


def normalize_case(images):
    """images: {engine: (w,h,rgba)}. Returns ({engine: (W,H,gray)},
    {engine: (dx,dy)}) on the union canvas after per-engine
    crop+pad+rescale-to-NORM_H plus translation alignment by ink
    centroid: pure offsets are layout noise, not structure, so
    canvases coincide before compare and only shape differences
    cost similarity. Translations are integer paste offsets; the
    reference engine (zatex, else the first) translates by (0,0).
    Zero translations reproduce the old centered layout exactly."""
    scaled = {}
    for eng, (w, h, px) in images.items():
        cw, chh, cropped = crop_pad(w, h, px)
        gray = to_gray(cw, chh, cropped)
        nw, ng = rescale_gray(cw, chh, gray, NORM_H)
        scaled[eng] = (nw, NORM_H, ng)
    centroids = {eng: ink_centroid(nw, nh, g)
                 for eng, (nw, nh, g) in scaled.items()}
    ref = "zatex" if "zatex" in centroids else next(iter(centroids))
    rx, ry = centroids[ref]
    trans = {eng: (int(round(rx - cx)), int(round(ry - cy)))
             for eng, (cx, cy) in centroids.items()}
    W0 = max(v[0] for v in scaled.values())
    base_ox = {eng: (W0 - nw) // 2 for eng, (nw, nh, g) in scaled.items()}
    min_x = min(base_ox[eng] + trans[eng][0] for eng in scaled)
    min_y = min(trans[eng][1] for eng in scaled)
    max_x = max(base_ox[eng] + scaled[eng][0] + trans[eng][0]
                for eng in scaled)
    max_y = max(NORM_H + trans[eng][1] for eng in scaled)
    W, H = max_x - min_x, max_y - min_y
    out = {}
    for eng, (nw, nh, ng) in scaled.items():
        canvas = [255.0] * (W * H)
        ox = base_ox[eng] + trans[eng][0] - min_x
        oy = trans[eng][1] - min_y
        for y in range(nh):
            for x in range(nw):
                canvas[(y + oy) * W + ox + x] = ng[y * nw + x]
        out[eng] = (W, H, canvas)
    return out, trans


def sim_pair(a, b):
    return block_ssim(a[0], a[2], b[0], b[2])


def score_case(norm, trans):
    """Returns (score, per_oracle dict, spread, missing list, shift).
    shift is the largest ZaTeX-oracle alignment offset (|dx|+|dy| in
    rescaled px): big shift + high score reads "same shape, offset
    somewhere"; low score after alignment is structure, whatever the
    shift. Zero when zatex itself is missing."""
    if "zatex" not in norm:
        return None, {}, 0.0, ["zatex"], 0
    per, missing = {}, []
    for o in ORACLES:
        if o in norm:
            per[o] = sim_pair(norm["zatex"], norm[o])
        else:
            missing.append(o)
    score = max(per.values()) if per else None
    oo = []
    for i in range(len(ORACLES)):
        for j in range(i + 1, len(ORACLES)):
            a, b = ORACLES[i], ORACLES[j]
            if a in norm and b in norm:
                oo.append(sim_pair(norm[a], norm[b]))
    spread = min(oo) if oo else 1.0
    zx, zy = trans.get("zatex", (0, 0))
    shift = 0
    for o in ORACLES:
        if o in norm and o in trans:
            ox, oy = trans[o]
            shift = max(shift, abs(ox - zx) + abs(oy - zy))
    return score, per, spread, missing, shift


def gray_to_rgba(W, H, g):
    out = bytearray(W * H * 4)
    for i, v in enumerate(g):
        c = max(0, min(255, int(round(v))))
        out[i * 4:i * 4 + 4] = bytes([c, c, c, 255])
    return out


def load_corpus(path):
    with open(path) as f:
        rows = json.load(f)
    return rows


def score_one_case(args):
    """Worker: score a single case. Top-level for pool pickling.

    Writes that case's normalized PNGs (distinct files per case, so
    workers share nothing) and returns its report row, or None when no
    engine rendered it.
    """
    rawdir, pngdir, case = args
    cid = case["id"]
    images = {}
    for eng in ENGINES:
        p = os.path.join(rawdir, "%s.%s.png" % (cid, eng))
        if os.path.exists(p):
            images[eng] = read_png(p)
    if not images:
        return None
    norm, trans = normalize_case(images)
    for eng, (W, H, g) in norm.items():
        write_png(os.path.join(pngdir, "%s.%s.png" % (cid, eng)),
                  W, H, gray_to_rgba(W, H, g))
    score, per, spread, missing, shift = score_case(norm, trans)
    tags = []
    if spread < AMBIGUOUS_SPREAD:
        tags.append("spec-ambiguous")
    # Issue #60 tripwire: ZaTeX-vs-pinned-KaTeX worse than the
    # oracle-oracle floor by more than the margin. Needs "katex" plus
    # a spread to compare against (spread defaults to 1.0 when fewer
    # than two oracle pairs render, which keeps the rule meaningful).
    katex_outlier = ("katex" in per and
                     per["katex"] < spread - KATEX_OUTLIER_MARGIN)
    if katex_outlier:
        tags.append("katex-outlier")
    return {"case": case, "score": score, "per": per,
            "spread": spread, "missing": missing, "shift": shift,
            "tag": " ".join(tags), "katex_outlier": katex_outlier,
            "engines": [e for e in ENGINES if e in norm]}


def default_jobs():
    try:
        return os.cpu_count() or 4
    except NotImplementedError:
        return 4


def build_report(rawdir, outdir, corpus, jobs=1):
    pngdir = os.path.join(outdir, "png")
    os.makedirs(pngdir, exist_ok=True)
    # Cases are independent: score them in a process pool (same worker
    # function per case, rows reassembled in corpus order before the
    # stable worst-first sort, so output is byte-identical).
    tasks = [(rawdir, pngdir, case) for case in corpus]
    if jobs < 1:
        jobs = 1
    if jobs == 1:
        rows = [score_one_case(t) for t in tasks]
    else:
        from multiprocessing import Pool
        with Pool(min(jobs, len(tasks))) as pool:
            rows = list(pool.imap(score_one_case, tasks))
    rows = [r for r in rows if r is not None]
    # Link integrity: every render the rows reference must exist on disk
    # under exactly that name. Catches missing renders and case drift
    # between corpus ids and filenames (invisible on case-insensitive
    # filesystems, dead links on GitHub). Fail loudly: a report with
    # dead images is broken output, not a triage aid.
    refs = set("%s.%s.png" % (r["case"]["id"], e)
               for r in rows for e in r["engines"])
    missing = refs - set(os.listdir(pngdir))
    if missing:
        raise ValueError("report references missing renders: %s"
                         % sorted(missing))
    rows.sort(key=lambda r: (r["score"] is None, r["score"]
                             if r["score"] is not None else 0.0))
    lines = []
    lines.append("# Oracle diff report (triage only — not a gate, not truth)")
    lines.append("")
    lines.append("ZaTeX vs 3 independent oracle engines per case. "
                 "`score(c) = max` oracle similarity: closeness to *at "
                 "least one* oracle means low attention; a low max means "
                 "ZaTeX is the solo outlier. `spread` is the minimum "
                 "oracle-oracle similarity; rows with spread < %.2f are "
                 "tagged `spec-ambiguous` (oracles disagree with each "
                 "other — spec ambiguity, never a ZaTeX bug). Rows where "
                 "ZaTeX-vs-pinned-KaTeX falls more than %.2f below `spread` "
                 "are tagged `katex-outlier`: ZaTeX stands alone against "
                 "the reference even after allowing for oracle "
                 "disagreement — investigate first (triage attention, "
                 "never a gate). When oracles "
                 "disagree, pinned KaTeX 0.18.7 remains the sole truth "
                 "for accept/reject and geometry disputes."
                 % (AMBIGUOUS_SPREAD, KATEX_OUTLIER_MARGIN))
    lines.append("")
    lines.append("Normalization per case: tight-crop ink bbox + %dpx white "
                 "pad, uniform rescale to height %d (aspect preserved), "
                 "translation-aligned by ink centroid on the union canvas; "
                 "block SSIM on grayscale. Pure offsets are layout noise, "
                 "not structure: they cost ~nothing after alignment, so a "
                 "low score means genuinely different shapes. `shift` is "
                 "the largest ZaTeX-oracle alignment offset in rescaled "
                 "px. Absolute-size divergences are out of scope "
                 "here (covered by layout-IR tests)." % (PAD_PX, NORM_H))
    lines.append("")
    header = ("| case | source | score | KaTeX | LuaTeX | MathJax | spread | "
              "shift | tag | renders |")
    lines.append(header)
    # The delimiter must carry exactly as many cells as the header: GFM
    # drops a table whose counts disagree (it renders as raw pipes),
    # which is how a 9-cell delimiter broke this 10-column report.
    lines.append("|" + " --- |" * (header.count("|") - 1))
    for r in rows:
        c = r["case"]
        src = "`%s`" % c["tex"].replace("|", "\\|").replace("\n", " ")
        if len(src) > 80:
            src = src[:77] + "...`"
        per = r["per"]
        f = lambda k: ("%.3f" % per[k]) if k in per else "missing"
        sc = "n/a (no zatex render)" if r["score"] is None else "%.3f" % r["score"]
        iss = "" if c.get("issue") is None else "#%d" % c["issue"]
        # Issue #59: inline images (shown directly, not links — the
        # report's point is the visible differences) in engine order.
        # Only rendered engines get an image: unrendered ones have no
        # file, and linking them produces dead images (the row's tag
        # column already records them via "missing:...").
        imgs = "<br>".join(
            "![%s](png/%s.%s.png)" % (e[0].upper(), c["id"], e)
            for e in r["engines"])
        miss = (" missing:" + ",".join(r["missing"])) if r["missing"] else ""
        lines.append("| %s %s | %s | %s | %s | %s | %s | %.3f | %d | %s%s | %s |" % (
            c["id"], iss, src, sc, f("katex"), f("luatex"), f("mathjax"),
            r["spread"], r["shift"], r["tag"], miss, imgs))
    lines.append("")
    with open(os.path.join(outdir, "report.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return rows


def synth_image(w, h, kind, dx=0):
    px = bytearray(w * h * 4)
    for i in range(w * h):
        px[i * 4:i * 4 + 4] = bytes([255, 255, 255, 255])
    if kind == "bar":
        for y in range(8, 12):
            for x in range(4, w - 4):
                o = ((y * w + x + dx) % (w * h)) * 4
                px[o:o + 3] = bytes([0, 0, 0])
    elif kind == "dot":
        for y in range(4, 8):
            for x in range(10, 14):
                o = ((y * w + x + dx) % (w * h)) * 4
                px[o:o + 3] = bytes([0, 0, 0])
    elif kind == "shifted-bar":
        for y in range(14, 18):
            for x in range(4, w - 4):
                o = ((y * w + x) % (w * h)) * 4
                px[o:o + 3] = bytes([0, 0, 0])
    elif kind == "midbar":
        # Centered bar (pad-clear on all sides, so its crop never
        # clamps): pairs with midbar-shifted to isolate PURE
        # translation — identical crop sizes, so only the offset
        # differs and alignment must recover it bit-exactly.
        for y in range(14, 18):
            for x in range(4, w - 4):
                o = ((y * w + x) % (w * h)) * 4
                px[o:o + 3] = bytes([0, 0, 0])
    elif kind == "midbar-shifted":
        for y in range(17, 21):
            for x in range(4, w - 4):
                o = ((y * w + x) % (w * h)) * 4
                px[o:o + 3] = bytes([0, 0, 0])
    return w, h, px


def selfcheck():
    fails = []

    def check(name, cond):
        print(("PASS " if cond else "FAIL ") + name)
        if not cond:
            fails.append(name)

    # SSIM math unit checks on synthetic images.
    a = synth_image(32, 32, "bar")
    b = synth_image(32, 32, "bar")
    na, sh_na = normalize_case({"zatex": a, "katex": b})
    check("identical images score 1.0",
          abs(sim_pair(na["zatex"], na["katex"]) - 1.0) < 1e-9)
    check("identical images align to themselves",
          sh_na["zatex"] == (0, 0) and sh_na["katex"] == (0, 0))
    # Centroid alignment: a pure offset is layout noise, not
    # structure — the pair recovers, while a genuinely different
    # shape stays below it. (midbar pair: identical crops, so
    # tight-crop already absorbs the offset; the asymmetric pair
    # below exercises the translation path, where the y component
    # carries the offset and the x slop is rescale-width side
    # effect of the clamped crops.)
    m1 = synth_image(32, 32, "midbar")
    m2 = synth_image(32, 32, "midbar-shifted")
    nm, sh_nm = normalize_case({"zatex": m1, "katex": m2})
    recovered = sim_pair(nm["zatex"], nm["katex"])
    check("pure-offset pairs recover under alignment (got %.4f)" % recovered,
          recovered > 0.999)
    check("agreed crops align to themselves",
          sh_nm["zatex"] == (0, 0) and sh_nm["katex"] == (0, 0))
    c = synth_image(32, 32, "shifted-bar")
    nc, sh_nc = normalize_case({"zatex": a, "katex": c})
    asym = sim_pair(nc["zatex"], nc["katex"])
    check("translation path detects the offset under crop asymmetry",
          sh_nc["zatex"] == (0, 0) and sh_nc["katex"][1] == -6)
    check("asymmetric crops recover above the unaligned 0.87 (got %.4f)" %
          asym, asym > 0.93)
    d = synth_image(32, 32, "dot")
    nd, _ = normalize_case({"zatex": a, "katex": d})
    diff = sim_pair(nd["zatex"], nd["katex"])
    check("different shapes score below recovered pair (%.4f < %.4f)" %
          (diff, recovered), diff < recovered)
    # Tight-crop: bbox of the bar must exclude the white border.
    x0, y0, x1, y1 = ink_bbox(32, 32, a[2])
    check("ink bbox tight on synthetic bar", (x0, y0, x1, y1) == (4, 8, 27, 11))

    # Fixture report: synthetic 4-engine renders exercise sorting/tags.
    import tempfile
    tmp = tempfile.mkdtemp(prefix="oracle-diff-selfcheck-")
    raw = os.path.join(tmp, "raw")
    os.makedirs(raw)
    cases = [
        {"id": "agree", "tex": "x^2", "display": False, "issue": None},
        {"id": "solo", "tex": "\\frac a b", "display": False, "issue": 32},
        {"id": "ambig", "tex": "\\circledS", "display": False, "issue": 37},
    ]
    base = synth_image(48, 32, "bar")
    for eng in ENGINES:
        write_png(os.path.join(raw, "agree.%s.png" % eng), 48, 32, base[2])
    for eng in ENGINES:
        kind = "dot" if eng == "zatex" else "bar"
        img = synth_image(48, 32, kind)
        write_png(os.path.join(raw, "solo.%s.png" % eng), 48, 32, img[2])
    # ambig: zatex=bar, oracles disagree among themselves (bar/dot/bar).
    oracle_kinds = {"zatex": "bar", "katex": "bar",
                    "mathjax": "dot", "luatex": "bar"}
    for eng, kind in oracle_kinds.items():
        img = synth_image(48, 32, kind)
        write_png(os.path.join(raw, "ambig.%s.png" % eng), 48, 32, img[2])
    # part: only zatex+katex rendered (luatex/mathjax missing, as happens
    # for real amsmath-gap rows) — the row must not reference their PNGs.
    cases.append({"id": "part", "tex": "x", "display": False, "issue": None})
    for eng in ("zatex", "katex"):
        img = synth_image(48, 32, "bar")
        write_png(os.path.join(raw, "part.%s.png" % eng), 48, 32, img[2])
    out = os.path.join(tmp, "out")
    rows = build_report(raw, out, cases)
    order = [r["case"]["id"] for r in rows]
    by_id = {r["case"]["id"]: r for r in rows}
    check("worst-first sort puts solo outlier first", order[0] == "solo")
    check("agreement row scores 1.0", by_id["agree"]["score"] == 1.0)
    check("identical renders report zero shift",
          by_id["agree"]["shift"] == 0)
    check("structural rows keep their score below 1.0 even with a shift",
          by_id["solo"]["score"] < 1.0 and by_id["solo"]["shift"] > 0)
    check("oracle-matching row also scores 1.0",
          by_id["ambig"]["score"] == 1.0)
    check("solo row scores below agreement row",
          by_id["solo"]["score"] < by_id["agree"]["score"])
    check("oracle-disagreement row tagged spec-ambiguous",
          by_id["ambig"]["tag"] == "spec-ambiguous")
    # Issue #60 tripwire: the solo row (zatex differs, oracles agree) is a
    # katex-outlier; rows matching KaTeX are not.
    check("solo-outlier row tagged katex-outlier",
          by_id["solo"]["katex_outlier"] is True and
          "katex-outlier" in by_id["solo"]["tag"])
    check("agreement row is not a katex-outlier",
          by_id["agree"]["katex_outlier"] is False)
    check("oracle-matching row is not a katex-outlier",
          by_id["ambig"]["katex_outlier"] is False)
    check("report.md written with all rows",
          os.path.exists(os.path.join(out, "report.md")) and
          all(i in open(os.path.join(out, "report.md")).read()
              for i in ("agree", "solo", "ambig")))
    check("normalized pngs written per engine",
          all(os.path.exists(os.path.join(out, "png", "%s.%s.png" % (i, e)))
              for i in ("agree", "solo", "ambig") for e in ENGINES))
    # No dead image references: every png/ link in the report resolves.
    import re
    md = open(os.path.join(out, "report.md")).read()
    refs = set(re.findall(r"png/(\S+?\.png)", md))
    on_disk = set(os.listdir(os.path.join(out, "png")))
    check("every referenced render exists (no dead images)",
          refs <= on_disk)
    # Table shape: GFM drops a table whose header/delimiter cell counts
    # disagree, so assert they (and every body row) agree. Split on
    # unescaped pipes — `\|` inside a source cell does not delimit.
    def ncells(row):
        parts = re.split(r"(?<!\\)\|", row)
        if parts and parts[0].strip() == "":
            parts = parts[1:]
        if parts and parts[-1].strip() == "":
            parts = parts[:-1]
        return len(parts)
    table = [ln for ln in md.splitlines() if ln.startswith("|")]
    check("report table header/delimiter/body column counts agree",
          len(table) > 2 and
          all(ncells(ln) == ncells(table[0]) for ln in table[1:]))
    part_md = [ln for ln in md.splitlines() if ln.startswith("| part ")]
    check("missing-engine row omits unrendered engines",
          len(part_md) == 1 and "part.luatex.png" not in part_md[0]
          and "part.mathjax.png" not in part_md[0]
          and "missing:luatex,mathjax" in part_md[0])
    # Corpus fixture sanity: known #30-#38 divergences are represented.
    issues = set()
    for path in (os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "corpus.json"),):
        if os.path.exists(path):
            for row in json.load(open(path)):
                if row.get("issue"):
                    issues.add(row["issue"])
    check("fixture corpus covers issues 30-37 divergences",
          set(range(30, 38)) <= issues)
    # Corpus ids derive every staged/render filename: two ids differing
    # only by case collide on case-insensitive filesystems (one tex
    # clobbers the other, both rows score the same renders) and produce
    # dead links on case-sensitive hosts. Forbid them outright.
    ids = [row["id"] for row in json.load(open(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "corpus.json")))]
    check("corpus ids unique case-insensitively (no filename collision)",
          len({i.lower() for i in ids}) == len(ids))
    if fails:
        print("%d FAILURES" % len(fails))
        return 1
    print("selfcheck: all green")
    return 0


def main(argv):
    if "--selfcheck" in argv:
        return selfcheck()
    raw = out = corpus = None
    jobs = int(os.environ.get("ORACLE_DIFF_JOBS", default_jobs()))
    i = 0
    while i < len(argv):
        if argv[i] == "--raw" and i + 1 < len(argv):
            raw = argv[i + 1]
            i += 2
        elif argv[i] == "--out" and i + 1 < len(argv):
            out = argv[i + 1]
            i += 2
        elif argv[i] == "--corpus" and i + 1 < len(argv):
            corpus = argv[i + 1]
            i += 2
        elif argv[i] == "--jobs" and i + 1 < len(argv):
            jobs = int(argv[i + 1])
            i += 2
        else:
            i += 1
    if not raw or not out or not corpus:
        sys.stderr.write("usage: report.py --raw DIR --out DIR "
                         "--corpus FILE [--jobs N]\n")
        return 2
    rows = build_report(raw, out, load_corpus(corpus), jobs)
    print("wrote %s/report.md (%d cases)" % (out, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

