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

/// One laid-out glyph run. Must match `zatex.h` `zatex_run_t`
/// field-for-field. The first 20 bytes are the frozen v1 prefix
/// (`CRunV1`): field offsets never move, and `x_scale` (issue #197)
/// then `color` (issue #251) append at the tail.
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
    ///
    /// Rounding contract (issue #272, decided: u16 per-mille kept —
    /// float would only re-encode the truncated ratio with binary
    /// error, and the core stays integer-only per AGENTS.md). The
    /// engine computes `@divTrunc(span * 1000, nat)` — truncation
    /// toward zero (floor on the positive domain), clamped to u16
    /// (stretch-only paths keep 1000 unless the span exceeds the
    /// natural width; fitting paths floor at 1). Hosts apply the same
    /// truncation to pen advances
    /// (`@divTrunc(step * x_scale, 1000)`, as zatex-png render.zig
    /// does) and `x_scale / 1000.0` in double for raster scale.
    ///
    /// Array-stride warning (issue #203): appending changes
    /// `@sizeOf(CRun)`, so a new dylib striding wider than an old
    /// host's slots would scramble every run past the first. This
    /// field is therefore written only when the host's run stride
    /// admits it — see `zatex_layout_utf8_ex`. The v1 entry
    /// (`zatex_layout_utf8`) never writes it.
    x_scale: u16 = 1000,
    /// Per-run paint in 0xRRGGBBAA (`\color` scope, issue #35, projected
    /// through this surface by issue #251); 0 is the ambient (host
    /// default) paint and matches `ir.Run.color == 0` exactly —
    /// resolved paints always carry opaque alpha, so 0 is unambiguous.
    /// Must match `zatex.h` `zatex_run_t.color`. Same stride rule as
    /// `x_scale`: written only when the host stride reaches past it
    /// (bytes 24..28), so 24-stride hosts stay bit-identical.
    color: u32 = 0,
};

/// Frozen v1 run prefix (issue #203): the 20-byte head every host
/// understands, field-for-field identical to the head of `CRun`.
/// Must match `zatex.h` `zatex_run_v1_t` field-for-field. The v1
/// layout entry fills arrays of exactly this shape; the `_ex` entry
/// strides by the host's own element size and writes the fields that
/// fit, so old-sized readers stay safe across dylib updates.
pub const CRunV1 = extern struct {
    font_id: u16,
    size_units: u16,
    x: i32,
    baseline_y: i32,
    glyph_start: u32,
    glyph_count: u32,
};

/// Byte length of the frozen v1 prefix (`@sizeOf(CRunV1)`): the
/// minimum run stride the engine accepts.
pub const crun_v1_len: usize = 20;
/// Offset of `x_scale` within `CRun` (`@offsetOf(CRun, "x_scale")`).
pub const crun_xscale_off: usize = 20;
/// First byte past `x_scale`: the engine writes it only when the
/// host stride reaches this far. Wider strides leave every remaining
/// tail byte (including struct padding at 22..24) untouched.
pub const crun_xscale_end: usize = 22;
/// Offset of `color` within `CRun` (`@offsetOf(CRun, "color")`): the
/// 2-byte pad at 22..24 keeps the u32 4-aligned, so the paint lands
/// at 24, not 22.
pub const crun_color_off: usize = 24;
/// First byte past `color`: the engine writes bytes 24..28 only when
/// the host stride reaches this far (issue #251). Strides in
/// 22..28 carry `x_scale` without paint, exactly like the old
/// 24-byte struct did — old hosts stay bit-identical.
pub const crun_color_end: usize = 28;

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
    /// Typed failure code (issue #273): refines `status` (`ERR_*`
    /// below) so hosts branch without parsing `err_msg`. Zero on
    /// success. Appended, never reordered — old readers ignore the
    /// tail, same rule as `err_msg`. Hosts pairing with a dylib that
    /// predates `CAP_ERR_CODE` must zero-initialize this struct: an
    /// old dylib never writes this field.
    err_code: i32 = 0,
};

pub const STATUS_OK: i32 = 0;
pub const STATUS_UNSUPPORTED: i32 = 1;
pub const STATUS_INVALID: i32 = 2;
pub const STATUS_TOO_DEEP: i32 = 3;
pub const STATUS_TOO_LONG: i32 = 4;
pub const STATUS_EXPANSION_LIMIT: i32 = 5;
pub const STATUS_NO_SPACE: i32 = 6;
pub const STATUS_LIMIT: i32 = 7;

/// Typed failure codes for `CLayout.err_code` (issue #273): each refines
/// one `STATUS_*` bucket so hosts branch on the retry policy without
/// parsing `err_msg`. Values are added, never renumbered. Must match
/// `zatex.h` `ZATEX_ERR_*` one-for-one.
///
/// The three space codes compose with the need-counts (issue #263):
/// `ERR_OVERFLOW_RUNS/RULES/GLYPHS` always carry the exact needs in
/// `nruns`/`nrules` (retry once, grown); `ERR_NO_SPACE` carries zeroed
/// counts (even maximum buffers cannot succeed — fail with a message).
pub const ERR_OK: i32 = 0;
/// Malformed input, KaTeX ParseError parity (`error.Invalid`).
/// Status 2.
pub const ERR_BAD_TEX: i32 = 1;
/// Outside engine scope, caller falls back (`error.Unsupported`,
/// reserved — the core never emits it today). Status 1.
pub const ERR_UNSUPPORTED_CMD: i32 = 2;
/// Nesting depth exceeded (`error.TooDeep`). Status 3.
pub const ERR_TOO_DEEP: i32 = 3;
/// Input exceeds 65536 bytes (`error.TooLong`). Status 4.
pub const ERR_OVERFLOW_INPUT: i32 = 4;
/// Macro expansion budget exceeded (`error.ExpansionLimit`). Status 5.
pub const ERR_EXPANSION_LIMIT: i32 = 5;
/// Caller runs buffer short (or a null-runs probe): need in `nruns`.
/// Status 6, retryable.
pub const ERR_OVERFLOW_RUNS: i32 = 6;
/// Caller rules buffer short (or a null-rules probe): need in `nrules`.
/// Status 6, retryable.
pub const ERR_OVERFLOW_RULES: i32 = 7;
/// Caller glyph buffer short (or a null-glyphs probe; glyph needs have
/// no field — grow and retry). Status 6, retryable.
pub const ERR_OVERFLOW_GLYPHS: i32 = 8;
/// Fixed engine pools exceeded at ceiling size (`error.NoSpace` from
/// layout): zeroed needs, unretryable. Status 6.
pub const ERR_NO_SPACE: i32 = 9;
/// Request exceeds engine ceilings (over-ceiling caps, short stride):
/// fix the request shape, not the buffers. Status 7.
pub const ERR_LIMIT: i32 = 10;

/// Run tail fields (issue #271): the ONE write mechanism behind every
/// layout entry, superseding the per-field stride pattern from
/// #197/#203/#251. Each row is one complete tail field the engine
/// writes iff the host stride reaches past it; bytes covered by no row
/// (struct padding at 22..24, unknown future tails) are never written,
/// so old-sized readers stay bit-identical and wider strides keep
/// working. The v1 entry strides 20 (prefix only, never the tails);
/// `_ex` strides the host's own element size. Future tails append rows
/// here — never new branches at the call sites below.
const run_tail_fields = [_]struct { off: usize, end: usize }{
    .{ .off = crun_xscale_off, .end = crun_xscale_end }, // x_scale (#197)
    .{ .off = crun_color_off, .end = crun_color_end }, // color (#251)
};

/// Strided, alignment-safe run store: the frozen v1 prefix plus each
/// tail field the host stride admits (`writeRun` is the only place
/// that touches caller run memory). Hosts pass their own element size
/// as `stride` (issue #203); the field table decides what lands.
/// Inlined: the single call site unrolls to the old straight-line
/// stores, so the table costs no code size over the branches it
/// replaced (issue #271 keeps the ReleaseSmall budget, issue 12).
inline fn writeRun(dst: [*]u8, stride: usize, src: *const CRun) void {
    const src_bytes = std.mem.asBytes(src);
    @memcpy(dst[0..crun_v1_len], src_bytes[0..crun_v1_len]);
    for (run_tail_fields) |f| {
        if (stride >= f.end) {
            @memcpy(dst[f.off..f.end], src_bytes[f.off..f.end]);
        }
    }
}

