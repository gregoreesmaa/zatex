#!/usr/bin/env python3
"""diff_geometry — TeX DVI JSON vs ZaTeX IR JSON per corpus row (issue #178).

Compares box *construction* (ordered glyph-code sequence length and
rule count), never metrics: TeX sets Computer Modern while ZaTeX
measures the host's fonts (or the irdump stub), so advances cannot
agree and are not compared. Glyph *codes* are compared as multiset
equality only as a diagnostic column, not as a verdict — CM vs LM
codepoints differ by design (e.g. math italic vs ASCII).

Input: a directory holding `<id>.tex.json` (geometry output) and
`<id>.zatex.json` (irdump output) per row of `corpus.json`.
Output: `report.md` (worst-first) plus a one-line stdout summary.

Exit 0 always: this is triage attention, never a gate (AGENTS.md §4).
Pinned KaTeX remains the sole truth for accept/reject and geometry
disputes; a MISMATCH here means "ask why", never "change ZaTeX".
Stdlib only.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_corpus(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main(argv):
    corpus_path = argv[1] if len(argv) > 1 else os.path.join(HERE, "corpus.json")
    workdir = argv[2] if len(argv) > 2 else "."
    out_path = argv[3] if len(argv) > 3 else os.path.join(workdir, "report.md")

    corpus = load_corpus(corpus_path)
    rows = []
    for row in corpus:
        rid = row["id"]
        tex_path = os.path.join(workdir, rid + ".tex.json")
        zatex_path = os.path.join(workdir, rid + ".zatex.json")
        try:
            tex = load_json(tex_path)
        except (OSError, ValueError) as e:
            rows.append((rid, "tex-missing", f"no TeX JSON: {e}", None))
            continue
        try:
            zatex = load_json(zatex_path)
        except (OSError, ValueError) as e:
            rows.append((rid, "zatex-missing", f"no ZaTeX JSON: {e}", None))
            continue
        tg = tex["counts"]["glyphs"]
        tr = tex["counts"]["rules"]
        zg = zatex["glyphs"]
        zr = zatex["rules"]
        detail = (f"TeX {tg} glyphs/{tr} rules vs "
                  f"ZaTeX {zg} glyphs/{zr} rules "
                  f"(TeX {tex['tex_version']})")
        if tg == zg and tr == zr:
            rows.append((rid, "MATCH", detail, tex))
        else:
            rows.append((rid, "MISMATCH", detail, tex))

    bad = [r for r in rows if r[1] != "MATCH"]
    bad_first = sorted(rows, key=lambda r: (r[1] == "MATCH", r[0]))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# tex-geometry report (informational, never a gate)\n\n")
        f.write("Pinned KaTeX remains truth; a MISMATCH is a question, "
                "not a verdict. See `docs/tex-oracle.md`.\n\n")
        f.write("| row | verdict | detail |\n| --- | --- | --- |\n")
        for rid, verdict, detail, _ in bad_first:
            f.write(f"| `{rid}` | {verdict} | {detail} |\n")
    print(f"tex-geometry: {len(rows) - len(bad)}/{len(rows)} MATCH"
          + (f" ({', '.join(r[0] for r in bad)})" if bad else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
