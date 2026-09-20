//! ZaTeX C ABI: the embedding surface (issue 9).
//!
//! Reentrant, zero-allocation, no pointers in results: runs reference
//! the caller's glyph buffer by (start, count) indices, so outputs
//! stay valid as long as the caller's buffers do. Status codes mirror
//! `LayoutError`; `err_offset` carries ParseError parity.
const std = @import("std");
const zatex = @import("zatex.zig");

/// [height_above, depth_below] of one glyph at 1000 units (v4 C
/// surface, issue: sqrt junction; blank glyphs report [0, 0]).
pub const CExtents = extern struct {
    ha: i32,
    db: i32,
};

/// True ink box at 1000 units, y up from the baseline, unclipped
/// (v4 C surface; blank glyphs report all zeros).
pub const CInkBox = extern struct {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
};

/// Must match `zatex.h`. Nullable hooks map to the optional provider
/// hooks (null = deterministic fallback). New hooks append at the end:
/// old hosts (shorter struct) keep exact v3 behavior.
pub const CMetrics = extern struct {
    ctx: ?*const anyopaque,
    glyph_id: ?*const fn (ctx: ?*const anyopaque, font: u16, cp: u32) callconv(.c) u16,
    advance: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32,
    rule_thickness: ?*const fn (ctx: ?*const anyopaque, font: u16, kind: u32) callconv(.c) i32,
    glyph_variant: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16, min_height: i32) callconv(.c) u16 = null,
    italic_correction: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32 = null,
    kern_correction: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16, height: i32, corner: u32) callconv(.c) i32 = null,
    extents: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) CExtents = null,
    ink_bounds: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) CInkBox = null,
};

pub const CRun = extern struct {
    font_id: u16,
    size_units: u16,
    x: i32,
    baseline_y: i32,
    glyph_start: u32,
    glyph_count: u32,
    /// Horizontal raster scale in per-mille (1000 = identity), the
    /// `ir.Run.x_scale` stretch factor (issue #197: wide accents,
    /// braces, arrows). Must match `zatex.h` `zatex_run_t.x_scale`.
    /// Appended — old readers ignore the tail and draw unstretched,
    /// exactly as before.
    x_scale: u16 = 1000,
};

pub const CRule = extern struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
};

pub const CLayout = extern struct {
    width: u32,
    height_above: u32,
    depth_below: u32,
    nruns: u32,
    nrules: u32,
    status: i32,
    err_offset: u32,
    /// `Diag.message` bytes on failure (issues #126/#136): pointer
    /// into static storage, always valid (never freed); length in
    /// `err_msg_len`. Null/0 on success. Appended, never reordered —
    /// old readers ignore the tail.
    err_msg: ?[*]const u8 = null,
    err_msg_len: usize = 0,
};

pub const STATUS_OK: i32 = 0;
pub const STATUS_UNSUPPORTED: i32 = 1;
pub const STATUS_INVALID: i32 = 2;
pub const STATUS_TOO_DEEP: i32 = 3;
pub const STATUS_TOO_LONG: i32 = 4;
pub const STATUS_EXPANSION_LIMIT: i32 = 5;
pub const STATUS_NO_SPACE: i32 = 6;
pub const STATUS_LIMIT: i32 = 7;

fn toStatus(e: zatex.LayoutError) i32 {
    return switch (e) {
        error.Unsupported => STATUS_UNSUPPORTED,
        error.Invalid => STATUS_INVALID,
        error.TooDeep => STATUS_TOO_DEEP,
        error.TooLong => STATUS_TOO_LONG,
        error.ExpansionLimit => STATUS_EXPANSION_LIMIT,
        error.NoSpace => STATUS_NO_SPACE,
        error.OutOfMemory => STATUS_NO_SPACE,
    };
}

