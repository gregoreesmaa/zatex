#!/usr/bin/env python3
"""Generate docs/katex-syntax.md: KaTeX support-table mirror with renders.

Reads docs/support-table.md, builds one example per `accept` row, renders
via zatex-png batch into docs/renders/, and emits the mirror markdown.
Rows in tools/doc_gaps.json are expected render failures (engine gaps or
table overclaims); any other failure — or a gap that starts rendering —
fails loudly so regressions and gap hygiene both gate.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "docs", "support-table.md")
RENDERS = os.path.join(ROOT, "docs", "renders")
MD = os.path.join(ROOT, "docs", "katex-syntax.md")
GAPS = os.path.join(ROOT, "tools", "doc_gaps.json")
CLI_DIR = os.path.join(ROOT, "packages", "zatex-png")
CLI = os.path.join(CLI_DIR, "zig-out", "bin", "zatex-png")
PX = 48

# fn -> (tex, display). Single backslashes; the corpus writer escapes.
EXACT = {
    # Punctuation / escapes.
    "!": ("x!", False),
    "\\!": ("x\\!x", False),
    "#": ("\\def\\f#1{#1}\\f{x}", False),
    "\\#": ("\\#", False),
    "%": ("a% note\nb", False),
    "\\%": ("\\%", False),
    "&": ("\\begin{aligned}a&=b\\end{aligned}", True),
    "\\&": ("\\&", False),
    "'": ("x'", False),
    "\\'": ("\\'e", False),
    "(": ("(x)", False),
    ")": ("(x)", False),
    "\\(\u2026\\)": ("\\(x^2\\)", False),
    "\\\\ ": ("\\begin{matrix}a\\\\b\\end{matrix}", True),
    "\\ ": ("a\\ b", False),
    '\\"': ('\\"o', False),
    "\\$": ("\\$", False),
    "\\,": ("x\\,x", False),
    "\\.": ("\\.o", False),
    "\\:": ("x\\:x", False),
    "\\;": ("x\\;x", False),
    "\\_": ("\\_", False),
    "\\`": ("\\`a", False),
    "<": ("x<y", False),
    "\\=": ("\\={x}", False),
    "{": ("{a}", False),
    "}": ("{a}", False),
    "\\{": ("\\{x\\}", False),
    "\\}": ("\\{x\\}", False),
    "\\|": ("\\|x\\|", False),
    "|": ("a|b", False),
    "\\~": ("\\~n", False),
    "^": ("x^2", False),
    "\\^": ("\\^{x}", False),
    "_": ("x_i", False),
    ">": ("x>y", False),
    "[": ("[x]", False),
    "]": ("x]", False),
    "~": ("a~b", False),
    # Single letters.
    "\\H": ("\\H{o}", False),
    "\\O": ("\\text{\\O}", False),
    "\\P": ("\\P", False),
    "\\S": ("\\S", False),
    "\\i": ("\\text{\\i}", False),
    "\\j": ("\\text{\\j}", False),
    "\\o": ("\\text{\\o}", False),
    "\\r": ("\\r{a}", False),
    "\\u": ("\\u{x}", False),
    "\\v": ("\\v{x}", False),
    # Fractions, binomials, infix generalizes.
    "\\frac": ("\\frac{a}{b}", False),
    "\\dfrac": ("\\dfrac{a}{b}", False),
    "\\tfrac": ("\\tfrac{a}{b}", False),
    "\\cfrac": ("\\cfrac{a}{b}", False),
    "\\binom": ("\\binom{n}{k}", False),
    "\\dbinom": ("\\dbinom{n}{k}", False),
    "\\genfrac": ("\\genfrac(){0pt}{1}{a}{b}", False),
    "\\over": ("{a\\over b}", False),
    "\\atop": ("{a\\atop b}", False),
    "\\choose": ("{n\\choose k}", False),
    "\\sqrt": ("\\sqrt{x}", False),
    "\\overset": ("\\overset{!}{=}", False),
    "\\underset": ("\\underset{*}{+}", False),
    "\\xleftarrow": ("\\xleftarrow[sub]{sup}", False),
    "\\xrightarrow": ("\\xrightarrow{a}b", False),
    "\\cancel": ("\\cancel{x}", False),
    "\\bcancel": ("\\bcancel{x}", False),
    "\\sout": ("\\sout{x}", False),
    "\\not": ("a\\not\\in b", False),
    "\\boldsymbol": ("\\boldsymbol{\\alpha}", False),
    "\\pmb": ("\\pmb{x}", False),
    "\\mod": ("x\\mod y", False),
    "\\braket": ("\\braket{x}{y}", False),
    "\\Braket": ("\\Braket{x}{y}", False),
    "\\bra": ("\\bra{x}", False),
    "\\ket": ("\\ket{x}", False),
    "\\Bra": ("\\Bra{x}", False),
    "\\Ket": ("\\Ket{x}", False),
    "\\phase": ("\\phase{30}", False),
    "\\Set": ("\\Set{x|x>0}", False),
    "\\vcenter": ("\\vcenter{x}", False),
    "\\mathinner": ("\\mathinner{x}", False),
    "\\mathop": ("\\mathop{x}", False),
    "\\mathrel": ("\\mathrel{x}", False),
    "\\mathstrut": ("x\\mathstrut y", False),
    "\\mathclap": ("\\mathclap{x}", False),
    "\\mathllap": ("\\mathllap{x}y", False),
    "\\mathrlap": ("\\mathrlap{x}y", False),
    # Text fonts, colors, boxes.
    "\\text": ("\\text{for }x", False),
    "\\textbf": ("\\textbf{a+b}", False),
    "\\textit": ("\\textit{a+b}", False),
    "\\textsf": ("\\textsf{x}", False),
    "\\texttt": ("\\texttt{x}", False),
    "\\textrm": ("\\textrm{x}", False),
    "\\textnormal": ("\\textnormal{x}", False),
    "\\mathbb": ("\\mathbb{R}", False),
    "\\mathbf": ("\\mathbf{B}", False),
    "\\mathcal": ("\\mathcal{E}", False),
    "\\mathfrak": ("\\mathfrak{G}", False),
    "\\mathit": ("\\mathit{C}", False),
    "\\mathrm": ("\\mathrm{A}", False),
    "\\mathsf": ("\\mathsf{H}", False),
    "\\mathtt": ("\\mathtt{I}", False),
    "\\mathscr": ("\\mathscr{F}", False),
    "\\color": ("\\color{red}x", False),
    "\\textcolor": ("\\textcolor{blue}{x}", False),
    "\\colorbox": ("\\colorbox{yellow}{a+b}", False),
    "\\fcolorbox": ("\\fcolorbox{red}{#ff0}{x}", False),
    "\\rule": ("\\rule{1em}{2pt}", False),
    "\\raisebox": ("\\raisebox{2pt}{x}", False),
    "\\hspace": ("a\\hspace{1em}b", False),
    "\\kern": ("a\\kern2ptb", False),
    "\\quad": ("x\\quad y", False),
    "\\qquad": ("x\\qquad y", False),
    "\\enskip": ("x\\enskip y", False),
    "\\smash": ("\\smash[t]{x}^{2}", False),
    "\\llap": ("\\llap{x}y", False),
    "\\rlap": ("\\rlap{x}y", False),
    "\\clap": ("\\clap{x}y", False),
    "\\phantom": ("\\phantom{x}y", False),
    "\\hphantom": ("\\hphantom{x}y", False),
    "\\vphantom": ("\\vphantom{X}y", False),
    "\\boxed": ("\\boxed{x^2}", False),
    "\\fbox": ("\\fbox{x}", False),
    "\\href": ("\\href{https://example.com}{link}", False),
    "\\url": ("\\url{https://example.com/a}", False),
    "\\verb": ("\\verb|x|", False),
    "\\operatorname": ("\\operatorname{sin}x", False),
    "\\operatorname*": ("\\operatorname*{lim}_{n}", False),
    "\\operatorname\\*": ("\\operatorname*{lim}_{n}", False),
    "\\operatornamewithlimits": ("\\operatornamewithlimits{lim}_n", False),
    # Macros.
    "\\def": ("\\def\\h{x}\\h", False),
    "\\gdef": ("\\gdef\\g{y}\\g", False),
    "\\edef": ("\\edef\\e{z}\\e", False),
    "\\xdef": ("\\xdef\\g{y}\\g", False),
    "\\global": ("\\global\\def\\g{y}\\g", False),
    "\\let": ("\\let\\c=\\alpha\\c", False),
    "\\newcommand": ("\\newcommand{\\f}{x^2}\\f", False),
    "\\renewcommand": ("\\renewcommand{\\sum}{S}\\sum", False),
    "\\providecommand": ("\\providecommand{\\g}{g}\\g", False),
    "\\mathchoice": ("\\mathchoice{a}{b}{c}{d}", False),
    # Limits, styles.
    "\\limits": ("\\int\\limits_0^1 x", False),
    "\\nolimits": ("\\sum\\nolimits_{i} x", False),
    "\\displaystyle": ("{\\displaystyle\\sum_i x}", False),
    "\\textstyle": ("{\\textstyle\\sum_i x}", False),
    "\\scriptstyle": ("{\\scriptstyle\\sum_i x}", False),
    "\\scriptscriptstyle": ("{\\scriptscriptstyle\\sum_i x}", False),
    # Delimiter pairs.
    "\\middle": ("\\left(a\\middle|b\\right)", False),
    "\\left": ("\\left(x\\right)", False),
    "\\right": ("\\left(x\\right)", False),
    "\\big": ("\\big(x\\big)", False),
    "\\Big": ("\\Big(x\\Big)", False),
    "\\bigg": ("\\bigg(x\\bigg)", False),
    "\\Bigg": ("\\Bigg(x\\Bigg)", False),
    "\\bigl": ("\\bigl(x\\bigr)", False),
    "\\Bigl": ("\\Bigl(x\\Bigr)", False),
    "\\bigr": ("\\bigl(x\\bigr)", False),
    "\\Bigr": ("\\Bigl(x\\Bigr)", False),
    "\\bigm": ("a\\bigm|b", False),
    "\\Bigm": ("a\\Bigm|b", False),
    "\\biggm": ("a\\biggm|b", False),
    "\\Biggm": ("a\\Biggm|b", False),
    # Text-mode nationals / section marks.
    "\\aa": ("\\aa", False),
    "\\AA": ("\\AA", False),
    "\\ae": ("\\text{\\ae}", False),
    "\\AE": ("\\text{\\AE}", False),
    "\\o": ("\\text{\\o}", False),
    "\\O": ("\\text{\\O}", False),
    "\\ss": ("\\text{\\ss}", False),
    "\\oe": ("\\text{\\oe}", False),
    "\\OE": ("\\text{\\OE}", False),
    "\\sect": ("\\sect", False),
    # Text-mode symbols (natural habitat: inside \text).
    "\\textasciicircum": ("\\text{\\textasciicircum}", False),
    "\\textasciitilde": ("\\text{\\textasciitilde}", False),
    "\\textbackslash": ("\\text{\\textbackslash}", False),
    "\\textbar": ("\\text{\\textbar}", False),
    "\\textbardbl": ("\\text{\\textbardbl}", False),
    "\\textbraceleft": ("\\text{\\textbraceleft}", False),
    "\\textbraceright": ("\\text{\\textbraceright}", False),
    "\\textcircled": ("\\textcircled{a}", False),
    "\\textdagger": ("\\text{\\textdagger}", False),
    "\\textdaggerdbl": ("\\text{\\textdaggerdbl}", False),
    "\\textdegree": ("\\text{\\textdegree}", False),
    "\\textdollar": ("\\text{\\textdollar}", False),
    "\\textellipsis": ("\\text{\\textellipsis}", False),
    "\\textemdash": ("\\text{\\textemdash}", False),
    "\\textendash": ("\\text{\\textendash}", False),
    "\\textgreater": ("\\text{\\textgreater}", False),
    "\\textless": ("\\text{\\textless}", False),
    "\\textquotedblleft": ("\\text{\\textquotedblleft}", False),
    "\\textquotedblright": ("\\text{\\textquotedblright}", False),
    "\\textquoteleft": ("\\text{\\textquoteleft}", False),
    "\\textquoteright": ("\\text{\\textquoteright}", False),
    "\\textregistered": ("\\textregistered", False),
    "\\textsterling": ("\\text{\\textsterling}", False),
    "\\textunderscore": ("\\text{\\textunderscore}", False),
    # Rules, tags, misc structural.
    "\\hline": ("\\begin{array}{c}a\\\\\\hline b\\end{array}", True),
    "\\hdashline": ("\\begin{array}{c}a\\\\\\hdashline b\\end{array}", True),
    "\\cr": ("\\begin{matrix}a\\cr b\\end{matrix}", True),
    "\\arraystretch": (
        "\\renewcommand{\\arraystretch}{1.5}\\begin{matrix}a\\\\b\\end{matrix}",
        True,
    ),
    "\\begin": ("\\begin{pmatrix}a\\end{pmatrix}", False),
    "\\end": ("\\begin{pmatrix}a\\end{pmatrix}", False),
    "\\substack": ("\\sum_{\\substack{a\\\\b}}x", True),
    "\\notag": ("\\begin{aligned}a&=b\\notag\\end{aligned}", True),
    "\\nonumber": ("\\begin{aligned}a&=b\\nonumber\\end{aligned}", True),
}

# env name (without braces/star) -> full example. All display mode.
ENV = {
    "matrix": "\\begin{matrix}a&b\\\\c&d\\end{matrix}",
    "pmatrix": "\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}",
    "bmatrix": "\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}",
    "Bmatrix": "\\begin{Bmatrix}a&b\\\\c&d\\end{Bmatrix}",
    "vmatrix": "\\begin{vmatrix}a&b\\\\c&d\\end{vmatrix}",
    "Vmatrix": "\\begin{Vmatrix}a&b\\\\c&d\\end{Vmatrix}",
    "smallmatrix": "\\bigl(\\begin{smallmatrix}a&b\\\\c&d\\end{smallmatrix}\\bigr)",
    "array": "\\begin{array}{cc|c}a&b&c\\\\\\hline d&e&f\\end{array}",
    "aligned": "\\begin{aligned}a&=b+c\\\\d&=e\\end{aligned}",
    "alignedat": "\\begin{alignedat}{2}a&=b&c&=d\\end{alignedat}",
    "alignat": "\\begin{alignat}{2}a&=b&c&=d\\end{alignat}",
    "align": "\\begin{align}a&=b\\end{align}",
    "cases": "f(x)=\\begin{cases}1&x>0\\\\0&x=0\\end{cases}",
    "dcases": "\\begin{dcases}1&x>0\\\\0&x=0\\end{dcases}",
    "drcases": "\\begin{drcases}1&x>0\\end{drcases}",
    "rcases": "\\begin{rcases}1&x>0\\end{rcases}",
    "gathered": "\\begin{gathered}a\\\\b\\end{gathered}",
    "gather": "\\begin{gather}a\\\\b\\end{gather}",
    "equation": "\\begin{equation}a=b\\end{equation}",
    "split": "\\begin{equation}\\begin{split}a&=b\\\\c&=d\\end{split}\\end{equation}",
    "CD": "\\begin{CD}a@>b>>c\\end{CD}",
}

ACCENTS = {
    "acute", "bar", "breve", "check", "ddddot", "dddot", "ddot", "dot",
    "grave", "hat", "mathring", "tilde", "vec", "widecheck", "widehat",
    "widetilde",
}
BIGOPS = {
    "sum", "prod", "coprod", "int", "oint", "iint", "iiint", "bigcap",
    "bigcup", "bigodot", "bigoplus", "bigotimes", "bigsqcup", "biguplus",
    "bigvee", "bigwedge",
}
FUNCOPS = {
    "arccos", "arcsin", "arctan", "arg", "cos", "cosh", "cot", "coth",
    "csc", "deg", "det", "dim", "exp", "gcd", "hom", "inf", "ker", "lg",
    "ln", "log", "max", "min", "sup", "Pr", "sec", "sin", "sinh", "tan",
    "tanh",
}
LIMS = {"lim", "liminf", "limsup"}


def example_for(fn):
    """Return (tex, display) or None when no rule covers fn."""
    if fn in EXACT:
        return EXACT[fn]
    if fn.startswith("{") and fn.endswith("}"):
        inner = fn[1:-1]
        star = inner.endswith("*")
        name = inner[:-1] if star else inner
        if name in ENV:
            tex = ENV[name]
            if star:
                tex = tex.replace("\\begin{" + name + "}", "\\begin{" + name + "*}")
                tex = tex.replace("\\end{" + name + "}", "\\end{" + name + "*}")
            return tex, True
        return None
    if fn.startswith("\\"):
        name = fn[1:]
        if name in ACCENTS:
            return "\\" + name + "{x}", False
        if name in BIGOPS:
            return "\\" + name + "_{i=1}^n x", False
        if name in FUNCOPS:
            return "\\" + name + " x", False
        if name in LIMS:
            return "\\" + name + "_{x\\to0}", False
        if re.fullmatch(r"[A-Za-z]+\*?", name):
            # Spaces terminate the command word (else `y` joins it).
            return "x " + fn + " y", False
        return None
    return None


# Fixed slugs for renders whose derived name would mislead: `\ ` and
# `\\ ` both derive from bare whitespace (`dash`), hiding what they show.
SLUG_PIN = {"\\ ": "ctrlspace", "\\\\ ": "newline"}


def slug_for(fn, used):
    s = SLUG_PIN.get(fn, fn).lower()
    for a, b in [("\\", ""), ("{", ""), ("}", ""), ("*", "star"),
                 ("|", "pipe"), ("&", "amp"), ("^", "pow"), ("~", "tilde"),
                 ("<", "lt"), (">", "gt"), ("=", "eq"), ("(", "lp"),
                 (")", "rp"), ('"', "quot"), ("`", ""), (" ", "-"),
                 ("%", "pct"), ("#", "hash"), ("$", "dollar"),
                 ("_", "us"), (",", "comma"), (".", "dot"),
                 (":", "colon"), (";", "semi"), ("!", "bang"),
                 ("+", "plus"), ("-", "dash"), ("/", "slash"),
                 ("'", "prime"), ("\u2026", "dots")]:
        s = s.replace(a, b)
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "fn"
    base, n = s, 2
    while s.lower() in used:
        s = "%s-%d" % (base, n)
        n += 1
    used.add(s.lower())
    return s


def parse_table(path):
    sections = []
    current = None
    row_re = re.compile(r"^\| `(.*)` \| ([\w-]+) \| (.*) \|$")
    for line in open(path):
        m = re.match(r"## (.*)", line.rstrip("\n"))
        if m:
            current = {"title": m.group(1), "rows": []}
            sections.append(current)
            continue
        m = row_re.match(line.rstrip("\n"))
        if m and current is not None:
            current["rows"].append({
                "fn": m.group(1),
                "status": m.group(2),
                "note": m.group(3),
            })
    return sections


def md_escape(tex):
    # Backticks need no backslash escaping; pipes and newlines do.
    return tex.replace("|", "\\|").replace("\n", "\\n")


def main():
    sections = parse_table(TABLE)
    gaps = json.load(open(GAPS))
    gap_fns = set(gaps)
    # Resolve examples; fail on uncovered accept rows.
    used_slugs = set()
    jobs = []  # (section, row, slug, tex, display)
    missing = []
    for sec in sections:
        for row in sec["rows"]:
            if row["status"] != "accept":
                continue
            ex = example_for(row["fn"])
            if ex is None:
                missing.append(row["fn"])
                continue
            tex, display = ex
            slug = slug_for(row["fn"], used_slugs)
            jobs.append((sec, row, slug, tex, display))
    if missing:
        print("no example rule for %d accept rows:" % len(missing))
        for fn in missing:
            print("  " + fn)
        return 1
    print("%d accept rows, %d with examples" % (
        sum(1 for s in sections for r in s["rows"] if r["status"] == "accept"),
        len(jobs),
    ))
    # Build the renderer.
    r = subprocess.run(["zig", "build"], cwd=CLI_DIR)
    if r.returncode != 0:
        return r.returncode
    # Batch render to a temp dir first; checked-in renders only sync on
    # full accounting below.
    tmp = os.path.join(RENDERS, ".tmp")
    os.makedirs(RENDERS, exist_ok=True)
    corpus = [{"id": slug, "tex": tex, "display": disp, "expect": "accept"}
              for _, _, slug, tex, disp in jobs]
    corp_path = os.path.join(tmp, "corpus.json")
    os.makedirs(tmp, exist_ok=True)
    for name in os.listdir(tmp):
        if name.endswith(".png"):
            os.remove(os.path.join(tmp, name))
    json.dump(corpus, open(corp_path, "w"))
    proc = subprocess.run(
        [CLI, "--corpus", corp_path, "--outdir", tmp, "--px", str(PX)],
        cwd=CLI_DIR, capture_output=True, text=True,
    )
    log = proc.stdout + proc.stderr
    failed = set(re.findall(r"row '([^']+)' failed", log))
    by_slug = {slug: (sec, row, tex, disp) for sec, row, slug, tex, disp in jobs}
    for slug in by_slug:
        if slug not in failed and not os.path.exists(os.path.join(tmp, slug + ".png")):
            failed.add(slug)
    failed_fns = set(by_slug[s][1]["fn"] for s in failed)
    unexpected = failed_fns - gap_fns
    stale = gap_fns - failed_fns
    if unexpected:
        print("UNEXPECTED render failures (%d):" % len(unexpected))
        for fn in sorted(unexpected):
            print("  " + fn)
        return 1
    if stale:
        print("STALE gaps (now render; remove from %s):" % GAPS)
        for fn in sorted(stale):
            print("  " + fn)
        return 1
    # Sync renders/ and emit the mirror.
    want = set(slug + ".png" for _, _, slug, _, _ in jobs if slug not in failed)
    for name in os.listdir(RENDERS):
        if name == ".tmp":
            continue
        if name not in want:
            os.remove(os.path.join(RENDERS, name))
    for name in want:
        src = os.path.join(tmp, name)
        dst = os.path.join(RENDERS, name)
        if os.path.exists(dst):
            os.remove(dst)
        os.rename(src, dst)
    gap_info = gaps
    with open(MD, "w") as out:
        out.write("# KaTeX syntax mirror (generated — do not edit)\n\n")
        out.write("A render of every accepted function, generated from "
                  "`docs/support-table.md` by `tools/gen_doc_renders.py` "
                  "(renders via `zatex-png` into `docs/renders/`; expected "
                  "render gaps live in `tools/doc_gaps.json`). Status, "
                  "evidence, and ownership live in the support table — "
                  "edit that, never this file.\n\n")
        for sec in sections:
            out.write("## %s\n\n" % sec["title"])
            out.write("| Function | Example | Render | Note |\n")
            out.write("| --- | --- | --- | --- |\n")
            for row in sec["rows"]:
                fn, st = row["fn"], row["status"]
                if st != "accept":
                    out.write("| `%s` | — | — | %s |\n" % (fn, row["note"]))
                    continue
                slug = next(s for _, r, s, _, _ in jobs if r is row)
                tex = next(t for _, r, _, t, _ in jobs if r is row)
                if fn in gap_info:
                    g = gap_info[fn]
                    out.write("| `%s` | `%s` | *no render (%s)* | %s |\n" % (
                        fn, md_escape(tex), g["kind"], g["note"]))
                else:
                    out.write("| `%s` | `%s` | ![](renders/%s.png) |  |\n" % (
                        fn, md_escape(tex), slug))
            out.write("\n")
    print("mirror written: %d renders, %d gaps" % (len(want), len(failed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
