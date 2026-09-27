//! libzatex_test — scripted test double for hosts (issue #274).
//!
//! Every host hand-rolls engine stubs to test its OK and fallback
//! paths; this ships one blessed stub implementing the SAME `zatex.h`
//! entry points with deterministic scripted responses, so hosts
//! `dlopen` the double in CI instead of maintaining their own.
//!
//! This is a stub, not a second engine: there is no layout math
//! here, only fixed scripted bytes (AGENTS.md: one layout core).
//! It never calls the metrics hooks and never imports the engine —
//! `testdouble.zig` compiles standalone, zero dependencies.
//!
//! Script protocol (mirrored as `ZATEX_TD_*` macros in
//! `zatex_testdouble.h`; the header is normative):
//! - `\frac{a}{b}+x^2` (the hello-formula input) → STATUS_OK with a
//!   fixed 3-run / 1-rule / 5-glyph layout. One run carries a
//!   non-identity `x_scale` and one a non-ambient `color`, so hosts
//!   can observe tail delivery through `_ex`.
//! - `__ZATEX_TD_NOSPACE__` → STATUS_NO_SPACE with `nruns`/`nrules`
//!   needs (buffers untouched), modelling a layable formula that
//!   needs bigger caller buffers.
//! - `__ZATEX_TD_LIMIT__` → STATUS_LIMIT with over-ceiling needs
//!   (buffers untouched), modelling a request even maximum buffers
//!   cannot satisfy.
//! - `__ZATEX_TD_BAD__` → STATUS_INVALID with `err_offset` 5 and a
//!   static message, modelling a bad-input fallback.
//! - Anything else → STATUS_INVALID, offset 0 (explicitness: the
//!   double only speaks its script).
//!
//! Shapes mirror the real engine where hosts can observe them: null
//! `out` returns NO_SPACE, null metrics/source returns NO_SPACE with
//! zeroed counts, inputs over 65536 bytes return TOO_LONG, strides
//! below 20 return LIMIT without touching the runs buffer, null
//! buffers act as sizing probes (NO_SPACE with needs), and short
//! buffers on the OK script return NO_SPACE with needs. The stride
//! contract is honored field-for-field (v1 prefix always, `x_scale`
//! iff stride >= 22, `color` iff stride >= 28).
const std = @import("std");

/// Must match `zatex.h` / `cabi.zig` field-for-field (frozen ABI).
pub const CRun = extern struct {
    font_id: u16,
    size_units: u16,
    x: i32,
    baseline_y: i32,
    glyph_start: u32,
    glyph_count: u32,
    x_scale: u16 = 1000,
    color: u32 = 0,
};

