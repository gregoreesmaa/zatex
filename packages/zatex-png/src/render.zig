//! IR -> pixels: one layout becomes one PNG. Positions come from the
//! core in font units (1000 = 1 em at the ambient size); this file only
//! scales them by px_per_em/1000 and draws — no layout math, ever.
//!
//! The context is y-flipped once, so all content is addressed in the
//! core's top-left-origin coordinates mapped through H - y.
const std = @import("std");
const zatex = @import("zatex");
const backend = @import("backend.zig");
const Font = @import("font.zig").Font;

pub const Error = error{
    RenderInit,
    PngWrite,
};

/// Single-slot canvas cache for batch renders (issue #284): creating
/// a canvas allocates pixels plus the fixed scratch (512 segs, 8192
/// lines, row coverage) per image; a corpus batch renders hundreds of
/// images and frees each one. The pool keeps the last canvas and
/// reuses it whenever the next image has exactly the same dimensions
/// (same formula shape at the same `--px`); on a size mismatch it
/// closes the cached canvas and creates a fresh one — identical to
/// the unpooled path. Reuse is pixel-exact: every render fills the
/// full canvas (background rect over w x h) before drawing, so no
/// stale pixel can survive a hit. Backend-generic (over
/// `backend.impl.Canvas`): backends without scratch (CoreGraphics)
/// still save the context alloc on a hit.
pub const CanvasPool = struct {
    cached: ?backend.impl.Canvas = null,
    w: usize = 0,
    h: usize = 0,

    pub fn deinit(self: *CanvasPool) void {
        if (self.cached) |*c| c.close();
        self.cached = null;
    }

    fn take(self: *CanvasPool, w: usize, h: usize) error{RenderInit}!backend.impl.Canvas {
        if (self.cached) |c| {
            if (self.w == w and self.h == h) {
                self.cached = null;
                return c;
            }
            var old = c;
            old.close();
            self.cached = null;
        }
        const fresh = try backend.impl.Canvas.create(w, h);
        self.w = w;
        self.h = h;
        return fresh;
    }

    fn give(self: *CanvasPool, canvas: backend.impl.Canvas, w: usize, h: usize) void {
        std.debug.assert(self.cached == null);
        self.cached = canvas;
        self.w = w;
        self.h = h;
    }
};

/// Render `layout` (laid out with `font`'s provider, so advances agree)
/// to `out_path` at `px_per_em` pixels per em with `pad_px` padding.
/// Black on white, 8-bit RGBA PNG.
pub fn renderToPng(
    font: *const Font,
    layout: zatex.ir.Layout,
    px_per_em: u32,
    pad_px: u32,
    out_path: []const u8,
) Error!void {
    return renderToPngPooled(font, layout, px_per_em, pad_px, out_path, null);
}

