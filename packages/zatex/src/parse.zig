//! ZaTeX front end: lexer, macro expander, parser → AST.
//!
//! Bounded and allocation-free: tokens, nodes, macro bodies, and the
//! expansion pushback all live in fixed pools inside `ParseCtx` (one
//! stack value owned by the layout call). Macro expansion is
//! token-level with a hard `max_expand` budget (KaTeX parity: 1000).
const std = @import("std");
const contract = @import("contract.zig");
const symbols = @import("symbols.zig");

const Error = contract.LayoutError;

/// Read-only AST accessors for the layout core and emitters (the
/// pools live in `ParseCtx`; these keep that ownership explicit).
pub fn nodeAt(ctx: *const ParseCtx, id: Idx) Node {
    return ctx.nodes[id];
}
pub fn kidsOf(ctx: *const ParseCtx, r: Range) []const u16 {
    return ctx.kids[r.start .. r.start + r.len];
}
pub fn rowsOf(ctx: *const ParseCtx, start: u16, len: u16) []const Row {
    return ctx.rows[start .. start + len];
}
pub fn toksOf(ctx: *const ParseCtx, r: Range) []const Tok {
    return ctx.toks[r.start .. r.start + r.len];
}

/// Operator description for limit placement (shared by the layout
/// core and the MathML emitter — one decision, two writers).
pub const OpDesc = struct {
    cp: u21,
    large: bool,
    func: bool,
    limits: LimitsMode,
    lim_def: bool,
};

/// See through transparent wrappers to the operator beneath.
pub fn opBase(ctx: *const ParseCtx, id: Idx) ?OpDesc {
    var cur = id;
    while (true) {
        switch (nodeAt(ctx, cur)) {
            .op => |o| return .{
                .cp = o.cp,
                .large = o.large,
                .func = o.func,
                .limits = o.limits,
                .lim_def = o.lim_def,
            },
            .style => |s| cur = s.body,
            .font => |f| cur = f.body,
            .color => |c| cur = c.body,
            // A background box body is text tokens, never an operator.
            .colorbox => return null,
            .href => |h| cur = h.body,
            .htmlwrap => |b| cur = b,
            else => return null,
        }
    }
}

/// Limit-vs-side decision (KaTeX parity, probed): display style stacks
/// only for default-limit operators (`\sum`, `\lim`) or forced
/// `\limits`; integrals and text style always go to the side.
pub fn useLimits(style: Style, o: OpDesc) bool {
    return style.isDisplay() and switch (o.limits) {
        .on => true,
        .off => false,
        .auto => o.lim_def,
    };
}

/// Canonical TeX glue widths in thousandths of an em (1mu = 1/18em).
/// Single source of truth for `.space` payloads (issue 16): the parser
/// produces them, `layout.zig` measures them, `mathml.zig` serializes
/// them. No other file may hard-code these widths.
pub const space_thin: i16 = 167; // 3mu: `\,` (negated for `\!`)
pub const space_med: i16 = 222; // 4mu: `\:`
pub const space_thick: i16 = 278; // 5mu: `\;`
pub const space_interword: i16 = 333; // `\ `, `~`, text spaces

pub const Idx = u16;
pub const NONE: Idx = 0xFFFF;

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

pub const TokKind = enum(u8) {
    char,
    ctrl,
    sup,
    sub,
    lbrace,
    rbrace,
    amp,
    newline,
    param,
    /// Internal sentinel: pushed before re-parsed token ranges (e.g.
    /// `\genfrac` numerator) so the formula parser stops at the range
    /// end instead of continuing into the source.
    marker,
    end,
};

/// One lexical token. `name` borrows the source (or a static string);
/// `pos` is the source byte offset (use-site offset for expanded
/// tokens — KaTeX likewise reports macro-use positions).
pub const Tok = struct {
    kind: TokKind,
    cp: u21 = 0,
    name: []const u8 = "",
    arg: u3 = 0,
    pos: u32 = 0,
    /// True for tokens injected by macro expansion: they borrow the
    /// definition's bytes while `pos` carries the use site, so there
    /// is no source cursor a raw scanner (`\verb`) could trust.
    synth: bool = false,
};

// ---------------------------------------------------------------------------
// Styles and fonts
// ---------------------------------------------------------------------------

/// TeX styles D T S SS × cramped. The layout core maps these to sizes
/// (1000/1000/700/500) and style-dependent shifts.
pub const Style = enum(u8) {
    D,
    Dc,
    T,
    Tc,
    S,
    Sc,
    SS,
    SSc,

    pub fn cramped(self: Style) Style {
        return switch (self) {
            .D => .Dc,
            .T => .Tc,
            .S => .Sc,
            .SS => .SSc,
            else => self,
        };
    }
    /// Style of superscripts/subscripts (TeX: D/T→S, S/SS→SS).
    pub fn script(self: Style) Style {
        return switch (self) {
            .D, .Dc, .T, .Tc => .S,
            .S, .Sc, .SS, .SSc => .SS,
        };
    }
    /// Numerator style (D→T, T→S, S/SS→SS), never cramped.
    pub fn numerator(self: Style) Style {
        return switch (self) {
            .D, .Dc => .T,
            .T, .Tc => .S,
            .S, .Sc, .SS, .SSc => .SS,
        };
    }
    /// Denominator style (cramped variant of the smaller style).
    pub fn denominator(self: Style) Style {
        return switch (self) {
            .D, .Dc => .Tc,
            .T, .Tc => .Sc,
            .S, .Sc, .SS, .SSc => .SSc,
        };
    }
    pub fn sizeUnits(self: Style) u16 {
        return switch (self) {
            .D, .Dc, .T, .Tc => 1000,
            .S, .Sc => 700,
            .SS, .SSc => 500,
        };
    }
    pub fn isDisplay(self: Style) bool {
        return self == .D or self == .Dc;
    }
};

/// Math font families (see `contract.FontId` for the provider mapping).
pub const FontFam = enum(u8) {
    rm,
    mathit,
    bold,
    sans,
    tt,
    frak,
    script,
    bb,
    cal,

    pub fn id(self: FontFam) u16 {
        return @intFromEnum(@as(contract.FontId, switch (self) {
            .rm => .rm,
            .mathit => .math_italic,
            .bold => .bold,
            .sans => .sans,
            .tt => .tt,
            .frak => .frak,
            .script => .script,
            .bb => .bb,
            .cal => .cal,
        }));
    }
};

// ---------------------------------------------------------------------------
// AST nodes
// ---------------------------------------------------------------------------

pub const Range = struct {
    start: u16,
    len: u16,
};

pub const Row = struct {
    start: u16,
    len: u16,
};

pub const FracKind = struct {
    bar: bool = true,
    /// Parenthesized (`\binom`, `\choose`).
    parens: bool = false,
    /// Rule thickness override in font units (0 = font default).
    thick: i32 = 0,
};

pub const LimitsMode = enum(u8) { auto, on, off };

pub const OverKind = enum(u8) {
    overline,
    underline,
    overbrace,
    underbrace,
    overleft,
    overright,
    overboth,
    underleft,
    underright,
    underboth,
    overset,
    underset,
    xleft,
    xright,
    xboth,
    xhookleft,
    xhookright,
    xmapsto,
    xtwoheadleft,
    xtwoheadright,
};

pub const EnvKind = enum(u8) {
    matrix,
    pmatrix,
    bmatrix,
    Bmatrix,
    vmatrix,
    Vmatrix,
    smallmatrix,
    array,
    aligned,
    alignedat,
    cases,
    gathered,
};

pub const LapKind = enum(u8) { llap, rlap, clap };

pub const Node = union(enum) {
    atom: struct {
        class: symbols.AtomClass,
        font: FontFam,
        cp: u21,
    },
    /// Upright or symbolic operator; `text` holds word operators
    /// (`sin`, user `\operatorname`); empty for single-glyph ops.
    op: struct {
        cp: u21,
        large: bool,
        func: bool,
        limits: LimitsMode,
        /// Default limit placement for `auto` (KaTeX: sums/lim yes,
        /// integrals/sin no).
        lim_def: bool,
        text: []const u8,
    },
    group: Range,
    frac: struct {
        num: Idx,
        den: Idx,
        kind: FracKind,
    },
    sqrt: struct {
        radicand: Idx,
        index: Idx,
    },
    supsub: struct {
        base: Idx,
        sup: Idx,
        sub: Idx,
        /// True when the sup came only from primes (`x''^2` may still
        /// take `^`; KaTeX parity).
        prime_sup: bool,
    },
    delim: struct {
        left: u21,
        right: u21,
        body: Idx,
    },
    middle: struct {
        cp: u21,
    },
    big: struct {
        cp: u21,
        level: u2,
        class: symbols.AtomClass,
    },
    accent: struct {
        cp: u21,
        wide: bool,
        nucleus: Idx,
    },
    over: struct {
        kind: OverKind,
        nucleus: Idx,
        extra: Idx,
        under: Idx,
    },
    style: struct {
        style: Style,
        body: Idx,
    },
    font: struct {
        fam: FontFam,
        body: Idx,
    },
    /// Token range (into the token arena) for `\text` bodies.
    text: struct {
        toks: Range,
        fam: FontFam,
    },
    env: struct {
        kind: EnvKind,
        rows_start: u16,
        rows_len: u16,
        spec_start: u16,
        spec_len: u16,
    },
    substack: Range,
    mathchoice: [4]Idx,
    opname: struct {
        toks: Range,
        limits: LimitsMode,
    },
    /// Explicit glue in thousandths of an em (may be negative).
    space: i16,
    vspace: i16,
    newline: void,
    hline: void,
    /// Foreground color: `spec` is the literal color-spec token
    /// range (`red`, `#f00`, `rgb(...)`). Layout renders `body`;
    /// the MathML emitter wraps it in `mstyle`.
    color: struct {
        body: Idx,
        spec: Range,
    },
    /// Background box (`\colorbox`, `\fcolorbox`): `body` is text
    /// tokens (KaTeX parses the body in text mode), `frame` is empty
    /// for `\colorbox`. Layout renders the body text.
    colorbox: struct {
        body: Range,
        bg: Range,
        frame: Range,
    },
    href: struct {
        body: Idx,
        target: Range,
    },
    htmlwrap: Idx,
    phantom: struct {
        body: Idx,
        keep_h: bool,
        keep_v: bool,
    },
    boxed: Idx,
    cancel: Idx,
    lap: struct {
        body: Idx,
        kind: LapKind,
    },
    smash: struct {
        body: Idx,
        keep_t: bool,
        keep_b: bool,
    },
    raisebox: struct {
        body: Idx,
        dh: i16,
    },
    rule: struct {
        w: i16,
        h: i16,
        dep: i16,
    },
};

/// User macro definition: token-range body with `#1..#9` params, or a
/// `\let` alias for a single token.
const Def = struct {
    name: []const u8,
    nargs: u3,
    body: Range,
    is_alias: bool = false,
    alias_tok: Tok = .{ .kind = .end },
};

/// Fixed pool sizes. Large enough for real formulas, small enough for
/// a bounded stack frame (~100 KB total).
pub const max_nodes: usize = 768;
pub const max_kids: usize = 2048;
pub const max_toks: usize = 1536;
pub const max_pushback: usize = 384;
pub const max_defs: usize = 48;
pub const max_rows: usize = 192;

