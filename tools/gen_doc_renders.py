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
# Pinned KaTeX table (byte-identical to KaTeX/KaTeX@v0.18.7
# docs/support_table.md; re-fetch on pin bump). Its Source/Rendered
# columns supply the mirror's example letters (review: exact mirror).
KATEX_TABLE = os.path.join(ROOT, "tools", "katex", "support_table.md")
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
    "\\href": ("\\href{https://github.com/gregoreesmaa/zatex}{\\text{ZaTeX}}", False),
    # Prefix/assignment commands: the generic `x \fn y` derivation is
    # invalid (missing operands); use the sweep-proven tex instead
    # (both render `A`, KaTeX-proof: arb-futurelet, arb-long).
    "\\futurelet": ("\\def\\foo{A}\\futurelet\\a\\foo\\foo", False),
    "\\long": ("\\long\\def\\foo{A}\\foo", False),
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
    "\\tag": ("\\tag{1}x", True),
    "\\tag*": ("\\tag*{a}x", True),
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
SLUG_PIN = {"\\ ": "ctrlspace", "\\\\ ": "dblbackslash"}


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


def katex_name(cell):
    """Unescape a function-name cell (`\\X` -> `X` for symbol names).
    Only the name column uses this; example spans stay verbatim."""
    raw = cell.lstrip()
    had = raw != raw.rstrip(' ')
    raw = raw.rstrip(' ')
    if had and raw.endswith(chr(92)):
        raw += ' '
    raw = raw.replace('&#060;', '<').replace('&#124;', '|')
    buf = []
    i = 0
    while i < len(raw):
        c = raw[i]
        if c == chr(92) and i + 1 < len(raw) and not raw[i + 1].isalnum() and not raw[i + 1].isspace():
            buf.append(raw[i + 1])
            i += 2
        else:
            buf.append(c)
            i += 1
    return ''.join(buf)


def clean_sep(s):
    return re.sub(r'[ \t\n]|<br[ \t\n]*/?>|&[a-z]+;', '', s)


def katex_examples(path):
    """Map fn -> [src_tex|None, ren_tex|None, ren_display] from the
    vendored KaTeX table, VERBATIM (code spans and $..$ math render
    literally upstream; only the fn name column needs unescaping).

    Source spans join with newlines; prose between spans truncates
    (e.g. href notes) with a report; single-char edge text is kept
    (the leading `a` cell). Rendered strips one $ pair ($$ is
    display). Empty/comment-only tex maps to None.
    """
    out = {}
    logical = []
    for raw_line in open(path, encoding='utf-8'):
        line = raw_line.rstrip(chr(10))
        if line.startswith('|'):
            logical.append(line)
        elif line.strip() != '' and not line.startswith('#') and logical:
            logical[-1] += chr(10) + line
    for line in logical:
        # One upstream row ({pmatrix}) lacks its trailing pipe; tolerate
        # the quirk here rather than editing the vendored fixture.
        parts = line.split('|')
        cells = parts[1:-1] if line.endswith('|') else parts[1:]
        if len(cells) < 3:
            continue
        first = cells[0].lstrip()
        if first.startswith('Symbol/Function') or re.fullmatch(r':-+', first.strip()):
            continue
        rest = cells[1:]
        fn = katex_name(cells[0])
        src_tex, ren_tex, ren_disp = None, None, False
        segs = re.split('(`[^`]*`)', rest[1])
        chunks = []
        if clean_sep(segs[0]) != '':
            if len(clean_sep(segs[0])) == 1:
                chunks.append(clean_sep(segs[0]))
            else:
                print("katex source leading prose dropped: %s <- %s" % (fn, segs[0].strip()[:40]))
        for j in range(1, len(segs), 2):
            # KaTeX nests presentational $..$ (math-italic) inside code
            # spans; unwrap to the plain equation (literal \$ survives).
            chunks.append(re.sub(r'(?<!\\)\$([^$]+?)(?<!\\)\$', r'\1',
                                 segs[j][1:-1]))
            if j + 1 < len(segs):
                mid = segs[j + 1]
                if mid == '' or clean_sep(mid) == '':
                    continue
                tail = clean_sep(mid)
                if len(tail) == 1 and j + 2 >= len(segs):
                    chunks.append(tail)
                else:
                    print("katex source truncated: %s at %s" % (fn, mid.strip()[:40]))
                    break
        if chunks:
            t = chr(10).join(chunks)
            if not (t.strip() == '' or t.lstrip().startswith('%')):
                src_tex = t
        rend = rest[0].strip()
        if rend.startswith('$$') and rend.endswith('$$') and len(rend) > 4:
            t = rend[2:-2]
            if not (t.strip() == '' or t.lstrip().startswith('%')):
                ren_tex, ren_disp = t, True
        elif rend.startswith('$') and rend.endswith('$') and len(rend) > 2:
            t = rend[1:-1]
            if not (t.strip() == '' or t.lstrip().startswith('%')):
                ren_tex, ren_disp = t, False
        out[fn] = [src_tex, ren_tex, ren_disp]
    return out


