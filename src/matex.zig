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

/// v0 contract: nothing renders yet, so every input reports unsupported
/// and callers must fall back (in `read`: plain code cards). Inspects
/// the slice only — zero allocations.
pub fn supports(source: []const u8) bool {
    _ = source;
    return false;
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

test "unsupported input reports false so callers fall back" {
    try std.testing.expect(!supports("\\sum_{i=1}^{n} i"));
}
