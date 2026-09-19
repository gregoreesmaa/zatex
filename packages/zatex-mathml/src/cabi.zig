//! zatex-mathml C ABI: `zatex_mathml_utf8` (moved from the core's
//! `cabi.zig` so the core distribution library stays MathML-free).
//!
//! Reentrant, zero-allocation, caller-owned output buffer. Status
//! codes mirror the core's integer-for-integer (`STATUS_*` below must
//! match `packages/zatex/src/cabi.zig`); `toStatus` maps `LayoutError`
//! the same way.
const std = @import("std");
const zatex = @import("zatex");
const mathml_mod = @import("mathml.zig");

/// Must match `zatex_mathml.h` and the core's `cabi.zig` values.
pub const STATUS_OK: i32 = 0;
pub const STATUS_UNSUPPORTED: i32 = 1;
pub const STATUS_INVALID: i32 = 2;
pub const STATUS_TOO_DEEP: i32 = 3;
pub const STATUS_TOO_LONG: i32 = 4;
pub const STATUS_EXPANSION_LIMIT: i32 = 5;
pub const STATUS_NO_SPACE: i32 = 6;

fn toStatus(e: zatex.LayoutError) i32 {
    return switch (e) {
        error.Unsupported => STATUS_UNSUPPORTED,
        error.Invalid => STATUS_INVALID,
        error.TooDeep => STATUS_TOO_DEEP,
        error.TooLong => STATUS_TOO_LONG,
        error.ExpansionLimit => STATUS_EXPANSION_LIMIT,
        error.NoSpace => STATUS_NO_SPACE,
        error.OutOfMemory => STATUS_NO_SPACE,
    };
}

/// MathML Core serialization into caller-owned `out`. Returns the
/// byte count, or a negative status on error.
export fn zatex_mathml_utf8(
    src_ptr: ?[*]const u8,
    src_len: usize,
    display_mode: bool,
    out_ptr: ?[*]u8,
    out_cap: usize,
) isize {
    const out = (out_ptr orelse return -STATUS_NO_SPACE)[0..out_cap];
    if (src_len > zatex.max_input_len) return -STATUS_TOO_LONG;
    const src = (src_ptr orelse return -STATUS_NO_SPACE)[0..src_len];
    const s = mathml_mod.render(src, .{ .display_mode = display_mode }, out) catch |e| return -toStatus(e);
    return @intCast(s.len);
}

test "cabi mathml truncates with negative NoSpace" {
    var tiny: [8]u8 = undefined;
    const src = "\\frac{a}{b}";
    const n = zatex_mathml_utf8(src.ptr, src.len, false, &tiny, tiny.len);
    try std.testing.expectEqual(-STATUS_NO_SPACE, n);
}

test "cabi mathml serializes" {
    var out: [256]u8 = undefined;
    const src = "\\frac12";
    const n = zatex_mathml_utf8(src.ptr, src.len, false, &out, out.len);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, out[0..@intCast(n)], "<mfrac>") != null);
}

test "cabi mathml null and empty buffers fail NoSpace" {
    var out: [256]u8 = undefined;
    const src = "x";
    try std.testing.expectEqual(-STATUS_NO_SPACE, zatex_mathml_utf8(src.ptr, src.len, false, null, 0));
    try std.testing.expectEqual(-STATUS_NO_SPACE, zatex_mathml_utf8(null, src.len, false, &out, out.len));
    try std.testing.expectEqual(-STATUS_NO_SPACE, zatex_mathml_utf8(src.ptr, src.len, false, &out, 0));
}

test "cabi mathml maps every reachable status" {
    var out: [4096]u8 = undefined;
    const ok = "x+\\frac12";
    const n_ok = zatex_mathml_utf8(ok.ptr, ok.len, false, &out, out.len);
    try std.testing.expect(n_ok > 0);
    const bad = "\\nope";
    try std.testing.expectEqual(-STATUS_INVALID, zatex_mathml_utf8(bad.ptr, bad.len, false, &out, out.len));
    var deep: [200]u8 = undefined;
    @memset(&deep, '{');
    try std.testing.expectEqual(-STATUS_TOO_DEEP, zatex_mathml_utf8(&deep, deep.len, false, &out, out.len));
    try std.testing.expectEqual(-STATUS_TOO_LONG, zatex_mathml_utf8(ok.ptr, zatex.max_input_len + 1, false, &out, out.len));
    const loop = "\\def\\a{\\a}\\a";
    try std.testing.expectEqual(-STATUS_EXPANSION_LIMIT, zatex_mathml_utf8(loop.ptr, loop.len, false, &out, out.len));
}

test "cabi mathml display flag selects the block envelope" {
    var out: [512]u8 = undefined;
    const src = "x";
    const n_block = zatex_mathml_utf8(src.ptr, src.len, true, &out, out.len);
    try std.testing.expect(n_block > 0);
    try std.testing.expect(std.mem.indexOf(u8, out[0..@intCast(n_block)], "display=\"block\"") != null);
    const n_inline = zatex_mathml_utf8(src.ptr, src.len, false, &out, out.len);
    try std.testing.expect(n_inline > 0);
    try std.testing.expect(std.mem.indexOf(u8, out[0..@intCast(n_inline)], "display=\"block\"") == null);
}
