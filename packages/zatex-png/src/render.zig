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
    // Overflow shifts (issues #71/#96, fused + memoized in #282): one
    // pass over runs/glyphs measures the leftmost ink edge (zero-width
    // overlaps like `\llap` place runs left of the origin, and a canvas
    // starting at 0 clips that ink while KaTeX shows the overflow) and
    // the rightmost ink past the advance width (e.g. `\minuso`'s rlap
    // circle). The per-render memo answers repeat glyphs without
    // re-querying the backend ink boxes. Only the left edge moves the
    // origin (a non-negative shift); the right edge widens the canvas
    // past advance+pad. Zeros keep every other bitmap bit-identical.
    var memo = GlyphMemo{};
    const query = fontQuery(font);
    const shifts = shiftUnits(&memo, query, layout.runs, layout.rules, layout.width);
    const shift: f64 = @as(f64, @floatFromInt(shifts.left)) * s;
    const rshift: f64 = @as(f64, @floatFromInt(shifts.right)) * s;
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

    var canvas = try backend.impl.Canvas.create(w, h);
    defer canvas.close();

    // White background, black ink. The software canvas allocates
    // pre-cleared white (issue #285), so the explicit clear below is
    // a no-op blit for it (integer fast path in `fillRect` rewrites
    // the same bytes) and stays the real clear for backends whose
    // `create` leaves pixels undefined (CoreGraphics bitmaps start
    // zeroed = transparent black there).
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
            const f0 = memoFace(&memo, query, run.glyphs[gi]) orelse {
                // Unowned id (no face loaded it): still step the pen.
                const step0: i64 = @divTrunc(
                    @as(i64, memoAdvance(&memo, query, run.glyphs[gi])) * @as(i64, run.size_units),
                    1000,
                );
                x_units += @divTrunc(step0 * @as(i64, run.x_scale), 1000);
                gi += 1;
                continue;
            };
            var gj = gi + 1;
            while (gj < run.glyphs.len) {
                const dn = memoFace(&memo, query, run.glyphs[gj]) orelse break;
                if (dn.h != f0.h) break;
                gj += 1;
            }
            // One typed handle per face group for the backend run (the
            // memo only keeps the comparable token); the grouping above
            // already proved every glyph in [gi, gj) shares this face,
            // so the per-glyph `drawFace` re-query is gone.
            const df = font.drawFace(run.glyphs[gi]) orelse {
                const step0: i64 = @divTrunc(
                    @as(i64, memoAdvance(&memo, query, run.glyphs[gi])) * @as(i64, run.size_units),
                    1000,
                );
                x_units += @divTrunc(step0 * @as(i64, run.x_scale), 1000);
                gi += 1;
                continue;
            };
            var rf = try canvas.beginRun(df.handle, px_size, sx, sh, run.mirrored);
            while (gi < gj) : (gi += 1) {
                const g = run.glyphs[gi];
                // Grouping proved ownership; the fallback is dead but
                // keeps the loop total (never panics).
                const face_gid = if (memoFace(&memo, query, g)) |f| f.gid else df.gid;
                const gx: f64 = @as(f64, @floatFromInt(x_units)) * s + pad + shift;
                rf.drawGlyph(face_gid, gx, base_y);
                const step: i64 = @divTrunc(
                    @as(i64, memoAdvance(&memo, query, g)) * @as(i64, run.size_units),
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

/// Per-render glyph memo (issue #282): one backend query per
/// distinct unified glyph per render instead of one per occurrence
/// per walk (left shift + right shift + grouping + draw = up to 6
/// faceOf+outline-box queries each). The shift pass warms it;
/// grouping and draw reuse it.
///
/// Direct-mapped 16-entry array keyed on the unified glyph id (the
/// #159 memo precedent: collisions only evict, the key is always
/// validated, so output is bit-identical). Each entry holds the
/// advance, the full ink box, and the owning face (a comparable token
/// plus its face-local gid). Stack-local in `renderToPng`; zero heap.
///
/// Misses call through the query seam exactly like the uncached code
/// would (advance/ink fall back to 500/zeros inside the font for
/// unowned ids; faces stay null), so values are bit-identical — only
/// the call counts drop.
const memo_slots: usize = 16;

/// Owning face for one glyph: an opaque comparable token for the
/// backend handle (grouping compares tokens) plus the face-local gid
/// the draw loop feeds the backend.
const FaceKey = struct {
    h: *const anyopaque,
    gid: u16,
};

const MemoEntry = struct {
    valid: bool = false,
    unified: u16 = 0,
    adv: i32 = 0,
    ink: [4]i32 = .{ 0, 0, 0, 0 },
    adv_ink_set: bool = false,
    face: ?FaceKey = null,
    face_set: bool = false,
};

const GlyphMemo = struct {
    entries: [memo_slots]MemoEntry = [_]MemoEntry{.{}} ** memo_slots,

    fn slot(self: *GlyphMemo, glyph: u16) *MemoEntry {
        const e = &self.entries[@as(usize, glyph) % memo_slots];
        if (!e.valid or e.unified != glyph) e.* = .{ .valid = true, .unified = glyph };
        return e;
    }
};

/// Query seam behind the memo: integer thousandths like the core
/// measures, so the shift walk stays exact. Production wires the
/// `Font` methods; tests wire stubs with counters.
const GlyphQuery = struct {
    ptr: *const anyopaque,
    advance1000: *const fn (ptr: *const anyopaque, glyph: u16) i32,
    inkBounds1000: *const fn (ptr: *const anyopaque, glyph: u16) [4]i32,
    faceOf: *const fn (ptr: *const anyopaque, glyph: u16) ?FaceKey,
};

fn fontQuery(font: *const Font) GlyphQuery {
    const W = struct {
        fn adv(ptr: *const anyopaque, glyph: u16) i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.advance1000(glyph);
        }
        fn ink(ptr: *const anyopaque, glyph: u16) [4]i32 {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            return f.inkBounds1000(glyph);
        }
        fn face(ptr: *const anyopaque, glyph: u16) ?FaceKey {
            const f: *const Font = @ptrCast(@alignCast(ptr));
            const d = f.drawFace(glyph) orelse return null;
            return .{ .h = @ptrCast(d.handle), .gid = d.gid };
        }
    };
    return .{ .ptr = font, .advance1000 = W.adv, .inkBounds1000 = W.ink, .faceOf = W.face };
}

/// Memoized advance (fills on first use per distinct glyph).
fn memoAdvance(memo: *GlyphMemo, q: GlyphQuery, glyph: u16) i32 {
    const e = memo.slot(glyph);
    if (!e.adv_ink_set) {
        e.adv = q.advance1000(q.ptr, glyph);
        e.ink = q.inkBounds1000(q.ptr, glyph);
        e.adv_ink_set = true;
    }
    return e.adv;
}

/// Memoized ink box (shares the `memoAdvance` fill).
fn memoInk(memo: *GlyphMemo, q: GlyphQuery, glyph: u16) [4]i32 {
    _ = memoAdvance(memo, q, glyph);
    return memo.slot(glyph).ink;
}

/// Memoized owning face (fills on first use per distinct glyph,
/// independently of the advance/ink fill above).
fn memoFace(memo: *GlyphMemo, q: GlyphQuery, glyph: u16) ?FaceKey {
    const e = memo.slot(glyph);
    if (!e.face_set) {
        e.face = q.faceOf(q.ptr, glyph);
        e.face_set = true;
    }
    return e.face;
}

/// Fused viewport shift (issue #282): one pass over runs/glyphs
/// computing BOTH canvas shifts — the left overflow (issue #71:
/// `\llap` ink left of the origin) and the right overflow (issue #96:
/// `\minuso`-style ink past the advance width). The per-glyph
/// arithmetic is the two old twin-walk bodies sharing one origin step
/// and one memo lookup, so the values equal the twins exactly while
/// each glyph's backend ink box is queried once per render instead of
/// twice here plus the draw-time queries.
///
/// Walks glyph origins exactly like the draw loop: origin stepping
/// uses the same integer advances, and each glyph contributes its true
/// ink edges (ink box is origin-relative thousandths, y-up: mirrored
/// ink, issue #97, spans [-right, -left] about the origin). Faux-
/// italic shear (issue #77) slides ink horizontally with height — the
/// shift is linear, so the extremes sit at the ink top/bottom — and
/// mirrored runs shear the other way (the backend negates the slant
/// with the flip). Rules contribute their rect edges. Pure viewport
/// fit — box coordinates are untouched, so zero shifts render
/// bit-identical output to before.
fn shiftUnits(
    memo: *GlyphMemo,
    q: GlyphQuery,
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
            const ink = memoInk(memo, q, g);
            // Mirror of the twin: mirrored ink spans [-right, -left]
            // about the origin, so the left edge hangs off the ink
            // right and the right edge off the negated ink left; plain
            // runs hang off the ink left/right respectively.
            const ink_lo: i64 = if (run.mirrored) ink[2] else ink[0];
            const ink_ro: i64 = if (run.mirrored) -@as(i64, ink[0]) else ink[2];
            const ink_le = @divTrunc(ink_lo * @as(i64, run.size_units) * @as(i64, run.x_scale), 1000 * 1000);
            const ink_re = @divTrunc(ink_ro * @as(i64, run.size_units) * @as(i64, run.x_scale), 1000 * 1000);
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
            const step: i64 = @divTrunc(
                @as(i64, memoAdvance(memo, q, g)) * @as(i64, run.size_units),
                1000,
            );
            x_units += @divTrunc(step * @as(i64, run.x_scale), 1000);
        }
    }
    return .{
        .left = if (left < 0) @intCast(-left) else 0,
        .right = if (edge > @as(i64, width)) @intCast(edge - @as(i64, width)) else 0,
    };
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