pub const CRunV1 = extern struct {
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

pub const CExtents = extern struct {
    ha: i32,
    db: i32,
};

pub const CInkBox = extern struct {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
};

pub const CLayout = extern struct {
    width: u32,
    height_above: u32,
    depth_below: u32,
    nruns: u32,
    nrules: u32,
    status: i32,
    err_offset: u32,
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

pub const CAP_X_SCALE: u32 = 1 << 0;
pub const CAP_RUN_COLOR: u32 = 1 << 1;
pub const CAP_NEED_COUNTS: u32 = 1 << 2;

pub const crun_v1_len: usize = 20;
pub const crun_xscale_off: usize = 20;
pub const crun_xscale_end: usize = 22;
pub const crun_color_off: usize = 24;
pub const crun_color_end: usize = 28;

pub const max_input_len: usize = 65536;

// Script inputs (mirrored in `zatex_testdouble.h` — update both).
pub const script_hello: []const u8 = "\\frac{a}{b}+x^2";
pub const script_nospace: []const u8 = "__ZATEX_TD_NOSPACE__";
pub const script_limit: []const u8 = "__ZATEX_TD_LIMIT__";
pub const script_bad: []const u8 = "__ZATEX_TD_BAD__";

// File-scope statics: the message pointers outlive the call
// unconditionally (same contract as the engine's `Diag.message`).
const msg_bad: []const u8 = "test-double: forced bad input";
const msg_unknown: []const u8 = "test-double: unknown script (use ZATEX_TD_* sentinels)";
const conform_diag: []const u8 = "test-double: scripted conform diagnostic\n";

// Fixed OK-script layout: 3 runs, 1 rule, 5 backing glyphs.
// Run 1 carries a stretched tail and run 2 a paint tail so hosts
// observe `_ex` tail delivery (v1 readers see the same heads).
const hello_runs: [3]CRun = .{
    .{ .font_id = 0, .size_units = 1000, .x = 0, .baseline_y = 900, .glyph_start = 0, .glyph_count = 2, .x_scale = 1000, .color = 0 },
    .{ .font_id = 0, .size_units = 700, .x = 500, .baseline_y = 600, .glyph_start = 2, .glyph_count = 1, .x_scale = 2000, .color = 0 },
    .{ .font_id = 1, .size_units = 1000, .x = 1200, .baseline_y = 900, .glyph_start = 3, .glyph_count = 2, .x_scale = 1000, .color = 0xFF0000FF },
};
const hello_rules: [1]CRule = .{.{ .x = 100, .y = 650, .w = 800, .h = 40 }};
const hello_glyphs: [5]u16 = .{ 0x61, 0x62, 0x61, 0x78, 0x32 };
const hello_width: u32 = 2100;
const hello_above: u32 = 900;
const hello_below: u32 = 350;

// Forced needs: NO_SPACE models a layable formula (allocate and
// retry); LIMIT models an over-ceiling request (even maximum
// buffers fail — 256 runs / 64 rules are the engine ceilings).
const nospace_runs: u32 = 3;
const nospace_rules: u32 = 2;
const limit_runs: u32 = 300;
const limit_rules: u32 = 70;

fn layoutImpl(
    src_ptr: ?[*]const u8,
    src_len: usize,
    metrics: ?*const CMetrics,
    runs_ptr: ?*anyopaque,
    runs_cap: usize,
    runs_stride: usize,
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
    _ = m; // scripted: hooks are never called (NULL hooks are fine).
    if (src_len > max_input_len) {
        out.status = STATUS_TOO_LONG;
        return out.status;
    }
    const src = (src_ptr orelse return STATUS_NO_SPACE)[0..src_len];

    if (std.mem.eql(u8, src, script_nospace)) {
        out.status = STATUS_NO_SPACE;
        out.nruns = nospace_runs;
        out.nrules = nospace_rules;
        return out.status;
    }
    if (std.mem.eql(u8, src, script_limit)) {
        out.status = STATUS_LIMIT;
        out.nruns = limit_runs;
        out.nrules = limit_rules;
        return out.status;
    }
    if (std.mem.eql(u8, src, script_bad)) {
        out.status = STATUS_INVALID;
        out.err_offset = 5;
        out.err_msg = msg_bad.ptr;
        out.err_msg_len = msg_bad.len;
        return out.status;
    }
    if (!std.mem.eql(u8, src, script_hello)) {
        out.status = STATUS_INVALID;
        out.err_offset = 0;
        out.err_msg = msg_unknown.ptr;
        out.err_msg_len = msg_unknown.len;
        return out.status;
    }

    // OK script: space accounting mirrors the engine (probe or short
    // buffers report NO_SPACE with the needs; caller buffers stay
    // untouched), then one bulk copy through the stride contract.
    const need_runs: u32 = hello_runs.len;
    const need_rules: u32 = hello_rules.len;
    const need_glyphs: usize = hello_glyphs.len;
    const short = need_runs > runs_cap or need_rules > rules_cap or need_glyphs > glyphs_cap;
    const probe = runs_ptr == null or rules_ptr == null or glyphs_ptr == null;
    if (probe or short or runs_stride < crun_v1_len) {
        out.status = if (probe or short) STATUS_NO_SPACE else STATUS_LIMIT;
        out.nruns = need_runs;
        out.nrules = need_rules;
        return out.status;
    }
    const runs_base: [*]u8 = @ptrCast(runs_ptr.?);
    const rules_z = rules_ptr.?[0..rules_cap];
    const glyphs = glyphs_ptr.?[0..glyphs_cap];
    for (hello_runs, 0..) |r, i| {
        const src_bytes = std.mem.asBytes(&r);
        const dst = runs_base + i * runs_stride;
        @memcpy(dst[0..crun_v1_len], src_bytes[0..crun_v1_len]);
        if (runs_stride >= crun_xscale_end) {
            @memcpy(dst[crun_xscale_off..crun_xscale_end], src_bytes[crun_xscale_off..crun_xscale_end]);
        }
        if (runs_stride >= crun_color_end) {
            @memcpy(dst[crun_color_off..crun_color_end], src_bytes[crun_color_off..crun_color_end]);
        }
    }
    @memcpy(rules_z[0..need_rules], hello_rules[0..]);
    @memcpy(glyphs[0..need_glyphs], hello_glyphs[0..]);
    out.* = .{
        .width = hello_width,
        .height_above = hello_above,
        .depth_below = hello_below,
        .nruns = need_runs,
        .nrules = need_rules,
        .status = STATUS_OK,
        .err_offset = 0,
        .err_msg = null,
        .err_msg_len = 0,
    };
    return STATUS_OK;
}

export fn zatex_layout_utf8(
    src_ptr: ?[*]const u8,
    src_len: usize,
    display_mode: bool,
    metrics: ?*const CMetrics,
    runs_ptr: ?*anyopaque,
    runs_cap: usize,
    rules_ptr: ?[*]CRule,
    rules_cap: usize,
    glyphs_ptr: ?[*]u16,
    glyphs_cap: usize,
    out_ptr: ?*CLayout,
) i32 {
    _ = display_mode; // scripted: display/text layout is identical.
    return layoutImpl(src_ptr, src_len, metrics, runs_ptr, runs_cap, crun_v1_len, rules_ptr, rules_cap, glyphs_ptr, glyphs_cap, out_ptr);
}

export fn zatex_layout_utf8_ex(
    src_ptr: ?[*]const u8,
    src_len: usize,
    display_mode: bool,
    metrics: ?*const CMetrics,
    runs_ptr: ?*anyopaque,
    runs_cap: usize,
    runs_stride: usize,
    rules_ptr: ?[*]CRule,
    rules_cap: usize,
    glyphs_ptr: ?[*]u16,
    glyphs_cap: usize,
    out_ptr: ?*CLayout,
) i32 {
    _ = display_mode;
    return layoutImpl(src_ptr, src_len, metrics, runs_ptr, runs_cap, runs_stride, rules_ptr, rules_cap, glyphs_ptr, glyphs_cap, out_ptr);
}

export fn zatex_capabilities() u32 {
    return CAP_X_SCALE | CAP_RUN_COLOR | CAP_NEED_COUNTS;
}

export fn zatex_version() u32 {
    // Pinned to the current `contract.version` 0.0.0: hosts require
    // an exact pre-1.0 match, and the double reports the source it
    // was cut from. Bump with `contract.version`.
    return (@as(u32, 0) << 16) | (@as(u32, 0) << 8) | 0;
}

export fn zatex_conform_metrics(metrics: ?*const CMetrics, font: u16, buf_ptr: ?[*]u8, buf_cap: usize) i32 {
    _ = metrics orelse return -1;
    // Scripted: font 0 is the clean pass; any other font carries one
    // diagnostic so hosts exercise the nonzero path too.
    if (font == 0) return 0;
    if (buf_ptr) |bp| {
        if (buf_cap == 0) return -1;
        const out = bp[0..buf_cap];
        const take = @min(conform_diag.len, buf_cap - 1);
        @memcpy(out[0..take], conform_diag[0..take]);
        out[take] = 0;
    }
    return 1;
}

// ---- `zig build test` coverage: every scripted path ----

const td_metrics: CMetrics = .{ .ctx = null, .glyph_id = null, .advance = null, .rule_thickness = null };

test "test-double stub matches the frozen ABI shapes" {
    // The double re-declares the ABI (it must not import the engine,
    // or it stops being a standalone stub): pin every size/offset the
    // stride contract and hosts rely on.
    comptime {
        std.debug.assert(@sizeOf(CRunV1) == 20);
        std.debug.assert(@sizeOf(CRun) == 28);
        std.debug.assert(@offsetOf(CRun, "x_scale") == 20);
        std.debug.assert(@offsetOf(CRun, "color") == 24);
        std.debug.assert(@sizeOf(CRule) == 16);
        std.debug.assert(crun_v1_len == 20);
        std.debug.assert(crun_xscale_off == 20 and crun_xscale_end == 22);
        std.debug.assert(crun_color_off == 24 and crun_color_end == 28);
    }
}

test "test-double hello formula lays out fixed runs/rules" {
    var runs: [8]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var out: CLayout = undefined;
    const st = zatex_layout_utf8_ex(script_hello.ptr, script_hello.len, false, &td_metrics, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_OK, st);
    try std.testing.expectEqual(STATUS_OK, out.status);
    try std.testing.expectEqual(hello_width, out.width);
    try std.testing.expectEqual(hello_above, out.height_above);
    try std.testing.expectEqual(hello_below, out.depth_below);
    try std.testing.expectEqual(@as(u32, 3), out.nruns);
    try std.testing.expectEqual(@as(u32, 1), out.nrules);
    try std.testing.expectEqualSlices(u16, &hello_glyphs, glyphs[0..hello_glyphs.len]);
    // Tails are observable through `_ex`: the stretch and the paint.
    try std.testing.expectEqual(@as(u16, 2000), runs[1].x_scale);
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), runs[2].color);
    try std.testing.expectEqual(hello_rules[0].x, rules[0].x);
    try std.testing.expectEqual(hello_rules[0].w, rules[0].w);
    // Glyph index ranges land inside the caller buffer.
    for (runs[0..out.nruns]) |r| {
        try std.testing.expect(r.glyph_start + r.glyph_count <= hello_glyphs.len);
    }
}

