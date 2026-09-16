//! CoreGraphics backend (macOS, and iOS later): `Canvas` + font handle
//! over the manual bindings in `cg.zig`. Call sequence and float math
//! match the pre-interface renderer exactly, so re-renders stay
//! byte-identical to the checked-in baselines.
const std = @import("std");
const cg = @import("cg.zig");

pub const Font = struct {
    cgfont: cg.CGFontRef,
    /// CoreText font at `upm` points, so ink boxes arrive in font
    /// units for `extents1000` below.
    ctunits: cg.CTFontRef,
    upm: u16,

    /// Open the font file for drawing. Metrics still come from the
    /// portable `otmath` reader in `font.zig`; this handle only draws
    /// glyphs and reports ink boxes.
    pub fn load(alloc: std.mem.Allocator, path: []const u8, upm: u16) error{ FontLoad, OutOfMemory }!Font {
        const cpath = try alloc.dupeZ(u8, path);
        defer alloc.free(cpath);
        const dp = cg.CGDataProviderCreateWithFilename(cpath);
        if (dp == null) return error.FontLoad;
        defer cg.CFRelease(dp);
        const gf = cg.CGFontCreateWithDataProvider(dp);
        if (gf == null) return error.FontLoad;
        const ctu = cg.CTFontCreateWithGraphicsFont(gf, @floatFromInt(upm), null, null);
        if (ctu == null) return error.FontLoad;
        return .{ .cgfont = gf, .ctunits = ctu, .upm = upm };
    }

    pub fn close(self: *Font) void {
        cg.CFRelease(self.ctunits);
        cg.CFRelease(self.cgfont);
    }

    /// Real ink extents from CoreText, scaled to core thousandths:
    /// [height_above, depth_below]. Blank glyphs (space) report
    /// [0, 0], which the core handles as width-only boxes.
    pub fn extents1000(self: *const Font, glyph: u16) [2]i32 {
        var r: cg.CGRect = .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 0, .height = 0 } };
        const g: cg.CGGlyph = glyph;
        _ = cg.CTFontGetBoundingRectsForGlyphs(self.ctunits, cg.kCTFontOrientationDefault, @ptrCast(&g), @ptrCast(&r), 1);
        const top = r.origin.y + r.size.height;
        const bot = r.origin.y;
        const ha: i32 = if (top <= 0) 0 else scale1000(self.upm, @as(i32, @intFromFloat(@ceil(top))));
        const db: i32 = if (bot >= 0) 0 else scale1000(self.upm, @as(i32, @intFromFloat(@ceil(-bot))));
        return .{ ha, db };
    }

    /// True ink box `[x_min, y_min, x_max, y_max]`, y up from the
    /// baseline at 1000 units, unclipped (v4 provider hook). Blank
    /// glyphs report all zeros, which the core skips.
    pub fn inkBounds1000(self: *const Font, glyph: u16) [4]i32 {
        var r: cg.CGRect = .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 0, .height = 0 } };
        const g: cg.CGGlyph = glyph;
        _ = cg.CTFontGetBoundingRectsForGlyphs(self.ctunits, cg.kCTFontOrientationDefault, @ptrCast(&g), @ptrCast(&r), 1);
        const x0 = scale1000(self.upm, @as(i32, @intFromFloat(@floor(r.origin.x))));
        const y0 = scale1000(self.upm, @as(i32, @intFromFloat(@floor(r.origin.y))));
        const x1 = scale1000(self.upm, @as(i32, @intFromFloat(@ceil(r.origin.x + r.size.width))));
        const y1 = scale1000(self.upm, @as(i32, @intFromFloat(@ceil(r.origin.y + r.size.height))));
        return .{ x0, y0, x1, y1 };
    }
};

fn scale1000(upm: u16, v: i32) i32 {
    return @divTrunc(v * 1000, upm);
}