/// Counting query seam for the shift tests and the #282 energy
/// pins: full ink boxes like the backend serves, plus per-query call
/// counters. Pins below assert exact counts (#159 style), so
/// unfusing the shift pass or dropping the memo fails the suite like
/// a correctness regression.
const CountQuery = struct {
    adv_calls: usize = 0,
    ink_calls: usize = 0,
    face_calls: usize = 0,
    shear_box: bool = true,

    var face_a: u8 = 0;
    var face_b: u8 = 0;

    fn adv(ptr: *const anyopaque, g: u16) i32 {
        const self: *CountQuery = @ptrCast(@alignCast(@constCast(ptr)));
        self.adv_calls += 1;
        return if (g == 'x') 500 else if (g == 's') 306 else 400;
    }
    fn ink(ptr: *const anyopaque, g: u16) [4]i32 {
        const self: *CountQuery = @ptrCast(@alignCast(@constCast(ptr)));
        self.ink_calls += 1;
        // `x` overhangs 50 each side; `s` is the sheared dotless-j
        // shape (LM ȷ proportions); everything else is inset. Without
        // the shear box the top/bottom read zero and sheared runs
        // keep the unsheared bound exactly (floor terms vanish).
        if (g == 'x') return .{ -50, 0, 550, 700 };
        if (g == 's') {
            if (self.shear_box) return .{ -40, -205, 346, 442 };
            return .{ -40, 0, 346, 0 };
        }
        return .{ 10, 0, 390, 0 };
    }
    fn face(ptr: *const anyopaque, g: u16) ?FaceKey {
        const self: *CountQuery = @ptrCast(@alignCast(@constCast(ptr)));
        self.face_calls += 1;
        // Two faces by glyph parity (stable tokens for grouping).
        const h: *const anyopaque = if (g % 2 == 0) @ptrCast(&face_a) else @ptrCast(&face_b);
        return .{ .h = h, .gid = g };
    }

    fn iface(self: *CountQuery) GlyphQuery {
        return .{
            .ptr = @ptrCast(self),
            .advance1000 = adv,
            .inkBounds1000 = ink,
            .faceOf = face,
        };
    }
};