/// Capability bits for `zatex_capabilities` (issue #262): one
/// `dlsym`-free word negotiated once, so hosts branch on bits instead
/// of accreting per-symbol probes (`_ex` for `x_scale` today, a color
/// tail tomorrow). Bits are additive — new extensions set new bits,
/// never move these. A dylib predating the query (dlsym NULL) is the
/// v1 surface: frozen prefix only, zeroed counts on space failures.
pub const CAP_X_SCALE: u32 = 1 << 0;
pub const CAP_RUN_COLOR: u32 = 1 << 1;
pub const CAP_NEED_COUNTS: u32 = 1 << 2;
pub const CAP_ERR_CODE: u32 = 1 << 3;

/// Coarse `status` plus fine `err_code` for one `LayoutError`.
const StatusCode = struct { status: i32, code: i32 };

/// `LayoutError` to `StatusCode` (issue #273): one switch behind every
/// failing store, so the coarse bucket and the fine code can never
/// drift apart. Space-pool exhaustion maps to `ERR_NO_SPACE`
/// (unretryable); caller-buffer shorts never reach here — the impl
/// assigns `ERR_OVERFLOW_*` at the needs-carrying store instead.
fn toStatusCode(e: zatex.LayoutError) StatusCode {
    return switch (e) {
        error.Unsupported => .{ .status = STATUS_UNSUPPORTED, .code = ERR_UNSUPPORTED_CMD },
        error.Invalid => .{ .status = STATUS_INVALID, .code = ERR_BAD_TEX },
        error.TooDeep => .{ .status = STATUS_TOO_DEEP, .code = ERR_TOO_DEEP },
        error.TooLong => .{ .status = STATUS_TOO_LONG, .code = ERR_OVERFLOW_INPUT },
        error.ExpansionLimit => .{ .status = STATUS_EXPANSION_LIMIT, .code = ERR_EXPANSION_LIMIT },
        error.NoSpace => .{ .status = STATUS_NO_SPACE, .code = ERR_NO_SPACE },
        error.OutOfMemory => .{ .status = STATUS_NO_SPACE, .code = ERR_NO_SPACE },
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

/// Shared layout implementation behind both C entries. `runs_ptr`
/// points at `runs_cap` array elements each `runs_stride` bytes wide
/// (the host's own element size); see the stride contract on
/// `zatex_layout_utf8_ex`.
///
/// Space-failure contract (issue #263): layout completes into
/// ceiling-size stack temporaries before caller buffers are touched,
/// so a layable formula's exact host-visible needs are always known —
/// `STATUS_NO_SPACE`/`STATUS_LIMIT` carry them in
/// `out.nruns`/`out.nrules` and hosts allocate exactly once. Zeroed
/// counts mean the need exceeds engine capacity (even maximum buffers
/// cannot succeed) or the call never reached layout (null
/// metrics/source). All other failures keep today's shapes (zeroed
/// counts, `err_*` diagnostics).
fn layoutUtf8Impl(
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
        // Generic until the failing store refines it below (issue
        // #273): null metrics/source never reach layout, so the zeroed
        // shape keeps this code.
        .err_code = ERR_NO_SPACE,
    };
    const m = metrics orelse return STATUS_NO_SPACE;
    if (src_len > zatex.max_input_len) {
        out.status = STATUS_TOO_LONG;
        out.err_code = ERR_OVERFLOW_INPUT;
        return out.status;
    }
    const src = (src_ptr orelse return STATUS_NO_SPACE)[0..src_len];
    const host = Host{ .m = m };
    const prov = hostProvider(m, &host);
    // Scratch overlay (zero heap): layout completes into ceiling-size
    // stack temporaries before caller buffers are touched, so a
    // layable formula's exact needs are always known with one pass —
    // no retry, no partial writes (issue #263). Glyphs land in
    // `glyph_tmp` (at most one per glyph box, far below its length)
    // and copy to the caller buffer on success.
    var runs_tmp: [256]zatex.ir.Run = undefined;
    var rules_tmp: [64]zatex.ir.Rule = undefined;
    // Energy (issue #287): one glyph per glyph box, so the need is
    // bounded by `max_boxes` (448) — 1024 keeps 2x headroom over the
    // old 2048. The runs/rules temps stay: they are the C-visible run
    // ceiling (256) and rule ceiling (64), i.e. behavior caps, and the
    // double-buffer itself is the #263 no-partial-writes contract
    // (needs are only known after a full layout, so translating
    // directly into caller slices could not report them honestly).
    var glyph_tmp: [1024]u16 = undefined;
    var diag = zatex.Diag.empty();
    const l = zatex.layoutInner(src, .{ .display_mode = display_mode }, prov, &runs_tmp, &rules_tmp, &glyph_tmp, &diag) catch |e| {
        // Malformed input reports its true error even on a probe or an
        // over-ceiling request (more informative than the historical
        // shape status, which only wins for layable formulas below).
        const sc = toStatusCode(e);
        out.status = sc.status;
        out.err_code = sc.code;
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
        // A NoSpace here needs past the ceilings/pools: even maximum
        // buffers cannot succeed, so the zeroed counts above already
        // say "exceeds capacity" — nothing to measure.
        return out.status;
    };
    // Space failures carry the needs (issue #263) through one shared
    // store: a null-buffer probe reports NO_SPACE even when the caps
    // are also over ceiling (the historical precedence). Caller
    // buffers stay untouched, same as the old ceilings check.
    //
    // Fused translate (issue #289): the run loop below pre-checks the
    // only counter it needs up front (run count, free — `l.runs.len`),
    // writes runs, and accumulates the glyph total in the same pass;
    // the rect copy counts `diag`-skips as it copies; the glyph commit
    // checks its cap last. Needs therefore cross without a separate
    // `need_rules` recount or `need_glyphs` sum on the success path:
    // the only extra walks are on failure arms (already-failing calls
    // measuring exact needs for the retry), where they cost nothing
    // observable. The ceiling pre-check (caps at or under the temps,
    // stride at or over the v1 prefix) keeps the no-partial-write
    // contract on the fast path: every buffer provably fits before the
    // first caller byte lands. Failure arms may leave a prefix in
    // caller buffers — the status is NO_SPACE/LIMIT with exact needs
    // and hosts retry with grown buffers (the #263 contract names
    // counts, not contents, on failure).
    const need_runs: u32 = @intCast(l.runs.len);
    const probe = runs_ptr == null or rules_ptr == null or glyphs_ptr == null;
    if (probe or need_runs > runs_cap or runs_cap > runs_tmp.len or rules_cap > rules_tmp.len or runs_stride < crun_v1_len) {
        // Glyph and rect needs still cross (measured cheaply below:
        // the glyph sum is one pass over run headers, the rect scan
        // skips only `diag` strikes exactly as the copy would).
        var need_glyphs: usize = 0;
        for (l.runs) |r| need_glyphs += r.glyphs.len;
        var need_rules: u32 = 0;
        for (l.rules) |r| {
            if (r.diag != .none) continue;
            need_rules += 1;
        }
        const short = probe or need_runs > runs_cap or need_rules > rules_cap or need_glyphs > glyphs_cap;
        // A null-buffer probe reports NO_SPACE even when the caps are
        // also over ceiling (the historical precedence).
        out.status = if (probe or short) STATUS_NO_SPACE else STATUS_LIMIT;
        out.err_offset = 0;
        out.nruns = need_runs;
        out.nrules = need_rules;
        if (probe or short) {
            // Retryable caller-buffer overflow (issue #273 refines the
            // status with the need-counts from #263): name the first
            // short buffer in runs/rules/glyphs priority. A
            // null-buffer probe names its first null the same way, so
            // hosts grow exactly one buffer per retry. One of the two
            // arms always fires here — `probe or short` guarantees it.
            const runs_short = runs_ptr == null or need_runs > runs_cap;
            const rules_short = rules_ptr == null or need_rules > rules_cap;
            out.err_code = if (runs_short)
                ERR_OVERFLOW_RUNS
            else if (rules_short)
                ERR_OVERFLOW_RULES
            else
                ERR_OVERFLOW_GLYPHS;
        } else {
            // Over-ceiling caps or a short stride: the request shape,
            // not the buffers. The needs still cross (measured above
            // into ceiling temps) for the corrected retry.
            out.err_code = ERR_LIMIT;
        }
        return out.status;
    }
    // Reinterpret caller buffers as Zig slices. Runs arrive as an
    // opaque base: the host's element size (`runs_stride`) is the
    // only stride the engine ever uses (issue #203), so old-sized
    // slots stay aligned no matter what the current `CRun` holds.
    const runs_base: [*]u8 = @ptrCast(runs_ptr.?);
    const rules_z = rules_ptr.?[0..rules_cap];
    const glyphs = glyphs_ptr.?[0..glyphs_cap];
    // Energy (#155): glyph slices emit run-sequentially into the temp,
    // so `glyph_start` is a running cursor — no per-run pointer
    // subtraction. Debug builds assert contiguity against the old
    // difference on every run.
    var ng: u32 = 0;
    for (l.runs, 0..) |r, i| {
        // Active in test/Debug builds; compiled out of ReleaseSmall.
        const start = (@intFromPtr(r.glyphs.ptr) - @intFromPtr(&glyph_tmp[0])) / 2;
        std.debug.assert(start == ng);
        const v: CRun = .{
            .font_id = r.font_id,
            .size_units = r.size_units,
            .x = r.x,
            .baseline_y = r.baseline_y,
            .glyph_start = ng,
            .glyph_count = @intCast(r.glyphs.len),
            // Stretch factor (issue #197): without it C hosts draw
            // wide accents at natural size, off-span.
            .x_scale = r.x_scale,
            // Paint (issue #251): 0 is ambient (`ir.Run.color == 0`),
            // so unstylized formulas cross exactly as before.
            .color = r.color,
        };
        // One mechanism (issue #271): the field table decides what
        // lands — no per-field branches here.
        const off = std.math.mul(usize, i, runs_stride) catch {
            // Absurd strides only (caps and the run count were
            // pre-checked): same LIMIT shape with the rect-projected
            // need (the glyph sum is `ng` plus the unwritten tail —
            // folded into the single loop below, not needed here since
            // no glyph need crosses on LIMIT).
            var need_rules: u32 = 0;
            for (l.rules) |rr| {
                if (rr.diag != .none) continue;
                need_rules += 1;
            }
            out.status = STATUS_LIMIT;
            out.err_code = ERR_LIMIT;
            out.err_offset = 0;
            out.nruns = need_runs;
            out.nrules = need_rules;
            return out.status;
        };
        writeRun(runs_base + off, runs_stride, &v);
        ng += @intCast(r.glyphs.len);
        // Fused need-count (issue #289): the glyph total accumulates
        // here, in the same pass that writes the runs — no separate
        // `need_glyphs` sum loop.
        std.debug.assert(ng <= glyph_tmp.len);
    }
    // The frozen narrow surface projects filled rects only: diagonal
    // strikes (issue #107 `Rule.diag`) have no rect form, so they are
    // skipped rather than misdrawn. (Run paint does cross — see `CRun.color`
    // — but rects carry no paint on this surface: `\colorbox` bodies
    // keep their run colors while the background rect stays ambient.)
    // Fused translate (issue #289): the rules copy checks the caller
    // cap incrementally and the glyph commit checks its cap — the
    // ceiling pre-check above plus these two in-loop checks keep the
    // no-partial-write contract with no separate need-count pass. On
    // overflow the caller buffers may hold a prefix, but the status is
    // NO_SPACE with exact needs and hosts must retry with grown
    // buffers (the #263 contract: counts, not contents, cross on
    // failure) — and the success path below only commits when every
    // check passed.
    var nrules: u32 = 0;
    for (l.rules) |r| {
        if (r.diag != .none) continue;
        if (nrules >= rules_cap) {
            // Exact rect need for the retry (the glyph need is the
            // `ng` cursor plus the unwritten tail — but the rules
            // arm names RULES, so only the rect need crosses, exactly
            // as the old shared store did).
            var need_rules: u32 = 0;
            for (l.rules) |rr| {
                if (rr.diag != .none) continue;
                need_rules += 1;
            }
            out.status = STATUS_NO_SPACE;
            out.err_code = ERR_OVERFLOW_RULES;
            out.err_offset = 0;
            out.nruns = need_runs;
            out.nrules = need_rules;
            return out.status;
        }
        rules_z[nrules] = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        nrules += 1;
    }
    // Backing glyphs: the run loop proved `ng` glyphs; commit only
    // when the caller buffer fits, otherwise NO_SPACE with exact
    // needs (same shape as the rules-short arm above).
    if (ng > glyphs_cap) {
        out.status = STATUS_NO_SPACE;
        out.err_code = ERR_OVERFLOW_GLYPHS;
        out.err_offset = 0;
        out.nruns = need_runs;
        out.nrules = nrules;
        return out.status;
    }
    @memcpy(glyphs[0..ng], glyph_tmp[0..ng]);
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
        .err_code = ERR_OK,
    };
    return STATUS_OK;
}

