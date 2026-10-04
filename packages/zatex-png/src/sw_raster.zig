//! Scanline rasterizer for the software backend: path segments in,
//! covered pixels out. No allocation, no host calls — portable across
//! every OS the software backend serves.
//!
//! Fill rule is nonzero winding (what CFF/PostScript fills use).
//! Antialiasing is 4x4 ordered-grid supersampling resolved through a
//! per-row crossing walk: each output row processes its 4 sub-rows,
//! collects line crossings, sorts them, and fills spans with a nonzero
//! winding count. Curves are flattened once per glyph (tolerance 0.25
//! device px) into a caller line buffer; overflow truncates gracefully
//! (draws a subset — deterministic, and caps are sized so the fixture
//! never gets near them).
const std = @import("std");
const Seg = @import("cff").Seg;

/// Straight segment in device pixels (y-up, canvas space).
pub const Line = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
};

/// Fill color, straight (non-premultiplied) components in 0..1.
pub const Color = struct {
    r: f64,
    g: f64,
    b: f64,
    a: f64 = 1,
};

pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 1 };
pub const white = Color{ .r = 1, .g = 1, .b = 1, .a = 1 };

/// Flatten `segs` (font units) into device-space lines at (`sx`, `sy`)
/// (px per font unit) offset by (`ox`, `oy`), returning the used
/// prefix of `out`. The split scales exist for run raster-stretch
/// (wide accents, brace spans — issues #31/#37); uniform text passes
/// `sx == sy`. `sh` shears ink right by `sh` device px per device px
/// above the baseline at `oy` (faux math-italic for dotless i/j,
/// issue #77); 0 disables. Device space is y-up, so height above the
/// baseline is just `y*sy`. Shear applies at the segment level, before
/// curve subdivision, which already runs in device space. Curves
/// subdivide to 0.25px flatness, depth-capped.
pub fn flatten(segs: []const Seg, sx: f64, sy: f64, ox: f64, oy: f64, sh: f64, out: []Line) []Line {
    var n: usize = 0;
    for (segs) |s| {
        const ax = ox + s.x[0] * sx + sh * (s.y[0] * sy);
        const ay = oy + s.y[0] * sy;
        if (!s.is_curve) {
            if (n < out.len) {
                out[n] = .{
                    .x0 = @floatCast(ax),
                    .y0 = @floatCast(ay),
                    .x1 = @floatCast(ox + s.x[3] * sx + sh * (s.y[3] * sy)),
                    .y1 = @floatCast(oy + s.y[3] * sy),
                };
                n += 1;
            }
        } else {
            n = flattenCubic(
                ax,
                ay,
                ox + s.x[1] * sx + sh * (s.y[1] * sy),
                oy + s.y[1] * sy,
                ox + s.x[2] * sx + sh * (s.y[2] * sy),
                oy + s.y[2] * sy,
                ox + s.x[3] * sx + sh * (s.y[3] * sy),
                oy + s.y[3] * sy,
                out,
                n,
                0,
            );
        }
    }
    return out[0..n];
}

fn flattenCubic(x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64, out: []Line, n: usize, depth: u8) usize {
    var m = n;
    // Flatness: max control deviation from the chord, squared.
    const ux = 3 * x1 - 2 * x0 - x3;
    const uy = 3 * y1 - 2 * y0 - y3;
    const vx = 3 * x2 - 2 * x3 - x0;
    const vy = 3 * y2 - 2 * y3 - y0;
    // Flat when both deviation vectors fit in 0.25px (squared <= 1/16).
    if (depth >= 16 or (ux * ux + uy * uy + vx * vx + vy * vy) <= 0.0625) {
        if (m < out.len) {
            out[m] = .{ .x0 = @floatCast(x0), .y0 = @floatCast(y0), .x1 = @floatCast(x3), .y1 = @floatCast(y3) };
            m += 1;
        }
        return m;
    }
    const mx01 = (x0 + x1) / 2;
    const my01 = (y0 + y1) / 2;
    const mx12 = (x1 + x2) / 2;
    const my12 = (y1 + y2) / 2;
    const mx23 = (x2 + x3) / 2;
    const my23 = (y2 + y3) / 2;
    const ax = (mx01 + mx12) / 2;
    const ay = (my01 + my12) / 2;
    const bx = (mx12 + mx23) / 2;
    const by = (my12 + my23) / 2;
    const cx = (ax + bx) / 2;
    const cy = (ay + by) / 2;
    m = flattenCubic(x0, y0, mx01, my01, ax, ay, cx, cy, out, m, depth + 1);
    m = flattenCubic(cx, cy, bx, by, mx23, my23, x3, y3, out, m, depth + 1);
    return m;
}

const SS = 4; // supersample factor per axis
const MAX_XSECT = 256; // crossings per sub-row; clipped beyond (never hit by math glyphs)

