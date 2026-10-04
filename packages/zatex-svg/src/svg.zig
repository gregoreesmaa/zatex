//! SVG emitter: geometric walker over `zatex.ir.Layout`.
//! Rules walk first (filled rects, diagonal strikes), then runs (one
//! soup path per run, transforms baked into coordinates), inside the
//! shift-fitted skeleton. Zero heap allocation; exhaustion is
//! `error.NoSpace`.
const std = @import("std");
const zatex = @import("zatex");
const cff = @import("cff");
const outlines_mod = @import("outlines.zig");

/// Walk `layout` into a standalone SVG document in `out`: shift-fit
/// the viewport, `skeletonHead`, rules loop, runs loop, `</svg>`.
/// `segs` is the single outline scratch shared by the draw walk and
/// the shift walks (sequential reuse, never nested): the shift walks
/// thread a slice of it through `inkThou` instead of burning a
/// per-glyph stack frame per call.
pub fn renderLayout(
    layout: zatex.ir.Layout,
    ol: outlines_mod.Outlines,
    segs: []cff.Seg,
    out: []u8,
) zatex.LayoutError![]u8 {
    var w = W{ .buf = out };
    return renderLayoutW(layout, ol, segs, &w);
}

/// Byte count the layout renders to: the same walk as
/// `renderLayout` through a measuring writer, so the CLI allocates
/// exactly what it writes instead of a fixed 1MB. Deterministic:
/// same input + same faces measure and write identical bytes.
pub fn measureLayout(
    layout: zatex.ir.Layout,
    ol: outlines_mod.Outlines,
    segs: []cff.Seg,
) zatex.LayoutError!usize {
    var w = W{ .buf = &.{}, .measure = true };
    _ = try renderLayoutW(layout, ol, segs, &w);
    return w.total;
}

fn renderLayoutW(
    layout: zatex.ir.Layout,
    ol: outlines_mod.Outlines,
    segs: []cff.Seg,
    w: *W,
) zatex.LayoutError![]u8 {
    // Per-render glyph cache (issue #282): the fused shift pass warms
    // it (one outline parse per distinct glyph), the runs loop reuses
    // it — repeat glyphs never re-parse. Stack-local, zero heap.
    var cache = GlyphCache{};
    const sh = shiftUnits(ol, &cache, segs, layout.runs, layout.rules, layout.width);
    const total_w = satI32(@as(i64, layout.width) + @as(i64, sh.left) + @as(i64, sh.right));
    const box_h = satI32(@as(i64, layout.height_above) + @as(i64, layout.depth_below));
    // Vertical rule fit (issue #270 review): diagonal cancel strikes
    // overhang the layout box by KaTeX's 0.2em pad (pinned 0.18.7
    // `enclose.ts`: the vlist keeps the inner box), and a standalone
    // file must contain its ink — KaTeX HTML overflows visibly
    // instead of clipping. Rules only (run ink is contained by
    // construction: ink-derived boxes plus max() containment); zero
    // keeps every other golden bit-identical.
    const top = topShiftUnits(layout.rules);
    const bottom = bottomShiftUnits(layout.rules, box_h);
    const total_h = satI32(@as(i64, box_h) + @as(i64, top) + @as(i64, bottom));
    const neg_top = satI32(-@as(i64, top));
    w.skeletonHead(
        satI32(-@as(i64, sh.left)),
        neg_top,
        total_w,
        total_h,
        @as(f64, @floatFromInt(total_w)) / 1000.0,
        @as(f64, @floatFromInt(total_h)) / 1000.0,
    );
    for (layout.rules) |r| {
        if (r.diag == .none) emitRule(w, r);
    }
    for (layout.runs) |run| emitRun(w, ol, &cache, segs, run);
    // Cancel strikes paint over the body (pinned 0.18.7 `enclose.ts`:
    // "Write the \cancel stroke on top of inner"); rect rules never
    // overlap ink and stay underneath (a colorbox background must not
    // cover its content).
    for (layout.rules) |r| {
        if (r.diag != .none) emitRule(w, r);
    }
    w.str("</svg>");
    if (w.overflow) return error.NoSpace;
    return w.done();
}

/// One-shot `render`: CLI glue over `layoutDiag` + `renderLayout`.
///
/// Same-files agreement: the measuring `prov` and the outline faces
/// behind `ol` must be the same files — pen steps bake the measured
/// advances while ink comes from the faces, so a mismatch drifts
/// glyphs from their boxes. `TooLong` is guarded first; `Invalid`
/// carries `diag.offset`/`diag.message` through from `layoutDiag`;
/// `OutOfMemory` maps to `NoSpace` at the boundary (nothing
/// allocates, so it is unreachable — the mapping exists for
/// exhaustiveness). `Unsupported` passes through for engine-scope
/// rejections the layout path may report.
pub fn render(
    source: []const u8,
    options: zatex.LayoutOptions,
    prov: zatex.MetricsProvider,
    ol: outlines_mod.Outlines,
    runs: []zatex.ir.Run,
    rules: []zatex.ir.Rule,
    glyphs: []u16,
    segs: []cff.Seg,
    out: []u8,
    diag: *zatex.Diag,
) zatex.LayoutError![]u8 {
    if (source.len > zatex.max_input_len) return error.TooLong;
    const layout = zatex.layoutDiag(source, options, prov, runs, rules, glyphs, diag) catch |err| return mapErr(err);
    return renderLayout(layout, ol, segs, out) catch |err| return mapErr(err);
}

/// Boundary error mapping: the reserved `OutOfMemory` (the core and
/// this walker allocate nothing) surfaces as `NoSpace`; every other
/// variant passes through unchanged.
fn mapErr(err: zatex.LayoutError) zatex.LayoutError {
    return if (err == error.OutOfMemory) error.NoSpace else err;
}