/// Frozen v1 layout entry: lay out one UTF-8 formula into
/// caller-owned buffers. `src_len` is capped at `max_input_len`;
/// output counts are capped by the buffer lengths (`STATUS_NO_SPACE`
/// on overflow).
///
/// `runs` is an array of `runs_cap` 20-byte v1 slots (`zatex.h`
/// `zatex_run_v1_t`, Zig `CRunV1`). The engine strides 20 and writes
/// the v1 prefix only — never `x_scale`, never `color` — so hosts
/// compiled against the old struct stay bit-identical across dylib
/// updates: they draw unstretched in the ambient paint, exactly as
/// before (issue #203). Hosts compiled against the 28-byte
/// `zatex_run_t` call `zatex_layout_utf8_ex`.
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
    return layoutUtf8Impl(src_ptr, src_len, display_mode, metrics, runs_ptr, runs_cap, crun_v1_len, rules_ptr, rules_cap, glyphs_ptr, glyphs_cap, out_ptr);
}

/// Stride-negotiated layout entry (issue #203): identical to
/// `zatex_layout_utf8`, except `runs` elements are `runs_stride`
/// bytes wide — pass `sizeof` the host's run struct
/// (`sizeof(zatex_run_t)`, 28 today).
///
/// Stride contract: the engine writes the frozen v1 prefix (bytes
/// 0..20) into every element, `x_scale` (bytes 20..22) only when
/// `runs_stride >= 22`, and `color` (bytes 24..28) only when
/// `runs_stride >= 28`; every other tail byte (including struct
/// padding at 22..24) is left untouched. Strides below 20 fail with
/// `STATUS_LIMIT` without touching the runs buffer. A future wider
/// host struct keeps working: the engine never writes past its known
/// 28 bytes, and never strides wider than the host's own size.
///
/// Pairing: hosts wanting `x_scale`/`color` need a dylib exporting
/// this entry — `dlsym` it and fall back to `zatex_layout_utf8` when
/// absent (old dylib), drawing unstretched in the ambient paint — or
/// negotiate once via `zatex_capabilities` (issue #262) and branch on
/// `CAP_X_SCALE`/`CAP_RUN_COLOR`. The v1 entry is safe with any
/// dylib/host mix.
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
    return layoutUtf8Impl(src_ptr, src_len, display_mode, metrics, runs_ptr, runs_cap, runs_stride, rules_ptr, rules_cap, glyphs_ptr, glyphs_cap, out_ptr);
}

/// Capability word (issue #262): bitmask of `CAP_*` bits negotiated
/// once, so hosts branch on capability bits instead of per-symbol
/// `dlsym` probing. The `_ex` pairing keeps working (a present `_ex`
/// implies `CAP_X_SCALE`, a 28-stride paint implies `CAP_RUN_COLOR`),
/// but new extensions stop multiplying loader paths: probe this one
/// symbol, fall back to the v1 surface when absent (old dylib).
/// `CAP_ERR_CODE` (issue #273) guards `CLayout.err_code`: a dylib
/// predating it never writes the field, so hosts zero-initialize the
/// layout struct and only read the code when the bit is set.
export fn zatex_capabilities() u32 {
    return CAP_X_SCALE | CAP_RUN_COLOR | CAP_NEED_COUNTS | CAP_ERR_CODE;
}

/// Packed semantic version, ABI-stable (issue #276): `major << 16 |
/// minor << 8 | patch` with normative widths major 16 bits, minor 8
/// bits, patch 8 bits (`contract.version` comptime-asserts minor and
/// patch below 256 so fields never bleed; major below 65536).
/// Pre-1.0 hosts require an exact match, not a range. This word is
/// the library version only — `provider_version` (`MetricsProvider`
/// hooks) is a separate contract and never rides here.
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