def md_escape(tex):
    # Backticks need no backslash escaping; newlines do. Pipes use an
    # entity: a backslash escape does NOT protect a pipe inside a
    # code span from table splitters (issue #82).
    return tex.replace("|", "&#124;").replace("\n", "\\n")


def fn_cell(fn):
    # Same pipe rule as md_escape for the Function cell (issue #82).
    return fn.replace("|", "&#124;")


def code_span(s):
    # Content holding a backtick (the grave-accent rows) needs a
    # double-backtick span, else the inner backtick ends the span
    # early and leaks stray backtick cells (issue #82).
    if "`" in s:
        pad = " " if s.startswith("`") or s.endswith("`") else ""
        return "``%s%s%s``" % (pad, s, pad)
    return "`%s`" % s


def check_row(line):
    # Invariant (issue #82): no literal pipe may sit inside a code
    # span of an emitted table row — any splitter would cut the row
    # into stray backtick cells. Double-backtick spans are stripped
    # first so an inner grave never misaligns the pairing.
    for span in re.findall(r"``(.*?)``", line):
        if "|" in span:
            raise SystemExit("bare pipe in code span: %s" % line.rstrip("\n"))
    single = re.sub(r"``.*?``", "", line)
    for span in re.findall(r"`([^`]*)`", single):
        if "|" in span:
            raise SystemExit("bare pipe in code span: %s" % line.rstrip("\n"))


def kx_covers(fn, tex):
    """True when tex exercises fn (KaTeX's example is usable as-is).

    Single-char functions are covered by construction. `{env}` needs
    its begin tag; commands need the command with a non-letter after
    it (so `\\bar` in `\\barwedge` does not count). When neither
    KaTeX's tex nor ours contains the function (e.g. `#` params),
    KaTeX's still wins.
    """
    if len(fn) == 1:
        return True
    if fn.startswith('{') and fn.endswith('}'):
        return (chr(92) + 'begin{' + fn[1:-1] + '}') in tex
    if not fn.startswith(chr(92)):
        return fn in tex
    i = tex.find(fn)
    while i >= 0:
        j = i + len(fn)
        nxt = tex[j:j + 1]
        if j >= len(tex) or not nxt.isascii() or not nxt.isalpha():
            return True
        i = tex.find(fn, i + 1)
    return False