pub const ParseCtx = struct {
    src: []const u8,
    spos: u32,
    nodes: [max_nodes]Node = undefined,
    nnodes: u16 = 0,
    kids: [max_kids]u16 = undefined,
    nkids: u16 = 0,
    rows: [max_rows]Row = undefined,
    nrows: u16 = 0,
    toks: [max_toks]Tok = undefined,
    ntoks: u16 = 0,
    pb: [max_pushback]Tok = undefined,
    npb: u16 = 0,
    defs: [max_defs]Def = undefined,
    ndefs: u8 = 0,
    /// When true, whitespace lexes as `char(' ')` instead of being
    /// skipped (text-mode captures). Math captures leave it false.
    keep_spaces: bool = false,
    in_env: u8 = 0,
    in_fence: u8 = 0,
    expansions: u32 = 0,
    err_pos: u32 = 0,
    err_msg: []const u8 = "",

    pub fn init(src: []const u8) ParseCtx {
        return .{ .src = src, .spos = 0 };
    }

    pub fn fail(self: *ParseCtx, pos: u32, comptime msg: []const u8) Error {
        self.err_pos = pos;
        self.err_msg = msg;
        return error.Invalid;
    }

    fn allocNode(self: *ParseCtx, n: Node) Error!Idx {
        if (self.nnodes >= max_nodes) return error.NoSpace; // pool, not depth
        const id = self.nnodes;
        self.nodes[id] = n;
        self.nnodes += 1;
        return id;
    }

    fn allocKids(self: *ParseCtx, n: usize) Error!u16 {
        if (n > max_kids - self.nkids) return error.NoSpace; // pool, not depth
        const s = self.nkids;
        self.nkids += @intCast(n);
        return s;
    }

    fn allocToks(self: *ParseCtx, n: usize) Error!u16 {
        if (n > max_toks - self.ntoks) return error.ExpansionLimit;
        const s = self.ntoks;
        self.ntoks += @intCast(n);
        return s;
    }

    fn allocRow(self: *ParseCtx, r: Row) Error!u16 {
        if (self.nrows >= max_rows) return error.NoSpace; // pool, not depth
        const id = self.nrows;
        self.rows[id] = r;
        self.nrows += 1;
        return id;
    }

    fn push(self: *ParseCtx, t: Tok) Error!void {
        if (self.npb >= max_pushback) {
            self.err_pos = t.pos;
            self.err_msg = "macro expansion too large"; // pool exhaustion surfaces as NoSpace
            return error.NoSpace;
        }
        self.pb[self.npb] = t;
        self.npb += 1;
    }

    // -- byte lexer ----------------------------------------------------

    fn skipGap(self: *ParseCtx) void {
        while (self.spos < self.src.len) {
            const c = self.src[self.spos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.spos += 1;
            } else if (c == '%') {
                while (self.spos < self.src.len and self.src[self.spos] != '\n') self.spos += 1;
            } else break;
        }
    }

    fn lexRaw(self: *ParseCtx) Error!Tok {
        if (self.keep_spaces) {
            // Skip comments only; collapse whitespace runs to one space.
            while (self.spos < self.src.len and self.src[self.spos] == '%') {
                while (self.spos < self.src.len and self.src[self.spos] != '\n') self.spos += 1;
            }
            if (self.spos < self.src.len) {
                const c = self.src[self.spos];
                if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                    const start: u32 = self.spos;
                    while (self.spos < self.src.len) {
                        const d = self.src[self.spos];
                        if (d != ' ' and d != '\t' and d != '\r' and d != '\n') break;
                        self.spos += 1;
                    }
                    return .{ .kind = .char, .cp = ' ', .pos = start };
                }
            }
            if (self.spos >= self.src.len) return .{ .kind = .end, .pos = @intCast(self.src.len) };
        } else {
            self.skipGap();
        }
        if (self.spos >= self.src.len) return .{ .kind = .end, .pos = @intCast(self.src.len) };
        const start: u32 = self.spos;
        const c = self.src[self.spos];
        if (c == '\\') {
            self.spos += 1;
            if (self.spos < self.src.len and isLetter(self.src[self.spos])) {
                const ns = self.spos;
                while (self.spos < self.src.len and isLetter(self.src[self.spos])) self.spos += 1;
                return .{ .kind = .ctrl, .name = self.src[ns..self.spos], .pos = start };
            }
            if (self.spos >= self.src.len) {
                self.err_pos = start;
                self.err_msg = "trailing backslash";
                return error.Invalid;
            }
            const d = self.src[self.spos];
            self.spos += 1;
            if (d == '\n') return .{ .kind = .newline, .pos = start };
            if (d == '\r') {
                if (self.spos < self.src.len and self.src[self.spos] == '\n') self.spos += 1;
                return .{ .kind = .newline, .pos = start };
            }
            if (d == ' ' or d == '\t') return .{ .kind = .ctrl, .name = " ", .cp = ' ', .pos = start };
            // Single-character control sequence (`\%`, `\{`, ...).
            var buf: [4]u8 = undefined;
            buf[0] = d;
            _ = &buf;
            return .{ .kind = .ctrl, .cp = d, .name = self.src[self.spos - 1 .. self.spos], .pos = start };
        }
        if (c == '{') {
            self.spos += 1;
            return .{ .kind = .lbrace, .pos = start };
        }
        if (c == '}') {
            self.spos += 1;
            return .{ .kind = .rbrace, .pos = start };
        }
        if (c == '^') {
            self.spos += 1;
            return .{ .kind = .sup, .pos = start };
        }
        if (c == '_') {
            self.spos += 1;
            return .{ .kind = .sub, .pos = start };
        }
        if (c == '&') {
            self.spos += 1;
            return .{ .kind = .amp, .pos = start };
        }
        const len = utf8Len(c);
        if (len == 0 or self.spos + len > self.src.len) {
            self.err_pos = start;
            self.err_msg = "invalid utf-8";
            return error.Invalid;
        }
        const cp = decode(self.src[self.spos .. self.spos + len]);
        self.spos += @intCast(len);
        return .{ .kind = .char, .cp = cp, .pos = start };
    }

    // -- token stream with macro expansion ------------------------------

    pub fn next(self: *ParseCtx) Error!Tok {
        if (self.npb > 0) {
            self.npb -= 1;
            return self.pb[self.npb];
        }
        return self.lexRaw();
    }

    pub fn peek(self: *ParseCtx) Error!Tok {
        const t = try self.next();
        try self.push(t);
        return t;
    }

    fn findDef(self: *ParseCtx, name: []const u8) ?*Def {
        var i: u8 = 0;
        while (i < self.ndefs) : (i += 1) {
            if (tokNameEq(self.defs[i].name, name)) return &self.defs[i];
        }
        return null;
    }

    /// Capture tokens through the matching close brace. The opening
    /// `{` must already be consumed. `#1..#9` become params (`##`
    /// stays literal) — the same capture backs macro bodies, `\text`,
    /// and token-level macro arguments.
    fn captureToBrace(self: *ParseCtx, open_pos: u32) Error!Range {
        const start = try self.allocToks(0);
        var depth: u16 = 0;
        var count: u16 = 0;
        while (true) {
            const t = try self.next();
            switch (t.kind) {
                .end => return self.fail(open_pos, "expected '}' before end of input"),
                .lbrace => {
                    depth += 1;
                    _ = try self.allocToks(1);
                    self.toks[start + count] = t;
                    count += 1;
                },
                .rbrace => {
                    if (depth == 0) return .{ .start = start, .len = count };
                    depth -= 1;
                    _ = try self.allocToks(1);
                    self.toks[start + count] = t;
                    count += 1;
                },
                .char => {
                    if (t.cp == '#') {
                        const u = try self.next();
                        if (u.kind == .char and u.cp >= '1' and u.cp <= '9') {
                            _ = try self.allocToks(1);
                            self.toks[start + count] = .{
                                .kind = .param,
                                .arg = @intCast(u.cp - '1'),
                                .pos = t.pos,
                            };
                            count += 1;
                        } else if (u.kind == .char and u.cp == '#') {
                            _ = try self.allocToks(1);
                            self.toks[start + count] = t;
                            count += 1;
                        } else {
                            return self.fail(t.pos, "unexpected '#'");
                        }
                    } else {
                        _ = try self.allocToks(1);
                        self.toks[start + count] = t;
                        count += 1;
                    }
                },
                else => {
                    _ = try self.allocToks(1);
                    self.toks[start + count] = t;
                    count += 1;
                },
            }
        }
    }

    /// Capture one token-level macro argument: a braced group (as
    /// tokens) or a single token.
    fn captureArg(self: *ParseCtx) Error!Range {
        const t = try self.peek();
        if (t.kind == .lbrace) {
            _ = try self.next();
            return self.captureToBrace(t.pos);
        }
        _ = try self.next();
        if (t.kind == .end) return self.fail(t.pos, "expected argument");
        const start = try self.allocToks(1);
        self.toks[start] = t;
        return .{ .start = start, .len = 1 };
    }

    /// Expand a user-macro use. The control token was already consumed.
    fn expandUse(self: *ParseCtx, def: *Def, use_pos: u32) Error!void {
        if (def.is_alias) {
            self.expansions += 1;
            if (self.expansions > contract.max_expand) {
                self.err_pos = use_pos;
                self.err_msg = "macro expansion limit exceeded";
                return error.ExpansionLimit;
            }
            var t = def.alias_tok;
            t.pos = use_pos;
            t.synth = true;
            return self.push(t);
        }
        var args: [9]Range = undefined;
        var i: u3 = 0;
        while (i < def.nargs) : (i += 1) args[i] = try self.captureArg();
        self.expansions += 1;
        if (self.expansions > contract.max_expand) {
            self.err_pos = use_pos;
            self.err_msg = "macro expansion limit exceeded";
            return error.ExpansionLimit;
        }
        // Push body reversed so stream order is preserved; params
        // splice their argument token ranges in order.
        var k = def.body.len;
        while (k > 0) {
            k -= 1;
            const bt = self.toks[def.body.start + k];
            if (bt.kind == .param) {
                if (bt.arg >= def.nargs) {
                    self.err_pos = use_pos;
                    self.err_msg = "macro parameter out of range";
                    return error.Invalid;
                }
                const ar = args[bt.arg];
                var j = ar.len;
                while (j > 0) {
                    j -= 1;
                    var at = self.toks[ar.start + j];
                    at.pos = use_pos;
                    at.synth = true;
                    try self.push(at);
                }
            } else {
                var nt = bt;
                nt.pos = use_pos;
                nt.synth = true;
                try self.push(nt);
            }
        }
    }
};

fn isLetter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '@';
}

pub fn tokNameEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

fn utf8Len(c: u8) u3 {
    if (c < 0x80) return 1;
    if (c & 0xE0 == 0xC0) return 2;
    if (c & 0xF0 == 0xE0) return 3;
    if (c & 0xF8 == 0xF0) return 4;
    return 0;
}

fn decode(b: []const u8) u21 {
    if (b.len == 1) return b[0];
    if (b.len == 2) return (@as(u21, b[0] & 0x1F) << 6) | (b[1] & 0x3F);
    if (b.len == 3) return (@as(u21, b[0] & 0x0F) << 12) | (@as(u21, b[1] & 0x3F) << 6) | (b[2] & 0x3F);
    return (@as(u21, b[0] & 0x07) << 18) | (@as(u21, b[1] & 0x3F) << 12) | (@as(u21, b[2] & 0x3F) << 6) | (b[3] & 0x3F);
}

test "lexer splits control sequences and symbols" {
    var ctx = ParseCtx.init("x\\alpha^2");
    const t0 = try ctx.next();
    try std.testing.expect(t0.kind == .char and t0.cp == 'x');
    const t1 = try ctx.next();
    try std.testing.expect(t1.kind == .ctrl and tokNameEq(t1.name, "alpha"));
    try std.testing.expectEqual(@as(u32, 1), t1.pos);
    const t2 = try ctx.next();
    try std.testing.expect(t2.kind == .sup);
    const t3 = try ctx.next();
    try std.testing.expect(t3.kind == .char and t3.cp == '2');
}

test "% starts a comment to end of line" {
    var ctx = ParseCtx.init("a% junk\nb");
    _ = try ctx.next();
    const t = try ctx.next();
    try std.testing.expect(t.kind == .char and t.cp == 'b');
}

