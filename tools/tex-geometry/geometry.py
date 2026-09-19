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
# Real dvitype shapes (grounded against TeX Live 2022/Debian output,
# see the agree-quad dump in CI artifact `tex-oracle`): `fntdef`
# carries the opcode length class before the font number
# (`144: fntdef1 26: cmmi10`), and `fntnum` selects the current font.
FNTDEF = re.compile(r"\bfntdef\d+ (\d+): (\S+)")
FNTNUM = re.compile(r"\bfntnum(\d+)\b")
NUMDEN = re.compile(r"numerator/denominator=(\d+)/(\d+)")
MAG = re.compile(r"magnification=(\d+)")


def parse_dump(text):
    glyphs = []
    rules = []
    fonts = {}
    units = {"num": 25400000, "den": 473628672, "mag": 1000}
    current_font = None
    for line in text.splitlines():
        m = NUMDEN.search(line)
        if m:
            units["num"] = int(m.group(1))
            units["den"] = int(m.group(2))
        m = MAG.search(line)
        if m:
            units["mag"] = int(m.group(1))
        m = FNTDEF.search(line)
        if m:
            fonts[m.group(1)] = m.group(2)
        m = FNTNUM.search(line)
        if m:
            current_font = int(m.group(1))
        m = SETCHAR.search(line)
        if m:
            glyphs.append({"font": current_font,
                           "code": int(m.group(1))})
            continue
        m = PUTCHAR.search(line)
        if m:
            glyphs.append({"font": current_font,
                           "code": int(m.group(1))})
            continue
        m = SETN.match(line)
        if m:
            glyphs.append({"font": current_font,
                           "code": int(m.group(3))})
            continue
        m = PUTN.match(line)
        if m:
            glyphs.append({"font": current_font,
                           "code": int(m.group(3))})
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


# Canned fixture in the real dvitype shapes (grounded against the
# agree-quad dump from TeX Live 2022/Debian): exercises every counted
# op form (setchar, set1, putchar, setrule, putrule, fntdef with the
# opcode length class, fntnum selection, numerator/denominator and
# magnification lines) plus ignored lines (push/pop/positioning/page
# brackets, xxx specials).
FIXTURE = """\
This is DVItype, Version 3.6 (TeX Live 2022/Debian)
numerator/denominator=25400000/473628672
magnification=1000;       0.00006334 pixels per DVI unit
Font 26: cmmi10---loaded at size 655360 DVI units
Font 22: cmr7---loaded at size 458752 DVI units
42: beginning of page 1
87: down4 24760517 v:=24760517
88: xxx 'header=l3backend-dvips.pro'
95: push
96: right4 655360 h:=0+655360, hh:=10
144: fntdef1 26: cmmi10
166: fntnum26 current font is cmmi10
121: setchar120 h:=655360+327680, hh:=15
130: push
131: down4 200000 v:=24960517
173: fntdef1 22: cmr7
193: fntnum22 current font is cmr7
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
    assert [(g["font"], g["code"]) for g in doc["glyphs"]] == [
        (26, 120), (22, 50), (22, 51)], doc["glyphs"]
    assert doc["rules"][0] == {"height": 262144, "width": 524288}
    assert doc["rules"][1] == {"height": 100, "width": 200}
    assert doc["fonts"] == {"26": "cmmi10", "22": "cmr7"}, doc["fonts"]
    assert doc["dvi_units"] == {"num": 25400000, "den": 473628672,
                                "mag": 1000}
    # Units come from the dump, not the defaults: a custom preamble
    # parses through.
    g2, _, _, u2 = parse_dump("numerator/denominator=1/2\n"
                              "magnification=2000\n"
                              "1: setchar65\n")
    assert u2 == {"num": 1, "den": 2, "mag": 2000}, u2
    assert g2 == [{"font": None, "code": 65}], g2
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
