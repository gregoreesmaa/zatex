//! Blessed file-based MetricsProvider (issue #192).
//!
//! Every native host needs the same font-file truth to feed
//! `MetricsProvider` — cmap glyph ids, hmtx advances, MATH-table
//! corrections, outline ink boxes — and each hand-rolled copy gets it
//! wrong in a new way (missing italic corrections, a 500 fallback that
//! lies for zero-width glyphs, missing ink bounds so zero-advance marks
//! cannot center by ink). This module promotes the reference hosts'
//! exact logic into the library as one blessed constructor: hand it
//! font file bytes, get a provider whose advances/italic/ink/extents
//! match the reference hosts bit-for-bit.
//!
//! This is HOST-side code (like `otmath`, `fontstack`, `cff`), never
//! linked into the layout core: the core still only sees the
//! `MetricsProvider` callback struct, and the shipped core artifact is
//! untouched. Caller-provided bytes are borrowed, never copied; all
//! queries are allocation-free and bounded (per-query outline walks
//! execute into a fixed 512-segment stack scratch, the same budget the
//! software backend measures with).
//!
//! The gid-namespace handshake (see `handshake_probes`): file gids come
//! from the font's cmap, so a host that draws through a platform shaper
//! must confirm the shaper speaks the same gid namespace before trusting
//! file metrics — else wrong glyphs render. The host recipe lives in
//! `docs/file-provider.md`.
const std = @import("std");
const zatex = @import("zatex");
const contract = zatex.contract;
const otmath = @import("otmath");
const fontstack = @import("fontstack");
const cff = @import("cff");

/// Probe codepoints for the gid-namespace handshake: ASCII letters (any
/// text font covers them), headline math (summation, alpha), and a
/// zero-width combining mark (U+20D7, the accent-centering canary).
/// Probes the file does not cover are skipped by `handshakeMatches`;
/// a file covering none of them cannot prove a namespace.
pub const handshake_probes = [_]u21{ 'A', 'x', 0x2211, 0x03B1, 0x20D7 };

pub const FileProvider = struct {
    stack: fontstack.Stack = .{},
    outlines: ?cff.CffFont = null,

    /// Borrow one font file's bytes: the single face answers every
    /// `FontId` (the stack's single-face fast path), exactly like the
    /// legacy single-file host. Fails only when the bytes are not a
    /// font at all (`otmath.load` rejects them); a font without a CFF
    /// table still loads, with ink/extents degraded (see `extentsFor`
    /// / `inkBoundsFor`).
    pub fn init(bytes: []const u8) !FileProvider {
        var fp = FileProvider{};
        try fp.stack.addFile(.lm, bytes);
        fp.outlines = cff.load(bytes) catch null;
        return fp;
    }

    pub fn upm(self: *const FileProvider) u16 {
        return self.stack.upm();
    }

    /// Standalone provider (ctx borrows the struct): glyph identity,
    /// advances, rule constants, variant/italic/kern routing from the
    /// same `fontstack` code the reference host uses, plus outline
    /// ink/extents from the same `cff` conversion the software backend
    /// draws with. Every optional hook is filled — the core always
    /// takes its ink-centering path, never the v3 fallback.
    pub fn provider(self: *FileProvider) contract.MetricsProvider {
        return .{
            .ctx = @ptrCast(self),
            .glyphId = gid,
            .advance = adv,
            .ruleThickness = rule,
            .extents = ext,
            .glyphVariant = variant,
            .italicCorrection = italic,
            .kernCorrection = kern,
            .inkBounds = ink,
        };
    }

    /// Engine gid for a codepoint in this file's namespace: the value
    /// the host compares against its shaper's gid during the handshake.
    pub fn handshakeGid(self: *const FileProvider, cp: u21) u16 {
        return self.stack.glyphIdFor(0, cp);
    }

    pub fn advance1000(self: *const FileProvider, unified: u16) i32 {
        return self.stack.advance1000(unified);
    }

    pub fn italicFor(self: *const FileProvider, unified: u16) i32 {
        return self.stack.italicFor(unified);
    }

    /// Outline ink box at 1000 units, y up, unclipped — or all zeros
    /// when the file has no CFF table or the glyph draws nothing (the
    /// core treats all-zeros as absent, exact v3 behavior).
    pub fn inkBoundsFor(self: *const FileProvider, unified: u16) [4]i32 {
        const r = self.stack.faceOf(unified) orelse return .{ 0, 0, 0, 0 };
        const cf = self.outlines orelse return .{ 0, 0, 0, 0 };
        var scratch: [512]cff.Seg = undefined;
        return cff.inkBounds1000(&cf, self.stack.faces[r.index].font.upm, r.gid, &scratch);
    }

    /// Outline extents at 1000 units — or the legacy 700/250 constant
    /// when the file has no CFF table (same fallback the core applies
    /// when the hook is null, so non-CFF fonts keep v3 geometry).
    pub fn extentsFor(self: *const FileProvider, unified: u16) [2]i32 {
        const r = self.stack.faceOf(unified) orelse return .{ 700, 250 };
        const cf = self.outlines orelse return .{ 700, 250 };
        var scratch: [512]cff.Seg = undefined;
        return cff.extents1000(&cf, self.stack.faces[r.index].font.upm, r.gid, &scratch);
    }

    fn gid(ctx: *const anyopaque, font_id: u16, cp: u21) u16 {
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.stack.glyphIdFor(font_id, cp);
    }

    fn adv(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.advance1000(glyph);
    }

    fn rule(ctx: *const anyopaque, font_id: u16, kind: contract.RuleKind) i32 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.stack.ruleFor(kind);
    }

    fn variant(ctx: *const anyopaque, font_id: u16, glyph: u16, min_height: i32) u16 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.stack.variantFor(glyph, min_height);
    }

    fn italic(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.italicFor(glyph);
    }

    fn kern(
        ctx: *const anyopaque,
        font_id: u16,
        glyph: u16,
        height: i32,
        corner: contract.KernCorner,
    ) i32 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.stack.kernFor(glyph, height, corner);
    }

    fn ext(ctx: *const anyopaque, font_id: u16, glyph: u16) [2]i32 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.extentsFor(glyph);
    }

    fn ink(ctx: *const anyopaque, font_id: u16, glyph: u16) [4]i32 {
        _ = font_id;
        const self: *const FileProvider = @ptrCast(@alignCast(ctx));
        return self.inkBoundsFor(glyph);
    }
};