test "utf-8 decodes to codepoints" {
    var ctx = ParseCtx.init("\u{03B1}");
    const t = try ctx.next();
    try std.testing.expect(t.kind == .char and t.cp == 0x03B1);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const build_options = @import("build_options");
const active_profile: contract.Profile =
    std.meta.stringToEnum(contract.Profile, build_options.profile) orelse .full;

/// Gate non-subset primitives: in the `subset` profile they vanish
/// (error.Unsupported so hosts fall back); in `full` this is a
/// comptime no-op eliminated with the branch.
fn subsetGate(comptime ok_in_subset: bool) Error!void {
    if (comptime active_profile == .subset) {
        if (!ok_in_subset) return error.Unsupported;
    }
}

const Frame = enum { top, group, leftright, envcell, bracket };

const CellTerm = enum { amp, newline, end, right };

/// Parse entry: one formula → root group node.
pub fn parse(ctx: *ParseCtx, display: bool) Error!Idx {
    _ = display;
    const root = try parseFormula(ctx, 0, .top);
    const t = try ctx.next();
    if (t.kind != .end) return ctx.fail(t.pos, "unexpected input");
    return root;
}

/// Parse a row of atoms until the frame terminator. Returns a group.
fn parseFormula(ctx: *ParseCtx, depth: u8, frame: Frame) Error!Idx {
    var buf: [512]u16 = undefined;
    var n: usize = 0;
    var bdepth: u8 = 0;
    const put = struct {
        fn p(b: *[512]u16, nn: *usize, id: Idx) Error!void {
            if (nn.* >= 512) return error.NoSpace;
            b[nn.*] = id;
            nn.* += 1;
        }
    }.p;
    while (true) {
        const t = try ctx.peek();
        if (t.kind == .marker) {
            _ = try ctx.next();
            break;
        }
        if (frame == .bracket and t.kind == .char and t.cp == ']') {
            if (bdepth == 0) {
                _ = try ctx.next();
                break;
            }
            bdepth -= 1;
        }
        if (frame == .bracket and t.kind == .char and t.cp == '[') bdepth += 1;
        switch (t.kind) {
            .end => {
                if (frame != .top) return ctx.fail(t.pos, "unexpected end of input");
                _ = try ctx.next();
                break;
            },
            .rbrace => {
                if (frame != .group) return ctx.fail(t.pos, "unexpected '}'");
                _ = try ctx.next();
                break;
            },
            .amp => {
                if (frame != .envcell) return ctx.fail(t.pos, "unexpected '&'");
                break;
            },
            .newline => {
                if (frame == .envcell) break;
                _ = try ctx.next();
                try put(&buf, &n, try ctx.allocNode(.{ .newline = {} }));
            },
            .ctrl => {
                if (isName(t, "end")) {
                    if (frame != .envcell) return ctx.fail(t.pos, "unexpected '\\end'");
                    break;
                }
                if (isName(t, "right")) {
                    if (frame != .leftright and frame != .envcell) return ctx.fail(t.pos, "unexpected '\\right'");
                    if (frame == .leftright) break;
                    // Inside an env cell, \right closes an inner \left
                    // only — but inner \left consumes its own \right,
                    // so reaching here means unbalanced.
                    return ctx.fail(t.pos, "unexpected '\\right'");
                }
                if (isName(t, "cr")) {
                    if (frame != .envcell) return ctx.fail(t.pos, "unexpected '\\cr'");
                    break;
                }
                if (isInfix(t)) {
                    // `\over`-family splits the current row: kids so
                    // far are the numerator.
                    _ = try ctx.next();
                    try subsetGate(true);
                    const num = try finishGroup(ctx, buf[0..n]);
                    const frac_id = try parseInfix(ctx, depth, frame, t, num);
                    n = 0;
                    try put(&buf, &n, frac_id);
                    // parseInfix consumed through the frame end.
                    break;
                }
                if (isName(t, "limits") or isName(t, "nolimits")) {
                    _ = try ctx.next();
                    if (n == 0) return ctx.fail(t.pos, "'\\limits' must follow an operator");
                    const last = buf[n - 1];
                    switch (ctx.nodes[last]) {
                        .op => |*o| o.limits = if (isName(t, "limits")) .on else .off,
                        else => return ctx.fail(t.pos, "'\\limits' must follow an operator"),
                    }
                    // Scripts after `\limits` attach to the same
                    // operator (`\int\limits_a^b`, KaTeX parity).
                    if (try attachScripts(ctx, depth, last)) |id| buf[n - 1] = id;
                    continue;
                }
                if (isName(t, "color") or isName(t, "textcolor")) {
                    // `\color` is a declaration: its body is the rest
                    // of the enclosing group (braces around the next
                    // atom do NOT scope it). Only `\textcolor` takes a
                    // scoped single group-or-atom body (KaTeX parity).
                    _ = try ctx.next();
                    try subsetGate(false);
                    const spec = try captureColorSpec(ctx);
                    if (isName(t, "textcolor")) {
                        const body = try parseGroupOrAtom(ctx, depth);
                        try put(&buf, &n, try ctx.allocNode(.{
                            .color = .{ .body = body, .spec = spec },
                        }));
                        continue;
                    }
                    const rest = try parseFormula(ctx, depth, frame);
                    // parseFormula consumed the frame end; wrap rest.
                    if (n >= 512) return error.NoSpace;
                    var nb: [512]u16 = undefined;
                    @memcpy(nb[0..n], buf[0..n]);
                    nb[n] = try ctx.allocNode(.{
                        .color = .{ .body = rest, .spec = spec },
                    });
                    return finishGroup(ctx, nb[0 .. n + 1]);
                }
                if (isStyleName(t.name)) {
                    _ = try ctx.next();
                    try subsetGate(false);
                    const st = styleFor(t.name);
                    const rest = try parseFormula(ctx, depth, frame);
                    // parseFormula consumed the frame end; wrap rest.
                    const g = try finishGroup(ctx, buf[0..n]);
                    _ = g;
                    const styled = try ctx.allocNode(.{ .style = .{ .style = st, .body = rest } });
                    // Rebuild: prefix + styled (rest already includes
                    // everything after the style command).
                    var nb: [512]u16 = undefined;
                    @memcpy(nb[0..n], buf[0..n]);
                    nb[n] = styled;
                    return finishGroup(ctx, nb[0 .. n + 1]);
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| try put(&buf, &n, id);
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| try put(&buf, &n, id);
            },
        }
    }
    return finishGroup(ctx, buf[0..n]);
}

fn finishGroup(ctx: *ParseCtx, kids: []const u16) Error!Idx {
    const s = try ctx.allocKids(kids.len);
    @memcpy(ctx.kids[s .. s + kids.len], kids);
    return ctx.allocNode(.{ .group = .{ .start = s, .len = @intCast(kids.len) } });
}

/// Prepend an empty group inside a cell group (aligned-environment
/// parity, see `parseEnv`). Cells are always groups; anything else
/// passes through untouched.
fn prependEmptyGroup(ctx: *ParseCtx, cell: Idx) Error!Idx {
    const g = switch (ctx.nodes[cell]) {
        .group => |gr| gr,
        else => return cell,
    };
    const empty = try ctx.allocNode(.{ .group = .{ .start = 0, .len = 0 } });
    const s = try ctx.allocKids(@as(usize, g.len) + 1);
    ctx.kids[s] = empty;
    @memcpy(ctx.kids[s + 1 .. s + 1 + g.len], ctx.kids[g.start .. g.start + g.len]);
    return ctx.allocNode(.{ .group = .{ .start = s, .len = g.len + 1 } });
}

fn isName(t: Tok, name: []const u8) bool {
    return t.kind == .ctrl and tokNameEq(t.name, name);
}

fn isInfix(t: Tok) bool {
    if (t.kind != .ctrl) return false;
    return tokNameEq(t.name, "over") or tokNameEq(t.name, "atop") or
        tokNameEq(t.name, "choose") or tokNameEq(t.name, "brace") or
        tokNameEq(t.name, "brack");
}

fn infixKind(t: Tok) FracKind {
    var kind = FracKind{ .bar = true };
    if (tokNameEq(t.name, "atop")) kind.bar = false;
    if (tokNameEq(t.name, "choose") or tokNameEq(t.name, "brace") or tokNameEq(t.name, "brack")) {
        kind.bar = false;
        kind.parens = true;
    }
    return kind;
}

/// `\over`-family: caller already consumed the command; parse the
/// denominator through the frame end and build the frac node.
fn parseInfix(ctx: *ParseCtx, depth: u8, frame: Frame, t: Tok, num: Idx) Error!Idx {
    const den = try parseFormula(ctx, depth, frame);
    return finishInfix(ctx, t, num, den);
}

fn finishInfix(ctx: *ParseCtx, t: Tok, num: Idx, den: Idx) Error!Idx {
    return ctx.allocNode(.{ .frac = .{ .num = num, .den = den, .kind = infixKind(t) } });
}

/// Parse one atom with optional `^`/`_`/`'` suffixes. Returns null
/// for side-effect commands (macro definitions) that emit no node.
fn parseAtom(ctx: *ParseCtx, depth: u8) Error!?Idx {
    const base = (try parseSingle(ctx, depth)) orelse return null;
    return attachScripts(ctx, depth, base);
}

/// One atom without suffixes (used for script and accent arguments:
/// `x^a_b` attaches both scripts to `x` — KaTeX parity).
fn parseSingleNoSuffix(ctx: *ParseCtx, depth: u8) Error!?Idx {
    return parseSingle(ctx, depth);
}

/// A braced group (full formula) or a single suffix-free atom.
fn parseGroupOrAtom(ctx: *ParseCtx, depth: u8) Error!Idx {
    const t = try ctx.peek();
    if (t.kind == .lbrace) {
        _ = try ctx.next();
        return parseFormula(ctx, depth + 1, .group);
    }
    // Depth guard: every nesting level passes through here or a group.
    if (depth >= contract.max_nesting_depth) {
        return tooDeep(ctx, t.pos);
    }
    const maybe = try parseSingle(ctx, depth + 1);
    return maybe orelse ctx.fail(t.pos, "expected argument");
}

fn tooDeep(ctx: *ParseCtx, pos: u32) Error {
    ctx.err_pos = pos;
    ctx.err_msg = "nesting too deep";
    return error.TooDeep;
}

fn parseSingle(ctx: *ParseCtx, depth: u8) Error!?Idx {
    if (depth >= contract.max_nesting_depth) {
        const t = try ctx.peek();
        return tooDeep(ctx, t.pos);
    }
    const t = try ctx.next();
    switch (t.kind) {
        .char => {
            // Captured whitespace never reaches math (text captures
            // own it); guard anyway.
            if (t.cp == ' ') return null;
            // TeX parameter character: only legal inside macro
            // definitions (handled by the token capturer); KaTeX
            // rejects it in math mode.
            if (t.cp == '#') return ctx.fail(t.pos, "unexpected '#'");
            // KaTeX has no `$` delimiters inside math input.
            if (t.cp == '$') return ctx.fail(t.pos, "can't use '$' in math mode");
            if (t.cp == '~') {
                const id: ?Idx = try ctx.allocNode(.{ .space = space_interword });
                return id;
            }
            if (t.cp == '\'') {
                const id: ?Idx = try ctx.allocNode(.{ .atom = .{
                    .class = .Ord,
                    .font = .rm,
                    .cp = 0x2032,
                } });
                return id;
            }
            const cls = symbols.asciiClass(t.cp) orelse .Ord;
            const font: FontFam = if (t.cp >= '0' and t.cp <= '9')
                .rm
            else if ((t.cp >= 'a' and t.cp <= 'z') or (t.cp >= 'A' and t.cp <= 'Z'))
                .mathit
            else
                .rm;
            const id: ?Idx = try ctx.allocNode(.{ .atom = .{ .class = cls, .font = font, .cp = t.cp } });
            return id;
        },
        .lbrace => {
            const id: ?Idx = try parseFormula(ctx, depth + 1, .group);
            return id;
        },
        .sup => return ctx.fail(t.pos, "expected base before '^'"),
        .sub => return ctx.fail(t.pos, "expected base before '_'"),
        .amp => return ctx.fail(t.pos, "unexpected '&'"),
        .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
        .newline => {
            const id: ?Idx = try ctx.allocNode(.{ .newline = {} });
            return id;
        },
        .param => return ctx.fail(t.pos, "unexpected '#'"),
        .marker => return ctx.fail(t.pos, "unexpected input"),
        .end => return ctx.fail(t.pos, "unexpected end of input"),
        .ctrl => {
            // Macro definitions are side effects (no node).
            if (t.name.len > 1) {
                if (tokNameEq(t.name, "newcommand") or tokNameEq(t.name, "renewcommand") or
                    tokNameEq(t.name, "providecommand"))
                {
                    try subsetGate(false);
                    try parseNewCommand(ctx, t, tokNameEq(t.name, "renewcommand"), tokNameEq(t.name, "providecommand"));
                    return null;
                }
                if (tokNameEq(t.name, "def") or tokNameEq(t.name, "gdef")) {
                    try subsetGate(false);
                    try parseDef(ctx, t);
                    return null;
                }
                if (tokNameEq(t.name, "let")) {
                    try subsetGate(false);
                    try parseLet(ctx, t);
                    return null;
                }
            }
            // User macros shadow builtins.
            if (t.name.len > 0 and isMacroName(t)) {
                if (ctx.findDef(t.name)) |def| {
                    try ctx.expandUse(def, t.pos);
                    return parseSingle(ctx, depth);
                }
            }
            const id: ?Idx = try parseCtrl(ctx, depth, t);
            return id;
        },
    }
}

fn isMacroName(t: Tok) bool {
    // Single-character names always go through macro lookup too
    // (`\let` can alias anything); multi-letter names likewise.
    return t.kind == .ctrl;
}

/// Attach `^`/`_`/`'` suffixes to a base node.
fn attachScripts(ctx: *ParseCtx, depth: u8, base: Idx) Error!?Idx {
    var sup_parts: [9]Idx = undefined;
    var nsup: u8 = 0;
    var prime_made = false;
    var sub: Idx = NONE;
    while (true) {
        const p = try ctx.peek();
        if (p.kind == .sup) {
            _ = try ctx.next();
            if (nsup > 0 and !prime_made) return ctx.fail(p.pos, "double superscript");
            // KaTeX parity: a missing group at EOF points at the
            // operator (`x^` → 1), not at end of input.
            if ((try ctx.peek()).kind == .end) return ctx.fail(p.pos, "expected group after '^'");
            const s = try parseGroupOrAtom(ctx, depth);
            if (prime_made) {
                if (nsup >= 9) return ctx.fail(p.pos, "superscript too complex");
                sup_parts[nsup] = s;
                nsup += 1;
                prime_made = false;
            } else {
                sup_parts[0] = s;
                nsup = 1;
            }
        } else if (p.kind == .sub) {
            _ = try ctx.next();
            if (sub != NONE) return ctx.fail(p.pos, "double subscript");
            // KaTeX parity: a missing group at EOF points at the
            // operator (`x_` → 1), not at end of input.
            if ((try ctx.peek()).kind == .end) return ctx.fail(p.pos, "expected group after '_'");
            sub = try parseGroupOrAtom(ctx, depth);
        } else if (p.kind == .char and p.cp == '\'') {
            _ = try ctx.next();
            // KaTeX parity: a prime after an explicit superscript is a
            // double superscript (`x^2'` rejects; `x'^2` merges).
            if (nsup > 0 and !prime_made) return ctx.fail(p.pos, "double superscript");
            if (nsup >= 9) return ctx.fail(p.pos, "superscript too complex");
            sup_parts[nsup] = try ctx.allocNode(.{ .atom = .{
                .class = .Ord,
                .font = .rm,
                .cp = 0x2032,
            } });
            nsup += 1;
            prime_made = true;
        } else break;
    }
    if (nsup == 0 and sub == NONE) return base;
    var sup: Idx = NONE;
    if (nsup == 1) {
        sup = sup_parts[0];
    } else if (nsup > 1) {
        const s = try ctx.allocKids(nsup);
        @memcpy(ctx.kids[s .. s + nsup], sup_parts[0..nsup]);
        sup = try ctx.allocNode(.{ .group = .{ .start = s, .len = nsup } });
    }
    const id: ?Idx = try ctx.allocNode(.{ .supsub = .{
        .base = base,
        .sup = sup,
        .sub = sub,
        .prime_sup = prime_made and nsup > 0,
    } });
    return id;
}

/// Parse one environment cell: a formula stopping at `&`, `\\`,
/// `\cr`, `\end`, or `\right`. Returns the cell group and terminator.
fn parseCell(ctx: *ParseCtx, depth: u8) Error!struct { cell: Idx, term: CellTerm } {
    var buf: [512]u16 = undefined;
    var n: usize = 0;
    while (true) {
        const t = try ctx.peek();
        switch (t.kind) {
            .end => return ctx.fail(t.pos, "unexpected end of input"),
            .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
            .amp => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .amp };
            },
            .newline => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
            },
            .ctrl => {
                if (isName(t, "end") or isName(t, "right") or isName(t, "cr")) {
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = if (isName(t, "amp")) .amp else if (isName(t, "end")) .end else if (isName(t, "right")) .right else .newline };
                }
                // `\\` is the row separator inside environments (the
                // lexer yields it as `.ctrl("\\")`, never `.newline`).
                if (tokNameEq(t.name, "\\")) {
                    _ = try ctx.next();
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
                }
                // Gap-position rule (KaTeX `getHLines` parity): a rule
                // command opening a cell belongs to the row gap, not
                // the cell, so it contributes no cell content.
                if (n == 0 and (tokNameEq(t.name, "hline") or tokNameEq(t.name, "hdashline"))) {
                    _ = try ctx.next();
                    continue;
                }
                if (isInfix(t)) {
                    _ = try ctx.next();
                    try subsetGate(true);
                    const num = try finishGroup(ctx, buf[0..n]);
                    const rest = try parseCellRest(ctx, depth);
                    const frac_id = try finishInfix(ctx, t, num, rest.cell);
                    buf[0] = frac_id;
                    n = 1;
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = rest.term };
                }
                if (isName(t, "limits") or isName(t, "nolimits")) {
                    _ = try ctx.next();
                    if (n == 0) return ctx.fail(t.pos, "'\\limits' must follow an operator");
                    const last = buf[n - 1];
                    switch (ctx.nodes[last]) {
                        .op => |*o| o.limits = if (isName(t, "limits")) .on else .off,
                        else => return ctx.fail(t.pos, "'\\limits' must follow an operator"),
                    }
                    // Scripts after `\limits` attach to the same
                    // operator (`\int\limits_a^b`, KaTeX parity).
                    if (try attachScripts(ctx, depth, last)) |id| buf[n - 1] = id;
                    continue;
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
        }
    }
}

/// Parse the remainder of a cell after an infix command (through the
/// cell terminator, which is left for the caller to consume... no —
/// consumed here and reported).
fn parseCellRest(ctx: *ParseCtx, depth: u8) Error!struct { cell: Idx, term: CellTerm } {
    var buf: [512]u16 = undefined;
    var n: usize = 0;
    while (true) {
        const t = try ctx.peek();
        switch (t.kind) {
            .end => return ctx.fail(t.pos, "unexpected end of input"),
            .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
            .amp => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .amp };
            },
            .newline => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
            },
            .ctrl => {
                if (isName(t, "end") or isName(t, "right") or isName(t, "cr")) {
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = if (isName(t, "end")) .end else if (isName(t, "right")) .right else .newline };
                }
                if (tokNameEq(t.name, "\\")) {
                    _ = try ctx.next();
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
                }
                if (n == 0 and (tokNameEq(t.name, "hline") or tokNameEq(t.name, "hdashline"))) {
                    _ = try ctx.next();
                    continue;
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
        }
    }
}

// ---------------------------------------------------------------------------
// Control-sequence dispatch
// ---------------------------------------------------------------------------

