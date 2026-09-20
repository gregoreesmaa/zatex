//! ZaTeX reference host: test-only MetricsProvider over the vendored
//! font stack, plus the coverage/determinism probes.
//!
//! This is HOST code (like `read`'s future math plugin), not the core:
//! it reads font files, drives `otmath` through `fontstack`, and
//! answers provider queries. It exists to prove the core against real
//! fonts — byte-identical input+font=output, every emittable glyph
//! resolving (issue #92: Latin Modern Math alone left 28 KaTeX-accepted
//! glyphs blank, so the stack layers the vendored KaTeX CFF-OTF faces
//! and the system STIX fallback under LM-first chains).
const std = @import("std");
const zatex = @import("zatex");
const otmath = @import("otmath");
const fontstack = @import("fontstack");
const inv = @import("invariants");
const contract = zatex.contract;
const symbols = zatex.symbols;

/// Vendored reference font (test fixture, never linked into hosts).
const vendored_path = "fixtures/fonts/latinmodern-math.otf";

/// Vendored one-glyph STIX subset (issue #92): the over/under hook
/// U+203E lives in no other vendored face, so without this file the
/// underbar would depend on the machine's system fonts.
const stix_subset_path = "fixtures/fonts/STIXTwoMath-overline.otf";

/// Vendored KaTeX faces (issue #92): CFF-OTF converts of the pinned
/// bundle's TTFs — same outlines the software backend rasterizes.
/// Order here is load order (LM stays face 0: unified gids for
/// LM-resolved glyphs are unchanged).
const katex_faces = [_]struct { path: []const u8, role: fontstack.Role }{
    .{ .path = "fixtures/fonts/katex/KaTeX_Main-Regular.otf", .role = .main },
    .{ .path = "fixtures/fonts/katex/KaTeX_Main-Bold.otf", .role = .main_bold },
    .{ .path = "fixtures/fonts/katex/KaTeX_Main-Italic.otf", .role = .main_italic },
    .{ .path = "fixtures/fonts/katex/KaTeX_Main-BoldItalic.otf", .role = .main_bi },
    .{ .path = "fixtures/fonts/katex/KaTeX_Math-Italic.otf", .role = .math_italic },
    .{ .path = "fixtures/fonts/katex/KaTeX_AMS-Regular.otf", .role = .ams },
    .{ .path = "fixtures/fonts/katex/KaTeX_SansSerif-Regular.otf", .role = .sans },
    .{ .path = "fixtures/fonts/katex/KaTeX_Typewriter-Regular.otf", .role = .typewriter },
    .{ .path = "fixtures/fonts/katex/KaTeX_Caligraphic-Regular.otf", .role = .cal },
    .{ .path = "fixtures/fonts/katex/KaTeX_Fraktur-Regular.otf", .role = .frak },
    .{ .path = "fixtures/fonts/katex/KaTeX_Script-Regular.otf", .role = .script },
};

/// System-font fallback candidates (issue 8): STIX Two Math ships in
/// the macOS Supplemental fonts; /Library/Fonts covers user installs.
const system_candidates = [_][]const u8{
    "/System/Library/Fonts/Supplemental/STIXTwoMath.otf",
    "/Library/Fonts/STIXTwoMath.otf",
};

fn layoutCase(
    ref: *Ref,
    src: []const u8,
    display: bool,
    runs: []zatex.ir.Run,
    rules: []zatex.ir.Rule,
    glyphs: []u16,
) !zatex.ir.Layout {
    return zatex.layoutFull(src, .{ .display_mode = display }, ref.provider(), runs, rules, glyphs);
}

const Ref = struct {
    bufs: [fontstack.max_faces][]u8 = undefined,
    nbufs: usize = 0,
    stack: fontstack.Stack = .{},

    /// Full fixture set: LM first (face 0, so LM-resolved unified
    /// gids are unchanged), then the KaTeX faces, then the first
    /// loadable system STIX (skipped where the OS lacks it).
    fn load() !Ref {
        var r = Ref{};
        errdefer r.free();
        try r.addRequired(vendored_path, .lm);
        for (katex_faces) |k| try r.addRequired(k.path, k.role);
        try r.addRequired(stix_subset_path, .stix);
        for (system_candidates) |p| {
            r.addOptional(p, .stix) catch continue;
            break;
        }
        // Large operators (issue #101) load last so every existing
        // unified gid stays bit-identical.
        try r.addRequired("fixtures/fonts/katex/KaTeX_Size1-Regular.otf", .size1);
        try r.addRequired("fixtures/fonts/katex/KaTeX_Size2-Regular.otf", .size2);
        return r;
    }

    /// Single-file host (system fallback, custom fonts): the one
    /// face answers every chain position that names its role.
    fn loadFrom(path: []const u8, role: fontstack.Role) !Ref {
        var r = Ref{};
        errdefer r.free();
        try r.addRequired(path, role);
        return r;
    }

    fn addRequired(self: *Ref, path: []const u8, role: fontstack.Role) !void {
        const bytes = try readFile(path);
        errdefer std.testing.allocator.free(bytes);
        try self.stack.addFile(role, bytes);
        self.bufs[self.nbufs] = bytes;
        self.nbufs += 1;
    }

    fn addOptional(self: *Ref, path: []const u8, role: fontstack.Role) !void {
        return self.addRequired(path, role);
    }

    fn readFile(path: []const u8) ![]u8 {
        var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
        defer threaded.deinit();
        return std.Io.Dir.cwd().readFileAlloc(
            threaded.io(),
            path,
            std.testing.allocator,
            .limited(4 * 1024 * 1024),
        );
    }

    fn free(self: *Ref) void {
        for (self.bufs[0..self.nbufs]) |b| std.testing.allocator.free(b);
        self.nbufs = 0;
    }

    fn provider(self: *Ref) contract.MetricsProvider {
        return self.stack.provider();
    }
};

/// First loadable font in `paths` (single-face host), or null when
/// none load. Unloadable entries are skipped, never fatal — this is
/// what makes the fallback chain total on machines without any
/// candidate installed.
fn loadFirst(paths: []const []const u8, role: fontstack.Role) ?Ref {
    for (paths) |p| {
        if (Ref.loadFrom(p, role)) |r| return r else |_| continue;
    }
    return null;
}

