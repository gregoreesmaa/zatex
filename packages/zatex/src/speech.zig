//! Speech strings over the parse tree (issue #27), phrased after
//! KaTeX's `render-a11y-string` (pinned 0.18.7,
//! `contrib/render-a11y-string.ts`, issues #121/#124): comma
//! separators, `start …` / `end …` regions, the `powerMap` shorts
//! (`squared`, `cubed`, `degrees`), class-sensitive bin/rel words
//! (`divided by`, `is less than`), open/close-sensitive delimiters,
//! and multi-digit numbers spoken whole (`12`, never `1, 2`).
//!
//! Thin text walker for accessibility tooling: no layout math, no
//! fonts, integer-free.
//!
//! Intentional deltas from render-a11y-string (kept SRE cadence,
//! enumerated per issue #124):
//! - Sub/superscripts read `subscript … end subscript`
//!   (`start/end subscript` in KaTeX), except the powerMap shorts.
//!   Large operators with both scripts range `from … to` (KaTeX:
//!   subscript/superscript regions); `\lim`-family conditions read
//!   bare (`limit, x` — KaTeX wraps a subscript region).
//! - Unmapped symbols return `Unsupported`, failing the whole string
//!   (KaTeX reads the raw TeX instead, e.g. `\uparrow` as a rel or
//!   `\tilde` as an accent label); genuinely unknown input stays
//!   loud rather than guessed (the `\Join` test pins this).
//! - `\binom`-family fences read `choose`/`brace`/`bracket` (KaTeX:
//!   `start binomial … over … end binomial`).
//! - `\cancel`/`\box`/`sout`/`phase` bodies read transparently
//!   (KaTeX: `start cancel/box/strikeout/phase angle` regions); the
//!   over/under family keeps SRE words (`overbar`, `overbrace`, …).
//! - `\tag` reads `… tagged …` and envs, href bodies, and html
//!   branches read through (KaTeX throws on all of them).
//! - Word operators outside the a11y map (`\det`, `\gcd`, …) read
//!   raw (KaTeX parity). Large operators keep SRE names (`product`,
//!   `union`, `intersection`, `contour integral` — pinned KaTeX
//!   names only `sum`/`integral` and reads the rest raw);
//!   large operators outside our spoken six (`\biguplus`, …) are
//!   `Unsupported` (KaTeX reads them raw too).
//! - Kept SRE words where KaTeX's own maps go quiet or quirky:
//!   `minus` (pinned KaTeX reads `-` as Bin everywhere, so its
//!   `negative` entry is unreachable), `slash` (`/` is Ord),
//!   `exclamation` and `semicolon` (KaTeX reads them raw), `nabla`
//!   (KaTeX `del`), `double vertical bar` (KaTeX raw), and accent
//!   names past hat/acute/vector (KaTeX reads those labels raw).
const std = @import("std");
const zatex = @import("zatex");
const parse = zatex.parse;
const symbols = zatex.symbols;
const contract = zatex.contract;

pub fn speak(source: []const u8, display: bool, out: []u8) contract.LayoutError![]u8 {
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, display) catch |e| return e;
    var w = Walker{ .ctx = &pc, .out = out };
    w.node(root) catch |e| return e;
    return out[0..w.pos];
}