fn parseCtrl(ctx: *ParseCtx, depth: u8, t: Tok) Error!Idx {
    // Single-character names (`\%`, `\,`, `\'`, ...).
    if (t.name.len == 1) return parseSingleCharCtrl(ctx, depth, t);
    const name = t.name;

    if (tokNameEq(name, "frac")) return parseFracLike(ctx, depth, .{ .bar = true });
    // Display fractions wrap in a style node (KaTeX parity: the
    // `mstyle` sits outside the fraction — and outside `\dbinom`'s
    // parentheses — while layout inherits metrics from the ambient).
    if (tokNameEq(name, "dfrac")) return parseStyledFrac(ctx, depth, .D, .{ .bar = true });
    if (tokNameEq(name, "tfrac")) return parseStyledFrac(ctx, depth, .T, .{ .bar = true });
    if (tokNameEq(name, "cfrac")) return parseStyledFrac(ctx, depth, .D, .{ .bar = true });
    if (tokNameEq(name, "binom")) return parseFracLike(ctx, depth, .{ .bar = false, .parens = true });
    if (tokNameEq(name, "dbinom")) {
        return parseStyledFrac(ctx, depth, .D, .{ .bar = false, .parens = true });
    }
    if (tokNameEq(name, "genfrac")) {
        try subsetGate(false);
        return parseGenfrac(ctx, depth, t);
    }
    if (tokNameEq(name, "sqrt")) return parseSqrt(ctx, depth);
    if (tokNameEq(name, "left")) {
        try subsetGate(false);
        return parseLeftRight(ctx, depth, t);
    }
    if (tokNameEq(name, "middle")) {
        try subsetGate(false);
        // KaTeX parity: the delimiter parses first (a missing one
        // fails there); the fence check reports at the delimiter.
        const dpos = (try ctx.peek()).pos;
        const cp = try parseDelimSpec(ctx);
        if (ctx.in_fence == 0) return ctx.fail(dpos, "'\\middle' outside '\\left'");
        return ctx.allocNode(.{ .middle = .{ .cp = cp } });
    }
    if (tokNameEq(name, "right")) return ctx.fail(t.pos, "unexpected '\\right'");
    if (isBigName(name)) {
        try subsetGate(false);
        return parseBig(ctx, name, t);
    }
    if (symbols.lookupAccent(name)) |a| {
        try subsetGate(false);
        const nuc = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .accent = .{ .cp = a.cp, .wide = a.wide, .nucleus = nuc } });
    }
    if (parseOverName(name)) |kind| {
        try subsetGate(false);
        return parseOver(ctx, depth, t, kind);
    }
    if (tokNameEq(name, "overset") or tokNameEq(name, "underset")) {
        try subsetGate(false);
        const sup = try parseGroupOrAtom(ctx, depth);
        const base = try parseGroupOrAtom(ctx, depth);
        const kind: OverKind = if (tokNameEq(name, "overset")) .overset else .underset;
        return ctx.allocNode(.{ .over = .{ .kind = kind, .nucleus = base, .extra = sup, .under = NONE } });
    }
    if (tokNameEq(name, "not")) {
        // Combining slash as a plain atom: KaTeX overlays it onto the
        // following symbol at emit time (`\not\in` → one `mo`), which
        // the MathML renderer replicates textually.
        try subsetGate(false);
        return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 0x0338 } });
    }
    if (tokNameEq(name, "begin")) {
        try subsetGate(false);
        return parseEnv(ctx, depth, t);
    }
    if (tokNameEq(name, "end")) return ctx.fail(t.pos, "unexpected '\\end'");
    if (tokNameEq(name, "hline")) {
        if (ctx.in_env == 0) return ctx.fail(t.pos, "'\\hline' outside environment");
        return ctx.allocNode(.{ .hline = {} });
    }
    if (tokNameEq(name, "cr")) return ctx.fail(t.pos, "unexpected '\\cr'");
    if (tokNameEq(name, "text") or tokNameEq(name, "mbox")) {
        const toks = try parseBracedToks(ctx, t, true);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
    }
    if (textFontFamFor(name)) |fam| {
        const toks = try parseBracedToks(ctx, t, true);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .text = .{ .toks = toks, .fam = fam } });
    }
    if (fontFamFor(name)) |fam| {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .font = .{ .fam = fam, .body = body } });
    }
    if (tokNameEq(name, "boldsymbol")) {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .font = .{ .fam = .bold, .body = body } });
    }
    if (tokNameEq(name, "verb")) {
        try subsetGate(false);
        return parseVerb(ctx, t);
    }
    if (tokNameEq(name, "color") or tokNameEq(name, "textcolor")) {
        try subsetGate(false);
        const spec = try captureColorSpec(ctx);
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .color = .{ .body = body, .spec = spec } });
    }
    if (tokNameEq(name, "colorbox") or tokNameEq(name, "fcolorbox")) {
        try subsetGate(false);
        // `\fcolorbox{frame}{background}{body}`; `\colorbox` omits frame.
        var frame: Range = .{ .start = 0, .len = 0 };
        if (tokNameEq(name, "fcolorbox")) frame = try captureColorSpec(ctx);
        const bg = try captureColorSpec(ctx);
        const toks = try parseBracedToks(ctx, t, true);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .colorbox = .{ .body = toks, .bg = bg, .frame = frame } });
    }
    if (tokNameEq(name, "href")) {
        try subsetGate(false);
        const target = try ctx.captureArg();
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .href = .{ .body = body, .target = target } });
    }
    if (tokNameEq(name, "url")) {
        try subsetGate(false);
        const toks = try captureSpacedArg(ctx);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .tt } });
    }
    if (tokNameEq(name, "htmlClass") or tokNameEq(name, "htmlId") or
        tokNameEq(name, "htmlStyle") or tokNameEq(name, "htmlData"))
    {
        try subsetGate(false);
        _ = try ctx.captureArg();
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .htmlwrap = body });
    }
    if (tokNameEq(name, "operatorname")) {
        try subsetGate(false);
        var limits: LimitsMode = .off;
        const pk = try ctx.peek();
        if (pk.kind == .char and pk.cp == '*') {
            _ = try ctx.next();
            limits = .on;
        }
        const toks = try ctx.captureArg();
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .opname = .{ .toks = toks, .limits = limits } });
    }
    if (tokNameEq(name, "substack")) {
        try subsetGate(false);
        return parseSubstack(ctx, depth, t);
    }
    if (tokNameEq(name, "mathchoice")) {
        try subsetGate(false);
        var c: [4]Idx = undefined;
        c[0] = try parseGroupOrAtom(ctx, depth);
        c[1] = try parseGroupOrAtom(ctx, depth);
        c[2] = try parseGroupOrAtom(ctx, depth);
        c[3] = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .mathchoice = c });
    }
    if (tokNameEq(name, "smash")) {
        try subsetGate(false);
        return parseSmash(ctx, depth);
    }
    if (tokNameEq(name, "raisebox")) {
        try subsetGate(false);
        const dh = try parseDimenArg(ctx, t);
        // KaTeX parity: the body is an hbox (text mode), not math —
        // math commands inside are rejected, as in `\text`.
        const toks = try parseBracedToks(ctx, t, false);
        try checkTextToks(ctx, toks);
        const body = try ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
        return ctx.allocNode(.{ .raisebox = .{ .body = body, .dh = dh } });
    }
    if (tokNameEq(name, "rule")) {
        try subsetGate(false);
        return parseRule(ctx, depth);
    }
    if (tokNameEq(name, "boxed") or tokNameEq(name, "fbox")) {
        try subsetGate(false);
        const math = try parseGroupOrAtom(ctx, depth);
        // KaTeX desugars `\boxed{X}` to `\fbox{$\displaystyle{X}$}`;
        // the displaystyle is real (layout-affecting), so it becomes
        // a style node. (`\fbox` itself takes an hbox, which stays a
        // declared divergence: math-in-text is `katex_only`.)
        if (tokNameEq(name, "boxed")) {
            const disp = try ctx.allocNode(.{ .style = .{ .style = .D, .body = math } });
            return ctx.allocNode(.{ .boxed = disp });
        }
        return ctx.allocNode(.{ .boxed = math });
    }
    if (tokNameEq(name, "phantom") or tokNameEq(name, "hphantom") or tokNameEq(name, "vphantom")) {
        try subsetGate(false);
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .phantom = .{
            .body = body,
            // `\phantom` keeps both axes; `\hphantom` width only;
            // `\vphantom` height/depth only.
            .keep_h = !tokNameEq(name, "vphantom"),
            .keep_v = !tokNameEq(name, "hphantom"),
        } });
    }
    if (tokNameEq(name, "llap") or tokNameEq(name, "rlap") or tokNameEq(name, "clap") or
        tokNameEq(name, "mathllap") or tokNameEq(name, "mathrlap") or tokNameEq(name, "mathclap"))
    {
        try subsetGate(false);
        const math_body = tokNameEq(name, "mathllap") or tokNameEq(name, "mathrlap") or tokNameEq(name, "mathclap");
        // KaTeX parity: `\llap` and friends render contents in text
        // mode (`\mathllap{\textrm{#1}}`); only the `math*` primitives
        // take math bodies.
        const body = if (math_body)
            try parseGroupOrAtom(ctx, depth)
        else blk: {
            const toks = try parseBracedToks(ctx, t, false);
            try checkTextToks(ctx, toks);
            break :blk try ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
        };
        const kind: LapKind =
            if (tokNameEq(name, "llap") or tokNameEq(name, "mathllap")) .llap
            else if (tokNameEq(name, "rlap") or tokNameEq(name, "mathrlap")) .rlap
            else .clap;
        return ctx.allocNode(.{ .lap = .{ .body = body, .kind = kind } });
    }
    if (tokNameEq(name, "cancel") or tokNameEq(name, "bcancel")) {
        try subsetGate(false);
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .cancel = body });
    }
    if (tokNameEq(name, "quad")) return ctx.allocNode(.{ .space = 1000 });
    if (tokNameEq(name, "qquad")) return ctx.allocNode(.{ .space = 2000 });
    if (tokNameEq(name, "enskip")) return ctx.allocNode(.{ .space = 500 });
    if (tokNameEq(name, "hspace") or tokNameEq(name, "kern") or
        tokNameEq(name, "hskip") or tokNameEq(name, "mkern") or tokNameEq(name, "mskip"))
    {
        const pk = try ctx.peek();
        if (pk.kind == .char and pk.cp == '*') _ = try ctx.next();
        const v = try parseDimenArg(ctx, t);
        return ctx.allocNode(.{ .space = v });
    }
    if (tokNameEq(name, "vspace")) {
        try subsetGate(false);
        const v = try parseDimenArg(ctx, t);
        return ctx.allocNode(.{ .vspace = v });
    }

    // Symbol table (Greek, operators, relations, ...).
    if (symbols.lookup(name)) |sym| {
        if (sym.large_op or sym.func) {
            const text: []const u8 = if (sym.func) name else "";
            const cp: u21 = if (sym.func) 0 else sym.cp;
            return ctx.allocNode(.{ .op = .{
                .cp = cp,
                .large = sym.large_op,
                .func = sym.func,
                .limits = .auto,
                .lim_def = sym.limits_default,
                .text = text,
            } });
        }
        return ctx.allocNode(.{ .atom = .{ .class = sym.class, .font = .rm, .cp = sym.cp } });
    }
    if (symbols.lookupDelim(name)) |d| {
        // Bare delimiter (no `\left`): fixed-size atom in the
        // delimiter's own class (KaTeX symbol-table group).
        return ctx.allocNode(.{ .atom = .{ .class = d.cls, .font = .rm, .cp = d.cp } });
    }
    return ctx.fail(t.pos, "undefined control sequence");
}

// ---------------------------------------------------------------------------
// Single-character control sequences
// ---------------------------------------------------------------------------

fn parseSingleCharCtrl(ctx: *ParseCtx, depth: u8, t: Tok) Error!Idx {
    const c: u8 = t.name[0];
    switch (c) {
        '{' => return ctx.allocNode(.{ .atom = .{ .class = .Open, .font = .rm, .cp = '{' } }),
        '}' => return ctx.allocNode(.{ .atom = .{ .class = .Close, .font = .rm, .cp = '}' } }),
        '$' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '$' } }),
        '%' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '%' } }),
        '&' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '&' } }),
        '#' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '#' } }),
        '_' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '_' } }),
        '|' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 0x2016 } }),
        ' ' => return ctx.allocNode(.{ .space = space_interword }),
        ',' => return ctx.allocNode(.{ .space = space_thin }),
        ':' => return ctx.allocNode(.{ .space = space_med }),
        ';' => return ctx.allocNode(.{ .space = space_thick }),
        '!' => return ctx.allocNode(.{ .space = -space_thin }),
        // No `\/` arm: KaTeX has no italic-correction escape, in math
        // or text mode — it falls through to "undefined control sequence".
        '\\' => return ctx.allocNode(.{ .newline = {} }),
        else => {},
    }
    // Text accents (`\'`, `\"`, ...) in math mode build accent nodes
    // (KaTeX parity: allowed outside strict mode, with the spacing
    // accent glyph as label). `\t`, `\d`, `\b` have no math-mode
    // accent form and keep the precomposed lowering below.
    if (textAccentCp(c)) |acc| {
        const a = try parseGroupOrAtom(ctx, depth);
        if (mathTextAccentCp(c)) |spacing| {
            return ctx.allocNode(.{ .accent = .{ .cp = spacing, .wide = false, .nucleus = a } });
        }
        return applyTextAccent(ctx, t.pos, acc, a);
    }
    // Single-letter named symbols (`\S`, `\aa`, ...) live in the same
    // table as multi-letter names (KaTeX parity, full profile only).
    if (comptime active_profile == .full) {
        if (symbols.lookup(t.name)) |sym| {
            return ctx.allocNode(.{ .atom = .{ .class = sym.class, .font = .rm, .cp = sym.cp } });
        }
    }
    return ctx.fail(t.pos, "undefined control sequence");
}

/// Spacing accent label for math-mode text accents (KaTeX
/// `accent`-group symbols in text mode).
fn mathTextAccentCp(c: u8) ?u21 {
    for (symbols.all_math_text_accents) |e| if (e.c == c) return e.cp;
    return null;
}

pub fn textAccentCp(c: u8) ?u21 {
    return switch (c) {
        '\'' => 0x0301,
        '`' => 0x0300,
        '^' => 0x0302,
        '"' => 0x0308,
        '~' => 0x0303,
        '=' => 0x0304,
        '.' => 0x0307,
        'u' => 0x0306,
        'v' => 0x030C,
        'H' => 0x030B,
        't' => 0x0361,
        'c' => 0x0327,
        'd' => 0x0323,
        'b' => 0x0331,
        'r' => 0x030A,
        else => null,
    };
}

/// Apply a text accent to a single-letter argument. Common
/// Latin precompositions map to single codepoints; anything else is
/// rejected (KaTeX parity is approximate here — the sweep pins it).
fn applyTextAccent(ctx: *ParseCtx, pos: u32, acc: u21, arg: Idx) Error!Idx {
    const base: u21 = switch (ctx.nodes[arg]) {
        .atom => |a| a.cp,
        .group => |g| blk: {
            if (g.len != 1) return ctx.fail(pos, "accent supports single letters");
            break :blk switch (ctx.nodes[ctx.kids[g.start]]) {
                .atom => |a| a.cp,
                else => return ctx.fail(pos, "accent supports single letters"),
            };
        },
        else => return ctx.fail(pos, "accent supports single letters"),
    };
    if (precompose(acc, base)) |cp| {
        return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = cp } });
    }
    return ctx.fail(pos, "unsupported accent combination");
}