test "cabi rule_thickness kind values match zatex.h docs (issue #205)" {
    // The documented C ABI table, one line per value in zatex.h. The
    // bridge passes @intFromEnum(kind), so declaration order IS the
    // ABI — pin it against the Zig side drifting.
    try std.testing.expectEqual(0, @intFromEnum(zatex.RuleKind.fraction_bar));
    try std.testing.expectEqual(1, @intFromEnum(zatex.RuleKind.radical));
    try std.testing.expectEqual(2, @intFromEnum(zatex.RuleKind.overline));
    try std.testing.expectEqual(3, @intFromEnum(zatex.RuleKind.underline));
    // End to end: the u32 each construct's rule carries over the C
    // bridge is the documented row.
    const S = struct {
        var seen: ?u32 = null;
        fn gid(_: ?*const anyopaque, _: u16, cp: u32) callconv(.c) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: ?*const anyopaque, _: u16, _: u16) callconv(.c) i32 {
            return 500;
        }
        fn rt(_: ?*const anyopaque, _: u16, kind: u32) callconv(.c) i32 {
            seen = kind;
            return 40;
        }
    };
    const m: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt };
    const cases = [_]struct { tex: []const u8, want: u32 }{
        .{ .tex = "\\frac12", .want = 0 },
        .{ .tex = "\\sqrt{x}", .want = 1 },
        .{ .tex = "\\overline{x}", .want = 2 },
        // KaTeX parity: \underline reuses the overline weight
        // (layoutOver queries .overline for both), so the core
        // never emits kind 3 today — .underline stays reserved.
        .{ .tex = "\\underline{x}", .want = 2 },
    };
    for (cases) |c| {
        S.seen = null;
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        const st = zatex_layout_utf8(c.tex.ptr, c.tex.len, false, &m, &runs, runs.len, &rules, rules.len, &glyphs, glyphs.len, &out);
        try std.testing.expectEqual(STATUS_OK, st);
        try std.testing.expect(S.seen != null);
        try std.testing.expectEqual(c.want, S.seen.?);
    }
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
    const st = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
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
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m_null, &runs0, runs0.len, @sizeOf(CRun), &rules0, rules0.len, &glyphs0, glyphs0.len, &out0));
    try std.testing.expectEqual(@as(u32, 1), out0.nrules);
    const m_v4: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt, .extents = S.ext, .ink_bounds = S.ink };
    var runs1: [16]CRun = undefined;
    var rules1: [4]CRule = undefined;
    var glyphs1: [64]u16 = undefined;
    var out1: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m_v4, &runs1, runs1.len, @sizeOf(CRun), &rules1, rules1.len, &glyphs1, glyphs1.len, &out1));
    try std.testing.expectEqual(@as(u32, 1), out1.nrules);
    try std.testing.expect(rules1[0].x < rules0[0].x);
    try std.testing.expect(out1.height_above != out0.height_above);
}

test "cabi run layout is frozen v1 plus appended tails (issues #197, #251)" {
    // Frozen v1 prefix: field offsets never move. `x_scale` then
    // `color` append at the tail (same policy as `CLayout.err_msg`),
    // padding the struct to 28. Appending alone does NOT keep old
    // array readers safe (issue #203) — that is the stride contract's
    // job; this test pins the offsets both sides rely on.
    comptime {
        std.debug.assert(@offsetOf(CRun, "font_id") == 0);
        std.debug.assert(@offsetOf(CRun, "size_units") == 2);
        std.debug.assert(@offsetOf(CRun, "x") == 4);
        std.debug.assert(@offsetOf(CRun, "baseline_y") == 8);
        std.debug.assert(@offsetOf(CRun, "glyph_start") == 12);
        std.debug.assert(@offsetOf(CRun, "glyph_count") == 16);
        std.debug.assert(@offsetOf(CRun, "x_scale") == 20);
        std.debug.assert(@sizeOf(CRun) == 28);
        // The v1 prefix type is the head of `CRun`, 20 bytes flat.
        std.debug.assert(@sizeOf(CRunV1) == crun_v1_len);
        std.debug.assert(@offsetOf(CRunV1, "font_id") == @offsetOf(CRun, "font_id"));
        std.debug.assert(@offsetOf(CRunV1, "size_units") == @offsetOf(CRun, "size_units"));
        std.debug.assert(@offsetOf(CRunV1, "x") == @offsetOf(CRun, "x"));
        std.debug.assert(@offsetOf(CRunV1, "baseline_y") == @offsetOf(CRun, "baseline_y"));
        std.debug.assert(@offsetOf(CRunV1, "glyph_start") == @offsetOf(CRun, "glyph_start"));
        std.debug.assert(@offsetOf(CRunV1, "glyph_count") == @offsetOf(CRun, "glyph_count"));
        std.debug.assert(crun_xscale_off == @offsetOf(CRun, "x_scale"));
        std.debug.assert(crun_xscale_end == @offsetOf(CRun, "x_scale") + @sizeOf(u16));
        // Paint tail (issue #251): 2-byte pad at 22..24 keeps the u32
        // 4-aligned, so color lands at 24.
        std.debug.assert(crun_color_off == @offsetOf(CRun, "color"));
        std.debug.assert(crun_color_end == @offsetOf(CRun, "color") + @sizeOf(u32));
        // The rect surface is untouched by this change.
        std.debug.assert(@sizeOf(CRule) == 16);
    }
}

test "cabi v1 entry keeps old-sized readers safe (issue #203)" {
    // The issue's canary scenario: an old host owns 20-byte slots
    // filled with 0xAA and lays out `\sqrt{x}+\frac{a}{b}` (5 runs).
    // The v1 entry must fill every run past the first with the same
    // head the full-struct entry reports, write exactly 20 bytes per
    // run (the guard past the slots stays 0xAA), and never deliver
    // `x_scale` (drawn unstretched, exactly as before).
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
    const src = "\\sqrt{x}+\\frac{a}{b}";
    // Reference: full structs through `_ex`.
    var ref_runs: [16]CRun = undefined;
    var ref_rules: [8]CRule = undefined;
    var ref_glyphs: [64]u16 = undefined;
    var ref_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref_runs, ref_runs.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
    try std.testing.expect(ref_out.nruns > 1);
    // Old host: one flat buffer — 16 v1 slots plus a guard the
    // engine must never touch — through the v1 entry.
    var raw: [16 * crun_v1_len + 64]u8 = undefined;
    @memset(&raw, 0xAA);
    var rules: [8]CRule = undefined;
    var glyphs: [64]u16 = undefined;
    var out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(src.ptr, src.len, false, &m, &raw, 16, &rules, rules.len, &glyphs, glyphs.len, &out));
    try std.testing.expectEqual(ref_out.nruns, out.nruns);
    try std.testing.expectEqual(ref_out.width, out.width);
    try std.testing.expectEqual(ref_out.height_above, out.height_above);
    try std.testing.expectEqual(ref_out.depth_below, out.depth_below);
    var total: u32 = 0;
    for (0..out.nruns) |i| {
        var s: CRunV1 = undefined;
        @memcpy(std.mem.asBytes(&s), raw[i * crun_v1_len ..][0..crun_v1_len]);
        const r = ref_runs[i];
        try std.testing.expectEqual(r.font_id, s.font_id);
        try std.testing.expectEqual(r.size_units, s.size_units);
        try std.testing.expectEqual(r.x, s.x);
        try std.testing.expectEqual(r.baseline_y, s.baseline_y);
        try std.testing.expectEqual(r.glyph_start, s.glyph_start);
        try std.testing.expectEqual(r.glyph_count, s.glyph_count);
        total += s.glyph_count;
    }
    try std.testing.expectEqualSlices(u16, ref_glyphs[0..total], glyphs[0..total]);
    // Exactly 20 bytes per run: slots past `nruns` and the trailing
    // guard are still canary.
    for (raw[out.nruns * crun_v1_len ..]) |b| {
        try std.testing.expectEqual(@as(u8, 0xAA), b);
    }
    // `_ex` with the v1 stride is byte-identical to the v1 entry.
    var raw2: [16 * crun_v1_len + 64]u8 = undefined;
    @memset(&raw2, 0xAA);
    var out2: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &raw2, 16, crun_v1_len, &rules, rules.len, &glyphs, glyphs.len, &out2));
    try std.testing.expectEqual(out.nruns, out2.nruns);
    try std.testing.expectEqualSlices(u8, &raw, &raw2);
    // A stretched input through the v1 entry: heads still match the
    // reference run-for-run; the stretch itself is not delivered.
    const wide_src = "\\widetilde{AB}";
    var wref: [8]CRun = undefined;
    var wrout: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(wide_src.ptr, wide_src.len, false, &m, &wref, wref.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &wrout));
    var wraw: [8 * crun_v1_len]u8 = undefined;
    @memset(&wraw, 0xAA);
    var wout: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(wide_src.ptr, wide_src.len, false, &m, &wraw, 8, &rules, rules.len, &glyphs, glyphs.len, &wout));
    try std.testing.expectEqual(wrout.nruns, wout.nruns);
    for (0..wout.nruns) |i| {
        var s: CRunV1 = undefined;
        @memcpy(std.mem.asBytes(&s), wraw[i * crun_v1_len ..][0..crun_v1_len]);
        try std.testing.expectEqual(wref[i].font_id, s.font_id);
        try std.testing.expectEqual(wref[i].x, s.x);
        try std.testing.expectEqual(wref[i].glyph_count, s.glyph_count);
    }
}

