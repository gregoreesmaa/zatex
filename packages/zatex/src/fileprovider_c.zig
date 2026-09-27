//! C-callable blessed metrics provider (issue #256): font bytes or a
//! font path in, ready `zatex_metrics_t` out. Host-side, never in the
//! layout core — the dist lib never imports this file (the size gate
//! proves it); C hosts compile it in as the bridge (see
//! `zatex_fileprovider.h` for the recipe).
//!
//! The C surface is four entries: `zatex_fp_load_bytes`,
//! `zatex_fp_load_path`, `zatex_fp_metrics`, `zatex_fp_free`, plus the
//! `ZATEX_FP_*` status codes. Loads copy their input (the caller may
//! free immediately); every query is allocation-free and bounded; two
//! handles share no state. `FileProvider.init` failures become
//! `ZATEX_FP_NOT_A_FONT` (total on adversarial input, never a panic).
const std = @import("std");
const zatex = @import("zatex");
const fileprovider = @import("fileprovider");

/// Must match `zatex.h` field-for-field (same contract as
/// `cabi.zig`'s `CMetrics`, restated here so this bridge never imports
/// the core's C file — one instance of the core per binary, no
/// duplicate exports). The header-match test below machine-checks
/// every offset and the size against `zatex.h` via `@cImport`.
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

pub const Code = enum(c_int) {
    ok = 0,
    bad_arg = 1,
    no_memory = 2,
    not_a_font = 3,
    io = 4,
    too_big = 5,
};

/// Font input cap: the largest file this bridge copies (64 MiB — the
/// reference fixture is under 1 MiB; anything larger is not a font).
pub const max_bytes: usize = 64 << 20;

/// Owned handle: `bytes` is the private copy every query borrows,
/// `prov` is the native provider whose `ctx` points at `fp` (wired
/// after heap placement, so the pointer is stable until `free`).
const Handle = struct {
    bytes: []u8,
    fp: fileprovider.FileProvider,
    prov: zatex.MetricsProvider,
};

const alloc = std.heap.c_allocator;

fn setCode(code: ?*c_int, c: Code) void {
    if (code) |p| p.* = @intFromEnum(c);
}

fn openOwned(bytes: []const u8, code: ?*c_int) ?*Handle {
    const h = alloc.create(Handle) catch {
        setCode(code, .no_memory);
        return null;
    };
    errdefer alloc.destroy(h);
    const copy = alloc.dupe(u8, bytes) catch {
        setCode(code, .no_memory);
        return null;
    };
    errdefer alloc.free(copy);
    h.* = .{
        .bytes = copy,
        .fp = fileprovider.FileProvider.init(copy) catch |e| {
            setCode(code, if (e == error.OutOfMemory) .no_memory else .not_a_font);
            return null;
        },
        .prov = undefined,
    };
    h.prov = h.fp.provider();
    setCode(code, .ok);
    return h;
}

export fn zatex_fp_load_bytes(bytes: ?[*]const u8, len: usize, code: ?*c_int) callconv(.c) ?*Handle {
    if (len > max_bytes) {
        setCode(code, .too_big);
        return null;
    }
    const src = bytes orelse {
        setCode(code, .bad_arg);
        return null;
    };
    return openOwned(src[0..len], code);
}

export fn zatex_fp_load_path(path: ?[*:0]const u8, code: ?*c_int) callconv(.c) ?*Handle {
    const p = path orelse {
        setCode(code, .bad_arg);
        return null;
    };
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        std.mem.span(p),
        alloc,
        .limited(max_bytes + 1),
    ) catch {
        setCode(code, .io);
        return null;
    };
    defer alloc.free(bytes);
    if (bytes.len > max_bytes) {
        setCode(code, .too_big);
        return null;
    }
    // `openOwned` copies again so the read buffer frees on return.
    return openOwned(bytes, code);
}

fn handleOf(ctx: ?*const anyopaque) *const Handle {
    return @ptrCast(@alignCast(ctx.?));
}

fn cGid(ctx: ?*const anyopaque, font: u16, cp: u32) callconv(.c) u16 {
    const h = handleOf(ctx);
    const trunc: u21 = @truncate(cp);
    return h.prov.glyphId(h.prov.ctx, font, trunc);
}

