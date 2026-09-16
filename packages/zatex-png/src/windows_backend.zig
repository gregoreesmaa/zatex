//! Windows backend: native GDI rasterizer under `-Dbackend=native`,
//! portable software rasterizer otherwise (the default).
//!
//! Native-vs-software tradeoff (issues #64/#67), decided here:
//! - DirectWrite (`IDWriteFactory` shaping/measurement/rasterization)
//!   is the modern native stack, but every entry point sits behind COM
//!   vtables whose slot order cannot be verified without a Windows
//!   runner (CI has none — not even cross-execution). A mistranscribed
//!   slot is a silent crash, so DirectWrite stays future work until a
//!   Windows runner lands (the showcase workflow, issue #66, is shaped
//!   to add one).
//! - GDI (`AddFontResourceExW` + `GetGlyphOutlineW`) is a flat C ABI,
//!   stable since Windows NT, cross-linkable from any host, with
//!   per-glyph advances, ink boxes and 64-level coverage bitmaps —
//!   everything the `Backend` interface needs. The issue itself names
//!   GDI/Uniscribe as the legacy-fallback camp; this backend is that
//!   camp, made explicit and tested.
//! - The deterministic software backend stays the default: GDI coverage
//!   varies with the system rasterizer, so native pixels are triage /
//!   showcase material, never gates (AGENTS.md section 4).
//!
//! Split of duties (same as the CoreGraphics backend): advances and
//! glyph ids stay with `otmath` (shared in `font.zig`, so layout pen
//! positions are backend-independent); GDI serves ink extents plus
//! pixels. `extents1000`/`inkBounds1000` come from `GGO_METRICS` at a
//! selected size of one em, so device units equal font units. Runs
//! select a per-size font (created in `beginRun`, destroyed in `end`);
//! layout-time metrics use the one-em font selected at load.
//! Horizontal raster stretch (`x_scale`, wide accents / brace spans)
//! has no GDI equivalent per glyph, so the blit nearest-neighbour
//! scales coverage horizontally — deterministic, slightly softer than
//! the software backend on stretched runs only.
const std = @import("std");
const builtin = @import("builtin");
const sw = @import("sw_backend.zig");
const build_options = @import("build_options");

const native_active = std.mem.eql(u8, build_options.backend, "native");
const on_windows = builtin.os.tag == .windows;

pub const Font = if (!native_active) sw.Font else GdiFont;
pub const Canvas = if (!native_active) sw.Canvas else GdiCanvas;
pub const Run = if (!native_active) sw.Run else GdiRun;

// ---------------------------------------------------------------------------
// GDI32 surface (flat C ABI; linkable cross-platform via mingw import
// libs — no SDK needed, which is what keeps the `software` backend's
// zero-host-dependency cross-compile story intact for this file too).
// ---------------------------------------------------------------------------

const HDC = ?*anyopaque;
const HFONT = ?*anyopaque;
const HGDIOBJ = ?*anyopaque;

const POINT = extern struct { x: i32, y: i32 };
const FIXED = extern struct { fract: u16, value: i16 };
const MAT2 = extern struct { eM11: FIXED, eM12: FIXED, eM21: FIXED, eM22: FIXED };
const mat2_identity = MAT2{
    .eM11 = .{ .fract = 0, .value = 1 },
    .eM12 = .{ .fract = 0, .value = 0 },
    .eM21 = .{ .fract = 0, .value = 0 },
    .eM22 = .{ .fract = 0, .value = 1 },
};
const GLYPHMETRICS = extern struct {
    blackBoxX: u32,
    blackBoxY: u32,
    ptGlyphOrigin: POINT,
    cellIncX: i16,
    cellIncY: i16,
};
const LOGFONTW = extern struct {
    lfHeight: i32 = 0,
    lfWidth: i32 = 0,
    lfEscapement: i32 = 0,
    lfOrientation: i32 = 0,
    lfWeight: i32 = 400,
    lfItalic: u8 = 0,
    lfUnderline: u8 = 0,
    lfStrikeOut: u8 = 0,
    lfCharSet: u8 = 1, // DEFAULT_CHARSET: GDI maps Unicode itself.
    lfOutPrecision: u8 = 0,
    lfClipPrecision: u8 = 0,
    lfQuality: u8 = 4, // ANTIALIASED_QUALITY: full gray levels below.
    lfPitchAndFamily: u8 = 0,
    lfFaceName: [32]u16 = [_]u16{0} ** 32,
};