const Host = struct {
    m: *const CMetrics,

    fn gid(ctx: *const anyopaque, font: u16, cp: u21) u16 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.glyph_id orelse return 0;
        return f(h.m.ctx, font, cp);
    }
    fn adv(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.advance orelse return 500;
        return f(h.m.ctx, font, glyph);
    }
    fn rule(ctx: *const anyopaque, font: u16, kind: zatex.RuleKind) i32 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.rule_thickness orelse return 40;
        return f(h.m.ctx, font, @intFromEnum(kind));
    }
    fn variant(ctx: *const anyopaque, font: u16, glyph: u16, need: i32) u16 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.glyph_variant orelse return glyph;
        return f(h.m.ctx, font, glyph, need);
    }
    fn italic(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.italic_correction orelse return 0;
        return f(h.m.ctx, font, glyph);
    }
    fn kern(ctx: *const anyopaque, font: u16, glyph: u16, height: i32, corner: zatex.contract.KernCorner) i32 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.kern_correction orelse return 0;
        return f(h.m.ctx, font, glyph, height, @intFromEnum(corner));
    }
    fn ext(ctx: *const anyopaque, font: u16, glyph: u16) [2]i32 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.extents orelse return .{ 700, 250 };
        const e = f(h.m.ctx, font, glyph);
        return .{ e.ha, e.db };
    }
    fn ink(ctx: *const anyopaque, font: u16, glyph: u16) [4]i32 {
        const h: *const Host = @ptrCast(@alignCast(ctx));
        const f = h.m.ink_bounds orelse return .{ 0, 0, 0, 0 };
        const b = f(h.m.ctx, font, glyph);
        return .{ b.x0, b.y0, b.x1, b.y1 };
    }
};

/// One bridge for every engine entry: the same C hooks back both
/// layout and the conformance check, so a clean conformance run
/// describes the provider layout actually sees. `host` must outlive
/// the returned provider (callers keep it on their stack frame).
fn hostProvider(m: *const CMetrics, host: *const Host) zatex.MetricsProvider {
    return .{
        .ctx = @ptrCast(host),
        .glyphId = Host.gid,
        .advance = Host.adv,
        .ruleThickness = Host.rule,
        .glyphVariant = if (m.glyph_variant != null) Host.variant else null,
        .italicCorrection = if (m.italic_correction != null) Host.italic else null,
        .kernCorrection = if (m.kern_correction != null) Host.kern else null,
        // Null C hooks stay null natively: the core keeps its own
        // fallbacks bit-identically (no duplicated constants here).
        .extents = if (m.extents != null) Host.ext else null,
        .inkBounds = if (m.ink_bounds != null) Host.ink else null,
    };
}

