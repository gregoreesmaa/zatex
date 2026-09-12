//! MaTeX — KaTeX-compatible LaTeX math engine (native Zig).
//!
//! Library root. Layout core lands here milestone by milestone (see
//! GitHub issues); the output contract lives in `ir.zig`.
const std = @import("std");
const build_options = @import("build_options");

pub const ir = @import("ir.zig");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

pub const Profile = enum { subset, full };

pub const profile: Profile =
    std.meta.stringToEnum(Profile, build_options.profile) orelse .full;

// ---------------------------------------------------------------------------
// Stable v1 contract. Frozen 2026-09-12: additive-only evolution from here.
// New fallible conditions join LayoutError, new options gain defaults,
// provider callbacks arrive with a version bump — call-site shapes stay.
// ---------------------------------------------------------------------------

/// Hard caps. Part of the contract, not tunables.
pub const max_input_len: usize = 64 * 1024;
pub const max_nesting_depth: u8 = 32;
pub const max_expand: u32 = 1000; // KaTeX `maxExpand` default parity.

/// Layout knobs. Fields gain defaults, never lose them.
pub const LayoutOptions = struct {
    display_mode: bool = false,
};

/// Rule kinds the core may ask a thickness for.
pub const RuleKind = enum { fraction_bar, radical, overline, underline };

/// Host-supplied font metrics. The core never touches font files: glyph
/// identity, advances, and rule weights arrive here in integer font
/// units. `font` is the host's own namespace, opaque to the core.
pub const provider_version: u32 = 1;
pub const MetricsProvider = struct {
    ctx: *const anyopaque,
    glyphId: *const fn (ctx: *const anyopaque, font: u16, codepoint: u21) u16,
    advance: *const fn (ctx: *const anyopaque, font: u16, glyph: u16) i32,
    ruleThickness: *const fn (ctx: *const anyopaque, font: u16, kind: RuleKind) i32,
};

/// Every failure the engine can ever report. Variants are added, never
/// removed or repurposed; `OutOfMemory` is reserved (the core allocates
/// nothing) so the set never reshapes under callers.
pub const LayoutError = error{
    Unsupported, // outside subset/profile scope → caller falls back
    Invalid, // malformed input (KaTeX ParseError parity)
    TooDeep, // max_nesting_depth exceeded
    TooLong, // max_input_len exceeded
    ExpansionLimit, // max_expand exceeded
    NoSpace, // caller runs/rules buffers filled
    OutOfMemory, // reserved; the core allocates nothing
};

/// KaTeX `ParseError` parity: byte offset plus a static message.
/// Positions are byte offsets into `source`, matching KaTeX's
/// character offsets for ASCII input.
pub const Diag = struct {
    offset: u32,
    message: []const u8,

    pub fn empty() Diag {
        return .{ .offset = 0, .message = "" };
    }
};

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
    _ = source;
    _ = options;
    _ = provider;
    _ = runs;
    _ = rules;
    _ = glyphs;
    return error.Unsupported;
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
    _ = diag;
    return layoutFull(source, options, provider, runs, rules, glyphs);
}

/// MathML Core serialization of one formula into caller-owned `out`.
/// Pure structural mapping over the parse tree — no layout math.
pub fn mathml(source: []const u8, options: LayoutOptions, out: []u8) LayoutError![]const u8 {
    _ = source;
    _ = options;
    _ = out;
    return error.Unsupported;
}

/// Lay out one formula into caller-owned buffers (zero allocations).
/// v0: nothing renders yet — oversize input errors TooLong, everything
/// else errors Unsupported so callers fall back in a single pass.
pub fn layout(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
) LayoutError!ir.Layout {
    _ = options;
    _ = provider;
    _ = runs;
    _ = rules;
    if (source.len > max_input_len) return error.TooLong;
    return error.Unsupported;
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
    try std.testing.expectEqual(@as(u32, 0), diag.offset);
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