const FR_PRIVATE: u32 = 0x10;
const GGO_METRICS: u32 = 0;
const GGO_GRAY8_BITMAP: u32 = 6;
const GGO_GLYPH_INDEX: u32 = 0x80;
const GDI_ERROR: u32 = 0xFFFFFFFF;

extern "gdi32" fn AddFontResourceExW(lpszFilename: [*:0]const u16, fl: u32, res: ?*anyopaque) callconv(.winapi) c_int;
extern "gdi32" fn CreateCompatibleDC(hdc: HDC) callconv(.winapi) HDC;
extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) c_int;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.winapi) c_int;
extern "gdi32" fn SelectObject(hdc: HDC, ho: HGDIOBJ) callconv(.winapi) HGDIOBJ;
extern "gdi32" fn CreateFontIndirectW(lf: *const LOGFONTW) callconv(.winapi) HFONT;
extern "gdi32" fn GetGlyphOutlineW(hdc: HDC, uChar: u32, fuFormat: u32, gm: *GLYPHMETRICS, cbBuffer: u32, buffer: ?[*]u8, mat2: *const MAT2) callconv(.winapi) u32;

fn scale1000(upm: u16, v: i32) i32 {
    return @divTrunc(v * 1000, upm);
}

/// Typographic family name (nameID 1) from raw font bytes: prefers
/// Win/Unicode/BMP English, falls back to Mac Roman; writes UTF-16LE
/// into `out`, returns units used. Pure bytes logic — host-testable.
fn familyName(bytes: []const u8, out: *[32]u16) error{FontLoad}!usize {
    const u16be = struct {
        fn f(b: []const u8, o: usize) error{FontLoad}!u16 {
            if (o + 2 > b.len) return error.FontLoad;
            return std.mem.readInt(u16, b[o..][0..2], .big);
        }
    }.f;
    const u32be = struct {
        fn f(b: []const u8, o: usize) error{FontLoad}!u32 {
            if (o + 4 > b.len) return error.FontLoad;
            return std.mem.readInt(u32, b[o..][0..4], .big);
        }
    }.f;
    if (bytes.len < 12) return error.FontLoad;
    const ntab = try u16be(bytes, 4);
    var name_off: usize = 0;
    var name_len: usize = 0;
    var t: usize = 0;
    while (t < ntab) : (t += 1) {
        const e = 12 + t * 16;
        if (e + 16 > bytes.len) return error.FontLoad;
        if (std.mem.eql(u8, bytes[e..][0..4], "name")) {
            name_off = try u32be(bytes, e + 8);
            name_len = try u32be(bytes, e + 12);
            break;
        }
    }
    if (name_off == 0 or name_off + 6 > bytes.len) return error.FontLoad;
    const count = try u16be(bytes, name_off + 2);
    const str_off = name_off + try u16be(bytes, name_off + 4);
    var pick: ?usize = null;
    var fallback: ?usize = null;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const r = name_off + 6 + i * 12;
        if (r + 12 > bytes.len) return error.FontLoad;
        const plat = try u16be(bytes, r);
        const enc = try u16be(bytes, r + 2);
        const lang = try u16be(bytes, r + 4);
        const nid = try u16be(bytes, r + 6);
        if (nid != 1) continue;
        if (plat == 3 and enc == 1 and lang == 0x409) {
            pick = r;
            break;
        }
        if (fallback == null and plat == 1 and enc == 0) fallback = r;
    }
    const rec = pick orelse fallback orelse return error.FontLoad;
    const slen = try u16be(bytes, rec + 8);
    const soff = str_off + try u16be(bytes, rec + 10);
    if (soff + slen > bytes.len or soff + slen > name_off + name_len) return error.FontLoad;
    const plat = try u16be(bytes, rec);
    if (plat == 3) {
        const n = slen / 2;
        if (n == 0 or n > 32) return error.FontLoad;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            const u = std.mem.readInt(u16, bytes[soff + k * 2 ..][0..2], .big);
            out[k] = u; // BMP family names need no surrogate handling.
        }
        return n;
    } else {
        if (slen == 0 or slen > 32) return error.FontLoad;
        var k: usize = 0;
        while (k < slen) : (k += 1) {
            const c = bytes[soff + k];
            out[k] = if (c < 128) c else '?';
        }
        return slen;
    }
}

