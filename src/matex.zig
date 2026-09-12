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

/// v0 contract: nothing renders yet. Single pass — callers attempt
/// layout directly and `error.Unsupported` means "not renderable, fall
/// back" (in `read`: plain code cards). Inspects the slice only.
pub const LayoutError = error{Unsupported};

pub fn layout(source: []const u8) LayoutError!ir.Layout {
    _ = source;
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
    try std.testing.expectError(error.Unsupported, layout("\\sum_{i=1}^{n} i"));
}