/// Vendored stack first, system font second (issue 8 fallback path).
/// Hosts without the fixture checkout (like `read`) use the same
/// order: bundled-or-vendored first, OS font second.
fn loadWithFallback() !Ref {
    if (Ref.load()) |r| return r else |_| {}
    if (loadFirst(&system_candidates, .stix)) |r| return r;
    return error.FileNotFound;
}

// Every codepoint the core can emit must resolve in the reference
// stack (issue 8 acceptance probe, issue #92: the 29 codepoints LM
// Math 1.959 lacked now resolve through the KaTeX faces). All misses
// print before failing; the vendored set suffices with no system
// font, so the probe is deterministic on every machine.
test "coverage: every emittable glyph resolves" {
    var ref = try Ref.load();
    defer ref.free();
    var misses: usize = 0;
    // Distinct commands can share a codepoint (`\\varsubsetneqq` is
    // `\\subsetneqq`'s alias twin, issue #73): count each codepoint
    // once so the report stays exact.
    var seen: [64]u21 = undefined;
    var nseen: usize = 0;
    const miss = struct {
        fn m(cp: u21, bad_out: *usize, seen_out: *[64]u21, nseen_out: *usize) void {
            for (seen_out.*[0..nseen_out.*]) |s| if (s == cp) return;
            if (nseen_out.* < seen_out.len) {
                seen_out.*[nseen_out.*] = cp;
                nseen_out.* += 1;
            }
            std.debug.print("unresolved U+{X}\n", .{cp});
            bad_out.* += 1;
        }
    }.m;
    // The rm chain (LM + Main + AMS + STIX) is the broadest vendored
    // chain: anything emittable resolves through it.
    const rm: u16 = 0;
    for (symbols.all_symbols) |e| {
        if (e.sym.func) continue; // word operators are ASCII letters
        if (ref.stack.glyphIdFor(rm, e.sym.cp) == 0) miss(e.sym.cp, &misses, &seen, &nseen);
    }
    for (symbols.all_delims) |d| {
        if (ref.stack.glyphIdFor(rm, d.cp) == 0) miss(d.cp, &misses, &seen, &nseen);
    }
    for (symbols.all_accents) |a| {
        if (ref.stack.glyphIdFor(rm, a.cp) == 0) miss(a.cp, &misses, &seen, &nseen);
    }
    for (symbols.all_math_text_accents) |a| {
        if (ref.stack.glyphIdFor(rm, a.cp) == 0) miss(a.cp, &misses, &seen, &nseen);
    }
    // Bare fence chars, rule/radical signs, arrows, text precomposes.
    const extra = [_]u21{
        '(',  ')',  '[',  ']',  '{',  '}',  '|',  '/',  '<',  '>',
        0x005C, 0x221A, 0x23DE, 0x23DF, 0x2190, 0x2192, 0x2194, ' ',
        0x00E1, 0x00E9, 0x00F1, 0x00E7, 0x010D, 0x00E4, 0x00FC,
    };
    for (extra) |cp| {
        if (ref.stack.glyphIdFor(rm, cp) == 0) miss(cp, &misses, &seen, &nseen);
    }
    var c: u21 = '0';
    while (c <= '9') : (c += 1) {
        if (ref.stack.glyphIdFor(rm, c) == 0) miss(c, &misses, &seen, &nseen);
    }
    c = 'a';
    while (c <= 'z') : (c += 1) {
        if (ref.stack.glyphIdFor(rm, c) == 0) miss(c, &misses, &seen, &nseen);
    }
    c = 'A';
    while (c <= 'Z') : (c += 1) {
        if (ref.stack.glyphIdFor(rm, c) == 0) miss(c, &misses, &seen, &nseen);
    }
    try std.testing.expectEqual(@as(usize, 0), misses);
}

// Same input + same font = byte-identical layout.
test "determinism: repeated layout is byte-identical" {
    var ref = try Ref.load();
    defer ref.free();
    const src = "\\sum_{i=1}^{n}\\frac{i}{\\sqrt{i+1}}\\quad\\hat{\\xi}\\in\\mathbb{R}";
    var runs_a: [64]zatex.ir.Run = undefined;
    var rules_a: [16]zatex.ir.Rule = undefined;
    var glyphs_a: [512]u16 = undefined;
    var runs_b: [64]zatex.ir.Run = undefined;
    var rules_b: [16]zatex.ir.Rule = undefined;
    var glyphs_b: [512]u16 = undefined;
    const a = try zatex.layoutFull(src, .{ .display_mode = true }, ref.provider(), &runs_a, &rules_a, &glyphs_a);
    const b = try zatex.layoutFull(src, .{ .display_mode = true }, ref.provider(), &runs_b, &rules_b, &glyphs_b);
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.height_above, b.height_above);
    try std.testing.expectEqual(a.depth_below, b.depth_below);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    try std.testing.expectEqual(a.rules.len, b.rules.len);
    for (a.runs, b.runs) |x, y| {
        try std.testing.expectEqual(x.font_id, y.font_id);
        try std.testing.expectEqual(x.size_units, y.size_units);
        try std.testing.expectEqual(x.x, y.x);
        try std.testing.expectEqual(x.baseline_y, y.baseline_y);
        try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
    }
    for (a.rules, b.rules) |x, y| try std.testing.expectEqual(x, y);
    try std.testing.expect(a.width > 0 and a.rules.len > 0);
}

// Font-backed end-to-end smoke: tall fences grow through variants.
test "reference: scaled fences use taller variants" {
    var ref = try Ref.load();
    defer ref.free();
    var runs_t: [64]zatex.ir.Run = undefined;
    var rules_t: [16]zatex.ir.Rule = undefined;
    var glyphs_t: [512]u16 = undefined;
    var runs_f: [64]zatex.ir.Run = undefined;
    var rules_f: [16]zatex.ir.Rule = undefined;
    var glyphs_f: [512]u16 = undefined;
    const tall = try zatex.layoutFull(
        "\\left(\\frac{\\frac{a}{b}}{\\frac{c}{d}}\\right)",
        .{},
        ref.provider(),
        &runs_t,
        &rules_t,
        &glyphs_t,
    );
    const flat = try zatex.layoutFull("(x)", .{}, ref.provider(), &runs_f, &rules_f, &glyphs_f);
    try std.testing.expect(tall.height_above + tall.depth_below > flat.height_above + flat.depth_below);
    // The grown left paren is a .v-series variant, not base gid 9:
    // the first emitted run is the left fence.
    try std.testing.expect(tall.runs.len > 0 and tall.runs[0].glyphs.len > 0);
    try std.testing.expect(tall.runs[0].glyphs[0] != 9);
    try std.testing.expect(tall.width > flat.width);
}

