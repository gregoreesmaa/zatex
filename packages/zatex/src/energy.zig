//! Energy regression budgets for issues #145-#160 (issue #160 gate).
//!
//! Test-only module (never imported by the core): pins the
//! non-functional budgets the #145-#159 optimizations buy, so future
//! work re-spending them fails CI like a correctness regression.
//! Deterministic counts only — no wall-clock asserts, per the
//! deterministic-output tenet (AGENTS.md §1).
//!
//! What each budget covers (revert-sensitivity):
//! - hook-call budgets (#159 memo, #148 single ink): reverting the
//!   optimization raises the pinned counters and fails the test.
//!   (`xx`/`aaa` pin memo hits at ==1 advance call; `\overbrace`
//!   pins a single ink hook call.)
//! - pool high-water marks (#156 glue fold, #152 direct fill, #153 env
//!   fold): reverting re-materializes boxes/kids and fails the test.
//! - MathML byte budgets (#157/#158 oracle-blocked — pinned KaTeX
//!   0.18.7 emits the `1em` shell, nested `mstyle`s, and unmerged
//!   `mo`s, so the proposed folds are parity violations): pins current
//!   bytes exactly, so drift in either direction fails for review.
//! - struct-size ratchets (#150/#151): growth fails the test.
//! - dispatch battery (#146): accept/reject across every first-byte
//!   group, so a dispatch-grouping regression fails.
//! - glyph-slice contiguity (#155): the C ABI cursor's invariant,
//!   pinned at the IR level (plus a debug assert on the C path that
//!   runs under the existing C ABI tests).
//! - #145 (division hoist), #147 (macro swap-with-previous), #154
//!   (ring docs): no external counter exists or the win is structural;
//!   covered by byte-identical goldens (the whole suite) plus the
//!   targeted behavioral tests below (macro redefine through the
//!   swapped pointer; `layout`/`layoutFull` agreement + reentrancy).
const std = @import("std");
const zatex = @import("zatex");
const engine = zatex.layout_core;
const parse = zatex.parse;
const ir = zatex.ir;

// ---------------------------------------------------------------------------
// Harness: counting provider, layout driver with pool marks
// ---------------------------------------------------------------------------

const Counters = struct {
    glyph_id: u64 = 0,
    advance: u64 = 0,
    rule_thickness: u64 = 0,
    extents: u64 = 0,
    variant: u64 = 0,
    italic: u64 = 0,
    kern: u64 = 0,
    ink: u64 = 0,
};

var counters = Counters{};

const Count = struct {
    fn gid(_: *const anyopaque, _: u16, cp: u21) u16 {
        counters.glyph_id += 1;
        return @truncate(cp);
    }
    fn adv(_: *const anyopaque, _: u16, _: u16) i32 {
        counters.advance += 1;
        return 500;
    }
    fn rule(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
        counters.rule_thickness += 1;
        return 40;
    }
    fn ext(_: *const anyopaque, _: u16, _: u16) [2]i32 {
        counters.extents += 1;
        return .{ 700, 250 };
    }
    fn vari(_: *const anyopaque, _: u16, g: u16, _: i32) u16 {
        counters.variant += 1;
        return g;
    }
    fn ital(_: *const anyopaque, _: u16, _: u16) i32 {
        counters.italic += 1;
        return 0;
    }
    fn kern(_: *const anyopaque, _: u16, _: u16, _: i32, _: zatex.contract.KernCorner) i32 {
        counters.kern += 1;
        return 0;
    }
    fn ink(_: *const anyopaque, _: u16, _: u16) [4]i32 {
        counters.ink += 1;
        return .{ 0, 0, 600, 700 };
    }
};

fn countProvider() zatex.MetricsProvider {
    const S = struct {
        var dummy: u8 = 0;
    };
    return .{
        .ctx = &S.dummy,
        .glyphId = Count.gid,
        .advance = Count.adv,
        .ruleThickness = Count.rule,
        .extents = Count.ext,
        .glyphVariant = Count.vari,
        .italicCorrection = Count.ital,
        .kernCorrection = Count.kern,
        .inkBounds = Count.ink,
    };
}