const Xsect = struct { x: f32, dir: i32 };

/// Source-over blend of `col` at effective alpha `a` onto RGBA pixel `p`.
fn blendPixel(p: *[4]u8, col: Color, a: f64) void {
    if (a <= 0) return;
    if (a == 1) {
        // Opaque store (issue #285): at `a == 1` the float blend below
        // reduces to `q*255 + 0.5` per channel — the store below
        // computes exactly those bytes, so skip the float math and
        // the `p` read. Any `a < 1` takes the blend: near-opaque
        // alphas can round a different byte (pinned by the test).
        const s = opaqueBytes(col);
        p[0] = s[0];
        p[1] = s[1];
        p[2] = s[2];
        return;
    }
    const ia = 1 - a;
    const r: f64 = @floatFromInt(p[0]);
    const g: f64 = @floatFromInt(p[1]);
    const b: f64 = @floatFromInt(p[2]);
    p[0] = @intFromFloat(@max(0, @min(255, col.r * 255 * a + r * ia + 0.5)));
    p[1] = @intFromFloat(@max(0, @min(255, col.g * 255 * a + g * ia + 0.5)));
    p[2] = @intFromFloat(@max(0, @min(255, col.b * 255 * a + b * ia + 0.5)));
}

/// Source color as stored bytes (`+ 0.5` matches `blendPixel`'s round).
fn opaqueBytes(col: Color) [3]u8 {
    return .{
        @intFromFloat(@max(0, @min(255, col.r * 255 + 0.5))),
        @intFromFloat(@max(0, @min(255, col.g * 255 + 0.5))),
        @intFromFloat(@max(0, @min(255, col.b * 255 + 0.5))),
    };
}

/// Fill flattened device-space lines (y-up canvas space) into `pixels`
/// (top-left row-major RGBA, `cw` x `ch`). Nonzero winding, 4x4
/// supersampled. `row_cov` is caller scratch of at least `cw` f32s.
pub fn fillLines(pixels: []u8, cw: usize, ch: usize, lines: []const Line, col: Color, row_cov: []f32) void {
    if (lines.len == 0 or col.a <= 0) return;
    std.debug.assert(row_cov.len >= cw);
    // Device bbox of the lines, clipped to the canvas.
    var bx0: f32 = std.math.inf(f32);
    var by0: f32 = std.math.inf(f32);
    var bx1: f32 = -std.math.inf(f32);
    var by1: f32 = -std.math.inf(f32);
    for (lines) |l| {
        bx0 = @min(bx0, @min(l.x0, l.x1));
        by0 = @min(by0, @min(l.y0, l.y1));
        bx1 = @max(bx1, @max(l.x0, l.x1));
        by1 = @max(by1, @max(l.y0, l.y1));
    }
    // NaN fails every comparison below and clips to empty; finite
    // out-of-range edges clamp into the canvas before any cast.
    if (!(bx0 < bx1) or !(by0 < by1)) return;
    const cwf: f32 = @floatFromInt(cw);
    const chf: f32 = @floatFromInt(ch);
    const fx0 = @max(0, @min(cwf, bx0));
    const fy0 = @max(0, @min(chf, by0));
    const fx1 = @max(0, @min(cwf, bx1));
    const fy1 = @max(0, @min(chf, by1));
    if (!(fx0 < fx1) or !(fy0 < fy1)) return;
    const rx0: usize = @intFromFloat(@floor(fx0));
    const ry0: usize = @intFromFloat(@floor(fy0));
    const rx1: usize = @intFromFloat(@ceil(fx1));
    const ry1: usize = @intFromFloat(@ceil(fy1));

    var xs: [MAX_XSECT]Xsect = undefined;
    // Opaque fast path (issue #285): when the paint is opaque
    // (`col.a == 1`) and the pixel fully covered (`cov == 1`), the
    // effective alpha is exactly 1, so `blendPixel` would store —
    // store here directly with the precomputed bytes. Anything else
    // (translucent paint, fringe coverage) blends the old way.
    const opaque_fill = col.a == 1;
    const solid = opaqueBytes(col);
    var row = ry0;
    while (row < ry1) : (row += 1) {
        @memset(row_cov[rx0..rx1], 0);
        var s: usize = 0;
        while (s < SS) : (s += 1) {
            const ys: f32 = @as(f32, @floatFromInt(row)) + (@as(f32, @floatFromInt(s)) + 0.5) / SS;
            var nxs: usize = 0;
            for (lines) |l| {
                const lo = @min(l.y0, l.y1);
                const hi = @max(l.y0, l.y1);
                if (ys < lo or ys >= hi or nxs >= MAX_XSECT) continue;
                const t = (ys - l.y0) / (l.y1 - l.y0);
                xs[nxs] = .{ .x = l.x0 + t * (l.x1 - l.x0), .dir = if (l.y1 > l.y0) @as(i32, 1) else -1 };
                nxs += 1;
            }
            // Insertion sort: crossing counts are tiny.
            var i: usize = 1;
            while (i < nxs) : (i += 1) {
                const k = xs[i];
                var j = i;
                while (j > 0 and xs[j - 1].x > k.x) : (j -= 1) xs[j] = xs[j - 1];
                xs[j] = k;
            }
            var wind: i32 = 0;
            var k: usize = 0;
            while (k < nxs) : (k += 1) {
                const xa = xs[k].x;
                wind += xs[k].dir;
                const xb = if (k + 1 < nxs) xs[k + 1].x else xa;
                if (wind != 0 and xb > xa) {
                    const a = @max(xa, @as(f32, @floatFromInt(rx0)));
                    const b = @min(xb, @as(f32, @floatFromInt(rx1)));
                    var px: usize = @as(usize, @intFromFloat(a));
                    if (px < rx0) px = rx0;
                    while (px < rx1 and @as(f32, @floatFromInt(px)) < b) : (px += 1) {
                        const lo = @max(a, @as(f32, @floatFromInt(px)));
                        const hi = @min(b, @as(f32, @floatFromInt(px + 1)));
                        if (hi > lo) row_cov[px] += (hi - lo) / SS;
                    }
                }
            }
        }
        const prow = ch - 1 - row; // canvas rows are top-left
        var px = rx0;
        while (px < rx1) : (px += 1) {
            const cov = @min(1, row_cov[px]);
            if (cov <= 0) continue;
            if (opaque_fill and cov == 1) {
                // `a == 1` floats store exactly (see `blendPixel`),
                // so coverage 1 stores the color: same bytes as the
                // old float path for stems and bar interiors.
                const p = pixels[prow * cw * 4 + px * 4 ..][0..4];
                p[0] = solid[0];
                p[1] = solid[1];
                p[2] = solid[2];
                continue;
            }
            blendPixel(pixels[prow * cw * 4 + px * 4 ..][0..4], col, col.a * @as(f64, @floatCast(cov)));
        }
    }
}

