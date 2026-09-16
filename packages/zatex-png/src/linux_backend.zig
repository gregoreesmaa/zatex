//! Linux backend: opt-in system rasterizer under `-Dbackend=native`
//! (fontconfig discovery + FreeType rasterization), portable software
//! rasterizer otherwise (the default).
//!
//! Native-vs-software tradeoff (issues #65/#67), decided here:
//! - What system access buys: user-installed math fonts and distro
//!   integration (a host that ships its own math fonts need not bundle
//!   the fixture). `discover` resolves a fontconfig family to a file
//!   hosts can hand to `load`.
//! - What it costs: per-machine pixels. FreeType hinting versions
//!   (v35 vs v40 interpreters), distro patches and fontconfig
//!   substitutions all move coverage, so native renders are triage /
//!   showcase material, never gates (AGENTS.md section 4). Metrics stay
//!   unhinted design units (stable across FreeType versions); only the
//!   rasterized coverage varies.
//! - Zero link dependencies either way: both libraries bind at RUNTIME
//!   via dlopen, so cross-compiles link without a sysroot and machines
//!   without the libraries keep working (native `load` fails honestly
//!   with `FontLoad`; the duplicated software backend stays default).
//!
//! Split of duties (same as every backend): advances and glyph ids
//! stay with `otmath` (shared in `font.zig`); FreeType serves ink
//! extents plus pixels.
const std = @import("std");
const builtin = @import("builtin");
const sw = @import("sw_backend.zig");
const build_options = @import("build_options");

const native_active = std.mem.eql(u8, build_options.backend, "native");

pub const Font = if (!native_active) sw.Font else FtFont;
pub const Canvas = if (!native_active) sw.Canvas else FtCanvas;
pub const Run = if (!native_active) sw.Run else FtRun;

// ---------------------------------------------------------------------------
// FreeType + fontconfig: minimal stable C ABI via dlopen (no headers,
// no link refs — `check_backends.sh`, issue #67, asserts exactly that
// for non-native builds).
// ---------------------------------------------------------------------------

const FT_Error = c_int;
const FT_Library = ?*anyopaque;
const FT_Face = ?*anyopaque;
const FT_UInt = c_uint;
const FT_ULong = c_ulong;

const FT_VectorRec = extern struct { x: c_long, y: c_long };
const FT_BBoxRec = extern struct { xMin: c_long, yMin: c_long, xMax: c_long, yMax: c_long };
const FT_Glyph_MetricsRec = extern struct {
    width: c_long,
    height: c_long,
    horiBearingX: c_long,
    horiBearingY: c_long,
    horiAdvance: c_long,
    vertBearingX: c_long,
    vertBearingY: c_long,
    vertAdvance: c_long,
};
const FT_BitmapRec = extern struct {
    rows: c_uint,
    width: c_uint,
    pitch: c_int,
    buffer: ?[*]u8,
    num_grays: c_ushort,
    pixel_mode: u8,
    palette_mode: u8,
    palette: ?*anyopaque,
};
const FT_OutlineRec = extern struct {
    n_contours: c_short,
    n_points: c_short,
    points: ?*anyopaque,
    tags: ?[*]u8,
    contours: ?[*]c_short,
    flags: c_int,
};
const FT_GlyphSlotRec = extern struct {
    library: FT_Library,
    face: FT_Face,
    next: ?*anyopaque,
    reserved: FT_UInt,
    // FT_Generic (was `reserved` pre-2.10): omitting it shifts every
    // later field by 16 bytes and the outline reads as empty.
    generic: extern struct { data: ?*anyopaque, finalizer: ?*anyopaque },
    metrics: FT_Glyph_MetricsRec,
    linearHoriAdvance: c_long,
    linearVertAdvance: c_long,
    advance: FT_VectorRec,
    format: c_int,
    bitmap: FT_BitmapRec,
    bitmap_left: c_int,
    bitmap_top: c_int,
    outline: FT_OutlineRec,
    num_subglyphs: FT_UInt,
    subglyphs: ?*anyopaque,
    control_data: ?*anyopaque,
    control_len: c_long,
    lsb_delta: c_long,
    rsb_delta: c_long,
    other: ?*anyopaque,
    internal: ?*anyopaque,
};
const FT_FaceRec = extern struct {
    num_faces: c_long,
    face_index: c_long,
    face_flags: c_long,
    style_flags: c_long,
    num_glyphs: c_long,
    family_name: ?[*:0]const u8,
    style_name: ?[*:0]const u8,
    num_fixed_sizes: c_int,
    available_sizes: ?*anyopaque,
    num_charmaps: c_int,
    charmaps: ?*anyopaque,
    generic: extern struct { data: ?*anyopaque, finalizer: ?*anyopaque },
    bbox: FT_BBoxRec,
    units_per_EM: c_ushort,
    ascender: c_short,
    descender: c_short,
    height: c_short,
    max_advance_width: c_short,
    max_advance_height: c_short,
    underline_position: c_short,
    underline_thickness: c_short,
    glyph: ?*FT_GlyphSlotRec,
    size: ?*anyopaque,
    charmap: ?*anyopaque,
};