/// Scalar outcome of one counted layout (no borrowed slices escape).
const Outcome = struct {
    width: u32,
    height_above: u32,
    depth_below: u32,
    nruns: usize,
    nrules: usize,
    nboxes: u16,
    nbkids: u16,
};

fn layoutCounted(source: []const u8, display: bool) !Outcome {
    counters = .{};
    var runs_buf: [1024]ir.Run = undefined;
    var rules_buf: [64]ir.Rule = undefined;
    var glyphs_buf: [8192]u16 = undefined;
    var pc = parse.ParseCtx.init(source);
    const root = try parse.parse(&pc, display);
    var lc = engine.LayCtx.init(&pc, countProvider());
    const style: parse.Style = if (display) .D else .T;
    const l = try engine.layout(&lc, root, style, &runs_buf, &rules_buf, &glyphs_buf);
    return .{
        .width = l.width,
        .height_above = l.height_above,
        .depth_below = l.depth_below,
        .nruns = l.runs.len,
        .nrules = l.rules.len,
        .nboxes = lc.nboxes,
        .nbkids = lc.nbkids,
    };
}

fn mathmlLen(source: []const u8) !usize {
    var buf: [32768]u8 = undefined;
    const s = try zatex.mathml(source, .{}, &buf);
    return s.len;
}

fn expectLe(actual: u64, budget: u64) !void {
    try std.testing.expect(actual <= budget);
}

// ---------------------------------------------------------------------------
// Struct-size ratchets (#150 Box pack, #151 Tok flags)
// ---------------------------------------------------------------------------

test "energy struct sizes ratchet" {
    // Pre-change: Box 40, Tok 32 (align-8 wall: Tok content went
    // 28 -> 27 but the slice keeps align 8, so 32 is the floor —
    // the ratchet pins the floor against future growth).
    try std.testing.expect(@sizeOf(engine.Box) <= 36);
    try std.testing.expect(@sizeOf(parse.Tok) <= 32);
}

// ---------------------------------------------------------------------------
// Hook-call budgets (#159 memo, #148 single ink)
// ---------------------------------------------------------------------------

test "energy hook budgets on corpus" {
    var o = try layoutCounted("x", false);
    try expectLe(counters.glyph_id, 1);
    try expectLe(counters.advance, 1);
    try expectLe(counters.extents, 1);
    try expectLe(o.nboxes, 2);
    try expectLe(o.nbkids, 1);

    o = try layoutCounted("x^2_1", false);
    try expectLe(counters.glyph_id, 4);
    try expectLe(counters.advance, 3);
    try expectLe(counters.extents, 3);
    try expectLe(counters.kern, 2);
    try expectLe(o.nboxes, 5);
    try expectLe(o.nbkids, 4);

    o = try layoutCounted("\\frac{1}{2}", false);
    try expectLe(counters.glyph_id, 2);
    try expectLe(counters.advance, 2);
    try expectLe(counters.extents, 2);
    try expectLe(counters.rule_thickness, 1);
    try expectLe(o.nboxes, 7);
    try expectLe(o.nbkids, 6);

    o = try layoutCounted("\\sum_{i=1}^{n} i", false);
    try expectLe(counters.glyph_id, 7);
    try expectLe(counters.advance, 5);
    try expectLe(counters.extents, 5);
    try expectLe(counters.kern, 2);
    try expectLe(o.nboxes, 10);
    try expectLe(o.nbkids, 9);

    o = try layoutCounted("\\sin x", false);
    try expectLe(counters.glyph_id, 4);
    try expectLe(counters.advance, 4);
    try expectLe(counters.extents, 4);
    try expectLe(o.nboxes, 6);
    try expectLe(o.nbkids, 5);
}

