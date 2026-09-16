//! Host font plumbing: the vendored fixture stack through core's
//! OpenType reader, answering `MetricsProvider` exactly like the
//! reference host does, plus the backend font handles for drawing.
//!
//! Same input + same font files = byte-identical pixels: advances come
//! from the same `otmath` tables the layout core measured with, so
//! draw positions agree with layout positions by construction.
//!
//! Multi-face (issue #92): one `backend.impl.Font` handle per stack
//! face; runs are split by face at draw time (`faceOf`), so glyphs
//! from any face draw from their own file. Single-file `--font`
//! mode keeps the legacy one-face behavior exactly.
const std = @import("std");
const zatex = @import("zatex");
const otmath = @import("otmath");
const fontstack = @import("fontstack");
const backend = @import("backend.zig");

const contract = zatex.contract;

pub const Font = struct {
    pub const StackFile = struct {
        path: []const u8,
        role: fontstack.Role,
        required: bool = true,
    };

    alloc: std.mem.Allocator,
    bufs: [fontstack.max_faces][]u8 = undefined,
    nbufs: usize = 0,
    stack: fontstack.Stack = .{},
    handles: [fontstack.max_faces]backend.impl.Font = undefined,

    /// Legacy single-file host: the one face answers everything
    /// (the stack fast-paths `nfaces == 1` to the lone face).
    pub fn load(alloc: std.mem.Allocator, path: []const u8) !Font {
        var f = Font{ .alloc = alloc };
        errdefer f.close();
        try f.addFile(path, .lm);
        return f;
    }

    /// Full fixture stack. Required entries must load; optional
    /// ones (system fallback) skip silently.
    pub fn loadStack(alloc: std.mem.Allocator, files: []const StackFile) !Font {
        var f = Font{ .alloc = alloc };
        errdefer f.close();
        for (files) |sf| {
            f.addFile(sf.path, sf.role) catch |e| {
                if (sf.required) return e;
            };
        }
        if (f.stack.nfaces == 0) return error.FontLoad;
        return f;
    }

    fn addFile(self: *Font, path: []const u8, role: fontstack.Role) !void {
        if (self.stack.nfaces >= fontstack.max_faces) return error.FontLoad;
        var threaded = std.Io.Threaded.init(self.alloc, .{});
        defer threaded.deinit();
        const bytes = std.Io.Dir.cwd().readFileAlloc(
            threaded.io(),
            path,
            self.alloc,
            .limited(8 * 1024 * 1024),
        ) catch return error.FontLoad;
        const ot = otmath.load(bytes) catch {
            self.alloc.free(bytes);
            return error.FontLoad;
        };
        var handle = backend.impl.Font.load(self.alloc, path, ot.upm) catch {
            self.alloc.free(bytes);
            return error.FontLoad;
        };
        self.stack.addFile(role, bytes) catch {
            handle.close();
            self.alloc.free(bytes);
            return error.FontLoad;
        };
        self.handles[self.stack.nfaces - 1] = handle;
        self.bufs[self.nbufs] = bytes;
        self.nbufs += 1;
    }

    pub fn close(self: *Font) void {
        for (self.handles[0..self.stack.nfaces]) |*h| h.close();
        for (self.bufs[0..self.nbufs]) |b| self.alloc.free(b);
        self.stack.nfaces = 0;
        self.nbufs = 0;
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
            .inkBounds = ink,
        };
    }

    /// Advance in core thousandths (what layout measured with). The
    /// renderer reuses this to step glyph origins identically.
    pub fn advance1000(self: *const Font, glyph: u16) i32 {
        return self.stack.advance1000(glyph);
    }

    /// Backend handle + face-local gid for a unified gid (run
    /// splitting at draw time). Null when no face owns the id.
    pub fn drawFace(self: *const Font, unified: u16) ?struct {
        handle: *const backend.impl.Font,
        gid: u16,
    } {
        const r = self.stack.faceOf(unified) orelse return null;
        return .{ .handle = &self.handles[r.index], .gid = r.gid };
    }

    /// Ink extents from the owning backend face (core thousandths,
    /// baseline-relative): [height_above, depth_below].
    pub fn extents1000(self: *const Font, glyph: u16) [2]i32 {
        const d = self.drawFace(glyph) orelse return .{ 0, 0 };
        return d.handle.extents1000(d.gid);
    }

    /// True ink box from the owning backend face (v4 hook).
    pub fn inkBounds1000(self: *const Font, glyph: u16) [4]i32 {
        const d = self.drawFace(glyph) orelse return .{ 0, 0, 0, 0 };
        return d.handle.inkBounds1000(d.gid);
    }

    fn gid(ctx: *const anyopaque, font_id: u16, cp: u21) u16 {
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.stack.glyphIdFor(font_id, cp);
    }

    fn adv(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.advance1000(glyph);
    }

    fn rule(ctx: *const anyopaque, font_id: u16, kind: contract.RuleKind) i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.stack.ruleFor(kind);
    }

    fn variant(ctx: *const anyopaque, font_id: u16, glyph: u16, min_height: i32) u16 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.stack.variantFor(glyph, min_height);
    }

    fn italic(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.stack.italicFor(glyph);
    }

    fn ext(ctx: *const anyopaque, font_id: u16, glyph: u16) [2]i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.extents1000(glyph);
    }

    fn ink(ctx: *const anyopaque, font_id: u16, glyph: u16) [4]i32 {
        _ = font_id;
        const self: *const Font = @ptrCast(@alignCast(ctx));
        return self.inkBounds1000(glyph);
    }
};

