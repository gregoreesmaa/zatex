//! MaTeX front end: lexer, macro expander, parser → AST.
//!
//! Bounded and allocation-free: tokens, nodes, macro bodies, and the
//! expansion pushback all live in fixed pools inside `ParseCtx` (one
//! stack value owned by the layout call). Macro expansion is
//! token-level with a hard `max_expand` budget (KaTeX parity: 1000).
const std = @import("std");
const contract = @import("contract.zig");
const symbols = @import("symbols.zig");

const Error = contract.LayoutError;
const profile = @import("matex.zig").profile;

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
    /// 0 = auto (current style), 1 = display, 2 = text.
    fstyle: u2 = 0,
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
    /// Color target ignored: the IR has no color channel (see the
    /// `\color` decision in the parser). Layout renders `body`.
    color: Idx,
    href: Idx,
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
pub const max_toks: usize = 2048;
pub const max_pushback: usize = 512;
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
        if (self.nnodes >= max_nodes) return error.TooDeep;
        const id = self.nnodes;
        self.nodes[id] = n;
        self.nnodes += 1;
        return id;
    }

    fn allocKids(self: *ParseCtx, n: usize) Error!u16 {
        if (n > max_kids - self.nkids) return error.TooDeep;
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
        if (self.nrows >= max_rows) return error.TooDeep;
        const id = self.nrows;
        self.rows[id] = r;
        self.nrows += 1;
        return id;
    }

    fn push(self: *ParseCtx, t: Tok) Error!void {
        if (self.npb >= max_pushback) {
            self.err_pos = t.pos;
            self.err_msg = "macro expansion too large";
            return error.ExpansionLimit;
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
        self.skipGap();
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
                    try self.push(at);
                }
            } else {
                var nt = bt;
                nt.pos = use_pos;
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
            if (nn.* >= 512) return error.TooDeep;
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
                    continue;
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
        return ctx.fail(t.pos, "nesting too deep");
    }
    const maybe = try parseSingle(ctx, depth + 1);
    return maybe orelse ctx.fail(t.pos, "expected argument");
}

fn parseSingle(ctx: *ParseCtx, depth: u8) Error!?Idx {
    if (depth >= contract.max_nesting_depth) {
        const t = try ctx.peek();
        return ctx.fail(t.pos, "nesting too deep");
    }
    const t = try ctx.next();
    switch (t.kind) {
        .char => {
            const cls = symbols.asciiClass(t.cp) orelse .Ord;
            const font: FontFam = if (t.cp >= '0' and t.cp <= '9')
                .rm
            else if ((t.cp >= 'a' and t.cp <= 'z') or (t.cp >= 'A' and t.cp <= 'Z'))
                .mathit
            else
                .rm;
            return ctx.allocNode(.{ .atom = .{ .class = cls, .font = font, .cp = t.cp } });
        },
        .lbrace => return parseFormula(ctx, depth + 1, .group),
        .sup => return ctx.fail(t.pos, "expected base before '^'"),
        .sub => return ctx.fail(t.pos, "expected base before '_'"),
        .amp => return ctx.fail(t.pos, "unexpected '&'"),
        .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
        .newline => return ctx.allocNode(.{ .newline = {} }),
        .param => return ctx.fail(t.pos, "unexpected '#'"),
        .end => return ctx.fail(t.pos, "unexpected end of input"),
        .ctrl => {
            // User macros shadow builtins.
            if (t.name.len > 0 and isMacroName(t)) {
                if (ctx.findDef(t.name)) |def| {
                    try ctx.expandUse(def, t.pos);
                    return parseSingle(ctx, depth);
                }
            }
            return parseCtrl(ctx, depth, t);
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
            sub = try parseGroupOrAtom(ctx, depth);
        } else if (p.kind == .char and p.cp == '\'') {
            _ = try ctx.next();
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
    return ctx.allocNode(.{ .supsub = .{
        .base = base,
        .sup = sup,
        .sub = sub,
        .prime_sup = prime_made and nsup > 0,
    } });
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
            .amp => return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .amp },
            .newline => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
            },
            .ctrl => {
                if (isName(t, "end") or isName(t, "right") or isName(t, "cr")) {
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = if (isName(t, "amp")) .amp else if (isName(t, "end")) .end else if (isName(t, "right")) .right else .newline };
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
                    continue;
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.TooDeep;
                    buf[n] = id;
                    n += 1;
                }
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.TooDeep;
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
            .amp => return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .amp },
            .newline => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
            },
            .ctrl => {
                if (isName(t, "end") or isName(t, "right") or isName(t, "cr")) {
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = if (isName(t, "end")) .end else if (isName(t, "right")) .right else .newline };
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.TooDeep;
                    buf[n] = id;
                    n += 1;
                }
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.TooDeep;
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

