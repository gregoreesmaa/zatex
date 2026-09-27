//! SVG emitter: geometric walker over `zatex.ir.Layout`.
// Scaffold: replaced by Tasks 2-4.
const std = @import("std");
const zatex = @import("zatex");
const cff = @import("cff");
const outlines_mod = @import("outlines.zig");

// Scaffold: replaced by Tasks 2-4.
pub fn renderLayout(
    layout: zatex.ir.Layout,
    ol: outlines_mod.Outlines,
    segs: []cff.Seg,
    out: []u8,
) zatex.LayoutError![]u8 {
    _ = layout;
    _ = ol;
    _ = segs;
    _ = out;
    return error.NoSpace;
}

// Scaffold: replaced by Tasks 2-4.
pub fn render(
    source: []const u8,
    options: zatex.LayoutOptions,
    prov: zatex.MetricsProvider,
    ol: outlines_mod.Outlines,
    runs: []zatex.ir.Run,
    rules: []zatex.ir.Rule,
    glyphs: []u16,
    segs: []cff.Seg,
    out: []u8,
    diag: *zatex.Diag,
) zatex.LayoutError![]u8 {
    _ = source;
    _ = options;
    _ = prov;
    _ = ol;
    _ = runs;
    _ = rules;
    _ = glyphs;
    _ = segs;
    _ = out;
    _ = diag;
    return error.NoSpace;
}

