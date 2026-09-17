//! ZaTeX C ABI: the embedding surface (issue 9).
//!
//! Reentrant, zero-allocation, no pointers in results: runs reference
//! the caller's glyph buffer by (start, count) indices, so outputs
//! stay valid as long as the caller's buffers do. Status codes mirror
//! `LayoutError`; `err_offset` carries ParseError parity.
const std = @import("std");
const zatex = @import("zatex.zig");

/// Must match `zatex.h`. Nullable hooks map to the optional provider
/// hooks (null = deterministic fallback).
pub const CMetrics = extern struct {
    ctx: ?*const anyopaque,
    glyph_id: ?*const fn (ctx: ?*const anyopaque, font: u16, cp: u32) callconv(.c) u16,
    advance: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32,
    rule_thickness: ?*const fn (ctx: ?*const anyopaque, font: u16, kind: u32) callconv(.c) i32,
    glyph_variant: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16, min_height: i32) callconv(.c) u16 = null,
    italic_correction: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32 = null,
    kern_correction: ?*const fn (ctx: ?*const anyopaque, font: u16, glyph: u16, height: i32, corner: u32) callconv(.c) i32 = null,
};

pub const CRun = extern struct {
    font_id: u16,
    size_units: u16,
    x: i32,
    baseline_y: i32,
    glyph_start: u32,
    glyph_count: u32,
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
};

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
    };
    const m = metrics orelse return STATUS_NO_SPACE;
    if (src_len > zatex.max_input_len) {
        out.status = STATUS_TOO_LONG;
        return out.status;
    }
    const src = (src_ptr orelse return STATUS_NO_SPACE)[0..src_len];
    const host = Host{ .m = m };
    const prov: zatex.MetricsProvider = .{
        .ctx = @ptrCast(&host),
        .glyphId = Host.gid,
        .advance = Host.adv,
        .ruleThickness = Host.rule,
        .glyphVariant = Host.variant,
        .italicCorrection = Host.italic,
        .kernCorrection = Host.kern,
    };
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
    };
    return STATUS_OK;
}

/// MathML Core serialization into caller-owned `out`. Returns the
/// byte count, or a negative status on error.
export fn zatex_mathml_utf8(
    src_ptr: ?[*]const u8,
    src_len: usize,
    display_mode: bool,
    out_ptr: ?[*]u8,
    out_cap: usize,
) isize {
    const out = (out_ptr orelse return -STATUS_NO_SPACE)[0..out_cap];
    if (src_len > zatex.max_input_len) return -STATUS_TOO_LONG;
    const src = (src_ptr orelse return -STATUS_NO_SPACE)[0..src_len];
    const s = zatex.mathml(src, .{ .display_mode = display_mode }, out) catch |e| return -toStatus(e);
    return @intCast(s.len);
}

/// Packed semantic version: major << 16 | minor << 8 | patch.
export fn zatex_version() u32 {
    return (@as(u32, zatex.version.major) << 16) |
        (@as(u32, zatex.version.minor) << 8) | zatex.version.patch;
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
test "cabi mathml truncates with negative NoSpace" {
    var tiny: [8]u8 = undefined;
    const src = "\\frac{a}{b}";
    const n = zatex_mathml_utf8(src.ptr, src.len, false, &tiny, tiny.len);
    try std.testing.expectEqual(-STATUS_NO_SPACE, n);
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

test "cabi mathml serializes" {
    var out: [256]u8 = undefined;
    const src = "\\frac12";
    const n = zatex_mathml_utf8(src.ptr, src.len, false, &out, out.len);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, out[0..@intCast(n)], "<mfrac>") != null);
}