pub fn precompose(acc: u21, base: u21) ?u21 {
    const Key = struct { acc: u21, base: u21, cp: u21 };
    const table: []const Key = &.{
        .{ .acc = 0x0301, .base = 'a', .cp = 0x00E1 }, .{ .acc = 0x0301, .base = 'e', .cp = 0x00E9 },
        .{ .acc = 0x0301, .base = 'i', .cp = 0x00ED }, .{ .acc = 0x0301, .base = 'o', .cp = 0x00F3 },
        .{ .acc = 0x0301, .base = 'u', .cp = 0x00FA }, .{ .acc = 0x0301, .base = 'y', .cp = 0x00FD },
        .{ .acc = 0x0301, .base = 'A', .cp = 0x00C1 }, .{ .acc = 0x0301, .base = 'E', .cp = 0x00C9 },
        .{ .acc = 0x0301, .base = 'I', .cp = 0x00CD }, .{ .acc = 0x0301, .base = 'O', .cp = 0x00D3 },
        .{ .acc = 0x0301, .base = 'U', .cp = 0x00DA },
        .{ .acc = 0x0300, .base = 'a', .cp = 0x00E0 }, .{ .acc = 0x0300, .base = 'e', .cp = 0x00E8 },
        .{ .acc = 0x0300, .base = 'i', .cp = 0x00EC }, .{ .acc = 0x0300, .base = 'o', .cp = 0x00F2 },
        .{ .acc = 0x0300, .base = 'u', .cp = 0x00F9 }, .{ .acc = 0x0300, .base = 'A', .cp = 0x00C0 },
        .{ .acc = 0x0300, .base = 'E', .cp = 0x00C8 }, .{ .acc = 0x0300, .base = 'I', .cp = 0x00CC },
        .{ .acc = 0x0300, .base = 'O', .cp = 0x00D2 }, .{ .acc = 0x0300, .base = 'U', .cp = 0x00D9 },
        .{ .acc = 0x0302, .base = 'a', .cp = 0x00E2 }, .{ .acc = 0x0302, .base = 'e', .cp = 0x00EA },
        .{ .acc = 0x0302, .base = 'i', .cp = 0x00EE }, .{ .acc = 0x0302, .base = 'o', .cp = 0x00F4 },
        .{ .acc = 0x0302, .base = 'u', .cp = 0x00FB }, .{ .acc = 0x0302, .base = 'A', .cp = 0x00C2 },
        .{ .acc = 0x0302, .base = 'E', .cp = 0x00CA }, .{ .acc = 0x0302, .base = 'I', .cp = 0x00CE },
        .{ .acc = 0x0302, .base = 'O', .cp = 0x00D4 }, .{ .acc = 0x0302, .base = 'U', .cp = 0x00DB },
        .{ .acc = 0x0308, .base = 'a', .cp = 0x00E4 }, .{ .acc = 0x0308, .base = 'e', .cp = 0x00EB },
        .{ .acc = 0x0308, .base = 'i', .cp = 0x00EF }, .{ .acc = 0x0308, .base = 'o', .cp = 0x00F6 },
        .{ .acc = 0x0308, .base = 'u', .cp = 0x00FC }, .{ .acc = 0x0308, .base = 'y', .cp = 0x00FF },
        .{ .acc = 0x0308, .base = 'A', .cp = 0x00C4 }, .{ .acc = 0x0308, .base = 'E', .cp = 0x00CB },
        .{ .acc = 0x0308, .base = 'I', .cp = 0x00CF }, .{ .acc = 0x0308, .base = 'O', .cp = 0x00D6 },
        .{ .acc = 0x0308, .base = 'U', .cp = 0x00DC },
        .{ .acc = 0x0303, .base = 'a', .cp = 0x00E3 }, .{ .acc = 0x0303, .base = 'o', .cp = 0x00F5 },
        .{ .acc = 0x0303, .base = 'n', .cp = 0x00F1 }, .{ .acc = 0x0303, .base = 'A', .cp = 0x00C3 },
        .{ .acc = 0x0303, .base = 'O', .cp = 0x00D5 }, .{ .acc = 0x0303, .base = 'N', .cp = 0x00D1 },
        .{ .acc = 0x030A, .base = 'a', .cp = 0x00E5 }, .{ .acc = 0x030A, .base = 'A', .cp = 0x00C5 },
        .{ .acc = 0x0327, .base = 'c', .cp = 0x00E7 }, .{ .acc = 0x0327, .base = 'C', .cp = 0x00C7 },
        .{ .acc = 0x030C, .base = 'c', .cp = 0x010D }, .{ .acc = 0x030C, .base = 's', .cp = 0x0161 },
        .{ .acc = 0x030C, .base = 'z', .cp = 0x017E }, .{ .acc = 0x030C, .base = 'C', .cp = 0x010C },
        .{ .acc = 0x030C, .base = 'S', .cp = 0x0160 }, .{ .acc = 0x030C, .base = 'Z', .cp = 0x017D },
        .{ .acc = 0x0306, .base = 'a', .cp = 0x0103 }, .{ .acc = 0x0306, .base = 'g', .cp = 0x011F },
        .{ .acc = 0x0304, .base = 'a', .cp = 0x0101 }, .{ .acc = 0x0304, .base = 'e', .cp = 0x0113 },
        .{ .acc = 0x0304, .base = 'i', .cp = 0x012B }, .{ .acc = 0x0304, .base = 'o', .cp = 0x014D },
        .{ .acc = 0x0304, .base = 'u', .cp = 0x016B },
        .{ .acc = 0x0307, .base = 'z', .cp = 0x017C }, .{ .acc = 0x0307, .base = 'Z', .cp = 0x017B },
        .{ .acc = 0x030B, .base = 'o', .cp = 0x0151 }, .{ .acc = 0x030B, .base = 'u', .cp = 0x0171 },
        .{ .acc = 0x030B, .base = 'O', .cp = 0x0150 }, .{ .acc = 0x030B, .base = 'U', .cp = 0x0170 },
        .{ .acc = 0x0323, .base = 'a', .cp = 0x1EA0 }, .{ .acc = 0x0323, .base = 'e', .cp = 0x1EB8 },
    };
    for (table) |e| if (e.acc == acc and e.base == base) return e.cp;
    return null;
}

// ---------------------------------------------------------------------------
// Style commands, fonts, over/under
// ---------------------------------------------------------------------------

fn isStyleName(name: []const u8) bool {
    return tokNameEq(name, "displaystyle") or tokNameEq(name, "textstyle") or
        tokNameEq(name, "scriptstyle") or tokNameEq(name, "scriptscriptstyle");
}

fn styleFor(name: []const u8) Style {
    if (tokNameEq(name, "displaystyle")) return .D;
    if (tokNameEq(name, "textstyle")) return .T;
    if (tokNameEq(name, "scriptstyle")) return .S;
    return .SS;
}

fn fontFamFor(name: []const u8) ?FontFam {
    // Math-mode families take math arguments (`\mathbf{\alpha}`).
    if (tokNameEq(name, "mathrm") or tokNameEq(name, "rm")) return .rm;
    if (tokNameEq(name, "mathit") or tokNameEq(name, "it") or
        tokNameEq(name, "mathnormal")) return .mathit;
    if (tokNameEq(name, "mathbf") or tokNameEq(name, "bf")) return .bold;
    if (tokNameEq(name, "mathsf") or tokNameEq(name, "sf")) return .sans;
    if (tokNameEq(name, "mathtt") or tokNameEq(name, "tt")) return .tt;
    if (tokNameEq(name, "mathfrak")) return .frak;
    if (tokNameEq(name, "mathscr")) return .script;
    if (tokNameEq(name, "mathbb") or tokNameEq(name, "Bbb")) return .bb;
    if (tokNameEq(name, "mathcal") or tokNameEq(name, "cal")) return .cal;
    return null;
}

/// Text-mode families take text arguments (`\textbf{a+b}` is an
/// `mtext`, and `\textbf{\alpha}` is a KaTeX error). `\textsl` is
/// absent: KaTeX rejects it as undefined.
fn textFontFamFor(name: []const u8) ?FontFam {
    if (tokNameEq(name, "textrm") or tokNameEq(name, "textup") or
        tokNameEq(name, "textnormal") or tokNameEq(name, "textmd")) return .rm;
    if (tokNameEq(name, "textit")) return .mathit;
    if (tokNameEq(name, "textbf")) return .bold;
    if (tokNameEq(name, "textsf")) return .sans;
    if (tokNameEq(name, "texttt")) return .tt;
    return null;
}

fn parseOverName(name: []const u8) ?OverKind {
    if (tokNameEq(name, "overline")) return .overline;
    if (tokNameEq(name, "underline")) return .underline;
    if (tokNameEq(name, "overbrace")) return .overbrace;
    if (tokNameEq(name, "underbrace")) return .underbrace;
    if (tokNameEq(name, "overleftarrow")) return .overleft;
    if (tokNameEq(name, "overrightarrow")) return .overright;
    if (tokNameEq(name, "overleftrightarrow")) return .overboth;
    if (tokNameEq(name, "underleftarrow")) return .underleft;
    if (tokNameEq(name, "underrightarrow")) return .underright;
    if (tokNameEq(name, "underleftrightarrow")) return .underboth;
    if (tokNameEq(name, "xleftarrow")) return .xleft;
    if (tokNameEq(name, "xrightarrow")) return .xright;
    if (tokNameEq(name, "xleftrightarrow")) return .xboth;
    if (tokNameEq(name, "xhookleftarrow")) return .xhookleft;
    if (tokNameEq(name, "xhookrightarrow")) return .xhookright;
    if (tokNameEq(name, "xmapsto")) return .xmapsto;
    if (tokNameEq(name, "xtwoheadleftarrow")) return .xtwoheadleft;
    if (tokNameEq(name, "xtwoheadrightarrow")) return .xtwoheadright;
    return null;
}

fn parseOver(ctx: *ParseCtx, depth: u8, t: Tok, kind: OverKind) Error!Idx {
    switch (kind) {
        .xleft, .xright, .xboth, .xhookleft, .xhookright, .xmapsto, .xtwoheadleft, .xtwoheadright => {
            var under: Idx = NONE;
            const pk = try ctx.peek();
            if (pk.kind == .char and pk.cp == '[') {
                _ = try ctx.next();
                const r = try parseFormula(ctx, depth, .bracket);
                under = r;
            }
            const above = try parseGroupOrAtom(ctx, depth);
            return ctx.allocNode(.{ .over = .{
                .kind = kind,
                .nucleus = NONE,
                .extra = above,
                .under = under,
            } });
        },
        else => {
            const nuc = try parseGroupOrAtom(ctx, depth);
            return ctx.allocNode(.{ .over = .{
                .kind = kind,
                .nucleus = nuc,
                .extra = NONE,
                .under = NONE,
            } });
        },
    }
    _ = t;
}

// ---------------------------------------------------------------------------
// Fractions, roots, fences
// ---------------------------------------------------------------------------

fn parseFracLike(ctx: *ParseCtx, depth: u8, kind: FracKind) Error!Idx {
    try subsetGate(true);
    const num = try parseGroupOrAtom(ctx, depth);
    const den = try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .frac = .{ .num = num, .den = den, .kind = kind } });
}

fn parseSqrt(ctx: *ParseCtx, depth: u8) Error!Idx {
    try subsetGate(true);
    var index: Idx = NONE;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        index = try parseFormula(ctx, depth, .bracket);
    }
    const rad = try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .sqrt = .{ .radicand = rad, .index = index } });
}

/// Read one delimiter specification: a bare char, `\|`, or a named
/// delimiter command. `.` means "no fence" (u21 0).
fn parseDelimSpec(ctx: *ParseCtx) Error!u21 {
    const t = try ctx.next();
    switch (t.kind) {
        .char => {
            if (t.cp == '.') return 0;
            return switch (t.cp) {
                '(', ')', '[', ']', '{', '}', '|', '/', '<', '>' => t.cp,
                else => ctx.fail(t.pos, "expected delimiter"),
            };
        },
        .ctrl => {
            if (t.name.len == 1) {
                const c = t.name[0];
                switch (c) {
                    '|', '/' => return c,
                    '\\' => return 0x005C,
                    '{' => return '{',
                    '}' => return '}',
                    else => return ctx.fail(t.pos, "expected delimiter"),
                }
            }
            if (symbols.lookupDelim(t.name)) |d| return d.cp;
            return ctx.fail(t.pos, "expected delimiter");
        },
        else => return ctx.fail(t.pos, "expected delimiter"),
    }
}

fn parseLeftRight(ctx: *ParseCtx, depth: u8, t: Tok) Error!Idx {
    const left = try parseDelimSpec(ctx);
    ctx.in_fence += 1;
    const body = try parseFormula(ctx, depth, .leftright);
    ctx.in_fence -= 1;
    // parseFormula stopped before `\right` (unconsumed).
    const r = try ctx.next();
    if (r.kind != .ctrl or !tokNameEq(r.name, "right")) return ctx.fail(r.pos, "expected '\\right'");
    _ = t;
    const right = try parseDelimSpec(ctx);
    return ctx.allocNode(.{ .delim = .{ .left = left, .right = right, .body = body } });
}

fn isBigName(name: []const u8) bool {
    const prefixes = [_][]const u8{ "bigl", "bigm", "bigr", "Bigl", "Bigm", "Bigr", "biggl", "biggm", "biggr", "Biggl", "Biggm", "Biggr", "big", "Big", "bigg", "Bigg" };
    for (prefixes) |p| if (tokNameEq(name, p)) return true;
    return false;
}

fn parseBig(ctx: *ParseCtx, name: []const u8, t: Tok) Error!Idx {
    // Level from the prefix (`big`/`Big`/`bigg`/`Bigg`), class from
    // the `l`/`m`/`r` suffix (absent = Ord).
    var level: u2 = 0;
    if (name[0] == 'B') level = 1;
    var rest = name[3..];
    if (name[0] == 'b' and rest.len > 0 and rest[0] == 'g') {
        level = 2;
        rest = rest[1..];
    }
    if (name[0] == 'B' and rest.len > 0 and (rest[0] == 'g' or (rest.len > 1 and rest[1] == 'g'))) {
        level = 3;
        rest = rest[1..];
        if (rest.len > 0 and rest[0] == 'g') rest = rest[0..0]; // "Bigg"
    }
    var class: symbols.AtomClass = .Ord;
    if (rest.len == 1) class = suffixClass(rest[0]) else if (rest.len != 0) {
        return ctx.fail(t.pos, "undefined control sequence");
    }
    // Delimiter spec (`.` is not allowed here — KaTeX rejects `\big.`).
    const dt = try ctx.next();
    const cp: u21 = switch (dt.kind) {
        .char => switch (dt.cp) {
            '(', ')', '[', ']', '{', '}', '|', '/', '<', '>' => dt.cp,
            else => return ctx.fail(dt.pos, "expected delimiter"),
        },
        .ctrl => blk: {
            if (dt.name.len == 1) {
                const c = dt.name[0];
                break :blk switch (c) {
                    '|', '/' => @as(u21, c),
                    '\\' => @as(u21, 0x005C),
                    '{' => @as(u21, '{'),
                    '}' => @as(u21, '}'),
                    else => return ctx.fail(dt.pos, "expected delimiter"),
                };
            }
            break :blk (symbols.lookupDelim(dt.name) orelse return ctx.fail(dt.pos, "expected delimiter")).cp;
        },
        else => return ctx.fail(dt.pos, "expected delimiter"),
    };
    return ctx.allocNode(.{ .big = .{ .cp = cp, .level = level, .class = class } });
}

fn suffixClass(c: u8) symbols.AtomClass {
    return switch (c) {
        'l' => .Open,
        'm' => .Rel,
        'r' => .Close,
        else => .Ord,
    };
}