/// Fixed-precision buffer writer (mathml `Writer` shape, extended
/// with `num`/`hexColor`/`opacity`). Zero allocation; any write past
/// the buffer sets `overflow` and stops (surfaces as `error.NoSpace`).
/// In `measure` mode nothing is stored: every byte is only counted
/// into `total`, so `measureLayout` learns the exact size first and
/// the CLI allocates exactly that (overflow never sets there).
const W = struct {
    buf: []u8,
    pos: usize = 0,
    overflow: bool = false,
    measure: bool = false,
    total: usize = 0,

    fn str(self: *W, s: []const u8) void {
        if (self.measure) {
            self.total += s.len;
            return;
        }
        if (self.overflow) return;
        if (self.pos + s.len > self.buf.len) {
            self.overflow = true;
            return;
        }
        @memcpy(self.buf[self.pos .. self.pos + s.len], s);
        self.pos += s.len;
        self.total += s.len;
    }

    fn byte(self: *W, c: u8) void {
        if (self.measure) {
            self.total += 1;
            return;
        }
        if (self.overflow) return;
        if (self.pos + 1 > self.buf.len) {
            self.overflow = true;
            return;
        }
        self.buf[self.pos] = c;
        self.pos += 1;
        self.total += 1;
    }

    fn uint(self: *W, v: u32) void {
        self.uint64(v);
    }

    fn int(self: *W, v: i32) void {
        if (v < 0) {
            self.byte('-');
            self.uint64(@as(u64, @intCast(-(@as(i64, v)))));
        } else {
            self.uint64(@as(u64, @intCast(v)));
        }
    }

    fn uint64(self: *W, v: u64) void {
        if (v == 0) {
            self.byte('0');
            return;
        }
        var tmp: [20]u8 = undefined;
        var n: usize = 0;
        var x = v;
        while (x > 0) : (n += 1) {
            tmp[n] = '0' + @as(u8, @intCast(x % 10));
            x /= 10;
        }
        while (n > 0) : (n -= 1) self.byte(tmp[n - 1]);
    }

    /// Fixed 2-decimal float: `q = round_half_away(v * 100)` over
    /// integers, trailing zeros stripped, `-0` → `0`. Never
    /// `std.fmt` floats (determinism per Global Constraints).
    fn num(self: *W, v: f64) void {
        if (self.overflow) return;
        if (!std.math.isFinite(v)) {
            self.overflow = true;
            return;
        }
        const scaled = v * 100.0;
        if (!(scaled > -9223372036854775808.0 and scaled < 9223372036854775808.0)) {
            self.overflow = true;
            return;
        }
        const q: i64 = @intFromFloat(@round(scaled));
        const neg = q < 0;
        // Avoid negating minInt (UB in safe modes).
        const mag: u64 = if (neg) @as(u64, @intCast(-(q + 1))) + 1 else @as(u64, @intCast(q));
        const int_part = mag / 100;
        const frac: u8 = @intCast(mag % 100);
        if (neg) self.byte('-');
        self.uint64(int_part);
        if (frac != 0) {
            self.byte('.');
            self.byte('0' + @as(u8, @intCast(frac / 10)));
            if (frac % 10 != 0) self.byte('0' + @as(u8, @intCast(frac % 10)));
        }
    }

    /// `#` + 6 lowercase hex nibbles.
    fn hexColor(self: *W, rgb: u24) void {
        self.byte('#');
        const v: u32 = rgb;
        var shift: u5 = 20;
        while (true) {
            const nibble: u8 = @intCast((v >> shift) & 0xF);
            self.byte(if (nibble < 10) '0' + nibble else 'a' + (nibble - 10));
            if (shift == 0) break;
            shift -= 4;
        }
    }

    /// Alpha byte as `num(a / 255)`.
    fn opacity(self: *W, a: u8) void {
        self.num(@as(f64, @floatFromInt(a)) / 255.0);
    }

    /// `<svg … viewBox="minX minY totalW totalH" width="w_em em" …>` open tag.
    /// Width/height arrive as `units / 1000` through `num`.
    fn skeletonHead(self: *W, minX: i32, minY: i32, totalW: i32, totalH: i32, w_em: f64, h_em: f64) void {
        self.str("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"");
        self.int(minX);
        self.byte(' ');
        self.int(minY);
        self.byte(' ');
        self.int(totalW);
        self.byte(' ');
        self.int(totalH);
        self.str("\" width=\"");
        self.num(w_em);
        self.str("em\" height=\"");
        self.num(h_em);
        self.str("em\">");
    }

    fn done(self: *W) []u8 {
        return self.buf[0..self.pos];
    }
};

/// Split paint: `0xRRGGBBAA`; null is ambient black ink.
const Paint = struct {
    rgb: u24,
    a: u8,
};

fn paintOf(color: ?u32) Paint {
    const c = color orelse return .{ .rgb = 0x000000, .a = 0xFF };
    return .{ .rgb = @intCast(c >> 8), .a = @intCast(c & 0xFF) };
}

/// Saturating i64 to i32: adversarial box sums stay total.
fn satI32(v: i64) i32 {
    if (v > std.math.maxInt(i32)) return std.math.maxInt(i32);
    if (v < std.math.minInt(i32)) return std.math.minInt(i32);
    return @intCast(v);
}

/// Pen step shared by the draw walk and the shift walks: integer
/// advance exactly like the core measured, then the x_scale stretch
/// (`zatex-png` render.zig:122-127 parity).
fn stepPen(x_units: i64, adv1000: i32, run: zatex.ir.Run) i64 {
    const step: i64 = @divTrunc(@as(i64, adv1000) * @as(i64, run.size_units), 1000);
    return x_units + @divTrunc(step * @as(i64, run.x_scale), 1000);
}

/// One rule: filled integer rect, or a butt-cap diagonal across the
/// rect (`up`: bottom-left to top-right; `down`: top-left to
/// bottom-right). Core and SVG are both y-down, so no flip.
fn emitRule(w: *W, r: zatex.ir.Rule) void {
    const p = paintOf(r.color);
    if (r.diag == .none) {
        w.str("<rect x=\"");
        w.int(r.x);
        w.str("\" y=\"");
        w.int(r.y);
        w.str("\" width=\"");
        w.uint(r.w);
        w.str("\" height=\"");
        w.uint(r.h);
        w.str("\" fill=\"");
        w.hexColor(p.rgb);
        w.byte('"');
        if (p.a != 0xFF) {
            w.str(" fill-opacity=\"");
            w.opacity(p.a);
            w.byte('"');
        }
        w.str("/>");
        return;
    }
    const x2 = satI32(@as(i64, r.x) + @as(i64, r.w));
    const y2 = satI32(@as(i64, r.y) + @as(i64, r.h));
    const up = r.diag == .up;
    w.str("<line x1=\"");
    w.int(r.x);
    w.str("\" y1=\"");
    w.int(if (up) y2 else r.y);
    w.str("\" x2=\"");
    w.int(x2);
    w.str("\" y2=\"");
    w.int(if (up) r.y else y2);
    w.str("\" stroke=\"");
    w.hexColor(p.rgb);
    w.byte('"');
    if (p.a != 0xFF) {
        w.str(" stroke-opacity=\"");
        w.opacity(p.a);
        w.byte('"');
    }
    w.str(" stroke-width=\"");
    w.uint(r.thick);
    w.str("\" stroke-linecap=\"butt\"/>");
}

/// Per-render glyph cache (issue #282): one outline parse per
/// distinct unified glyph per render instead of one per occurrence
/// per walk (left shift + right shift + draw = 3 parses each).
///
/// Direct-mapped 16-entry array keyed on the unified glyph id (the
/// #159 memo precedent: collisions only evict, the key is always
/// validated, so output is bit-identical). Each entry holds the
/// advance, the units-per-em, the thousandths ink box, and the parsed
/// segments (copied in, so hook-owned static slices are safe to keep).
/// Stack-local in `renderLayout`; zero heap allocation.
///
/// Segment cap: 128 per entry (~9 KiB each). The probed KaTeX faces
/// peak at 146 segments (one glyph overflows); anything larger — the
/// Latin Modern giants included — bypasses the segment store and
/// parses per occurrence exactly like before, while its advance/upm/
/// ink stay cached. Bypass glyphs are bit-identical by construction
/// (same hooks, same values, only fewer calls for the cached parts).
const cache_slots: usize = 16;
const cache_segs: usize = 128;

const CacheEntry = struct {
    used: bool = false,
    unified: u16 = 0,
    adv: i32 = 0,
    upm: u16 = 0,
    ink: [4]i32 = .{ 0, 0, 0, 0 },
    has_segs: bool = false,
    nsegs: usize = 0,
    segs: [cache_segs]cff.Seg = undefined,
};

const GlyphCache = struct {
    entries: [cache_slots]CacheEntry = [_]CacheEntry{.{}} ** cache_slots,

    /// Cached metrics + segments for one glyph. Misses query each
    /// hook at most once and fill the slot:
    /// - advance/upm/ink come straight from their hooks (same values
    ///   the walks would read per occurrence, so shifts stay
    ///   bit-identical even for seams whose ink box is not derived
    ///   from the served segments).
    /// - the outline then parses once into the slot for the draw loop
    ///   (null or over-cap outlines skip the segment store and parse
    ///   per occurrence, as before; empty outlines store nothing —
    ///   a full parse would bbox to null and report zero ink too).
    fn lookup(self: *GlyphCache, ol: outlines_mod.Outlines, scratch: []cff.Seg, g: u16) *CacheEntry {
        const slot = @as(usize, g) % cache_slots;
        const e = &self.entries[slot];
        if (e.used and e.unified == g) return e;
        e.used = true;
        e.unified = g;
        e.adv = ol.advance1000(ol.ptr, g);
        e.upm = ol.upmOf(ol.ptr, g);
        e.ink = ol.inkThou(ol.ptr, g, scratch);
        e.has_segs = false;
        e.nsegs = 0;
        if (e.upm == 0) return e;
        const got = ol.glyphSegs(ol.ptr, g, &e.segs) orelse return e;
        if (got.len == 0 or got.len > cache_segs) return e;
        // Hook-owned slices (stubs serve statics) must be copied: the
        // file impl already wrote into `e.segs` (self-copy), anything
        // else lands there now. Lengths match, so this is exact.
        if (got.ptr != e.segs[0..].ptr) @memcpy(e.segs[0..got.len], got);
        e.nsegs = got.len;
        e.has_segs = true;
        return e;
    }

    fn cachedSegs(self: *GlyphCache, ol: outlines_mod.Outlines, scratch: []cff.Seg, g: u16) ?[]const cff.Seg {
        const e = self.lookup(ol, scratch, g);
        if (e.has_segs) return e.segs[0..e.nsegs];
        return ol.glyphSegs(ol.ptr, g, scratch);
    }
};

/// One run: `<g>` carrying only the fill (omitted for ambient black),
/// wrapping a single soup `<path>` with every transform baked into
/// coordinates. X = ox + mx·s·kx·x + mx·kh·(y·s), Y = oy − s·y with
/// s = size/unified-upm, kx = x_scale/1000, kh = x_shear/1000,
/// mx = mirrored ? -1 : 1. `M` on pen mismatch (exact float compare),
/// `L`/`C` continuations, then an optional `Z` for path closedness
/// when a segment ends at its subpath start (curves always emit
/// their `C` data first; bare `Z` is reserved for straight closing
/// edges). Glyphs with no segments still step the pen. A run with
/// no ink emits nothing at all. Metrics and segments come from the
/// per-render `GlyphCache` (warmed by the shift pass); bypass glyphs
/// (null or over-cap outlines) parse into `scratch` per occurrence,
/// exactly like before.
fn emitRun(w: *W, ol: outlines_mod.Outlines, cache: *GlyphCache, scratch: []cff.Seg, run: zatex.ir.Run) void {
    if (run.glyphs.len == 0 or run.size_units == 0) return;
    const ambient = run.color == null;
    const mark = w.pos;
    // `total` mirrors `pos` in write mode (every stored byte is also
    // counted) and is the only progress signal in measure mode (where
    // `pos` stays 0): the empty-path check below must compare totals,
    // and the rollback must restore both, or the measure pass drops
    // every run's closer and undercounts.
    const mark_total = w.total;
    if (!ambient) {
        const p = paintOf(run.color);
        w.str("<g fill=\"");
        w.hexColor(p.rgb);
        w.byte('"');
        if (p.a != 0xFF) {
            w.str(" fill-opacity=\"");
            w.opacity(p.a);
            w.byte('"');
        }
        w.byte('>');
    }
    w.str("<path d=\"");
    const dmark_total = w.total;
    const oy: f64 = @floatFromInt(run.baseline_y);
    var x_units: i64 = run.x;
    var pen_x: f64 = 0;
    var pen_y: f64 = 0;
    var have_pen = false;
    var sub_x: f64 = 0;
    var sub_y: f64 = 0;
    for (run.glyphs) |g| {
        const e = cache.lookup(ol, scratch, g);
        if (e.upm == 0) {
            x_units = stepPen(x_units, e.adv, run);
            continue;
        }
        const got = cache.cachedSegs(ol, scratch, g) orelse {
            x_units = stepPen(x_units, e.adv, run);
            continue;
        };
        const s: f64 = @as(f64, @floatFromInt(run.size_units)) / @as(f64, @floatFromInt(e.upm));
        const kx: f64 = @as(f64, @floatFromInt(run.x_scale)) / 1000.0;
        const kh: f64 = @as(f64, @floatFromInt(run.x_shear)) / 1000.0;
        const mx: f64 = if (run.mirrored) -1.0 else 1.0;
        const ox: f64 = @floatFromInt(x_units);
        for (got) |sg| {
            // Lines store endpoints in slots 0 and 3; curves use all
            // four (cff.outlineBbox parity).
            var bx: [4]f64 = undefined;
            var by: [4]f64 = undefined;
            var k: usize = 0;
            while (k < 4) : (k += 1) {
                if (!sg.is_curve and (k == 1 or k == 2)) continue;
                const ys = sg.y[k] * s;
                bx[k] = ox + mx * s * kx * sg.x[k] + mx * kh * ys;
                by[k] = oy - ys;
            }
            if (!have_pen or bx[0] != pen_x or by[0] != pen_y) {
                w.byte('M');
                w.num(bx[0]);
                w.byte(' ');
                w.num(by[0]);
                sub_x = bx[0];
                sub_y = by[0];
            }
            // Type 2 has no closepath operator: a closed loop routinely
            // ends with a `curveto` back to its subpath start. The
            // curve's own data must be emitted first; bare `Z` alone
            // would discard it. Bare `Z` is reserved for straight
            // closing edges (it draws that edge); curves emit `C`
            // then an optional `Z` for path closedness.
            if (sg.is_curve) {
                w.byte('C');
                w.num(bx[1]);
                w.byte(' ');
                w.num(by[1]);
                w.byte(' ');
                w.num(bx[2]);
                w.byte(' ');
                w.num(by[2]);
                w.byte(' ');
                w.num(bx[3]);
                w.byte(' ');
                w.num(by[3]);
                if (bx[3] == sub_x and by[3] == sub_y) w.byte('Z');
            } else if (bx[3] == sub_x and by[3] == sub_y) {
                w.byte('Z');
            } else {
                w.byte('L');
                w.num(bx[3]);
                w.byte(' ');
                w.num(by[3]);
            }
            pen_x = bx[3];
            pen_y = by[3];
            have_pen = true;
        }
        x_units = stepPen(x_units, e.adv, run);
    }
    if (w.total == dmark_total) {
        w.pos = mark; // no ink: drop the empty path (and its group)
        w.total = mark_total;
        return;
    }
    w.str("\"/>");
    if (!ambient) w.str("</g>");
}

/// Fused viewport shift in layout units (issue #282): one pass over
/// runs/glyphs computing BOTH the left overflow (ink past the origin)
/// and the right overflow (ink past the advance width). Transcribes
/// `zatex-png`'s twin walks; the per-glyph arithmetic below is their
/// two bodies sharing one origin step and one cache lookup, so the
/// values equal `leftShiftUnits`/`rightShiftUnits` exactly while each
/// glyph's outline parses once per render (via `cache`) instead of
/// twice here plus once in the draw loop.
///
/// Per glyph the walk mirrors the draw loop's origin stepping, and
/// the glyph contributes its true ink edges (`inkThou` [l,b,r,t],
/// y-up, origin-relative): mirrored ink spans [-r,-l] about the
/// origin, so the left edge hangs off the ink right and the right
/// edge off the negated ink left; shear slides ink with height, so
/// the extremes sit at the ink top/bottom. Rules contribute their
/// rect edges. Zero keeps the viewport bit-identical.
fn shiftUnits(
    ol: outlines_mod.Outlines,
    cache: *GlyphCache,
    scratch: []cff.Seg,
    runs: []const zatex.ir.Run,
    rules: []const zatex.ir.Rule,
    width: u32,
) struct { left: u32, right: u32 } {
    var left: i64 = 0;
    var edge: i64 = width;
    for (rules) |r| {
        if (@as(i64, r.x) < left) left = @as(i64, r.x);
        const rright: i64 = @as(i64, r.x) + @as(i64, r.w);
        if (rright > edge) edge = rright;
    }
    for (runs) |run| {
        if (run.glyphs.len == 0) continue;
        var x_units: i64 = run.x;
        for (run.glyphs) |g| {
            const e = cache.lookup(ol, scratch, g);
            const ink = e.ink;
            const ink_l: i64 = if (run.mirrored) ink[2] else ink[0];
            const ink_r: i64 = if (run.mirrored) -@as(i64, ink[0]) else ink[2];
            const ink_le = @divTrunc(ink_l * @as(i64, run.size_units) * @as(i64, run.x_scale), 1000 * 1000);
            const ink_re = @divTrunc(ink_r * @as(i64, run.size_units) * @as(i64, run.x_scale), 1000 * 1000);
            var ledge = if (run.mirrored) x_units - ink_le else x_units + ink_le;
            var redge = x_units + ink_re;
            if (run.x_shear != 0) {
                const top_u = @divTrunc(@as(i64, ink[3]) * @as(i64, run.size_units), 1000);
                const bot_u = @divTrunc(@as(i64, ink[1]) * @as(i64, run.size_units), 1000);
                const sh_top = @divFloor(@as(i64, run.x_shear) * top_u, 1000);
                const sh_bot = @divFloor(@as(i64, run.x_shear) * bot_u, 1000);
                if (run.mirrored) {
                    ledge -= @max(@as(i64, 0), @max(sh_top, sh_bot));
                    redge -= @min(@as(i64, 0), @min(sh_top, sh_bot));
                } else {
                    ledge += @min(@as(i64, 0), @min(sh_top, sh_bot));
                    redge += @max(@as(i64, 0), @max(sh_top, sh_bot));
                }
            }
            if (ledge < left) left = ledge;
            if (redge > edge) edge = redge;
            x_units = stepPen(x_units, e.adv, run);
        }
    }
    return .{
        .left = if (left < 0) @intCast(-left) else 0,
        .right = if (edge > @as(i64, width)) @intCast(edge - @as(i64, width)) else 0,
    };
}

/// Top-overflow shift in layout units (>= 0): diagonal cancel strikes
/// overhang the layout box top by KaTeX's 0.2em pad (pinned 0.18.7
/// `enclose.ts`). Rules only, like the render walk; zero keeps the
/// viewport bit-identical.
fn topShiftUnits(rules: []const zatex.ir.Rule) u32 {
    var top: i32 = 0;
    for (rules) |r| {
        if (r.y < top) top = r.y;
    }
    return if (top < 0) @intCast(-top) else 0;
}

/// Bottom-overflow shift in layout units (>= 0): mirror of
/// `topShiftUnits` for rule ink past the box bottom.
fn bottomShiftUnits(rules: []const zatex.ir.Rule, box_h: i32) u32 {
    var bot: i64 = box_h;
    for (rules) |r| {
        const edge: i64 = @as(i64, r.y) + @as(i64, r.h);
        if (edge > bot) bot = edge;
    }
    return if (bot > box_h) @intCast(bot - box_h) else 0;
}

/// Shared stub seam for walker tests: one line seg `(0,0)->(500,700)`
/// in font units for every glyph, upm 1000. Advances and ink boxes
/// mirror `zatex-png`'s shift-twin stubs (`x` overhangs by 50 each
/// side, `s` is the sheared dotless-j shape, everything else inset).
fn stubOutlines() outlines_mod.Outlines {
    const S = struct {
        var segbuf: [1]cff.Seg = .{.{
            .x = .{ 0, 0, 0, 500 },
            .y = .{ 0, 0, 0, 700 },
            .is_curve = false,
        }};
        fn segs(_: *const anyopaque, _: u16, _: []cff.Seg) ?[]const cff.Seg {
            return &segbuf;
        }
        fn adv(_: *const anyopaque, g: u16) i32 {
            return switch (g) {
                'x' => 500,
                's' => 306,
                else => 400,
            };
        }
        fn upm(_: *const anyopaque, _: u16) u16 {
            return 1000;
        }
        fn ink(_: *const anyopaque, g: u16, _: []cff.Seg) [4]i32 {
            return switch (g) {
                'x' => .{ -50, 0, 550, 700 },
                's' => .{ -40, -205, 346, 442 },
                else => .{ 10, 0, 390, 0 },
            };
        }
        var tag: u8 = 0;
    };
    return .{
        .ptr = &S.tag,
        .glyphSegs = S.segs,
        .advance1000 = S.adv,
        .upmOf = S.upm,
        .inkThou = S.ink,
    };
}

fn bakeLayout(runs: []const zatex.ir.Run, rules: []const zatex.ir.Rule, out: []u8) ![]u8 {
    var segs: [8]cff.Seg = undefined;
    const l = zatex.ir.Layout{ .width = 1000, .height_above = 1000, .depth_below = 500, .runs = runs, .rules = rules };
    return renderLayout(l, stubOutlines(), &segs, out);
}

test "rules emit rects then diag lines with paint" {
    const rules = [_]zatex.ir.Rule{
        .{ .x = 10, .y = 20, .w = 100, .h = 40 },
        .{ .x = 0, .y = 0, .w = 50, .h = 50, .color = 0xFF0000FF, .diag = .up, .thick = 8 },
    };
    const l = zatex.ir.Layout{ .width = 200, .height_above = 100, .depth_below = 50, .runs = &.{}, .rules = &rules };
    var segs: [8]cff.Seg = undefined;
    var out: [1024]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    // rules-then-runs order, integer rect, butt line, red paint:
    const rect_i = std.mem.indexOf(u8, got, "<rect x=\"10\" y=\"20\" width=\"100\" height=\"40\"");
    try std.testing.expect(rect_i != null);
    const line_i = std.mem.indexOf(u8, got, "<line x1=\"0\" y1=\"50\" x2=\"50\" y2=\"0\"");
    try std.testing.expect(line_i != null);
    try std.testing.expect(rect_i.? < line_i.?);
    try std.testing.expect(std.mem.indexOf(u8, got, "stroke=\"#ff0000\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "stroke-width=\"8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "stroke-linecap=\"butt\"") != null);
}

test "bake identity: X=ox+x, Y=oy-y" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'} },
    };
    const rules = [_]zatex.ir.Rule{
        .{ .x = 0, .y = 0, .w = 10, .h = 10 },
    };
    var out: [2048]u8 = undefined;
    const got = try bakeLayout(&runs, &rules, &out);
    try std.testing.expect(std.mem.indexOf(u8, got, "M100 200L600 -500") != null);
    // rules walk before runs:
    try std.testing.expect(std.mem.indexOf(u8, got, "<rect").? < std.mem.indexOf(u8, got, "M100 200").?);
}