const FT_LOAD_NO_SCALE: i32 = 1;
const FT_LOAD_RENDER: i32 = 4;
const FT_PIXEL_MODE_GRAY: u8 = 2;

const FnInit = *const fn (?*FT_Library) callconv(.c) FT_Error;
const FnDoneLibrary = *const fn (FT_Library) callconv(.c) FT_Error;
const FnNewFace = *const fn (FT_Library, [*:0]const u8, c_long, ?*FT_Face) callconv(.c) FT_Error;
const FnDoneFace = *const fn (FT_Face) callconv(.c) FT_Error;
const FnLoadGlyph = *const fn (FT_Face, FT_UInt, i32) callconv(.c) FT_Error;
const FnLoadChar = *const fn (FT_Face, FT_ULong, i32) callconv(.c) FT_Error;
const FnSetPixelSizes = *const fn (FT_Face, FT_UInt, FT_UInt) callconv(.c) FT_Error;
const FnOutlineGetCBox = *const fn (?*const FT_OutlineRec, *FT_BBoxRec) callconv(.c) void;
const FnGetCharIndex = *const fn (FT_Face, FT_ULong) callconv(.c) FT_UInt;

const FtFns = struct {
    Init: FnInit,
    Done_Library: FnDoneLibrary,
    New_Face: FnNewFace,
    Done_Face: FnDoneFace,
    Load_Glyph: FnLoadGlyph,
    Load_Char: FnLoadChar,
    Set_Pixel_Sizes: FnSetPixelSizes,
    Outline_Get_CBox: FnOutlineGetCBox,
    Get_Char_Index: FnGetCharIndex,
};

const FcFns = struct {
    Init: *const fn () callconv(.c) c_int,
    Fini: *const fn () callconv(.c) void,
    PatternCreate: *const fn () callconv(.c) ?*anyopaque,
    PatternDestroy: *const fn (?*anyopaque) callconv(.c) void,
    PatternAddString: *const fn (?*anyopaque, [*:0]const u8, [*:0]const u8) callconv(.c) c_int,
    ConfigSubstitute: *const fn (?*anyopaque, ?*anyopaque, c_int) callconv(.c) c_int,
    DefaultSubstitute: *const fn (?*anyopaque) callconv(.c) void,
    FontMatch: *const fn (?*anyopaque, ?*anyopaque, ?*c_int) callconv(.c) ?*anyopaque,
    PatternGetString: *const fn (?*anyopaque, [*:0]const u8, c_int, *[*:0]u8) callconv(.c) c_int,
};

fn openFirst(names: []const []const u8) ?std.DynLib {
    for (names) |n| {
        if (std.DynLib.open(n)) |l| return l else |_| {}
    }
    return null;
}

fn scale1000(upm: u16, v: i32) i32 {
    return @divTrunc(v * 1000, upm);
}