// Host metrics conformance (issue #194): the reference provider
// passes the shipped check cleanly, and each of the three
// historical provider bugs fails with a named diagnostic when
// reintroduced — natively and through the C entry point.
test "conform: reference provider passes cleanly at font 0" {
    var ref = try Ref.load();
    defer ref.free();
    var buf: [4096]u8 = undefined;
    const res = zatex.conform.check(ref.provider(), 0, &buf);
    try std.testing.expectEqual(@as(usize, 0), res.diagnostics);
}

test "conform: NULL italic hook on the reference fails named" {
    var ref = try Ref.load();
    defer ref.free();
    var prov = ref.provider();
    prov.italicCorrection = null;
    var buf: [4096]u8 = undefined;
    const res = zatex.conform.check(prov, 0, &buf);
    try std.testing.expect(res.diagnostics > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..res.bytes], "italic hook: NULL") != null);
}

test "conform: 500-for-zero advances on the reference fail named" {
    var ref = try Ref.load();
    defer ref.free();
    const W = struct {
        inner: zatex.MetricsProvider,
        fn adv(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            const v = s.inner.advance(s.inner.ctx, font, glyph);
            return if (v == 0) 500 else v;
        }
        fn gid(ctx: *const anyopaque, font: u16, cp: u21) u16 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            return s.inner.glyphId(s.inner.ctx, font, cp);
        }
        fn rule(ctx: *const anyopaque, font: u16, kind: zatex.RuleKind) i32 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            return s.inner.ruleThickness(s.inner.ctx, font, kind);
        }
        fn variant(ctx: *const anyopaque, font: u16, glyph: u16, min_height: i32) u16 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            const f = s.inner.glyphVariant orelse return glyph;
            return f(s.inner.ctx, font, glyph, min_height);
        }
        fn italic(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            const f = s.inner.italicCorrection orelse return 0;
            return f(s.inner.ctx, font, glyph);
        }
        fn kern(ctx: *const anyopaque, font: u16, glyph: u16, height: i32, corner: zatex.contract.KernCorner) i32 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            const f = s.inner.kernCorrection orelse return 0;
            return f(s.inner.ctx, font, glyph, height, corner);
        }
        fn ext(ctx: *const anyopaque, font: u16, glyph: u16) [2]i32 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            const f = s.inner.extents orelse return .{ 700, 250 };
            return f(s.inner.ctx, font, glyph);
        }
        fn ink(ctx: *const anyopaque, font: u16, glyph: u16) [4]i32 {
            const s: *const @This() = @ptrCast(@alignCast(ctx));
            const f = s.inner.inkBounds orelse return .{ 0, 0, 0, 0 };
            return f(s.inner.ctx, font, glyph);
        }
    };
    var w = W{ .inner = ref.provider() };
    const prov = zatex.MetricsProvider{
        .ctx = &w,
        .glyphId = W.gid,
        .advance = W.adv,
        .ruleThickness = W.rule,
        .glyphVariant = W.variant,
        .italicCorrection = W.italic,
        .kernCorrection = W.kern,
        .extents = W.ext,
        .inkBounds = W.ink,
    };
    var buf: [4096]u8 = undefined;
    const res = zatex.conform.check(prov, 0, &buf);
    try std.testing.expect(res.diagnostics > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..res.bytes], "advance U+20D7: got 500, want 0") != null);
}

test "conform: NULL ink hook on the reference fails named" {
    var ref = try Ref.load();
    defer ref.free();
    var prov = ref.provider();
    prov.inkBounds = null;
    var buf: [4096]u8 = undefined;
    const res = zatex.conform.check(prov, 0, &buf);
    try std.testing.expect(res.diagnostics > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..res.bytes], "ink hook: NULL") != null);
}

// C ABI surface for the conformance check: mirrors zatex.h plus
// cabi.zig `CMetrics` field-for-field (the passing run below proves
// the mirror at runtime — a drifted mirror reads garbage and fails).
const CExtents = extern struct {
    ha: i32,
    db: i32,
};
const CInkBox = extern struct {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
};
const CMetrics = extern struct {
    ctx: ?*const anyopaque,
    glyph_id: ?*const fn (?*const anyopaque, u16, u32) callconv(.c) u16,
    advance: ?*const fn (?*const anyopaque, u16, u16) callconv(.c) i32,
    rule_thickness: ?*const fn (?*const anyopaque, u16, u32) callconv(.c) i32,
    glyph_variant: ?*const fn (?*const anyopaque, u16, u16, i32) callconv(.c) u16 = null,
    italic_correction: ?*const fn (?*const anyopaque, u16, u16) callconv(.c) i32 = null,
    kern_correction: ?*const fn (?*const anyopaque, u16, u16, i32, u32) callconv(.c) i32 = null,
    extents: ?*const fn (?*const anyopaque, u16, u16) callconv(.c) CExtents = null,
    ink_bounds: ?*const fn (?*const anyopaque, u16, u16) callconv(.c) CInkBox = null,
};

extern fn zatex_conform_metrics(metrics: ?*const CMetrics, font: u16, buf: ?[*]u8, cap: usize) i32;

