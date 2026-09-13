//! ZaTeX reference host: test-only MetricsProvider over the vendored
//! Latin Modern Math, plus the coverage/determinism probes.
//!
//! This is HOST code (like `read`'s future math plugin), not the core:
//! it reads a font file, drives `otmath`, and answers provider queries.
//! It exists to prove the core against a real font — byte-identical
//! input+font=output, every emittable glyph resolving.
const std = @import("std");
const zatex = @import("zatex");
const otmath = @import("otmath");
const inv = @import("invariants");
const contract = zatex.contract;
const symbols = zatex.symbols;

/// Vendored reference font (test fixture, never linked into hosts).
const vendored_path = "fixtures/fonts/latinmodern-math.otf";

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
    bytes: []u8,
    font: otmath.Font,
    /// Test knobs (all neutral by default):
    /// - `no_italic` zeroes italic corrections.
    /// - `kern_caps` answers every kern query with canned cut-ins
    ///   (`sup` for top-right, `sub` for bottom-right).
    /// - `extents_mul` scales the (otherwise default 700/250) extents.
    no_italic: bool = false,
    kern_caps: ?struct { sup: i32, sub: i32 } = null,
    extents_mul: u32 = 1,

    fn load() !Ref {
        return loadFrom(vendored_path);
    }

    fn loadFrom(path: []const u8) !Ref {
        var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
        defer threaded.deinit();
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            threaded.io(),
            path,
            std.testing.allocator,
            .limited(4 * 1024 * 1024),
        );
        return .{ .bytes = bytes, .font = try otmath.load(bytes) };
    }

    fn free(self: *Ref) void {
        std.testing.allocator.free(self.bytes);
    }

    fn scale1000(self: *const Ref, v: i32) i32 {
        return @divTrunc(v * 1000, self.font.upm);
    }

    fn provider(self: *Ref) contract.MetricsProvider {
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

    fn gid(ctx: *const anyopaque, font_id: u16, cp: u21) u16 {
        _ = font_id;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        return otmath.glyphId(self.font, cp) catch 0;
    }

    fn adv(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        const a = otmath.advance(self.font, glyph) catch 500;
        return self.scale1000(a);
    }

    fn rule(ctx: *const anyopaque, font_id: u16, kind: contract.RuleKind) i32 {
        _ = font_id;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        const c: otmath.Const = switch (kind) {
            .fraction_bar => .frac_rule,
            .radical => .radical_rule,
            .overline => .overbar_rule,
            .underline => .underbar_rule,
        };
        const v = otmath.constant(self.font, c) catch 40;
        const s = self.scale1000(v);
        return if (s <= 0) 40 else s;
    }

    fn variant(ctx: *const anyopaque, font_id: u16, glyph: u16, min_height: i32) u16 {
        _ = font_id;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        // min_height arrives denominated at 1000 units; convert to
        // font units for the MATH advance comparison.
        const need = @divTrunc(min_height * self.font.upm, 1000);
        return otmath.vertVariant(self.font, glyph, need) catch glyph;
    }

    fn italic(ctx: *const anyopaque, font_id: u16, glyph: u16) i32 {
        _ = font_id;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        if (self.no_italic) return 0;
        const v = otmath.italicCorrection(self.font, glyph) catch 0;
        return self.scale1000(v);
    }

    fn kern(ctx: *const anyopaque, font_id: u16, glyph: u16, height: i32, corner: contract.KernCorner) i32 {
        _ = font_id;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        if (self.kern_caps) |caps| {
            return switch (corner) {
                .top_right => caps.sup,
                .bottom_right => caps.sub,
                else => 0,
            };
        }
        const oc: otmath.KernCorner = switch (corner) {
            .top_right => .top_right,
            .top_left => .top_left,
            .bottom_right => .bottom_right,
            .bottom_left => .bottom_left,
        };
        const v = otmath.kernCorrection(self.font, glyph, height, oc) catch 0;
        return self.scale1000(v);
    }

    fn ext(ctx: *const anyopaque, font_id: u16, glyph: u16) [2]i32 {
        _ = font_id;
        _ = glyph;
        const self: *const Ref = @ptrCast(@alignCast(ctx));
        const m: i32 = @intCast(self.extents_mul);
        return .{ 700 * m, 250 * m };
    }
};

