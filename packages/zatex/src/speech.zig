//! SRE-flavored speech strings over the parse tree (issue #27).
//!
//! Thin text walker for accessibility tooling: no layout math, no
//! fonts, integer-free. Vocabulary follows the Speech Rule Engine
//! (a fraction speaks its numerator and denominator, never a slash);
//! phrasing cadence (comma separators, `end ...` closers) follows
//! KaTeX's render-a11y-string. Unmapped symbols and uncovered nodes
//! return `Unsupported` rather than guessing.
const std = @import("std");
const zatex = @import("zatex");
const parse = zatex.parse;
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
        try self.sep();
        try self.put(s);
    }

    fn wordCp(self: *Walker, cp: u21) contract.LayoutError!void {
        try self.sep();
        var cbuf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &cbuf) catch return error.Unsupported;
        try self.put(cbuf[0..n]);
    }

    fn node(self: *Walker, id: parse.Idx) contract.LayoutError!void {
        const n = parse.nodeAt(self.ctx, id);
        switch (n) {
            .atom => |a| {
                if (isLetterOrDigit(a.cp)) {
                    try self.wordCp(a.cp);
                } else {
                    try self.word(try speakAtom(a.cp));
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
                    try self.word("fraction");
                    try self.word("numerator");
                    try self.node(f.num);
                    try self.word("denominator");
                    try self.node(f.den);
                    try self.word("end fraction");
                } else {
                    try self.node(f.num);
                    try self.word("over");
                    try self.node(f.den);
                }
            },
            .sqrt => |s| {
                if (s.index == parse.NONE) {
                    try self.word("square root of");
                    try self.node(s.radicand);
                    try self.word("end root");
                } else {
                    const idx = parse.nodeAt(self.ctx, s.index);
                    if (idx == .atom and idx.atom.cp == '3') {
                        try self.word("cube root of");
                    } else {
                        try self.node(s.index);
                        try self.word("root of");
                    }
                    try self.node(s.radicand);
                    try self.word("end root");
                }
            },
            .delim => |d| {
                if (d.left != 0) {
                    try self.word("left");
                    try self.word(try speakDelim(d.left));
                }
                try self.node(d.body);
                if (d.right != 0) {
                    try self.word("right");
                    try self.word(try speakDelim(d.right));
                }
            },
            .middle => |m| try self.word(try speakDelim(m.cp)),
            .big => |b| try self.word(try speakDelim(b.cp)),
            .accent => |a| {
                try self.node(a.nucleus);
                try self.word(try speakAccent(a.cp));
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
                const toks = parse.toksOf(self.ctx, t.toks);
                for (toks) |tok| {
                    if (tok.kind == .char) {
                        var cbuf: [4]u8 = undefined;
                        const m = std.unicode.utf8Encode(tok.cp, &cbuf) catch continue;
                        try self.word(cbuf[0..m]);
                    }
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
            .space => {},
            .nbsp => {},
            .vspace => {},
            .newline => try self.word("line break"),
            .hline => {},
            .color => |c| try self.node(c.body),
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
            .phantom => |p| try self.node(p.body),
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
            .rule => try self.word("rule"),
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
            try self.word("superscript");
            try self.node(s.sup);
            try self.word("end superscript");
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
        // Word operators (`sin`, user `\operatorname`) carry their name
        // as text; single-glyph large operators resolve by codepoint.
        if (o.text.len > 0) {
            try self.word(o.text);
            return;
        }
        try self.word(try speakLargeOp(o.cp));
    }
};

fn isLetterOrDigit(cp: u21) bool {
    return (cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z') or (cp >= '0' and cp <= '9');
}

fn speakAtom(cp: u21) contract.LayoutError![]const u8 {
    const table = [_][2][]const u8{
        .{ "+", "plus" },           .{ "-", "minus" },
        .{ "=", "equals" },         .{ "<", "less than" },
        .{ ">", "greater than" },   .{ "(", "left parenthesis" },
        .{ ")", "right parenthesis" },
        .{ ",", "comma" },          .{ ".", "period" },
        .{ "!", "exclamation" },    .{ "?", "question" },
        .{ ":", "colon" },          .{ ";", "semicolon" },
        .{ "/", "slash" },          .{ "*", "star" },
        .{ "|", "vertical bar" },   .{ "'", "prime" },
    };
    for (table) |row| {
        if (row[0].len == 1 and @as(u21, row[0][0]) == cp) return row[1];
    }
    return speakSymbol(cp);
}

fn speakSymbol(cp: u21) contract.LayoutError![]const u8 {
    const table = [_]struct { cp: u21, name: []const u8 }{
        .{ .cp = 0x03B1, .name = "alpha" },
        .{ .cp = 0x03B2, .name = "beta" },
        .{ .cp = 0x03B3, .name = "gamma" },
        .{ .cp = 0x03C0, .name = "pi" },
        .{ .cp = 0x03C3, .name = "sigma" },
        .{ .cp = 0x03BC, .name = "mu" },
        .{ .cp = 0x221E, .name = "infinity" },
        .{ .cp = 0x2264, .name = "less than or equal to" },
        .{ .cp = 0x2265, .name = "greater than or equal to" },
        .{ .cp = 0x2260, .name = "not equal to" },
        .{ .cp = 0x00D7, .name = "times" },
        .{ .cp = 0x22C5, .name = "dot" },
        .{ .cp = 0x00B1, .name = "plus minus" },
        .{ .cp = 0x2202, .name = "partial" },
        .{ .cp = 0x2207, .name = "nabla" },
        .{ .cp = 0x2223, .name = "divides" },
        .{ .cp = 0x27E8, .name = "left angle" },
        .{ .cp = 0x27E9, .name = "right angle" },
        .{ .cp = 0x2032, .name = "prime" },
    };
    for (table) |row| if (row.cp == cp) return row.name;
    return error.Unsupported;
}

fn speakDelim(cp: u21) contract.LayoutError![]const u8 {
    const table = [_]struct { cp: u21, name: []const u8 }{
        .{ .cp = '(', .name = "parenthesis" },
        .{ .cp = ')', .name = "parenthesis" },
        .{ .cp = '[', .name = "bracket" },
        .{ .cp = ']', .name = "bracket" },
        .{ .cp = '{', .name = "brace" },
        .{ .cp = '}', .name = "brace" },
        .{ .cp = '|', .name = "vertical bar" },
        .{ .cp = '/', .name = "slash" },
        .{ .cp = 0x27E8, .name = "angle" },
        .{ .cp = 0x27E9, .name = "angle" },
        .{ .cp = 0x2016, .name = "double vertical bar" },
    };
    for (table) |row| if (row.cp == cp) return row.name;
    return error.Unsupported;
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

test "speech: fraction speaks numerator and denominator" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "fraction, numerator, 1, denominator, 2, end fraction",
        try speak("\\frac12", false, &out),
    );
}

test "speech: equation tag speaks formula then tag" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "x, tagged, 1",
        try speak("\\tag{1}x", true, &out),
    );
}

test "speech: scripts are compositional" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "x, superscript, 2, end superscript",
        try speak("x^2", false, &out),
    );
    try std.testing.expectEqualStrings(
        "x, subscript, 1, end subscript",
        try speak("x_1", false, &out),
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

test "speech: roots, sums, and colors" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "square root of, x, end root",
        try speak("\\sqrt{x}", false, &out),
    );
    try std.testing.expectEqualStrings(
        "sum, from, i, equals, 1, to, n",
        try speak("\\sum_{i=1}^n", false, &out),
    );
    // Style wrappers are transparent to speech.
    var a: [256]u8 = undefined;
    var b: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        try speak("a+b", false, &a),
        try speak("\\color{red}{a+b}", false, &b),
    );
}

test "speech: unmapped symbols are Unsupported, not guessed" {
    var out: [256]u8 = undefined;
    // U+22C8 (Join) parses but has no speech name.
    try std.testing.expectError(error.Unsupported, speak("\\Join", false, &out));
}

test "speech: accents speak their names" {
    var out: [256]u8 = undefined;
    try std.testing.expectEqualStrings("M, tilde", try speak("\\tilde{M}", false, &out));
    try std.testing.expectEqualStrings("x, hat", try speak("\\hat{x}", false, &out));
}
