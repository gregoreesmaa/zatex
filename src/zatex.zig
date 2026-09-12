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