test "bake mirror negates x" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'}, .mirrored = true },
    };
    var out: [2048]u8 = undefined;
    const got = try bakeLayout(&runs, &.{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, got, "M100 200L-400 -500") != null);
}

test "bake shear slides with height" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'}, .x_shear = 250 },
    };
    var out: [2048]u8 = undefined;
    const got = try bakeLayout(&runs, &.{}, &out);
    // 100+500+0.25*700 = 775
    try std.testing.expect(std.mem.indexOf(u8, got, "M100 200L775 -500") != null);
}

test "bake x_scale stretches ink and pen" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{ 'x', 'x' }, .x_scale = 2000 },
    };
    var out: [2048]u8 = undefined;
    const got = try bakeLayout(&runs, &.{}, &out);
    // advance 500, doubled pen step: second origin at 100+1000 = 1100.
    try std.testing.expect(std.mem.indexOf(u8, got, "L1100 -500") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "M1100 200") != null);
}

test "bake mirrored scale shear composes" {
    // One glyph, all three x-transforms at once: the bake order
    // `mx` applies to BOTH the scale and the shear term, so a bake
    // that shears without mirroring (`kh` instead of `mx·kh`) lands
    // 350 units off here. Hand-computed from the bake formula
    // X = ox + mx·s·kx·x + mx·kh·(y·s), Y = oy − s·y with s = 1
    // (size 1000 / upm 1000), kx = 2, kh = 0.25, mx = −1, ox = 100,
    // oy = 200 over the stub line (0,0)->(500,700):
    // start: X = 100, Y = 200; end: X = 100 − 1000 − 175 = −1075,
    // Y = 200 − 700 = −500. (Unmirrored shear would give
    // 100 − 1000 + 175 = −725 instead of −1075.)
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'}, .mirrored = true, .x_scale = 2000, .x_shear = 250 },
    };
    var out: [2048]u8 = undefined;
    const got = try bakeLayout(&runs, &.{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, got, "M100 200L-1075 -500") != null);
}

