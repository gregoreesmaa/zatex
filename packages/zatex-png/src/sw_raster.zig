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
const Seg = @import("sw_font.zig").Seg;

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
    const ia = 1 - a;
    const r: f64 = @floatFromInt(p[0]);
    const g: f64 = @floatFromInt(p[1]);
    const b: f64 = @floatFromInt(p[2]);
    p[0] = @intFromFloat(@max(0, @min(255, col.r * 255 * a + r * ia + 0.5)));
    p[1] = @intFromFloat(@max(0, @min(255, col.g * 255 * a + g * ia + 0.5)));
    p[2] = @intFromFloat(@max(0, @min(255, col.b * 255 * a + b * ia + 0.5)));
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
            if (cov > 0) blendPixel(pixels[prow * cw * 4 + px * 4 ..][0..4], col, col.a * @as(f64, @floatCast(cov)));
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