const CWrap = struct {
    fn gid(ctx: ?*const anyopaque, font: u16, cp: u32) callconv(.c) u16 {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        return st.glyphIdFor(font, @intCast(cp));
    }
    fn adv(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32 {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        _ = font;
        return st.advance1000(glyph);
    }
    fn rule(ctx: ?*const anyopaque, font: u16, kind: u32) callconv(.c) i32 {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        _ = font;
        return st.ruleFor(@enumFromInt(kind));
    }
    fn variant(ctx: ?*const anyopaque, font: u16, glyph: u16, min_height: i32) callconv(.c) u16 {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        _ = font;
        return st.variantFor(glyph, min_height);
    }
    fn italic(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) i32 {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        _ = font;
        return st.italicFor(glyph);
    }
    fn kern(ctx: ?*const anyopaque, font: u16, glyph: u16, height: i32, corner: u32) callconv(.c) i32 {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        _ = font;
        return st.kernFor(glyph, height, @enumFromInt(corner));
    }
    fn ext(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) CExtents {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        const e = st.extentsFor();
        _ = font;
        _ = glyph;
        return .{ .ha = e[0], .db = e[1] };
    }
    fn ink(ctx: ?*const anyopaque, font: u16, glyph: u16) callconv(.c) CInkBox {
        const st: *const fontstack.Stack = @ptrCast(@alignCast(ctx.?));
        const b = st.inkFor(glyph);
        _ = font;
        return .{ .x0 = b[0], .y0 = b[1], .x1 = b[2], .y1 = b[3] };
    }
};

fn cMetricsFor(stack: *const fontstack.Stack) CMetrics {
    return .{
        .ctx = @ptrCast(stack),
        .glyph_id = CWrap.gid,
        .advance = CWrap.adv,
        .rule_thickness = CWrap.rule,
        .glyph_variant = CWrap.variant,
        .italic_correction = CWrap.italic,
        .kern_correction = CWrap.kern,
        .extents = CWrap.ext,
        .ink_bounds = CWrap.ink,
    };
}

fn cText(buf: []u8) []u8 {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) : (len += 1) {}
    return buf[0..len];
}

test "conform C entry: real provider passes with no rebuild or render" {
    var ref = try Ref.load();
    defer ref.free();
    var m = cMetricsFor(&ref.stack);
    var buf: [2048]u8 = undefined;
    @memset(&buf, 0xAA);
    const n = zatex_conform_metrics(&m, 0, &buf, buf.len);
    try std.testing.expectEqual(@as(i32, 0), n);
    try std.testing.expectEqual(@as(usize, 0), cText(&buf).len);
}

test "conform C entry: null hooks fail named" {
    var ref = try Ref.load();
    defer ref.free();
    var buf: [2048]u8 = undefined;

    var no_italic = cMetricsFor(&ref.stack);
    no_italic.italic_correction = null;
    try std.testing.expect(zatex_conform_metrics(&no_italic, 0, &buf, buf.len) > 0);
    try std.testing.expect(std.mem.indexOf(u8, cText(&buf), "italic hook: NULL (want MATH corrections)") != null);

    var no_advance = cMetricsFor(&ref.stack);
    no_advance.advance = null;
    try std.testing.expect(zatex_conform_metrics(&no_advance, 0, &buf, buf.len) > 0);
    try std.testing.expect(std.mem.indexOf(u8, cText(&buf), "advance U+20D7: got 500, want 0") != null);

    var no_ink = cMetricsFor(&ref.stack);
    no_ink.ink_bounds = null;
    try std.testing.expect(zatex_conform_metrics(&no_ink, 0, &buf, buf.len) > 0);
    try std.testing.expect(std.mem.indexOf(u8, cText(&buf), "ink hook: NULL") != null);
}

test "conform C entry: usage errors and dry runs" {
    var ref = try Ref.load();
    defer ref.free();
    var m = cMetricsFor(&ref.stack);
    var buf: [2048]u8 = undefined;
    try std.testing.expectEqual(@as(i32, -1), zatex_conform_metrics(null, 0, &buf, buf.len));
    try std.testing.expectEqual(@as(i32, -1), zatex_conform_metrics(&m, 0, &buf, 0));
    // Null buffer counts without writing.
    try std.testing.expectEqual(@as(i32, 0), zatex_conform_metrics(&m, 0, null, 0));
    var no_ink = cMetricsFor(&ref.stack);
    no_ink.ink_bounds = null;
    try std.testing.expect(zatex_conform_metrics(&no_ink, 0, null, 0) > 0);
}

// Fallback order is total: unloadable paths skip, the vendored fixture
// resolves through the same entry point hosts use.
test "fallback: unloadable paths skip, fixture resolves" {
    const bogus = [_][]const u8{"/nonexistent/zatex-font.otf"};
    try std.testing.expect(loadFirst(&bogus, .stix) == null);
    var ref = try loadWithFallback();
    defer ref.free();
    try std.testing.expect(ref.stack.upm() > 0);
}

// System STIX Two Math drives the full provider when the OS ships it
// (macOS Supplemental fonts); skips cleanly where it is absent.
test "fallback: system font lays out deterministically when present" {
    var sys = loadFirst(&system_candidates, .stix) orelse {
        std.debug.print("note: no system math font installed; probe skipped\n", .{});
        return;
    };
    defer sys.free();
    try std.testing.expect(sys.stack.upm() > 0);
    _ = try otmath.constant(sys.stack.faces[0].font, .frac_rule);
    try std.testing.expect(try otmath.glyphId(sys.stack.faces[0].font, '(') != 0);
    try std.testing.expect(try otmath.glyphId(sys.stack.faces[0].font, 0x2211) != 0); // summation
    try std.testing.expect(try otmath.glyphId(sys.stack.faces[0].font, 0x03B1) != 0); // alpha
    const src = "\\sum_{i=1}^{n}\\frac{i}{i+1}";
    var runs_a: [32]zatex.ir.Run = undefined;
    var rules_a: [8]zatex.ir.Rule = undefined;
    var glyphs_a: [256]u16 = undefined;
    var runs_b: [32]zatex.ir.Run = undefined;
    var rules_b: [8]zatex.ir.Rule = undefined;
    var glyphs_b: [256]u16 = undefined;
    const a = try zatex.layoutFull(src, .{ .display_mode = true }, sys.provider(), &runs_a, &rules_a, &glyphs_a);
    const b = try zatex.layoutFull(src, .{ .display_mode = true }, sys.provider(), &runs_b, &rules_b, &glyphs_b);
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    try std.testing.expect(a.width > 0 and a.rules.len > 0);
}

// Math-mode textords (`\S`, `\aa`, ...) lay out via the symbol table,
// and text-mode-only commands (`\i`, `\textdollar`, ...) lay out inside
// `\text` (KaTeX parity, pinned-proven per mode).
test "reference: textord nationals lay out" {
    var ref = try Ref.load();
    defer ref.free();
    const formulas = [_][]const u8{
        "\\S \\P \\sect \\aa \\AA",
        "\\text{\\i \\j \\o \\O \\ae \\AE \\ss \\oe \\OE}",
        "\\text{\\S \\P \\sect \\aa}",
        "\\text{\\textdollar \\textsterling \\textdegree \\textellipsis}",
        "\\text{\\textendash \\textemdash \\textbackslash \\textbar}",
    };
    for (formulas) |src| {
        var runs: [16]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [64]u16 = undefined;
        const l = try zatex.layoutFull(src, .{}, ref.provider(), &runs, &rules, &glyphs);
        try std.testing.expect(l.width > 0 and l.runs.len > 0);
    }
}

