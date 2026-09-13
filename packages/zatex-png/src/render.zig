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
    const w: usize = @max(1, ceilU(@as(f64, @floatFromInt(layout.width)) * s + 2 * pad));
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
    // Rules (fraction bars, vincula) are plain filled rects.
    for (layout.rules) |r| {
        const rx = @as(f64, @floatFromInt(r.x)) * s + pad;
        const rw = @as(f64, @floatFromInt(r.w)) * s;
        const rh = @as(f64, @floatFromInt(r.h)) * s;
        const ry = ruleOriginY(r.y, r.h, s, pad, H);
        canvas.fillRect(rx, ry, rw, rh);
    }

    // Runs: one backend run per run size, glyph origins stepped with
    // the same integer advances the core measured, scaled once to
    // pixels.
    for (layout.runs) |run| {
        const px_size: f64 = @as(f64, @floatFromInt(run.size_units)) *
            @as(f64, @floatFromInt(px_per_em)) / 1000.0;
        if (px_size <= 0 or run.glyphs.len == 0) continue;
        var rf = try canvas.beginRun(&font.handle, px_size);
        defer rf.end();
        var x_units: i64 = run.x;
        const base_y: f64 = glyphBaseY(run.baseline_y, s, pad, H);
        for (run.glyphs) |g| {
            const gx: f64 = @as(f64, @floatFromInt(x_units)) * s + pad;
            rf.drawGlyph(g, gx, base_y);
            x_units += @divTrunc(
                @as(i64, font.advance1000(g)) * @as(i64, run.size_units),
                1000,
            );
        }
    }

    try canvas.writePng(out_path);
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