pub const GdiFont = struct {
    hdc: HDC,
    metrics_font: HFONT,
    family: [32]u16,
    upm: u16,

    pub fn load(alloc: std.mem.Allocator, path: []const u8, upm: u16) error{ FontLoad, OutOfMemory }!GdiFont {
        _ = alloc;
        if (comptime !on_windows) return error.FontLoad;
        if (upm == 0) return error.FontLoad;
        var wpath: [1024]u16 = undefined;
        const wlen = std.unicode.utf8ToUtf16Le(&wpath, path) catch return error.FontLoad;
        if (wlen + 1 > wpath.len) return error.FontLoad;
        wpath[wlen] = 0;
        if (AddFontResourceExW(wpath[0..wlen :0], FR_PRIVATE, null) == 0) return error.FontLoad;
        // Family name from the file itself (works for any font file,
        // not just the fixture whose name we could hardcode).
        var threaded = std.Io.Threaded.init(std.heap.c_allocator, .{});
        defer threaded.deinit();
        const bytes = std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, std.heap.c_allocator, .limited(8 * 1024 * 1024)) catch return error.FontLoad;
        defer std.heap.c_allocator.free(bytes);
        var family: [32]u16 = [_]u16{0} ** 32;
        _ = familyName(bytes, &family) catch return error.FontLoad;
        const hdc = CreateCompatibleDC(null) orelse return error.FontLoad;
        errdefer _ = DeleteDC(hdc);
        // One-em metrics font: device units equal font units, so no
        // scaling error enters extents (mirrors sw outline units).
        const mf = CreateFontIndirectW(&LOGFONTW{ .lfHeight = -@as(i32, upm), .lfFaceName = family }) orelse return error.FontLoad;
        _ = SelectObject(hdc, mf);
        return .{ .hdc = hdc, .metrics_font = mf, .family = family, .upm = upm };
    }

    pub fn close(self: *GdiFont) void {
        if (comptime !on_windows) return;
        _ = SelectObject(self.hdc, null);
        _ = DeleteObject(self.metrics_font);
        _ = DeleteDC(self.hdc);
        // Private resource dies with the process; no removal call.
    }

    fn metrics(self: *const GdiFont, glyph: u16, buf: ?[*]u8, buflen: u32) ?GLYPHMETRICS {
        if (comptime !on_windows) return null;
        var gm: GLYPHMETRICS = std.mem.zeroes(GLYPHMETRICS);
        const r = GetGlyphOutlineW(self.hdc, glyph, GGO_GRAY8_BITMAP | GGO_GLYPH_INDEX, &gm, buflen, buf, &mat2_identity);
        if (r == GDI_ERROR) return null;
        return gm;
    }

    /// Ink extents from GDI black-box metrics: [height_above,
    /// depth_below], same zero convention as the software backend.
    pub fn extents1000(self: *const GdiFont, glyph: u16) [2]i32 {
        const gm = self.metrics(glyph, null, 0) orelse return .{ 0, 0 };
        const top = -gm.ptGlyphOrigin.y;
        const bot = top - @as(i32, @intCast(gm.blackBoxY));
        const ha: i32 = if (top <= 0) 0 else scale1000(self.upm, top);
        const db: i32 = if (bot >= 0) 0 else scale1000(self.upm, -bot);
        return .{ ha, db };
    }

    /// True ink box, y up from the baseline at 1000 units (v4 hook).
    pub fn inkBounds1000(self: *const GdiFont, glyph: u16) [4]i32 {
        const gm = self.metrics(glyph, null, 0) orelse return .{ 0, 0, 0, 0 };
        const w = @as(i32, @intCast(gm.blackBoxX));
        const h = @as(i32, @intCast(gm.blackBoxY));
        if (w <= 0 or h <= 0) return .{ 0, 0, 0, 0 };
        const x0 = gm.ptGlyphOrigin.x;
        const y1 = -gm.ptGlyphOrigin.y;
        return .{
            scale1000(self.upm, x0),
            scale1000(self.upm, y1 - h),
            scale1000(self.upm, x0 + w),
            scale1000(self.upm, y1),
        };
    }
};