test "fused shift covers runs and rules, else zero" {
    var cq = CountQuery{};
    var memo = GlyphMemo{};
    const q = cq.iface();
    // No negative ink: zero shifts (bit-identical canvas).
    const runs_ok = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    var sh = shiftUnits(&memo, q, &runs_ok, &.{}, 400);
    try std.testing.expectEqual(@as(u32, 0), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    // llap shape: run at -500 whose glyph overhangs a further 50.
    const runs_lap = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{'x'} },
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    sh = shiftUnits(&memo, q, &runs_lap, &.{}, 500);
    try std.testing.expectEqual(@as(u32, 550), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    // Origins step by advances inside a run: the walk sees the first
    // `x` at -500 (ink to -550), not just the run origin; the second
    // `x` at 0 reaches ink-right 550 past width 500.
    const runs_step = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{ 'x', 'x' } },
    };
    sh = shiftUnits(&memo, q, &runs_step, &.{}, 500);
    try std.testing.expectEqual(@as(u32, 550), sh.left);
    try std.testing.expectEqual(@as(u32, 50), sh.right);
    // Rules contribute their rect edges (right edge 60 stays inside
    // width 500, so only the left edge shifts).
    const rules = [_]zatex.ir.Rule{
        .{ .x = -40, .y = 0, .w = 100, .h = 10 },
    };
    sh = shiftUnits(&memo, q, &runs_ok, &rules, 500);
    try std.testing.expectEqual(@as(u32, 40), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    // Mirrored ink (issue #97) hangs off the ink right on the left
    // and off the negated ink left on the right: `y` mirrored at 0
    // reaches 0-390 left and 0-10 right; `x` mirrored at -500 reaches
    // -500-550 left and -500+50 right.
    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'}, .mirrored = true },
        .{ .font_id = 0, .size_units = 1000, .x = -500, .baseline_y = 0, .glyphs = &[_]u16{'x'}, .mirrored = true },
    };
    sh = shiftUnits(&memo, q, &runs_mir, &.{}, 500);
    try std.testing.expectEqual(@as(u32, 1050), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
}