/// `renderToPng` through a batch canvas pool (null disables pooling —
/// the single-render path). Pool hits render byte-identically: the
/// canvas is fully repainted every render, and a size mismatch
/// recreates instead of reusing.
pub fn renderToPngPooled(
    font: *const Font,
    layout: zatex.ir.Layout,
    px_per_em: u32,
    pad_px: u32,
    out_path: []const u8,
    pool: ?*CanvasPool,
) Error!void {
    const s: f64 = @as(f64, @floatFromInt(px_per_em)) / 1000.0;
    const pad: f64 = @floatFromInt(pad_px);
    // Left-overflow shift (issue #71): zero-width overlaps (`\llap`,
    // centered `\mathclap`) place runs left of the layout origin, and a
    // canvas starting at 0 clips that ink while KaTeX shows the
    // overflow. Measure the leftmost ink edge and shift the origin so
    // it lands on pad. Only the left edge moves (a non-negative shift):
    // right/top/bottom keep the advance+pad canvas, whose pads already
    // absorb ordinary overhang there.
    const shift: f64 = @as(f64, @floatFromInt(leftShiftUnits(fontShiftMetrics(font), layout.runs, layout.rules))) * s;
    // Right-overflow shift (issue #96): ink past the advance width
    // (e.g. `\minuso`'s rlap circle) clips the same way the left
    // edge did before #71 — widen the canvas past advance+pad.
    const rshift: f64 = @as(f64, @floatFromInt(rightShiftUnits(fontShiftMetrics(font), layout.runs, layout.rules, layout.width))) * s;
    const w: usize = @max(1, ceilU(@as(f64, @floatFromInt(layout.width)) * s + 2 * pad + shift + rshift));
    // Top/bottom rule fit (issue #270 review): diagonal cancel
    // strikes overhang the layout box by KaTeX's 0.2em pad (pinned
    // 0.18.7 `enclose.ts`), and a standalone bitmap must contain its
    // ink — KaTeX HTML overflows visibly instead of clipping. Rules
    // only (run ink is contained by construction); zero keeps every
    // other bitmap bit-identical.
    const top_units = topShiftUnits(layout.rules);
    const box_units: i64 = @as(i64, layout.height_above) + @as(i64, layout.depth_below);
    const bot_units = bottomShiftUnits(layout.rules, box_units);
    const top_px: f64 = @as(f64, @floatFromInt(top_units)) * s;
    const bot_px: f64 = @as(f64, @floatFromInt(bot_units)) * s;
    const pad_top: f64 = pad + top_px;
    const h: usize = @max(1, ceilU((@as(f64, @floatFromInt(layout.height_above)) +
        @as(f64, @floatFromInt(layout.depth_below))) * s + 2 * pad + top_px + bot_px));

    var canvas = if (pool) |p| try p.take(w, h) else try backend.impl.Canvas.create(w, h);
    defer {
        if (pool) |p| p.give(canvas, w, h) else canvas.close();
    }

    // White background, black ink.
    canvas.setFill(1, 1, 1, 1);
    canvas.fillRect(0, 0, @floatFromInt(w), @floatFromInt(h));
    canvas.setFill(0, 0, 0, 1);
    // The canvas is y-up (origin bottom-left), so every y-down layout
    // coordinate maps through H - y — glyph baselines and rule rects
    // alike. (On Quartz this means leaving the CTM untouched: flipping
    // it renders glyphs upside down.)
    const H: f64 = @floatFromInt(h);
    // Rules (fraction bars, vincula, colorbox backgrounds) are plain
    // filled rects, each in its own paint (issue #35). Diagonal
    // strikes (issue #107) stroke corner-to-corner across the same
    // rect instead: `up` from bottom-left, `down` from top-left.
    for (layout.rules) |r| {
        if (r.diag != .none) continue;
        const rx = @as(f64, @floatFromInt(r.x)) * s + pad + shift;
        const rw = @as(f64, @floatFromInt(r.w)) * s;
        const rh = @as(f64, @floatFromInt(r.h)) * s;
        const ry = ruleOriginY(r.y, r.h, s, pad_top, H);
        setPaint(&canvas, r.color);
        canvas.fillRect(rx, ry, rw, rh);
    }

    // Cancel strikes paint over the body (pinned 0.18.7 `enclose.ts`:
    // "Write the \cancel stroke on top of inner"); rect rules never
    // overlap ink and stay underneath.
    for (layout.rules) |r| {
        if (r.diag == .none) continue;
        const rx = @as(f64, @floatFromInt(r.x)) * s + pad + shift;
        const rw = @as(f64, @floatFromInt(r.w)) * s;
        const rh = @as(f64, @floatFromInt(r.h)) * s;
        setPaint(&canvas, r.color);
        // Canvas y of the rect's top and bottom edges (Quartz y-up).
        const y_top = H - (@as(f64, @floatFromInt(r.y)) * s + pad_top);
        const y_bot = y_top - rh;
        const t = @as(f64, @floatFromInt(r.thick)) * s;
        if (r.diag == .up) canvas.strokeLine(rx, y_bot, rx + rw, y_top, t) else canvas.strokeLine(rx, y_top, rx + rw, y_bot, t);
    }

    // Runs: one backend run per run size, glyph origins stepped with
    // the same integer advances the core measured, scaled once to
    // pixels. Runs never merge across colors, so one setPaint per run
    // is exact (issue #35).
    for (layout.runs) |run| {
        const px_size: f64 = @as(f64, @floatFromInt(run.size_units)) *
            @as(f64, @floatFromInt(px_per_em)) / 1000.0;
        if (px_size <= 0 or run.glyphs.len == 0) continue;
        // Raster stretch (issues #31/#37): the core lays out the
        // construction width and stamps the stretch factor; ink and
        // pen advances scale together so stepped origins stay exact.
        const sx: f64 = @as(f64, @floatFromInt(run.x_scale)) / 1000.0;
        // Faux-italic slant as a dimensionless ratio (issue #77).
        const sh: f64 = @as(f64, @floatFromInt(run.x_shear)) / 1000.0;
        setPaint(&canvas, run.color);
        var x_units: i64 = run.x;
        const base_y: f64 = glyphBaseY(run.baseline_y, s, pad_top, H);
        // Multi-face (issue #92): consecutive glyphs from one face
        // draw under one backend run; the pen still steps with the
        // unified advances, so split points stay exact.
        var gi: usize = 0;
        while (gi < run.glyphs.len) {
            const df = font.drawFace(run.glyphs[gi]) orelse {
                // Unowned id (no face loaded it): still step the pen.
                const step0: i64 = @divTrunc(
                    @as(i64, font.advance1000(run.glyphs[gi])) * @as(i64, run.size_units),
                    1000,
                );
                x_units += @divTrunc(step0 * @as(i64, run.x_scale), 1000);
                gi += 1;
                continue;
            };
            var gj = gi + 1;
            while (gj < run.glyphs.len) {
                const dn = font.drawFace(run.glyphs[gj]) orelse break;
                if (dn.handle != df.handle) break;
                gj += 1;
            }
            var rf = try canvas.beginRun(df.handle, px_size, sx, sh, run.mirrored);
            while (gi < gj) : (gi += 1) {
                const g = run.glyphs[gi];
                const face_gid = (font.drawFace(g) orelse df).gid;
                const gx: f64 = @as(f64, @floatFromInt(x_units)) * s + pad + shift;
                rf.drawGlyph(face_gid, gx, base_y);
                const step: i64 = @divTrunc(
                    @as(i64, font.advance1000(g)) * @as(i64, run.size_units),
                    1000,
                );
                // Identity scales step exactly as before.
                x_units += @divTrunc(step * @as(i64, run.x_scale), 1000);
            }
            rf.end();
        }
    }

    try canvas.writePng(out_path);
}