test "energy memo collapses repeat glyph queries" {
    // Each repeated glyph must cost exactly one hook call: reverting
    // the #159 memo raises these to 2/2 and 3/3 and fails the test.
    _ = try layoutCounted("xx", false);
    try std.testing.expectEqual(@as(u64, 1), counters.advance);
    try std.testing.expectEqual(@as(u64, 1), counters.extents);

    _ = try layoutCounted("aaa", false);
    try std.testing.expectEqual(@as(u64, 1), counters.advance);
    try std.testing.expectEqual(@as(u64, 1), counters.extents);

    // The word loop shares the same memo path.
    _ = try layoutCounted("\\text{aaa}", false);
    try std.testing.expectEqual(@as(u64, 1), counters.advance);
    try std.testing.expectEqual(@as(u64, 1), counters.extents);

    // Macro-expanded repeats hit too.
    _ = try layoutCounted("\\def\\a{X}\\a\\a\\a", false);
    try std.testing.expectEqual(@as(u64, 1), counters.advance);
    try std.testing.expectEqual(@as(u64, 1), counters.extents);
}

test "energy brace label calls ink once" {
    // #148: the null check and the value share one hook call.
    _ = try layoutCounted("\\overbrace{x}", false);
    try std.testing.expectEqual(@as(u64, 1), counters.ink);
}

// ---------------------------------------------------------------------------
// Pool high-water marks (#156 glue fold, #152 direct fill, #153 env fold)
// ---------------------------------------------------------------------------

test "energy pool high-water on corpus" {
    // No kern boxes are materialized for inter-atom glue (#156): a
    // 5-atom row costs 5 kids, not 5 + gaps.
    var o = try layoutCounted("a+b=c", false);
    try expectLe(o.nboxes, 6);
    try expectLe(o.nbkids, 5);

    o = try layoutCounted("x+y+z", false);
    try expectLe(o.nboxes, 6);
    try expectLe(o.nbkids, 5);

    o = try layoutCounted("\\quad x \\quad y", false);
    try expectLe(o.nboxes, 5);
    try expectLe(o.nbkids, 4);

    o = try layoutCounted("\\begin{matrix}a&b\\\\c&d\\end{matrix}", false);
    try expectLe(o.nboxes, 10);
    try expectLe(o.nbkids, 9);

    o = try layoutCounted("\\overbrace{x}", false);
    try expectLe(o.nboxes, 5);
    try expectLe(o.nbkids, 4);
}

// ---------------------------------------------------------------------------
// MathML byte budgets (#157/#158 oracle-blocked: pin current output)
// ---------------------------------------------------------------------------

test "energy mathml byte budgets" {
    // Pinned KaTeX 0.18.7 emits the identity `mathsize="1em"` shell
    // for `\normalsize`, nested identical `mstyle`s, and unmerged
    // adjacent `mo`s — verified by direct probe (see issues #157,
    // #158). These pins fail on ANY drift so the parity question
    // reopens loudly instead of silently.
    // Values include the #119 `<semantics>` + `application/x-tex`
    // annotation wrapper (KaTeX 0.18.7 parity); the pinned shapes
    // inside are unchanged: the `mathsize="1em"` shell (#157),
    // unmerged `mo`s (#158).
    try std.testing.expectEqual(@as(usize, 202), try mathmlLen("\\normalsize{x}"));
    try std.testing.expectEqual(@as(usize, 201), try mathmlLen("x+y+z"));
    try std.testing.expectEqual(@as(usize, 204), try mathmlLen("\\mathbf{12}"));
    try std.testing.expectEqual(@as(usize, 192), try mathmlLen("\\frac{1}{2}"));
}

// ---------------------------------------------------------------------------
// Fuzz energy ceiling: adversarial-but-valid inputs stay budgeted
// ---------------------------------------------------------------------------

