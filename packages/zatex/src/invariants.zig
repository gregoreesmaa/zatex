//! Shared layout-invariant helpers for QA probes (issues #23, #24).
//!
//! Test-side only (never imported by the core): small, total,
//! allocation-free checks over `ir.Layout` plus a canonical IR text
//! dump for byte-level determinism compares. Both the reference-host
//! metamorphic probes (`refhost.zig`) and the grammar fuzzer
//! (`fuzz.zig`) assert through these instead of redefining them.
const std = @import("std");
const zatex = @import("zatex");
const ir = zatex.ir;

/// Every scalar is non-negative and every mark has positive extent.
pub fn expectNonNegative(l: ir.Layout) !void {
    try std.testing.expect(l.width >= 0);
    try std.testing.expect(l.height_above >= 0);
    try std.testing.expect(l.depth_below >= 0);
    for (l.runs) |r| {
        try std.testing.expect(r.x >= 0);
        try std.testing.expect(r.baseline_y >= 0);
        try std.testing.expect(r.glyphs.len > 0);
    }
    for (l.rules) |r| {
        try std.testing.expect(r.x >= 0);
        try std.testing.expect(r.y >= 0);
        try std.testing.expect(r.w > 0);
        try std.testing.expect(r.h > 0);
    }
}

/// Every run baseline and rule rect lands inside the ink box
/// `[0, height_above + depth_below]`.
pub fn expectContained(l: ir.Layout) !void {
    const total: i64 = @as(i64, l.height_above) + @as(i64, l.depth_below);
    for (l.runs) |r| {
        try std.testing.expect(r.baseline_y >= 0 and r.baseline_y <= total);
    }
    for (l.rules) |r| {
        try std.testing.expect(r.y >= 0 and @as(i64, r.y) + @as(i64, r.h) <= total);
    }
}

/// Byte-level determinism: same input + same metrics = same layout.
pub fn expectSameLayout(a: ir.Layout, b: ir.Layout) !void {
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.height_above, b.height_above);
    try std.testing.expectEqual(a.depth_below, b.depth_below);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    try std.testing.expectEqual(a.rules.len, b.rules.len);
    for (a.runs, b.runs) |x, y| {
        try std.testing.expectEqual(x.font_id, y.font_id);
        try std.testing.expectEqual(x.size_units, y.size_units);
        try std.testing.expectEqual(x.x, y.x);
        try std.testing.expectEqual(x.baseline_y, y.baseline_y);
        try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
    }
    for (a.rules, b.rules) |x, y| try std.testing.expectEqual(x, y);
}

/// Nesting never shrinks the ink box (wrapping `small` yields `big`).
pub fn expectGrowsOrEqual(small: ir.Layout, big: ir.Layout) !void {
    try std.testing.expect(big.width >= small.width);
    const st: i64 = @as(i64, small.height_above) + @as(i64, small.depth_below);
    const bt: i64 = @as(i64, big.height_above) + @as(i64, big.depth_below);
    try std.testing.expect(bt >= st);
}

/// Canonical IR text: `w/ha/db` then runs then rules. Bounded and
/// total over caller `out`; truncates with a `...` marker (still
/// deterministic, so truncated compares stay meaningful).
pub fn layoutText(l: ir.Layout, out: []u8) []u8 {
    var f = Fmt{ .buf = out };
    f.int(@as(i64, l.width));
    f.ch('/');
    f.int(@as(i64, l.height_above));
    f.ch('/');
    f.int(@as(i64, l.depth_below));
    f.ch('|');
    for (l.runs) |r| {
        f.int(r.font_id);
        f.ch(',');
        f.int(r.size_units);
        f.ch(',');
        f.int(@as(i64, r.x));
        f.ch(',');
        f.int(@as(i64, r.baseline_y));
        f.ch(':');
        for (r.glyphs) |g| {
            f.int(g);
            f.ch('.');
        }
        f.ch(';');
    }
    f.ch('|');
    for (l.rules) |r| {
        f.int(@as(i64, r.x));
        f.ch(',');
        f.int(@as(i64, r.y));
        f.ch(',');
        f.int(@as(i64, r.w));
        f.ch(',');
        f.int(@as(i64, r.h));
        f.ch(';');
    }
    if (f.trunc and f.pos >= 3) @memcpy(out[f.pos - 3 ..][0..3], "...");
    return out[0..f.pos];
}