test "cabi _ex negotiates run stride (issue #203)" {
    // Stride matrix on `\widetilde{AB}` (uniform-500 stubs pin the
    // accent stretch at exactly 2000, per the issue-#197 test): the
    // full-struct stride delivers the tails, wider strides leave the
    // unknown tail alone, narrower strides carry the prefix only, and
    // strides below 20 fail LIMIT without touching the buffer.
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
    const src = "\\widetilde{AB}";
    var ref: [8]CRun = undefined;
    @memset(std.mem.asBytes(&ref), 0xAA);
    var ref_rules: [8]CRule = undefined;
    var ref_glyphs: [64]u16 = undefined;
    var ref_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref, ref.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
    var stretched = false;
    for (ref[0..ref_out.nruns]) |r| {
        // The engine writes [0..22) plus the paint at [24..28): struct
        // padding at 22..24 stays host-owned. (This input is
        // unstylized, so every paint crossing here is ambient zero.)
        const bytes = std.mem.asBytes(&r);
        try std.testing.expectEqual(@as(u8, 0xAA), bytes[22]);
        try std.testing.expectEqual(@as(u8, 0xAA), bytes[23]);
        try std.testing.expectEqual(@as(u32, 0), r.color);
        if (r.x_scale != 1000) stretched = true;
    }
    try std.testing.expect(stretched);
    // A future 32-byte struct: heads, `x_scale`, and `color` land; the
    // pad (22..24) and the unknown tail (28..32) stay canary.
    var wide: [8 * 32]u8 = undefined;
    @memset(&wide, 0xAA);
    var wout: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &wide, 8, 32, &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &wout));
    try std.testing.expectEqual(ref_out.nruns, wout.nruns);
    for (0..wout.nruns) |i| {
        const slot = wide[i * 32 ..][0..32];
        var s: CRunV1 = undefined;
        @memcpy(std.mem.asBytes(&s), slot[0..crun_v1_len]);
        try std.testing.expectEqual(ref[i].font_id, s.font_id);
        try std.testing.expectEqual(ref[i].x, s.x);
        try std.testing.expectEqual(ref[i].glyph_count, s.glyph_count);
        // `x_scale` crosses as raw bytes: round-trip through a
        // local instead of assuming host endianness in the oracle.
        var got: u16 = undefined;
        @memcpy(std.mem.asBytes(&got), slot[crun_xscale_off..][0..2]);
        try std.testing.expectEqual(ref[i].x_scale, got);
        // Paint crosses the same way at 24..28 (ambient zero here);
        // the pad and the unknown tail stay canary.
        var paint: u32 = undefined;
        @memcpy(std.mem.asBytes(&paint), slot[crun_color_off..][0..4]);
        try std.testing.expectEqual(ref[i].color, paint);
        for (slot[crun_xscale_end..crun_color_off]) |b| {
            try std.testing.expectEqual(@as(u8, 0xAA), b);
        }
        for (slot[crun_color_end..]) |b| {
            try std.testing.expectEqual(@as(u8, 0xAA), b);
        }
    }
    // Prefix-only strides (20, 21): same heads, no `x_scale`.
    // Stride 20 packs slots contiguously (byte 20 starts the next
    // slot); stride 21 leaves a one-byte gap per slot, which must
    // stay canary — the tail write is exactly [20..22), never more.
    for ([_]usize{ 20, 21 }) |stride| {
        var raw: [8 * 21]u8 = undefined;
        @memset(&raw, 0xAA);
        var o: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &raw, 8, stride, &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &o));
        try std.testing.expectEqual(ref_out.nruns, o.nruns);
        for (0..o.nruns) |i| {
            var s: CRunV1 = undefined;
            @memcpy(std.mem.asBytes(&s), raw[i * stride ..][0..crun_v1_len]);
            try std.testing.expectEqual(ref[i].font_id, s.font_id);
            try std.testing.expectEqual(ref[i].x, s.x);
            if (stride == 21) {
                try std.testing.expectEqual(@as(u8, 0xAA), raw[i * stride + crun_v1_len]);
            }
        }
    }
    // Short strides fail LIMIT without touching the buffer — but the
    // needs still cross (issue #263).
    for ([_]usize{ 0, 1, 19 }) |bad| {
        var probe: [8]CRun = undefined;
        @memset(std.mem.asBytes(&probe), 0xAA);
        var o: CLayout = undefined;
        try std.testing.expectEqual(STATUS_LIMIT, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &probe, probe.len, bad, &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &o));
        try std.testing.expectEqual(STATUS_LIMIT, o.status);
        try std.testing.expectEqual(ref_out.nruns, o.nruns);
        try std.testing.expectEqual(ref_out.nrules, o.nrules);
        for (std.mem.asBytes(&probe)) |b| {
            try std.testing.expectEqual(@as(u8, 0xAA), b);
        }
    }
}

test "cabi old-sized arrays stay in bounds past 213 runs (issue #203)" {
    // 256 v1 slots hold 5120 bytes: a 28-byte stride overruns them
    // past run 182. Drive the v1 stride past that threshold — the
    // trailing guard must survive — then prove the over-cap input
    // fails cleanly on both entries.
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
    // Find a `x_0+x_1+...` input needing > 213 runs without topping
    // the 256 engine ceiling (counts come from the engine itself, so
    // future layout shifts keep this valid as long as some length
    // lands in the window).
    var text: [8192]u8 = undefined;
    var picked_len: usize = 0;
    var need: u32 = 0;
    for ([_]usize{ 60, 70, 80, 90, 100 }) |n| {
        var pos: usize = 0;
        for (0..n) |i| {
            if (i > 0) {
                text[pos] = '+';
                pos += 1;
            }
            const s = std.fmt.bufPrint(text[pos..], "x_{d}", .{i % 10}) catch break;
            pos += s.len;
        }
        var scratch: [256]CRun = undefined;
        var rules: [64]CRule = undefined;
        var glyphs: [8192]u16 = undefined;
        var o: CLayout = undefined;
        const probe_src = text[0..pos];
        const st = zatex_layout_utf8_ex(probe_src.ptr, probe_src.len, false, &m, &scratch, scratch.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &o);
        if (st == STATUS_OK and o.nruns > 213 and o.nruns <= 256) {
            picked_len = pos;
            need = o.nruns;
            break;
        }
    }
    try std.testing.expect(picked_len > 0);
    const src = text[0..picked_len];
    // Old-sized buffer plus guard through the v1 entry.
    var raw: [256 * crun_v1_len + 128]u8 = undefined;
    @memset(&raw, 0xAA);
    var rules: [64]CRule = undefined;
    var glyphs: [8192]u16 = undefined;
    var out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(src.ptr, src.len, false, &m, &raw, 256, &rules, rules.len, &glyphs, glyphs.len, &out));
    try std.testing.expectEqual(need, out.nruns);
    for (raw[256 * crun_v1_len ..]) |b| {
        try std.testing.expectEqual(@as(u8, 0xAA), b);
    }
    // Heads match the full-struct reference run-for-run.
    var ref: [256]CRun = undefined;
    var ref_glyphs: [8192]u16 = undefined;
    var ref_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref, ref.len, @sizeOf(CRun), &rules, rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
    try std.testing.expectEqual(out.nruns, ref_out.nruns);
    for (0..out.nruns) |i| {
        var s: CRunV1 = undefined;
        @memcpy(std.mem.asBytes(&s), raw[i * crun_v1_len ..][0..crun_v1_len]);
        try std.testing.expectEqual(ref[i].font_id, s.font_id);
        try std.testing.expectEqual(ref[i].x, s.x);
        try std.testing.expectEqual(ref[i].glyph_count, s.glyph_count);
    }
    // Past the ceiling both entries fail cleanly and the guard holds.
    var pos: usize = 0;
    for (0..140) |i| {
        if (i > 0) {
            text[pos] = '+';
            pos += 1;
        }
        const s = std.fmt.bufPrint(text[pos..], "x_{d}", .{i % 10}) catch break;
        pos += s.len;
    }
    const big = text[0..pos];
    @memset(&raw, 0xAA);
    var big_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8(big.ptr, big.len, false, &m, &raw, 256, &rules, rules.len, &glyphs, glyphs.len, &big_out));
    for (raw[256 * crun_v1_len ..]) |b| {
        try std.testing.expectEqual(@as(u8, 0xAA), b);
    }
    var ref_big: [256]CRun = undefined;
    @memset(std.mem.asBytes(&ref_big), 0xAA);
    var ref_big_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(big.ptr, big.len, false, &m, &ref_big, ref_big.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &ref_big_out));
}