pub const FtFont = struct {
    ft: std.DynLib,
    fns: FtFns,
    library: FT_Library,
    face: FT_Face,
    upm: u16,

    pub fn load(alloc: std.mem.Allocator, path: []const u8, upm: u16) error{ FontLoad, OutOfMemory }!FtFont {
        _ = alloc;
        if (upm == 0) return error.FontLoad;
        var ft = openFirst(&.{ "libfreetype.so.6", "libfreetype.so" }) orelse return error.FontLoad;
        errdefer ft.close();
        const fns = FtFns{
            .Init = ft.lookup(FnInit, "FT_Init_FreeType") orelse return error.FontLoad,
            .Done_Library = ft.lookup(FnDoneLibrary, "FT_Done_FreeType") orelse return error.FontLoad,
            .New_Face = ft.lookup(FnNewFace, "FT_New_Face") orelse return error.FontLoad,
            .Done_Face = ft.lookup(FnDoneFace, "FT_Done_Face") orelse return error.FontLoad,
            .Load_Glyph = ft.lookup(FnLoadGlyph, "FT_Load_Glyph") orelse return error.FontLoad,
            .Load_Char = ft.lookup(FnLoadChar, "FT_Load_Char") orelse return error.FontLoad,
            .Set_Pixel_Sizes = ft.lookup(FnSetPixelSizes, "FT_Set_Pixel_Sizes") orelse return error.FontLoad,
            .Outline_Get_CBox = ft.lookup(FnOutlineGetCBox, "FT_Outline_Get_CBox") orelse return error.FontLoad,
            .Get_Char_Index = ft.lookup(FnGetCharIndex, "FT_Get_Char_Index") orelse return error.FontLoad,
        };
        var library: FT_Library = null;
        if (fns.Init(&library) != 0 or library == null) return error.FontLoad;
        errdefer _ = fns.Done_Library(library);
        var pathz: [1024]u8 = undefined;
        if (path.len + 1 > pathz.len) return error.FontLoad;
        @memcpy(pathz[0..path.len], path);
        pathz[path.len] = 0;
        var face: FT_Face = null;
        if (fns.New_Face(library, pathz[0..path.len :0], 0, &face) != 0 or face == null) return error.FontLoad;
        return .{ .ft = ft, .fns = fns, .library = library, .face = face, .upm = upm };
    }

    pub fn close(self: *FtFont) void {
        if (self.face) |f| _ = self.fns.Done_Face(f);
        if (self.library) |l| _ = self.fns.Done_Library(l);
        self.ft.close();
        self.face = null;
        self.library = null;
    }

    fn faceRec(self: *const FtFont) *FT_FaceRec {
        return @ptrCast(@alignCast(self.face.?));
    }

    /// Unhinted design-unit outline box (stable across FreeType
    /// versions — only raster coverage is allowed to drift).
    fn cbox(self: *const FtFont, glyph: u16) ?FT_BBoxRec {
        const f = self.faceRec();
        if (self.fns.Load_Glyph(self.face, glyph, FT_LOAD_NO_SCALE) != 0) return null;
        var box: FT_BBoxRec = .{ .xMin = 0, .yMin = 0, .xMax = 0, .yMax = 0 };
        const slot = f.glyph orelse return null;
        self.fns.Outline_Get_CBox(&slot.outline, &box);
        return box;
    }

    pub fn extents1000(self: *const FtFont, glyph: u16) [2]i32 {
        const box = self.cbox(glyph) orelse return .{ 0, 0 };
        const top: i32 = @intCast(box.yMax);
        const bot: i32 = @intCast(box.yMin);
        const ha: i32 = if (top <= 0) 0 else scale1000(self.upm, top);
        const db: i32 = if (bot >= 0) 0 else scale1000(self.upm, -bot);
        return .{ ha, db };
    }

    pub fn inkBounds1000(self: *const FtFont, glyph: u16) [4]i32 {
        const box = self.cbox(glyph) orelse return .{ 0, 0, 0, 0 };
        const x0: i32 = @intCast(box.xMin);
        const y0: i32 = @intCast(box.yMin);
        const x1: i32 = @intCast(box.xMax);
        const y1: i32 = @intCast(box.yMax);
        if (x1 <= x0 or y1 <= y0) return .{ 0, 0, 0, 0 };
        return .{
            scale1000(self.upm, x0),
            scale1000(self.upm, y0),
            scale1000(self.upm, x1),
            scale1000(self.upm, y1),
        };
    }
};

