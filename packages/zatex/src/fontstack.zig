//! Host-side multi-face font stack (issue #92).
//!
//! The reference font (Latin Modern Math) lacks glyphs KaTeX accepts
//! (the #92 blank set: AMS symbols, moustaches, triangles, ...), and
//! single-file hosts cannot style text faces at all (issue #95: the
//! core emits `FontId` but a one-file provider has no bold/italic/
//! sans/mono face to answer with). The stack resolves both at the
//! root: one ordered face list per `FontId`, per-glyph fallback down
//! each chain, metrics always from the winning face.
//!
//! Design notes (all verified against the vendored fixtures):
//! - Latin Modern Math stays FIRST for `rm`/`math_italic`, so every
//!   codepoint it covers keeps byte-identical metrics (the AGENTS.md
//!   reference look is untouched); KaTeX CFF-OTF faces (converted
//!   from the pinned bundle, see `fixtures/fonts/katex/`) fill gaps
//!   and supply the text faces LM has no files for.
//! - KaTeX faces carry no SMP math-alphanumeric blocks, so styled
//!   math families (`\mathbf{A}` -> U+1D400) keep resolving to LM
//!   exactly as before; only BMP lookups move faces.
//! - Unified glyph ids (`base + face gid`) keep the provider's u16
//!   namespace collision-free; `faceOf` inverts the mapping for
//!   backends that draw per-face files.
//! - MATH-less faces (all KaTeX converts) have no variant/italic/
//!   kern data: those hooks fall back exactly as a missing table did
//!   before (identity / zero). Extensible assembly stays where it
//!   was (issues #102/#104 own that story).
//! - This is HOST/TOOL code (like `refhost`), never linked into the
//!   subset library: no heap allocation, files read by the caller.
const std = @import("std");
const zatex = @import("zatex");
const contract = zatex.contract;
const otmath = @import("otmath");

/// Face role: which file plays it is the caller's choice (fixture
/// paths, system fallback); the chains below only name roles.
pub const Role = enum {
    lm,
    main,
    main_bold,
    main_italic,
    main_bi,
    math_italic,
    ams,
    sans,
    typewriter,
    cal,
    frak,
    script,
    stix,
};

pub const max_faces = 16;

pub const Face = struct {
    role: Role,
    bytes: []const u8,
    font: otmath.Font,
    /// Unified-gid base: this face's gid `g` travels as `base + g`.
    base: u32,
};

pub const FaceRef = struct {
    index: usize,
    gid: u16,
};

