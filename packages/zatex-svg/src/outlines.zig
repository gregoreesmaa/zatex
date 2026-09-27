//! Outline seam: glyph ink as CFF segments, demuxed per stack face.
// Scaffold: replaced by Tasks 2-4.
const std = @import("std");
const cff = @import("cff");

// Scaffold: replaced by Tasks 2-4.
pub const Outlines = struct {
    ptr: *const anyopaque,
    // Segments in per-face font units (y-up, like CFF), or null to skip ink.
    // Never errors: failure resolves to null (skip-ink totality).
    glyphSegs: *const fn (ptr: *const anyopaque, unified: u16, out: []cff.Seg) ?[]const cff.Seg,
    // Integer advance in thousandths of an em (500 fallback inside file impl).
    advance1000: *const fn (ptr: *const anyopaque, unified: u16) i32,
    // Per-face units-per-em (1000 when unknown; ink is skipped anyway then).
    upmOf: *const fn (ptr: *const anyopaque, unified: u16) u16,
    // Ink box in thousandths, y-up, origin-relative [l, b, r, t]; zeros on failure.
    inkThou: *const fn (ptr: *const anyopaque, unified: u16) [4]i32,
};

test "scaffold outlines compiles" {
    try std.testing.expect(true);
}
