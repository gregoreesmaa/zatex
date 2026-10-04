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

/// CTFont memo capacity on a canvas (issue #286): formulas use a
/// handful of (face, size) pairs; beyond this `beginRun` falls back to
/// a per-run CTFont (the old behavior, no worse) without caching it.
const MAX_CACHED_CTFONTS = 32;

/// One memoized CoreText font: exact bits of the requested size (the
/// cache key) plus the face identity it was built from. Sizes compare
/// as bits, so 48.0 vs 48.0000001 never alias.
const CachedCTFont = struct {
    face: cg.CGFontRef,
    size_bits: u64,
    ct: cg.CTFontRef,
};

/// Batched identity glyphs per `CTFontDrawGlyphs` call (issue #286):
/// an identity run draws each glyph in its own call today; buffering
/// up to this many and flushing once amortizes the call overhead while
/// keeping stack scratch small.
const BATCH_GLYPHS = 256;

pub const Canvas = struct {
    ctx: cg.CGContextRef,
    /// CTFont memo (issue #286): one CoreText font per (face, size),
    /// created once and shared across runs of a canvas. Entries borrow
    /// the `Font` handles (`Font.close` outlives every canvas in the
    /// renderer, where `font` outlives the render call), so the cache
    /// owns only the CTFont refs it created. `close` releases them all.
    fonts: [MAX_CACHED_CTFONTS]CachedCTFont = undefined,
    nfonts: usize = 0,

    pub fn create(w: usize, h: usize) error{RenderInit}!Canvas {
        const space = cg.CGColorSpaceCreateDeviceRGB();
        if (space == null) return error.RenderInit;
        defer cg.CFRelease(space);
        const ctx = cg.CGBitmapContextCreate(null, w, h, 8, w * 4, space, cg.bitmap_info);
        if (ctx == null) return error.RenderInit;
        return .{ .ctx = ctx };
    }

    pub fn close(self: *Canvas) void {
        for (self.fonts[0..self.nfonts]) |e| cg.CFRelease(e.ct);
        self.nfonts = 0;
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

    /// Butt-cap thick segment in bottom-left float coords (diagonal
    /// strikes, issue #107): mirrors the SVG `line` KaTeX emits
    /// (`stroke-linecap: butt` there, `kCGLineCapButt` = 0 here).
    /// The stroke paint must be set separately (`setFill` leaves the
    /// stroke color untouched, so call `setStroke` first).
    pub fn setStroke(self: *Canvas, r: f64, g: f64, b: f64, a: f64) void {
        cg.CGContextSetRGBStrokeColor(self.ctx, r, g, b, a);
    }

    pub fn strokeLine(self: *Canvas, x0: f64, y0: f64, x1: f64, y1: f64, t: f64) void {
        if (!(t > 0)) return;
        if (x0 == x1 and y0 == y1) return;
        cg.CGContextSetLineWidth(self.ctx, t);
        cg.CGContextSetLineCap(self.ctx, 0);
        cg.CGContextMoveToPoint(self.ctx, x0, y0);
        cg.CGContextAddLineToPoint(self.ctx, x1, y1);
        cg.CGContextStrokePath(self.ctx);
    }

    /// CTFont memo lookup (issue #286): exact (face, size-bits) hit
    /// shares the canvas-owned font; a miss creates, caches when there
    /// is room, and shares alike. Sizes key as bits (see
    /// `CachedCTFont`). A full table returns an owned per-run font
    /// (the old lifetime) instead of failing the render.
    fn ctForSize(self: *Canvas, font: *const Font, size_px: f64) error{RenderInit}!struct { ct: cg.CTFontRef, owned: bool } {
        const bits: u64 = @bitCast(size_px);
        for (self.fonts[0..self.nfonts]) |e| {
            if (e.face == font.cgfont and e.size_bits == bits) return .{ .ct = e.ct, .owned = false };
        }
        const ct = cg.CTFontCreateWithGraphicsFont(font.cgfont, size_px, null, null);
        if (ct == null) return error.RenderInit;
        if (self.nfonts < self.fonts.len) {
            self.fonts[self.nfonts] = .{ .face = font.cgfont, .size_bits = bits, .ct = ct };
            self.nfonts += 1;
            return .{ .ct = ct, .owned = false };
        }
        return .{ .ct = ct, .owned = true };
    }

    /// One CTFont per (face, size) shared across runs (issue #286),
    /// released by `Canvas.close` — runs borrow, except a full-table
    /// fallback whose per-run font `Run.end` releases (lifetime
    /// flagged on the run). `x_scale` stretches ink horizontally
    /// (wide accents, brace spans — issues #31/#37); 1 draws
    /// unchanged. `x_shear` slants ink right per unit above the
    /// baseline (dotless i/j, issue #77); 0 draws unchanged.
    /// `mirrored` flips ink about the glyph origin (`\reflectbox`,
    /// issue #97); false draws unchanged.
    pub fn beginRun(self: *Canvas, font: *const Font, size_px: f64, x_scale: f64, x_shear: f64, mirrored: bool) error{RenderInit}!Run {
        const f = try self.ctForSize(font, size_px);
        return .{ .ctx = self.ctx, .ct = f.ct, .owned = f.owned, .x_scale = x_scale, .x_shear = x_shear, .mirrored = mirrored };
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
    /// False when the CTFont is canvas-owned (shared memo entry):
    /// `end` releases only the full-table fallback (issue #286).
    owned: bool,
    x_scale: f64,
    /// Faux-italic slant, device px right per device px above the
    /// glyph origin (dotless i/j, issue #77); 0 draws unchanged.
    x_shear: f64,
    /// Mirror ink about the glyph origin (`\reflectbox`, issue #97).
    mirrored: bool,
    /// Identity-path batching (issue #286): buffered glyphs and
    /// positions flushed as one `CTFontDrawGlyphs(n)` on full/end.
    nglyphs: usize = 0,
    batch_glyphs: [BATCH_GLYPHS]cg.CGGlyph = undefined,
    batch_pos: [BATCH_GLYPHS]cg.CGPoint = undefined,

    fn flush(self: *Run) void {
        if (self.nglyphs == 0) return;
        cg.CTFontDrawGlyphs(self.ct, @ptrCast(&self.batch_glyphs), @ptrCast(&self.batch_pos), self.nglyphs, self.ctx);
        self.nglyphs = 0;
    }

    pub fn drawGlyph(self: *Run, glyph: u16, x: f64, y: f64) void {
        const gl: cg.CGGlyph = glyph;
        if (!self.mirrored and self.x_scale == 1 and self.x_shear == 0) {
            // Identity ink batches into one draw call per flush
            // (issue #286): same positions, same font, one call.
            if (self.nglyphs >= self.batch_glyphs.len) self.flush();
            self.batch_glyphs[self.nglyphs] = gl;
            self.batch_pos[self.nglyphs] = .{ .x = x, .y = y };
            self.nglyphs += 1;
            return;
        }
        // A stretched glyph cannot join the identity batch (different
        // CTM): flush first so draw order stays exact.
        self.flush();
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
        self.flush();
        if (self.owned) cg.CFRelease(self.ct);
    }
};