const Walker = struct {
    ctx: *parse.ParseCtx,
    out: []u8,
    pos: usize = 0,
    /// True when the last emitted word is all ASCII digits: KaTeX
    /// `buildString` folds digit runs into whole numbers (`12`,
    /// never `1, 2`), so a digit codepoint appends bare.
    last_digit: bool = false,

    fn put(self: *Walker, s: []const u8) contract.LayoutError!void {
        if (self.pos + s.len > self.out.len) return error.NoSpace;
        @memcpy(self.out[self.pos..][0..s.len], s);
        self.pos += s.len;
    }

    fn sep(self: *Walker) contract.LayoutError!void {
        // Item separator: empty output stays clean, nesting reads flat.
        if (self.pos > 0) try self.put(", ");
    }

    fn word(self: *Walker, s: []const u8) contract.LayoutError!void {
        // Digit runs fold into whole numbers (KaTeX `buildString`):
        // an all-digit word after an all-digit word appends bare.
        if (!(self.last_digit and s.len > 0 and allDigits(s))) try self.sep();
        try self.put(s);
        self.last_digit = s.len > 0 and allDigits(s);
    }

    fn wordCp(self: *Walker, cp: u21) contract.LayoutError!void {
        if (self.last_digit and cp >= '0' and cp <= '9') {
            var cbuf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &cbuf) catch return error.Unsupported;
            try self.put(cbuf[0..n]);
            return;
        }
        try self.sep();
        var cbuf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &cbuf) catch return error.Unsupported;
        try self.put(cbuf[0..n]);
        self.last_digit = cp >= '0' and cp <= '9';
    }

    fn node(self: *Walker, id: parse.Idx) contract.LayoutError!void {
        const n = parse.nodeAt(self.ctx, id);
        switch (n) {
            .atom => |a| {
                if (isLetterOrDigit(a.cp)) {
                    try self.wordCp(a.cp);
                } else {
                    try self.word(try speakAtom(a.cp, a.class));
                }
            },
            .group => |g| {
                const kids = parse.kidsOf(self.ctx, .{ .start = g.start, .len = g.len });
                for (kids) |k| try self.node(k);
            },
            .supsub => |s| try self.supsub(s),
            .frac => |f| {
                if (f.kind.fence != .none) {
                    try self.node(f.num);
                    try self.word(switch (f.kind.fence) {
                        .none => unreachable,
                        .parens => "choose",
                        .braces => "brace",
                        .brackets => "bracket",
                    });
                    try self.node(f.den);
                } else if (f.kind.bar) {
                    // KaTeX `genfrac` a11y (pinned 0.18.7): `start
                    // fraction, 1, divided by, 2, end fraction`.
                    try self.word("start fraction");
                    try self.node(f.num);
                    try self.word("divided by");
                    try self.node(f.den);
                    try self.word("end fraction");
                } else {
                    try self.node(f.num);
                    try self.word("over");
                    try self.node(f.den);
                }
            },
            .sqrt => |s| {
                // KaTeX `sqrt` a11y (pinned 0.18.7): square and cube
                // roots name both ends; any other index reads `root,
                // start index, N, end index` with the radicand
                // unspoken (KaTeX quirk, kept for parity).
                if (s.index == parse.NONE) {
                    try self.word("square root of");
                    try self.node(s.radicand);
                    try self.word("end square root");
                } else if (try self.indexIs(s.index, '3')) {
                    try self.word("cube root of");
                    try self.node(s.radicand);
                    try self.word("end cube root");
                } else {
                    try self.word("root");
                    try self.word("start index");
                    try self.node(s.index);
                    try self.word("end index");
                }
            },
            .delim => |d| {
                // KaTeX `leftright` a11y: open/close-sensitive words
                // (`[` → `open bracket`, `]` → `close bracket`), no
                // `left`/`right` prefix; `.` sides stay silent.
                if (d.left != 0 and d.left != '.') {
                    try self.word(try speakDelimOpen(d.left));
                }
                try self.node(d.body);
                if (d.right != 0 and d.right != '.') {
                    try self.word(try speakDelimClose(d.right));
                }
            },
            .middle => |m| try self.word(try genericWord(m.cp)),
            .big => |b| try self.word(try genericWord(b.cp)),
            .accent => |a| {
                // KaTeX `accent` a11y: `base, with, hat, on top`.
                try self.node(a.nucleus);
                try self.word("with");
                try self.word(try speakAccent(a.cp));
                try self.word("on top");
            },
            .over => |o| try self.over(o),
            .style => |s| try self.node(s.body),
            .size => |s| try self.node(s.body),
            .font => |f| try self.node(f.body),
            .pmb => |p| try self.node(p.body),
            .reflect => |r| try self.node(r.body),
            .vcenter => |v| try self.node(v.body),
            .circled => |c| try self.node(c.body),
            .text => |t| {
                // KaTeX `text` a11y: `start text, …, end text`
                // (`\textbf` reads `start bold text`).
                if (t.fam == .bold) {
                    try self.word("start bold text");
                } else {
                    try self.word("start text");
                }
                const toks = parse.toksOf(self.ctx, t.toks);
                for (toks) |tok| {
                    if (tok.kind == .char) {
                        // KaTeX `stringMap`: an interword space reads
                        // `space`, every other char reads literally.
                        if (tok.cp == ' ') {
                            try self.word("space");
                            continue;
                        }
                        var cbuf: [4]u8 = undefined;
                        const m = std.unicode.utf8Encode(tok.cp, &cbuf) catch continue;
                        try self.word(cbuf[0..m]);
                    }
                }
                if (t.fam == .bold) {
                    try self.word("end bold text");
                } else {
                    try self.word("end text");
                }
            },
            .env => |e| {
                const tag = @tagName(e.kind);
                try self.word(tag);
                const rows = parse.rowsOf(self.ctx, e.rows_start, e.rows_len);
                var r: usize = 0;
                while (r < rows.len) : (r += 1) {
                    try self.word("row");
                    const kids = parse.kidsOf(self.ctx, .{ .start = rows[r].start, .len = rows[r].len });
                    for (kids) |k| try self.node(k);
                }
                try self.sep();
                try self.put("end ");
                try self.put(tag);
                self.last_digit = false;
            },
            .substack => |r| {
                try self.word("substack");
                const kids = parse.kidsOf(self.ctx, .{ .start = r.start, .len = r.len });
                for (kids) |k| try self.node(k);
                try self.word("end substack");
            },
            .mathchoice => |c| try self.node(c[0]),
            .varlim => |v| try self.node(v.body),
            .opname => |o| {
                const toks = parse.toksOf(self.ctx, o.toks);
                for (toks) |tok| {
                    if (tok.kind == .char) {
                        var cbuf: [4]u8 = undefined;
                        const m = std.unicode.utf8Encode(tok.cp, &cbuf) catch continue;
                        try self.word(cbuf[0..m]);
                    }
                }
            },
            // KaTeX a11y: computed kern (`.space`) stays silent, but
            // interword spacing (`.nbsp`: `\ `, `~`) reads `space`.
            .space => {},
            .nbsp => try self.word("space"),
            .vspace => {},
            .newline => try self.word("line break"),
            .hline => {},
            // KaTeX `color` a11y: `start color red, …, end color red`.
            .color => |c| {
                try self.specWord("start color ", c.spec);
                try self.node(c.body);
                try self.specWord("end color ", c.spec);
            },
            .colorbox => |c| {
                const toks = parse.toksOf(self.ctx, c.body);
                for (toks) |tok| {
                    if (tok.kind == .char) {
                        var cbuf: [4]u8 = undefined;
                        const m = std.unicode.utf8Encode(tok.cp, &cbuf) catch continue;
                        try self.word(cbuf[0..m]);
                    }
                }
            },
            .href => |h| try self.node(h.body),
            .htmlwrap => |b| try self.node(b),
            .tag => |tg| {
                try self.node(tg.formula);
                try self.word("tagged");
                try self.node(tg.body);
            },
            .classwrap => |c| try self.node(c.body),
            // KaTeX `phantom` a11y: the body stays unspoken.
            .phantom => try self.word("empty space"),
            .boxed => |b| try self.node(b),
            .fbox => |b| try self.node(b),
            .htmlmathml => |h| try self.node(h.html),
            .cancel => |c| try self.node(c.body),
            .xcancel => |b| try self.node(b),
            .sout => |b| try self.node(b),
            .phase => |b| try self.node(b),
            .lap => |l| try self.node(l.body),
            .cdlabel => |c| try self.node(c.body),
            // KaTeX a11y order ("not equals"): modifier first.
            .not => |nt| {
                try self.word("not");
                try self.node(nt.base);
            },
            .smash => |s| try self.node(s.body),
            .raisebox => |r| try self.node(r.body),
            .rule => try self.word("rectangle"),
            .graphics => |g| {
                // The author-supplied alt text speaks (chars as
                // words, like `.text`); an empty alt announces the
                // image itself.
                const before = self.pos;
                for (parse.toksOf(self.ctx, g.alt)) |tok| {
                    if (tok.kind == .char) try self.wordCp(tok.cp);
                }
                if (self.pos == before) try self.word("image");
            },
            .op => |o| try self.op(o),
        }
    }

    fn supsub(self: *Walker, s: anytype) contract.LayoutError!void {
        // Large operators with both scripts read as ranged sums; the
        // generic case stays compositional.
        if (s.base != parse.NONE) {
            const b = parse.nodeAt(self.ctx, s.base);
            if (b == .op and b.op.large and s.sup != parse.NONE and s.sub != parse.NONE) {
                try self.word(try speakLargeOp(b.op.cp));
                try self.word("from");
                try self.node(s.sub);
                try self.word("to");
                try self.node(s.sup);
                return;
            }
            if (b == .op and b.op.large and b.op.cp == 0x6C and s.sub != parse.NONE and s.sup == parse.NONE) {
                // `lim` reads with its condition.
                try self.word("limit");
                try self.node(s.sub);
                return;
            }
            try self.node(s.base);
        }
        if (s.prime_sup) {
            // Primes live in the sup slot; speak them bare (`x prime`,
            // never "superscript").
            try self.node(s.sup);
        } else if (s.sup != parse.NONE) {
            // KaTeX `powerMap`: a lone `2`/`3`/prime/degree/circle
            // sup reads short (`x, squared`), never `superscript`.
            if (try self.supPower(s.sup)) |pw| {
                try self.word(pw);
            } else {
                try self.word("superscript");
                try self.node(s.sup);
                try self.word("end superscript");
            }
        }
        if (s.sub != parse.NONE) {
            try self.word("subscript");
            try self.node(s.sub);
            try self.word("end subscript");
        }
    }

    fn over(self: *Walker, o: anytype) contract.LayoutError!void {
        try self.node(o.nucleus);
        switch (o.kind) {
            .overline => try self.word("overbar"),
            .underline => try self.word("underbar"),
            .overbrace => try self.word("overbrace"),
            .underbrace => try self.word("underbrace"),
            .overbracket => try self.word("overbracket"),
            .underbracket => try self.word("underbracket"),
            .overset => try self.word("overset"),
            .stackrel => try self.word("stackrel"),
            .underset => try self.word("underset"),
            .xleft => try self.word("left arrow"),
            .xright => try self.word("right arrow"),
            .xboth => try self.word("left right arrow"),
            .overleft => try self.word("left harpoon"),
            .overright => try self.word("right harpoon"),
            .overboth => try self.word("left right harpoon"),
            .underleft => try self.word("left harpoon below"),
            .underright => try self.word("right harpoon below"),
            .underboth => try self.word("left right harpoon below"),
            .xhookleft => try self.word("left hook arrow"),
            .xhookright => try self.word("right hook arrow"),
            .xmapsto => try self.word("maps to"),
            .xtwoheadleft => try self.word("left two-headed arrow"),
            .xtwoheadright => try self.word("right two-headed arrow"),
            .xdoubleleft => try self.word("left double arrow"),
            .xdoubleboth => try self.word("left right double arrow"),
            .xdoubleright => try self.word("right double arrow"),
            .xleftharpoondown => try self.word("left harpoon down"),
            .xleftharpoonup => try self.word("left harpoon up"),
            .xleftrightharpoons => try self.word("left right harpoons"),
            .xlongequal => try self.word("long equals"),
            .xrightharpoondown => try self.word("right harpoon down"),
            .xrightharpoonup => try self.word("right harpoon up"),
            .xrightleftharpoons => try self.word("right left harpoons"),
            .xtofrom => try self.word("to from"),
            .overgroup => try self.word("overgroup"),
            .undergroup => try self.word("undergroup"),
            .overlinesegment => try self.word("over line segment"),
            .underlinesegment => try self.word("under line segment"),
            .overleftharpoon => try self.word("over left harpoon"),
            .overrightharpoon => try self.word("over right harpoon"),
            .overRightarrow => try self.word("over double right arrow"),
            .underbar => try self.word("underbar"),
            .utilde => try self.word("under tilde"),
            .angl => try self.word("actuarial angle"),
        }
        if (o.extra != parse.NONE) {
            try self.word("with");
            try self.node(o.extra);
        }
        if (o.under != parse.NONE) {
            try self.word("from");
            try self.node(o.under);
        }
    }

    fn op(self: *Walker, o: anytype) contract.LayoutError!void {
        // Word operators (`sin`, user `\operatorname`) carry their
        // name as text; names in the a11y map read their KaTeX word
        // (`sine`, `natural log`, …), anything else reads raw (KaTeX
        // `stringMap` fallback parity). Single-glyph large operators
        // resolve by codepoint.
        if (o.text.len > 0) {
            try self.word(opWord(o.text) orelse o.text);
            return;
        }
        try self.word(try speakLargeOp(o.cp));
    }

    /// KaTeX `powerMap` short for a superscript subtree, if it is one
    /// atom (through single-child groups) naming a mapped power.
    fn supPower(self: *Walker, id: parse.Idx) contract.LayoutError!?[]const u8 {
        var cur = id;
        while (true) {
            const n = parse.nodeAt(self.ctx, cur);
            if (n != .group) break;
            const kids = parse.kidsOf(self.ctx, n.group);
            if (kids.len != 1) return null;
            cur = kids[0];
        }
        const n = parse.nodeAt(self.ctx, cur);
        if (n != .atom) return null;
        return switch (n.atom.cp) {
            '2' => "squared",
            '3' => "cubed",
            0x2032 => "prime",
            0x00B0, 0x2218 => "degrees",
            else => null,
        };
    }

    /// True when an index subtree is one atom (through single-child
    /// groups) with the given codepoint (the cube-root check).
    fn indexIs(self: *Walker, id: parse.Idx, cp: u21) contract.LayoutError!bool {
        var cur = id;
        while (true) {
            const n = parse.nodeAt(self.ctx, cur);
            if (n != .group) break;
            const kids = parse.kidsOf(self.ctx, n.group);
            if (kids.len != 1) return false;
            cur = kids[0];
        }
        const n = parse.nodeAt(self.ctx, cur);
        return n == .atom and n.atom.cp == cp;
    }

    /// One `start/end color NAME` phrase: the validated spec range
    /// holds chars only (a name or `#hex`), buffered so the KaTeX
    /// `katex-` prefix strips before anything is emitted.
    fn specWord(self: *Walker, prefix: []const u8, spec: parse.Range) contract.LayoutError!void {
        var name: [64]u8 = undefined;
        var nlen: usize = 0;
        for (parse.toksOf(self.ctx, spec)) |tok| {
            if (tok.kind != .char) continue;
            var cbuf: [4]u8 = undefined;
            const m = std.unicode.utf8Encode(tok.cp, &cbuf) catch continue;
            if (nlen + m > name.len) return error.NoSpace;
            @memcpy(name[nlen..][0..m], cbuf[0..m]);
            nlen += m;
        }
        var name_s = name[0..nlen];
        if (std.mem.startsWith(u8, name_s, "katex-")) name_s = name_s[6..];
        try self.sep();
        try self.put(prefix);
        try self.put(name_s);
        self.last_digit = false;
    }
};