/// Fill an axis-aligned rect in bottom-left float coords (source-over).
pub fn fillRect(pixels: []u8, cw: usize, ch: usize, x: f64, y: f64, w: f64, h: f64, col: Color) void {
    if (!(w > 0) or !(h > 0) or col.a <= 0) return;
    const cwf: f64 = @floatFromInt(cw);
    const chf: f64 = @floatFromInt(ch);
    // Clamp both edges into [0, dim]: rules entirely off-canvas (or
    // NaN-carrying, which fails the `!(w > 0)` guard above) clip to
    // empty instead of panicking the float->int cast.
    const x0 = @max(0, @min(cwf, x));
    const y0 = @max(0, @min(chf, y));
    const x1 = @max(0, @min(cwf, x + w));
    const y1 = @max(0, @min(chf, y + h));
    if (x1 <= x0 or y1 <= y0) return;
    // Integer fast path (issue #285): opaque axis-aligned rects touch
    // no fringe pixels, so per-pixel fx*fy float coverage + blend is
    // pure overhead. Store whole rows directly (the canvas clear in
    // `render.zig` takes this path on every bitmap). `a=1` floats
    // still print/store exactly (0.1 + 0.2 aside, colors come from
    // `/255` ratios or unit constants), so the guard is exact
    // equality; anything else blends the old way. Alpha stays 255:
    // every cleared pixel starts opaque and fills keep it opaque.
    if (col.a == 1 and x0 == @floor(x0) and y0 == @floor(y0) and x1 == @ceil(x1) and y1 == @ceil(y1)) {
        const s = opaqueBytes(col);
        const ix0: usize = @min(cw, @as(usize, @intFromFloat(x0)));
        const iy0: usize = @min(ch, @as(usize, @intFromFloat(y0)));
        const ix1: usize = @min(cw, @as(usize, @intFromFloat(x1)));
        const iy1: usize = @min(ch, @as(usize, @intFromFloat(y1)));
        if (ix0 < ix1 and iy0 < iy1) {
            const wbytes = (ix1 - ix0) * 4;
            var iy = iy0;
            while (iy < iy1) : (iy += 1) {
                const row = pixels[(ch - 1 - iy) * cw * 4 + ix0 * 4 ..][0..wbytes];
                var k: usize = 0;
                while (k < wbytes) : (k += 4) {
                    row[k] = s[0];
                    row[k + 1] = s[1];
                    row[k + 2] = s[2];
                }
            }
        }
        return;
    }
    const ix0: usize = @min(cw, @as(usize, @intFromFloat(@floor(x0))));
    var iy0: usize = @min(ch, @as(usize, @intFromFloat(@floor(y0))));
    const ix1: usize = @min(cw, @as(usize, @intFromFloat(@ceil(x1))));
    const iy1: usize = @min(ch, @as(usize, @intFromFloat(@ceil(y1))));
    while (iy0 < iy1) : (iy0 += 1) {
        const lo_y = @max(y0, @as(f64, @floatFromInt(iy0)));
        const hi_y = @min(y1, @as(f64, @floatFromInt(iy0 + 1)));
        const fy = hi_y - lo_y;
        if (fy <= 0) continue;
        var ix = ix0;
        while (ix < ix1) : (ix += 1) {
            const lo_x = @max(x0, @as(f64, @floatFromInt(ix)));
            const hi_x = @min(x1, @as(f64, @floatFromInt(ix + 1)));
            const fx = hi_x - lo_x;
            if (fx <= 0) continue;
            const prow = ch - 1 - iy0;
            blendPixel(pixels[prow * cw * 4 + ix * 4 ..][0..4], col, col.a * fx * fy);
        }
    }
}