/// Glyph metrics for the left-shift walk: integer thousandths like the
/// core measures, so the walk stays exact with stub providers in tests.
/// Ink top/bottom (y-up thousandths from the baseline) are optional:
/// stubs omit them and sheared runs then keep the unsheared bound.
const ShiftMetrics = struct {
    ptr: *const anyopaque,
    advance1000: *const fn (ptr: *const anyopaque, glyph: u16) i32,
    inkLeft1000: *const fn (ptr: *const anyopaque, glyph: u16) i32,
    /// Ink right edge (origin-relative thousandths, y-up): mirrored
    /// ink (issue #97) spans [-right, -left] about the origin, so the
    /// left edge hangs off the right metric.
    inkRight1000: *const fn (ptr: *const anyopaque, glyph: u16) i32,
    inkTop1000: ?*const fn (ptr: *const anyopaque, glyph: u16) i32 = null,
    inkBottom1000: ?*const fn (ptr: *const anyopaque, glyph: u16) i32 = null,
};

fn fontShiftMetrics(font: *const Font) ShiftMetrics {
    const W = struct {
        fn adv(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.advance1000(glyph);
        }
        fn ink(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.inkBounds1000(glyph)[0];
        }
        fn inkR(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.inkBounds1000(glyph)[2];
        }
        fn top(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.inkBounds1000(glyph)[3];
        }
        fn bot(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.inkBounds1000(glyph)[1];
        }
    };
    return .{ .ptr = font, .advance1000 = W.adv, .inkLeft1000 = W.ink, .inkRight1000 = W.inkR, .inkTop1000 = W.top, .inkBottom1000 = W.bot };
}