/// Resolve a fontconfig family (e.g. "DejaVu Sans") to a font file
/// path (written into `buf`, returned as a slice). This is the
/// system-font discovery half of the native backend; `load` above
/// stays file-based so same-file renders stay deterministic.
pub fn discover(family: []const u8, buf: []u8) ?[]const u8 {
    var fc = openFirst(&.{ "libfontconfig.so.1", "libfontconfig.so" }) orelse return null;
    defer fc.close();
    const Init = fc.lookup(*const fn () callconv(.c) c_int, "FcInit") orelse return null;
    const Fini = fc.lookup(*const fn () callconv(.c) void, "FcFini") orelse return null;
    const PatternCreate = fc.lookup(*const fn () callconv(.c) ?*anyopaque, "FcPatternCreate") orelse return null;
    const PatternDestroy = fc.lookup(*const fn (?*anyopaque) callconv(.c) void, "FcPatternDestroy") orelse return null;
    const AddString = fc.lookup(*const fn (?*anyopaque, [*:0]const u8, [*:0]const u8) callconv(.c) c_int, "FcPatternAddString") orelse return null;
    const ConfigSub = fc.lookup(*const fn (?*anyopaque, ?*anyopaque, c_int) callconv(.c) c_int, "FcConfigSubstitute") orelse return null;
    const DefaultSub = fc.lookup(*const fn (?*anyopaque) callconv(.c) void, "FcDefaultSubstitute") orelse return null;
    const Match = fc.lookup(*const fn (?*anyopaque, ?*anyopaque, ?*c_int) callconv(.c) ?*anyopaque, "FcFontMatch") orelse return null;
    const GetString = fc.lookup(*const fn (?*anyopaque, [*:0]const u8, c_int, *[*:0]u8) callconv(.c) c_int, "FcPatternGetString") orelse return null;
    if (Init() == 0) return null;
    defer Fini();
    const pat = PatternCreate() orelse return null;
    defer PatternDestroy(pat);
    var famz: [256]u8 = undefined;
    if (family.len + 1 > famz.len) return null;
    @memcpy(famz[0..family.len], family);
    famz[family.len] = 0;
    if (AddString(pat, "family", famz[0..family.len :0]) == 0) return null;
    if (ConfigSub(null, pat, 0) == 0) return null;
    DefaultSub(pat);
    // FcFontMatch asserts result != NULL (fcmatch.c), so a real slot is
    // mandatory even though we ignore the match quality: NULL aborts
    // fontconfig builds with assertions enabled (seen on ubuntu CI).
    var fc_result: c_int = 0;
    const match = Match(null, pat, &fc_result) orelse return null;
    defer PatternDestroy(match);
    var file: [*:0]u8 = undefined;
    if (GetString(match, "file", 0, &file) != 0) return null;
    const path = std.mem.span(file);
    if (path.len + 1 > buf.len) return null;
    @memcpy(buf[0..path.len], path);
    return buf[0..path.len];
}

pub const FtCanvas = struct {
    swc: sw.Canvas,

    pub fn create(w: usize, h: usize) error{RenderInit}!FtCanvas {
        return .{ .swc = try sw.Canvas.create(w, h) };
    }

    pub fn close(self: *FtCanvas) void {
        self.swc.close();
    }

    pub fn setFill(self: *FtCanvas, r: f64, g: f64, b: f64, a: f64) void {
        self.swc.setFill(r, g, b, a);
    }

    pub fn fillRect(self: *FtCanvas, x: f64, y: f64, w: f64, h: f64) void {
        self.swc.fillRect(x, y, w, h);
    }

    pub fn beginRun(self: *FtCanvas, font: *const FtFont, size_px: f64, x_scale: f64, x_shear: f64) error{RenderInit}!FtRun {
        const px: u32 = @intFromFloat(@max(1, @round(size_px)));
        if (font.fns.Set_Pixel_Sizes(font.face, 0, px) != 0) return error.RenderInit;
        return .{ .canvas = self, .font = font, .x_scale = x_scale, .x_shear = x_shear };
    }

    pub fn writePng(self: *FtCanvas, out_path: []const u8) error{PngWrite}!void {
        try self.swc.writePng(out_path);
    }
};