pub const Stack = struct {
    faces: [max_faces]Face = undefined,
    nfaces: usize = 0,
    total_glyphs: u32 = 0,
    /// Test knobs (refhost parity): `no_italic` zeroes italic
    /// corrections; `kern_caps` answers every kern query canned;
    /// `extents_mul` scales the constant 700/250 extents.
    no_italic: bool = false,
    kern_caps: ?struct { sup: i32, sub: i32 } = null,
    extents_mul: u32 = 1,

    pub fn addFile(self: *Stack, role: Role, bytes: []const u8) !void {
        if (self.nfaces >= max_faces) return error.NoSpace;
        const font = try otmath.load(bytes);
        const n: u32 = font.num_glyphs;
        if (self.total_glyphs + n > 0xFFFF) return error.NoSpace;
        self.faces[self.nfaces] = .{
            .role = role,
            .bytes = bytes,
            .font = font,
            .base = self.total_glyphs,
        };
        self.nfaces += 1;
        self.total_glyphs += n;
    }

    fn faceIndex(self: *const Stack, role: Role) ?usize {
        for (self.faces[0..self.nfaces], 0..) |f, i| {
            if (f.role == role) return i;
        }
        return null;
    }

    /// Ordered face roles per provider font id (`contract.FontId`
    /// order: rm, math_italic, bold, sans, tt, frak, script, bb, cal,
    /// bold_italic). LM first for rm (reference look stable); KaTeX
    /// faces first everywhere else so text styling is real (issue
    /// #95: `\textit` shares its id with math italic, and only an
    /// italic-first chain renders it slanted). SMP math families
    /// never occur in KaTeX faces, so styled math still lands on LM.
    /// Accepted edge: `\mathit` digits follow the italic face like
    /// text digits instead of KaTeX's upright digit.
    fn chain(font_id: u16) []const Role {
        return switch (font_id) {
            0 => &.{ .lm, .main, .ams, .stix },
            1 => &.{ .main_italic, .math_italic, .lm, .stix },
            2 => &.{ .main_bold, .lm, .stix },
            3 => &.{ .sans, .lm, .stix },
            4 => &.{ .typewriter, .lm, .stix },
            5 => &.{ .frak, .lm, .stix },
            6 => &.{ .script, .lm, .stix },
            7 => &.{ .ams, .lm, .stix },
            8 => &.{ .cal, .lm, .stix },
            9 => &.{ .main_bi, .lm, .stix },
            else => &.{ .lm, .main, .ams, .stix },
        };
    }

    fn resolve(self: *const Stack, font_id: u16, cp: u21) ?FaceRef {
        // Single-file host (custom `--font`): the lone face answers
        // every font id, exactly like the pre-stack provider did.
        if (self.nfaces == 1) {
            const g = otmath.glyphId(self.faces[0].font, cp) catch return null;
            if (g == 0) return null;
            return .{ .index = 0, .gid = g };
        }
        for (chain(font_id)) |role| {
            const i = self.faceIndex(role) orelse continue;
            const g = otmath.glyphId(self.faces[i].font, cp) catch continue;
            if (g != 0) return .{ .index = i, .gid = g };
        }
        return null;
    }

    /// Units per em of the first face (the reference face in every
    /// shipped stack), or 0 when empty.
    pub fn upm(self: *const Stack) u16 {
        if (self.nfaces == 0) return 0;
        return self.faces[0].font.upm;
    }

    /// Invert a unified gid to its face (backends drawing per-face
    /// files). Returns null for out-of-range ids.
    pub fn faceOf(self: *const Stack, unified: u16) ?FaceRef {
        const u: u32 = unified;
        for (self.faces[0..self.nfaces], 0..) |f, i| {
            const n: u32 = f.font.num_glyphs;
            if (u >= f.base and u < f.base + n) {
                return .{ .index = i, .gid = @intCast(u - f.base) };
            }
        }
        return null;
    }

    fn scale1000(face: *const Face, v: i32) i32 {
        return @divTrunc(v * 1000, face.font.upm);
    }

    /// Standalone provider (ctx borrows the stack): glyph identity,
    /// advances, rule constants, and variant/italic/kern routing plus
    /// the constant 700/250 extents. Owners needing their own extents
    /// (backend ink boxes) build the struct by hand from the `*For`
    /// methods below with their own ctx.
    pub fn provider(self: *Stack) contract.MetricsProvider {
        return .{
            .ctx = @ptrCast(self),
            .glyphId = gid,
            .advance = adv,
            .ruleThickness = rule,
            .glyphVariant = variant,
            .italicCorrection = italic,
            .kernCorrection = kern,
            .extents = ext,
        };
    }

    pub fn glyphIdFor(self: *const Stack, font_id: u16, cp: u21) u16 {
        const r = self.resolve(font_id, cp) orelse return 0;
        const u = self.faces[r.index].base + r.gid;
        return @intCast(u);
    }

    fn gid(ctx: *const anyopaque, font_id: u16, cp: u21) u16 {
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.glyphIdFor(font_id, cp);
    }

    pub fn advance1000(self: *const Stack, unified: u16) i32 {
        const r = self.faceOf(unified) orelse return 500;
        const f = &self.faces[r.index];
        const a = otmath.advance(f.font, r.gid) catch 500;
        return scale1000(f, a);
    }

    fn adv(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.advance1000(glyph);
    }

    /// Rule constants come from the first MATH-capable face (LM in
    /// every shipped stack), exactly as the single-font host did.
    fn ruleFace(self: *const Stack) ?*const Face {
        for (self.faces[0..self.nfaces]) |*f| {
            if (f.font.math_off != 0) return f;
        }
        return null;
    }

    pub fn ruleFor(self: *const Stack, kind: contract.RuleKind) i32 {
        const f = self.ruleFace() orelse return 40;
        const c: otmath.Const = switch (kind) {
            .fraction_bar => .frac_rule,
            .radical => .radical_rule,
            .overline => .overbar_rule,
            .underline => .underbar_rule,
        };
        const v = otmath.constant(f.font, c) catch 40;
        const s = scale1000(f, v);
        return if (s <= 0) 40 else s;
    }

    fn rule(ctx: *const anyopaque, font_id: u16, kind: contract.RuleKind) i32 {
        _ = font_id;
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.ruleFor(kind);
    }

    pub fn variantFor(self: *const Stack, glyph: u16, min_height: i32) u16 {
        const r = self.faceOf(glyph) orelse return glyph;
        const f = &self.faces[r.index];
        // min_height arrives denominated at 1000 units; convert to
        // font units for the MATH advance comparison.
        const need = @divTrunc(min_height * f.font.upm, 1000);
        const v = otmath.vertVariant(f.font, r.gid, need) catch return glyph;
        // A picked variant stays in this face's namespace.
        const u = f.base + v;
        return if (u > 0xFFFF) glyph else @intCast(u);
    }

    fn variant(ctx: *const anyopaque, font_id: u16, glyph: u16, min_height: i32) u16 {
        _ = font_id;
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.variantFor(glyph, min_height);
    }

    pub fn italicFor(self: *const Stack, glyph: u16) i32 {
        if (self.no_italic) return 0;
        const r = self.faceOf(glyph) orelse return 0;
        const f = &self.faces[r.index];
        const v = otmath.italicCorrection(f.font, r.gid) catch 0;
        return scale1000(f, v);
    }

    fn italic(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.italicFor(glyph);
    }

    pub fn kernFor(
        self: *const Stack,
        glyph: u16,
        height: i32,
        corner: contract.KernCorner,
    ) i32 {
        if (self.kern_caps) |caps| {
            return switch (corner) {
                .top_right => caps.sup,
                .bottom_right => caps.sub,
                else => 0,
            };
        }
        const r = self.faceOf(glyph) orelse return 0;
        const f = &self.faces[r.index];
        const oc: otmath.KernCorner = switch (corner) {
            .top_right => .top_right,
            .top_left => .top_left,
            .bottom_right => .bottom_right,
            .bottom_left => .bottom_left,
        };
        const v = otmath.kernCorrection(f.font, r.gid, height, oc) catch 0;
        return scale1000(f, v);
    }

    fn kern(
        ctx: *const anyopaque,
        font_id: u16,
        glyph: u16,
        height: i32,
        corner: contract.KernCorner,
    ) i32 {
        _ = font_id;
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.kernFor(glyph, height, corner);
    }

    pub fn extentsFor(self: *const Stack) [2]i32 {
        const m: i32 = @intCast(self.extents_mul);
        return .{ 700 * m, 250 * m };
    }

    fn ext(ctx: *const anyopaque, font_id: u16, glyph: u16) [2]i32 {
        _ = font_id;
        _ = glyph;
        const self: *const Stack = @ptrCast(@alignCast(ctx));
        return self.extentsFor();
    }

    pub fn roleOf(self: *const Stack, unified: u16) ?Role {
        const r = self.faceOf(unified) orelse return null;
        return self.faces[r.index].role;
    }
};