/// Canvas shift (layout units, >= 0) so left-overflow ink lands on pad.
/// Walks glyph origins exactly like the draw loop above: origin stepping
/// uses the same integer advances, and each glyph contributes its true
/// ink-left edge (ink box is origin-relative thousandths, y-up). Rules
/// contribute their rect left edge. Pure viewport fit — box coordinates
/// are untouched, so a zero shift (the common case) renders bit-identical
/// output to before.
/// Right-overflow shift (issue #96): mirror of `leftShiftUnits`
/// for ink past the advance width (e.g. `\minuso`, whose rlap
/// circle overhangs the minus box). Returns extra layout units to
/// append to the canvas width; zero keeps canvases bit-identical.
fn rightShiftUnits(m: ShiftMetrics, runs: []const zatex.ir.Run, rules: []const zatex.ir.Rule, width: u32) u32 {
    var edge: i64 = width;
    for (rules) |r| {
        const right: i64 = @as(i64, r.x) + @as(i64, r.w);
        if (right > edge) edge = right;
    }
    for (runs) |run| {
        if (run.glyphs.len == 0) continue;
        var x_units: i64 = run.x;
        for (run.glyphs) |g| {
            // Mirror of the twin: mirrored ink spans [-right, -left]
            // about the origin, so its right edge hangs off the ink
            // left; plain runs hang off the ink right.
            const ink_o: i64 = if (run.mirrored) -m.inkLeft1000(m.ptr, g) else m.inkRight1000(m.ptr, g);
            const ink_e = @divTrunc(ink_o * @as(i64, run.size_units) * @as(i64, run.x_scale), 1000 * 1000);
            var right = x_units + ink_e;
            if (run.x_shear != 0 and m.inkTop1000 != null and m.inkBottom1000 != null) {
                const top_u = @divTrunc(@as(i64, m.inkTop1000.?(m.ptr, g)) * @as(i64, run.size_units), 1000);
                const bot_u = @divTrunc(@as(i64, m.inkBottom1000.?(m.ptr, g)) * @as(i64, run.size_units), 1000);
                const sh_top = @divFloor(@as(i64, run.x_shear) * top_u, 1000);
                const sh_bot = @divFloor(@as(i64, run.x_shear) * bot_u, 1000);
                if (run.mirrored) {
                    right -= @min(@as(i64, 0), @min(sh_top, sh_bot));
                } else {
                    right += @max(@as(i64, 0), @max(sh_top, sh_bot));
                }
            }
            if (right > edge) edge = right;
            const step: i64 = @divTrunc(
                @as(i64, m.advance1000(m.ptr, g)) * @as(i64, run.size_units),
                1000,
            );
            x_units += @divTrunc(step * @as(i64, run.x_scale), 1000);
        }
    }
    return if (edge > @as(i64, width)) @intCast(edge - @as(i64, width)) else 0;
}

fn leftShiftUnits(m: ShiftMetrics, runs: []const zatex.ir.Run, rules: []const zatex.ir.Rule) u32 {
    var left: i64 = 0;
    for (rules) |r| {
        if (@as(i64, r.x) < left) left = @as(i64, r.x);
    }
    for (runs) |run| {
        if (run.glyphs.len == 0) continue;
        var x_units: i64 = run.x;
        for (run.glyphs) |g| {
            // Mirrored ink (issue #97) spans [-right, -left] about
            // the origin, so its left edge hangs off the ink right.
            const ink_o: i64 = if (run.mirrored) m.inkRight1000(m.ptr, g) else m.inkLeft1000(m.ptr, g);
            const ink_e = @divTrunc(ink_o * @as(i64, run.size_units) * @as(i64, run.x_scale), 1000 * 1000);
            // Faux-italic shear (issue #77) slides ink horizontally
            // with height: the shift is linear, so the extremes sit
            // at the ink top/bottom. Backends round each row to
            // nearest, so floor here stays conservative (never
            // under-shifts). Runs at shear 0, or stubs without
            // top/bottom metrics, keep the old bound exactly.
            // Mirrored runs shear the other way (the backend negates
            // the slant with the flip), so the extremes mirror too.
            var edge = if (run.mirrored) x_units - ink_e else x_units + ink_e;
            if (run.x_shear != 0 and m.inkTop1000 != null and m.inkBottom1000 != null) {
                const top_u = @divTrunc(@as(i64, m.inkTop1000.?(m.ptr, g)) * @as(i64, run.size_units), 1000);
                const bot_u = @divTrunc(@as(i64, m.inkBottom1000.?(m.ptr, g)) * @as(i64, run.size_units), 1000);
                const sh_top = @divFloor(@as(i64, run.x_shear) * top_u, 1000);
                const sh_bot = @divFloor(@as(i64, run.x_shear) * bot_u, 1000);
                if (run.mirrored) {
                    edge -= @max(@as(i64, 0), @max(sh_top, sh_bot));
                } else {
                    edge += @min(@as(i64, 0), @min(sh_top, sh_bot));
                }
            }
            if (edge < left) left = edge;
            const step: i64 = @divTrunc(
                @as(i64, m.advance1000(m.ptr, g)) * @as(i64, run.size_units),
                1000,
            );
            x_units += @divTrunc(step * @as(i64, run.x_scale), 1000);
        }
    }
    return if (left < 0) @intCast(-left) else 0;
}

