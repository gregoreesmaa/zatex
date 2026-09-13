//! Pure-Zig software backend: the portable endgame for every OS
//! without a native text stack. Glyph outlines come from the font file
//! itself (`sw_font.zig`: CFF/Type2 interpreter), coverage from a
//! scanline rasterizer (`sw_raster.zig`), PNG from `std.compress.flate`
//! (`sw_png.zig`). Zero host dependencies beyond libc (for `malloc`,
//! already linked): no FreeType, no fontconfig, no DirectWrite.
//!
//! Canvas convention matches the interface: caller floats in pixels,
//! origin bottom-left, y-up. CFF outlines are natively y-up, so glyph
//! origins map directly (the core-to-canvas flip still lives in
//! portable `render.zig`, which feeds this backend bottom-left
//! coordinates like every other backend).
const std = @import("std");
const sw_font = @import("sw_font.zig");
const sw_raster = @import("sw_raster.zig");
const sw_png = @import("sw_png.zig");

/// Segments reused across glyphs of one canvas (sized so the fixture's
/// worst glyph fits several times over; overflow blanks that glyph).
const SCRATCH_SEGS = 8192;
/// Flattened lines per glyph draw (same policy as segments).
const SCRATCH_LINES = 16384;

pub const Font = struct {
    alloc: std.mem.Allocator,
    bytes: []u8,
    cff: sw_font.CffFont,
    upm: u16,

    /// Open the font file for drawing. Advances still come from the
    /// portable `otmath` reader in `font.zig`; this handle draws glyphs
    /// and reports ink boxes from the same file's CFF outlines.
    pub fn load(alloc: std.mem.Allocator, path: []const u8, upm: u16) error{ FontLoad, OutOfMemory }!Font {
        var threaded = std.Io.Threaded.init(alloc, .{});
        defer threaded.deinit();
        const bytes = std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(32 * 1024 * 1024)) catch return error.FontLoad;
        errdefer alloc.free(bytes);
        const cff = sw_font.load(bytes) catch return error.FontLoad;
        return .{ .alloc = alloc, .bytes = bytes, .cff = cff, .upm = upm };
    }

    pub fn close(self: *Font) void {
        self.alloc.free(self.bytes);
    }

    /// True ink extents from CFF outlines, scaled to core thousandths:
    /// [height_above, depth_below]. Blank or undecodable glyphs report
    /// [0, 0] (the rasterizer blanks them identically, so layout and
    /// pixels stay consistent with each other).
    pub fn extents1000(self: *const Font, glyph: u16) [2]i32 {
        var scratch: [512]sw_font.Seg = undefined;
        const bb = sw_font.outlineBbox(&self.cff, glyph, &scratch) catch return .{ 0, 0 };
        const b = bb orelse return .{ 0, 0 };
        const top = b[3];
        const bot = b[1];
        const ha: i32 = if (top <= 0) 0 else self.scale1000(@intFromFloat(@ceil(top)));
        const db: i32 = if (bot >= 0) 0 else self.scale1000(@intFromFloat(@ceil(-bot)));
        return .{ ha, db };
    }

    fn scale1000(self: *const Font, v: i32) i32 {
        return @divTrunc(v * 1000, self.upm);
    }
};