pub const GdiCanvas = struct {
    swc: sw.Canvas,
    scratch: []u8,

    pub fn create(w: usize, h: usize) error{RenderInit}!GdiCanvas {
        var swc = try sw.Canvas.create(w, h);
        errdefer swc.close();
        // Gray8 coverage scratch: one byte per canvas pixel is always
        // enough for a glyph bitmap fully inside the canvas; larger
        // glyphs skip deterministically (documented, huge-px edge).
        const scratch = swc.alloc.alloc(u8, w *| h) catch return error.RenderInit;
        return .{ .swc = swc, .scratch = scratch };
    }

    pub fn close(self: *GdiCanvas) void {
        self.swc.alloc.free(self.scratch);
        self.swc.close();
    }

    pub fn setFill(self: *GdiCanvas, r: f64, g: f64, b: f64, a: f64) void {
        self.swc.setFill(r, g, b, a);
    }

    pub fn fillRect(self: *GdiCanvas, x: f64, y: f64, w: f64, h: f64) void {
        self.swc.fillRect(x, y, w, h);
    }

    pub fn beginRun(self: *GdiCanvas, font: *const GdiFont, size_px: f64, x_scale: f64, x_shear: f64) error{RenderInit}!GdiRun {
        if (comptime !on_windows) return error.RenderInit;
        const px: i32 = @intFromFloat(@max(1, @round(size_px)));
        const hf = CreateFontIndirectW(&LOGFONTW{ .lfHeight = -px, .lfFaceName = font.family }) orelse return error.RenderInit;
        const prev = SelectObject(font.hdc, hf);
        return .{ .canvas = self, .font = font, .hfont = hf, .prev = prev, .x_scale = x_scale, .x_shear = x_shear };
    }

    pub fn writePng(self: *GdiCanvas, out_path: []const u8) error{PngWrite}!void {
        try self.swc.writePng(out_path);
    }
};

pub const GdiRun = struct {
    canvas: *GdiCanvas,
    font: *const GdiFont,
    hfont: HFONT,
    prev: HGDIOBJ,
    x_scale: f64,
    /// Faux-italic slant, device px right per device px above the
    /// baseline (dotless i/j, issue #77); 0 draws unchanged.
    x_shear: f64,

    pub fn drawGlyph(self: *GdiRun, glyph: u16, x: f64, y: f64) void {
        if (comptime !on_windows) return;
        // Caller floats are bottom-left y-up pixels (interface); the
        // sw canvas underneath is top-left row-major RGBA.
        const c = &self.canvas.swc;
        var gm: GLYPHMETRICS = std.mem.zeroes(GLYPHMETRICS);
        const need = GetGlyphOutlineW(self.font.hdc, glyph, GGO_GRAY8_BITMAP | GGO_GLYPH_INDEX, &gm, 0, null, &mat2_identity);
        if (need == GDI_ERROR or need == 0) return;
        const gw: usize = gm.blackBoxX;
        const gh: usize = gm.blackBoxY;
        if (gw == 0 or gh == 0 or need > self.canvas.scratch.len) return;
        const got = GetGlyphOutlineW(self.font.hdc, glyph, GGO_GRAY8_BITMAP | GGO_GLYPH_INDEX, &gm, @intCast(self.canvas.scratch.len), self.canvas.scratch.ptr, &mat2_identity);
        if (got == GDI_ERROR) return;
        const stride: usize = (gw + 3) & ~@as(usize, 3);
        const sx: f64 = if (self.x_scale > 0) self.x_scale else 1;
        // Pen maps to canvas: ink left/top in device px at the run
        // size (the run font was selected for size_px, so GDI units
        // are already output pixels — no rescaling, unlike metrics).
        const y_base: i64 = @as(i64, @intFromFloat(@round(y)));
        const ox: i64 = @as(i64, @intFromFloat(@round(x))) + gm.ptGlyphOrigin.x;
        const oy_top: i64 = y_base - gm.ptGlyphOrigin.y;
        const W: i64 = @intCast(c.w);
        const H: i64 = @intCast(c.h);
        const fill = c.fill;
        if (fill.a <= 0) return;
        var dy: usize = 0;
        while (dy < gh) : (dy += 1) {
            // x_scale stretches ink horizontally by nearest-neighbour
            // sampling (documented GDI-backend limitation).
            const row_up: i64 = oy_top - @as(i64, @intCast(dy));
            const row: i64 = H - 1 - row_up;
            if (row < 0 or row >= H) continue;
            // Faux-italic shear (issue #77): this row sits
            // `row_up - y_base` device px above the baseline, so its
            // ink shifts right by shear times that height — the same
            // frame as the FreeType backend, inheriting this
            // backend's own origin mapping.
            const hab: i64 = row_up - y_base;
            const shx: i64 = @as(i64, @intFromFloat(@round(self.x_shear * @as(f64, @floatFromInt(hab)))));
            var dx: usize = 0;
            const dw: usize = @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(gw)) * sx)));
            while (dx < dw) : (dx += 1) {
                const col: i64 = ox + @as(i64, @intCast(dx)) + shx;
                if (col < 0 or col >= W) continue;
                const srcx: usize = @min(gw - 1, @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(dx)) / sx))));
                const v = self.canvas.scratch[dy * stride + srcx];
                if (v == 0) continue;
                const a = fill.a * @as(f64, @floatFromInt(v)) / 63.0;
                const p = c.pixels[@as(usize, @intCast(row * W + col)) * 4 ..][0..4];
                const ia = 1 - a;
                const r: f64 = @floatFromInt(p[0]);
                const g: f64 = @floatFromInt(p[1]);
                const b: f64 = @floatFromInt(p[2]);
                p[0] = @intFromFloat(@max(0, @min(255, fill.r * 255 * a + r * ia + 0.5)));
                p[1] = @intFromFloat(@max(0, @min(255, fill.g * 255 * a + g * ia + 0.5)));
                p[2] = @intFromFloat(@max(0, @min(255, fill.b * 255 * a + b * ia + 0.5)));
            }
        }
    }

    pub fn end(self: *GdiRun) void {
        if (comptime !on_windows) return;
        _ = SelectObject(self.font.hdc, self.prev);
        _ = DeleteObject(self.hfont);
    }
};