fn isLetterOrDigit(cp: u21) bool {
    return (cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z') or (cp >= '0' and cp <= '9');
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |b| if (b < '0' or b > '9') return false;
    return true;
}

/// One atom's word, dispatched on its TeX class like KaTeX
/// `buildString` (issues #121/#124, pinned 0.18.7): Bin atoms read
/// the `binMap` row, Rel atoms the `relMap` row, Open/Close atoms
/// the `openMap`/`closeMap`-then-`stringMap` rows, everything else
/// the `stringMap` row (`genericWord`). A Bin/Rel row that misses
/// falls through to the generic row, so e.g. a Rel `\uparrow` still
/// reads `up arrow`; only a total miss is `Unsupported`.
fn speakAtom(cp: u21, class: symbols.AtomClass) contract.LayoutError![]const u8 {
    switch (class) {
        .Bin => if (binWord(cp)) |w| return w,
        .Rel => if (relWord(cp)) |w| return w,
        // Bare fences carry their side as the atom class (KaTeX
        // `buildString` open/close dispatch): `\lvert` reads `open
        // vertical bar` with no `\left` in sight.
        .Open => return speakDelimOpen(cp),
        .Close => return speakDelimClose(cp),
        else => {},
    }
    return genericWord(cp);
}

/// KaTeX `binMap` by codepoint. (`/` is Ord in both engines, so its
/// `divided by` row is reachable only through `\mathbin{/}`.)
fn binWord(cp: u21) ?[]const u8 {
    return switch (cp) {
        '+' => "plus",
        '-' => "minus",
        0x00B1 => "plus minus",
        0x22C5 => "dot",
        '*' => "times",
        '/' => "divided by",
        0x00D7 => "times",
        0x00F7 => "divided by",
        0x2218 => "circle",
        0x2219 => "bullet",
        else => null,
    };
}

/// KaTeX `relMap` by codepoint.
fn relWord(cp: u21) ?[]const u8 {
    return switch (cp) {
        '=' => "equals",
        0x2248 => "approximately equals",
        0x2260 => "does not equal",
        0x2265 => "is greater than or equal to",
        0x2264 => "is less than or equal to",
        '>' => "is greater than",
        '<' => "is less than",
        0x2190, 0x21D0 => "left arrow",
        0x2192, 0x21D2 => "right arrow",
        ':' => "colon",
        else => null,
    };
}

/// KaTeX `stringMap` by codepoint (issue #121's high-traffic set on
/// top of the pre-existing rows): greeks, dots, degree, circle,
/// angle, arrows, named functions are word-ops (see `opWord`),
/// `percent`, `dollar sign`. Total miss is `Unsupported`.
fn genericWord(cp: u21) contract.LayoutError![]const u8 {
    switch (cp) {
        '+' => return "plus",
        '-' => return "minus",
        '=' => return "equals",
        '<' => return "is less than",
        '>' => return "is greater than",
        '(' => return "left parenthesis",
        ')' => return "right parenthesis",
        '[' => return "open bracket",
        ']' => return "close bracket",
        ',' => return "comma",
        '.' => return "point",
        '!' => return "exclamation",
        '?' => return "question mark",
        ':' => return "colon",
        ';' => return "semicolon",
        '/' => return "slash",
        '*' => return "star",
        '|' => return "vertical bar",
        '\'' => return "prime",
        '%' => return "percent",
        '$' => return "dollar sign",
        else => {},
    }
    const table = [_]struct { cp: u21, name: []const u8 }{
        .{ .cp = 0x03B1, .name = "alpha" },
        .{ .cp = 0x03B2, .name = "beta" },
        .{ .cp = 0x03B3, .name = "gamma" },
        .{ .cp = 0x03C9, .name = "omega" },
        .{ .cp = 0x03B8, .name = "theta" },
        .{ .cp = 0x03BB, .name = "lambda" },
        .{ .cp = 0x03B4, .name = "delta" },
        .{ .cp = 0x0394, .name = "delta" },
        .{ .cp = 0x03C1, .name = "rho" },
        .{ .cp = 0x03C4, .name = "tau" },
        .{ .cp = 0x03C0, .name = "pi" },
        .{ .cp = 0x03C3, .name = "sigma" },
        .{ .cp = 0x03BC, .name = "mu" },
        .{ .cp = 0x2113, .name = "ell" },
        .{ .cp = 0x2026, .name = "dots" },
        .{ .cp = 0x2218, .name = "circle" },
        .{ .cp = 0x00B0, .name = "degree" },
        .{ .cp = 0x2220, .name = "angle" },
        .{ .cp = 0x2190, .name = "left arrow" },
        .{ .cp = 0x2192, .name = "right arrow" },
        .{ .cp = 0x2191, .name = "up arrow" },
        .{ .cp = 0x2193, .name = "down arrow" },
        .{ .cp = 0x2195, .name = "up down arrow" },
        .{ .cp = 0x21D0, .name = "left arrow" },
        .{ .cp = 0x21D2, .name = "right arrow" },
        .{ .cp = 0x21D1, .name = "up arrow" },
        .{ .cp = 0x21D3, .name = "down arrow" },
        .{ .cp = 0x221E, .name = "infinity" },
        .{ .cp = 0x2264, .name = "is less than or equal to" },
        .{ .cp = 0x2265, .name = "is greater than or equal to" },
        .{ .cp = 0x2260, .name = "does not equal" },
        .{ .cp = 0x2248, .name = "approximately equals" },
        .{ .cp = 0x00D7, .name = "times" },
        .{ .cp = 0x00F7, .name = "divided by" },
        .{ .cp = 0x22C5, .name = "dot" },
        .{ .cp = 0x00B1, .name = "plus minus" },
        .{ .cp = 0x2202, .name = "partial" },
        .{ .cp = 0x2207, .name = "nabla" },
        .{ .cp = 0x2223, .name = "divides" },
        .{ .cp = 0x27E8, .name = "open angle" },
        .{ .cp = 0x27E9, .name = "close angle" },
        .{ .cp = 0x230A, .name = "open floor" },
        .{ .cp = 0x230B, .name = "close floor" },
        .{ .cp = 0x2016, .name = "double vertical bar" },
        .{ .cp = 0x2032, .name = "prime" },
    };
    for (table) |row| if (row.cp == cp) return row.name;
    return error.Unsupported;
}

/// KaTeX `stringMap` word for a named function (`\sin` → `sine`).
/// Names outside the a11y map read raw (KaTeX fallback parity).
fn opWord(text: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, text, "sin")) return "sine";
    if (std.mem.eql(u8, text, "cos")) return "cosine";
    if (std.mem.eql(u8, text, "tan")) return "tangent";
    if (std.mem.eql(u8, text, "cot")) return "cotangent";
    if (std.mem.eql(u8, text, "ln")) return "natural log";
    if (std.mem.eql(u8, text, "log")) return "log";
    if (std.mem.eql(u8, text, "lim")) return "limit";
    return null;
}