pub const Canvas = struct {
    alloc: std.mem.Allocator,
    w: usize,
    h: usize,
    pixels: []u8, // top-left row-major RGBA
    fill: sw_raster.Color,
    segs: []sw_font.Seg,
    lines: []sw_raster.Line,
    row_cov: []f32,

    pub fn create(w: usize, h: usize) error{RenderInit}!Canvas {
        const alloc = std.heap.c_allocator;
        const pixels = alloc.alloc(u8, w * h * 4) catch return error.RenderInit;
        @memset(pixels, 255);
        errdefer alloc.free(pixels);
        const segs = alloc.alloc(sw_font.Seg, SCRATCH_SEGS) catch return error.RenderInit;
        errdefer alloc.free(segs);
        const lines = alloc.alloc(sw_raster.Line, SCRATCH_LINES) catch return error.RenderInit;
        errdefer alloc.free(lines);
        const row_cov = alloc.alloc(f32, w) catch return error.RenderInit;
        return .{
            .alloc = alloc,
            .w = w,
            .h = h,
            .pixels = pixels,
            .fill = sw_raster.black,
            .segs = segs,
            .lines = lines,
            .row_cov = row_cov,
        };
    }

    pub fn close(self: *Canvas) void {
        self.alloc.free(self.pixels);
        self.alloc.free(self.segs);
        self.alloc.free(self.lines);
        self.alloc.free(self.row_cov);
    }

    pub fn setFill(self: *Canvas, r: f64, g: f64, b: f64, a: f64) void {
        self.fill = .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fillRect(self: *Canvas, x: f64, y: f64, w: f64, h: f64) void {
        sw_raster.fillRect(self.pixels, self.w, self.h, x, y, w, h, self.fill);
    }

    pub fn beginRun(self: *Canvas, font: *const Font, size_px: f64) error{RenderInit}!Run {
        return .{ .canvas = self, .font = font, .size_px = size_px };
    }

    /// Write the canvas as 8-bit RGBA PNG to `out_path`.
    pub fn writePng(self: *Canvas, out_path: []const u8) error{PngWrite}!void {
        sw_png.writeRgba(self.alloc, out_path, self.w, self.h, self.pixels) catch return error.PngWrite;
    }
};

pub const Run = struct {
    canvas: *Canvas,
    font: *const Font,
    size_px: f64,

    pub fn drawGlyph(self: *Run, glyph: u16, x: f64, y: f64) void {
        const c = self.canvas;
        const scale = self.size_px / @as(f64, @floatFromInt(self.font.upm));
        if (scale <= 0) return;
        const segs = sw_font.outline(&self.font.cff, glyph, c.segs) catch return;
        if (segs.len == 0) return;
        const lines = sw_raster.flatten(segs, scale, x, y, c.lines);
        sw_raster.fillLines(c.pixels, c.w, c.h, lines, c.fill, c.row_cov);
    }

    pub fn end(self: *Run) void {
        _ = self;
    }
};

/// Fixture bytes for tests: `@embedFile` cannot leave the package and
/// the test runner makes no CWD promise, so tests read the vendored
/// fixture through the build-provided absolute path.
pub fn fixtureBytes(alloc: std.mem.Allocator) ![]u8 {
    const path = @import("build_options").fixture_font;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(32 * 1024 * 1024));
}

// extents1000 uses a 512-segment stack scratch: assert every fixture
// glyph's outline fits, so layout never silently shrinks a glyph whose
// rasterizer drew it fully.
test "512 outline segments hold every fixture glyph" {
    const alloc = std.testing.allocator;
    const bytes = try fixtureBytes(alloc);
    defer alloc.free(bytes);
    const cff = try sw_font.load(bytes);
    var scratch: [512]sw_font.Seg = undefined;
    var big: [8192]sw_font.Seg = undefined;
    var g: usize = 0;
    while (g < cff.num_glyphs) : (g += 1) {
        const full = sw_font.outline(&cff, @intCast(g), &big) catch continue;
        if (full.len > 512) std.debug.print("glyph {d} needs {d} segs\n", .{ g, full.len });
        try std.testing.expect(full.len <= 512);
        _ = try sw_font.outlineBbox(&cff, @intCast(g), &scratch);
    }
}

test "software extents agree with CoreText ink boxes" {
    // Host-only cross-check (CoreText exists only on Apple targets):
    // any systematic disagreement here shifts LAYOUT, not just pixels,
    // so investigate rather than tolerate. Skipped off-mac; the
    // dimension-equality corpus re-render covers determinism there.
    // The cg import lives inside the comptime branch so foreign test
    // binaries never reference CoreText symbols.
    if (comptime @import("builtin").os.tag != .macos) return error.SkipZigTest;
    if (comptime @import("builtin").os.tag == .macos) {
        const cg = @import("cg_backend.zig");
        const alloc = std.testing.allocator;
        const path = @import("build_options").fixture_font;
        var sw = try Font.load(alloc, path, 1000);
        defer sw.close();
        var cgf = try cg.Font.load(alloc, path, 1000);
        defer cgf.close();
        var worst_glyph: u16 = 0;
        var worst: i32 = 0;
        var over2: usize = 0;
        var g: u32 = 0;
        while (g < 4802) : (g += 1) {
            const glyph: u16 = @intCast(g);
            const a = sw.extents1000(glyph);
            const b = cgf.extents1000(glyph);
            const d0 = a[0] - b[0];
            const d1 = a[1] - b[1];
            const d: i32 = @max(if (d0 < 0) -d0 else d0, if (d1 < 0) -d1 else d1);
            if (d > worst) {
                worst = d;
                worst_glyph = glyph;
            }
            if (d > 2) over2 += 1;
        }
        std.debug.print("sw-vs-coretext extents: worst={d} (glyph {d}), rows>2: {d}/4802\n", .{ worst, worst_glyph, over2 });
        try std.testing.expect(over2 == 0);
    }
}