// Row stacks must land inside the ink box: every run baseline and
// rule rect stays within [0, height_above + depth_below]. Guards the
// table-baseline dy convention in the array/substack emitters.
test "reference: array rows stay inside the ink box" {
    var ref = try Ref.load();
    defer ref.free();
    const formulas = [_][]const u8{
        "\\begin{matrix} a & b \\\\ c & d \\end{matrix}",
        "f(x) = \\begin{cases} 1 & x > 0 \\\\ 0 & x = 0 \\end{cases}",
        "\\begin{array}{c} a \\\\ \\hline \\\\ b \\end{array}",
        "\\sum_{\\substack{a \\\\ b}} x",
    };
    for (formulas) |src| {
        var runs: [64]zatex.ir.Run = undefined;
        var rules: [16]zatex.ir.Rule = undefined;
        var glyphs: [512]u16 = undefined;
        const l = try zatex.layoutFull(src, .{ .display_mode = true }, ref.provider(), &runs, &rules, &glyphs);
        const total: i64 = @as(i64, l.height_above) + @as(i64, l.depth_below);
        try std.testing.expect(total > 0 and l.runs.len > 0);
        for (l.runs) |r| {
            try std.testing.expect(r.baseline_y >= 0 and r.baseline_y <= total);
        }
        for (l.rules) |r| {
            try std.testing.expect(r.y >= 0 and @as(i64, r.y) + @as(i64, r.h) <= total);
        }
    }
}

// ---------------------------------------------------------------------------
// Metamorphic + determinism probes on IR text (issue #24). Reference-free:
// no goldens, no pixels — relations between layouts of related inputs,
// plus byte-level re-layout identity through `invariants.layoutText`.
// ---------------------------------------------------------------------------

// `\color{...}{X}` changes no geometry: identical IR to `X` (also the
// basis for the #27 style-scoping tests and the #23 fuzzer oracles).
test "metamorphic: color is geometry-transparent" {
    var ref = try Ref.load();
    defer ref.free();
    const cases = [_][]const u8{
        "x+y",
        "a=b",
        "\\frac{a}{b}",
        "x^2_1",
        "\\sum_{i=1}^n i",
    };
    for (cases) |src| {
        var cbuf: [256]u8 = undefined;
        const colored = try std.fmt.bufPrint(&cbuf, "\\color{{red}}{{{s}}}", .{src});
        for ([_]bool{ false, true }) |display| {
            var ra: [64]zatex.ir.Run = undefined;
            var la: [16]zatex.ir.Rule = undefined;
            var ga: [512]u16 = undefined;
            var rb: [64]zatex.ir.Run = undefined;
            var lb: [16]zatex.ir.Rule = undefined;
            var gb: [512]u16 = undefined;
            const a = try layoutCase(&ref, src, display, &ra, &la, &ga);
            const b = try layoutCase(&ref, colored, display, &rb, &lb, &gb);
            // Paint is not geometry (issue #35 threads `\color` onto
            // runs/rules): compare the footprint, not the paint.
            try std.testing.expectEqual(a.width, b.width);
            try std.testing.expectEqual(a.height_above, b.height_above);
            try std.testing.expectEqual(a.depth_below, b.depth_below);
            try std.testing.expectEqual(a.runs.len, b.runs.len);
            try std.testing.expectEqual(a.rules.len, b.rules.len);
        }
    }
}

// `\phantom{A}` keeps A's box while emitting nothing: same footprint.
test "metamorphic: phantom preserves the footprint" {
    var ref = try Ref.load();
    defer ref.free();
    const pairs = [_][2][]const u8{
        .{ "\\phantom{x}+y", "x+y" },
        .{ "\\phantom{\\frac{a}{b}}+y", "\\frac{a}{b}+y" },
    };
    for (pairs) |p| {
        for ([_]bool{ false, true }) |display| {
            var ra: [64]zatex.ir.Run = undefined;
            var la: [16]zatex.ir.Rule = undefined;
            var ga: [512]u16 = undefined;
            var rb: [64]zatex.ir.Run = undefined;
            var lb: [16]zatex.ir.Rule = undefined;
            var gb: [512]u16 = undefined;
            const a = try layoutCase(&ref, p[0], display, &ra, &la, &ga);
            const b = try layoutCase(&ref, p[1], display, &rb, &lb, &gb);
            try std.testing.expectEqual(b.width, a.width);
            try std.testing.expectEqual(b.height_above, a.height_above);
            try std.testing.expectEqual(b.depth_below, a.depth_below);
        }
    }
}

// Bare, grouped, and empty-group-terminated atoms are one box.
test "metamorphic: x vs {x} vs x{} are byte-identical" {
    var ref = try Ref.load();
    defer ref.free();
    for ([_]bool{ false, true }) |display| {
        var r0: [16]zatex.ir.Run = undefined;
        var l0: [4]zatex.ir.Rule = undefined;
        var g0: [64]u16 = undefined;
        var r1: [16]zatex.ir.Run = undefined;
        var l1: [4]zatex.ir.Rule = undefined;
        var g1: [64]u16 = undefined;
        var r2: [16]zatex.ir.Run = undefined;
        var l2: [4]zatex.ir.Rule = undefined;
        var g2: [64]u16 = undefined;
        const a = try layoutCase(&ref, "x", display, &r0, &l0, &g0);
        const b = try layoutCase(&ref, "{x}", display, &r1, &l1, &g1);
        const c = try layoutCase(&ref, "x{}", display, &r2, &l2, &g2);
        try inv.expectSameLayout(a, b);
        try inv.expectSameLayout(a, c);
    }
}