/// Open-position delimiter word (KaTeX `openMap`, then `stringMap`).
/// `.` (empty side) has no word — callers skip it.
fn speakDelimOpen(cp: u21) contract.LayoutError![]const u8 {
    if (cp == '|') return "open vertical bar";
    return genericWord(cp);
}

/// Close-position delimiter word (KaTeX `closeMap`, then `stringMap`).
fn speakDelimClose(cp: u21) contract.LayoutError![]const u8 {
    if (cp == '|') return "close vertical bar";
    return genericWord(cp);
}

fn speakAccent(cp: u21) contract.LayoutError![]const u8 {
    const table = [_]struct { cp: u21, name: []const u8 }{
        .{ .cp = 0x005E, .name = "hat" },
        .{ .cp = 0x02C7, .name = "check" },
        .{ .cp = 0x0060, .name = "grave" },
        .{ .cp = 0x00B4, .name = "acute" },
        .{ .cp = 0x007E, .name = "tilde" },
        .{ .cp = 0x00AF, .name = "bar" },
        .{ .cp = 0x02D8, .name = "breve" },
        .{ .cp = 0x20D7, .name = "vector" },
        .{ .cp = 0x02D9, .name = "dot" },
        .{ .cp = 0x00A8, .name = "double dot" },
    };
    for (table) |row| if (row.cp == cp) return row.name;
    return error.Unsupported;
}