/// Top-overflow shift in layout units (>= 0): diagonal cancel strikes
/// overhang the layout box top by KaTeX's 0.2em pad (pinned 0.18.7
/// `enclose.ts`), and a standalone bitmap must contain its ink —
/// KaTeX HTML overflows visibly instead of clipping. Rules only (run
/// ink is contained by construction); zero keeps every other bitmap
/// bit-identical.
fn topShiftUnits(rules: []const zatex.ir.Rule) u32 {
    var top: i64 = 0;
    for (rules) |r| {
        if (@as(i64, r.y) < top) top = @as(i64, r.y);
    }
    return if (top < 0) @intCast(-top) else 0;
}

/// Bottom-overflow shift in layout units (>= 0): mirror of
/// `topShiftUnits` for rule ink past the box bottom.
fn bottomShiftUnits(rules: []const zatex.ir.Rule, box_units: i64) u32 {
    var bot: i64 = box_units;
    for (rules) |r| {
        const edge: i64 = @as(i64, r.y) + @as(i64, r.h);
        if (edge > bot) bot = edge;
    }
    return if (bot > box_units) @intCast(bot - box_units) else 0;
}

test "vertical shifts cover rule overhang, else zero" {
    // A cancel-style diagonal overhanging the box both ways (pinned
    // 0.18.7 `enclose.ts`: the vlist keeps the inner box while the
    // strike laps 0.2em past it): the canvas grows to contain the
    // rule instead of clipping it (issue #270 review).
    const rules = [_]zatex.ir.Rule{
        .{ .x = 0, .y = -200, .w = 572, .h = 853, .diag = .up, .thick = 46 },
    };
    try std.testing.expectEqual(@as(u32, 200), topShiftUnits(&rules));
    try std.testing.expectEqual(@as(u32, 200), bottomShiftUnits(&rules, 453));
    try std.testing.expectEqual(@as(u32, 0), topShiftUnits(&[_]zatex.ir.Rule{}));
    try std.testing.expectEqual(@as(u32, 0), bottomShiftUnits(&[_]zatex.ir.Rule{}, 453));
    // Contained rules shift nothing.
    const inside = [_]zatex.ir.Rule{
        .{ .x = 0, .y = 0, .w = 100, .h = 40 },
    };
    try std.testing.expectEqual(@as(u32, 0), topShiftUnits(&inside));
    try std.testing.expectEqual(@as(u32, 0), bottomShiftUnits(&inside, 453));
}

