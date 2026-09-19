#!/usr/bin/env python3
"""tex_score — ZaTeX-vs-TeX pixel similarity through the shared oracle
math (issue #178).

Takes raw renders per narrow-corpus row — `<id>.zatex.png` (zatex-png)
and `<id>.tex.png` (the DVI route: dvipdfmx + pdftoppm, same -r 300
the luatex oracle uses) — and runs them through `report.py`'s own
`normalize_case` + `sim_pair` (crop+pad+rescale-128+centroid-align,
block SSIM). Writes normalized TeX renders (`norm/<id>.tex.png`,
committed beside the other engines' renders) and `texsim.json`
(`{id: sim}`) for `append_report.py`.

This is the same math with the same calibration as the pixel table —
relative triage numbers, never a gate. Cross-font spread dominates
(CM vs host fonts), so expect L-column territory (~0.2-0.5 even on
agreement): judge a TeX sim against its row's LuaTeX sim (same font
family, sibling route), not against 1.0. The font-independent check
stays the construction-counts verdict in `diff_geometry.py`.

Usage:
  tex_score.py <corpus.json> <workdir>   # workdir holds raw PNGs
  tex_score.py --selfcheck               # no daemon, no TeX, no fonts
Stdlib only (plus report.py, also stdlib-only).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "oracle-diff"))
from report import normalize_case, sim_pair, read_png, write_png, gray_to_rgba  # noqa: E402


def score_row(zatex_png, tex_png, norm_tex_png):
    zw, zh, zpx = read_png(zatex_png)
    tw, th, tpx = read_png(tex_png)
    norm, _ = normalize_case({"zatex": (zw, zh, zpx),
                              "tex": (tw, th, tpx)})
    sim = sim_pair(norm["zatex"], norm["tex"])
    W, H, g = norm["tex"]
    write_png(norm_tex_png, W, H, gray_to_rgba(W, H, g))
    return sim


def main(argv):
    if "--selfcheck" in argv:
        return selfcheck()
    corpus_path, workdir = argv[1], argv[2]
    normdir = os.path.join(workdir, "norm")
    os.makedirs(normdir, exist_ok=True)
    corpus = json.load(open(corpus_path, encoding="utf-8"))
    sims = {}
    for row in corpus:
        rid = row["id"]
        zp = os.path.join(workdir, rid + ".zatex.png")
        tp = os.path.join(workdir, rid + ".tex.png")
        for p in (zp, tp):
            if not os.path.exists(p):
                raise SystemExit(f"tex_score: missing raw render {p}")
        np_ = os.path.join(normdir, rid + ".tex.png")
        sim = score_row(zp, tp, np_)
        sims[rid] = sim
        print(f"== {rid}: tex sim {sim:.3f}")
    with open(os.path.join(workdir, "texsim.json"), "w",
              encoding="utf-8") as f:
        json.dump(sims, f, indent=2, sort_keys=True)
        f.write("\n")
    return 0


def selfcheck():
    # Identical inputs score 1.0 through the shared pipeline; a
    # structurally different pair scores strictly lower. Synthetic
    # PNGs only: no engines, no fonts, no daemon.
    import tempfile
    from report import synth_image
    tmp = tempfile.mkdtemp(prefix="tex-score-selfcheck-")
    a = os.path.join(tmp, "a.zatex.png")
    b = os.path.join(tmp, "a.tex.png")
    w, h, px = synth_image(48, 32, "bar")
    write_png(a, w, h, px)
    write_png(b, w, h, px)
    n = os.path.join(tmp, "norm", "a.tex.png")
    os.makedirs(os.path.join(tmp, "norm"))
    assert abs(score_row(a, b, n) - 1.0) < 1e-9
    assert os.path.exists(n)
    w2, h2, px2 = synth_image(48, 32, "dot")
    write_png(b, w2, h2, px2)
    lower = score_row(a, b, n)
    assert lower < 1.0, lower
    print(f"tex_score --selfcheck: ok (identical 1.0, different {lower:.3f})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