fn parseCtrl(ctx: *ParseCtx, depth: u8, t: Tok) Error!?Idx {
    // Single-character names (`\%`, `\,`, `\'`, ...).
    if (t.name.len == 1) return parseSingleCharCtrl(ctx, depth, t);
    const name = t.name;

    // Macro definition forms (side effect, no node).
    if (tokNameEq(name, "newcommand") or tokNameEq(name, "renewcommand") or
        tokNameEq(name, "providecommand"))
    {
        try subsetGate(false);
        try parseNewCommand(ctx, t, tokNameEq(name, "renewcommand"), tokNameEq(name, "providecommand"));
        return null;
    }
    if (tokNameEq(name, "def")) {
        try subsetGate(false);
        try parseDef(ctx, t);
        return null;
    }
    if (tokNameEq(name, "let")) {
        try subsetGate(false);
        try parseLet(ctx, t);
        return null;
    }

    if (tokNameEq(name, "frac")) return parseFracLike(ctx, depth, .{ .bar = true });
    if (tokNameEq(name, "dfrac")) return parseFracLike(ctx, depth, .{ .bar = true, .fstyle = 1 });
    if (tokNameEq(name, "tfrac")) return parseFracLike(ctx, depth, .{ .bar = true, .fstyle = 2 });
    if (tokNameEq(name, "cfrac")) return parseFracLike(ctx, depth, .{ .bar = true, .fstyle = 1 });
    if (tokNameEq(name, "binom")) return parseFracLike(ctx, depth, .{ .bar = false, .parens = true });
    if (tokNameEq(name, "dbinom")) {
        return parseFracLike(ctx, depth, .{ .bar = false, .parens = true, .fstyle = 1 });
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
        if (ctx.in_fence == 0) return ctx.fail(t.pos, "'\\middle' outside '\\left'");
        const cp = try parseDelimSpec(ctx);
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
        try subsetGate(false);
        const nuc = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .accent = .{ .cp = 0x0338, .wide = false, .nucleus = nuc } });
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
    if (fontFamFor(name)) |fam| {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .font = .{ .fam = fam, .body = body } });
    }
    if (tokNameEq(name, "boldsymbol")) {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .font = .{ .fam = .bold, .body = body } });
    }
    if (tokNameEq(name, "color")) {
        try subsetGate(false);
        _ = try ctx.captureArg();
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .color = body });
    }
    if (tokNameEq(name, "href")) {
        try subsetGate(false);
        _ = try ctx.captureArg();
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .href = body });
    }
    if (tokNameEq(name, "url")) {
        try subsetGate(false);
        const toks = try ctx.captureArg();
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
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .raisebox = .{ .body = body, .dh = dh } });
    }
    if (tokNameEq(name, "rule")) {
        try subsetGate(false);
        return parseRule(ctx, depth);
    }
    if (tokNameEq(name, "boxed") or tokNameEq(name, "fbox")) {
        try subsetGate(false);
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .boxed = body });
    }
    if (tokNameEq(name, "phantom") or tokNameEq(name, "hphantom") or tokNameEq(name, "vphantom")) {
        try subsetGate(false);
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .phantom = .{
            .body = body,
            .keep_h = tokNameEq(name, "vphantom"),
            .keep_v = tokNameEq(name, "hphantom"),
        } });
    }
    if (tokNameEq(name, "llap") or tokNameEq(name, "rlap") or tokNameEq(name, "clap")) {
        try subsetGate(false);
        const body = try parseGroupOrAtom(ctx, depth);
        const kind: LapKind = if (tokNameEq(name, "llap")) .llap else if (tokNameEq(name, "rlap")) .rlap else .clap;
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
                .text = text,
            } });
        }
        return ctx.allocNode(.{ .atom = .{ .class = sym.class, .font = .rm, .cp = sym.cp } });
    }
    if (symbols.lookupDelim(name)) |cp| {
        // Bare delimiter (no `\left`): fixed-size fence atom.
        return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = cp } });
    }
    return ctx.fail(t.pos, "undefined control sequence");
}