test "family name parses from the fixture" {
    const alloc = std.testing.allocator;
    const path = @import("build_options").fixture_font;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(8 * 1024 * 1024));
    defer alloc.free(bytes);
    var out: [32]u16 = [_]u16{0} ** 32;
    const n = try familyName(bytes, &out);
    const want = std.unicode.utf8ToUtf16LeStringLiteral("Latin Modern Math");
    try std.testing.expectEqual(want.len, n);
    try std.testing.expectEqualSlices(u16, want, out[0..n]);
}

test "family name rejects truncation" {
    var out: [32]u16 = [_]u16{0} ** 32;
    try std.testing.expectError(error.FontLoad, familyName(&[_]u8{ 0, 1 }, &out));
    try std.testing.expectError(error.FontLoad, familyName(&[_]u8{0} ** 40, &out));
}

test "gdi backend degrades off-windows" {
    // Off Windows every entry point is a graceful error/blank so the
    // file stays host-compilable and host-testable; on Windows these
    // assert nothing (real GDI answers there).
    if (comptime on_windows) return error.SkipZigTest;
    var f = GdiFont{ .hdc = null, .metrics_font = null, .family = [_]u16{0} ** 32, .upm = 1000 };
    try std.testing.expectError(error.FontLoad, GdiFont.load(std.testing.allocator, "nope.otf", 1000));
    try std.testing.expectEqual([2]i32{ 0, 0 }, f.extents1000(65));
    try std.testing.expectEqual([4]i32{ 0, 0, 0, 0 }, f.inkBounds1000(65));
}

test "windows extents agree with the software backend" {
    // Cross-check half of the native-backend precondition (issue
    // #64): GDI ink extents must track otmath-derived outline boxes
    // like the CoreText cross-check in sw_backend's test. Runs only
    // where GDI exists; the showcase workflow (issue #66) exercises
    // full renders on a Windows runner instead.
    if (comptime !on_windows) return error.SkipZigTest;
    const alloc = std.testing.allocator;
    const path = @import("build_options").fixture_font;
    var g = try GdiFont.load(alloc, path, 1000);
    defer g.close();
    var s = try sw.Font.load(alloc, path, 1000);
    defer s.close();
    var worst: i32 = 0;
    var over2: usize = 0;
    var glyph: u16 = 0;
    while (glyph < 256) : (glyph += 1) {
        const a = g.extents1000(glyph);
        const b = s.extents1000(glyph);
        const d0 = a[0] - b[0];
        const d1 = a[1] - b[1];
        const d: i32 = @max(if (d0 < 0) -d0 else d0, if (d1 < 0) -d1 else d1);
        if (d > worst) worst = d;
        if (d > 2) over2 += 1;
    }
    std.debug.print("gdi-vs-sw extents: worst={d}, rows>2: {d}/256\n", .{ worst, over2 });
    try std.testing.expect(over2 == 0);
}