test "cabi carries x_scale through for wide accents (issue #197)" {
    // `\widetilde{AB}` / `\widehat{AB}` through the C ABI (via the
    // stride-negotiated `_ex` entry — the v1 entry drops the tail by
    // design, see issue #203) must span their nuclei exactly like
    // the IR backend: every run's origin and stretch factor match
    // the Zig surface run-for-run, and the stretched accent advance
    // covers the nucleus span. Stub advances are uniform 500 (null
    // v4 hooks): AB spans 1000 over the 500-wide accent glyph, so
    // the factor is 2000.

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
        const st = zatex_layout_utf8_ex(c.tex.ptr, c.tex.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
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
    const st = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
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
        const st = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
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
        const st = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
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
    const st_runs = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &big_runs, big_runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_LIMIT, st_runs);
    const st_rules = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &big_rules, big_rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_LIMIT, st_rules);
    // At-ceiling buffers still serve small formulas.
    var cap_runs: [256]CRun = undefined;
    var cap_rules: [64]CRule = undefined;
    const st_ok = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &cap_runs, cap_runs.len, @sizeOf(CRun), &cap_rules, cap_rules.len, &glyphs, glyphs.len, &out);
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
    const st_runs = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &tiny_runs, tiny_runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
    try std.testing.expectEqual(STATUS_NO_SPACE, st_runs);
    const st_rules = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &tiny_rules, tiny_rules.len, &glyphs, glyphs.len, &out);
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
        const s1 = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &r1, r1.len, @sizeOf(CRun), &l1, l1.len, &g1, g1.len, &o1);
        const s2 = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &r2, r2.len, @sizeOf(CRun), &l2, l2.len, &g2, g2.len, &o2);
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

test "cabi carries per-run color with the stride pattern (issue #251)" {
    // `\color` scopes thread parse→IR→native runs (issue #35); the C
    // surface projects the paint as a 4-byte RGBA tail (0 = ambient),
    // written only when the run stride reaches past it — the #203
    // pattern: 24-stride hosts stay bit-identical, v1 never delivers.
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
    const red: u32 = 0xFF0000FF;
    // Fully scoped: every run carries red.
    {
        const src = "\\color{red}{x}";
        var runs: [8]CRun = undefined;
        var rules: [4]CRule = undefined;
        var glyphs: [32]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expect(out.nruns > 0);
        for (runs[0..out.nruns]) |r| {
            try std.testing.expectEqual(red, r.color);
        }
    }
    // Hex spec resolves the same way (`#00ff00` → opaque green).
    {
        const src = "\\color{#00ff00}{x}";
        var runs: [8]CRun = undefined;
        var rules: [4]CRule = undefined;
        var glyphs: [32]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expect(out.nruns > 0);
        for (runs[0..out.nruns]) |r| {
            try std.testing.expectEqual(@as(u32, 0x00FF00FF), r.color);
        }
    }
    // Scoped paint: `\textcolor` bounds the paint to one atom, so
    // colored and ambient runs coexist (runs never merge across
    // colors); unstylized input is all ambient (0). (`\color` is a
    // declaration over the rest — no ambient tail by construction.)
    {
        const src = "\\textcolor{red}{x}+y";
        var runs: [8]CRun = undefined;
        var rules: [4]CRule = undefined;
        var glyphs: [32]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        var seen_red = false;
        var seen_ambient = false;
        for (runs[0..out.nruns]) |r| {
            if (r.color == red) seen_red = true;
            if (r.color == 0) seen_ambient = true;
            try std.testing.expect(r.color == red or r.color == 0);
        }
        try std.testing.expect(seen_red and seen_ambient);
        const plain = "x+y";
        var pruns: [8]CRun = undefined;
        var pout: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(plain.ptr, plain.len, false, &m, &pruns, pruns.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &pout));
        for (pruns[0..pout.nruns]) |r| {
            try std.testing.expectEqual(@as(u32, 0), r.color);
        }
    }
    // Valid-but-unknown word (KaTeX passes bare words through; only
    // known names resolve) renders ambient — never a garbage paint.
    {
        const src = "\\color{chartreuse}{x}";
        var runs: [8]CRun = undefined;
        var rules: [4]CRule = undefined;
        var glyphs: [32]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expect(out.nruns > 0);
        for (runs[0..out.nruns]) |r| {
            try std.testing.expectEqual(@as(u32, 0), r.color);
        }
    }
    // Old 24-byte stride: same heads as the 28 reference, `x_scale`
    // delivered, paint region untouched (canary) — bit-identical to
    // the pre-color dylib.
    {
        const src = "\\color{red}{x}+\\widetilde{AB}";
        var ref: [8]CRun = undefined;
        var ref_rules: [8]CRule = undefined;
        var ref_glyphs: [64]u16 = undefined;
        var ref_out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref, ref.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
        try std.testing.expect(ref_out.nruns > 1);
        var old: [8 * 24]u8 = undefined;
        @memset(&old, 0xAA);
        var orules: [8]CRule = undefined;
        var oglyphs: [64]u16 = undefined;
        var oout: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &old, 8, 24, &orules, orules.len, &oglyphs, oglyphs.len, &oout));
        try std.testing.expectEqual(ref_out.nruns, oout.nruns);
        for (0..oout.nruns) |i| {
            const slot = old[i * 24 ..][0..24];
            var head: CRunV1 = undefined;
            @memcpy(std.mem.asBytes(&head), slot[0..crun_v1_len]);
            try std.testing.expectEqual(ref[i].font_id, head.font_id);
            try std.testing.expectEqual(ref[i].x, head.x);
            try std.testing.expectEqual(ref[i].glyph_count, head.glyph_count);
            var scale: u16 = undefined;
            @memcpy(std.mem.asBytes(&scale), slot[crun_xscale_off..][0..2]);
            try std.testing.expectEqual(ref[i].x_scale, scale);
            // Padding at 22..24 stays host-owned (never written).
            try std.testing.expectEqual(@as(u8, 0xAA), slot[22]);
            try std.testing.expectEqual(@as(u8, 0xAA), slot[23]);
        }
        // And the v1 entry on colored input: same heads, no paint.
        var vraw: [8 * crun_v1_len]u8 = undefined;
        @memset(&vraw, 0xAA);
        var vout: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(src.ptr, src.len, false, &m, &vraw, 8, &orules, orules.len, &oglyphs, oglyphs.len, &vout));
        try std.testing.expectEqual(ref_out.nruns, vout.nruns);
        for (0..vout.nruns) |i| {
            var head: CRunV1 = undefined;
            @memcpy(std.mem.asBytes(&head), vraw[i * crun_v1_len ..][0..crun_v1_len]);
            try std.testing.expectEqual(ref[i].x, head.x);
            try std.testing.expectEqual(ref[i].glyph_count, head.glyph_count);
        }
    }
}

test "cabi capabilities bitmask (issue #262)" {
    // One word negotiated once: the current surface carries the
    // stretch tail, the paint tail, space-failure needs, and the typed
    // error code (issue #273). New bits arrive additively — this pins
    // the known set, not the zeros above it.
    try std.testing.expectEqual(CAP_X_SCALE, @as(u32, 1) << 0);
    try std.testing.expectEqual(CAP_RUN_COLOR, @as(u32, 1) << 1);
    try std.testing.expectEqual(CAP_NEED_COUNTS, @as(u32, 1) << 2);
    try std.testing.expectEqual(CAP_ERR_CODE, @as(u32, 1) << 3);
    const caps = zatex_capabilities();
    try std.testing.expectEqual(CAP_X_SCALE | CAP_RUN_COLOR | CAP_NEED_COUNTS | CAP_ERR_CODE, caps);
    // Deterministic across calls (pure constant, no provider state).
    try std.testing.expectEqual(caps, zatex_capabilities());
}