// Surd clearance: KaTeX parity, pinned 0.18.7 `sqrt.js` (TeXbook
// Rule 11). In text style the clearance above the radicand is
// theta + theta/4 and the vinculum is the radical rule (integer
// units from the live provider); an oversized radical only ever
// grows the clearance, so the minimum stands. Inners with sups sit
// up to 30mu lower because the radicand is cramped (TeX).
test "metamorphic: sqrt clears its radicand" {
    var ref = try Ref.load();
    defer ref.free();
    const prov = ref.provider();
    const th = prov.ruleThickness(prov.ctx, 0, .fraction_bar);
    const rw = prov.ruleThickness(prov.ctx, 0, .radical);
    try std.testing.expect(th > 0);
    try std.testing.expect(rw > 0);
    for ([_][]const u8{ "x", "\\frac{a}{b}", "x^2" }) |inner| {
        var cbuf: [128]u8 = undefined;
        const src = try std.fmt.bufPrint(&cbuf, "\\sqrt{{{s}}}", .{inner});
        var ra: [64]zatex.ir.Run = undefined;
        var la: [16]zatex.ir.Rule = undefined;
        var ga: [512]u16 = undefined;
        var rb: [64]zatex.ir.Run = undefined;
        var lb: [16]zatex.ir.Rule = undefined;
        var gb: [512]u16 = undefined;
        const a = try layoutCase(&ref, inner, false, &ra, &la, &ga);
        const b = try layoutCase(&ref, src, false, &rb, &lb, &gb);
        // Exactly one added rule: the radical bar (the inner frac
        // keeps its own bar).
        try std.testing.expectEqual(a.rules.len + 1, b.rules.len);
        const want: i64 = @as(i64, a.height_above) + @as(i64, th) + @divTrunc(@as(i64, th), 4) + @as(i64, rw) - 30;
        try std.testing.expect(@as(i64, b.height_above) >= want);
        try std.testing.expect(b.depth_below >= a.depth_below);
        try std.testing.expect(b.width > a.width);
    }
}

// Fraction clearance: numerator and denominator clear the bar.
test "metamorphic: frac clears numerator and denominator" {
    var ref = try Ref.load();
    defer ref.free();
    var rn: [16]zatex.ir.Run = undefined;
    var ln: [4]zatex.ir.Rule = undefined;
    var gn: [64]u16 = undefined;
    var rd: [16]zatex.ir.Run = undefined;
    var ld: [4]zatex.ir.Rule = undefined;
    var gd: [64]u16 = undefined;
    var rf: [64]zatex.ir.Run = undefined;
    var lf: [16]zatex.ir.Rule = undefined;
    var gf: [512]u16 = undefined;
    const n = try layoutCase(&ref, "a+1", false, &rn, &ln, &gn);
    const d = try layoutCase(&ref, "b-2", false, &rd, &ld, &gd);
    const f = try layoutCase(&ref, "\\frac{a+1}{b-2}", false, &rf, &lf, &gf);
    try std.testing.expectEqual(@as(usize, 1), f.rules.len);
    try std.testing.expect(f.rules[0].h > 0);
    const nt: i64 = @as(i64, n.height_above) + @as(i64, n.depth_below);
    const dt: i64 = @as(i64, d.height_above) + @as(i64, d.depth_below);
    const ft: i64 = @as(i64, f.height_above) + @as(i64, f.depth_below);
    // KaTeX-true bound (issue #32): fraction content is set one style
    // smaller (x0.7), so the total covers script-scaled content plus
    // the bar — never full-size content. Pinned KaTeX 0.18.7 totals
    // 1.2484em for this fraction vs nt+dt+rule = 1.6511em, so the old
    // bound encoded the pre-fix over-spacing.
    try std.testing.expect(ft * 10 >= 7 * (nt + dt) + @as(i64, f.rules[0].h) * 10);
    try inv.expectNonNegative(f);
    try inv.expectContained(f);
}

// ---------------------------------------------------------------------------
// OpenType MATH calibration probes (issue #26). Integer units only;
// KaTeX-structural agreement is guarded by the parity sweep, while
// metrics-sensitive widths are pinned here against the real font.
// ---------------------------------------------------------------------------

// Real-font kern reads zero (no MathKern table in Latin Modern Math),
// so canned-zero and live-zero providers agree byte-for-byte.
test "calibration: absent kern table reads graceful zeros" {
    var ref = try Ref.load();
    defer ref.free();
    ref.stack.kern_caps = .{ .sup = 0, .sub = 0 };
    var r0: [64]zatex.ir.Run = undefined;
    var l0: [16]zatex.ir.Rule = undefined;
    var g0: [512]u16 = undefined;
    const canned = try layoutCase(&ref, "x^2_1", false, &r0, &l0, &g0);
    ref.stack.kern_caps = null;
    var r1: [64]zatex.ir.Run = undefined;
    var l1: [16]zatex.ir.Rule = undefined;
    var g1: [512]u16 = undefined;
    const live = try layoutCase(&ref, "x^2_1", false, &r1, &l1, &g1);
    try inv.expectSameLayout(canned, live);
}

// Canned cut-ins tuck scripts by exact integers: TR answers sups,
// BR answers subs. Deltas are collected per run so no run-order
// assumption sneaks in.
test "calibration: kern cut-ins tuck sup/sub exactly" {
    var ref = try Ref.load();
    defer ref.free();
    const cases = [_]struct { src: []const u8, want: [2]i32 }{
        .{ .src = "x^2_1", .want = .{ 40, 20 } },
        .{ .src = "x^2", .want = .{ 40, 0 } },
        .{ .src = "x_1", .want = .{ 20, 0 } },
    };
    for (cases) |c| {
        ref.stack.kern_caps = .{ .sup = 40, .sub = 20 };
        var ra: [64]zatex.ir.Run = undefined;
        var la: [16]zatex.ir.Rule = undefined;
        var ga: [512]u16 = undefined;
        const a = try layoutCase(&ref, c.src, false, &ra, &la, &ga);
        ref.stack.kern_caps = null;
        var rb: [64]zatex.ir.Run = undefined;
        var lb: [16]zatex.ir.Rule = undefined;
        var gb: [512]u16 = undefined;
        const b = try layoutCase(&ref, c.src, false, &rb, &lb, &gb);
        try std.testing.expectEqual(a.runs.len, b.runs.len);
        var got = [_]i32{ 0, 0 };
        var n: usize = 0;
        for (a.runs, b.runs) |x, y| {
            try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
            try std.testing.expectEqual(x.baseline_y, y.baseline_y);
            const dx = y.x - x.x;
            try std.testing.expect(dx >= 0);
            if (dx > 0) {
                try std.testing.expect(n < got.len);
                got[n] = dx;
                n += 1;
            }
        }
        // Order-free compare of the (up-to-two) deltas.
        var matched = [_]bool{ false, false };
        var want_n: usize = 0;
        for (c.want) |w| if (w > 0) {
            want_n += 1;
        };
        try std.testing.expectEqual(want_n, n);
        for (got[0..n]) |d| {
            var hit = false;
            for (c.want, 0..) |w, k| {
                if (!matched[k] and w == d) {
                    matched[k] = true;
                    hit = true;
                    break;
                }
            }
            try std.testing.expect(hit);
        }
    }
}