/// The gid-namespace handshake: true when the shaper's namespace
/// matches the file's. Every covered probe must agree, and at least
/// one must agree nonzero (all-missing proves nothing). On false the
/// host must fall back to pure callbacks — file gids would draw wrong
/// glyphs through that shaper. `shaperGid` is the host's own lookup
/// (e.g. CoreText's glyph for the codepoint); no file access needed.
pub fn handshakeMatches(fp: *const FileProvider, shaperGid: *const fn (cp: u21) u16) bool {
    var agreed = false;
    for (handshake_probes) |cp| {
        const e = fp.handshakeGid(cp);
        if (e == 0) continue;
        if (shaperGid(cp) != e) return false;
        agreed = true;
    }
    return agreed;
}

// ---------------------------------------------------------------------------
// Tests (issue #192): fixture-backed pins against the tables themselves.
// ---------------------------------------------------------------------------

const lm_path = "fixtures/fonts/latinmodern-math.otf";
const stix_path = "fixtures/fonts/STIXTwoMath-overline.otf";

fn loadTestFile(path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        path,
        std.testing.allocator,
        .limited(4 * 1024 * 1024),
    );
}

fn scale1000(upm: u16, v: i32) i32 {
    return @divTrunc(v * 1000, upm);
}

// Advances are hmtx bit-for-bit — including 0 for zero-width glyphs
// (the `read` host's 500 fallback lied for all of these).
test "fileprovider advances equal hmtx, zero stays zero" {
    const bytes = try loadTestFile(lm_path);
    defer std.testing.allocator.free(bytes);
    const font = try otmath.load(bytes);
    try std.testing.expectEqual(@as(u16, 1000), font.upm);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    // Full-font sweep: every gid reads its own hmtx advance, scaled.
    var g: u32 = 0;
    while (g < font.num_glyphs) : (g += 1) {
        const want = scale1000(font.upm, try otmath.advance(font, @intCast(g)));
        try std.testing.expectEqual(want, prov.advance(prov.ctx, 0, @intCast(g)));
    }
    // Headline pins (fontTools ground truth): 'x' advances 528.
    try std.testing.expectEqual(@as(i32, 528), prov.advance(prov.ctx, 0, try otmath.glyphId(font, 'x')));
    // Zero-width combining marks resolve AND read 0, never 500.
    for ([_]u21{ 0x0302, 0x0303, 0x20D7 }) |cp| {
        const gid = prov.glyphId(prov.ctx, 0, cp);
        try std.testing.expect(gid != 0);
        try std.testing.expectEqual(@as(i32, 0), try otmath.advance(font, gid));
        try std.testing.expectEqual(@as(i32, 0), prov.advance(prov.ctx, 0, gid));
    }
}

