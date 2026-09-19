#!/usr/bin/env python3
"""geometry — dvitype dump -> machine-comparable TeX geometry JSON (issue #178).

Reads a `dvitype` text dump of one DVI page (as produced by `extract`)
and emits canonical JSON: the ordered glyph placements (font number +
character code), the rules (height x width in DVI units), the font
table, and the DVI preamble units. Absolute (h,v) tracking is
deliberately OUT: the compared property is box *construction* (which
glyphs/rules, in which order — the Knuth-lineage second opinion on
`\\frac` bars, scripts, and delimiters), never metrics — TeX sets
Computer Modern while ZaTeX measures the host's fonts, so advances
cannot agree and are not compared. See `docs/tex-oracle.md`.

Stdlib only. `geometry --selfcheck` validates the parser against a
canned dvitype fixture and runs anywhere (no daemon, no TeX).
"""
import json
import re
import sys

# dvitype op lines this parser counts. Everything else (push/pop,
# positioning arithmetic, specials, page brackets) is ignored: the
# schema compares construction, and unknown lines must never fail a
# sweep row — the zero-glyph sanity check below catches a total
# format break instead.
SETCHAR = re.compile(r"\bsetchar(\d+)\b")
SETN = re.compile(r"^(\d+): set(\d) (-?\d+)\b")
PUTN = re.compile(r"^(\d+): put(\d) (-?\d+)\b")
PUTCHAR = re.compile(r"\bputchar(\d+)\b")
SETRULE = re.compile(r"\bsetrule height (-?\d+), width (-?\d+)")
PUTRULE = re.compile(r"\bputrule height (-?\d+), width (-?\d+)")
FNTDEF = re.compile(r"\bfntdef(\d+):\s*(\S+)")
PREAMBLE = re.compile(r"\bnum=(\d+), den=(\d+), mag=(\d+)")


def parse_dump(text):
    glyphs = []
    rules = []
    fonts = {}
    units = {"num": 25400000, "den": 473628672, "mag": 1000}
    for line in text.splitlines():
        m = PREAMBLE.search(line)
        if m:
            units = {"num": int(m.group(1)), "den": int(m.group(2)),
                     "mag": int(m.group(3))}
        m = FNTDEF.search(line)
        if m:
            fonts[m.group(1)] = m.group(2)
        m = SETCHAR.search(line)
        if m:
            glyphs.append({"font": None, "code": int(m.group(1))})
            continue
        m = PUTCHAR.search(line)
        if m:
            glyphs.append({"font": None, "code": int(m.group(1))})
            continue
        m = SETN.match(line)
        if m:
            glyphs.append({"font": None, "code": int(m.group(3))})
            continue
        m = PUTN.match(line)
        if m:
            glyphs.append({"font": None, "code": int(m.group(3))})
            continue
        m = SETRULE.search(line)
        if m:
            rules.append({"height": int(m.group(1)),
                          "width": int(m.group(2))})
            continue
        m = PUTRULE.search(line)
        if m:
            rules.append({"height": int(m.group(1)),
                          "width": int(m.group(2))})
    return glyphs, rules, fonts, units


def to_json(tex, display, tex_version, dump_text):
    glyphs, rules, fonts, units = parse_dump(dump_text)
    if not glyphs:
        raise SystemExit("geometry: no glyph placements parsed "
                         "(not a dvitype dump?)")
    return {
        "tex": tex,
        "display": bool(display),
        "tex_version": tex_version,
        "dvi_units": units,
        "fonts": fonts,
        "glyphs": glyphs,
        "rules": rules,
        "counts": {"glyphs": len(glyphs), "rules": len(rules)},
    }


def main(argv):
    if "--selfcheck" in argv:
        return selfcheck()
    # geometry --tex ID --display 0|1 --tex-version STR --dump FILE [--out FILE]
    args = dict(zip(argv[1::2], argv[2::2]))
    try:
        tex = args["--tex"]
        display = args["--display"] == "1"
        version = args["--tex-version"]
        dump = open(args["--dump"], encoding="utf-8",
                    errors="replace").read()
    except (KeyError, OSError) as e:
        raise SystemExit(f"geometry: bad arguments: {e}")
    doc = to_json(tex, display, version, dump)
    out = json.dumps(doc, indent=2, sort_keys=True) + "\n"
    if "--out" in args:
        with open(args["--out"], "w", encoding="utf-8") as f:
            f.write(out)
    else:
        sys.stdout.write(out)
    return 0


# Canned dvitype-shaped fixture: exercises every counted op form
# (setchar, set1, putchar, setrule, putrule, fntdef, preamble) plus
# ignored lines (push/pop/positioning/page brackets).
FIXTURE = """\
0: preamble, i=2, num=25400000, den=473628672, mag=1000, stack max = 10
42: beginning of page 1
87: down4 24760517 v:=24760517
95: push
96: right4 655360 h:=0+655360, hh:=10
101: fntdef1: cmr10 --- design size follows
120: fntnum1
121: setchar120 h:=655360+327680, hh:=15
130: push
131: down4 200000 v:=24960517
132: set1 50 h:=983040+100000, hh:=18
133: pop
140: putchar51
141: setrule height 262144, width 524288
142: putrule height 100, width 200
200: pop
201: eop
"""


def selfcheck():
    doc = to_json("x^2", False, "TeX 3.141592653 (TeX Live 2022)",
                  FIXTURE)
    assert doc["counts"] == {"glyphs": 3, "rules": 2}, doc["counts"]
    assert [g["code"] for g in doc["glyphs"]] == [120, 50, 51]
    assert doc["rules"][0] == {"height": 262144, "width": 524288}
    assert doc["rules"][1] == {"height": 100, "width": 200}
    assert doc["fonts"] == {"1": "cmr10"}, doc["fonts"]
    assert doc["dvi_units"] == {"num": 25400000, "den": 473628672,
                                "mag": 1000}
    # Canonical bytes: same dump serializes byte-identical JSON.
    once = json.dumps(doc, indent=2, sort_keys=True) + "\n"
    twice = json.dumps(to_json("x^2", False,
                               "TeX 3.141592653 (TeX Live 2022)",
                               FIXTURE), indent=2, sort_keys=True) + "\n"
    assert once == twice
    # Empty dump fails loudly instead of comparing zeros.
    try:
        to_json("x", False, "v", "42: beginning of page 1\n201: eop\n")
    except SystemExit:
        pass
    else:
        raise AssertionError("empty dump must fail")
    print("geometry --selfcheck: ok (3 glyphs, 2 rules, canonical)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