fn speakLargeOp(cp: u21) contract.LayoutError![]const u8 {
    const table = [_]struct { cp: u21, name: []const u8 }{
        .{ .cp = 0x2211, .name = "sum" },
        .{ .cp = 0x220F, .name = "product" },
        .{ .cp = 0x222B, .name = "integral" },
        .{ .cp = 0x222E, .name = "contour integral" },
        .{ .cp = 0x22C3, .name = "union" },
        .{ .cp = 0x22C2, .name = "intersection" },
    };
    for (table) |row| if (row.cp == cp) return row.name;
    return error.Unsupported;
}

test "speech: fraction reads start/divided by/end (issue #124)" {
    // Pinned 0.18.7 `renderA11yString("\\frac{1}{2}")` byte parity.
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "start fraction, 1, divided by, 2, end fraction",
        try speak("\\frac12", false, &out),
    );
    try std.testing.expectEqualStrings(
        "start fraction, 1, divided by, 2, end fraction",
        try speak("\\frac{1}{2}", false, &out),
    );
}

test "speech: equation tag speaks formula then tag" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "x, tagged, start text, 1, end text",
        try speak("\\tag{1}x", true, &out),
    );
}

test "speech: powerMap shorts replace superscript (issue #124)" {
    // Pinned 0.18.7: `x^2` → `x, squared`, `x^3` → `x, cubed`.
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "x, squared",
        try speak("x^2", false, &out),
    );
    try std.testing.expectEqualStrings(
        "x, cubed",
        try speak("x^3", false, &out),
    );
    try std.testing.expectEqualStrings(
        "x, squared",
        try speak("x^{2}", false, &out),
    );
    try std.testing.expectEqualStrings(
        "x, degrees",
        try speak("x^\\circ", false, &out),
    );
    try std.testing.expectEqualStrings(
        "x, prime",
        try speak("x^\\prime", false, &out),
    );
    // Non-mapped sups keep the compositional shape (kept SRE
    // cadence, documented delta from `start/end superscript`).
    try std.testing.expectEqualStrings(
        "x, subscript, 1, end subscript",
        try speak("x_1", false, &out),
    );
    try std.testing.expectEqualStrings(
        "x, superscript, 22, end superscript",
        try speak("x^{22}", false, &out),
    );
}