test "cabi run tails cross complete fields only (issue #271)" {
    // The ONE mechanism: every stride in 20..40 delivers the frozen
    // prefix plus exactly the complete tail fields it reaches — never
    // struct padding (22..24), never a partial field, never unknown
    // tails. `\color{red}{x}+\widetilde{AB}` carries both a paint and
    // a stretch, so every table row is exercised at once.
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
    const src = "\\color{red}{x}+\\widetilde{AB}";
    var ref: [8]CRun = undefined;
    var ref_rules: [8]CRule = undefined;
    var ref_glyphs: [64]u16 = undefined;
    var ref_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref, ref.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
    // Both table rows fire on this input: some run is stretched, some
    // run is painted — otherwise the matrix below proves nothing.
    var saw_scale = false;
    var saw_paint = false;
    for (ref[0..ref_out.nruns]) |r| {
        if (r.x_scale != 1000) saw_scale = true;
        if (r.color != 0) saw_paint = true;
    }
    try std.testing.expect(saw_scale and saw_paint);
    var stride: usize = 20;
    while (stride <= 40) : (stride += 1) {
        var raw: [16 * 40 + 64]u8 = undefined;
        @memset(&raw, 0xAA);
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &raw, 16, stride, &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ref_out.nruns, out.nruns);
        try std.testing.expectEqual(ERR_OK, out.err_code);
        for (0..out.nruns) |i| {
            const slot = raw[i * stride ..][0..stride];
            var head: CRunV1 = undefined;
            @memcpy(std.mem.asBytes(&head), slot[0..crun_v1_len]);
            try std.testing.expectEqual(ref[i].font_id, head.font_id);
            try std.testing.expectEqual(ref[i].x, head.x);
            try std.testing.expectEqual(ref[i].glyph_count, head.glyph_count);
            // Complete fields land byte-exact; incomplete ones (and
            // the pad, which is in no row) stay canary.
            var scale: u16 = undefined;
            if (stride >= crun_xscale_end) {
                @memcpy(std.mem.asBytes(&scale), slot[crun_xscale_off..crun_xscale_end]);
                try std.testing.expectEqual(ref[i].x_scale, scale);
            }
            var paint: u32 = undefined;
            if (stride >= crun_color_end) {
                @memcpy(std.mem.asBytes(&paint), slot[crun_color_off..crun_color_end]);
                try std.testing.expectEqual(ref[i].color, paint);
            }
            for (slot, 0..) |b, j| {
                const in_scale = j >= crun_xscale_off and j < crun_xscale_end and stride >= crun_xscale_end;
                const in_paint = j >= crun_color_off and j < crun_color_end and stride >= crun_color_end;
                if (!in_scale and !in_paint and j >= crun_v1_len) {
                    try std.testing.expectEqual(@as(u8, 0xAA), b);
                }
            }
        }
        // Slots past `nruns` stay untouched.
        for (raw[out.nruns * stride ..]) |b| {
            try std.testing.expectEqual(@as(u8, 0xAA), b);
        }
    }
}

test "cabi x_scale is truncated per-mille (issue #272)" {
    // The rounding contract, pinned through the C entry: the accent
    // glyph advances 600 over a 1000-wide nucleus, so the exact ratio
    // is 1000000/600 = 1666.67 — truncation lands 1666, round-half-up
    // would land 1667. (u16 per-mille kept deliberately: float would
    // only re-encode this truncated ratio with binary error.)
    const S = struct {
        fn gid(_: ?*const anyopaque, _: u16, cp: u32) callconv(.c) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: ?*const anyopaque, _: u16, glyph: u16) callconv(.c) i32 {
            // The `~` accent glyph is narrower than the nucleus span
            // without dividing it evenly — the truncation discriminator.
            if (glyph == 0x7E) return 600;
            return 500;
        }
        fn rt(_: ?*const anyopaque, _: u16, _: u32) callconv(.c) i32 {
            return 40;
        }
    };
    const m: CMetrics = .{ .ctx = null, .glyph_id = S.gid, .advance = S.adv, .rule_thickness = S.rt };
    const src = "\\widetilde{AB}";
    var runs: [8]CRun = undefined;
    var rules: [8]CRule = undefined;
    var glyphs: [64]u16 = undefined;
    var out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
    // The span itself is unaffected — only the factor truncates.
    try std.testing.expectEqual(@as(u32, 1000), out.width);
    var accent_scale: ?u16 = null;
    for (runs[0..out.nruns]) |r| {
        const cg = glyphs[r.glyph_start..][0..r.glyph_count];
        var is_accent = false;
        for (cg) |g| {
            if (g == 0x7E) is_accent = true;
        }
        // Stretch never merges across runs, so the accent run is pure
        // and every other run is unstretched identity.
        if (is_accent) {
            accent_scale = r.x_scale;
        } else {
            try std.testing.expectEqual(@as(u16, 1000), r.x_scale);
        }
    }
    try std.testing.expectEqual(@as(?u16, 1666), accent_scale);
}

test "cabi err_code refines status (issue #273)" {
    // Append-only pin: the code rides the tail past `err_msg_len`,
    // never disturbing the frozen head.
    comptime {
        std.debug.assert(@offsetOf(CLayout, "err_code") > @offsetOf(CLayout, "err_msg_len"));
        std.debug.assert(@offsetOf(CLayout, "status") == 20);
    }
    // The reserved mapping holds even though the core never emits it
    // today: `Unsupported` stays wired to status 1 and its own code.
    try std.testing.expectEqual(
        StatusCode{ .status = STATUS_UNSUPPORTED, .code = ERR_UNSUPPORTED_CMD },
        toStatusCode(error.Unsupported),
    );
    try std.testing.expectEqual(
        StatusCode{ .status = STATUS_NO_SPACE, .code = ERR_NO_SPACE },
        toStatusCode(error.OutOfMemory),
    );
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
    // Success clears the code.
    {
        const src = "x^2+\\frac12";
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_OK, out.err_code);
    }
    // Malformed input: BAD_TEX with the message still attached.
    {
        const src = "\\nope";
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_INVALID, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_BAD_TEX, out.err_code);
        try std.testing.expect(out.err_msg_len > 0);
    }
    // Depth, input-length, and expansion failures each name themselves.
    {
        var deep: [80]u8 = undefined;
        @memset(&deep, '{');
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_TOO_DEEP, zatex_layout_utf8_ex(&deep, deep.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_TOO_DEEP, out.err_code);
    }
    {
        var big: [zatex.max_input_len + 1]u8 = .{'x'} ** (zatex.max_input_len + 1);
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_TOO_LONG, zatex_layout_utf8_ex(&big, big.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_OVERFLOW_INPUT, out.err_code);
    }
    {
        const src = "\\def\\a{\\a}\\a";
        var runs: [16]CRun = undefined;
        var rules: [8]CRule = undefined;
        var glyphs: [64]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_EXPANSION_LIMIT, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_EXPANSION_LIMIT, out.err_code);
    }
    // Caller-buffer shorts name the first short buffer in
    // runs/rules/glyphs priority and carry the #263 needs.
    {
        const src = "\\sqrt{x}+\\frac{a}{b}";
        var ref_runs: [256]CRun = undefined;
        var ref_rules: [64]CRule = undefined;
        var ref_glyphs: [512]u16 = undefined;
        var ref_out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref_runs, ref_runs.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
        // Starve runs.
        {
            var tiny: [0]CRun = undefined;
            var rules: [64]CRule = undefined;
            var glyphs: [512]u16 = undefined;
            var out: CLayout = undefined;
            try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &tiny, tiny.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
            try std.testing.expectEqual(ERR_OVERFLOW_RUNS, out.err_code);
            try std.testing.expectEqual(ref_out.nruns, out.nruns);
            try std.testing.expectEqual(ref_out.nrules, out.nrules);
        }
        // Starve rules.
        {
            var runs: [256]CRun = undefined;
            var tiny: [0]CRule = undefined;
            var glyphs: [512]u16 = undefined;
            var out: CLayout = undefined;
            try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &tiny, tiny.len, &glyphs, glyphs.len, &out));
            try std.testing.expectEqual(ERR_OVERFLOW_RULES, out.err_code);
            try std.testing.expectEqual(ref_out.nruns, out.nruns);
        }
        // Starve glyphs.
        {
            var runs: [256]CRun = undefined;
            var rules: [64]CRule = undefined;
            var tiny: [0]u16 = undefined;
            var out: CLayout = undefined;
            try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &tiny, tiny.len, &out));
            try std.testing.expectEqual(ERR_OVERFLOW_GLYPHS, out.err_code);
        }
        // A null-runs probe names runs and still measures.
        {
            var rules: [64]CRule = undefined;
            var glyphs: [512]u16 = undefined;
            var out: CLayout = undefined;
            const st = zatex_layout_utf8_ex(src.ptr, src.len, false, &m, null, 0, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out);
            try std.testing.expectEqual(STATUS_NO_SPACE, st);
            try std.testing.expectEqual(ERR_OVERFLOW_RUNS, out.err_code);
            try std.testing.expectEqual(ref_out.nruns, out.nruns);
        }
    }
    // Engine pools exhausted past the ceilings: unretryable NO_SPACE
    // with zeroed needs.
    {
        var text: [8192]u8 = undefined;
        var pos: usize = 0;
        for (0..140) |i| {
            if (i > 0) {
                text[pos] = '+';
                pos += 1;
            }
            const s = std.fmt.bufPrint(text[pos..], "x_{d}", .{i % 10}) catch unreachable;
            pos += s.len;
        }
        const src = text[0..pos];
        var runs: [256]CRun = undefined;
        var rules: [64]CRule = undefined;
        var glyphs: [8192]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_NO_SPACE, out.err_code);
        try std.testing.expectEqual(@as(u32, 0), out.nruns);
        try std.testing.expectEqual(@as(u32, 0), out.nrules);
    }
    // Request-shape failures: over-ceiling caps and short strides.
    {
        const src = "x";
        var big_runs: [300]CRun = undefined;
        var rules: [4]CRule = undefined;
        var glyphs: [16]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_LIMIT, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &big_runs, big_runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ERR_LIMIT, out.err_code);
        var probe: [8]CRun = undefined;
        var o2: CLayout = undefined;
        try std.testing.expectEqual(STATUS_LIMIT, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &probe, probe.len, 19, &rules, rules.len, &glyphs, glyphs.len, &o2));
        try std.testing.expectEqual(ERR_LIMIT, o2.err_code);
        // ...while the v1 entry on the same input still succeeds with
        // a clear code — old hosts are bit-identical.
        var vraw: [8 * crun_v1_len]u8 = undefined;
        var o3: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8(src.ptr, src.len, false, &m, &vraw, 8, &rules, rules.len, &glyphs, glyphs.len, &o3));
        try std.testing.expectEqual(ERR_OK, o3.err_code);
    }
}

