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

test "unrenderable input errors so callers fall back in one pass" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    const p = testProvider();
    try std.testing.expectError(
        error.Unsupported,
        layout("\\sum_{i=1}^{n} i", .{}, p, &runs_buf, &rules_buf),
    );
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
