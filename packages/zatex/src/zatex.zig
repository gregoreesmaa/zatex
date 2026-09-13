//! ZaTeX — KaTeX-compatible LaTeX math engine (native Zig).
//!
//! Library root: public API plus the engine wiring (parse → layout →
//! IR/MathML). The frozen v1 shapes live in `contract.zig` and are
//! re-exported here unchanged; the output contract lives in `ir.zig`.
const std = @import("std");
const build_options = @import("build_options");

pub const ir = @import("ir.zig");
pub const parse = @import("parse.zig");
pub const symbols = @import("symbols.zig");
const engine = @import("layout.zig");
const mathml_mod = @import("mathml.zig");
pub const contract = @import("contract.zig");

// C ABI (issue 9): exports + conformance tests ride along with the lib.
comptime {
    _ = @import("cabi.zig");
}

// ---------------------------------------------------------------------------
// Stable v1 contract. Frozen 2026-09-12: additive-only evolution from here.
// New fallible conditions join LayoutError, new options gain defaults,
// provider callbacks arrive with a version bump — call-site shapes stay.
// (Canonical definitions in `contract.zig`; same names, same shapes.)
// ---------------------------------------------------------------------------

pub const version = contract.version;
pub const Profile = contract.Profile;
pub const max_input_len = contract.max_input_len;
pub const max_nesting_depth = contract.max_nesting_depth;
pub const max_expand = contract.max_expand;
pub const LayoutOptions = contract.LayoutOptions;
pub const RuleKind = contract.RuleKind;
pub const provider_version = contract.provider_version;
pub const MetricsProvider = contract.MetricsProvider;
pub const LayoutError = contract.LayoutError;
pub const Diag = contract.Diag;
pub const FontId = contract.FontId;

pub const profile: Profile =
    std.meta.stringToEnum(Profile, build_options.profile) orelse .full;

/// Reentrant layout path: `glyphs` backs every `Run.glyphs` slice in
/// the returned `Layout`. Zero heap allocations; `NoSpace` when any
/// caller buffer fills.
pub fn layoutFull(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
) LayoutError!ir.Layout {
    var diag = Diag.empty();
    return layoutInner(source, options, provider, runs, rules, glyphs, &diag);
}

/// Layout with KaTeX-parity diagnostics: on `Invalid`, `diag` carries
/// the failure offset and message.
pub fn layoutDiag(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
    diag: *Diag,
) LayoutError!ir.Layout {
    return layoutInner(source, options, provider, runs, rules, glyphs, diag);
}

/// Shared engine entry for the Zig and C surfaces (see `cabi.zig`).
pub fn layoutInner(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
    diag: *Diag,
) LayoutError!ir.Layout {
    if (source.len > max_input_len) return error.TooLong;
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, options.display_mode) catch |e| {
        // Offsets match KaTeX `ParseError.position` exactly: the
        // 0-based byte offset of the offending token (KaTeX's message
        // text adds 1 for humans; the property is the API contract).
        diag.offset = if (pc.err_pos > source.len) @intCast(source.len) else pc.err_pos;
        diag.message = pc.err_msg;
        return e;
    };
    var lc = engine.LayCtx.init(&pc, provider);
    const style: parse.Style = if (options.display_mode) .D else .T;
    return engine.layout(&lc, root, style, runs, rules, glyphs);
}

/// MathML Core serialization of one formula into caller-owned `out`.
/// Pure structural mapping over the parse tree — no layout math.
pub fn mathml(source: []const u8, options: LayoutOptions, out: []u8) LayoutError![]const u8 {
    return mathml_mod.render(source, options, out);
}

/// Lay out one formula into caller-owned buffers (zero allocations).
/// `Run.glyphs` slices borrow a shared 8K-glyph ring that stays valid
/// until the next `layout` call (documented ctime-style borrow);
/// prefer `layoutFull` for reentrant use.
pub fn layout(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
) LayoutError!ir.Layout {
    const S = struct {
        var ring: [8192]u16 = undefined;
    };
    return layoutFull(source, options, provider, runs, rules, &S.ring);
}

test "profile option resolves to a known profile" {
    try std.testing.expect(@intFromEnum(profile) <= @intFromEnum(Profile.full));
}

test "empty input lays out empty" {
    const l = ir.Layout.empty();
    try std.testing.expectEqual(@as(u32, 0), l.width);
    try std.testing.expectEqual(@as(usize, 0), l.runs.len);
    try std.testing.expectEqual(@as(usize, 0), l.rules.len);
}