/// Butt-cap thick segment in bottom-left float coords, source-over
/// (diagonal strikes, issue #107). Coverage is analytic: each pixel
/// square is clipped against the segment's edge half-planes and butt
/// caps, so an axis-aligned stroke agrees with `fillRect` exactly
/// (pinned by the test below) and diagonals antialias like KaTeX's
/// SVG line. Zero-length segments draw nothing (butt caps meet).
pub fn strokeLine(pixels: []u8, cw: usize, ch: usize, x0: f64, y0: f64, x1: f64, y1: f64, t: f64, col: Color) void {
    if (!(t > 0) or col.a <= 0) return;
    // Axis-aligned strokes are the rect the caps degenerate to (the
    // equivalence is pinned by the tests below), so route them
    // through fillRect (issue #285): one interval fill per row
    // instead of a 4-plane Sutherland clip + shoelace per pixel.
    // `t` is exact in f64 for every thickness the core emits
    // (integer thousandths scaled once), so the equality guard reads
    // straight-line rules (fraction bars, vincula) exactly.
    if (x0 == x1) {
        const hw = t / 2;
        fillRect(pixels, cw, ch, x0 - hw, @min(y0, y1), t, @abs(y1 - y0), col);
        return;
    }
    if (y0 == y1) {
        const hw = t / 2;
        fillRect(pixels, cw, ch, @min(x0, x1), y0 - hw, @abs(x1 - x0), t, col);
        return;
    }
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len2 = dx * dx + dy * dy;
    if (!(len2 > 0)) return;
    const len = @sqrt(len2);
    // Unit direction and left normal; half-planes: |n.p| <= hw caps
    // the edges, 0 <= d.p <= len caps the butt ends (p from p0).
    const ux = dx / len;
    const uy = dy / len;
    const nx = -uy;
    const ny = ux;
    const hw = t / 2;
    // Bounding box of the parallelogram, clamped into the canvas.
    const px0 = @min(x0, x1) - @abs(nx) * hw;
    const px1 = @max(x0, x1) + @abs(nx) * hw;
    const py0 = @min(y0, y1) - @abs(ny) * hw;
    const py1 = @max(y0, y1) + @abs(ny) * hw;
    // Scanline intervals (issue #285): the band meets scan row `iy`
    // where the center line crosses it, so the ink span is analytic —
    // no per-pixel Sutherland clip. Past this point the stroke is
    // strictly diagonal (`x0 == x1` / `y0 == y1` returned above), so
    // `ux` and `nx` are both nonzero and the slopes below divide
    // safely. At fixed height `fy` the edge constraint
    // `|nx*(fx-x0) + ny*(fy-y0)| <= hw` spans
    // `fxc(fy) ± hw/|nx|` around the center crossing
    // `fxc(fy) = x0 - ny*(fy-y0)/nx`, and the butt caps
    // `0 <= ux*(fx-x0) + uy*(fy-y0) <= len` span the segment
    // endpoints' crossings `fxe(fy, e) = x0 + (e-uy*(fy-y0))/ux`
    // for `e` in `{0, len}`. Both move linearly in `fy`, so the
    // row union is the min/max over its two edges — rows whose span
    // is empty (or outside the bbox) skip the pixel loop entirely,
    // and surviving rows only walk their ink span instead of the
    // whole bbox width (a cancel box clips ~400k pixel walks down
    // to its ink rows). Coverage per pixel still runs through
    // `segCoverage` unchanged, so bytes are identical.
    const iy0: usize = @min(ch, @as(usize, @intFromFloat(@max(0, @floor(py0)))));
    const iy1: usize = @min(ch, @as(usize, @intFromFloat(@max(0, @ceil(py1)))));
    const ix0: usize = @min(cw, @as(usize, @intFromFloat(@max(0, @floor(px0)))));
    const ix1: usize = @min(cw, @as(usize, @intFromFloat(@max(0, @ceil(px1)))));
    // Reciprocals hoisted out of the row loop (same values the old
    // code recomputed per pixel inside `segCoverage`'s clip setup).
    const inv_nx = 1 / nx;
    const inv_ux = 1 / ux;
    const hw_nx = hw / @abs(nx);
    var iy = iy0;
    while (iy < iy1) : (iy += 1) {
        // Ink span of this row: union over its [iy, iy+1] edges of the
        // edge-band span and the butt-cap span, floored/ceiled outward
        // by one (conservative: the span only ever *widens* the pixel
        // walk; pixels it wrongly admits compute cov 0 and store
        // nothing).
        const fy0: f64 = @floatFromInt(iy);
        const fy1: f64 = @floatFromInt(iy + 1);
        const fc0 = x0 - ny * (fy0 - y0) * inv_nx;
        const fc1 = x0 - ny * (fy1 - y0) * inv_nx;
        const c_lo = @min(fc0, fc1) - hw_nx;
        const c_hi = @max(fc0, fc1) + hw_nx;
        const e00 = x0 + (0 - uy * (fy0 - y0)) * inv_ux;
        const e01 = x0 + (0 - uy * (fy1 - y0)) * inv_ux;
        const e10 = x0 + (len - uy * (fy0 - y0)) * inv_ux;
        const e11 = x0 + (len - uy * (fy1 - y0)) * inv_ux;
        const e_lo = @min(@min(e00, e01), @min(e10, e11));
        const e_hi = @max(@max(e00, e01), @max(e10, e11));
        var sx0 = @max(c_lo, e_lo) - 1;
        var sx1 = @min(c_hi, e_hi) + 1;
        if (sx0 < @as(f64, @floatFromInt(ix0))) sx0 = @as(f64, @floatFromInt(ix0));
        if (sx1 > @as(f64, @floatFromInt(ix1))) sx1 = @as(f64, @floatFromInt(ix1));
        const jx0: usize = @min(ix1, @as(usize, @intFromFloat(@max(0, @floor(sx0)))));
        const jx1: usize = @min(ix1, @as(usize, @intFromFloat(@max(0, @ceil(sx1)))));
        var ix = jx0;
        while (ix < jx1) : (ix += 1) {
            const fx: f64 = @floatFromInt(ix);
            const fy: f64 = @floatFromInt(iy);
            const cov = segCoverage(fx - x0, fy - y0, ux, uy, nx, ny, hw, len);
            if (cov > 0) {
                const prow = ch - 1 - iy;
                blendPixel(pixels[prow * cw * 4 + ix * 4 ..][0..4], col, col.a * cov);
            }
        }
    }
}