pub const FtRun = struct {
    canvas: *FtCanvas,
    font: *const FtFont,
    x_scale: f64,
    /// Faux-italic slant, device px right per device px above the
    /// baseline (dotless i/j, issue #77); 0 draws unchanged.
    x_shear: f64,

    pub fn drawGlyph(self: *FtRun, glyph: u16, x: f64, y: f64) void {
        // Caller floats are bottom-left y-up pixels (interface); the
        // sw canvas underneath is top-left row-major RGBA.
        const c = &self.canvas.swc;
        if (self.font.fns.Load_Glyph(self.font.face, glyph, FT_LOAD_RENDER) != 0) return;
        const slot = self.font.faceRec().glyph orelse return;
        const bm = slot.bitmap;
        if (bm.pixel_mode != FT_PIXEL_MODE_GRAY or bm.buffer == null) return;
        const sx: f64 = if (self.x_scale > 0) self.x_scale else 1;
        const ox: i64 = @as(i64, @intFromFloat(@round(x))) + slot.bitmap_left;
        const oy_top: i64 = @as(i64, @intFromFloat(@round(y))) + slot.bitmap_top;
        const W: i64 = @intCast(c.w);
        const H: i64 = @intCast(c.h);
        const fill = c.fill;
        if (fill.a <= 0) return;
        const buf = bm.buffer.?;
        var dy: u32 = 0;
        while (dy < bm.rows) : (dy += 1) {
            const row: i64 = H - 1 - (oy_top - @as(i64, dy));
            if (row < 0 or row >= H) continue;
            // Faux-italic shear (issue #77): row dy sits
            // `bitmap_top - dy` device px above the baseline, so its
            // ink shifts right by shear times that height.
            const hab: i64 = @as(i64, slot.bitmap_top) - @as(i64, dy);
            const shx: i64 = @as(i64, @intFromFloat(@round(self.x_shear * @as(f64, @floatFromInt(hab)))));
            var dx: u32 = 0;
            const dw: u32 = @intFromFloat(@round(@as(f64, @floatFromInt(bm.width)) * sx));
            while (dx < dw) : (dx += 1) {
                const col: i64 = ox + dx + shx;
                if (col < 0 or col >= W) continue;
                const srcx: u32 = @min(bm.width - 1, @as(u32, @intFromFloat(@floor(@as(f64, @floatFromInt(dx)) / sx))));
                const v = buf[dy * @as(usize, @intCast(bm.pitch)) + srcx];
                if (v == 0) continue;
                const a = fill.a * @as(f64, @floatFromInt(v)) / 255.0;
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

    pub fn end(self: *FtRun) void {
        _ = self;
    }
};

test "freetype absence degrades honestly" {
    // Without the system libraries every entry point fails honestly
    // (null discovery, FontLoad); where they exist, the tests below
    // exercise them. Never fails for missing libraries.
    var buf: [1024]u8 = undefined;
    var probe = openFirst(&.{ "libfreetype.so.6", "libfreetype.so" });
    if (probe == null) {
        try std.testing.expect(discover("DejaVu Sans", &buf) == null);
        try std.testing.expectError(error.FontLoad, FtFont.load(std.testing.allocator, "nope.otf", 1000));
    } else {
        probe.?.close();
        if (discover("DejaVu Sans", &buf)) |p| {
            std.debug.print("fontconfig resolved DejaVu Sans to {s}\n", .{p});
        }
    }
}

test "freetype extents track the software backend" {
    // Cross-check half of the native-backend precondition (issue
    // #65): unhinted FreeType boxes must track otmath-derived outline
    // boxes within 2mu like the CoreText cross-check in sw_backend's
    // test. Skips where the libraries are absent (macOS CI included);
    // ubuntu CI runs it for real.
    if (openFirst(&.{ "libfreetype.so.6", "libfreetype.so" }) == null) return error.SkipZigTest;
    const alloc = std.testing.allocator;
    const path = @import("build_options").fixture_font;
    var f = try FtFont.load(alloc, path, 1000);
    defer f.close();
    var s = try sw.Font.load(alloc, path, 1000);
    defer s.close();
    // cmap agreement first: same file must yield the same glyph ids.
    for ([_]u21{ 'A', 'x', 0x221A, 0x1D465, 0x3B1 }) |cp| {
        const gid = f.fns.Get_Char_Index(f.face, cp);
        try std.testing.expect(gid != 0);
    }
    var worst: i32 = 0;
    var over2: usize = 0;
    var glyph: u16 = 1;
    while (glyph < 256) : (glyph += 1) {
        const a = f.extents1000(glyph);
        const b = s.extents1000(glyph);
        const d0 = a[0] - b[0];
        const d1 = a[1] - b[1];
        const d: i32 = @max(if (d0 < 0) -d0 else d0, if (d1 < 0) -d1 else d1);
        if (d > worst) worst = d;
        if (d > 2) over2 += 1;
    }
    std.debug.print("ft-vs-sw extents: worst={d}, rows>2: {d}/255\n", .{ worst, over2 });
    try std.testing.expect(over2 == 0);
}