test "speech: fenced stacks speak their fence (issue #93)" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "n, choose, k",
        try speak("\\binom{n}{k}", false, &out),
    );
    try std.testing.expectEqualStrings(
        "n, brace, k",
        try speak("{n\\brace k}", false, &out),
    );
    try std.testing.expectEqualStrings(
        "n, bracket, k",
        try speak("{n\\brack k}", false, &out),
    );
}

test "speech: roots name both ends (issue #124)" {
    // Pinned 0.18.7: `square root of, x, end square root`; cube
    // roots name `cube`; any other index reads `root, start index,
    // N, end index` with the radicand unspoken (KaTeX quirk, kept).
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "square root of, x, end square root",
        try speak("\\sqrt{x}", false, &out),
    );
    try std.testing.expectEqualStrings(
        "cube root of, x, end cube root",
        try speak("\\sqrt[3]{x}", false, &out),
    );
    try std.testing.expectEqualStrings(
        "root, start index, 4, end index",
        try speak("\\sqrt[4]{x}", false, &out),
    );
}

test "speech: sums range from/to, colors name regions" {
    // The large-op `from/to` ranging is kept SRE cadence (pinned
    // KaTeX uses subscript/superscript regions; see header).
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "sum, from, i, equals, 1, to, n",
        try speak("\\sum_{i=1}^n", false, &out),
    );
    // Pinned 0.18.7: `start color red, x, plus, y, end color red`
    // (KaTeX colors the rest of the expression, and so does our
    // parse — the region covers `+y` on both sides).
    try std.testing.expectEqualStrings(
        "start color red, x, plus, y, end color red",
        try speak("\\color{red}{x}+y", false, &out),
    );
}