// ---------------------------------------------------------------------------
// Dimensions
// ---------------------------------------------------------------------------

/// Parse a dimension argument (braced tokens or bare `2.5ex`).
/// Result in thousandths of an em, clamped to i16.
fn parseDimenArg(ctx: *ParseCtx, cmd: Tok) Error!i16 {
    const pk = try ctx.peek();
    if (pk.kind == .lbrace) {
        _ = try ctx.next();
        const r = try ctx.captureToBrace(pk.pos);
        return dimenFromToks(ctx, r, cmd.pos);
    }
    // Bare dimension: number chars, then at most two unit letters.
    // KaTeX parity: the unit is exactly `[a-z]{2}`; anything after it
    // belongs to the following input (`\kern2pt c` kerns 2pt, then `c`).
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    var nletters: usize = 0;
    while (n < buf.len) {
        const q = try ctx.peek();
        if (q.kind != .char) break;
        const c = q.cp;
        if (c > 0x7F) break;
        const is_letter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
        if (is_letter) {
            if (nletters >= 2) break;
            nletters += 1;
        } else {
            const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-';
            if (!ok) break;
        }
        _ = try ctx.next();
        buf[n] = @intCast(c);
        n += 1;
    }
    if (n == 0) return ctx.fail(cmd.pos, "expected dimension");
    return dimenFromBytes(buf[0..n], cmd.pos, ctx);
}

fn dimenFromToks(ctx: *ParseCtx, r: Range, pos: u32) Error!i16 {
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    var i: u16 = 0;
    while (i < r.len) : (i += 1) {
        const tk = ctx.toks[r.start + i];
        if (tk.kind != .char or tk.cp > 0x7F) return ctx.fail(tk.pos, "expected dimension");
        const c: u8 = @intCast(tk.cp);
        const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-' or
            (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
        if (!ok) return ctx.fail(tk.pos, "expected dimension");
        if (n >= buf.len) return ctx.fail(tk.pos, "dimension too long");
        buf[n] = c;
        n += 1;
    }
    return dimenFromBytes(buf[0..n], pos, ctx);
}

fn dimenFromBytes(b: []const u8, pos: u32, ctx: *ParseCtx) Error!i16 {
    var i: usize = 0;
    var neg = false;
    if (i < b.len and (b[i] == '+' or b[i] == '-')) {
        neg = b[i] == '-';
        i += 1;
    }
    var int: i64 = 0;
    var frac: i64 = 0;
    var fdiv: i64 = 1;
    var digits = false;
    while (i < b.len and b[i] >= '0' and b[i] <= '9') : (i += 1) {
        int = int * 10 + (b[i] - '0');
        digits = true;
    }
    if (i < b.len and b[i] == '.') {
        i += 1;
        while (i < b.len and b[i] >= '0' and b[i] <= '9' and fdiv < 1000000) : (i += 1) {
            frac = frac * 10 + (b[i] - '0');
            fdiv *= 10;
            digits = true;
        }
        while (i < b.len and b[i] >= '0' and b[i] <= '9') : (i += 1) {}
    }
    if (!digits) return ctx.fail(pos, "expected dimension");
    // Unit: exactly two lowercase letters (KaTeX `[a-z]{2}` — `PT` is
    // rejected). Anything after them belongs to the following input
    // and is ignored here.
    if (i + 2 > b.len) return ctx.fail(pos, "expected dimension");
    const unit = b[i .. i + 2];
    // Thousandths of an em per unit (1em = 10pt at the reference size).
    const per_em: i64 = if (std.mem.eql(u8, unit, "em"))
        1000
    else if (std.mem.eql(u8, unit, "ex"))
        500 // ≈ x-height; documented approximation
    else if (std.mem.eql(u8, unit, "mu"))
        1000
    else if (std.mem.eql(u8, unit, "pt"))
        100
    else if (std.mem.eql(u8, unit, "pc"))
        1200
    else if (std.mem.eql(u8, unit, "in"))
        7227
    else if (std.mem.eql(u8, unit, "bp"))
        100
    else if (std.mem.eql(u8, unit, "cm"))
        2845
    else if (std.mem.eql(u8, unit, "mm"))
        285
    else if (std.mem.eql(u8, unit, "dd"))
        107
    else if (std.mem.eql(u8, unit, "cc"))
        1288
    else if (std.mem.eql(u8, unit, "sp"))
        0
    else
        return ctx.fail(pos, "unknown unit");
    var v: i64 = int * per_em + @divTrunc(frac * per_em, fdiv);
    if (std.mem.eql(u8, unit, "mu")) v = @divTrunc(v, 18);
    if (neg) v = -v;
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    return @intCast(v);
}

// ---------------------------------------------------------------------------
// `\text` bodies, `\genfrac`, `\smash`, `\rule`, `\substack`
// ---------------------------------------------------------------------------

/// Braced token capture with `\text`-style validation of the braces.
/// Spaces survive the capture (text mode); the flag is restored after.
fn parseBracedToks(ctx: *ParseCtx, cmd: Tok, comptime need_brace: bool) Error!Range {
    const pk = try ctx.peek();
    if (pk.kind == .lbrace) {
        _ = try ctx.next();
        const prev = ctx.keep_spaces;
        ctx.keep_spaces = true;
        const r = ctx.captureToBrace(pk.pos) catch |e| {
            ctx.keep_spaces = prev;
            return e;
        };
        ctx.keep_spaces = prev;
        return r;
    }
    if (need_brace) return ctx.fail(cmd.pos, "expected '{'");
    return ctx.captureArg();
}

/// Token capture with spaces preserved (for `\url`).
fn captureSpacedArg(ctx: *ParseCtx) Error!Range {
    const prev = ctx.keep_spaces;
    ctx.keep_spaces = true;
    const r = ctx.captureArg() catch |e| {
        ctx.keep_spaces = prev;
        return e;
    };
    ctx.keep_spaces = prev;
    return r;
}

/// Color-spec capture (`\color`, `\textcolor`, boxes): like
/// `captureToBrace` but fully literal — no `#1` parameter processing
/// — so hex specs (`#f00`) survive. A lone no-argument user macro
/// (`\newcommand{\c}{red}\color{\c}{x}`) resolves to its body.
fn captureColorSpec(ctx: *ParseCtx) Error!Range {
    const t = try ctx.peek();
    if (t.kind != .lbrace) {
        const r = try ctx.captureArg();
        try validateColorSpec(ctx, r, ctx.toks[r.start].pos);
        return r;
    }
    _ = try ctx.next();
    const prev = ctx.keep_spaces;
    ctx.keep_spaces = true;
    var r = captureLiteral(ctx) catch |e| {
        ctx.keep_spaces = prev;
        return e;
    };
    ctx.keep_spaces = prev;
    if (r.len == 1) {
        const tk = ctx.toks[r.start];
        if (tk.kind == .ctrl) {
            if (ctx.findDef(tk.name)) |d| {
                if (!d.is_alias and d.nargs == 0) r = d.body;
            }
        }
    }
    try validateColorSpec(ctx, r, t.pos);
    return r;
}

fn isHexDigit(cp: u21) bool {
    return (cp >= '0' and cp <= '9') or
        (cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F');
}

fn isColorWord(cp: u21) bool {
    return (cp >= '0' and cp <= '9') or
        (cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z');
}

/// KaTeX color rule (probed): a bare word passes through unchecked,
/// `#` needs 3 or 6 hex digits, and everything else — empty specs,
/// spaces, `rgb(...)`, control sequences — is "Invalid color".
/// Failure carries the spec brace position (KaTeX parity).
fn validateColorSpec(ctx: *ParseCtx, r: Range, brace_pos: u32) Error!void {
    const toks = ctx.toks[r.start .. r.start + r.len];
    if (toks.len == 0) return ctx.fail(brace_pos, "invalid color");
    if (toks[0].kind == .char and toks[0].cp == '#') {
        const n = toks.len - 1;
        if (n != 3 and n != 6) return ctx.fail(brace_pos, "invalid color");
        for (toks[1..]) |tk| {
            if (tk.kind != .char or !isHexDigit(tk.cp))
                return ctx.fail(brace_pos, "invalid color");
        }
        return;
    }
    for (toks) |tk| {
        if (tk.kind != .char or !isColorWord(tk.cp))
            return ctx.fail(brace_pos, "invalid color");
    }
}

/// Capture tokens through the matching close brace with no
/// interpretation whatsoever. The opening `{` is already consumed.
fn captureLiteral(self: *ParseCtx) Error!Range {
    const start = try self.allocToks(0);
    var depth: u16 = 0;
    var count: u16 = 0;
    while (true) {
        const t = try self.next();
        switch (t.kind) {
            .end => return self.fail(t.pos, "expected '}' before end of input"),
            .lbrace => {
                depth += 1;
                _ = try self.allocToks(1);
                self.toks[start + count] = t;
                count += 1;
            },
            .rbrace => {
                if (depth == 0) return .{ .start = start, .len = count };
                depth -= 1;
                _ = try self.allocToks(1);
                self.toks[start + count] = t;
                count += 1;
            },
            else => {
                _ = try self.allocToks(1);
                self.toks[start + count] = t;
                count += 1;
            },
        }
    }
}

/// `\verb` / `\verb*`: the delimiter is the literal byte after the
/// command (an optional `*` toggles visible spaces). Content is raw —
/// no comments, no escapes — up to the next delimiter, and newlines
/// end the scan (KaTeX parity). Materialized as `.char` tokens in a
/// monospace text node, so downstream emitters need no new paths.
fn parseVerb(ctx: *ParseCtx, t: Tok) Error!Idx {
    // The delimiter scan reads raw source bytes at the lexer's cursor,
    // which is only meaningful for a freshly lexed token: expanded
    // tokens borrow definition bytes, and re-parsed ranges (markers)
    // leave the cursor after the whole construct.
    const tok_end = t.pos + 1 + @as(u32, @intCast(t.name.len));
    if (t.synth or ctx.npb > 0 or ctx.spos != tok_end)
        return ctx.fail(t.pos, "'\\verb' inside macro expansion is not supported");
    var p: usize = ctx.spos;
    var star = false;
    if (p < ctx.src.len and ctx.src[p] == '*') {
        star = true;
        p += 1;
    }
    if (p >= ctx.src.len)
        return ctx.fail(t.pos, "'\\verb' ended by end of line instead of matching delimiter");
    const dl = utf8Len(ctx.src[p]);
    if (dl == 0 or p + dl > ctx.src.len) {
        ctx.err_pos = @intCast(p);
        ctx.err_msg = "invalid utf-8";
        return error.Invalid;
    }
    const delim = decode(ctx.src[p .. p + dl]);
    p += dl;
    const start = try ctx.allocToks(0);
    var count: u16 = 0;
    while (true) {
        if (p >= ctx.src.len)
            return ctx.fail(t.pos, "'\\verb' ended by end of line instead of matching delimiter");
        const b = ctx.src[p];
        if (b == '\n')
            return ctx.fail(t.pos, "'\\verb' ended by end of line instead of matching delimiter");
        const l = utf8Len(b);
        if (l == 0 or p + l > ctx.src.len) {
            ctx.err_pos = @intCast(p);
            ctx.err_msg = "invalid utf-8";
            return error.Invalid;
        }
        const cp = decode(ctx.src[p .. p + l]);
        if (cp == delim) {
            p += l;
            break;
        }
        _ = try ctx.allocToks(1);
        ctx.toks[start + count] = .{
            .kind = .char,
            .cp = if (star and cp == ' ') 0x2423 else cp,
            .pos = @intCast(p),
        };
        count += 1;
        p += l;
    }
    ctx.spos = @intCast(p);
    return ctx.allocNode(.{ .text = .{
        .toks = .{ .start = start, .len = count },
        .fam = .tt,
    } });
}

fn checkTextToks(ctx: *ParseCtx, r: Range) Error!void {
    var i: u16 = 0;
    while (i < r.len) : (i += 1) {
        const tk = ctx.toks[r.start + i];
        switch (tk.kind) {
            .char, .lbrace, .rbrace, .newline => {
                // KaTeX re-enters math mode on `$` inside `\text`;
                // without math-in-text support the byte is rejected.
                if (tk.kind == .char and tk.cp == '$')
                    return ctx.fail(tk.pos, "can't use '$' in text mode");
            },
            .ctrl => {
                // Single-character escapes (`\%`, `\_`, ...), spacing,
                // accents, and (full profile) text-mode commands (`\i`,
                // `\textdollar`, ...) are allowed in text; math commands
                // are not.
                const is_text_cmd = if (comptime active_profile == .full)
                    symbols.lookupText(tk.name) != null
                else
                    false;
                if (tk.name.len != 1) {
                    if (!is_text_cmd)
                        return ctx.fail(tk.pos, "can't use math command in text mode");
                    continue;
                }
                const c = tk.name[0];
                switch (c) {
                    '{', '}', '%', '&', '#', '_', '$', ' ', ',', ':', ';', '!', '~', '|', '\'', '`', '^', '"', '=', '.', 'u', 'v', 'H', 't', 'c', 'd', 'b', 'r' => {},
                    else => if (!is_text_cmd)
                        return ctx.fail(tk.pos, "can't use math command in text mode"),
                }
            },
            .sup, .sub => return ctx.fail(tk.pos, "can't use '^'/'_' in text mode"),
            .amp => return ctx.fail(tk.pos, "can't use '&' in text mode"),
            .param => return ctx.fail(tk.pos, "unexpected '#'"),
            .marker, .end => return ctx.fail(tk.pos, "unexpected end of text"),
        }
    }
}

fn parseGenfrac(ctx: *ParseCtx, depth: u8, cmd: Tok) Error!Idx {
    const l = try ctx.captureArg();
    const r = try ctx.captureArg();
    const thick_t = try ctx.captureArg();
    const style_t = try ctx.captureArg();
    const num_t = try ctx.captureArg();
    const den_t = try ctx.captureArg();
    const left = try singleDelimArg(ctx, l, cmd.pos);
    const right = try singleDelimArg(ctx, r, cmd.pos);
    var thick: i32 = 0;
    if (thick_t.len > 0) thick = try dimenFromToks(ctx, thick_t, cmd.pos);
    var fstyle: ?Style = null;
    if (style_t.len > 0) {
        if (style_t.len != 1) return ctx.fail(cmd.pos, "expected style number");
        const d = ctx.toks[style_t.start];
        if (d.kind != .char) return ctx.fail(cmd.pos, "expected style number");
        fstyle = switch (d.cp) {
            '0' => .D,
            '1' => .T,
            '2' => .S,
            '3' => .SS,
            else => return ctx.fail(cmd.pos, "expected style number"),
        };
    }
    const num = try parseTokenRange(ctx, depth, num_t);
    const den = try parseTokenRange(ctx, depth, den_t);
    var body = try ctx.allocNode(.{ .frac = .{
        .num = num,
        .den = den,
        .kind = .{ .bar = true, .parens = false, .thick = thick },
    } });
    if (left != 0 or right != 0) {
        body = try ctx.allocNode(.{ .delim = .{ .left = left, .right = right, .body = body } });
    }
    // The style `mstyle` sits outside delimiters (KaTeX parity).
    if (fstyle) |st| {
        body = try ctx.allocNode(.{ .style = .{ .style = st, .body = body } });
    }
    return body;
}

/// Display fraction: a style node outside the fraction (the `mstyle`
/// sits outside `\dbinom` parentheses too; layout inherits metrics).
fn parseStyledFrac(ctx: *ParseCtx, depth: u8, style: Style, kind: FracKind) Error!Idx {
    const f = try parseFracLike(ctx, depth, kind);
    return ctx.allocNode(.{ .style = .{ .style = style, .body = f } });
}

fn singleDelimArg(ctx: *ParseCtx, r: Range, pos: u32) Error!u21 {
    if (r.len == 0) return 0;
    if (r.len != 1) return ctx.fail(pos, "expected delimiter");
    const tk = ctx.toks[r.start];
    switch (tk.kind) {
        .char => {
            if (tk.cp == '.') return 0;
            return switch (tk.cp) {
                '(', ')', '[', ']', '{', '}', '|', '/', '<', '>' => tk.cp,
                else => ctx.fail(tk.pos, "expected delimiter"),
            };
        },
        .ctrl => {
            if (tk.name.len == 1) {
                const c = tk.name[0];
                switch (c) {
                    '|', '/' => return c,
                    '\\' => return 0x005C,
                    '{' => return '{',
                    '}' => return '}',
                    else => return ctx.fail(tk.pos, "expected delimiter"),
                }
            }
            if (symbols.lookupDelim(tk.name)) |d| return d.cp;
            return ctx.fail(tk.pos, "expected delimiter");
        },
        else => return ctx.fail(tk.pos, "expected delimiter"),
    }
}

/// Parse a captured token range as a formula (used by `\genfrac`).
fn parseTokenRange(ctx: *ParseCtx, depth: u8, r: Range) Error!Idx {
    try ctx.push(.{ .kind = .marker });
    var i = r.len;
    while (i > 0) {
        i -= 1;
        try ctx.push(ctx.toks[r.start + i]);
    }
    return parseFormula(ctx, depth, .top);
}

fn parseSmash(ctx: *ParseCtx, depth: u8) Error!Idx {
    // Default: smash both. `[t]` smashes the top only, `[b]` the depth
    // only, `[tb]` both explicitly. An empty or invalid option smashes
    // nothing (KaTeX parity: it breaks on the first invalid letter but
    // still accepts the command).
    var keep_t = false;
    var keep_b = false;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        var has_t = false;
        var has_b = false;
        var any = false;
        var valid = true;
        while (true) {
            const o = try ctx.next();
            if (o.kind == .char and o.cp == ']') break;
            if (o.kind == .end) return ctx.fail(pk.pos, "expected ']'");
            if (valid and o.kind == .char and (o.cp == 't' or o.cp == 'b')) {
                any = true;
                if (o.cp == 't') has_t = true else has_b = true;
            } else {
                valid = false;
            }
        }
        if (!valid or !any) {
            keep_t = true;
            keep_b = true;
        } else {
            keep_t = has_b and !has_t;
            keep_b = has_t and !has_b;
        }
    }
    const body = try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .smash = .{ .body = body, .keep_t = keep_t, .keep_b = keep_b } });
}