# Local overrides that beat KaTeX's own examples (issue #72): the mirror
# documents ZaTeX, so brand examples must read ZaTeX, not KaTeX.
OVERRIDES = {
    # ZaTeX wordmark, logo-style (all caps with smaller raised `A`
    # and lowered `E`, tight `\!` kerns in the spirit of
    # `\LaTeX`/`\KaTeX`): subset-safe construction — scripts and
    # kerns only, no `\raisebox`, no new command (issue #76).
    "\\href": ("\\href{https://github.com/gregoreesmaa/zatex}{\\mathrm{Z\\!^AT\\!_EX}}", False),
    # The canonical `\mathclap` use is a wide limit under a display
    # sum; rendered inline the zero-width content collides with its
    # neighbors in BOTH engines (pinned KaTeX centers the same way),
    # so the mirror shows the display form.
    "\\mathclap": ("\\sum_{\\mathclap{1\\le i\\le n}} x_{i}", True),
    # No KaTeX-table cell yields an example for these accept rows, so
    # pin local ones (both render; the `\\ ` one mirrors EXACT's
    # matrix linebreak, the subarray one mirrors sweep `subarray-l`).
    # (The key carries KaTeX's trailing cell space after `\\`,
    # matching `katex_name` and SLUG_PIN; issue #91.)
    "\\\\ ": ("\\begin{matrix}a\\\\b\\end{matrix}", False),
    "{subarray}": ("\\sum_{\\begin{subarray}{l}1\\le i\\le n\\end{subarray}}x_i", True),
    # KaTeX's own example wraps in `$…$` delimiters (rejected in
    # math input here); same equation without them.
    "\\dotsm": ("x_1 x_2 \\dotsm x_n", False),
    # No KaTeX-table cell yields an example (the `to` width is
    # ignored by both engines); the sweep golden renders in both.
    "\\hbox to <dimen>": ("\\hbox to 10pt{A}", False),
    # KaTeX's own examples use shapes outside this engine's text
    # coverage (an unclosed group, `$` delimiters, nested
    # text-fonts); the sweep goldens render in both.
    "\\begingroup": ("\\begingroup x\\endgroup", False),
    # KaTeX's `\emph{nested \emph{emphasis}}` needs nested text-font
    # commands (rejected here); the flat form renders (issue #91).
    "\\emph": ("\\emph{x}", False),
    "\\endgroup": ("\\begingroup x\\endgroup", False),
    # KaTeX's own `\hbox{$x^2$}` (restored verbatim, issue #91): the
    # Source-tier derivation strips the inner `$` pair (`\hbox{x^2}`,
    # whose bare `^` text capture rejects), but the true equation
    # re-enters math mode and renders.
    "\\hbox": ("\\hbox{$x^2$}", False),
    # KaTeX's own `\reflectbox{$x^2$}` (restored verbatim, issue #97):
    # the box arg takes the `\hbox` path, so `$...$` re-enters math
    # mode and renders — and `x^2` is visibly asymmetric, proving the
    # mirror (the old flat `x` was a mirror image of itself).
    "\\reflectbox": ("\\reflectbox{$x^2$}", False),
    # KaTeX's Rendered column (`\set{x|x<5}`); its Source column uses
    # `\VERT`, undefined in BOTH engines (issue #84: Vert, not VERT).
    # The pipe form exercises the split path (issue #91).
    "\\set": ("\\set{x|x<5}", False),
    # KaTeX's own Source examples use `\\VERT`, which is undefined in
    # BOTH engines (issue #84: use Vert, never VERT), and wrap in `$`
    # delimiters this engine rejects in math input — so the mirror
    # uses the Rendered-column single-bar shapes instead. `\\Set`
    # keeps KaTeX's bare `\\frac 1 2` args (issue #89's case).
    # Console no-ops write to the JS console in KaTeX and vanish; the
    # native engine consumes and discards (no console). Each example
    # renders its surviving neighbor.
    "\\message": ("\\message{hi}x", False),
    "\\errmessage": ("\\errmessage{hi}x", False),
    "\\show": ("x\\show y", False),
    "\\braket": ("\\braket{\\phi|\\psi}", False),
    "\\Braket": ("\\Braket{\\phi|\\frac12|\\psi}", False),
    "\\Set": ("\\Set{ x | x<\\frac 1 2}", False),
}


# Accept-row notes for the mirror's Note column (issues #75/#79/#91):
# behavior contracts a render alone cannot show. Keys are
# support-table fn cells; values must avoid literal pipes in code
# spans (`check_row` enforces it on the emitted line).
ROW_NOTES = {
    # Math islands for text mode (issue #81 covers `$`, this row
    # `\(...\)`): a top-level `\(` still rejects, exactly like
    # pinned KaTeX ("Can't use function `\(` in math mode").
    "\\(\u2026\\)": "Delimiters for math islands inside `\\text`; top-level `\\(x\\)` rejects like pinned KaTeX",
    # The tag hoists to the whole equation from any position —
    # even `\text` bodies — and a row-local tag keeps its number
    # columns despite `\nonumber` (ordering pinned 0.18.7).
    "\\tag": "Hoists to the equation; a row-local tag keeps its number columns despite `\\nonumber`",
    # No visible break in running math (zero-size mspace, KaTeX
    # parity); the break only shows across env rows.
    "\\newline": "Breaks env rows like `\\\\`; inert mspace in running math",
    # KaTeX's own example lacks the function, so the local tier
    # rightly wins — recorded so nobody "fixes" these back (#91).
    "\\$": "KaTeX shows `\\text{\\textdollar}`; this form exercises `\\$`",
    "\\|": "KaTeX shows `\\Vert`; this form exercises `\\&#124;`",
}


