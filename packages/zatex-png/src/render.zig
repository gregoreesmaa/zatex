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
    const w: usize = @max(1, ceilU(@as(f64, @floatFromInt(layout.width)) * s + 2 * pad + shift));
    const h: usize = @max(1, ceilU((@as(f64, @floatFromInt(layout.height_above)) +
        @as(f64, @floatFromInt(layout.depth_below))) * s + 2 * pad));

    var canvas = try backend.impl.Canvas.create(w, h);
    defer canvas.close();

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
        const rx = @as(f64, @floatFromInt(r.x)) * s + pad + shift;
        const rw = @as(f64, @floatFromInt(r.w)) * s;
        const rh = @as(f64, @floatFromInt(r.h)) * s;
        const ry = ruleOriginY(r.y, r.h, s, pad, H);
        setPaint(&canvas, r.color);
        if (r.diag == .none) {
            canvas.fillRect(rx, ry, rw, rh);
            continue;
        }
        // Canvas y of the rect's top and bottom edges (Quartz y-up).
        const y_top = H - (@as(f64, @floatFromInt(r.y)) * s + pad);
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
        var rf = try canvas.beginRun(&font.handle, px_size, sx, sh, run.mirrored);
        defer rf.end();
        var x_units: i64 = run.x;
        const base_y: f64 = glyphBaseY(run.baseline_y, s, pad, H);
        for (run.glyphs) |g| {
            const gx: f64 = @as(f64, @floatFromInt(x_units)) * s + pad + shift;
            rf.drawGlyph(g, gx, base_y);
            const step: i64 = @divTrunc(
                @as(i64, font.advance1000(g)) * @as(i64, run.size_units),
                1000,
            );
            // Identity scales step exactly as before.
            x_units += @divTrunc(step * @as(i64, run.x_scale), 1000);
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
            return f.handle.inkBounds1000(glyph)[0];
        }
        fn inkR(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.handle.inkBounds1000(glyph)[2];
        }
        fn top(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.handle.inkBounds1000(glyph)[3];
        }
        fn bot(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.handle.inkBounds1000(glyph)[1];
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