// ---------------------------------------------------------------------------
// Tests (issue #92/#95): fixture-backed, deterministic (no system font).
// ---------------------------------------------------------------------------

const lm_path = "fixtures/fonts/latinmodern-math.otf";
const katex_dir = "fixtures/fonts/katex/";

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

const TestStack = struct {
    bufs: [max_faces][]u8 = .{undefined} ** max_faces,
    nbufs: usize = 0,
    stack: Stack = .{},

    fn add(self: *TestStack, role: Role, path: []const u8) !void {
        const bytes = try loadTestFile(path);
        errdefer std.testing.allocator.free(bytes);
        try self.stack.addFile(role, bytes);
        self.bufs[self.nbufs] = bytes;
        self.nbufs += 1;
    }

    fn free(self: *TestStack) void {
        for (self.bufs[0..self.nbufs]) |b| std.testing.allocator.free(b);
        self.nbufs = 0;
    }
};

/// The 29 codepoints Latin Modern Math 1.959 lacks (issue #92 blank
/// set + modifier letters): LM alone reports gid 0 for every one,
/// the stack resolves every one through the KaTeX faces.
const blank_set = [_]u21{
    0x03DD, 0x2132, 0x2141, 0x24C8, 0x25B9, 0x25C3, 0x02C9, 0x02CA, 0x02CB,
    0x21E0, 0x21E2, 0x22D4, 0x23B0, 0x23B1, 0x2571, 0x2572, 0x2605, 0x29EB,
    0x2A5E, 0x2AB5, 0x2AB6, 0x2AB7, 0x2AB8, 0x2AB9, 0x2ABA, 0x2AC5, 0x2AC6,
    0x2ACB, 0x2ACC,
};

test "issue92 blank set misses LM alone, resolves through the stack" {
    var alm = TestStack{};
    defer alm.free();
    try alm.add(.lm, lm_path);
    for (blank_set) |cp| {
        try std.testing.expectEqual(@as(u16, 0), alm.stack.glyphIdFor(0, cp));
    }
    var full = TestStack{};
    defer full.free();
    try full.add(.lm, lm_path);
    try full.add(.main, katex_dir ++ "KaTeX_Main-Regular.otf");
    try full.add(.ams, katex_dir ++ "KaTeX_AMS-Regular.otf");
    for (blank_set) |cp| {
        const g = full.stack.glyphIdFor(0, cp);
        try std.testing.expect(g != 0);
        // Fallback engaged: none of these come from LM itself.
        try std.testing.expect(full.stack.roleOf(g) != .lm);
        try std.testing.expect(full.stack.advance1000(g) > 0);
    }
    // Headline pins: star via AMS, modifier macron via Main.
    try std.testing.expectEqual(Role.ams, full.stack.roleOf(full.stack.glyphIdFor(0, 0x2605)));
    try std.testing.expectEqual(Role.main, full.stack.roleOf(full.stack.glyphIdFor(0, 0x02C9)));
}