test "left shift opens the viewBox for llap ink" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{'x'} },
    };
    const l = zatex.ir.Layout{ .width = 500, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var segs: [8]cff.Seg = undefined;
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    // ink-left -50 at -500 reaches -550; nothing past the width.
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"-550 0 1050 1000\"") != null);
}

test "zero-shift common case keeps minX zero" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    const l = zatex.ir.Layout{ .width = 400, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var segs: [8]cff.Seg = undefined;
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"0 0 400 1000\"") != null);
}

test "right shift widens the viewBox for overhang ink" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    const l = zatex.ir.Layout{ .width = 300, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var segs: [8]cff.Seg = undefined;
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    // ink-right 390 past width 300: 90 wider, left edge untouched.
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"0 0 390 1000\"") != null);
}

test "colored runs wrap the path in a fill group" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'}, .color = 0xFF0000FF },
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'}, .color = 0x00FF0080 },
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'} },
    };
    var out: [2048]u8 = undefined;
    const got = try bakeLayout(&runs, &.{}, &out);
    // Opaque red: fill group without opacity; half green: with it.
    try std.testing.expect(std.mem.indexOf(u8, got, "<g fill=\"#ff0000\"><path d=\"M100 200L600 -500\"/></g>") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "<g fill=\"#00ff00\" fill-opacity=\"0.5\"><path") != null);
    // All three runs bake the same soup, but only the two painted
    // runs open a group: ambient black carries no `<g>` at all.
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, "<path d=\"M100 200L600 -500\"/>"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "<g fill="));
}