// Italic corrections are the MATH table bit-for-bit.
test "fileprovider italic equals the MATH table" {
    const bytes = try loadTestFile(lm_path);
    defer std.testing.allocator.free(bytes);
    const font = try otmath.load(bytes);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    var g: u32 = 0;
    while (g < font.num_glyphs) : (g += 1) {
        const want = scale1000(font.upm, try otmath.italicCorrection(font, @intCast(g)));
        try std.testing.expectEqual(want, prov.italicCorrection.?(prov.ctx, 0, @intCast(g)));
    }
    // fontTools pins: 'x' corrects 16, xi corrects 0.
    try std.testing.expectEqual(@as(i32, 16), prov.italicCorrection.?(prov.ctx, 0, try otmath.glyphId(font, 'x')));
    try std.testing.expectEqual(@as(i32, 0), prov.italicCorrection.?(prov.ctx, 0, try otmath.glyphId(font, 0x03BE)));
}

// Ink is the CFF outline box with outward rounding; extents derive
// from the same box the software backend draws.
test "fileprovider ink and extents equal the outline truth" {
    const bytes = try loadTestFile(lm_path);
    defer std.testing.allocator.free(bytes);
    const font = try otmath.load(bytes);
    const cf = try cff.load(bytes);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    // Full-font sweep against the shared conversion (the software
    // backend draws through the same helper, so measure == draw).
    var scratch: [512]cff.Seg = undefined;
    var g: u32 = 0;
    while (g < font.num_glyphs) : (g += 1) {
        const u: u16 = @intCast(g);
        try std.testing.expectEqual(cff.inkBounds1000(&cf, font.upm, u, &scratch), prov.inkBounds.?(prov.ctx, 0, u));
        try std.testing.expectEqual(cff.extents1000(&cf, font.upm, u, &scratch), prov.extents.?(prov.ctx, 0, u));
    }
    // fontTools cross-checks (independent oracle, integer outlines so
    // floor/ceil are the identity): 'x', the combining hat, and U+20D7
    // whose ink hangs left of its origin (negative x0 — the accent
    // canary that hand-rolled hosts misplace).
    const hat = try otmath.glyphId(font, 0x0302);
    try std.testing.expectEqual([4]i32{ -446, 587, -82, 734 }, prov.inkBounds.?(prov.ctx, 0, hat));
    const vec = try otmath.glyphId(font, 0x20D7);
    try std.testing.expect(vec != 0);
    const vib = prov.inkBounds.?(prov.ctx, 0, vec);
    try std.testing.expectEqual(@as(i32, -472), vib[0]);
    try std.testing.expect(vib[2] > vib[0] and vib[3] > vib[1]);
    const x = try otmath.glyphId(font, 'x');
    try std.testing.expectEqual([4]i32{ 12, 0, 516, 431 }, prov.inkBounds.?(prov.ctx, 0, x));
    try std.testing.expectEqual([2]i32{ 431, 0 }, prov.extents.?(prov.ctx, 0, x));
    // Summation dips below the baseline: depth comes from the outline.
    const sum = try otmath.glyphId(font, 0x2211);
    try std.testing.expectEqual([2]i32{ 750, 250 }, prov.extents.?(prov.ctx, 0, sum));
    // Blank glyphs (space) report zeros, which the core skips.
    const sp = try otmath.glyphId(font, ' ');
    try std.testing.expectEqual([4]i32{ 0, 0, 0, 0 }, prov.inkBounds.?(prov.ctx, 0, sp));
    try std.testing.expectEqual([2]i32{ 0, 0 }, prov.extents.?(prov.ctx, 0, sp));
}