test "speech: unmapped symbols are Unsupported, not guessed" {
    var out: [256]u8 = undefined;
    // U+22C8 (Join) parses but has no speech name.
    try std.testing.expectError(error.Unsupported, speak("\\Join", false, &out));
}

test "speech: accents read base, with, name, on top (issue #124)" {
    // Pinned 0.18.7: `x, with, hat, on top`.
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings("M, with, tilde, on top", try speak("\\tilde{M}", false, &out));
    try std.testing.expectEqualStrings("x, with, hat, on top", try speak("\\hat{x}", false, &out));
}

test "speech: high-traffic greeks are mapped (issue #121)" {
    var out: [256]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "\\omega", "omega" },
        .{ "\\theta", "theta" },
        .{ "\\lambda", "lambda" },
        .{ "\\delta", "delta" },
        .{ "\\Delta", "delta" },
        .{ "\\rho", "rho" },
        .{ "\\tau", "tau" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c[1], try speak(c[0], false, &out));
    }
}

test "speech: arrows, named functions, dots and signs (issue #121)" {
    var out: [256]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "\\leftarrow", "left arrow" },
        .{ "\\rightarrow", "right arrow" },
        .{ "\\uparrow", "up arrow" },
        .{ "\\downarrow", "down arrow" },
        .{ "\\updownarrow", "up down arrow" },
        .{ "\\Rightarrow", "right arrow" },
        .{ "\\sin", "sine" },
        .{ "\\cos", "cosine" },
        .{ "\\tan", "tangent" },
        .{ "\\ln", "natural log" },
        .{ "\\log", "log" },
        .{ "\\lim", "limit" },
        .{ "\\ell", "ell" },
        .{ "\\ldots", "dots" },
        .{ "\\circ", "circle" },
        .{ "\\degree", "degree" },
        .{ "\\angle", "angle" },
        .{ "\\%", "percent" },
        .{ "\\$", "dollar sign" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c[1], try speak(c[0], false, &out));
    }
}