// ---------------------------------------------------------------------------
// Tests: multi-face demux (issue #92) over the absolute fixture dir.
// ---------------------------------------------------------------------------

test "stack demux routes each glyph to its owning face" {
    const dir = std.fs.path.dirname(@import("build_options").fixture_font) orelse ".";
    var p0: [1024]u8 = undefined;
    var p1: [1024]u8 = undefined;
    var p2: [1024]u8 = undefined;
    const lm = try std.fmt.bufPrint(&p0, "{s}/latinmodern-math.otf", .{dir});
    const ams = try std.fmt.bufPrint(&p1, "{s}/katex/KaTeX_AMS-Regular.otf", .{dir});
    const bold = try std.fmt.bufPrint(&p2, "{s}/katex/KaTeX_Main-Bold.otf", .{dir});
    const alloc = std.testing.allocator;
    var font = try Font.loadStack(alloc, &.{
        .{ .path = lm, .role = .lm },
        .{ .path = ams, .role = .ams },
        .{ .path = bold, .role = .main_bold },
    });
    defer font.close();
    const prov = font.provider();
    // rm 'A' stays on face 0 (LM); the AMS star demuxes to face 1
    // with a drawable, nonzero-ink outline (the #92 acceptance at
    // unit level: the glyph both resolves AND draws).
    const a = prov.glyphId(prov.ctx, 0, 'A');
    try std.testing.expect(a != 0);
    const da = font.drawFace(a) orelse return error.TestUnexpectedResult;
    try std.testing.expect(da.handle == &font.handles[0]);
    const star = prov.glyphId(prov.ctx, 0, 0x2605);
    try std.testing.expect(star != 0);
    const ds = font.drawFace(star) orelse return error.TestUnexpectedResult;
    try std.testing.expect(ds.handle == &font.handles[1]);
    const ink = ds.handle.inkBounds1000(ds.gid);
    try std.testing.expect(ink[2] > ink[0] and ink[3] > ink[1]);
    try std.testing.expect(font.advance1000(star) > 0);
    // Bold 'A' draws from the Main-Bold face (issue #95).
    const ab = prov.glyphId(prov.ctx, 2, 'A');
    try std.testing.expect(ab != 0);
    const db = font.drawFace(ab) orelse return error.TestUnexpectedResult;
    try std.testing.expect(db.handle == &font.handles[2]);
}