test "runs with no ink emit nothing" {
    const S = struct {
        fn segs(_: *const anyopaque, _: u16, _: []cff.Seg) ?[]const cff.Seg {
            return null;
        }
        fn adv(_: *const anyopaque, _: u16) i32 {
            return 500;
        }
        fn upm(_: *const anyopaque, _: u16) u16 {
            return 1000;
        }
        fn ink(_: *const anyopaque, _: u16, _: []cff.Seg) [4]i32 {
            return .{ 0, 0, 0, 0 };
        }
        var tag: u8 = 0;
    };
    const ol = outlines_mod.Outlines{ .ptr = &S.tag, .glyphSegs = S.segs, .advance1000 = S.adv, .upmOf = S.upm, .inkThou = S.ink };
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'x'}, .color = 0xFF0000FF },
    };
    const l = zatex.ir.Layout{ .width = 500, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var segs: [8]cff.Seg = undefined;
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, ol, &segs, &out);
    try std.testing.expect(std.mem.indexOf(u8, got, "<path") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "<g") == null);
    try std.testing.expect(std.mem.endsWith(u8, got, "</svg>"));
}

test "measure agrees with write, inked and inkless runs" {
    // The measure pass must count exactly what the write pass stores:
    // the empty-path rollback compares totals (in measure mode `pos`
    // never advances, so a `pos` comparison drops every closer).
    // One inked run, one colored inked run, one inkless run.
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'} },
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'x'}, .color = 0xFF0000FF },
        .{ .font_id = 0, .size_units = 1000, .x = 100, .baseline_y = 200, .glyphs = &[_]u16{'n'} },
    };
    const S = struct {
        var segbuf: [1]cff.Seg = .{.{
            .x = .{ 0, 0, 0, 500 },
            .y = .{ 0, 0, 0, 700 },
            .is_curve = false,
        }};
        fn segs(_: *const anyopaque, g: u16, _: []cff.Seg) ?[]const cff.Seg {
            // 'n' draws nothing (inkless run exercises the rollback).
            if (g == 'n') return null;
            return &segbuf;
        }
        fn adv(_: *const anyopaque, _: u16) i32 {
            return 500;
        }
        fn upm(_: *const anyopaque, _: u16) u16 {
            return 1000;
        }
        fn ink(_: *const anyopaque, _: u16, _: []cff.Seg) [4]i32 {
            return .{ 0, 0, 500, 700 };
        }
        var tag: u8 = 0;
    };
    const ol = outlines_mod.Outlines{ .ptr = &S.tag, .glyphSegs = S.segs, .advance1000 = S.adv, .upmOf = S.upm, .inkThou = S.ink };
    const l = zatex.ir.Layout{ .width = 1000, .height_above = 1000, .depth_below = 500, .runs = &runs, .rules = &.{} };
    var segs: [8]cff.Seg = undefined;
    const n = try measureLayout(l, ol, &segs);
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, ol, &segs, &out);
    try std.testing.expectEqual(got.len, n);
    // Inkless run emitted nothing: two paths, one group.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "<path"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "<g fill="));
    try std.testing.expect(std.mem.endsWith(u8, got, "</svg>"));
}

test "shift walks follow shear and mirror extremes" {
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'s'}, .x_shear = 250 },
    };
    const l = zatex.ir.Layout{ .width = 400, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var segs: [8]cff.Seg = undefined;
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    // Plain shear: descender tail drags left (-40-52 = -92); the top
    // leans right past the width (346+110 = 456 > 400: +56 wide).
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"-92 0 548 1000\"") != null);

    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'s'}, .x_shear = 250, .mirrored = true },
    };
    const lm = zatex.ir.Layout{ .width = 400, .height_above = 800, .depth_below = 200, .runs = &runs_mir, .rules = &.{} };
    const got_mir = try renderLayout(lm, stubOutlines(), &segs, &out);
    // Mirrored shear leans the other way: 0-346-110 = -456.
    try std.testing.expect(std.mem.indexOf(u8, got_mir, "viewBox=\"-456 0 856 1000\"") != null);
}

/// Counting outline seam for the #282 energy pins: fixed segs/ink
/// per glyph like `stubOutlines`, plus per-hook call counters. Pins
/// below assert exact counts (#159 style), so unfusing the shift
/// pass or dropping the cache fails the suite like a correctness
/// regression.
const CountOutlines = struct {
    segs_calls: usize = 0,
    adv_calls: usize = 0,
    upm_calls: usize = 0,
    ink_calls: usize = 0,

    var segbuf: [1]cff.Seg = .{.{
        .x = .{ 0, 0, 0, 500 },
        .y = .{ 0, 0, 0, 700 },
        .is_curve = false,
    }};

    fn segs(ptr: *const anyopaque, _: u16, _: []cff.Seg) ?[]const cff.Seg {
        const self: *CountOutlines = @ptrCast(@alignCast(@constCast(ptr)));
        self.segs_calls += 1;
        return &segbuf;
    }
    fn adv(ptr: *const anyopaque, g: u16) i32 {
        const self: *CountOutlines = @ptrCast(@alignCast(@constCast(ptr)));
        self.adv_calls += 1;
        return if (g == 'x') 500 else 400;
    }
    fn upm(ptr: *const anyopaque, _: u16) u16 {
        const self: *CountOutlines = @ptrCast(@alignCast(@constCast(ptr)));
        self.upm_calls += 1;
        return 1000;
    }
    fn ink(ptr: *const anyopaque, g: u16, _: []cff.Seg) [4]i32 {
        const self: *CountOutlines = @ptrCast(@alignCast(@constCast(ptr)));
        self.ink_calls += 1;
        return if (g == 'x') .{ -50, 0, 550, 700 } else .{ 10, 0, 390, 0 };
    }

    fn iface(self: *CountOutlines) outlines_mod.Outlines {
        return .{
            .ptr = @ptrCast(self),
            .glyphSegs = segs,
            .advance1000 = adv,
            .upmOf = upm,
            .inkThou = ink,
        };
    }
};