// A second file (the one-glyph STIX subset): same contract, its own
// cmap/hmtx/MATH/ink.
test "fileprovider serves the STIX subset file" {
    const bytes = try loadTestFile(stix_path);
    defer std.testing.allocator.free(bytes);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    // U+203E is the subset's only glyph (gid 1, advance 512).
    const gid = prov.glyphId(prov.ctx, 0, 0x203E);
    try std.testing.expectEqual(@as(u16, 1), gid);
    try std.testing.expectEqual(@as(i32, 512), prov.advance(prov.ctx, 0, gid));
    try std.testing.expectEqual(@as(u16, 0), prov.glyphId(prov.ctx, 0, 'x'));
    // fontTools bounds (0, 792, 512, 839): ink is the box, extents the
    // vertical slice of it.
    try std.testing.expectEqual([4]i32{ 0, 792, 512, 839 }, prov.inkBounds.?(prov.ctx, 0, gid));
    try std.testing.expectEqual([2]i32{ 839, 0 }, prov.extents.?(prov.ctx, 0, gid));
    // MATH rule constants come from the file, like the reference host.
    try std.testing.expect(prov.ruleThickness(prov.ctx, 0, .fraction_bar) > 0);
}

// Every optional hook is filled: the core always takes its refined
// paths (variant/italic/kern/ink/extents), never the v3 fallbacks.
test "fileprovider fills every provider hook" {
    const bytes = try loadTestFile(lm_path);
    defer std.testing.allocator.free(bytes);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    try std.testing.expect(prov.extents != null);
    try std.testing.expect(prov.glyphVariant != null);
    try std.testing.expect(prov.italicCorrection != null);
    try std.testing.expect(prov.kernCorrection != null);
    try std.testing.expect(prov.inkBounds != null);
    // Rule constants match the direct table read (frac rule 40).
    try std.testing.expectEqual(@as(i32, 40), prov.ruleThickness(prov.ctx, 0, .fraction_bar));
    // Grown parens route through MATH variants in-file.
    const paren = prov.glyphId(prov.ctx, 0, '(');
    try std.testing.expect(prov.glyphVariant.?(prov.ctx, 0, paren, 5000) != paren);
}

// Handshake: the engine gid probe agrees with a same-namespace shaper
// and rejects an offset or empty one (which must fall back).
test "handshake accepts same-namespace gids, rejects the rest" {
    const bytes = try loadTestFile(lm_path);
    defer std.testing.allocator.free(bytes);
    const font = try otmath.load(bytes);
    var fp = try FileProvider.init(bytes);
    // Probes read the cmap truth directly.
    try std.testing.expectEqual(try otmath.glyphId(font, 'x'), fp.handshakeGid('x'));
    try std.testing.expectEqual(try otmath.glyphId(font, 0x20D7), fp.handshakeGid(0x20D7));
    const S = struct {
        var file: otmath.Font = undefined;
        fn same(cp: u21) u16 {
            return otmath.glyphId(file, cp) catch 0;
        }
        fn off_by_one(cp: u21) u16 {
            const g = otmath.glyphId(file, cp) catch 0;
            return if (g == 0) 0 else g + 1;
        }
        fn empty(_: u21) u16 {
            return 0;
        }
    };
    S.file = font;
    try std.testing.expect(handshakeMatches(&fp, S.same));
    try std.testing.expect(!handshakeMatches(&fp, S.off_by_one));
    try std.testing.expect(!handshakeMatches(&fp, S.empty));
}

// Minimal sfnt without a CFF table (head/maxp/cmap12/hmtx/hhea only):
// metrics still work, ink/extents degrade to v3 behavior.
const PlainFixture = struct {
    buf: [512]u8 = .{0} ** 512,
    pos: usize = 0,

    fn w16(self: *PlainFixture, v: u16) void {
        self.buf[self.pos] = @intCast(v >> 8);
        self.buf[self.pos + 1] = @intCast(v & 0xFF);
        self.pos += 2;
    }

    fn w32(self: *PlainFixture, v: u32) void {
        self.w16(@intCast(v >> 16));
        self.w16(@intCast(v & 0xFFFF));
    }

    fn bytes(self: *PlainFixture) []const u8 {
        return self.buf[0..self.pos];
    }
};