/// Coverage of the unit square `[ox, ox+1] x [oy, oy+1]` (offset from
/// the segment start) by the butt-cap half-width-`hw` band: clip the
/// square against the four half-planes, measure what survives.
fn segCoverage(ox: f64, oy: f64, ux: f64, uy: f64, nx: f64, ny: f64, hw: f64, len: f64) f64 {
    var xs: [10]f64 = .{ ox, ox + 1, ox + 1, ox, 0, 0, 0, 0, 0, 0 };
    var ys: [10]f64 = .{ oy, oy, oy + 1, oy + 1, 0, 0, 0, 0, 0, 0 };
    var n: usize = 4;
    // Each half-plane keeps a*x + b*y <= c.
    const planes = [4][3]f64{
        .{ nx, ny, hw },
        .{ -nx, -ny, hw },
        .{ ux, uy, len },
        .{ -ux, -uy, 0 },
    };
    for (planes) |pl| {
        var oxs: [10]f64 = undefined;
        var oys: [10]f64 = undefined;
        var m: usize = 0;
        if (n == 0) return 0;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const j = (i + 1) % n;
            const di = pl[0] * xs[i] + pl[1] * ys[i] - pl[2];
            const dj = pl[0] * xs[j] + pl[1] * ys[j] - pl[2];
            if (di <= 0) {
                oxs[m] = xs[i];
                oys[m] = ys[i];
                m += 1;
            }
            if ((di <= 0) != (dj <= 0)) {
                const f = di / (di - dj);
                oxs[m] = xs[i] + (xs[j] - xs[i]) * f;
                oys[m] = ys[i] + (ys[j] - ys[i]) * f;
                m += 1;
            }
        }
        @memcpy(xs[0..m], oxs[0..m]);
        @memcpy(ys[0..m], oys[0..m]);
        n = m;
    }
    if (n < 3) return 0;
    var area: f64 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const j = (i + 1) % n;
        area += xs[i] * ys[j] - xs[j] * ys[i];
    }
    const cov = @abs(area) / 2;
    return @min(1, @max(0, cov));
}