/// First loadable font in `paths`, or null when none load. Unloadable
/// entries are skipped, never fatal — this is what makes the fallback
/// chain total on machines without any candidate installed.
fn loadFirst(paths: []const []const u8) ?Ref {
    for (paths) |p| {
        if (Ref.loadFrom(p)) |r| return r else |_| continue;
    }
    return null;
}

/// Vendored reference first, system font second (issue 8 fallback
/// path). Hosts without the fixture checkout (like `read`) use the
/// same order: bundled-or-vendored first, OS font second.
fn loadWithFallback() !Ref {
    if (Ref.loadFrom(vendored_path)) |r| return r else |_| {}
    if (loadFirst(&system_candidates)) |r| return r;
    return error.FileNotFound;
}

// Every codepoint the core can emit must resolve in the reference
// font (issue 8 acceptance probe). All misses print before failing.
test "coverage: every emittable glyph resolves" {
    var ref = try Ref.load();
    defer ref.free();
    // Glyphs absent from Latin Modern Math 1.959 itself (verified
    // against the font's cmap): the core still accepts the commands
    // (KaTeX parity) and providers report glyph 0 (.notdef fallback).
    // The exact set is asserted below so font upgrades fail loudly.
    const known_missing = [_]u21{ 0x03DD, 0x2132, 0x2141, 0x24C8, 0x25B9, 0x25C3, 0x02C9, 0x02CA, 0x02CB };
    var misses: usize = 0;
    var known: usize = 0;
    const miss = struct {
        fn m(cp: u21, bad_out: *usize, known_out: *usize, allowed: []const u21) void {
            for (allowed) |k| {
                if (k == cp) {
                    known_out.* += 1;
                    return;
                }
            }
            std.debug.print("unresolved U+{X}\n", .{cp});
            bad_out.* += 1;
        }
    }.m;
    for (symbols.all_symbols) |e| {
        if (e.sym.func) continue; // word operators are ASCII letters
        if ((try otmath.glyphId(ref.font, e.sym.cp)) == 0) miss(e.sym.cp, &misses, &known, &known_missing);
    }
    for (symbols.all_delims) |d| {
        if ((try otmath.glyphId(ref.font, d.cp)) == 0) miss(d.cp, &misses, &known, &known_missing);
    }
    for (symbols.all_accents) |a| {
        if ((try otmath.glyphId(ref.font, a.cp)) == 0) miss(a.cp, &misses, &known, &known_missing);
    }
    for (symbols.all_math_text_accents) |a| {
        if ((try otmath.glyphId(ref.font, a.cp)) == 0) miss(a.cp, &misses, &known, &known_missing);
    }
    // Bare fence chars, rule/radical signs, arrows, text precomposes.
    const extra = [_]u21{
        '(',  ')',  '[',  ']',  '{',  '}',  '|',  '/',  '<',  '>',
        0x005C, 0x221A, 0x23DE, 0x23DF, 0x2190, 0x2192, 0x2194, ' ',
        0x00E1, 0x00E9, 0x00F1, 0x00E7, 0x010D, 0x00E4, 0x00FC,
    };
    for (extra) |cp| {
        if ((try otmath.glyphId(ref.font, cp)) == 0) miss(cp, &misses, &known, &known_missing);
    }
    var c: u21 = '0';
    while (c <= '9') : (c += 1) {
        if ((try otmath.glyphId(ref.font, c)) == 0) miss(c, &misses, &known, &known_missing);
    }
    c = 'a';
    while (c <= 'z') : (c += 1) {
        if ((try otmath.glyphId(ref.font, c)) == 0) miss(c, &misses, &known, &known_missing);
    }
    c = 'A';
    while (c <= 'Z') : (c += 1) {
        if ((try otmath.glyphId(ref.font, c)) == 0) miss(c, &misses, &known, &known_missing);
    }
    try std.testing.expectEqual(@as(usize, 0), misses);
    try std.testing.expectEqual(known_missing.len, known);
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

// Fallback order is total: unloadable paths skip, the vendored fixture
// resolves through the same entry point hosts use.
test "fallback: unloadable paths skip, fixture resolves" {
    const bogus = [_][]const u8{"/nonexistent/zatex-font.otf"};
    try std.testing.expect(loadFirst(&bogus) == null);
    var ref = try loadWithFallback();
    defer ref.free();
    try std.testing.expect(ref.font.upm > 0);
}

// System STIX Two Math drives the full provider when the OS ships it
// (macOS Supplemental fonts); skips cleanly where it is absent.
test "fallback: system font lays out deterministically when present" {
    var sys = loadFirst(&system_candidates) orelse {
        std.debug.print("note: no system math font installed; probe skipped\n", .{});
        return;
    };
    defer sys.free();
    try std.testing.expect(sys.font.upm > 0);
    _ = try otmath.constant(sys.font, .frac_rule);
    try std.testing.expect(try otmath.glyphId(sys.font, '(') != 0);
    try std.testing.expect(try otmath.glyphId(sys.font, 0x2211) != 0); // summation
    try std.testing.expect(try otmath.glyphId(sys.font, 0x03B1) != 0); // alpha
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
    ref.kern_caps = .{ .sup = 0, .sub = 0 };
    var r0: [64]zatex.ir.Run = undefined;
    var l0: [16]zatex.ir.Rule = undefined;
    var g0: [512]u16 = undefined;
    const canned = try layoutCase(&ref, "x^2_1", false, &r0, &l0, &g0);
    ref.kern_caps = null;
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
        ref.kern_caps = .{ .sup = 40, .sub = 20 };
        var ra: [64]zatex.ir.Run = undefined;
        var la: [16]zatex.ir.Rule = undefined;
        var ga: [512]u16 = undefined;
        const a = try layoutCase(&ref, c.src, false, &ra, &la, &ga);
        ref.kern_caps = null;
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
    ref.kern_caps = .{ .sup = 1000, .sub = 1000 };
    var ra: [64]zatex.ir.Run = undefined;
    var la: [16]zatex.ir.Rule = undefined;
    var ga: [512]u16 = undefined;
    const big = try layoutCase(&ref, "x^2_1", false, &ra, &la, &ga);
    ref.kern_caps = .{ .sup = -50, .sub = -50 };
    var rb: [64]zatex.ir.Run = undefined;
    var lb: [16]zatex.ir.Rule = undefined;
    var gb: [512]u16 = undefined;
    const neg = try layoutCase(&ref, "x^2_1", false, &rb, &lb, &gb);
    ref.kern_caps = null;
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
// shifts by half the correction (x: 16/2 = 8 at text size).
test "calibration: italic correction centers accents" {
    var ref = try Ref.load();
    defer ref.free();
    var ra: [32]zatex.ir.Run = undefined;
    var la: [8]zatex.ir.Rule = undefined;
    var ga: [128]u16 = undefined;
    const a = try layoutCase(&ref, "\\hat{x}", false, &ra, &la, &ga);
    ref.no_italic = true;
    var rb: [32]zatex.ir.Run = undefined;
    var lb: [8]zatex.ir.Rule = undefined;
    var gb: [128]u16 = undefined;
    const b = try layoutCase(&ref, "\\hat{x}", false, &rb, &lb, &gb);
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    var shifts: usize = 0;
    for (a.runs, b.runs) |x, y| {
        try std.testing.expectEqualSlices(u16, x.glyphs, y.glyphs);
        const dx = y.x - x.x;
        if (dx != 0) {
            try std.testing.expectEqual(@as(i32, -8), dx);
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
    ref.extents_mul = 2;
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
    const brace = try otmath.glyphId(ref.font, '{');
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