/// Fixed-precision buffer writer (mathml `Writer` shape, extended
/// with `num`/`hexColor`/`opacity`). Zero allocation; any write past
/// the buffer sets `overflow` and stops (surfaces as `error.NoSpace`).
const W = struct {
    buf: []u8,
    pos: usize = 0,
    overflow: bool = false,

    fn str(self: *W, s: []const u8) void {
        if (self.overflow) return;
        if (self.pos + s.len > self.buf.len) {
            self.overflow = true;
            return;
        }
        @memcpy(self.buf[self.pos .. self.pos + s.len], s);
        self.pos += s.len;
    }

    fn byte(self: *W, c: u8) void {
        if (self.overflow) return;
        if (self.pos + 1 > self.buf.len) {
            self.overflow = true;
            return;
        }
        self.buf[self.pos] = c;
        self.pos += 1;
    }

    fn uint(self: *W, v: u32) void {
        self.uint64(v);
    }

    fn int(self: *W, v: i32) void {
        if (v < 0) {
            self.byte('-');
            self.uint64(@as(u64, @intCast(-(@as(i64, v)))));
        } else {
            self.uint64(@as(u64, @intCast(v)));
        }
    }

    fn uint64(self: *W, v: u64) void {
        if (v == 0) {
            self.byte('0');
            return;
        }
        var tmp: [20]u8 = undefined;
        var n: usize = 0;
        var x = v;
        while (x > 0) : (n += 1) {
            tmp[n] = '0' + @as(u8, @intCast(x % 10));
            x /= 10;
        }
        while (n > 0) : (n -= 1) self.byte(tmp[n - 1]);
    }

    /// Fixed 2-decimal float: `q = round_half_away(v * 100)` over
    /// integers, trailing zeros stripped, `-0` → `0`. Never
    /// `std.fmt` floats (determinism per Global Constraints).
    fn num(self: *W, v: f64) void {
        if (self.overflow) return;
        if (!std.math.isFinite(v)) {
            self.overflow = true;
            return;
        }
        const scaled = v * 100.0;
        if (!(scaled > -9223372036854775808.0 and scaled < 9223372036854775808.0)) {
            self.overflow = true;
            return;
        }
        const q: i64 = @intFromFloat(@round(scaled));
        const neg = q < 0;
        // Avoid negating minInt (UB in safe modes).
        const mag: u64 = if (neg) @as(u64, @intCast(-(q + 1))) + 1 else @as(u64, @intCast(q));
        const int_part = mag / 100;
        const frac: u8 = @intCast(mag % 100);
        if (neg) self.byte('-');
        self.uint64(int_part);
        if (frac != 0) {
            self.byte('.');
            self.byte('0' + @as(u8, @intCast(frac / 10)));
            if (frac % 10 != 0) self.byte('0' + @as(u8, @intCast(frac % 10)));
        }
    }

    /// `#` + 6 lowercase hex nibbles.
    fn hexColor(self: *W, rgb: u24) void {
        self.byte('#');
        const v: u32 = rgb;
        var shift: u5 = 20;
        while (true) {
            const nibble: u8 = @intCast((v >> shift) & 0xF);
            self.byte(if (nibble < 10) '0' + nibble else 'a' + (nibble - 10));
            if (shift == 0) break;
            shift -= 4;
        }
    }

    /// Alpha byte as `num(a / 255)`.
    fn opacity(self: *W, a: u8) void {
        self.num(@as(f64, @floatFromInt(a)) / 255.0);
    }

    /// `<svg … viewBox="minX 0 totalW totalH" width="w_em em" …>` open tag.
    /// Width/height arrive as `units / 1000` through `num`.
    fn skeletonHead(self: *W, minX: i32, totalW: i32, totalH: i32, w_em: f64, h_em: f64) void {
        self.str("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"");
        self.int(minX);
        self.str(" 0 ");
        self.int(totalW);
        self.byte(' ');
        self.int(totalH);
        self.str("\" width=\"");
        self.num(w_em);
        self.str("em\" height=\"");
        self.num(h_em);
        self.str("em\">");
    }

    fn done(self: *W) []const u8 {
        return self.buf[0..self.pos];
    }
};

/// Split paint: `0xRRGGBBAA`; null is ambient black ink.
const Paint = struct {
    rgb: u24,
    a: u8,
};

fn paintOf(color: ?u32) Paint {
    const c = color orelse return .{ .rgb = 0x000000, .a = 0xFF };
    return .{ .rgb = @intCast(c >> 8), .a = @intCast(c & 0xFF) };
}

test "scaffold svg compiles" {
    try std.testing.expect(true);
}

test "num formats fixed 2-decimal stripped" {
    var buf: [64]u8 = undefined;
    var w = W{ .buf = &buf };
    w.num(1.0); w.byte(' ');
    w.num(1.5); w.byte(' ');
    w.num(0.125); w.byte(' '); // exact-binary half: half away → 0.13
    w.num(1.006); w.byte(' '); // → 1.01
    w.num(-0.001); w.byte(' '); // → 0
    w.num(123.456); // → 123.46
    try std.testing.expect(!w.overflow);
    try std.testing.expectEqualStrings("1 1.5 0.13 1.01 0 123.46", w.done());
}

test "skeleton wraps body with integer viewBox" {
    // head(minX, totalW, totalH, w_em, h_em) then body then "</svg>"
    var buf: [256]u8 = undefined;
    var w = W{ .buf = &buf };
    w.skeletonHead(-550, 1050, 900, 1.05, 0.9);
    w.str("<rect/>");
    w.str("</svg>");
    try std.testing.expectEqualStrings(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-550 0 1050 900\" width=\"1.05em\" height=\"0.9em\"><rect/></svg>",
        w.done());
}

test "paintOf splits color and defaults null to black" {
    const ambient = paintOf(null);
    try std.testing.expectEqual(@as(u24, 0x000000), ambient.rgb);
    try std.testing.expectEqual(@as(u8, 0xFF), ambient.a);
    const red = paintOf(0xFF0000FF);
    try std.testing.expectEqual(@as(u24, 0xFF0000), red.rgb);
    try std.testing.expectEqual(@as(u8, 0xFF), red.a);
    const green_half = paintOf(0x00FF0080);
    try std.testing.expectEqual(@as(u24, 0x00FF00), green_half.rgb);
    try std.testing.expectEqual(@as(u8, 0x80), green_half.a);
}

test "hexColor opacity and overflow stop" {
    var buf: [32]u8 = undefined;
    var w = W{ .buf = &buf };
    w.hexColor(0xFF0000);
    w.byte(' ');
    w.hexColor(0x00ff80);
    w.byte(' ');
    w.opacity(0xFF);
    w.byte(' ');
    w.opacity(0x80);
    w.byte(' ');
    w.opacity(0x00);
    try std.testing.expect(!w.overflow);
    try std.testing.expectEqualStrings("#ff0000 #00ff80 1 0.5 0", w.done());

    var tiny: [3]u8 = undefined;
    var o = W{ .buf = &tiny };
    o.str("ab");
    o.str("cd"); // 2 + 2 > 3 → overflow, nothing written
    try std.testing.expect(o.overflow);
    o.str("more"); // stuck: further writes are no-ops
    try std.testing.expectEqualStrings("ab", o.done());
}