test "strokeLine horizontal matches fillRect exactly" {
    // A horizontal butt-cap stroke is the same ink as the equivalent
    // fill (issue #107): byte-identical pixels, not just coverage.
    var a: [12 * 8 * 4]u8 = @splat(255);
    var b: [12 * 8 * 4]u8 = @splat(255);
    strokeLine(&a, 12, 8, 1, 4, 10, 4, 3, black);
    fillRect(&b, 12, 8, 1, 2.5, 9, 3, black);
    try std.testing.expectEqualSlices(u8, &b, &a);
}

test "strokeLine vertical matches fillRect exactly" {
    var a: [8 * 12 * 4]u8 = @splat(255);
    var b: [8 * 12 * 4]u8 = @splat(255);
    strokeLine(&a, 8, 12, 4, 1, 4, 10, 3, black);
    fillRect(&b, 8, 12, 2.5, 1, 3, 9, black);
    try std.testing.expectEqualSlices(u8, &b, &a);
}

test "strokeLine zero-length draws nothing, diagonals mirror" {
    var a: [10 * 10 * 4]u8 = @splat(255);
    strokeLine(&a, 10, 10, 5, 5, 5, 5, 3, black);
    for (a) |v| try std.testing.expectEqual(@as(u8, 255), v);
    // Up vs down diagonals are vertical mirrors of each other (up
    // to float rounding in the coverage: one byte of slack).
    var u: [11 * 11 * 4]u8 = @splat(255);
    var d: [11 * 11 * 4]u8 = @splat(255);
    strokeLine(&u, 11, 11, 1, 1, 9, 9, 2, black);
    strokeLine(&d, 11, 11, 1, 9, 9, 1, 2, black);
    var y: usize = 0;
    // Row pairs (10-y, y+1); the outer rows pair off-canvas (both
    // segments stay clear of them — asserted empty below).
    while (y < 10) : (y += 1) {
        var x: usize = 0;
        while (x < 11) : (x += 1) {
            // Canvas rows mirror about y=5: pixel [iy,iy+1] pairs
            // with [9-iy,10-iy], i.e. buffer rows (10-iy) and (iy+1).
            const pu = u[(10 - y) * 11 * 4 + x * 4 ..][0..4];
            const pd = d[(y + 1) * 11 * 4 + x * 4 ..][0..4];
            for (pu, pd) |va, vb| {
                const diff = if (va > vb) va - vb else vb - va;
                try std.testing.expect(diff <= 1);
            }
        }
    }
    for (u[0 .. 11 * 4]) |v| try std.testing.expectEqual(@as(u8, 255), v);
    for (d[0 .. 11 * 4]) |v| try std.testing.expectEqual(@as(u8, 255), v);
    // Butt caps: a fractional endpoint half-covers the cap pixel,
    // while a pixel well inside the band is fully covered.
    var c: [8 * 8 * 4]u8 = @splat(255);
    strokeLine(&c, 8, 8, 0.5, 3, 7, 3, 2, black);
    const cap = c[(8 - 1 - 3) * 8 * 4 + 0 * 4];
    try std.testing.expect(cap > 0 and cap < 255);
    const mid = c[(8 - 1 - 3) * 8 * 4 + 4 * 4];
    try std.testing.expectEqual(@as(u8, 0), mid);
}

test "fillRect covers exactly and blends edges" {
    const alloc = std.testing.allocator;
    const cw: usize = 6;
    const ch: usize = 6;
    const px = try alloc.alloc(u8, cw * ch * 4);
    defer alloc.free(px);
    @memset(px, 255);
    fillRect(px, cw, ch, 1, 1, 3, 3, black);
    // Interior pixel fully black, exterior fully white.
    try std.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px[(ch - 1 - 2) * cw * 4 + 2 * 4 ..][0..4].*);
    try std.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px[(ch - 1 - 0) * cw * 4 + 0 * 4 ..][0..4].*);
    // Half-covered edge pixel blends to mid grey.
    @memset(px, 255);
    fillRect(px, cw, ch, 1.5, 1, 2, 2, black);
    const edge = px[(ch - 1 - 1) * cw * 4 + 1 * 4];
    try std.testing.expect(edge > 100 and edge < 160);
}