fn layoutOk(
    source: []const u8,
    options: LayoutOptions,
    runs_buf: []ir.Run,
    rules_buf: []ir.Rule,
    glyphs_buf: []u16,
) !ir.Layout {
    return layoutFull(source, options, testProvider(), runs_buf, rules_buf, glyphs_buf);
}

test "accept: single symbol lays out one run" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
    try std.testing.expect(l.width > 0);
}

test "accept: sup-sub scripts lay out" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("x^2_1", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(l.width > 0);
    try std.testing.expect(l.runs.len >= 2);
}

test "accept: greek and operators lay out" {
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("\\alpha+\\beta", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 3), l.runs.len);
}

test "accept: frac emits bar rule" {
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("\\frac{1}{2}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
}

test "accept: sqrt and sum lay out" {
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    _ = try layoutOk("\\sqrt{2}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    const l = try layoutOk("\\sum_{i=1}^{n} i", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(l.width > 0);
}

test "accept: unknown command is Invalid with offset" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var diag = Diag.empty();
    try std.testing.expectError(
        error.Invalid,
        layoutDiag("\\nope", .{}, testProvider(), &runs_buf, &rules_buf, &glyphs_buf, &diag),
    );
    // KaTeX parity: `ParseError.position` is the 0-based token start.
    try std.testing.expectEqual(@as(u32, 0), diag.offset);
}

test "accept: color, verb, and boxes lay out natively" {
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const cases = [_][]const u8{
        "\\color{red}{x}+y",
        "\\color{red}x+y",
        "\\textcolor{blue}{x}",
        "\\color{#f00}{x}",
        "\\verb|x|+\\verb*|a b|",
        "\\colorbox{yellow}{a+b}",
        "\\fcolorbox{red}{#ff0}{x}",
        "\\textbf{ab}+\\textit{cd}",
    };
    for (cases) |src| {
        _ = try layoutOk(src, .{}, &runs_buf, &rules_buf, &glyphs_buf);
    }
}

test "accept: unbalanced brace is Invalid" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var diag = Diag.empty();
    try std.testing.expectError(
        error.Invalid,
        layoutDiag("{x", .{}, testProvider(), &runs_buf, &rules_buf, &glyphs_buf, &diag),
    );
}

test "accept: macro loop errors ExpansionLimit" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    try std.testing.expectError(
        error.ExpansionLimit,
        layoutOk("\\def\\a{\\a}\\a", .{}, &runs_buf, &rules_buf, &glyphs_buf),
    );
}

test "accept: excessive nesting errors TooDeep" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var deep: [80]u8 = undefined;
    @memset(&deep, '{');
    try std.testing.expectError(
        error.TooDeep,
        layoutOk(&deep, .{}, &runs_buf, &rules_buf, &glyphs_buf),
    );
}