test "energy fuzz ceiling" {
    // 401-atom row: total, pool-bounded, hook-bounded.
    var long_row: [401]u8 = undefined;
    long_row[0] = 'a';
    var li: usize = 1;
    while (li < 400) : (li += 2) {
        long_row[li] = '+';
        long_row[li + 1] = 'a';
    }
    const o_row = try layoutCounted(long_row[0..], false);
    try expectLe(o_row.nboxes, 402);
    try expectLe(o_row.nbkids, 401);
    try expectLe(o_row.nruns, 401);
    try expectLe(counters.glyph_id, 401);

    // 10-deep fraction nest.
    var nest: [112]u8 = undefined;
    var ni: usize = 0;
    for (0..10) |_| {
        @memcpy(nest[ni .. ni + 6], "\\frac{");
        ni += 6;
    }
    @memcpy(nest[ni .. ni + 1], "1");
    ni += 1;
    for (0..10) |_| {
        @memcpy(nest[ni .. ni + 4], "}{2}");
        ni += 4;
    }
    const o_nest = try layoutCounted(nest[0..ni], false);
    try expectLe(o_nest.nboxes, 52);
    try expectLe(o_nest.nbkids, 51);
    try expectLe(o_nest.nrules, 10);

    // 10-deep phantom nest emits nothing but stays dimensioned.
    var phantom: [101]u8 = undefined;
    var pi: usize = 0;
    for (0..10) |_| {
        @memcpy(phantom[pi .. pi + 9], "\\phantom{");
        pi += 9;
    }
    phantom[pi] = 'x';
    pi += 1;
    for (0..10) |_| {
        phantom[pi] = '}';
        pi += 1;
    }
    const o_ph = try layoutCounted(phantom[0..pi], false);
    try std.testing.expectEqual(@as(usize, 0), o_ph.nruns);
    try std.testing.expectEqual(@as(usize, 0), o_ph.nrules);
    try expectLe(o_ph.nboxes, 22);
    try expectLe(o_ph.nbkids, 11);
    try std.testing.expect(o_ph.width > 0);
}

// ---------------------------------------------------------------------------
// Color sentinel (#150): white is a real paint, never ambient
// ---------------------------------------------------------------------------

