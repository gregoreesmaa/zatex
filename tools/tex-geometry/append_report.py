#!/usr/bin/env python3
"""append_report — publish tex-geometry rows into the oracle-diff triage
report (issue #178).

The committed `zig-out/oracle-diff/report.md` is the pixel sweep's
triage table (owned by `report.py`, never hand-edited). This tool
appends (or refreshes, idempotently) one clearly-delimited section
with the pure-TeX geometry verdicts for the overlapping narrow-corpus
rows, built ONLY from real CI data: `<id>.tex.json` (geometry output)
and `<id>.zatex.json` (irdump output) as uploaded by the `tex-oracle`
workflow's `tex-oracle` artifact.

Usage:
  append_report.py <report.md> <texgeo-dir>

The section lives between `<!-- tex-geometry:start -->` and
`<!-- tex-geometry:end -->` markers; a second run replaces it instead
of duplicating it. Missing JSON sides fail loudly (no zeros published).
Stdlib only.
"""
import json
import os
import sys

START = "<!-- tex-geometry:start -->"
END = "<!-- tex-geometry:end -->"


def load(workdir, rid, suffix):
    path = os.path.join(workdir, rid + suffix)
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise SystemExit(f"append_report: cannot load {path}: {e}")


def main(argv):
    report_path, workdir = argv[1], argv[2]
    corpus = json.load(open(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "corpus.json"),
        encoding="utf-8"))
    lines = [START,
             "## Pure-TeX geometry oracle (issue #178)",
             "",
             "Box *construction* per row from stock Knuth TeX (DVI glyph/rule "
             "counts) against ZaTeX (`irdump` counts) — counts compare, "
             "metrics never do (Computer Modern vs host fonts). Triage "
             "attention like the pixel table above, never a gate; pinned "
             "KaTeX remains truth. Driver and schema: `docs/tex-oracle.md`.",
             "",
             "| row | TeX | ZaTeX | verdict |",
             "| --- | --- | --- | --- |"]
    versions = set()
    for row in corpus:
        rid = row["id"]
        tex = load(workdir, rid, ".tex.json")
        zatex = load(workdir, rid, ".zatex.json")
        tg, tr = tex["counts"]["glyphs"], tex["counts"]["rules"]
        versions.add(tex["tex_version"])
        detail_tex = f"{tg} glyphs/{tr} rules"
        detail_z = f"{zatex['glyphs']} glyphs/{zatex['rules']} rules"
        verdict = ("MATCH" if (tg == zatex["glyphs"] and
                               tr == zatex["rules"]) else "MISMATCH")
        lines.append(f"| `{rid}` | {detail_tex} | {detail_z} | {verdict} |")
    lines.append("")
    lines.append(f"Engine: {'; '.join(sorted(versions))}.")
    lines.append(END)
    section = "\n".join(lines)

    with open(report_path, encoding="utf-8") as f:
        body = f.read()
    if START in body and END in body:
        pre, rest = body.split(START, 1)
        _, post = rest.split(END, 1)
        body = pre.rstrip("\n") + "\n\n" + section + post
    else:
        body = body.rstrip("\n") + "\n\n" + section + "\n"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(body)
    print(f"append_report: {len(corpus)} tex rows published into {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
