//! Canonical LaTeX serializer: AST back to tex (issue #27, copy-
//! as-LaTeX). Thin text walker: no layout math, no fonts. The fidelity
//! contract is a round-trip property — `mathml(serialize(x))` equals
//! `mathml(x)` — pinned per formula below, plus exact spellings for
//! the common cases. Unrepresentable nodes (rule-thickness-overridden
//! genfrac fractions, exotic lengths) return `Unsupported` instead of
//! silently changing meaning.
const std = @import("std");
const zatex = @import("zatex");
const parse = zatex.parse;
const symbols = zatex.symbols;
const contract = zatex.contract;

pub fn serialize(source: []const u8, display: bool, out: []u8) contract.LayoutError![]u8 {
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, display) catch |e| return e;
    var w = Walker{ .ctx = &pc, .out = out };
    // The root group is implicit (formula scope): bracing it would add
    // a spurious mrow on re-parse. Nested groups self-brace.
    const rn = parse.nodeAt(&pc, root);
    if (rn == .group) {
        const kids = parse.kidsOf(&pc, rn.group);
        for (kids) |k| w.node(k) catch |e| return e;
    } else {
        w.node(root) catch |e| return e;
    }
    return out[0..w.pos];
}

const Walker = struct {
    ctx: *parse.ParseCtx,
    out: []u8,
    pos: usize = 0,
    /// Set after a word-command (`\alpha`): a following letter-start
    /// needs a separating space or the lexer fuses them (`\alphax`).
    gap: bool = false,

    fn put(self: *Walker, s: []const u8) contract.LayoutError!void {
        if (self.gap and s.len > 0 and isLetter(s[0])) {
            if (self.pos + 1 > self.out.len) return error.NoSpace;
            self.out[self.pos] = ' ';
            self.pos += 1;
        }
        self.gap = false;
        if (self.pos + s.len > self.out.len) return error.NoSpace;
        @memcpy(self.out[self.pos..][0..s.len], s);
        self.pos += s.len;
    }

    fn putCp(self: *Walker, cp: u21) contract.LayoutError!void {
        var cbuf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &cbuf) catch return error.Unsupported;
        try self.put(cbuf[0..n]);
    }

    fn cmd(self: *Walker, name: []const u8) contract.LayoutError!void {
        // A backslash terminates any pending word: no gap before it.
        self.gap = false;
        try self.put("\\");
        try self.put(name);
        self.gap = isWord(name);
    }

    /// Tree-preserving argument: groups self-brace, single nodes stay
    /// bare (`\frac12` round-trips as `\frac12`, never `\frac{1}{2}`).
    /// Copy fidelity beats canonical prettiness: the tree is the truth.
    fn arg(self: *Walker, id: parse.Idx) contract.LayoutError!void {
        // Bare-prime argument (`\sqrt[3]'`, `\hat'`): the parser
        // binds a leading `'` inside as an empty-base supsub, so
        // replay the suffix bare — emitting the `{}` base would
        // re-bind the prime outside on re-parse. The `prime_sup`
        // guard pins the invariant the parser guarantees (only the
        // `'` synthesizer builds empty-base supsubs); without it a
        // future caller could emit an un-reparseable bare `^`/`_`.
        const n = parse.nodeAt(self.ctx, id);
        if (n == .supsub and n.supsub.prime_sup and self.isEmptyGroup(n.supsub.base)) {
            return self.supSuffix(n.supsub.sup, n.supsub.sub, n.supsub.prime_sup);
        }
        try self.node(id);
    }

    /// Sup/subscript suffix without the base (`'` primes, `^`, `_`).
    fn supSuffix(self: *Walker, sup: parse.Idx, sub: parse.Idx, prime_sup: bool) contract.LayoutError!void {
        if (prime_sup) {
            try self.primes(sup);
        } else if (sup != parse.NONE) {
            try self.put("^");
            try self.arg(sup);
        }
        if (sub != parse.NONE) {
            try self.put("_");
            try self.arg(sub);
        }
    }

    /// True for an empty `{}` group: the implicit base the parser
    /// allocates for a bare `'` (`\sqrt[3]'` binds it inside).
    fn isEmptyGroup(self: *Walker, id: parse.Idx) bool {
        if (id == parse.NONE) return false;
        const n = parse.nodeAt(self.ctx, id);
        if (n != .group) return false;
        return parse.kidsOf(self.ctx, n.group).len == 0;
    }

    /// Rest-scope body (`\displaystyle`, `\color` take everything to
    /// the scope end): an implicit group splices bare, anything else
    /// renders as-is. Bracing here would double the group on re-parse
    /// (explicit `{...}` kids re-brace themselves via node()).
    fn scope(self: *Walker, id: parse.Idx) contract.LayoutError!void {
        const n = parse.nodeAt(self.ctx, id);
        if (n == .group) {
            const kids = parse.kidsOf(self.ctx, n.group);
            for (kids) |k| try self.node(k);
        } else {
            try self.node(id);
        }
    }

    fn node(self: *Walker, id: parse.Idx) contract.LayoutError!void {
        const n = parse.nodeAt(self.ctx, id);
        switch (n) {
            .atom => |a| try self.atom(a.class, a.font, a.cp),
            .group => |g| {
                try self.put("{");
                const kids = parse.kidsOf(self.ctx, g);
                for (kids) |k| try self.node(k);
                try self.put("}");
            },
            .supsub => |s| {
                // Canonical order is sup-first: the tree keeps no
                // source order, and MathML is order-neutral here.
                if (s.base != parse.NONE) try self.node(s.base);
                try self.supSuffix(s.sup, s.sub, s.prime_sup);
            },
            .frac => |f| {
                if (f.kind.thick != 0) return error.Unsupported;
                if (f.kind.fence == .parens) {
                    try self.cmd("binom");
                    try self.arg(f.num);
                    try self.arg(f.den);
                } else if (f.kind.fence != .none) {
                    // Round-trip brace/brack through their infix
                    // commands (issue #93), mirroring atop below.
                    try self.put("{");
                    try self.node(f.num);
                    try self.put(switch (f.kind.fence) {
                        .none => unreachable,
                        .parens => unreachable,
                        .braces => " \\brace ",
                        .brackets => " \\brack ",
                    });
                    try self.node(f.den);
                    try self.put("}");
                } else if (f.kind.bar) {
                    try self.cmd("frac");
                    try self.arg(f.num);
                    try self.arg(f.den);
                } else {
                    try self.put("{");
                    try self.node(f.num);
                    try self.put(" \\atop ");
                    try self.node(f.den);
                    try self.put("}");
                }
            },
            .sqrt => |s| {
                try self.cmd("sqrt");
                if (s.index != parse.NONE) {
                    // The bracket scope is implicit like env cells.
                    try self.put("[");
                    const idx = parse.nodeAt(self.ctx, s.index);
                    if (idx == .group) {
                        const kids = parse.kidsOf(self.ctx, idx.group);
                        for (kids) |k| try self.node(k);
                    } else {
                        try self.node(s.index);
                    }
                    try self.put("]");
                }
                try self.arg(s.radicand);
            },
            .delim => |d| {
                // Matrix variants and cases self-fence at parse: the
                // fence node re-emerges from `\begin{...}`, so emitting
                // it again would double the fence on re-parse. Mirror
                // parse's pairing table exactly.
                if (parse.nodeAt(self.ctx, d.body) == .env) {
                    const e = parse.nodeAt(self.ctx, d.body).env;
                    const auto: ?struct { l: u21, r: u21 } = switch (e.kind) {
                        .pmatrix => .{ .l = '(', .r = ')' },
                        .bmatrix => .{ .l = '[', .r = ']' },
                        .Bmatrix => .{ .l = '{', .r = '}' },
                        .vmatrix => .{ .l = '|', .r = '|' },
                        .Vmatrix => .{ .l = 0x2016, .r = 0x2016 },
                        .cases => .{ .l = '{', .r = 0 },
                        .dcases => .{ .l = '{', .r = 0 },
                        .drcases => .{ .l = 0, .r = '}' },
                        .rcases => .{ .l = 0, .r = '}' },
                        else => null,
                    };
                    if (auto) |f| {
                        if (f.l == d.left and f.r == d.right) {
                            try self.node(d.body);
                            return;
                        }
                    }
                }
                try self.cmd("left");
                try self.delimCp(d.left);
                // Fence scope is implicit like sqrt brackets.
                const db = parse.nodeAt(self.ctx, d.body);
                if (db == .group) {
                    const kids = parse.kidsOf(self.ctx, db.group);
                    for (kids) |k| try self.node(k);
                } else {
                    try self.node(d.body);
                }
                try self.cmd("right");
                try self.delimCp(d.right);
            },
            .middle => |m| {
                try self.cmd("middle");
                try self.delimCp(m.cp);
            },
            .big => |b| {
                // Size word then side suffix: `\Bigl`, `\biggm`, ...
                try self.put("\\");
                try self.put(switch (b.level) {
                    0 => "big",
                    1 => "Big",
                    2 => "bigg",
                    3 => "Bigg",
                });
                switch (b.class) {
                    .Open => try self.put("l"),
                    .Close => try self.put("r"),
                    .Bin, .Rel => try self.put("m"),
                    else => {},
                }
                try self.delimCp(b.cp);
            },
            .accent => |a| {
                try self.cmd(symbols.accentFor(a.cp, a.wide) orelse return error.Unsupported);
                try self.arg(a.nucleus);
            },
            .over => |o| try self.over(o),
            .style => |s| {
                // A textstyle reset over a `\reflectbox` body is the
                // box command itself (issue #97: the parser builds
                // exactly this shape), so re-emit the command — a
                // bare `\textstyle \reflectbox{…}` would re-parse
                // with a doubled reset and drift the MathML.
                const inner = parse.nodeAt(self.ctx, s.body);
                if (s.style == .T and inner == .reflect and !inner.reflect.math) {
                    try self.node(s.body);
                    return;
                }
                try self.cmd(switch (s.style) {
                    .D, .Dc => "displaystyle",
                    .T, .Tc => "textstyle",
                    .S, .Sc => "scriptstyle",
                    .SS, .SSc => "scriptscriptstyle",
                });
                try self.put(" ");
                try self.scope(s.body);
            },
            .size => |s| {
                try self.cmd(switch (s.mult) {
                    500 => "tiny",
                    600 => "sixptsize",
                    700 => "scriptsize",
                    800 => "footnotesize",
                    900 => "small",
                    1000 => "normalsize",
                    1200 => "large",
                    1440 => "Large",
                    1728 => "LARGE",
                    2074 => "huge",
                    2488 => "Huge",
                    else => "normalsize",
                });
                try self.put(" ");
                try self.scope(s.body);
            },
            .pmb => |p| {
                try self.cmd("pmb");
                try self.arg(p.body);
            },
            .reflect => |r| {
                // The box argument re-braces: a bare `\text{…}` would
                // not re-parse as the captured argument. Literal text
                // keeps its raw tokens (exact `\reflectbox{x}`).
                try self.cmd(if (r.math) "mathreflectbox" else "reflectbox");
                const inner = parse.nodeAt(self.ctx, r.body);
                try self.put("{");
                if (!r.math and inner == .text) {
                    try self.textToks(parse.toksOf(self.ctx, inner.text.toks));
                } else {
                    try self.arg(r.body);
                }
                try self.put("}");
            },
            .vcenter => |v| {
                try self.cmd("vcenter");
                try self.arg(v.body);
            },
            .circled => |c| {
                try self.cmd("textcircled");
                try self.arg(c.body);
            },
            .font => |f| {
                try self.cmd(switch (f.fam) {
                    .rm => "mathrm",
                    .mathit => "mathit",
                    .bold => "mathbf",
                    .sans => "mathsf",
                    .tt => "mathtt",
                    .frak => "mathfrak",
                    .script => "mathscr",
                    .bb => "mathbb",
                    .cal => "mathcal",
                    .bolditalic => "bm",
                    .sansitalic => "mathsfit",
                });
                try self.arg(f.body);
            },
            .text => |t| {
                try self.cmd(switch (t.fam) {
                    .rm => "text",
                    .mathit => "textit",
                    .bold => "textbf",
                    .sans => "textsf",
                    .tt => "texttt",
                    else => return error.Unsupported,
                });
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, t.toks));
                try self.put("}");
            },
            .env => |e| {
                try self.cmd("begin");
                try self.put("{");
                try self.put(@tagName(e.kind));
                try self.put("}");
                if (e.kind == .array or e.kind == .subarray) {
                    try self.put("{");
                    const spec = parse.kidsOf(self.ctx, .{ .start = e.spec_start, .len = e.spec_len });
                    for (spec) |code| try self.putCp(switch (code) {
                        0 => 'l',
                        1 => 'c',
                        2 => 'r',
                        3 => '|',
                        else => return error.Unsupported,
                    });
                    try self.put("}");
                }
                const rows = parse.rowsOf(self.ctx, e.rows_start, e.rows_len);
                for (rows, 0..) |row, ri| {
                    if (ri > 0) try self.put("\\\\");
                    // Cells are implicitly grouped by position: bracing
                    // them would add spurious mrows on re-parse.
                    const kids = parse.kidsOf(self.ctx, .{ .start = row.start, .len = row.len });
                    for (kids, 0..) |k, ki| {
                        if (ki > 0) try self.put("&");
                        const cell = parse.nodeAt(self.ctx, k);
                        if (cell == .group) {
                            const ckids = parse.kidsOf(self.ctx, cell.group);
                            for (ckids) |ck| try self.node(ck);
                        } else {
                            try self.node(k);
                        }
                    }
                }
                try self.cmd("end");
                try self.put("{");
                try self.put(@tagName(e.kind));
                try self.put("}");
            },
            .substack => |r| {
                try self.cmd("substack");
                try self.put("{");
                const kids = parse.kidsOf(self.ctx, r);
                for (kids, 0..) |k, ki| {
                    if (ki > 0) try self.put("\\\\");
                    try self.node(k);
                }
                try self.put("}");
            },
            .mathchoice => |c| {
                try self.cmd("mathchoice");
                for (c) |b| try self.arg(b);
            },
            .opname => |o| {
                try self.cmd("operatorname");
                if (o.limits == .on) try self.put("*");
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, o.toks));
                try self.put("}");
                // Forced stacking re-emits its marker: without it the
                // scripts would re-parse side-set (issue #98).
                if (o.forced) try self.cmd("limits");
            },
            .varlim => |v| {
                // The body is always the built under/over; the
                // command name follows its kind.
                const varlim_cmd = switch (parse.nodeAt(self.ctx, v.body)) {
                    .over => |o| switch (o.kind) {
                        .underright => "varinjlim",
                        .underleft => "varprojlim",
                        .underline => "varliminf",
                        .overline => "varlimsup",
                        else => return error.Unsupported,
                    },
                    else => return error.Unsupported,
                };
                try self.cmd(varlim_cmd);
            },
            .space => |v| try self.space(v),
            // Interword space round-trips as the control space.
            .nbsp => try self.cmd(" "),
            .vspace => return error.Unsupported,
            .newline => try self.put("\\\\"),
            .hline => |h| try self.cmd(if (h.dashed) "hdashline" else "hline"),
            .color => |c| {
                try self.cmd("color");
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, c.spec));
                try self.put("}");
                try self.scope(c.body);
            },
            .colorbox => |c| {
                if (parse.toksOf(self.ctx, c.frame).len > 0) {
                    try self.cmd("fcolorbox");
                    try self.put("{");
                    try self.textToks(parse.toksOf(self.ctx, c.frame));
                    try self.put("}");
                } else {
                    try self.cmd("colorbox");
                }
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, c.bg));
                try self.put("}");
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, c.body));
                try self.put("}");
            },
            .href => |h| {
                try self.cmd("href");
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, h.target));
                try self.put("}");
                try self.arg(h.body);
            },
            .htmlwrap => |b| try self.node(b),
            .tag => |tg| {
                // Canonical prefix position (reparse hoists it back;
                // `x\tag{1}` round-trips as `\tag{1}{x}`).
                try self.cmd(if (tg.starred) "tag*" else "tag");
                const bt = parse.nodeAt(self.ctx, tg.body).text;
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, bt.toks));
                try self.put("}");
                try self.arg(tg.formula);
            },
            .classwrap => |c| {
                // Round-trip the wrapper (issue #51 review): dropping
                // it silently changes limit placement, so re-emit the
                // command plus any explicit limit control.
                try self.cmd(switch (c.class) {
                    .Op => "mathop",
                    .Rel => "mathrel",
                    .Inner => "mathinner",
                    .Bin => "mathbin",
                    .Punct => "mathpunct",
                    .Ord => "mathord",
                    .Open => "mathopen",
                    .Close => "mathclose",
                });
                try self.arg(c.body);
                if (c.limits == .on) try self.cmd("limits");
                if (c.limits == .off) try self.cmd("nolimits");
            },
            .phantom => |p| {
                if (p.keep_h and p.keep_v) try self.cmd("phantom");
                if (p.keep_h and !p.keep_v) try self.cmd("hphantom");
                if (!p.keep_h and p.keep_v) try self.cmd("vphantom");
                if (!p.keep_h and !p.keep_v) try self.cmd("phantom");
                try self.arg(p.body);
            },
            .boxed => |b| {
                // KaTeX desugar: `\boxed{X}` stores `style{D, X}`; the
                // displaystyle is ambient (re-added at parse), so the
                // canonical spelling drops it.
                try self.cmd("boxed");
                const inner = parse.nodeAt(self.ctx, b);
                if (inner == .style and (inner.style.style == .D or inner.style.style == .Dc)) {
                    try self.arg(inner.style.body);
                } else {
                    try self.arg(b);
                }
            },
            .fbox => |b| {
                // The body is always the handler-built `.text` node:
                // re-brace its tokens (a bare `\text{…}` here would
                // not re-parse as an hbox argument).
                const inner = parse.nodeAt(self.ctx, b);
                if (inner != .text) return error.Unsupported;
                try self.cmd("fbox");
                try self.put("{");
                try self.textToks(parse.toksOf(self.ctx, inner.text.toks));
                try self.put("}");
            },
            // Dual-branch content round-trips through the visual
            // branch (what layout and speech also read).
            .htmlmathml => |h| try self.node(h.html),
            .cancel => |c| {
                // Issue #107: `\bcancel` round-trips through its own
                // command (it used to serialize as `\cancel`).
                try self.cmd(if (c.down) "bcancel" else "cancel");
                try self.arg(c.body);
            },
            .xcancel => |b| {
                try self.cmd("xcancel");
                try self.arg(b);
            },
            .sout => |b| {
                try self.cmd("sout");
                try self.arg(b);
            },
            .phase => |b| {
                try self.cmd("phase");
                try self.arg(b);
            },
            .not => |nt| {
                try self.cmd("not");
                try self.arg(nt.base);
            },
            .lap => |l| {
                try self.cmd(switch (l.kind) {
                    .llap => "llap",
                    .rlap => "rlap",
                    .clap => "clap",
                });
                try self.arg(l.body);
            },
            .cdlabel => |c| {
                // No TeX spelling (CD-internal): serialize the label
                // body transparently (CD tables do not round-trip).
                try self.node(c.body);
            },
            .smash => |s| {
                try self.cmd("smash");
                if (s.keep_t and !s.keep_b) try self.put("[b]");
                if (!s.keep_t and s.keep_b) try self.put("[t]");
                try self.arg(s.body);
            },
            .raisebox => |r| {
                try self.cmd("raisebox");
                try self.put("{");
                try self.dimen(r.dh);
                try self.put("}");
                try self.arg(r.body);
            },
            .rule => |r| {
                try self.cmd("rule");
                if (r.raise != 0) {
                    try self.put("[");
                    try self.dimen(r.raise);
                    try self.put("]");
                }
                try self.put("{");
                try self.dimen(r.w);
                try self.put("}{");
                try self.dimen(r.h);
                try self.put("}");
            },
            .graphics => |g| {
                // Round-trip the canonical spelling: only meaningful
                // options re-emit (KaTeX field semantics — positive
                // `width`/`totalheight`, off-default `height` — plus
                // a representable `alt`), sizes as exact decimals.
                // An `alt` carrying `,=]` cannot survive the option
                // grammar, so it (and any internal token) marks the
                // node unrepresentable.
                const alt = parse.toksOf(self.ctx, g.alt);
                for (alt) |tk| {
                    if (tk.kind == .char and
                        (tk.cp == ',' or tk.cp == '=' or tk.cp == ']')) return error.Unsupported;
                    switch (tk.kind) {
                        .char, .ctrl, .lbrace, .rbrace, .sup, .sub, .amp, .newline => {},
                        else => return error.Unsupported,
                    }
                }
                try self.cmd("includegraphics");
                if (g.w > 0 or g.h != parse.graphics_default_h or g.th > 0 or alt.len > 0) {
                    var nb: [16]u8 = undefined;
                    try self.put("[");
                    var first = true;
                    if (g.w > 0) {
                        try self.put("width=");
                        try self.put(parse.fmtEm5(g.w, &nb));
                        first = false;
                    }
                    if (g.h != parse.graphics_default_h) {
                        if (!first) try self.put(",");
                        try self.put("height=");
                        try self.put(parse.fmtEm5(g.h, &nb));
                        first = false;
                    }
                    if (g.th > 0) {
                        if (!first) try self.put(",");
                        try self.put("totalheight=");
                        try self.put(parse.fmtEm5(g.th, &nb));
                        first = false;
                    }
                    if (alt.len > 0) {
                        if (!first) try self.put(",");
                        try self.put("alt=");
                        try self.graphicsToks(alt);
                    }
                    try self.put("]");
                }
                try self.put("{");
                try self.graphicsToks(parse.toksOf(self.ctx, g.src));
                try self.put("}");
            },
            .op => |o| {
                if (o.text.len > 0) {
                    try self.cmd("operatorname");
                    if (o.limits == .on) try self.put("*");
                    try self.put("{");
                    try self.put(o.text);
                    try self.put("}");
                } else if (o.func) {
                    try self.cmd(symbols.commandFor(o.cp) orelse return error.Unsupported);
                } else {
                    try self.cmd(symbols.commandFor(o.cp) orelse return error.Unsupported);
                }
                if (o.limits == .on) try self.cmd("limits");
                if (o.limits == .off) try self.cmd("nolimits");
            },
        }
    }

    fn atom(self: *Walker, class: symbols.AtomClass, font: parse.FontFam, cp: u21) contract.LayoutError!void {
        _ = class;
        // Default fonts print literally; anything else takes an
        // explicit family wrapper so the round-trip keeps mathvariant.
        const default_font: parse.FontFam = if ((cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z'))
            .mathit
        else
            .rm;
        if (font != default_font) {
            try self.cmd(switch (font) {
                .rm => "mathrm",
                .mathit => "mathit",
                .bold => "mathbf",
                .sans => "mathsf",
                .tt => "mathtt",
                .frak => "mathfrak",
                .script => "mathscr",
                .bb => "mathbb",
                .cal => "mathcal",
                .bolditalic => "bm",
                .sansitalic => "mathsfit",
            });
            try self.put("{");
            try self.putCp(cp);
            try self.put("}");
            return;
        }
        if ((cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z') or (cp >= '0' and cp <= '9')) {
            try self.putCp(cp);
            return;
        }
        // Punctuation and friends print literally when single-char.
        if (cp < 128 and needsEscape(cp)) {
            try self.put("\\");
            try self.putCp(cp);
            return;
        }
        if (cp < 128) {
            try self.putCp(cp);
            return;
        }
        try self.cmd(symbols.commandFor(cp) orelse return error.Unsupported);
    }

    fn primes(self: *Walker, id: parse.Idx) contract.LayoutError!void {
        const n = parse.nodeAt(self.ctx, id);
        if (n == .atom and n.atom.cp == 0x2032) {
            try self.put("'");
            return;
        }
        if (n == .group) {
            const kids = parse.kidsOf(self.ctx, n.group);
            for (kids) |k| {
                const a = parse.nodeAt(self.ctx, k);
                if (a != .atom or a.atom.cp != 0x2032) return error.Unsupported;
                try self.put("'");
            }
            return;
        }
        return error.Unsupported;
    }

    fn delimCp(self: *Walker, cp: u21) contract.LayoutError!void {
        if (cp == 0) {
            try self.put(".");
            return;
        }
        if (cp == '{' or cp == '}') {
            try self.put("\\");
            try self.putCp(cp);
            return;
        }
        if (cp < 128) {
            try self.putCp(cp);
            return;
        }
        try self.cmd(symbols.delimFor(cp) orelse return error.Unsupported);
    }

    fn over(self: *Walker, o: anytype) contract.LayoutError!void {
        switch (o.kind) {
            .overline => {
                try self.cmd("overline");
                try self.arg(o.nucleus);
            },
            .underline => {
                try self.cmd("underline");
                try self.arg(o.nucleus);
            },
            .overbrace => {
                try self.cmd("overbrace");
                try self.arg(o.nucleus);
                if (o.extra != parse.NONE) {
                    try self.put("^");
                    try self.arg(o.extra);
                }
            },
            .underbrace => {
                try self.cmd("underbrace");
                try self.arg(o.nucleus);
                if (o.extra != parse.NONE) {
                    try self.put("_");
                    try self.arg(o.extra);
                }
            },
            .overbracket => {
                try self.cmd("overbracket");
                try self.arg(o.nucleus);
                if (o.extra != parse.NONE) {
                    try self.put("^");
                    try self.arg(o.extra);
                }
            },
            .underbracket => {
                try self.cmd("underbracket");
                try self.arg(o.nucleus);
                if (o.extra != parse.NONE) {
                    try self.put("_");
                    try self.arg(o.extra);
                }
            },
            .overset => {
                try self.cmd("overset");
                try self.arg(o.extra);
                try self.arg(o.nucleus);
            },
            .stackrel => {
                try self.cmd("stackrel");
                try self.arg(o.extra);
                try self.arg(o.nucleus);
            },
            .underset => {
                try self.cmd("underset");
                try self.arg(o.extra);
                try self.arg(o.nucleus);
            },
            .xleft => {
                try self.cmd("xleftarrow");
                try self.xarrow(o);
            },
            .xright => {
                try self.cmd("xrightarrow");
                try self.xarrow(o);
            },
            .xboth => {
                try self.cmd("xleftrightarrow");
                try self.xarrow(o);
            },
            .xhookleft => {
                try self.cmd("xhookleftarrow");
                try self.xarrow(o);
            },
            .xhookright => {
                try self.cmd("xhookrightarrow");
                try self.xarrow(o);
            },
            .xmapsto => {
                try self.cmd("xmapsto");
                try self.xarrow(o);
            },
            .xtwoheadleft => {
                try self.cmd("xtwoheadleftarrow");
                try self.xarrow(o);
            },
            .xtwoheadright => {
                try self.cmd("xtwoheadrightarrow");
                try self.xarrow(o);
            },
            .xdoubleleft => {
                try self.cmd("xLeftarrow");
                try self.xarrow(o);
            },
            .xdoubleboth => {
                try self.cmd("xLeftrightarrow");
                try self.xarrow(o);
            },
            .xdoubleright => {
                try self.cmd("xRightarrow");
                try self.xarrow(o);
            },
            .xleftharpoondown => {
                try self.cmd("xleftharpoondown");
                try self.xarrow(o);
            },
            .xleftharpoonup => {
                try self.cmd("xleftharpoonup");
                try self.xarrow(o);
            },
            .xleftrightharpoons => {
                try self.cmd("xleftrightharpoons");
                try self.xarrow(o);
            },
            .xlongequal => {
                try self.cmd("xlongequal");
                try self.xarrow(o);
            },
            .xrightharpoondown => {
                try self.cmd("xrightharpoondown");
                try self.xarrow(o);
            },
            .xrightharpoonup => {
                try self.cmd("xrightharpoonup");
                try self.xarrow(o);
            },
            .xrightleftharpoons => {
                try self.cmd("xrightleftharpoons");
                try self.xarrow(o);
            },
            .xtofrom => {
                try self.cmd("xtofrom");
                try self.xarrow(o);
            },
            .overgroup => {
                try self.cmd("overgroup");
                try self.arg(o.nucleus);
            },
            .undergroup => {
                try self.cmd("undergroup");
                try self.arg(o.nucleus);
            },
            .overlinesegment => {
                try self.cmd("overlinesegment");
                try self.arg(o.nucleus);
            },
            .underlinesegment => {
                try self.cmd("underlinesegment");
                try self.arg(o.nucleus);
            },
            .overleftharpoon => {
                try self.cmd("overleftharpoon");
                try self.arg(o.nucleus);
            },
            .overrightharpoon => {
                try self.cmd("overrightharpoon");
                try self.arg(o.nucleus);
            },
            .overRightarrow => {
                try self.cmd("Overrightarrow");
                try self.arg(o.nucleus);
            },
            .underbar => {
                try self.cmd("underbar");
                try self.arg(o.nucleus);
            },
            .utilde => {
                try self.cmd("utilde");
                try self.arg(o.nucleus);
            },
            .angl => {
                try self.cmd("angl");
                try self.arg(o.nucleus);
            },
            else => return error.Unsupported,
        }
    }

    fn xarrow(self: *Walker, o: anytype) contract.LayoutError!void {
        if (o.under != parse.NONE) {
            try self.put("[");
            try self.node(o.under);
            try self.put("]");
        }
        try self.arg(o.extra);
    }

    fn space(self: *Walker, v: i16) contract.LayoutError!void {
        // Canonicalize by value: equivalent spellings (`\quad` vs
        // `\hspace{1em}`) share one output.
        switch (v) {
            167 => try self.cmd(","),
            222 => try self.cmd(":"),
            278 => try self.cmd(";"),
            -167 => try self.cmd("!"),
            500 => try self.cmd("enskip"),
            1000 => try self.cmd("quad"),
            2000 => try self.cmd("qquad"),
            else => {
                try self.cmd("hspace");
                try self.put("{");
                try self.dimen(v);
                try self.put("}");
            },
        }
    }

    fn dimen(self: *Walker, v: i16) contract.LayoutError!void {
        // Thousandths of an em; integral values print bare, others
        // with three decimals. Both re-parse exactly:
        // `dimenFromBytes` is integer math, so `0.056em` hits 56,
        // never 55 (mu kerns like `\mskip1mu` round-trip stably).
        if (@rem(v, 1000) != 0) {
            // Sign + up-to-2 whole digits + '.' + 3 fraction
            // digits + "em" (9 bytes worst case, digits by hand —
            // no format-spec subtleties).
            var tmp: [9]u8 = undefined;
            const mag: u32 = @intCast(if (v < 0) -@as(i32, v) else @as(i32, v));
            var head: [6]u8 = undefined;
            const hs = std.fmt.bufPrint(&head, "{s}{d}.", .{ if (v < 0) "-" else "", mag / 1000 }) catch return error.NoSpace;
            @memcpy(tmp[0..hs.len], hs);
            const f = mag % 1000;
            tmp[hs.len] = @intCast('0' + f / 100);
            tmp[hs.len + 1] = @intCast('0' + (f / 10) % 10);
            tmp[hs.len + 2] = @intCast('0' + f % 10);
            tmp[hs.len + 3] = 'e';
            tmp[hs.len + 4] = 'm';
            try self.put(tmp[0 .. hs.len + 5]);
            return;
        }
        var tmp: [8]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}em", .{@divTrunc(v, 1000)}) catch return error.NoSpace;
        try self.put(s);
    }

    fn textToks(self: *Walker, toks: []const parse.Tok) contract.LayoutError!void {
        for (toks) |tok| {
            switch (tok.kind) {
                .char => {
                    if (needsEscape(tok.cp)) try self.put("\\");
                    try self.putCp(tok.cp);
                },
                .ctrl => {
                    try self.put("\\");
                    try self.put(tok.name);
                },
                // Grouping braces are transparent in text (KaTeX
                // parity): re-emit them so arg-taking text commands
                // round-trip.
                .lbrace => try self.put("{"),
                .rbrace => try self.put("}"),
                else => return error.Unsupported,
            }
        }
    }

    /// Raw `\includegraphics` token range back to source spelling
    /// (re-parseable through `scanBracketArg`/`scanUrlArg`):
    /// `$` stays bare (KaTeX `parseUrlGroup` keeps it — `\$`
    /// would not unescape back); other specials re-escape (and
    /// unescape back); braces and `^_&` go bare; anything
    /// internal declines.
    fn graphicsToks(self: *Walker, toks: []const parse.Tok) contract.LayoutError!void {
        for (toks) |tok| {
            switch (tok.kind) {
                .char => {
                    if (tok.cp == '$') {
                        try self.putCp(tok.cp);
                    } else if (needsEscape(tok.cp)) {
                        try self.put("\\");
                        try self.putCp(tok.cp);
                    } else {
                        try self.putCp(tok.cp);
                    }
                },
                .ctrl => {
                    try self.put("\\");
                    try self.put(tok.name);
                },
                .lbrace => try self.put("{"),
                .rbrace => try self.put("}"),
                .sup => try self.put("^"),
                .sub => try self.put("_"),
                .amp => try self.put("&"),
                .newline => {
                    try self.put("\\");
                    try self.put("\n");
                },
                else => return error.Unsupported,
            }
        }
    }
};

fn isLetter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isWord(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| if (!isLetter(c)) return false;
    return true;
}

fn needsEscape(cp: u21) bool {
    return switch (cp) {
        '\\', '{', '}', '%', '&', '#', '_', '$', '^', '~' => true,
        else => false,
    };
}

test "serializer: exact canonical spellings" {
    var out: [256]u8 = undefined;
    const cases = [_][2][]const u8{
        .{ "x", "x" },
        .{ "\\alpha", "\\alpha" },
        .{ "x^2", "x^2" },
        .{ "x_1", "x_1" },
        .{ "x^{2}", "x^{2}" },
        .{ "\\frac12", "\\frac12" },
        .{ "\\frac{a}{b}", "\\frac{a}{b}" },
        .{ "\\sqrt{x}", "\\sqrt{x}" },
        .{ "\\sqrt[3]{x}", "\\sqrt[3]{x}" },
        .{ "\\left(x\\right)", "\\left(x\\right)" },
        .{ "\\color{red}{x}", "\\color{red}{x}" },
        .{ "\\text{a b}", "\\text{a b}" },
        .{ "\\sum_{i}^{n}", "\\sum^{n}_{i}" },
        .{ "\\binom{n}{k}", "\\binom{n}{k}" },
        .{ "a+b=c", "a+b=c" },
        .{ "\\overline{AB}", "\\overline{AB}" },
        .{ "\\cancel{x}", "\\cancel{x}" },
        .{ "\\bcancel{x}", "\\bcancel{x}" },
        .{ "\\xcancel{AB}", "\\xcancel{AB}" },
        .{ "\\sum x", "\\sum x" },
        .{ "\\fbox{Hi}", "\\fbox{Hi}" },
    };
    for (cases) |c| {
        const got = try serialize(c[0], false, &out);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test "serializer: round-trip keeps MathML identical" {
    const cases = [_][]const u8{
        "x",
        "x^2_1",
        "x'",
        "\\frac{a}{b}",
        "\\frac12",
        "\\sqrt{x}",
        "\\sqrt[3]{x}",
        "\\left(\\frac12\\right)",
        "\\sum_{i=1}^n i",
        "\\int_0^1 x\\,dx",
        "\\color{red}{a+b}",
        "\\color{red}x",
        "\\colorbox{yellow}{hi}",
        "\\text{hi there}",
        "a+b=c",
        "\\alpha+\\beta=\\gamma",
        "\\overline{AB}",
        "\\hat{x}",
        "\\begin{matrix}a&b\\\\c&d\\end{matrix}",
        "\\begin{cases}x&x\\ge 0\\\\-x&x<0\\end{cases}",
        "\\vec{v}",
        "\\boxed{x+1}",
        "\\fbox{Hi}",
        "\\bigl(\\frac12\\Bigr)",
        "\\sin x",
        "\\displaystyle\\sum_i x",
        "0123",
        "xyz",
        "\\mathop{x}_{y}",
        "\\mathop{x}\\limits_{y}",
        "\\mathop{x}\\nolimits_{y}",
        "\\operatorname*{asin}\\limits_y",
        "\\mathrel{x}",
        "\\mathinner{x}",
        "\\varinjlim x",
        "\\varliminf_{n}",
        "\\set{x}",
        "\\set{x|y}",
        "\\begingroup x\\endgroup",
        "\\reflectbox{x}",
        "\\mathreflectbox{x}",
        "\\tbinom{n}{k}",
        "{n\\brace k}",
        "{n\\brack k}",
        "\\emph{x}",
        "\\hbox{x}",
        "a\\bmod b",
        "\\pod{x}",
        "\\pmod{x}",
        "\\sqrt[3]'",
        "\\hat'",
        "\\overline'",
        "\\frac{{}^2}{b}",
    };
    for (cases) |src| {
        for ([_]bool{ false, true }) |display| {
            const opts: zatex.LayoutOptions = .{ .display_mode = display };
            var sbuf: [1024]u8 = undefined;
            const tex = serialize(src, display, &sbuf) catch |e| {
                std.debug.print("\nserialize {s} failed: {s}\n", .{ src, @errorName(e) });
                return e;
            };
            var m1: [8192]u8 = undefined;
            var m2: [8192]u8 = undefined;
            const a = try zatex.mathml(src, opts, &m1);
            const b = try zatex.mathml(tex, opts, &m2);
            if (!std.mem.eql(u8, a, b)) {
                std.debug.print("\nround-trip drift [{s}] -> [{s}]\n  was: {s}\n  now: {s}\n", .{ src, tex, a, b });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "serializer: equation tag round-trips in display mode" {
    // Canonical prefix position (reparse hoists it back).
    const cases = [_][2][]const u8{
        .{ "\\tag{1}x", "\\tag{1}{x}" },
        .{ "x\\tag{1}", "\\tag{1}{x}" },
        .{ "\\tag*{a}x", "\\tag*{a}{x}" },
    };
    for (cases) |c| {
        var sbuf: [1024]u8 = undefined;
        const tex = try serialize(c[0], true, &sbuf);
        try std.testing.expectEqualStrings(c[1], tex);
        var m1: [8192]u8 = undefined;
        var m2: [8192]u8 = undefined;
        const opts: zatex.LayoutOptions = .{ .display_mode = true };
        const a = try zatex.mathml(c[0], opts, &m1);
        const b = try zatex.mathml(tex, opts, &m2);
        try std.testing.expectEqualStrings(a, b);
    }
}

test "style scoping: color is transparent to atoms and spacing" {
    // Bin/Rel atoms survive styling: identical tags and identical IR
    // widths (KaTeX copy-tex likewise recovers the source through
    // style wrappers).
    const opts: zatex.LayoutOptions = .{};
    var m1: [4096]u8 = undefined;
    var m2: [4096]u8 = undefined;
    const plain = try zatex.mathml("a+b=c", opts, &m1);
    const styled = try zatex.mathml("\\color{red}{a+b=c}", opts, &m2);
    // Same mo sequence: plus and equals stay first-class atoms.
    for ([_][]const u8{ "<mo>+</mo>", "<mo>=</mo>" }) |mo| {
        try std.testing.expect(std.mem.indexOf(u8, plain, mo) != null);
        try std.testing.expect(std.mem.indexOf(u8, styled, mo) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, styled, "mathcolor") != null);
    var r0: [32]zatex.ir.Run = undefined;
    var l0: [8]zatex.ir.Rule = undefined;
    var g0: [256]u16 = undefined;
    var r1: [32]zatex.ir.Run = undefined;
    var l1: [8]zatex.ir.Rule = undefined;
    var g1: [256]u16 = undefined;
    const prov = stubProvider();
    const a = try zatex.layoutFull("a+b=c", opts, prov, &r0, &l0, &g0);
    const b = try zatex.layoutFull("\\color{red}{a+b=c}", opts, prov, &r1, &l1, &g1);
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
}

test "style scoping: colorbox keeps text, colors the box" {
    var mbuf: [4096]u8 = undefined;
    const s = try zatex.mathml("\\colorbox{yellow}{hi}", .{}, &mbuf);
    try std.testing.expect(std.mem.indexOf(u8, s, "background") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, ">hi</mtext>") != null);
}

fn stubProvider() zatex.MetricsProvider {
    const S = struct {
        fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
            return 40;
        }
    };
    return .{
        .ctx = &.{},
        .glyphId = S.glyphId,
        .advance = S.advance,
        .ruleThickness = S.ruleThickness,
    };
}