test "cabi reports needed counts on space failures (issue #263)" {
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
    // Two rects (radical vinculum + fraction bar) and several runs, so
    // every starvation premise below is pinned, not assumed.
    const src = "\\sqrt{x}+\\frac{a}{b}";
    // Reference needs from a ceiling-size call.
    var ref_runs: [256]CRun = undefined;
    var ref_rules: [64]CRule = undefined;
    var ref_glyphs: [4096]u16 = undefined;
    var ref_out: CLayout = undefined;
    try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &ref_runs, ref_runs.len, @sizeOf(CRun), &ref_rules, ref_rules.len, &ref_glyphs, ref_glyphs.len, &ref_out));
    try std.testing.expect((ref_out.nruns > 1) and (ref_out.nrules > 1));
    // Starved runs: exact needs cross, and allocating exactly them
    // (with a generous glyph buffer) succeeds in one retry.
    {
        var tiny: [1]CRun = undefined;
        var rules: [64]CRule = undefined;
        var glyphs: [4096]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &tiny, tiny.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ref_out.nruns, out.nruns);
        try std.testing.expectEqual(ref_out.nrules, out.nrules);
        var runs: [256]CRun = undefined;
        var rrules: [64]CRule = undefined;
        var rglyphs: [4096]u16 = undefined;
        var rout: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, out.nruns, @sizeOf(CRun), &rrules, out.nrules, &rglyphs, rglyphs.len, &rout));
        try std.testing.expectEqual(ref_out.nruns, rout.nruns);
    }
    // Starved rules: same shape (a 1-rule cap starves a 2-rect need).
    {
        var runs: [256]CRun = undefined;
        var tiny: [1]CRule = undefined;
        var glyphs: [4096]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &tiny, tiny.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ref_out.nruns, out.nruns);
        try std.testing.expectEqual(ref_out.nrules, out.nrules);
    }
    // Starved glyphs: runs/rules needs still cross; growing only the
    // glyph buffer then succeeds.
    {
        var runs: [256]CRun = undefined;
        var rules: [64]CRule = undefined;
        var tiny: [2]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &tiny, tiny.len, &out));
        try std.testing.expectEqual(ref_out.nruns, out.nruns);
        try std.testing.expectEqual(ref_out.nrules, out.nrules);
        var glyphs: [4096]u16 = undefined;
        var rout: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, out.nruns, @sizeOf(CRun), &rules, out.nrules, &glyphs, glyphs.len, &rout));
    }
    // Over-ceiling request: STATUS_LIMIT, but the needs still cross —
    // the host learns its 300-run ask was over ceiling and the true
    // need fits small buffers.
    {
        var big: [300]CRun = undefined;
        var rules: [64]CRule = undefined;
        var glyphs: [4096]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_LIMIT, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &big, big.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ref_out.nruns, out.nruns);
        try std.testing.expectEqual(ref_out.nrules, out.nrules);
    }
    // Null-buffer probe: NO_SPACE with the needs, allocate, succeed.
    {
        var out: CLayout = undefined;
        var glyphs: [4096]u16 = undefined;
        try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, null, 0, @sizeOf(CRun), null, 0, &glyphs, glyphs.len, &out));
        try std.testing.expectEqual(ref_out.nruns, out.nruns);
        try std.testing.expectEqual(ref_out.nrules, out.nrules);
        var runs: [256]CRun = undefined;
        var rules: [64]CRule = undefined;
        var rout: CLayout = undefined;
        try std.testing.expectEqual(STATUS_OK, zatex_layout_utf8_ex(src.ptr, src.len, false, &m, &runs, out.nruns, @sizeOf(CRun), &rules, out.nrules, &glyphs, glyphs.len, &rout));
    }
    // Past the ceilings the need is unmeasurable: zeroed counts (as
    // before) — with CAP_NEED_COUNTS set the host reads zero as
    // "exceeds capacity", not "old dylib".
    {
        try std.testing.expect((zatex_capabilities() & CAP_NEED_COUNTS) != 0);
        var text: [8192]u8 = undefined;
        var pos: usize = 0;
        for (0..140) |i| {
            if (i > 0) {
                text[pos] = '+';
                pos += 1;
            }
            const s = std.fmt.bufPrint(text[pos..], "x_{d}", .{i % 10}) catch break;
            pos += s.len;
        }
        const big = text[0..pos];
        var runs: [256]CRun = undefined;
        var rules: [64]CRule = undefined;
        var glyphs: [8192]u16 = undefined;
        var out: CLayout = undefined;
        try std.testing.expectEqual(STATUS_NO_SPACE, zatex_layout_utf8_ex(big.ptr, big.len, false, &m, &runs, runs.len, @sizeOf(CRun), &rules, rules.len, &glyphs, glyphs.len, &out));
        // Ceiling-size buffers on an over-ceiling formula: needs stay
        // zeroed (unmeasurable), exactly the old shape.
        try std.testing.expectEqual(@as(u32, 0), out.nruns);
        try std.testing.expectEqual(@as(u32, 0), out.nrules);
    }
}

test "zatex_version packs 16/8/8 with round-trip (issue #276)" {
    // Normative widths: major 16 bits, minor 8, patch 8. Fields must
    // fit — a patch above 255 would bleed into minor (0.0.300 would
    // read as 0.1.44). `contract.zig` comptime-asserts the widths;
    // this test pins the runtime word and the unpacking hosts use.
    try std.testing.expect(zatex.contract.version.minor < 256);
    try std.testing.expect(zatex.contract.version.patch < 256);
    try std.testing.expect(zatex.contract.version.major < 65536);
    const w = zatex_version();
    try std.testing.expectEqual(
        (@as(u32, @intCast(zatex.contract.version.major)) << 16) |
            (@as(u32, @intCast(zatex.contract.version.minor)) << 8) |
            @as(u32, @intCast(zatex.contract.version.patch)),
        w,
    );
    try std.testing.expectEqual(@as(u32, @intCast(zatex.contract.version.major)), w >> 16);
    try std.testing.expectEqual(@as(u32, @intCast(zatex.contract.version.minor)), (w >> 8) & 0xFF);
    try std.testing.expectEqual(@as(u32, @intCast(zatex.contract.version.patch)), w & 0xFF);
    // The version word packs the library version only (proven equal
    // above): `provider_version` rides its own word and is never
    // mixed into this one by construction (cabi.zig reads only
    // `zatex.version` here).
}

// NOTE (issues #275): the release-docs agreement guard (workflow
// trigger vs install asset names vs changelog trigger) and the
// build.zig.zon-vs-contract.version pin live in
// tools/check_release_docs.sh (CI `release-docs` job), not here:
// @embedFile cannot reach outside the package src tree, so a Zig
// test cannot read the workflow, docs, or changelog.