// Clamp policy: cut-ins saturate at the script gap and floor at zero,
// so hostile hooks can neither overlap scripts nor push them outward.
test "calibration: cut-ins clamp to the script gap" {
    var ref = try Ref.load();
    defer ref.free();
    ref.stack.kern_caps = .{ .sup = 1000, .sub = 1000 };
    var ra: [64]zatex.ir.Run = undefined;
    var la: [16]zatex.ir.Rule = undefined;
    var ga: [512]u16 = undefined;
    const big = try layoutCase(&ref, "x^2_1", false, &ra, &la, &ga);
    ref.stack.kern_caps = .{ .sup = -50, .sub = -50 };
    var rb: [64]zatex.ir.Run = undefined;
    var lb: [16]zatex.ir.Rule = undefined;
    var gb: [512]u16 = undefined;
    const neg = try layoutCase(&ref, "x^2_1", false, &rb, &lb, &gb);
    ref.stack.kern_caps = null;
    var rc: [64]zatex.ir.Run = undefined;
    var lc: [16]zatex.ir.Rule = undefined;
    var gc: [512]u16 = undefined;
    const plain = try layoutCase(&ref, "x^2_1", false, &rc, &lc, &gc);
    try std.testing.expectEqual(big.runs.len, plain.runs.len);
    var saw_gap = false;
    for (big.runs, plain.runs) |x, y| {
        const dx = y.x - x.x;
        // Inline script gap is 60mu: huge cut-ins saturate there.
        try std.testing.expect(dx == 0 or dx == 60);
        if (dx == 60) saw_gap = true;
    }
    try std.testing.expect(saw_gap);
    try inv.expectSameLayout(neg, plain);
}

// Italic-correction application: the accent over an italic nucleus
// shifts by half the correction of the LAID-OUT math glyph (issue
// #70: `y` is U+1D466 with correction 28, so 28/2 = 14 at text size;
// the old lookup saw text `y` with 8). The KaTeX table skew (56 for
// `y`) rides along in both runs, so only the correction half moves.
test "calibration: italic correction centers accents" {
    var ref = try Ref.load();
    defer ref.free();
    var ra: [32]zatex.ir.Run = undefined;
    var la: [8]zatex.ir.Rule = undefined;
    var ga: [128]u16 = undefined;
    const a = try layoutCase(&ref, "\\hat{y}", false, &ra, &la, &ga);
    ref.stack.no_italic = true;
    var rb: [32]zatex.ir.Run = undefined;
    var lb: [8]zatex.ir.Rule = undefined;
    var gb: [128]u16 = undefined;
    const b = try layoutCase(&ref, "\\hat{y}", false, &rb, &lb, &gb);
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    var shifts: usize = 0;
    for (a.runs, b.runs) |x, y| {
        try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
        const dx = y.x - x.x;
        if (dx != 0) {
            try std.testing.expectEqual(@as(i32, -14), dx);
            shifts += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), shifts);
}

// Layout-box vs ink-box split: advances drive widths, extents drive
// heights. Doubling extents doubles the ink height; widths don't move.
test "calibration: extents drive heights, advances drive widths" {
    var ref = try Ref.load();
    defer ref.free();
    var ra: [16]zatex.ir.Run = undefined;
    var la: [4]zatex.ir.Rule = undefined;
    var ga: [64]u16 = undefined;
    const a = try layoutCase(&ref, "x", false, &ra, &la, &ga);
    try std.testing.expectEqual(@as(u32, 700), a.height_above);
    try std.testing.expectEqual(@as(u32, 250), a.depth_below);
    ref.stack.extents_mul = 2;
    var rb: [16]zatex.ir.Run = undefined;
    var lb: [4]zatex.ir.Rule = undefined;
    var gb: [64]u16 = undefined;
    const b = try layoutCase(&ref, "x", false, &rb, &lb, &gb);
    try std.testing.expectEqual(@as(u32, 1400), b.height_above);
    try std.testing.expectEqual(@as(u32, 500), b.depth_below);
    try std.testing.expectEqual(a.width, b.width);
}

// Stretchy fences select taller variants through the provider.
test "calibration: tall braces use brace variants" {
    var ref = try Ref.load();
    defer ref.free();
    const brace = ref.stack.glyphIdFor(0, '{');
    try std.testing.expectEqual(@as(u16, 92), brace);
    var runs: [64]zatex.ir.Run = undefined;
    var rules: [16]zatex.ir.Rule = undefined;
    var glyphs: [512]u16 = undefined;
    const tall = try layoutCase(
        &ref,
        "\\left\\{\\frac{\\frac{a}{b}}{\\frac{c}{d}}\\right\\}",
        false,
        &runs,
        &rules,
        &glyphs,
    );
    try std.testing.expect(tall.runs.len > 0 and tall.runs[0].glyphs.len > 0);
    try std.testing.expect(tall.runs[0].glyphs[0] != brace);
}

// Re-layout of the same input + metrics is identical IR text.
test "determinism: IR text is stable across re-layouts" {
    var ref = try Ref.load();
    defer ref.free();
    const cases = [_][]const u8{
        "x",
        "\\sum_{i=1}^{n}\\frac{i}{\\sqrt{i+1}}",
        "\\begin{matrix} a & b \\\\ c & d \\end{matrix}",
    };
    for (cases) |src| {
        for ([_]bool{ false, true }) |display| {
            var ra: [64]zatex.ir.Run = undefined;
            var la: [16]zatex.ir.Rule = undefined;
            var ga: [512]u16 = undefined;
            var rb: [64]zatex.ir.Run = undefined;
            var lb: [16]zatex.ir.Rule = undefined;
            var gb: [512]u16 = undefined;
            const a = try layoutCase(&ref, src, display, &ra, &la, &ga);
            const b = try layoutCase(&ref, src, display, &rb, &lb, &gb);
            var ta: [4096]u8 = undefined;
            var tb: [4096]u8 = undefined;
            try std.testing.expectEqualStrings(inv.layoutText(a, &ta), inv.layoutText(b, &tb));
            try inv.expectSameLayout(a, b);
        }
    }
}