test "bare kern stops at the two-letter unit" {
    // KaTeX parity (sweep `hspace` case): `\kern2pt c` kerns 2pt and
    // leaves `c` for the formula.
    var ctx = ParseCtx.init("a\\kern2pt c");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 3), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "smash option leniency matches KaTeX" {
    // `[t]` smashes the top only; empty/invalid options smash nothing
    // but still parse.
    var c1 = ParseCtx.init("\\smash[t]{x}");
    const r1 = try parse(&c1, false);
    switch (c1.nodes[r1]) {
        .group => |g| switch (c1.nodes[c1.kids[g.start]]) {
            .smash => |s| {
                try std.testing.expect(!s.keep_t);
                try std.testing.expect(s.keep_b);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    var c2 = ParseCtx.init("\\smash[x]{y}");
    const r2 = try parse(&c2, false);
    switch (c2.nodes[r2]) {
        .group => |g| switch (c2.nodes[c2.kids[g.start]]) {
            .smash => |s| {
                try std.testing.expect(s.keep_t);
                try std.testing.expect(s.keep_b);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
}

fn parseRule(ctx: *ParseCtx, depth: u8) Error!Idx {
    var dep: i16 = 0;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        const r = try parseFormula(ctx, depth, .bracket);
        // The bracket frame yields a group; interpret a bare dimension
        // from its single atom when possible.
        dep = try ruleDimenFromGroup(ctx, r, pk.pos);
    }
    const w = try parseDimenArg(ctx, pk);
    const h = try parseDimenArg(ctx, pk);
    return ctx.allocNode(.{ .rule = .{ .w = w, .h = h, .dep = dep } });
}

fn ruleDimenFromGroup(ctx: *ParseCtx, g: Idx, pos: u32) Error!i16 {
    // Accept plain dimensions (`1pt`) or empty (= 0).
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    const kids: []const u16 = switch (ctx.nodes[g]) {
        .group => |gr| ctx.kids[gr.start .. gr.start + gr.len],
        else => return ctx.fail(pos, "expected dimension"),
    };
    for (kids) |id| {
        const a: u21 = switch (ctx.nodes[id]) {
            .atom => |at| at.cp,
            .space => continue,
            else => return ctx.fail(pos, "expected dimension"),
        };
        if (a > 0x7F) return ctx.fail(pos, "expected dimension");
        const c: u8 = @intCast(a);
        const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-' or
            (c >= 'a' and c <= 'z');
        if (!ok) return ctx.fail(pos, "expected dimension");
        if (n >= buf.len) return ctx.fail(pos, "dimension too long");
        buf[n] = c;
        n += 1;
    }
    if (n == 0) return 0;
    return dimenFromBytes(buf[0..n], pos, ctx);
}

/// `\substack{a \\ b \\ ...}`: centered rows, no `\begin`.
fn parseSubstack(ctx: *ParseCtx, depth: u8, cmd: Tok) Error!Idx {
    const pk = try ctx.peek();
    if (pk.kind != .lbrace) return ctx.fail(cmd.pos, "expected '{'");
    _ = try ctx.next();
    const rows_start = ctx.nrows;
    var rowbuf: [64]u16 = undefined;
    var nrow: usize = 0;
    var finished = false;
    while (!finished) {
        var buf: [512]u16 = undefined;
        var n: usize = 0;
        while (true) {
            const t = try ctx.peek();
            switch (t.kind) {
                .end => return ctx.fail(t.pos, "unexpected end of input"),
                .rbrace => {
                    _ = try ctx.next();
                    finished = true;
                    break;
                },
                .newline => {
                    _ = try ctx.next();
                    break;
                },
                .amp => return ctx.fail(t.pos, "unexpected '&'"),
                else => {
                    if (t.kind == .ctrl and isName(t, "cr")) {
                        _ = try ctx.next();
                        break;
                    }
                    // `\\` is the row separator (lexed as `.ctrl("\\")`).
                    if (t.kind == .ctrl and tokNameEq(t.name, "\\")) {
                        _ = try ctx.next();
                        break;
                    }
                    const maybe = try parseAtom(ctx, depth);
                    if (maybe) |id| {
                        if (n >= 512) return error.NoSpace;
                        buf[n] = id;
                        n += 1;
                    }
                },
            }
        }
        const cell = try finishGroup(ctx, buf[0..n]);
        const ks = try ctx.allocKids(1);
        ctx.kids[ks] = cell;
        if (nrow >= 64) return error.NoSpace;
        rowbuf[nrow] = try ctx.allocRow(.{ .start = ks, .len = 1 });
        nrow += 1;
    }
    return ctx.allocNode(.{ .substack = .{
        .start = rows_start,
        .len = @intCast(nrow),
    } });
}

// ---------------------------------------------------------------------------
// Macro definitions
// ---------------------------------------------------------------------------

/// `\newcommand{\name}[n]{body}` and siblings.
fn parseNewCommand(ctx: *ParseCtx, cmd: Tok, renew: bool, provide: bool) Error!void {
    const nt = try ctx.next();
    var name: []const u8 = "";
    if (nt.kind == .lbrace) {
        const inner = try ctx.next();
        if (inner.kind != .ctrl or inner.name.len == 0) return ctx.fail(inner.pos, "expected control sequence");
        name = inner.name;
        const cl = try ctx.next();
        if (cl.kind != .rbrace) return ctx.fail(cl.pos, "expected '}'");
    } else if (nt.kind == .ctrl and nt.name.len > 0) {
        name = nt.name;
    } else {
        return ctx.fail(nt.pos, "expected control sequence");
    }
    var nargs: u3 = 0;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        const d = try ctx.next();
        if (d.kind != .char or d.cp < '0' or d.cp > '9') return ctx.fail(d.pos, "expected argument count");
        nargs = @intCast(d.cp - '0');
        const cl = try ctx.next();
        if (cl.kind != .char or cl.cp != ']') return ctx.fail(cl.pos, "expected ']'");
    }
    const body = try ctx.captureArg();
    // Validate parameter numbers at definition time.
    var i: u16 = 0;
    while (i < body.len) : (i += 1) {
        const bt = ctx.toks[body.start + i];
        if (bt.kind == .param and bt.arg >= nargs) {
            return ctx.fail(bt.pos, "macro parameter out of range");
        }
    }
    const defined = ctx.findDef(name) != null;
    const builtin = isBuiltin(name);
    if (provide) {
        if (defined or builtin) return;
    } else if (renew) {
        if (!defined and !builtin) return ctx.fail(cmd.pos, "not defined; use '\\newcommand'");
    } else {
        if (defined or builtin) return ctx.fail(cmd.pos, "already defined; use '\\renewcommand'");
    }
    if (defined) {
        const d = ctx.findDef(name).?;
        d.nargs = nargs;
        d.body = body;
        d.is_alias = false;
        return;
    }
    if (ctx.ndefs >= max_defs) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "too many macros";
        return error.ExpansionLimit;
    }
    ctx.defs[ctx.ndefs] = .{ .name = name, .nargs = nargs, .body = body };
    ctx.ndefs += 1;
}

/// `\def\name#1#2{body}`.
fn parseDef(ctx: *ParseCtx, cmd: Tok) Error!void {
    const nt = try ctx.next();
    if (nt.kind != .ctrl or nt.name.len == 0) return ctx.fail(nt.pos, "expected control sequence");
    var nargs: u3 = 0;
    while (true) {
        const q = try ctx.peek();
        if (q.kind == .char and q.cp == '#') {
            _ = try ctx.next();
            const d = try ctx.next();
            if (d.kind != .char or d.cp != '1' + @as(u21, nargs)) return ctx.fail(d.pos, "parameters must be sequential");
            nargs += 1;
            if (nargs > 9) return ctx.fail(d.pos, "too many parameters");
        } else break;
    }
    const body = try ctx.captureArg();
    if (ctx.findDef(nt.name)) |d| {
        d.nargs = nargs;
        d.body = body;
        d.is_alias = false;
        return;
    }
    if (ctx.ndefs >= max_defs) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "too many macros";
        return error.ExpansionLimit;
    }
    ctx.defs[ctx.ndefs] = .{ .name = nt.name, .nargs = nargs, .body = body };
    ctx.ndefs += 1;
}

/// `\let\new=\old` / `\let\new\old`.
fn parseLet(ctx: *ParseCtx, cmd: Tok) Error!void {
    const nt = try ctx.next();
    if (nt.kind != .ctrl or nt.name.len == 0) return ctx.fail(nt.pos, "expected control sequence");
    var tgt = try ctx.next();
    if (tgt.kind == .char and tgt.cp == '=') tgt = try ctx.next();
    if (tgt.kind == .end or tgt.kind == .param) return ctx.fail(tgt.pos, "expected token after '\\let'");
    if (ctx.findDef(nt.name)) |d| {
        d.nargs = 0;
        d.is_alias = true;
        d.alias_tok = tgt;
        return;
    }
    if (ctx.ndefs >= max_defs) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "too many macros";
        return error.ExpansionLimit;
    }
    ctx.defs[ctx.ndefs] = .{ .name = nt.name, .nargs = 0, .body = .{ .start = 0, .len = 0 }, .is_alias = true, .alias_tok = tgt };
    ctx.ndefs += 1;
}

/// Names the engine implements natively (for `\newcommand` guards).
fn isBuiltin(name: []const u8) bool {
    if (symbols.lookup(name) != null) return true;
    if (symbols.lookupDelim(name) != null) return true;
    if (symbols.lookupAccent(name) != null) return true;
    if (isStyleName(name)) return true;
    if (fontFamFor(name) != null) return true;
    if (parseOverName(name) != null) return true;
    if (isBigName(name)) return true;
    const prims: []const []const u8 = &.{
        "frac", "dfrac", "tfrac", "cfrac", "binom", "dbinom", "genfrac",
        "sqrt", "left", "right", "middle", "begin", "end", "hline", "cr",
        "text", "mbox", "boldsymbol", "color", "href", "url", "htmlClass",
        "htmlId", "htmlStyle", "htmlData", "operatorname", "substack",
        "mathchoice", "smash", "raisebox", "rule", "boxed", "fbox",
        "phantom", "hphantom", "vphantom", "llap", "rlap", "clap",
        "cancel", "bcancel", "quad", "qquad", "enskip", "hspace", "vspace",
        "kern", "mkern", "mskip", "hskip", "newcommand", "renewcommand",
        "providecommand", "def", "gdef", "let", "over", "atop", "choose", "brace",
        "brack", "limits", "nolimits", "not", "overset", "underset",
    };
    for (prims) |p| if (tokNameEq(p, name)) return true;
    const envs: []const []const u8 = &.{
        "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix",
        "smallmatrix", "array", "aligned", "alignedat", "cases", "gathered",
    };
    for (envs) |e| if (tokNameEq(e, name)) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Environments
// ---------------------------------------------------------------------------

fn parseEnv(ctx: *ParseCtx, depth: u8, cmd: Tok) Error!Idx {
    // Environment name: `{matrix}` — letter chars.
    const lb = try ctx.next();
    if (lb.kind != .lbrace) return ctx.fail(lb.pos, "expected '{' after '\\begin'");
    var nbuf: [32]u8 = undefined;
    var nn: usize = 0;
    while (true) {
        const q = try ctx.next();
        if (q.kind == .rbrace) break;
        if (q.kind != .char or q.cp > 0x7F) return ctx.fail(q.pos, "expected environment name");
        const c: u8 = @intCast(q.cp);
        if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) return ctx.fail(q.pos, "expected environment name");
        if (nn >= nbuf.len) return ctx.fail(q.pos, "environment name too long");
        nbuf[nn] = c;
        nn += 1;
    }
    const kind: EnvKind = if (tokNameEq(nbuf[0..nn], "matrix"))
        .matrix
    else if (tokNameEq(nbuf[0..nn], "pmatrix"))
        .pmatrix
    else if (tokNameEq(nbuf[0..nn], "bmatrix"))
        .bmatrix
    else if (tokNameEq(nbuf[0..nn], "Bmatrix"))
        .Bmatrix
    else if (tokNameEq(nbuf[0..nn], "vmatrix"))
        .vmatrix
    else if (tokNameEq(nbuf[0..nn], "Vmatrix"))
        .Vmatrix
    else if (tokNameEq(nbuf[0..nn], "smallmatrix"))
        .smallmatrix
    else if (tokNameEq(nbuf[0..nn], "array"))
        .array
    else if (tokNameEq(nbuf[0..nn], "aligned"))
        .aligned
    else if (tokNameEq(nbuf[0..nn], "alignedat"))
        .alignedat
    else if (tokNameEq(nbuf[0..nn], "cases"))
        .cases
    else if (tokNameEq(nbuf[0..nn], "gathered"))
        .gathered
    else
        // KaTeX parity: reported at the `{name}` group opener.
        return ctx.fail(lb.pos, "unknown environment");

    // Column spec for `{array}` / `{alignedat}`.
    var spec: [16]u16 = undefined;
    var nspec: usize = 0;
    if (kind == .array) {
        const sl = try ctx.next();
        if (sl.kind != .lbrace) return ctx.fail(sl.pos, "expected column spec");
        while (true) {
            const q = try ctx.next();
            if (q.kind == .rbrace) break;
            if (q.kind != .char) return ctx.fail(q.pos, "expected column spec");
            const code: u16 = switch (q.cp) {
                'l' => 0,
                'c' => 1,
                'r' => 2,
                '|' => 3,
                else => return ctx.fail(q.pos, "expected column spec"),
            };
            if (nspec >= spec.len) return ctx.fail(q.pos, "too many columns");
            spec[nspec] = code;
            nspec += 1;
        }
        if (nspec == 0) return ctx.fail(cmd.pos, "empty column spec");
    } else if (kind == .alignedat) {
        const sl = try ctx.next();
        if (sl.kind != .lbrace) return ctx.fail(sl.pos, "expected column count");
        var count: usize = 0;
        var any = false;
        while (true) {
            const q = try ctx.next();
            if (q.kind == .rbrace) break;
            if (q.kind != .char or q.cp < '0' or q.cp > '9') return ctx.fail(q.pos, "expected column count");
            count = count * 10 + (q.cp - '0');
            any = true;
        }
        if (!any or count == 0 or count > 8) return ctx.fail(cmd.pos, "expected column count");
        // rl pairs.
        var k: usize = 0;
        while (k < count) : (k += 1) {
            if (nspec + 2 > spec.len) return ctx.fail(cmd.pos, "too many columns");
            spec[nspec] = 2;
            spec[nspec + 1] = 0;
            nspec += 2;
        }
    }

    ctx.in_env += 1;
    // Row spans are stashed locally and materialized densely at the
    // end: nested environments allocate pool rows while cells parse,
    // so the pool is not contiguous mid-parse.
    var spans: [64]Row = undefined;
    var nspans: usize = 0;
    var rowbuf: [64]u16 = undefined;
    var nrowbuf: usize = 0;
    var done = false;
    while (!done) {
        const c = try parseCell(ctx, depth);
        if (nrowbuf >= 64) return error.NoSpace;
        // amsmath parity (`\start@aligned`): every second cell of an
        // aligned row opens with an empty group so a leading operator
        // keeps binary spacing (and its MathML row).
        var cell = c.cell;
        if ((kind == .aligned or kind == .alignedat) and nrowbuf % 2 == 1) {
            cell = try prependEmptyGroup(ctx, cell);
        }
        rowbuf[nrowbuf] = cell;
        nrowbuf += 1;
        switch (c.term) {
            .amp => {},
            .newline => {
                if (nspans >= 64) return error.NoSpace;
                spans[nspans] = try stashRow(ctx, rowbuf[0..nrowbuf]);
                nspans += 1;
                nrowbuf = 0;
            },
            .end, .right => {
                // `\end{name}` — consume and verify. Errors report at
                // the `\end` (KaTeX parity).
                const etok = try ctx.next(); // \end
                const elb = try ctx.next();
                if (elb.kind != .lbrace) return ctx.fail(elb.pos, "expected '{' after '\\end'");
                var ebuf: [32]u8 = undefined;
                var en: usize = 0;
                while (true) {
                    const q = try ctx.next();
                    if (q.kind == .rbrace) break;
                    if (q.kind != .char or q.cp > 0x7F) return ctx.fail(q.pos, "expected environment name");
                    if (en >= ebuf.len) return ctx.fail(q.pos, "environment name too long");
                    ebuf[en] = @intCast(q.cp);
                    en += 1;
                }
                if (!tokNameEq(ebuf[0..en], nbuf[0..nn])) return ctx.fail(etok.pos, "mismatched '\\end'");
                if (c.term == .right) return ctx.fail(etok.pos, "unexpected '\\right'");
                // Final row (may be empty after a trailing `\\`).
                if (nrowbuf > 0 or nspans == 0) {
                    if (nspans >= 64) return error.NoSpace;
                    spans[nspans] = try stashRow(ctx, rowbuf[0..nrowbuf]);
                    nspans += 1;
                    nrowbuf = 0;
                }
                done = true;
            },
        }
    }
    ctx.in_env -= 1;
    // Materialize rows densely now that nested parsing is done.
    const rows_start = ctx.nrows;
    for (spans[0..nspans]) |sp| _ = try ctx.allocRow(sp);
    const spec_start = try ctx.allocKids(nspec);
    @memcpy(ctx.kids[spec_start .. spec_start + nspec], spec[0..nspec]);
    const env_id = try ctx.allocNode(.{ .env = .{
        .kind = kind,
        .rows_start = rows_start,
        .rows_len = @intCast(nspans),
        .spec_start = spec_start,
        .spec_len = @intCast(nspec),
    } });
    // Delimiter pairing for matrix variants. `cases` is a leftright
    // with a null right delimiter (KaTeX parity: no trailing mo).
    const fence: ?struct { l: u21, r: u21 } = switch (kind) {
        .pmatrix => .{ .l = '(', .r = ')' },
        .bmatrix => .{ .l = '[', .r = ']' },
        .Bmatrix => .{ .l = '{', .r = '}' },
        .vmatrix => .{ .l = '|', .r = '|' },
        .Vmatrix => .{ .l = 0x2016, .r = 0x2016 },
        .cases => .{ .l = '{', .r = 0 },
        else => null,
    };
    if (fence) |f| {
        return ctx.allocNode(.{ .delim = .{ .left = f.l, .right = f.r, .body = env_id } });
    }
    return env_id;
}

/// Copy one row's cell list into the kids pool; the `Row` span is
/// materialized into the rows pool by the caller at the end.
fn stashRow(ctx: *ParseCtx, cells: []const u16) Error!Row {
    const s = try ctx.allocKids(cells.len);
    @memcpy(ctx.kids[s .. s + cells.len], cells);
    return .{ .start = s, .len = @intCast(cells.len) };
}

test "parse single symbol and group" {
    var ctx = ParseCtx.init("x");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "parse sup-sub with primes" {
    var ctx = ParseCtx.init("x''^2_1");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .supsub => {},
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "double superscript is invalid" {
    var ctx = ParseCtx.init("x^2^3");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "unbalanced brace is invalid" {
    var ctx = ParseCtx.init("{x");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "newcommand then use parses" {
    var ctx = ParseCtx.init("\\newcommand{\\f}{x}\\f");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "gdef defines like def" {
    var ctx = ParseCtx.init("\\gdef\\g{y}\\g");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "macro loop hits expansion limit" {
    var ctx = ParseCtx.init("\\def\\a{\\a}\\a");
    try std.testing.expectError(error.ExpansionLimit, parse(&ctx, false));
}

test "redefining a builtin needs renewcommand" {
    var ctx = ParseCtx.init("\\newcommand{\\sum}{x}");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "unknown control sequence is invalid" {
    var ctx = ParseCtx.init("\\nope");
    const r = parse(&ctx, false);
    try std.testing.expectError(error.Invalid, r);
    try std.testing.expectEqual(@as(u32, 0), ctx.err_pos);
}

test "matrix ampersands and newlines split cells" {
    var ctx = ParseCtx.init("\\begin{matrix} a & b \\\\ c & d \\end{matrix}");
    const root = try parse(&ctx, false);
    const env_id = switch (ctx.nodes[root]) {
        .group => |g| blk: {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            break :blk ctx.kids[g.start];
        },
        else => return error.TestUnexpectedResult,
    };
    switch (ctx.nodes[env_id]) {
        .env => |e| {
            try std.testing.expectEqual(@as(u16, 2), e.rows_len);
            for (rowsOf(&ctx, e.rows_start, e.rows_len)) |row| {
                try std.testing.expectEqual(@as(u16, 2), row.len);
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "verb scans to delimiter as monospace text" {
    var ctx = ParseCtx.init("\\verb|x|");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .text => |tx| {
                    try std.testing.expectEqual(FontFam.tt, tx.fam);
                    const toks = toksOf(&ctx, tx.toks);
                    try std.testing.expectEqual(@as(u16, 1), tx.toks.len);
                    try std.testing.expect(toks[0].kind == .char and toks[0].cp == 'x');
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "verb star shows spaces visibly" {
    var ctx = ParseCtx.init("\\verb*|a b|");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            const toks = toksOf(&ctx, switch (ctx.nodes[ctx.kids[g.start]]) {
                .text => |tx| tx.toks,
                else => return error.TestUnexpectedResult,
            });
            try std.testing.expectEqual(@as(usize, 3), toks.len);
            try std.testing.expectEqual(@as(u21, 0x2423), toks[1].cp);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "verb rejects unclosed and multiline scans" {
    var c1 = ParseCtx.init("\\verb|x");
    try std.testing.expectError(error.Invalid, parse(&c1, false));
    var c2 = ParseCtx.init("\\verb|a\nb|");
    try std.testing.expectError(error.Invalid, parse(&c2, false));
}

test "verb inside macro expansion is rejected" {
    var ctx = ParseCtx.init("\\newcommand{\\v}{\\verb|x|}\\v");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "braced color still scopes over the rest of the group" {
    // KaTeX parity (sweep `color` case): `\color` is a declaration even
    // when the next atom is braced; only `\textcolor` scopes.
    var ctx = ParseCtx.init("\\color{red}{x}+y");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    switch (ctx.nodes[c.body]) {
                        .group => |bg| try std.testing.expectEqual(@as(u16, 3), bg.len),
                        else => return error.TestUnexpectedResult,
                    }
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unbraced color scopes over the rest of the group" {
    var ctx = ParseCtx.init("\\color{red}x+y");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    switch (ctx.nodes[c.body]) {
                        .group => |bg| try std.testing.expectEqual(@as(u16, 3), bg.len),
                        else => return error.TestUnexpectedResult,
                    }
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "color accepts hex specs and textcolor alias" {
    var ctx = ParseCtx.init("\\color{#f00}{x}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    const toks = toksOf(&ctx, c.spec);
                    try std.testing.expectEqual(@as(usize, 4), toks.len);
                    try std.testing.expect(toks[0].kind == .char and toks[0].cp == '#');
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    var c2 = ParseCtx.init("\\textcolor{blue}{x}");
    const r2 = try parse(&c2, false);
    switch (c2.nodes[r2]) {
        .group => |g| {
            switch (c2.nodes[c2.kids[g.start]]) {
                .color => {},
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "color spec resolves a no-arg macro" {
    var ctx = ParseCtx.init("\\newcommand{\\myred}{red}\\color{\\myred}{x}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    const toks = toksOf(&ctx, c.spec);
                    try std.testing.expectEqual(@as(usize, 3), toks.len);
                    try std.testing.expect(toks[0].kind == .char and toks[0].cp == 'r');
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "colorbox and fcolorbox parse text bodies" {
    var ctx = ParseCtx.init("\\colorbox{yellow}{a+b}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .colorbox => |c| {
                    try std.testing.expectEqual(@as(u16, 0), c.frame.len);
                    try std.testing.expect(toksOf(&ctx, c.bg).len == 6);
                    try std.testing.expect(toksOf(&ctx, c.body).len == 3);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    var c2 = ParseCtx.init("\\fcolorbox{red}{#ff0}{x}");
    const r2 = try parse(&c2, false);
    switch (c2.nodes[r2]) {
        .group => |g| {
            switch (c2.nodes[c2.kids[g.start]]) {
                .colorbox => |c| try std.testing.expect(c.frame.len > 0),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "text fonts take text arguments" {
    var ctx = ParseCtx.init("\\textbf{a+b}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .text => |tx| try std.testing.expectEqual(FontFam.bold, tx.fam),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Math commands are not allowed in text-font arguments (KaTeX parity).
    var c2 = ParseCtx.init("\\textbf{\\alpha}");
    try std.testing.expectError(error.Invalid, parse(&c2, false));
    // `\\textsl` is undefined in KaTeX.
    var c3 = ParseCtx.init("\\textsl{x}");
    try std.testing.expectError(error.Invalid, parse(&c3, false));
}

test "scripts after limits attach to the operator" {
    var ctx = ParseCtx.init("\\int\\limits_a^b");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .supsub => |s| {
                    switch (ctx.nodes[s.base]) {
                        .op => |o| try std.testing.expectEqual(LimitsMode.on, o.limits),
                        else => return error.TestUnexpectedResult,
                    }
                    try std.testing.expect(s.sup != NONE and s.sub != NONE);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "dollar in text mode is invalid" {
    var ctx = ParseCtx.init("\\text{a$b}");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "color specs follow the KaTeX validity rule" {
    // Bare words (even unknown ones) and 3/6-digit hex pass through.
    const ok_cases = [_][]const u8{
        "\\color{red}{x}",
        "\\color{notacolor}{x}",
        "\\color{#f00}{x}",
        "\\color{#ff00aa}{x}",
        "\\colorbox{red}{x}",
    };
    for (ok_cases) |src| {
        var ctx = ParseCtx.init(src);
        _ = try parse(&ctx, false);
    }
    // Empty specs, spaces, `rgb(...)`, and control sequences fail at
    // the spec brace (KaTeX parity: offset 6 below).
    const bad_cases = [_][]const u8{
        "\\color{}{x}",
        "\\color{red green}{x}",
        "\\color{rgb(1,0,0)}{x}",
        "\\color{\\%}{x}",
        "\\color{\\nosuchmacro}{x}",
        "\\colorbox{#ff}{x}",
    };
    for (bad_cases) |src| {
        var ctx = ParseCtx.init(src);
        const r = parse(&ctx, false);
        try std.testing.expectError(error.Invalid, r);
    }
    var ctx = ParseCtx.init("\\color{red green}{x}");
    _ = parse(&ctx, false) catch {};
    try std.testing.expectEqual(@as(u32, 6), ctx.err_pos);
}