/// Lay out one UTF-8 formula. All buffers are caller-owned. `src_len`
/// is capped at `max_input_len`; output counts are capped by the
/// buffer lengths (`STATUS_NO_SPACE` on overflow).
export fn zatex_layout_utf8(
    src_ptr: ?[*]const u8,
    src_len: usize,
    display_mode: bool,
    metrics: ?*const CMetrics,
    runs_ptr: ?[*]CRun,
    runs_cap: usize,
    rules_ptr: ?[*]CRule,
    rules_cap: usize,
    glyphs_ptr: ?[*]u16,
    glyphs_cap: usize,
    out_ptr: ?*CLayout,
) i32 {
    const out = out_ptr orelse return STATUS_NO_SPACE;
    out.* = .{
        .width = 0,
        .height_above = 0,
        .depth_below = 0,
        .nruns = 0,
        .nrules = 0,
        .status = STATUS_NO_SPACE,
        .err_offset = 0,
        .err_msg = null,
        .err_msg_len = 0,
    };
    const m = metrics orelse return STATUS_NO_SPACE;
    if (src_len > zatex.max_input_len) {
        out.status = STATUS_TOO_LONG;
        return out.status;
    }
    const src = (src_ptr orelse return STATUS_NO_SPACE)[0..src_len];
    const host = Host{ .m = m };
    const prov = hostProvider(m, &host);
    // Reinterpret caller buffers as Zig slices.
    const runs_z = (runs_ptr orelse return STATUS_NO_SPACE)[0..runs_cap];
    const rules_z = (rules_ptr orelse return STATUS_NO_SPACE)[0..rules_cap];
    const glyphs = (glyphs_ptr orelse return STATUS_NO_SPACE)[0..glyphs_cap];
    // Bridge C runs/rules to the IR shapes with a fixed scratch
    // overlay: layout into stack temporaries, then translate.
    var runs_tmp: [256]zatex.ir.Run = undefined;
    var rules_tmp: [64]zatex.ir.Rule = undefined;
    // Engine hard ceilings (documented in zatex.h): requests above
    // them fail STATUS_LIMIT instead of silently depending on how
    // much the fixed temporaries happen to hold.
    if (runs_cap > runs_tmp.len or rules_cap > rules_tmp.len) {
        out.status = STATUS_LIMIT;
        out.err_offset = 0;
        return out.status;
    }
    var diag = zatex.Diag.empty();
    const l = zatex.layoutInner(src, .{ .display_mode = display_mode }, prov, runs_tmp[0..runs_cap], rules_tmp[0..rules_cap], glyphs, &diag) catch |e| {
        out.status = toStatus(e);
        out.err_offset = diag.offset;
        // `Diag.message` crosses the ABI (issues #126/#136): static
        // storage, so the pointer outlives the call unconditionally.
        // Empty messages surface as null (no partial reads).
        if (diag.message.len > 0) {
            out.err_msg = diag.message.ptr;
            out.err_msg_len = diag.message.len;
        } else {
            out.err_msg = null;
            out.err_msg_len = 0;
        }
        return out.status;
    };
    if (l.runs.len > runs_z.len) {
        out.status = STATUS_NO_SPACE;
        out.err_offset = 0;
        return out.status;
    }
    // Energy (#155): glyph slices emit run-sequentially into the
    // caller buffer, so `glyph_start` is a running cursor — no
    // per-run pointer subtraction. Debug builds assert contiguity
    // against the old difference on every run.
    var ng: u32 = 0;
    for (l.runs, 0..) |r, i| {
        // Active in test/Debug builds; compiled out of ReleaseSmall.
        const start = (@intFromPtr(r.glyphs.ptr) - @intFromPtr(glyphs.ptr)) / 2;
        std.debug.assert(start == ng);
        runs_z[i] = .{
            .font_id = r.font_id,
            .size_units = r.size_units,
            .x = r.x,
            .baseline_y = r.baseline_y,
            .glyph_start = ng,
            .glyph_count = @intCast(r.glyphs.len),
            // Stretch factor (issue #197): without it C hosts draw
            // wide accents at natural size, off-span.
            .x_scale = r.x_scale,
        };
        ng += @intCast(r.glyphs.len);
    }
    // The frozen narrow surface projects filled rects only: diagonal
    // strikes (issue #107 `Rule.diag`) have no rect form, so they are
    // skipped rather than misdrawn (like color, which this surface
    // already drops — see `CRule`).
    // Energy (#155): the rect recount and the translate copy fuse
    // into one pass with an incremental cap check. Status contract
    // is unchanged (`STATUS_NO_SPACE` exactly as before; error-path
    // buffer contents were never specified); the happy path drops
    // from two rule traversals to one.
    var nrules: u32 = 0;
    for (l.rules) |r| {
        if (r.diag != .none) continue;
        if (nrules >= rules_z.len) {
            out.status = STATUS_NO_SPACE;
            out.err_offset = 0;
            return out.status;
        }
        rules_z[nrules] = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        nrules += 1;
    }
    out.* = .{
        .width = l.width,
        .height_above = l.height_above,
        .depth_below = l.depth_below,
        .nruns = @intCast(l.runs.len),
        .nrules = nrules,
        .status = STATUS_OK,
        .err_offset = 0,
        .err_msg = null,
        .err_msg_len = 0,
    };
    return STATUS_OK;
}

/// Packed semantic version: major << 16 | minor << 8 | patch.
export fn zatex_version() u32 {
    return (@as(u32, zatex.version.major) << 16) |
        (@as(u32, zatex.version.minor) << 8) | zatex.version.patch;
}