test "fillLines fills a triangle with nonzero winding" {
    const alloc = std.testing.allocator;
    const cw: usize = 8;
    const ch: usize = 8;
    const px = try alloc.alloc(u8, cw * ch * 4);
    defer alloc.free(px);
    @memset(px, 255);
    const cov = try alloc.alloc(f32, cw);
    defer alloc.free(cov);
    const tri = [_]Line{
        .{ .x0 = 1, .y0 = 1, .x1 = 7, .y1 = 1 },
        .{ .x0 = 7, .y0 = 1, .x1 = 4, .y1 = 7 },
        .{ .x0 = 4, .y0 = 7, .x1 = 1, .y1 = 1 },
    };
    fillLines(px, cw, ch, &tri, black, cov);
    // Centroid pixel solid, far corner white.
    try std.testing.expect(px[(ch - 1 - 3) * cw * 4 + 4 * 4] < 32);
    try std.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px[(ch - 1 - 7) * cw * 4 + 0 * 4 ..][0..4].*);
}

test "opaque fast paths store byte-identical pixels (issue #285)" {
    // The opaque store fires if and only if `a == 1`: at exactly 1
    // the float blend reproduces the source byte, so storing skips
    // identical math. Any `a < 1` blends, even just below 1 — the
    // float path can round a different byte there (gray 0.5 over
    // black at a=0.9981 blends to 127, storing would print 128).
    const gray_half: Color = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1 };
    var near_opaque: [4]u8 = .{ 0, 0, 0, 255 };
    blendPixel(&near_opaque, gray_half, 0.9981);
    try std.testing.expectEqual([4]u8{ 127, 127, 127, 255 }, near_opaque);
    // `blendPixel` at full coverage stores the source color: the
    // fast-path store must agree with the float blend exactly, even
    // off-white and off-black.
    const cols = [_]Color{
        black,
        white,
        .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        .{ .r = 0.2, .g = 0.6, .b = 1, .a = 1 },
        .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    };
    const dsts = [_][4]u8{ .{ 0, 0, 0, 255 }, .{ 255, 255, 255, 255 }, .{ 13, 200, 77, 255 }, .{ 1, 2, 3, 255 } };
    for (cols) |col| {
        for (dsts) |d| {
            var via_store: [4]u8 = d;
            blendPixel(&via_store, col, 1);
            // True opaque always rounds to the source byte exactly.
            const s = opaqueBytes(col);
            try std.testing.expectEqual(s[0], via_store[0]);
            try std.testing.expectEqual(s[1], via_store[1]);
            try std.testing.expectEqual(s[2], via_store[2]);
            try std.testing.expectEqual(d[3], via_store[3]);
        }
    }
    // Integer `fillRect` stores the same bytes as the fringe path:
    // an integer rect on a dirty canvas must equal the pre-#285
    // float loop (`fillRectRef` below) over the same geometry.
    const cw: usize = 7;
    const ch: usize = 5;
    var whole: [7 * 5 * 4]u8 = undefined;
    var refbuf: [7 * 5 * 4]u8 = undefined;
    for ([_]*[7 * 5 * 4]u8{ &whole, &refbuf }) |buf| {
        var i: usize = 0;
        while (i < buf.len) : (i += 1) buf[i] = @intCast((i * 31 + 7) & 0xFF);
        // Alpha must survive untouched (canvas stays opaque).
        var k: usize = 3;
        while (k < buf.len) : (k += 4) buf[k] = 255;
    }
    const col: Color = .{ .r = 0.9, .g = 0.1, .b = 0.4, .a = 1 };
    fillRect(&whole, cw, ch, 1, 1, 4, 3, col);
    fillRectRef(&refbuf, cw, ch, 1, 1, 4, 3, col);
    try std.testing.expectEqualSlices(u8, &refbuf, &whole);
}

/// Pre-#285 `fillRect` body: pure float fringe loop, no integer fast
/// path. Test-only reference for the equivalence test above; the
/// shipped path never calls it.
fn fillRectRef(pixels: []u8, cw: usize, ch: usize, x: f64, y: f64, w: f64, h: f64, col: Color) void {
    if (!(w > 0) or !(h > 0) or col.a <= 0) return;
    const cwf: f64 = @floatFromInt(cw);
    const chf: f64 = @floatFromInt(ch);
    const x0 = @max(0, @min(cwf, x));
    const y0 = @max(0, @min(chf, y));
    const x1 = @max(0, @min(cwf, x + w));
    const y1 = @max(0, @min(chf, y + h));
    if (x1 <= x0 or y1 <= y0) return;
    const ix0: usize = @min(cw, @as(usize, @intFromFloat(@floor(x0))));
    var iy0: usize = @min(ch, @as(usize, @intFromFloat(@floor(y0))));
    const ix1: usize = @min(cw, @as(usize, @intFromFloat(@ceil(x1))));
    const iy1: usize = @min(ch, @as(usize, @intFromFloat(@ceil(y1))));
    while (iy0 < iy1) : (iy0 += 1) {
        const lo_y = @max(y0, @as(f64, @floatFromInt(iy0)));
        const hi_y = @min(y1, @as(f64, @floatFromInt(iy0 + 1)));
        const fy = hi_y - lo_y;
        if (fy <= 0) continue;
        var ix = ix0;
        while (ix < ix1) : (ix += 1) {
            const lo_x = @max(x0, @as(f64, @floatFromInt(ix)));
            const hi_x = @min(x1, @as(f64, @floatFromInt(ix + 1)));
            const fx = hi_x - lo_x;
            if (fx <= 0) continue;
            const prow = ch - 1 - iy0;
            blendPixel(pixels[prow * cw * 4 + ix * 4 ..][0..4], col, col.a * fx * fy);
        }
    }
}