test "fused shift covers right overhang (issue #96)" {
    // `\minuso` shape: the rlap circle's ink runs past the minus
    // advance, the way `\llap` ink runs left of the origin.
    var cq = CountQuery{};
    var memo = GlyphMemo{};
    const q = cq.iface();
    // Ink inside the advance: zero shifts (bit-identical canvas).
    const runs_ok = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'y'} },
    };
    var sh = shiftUnits(&memo, q, &runs_ok, &.{}, 400);
    try std.testing.expectEqual(@as(u32, 0), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    // Overhanging glyph: `x` ink reaches 550 past a 500 width.
    const runs_over = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'x'} },
    };
    sh = shiftUnits(&memo, q, &runs_over, &.{}, 500);
    try std.testing.expectEqual(@as(u32, 50), sh.left);
    try std.testing.expectEqual(@as(u32, 50), sh.right);
    // Rules contribute their rect right edge.
    const rules = [_]zatex.ir.Rule{
        .{ .x = 450, .y = 0, .w = 100, .h = 10 },
    };
    sh = shiftUnits(&memo, q, &runs_ok, &rules, 500);
    try std.testing.expectEqual(@as(u32, 0), sh.left);
    try std.testing.expectEqual(@as(u32, 50), sh.right);
    // Mirrored ink spans [-right, -left]: `x` mirrored at 500 reaches
    // 500+50 off the ink left, and hangs 500-550 off the ink right.
    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 500, .baseline_y = 0, .glyphs = &[_]u16{'x'}, .mirrored = true },
    };
    sh = shiftUnits(&memo, q, &runs_mir, &.{}, 500);
    try std.testing.expectEqual(@as(u32, 50), sh.left);
    try std.testing.expectEqual(@as(u32, 50), sh.right);
}

test "fused shift follows shear at ink extremes (issue #77)" {
    // Sheared dotless-j shape: ink left -40, top 442, bottom -205
    // (LM ȷ proportions). Shear 250 drags the descender tail left by
    // floor(250*205/1000) = 52, so the left edge is 0-40-52 = -92.
    // The top leans right (+110): 346+110 = 456 past width 400. A
    // query without the shear box keeps the unsheared bound.
    var cq = CountQuery{};
    var memo = GlyphMemo{};
    const q = cq.iface();
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'s'}, .x_shear = 250 },
    };
    var sh = shiftUnits(&memo, q, &runs, &.{}, 400);
    try std.testing.expectEqual(@as(u32, 92), sh.left);
    try std.testing.expectEqual(@as(u32, 56), sh.right);
    cq.shear_box = false;
    memo = .{};
    sh = shiftUnits(&memo, q, &runs, &.{}, 400);
    try std.testing.expectEqual(@as(u32, 40), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    // Mirrored shear (issue #97) leans the other way: the top (+110)
    // drags left, so the edge is 0-346-110 = -456; the bottom (-52)
    // lifts right to 0+40+52 = +92 past a zero width. Without the
    // shear box the bounds stay put (0-346 left, 0+40 right).
    const runs_mir = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{'s'}, .x_shear = 250, .mirrored = true },
    };
    cq.shear_box = true;
    memo = .{};
    sh = shiftUnits(&memo, q, &runs_mir, &.{}, 400);
    try std.testing.expectEqual(@as(u32, 456), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    cq.shear_box = false;
    memo = .{};
    sh = shiftUnits(&memo, q, &runs_mir, &.{}, 400);
    try std.testing.expectEqual(@as(u32, 346), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
}

test "energy fused shift queries each distinct glyph once" {
    // Two `x` plus one `y` (3 occurrences, 2 distinct): one fused
    // pass costs one advance + one ink query per distinct glyph, and
    // no face queries at all. Unfused twins would cost 2 ink + 1
    // advance per occurrence (9 total); fused-but-uncached one set
    // per occurrence (6).
    var cq = CountQuery{};
    var memo = GlyphMemo{};
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &[_]u16{ 'x', 'x', 'y' } },
    };
    const sh = shiftUnits(&memo, cq.iface(), &runs, &.{}, 2000);
    try std.testing.expectEqual(@as(u32, 50), sh.left);
    try std.testing.expectEqual(@as(u32, 0), sh.right);
    try std.testing.expectEqual(@as(usize, 2), cq.adv_calls);
    try std.testing.expectEqual(@as(usize, 2), cq.ink_calls);
    try std.testing.expectEqual(@as(usize, 0), cq.face_calls);
}