test "test-double v1 entry delivers heads only" {
    var ref_runs: [8]CRun = undefined;
    var ref_rules: [4]CRule = undefined;
    var ref_glyphs: [16]u16 = undefined;
    var ref_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(script_hello.ptr, script_hello.len, false, &td_metrics, &ref_runs, ref_runs.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
    var raw: [8 * crun_v1_len]u8 = undefined;
    @memset(&raw, 0xAA);
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(script_hello.ptr, script_hello.len, false, &td_metrics, &raw, 8, &rules, rules.len, &glyphs, glyphs.len, &out));
    try std.testing.expectEqual(ref_out.nruns, out.nruns);
    for (0..out.nruns) |i| {
        var s: CRunV1 = undefined;
        @memcpy(std.mem.asBytes(&s), raw[i * crun_v1_len ..][0..crun_v1_len]);
        try std.testing.expectEqual(ref_runs[i].font_id, s.font_id);
        try std.testing.expectEqual(ref_runs[i].x, s.x);
        try std.testing.expectEqual(ref_runs[i].glyph_start, s.glyph_start);
        try std.testing.expectEqual(ref_runs[i].glyph_count, s.glyph_count);
    }
}

test "test-double forced no_space carries needs, buffers untouched" {
    var runs: [8]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    @memset(std.mem.asBytes(&runs), 0xAA);
    @memset(std.mem.asBytes(&rules), 0xAA);
    @memset(std.mem.asBytes(&glyphs), 0xAA);
    const runs_snap = runs;
    const rules_snap = rules;
    const glyphs_snap = glyphs;
    var out: CLayout = undefined;
    const st = zatex_layout_utf8_ex(script_nospace.ptr, script_nospace.len, false, &td_metrics, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_NO_SPACE, st);
    try std.testing.expectEqual(STATUS_NO_SPACE, out.status);
    try std.testing.expectEqual(nospace_runs, out.nruns);
    try std.testing.expectEqual(nospace_rules, out.nrules);
    try std.testing.expect(out.nruns > 0 and out.nrules > 0);
    try std.testing.expectEqual(runs_snap, runs);
    try std.testing.expectEqual(rules_snap, rules);
    try std.testing.expectEqual(glyphs_snap, glyphs);
}