test "energy fused shift parses each distinct glyph once" {
    // Two `x` plus one `y` across two runs: the fused pass warms the
    // cache (one outline query per hook per distinct glyph) and the
    // draw loop reuses it. Unfused (left+right+draw walks) would cost
    // 2 ink calls per occurrence (6) plus a segs parse per
    // occurrence (3); uncached-but-fused would cost 3 per hook.
    var co = CountOutlines{};
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{ 'x', 'x' } },
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    const l = zatex.ir.Layout{ .width = 1000, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var scratch: [8]cff.Seg = undefined;
    var out: [4096]u8 = undefined;
    const got = try renderLayout(l, co.iface(), &scratch, &out);
    // Ink overhangs pin the fused viewport (bit-identical contract):
    // `x` ink-left -50 at the origin opens minX -50, and ink-right
    // 550 past the second origin (500) reaches 1050: width 1000 plus
    // 50 left plus 50 right.
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"-50 0 1100 1000\"") != null);
    try std.testing.expectEqual(@as(usize, 2), co.segs_calls);
    try std.testing.expectEqual(@as(usize, 2), co.adv_calls);
    try std.testing.expectEqual(@as(usize, 2), co.upm_calls);
    try std.testing.expectEqual(@as(usize, 2), co.ink_calls);
}

test "energy cache bypass keeps hook ink and re-parses segs" {
    // Null-seg glyphs skip the segment store: ink still comes from
    // the hook (viewport honors it), while the draw loop parses per
    // occurrence exactly like before the cache.
    const S = struct {
        var n_ink: usize = 0;
        var n_segs: usize = 0;
        fn segs(_: *const anyopaque, _: u16, _: []cff.Seg) ?[]const cff.Seg {
            n_segs += 1;
            return null;
        }
        fn adv(_: *const anyopaque, _: u16) i32 {
            return 500;
        }
        fn upm(_: *const anyopaque, _: u16) u16 {
            return 1000;
        }
        fn ink(_: *const anyopaque, _: u16, _: []cff.Seg) [4]i32 {
            n_ink += 1;
            return .{ -50, 0, 550, 700 };
        }
    };
    S.n_ink = 0;
    S.n_segs = 0;
    const ol = outlines_mod.Outlines{ .ptr = &S.n_ink, .glyphSegs = S.segs, .advance1000 = S.adv, .upmOf = S.upm, .inkThou = S.ink };
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{ 'x', 'x' } },
    };
    const l = zatex.ir.Layout{ .width = 500, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var scratch: [8]cff.Seg = undefined;
    var out: [4096]u8 = undefined;
    const got = try renderLayout(l, ol, &scratch, &out);
    // Hook ink still fits the viewport (ink-left -50 opens minX -50;
    // the second `x` at 500 reaches ink-right 1050: 500 + 50 + 550).
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"-50 0 1100 1000\"") != null);
    // One hook-ink call for the distinct glyph; the draw loop
    // re-parses null segs per occurrence (no store to reuse).
    try std.testing.expectEqual(@as(usize, 1), S.n_ink);
    try std.testing.expectEqual(@as(usize, 3), S.n_segs);
}

test "energy cache evicts on collision without corrupting ink" {
    // Glyphs 16 apart share a slot: alternating them evicts every
    // time (each lookup re-queries), but the validated key keeps
    // every edge exact.
    var co = CountOutlines{};
    var glyphs: [34]u16 = undefined;
    var i: usize = 0;
    while (i < glyphs.len) : (i += 1) glyphs[i] = if (i % 2 == 0) 'x' else 'x' + 16;
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &glyphs },
    };
    const l = zatex.ir.Layout{ .width = 20000, .height_above = 800, .depth_below = 200, .runs = &runs, .rules = &.{} };
    var scratch: [8]cff.Seg = undefined;
    var out: [65536]u8 = undefined;
    const got = try renderLayout(l, co.iface(), &scratch, &out);
    // Every `x` (advance 500, ink-right 550) still reaches past its
    // successor's origin: the last one ends the line at its ink edge.
    try std.testing.expect(std.mem.indexOf(u8, got, "<path") != null);
    // 34 alternating colliding lookups in the shift pass plus 34
    // more in the draw loop (which re-looks-up per glyph): no hits
    // possible, every hook fires per occurrence in both passes —
    // while 3 repeats of one glyph cost exactly 1 per hook per pass
    // (pinned above in fused form).
    try std.testing.expectEqual(@as(usize, 68), co.segs_calls);
    try std.testing.expectEqual(@as(usize, 68), co.ink_calls);
}

test "num formats fixed 2-decimal stripped" {
    var buf: [64]u8 = undefined;
    var w = W{ .buf = &buf };
    w.num(1.0); w.byte(' ');
    w.num(1.5); w.byte(' ');
    w.num(0.125); w.byte(' '); // exact-binary half: half away → 0.13
    w.num(1.006); w.byte(' '); // → 1.01
    w.num(-0.001); w.byte(' '); // → 0
    w.num(123.456); // → 123.46
    try std.testing.expect(!w.overflow);
    try std.testing.expectEqualStrings("1 1.5 0.13 1.01 0 123.46", w.done());
}

test "skeleton wraps body with integer viewBox" {
    // head(minX, minY, totalW, totalH, w_em, h_em) then body then "</svg>"
    var buf: [256]u8 = undefined;
    var w = W{ .buf = &buf };
    w.skeletonHead(-550, 0, 1050, 900, 1.05, 0.9);
    w.str("<rect/>");
    w.str("</svg>");
    try std.testing.expectEqualStrings(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-550 0 1050 900\" width=\"1.05em\" height=\"0.9em\"><rect/></svg>",
        w.done());
}

test "paintOf splits color and defaults null to black" {
    const ambient = paintOf(null);
    try std.testing.expectEqual(@as(u24, 0x000000), ambient.rgb);
    try std.testing.expectEqual(@as(u8, 0xFF), ambient.a);
    const red = paintOf(0xFF0000FF);
    try std.testing.expectEqual(@as(u24, 0xFF0000), red.rgb);
    try std.testing.expectEqual(@as(u8, 0xFF), red.a);
    const green_half = paintOf(0x00FF0080);
    try std.testing.expectEqual(@as(u24, 0x00FF00), green_half.rgb);
    try std.testing.expectEqual(@as(u8, 0x80), green_half.a);
}

test "hexColor opacity and overflow stop" {
    var buf: [32]u8 = undefined;
    var w = W{ .buf = &buf };
    w.hexColor(0xFF0000);
    w.byte(' ');
    w.hexColor(0x00ff80);
    w.byte(' ');
    w.opacity(0xFF);
    w.byte(' ');
    w.opacity(0x80);
    w.byte(' ');
    w.opacity(0x00);
    try std.testing.expect(!w.overflow);
    try std.testing.expectEqualStrings("#ff0000 #00ff80 1 0.5 0", w.done());

    var tiny: [3]u8 = undefined;
    var o = W{ .buf = &tiny };
    o.str("ab");
    o.str("cd"); // 2 + 2 > 3 → overflow, nothing written
    try std.testing.expect(o.overflow);
    o.str("more"); // stuck: further writes are no-ops
    try std.testing.expectEqualStrings("ab", o.done());
}

fn testProvider() zatex.MetricsProvider {
    const S = struct {
        fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
            return 40;
        }
    };
    return .{
        .ctx = &.{},
        .glyphId = S.glyphId,
        .advance = S.advance,
        .ruleThickness = S.ruleThickness,
    };
}

test "one-shot renders x^2 through the stub seam" {
    var runs: [8]zatex.ir.Run = undefined;
    var rules: [4]zatex.ir.Rule = undefined;
    var glyphs: [32]u16 = undefined;
    var segs: [64]cff.Seg = undefined;
    var out: [4096]u8 = undefined;
    var diag = zatex.Diag.empty();
    const got = try render("x^2", .{}, testProvider(), stubOutlines(),
        &runs, &rules, &glyphs, &segs, &out, &diag);
    try std.testing.expect(std.mem.startsWith(u8, got, "<svg "));
    try std.testing.expect(std.mem.endsWith(u8, got, "</svg>"));
}