test "speech: bin/rel-sensitive words (issue #124)" {
    // Pinned 0.18.7 `binMap`/`relMap` rows (+ `stringMap` singles).
    var out: [256]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "a<b", "a, is less than, b" },
        .{ "a>b", "a, is greater than, b" },
        .{ "a\\div b", "a, divided by, b" },
        .{ "a\\cdot b", "a, dot, b" },
        .{ "a\\times b", "a, times, b" },
        .{ "a*b", "a, times, b" },
        .{ "a\\approx b", "a, approximately equals, b" },
        .{ "\\ne", "does not equal" },
        .{ "\\leq", "is less than or equal to" },
        .{ "\\geq", "is greater than or equal to" },
        .{ "a.b", "a, point, b" },
        .{ "f(x) = x^2", "f, left parenthesis, x, right parenthesis, equals, x, squared" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c[1], try speak(c[0], false, &out));
    }
}

test "speech: delimiters are open/close-sensitive (issue #124)" {
    var out: [256]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "\\left(x\\right)", "left parenthesis, x, right parenthesis" },
        .{ "[x]", "open bracket, x, close bracket" },
        .{ "\\langle x\\rangle", "open angle, x, close angle" },
        .{ "\\lfloor x\\rfloor", "open floor, x, close floor" },
        .{ "\\lvert x\\rvert", "open vertical bar, x, close vertical bar" },
        .{ "\\left.x\\right.", "x" },
        .{ "12", "12" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c[1], try speak(c[0], false, &out));
    }
}

test "speech: text, spacing, rule, phantom regions (issue #124)" {
    var out: [256]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "\\text{hi}", "start text, h, i, end text" },
        .{ "\\textbf{hi}", "start bold text, h, i, end bold text" },
        .{ "a~b", "a, space, b" },
        .{ "a\\,b", "a, b" },
        .{ "\\rule{1em}{1em}", "rectangle" },
        .{ "\\phantom{x}", "empty space" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c[1], try speak(c[0], false, &out));
    }
}