test "test-double forced limit carries over-ceiling needs" {
    var runs: [8]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var out: CLayout = undefined;
    const st = zatex_layout_utf8_ex(script_limit.ptr, script_limit.len, false, &td_metrics, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_LIMIT, st);
    try std.testing.expectEqual(STATUS_LIMIT, out.status);
    // Over the 256-run / 64-rule engine ceilings: even maximum
    // buffers cannot succeed, so the host must fail with a message.
    try std.testing.expect(out.nruns > 256);
    try std.testing.expect(out.nrules > 64);
}

test "test-double forced bad input carries err_offset and message" {
    var runs: [8]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var out: CLayout = undefined;
    const st = zatex_layout_utf8_ex(script_bad.ptr, script_bad.len, false, &td_metrics, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_INVALID, st);
    try std.testing.expectEqual(STATUS_INVALID, out.status);
    try std.testing.expectEqual(@as(u32, 5), out.err_offset);
    try std.testing.expect(out.err_msg_len > 0);
    const msg = out.err_msg.?[0..out.err_msg_len];
    try std.testing.expectEqualSlices(u8, msg_bad, msg);
}

test "test-double unknown input is invalid, short buffers report needs" {
    var runs: [8]CRun = undefined;
    var rules: [4]CRule = undefined;
    var glyphs: [16]u16 = undefined;
    var out: CLayout = undefined;
    const src = "x+y";
    try std.testing.expectEqual(STATUS_INVALID, zatex_layout_utf8_ex(src.ptr, src.len, false, &td_metrics, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
    try std.testing.expect(out.err_msg_len > 0);
    // The OK script with no room: NO_SPACE with the exact needs.
    var tiny_runs: [1]CRun = undefined;
    var out2: CLayout = undefined;
    const st2 = zatex_layout_utf8_ex(script_hello.ptr, script_hello.len, false, &td_metrics, &tiny_runs, tiny_runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out2);
    try std.testing.expectEqual(STATUS_NO_SPACE, st2);
    try std.testing.expectEqual(@as(u32, 3), out2.nruns);
    try std.testing.expectEqual(@as(u32, 1), out2.nrules);
    // Null buffers are a sizing probe: NO_SPACE with the needs.
    var out3: CLayout = undefined;
    const st3 = zatex_layout_utf8_ex(script_hello.ptr, script_hello.len, false, &td_metrics, null, 0, @sizeOf(CRun), null, 0, null, 0, &out3);
    try std.testing.expectEqual(STATUS_NO_SPACE, st3);
    try std.testing.expectEqual(@as(u32, 3), out3.nruns);
    // Strides below 20 fail LIMIT without touching the runs buffer.
    var raw: [8 * crun_v1_len]u8 = undefined;
    @memset(&raw, 0xAA);
    var out4: CLayout = undefined;
    const st4 = zatex_layout_utf8_ex(script_hello.ptr, script_hello.len, false, &td_metrics, &raw, 8, 19, &rules, rules.len, &glyphs, glyphs.len, &out4);
    try std.testing.expectEqual(STATUS_LIMIT, st4);
    for (raw) |b| try std.testing.expectEqual(@as(u8, 0xAA), b);
}

test "test-double capabilities, version, and conform scripts" {
    try std.testing.expectEqual(CAP_X_SCALE | CAP_RUN_COLOR | CAP_NEED_COUNTS, zatex_capabilities());
    try std.testing.expectEqual(@as(u32, 0), zatex_version());
    var buf: [256]u8 = undefined;
    try std.testing.expectEqual(@as(i32, 0), zatex_conform_metrics(&td_metrics, 0, &buf, buf.len));
    try std.testing.expectEqual(@as(i32, 1), zatex_conform_metrics(&td_metrics, 1, &buf, buf.len));
    try std.testing.expectEqualSlices(u8, conform_diag, buf[0..conform_diag.len]);
    try std.testing.expectEqual(@as(i32, -1), zatex_conform_metrics(null, 0, &buf, buf.len));
}