test "left shift covers runs and rules, else zero" {
    const S = struct {
        fn adv(_: *const anyopaque, g: u16) i32 {
            return if (g == 'x') 500 else 400;
        }
        fn ink(_: *const anyopaque, g: u16) i32 {
            // `x` overhangs 50 left of its origin; `y` is inset 10.
            return if (g == 'x') -50 else 10;
        }
        fn inkR(_: *const anyopaque, g: u16) i32 {
            // Right edges: `x` overhangs 50 right too, `y` ends at 390.
            return if (g == 'x') 550 else 390;
        }
        var tag: u8 = 0;
    };
    const m: ShiftMetrics = .{ .ptr = &S.tag, .advance1000 = S.adv, .inkLeft1000 = S.ink, .inkRight1000 = S.inkR };
    // No negative ink: zero shift (bit-identical canvas).
    const runs_ok = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    try std.testing.expectEqual(@as(u32, 0), leftShiftUnits(m, &runs_ok, &.{}));
    // llap shape: run at -500 whose glyph overhangs a further 50.
    const runs_lap = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{'x'} },
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    try std.testing.expectEqual(@as(u32, 550), leftShiftUnits(m, &runs_lap, &.{}));
    // Origins step by advances inside a run: the walk sees the first
    // `x` at -500 (ink to -550), not just the run origin.
    const runs_step = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{ 'x', 'x' } },
    };
    try std.testing.expectEqual(@as(u32, 550), leftShiftUnits(m, &runs_step, &.{}));
    // Rules contribute their rect left edge.
    const rules = [_]zatex.ir.Rule{
        .{ .x = -40, .y = 0, .w = 100, .h = 10 },
    };
    try std.testing.expectEqual(@as(u32, 40), leftShiftUnits(m, &runs_ok, &rules));
    // Mirrored ink (issue #97) hangs off the ink right: `y` mirrored
    // at 0 reaches 0-390; `x` mirrored at -500 reaches -500-550.
    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'}, .mirrored = true },
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{'x'}, .mirrored = true },
    };
    try std.testing.expectEqual(@as(u32, 1050), leftShiftUnits(m, &runs_mir, &.{}));
}

test "right shift covers runs and rules, else zero (issue #96)" {
    // `\minuso` shape: the rlap circle's ink runs past the minus
    // advance, the way `\llap` ink runs left of the origin. Same
    // stub metrics as the left-shift twin (`x`: advance 500, ink
    // right 550; `y`: advance 400, ink right 390).
    const S = struct {
        fn adv(_: *const anyopaque, g: u16) i32 {
            return if (g == 'x') 500 else 400;
        }
        fn ink(_: *const anyopaque, g: u16) i32 {
            return if (g == 'x') -50 else 10;
        }
        fn inkR(_: *const anyopaque, g: u16) i32 {
            return if (g == 'x') 550 else 390;
        }
        var tag: u8 = 0;
    };
    const m: ShiftMetrics = .{ .ptr = &S.tag, .advance1000 = S.adv, .inkLeft1000 = S.ink, .inkRight1000 = S.inkR };
    // Ink inside the advance: zero shift (bit-identical canvas).
    const runs_ok = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    try std.testing.expectEqual(@as(u32, 0), rightShiftUnits(m, &runs_ok, &.{}, 400));
    // Overhanging glyph: `x` ink reaches 550 past a 500 width.
    const runs_over = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'x'} },
    };
    try std.testing.expectEqual(@as(u32, 50), rightShiftUnits(m, &runs_over, &.{}, 500));
    // Rules contribute their rect right edge.
    const rules = [_]zatex.ir.Rule{
        .{ .x = 450, .y = 0, .w = 100, .h = 10 },
    };
    try std.testing.expectEqual(@as(u32, 50), rightShiftUnits(m, &runs_ok, &rules, 500));
    // Mirrored ink spans [-right, -left]: `x` mirrored at 500
    // reaches 500+50 off the ink left.
    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 500, .baseline_y = 0, .glyphs = &[_]u16{'x'}, .mirrored = true },
    };
    try std.testing.expectEqual(@as(u32, 50), rightShiftUnits(m, &runs_mir, &.{}, 500));
}

