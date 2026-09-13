//! Host font plumbing: the pinned fixture font through core's
//! OpenType reader, answering `MetricsProvider` exactly like the
//! reference host does, plus the backend font handle for drawing.
//!
//! Same input + same font file = byte-identical pixels: advances come
//! from the same `otmath` tables the layout core measured with, so
//! draw positions agree with layout positions by construction.
const std = @import("std");
const zatex = @import("zatex");
const otmath = @import("otmath");
const backend = @import("backend.zig");

const contract = zatex.contract;

pub const Font = struct {
    bytes: []u8,
    ot: otmath.Font,
    handle: backend.impl.Font,
    alloc: std.mem.Allocator,

    /// Load a font file (the pinned fixture in CI). Caller owns the
    /// bytes via `close`.
    pub fn load(alloc: std.mem.Allocator, path: []const u8) !Font {
        var threaded = std.Io.Threaded.init(alloc, .{});
        defer threaded.deinit();
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            threaded.io(),
            path,
            alloc,
            .limited(8 * 1024 * 1024),
        );
        errdefer alloc.free(bytes);
        const ot = try otmath.load(bytes);
        const handle = try backend.impl.Font.load(alloc, path, ot.upm);
        return .{ .bytes = bytes, .ot = ot, .handle = handle, .alloc = alloc };
    }

    pub fn close(self: *Font) void {
        self.handle.close();
        self.alloc.free(self.bytes);
    }

    fn scale1000(self: *const Font, v: i32) i32 {
        return @divTrunc(v * 1000, self.ot.upm);
    }

    pub fn provider(self: *Font) contract.MetricsProvider {
        return .{
            .ctx = @ptrCast(self),
            .glyphId = gid,
            .advance = adv,
            .ruleThickness = rule,
            .extents = ext,
            .glyphVariant = variant,
            .italicCorrection = italic,
        };
    }

    /// Advance in core thousandths (what layout measured with). The
    /// renderer reuses this to step glyph origins identically.
    pub fn advance1000(self: *const Font, glyph: u16) i32 {
        const a = otmath.advance(self.ot, glyph) catch 500;
        return self.scale1000(a);
    }

    fn gid(ctx: *const anyopaque, font_id: u16, cp: u21) u16 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return otmath.glyphId(self.ot, cp) catch 0;
    }

    fn adv(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.advance1000(glyph);
    }

    fn rule(ctx: *const anyopaque, font_id: u16, kind: contract.RuleKind) i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        const c: otmath.Const = switch (kind) {
            .fraction_bar => .frac_rule,
            .radical => .radical_rule,
            .overline => .overbar_rule,
            .underline => .underbar_rule,
        };
        const v = otmath.constant(self.ot, c) catch 40;
        const s = self.scale1000(v);
        return if (s <= 0) 40 else s;
    }

    fn variant(ctx: *const anyopaque, font_id: u16, glyph: u16, min_height: i32) u16 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        const need = @divTrunc(min_height * self.ot.upm, 1000);
        return otmath.vertVariant(self.ot, glyph, need) catch glyph;
    }

    fn italic(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        const v = otmath.italicCorrection(self.ot, glyph) catch 0;
        return self.scale1000(v);
    }

    /// Ink extents from the backend (core thousandths,
    /// baseline-relative): [height_above, depth_below].
    fn ext(ctx: *const anyopaque, font_id: u16, glyph: u16) [2]i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.handle.extents1000(glyph);
    }
};