/// Geometry identity: same ink-box footprint (width, height, depth).
/// Wrappers that emit nothing (`\phantom`) legitimately change the run
/// list while the footprint must not (issue #40: phantom width
/// preservation, color invariance at the geometry level).
pub fn expectSameFootprint(a: ir.Layout, b: ir.Layout) !void {
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.height_above, b.height_above);
    try std.testing.expectEqual(a.depth_below, b.depth_below);
}

/// Geometry identity: same ink box, same run/rule geometry, paint
/// ignored. `\\color` scopes paint runs without moving them (issue
/// #35) while `expectSameLayout` compares paint too, so color
/// invariance (issue #40) asserts through here: geometry must match
/// exactly while the paint assertions live next to it (never vacuous).
pub fn expectSameGeometry(a: ir.Layout, b: ir.Layout) !void {
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.height_above, b.height_above);
    try std.testing.expectEqual(a.depth_below, b.depth_below);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    try std.testing.expectEqual(a.rules.len, b.rules.len);
    for (a.runs, b.runs) |x, y| {
        try std.testing.expectEqual(x.font_id, y.font_id);
        try std.testing.expectEqual(x.size_units, y.size_units);
        try std.testing.expectEqual(x.x, y.x);
        try std.testing.expectEqual(x.baseline_y, y.baseline_y);
        try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
    }
    for (a.rules, b.rules) |x, y| {
        try std.testing.expectEqual(x.x, y.x);
        try std.testing.expectEqual(x.y, y.y);
        try std.testing.expectEqual(x.w, y.w);
        try std.testing.expectEqual(x.h, y.h);
    }
}

/// Canonical-dump identity: the `layoutText` bytes must match exactly.
/// Same relation as `expectSameLayout`, asserted through the shared
/// text dump (issue #40: color invariance via the canonical IR dump).
pub fn expectSameDump(a: ir.Layout, b: ir.Layout, bufa: []u8, bufb: []u8) !void {
    const ta = layoutText(a, bufa);
    const tb = layoutText(b, bufb);
    try std.testing.expectEqualStrings(ta, tb);
}

const Fmt = struct {
    buf: []u8,
    pos: usize = 0,
    trunc: bool = false,

    fn ch(self: *Fmt, c: u8) void {
        if (self.pos >= self.buf.len) {
            self.trunc = true;
            return;
        }
        self.buf[self.pos] = c;
        self.pos += 1;
    }

    fn int(self: *Fmt, v: i64) void {
        if (v < 0) {
            self.ch('-');
            self.uint(@as(u64, @intCast(-v)));
        } else {
            self.uint(@as(u64, @intCast(v)));
        }
    }

    fn uint(self: *Fmt, v: u64) void {
        var tmp: [20]u8 = undefined;
        var n: usize = 0;
        var x = v;
        if (x == 0) {
            self.ch('0');
            return;
        }
        while (x > 0) : (n += 1) {
            tmp[n] = '0' + @as(u8, @intCast(x % 10));
            x /= 10;
        }
        while (n > 0) : (n -= 1) self.ch(tmp[n - 1]);
    }
};

test "ir text is canonical and bounded" {
    const runs = [_]ir.Run{.{
        .font_id = 1,
        .size_units = 1000,
        .x = 10,
        .baseline_y = 700,
        .glyphs = &[_]u16{ 89, 50 },
    }};
    const l = ir.Layout{
        .width = 1000,
        .height_above = 700,
        .depth_below = 250,
        .runs = &runs,
        .rules = &.{},
    };
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("1000/700/250|1,1000,10,700:89.50.;|", layoutText(l, &buf));
    var tiny: [8]u8 = undefined;
    const t = layoutText(l, &tiny);
    try std.testing.expectEqual(@as(usize, 8), t.len);
    try std.testing.expect(std.mem.endsWith(u8, t, "..."));
}