pub const Canvas = struct {
    ctx: cg.CGContextRef,

    pub fn create(w: usize, h: usize) error{RenderInit}!Canvas {
        const space = cg.CGColorSpaceCreateDeviceRGB();
        if (space == null) return error.RenderInit;
        defer cg.CFRelease(space);
        const ctx = cg.CGBitmapContextCreate(null, w, h, 8, w * 4, space, cg.bitmap_info);
        if (ctx == null) return error.RenderInit;
        return .{ .ctx = ctx };
    }

    pub fn close(self: *Canvas) void {
        cg.CFRelease(self.ctx);
    }

    pub fn setFill(self: *Canvas, r: f64, g: f64, b: f64, a: f64) void {
        cg.CGContextSetRGBFillColor(self.ctx, r, g, b, a);
    }

    pub fn fillRect(self: *Canvas, x: f64, y: f64, w: f64, h: f64) void {
        cg.CGContextFillRect(self.ctx, .{
            .origin = .{ .x = x, .y = y },
            .size = .{ .width = w, .height = h },
        });
    }

    /// One CTFont per run at `size_px`, released by `Run.end` — the
    /// same object lifetime the renderer always had. `x_scale`
    /// stretches ink horizontally (wide accents, brace spans —
    /// issues #31/#37); 1 draws unchanged. `x_shear` slants ink
    /// right per unit above the baseline (dotless i/j, issue #77);
    /// 0 draws unchanged. `mirrored` flips ink about the glyph
    /// origin (`\reflectbox`, issue #97); false draws unchanged.
    pub fn beginRun(self: *Canvas, font: *const Font, size_px: f64, x_scale: f64, x_shear: f64, mirrored: bool) error{RenderInit}!Run {
        const ct = cg.CTFontCreateWithGraphicsFont(font.cgfont, size_px, null, null);
        if (ct == null) return error.RenderInit;
        return .{ .ctx = self.ctx, .ct = ct, .x_scale = x_scale, .x_shear = x_shear, .mirrored = mirrored };
    }

    /// Snapshot the canvas and write an 8-bit RGBA PNG to `out_path`.
    pub fn writePng(self: *Canvas, out_path: []const u8) error{PngWrite}!void {
        const img = cg.CGBitmapContextCreateImage(self.ctx);
        if (img == null) return error.PngWrite;
        defer cg.CFRelease(img);
        const url = cg.CFURLCreateFromFileSystemRepresentation(
            null,
            out_path.ptr,
            @intCast(out_path.len),
            false,
        );
        if (url == null) return error.PngWrite;
        defer cg.CFRelease(url);
        // UTI built directly (avoids the kUTTypePNG data symbol, which
        // newer SDK link stubs may not export).
        const png_uti = cg.CFStringCreateWithCString(null, "public.png", cg.kCFStringEncodingUTF8);
        if (png_uti == null) return error.PngWrite;
        defer cg.CFRelease(png_uti);
        const dest = cg.CGImageDestinationCreateWithURL(url, png_uti, 1, null);
        if (dest == null) return error.PngWrite;
        defer cg.CFRelease(dest);
        cg.CGImageDestinationAddImage(dest, img, null);
        if (!cg.CGImageDestinationFinalize(dest)) return error.PngWrite;
    }
};

pub const Run = struct {
    ctx: cg.CGContextRef,
    ct: cg.CTFontRef,
    x_scale: f64,
    /// Faux-italic slant, device px right per device px above the
    /// glyph origin (dotless i/j, issue #77); 0 draws unchanged.
    x_shear: f64,
    /// Mirror ink about the glyph origin (`\reflectbox`, issue #97).
    mirrored: bool,

    pub fn drawGlyph(self: *Run, glyph: u16, x: f64, y: f64) void {
        const gl: cg.CGGlyph = glyph;
        if (!self.mirrored and self.x_scale == 1 and self.x_shear == 0) {
            const pos = cg.CGPoint{ .x = x, .y = y };
            cg.CTFontDrawGlyphs(self.ct, @ptrCast(&gl), @ptrCast(&pos), 1, self.ctx);
            return;
        }
        // Stretched ink: draw in a translated + x-scaled CTM so the
        // glyph origin stays at (x, y) while ink widens rightward.
        // Shear concatenates after the scale: heights stay unscaled
        // (runs never scale y) while x gains sh per unit of height,
        // slanting ink right above the origin like the SW backend.
        // Mirrored ink negates the x-scale (and the slant with it),
        // flipping about the origin like the SW backend.
        const mx: f64 = if (self.mirrored) -1 else 1;
        cg.CGContextSaveGState(self.ctx);
        cg.CGContextTranslateCTM(self.ctx, x, y);
        cg.CGContextScaleCTM(self.ctx, mx * self.x_scale, 1);
        if (self.x_shear != 0) {
            cg.CGContextConcatCTM(self.ctx, .{ .a = 1, .b = 0, .c = mx * self.x_shear, .d = 1, .tx = 0, .ty = 0 });
        }
        const origin = cg.CGPoint{ .x = 0, .y = 0 };
        cg.CTFontDrawGlyphs(self.ct, @ptrCast(&gl), @ptrCast(&origin), 1, self.ctx);
        cg.CGContextRestoreGState(self.ctx);
    }

    pub fn end(self: *Run) void {
        cg.CFRelease(self.ct);
    }
};