/// Host metrics conformance check (issue #194). Runs the diagnostic
/// corpus (`zatex.conform`) against the host's `metrics` at `font`:
/// no rendering, no engine rebuild — the check ships in the library
/// and exercises the same bridge the layout path uses.
///
/// Returns the diagnostic count (0 is a clean pass; -1 is a usage
/// error: null `metrics`, or non-null `buf` with zero `cap`). When
/// `buf` is non-null, newline-separated diagnostics fill
/// `buf[0..buf_cap]` truncated to fit and always NUL-terminated (a
/// null `buf` counts only, for dry runs).
export fn zatex_conform_metrics(metrics: ?*const CMetrics, font: u16, buf_ptr: ?[*]u8, buf_cap: usize) i32 {
    const m = metrics orelse return -1;
    const host = Host{ .m = m };
    const prov = hostProvider(m, &host);
    var scratch: [3072]u8 = undefined;
    const res = zatex.conform.check(prov, font, &scratch);
    if (buf_ptr) |bp| {
        if (buf_cap == 0) return -1;
        const out = bp[0..buf_cap];
        const take = @min(res.bytes, buf_cap - 1);
        @memcpy(out[0..take], scratch[0..take]);
        out[take] = 0;
    }
    return @intCast(res.diagnostics);
}

test "cabi lays out through C function pointers" {
    const S = struct {
        fn gid(_: ?*const anyopaque, _: u16, cp: u32) callconv(.c) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return 500;
        }
        fn rt(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return 40;
        }
    };
    const m: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt };
    var runs: [16]CRun = undefined;
    var rules: [8]CRule = undefined;
    var glyphs: [64]u16 = undefined;
    var out: CLayout = undefined;
    const src = "x^2+\\frac12";
    const st = zatex_layout_utf8(src.ptr, src.len, false, &m, &runs, runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_OK, st);
    try std.testing.expect(out.nruns > 0 and out.nrules == 1);
    // Glyph index ranges land inside the caller buffer.
    for (runs[0..out.nruns]) |r| {
        try std.testing.expect(r.glyph_start + r.glyph_count <= glyphs.len);
    }
}

test "cabi v4 extents+ink flow into layout, null keeps v3" {
    // The sqrt junction is the coverage: with null v4 hooks the
    // vinculum starts at the radical advance edge (exact v3); with
    // real extents+ink it reshapes the box and pulls into the hook.
    const S = struct {
        fn gid(_: ?*const anyopaque, _: u16, cp: u32) callconv(.c) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return 500;
        }
        fn rt(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return 40;
        }
        fn ext(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) CExtents {
            return .{ .ha = 900, .db = 300 };
        }
        fn ink(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) CInkBox {
            return .{ .x0 = 10, .y0 = -50, .x1 = 480, .y1 = 950 };
        }
    };
    const src = "\\sqrt{x}";
    const m_null: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt };
    var runs0: [16]CRun = undefined;
    var rules0: [4]CRule = undefined;
    var glyphs0: [64]u16 = undefined;
    var out0: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(src.ptr, src.len, false, &m_null, &runs0, runs0.len, &rules0, rules0.len, &glyphs0, glyphs0.len, &out0));
    try std.testing.expectEqual(@as(u32, 1), out0.nrules);
    const m_v4: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt, .extents = S.ext, .ink_bounds = S.ink };
    var runs1: [16]CRun = undefined;
    var rules1: [4]CRule = undefined;
    var glyphs1: [64]u16 = undefined;
    var out1: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(src.ptr, src.len, false, &m_v4, &runs1, runs1.len, &rules1, rules1.len, &glyphs1, glyphs1.len, &out1));
    try std.testing.expectEqual(@as(u32, 1), out1.nrules);
    try std.testing.expect(rules1[0].x < rules0[0].x);
    try std.testing.expect(out1.height_above != out0.height_above);
}