test "adversarial inputs are total and deterministic" {
    // Seeded input soup plus structured worst cases: the engine must
    // always return (never hang or panic) and agree with itself.
    var runs_a: [64]ir.Run = undefined;
    var rules_a: [16]ir.Rule = undefined;
    var glyphs_a: [1024]u16 = undefined;
    var runs_b: [64]ir.Run = undefined;
    var rules_b: [16]ir.Rule = undefined;
    var glyphs_b: [1024]u16 = undefined;
    var mbuf_a: [2048]u8 = undefined;
    var mbuf_b: [2048]u8 = undefined;
    const pieces = [_][]const u8{ "x", "y", "2", "+", "-", "{", "}", "^", "_",
        "\\frac", "\\sum", "\\alpha", "\\text{a}",
        "(", ")", " ", "&", "#", "$", "\\left(", "\\", "~", ",", ";" };
    var prng = std.Random.DefaultPrng.init(0x5EED);
    var rnd = prng.random();
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        var buf: [256]u8 = undefined;
        var len: usize = 0;
        var k: usize = 0;
        const n = 1 + rnd.uintLessThan(usize, 24);
        while (k < n and len < buf.len) : (k += 1) {
            const pc = pieces[rnd.uintLessThan(usize, pieces.len)];
            const m = @min(pc.len, buf.len - len);
            @memcpy(buf[len..][0..m], pc[0..m]);
            len += m;
        }
        const src = buf[0..len];
        var da = Diag.empty();
        var db = Diag.empty();
        const r1 = layoutDiag(src, .{}, testProvider(), &runs_a, &rules_a, &glyphs_a, &da);
        const r2 = layoutDiag(src, .{}, testProvider(), &runs_b, &rules_b, &glyphs_b, &db);
        if (r1) |l1| {
            const l2 = try r2;
            try std.testing.expectEqual(l1.width, l2.width);
            try std.testing.expectEqual(l1.runs.len, l2.runs.len);
            try std.testing.expectEqual(l1.rules.len, l2.rules.len);
            try std.testing.expectEqual(da.offset, db.offset);
        } else |e1| {
            try std.testing.expectError(e1, r2);
            try std.testing.expect(da.offset <= src.len);
        }
        const m1 = mathml(src, .{}, &mbuf_a);
        const m2 = mathml(src, .{}, &mbuf_b);
        if (m1) |s1| {
            const s2 = try m2;
            try std.testing.expectEqualStrings(s1, s2);
        } else |e1| {
            try std.testing.expectError(e1, m2);
        }
    }
    // Structured worst cases with exact errors.
    var deep: [200]u8 = undefined;
    @memset(&deep, '{');
    try std.testing.expectError(error.TooDeep, layoutOk(&deep, .{}, &runs_a, &rules_a, &glyphs_a));
    var flat: [1401]u8 = undefined;
    var f: usize = 0;
    while (f < 700) : (f += 1) {
        flat[2 * f] = 'x';
        flat[2 * f + 1] = '+';
    }
    flat[1400] = 'x';
    try std.testing.expectError(error.NoSpace, layoutOk(&flat, .{}, &runs_a, &rules_a, &glyphs_a));
    // Exponential blowup fills the token pool before the expansion counter trips:
    // still an error, honestly reported as pool exhaustion.
    try std.testing.expectError(error.NoSpace, layoutOk("\\def\\a{\\a\\a}\\a", .{}, &runs_a, &rules_a, &glyphs_a));
    var bad: [4]u8 = .{ 'x', 0xFF, '+', 'y' };
    if (layoutOk(&bad, .{}, &runs_a, &rules_a, &glyphs_a)) |_| return error.TestUnexpectedResult else |_| {}
}
test "accept: user macro expands" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("\\newcommand{\\f}{x}\\f", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
}

test "accept: mathml maps frac structurally" {
    var out: [256]u8 = undefined;
    const s = try mathml("\\frac12", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mfrac>") != null);
}

test "accept: empty input lays out empty" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 0), l.width);
}

test "sqrt radicand is cramped: sup sits 30mu lower than top level" {
    // TeX sets the radicand in cramped style (issue #20 Dc grid rows):
    // a sup directly inside `\sqrt{...}` rises 30mu less than at top
    // level. Resolved by glyph id through the stub provider
    // ('x' = 120, '2' = 50, radical U+221A = 8730).
    const S = struct {
        fn raise(l: ir.Layout) !i32 {
            var yx: ?i32 = null;
            var y2: ?i32 = null;
            for (l.runs) |r| {
                for (r.glyphs) |g| {
                    if (g == 120 and yx == null) yx = r.baseline_y;
                    if (g == 50 and y2 == null) y2 = r.baseline_y;
                }
            }
            return (yx orelse return error.TestUnexpectedResult) -
                (y2 orelse return error.TestUnexpectedResult);
        }
    };
    var runs_a: [32]ir.Run = undefined;
    var rules_a: [8]ir.Rule = undefined;
    var glyphs_a: [128]u16 = undefined;
    var runs_b: [32]ir.Run = undefined;
    var rules_b: [8]ir.Rule = undefined;
    var glyphs_b: [128]u16 = undefined;
    const top = try layoutOk("x^2", .{}, &runs_a, &rules_a, &glyphs_a);
    const rad = try layoutOk("\\sqrt{x^2}", .{}, &runs_b, &rules_b, &glyphs_b);
    try std.testing.expectEqual(@as(i32, 400), try S.raise(top));
    try std.testing.expectEqual(try S.raise(top) - 30, try S.raise(rad));
}

test "oversize input errors TooLong before anything else" {
    var big: [max_input_len + 1]u8 = .{'x'} ** (max_input_len + 1);
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    try std.testing.expectError(
        error.TooLong,
        layout(&big, .{}, testProvider(), &runs_buf, &rules_buf),
    );
}

fn testProvider() MetricsProvider {
    const S = struct {
        fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn ruleThickness(_: *const anyopaque, _: u16, _: RuleKind) i32 {
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