test "oracle-165: blackboard-bold alphabet resolves, no gid-0 fallback" {
    // Pinned KaTeX renders `\mathbb` from real double-struck glyphs;
    // every ASCII letter/digit must resolve through the vendored
    // stack (Latin Modern Math carries the whole double-struck
    // alphabet, so no system font is involved either way).
    var ref = try Ref.load();
    defer ref.free();
    var runs: [64]zatex.ir.Run = undefined;
    var rules: [16]zatex.ir.Rule = undefined;
    var glyphs: [256]u16 = undefined;
    const lay = try layoutCase(&ref, "\\mathbb{ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789}", false, &runs, &rules, &glyphs);
    var n: usize = 0;
    for (lay.runs) |r| {
        for (r.glyphs) |g| {
            // gid 0 is the missing-glyph fallback (issue #142);
            // every bb letter must be a real LM glyph (face 0).
            try std.testing.expect(g != 0);
            const fr = ref.stack.faceOf(g) orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(@as(usize, 0), fr.index);
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 62), n);
}

test "issue196-b2: delimiter roles resolve KaTeX faces first" {
    // Owner decision (issue #196-B2): fence/delimiter roles resolve
    // KaTeX outlines first — KaTeX never sets a delimiter from a
    // Computer-Modern face (pinned 0.18.7 `delimTypeToFont`: small →
    // Main-Regular, large → SizeN-Regular). Small fences stay Main
    // (font 10); Rule 15e binom fences land on Size1 (font 11, KaTeX's
    // `delimsizing size1`); grown parens walk Size2 (font 12) while
    // ZaTeX need exceeds Size1 ink. stackAlways `|` and Size3-territory
    // dbinom keep the LM variant backstop; atom-role parens (B1) stay
    // rm untouched.
    var ref = try Ref.load();
    defer ref.free();
    var runs: [64]zatex.ir.Run = undefined;
    var rules: [16]zatex.ir.Rule = undefined;
    var glyphs: [512]u16 = undefined;
    // `\\binom{a}{b}` (text): both fences Size1, KaTeX-exact.
    {
        const lay = try layoutCase(&ref, "\\binom{a}{b}", false, &runs, &rules, &glyphs);
        try std.testing.expectEqual(@as(usize, 4), lay.runs.len);
        try std.testing.expectEqual(@as(u16, 11), lay.runs[0].font_id);
        try std.testing.expectEqual(@as(u16, 11), lay.runs[3].font_id);
        try std.testing.expectEqual(fontstack.Role.size1, ref.stack.roleOf(lay.runs[0].glyphs[0]).?);
        try std.testing.expectEqual(fontstack.Role.size1, ref.stack.roleOf(lay.runs[3].glyphs[0]).?);
    }
    // Small `\\left(x\\right)`: Main base covers, unchanged.
    {
        const lay = try layoutCase(&ref, "\\left(x\\right)", false, &runs, &rules, &glyphs);
        try std.testing.expectEqual(@as(u16, 10), lay.runs[0].font_id);
        try std.testing.expectEqual(@as(u16, 10), lay.runs[2].font_id);
        try std.testing.expectEqual(fontstack.Role.main, ref.stack.roleOf(lay.runs[0].glyphs[0]).?);
    }
    // Grown parens walk past Size1 to Size2 (ZaTeX need exceeds Size1
    // ink here; KaTeX's own need lands one step lower — pinned need
    // formula territory, issues #102/#200, not outlines).
    {
        const lay = try layoutCase(&ref, "\\left(\\frac{a}{b}\\right)", false, &runs, &rules, &glyphs);
        try std.testing.expectEqual(@as(u16, 12), lay.runs[0].font_id);
        try std.testing.expectEqual(@as(u16, 12), lay.runs[3].font_id);
        try std.testing.expectEqual(fontstack.Role.size2, ref.stack.roleOf(lay.runs[0].glyphs[0]).?);
    }
    // stackAlways `|` keeps the LM variant backstop (KaTeX stacks
    // Size4 pieces there; assembly is issues #102/#104).
    {
        const lay = try layoutCase(&ref, "\\left|\\frac{a}{b}\\right|", false, &runs, &rules, &glyphs);
        try std.testing.expectEqual(@as(u16, 0), lay.runs[0].font_id);
        try std.testing.expectEqual(fontstack.Role.lm, ref.stack.roleOf(lay.runs[0].glyphs[0]).?);
    }
    // `\\dbinom` display need is Size3 territory (KaTeX `delimsizing
    // size3`): unvendored, so the LM backstop stands — pinned here so
    // a future Size3 vendor fails loudly.
    {
        const lay = try layoutCase(&ref, "\\dbinom{a}{b}", true, &runs, &rules, &glyphs);
        try std.testing.expectEqual(@as(u16, 0), lay.runs[0].font_id);
        try std.testing.expectEqual(fontstack.Role.lm, ref.stack.roleOf(lay.runs[0].glyphs[0]).?);
    }
    // B1 atom-role parens stay rm: no fence path involved.
    {
        const lay = try layoutCase(&ref, "\\frac{y}{)(}", true, &runs, &rules, &glyphs);
        try std.testing.expectEqual(@as(u32, 1018), lay.width);
        var found = false;
        for (lay.runs) |r| {
            if (r.font_id == 0 and r.glyphs.len == 2) found = true;
        }
        try std.testing.expect(found);
    }
}

test "oracle-167: gathered cells are displaystyle" {
    // KaTeX's `gathered` handler styles cells `"display"` (like the
    // MathML walker already records): a display `\sum` draws from
    // the Size2 face (font id 12), never Size1 (11).
    var ref = try Ref.load();
    defer ref.free();
    var runs: [64]zatex.ir.Run = undefined;
    var rules: [16]zatex.ir.Rule = undefined;
    var glyphs: [256]u16 = undefined;
    const lay = try layoutCase(&ref, "\\begin{gathered}\\sum\\end{gathered}", false, &runs, &rules, &glyphs);
    try std.testing.expectEqual(@as(usize, 1), lay.runs.len);
    try std.testing.expectEqual(@as(u16, 12), lay.runs[0].font_id);
}