// ---------------------------------------------------------------------------
// Single-character control sequences
// ---------------------------------------------------------------------------

fn parseSingleCharCtrl(ctx: *ParseCtx, depth: u8, t: Tok) Error!?Idx {
    const c: u8 = t.name[0];
    switch (c) {
        '{' => return ctx.allocNode(.{ .atom = .{ .class = .Open, .font = .rm, .cp = '{' } }),
        '}' => return ctx.allocNode(.{ .atom = .{ .class = .Close, .font = .rm, .cp = '}' } }),
        '$' => return ctx.fail(t.pos, "can't use '$' in math mode"),
        '%' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '%' } }),
        '&' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '&' } }),
        '#' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '#' } }),
        '_' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '_' } }),
        '|' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 0x2016 } }),
        ' ' => return ctx.allocNode(.{ .space = 333 }),
        ',' => return ctx.allocNode(.{ .space = 167 }),
        ':' => return ctx.allocNode(.{ .space = 222 }),
        ';' => return ctx.allocNode(.{ .space = 278 }),
        '!' => return ctx.allocNode(.{ .space = -167 }),
        '/' => return ctx.allocNode(.{ .space = 0 }),
        '\\' => return ctx.allocNode(.{ .newline = {} }),
        else => {},
    }
    // Text accents (`\'`, `\"`, ...): letter argument → precomposed.
    if (textAccentCp(c)) |acc| {
        const a = try parseGroupOrAtom(ctx, depth);
        return applyTextAccent(ctx, t.pos, acc, a);
    }
    return ctx.fail(t.pos, "undefined control sequence");
}