test "energy memo shares face lookups between grouping and draw" {
    // The draw loop's grouping pass and glyph pass resolve faces
    // through the same memo entries: 4 occurrences over 2 faces cost
    // 2 face queries total, and the later advance/ink fills ride the
    // same entries without extra face calls.
    var cq = CountQuery{};
    var memo = GlyphMemo{};
    const q = cq.iface();
    const glyphs = [_]u16{ 'x', 'y', 'x', 'y' };
    // Grouping pass: one face lookup per occurrence, memoized to 2.
    var groups: usize = 0;
    var gi: usize = 0;
    while (gi < glyphs.len) {
        const f0 = memoFace(&memo, q, glyphs[gi]) orelse return error.TestUnexpectedResult;
        var gj = gi + 1;
        while (gj < glyphs.len) {
            const dn = memoFace(&memo, q, glyphs[gj]) orelse break;
            if (dn.h != f0.h) break;
            gj += 1;
        }
        groups += 1;
        gi = gj;
    }
    // 'x' is even, 'y' is odd: single-face runs of length 1 each.
    try std.testing.expectEqual(@as(usize, 4), groups);
    try std.testing.expectEqual(@as(usize, 2), cq.face_calls);
    // Draw pass over the same glyphs: zero new face queries, and the
    // advance/ink fills land on the same warm entries.
    for (glyphs) |g| {
        _ = memoFace(&memo, q, g) orelse return error.TestUnexpectedResult;
        _ = memoAdvance(&memo, q, g);
        _ = memoInk(&memo, q, g);
    }
    try std.testing.expectEqual(@as(usize, 2), cq.face_calls);
    try std.testing.expectEqual(@as(usize, 2), cq.adv_calls);
    try std.testing.expectEqual(@as(usize, 2), cq.ink_calls);
}

test "energy memo evicts on collision without corrupting edges" {
    // Glyphs 16 apart share a slot: alternating them evicts every
    // time, but the validated key keeps every edge exact and every
    // query re-fires (no false hits).
    var cq = CountQuery{};
    var memo = GlyphMemo{};
    const q = cq.iface();
    var glyphs: [34]u16 = undefined;
    var i: usize = 0;
    while (i < glyphs.len) : (i += 1) glyphs[i] = if (i % 2 == 0) 'x' else 'x' + 16;
    const runs = [_]zatex.ir.Run{
        .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 0, .glyphs = &glyphs },
    };
    const sh = shiftUnits(&memo, q, &runs, &.{}, 500);
    // Origins step 500/400 alternating (17 `x` + 17 partners = 14900
    // at the last origin, whose inset ink reaches 15290): the first
    // `x` opens the left at -50, the last partner sets the right.
    try std.testing.expectEqual(@as(u32, 50), sh.left);
    try std.testing.expectEqual(@as(u32, 14790), sh.right);
    try std.testing.expectEqual(@as(usize, 34), cq.adv_calls);
    try std.testing.expectEqual(@as(usize, 34), cq.ink_calls);
    try std.testing.expectEqual(@as(usize, 0), cq.face_calls);
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