def resolve_example(fn, kx):
    """(tex, display, tier). OVERRIDES first, then KaTeX's source spans,
    rendered column, then the local derivation. Each tier must
    exercise fn (single chars exempt); the first covering tier wins,
    else the first existing tex wins (e.g. `#` params). None only
    when no tier covers the row at all. A winning KaTeX tex this
    engine cannot render becomes a gap entry, never a silent
    substitute."""
    if fn in OVERRIDES:
        tex, disp = OVERRIDES[fn]
        return tex, disp, "local-override"
    ours = example_for(fn)
    tiers = []
    entry = kx.get(fn)
    if entry is not None:
        src_tex, ren_tex, ren_disp = entry
        if src_tex is not None:
            tiers.append((src_tex, ours[1] if ours is not None else False, "katex-source"))
        if ren_tex is not None:
            tiers.append((ren_tex, ren_disp, "katex-rendered"))
    if ours is not None:
        tiers.append((ours[0], ours[1], "local"))
    first = None
    for tex, disp, tier in tiers:
        if first is None:
            first = (tex, disp, tier)
        if kx_covers(fn, tex):
            return tex, disp, tier
    if first is not None:
        return first
    return None


def render_batch(cli, cli_dir, tmp, corp_path, px, entries):
    """Render (slug, tex, display) entries into tmp; return failed slugs."""
    for name in os.listdir(tmp):
        if name.endswith(".png"):
            os.remove(os.path.join(tmp, name))
    corpus = [{"id": slug, "tex": tex, "display": disp, "expect": "accept"}
              for slug, tex, disp in entries]
    json.dump(corpus, open(corp_path, "w"))
    proc = subprocess.run(
        [cli, "--corpus", corp_path, "--outdir", tmp, "--px", str(px)],
        cwd=cli_dir, capture_output=True, text=True,
    )
    failed = set(re.findall(r"row '([^']+)' failed", proc.stdout + proc.stderr))
    for slug, _, _ in entries:
        if slug not in failed and not os.path.exists(os.path.join(tmp, slug + ".png")):
            failed.add(slug)
    return failed


def main():
    sections = parse_table(TABLE)
    gaps = json.load(open(GAPS))
    gap_fns = set(gaps)
    kx = katex_examples(KATEX_TABLE)
    # Resolve examples; fail on uncovered accept rows.
    used_slugs = set()
    jobs = []  # [section, row, slug, tex, display]
    tiers = {}
    missing = []
    for sec in sections:
        for row in sec["rows"]:
            if row["status"] != "accept":
                continue
            ex = resolve_example(row["fn"], kx)
            if ex is None:
                missing.append(row["fn"])
                continue
            tex, display, tier = ex
            tiers[tier] = tiers.get(tier, 0) + 1
            slug = slug_for(row["fn"], used_slugs)
            jobs.append([sec, row, slug, tex, display])
    if missing:
        print("no example rule for %d accept rows:" % len(missing))
        for fn in missing:
            print("  " + fn)
        return 1
    print("example tiers: %s" % ", ".join(
        "%s=%d" % (t, tiers.get(t, 0))
        for t in ("katex-source", "katex-rendered", "local")))
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
    os.makedirs(tmp, exist_ok=True)
    corp_path = os.path.join(tmp, "corpus.json")
    by_slug = {j[2]: j for j in jobs}
    failed = render_batch(CLI, CLI_DIR, tmp, corp_path, PX,
                          [(j[2], j[3], j[4]) for j in jobs])
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
                  "edit that, never this file. Examples use KaTeX's own "
                  "equations (Source column of the vendored pinned table, "
                  "else its Rendered column); rows whose KaTeX example "
                  "this engine cannot render yet are gap-listed with "
                  "KaTeX's equation.\n\n")
        for sec in sections:
            out.write("## %s\n\n" % sec["title"])
            out.write("| Function | Example | Render | Note |\n")
            out.write("| --- | --- | --- | --- |\n")
            for row in sec["rows"]:
                fn, st = row["fn"], row["status"]
                fnc = code_span(fn_cell(fn))
                if st != "accept":
                    line = "| %s | — | — | %s |\n" % (fnc, row["note"])
                    check_row(line)
                    out.write(line)
                    continue
                slug = next(s for _, r, s, _, _ in jobs if r is row)
                tex = next(t for _, r, _, t, _ in jobs if r is row)
                exc = code_span(md_escape(tex))
                if fn in gap_info:
                    g = gap_info[fn]
                    line = "| %s | %s | *no render (%s)* | %s |\n" % (
                        fnc, exc, g["kind"], g["note"])
                else:
                    line = "| %s | %s | ![](renders/%s.png) | %s |\n" % (
                        fnc, exc, slug, ROW_NOTES.get(fn, ""))
                check_row(line)
                out.write(line)
            out.write("\n")
    print("mirror written: %d renders, %d gaps" % (len(want), len(failed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