fn textAccentCp(c: u8) ?u21 {
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

fn precompose(acc: u21, base: u21) ?u21 {
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
    if (tokNameEq(name, "mathrm") or tokNameEq(name, "textrm") or
        tokNameEq(name, "textup") or tokNameEq(name, "rm")) return .rm;
    if (tokNameEq(name, "mathit") or tokNameEq(name, "textit") or
        tokNameEq(name, "it") or tokNameEq(name, "mathnormal")) return .mathit;
    if (tokNameEq(name, "mathbf") or tokNameEq(name, "textbf") or
        tokNameEq(name, "bf")) return .bold;
    if (tokNameEq(name, "mathsf") or tokNameEq(name, "textsf") or
        tokNameEq(name, "sf")) return .sans;
    if (tokNameEq(name, "mathtt") or tokNameEq(name, "texttt") or
        tokNameEq(name, "tt")) return .tt;
    if (tokNameEq(name, "mathfrak")) return .frak;
    if (tokNameEq(name, "mathscr")) return .script;
    if (tokNameEq(name, "mathbb") or tokNameEq(name, "Bbb")) return .bb;
    if (tokNameEq(name, "mathcal") or tokNameEq(name, "cal")) return .cal;
    if (tokNameEq(name, "textsl")) return .mathit;
    if (tokNameEq(name, "textmd")) return .rm;
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
            if (symbols.lookupDelim(t.name)) |cp| return cp;
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
    _ = t;
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
            break :blk symbols.lookupDelim(dt.name) orelse return ctx.fail(dt.pos, "expected delimiter");
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
    // Bare dimension: consecutive number/unit chars.
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    while (n < buf.len) {
        const q = try ctx.peek();
        if (q.kind != .char) break;
        const c = q.cp;
        const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-' or
            (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
        if (!ok) break;
        if (c > 0x7F) break;
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
    // Unit letters.
    const ustart = i;
    while (i < b.len and ((b[i] >= 'a' and b[i] <= 'z') or (b[i] >= 'A' and b[i] <= 'Z'))) : (i += 1) {}
    if (i != b.len) return ctx.fail(pos, "expected dimension");
    const unit = b[ustart..];
    // Thousandths of an em per unit (1em = 10pt at the reference size).
    const per_em: i64 = if (eq2(unit, "em"))
        1000
    else if (eq2(unit, "ex"))
        500 // ≈ x-height; documented approximation
    else if (eq2(unit, "mu"))
        1000
    else if (eq2(unit, "pt"))
        100
    else if (eq2(unit, "pc"))
        1200
    else if (eq2(unit, "in"))
        7227
    else if (eq2(unit, "bp"))
        100
    else if (eq2(unit, "cm"))
        2845
    else if (eq2(unit, "mm"))
        285
    else if (eq2(unit, "dd"))
        107
    else if (eq2(unit, "cc"))
        1288
    else if (eq2(unit, "sp"))
        0
    else
        return ctx.fail(pos, "unknown unit");
    var v: i64 = int * per_em + @divTrunc(frac * per_em, fdiv);
    if (eq2(unit, "mu")) v = @divTrunc(v, 18);
    if (neg) v = -v;
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    return @intCast(v);
}

fn eq2(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        var u = x;
        var v = y;
        if (u >= 'A' and u <= 'Z') u += 32;
        if (v >= 'A' and v <= 'Z') v += 32;
        if (u != v) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// `\text` bodies, `\genfrac`, `\smash`, `\rule`, `\substack`
// ---------------------------------------------------------------------------

/// Braced token capture with `\text`-style validation of the braces.
fn parseBracedToks(ctx: *ParseCtx, cmd: Tok, comptime need_brace: bool) Error!Range {
    const pk = try ctx.peek();
    if (pk.kind == .lbrace) {
        _ = try ctx.next();
        return ctx.captureToBrace(pk.pos);
    }
    if (need_brace) return ctx.fail(cmd.pos, "expected '{'");
    return ctx.captureArg();
}

fn checkTextToks(ctx: *ParseCtx, r: Range) Error!void {
    var i: u16 = 0;
    while (i < r.len) : (i += 1) {
        const tk = ctx.toks[r.start + i];
        switch (tk.kind) {
            .char, .lbrace, .rbrace, .newline => {},
            .ctrl => {
                // Only single-character escapes (`\%`, `\_`, ...) and
                // spacing are allowed in text; math commands are not.
                if (tk.name.len != 1) return ctx.fail(tk.pos, "can't use math command in text mode");
                const c = tk.name[0];
                switch (c) {
                    '{', '}', '%', '&', '#', '_', '$', ' ', ',', ':', ';', '!', '~', '|', '/', '\'', '`', '^', '"', '=', '.', 'u', 'v', 'H', 't', 'c', 'd', 'b', 'r' => {},
                    else => return ctx.fail(tk.pos, "can't use math command in text mode"),
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
    var fstyle: u2 = 0;
    if (style_t.len > 0) {
        if (style_t.len != 1) return ctx.fail(cmd.pos, "expected style number");
        const d = ctx.toks[style_t.start];
        if (d.kind != .char or d.cp < '0' or d.cp > '3') return ctx.fail(cmd.pos, "expected style number");
        fstyle = @intCast(d.cp - '0' + 1);
    }
    const num = try parseTokenRange(ctx, depth, num_t);
    const den = try parseTokenRange(ctx, depth, den_t);
    const frac_id = try ctx.allocNode(.{ .frac = .{
        .num = num,
        .den = den,
        .kind = .{ .bar = true, .fstyle = fstyle, .parens = false, .thick = thick },
    } });
    if (left == 0 and right == 0) return frac_id;
    return ctx.allocNode(.{ .delim = .{ .left = left, .right = right, .body = frac_id } });
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
            if (symbols.lookupDelim(tk.name)) |cp| return cp;
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
    // Default: smash both. `[t]` keeps the bottom (smashes top only),
    // `[b]` keeps the top; `[tb]` smashes both explicitly.
    var keep_t = false;
    var keep_b = false;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        var has_t = false;
        var has_b = false;
        while (true) {
            const o = try ctx.next();
            if (o.kind == .char and o.cp == ']') break;
            if (o.kind == .end) return ctx.fail(pk.pos, "expected ']'");
            if (o.kind == .char and o.cp == 't') {
                has_t = true;
                continue;
            }
            if (o.kind == .char and o.cp == 'b') {
                has_b = true;
                continue;
            }
            return ctx.fail(o.pos, "expected 't' or 'b'");
        }
        keep_t = has_b and !has_t;
        keep_b = has_t and !has_b;
        if (has_t and has_b) {
            keep_t = false;
            keep_b = false;
        }
    }
    const body = try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .smash = .{ .body = body, .keep_t = keep_t, .keep_b = keep_b } });
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
                    const maybe = try parseAtom(ctx, depth);
                    if (maybe) |id| {
                        if (n >= 512) return error.TooDeep;
                        buf[n] = id;
                        n += 1;
                    }
                },
            }
        }
        const cell = try finishGroup(ctx, buf[0..n]);
        const ks = try ctx.allocKids(1);
        ctx.kids[ks] = cell;
        if (nrow >= 64) return error.TooDeep;
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
            if (d.kind != .char or d.cp != '1' + nargs) return ctx.fail(d.pos, "parameters must be sequential");
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
        "providecommand", "def", "let", "over", "atop", "choose", "brace",
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
        return ctx.fail(cmd.pos, "unknown environment");

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
        if (nrowbuf >= 64) return error.TooDeep;
        rowbuf[nrowbuf] = c.cell;
        nrowbuf += 1;
        switch (c.term) {
            .amp => {},
            .newline => {
                if (nspans >= 64) return error.TooDeep;
                spans[nspans] = try stashRow(ctx, rowbuf[0..nrowbuf]);
                nspans += 1;
                nrowbuf = 0;
            },
            .end, .right => {
                // `\end{name}` — consume and verify.
                _ = try ctx.next(); // \end
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
                if (!tokNameEq(ebuf[0..en], nbuf[0..nn])) return ctx.fail(cmd.pos, "mismatched '\\end'");
                if (c.term == .right) return ctx.fail(cmd.pos, "unexpected '\\right'");
                // Final row (may be empty after a trailing `\\`).
                if (nrowbuf > 0 or nspans == 0) {
                    if (nspans >= 64) return error.TooDeep;
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
    // Delimiter pairing for matrix variants.
    const fence: ?struct { l: u21, r: u21 } = switch (kind) {
        .pmatrix => .{ .l = '(', .r = ')' },
        .bmatrix => .{ .l = '[', .r = ']' },
        .Bmatrix => .{ .l = '{', .r = '}' },
        .vmatrix => .{ .l = '|', .r = '|' },
        .Vmatrix => .{ .l = 0x2016, .r = 0x2016 },
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