fn plainFontBytes(f: *PlainFixture) []const u8 {
    f.w32(0x00010000);
    f.w16(5);
    f.w16(0);
    f.w16(0);
    f.w16(0);
    const dir_at = f.pos;
    const tags = [_]u32{ 0x68656164, 0x6D617870, 0x636D6170, 0x686D7478, 0x68686561 };
    for (tags) |t| {
        f.w32(t);
        f.w32(0);
        f.w32(0);
        f.w32(0);
    }
    var starts: [5]usize = .{ 0, 0, 0, 0, 0 };
    var lens: [5]usize = .{ 0, 0, 0, 0, 0 };
    starts[0] = f.pos;
    for (0..9) |_| f.w16(0);
    f.w16(1000);
    lens[0] = f.pos - starts[0];
    starts[1] = f.pos;
    f.w32(0);
    f.w16(8);
    lens[1] = f.pos - starts[1];
    // cmap: one (3,10) -> format12 group ['A', 'A'] -> gid 3.
    starts[2] = f.pos;
    f.w16(0);
    f.w16(1);
    f.w16(3);
    f.w16(10);
    f.w32(20);
    while (f.pos < starts[2] + 20) f.w16(0);
    f.w16(12);
    f.w16(0);
    f.w32(28);
    f.w32(0);
    f.w32(1);
    f.w32(0x41);
    f.w32(0x41);
    f.w32(3);
    lens[2] = f.pos - starts[2];
    // hmtx: 4 (advance, lsb) pairs, advances all 600.
    starts[3] = f.pos;
    for (0..4) |_| {
        f.w16(600);
        f.w16(0);
    }
    lens[3] = f.pos - starts[3];
    starts[4] = f.pos;
    for (0..17) |_| f.w16(0);
    f.w16(4);
    lens[4] = f.pos - starts[4];
    for (0..5) |k| {
        const at = dir_at + k * 16 + 8;
        f.buf[at] = @intCast(starts[k] >> 24);
        f.buf[at + 1] = @intCast((starts[k] >> 16) & 0xFF);
        f.buf[at + 2] = @intCast((starts[k] >> 8) & 0xFF);
        f.buf[at + 3] = @intCast(starts[k] & 0xFF);
        const ln = dir_at + k * 16 + 12;
        f.buf[ln] = @intCast(lens[k] >> 24);
        f.buf[ln + 1] = @intCast((lens[k] >> 16) & 0xFF);
        f.buf[ln + 2] = @intCast((lens[k] >> 8) & 0xFF);
        f.buf[ln + 3] = @intCast(lens[k] & 0xFF);
    }
    return f.bytes();
}

test "fileprovider without CFF degrades to v3 geometry" {
    var fix = PlainFixture{};
    const bytes = plainFontBytes(&fix);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    // cmap/hmtx still answer: 'A' is gid 3 with advance 600.
    try std.testing.expectEqual(@as(u16, 3), prov.glyphId(prov.ctx, 0, 'A'));
    try std.testing.expectEqual(@as(i32, 600), prov.advance(prov.ctx, 0, 3));
    // No outlines: ink is absent (core skips), extents the legacy
    // constant — exactly the null-hook behavior.
    try std.testing.expectEqual([4]i32{ 0, 0, 0, 0 }, prov.inkBounds.?(prov.ctx, 0, 3));
    try std.testing.expectEqual([2]i32{ 700, 250 }, prov.extents.?(prov.ctx, 0, 3));
    // No MATH table either: rules fall back, hooks stay total.
    try std.testing.expectEqual(@as(i32, 40), prov.ruleThickness(prov.ctx, 0, .fraction_bar));
    try std.testing.expectEqual(@as(i32, 0), prov.italicCorrection.?(prov.ctx, 0, 3));
}

// End to end: real formulas lay out deterministically through the
// file provider, accents included (the ink path is live).
test "fileprovider layouts are deterministic" {
    const bytes = try loadTestFile(lm_path);
    defer std.testing.allocator.free(bytes);
    var fp = try FileProvider.init(bytes);
    const prov = fp.provider();
    const cases = [_][]const u8{
        "\\hat{x}+\\frac{a}{b}",
        "\\vec{x}",
        "\\sum_{i=1}^{n}\\frac{i}{\\sqrt{i+1}}",
    };
    for (cases) |src| {
        var ra: [64]zatex.ir.Run = undefined;
        var la: [16]zatex.ir.Rule = undefined;
        var ga: [512]u16 = undefined;
        var rb: [64]zatex.ir.Run = undefined;
        var lb: [16]zatex.ir.Rule = undefined;
        var gb: [512]u16 = undefined;
        const a = try zatex.layoutFull(src, .{}, prov, &ra, &la, &ga);
        const b = try zatex.layoutFull(src, .{}, prov, &rb, &lb, &gb);
        try std.testing.expectEqual(a.width, b.width);
        try std.testing.expectEqual(a.height_above, b.height_above);
        try std.testing.expectEqual(a.depth_below, b.depth_below);
        try std.testing.expectEqual(a.runs.len, b.runs.len);
        try std.testing.expectEqual(a.rules.len, b.rules.len);
        try std.testing.expect(a.width > 0 and a.runs.len > 0);
        for (a.runs, b.runs) |x, y| try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
    }
}