test "left shift follows shear at ink extremes (issue #77)" {
    // Sheared dotless-j shape: ink left -40, top 442, bottom -205
    // (LM ȷ proportions). Shear 250 drags the descender tail left by
    // floor(250*205/1000) = 52, so the edge is 0-40-52 = -92. The
    // top leans right (+110) and never widens the left shift. A
    // stub without top/bottom metrics keeps the unsheared bound.
    const S = struct {
        fn adv(_: *const anyopaque, g: u16) i32 {
            return if (g == 's') 306 else 400;
        }
        fn ink(_: *const anyopaque, g: u16) i32 {
            return if (g == 's') -40 else 10;
        }
        fn top(_: *const anyopaque, g: u16) i32 {
            return if (g == 's') 442 else 0;
        }
        fn bot(_: *const anyopaque, g: u16) i32 {
            return if (g == 's') -205 else 0;
        }
        fn inkR(_: *const anyopaque, g: u16) i32 {
            return if (g == 's') 346 else 390;
        }
        var tag: u8 = 0;
    };
    const m: ShiftMetrics = .{ .ptr = &S.tag, .advance1000 = S.adv, .inkLeft1000 = S.ink, .inkRight1000 = S.inkR };
    const m2: ShiftMetrics = .{ .ptr = &S.tag, .advance1000 = S.adv, .inkLeft1000 = S.ink, .inkRight1000 = S.inkR, .inkTop1000 = S.top, .inkBottom1000 = S.bot };
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'s'}, .x_shear = 250 },
    };
    try std.testing.expectEqual(@as(u32, 92), leftShiftUnits(m2, &runs, &.{}));
    try std.testing.expectEqual(@as(u32, 40), leftShiftUnits(m, &runs, &.{}));
    // Mirrored shear (issue #97) leans the other way: the top (+110)
    // drags left, so the edge is 0-346-110 = -456. Without
    // top/bottom metrics the sheared bound stays put (0-346).
    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'s'}, .x_shear = 250, .mirrored = true },
    };
    try std.testing.expectEqual(@as(u32, 456), leftShiftUnits(m2, &runs_mir, &.{}));
    try std.testing.expectEqual(@as(u32, 346), leftShiftUnits(m, &runs_mir, &.{}));
}

/// Select the paint for one IR run/rule: ambient (null) is black ink;
/// otherwise the 0xRRGGBBAA word the core stamped (issue #35).
fn setPaint(canvas: *backend.impl.Canvas, color: ?u32) void {
    // Strokes carry the same paint (diagonal strikes, issue #107):
    // single-state canvases alias the two, split-state ones (Quartz)
    // need both calls.
    const c = color orelse {
        canvas.setFill(0, 0, 0, 1);
        canvas.setStroke(0, 0, 0, 1);
        return;
    };
    const f = struct {
        fn b(v: u32) f64 {
            return @as(f64, @floatFromInt(v)) / 255.0;
        }
    }.b;
    const r = f((c >> 24) & 0xFF);
    const g = f((c >> 16) & 0xFF);
    const b = f((c >> 8) & 0xFF);
    const a = f(c & 0xFF);
    canvas.setFill(r, g, b, a);
    canvas.setStroke(r, g, b, a);
}

fn ceilU(v: f64) usize {
    const t: usize = @intFromFloat(v);
    return if (@as(f64, @floatFromInt(t)) < v) t + 1 else t;
}

/// Quartz (y-up) origin y for a glyph-run baseline: the layout core
/// addresses y down from the top of the ink box, so the baseline sits
/// H - y above the context origin.
fn glyphBaseY(baseline_y: i32, s: f64, pad: f64, H: f64) f64 {
    return H - (@as(f64, @floatFromInt(baseline_y)) * s + pad);
}

/// Quartz (y-up) origin y for a rule rect whose layout `y` is its top
/// edge measured down from the top of the ink box: same H - y flip as
/// glyph baselines, minus the rect height (origin is bottom-left).
fn ruleOriginY(y: i32, h_units: u32, s: f64, pad: f64, H: f64) f64 {
    const top_px = @as(f64, @floatFromInt(y)) * s + pad;
    return H - top_px - @as(f64, @floatFromInt(h_units)) * s;
}

