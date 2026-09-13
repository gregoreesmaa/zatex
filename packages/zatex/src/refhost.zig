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

const Ref = struct {
    bytes: []u8,
    font: otmath.Font,

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
        const v = otmath.italicCorrection(self.font, glyph) catch 0;
        return self.scale1000(v);
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