test "energy color sentinel survives white" {
    // All resolved colors carry opaque alpha, so transparent black
    // (`no_color`) can never be a real paint. White is the closest
    // call: it must resolve to 0xFFFFFFFF and still paint a run.
    var pcc = parse.ParseCtx.init("\\color{#ffffff}{x}");
    const croot = try parse.parse(&pcc, false);
    const ckids = parse.kidsOf(&pcc, parse.nodeAt(&pcc, croot).group);
    try std.testing.expectEqual(@as(usize, 1), ckids.len);
    const spec = parse.nodeAt(&pcc, ckids[0]).color.spec;
    try std.testing.expect(parse.resolveColorSpec(&pcc, spec) != engine.no_color);
    try std.testing.expectEqual(@as(?u32, 0xFFFFFFFF), parse.resolveColorSpec(&pcc, spec));

    counters = .{};
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var lc = engine.LayCtx.init(&pcc, countProvider());
    const l = try engine.layout(&lc, croot, .T, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
    try std.testing.expectEqual(@as(?u32, 0xFFFFFFFF), l.runs[0].color);
}

// ---------------------------------------------------------------------------
// Macro lookup (#147 with group-scope shadowing #125): definitions
// append and lookup reads innermost-first, so redefine wins;
// swap-with-previous applies only to global pairs (scope-safe).
// ---------------------------------------------------------------------------

test "energy macro redefine renders the latest body" {
    // `\def\a{1}\def\a{2}\a` must render "2": back-to-front lookup
    // returns the innermost definition.
    counters = .{};
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var pc = parse.ParseCtx.init("\\def\\a{1}\\def\\a{2}\\a");
    const root = try parse.parse(&pc, false);
    var lc = engine.LayCtx.init(&pc, countProvider());
    const l = try engine.layout(&lc, root, .T, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
    // Counting provider maps codepoints to truncated glyph ids.
    try std.testing.expectEqual(@as(u16, '2'), l.runs[0].glyphs[0]);

    // Repeated use of a late-defined macro stays correct after swaps
    // (digits pass the math-alpha remap through, so glyph ids are
    // directly comparable).
    var pc2 = parse.ParseCtx.init("\\def\\a{1}\\def\\b{2}\\def\\c{3}\\c\\b\\a\\c\\b\\a");
    const root2 = try parse.parse(&pc2, false);
    var lc2 = engine.LayCtx.init(&pc2, countProvider());
    const l2 = try engine.layout(&lc2, root2, .T, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l2.runs.len);
    const want = [_]u16{ '3', '2', '1', '3', '2', '1' };
    try std.testing.expectEqualSlices(u16, &want, l2.runs[0].glyphs);
}

// ---------------------------------------------------------------------------
// Dispatch battery (#146): every first-byte group routes correctly
// ---------------------------------------------------------------------------

test "energy dispatch battery" {
    // One accept per first-byte group (plus multi-byte OR-arms split
    // across groups), so a grouping regression fails loudly.
    const accepts = [_][]const u8{
        "\\angln", "\\approxcolon", "\\binom{n}{k}", "\\Bra{x}", "\\braket{a}{b}",
        "\\cancel{x}", "\\copyright", "\\dfrac{a}{b}",
        "\\operatorname{foo}", "\\sout{x}", "\\TeX", "\\text{hi}",
        "\\url{x}", "\\vcenter{x}", "\\verb|x|", "\\xcancel{x}",
        "\\frac{a}{b}", "\\sqrt{x}", "\\sum_{i=1}^n i", "\\hat{x}",
        "\\overline{x}", "\\overset{a}{b}", "\\underline{x}",
        "\\begin{matrix}a\\end{matrix}", "\\left(a\\right)", "\\lim_{x} f",
        "\\mathbf{x}", "\\boldsymbol{x}", "\\mod{n}", "\\pod{x}",
        "\\KaTeX", "\\LaTeX", "\\includegraphics{img}", "\\href{http://x}{y}",
        "\\color{red}{x}", "\\colorbox{red}{x}", "\\colon", "\\ratio",
        "\\vcentcolon", "\\implies A", "\\iff A", "\\not=", "\\neq",
        "\\nleqq x", "\\lvertneqq x", "\\nshortmid x", "\\varsubsetneq x",
        "\\substack{a\\\\b}", "\\smash{x}", "\\set{x}", "\\Set{x}",
        "\\Braket{x}", "\\boxed{x}", "\\fbox{hi}", "\\phantom{x}",
        "\\raisebox{1pt}{x}", "\\rule{1em}{1ex}", "\\mathstrut", "\\llap{x}",
        "\\mathchoice{a}{b}{c}{d}", "\\mathinner{x}", "\\plim", "\\pmb{x}",
        "\\reflectbox{x}", "\\textcircled{x}", "\\dotsi", "\\cdot",
        "\\alpha", "\\in", "\\notin", "\\owns", "\\hbar", "\\ell",
        "\\quad", "\\qquad", "\\hspace{1em}x", "\\kern1em", "\\newline",
        "\\nobreakspace", "\\,", "\\;", "\\:", "\\%", "\\$", "\\#",
        "\\begingroup x\\endgroup",
        "\\textstyle x", "\\displaystyle x", "\\scriptstyle x",
        "\\tiny x", "\\small x", "\\large x", "\\Huge x",
        "\\overbrace{x}^{y}", "\\underbrace{x}_{y}", "\\xrightarrow{a}",
        "\\boxed{\\frac{a}{b}}",
    };
    for (accepts) |src| {
        _ = try layoutCounted(src, false);
    }
    // Display mode exercises the displaystyle operator paths.
    _ = try layoutCounted("\\sum_{i=1}^n i", true);

    // Rejects keep their shape: unknown command at offset 0.
    {
        counters = .{};
        var pc = parse.ParseCtx.init("\\nope");
        const err = parse.parse(&pc, false);
        try std.testing.expectError(error.Invalid, err);
        try std.testing.expectEqual(@as(u32, 0), pc.err_pos);
    }
    // Lone subsuperscript still rejects at the caret.
    {
        var pc = parse.ParseCtx.init("x^");
        const err = parse.parse(&pc, false);
        try std.testing.expectError(error.Invalid, err);
        try std.testing.expectEqual(@as(u32, 1), pc.err_pos);
    }
    // Row/environment-only commands reject at top level (offset 0).
    const top_rejects = [_][]const u8{ "\\cr", "\\end", "\\hline" };
    for (top_rejects) |src| {
        var pc = parse.ParseCtx.init(src);
        const err = parse.parse(&pc, false);
        try std.testing.expectError(error.Invalid, err);
        try std.testing.expectEqual(@as(u32, 0), pc.err_pos);
    }
}

// ---------------------------------------------------------------------------
// Glyph-slice contiguity (#155): the C ABI cursor's IR-level invariant
// ---------------------------------------------------------------------------

test "energy run glyph slices are contiguous" {
    counters = .{};
    var runs_buf: [64]ir.Run = undefined;
    var rules_buf: [16]ir.Rule = undefined;
    var glyphs_buf: [256]u16 = undefined;
    var pc = parse.ParseCtx.init("a+\\frac{b}{c}+\\mathbf{de}+f");
    const root = try parse.parse(&pc, false);
    var lc = engine.LayCtx.init(&pc, countProvider());
    const l = try engine.layout(&lc, root, .T, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(l.runs.len > 1);
    var prev_end: usize = 0;
    for (l.runs) |r| {
        const start = (@intFromPtr(r.glyphs.ptr) - @intFromPtr(glyphs_buf[0..].ptr)) / 2;
        try std.testing.expectEqual(prev_end, start);
        try std.testing.expect(r.glyphs.len > 0);
        prev_end = start + r.glyphs.len;
    }
}

// ---------------------------------------------------------------------------
// Ring deprecation (#154): agreement + Full-path reentrancy
// ---------------------------------------------------------------------------

test "energy layout agrees with layoutFull and reenters" {
    // `layout` (shared ring) agrees byte-for-byte with `layoutFull`
    // (caller buffer) on dimensions, runs, and glyph contents.
    var runs_a: [16]ir.Run = undefined;
    var rules_a: [8]ir.Rule = undefined;
    var runs_b: [16]ir.Run = undefined;
    var rules_b: [8]ir.Rule = undefined;
    var glyphs_b: [256]u16 = undefined;
    const src = "x^2+\\frac12";
    const a = try zatex.layout(src, .{}, countProvider(), &runs_a, &rules_a);
    const b = try zatex.layoutFull(src, .{}, countProvider(), &runs_b, &rules_b, &glyphs_b);
    try std.testing.expectEqual(a.width, b.width);
    try std.testing.expectEqual(a.height_above, b.height_above);
    try std.testing.expectEqual(a.depth_below, b.depth_below);
    try std.testing.expectEqual(a.runs.len, b.runs.len);
    for (a.runs, b.runs) |ra, rb| {
        try std.testing.expectEqual(ra.font_id, rb.font_id);
        try std.testing.expectEqual(ra.size_units, rb.size_units);
        try std.testing.expectEqual(ra.x, rb.x);
        try std.testing.expectEqual(ra.baseline_y, rb.baseline_y);
        try std.testing.expectEqualSlices(u16, ra.glyphs, rb.glyphs);
    }

    // Two `layoutFull` results coexist (no shared state on the Full
    // path); the second call cannot disturb the first.
    var runs_c: [16]ir.Run = undefined;
    var rules_c: [8]ir.Rule = undefined;
    var glyphs_c: [256]u16 = undefined;
    var runs_d: [16]ir.Run = undefined;
    var rules_d: [8]ir.Rule = undefined;
    var glyphs_d: [256]u16 = undefined;
    const c = try zatex.layoutFull("aaa", .{}, countProvider(), &runs_c, &rules_c, &glyphs_c);
    const cw = c.width;
    _ = try zatex.layoutFull("\\frac{1}{2}", .{}, countProvider(), &runs_d, &rules_d, &glyphs_d);
    try std.testing.expectEqual(cw, c.width);
    try std.testing.expectEqual(@as(usize, 3), c.runs[0].glyphs.len);
}