fn cAdv(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32 {
    const h = handleOf(ctx);
    return h.prov.advance(h.prov.ctx, font, glyph);
}

fn cRule(ctx: ?*const anyopaque, font: u16, kind: u32) callconv(.c) i32 {
    const h = handleOf(ctx);
    // Total on out-of-range kinds (a corrupt host struct reads 40,
    // the documented fallback — never safety-checked UB).
    if (kind > 3) return 40;
    const k: zatex.RuleKind = @enumFromInt(kind);
    return h.prov.ruleThickness(h.prov.ctx, font, k);
}

fn cVariant(ctx: ?*const anyopaque, font: u16, glyph: u16, min_height: i32) callconv(.c) u16 {
    const h = handleOf(ctx);
    return h.prov.glyphVariant.?(h.prov.ctx, font, glyph, min_height);
}

fn cItalic(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32 {
    const h = handleOf(ctx);
    return h.prov.italicCorrection.?(h.prov.ctx, font, glyph);
}

fn cKern(ctx: ?*const anyopaque, font: u16, glyph: u16, height: i32, corner: u32) callconv(.c) i32 {
    const h = handleOf(ctx);
    if (corner > 3) return 0;
    const c: zatex.contract.KernCorner = @enumFromInt(corner);
    return h.prov.kernCorrection.?(h.prov.ctx, font, glyph, height, c);
}

fn cExt(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) CExtents {
    const h = handleOf(ctx);
    const e = h.prov.extents.?(h.prov.ctx, font, glyph);
    return .{ .ha = e[0], .db = e[1] };
}

fn cInk(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) CInkBox {
    const h = handleOf(ctx);
    const b = h.prov.inkBounds.?(h.prov.ctx, font, glyph);
    return .{ .x0 = b[0], .y0 = b[1], .x1 = b[2], .y1 = b[3] };
}

export fn zatex_fp_metrics(fp: ?*const Handle, out: ?*CMetrics) callconv(.c) void {
    const h = fp orelse return;
    const m = out orelse return;
    m.* = .{
        .ctx = @ptrCast(h),
        .glyph_id = cGid,
        .advance = cAdv,
        .rule_thickness = cRule,
        .glyph_variant = cVariant,
        .italic_correction = cItalic,
        .kern_correction = cKern,
        .extents = cExt,
        .ink_bounds = cInk,
    };
}

export fn zatex_fp_free(fp: ?*Handle) callconv(.c) void {
    const h = fp orelse return;
    alloc.free(h.bytes);
    alloc.destroy(h);
}

// ---------------------------------------------------------------------------
// Tests: the exported entries called the way a C host calls them.
// ---------------------------------------------------------------------------

const ch = @cImport({
    @cInclude("zatex_fileprovider.h");
});

test "c struct mirrors zatex.h exactly" {
    try std.testing.expectEqual(@sizeOf(ch.zatex_metrics_t), @sizeOf(CMetrics));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "ctx"), @offsetOf(CMetrics, "ctx"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "glyph_id"), @offsetOf(CMetrics, "glyph_id"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "advance"), @offsetOf(CMetrics, "advance"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "rule_thickness"), @offsetOf(CMetrics, "rule_thickness"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "glyph_variant"), @offsetOf(CMetrics, "glyph_variant"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "italic_correction"), @offsetOf(CMetrics, "italic_correction"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "kern_correction"), @offsetOf(CMetrics, "kern_correction"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "extents"), @offsetOf(CMetrics, "extents"));
    try std.testing.expectEqual(@offsetOf(ch.zatex_metrics_t, "ink_bounds"), @offsetOf(CMetrics, "ink_bounds"));
    // The header's status codes equal the bridge's.
    try std.testing.expectEqual(ch.ZATEX_FP_OK, @intFromEnum(Code.ok));
    try std.testing.expectEqual(ch.ZATEX_FP_BAD_ARG, @intFromEnum(Code.bad_arg));
    try std.testing.expectEqual(ch.ZATEX_FP_NO_MEMORY, @intFromEnum(Code.no_memory));
    try std.testing.expectEqual(ch.ZATEX_FP_NOT_A_FONT, @intFromEnum(Code.not_a_font));
    try std.testing.expectEqual(ch.ZATEX_FP_IO, @intFromEnum(Code.io));
    try std.testing.expectEqual(ch.ZATEX_FP_TOO_BIG, @intFromEnum(Code.too_big));
}