test "one-shot error matrix covers all 7 variants" {
    // Invalid: unknown command; diag carries the 0-based token offset.
    {
        var runs: [8]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [4096]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.Invalid, render("\\nope", .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
        try std.testing.expectEqual(@as(u32, 0), diag.offset);
        try std.testing.expect(diag.message.len > 0);
    }
    // TooDeep: 200 unmatched opens.
    {
        var deep: [200]u8 = undefined;
        @memset(&deep, '{');
        var runs: [8]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [4096]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.TooDeep, render(&deep, .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
    }
    // TooLong: one past the contract cap (guarded before layout).
    {
        var big: [zatex.max_input_len + 1]u8 = .{'x'} ** (zatex.max_input_len + 1);
        var runs: [8]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [4096]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.TooLong, render(&big, .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
    }
    // ExpansionLimit: self-feeding macro.
    {
        var runs: [8]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [4096]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.ExpansionLimit, render("\\def\\a{\\a}\\a", .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
    }
    // Unsupported: no input emits it through layoutDiag (probed:
    // `\includegraphics{a}`, `\htmlClass{c}{x}`, and
    // `\raisebox{2pt}{x}` all lay out), so the boundary passthrough
    // is pinned on the mapping function instead of a guessed input.
    try std.testing.expectEqual(error.Unsupported, mapErr(error.Unsupported));
    // NoSpace: an 8-byte out cannot hold even the skeleton.
    {
        var runs: [8]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [8]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.NoSpace, render("x^2", .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
    }
    // OutOfMemory: reserved and unreachable (nothing allocates); the
    // boundary maps it to NoSpace for exhaustiveness.
    try std.testing.expectEqual(error.NoSpace, mapErr(error.OutOfMemory));
    try std.testing.expectEqual(error.Invalid, mapErr(error.Invalid));
    try std.testing.expectEqual(error.NoSpace, mapErr(error.NoSpace));
}

fn readSvgTestFile(path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        path,
        std.testing.allocator,
        .limited(8 * 1024 * 1024),
    );
}

test "same input twice is byte-identical" {
    const src = "x^2+\\frac{a}{b}";
    // Stub seam twice.
    {
        var runs_a: [8]zatex.ir.Run = undefined;
        var rules_a: [4]zatex.ir.Rule = undefined;
        var glyphs_a: [32]u16 = undefined;
        var segs_a: [64]cff.Seg = undefined;
        var out_a: [4096]u8 = undefined;
        var diag_a = zatex.Diag.empty();
        var runs_b: [8]zatex.ir.Run = undefined;
        var rules_b: [4]zatex.ir.Rule = undefined;
        var glyphs_b: [32]u16 = undefined;
        var segs_b: [64]cff.Seg = undefined;
        var out_b: [4096]u8 = undefined;
        var diag_b = zatex.Diag.empty();
        const a = try render(src, .{}, testProvider(), stubOutlines(), &runs_a, &rules_a, &glyphs_a, &segs_a, &out_a, &diag_a);
        const b = try render(src, .{}, testProvider(), stubOutlines(), &runs_b, &rules_b, &glyphs_b, &segs_b, &out_b, &diag_b);
        try std.testing.expectEqualStrings(a, b);
    }
    // File outlines (LM + KaTeX_Main): same input, same files, same bytes.
    {
        const dir = std.fs.path.dirname(@import("build_options").fixture_font) orelse ".";
        var p0: [1024]u8 = undefined;
        var p1: [1024]u8 = undefined;
        const lm_path = try std.fmt.bufPrint(&p0, "{s}/latinmodern-math.otf", .{dir});
        const main_path = try std.fmt.bufPrint(&p1, "{s}/katex/KaTeX_Main-Regular.otf", .{dir});
        const lm_bytes = try readSvgTestFile(lm_path);
        defer std.testing.allocator.free(lm_bytes);
        const main_bytes = try readSvgTestFile(main_path);
        defer std.testing.allocator.free(main_bytes);
        var so_a = outlines_mod.StackOutlines{};
        try so_a.addFile(.lm, lm_bytes);
        try so_a.addFile(.main, main_bytes);
        var so_b = outlines_mod.StackOutlines{};
        try so_b.addFile(.lm, lm_bytes);
        try so_b.addFile(.main, main_bytes);
        var runs_a: [8]zatex.ir.Run = undefined;
        var rules_a: [4]zatex.ir.Rule = undefined;
        var glyphs_a: [32]u16 = undefined;
        var segs_a: [64]cff.Seg = undefined;
        var out_a: [4096]u8 = undefined;
        var diag_a = zatex.Diag.empty();
        var runs_b: [8]zatex.ir.Run = undefined;
        var rules_b: [4]zatex.ir.Rule = undefined;
        var glyphs_b: [32]u16 = undefined;
        var segs_b: [64]cff.Seg = undefined;
        var out_b: [4096]u8 = undefined;
        var diag_b = zatex.Diag.empty();
        const a = try render(src, .{}, testProvider(), so_a.iface(), &runs_a, &rules_a, &glyphs_a, &segs_a, &out_a, &diag_a);
        const b = try render(src, .{}, testProvider(), so_b.iface(), &runs_b, &rules_b, &glyphs_b, &segs_b, &out_b, &diag_b);
        try std.testing.expectEqualStrings(a, b);
    }
}

test "adversarial inputs are total" {
    // Same 1500-soup shape as the core's totality test (same pieces,
    // seed 0x5EED): each input either renders twice-identical or
    // errors identically twice — never hangs, never panics.
    var runs_a: [64]zatex.ir.Run = undefined;
    var rules_a: [16]zatex.ir.Rule = undefined;
    var glyphs_a: [1024]u16 = undefined;
    var segs_a: [64]cff.Seg = undefined;
    var out_a: [8192]u8 = undefined;
    var runs_b: [64]zatex.ir.Run = undefined;
    var rules_b: [16]zatex.ir.Rule = undefined;
    var glyphs_b: [1024]u16 = undefined;
    var segs_b: [64]cff.Seg = undefined;
    var out_b: [8192]u8 = undefined;
    const pieces = [_][]const u8{ "x", "y", "2", "+", "-", "{", "}", "^", "_",
        "\\frac", "\\sum", "\\alpha", "\\text{a}",
        "(", ")", " ", "&", "#", "$", "\\left(", "\\", "~", ",", ";" };
    var prng = std.Random.DefaultPrng.init(0x5EED);
    var rnd = prng.random();
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        var buf: [256]u8 = undefined;
        var len: usize = 0;
        var k: usize = 0;
        const n = 1 + rnd.uintLessThan(usize, 24);
        while (k < n and len < buf.len) : (k += 1) {
            const pc = pieces[rnd.uintLessThan(usize, pieces.len)];
            const m = @min(pc.len, buf.len - len);
            @memcpy(buf[len..][0..m], pc[0..m]);
            len += m;
        }
        const src = buf[0..len];
        var da = zatex.Diag.empty();
        var db = zatex.Diag.empty();
        const r1 = render(src, .{}, testProvider(), stubOutlines(), &runs_a, &rules_a, &glyphs_a, &segs_a, &out_a, &da);
        const r2 = render(src, .{}, testProvider(), stubOutlines(), &runs_b, &rules_b, &glyphs_b, &segs_b, &out_b, &db);
        if (r1) |b1| {
            const b2 = try r2;
            try std.testing.expectEqualStrings(b1, b2);
        } else |e1| {
            try std.testing.expectError(e1, r2);
            try std.testing.expectEqual(da.offset, db.offset);
        }
    }
}

test "tiny buffers are NoSpace, never panic" {
    // 8-byte out cannot hold even the skeleton.
    {
        var runs: [8]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [8]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.NoSpace, render("x^2", .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
    }
    // One run slot cannot hold the fraction row.
    {
        var runs: [1]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [32]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [4096]u8 = undefined;
        var diag = zatex.Diag.empty();
        try std.testing.expectError(error.NoSpace, render("\\frac{a}{b}+x", .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag));
    }
    // Empty input needs nothing: zero-length buffers still serve it.
    {
        var runs: [0]zatex.ir.Run = undefined;
        var rules: [0]zatex.ir.Rule = undefined;
        var glyphs: [0]u16 = undefined;
        var segs: [64]cff.Seg = undefined;
        var out: [512]u8 = undefined;
        var diag = zatex.Diag.empty();
        const got = try render("", .{}, testProvider(), stubOutlines(), &runs, &rules, &glyphs, &segs, &out, &diag);
        try std.testing.expect(std.mem.startsWith(u8, got, "<svg "));
        try std.testing.expect(std.mem.endsWith(u8, got, "</svg>"));
    }
}

test "translucent down rule paints stroke-opacity corner to corner" {
    const rules = [_]zatex.ir.Rule{
        .{ .x = 0, .y = 0, .w = 50, .h = 50, .color = 0xFF000080, .diag = .down, .thick = 8 },
        .{ .x = 10, .y = 20, .w = 100, .h = 40, .color = 0x00FF0080 },
    };
    const l = zatex.ir.Layout{ .width = 200, .height_above = 100, .depth_below = 50, .runs = &.{}, .rules = &rules };
    var segs: [8]cff.Seg = undefined;
    var out: [1024]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    // .down runs top-left → bottom-right with a translucent stroke.
    try std.testing.expect(std.mem.indexOf(u8, got, "<line x1=\"0\" y1=\"0\" x2=\"50\" y2=\"50\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "stroke=\"#ff0000\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "stroke-opacity=\"0.5\"") != null);
    // Translucent rect carries fill-opacity instead.
    try std.testing.expect(std.mem.indexOf(u8, got, "fill=\"#00ff00\" fill-opacity=\"0.5\"") != null);
}

test "viewport contains rule overhang top and bottom" {
    // A cancel-style diagonal overhanging the box both ways (pinned
    // 0.18.7 `enclose.ts`: the vlist keeps the inner box while the
    // strike laps 0.2em past it): the viewport grows to contain the
    // rule instead of clipping it (issue #270 review).
    const rules = [_]zatex.ir.Rule{
        .{ .x = 0, .y = -200, .w = 572, .h = 853, .diag = .up, .thick = 46 },
    };
    const l = zatex.ir.Layout{ .width = 572, .height_above = 442, .depth_below = 11, .runs = &.{}, .rules = &rules };
    var segs: [8]cff.Seg = undefined;
    var out: [2048]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    try std.testing.expect(std.mem.indexOf(u8, got, "viewBox=\"0 -200 572 853\"") != null);
}

test "diag strikes paint after runs, rects before" {
    // Pinned 0.18.7 `enclose.ts` ("Write the \cancel stroke on top
    // of inner"): a strike overlapping its body must not hide under
    // the glyph fill (issue #270 review: the cancel strike was
    // invisible where it crossed the x). Rect rules never overlap
    // ink and stay underneath (a colorbox background must not cover
    // its content).
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'x'} },
    };
    const rules = [_]zatex.ir.Rule{
        .{ .x = 0, .y = 0, .w = 100, .h = 40 },
        .{ .x = 0, .y = -200, .w = 572, .h = 853, .diag = .up, .thick = 46 },
    };
    const l = zatex.ir.Layout{ .width = 572, .height_above = 442, .depth_below = 11, .runs = &runs, .rules = &rules };
    var segs: [8]cff.Seg = undefined;
    var out: [4096]u8 = undefined;
    const got = try renderLayout(l, stubOutlines(), &segs, &out);
    const rect_i = std.mem.indexOf(u8, got, "<rect").?;
    const path_i = std.mem.indexOf(u8, got, "<path").?;
    const line_i = std.mem.indexOf(u8, got, "<line").?;
    try std.testing.expect(rect_i < path_i);
    try std.testing.expect(path_i < line_i);
}

fn lookup(corpus: []const u8, id: []const u8) []const u8 {
    // Rows are `<id> <tex>`; split on the FIRST space (tex contains spaces).
    var it = std.mem.splitScalar(u8, corpus, '\n');
    while (it.next()) |row| {
        if (row.len > id.len and std.mem.startsWith(u8, row, id) and row[id.len] == ' ')
            return row[id.len + 1 ..];
    }
    unreachable; // regen and the id list are generated together
}

// Golden-fixture stack: same files, same roles, same order as the CLI
// (`outlines_mod.CLI_STACK`), resolved through the
// `build_options.fixture_font` directory (no CWD promise in tests).
// File bytes stay alive in `file_held` for the stack/CFF borrow, so the
// same-files agreement with `render` holds exactly as in the CLI.
var file_so: outlines_mod.StackOutlines = .{};
var file_held: [outlines_mod.CLI_STACK.len][]u8 = undefined;
var file_n: usize = 0;

fn loadFileFixtures() !void {
    const dir = std.fs.path.dirname(@import("build_options").fixture_font) orelse ".";
    const marker = "fixtures/fonts/";
    var pathbuf: [1024]u8 = undefined;
    for (outlines_mod.CLI_STACK) |entry| {
        const full = if (std.mem.indexOf(u8, entry.path, marker)) |at|
            try std.fmt.bufPrint(&pathbuf, "{s}/{s}", .{ dir, entry.path[at + marker.len ..] })
        else
            entry.path;
        const bytes = readSvgTestFile(full) catch |e| {
            if (!entry.required) continue;
            return e;
        };
        errdefer std.testing.allocator.free(bytes);
        file_so.addFile(entry.role, bytes) catch |e| {
            std.testing.allocator.free(bytes);
            return e;
        };
        file_held[file_n] = bytes;
        file_n += 1;
    }
    // Every golden row renders ink through these faces; a face that
    // failed to load would silently empty its rows, so require the
    // full required stack (Task 3 probe precedent).
    // `file_n` also counts optional faces (e.g. the system STIX
    // fallbacks when present), so the invariant is "at least every
    // required face loaded", not an exact count.
    var want: usize = 0;
    for (outlines_mod.CLI_STACK) |entry| want += if (entry.required) 1 else 0;
    if (file_n < want) return error.FontLoad;
}

fn fileProv() zatex.MetricsProvider {
    return file_so.stack.provider();
}

fn fileOutlines() outlines_mod.Outlines {
    return file_so.iface();
}

test "goldens byte-match" {
    const corpus = @embedFile("corpus.txt");
    try loadFileFixtures();
    defer {
        for (file_held[0..file_n]) |b| std.testing.allocator.free(b);
    }
    // CLI-ceiling buffers (main.zig): every golden fits the 256-run /
    // 64-rule / 4096-glyph / 512-seg caps the CLI allocates, and `out`
    // is measure-then-exact (never the old fixed 1MB) — so this test
    // proves the production-sized path byte-matches, not an
    // over-provisioned one.
    var runs: [256]zatex.ir.Run = undefined;
    var rules: [64]zatex.ir.Rule = undefined;
    var glyphs: [4096]u16 = undefined;
    var segs: [512]cff.Seg = undefined;
    var diag = zatex.Diag.empty();
    // Test-only id list, imported inside the test fn (issue #288):
    // `golden_ids` is regen metadata, never library code — a
    // top-level import would link its strings into every consumer of
    // this module (including the CLI exe).
    inline for (@import("golden_ids.zig").ids) |id| {
        const want = @embedFile("goldens/" ++ id ++ ".svg");
        const src = lookup(corpus, id);
        // regen renders with `--display` iff the id ends in `-d`;
        // the snapshot keys display mode off the same suffix.
        const layout = try zatex.layoutDiag(src, .{ .display_mode = std.mem.endsWith(u8, id, "-d") }, fileProv(), &runs, &rules, &glyphs, &diag);
        const n = try measureLayout(layout, fileOutlines(), &segs);
        const out = try std.testing.allocator.alloc(u8, n);
        defer std.testing.allocator.free(out);
        const got = try renderLayout(layout, fileOutlines(), &segs, out);
        try std.testing.expectEqualStrings(want, got);
        try std.testing.expect(std.mem.indexOf(u8, want, "/Users/") == null);
        try std.testing.expect(std.mem.indexOf(u8, want, "/home/") == null);
    }
}