test "rules share the glyph H-y mapping" {
    // \frac{a}{b} at --px 200: layout baselines 490/1895, bar top 765
    // with h=40, canvas 446 px tall with 16 px padding. The bar must
    // land on the same top-left-origin rows the canvas was sized for
    // (169..177), strictly between the two glyph baselines.
    const s = 0.2;
    const pad = 16.0;
    const H = 446.0;
    // PNG row of a Quartz point y is H - 1 - y.
    const num_row = H - 1 - glyphBaseY(490, s, pad, H); // 113
    const den_row = H - 1 - glyphBaseY(1895, s, pad, H); // 394
    const bar_qy = ruleOriginY(765, 40, s, pad, H);
    const bar_top = H - bar_qy - 40 * s; // PNG row of rect top: 169
    try std.testing.expectEqual(113.0, num_row);
    try std.testing.expectEqual(394.0, den_row);
    try std.testing.expectEqual(169.0, bar_top);
    try std.testing.expect(num_row < bar_top and bar_top < den_row);
}

fn readPoolFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(32 * 1024 * 1024));
}

test "canvas pool renders byte-identically, hit and miss" {
    // Pooled renders must be pixel-exact: same-size reuse (hit) fully
    // repaints, and size mismatch (miss) recreates — both compare
    // byte-for-byte against the unpooled path. Unique scratch dir per
    // run (sw_png precedent: test binaries run concurrently).
    const alloc = std.testing.allocator;
    var font = try Font.load(alloc, @import("build_options").fixture_font);
    defer font.close();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var runs_a: [256]zatex.ir.Run = undefined;
    var rules_a: [64]zatex.ir.Rule = undefined;
    var glyphs_a: [4096]u16 = undefined;
    var runs_b: [256]zatex.ir.Run = undefined;
    var rules_b: [64]zatex.ir.Rule = undefined;
    var glyphs_b: [4096]u16 = undefined;
    var diag = zatex.Diag.empty();
    // Separate buffers per layout: run glyph slices borrow the glyph
    // buffer, so sharing would clobber the first layout.
    const la = try zatex.layoutDiag("x^2+\\frac{a}{b}", .{}, font.provider(), &runs_a, &rules_a, &glyphs_a, &diag);
    // A tiny layout: its canvas differs from `la`'s in both dimensions,
    // so the pool path below exercises a real size miss, not a hit.
    const lb = try zatex.layoutDiag("x", .{}, font.provider(), &runs_b, &rules_b, &glyphs_b, &diag);

    var pool = CanvasPool{};
    defer pool.deinit();
    var pn: [5][256]u8 = undefined;
    const names = [_][]const u8{ "pool_a.png", "pool_b.png", "pool_c.png", "pool_d.png", "pool_e.png" };
    var paths: [5][]const u8 = undefined;
    for (names, 0..) |nm, i| {
        paths[i] = try std.fmt.bufPrint(&pn[i], ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, nm });
    }

    // Unpooled baseline, then two pooled renders of the same layout
    // (miss then hit: both canvases are cached-and-returned).
    try renderToPng(&font, la, 48, 16, paths[0]);
    try std.testing.expect(pool.cached == null);
    try renderToPngPooled(&font, la, 48, 16, paths[1], &pool);
    try std.testing.expect(pool.cached != null);
    try renderToPngPooled(&font, la, 48, 16, paths[2], &pool);
    try std.testing.expect(pool.cached != null);

    // A different-size layout misses (recreates), then the first
    // layout misses again — both still byte-identical. The dimension
    // asserts prove these were real misses, not accidental hits.
    try renderToPngPooled(&font, lb, 48, 16, paths[3], &pool);
    const mw = pool.w;
    const mh = pool.h;
    try renderToPngPooled(&font, la, 48, 16, paths[4], &pool);
    try std.testing.expect(pool.w != mw or pool.h != mh);

    const ba = try readPoolFile(alloc, paths[0]);
    defer alloc.free(ba);
    const bb = try readPoolFile(alloc, paths[1]);
    defer alloc.free(bb);
    const bc = try readPoolFile(alloc, paths[2]);
    defer alloc.free(bc);
    const be = try readPoolFile(alloc, paths[4]);
    defer alloc.free(be);
    try std.testing.expectEqualSlices(u8, ba, bb);
    try std.testing.expectEqualSlices(u8, ba, bc);
    try std.testing.expectEqualSlices(u8, ba, be);
}