test "cabi run layout is frozen v1 plus appended x_scale (issue #197)" {
    // Frozen v1 prefix: field offsets never move, so old readers
    // keep parsing the head. `x_scale` appends at the tail (same
    // policy as `CLayout.err_msg`), padding the struct to 24.
    comptime {
        std.debug.assert(@offsetOf(CRun, "font_id") == 0);
        std.debug.assert(@offsetOf(CRun, "size_units") == 2);
        std.debug.assert(@offsetOf(CRun, "x") == 4);
        std.debug.assert(@offsetOf(CRun, "baseline_y") == 8);
        std.debug.assert(@offsetOf(CRun, "glyph_start") == 12);
        std.debug.assert(@offsetOf(CRun, "glyph_count") == 16);
        std.debug.assert(@offsetOf(CRun, "x_scale") == 20);
        std.debug.assert(@sizeOf(CRun) == 24);
        // The rect surface is untouched by this change.
        std.debug.assert(@sizeOf(CRule) == 16);
    }
}

test "cabi carries x_scale through for wide accents (issue #197)" {
    // `\widetilde{AB}` / `\widehat{AB}` through the C ABI must span
    // their nuclei exactly like the IR backend: every run's origin
    // and stretch factor match the Zig surface run-for-run, and the
    // stretched accent advance covers the nucleus span. Stub
    // advances are uniform 500 (null v4 hooks): AB spans 1000 over
    // the 500-wide accent glyph, so the factor is 2000.

    const S = struct {
        fn gid(_: ?*const anyopaque, _: u16, cp: u32) callconv(.c) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return 500;
        }
        fn rt(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return 40;
        }
    };
    const Z = struct {
        var dummy: u8 = 0;
        fn gid(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn rt(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
            return 40;
        }
    };
    const zprov: zatex.MetricsProvider = .{
        .ctx = &Z.dummy,
        .glyphId = Z.gid,
        .advance = Z.adv,
        .ruleThickness = Z.rt,
    };
    const m: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt };
    // accent codepoint per input: `~` (widetilde), `^` (widehat).
    const cases = [_]struct { tex: []const u8, accent: u16 }{
        .{ .tex = "\\widetilde{AB}", .accent = 0x007E },
        .{ .tex = "\\widehat{AB}", .accent = 0x005E },
    };
    for (cases) |c| {
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        const st = zatex_layout_utf8(c.tex.ptr, c.tex.len, false, &m, &runs, runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
        try std.testing.expectEqual(STATUS_OK, st);
        // Independent oracle: the Zig surface on the same input with
        // the equivalent provider (the IR backend's own view).
        var zruns: [16]zatex.ir.Run = undefined;
        var zrules: [8]zatex.ir.Rule = undefined;
        var zglyphs: [64]u16 = undefined;
        const l = try zatex.layoutFull(c.tex, .{}, zprov, &zruns, &zrules, &zglyphs);
        try std.testing.expectEqual(l.runs.len, out.nruns);
        var accent_scale: ?u16 = null;
        for (l.runs, 0..) |zr, i| {
            const cr = runs[i];
            try std.testing.expectEqual(zr.font_id, cr.font_id);
            try std.testing.expectEqual(zr.size_units, cr.size_units);
            try std.testing.expectEqual(zr.x, cr.x);
            try std.testing.expectEqual(zr.baseline_y, cr.baseline_y);
            try std.testing.expectEqual(zr.x_scale, cr.x_scale);
            try std.testing.expectEqual(zr.glyphs.len, cr.glyph_count);
            const cg = glyphs[cr.glyph_start..][0..cr.glyph_count];
            try std.testing.expectEqualSlices(u16, zr.glyphs, cg);
            for (cg) |g| {
                if (g == c.accent) accent_scale = cr.x_scale;
            }
        }
        // The accent run stretches (2000 over the 500 stub glyph)
        // and the stretched ink spans the 1000-wide nucleus: the C
        // host draws it with the documented origin-scale recipe.
        try std.testing.expectEqual(@as(?u16, 2000), accent_scale);
        try std.testing.expectEqual(@as(u32, 1000), l.width);
        try std.testing.expectEqual(@as(u32, 1000), out.width);
    }
}