const lm_path = "fixtures/fonts/latinmodern-math.otf";

fn loadFixture(path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        path,
        std.testing.allocator,
        .limited(4 * 1024 * 1024),
    );
}

/// Native provider over a filled C struct (the same bridge shape as
/// `cabi.zig`'s host side): proves the emitted struct drives layout.
const CBridge = struct {
    m: *const CMetrics,
    fn gid(ctx: *const anyopaque, font: u16, cp: u21) u16 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        return b.m.glyph_id.?(b.m.ctx, font, cp);
    }
    fn adv(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        return b.m.advance.?(b.m.ctx, font, glyph);
    }
    fn rule(ctx: *const anyopaque, font: u16, kind: zatex.RuleKind) i32 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        return b.m.rule_thickness.?(b.m.ctx, font, @intFromEnum(kind));
    }
    fn variant(ctx: *const anyopaque, font: u16, glyph: u16, need: i32) u16 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        return b.m.glyph_variant.?(b.m.ctx, font, glyph, need);
    }
    fn italic(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        return b.m.italic_correction.?(b.m.ctx, font, glyph);
    }
    fn kern(ctx: *const anyopaque, font: u16, glyph: u16, height: i32, corner: zatex.contract.KernCorner) i32 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        return b.m.kern_correction.?(b.m.ctx, font, glyph, height, @intFromEnum(corner));
    }
    fn ext(ctx: *const anyopaque, font: u16, glyph: u16) [2]i32 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        const e = b.m.extents.?(b.m.ctx, font, glyph);
        return .{ e.ha, e.db };
    }
    fn ink(ctx: *const anyopaque, font: u16, glyph: u16) [4]i32 {
        const b: *const CBridge = @ptrCast(@alignCast(ctx));
        const i = b.m.ink_bounds.?(b.m.ctx, font, glyph);
        return .{ i.x0, i.y0, i.x1, i.y1 };
    }
};

test "load_bytes fills a conformant, layout-driving provider" {
    const bytes = try loadFixture(lm_path);
    defer std.testing.allocator.free(bytes);
    var code: c_int = -1;
    const h = zatex_fp_load_bytes(bytes.ptr, bytes.len, &code) orelse {
        std.debug.panic("load failed, code {d}", .{code});
    };
    defer zatex_fp_free(h);
    try std.testing.expectEqual(@intFromEnum(Code.ok), code);

    var m: CMetrics = undefined;
    zatex_fp_metrics(h, &m);
    // All eight hooks filled (the refined core paths, never v3).
    try std.testing.expect(m.glyph_id != null);
    try std.testing.expect(m.advance != null);
    try std.testing.expect(m.rule_thickness != null);
    try std.testing.expect(m.glyph_variant != null);
    try std.testing.expect(m.italic_correction != null);
    try std.testing.expect(m.kern_correction != null);
    try std.testing.expect(m.extents != null);
    try std.testing.expect(m.ink_bounds != null);

    // Headline truth through the C ABI: 'x' advances 528, never 500.
    const x = m.glyph_id.?(m.ctx, 0, 'x');
    try std.testing.expect(x != 0);
    try std.testing.expectEqual(@as(i32, 528), m.advance.?(m.ctx, 0, x));
    // Zero-width combining mark advances 0 (the 500-fallback canary).
    const hat = m.glyph_id.?(m.ctx, 0, 0x0302);
    try std.testing.expectEqual(@as(i32, 0), m.advance.?(m.ctx, 0, hat));
    // Out-of-range rule kinds stay total (40, never UB).
    try std.testing.expectEqual(@as(i32, 40), m.rule_thickness.?(m.ctx, 0, 99));
    try std.testing.expectEqual(@as(i32, 0), m.kern_correction.?(m.ctx, 0, x, 0, 9));

    // The #194 self-test shape through the emitted struct: bridge
    // transparency — the C-emitted struct reports byte-identical
    // diagnostics to the native provider over the same file. (One LM
    // file misses U+203E, which lives in the full stack's KaTeX Main
    // face, so neither passes cleanly; what matters is the bridge
    // adds zero divergence.)
    const bridge = CBridge{ .m = &m };
    const prov = zatex.MetricsProvider{
        .ctx = &bridge,
        .glyphId = CBridge.gid,
        .advance = CBridge.adv,
        .ruleThickness = CBridge.rule,
        .glyphVariant = CBridge.variant,
        .italicCorrection = CBridge.italic,
        .kernCorrection = CBridge.kern,
        .extents = CBridge.ext,
        .inkBounds = CBridge.ink,
    };
    var fpn = try fileprovider.FileProvider.init(bytes);
    const nat = fpn.provider();
    var nbuf: [4096]u8 = undefined;
    const nres = zatex.conform.check(nat, 0, &nbuf);
    var cbuf: [4096]u8 = undefined;
    const cres = zatex.conform.check(prov, 0, &cbuf);
    try std.testing.expectEqual(nres.diagnostics, cres.diagnostics);
    try std.testing.expectEqualStrings(nbuf[0..nres.bytes], cbuf[0..cres.bytes]);

    // And it lays out: real geometry, not stub geometry.
    var runs: [256]zatex.ir.Run = undefined;
    var rules: [64]zatex.ir.Rule = undefined;
    var glyphs: [4096]u16 = undefined;
    const l = try zatex.layoutFull("x^2+\\frac12", .{}, prov, &runs, &rules, &glyphs);
    try std.testing.expect(l.width > 0);
    try std.testing.expect(l.runs.len > 0);
}