test "issue95 text faces resolve to real KaTeX faces" {
    var ts = TestStack{};
    defer ts.free();
    try ts.add(.lm, lm_path);
    try ts.add(.main_bold, katex_dir ++ "KaTeX_Main-Bold.otf");
    try ts.add(.main_italic, katex_dir ++ "KaTeX_Main-Italic.otf");
    try ts.add(.sans, katex_dir ++ "KaTeX_SansSerif-Regular.otf");
    try ts.add(.typewriter, katex_dir ++ "KaTeX_Typewriter-Regular.otf");
    // rm keeps the reference look (face 0 == LM).
    const a_rm = ts.stack.glyphIdFor(0, 'A');
    try std.testing.expect(a_rm != 0);
    try std.testing.expectEqual(Role.lm, ts.stack.roleOf(a_rm));
    // Each text face answers from its own KaTeX file (issue #95:
    // single-file hosts rendered all of these as LM regular).
    const a_bold = ts.stack.glyphIdFor(2, 'A');
    try std.testing.expect(a_bold != 0);
    try std.testing.expectEqual(Role.main_bold, ts.stack.roleOf(a_bold));
    try std.testing.expectEqual(Role.main_italic, ts.stack.roleOf(ts.stack.glyphIdFor(1, 'A')));
    try std.testing.expectEqual(Role.sans, ts.stack.roleOf(ts.stack.glyphIdFor(3, '0')));
    try std.testing.expectEqual(Role.typewriter, ts.stack.roleOf(ts.stack.glyphIdFor(4, 'x')));
    try std.testing.expect(ts.stack.advance1000(a_bold) > 0);
}

test "smp math families stay on LM" {
    var ts = TestStack{};
    defer ts.free();
    try ts.add(.lm, lm_path);
    try ts.add(.main_bold, katex_dir ++ "KaTeX_Main-Bold.otf");
    try ts.add(.ams, katex_dir ++ "KaTeX_AMS-Regular.otf");
    // KaTeX faces carry no SMP blocks, so styled math keeps LM
    // metrics byte-for-byte (no churn for mathbfmathcal/bb).
    for ([_]u21{ 0x1D400, 0x1D41A, 0x1D49C, 0x1D504, 0x1D538, 0x1D5A0, 0x1D670 }) |cp| {
        const g = ts.stack.glyphIdFor(2, cp);
        try std.testing.expect(g != 0);
        try std.testing.expectEqual(Role.lm, ts.stack.roleOf(g));
    }
}

test "issue92 underbar hook resolves from the vendored subset" {
    // U+203E lives in no LM/KaTeX face; the one-glyph STIX subset
    // keeps \underbar off machine-dependent system fonts.
    var ts = TestStack{};
    defer ts.free();
    try ts.add(.lm, lm_path);
    try std.testing.expectEqual(@as(u16, 0), ts.stack.glyphIdFor(0, 0x203E));
    try ts.add(.stix, "fixtures/fonts/STIXTwoMath-overline.otf");
    const g = ts.stack.glyphIdFor(0, 0x203E);
    try std.testing.expect(g != 0);
    try std.testing.expectEqual(Role.stix, ts.stack.roleOf(g));
    try std.testing.expect(ts.stack.advance1000(g) > 0);
}

test "unified gids round-trip and variants stay in-face" {
    var ts = TestStack{};
    defer ts.free();
    try ts.add(.lm, lm_path);
    try ts.add(.ams, katex_dir ++ "KaTeX_AMS-Regular.otf");
    for ([_]u21{ '(', 'A', 0x2605, 0x2211 }) |cp| {
        const g = ts.stack.glyphIdFor(0, cp);
        try std.testing.expect(g != 0);
        const r = ts.stack.faceOf(g) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(g, ts.stack.faces[r.index].base + r.gid);
    }
    try std.testing.expect(ts.stack.faceOf(0xFFFF) == null or ts.stack.total_glyphs > 0xFFFF);
    // A grown LM paren picks an LM MATH variant, still face 0.
    const paren = ts.stack.glyphIdFor(0, '(');
    const grown = ts.stack.variantFor(paren, 5000);
    try std.testing.expectEqual(@as(usize, 0), (ts.stack.faceOf(grown) orelse return error.TestUnexpectedResult).index);
    try std.testing.expect(grown != paren);
}