test "cabi conform entry: usage errors, truncation, termination" {
    const S = struct {
        fn gid(_: ?*const anyopaque, _: u16, cp: u32) callconv(.c) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return 500;
        }
        fn rt(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return 40;
        }
    };
    const m: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt };
    var buf: [2048]u8 = undefined;
    try std.testing.expectEqual(@as(i32, -1), zatex_conform_metrics(null, 0, &buf, buf.len));
    try std.testing.expectEqual(@as(i32, -1), zatex_conform_metrics(&m, 0, &buf, 0));
    // Dry run counts without writing.
    const dry = zatex_conform_metrics(&m, 0, null, 0);
    try std.testing.expect(dry > 0);
    // Full buffer: same count, NUL-terminated named diagnostics.
    @memset(&buf, 0xAA);
    const n = zatex_conform_metrics(&m, 0, &buf, buf.len);
    try std.testing.expectEqual(dry, n);
    try std.testing.expect(std.mem.indexOfScalar(u8, &buf, 0) != null);
    try std.testing.expect(std.mem.indexOf(u8, &buf, "advance U+20D7: got 500, want 0") != null);
    // Tiny buffer: same count, still NUL-terminated.
    @memset(&buf, 0xAA);
    try std.testing.expectEqual(dry, zatex_conform_metrics(&m, 0, &buf, 32));
    try std.testing.expectEqual(@as(u8, 0), buf[31]);
}

test "cabi reports Invalid with offset" {
    const m: CMetrics = .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null };
    var runs: [4]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var out: CLayout = undefined;
    const src = "\\nope";
    const st = zatex_layout_utf8(src.ptr, src.len, false, &m, &runs, runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_INVALID, st);
    try std.testing.expectEqual(@as(u32, 0), out.err_offset);
}

test "cabi carries Diag.message bytes on failure (issues #126, #136)" {
    // Every `Invalid` reachable through the C entry point yields a
    // non-empty message identical to the Zig `layoutDiag` one; the
    // pointer is static storage (re-readable after the call).
    // Success clears both fields.
    const m: CMetrics = .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null };
    const rejects = [_][]const u8{
        "\\nope",
        "x^2^3",
        "{x",
        "\\tag{1}x",
        "x_\\hbox{x}",
    };
    for (rejects) |src| {
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        const st = zatex_layout_utf8(src.ptr, src.len, false, &m, &runs, runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
        try std.testing.expectEqual(STATUS_INVALID, st);
        try std.testing.expect(out.err_msg_len > 0);
        const cmsg = out.err_msg.?[0..out.err_msg_len];
        // Same bytes the Zig surface reports (independent oracle:
        // `layoutDiag` on the same input).
        var zruns: [16]zatex.ir.Run = undefined;
        var zrules: [8]zatex.ir.Rule = undefined;
        var zglyphs: [64]u16 = undefined;
        var diag = zatex.Diag.empty();
        const S = struct {
            var dummy: u8 = 0;
            fn gid(_: *const anyopaque, _: u16, cp: u21) u16 {
                return @intCast(cp & 0xFFFF);
            }
            fn adv(_: *const anyopaque, _: u16, _: u16) i32 {
                return 500;
            }
            fn rt(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
                return 40;
            }
        };
        const prov: zatex.MetricsProvider = .{
            .ctx = &S.dummy,
            .glyphId = S.gid,
            .advance = S.adv,
            .ruleThickness = S.rt,
        };
        try std.testing.expectError(
            error.Invalid,
            zatex.layoutDiag(src, .{}, prov, &zruns, &zrules, &zglyphs, &diag),
        );
        try std.testing.expectEqual(diag.offset, out.err_offset);
        try std.testing.expectEqualStrings(diag.message, cmsg);
    }
    // Success: null message, zero length.
    {
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        const src = "x^2+\\frac12";
        const st = zatex_layout_utf8(src.ptr, src.len, false, &m, &runs, runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
        try std.testing.expectEqual(STATUS_OK, st);
        try std.testing.expect(out.err_msg == null);
        try std.testing.expectEqual(@as(usize, 0), out.err_msg_len);
    }
}

test "cabi reports Limit above engine ceilings" {
    const m: CMetrics = .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null };
    var runs: [4]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var big_runs: [300]CRun = undefined;
    var big_rules: [100]CRule = undefined;
    var out: CLayout = undefined;
    const src = "x";
    const st_runs = zatex_layout_utf8(src.ptr, src.len, false, &m, &big_runs, big_runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_LIMIT, st_runs);
    const st_rules = zatex_layout_utf8(src.ptr, src.len, false, &m, &runs, runs.len, &big_rules, big_rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_LIMIT, st_rules);
    // At-ceiling buffers still serve small formulas.
    var cap_runs: [256]CRun = undefined;
    var cap_rules: [64]CRule = undefined;
    const st_ok = zatex_layout_utf8(src.ptr, src.len, false, &m, &cap_runs, cap_runs.len, &cap_rules, cap_rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_OK, st_ok);
}