test "load_bytes copies: caller buffer may die on return" {
    const bytes = try loadFixture(lm_path);
    const h = zatex_fp_load_bytes(bytes.ptr, bytes.len, null) orelse {
        std.debug.panic("load failed", .{});
    };
    // Free the source BEFORE any query: the handle owns its copy.
    std.testing.allocator.free(bytes);
    defer zatex_fp_free(h);
    var m: CMetrics = undefined;
    zatex_fp_metrics(h, &m);
    try std.testing.expectEqual(@as(i32, 528), m.advance.?(m.ctx, 0, m.glyph_id.?(m.ctx, 0, 'x')));
}

test "garbage bytes report NOT_A_FONT, never panic" {
    var code: c_int = -1;
    const junk = "this is not a font";
    try std.testing.expectEqual(null, zatex_fp_load_bytes(junk.ptr, junk.len, &code));
    try std.testing.expectEqual(@intFromEnum(Code.not_a_font), code);
    try std.testing.expectEqual(null, zatex_fp_load_bytes(null, 0, &code));
    try std.testing.expectEqual(@intFromEnum(Code.bad_arg), code);
    try std.testing.expectEqual(null, zatex_fp_load_bytes(null, 8, &code));
    try std.testing.expectEqual(@intFromEnum(Code.bad_arg), code);
}

test "load_path reads files, missing paths report IO" {
    var code: c_int = -1;
    try std.testing.expectEqual(null, zatex_fp_load_path(null, &code));
    try std.testing.expectEqual(@intFromEnum(Code.bad_arg), code);
    try std.testing.expectEqual(null, zatex_fp_load_path("fixtures/does-not-exist.otf", &code));
    try std.testing.expectEqual(@intFromEnum(Code.io), code);
    const h = zatex_fp_load_path(lm_path, &code) orelse {
        std.debug.panic("load_path failed, code {d}", .{code});
    };
    defer zatex_fp_free(h);
    try std.testing.expectEqual(@intFromEnum(Code.ok), code);
    var m: CMetrics = undefined;
    zatex_fp_metrics(h, &m);
    try std.testing.expectEqual(@as(i32, 528), m.advance.?(m.ctx, 0, m.glyph_id.?(m.ctx, 0, 'x')));
}

test "null metrics and free are safe no-ops" {
    zatex_fp_metrics(null, null);
    zatex_fp_free(null);
    var m: CMetrics = undefined;
    zatex_fp_metrics(null, &m);
}