test "fillLines near-opaque paint blends, never stores (issue #285)" {
    // A translucent `col.a < 1` at full coverage must run the float
    // blend, not the opaque store: gray 0.5 at a=0.999 over black
    // blends to 127, storing would print 128.
    const cw: usize = 11;
    const ch: usize = 11;
    var px: [11 * 11 * 4]u8 = .{0} ** (11 * 11 * 4);
    var i: usize = 3;
    while (i < px.len) : (i += 4) px[i] = 255;
    var cov: [11]f32 = undefined;
    const tri = [_]Line{
        .{ .x0 = 0, .y0 = 0, .x1 = 11, .y1 = 0 },
        .{ .x0 = 11, .y0 = 0, .x1 = 5, .y1 = 11 },
        .{ .x0 = 5, .y0 = 11, .x1 = 0, .y1 = 0 },
    };
    const translucent: Color = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.999 };
    fillLines(&px, cw, ch, &tri, translucent, &cov);
    // Centroid pixel (5,3) is fully covered: must hold the blend.
    try std.testing.expectEqual([4]u8{ 127, 127, 127, 255 }, px[(ch - 1 - 3) * cw * 4 + 5 * 4 ..][0..4].*);
}

test "strokeLine diagonals match the unclipped path (issue #285)" {
    // The scanline-interval walk only narrows the pixel loop; every
    // visited pixel still runs the same `segCoverage`. Prove it by
    // re-running the old full-bbox walk inline and comparing bytes.
    const cases = [_][4]f64{
        .{ 1, 1, 9, 9 },
        .{ 1, 9, 9, 1 },
        .{ 0.5, 3, 7, 3.75 },
        .{ 2, 0.25, 8, 10 },
        .{ 10, 2, 1, 8 },
    };
    for (cases) |c| {
        var fast: [11 * 11 * 4]u8 = @splat(255);
        var ref: [11 * 11 * 4]u8 = @splat(255);
        strokeLine(&fast, 11, 11, c[0], c[1], c[2], c[3], 2, black);
        strokeLineRef(&ref, 11, 11, c[0], c[1], c[2], c[3], 2, black);
        try std.testing.expectEqualSlices(u8, &ref, &fast);
    }
}

/// Pre-#285 `strokeLine` body: full-bbox pixel walk, no scanline
/// intervals and no axis-aligned routing. Test-only reference for
/// the equivalence test above; the shipped path never calls it.
fn strokeLineRef(pixels: []u8, cw: usize, ch: usize, x0: f64, y0: f64, x1: f64, y1: f64, t: f64, col: Color) void {
    if (!(t > 0) or col.a <= 0) return;
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len2 = dx * dx + dy * dy;
    if (!(len2 > 0)) return;
    const len = @sqrt(len2);
    const ux = dx / len;
    const uy = dy / len;
    const nx = -uy;
    const ny = ux;
    const hw = t / 2;
    const px0 = @min(x0, x1) - @abs(nx) * hw;
    const px1 = @max(x0, x1) + @abs(nx) * hw;
    const py0 = @min(y0, y1) - @abs(ny) * hw;
    const py1 = @max(y0, y1) + @abs(ny) * hw;
    const iy0: usize = @min(ch, @as(usize, @intFromFloat(@max(0, @floor(py0)))));
    const iy1: usize = @min(ch, @as(usize, @intFromFloat(@max(0, @ceil(py1)))));
    const ix0: usize = @min(cw, @as(usize, @intFromFloat(@max(0, @floor(px0)))));
    const ix1: usize = @min(cw, @as(usize, @intFromFloat(@max(0, @ceil(px1)))));
    var iy = iy0;
    while (iy < iy1) : (iy += 1) {
        var ix = ix0;
        while (ix < ix1) : (ix += 1) {
            const fx: f64 = @floatFromInt(ix);
            const fy: f64 = @floatFromInt(iy);
            const cov = segCoverage(fx - x0, fy - y0, ux, uy, nx, ny, hw, len);
            if (cov > 0) {
                const prow = ch - 1 - iy;
                blendPixel(pixels[prow * cw * 4 + ix * 4 ..][0..4], col, col.a * cov);
            }
        }
    }
}