test "cabi reports NoSpace when caller buffers overflow" {
    const m: CMetrics = .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null };
    var runs: [8]CRun = undefined;
    var tiny_runs: [0]CRun = undefined;
    var rules: [4]CRule = undefined;
    var tiny_rules: [0]CRule = undefined;
    var glyphs: [64]u16 = undefined;
    var out: CLayout = undefined;
    const src = "\\frac12";
    const st_runs = zatex_layout_utf8(src.ptr, src.len, false, &m, &tiny_runs, tiny_runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_NO_SPACE, st_runs);
    const st_rules = zatex_layout_utf8(src.ptr, src.len, false, &m, &runs, runs.len, &tiny_rules, tiny_rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_NO_SPACE, st_rules);
}
test "cabi adversarial provider stays total and deterministic" {
    const S = struct {
        fn adv0(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return 0;
        }
        fn advNeg(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return -500;
        }
        fn ruleHuge(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return 1_000_000;
        }
        fn ruleNeg(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return -40;
        }
        fn gid0(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) u16 {
            return 0;
        }
        fn kern30(_: ?*const anyopaque, _: u16, _: u16, _: i32, _: u32) callconv(.c) i32 {
            return 30;
        }
    };
    const base: CMetrics = .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null };
    const cfgs = [_]CMetrics{
        .{ .ctx = null, .glyph_id = null, .advance = S.adv0, .rule_thickness = null },
        .{ .ctx = null, .glyph_id = null, .advance = S.advNeg, .rule_thickness = null },
        .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = S.ruleHuge },
        .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = S.ruleNeg },
        .{ .ctx = null, .glyph_id = S.gid0, .advance = null, .rule_thickness = null },
        .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null, .kern_correction = S.kern30 },
        base,
    };
    const src = "x+\\frac{a}{b}";
    for (cfgs) |m| {
        var r1: [64]CRun = undefined;
        var l1: [16]CRule = undefined;
        var g1: [512]u16 = undefined;
        var r2: [64]CRun = undefined;
        var l2: [16]CRule = undefined;
        var g2: [512]u16 = undefined;
        var o1: CLayout = undefined;
        var o2: CLayout = undefined;
        const s1 = zatex_layout_utf8(src.ptr, src.len, false, &m, &r1, r1.len, &l1, l1.len, &g1, g1.len, &o1);
        const s2 = zatex_layout_utf8(src.ptr, src.len, false, &m, &r2, r2.len, &l2, l2.len, &g2, g2.len, &o2);
        try std.testing.expectEqual(s1, s2);
        if (s1 == STATUS_OK) {
            try std.testing.expectEqual(o1.width, o2.width);
            try std.testing.expectEqual(o1.height_above, o2.height_above);
            try std.testing.expectEqual(o1.depth_below, o2.depth_below);
            try std.testing.expectEqual(o1.nruns, o2.nruns);
            try std.testing.expectEqual(o1.nrules, o2.nrules);
        }
    }
}
