//! ZaTeX — KaTeX-compatible LaTeX math engine (native Zig).
//!
//! Library root: public API plus the engine wiring (parse → layout →
//! IR/MathML). The frozen v1 shapes live in `contract.zig` and are
//! re-exported here unchanged; the output contract lives in `ir.zig`.
const std = @import("std");
const build_options = @import("build_options");

pub const ir = @import("ir.zig");
pub const parse = @import("parse.zig");
pub const symbols = @import("symbols.zig");
const engine = @import("layout.zig");
/// Layout core namespace (box tree, `LayCtx` pools). Public so
/// test-only modules (energy budgets, issue #160) can read pool
/// high-water marks without duplicating the engine wiring; the
/// stable embedding surface stays `layoutFull`/`layoutDiag`/C ABI.
pub const layout_core = engine;
const mathml_mod = @import("mathml.zig");
pub const contract = @import("contract.zig");

// C ABI (issue 9): exports + conformance tests ride along with the lib.
comptime {
    _ = @import("cabi.zig");
}

// ---------------------------------------------------------------------------
// Stable v1 contract. Frozen 2026-09-12: additive-only evolution from here.
// New fallible conditions join LayoutError, new options gain defaults,
// provider callbacks arrive with a version bump — call-site shapes stay.
// (Canonical definitions in `contract.zig`; same names, same shapes.)
// ---------------------------------------------------------------------------

pub const version = contract.version;
pub const Profile = contract.Profile;
pub const max_input_len = contract.max_input_len;
pub const max_nesting_depth = contract.max_nesting_depth;
pub const max_expand = contract.max_expand;
pub const LayoutOptions = contract.LayoutOptions;
pub const RuleKind = contract.RuleKind;
pub const provider_version = contract.provider_version;
pub const MetricsProvider = contract.MetricsProvider;
pub const LayoutError = contract.LayoutError;
pub const Diag = contract.Diag;
pub const FontId = contract.FontId;

pub const profile: Profile =
    std.meta.stringToEnum(Profile, build_options.profile) orelse .full;

/// Reentrant layout path: `glyphs` backs every `Run.glyphs` slice in
/// the returned `Layout`. Zero heap allocations; `NoSpace` when any
/// caller buffer fills.
pub fn layoutFull(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
) LayoutError!ir.Layout {
    var diag = Diag.empty();
    return layoutInner(source, options, provider, runs, rules, glyphs, &diag);
}

/// Layout with KaTeX-parity diagnostics: on `Invalid`, `diag` carries
/// the failure offset and message.
pub fn layoutDiag(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
    diag: *Diag,
) LayoutError!ir.Layout {
    return layoutInner(source, options, provider, runs, rules, glyphs, diag);
}

/// Shared engine entry for the Zig and C surfaces (see `cabi.zig`).
pub fn layoutInner(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
    diag: *Diag,
) LayoutError!ir.Layout {
    if (source.len > max_input_len) return error.TooLong;
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, options.display_mode) catch |e| {
        // Offsets match KaTeX `ParseError.position` exactly: the
        // 0-based byte offset of the offending token (KaTeX's message
        // text adds 1 for humans; the property is the API contract).
        diag.offset = if (pc.err_pos > source.len) @intCast(source.len) else pc.err_pos;
        diag.message = pc.err_msg;
        return e;
    };
    var lc = engine.LayCtx.init(&pc, provider);
    const style: parse.Style = if (options.display_mode) .D else .T;
    return engine.layout(&lc, root, style, runs, rules, glyphs);
}

/// MathML Core serialization of one formula into caller-owned `out`.
/// Pure structural mapping over the parse tree — no layout math.
pub fn mathml(source: []const u8, options: LayoutOptions, out: []u8) LayoutError![]const u8 {
    return mathml_mod.render(source, options, out);
}

/// Lay out one formula into caller-owned buffers (zero allocations).
///
/// Deprecated in favor of `layoutFull` (energy, issue #154): `Run.glyphs`
/// slices borrow a shared process-wide 8K-glyph (16 KiB `.bss`) ring with
/// ctime-style borrow semantics — every `layout` call, from any caller,
/// may overwrite it, so a previous result's glyph slices are valid only
/// until the next `layout` call returns, and two live results can never
/// coexist (not reentrant, not thread-safe). New hosts must pass their
/// own glyph buffer to `layoutFull`; this wrapper stays only for
/// source compatibility and carries the 16 KiB resident cost.
pub fn layout(
    source: []const u8,
    options: LayoutOptions,
    provider: MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
) LayoutError!ir.Layout {
    const S = struct {
        var ring: [8192]u16 = undefined;
    };
    return layoutFull(source, options, provider, runs, rules, &S.ring);
}

test "profile option resolves to a known profile" {
    try std.testing.expect(@intFromEnum(profile) <= @intFromEnum(Profile.full));
}

test "empty input lays out empty" {
    const l = ir.Layout.empty();
    try std.testing.expectEqual(@as(u32, 0), l.width);
    try std.testing.expectEqual(@as(usize, 0), l.runs.len);
    try std.testing.expectEqual(@as(usize, 0), l.rules.len);
}

fn layoutOk(
    source: []const u8,
    options: LayoutOptions,
    runs_buf: []ir.Run,
    rules_buf: []ir.Rule,
    glyphs_buf: []u16,
) !ir.Layout {
    return layoutFull(source, options, testProvider(), runs_buf, rules_buf, glyphs_buf);
}

test "accept: single symbol lays out one run" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
    try std.testing.expect(l.width > 0);
}

test "accept: sup-sub scripts lay out" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("x^2_1", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(l.width > 0);
    try std.testing.expect(l.runs.len >= 2);
}

test "accept: greek and operators lay out" {
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("\\alpha+\\beta", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 3), l.runs.len);
}

test "accept: frac emits bar rule" {
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("\\frac{1}{2}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
}

test "accept: sqrt and sum lay out" {
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    _ = try layoutOk("\\sqrt{2}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    const l = try layoutOk("\\sum_{i=1}^{n} i", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(l.width > 0);
}

test "accept: unknown command is Invalid with offset" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var diag = Diag.empty();
    try std.testing.expectError(
        error.Invalid,
        layoutDiag("\\nope", .{}, testProvider(), &runs_buf, &rules_buf, &glyphs_buf, &diag),
    );
    // KaTeX parity: `ParseError.position` is the 0-based token start.
    try std.testing.expectEqual(@as(u32, 0), diag.offset);
}

test "accept: color, verb, and boxes lay out natively" {
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const cases = [_][]const u8{
        "\\color{red}{x}+y",
        "\\color{red}x+y",
        "\\textcolor{blue}{x}",
        "\\color{#f00}{x}",
        "\\verb|x|+\\verb*|a b|",
        "\\colorbox{yellow}{a+b}",
        "\\fcolorbox{red}{#ff0}{x}",
        "\\textbf{ab}+\\textit{cd}",
    };
    for (cases) |src| {
        _ = try layoutOk(src, .{}, &runs_buf, &rules_buf, &glyphs_buf);
    }
}

test "accept: unbalanced brace is Invalid" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var diag = Diag.empty();
    try std.testing.expectError(
        error.Invalid,
        layoutDiag("{x", .{}, testProvider(), &runs_buf, &rules_buf, &glyphs_buf, &diag),
    );
}

test "accept: macro loop errors ExpansionLimit" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    try std.testing.expectError(
        error.ExpansionLimit,
        layoutOk("\\def\\a{\\a}\\a", .{}, &runs_buf, &rules_buf, &glyphs_buf),
    );
}

test "accept: excessive nesting errors TooDeep" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    var deep: [80]u8 = undefined;
    @memset(&deep, '{');
    try std.testing.expectError(
        error.TooDeep,
        layoutOk(&deep, .{}, &runs_buf, &rules_buf, &glyphs_buf),
    );
}

test "adversarial inputs are total and deterministic" {
    // Seeded input soup plus structured worst cases: the engine must
    // always return (never hang or panic) and agree with itself.
    var runs_a: [64]ir.Run = undefined;
    var rules_a: [16]ir.Rule = undefined;
    var glyphs_a: [1024]u16 = undefined;
    var runs_b: [64]ir.Run = undefined;
    var rules_b: [16]ir.Rule = undefined;
    var glyphs_b: [1024]u16 = undefined;
    var mbuf_a: [2048]u8 = undefined;
    var mbuf_b: [2048]u8 = undefined;
    const pieces = [_][]const u8{ "x", "y", "2", "+", "-", "{", "}", "^", "_",
        "\\frac", "\\sum", "\\alpha", "\\text{a}",
        "(", ")", " ", "&", "#", "$", "\\left(", "\\", "~", ",", ";" };
    var prng = std.Random.DefaultPrng.init(0x5EED);
    var rnd = prng.random();
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        var buf: [256]u8 = undefined;
        var len: usize = 0;
        var k: usize = 0;
        const n = 1 + rnd.uintLessThan(usize, 24);
        while (k < n and len < buf.len) : (k += 1) {
            const pc = pieces[rnd.uintLessThan(usize, pieces.len)];
            const m = @min(pc.len, buf.len - len);
            @memcpy(buf[len..][0..m], pc[0..m]);
            len += m;
        }
        const src = buf[0..len];
        var da = Diag.empty();
        var db = Diag.empty();
        const r1 = layoutDiag(src, .{}, testProvider(), &runs_a, &rules_a, &glyphs_a, &da);
        const r2 = layoutDiag(src, .{}, testProvider(), &runs_b, &rules_b, &glyphs_b, &db);
        if (r1) |l1| {
            const l2 = try r2;
            try std.testing.expectEqual(l1.width, l2.width);
            try std.testing.expectEqual(l1.runs.len, l2.runs.len);
            try std.testing.expectEqual(l1.rules.len, l2.rules.len);
            try std.testing.expectEqual(da.offset, db.offset);
        } else |e1| {
            try std.testing.expectError(e1, r2);
            try std.testing.expect(da.offset <= src.len);
        }
        const m1 = mathml(src, .{}, &mbuf_a);
        const m2 = mathml(src, .{}, &mbuf_b);
        if (m1) |s1| {
            const s2 = try m2;
            try std.testing.expectEqualStrings(s1, s2);
        } else |e1| {
            try std.testing.expectError(e1, m2);
        }
    }
    // Structured worst cases with exact errors.
    var deep: [200]u8 = undefined;
    @memset(&deep, '{');
    try std.testing.expectError(error.TooDeep, layoutOk(&deep, .{}, &runs_a, &rules_a, &glyphs_a));
    var flat: [1401]u8 = undefined;
    var f: usize = 0;
    while (f < 700) : (f += 1) {
        flat[2 * f] = 'x';
        flat[2 * f + 1] = '+';
    }
    flat[1400] = 'x';
    try std.testing.expectError(error.NoSpace, layoutOk(&flat, .{}, &runs_a, &rules_a, &glyphs_a));
    // Exponential blowup fills the token pool before the expansion counter trips:
    // still an error, honestly reported as pool exhaustion.
    try std.testing.expectError(error.NoSpace, layoutOk("\\def\\a{\\a\\a}\\a", .{}, &runs_a, &rules_a, &glyphs_a));
    var bad: [4]u8 = .{ 'x', 0xFF, '+', 'y' };
    if (layoutOk(&bad, .{}, &runs_a, &rules_a, &glyphs_a)) |_| return error.TestUnexpectedResult else |_| {}
}
test "accept: user macro expands" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("\\newcommand{\\f}{x}\\f", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
}

test "accept: mathml maps frac structurally" {
    var out: [256]u8 = undefined;
    const s = try mathml("\\frac12", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mfrac>") != null);
}

test "accept: empty input lays out empty" {
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [32]u16 = undefined;
    const l = try layoutOk("", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 0), l.width);
}

test "sqrt radicand is cramped: sup sits 30mu lower than top level" {
    // TeX sets the radicand in cramped style (issue #20 Dc grid rows):
    // a sup directly inside `\sqrt{...}` rises 30mu less than at top
    // level. Resolved by glyph id through the stub provider
    // (mathit x = U+1D465 -> 0xD465, '2' = 50, radical U+221A = 8730).
    const S = struct {
        fn raise(l: ir.Layout) !i32 {
            var yx: ?i32 = null;
            var y2: ?i32 = null;
            for (l.runs) |r| {
                for (r.glyphs) |g| {
                    if (g == 0xD465 and yx == null) yx = r.baseline_y;
                    if (g == 50 and y2 == null) y2 = r.baseline_y;
                }
            }
            return (yx orelse return error.TestUnexpectedResult) -
                (y2 orelse return error.TestUnexpectedResult);
        }
    };
    var runs_a: [32]ir.Run = undefined;
    var rules_a: [8]ir.Rule = undefined;
    var glyphs_a: [128]u16 = undefined;
    var runs_b: [32]ir.Run = undefined;
    var rules_b: [8]ir.Rule = undefined;
    var glyphs_b: [128]u16 = undefined;
    const top = try layoutOk("x^2", .{}, &runs_a, &rules_a, &glyphs_a);
    const rad = try layoutOk("\\sqrt{x^2}", .{}, &runs_b, &rules_b, &glyphs_b);
    try std.testing.expectEqual(@as(i32, 400), try S.raise(top));
    try std.testing.expectEqual(try S.raise(top) - 30, try S.raise(rad));
}

test "caller buffers: exhaustion is NoSpace, never panic" {
    // Every truncation point on the layout path reports honestly.
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    var runs1: [1]ir.Run = undefined;
    try std.testing.expectError(
        error.NoSpace,
        layoutFull("\\frac{a}{b}+x", .{}, testProvider(), &runs1, &rules_buf, &glyphs_buf),
    );
    var rules0: [0]ir.Rule = undefined;
    try std.testing.expectError(
        error.NoSpace,
        layoutFull("\\frac{a}{b}", .{}, testProvider(), &runs_buf, &rules0, &glyphs_buf),
    );
    var glyphs3: [3]u16 = undefined;
    try std.testing.expectError(
        error.NoSpace,
        layoutFull("wxyz", .{}, testProvider(), &runs_buf, &rules_buf, &glyphs3),
    );
    var mbuf: [8]u8 = undefined;
    try std.testing.expectError(error.NoSpace, mathml("\\frac{a}{b}", .{}, &mbuf));
    // Empty input needs nothing: zero-length buffers still serve it.
    var runs0: [0]ir.Run = undefined;
    var rules00: [0]ir.Rule = undefined;
    var glyphs0: [0]u16 = undefined;
    const l = try layoutFull("", .{}, testProvider(), &runs0, &rules00, &glyphs0);
    try std.testing.expectEqual(@as(u32, 0), l.width);
}

test "adversarial provider: graceful and deterministic" {
    // Zero/negative advances, degenerate rule weights, and missing
    // glyphs must never panic: the engine returns (ok or LayoutError)
    // and agrees with itself on a second run.
    const P = struct {
        adv_val: i32 = 500,
        rule_val: i32 = 40,
        no_glyphs: bool = false,
        fn gid(ctx: *const anyopaque, _: u16, cp: u21) u16 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            if (self.no_glyphs) return 0;
            return @intCast(cp & 0xFFFF);
        }
        fn adv(ctx: *const anyopaque, _: u16, _: u16) i32 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.adv_val;
        }
        fn rule(ctx: *const anyopaque, _: u16, _: RuleKind) i32 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.rule_val;
        }
    };
    const cfgs = [_]P{
        .{ .adv_val = 0 },
        .{ .adv_val = -500 },
        .{ .rule_val = 1_000_000 },
        .{ .rule_val = 0 },
        .{ .rule_val = -40 },
        .{ .no_glyphs = true },
    };
    const formulas = [_][]const u8{ "x+\\frac{a}{b}", "\\sum_{i}^{n}\\sqrt{x_i}" };
    for (cfgs) |cfg| {
        var holder = cfg;
        const prov: MetricsProvider = .{
            .ctx = &holder,
            .glyphId = P.gid,
            .advance = P.adv,
            .ruleThickness = P.rule,
        };
        for (formulas) |src| {
            var ra: [64]ir.Run = undefined;
            var la: [16]ir.Rule = undefined;
            var ga: [512]u16 = undefined;
            var rb: [64]ir.Run = undefined;
            var lb: [16]ir.Rule = undefined;
            var gb: [512]u16 = undefined;
            var da = Diag.empty();
            var db = Diag.empty();
            const r1 = layoutDiag(src, .{}, prov, &ra, &la, &ga, &da);
            const r2 = layoutDiag(src, .{}, prov, &rb, &lb, &gb, &db);
            if (r1) |l1| {
                const l2 = try r2;
                try std.testing.expectEqual(l1.width, l2.width);
                try std.testing.expectEqual(l1.height_above, l2.height_above);
                try std.testing.expectEqual(l1.depth_below, l2.depth_below);
                try std.testing.expectEqual(l1.runs.len, l2.runs.len);
                try std.testing.expectEqual(l1.rules.len, l2.rules.len);
            } else |e1| {
                try std.testing.expectError(e1, r2);
            }
        }
    }
}

test "oversize input errors TooLong before anything else" {
    var big: [max_input_len + 1]u8 = .{'x'} ** (max_input_len + 1);
    var runs_buf: [8]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    try std.testing.expectError(
        error.TooLong,
        layout(&big, .{}, testProvider(), &runs_buf, &rules_buf),
    );
}

test "issue36: text-mode spacing commands emit space, not glyphs" {
    // KaTeX parity (pinned 0.18.7): `\,`/`\:`/`\;`/`\>`/`\!` inside
    // `\text` (and `\llap` bodies, which are text mode) produce spacing
    // (`mspace`), never literal `,`/`:`/`;` glyphs.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const cases = [_]struct { src: []const u8, w: u32 }{
        .{ .src = "\\text{/\\,}", .w = 500 + 167 },
        .{ .src = "\\text{a\\;b}", .w = 500 + 278 + 500 },
        .{ .src = "\\text{a\\:b}", .w = 500 + 222 + 500 },
        .{ .src = "\\text{a\\>b}", .w = 500 + 222 + 500 },
        .{ .src = "\\text{a\\!b}", .w = 500 - 167 + 500 },
    };
    for (cases) |c| {
        const l = try layoutOk(c.src, .{}, &runs_buf, &rules_buf, &glyphs_buf);
        try std.testing.expectEqual(c.w, l.width);
        for (l.runs) |r| {
            for (r.glyphs) |g| {
                try std.testing.expect(g != @as(u16, ','));
                try std.testing.expect(g != @as(u16, ':'));
                try std.testing.expect(g != @as(u16, ';'));
            }
        }
    }
    // Math-mode thin/med pins (KaTeX 0.1667em / 0.2222em).
    const m1 = try layoutOk("a\\,\\,{b}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 2 * 167 + 500), m1.width);
    const m2 = try layoutOk("a\\:\\:{b}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 2 * 222 + 500), m2.width);
    // `{=}\llap{/\,}`: slash overlapped left, no comma ink (KaTeX shows
    // no comma here — the `\,` is text-mode space).
    const l = try layoutOk("{=}\\llap{/\\,}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500), l.width);
    var saw_slash = false;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g == @as(u16, '/')) saw_slash = true;
            try std.testing.expect(g != @as(u16, ','));
        }
    }
    try std.testing.expect(saw_slash);
}

test "issue38: text-mode dot/caron/double-acute accents render" {
    // KaTeX accepts `\.`, `\v`, `\H` inside `\text` (pinned 0.18.7 renders
    // an overlaid accent); the engine precomposes when a single codepoint
    // exists and overlays the spacing accent otherwise.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    // `\v{s}` / `\H{o}` precompose (U+0161 / U+0151) and take the fast
    // path; these have no precomposed form, so they overlay.
    const cases = [_][]const u8{
        "\\text{\\.{a}}",
        "\\text{\\v{e}}",
        "\\text{\\H{a}}",
    };
    for (cases) |src| {
        const l = try layoutOk(src, .{}, &runs_buf, &rules_buf, &glyphs_buf);
        // Accent ink overhangs without advancing: width is the base width.
        try std.testing.expectEqual(@as(u32, 500), l.width);
        try std.testing.expect(l.height_above > 700);
    }
    // Precompose fast path still a single glyph (`\~n` -> U+00F1).
    const l = try layoutOk("\\text{\\~n}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.runs.len);
    try std.testing.expectEqual(@as(u16, 0x00F1), l.runs[0].glyphs[0]);
}

test "issue36: liminf and limsup carry a thin space" {
    // KaTeX parity (pinned 0.18.7 expands `\liminf` to
    // `\operatorname*{lim\,inf}`): the two words are separated by a
    // thin space, not run together.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("\\liminf", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 3 * 500 + 167 + 3 * 500), l.width);
    const s = try layoutOk("\\limsup", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 3 * 500 + 167 + 3 * 500), s.width);
}

test "issue37: overbrace spans its nucleus and carries its label" {
    // KaTeX parity: the brace stretches to the nucleus span (never
    // narrower, never contributing extra width); `\overbrace{...}^`
    // centers its label above like limits (pinned 0.18.7 nested
    // `mover`), and symmetrically below for `\underbrace{...}_`.
    const P = struct {
        fn gid(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: *const anyopaque, _: u16, glyph: u16) i32 {
            if (glyph == 0x23DE or glyph == 0x23DF) return 900;
            return 500;
        }
        fn rule(_: *const anyopaque, _: u16, _: RuleKind) i32 {
            return 40;
        }
    };
    const prov: MetricsProvider = .{
        .ctx = &.{},
        .glyphId = P.gid,
        .advance = P.adv,
        .ruleThickness = P.rule,
    };
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const o = try layoutFull("\\overbrace{AB}", .{}, prov, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1000), o.width);
    const u = try layoutFull("\\underbrace{AB}", .{}, prov, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1000), u.width);
    // `1+2`: 500 + med + 500 + med + 500 = 1944; label `100` in
    // script style is 3 * 350 = 1050. Stacked, the brace span wins.
    const l = try layoutOk("\\overbrace{1+2}^{100}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1944), l.width);
    try std.testing.expect(l.height_above > 700 + 150);
    const d = try layoutOk("\\underbrace{1+2}_{100}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1944), d.width);
    try std.testing.expect(d.depth_below > 250 + 150);
}

test "issue37: sqrt root index is scriptscript, raised and tucked" {
    // KaTeX parity (pinned 0.18.7 `sqrt.js`, TeX `\r@@t`): the index
    // is always scriptscript (size 500, not 700), raised 0.6 x (body
    // height - depth) above the baseline, tucked with +5mu / -10mu
    // bearings. Stub arithmetic for `\sqrt[3]{x}` (text style, so
    // phi = theta = 40): clearance0 = 40 + 40/4 = 50, and the stub
    // surd (950 tall) fits without the overshoot split, so rule_top
    // = 700 + 50 + 40 = 790. Body depth 250, so the `3` baseline
    // sits 6*(790-250)/10 = 324 above the main baseline (absolute y
    // 790-324 = 466); bearings 277/-555 against a 250-wide index
    // normalize the body to x 0 with the index at 305, and the width
    // equals the plain root.
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const l = try layoutOk("\\sqrt[3]{x}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    var pruns_buf: [32]ir.Run = undefined;
    var prules_buf: [8]ir.Rule = undefined;
    var pglyphs_buf: [128]u16 = undefined;
    const p = try layoutOk("\\sqrt{x}", .{}, &pruns_buf, &prules_buf, &pglyphs_buf);
    try std.testing.expectEqual(p.width, l.width);
    try std.testing.expectEqual(@as(u32, 1090), l.width);
    // NOTE: the two layouts use separate glyph buffers — sharing one
    // would clobber `l`'s glyph slices when `p` is laid out.
    var saw_index = false;
    var saw_x = false;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g == @as(u16, '3')) {
                try std.testing.expectEqual(@as(u16, 500), r.size_units);
                try std.testing.expectEqual(@as(i32, 305), r.x);
                try std.testing.expectEqual(@as(i32, 466), r.baseline_y);
                saw_index = true;
            }
            if (g == @as(u16, 0xD465)) {
                try std.testing.expectEqual(@as(i32, 550), r.x);
                // Absolute from the ink-box top: the radicand sits at
                // dy 0, so its baseline is the box height (rule_top).
                try std.testing.expectEqual(@as(i32, 790), r.baseline_y);
                saw_x = true;
            }
        }
    }
    try std.testing.expect(saw_index and saw_x);
}

test "issue37: rule dimensions and raise pin the IR rect" {
    // KaTeX parity: `\rule[raise]{w}{h}` is a filled rect spanning
    // [raise, raise + h] above the baseline — never below it (the
    // bracket is a vertical raise, not depth). `x\rule[6pt]{2ex}{1ex}x`
    // in text style: 6pt = 600, 2ex = 1000 wide, 1ex = 500 tall, so
    // the rect is 1000x500 at the ink-box top between the two x runs.
    // (Whether the rasterizer fills or outlines that rect belongs to
    // the PNG backend, not the layout core.)
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const l = try layoutOk("x\\rule[6pt]{2ex}{1ex}x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 1000 + 500), l.width);
    try std.testing.expectEqual(@as(u32, 600 + 500), l.height_above);
    try std.testing.expectEqual(@as(u32, 250), l.depth_below);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
    try std.testing.expectEqual(@as(i32, 500), l.rules[0].x);
    try std.testing.expectEqual(@as(i32, 0), l.rules[0].y);
    try std.testing.expectEqual(@as(u32, 1000), l.rules[0].w);
    try std.testing.expectEqual(@as(u32, 500), l.rules[0].h);
}

test "issue35: color threads from parse to native runs and rules" {
    // KaTeX parity: `\color` paints its body (nested scopes win);
    // `\colorbox`/`\fcolorbox` paint background (and frame) rules.
    // Colors ride IR runs/rules as 0xRRGGBBAA (null = ambient).
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [16]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const r = try layoutOk("\\color{#f00}{x}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(?u32, 0xFF0000FF), r.runs[0].color);
    const n = try layoutOk("\\color{red}{\\color{#0f0}{x}}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(?u32, 0x00FF00FF), n.runs[0].color);
    const u = try layoutOk("x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(?u32, null), u.runs[0].color);
    // `\color` scopes over the rest of the enclosing group (KaTeX:
    // `\color{blue}{a}b` paints `b` too), so one run covers both.
    const s = try layoutOk("\\color{blue}{a}b", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), s.runs.len);
    try std.testing.expectEqual(@as(?u32, 0x0000FFFF), s.runs[0].color);
    // Color boundaries split runs (same font, different paint).
    const m = try layoutOk("\\color{blue}{a}\\color{red}{b}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 2), m.runs.len);
    try std.testing.expectEqual(@as(?u32, 0x0000FFFF), m.runs[0].color);
    try std.testing.expectEqual(@as(?u32, 0xFF0000FF), m.runs[1].color);
    // Boxes: background (+frame) rules carry their colors; the text
    // inside keeps the ambient (null) paint.
    const b = try layoutOk("\\colorbox{yellow}{x}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(b.rules.len >= 1);
    try std.testing.expectEqual(@as(?u32, 0xFFFF00FF), b.rules[0].color);
    const f = try layoutOk("\\fcolorbox{red}{yellow}{x}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    var saw_frame = false;
    var saw_bg = false;
    for (f.rules) |rl| {
        if (rl.color != null and rl.color.? == 0xFF0000FF) saw_frame = true;
        if (rl.color != null and rl.color.? == 0xFFFF00FF) saw_bg = true;
    }
    try std.testing.expect(saw_frame and saw_bg);
}

test "issue34: alphabet commands request distinct provider fonts" {
    // The core requests one font id per alphabet command through the
    // provider callback, AND resolves the ASCII codepoint into the
    // Mathematical Alphanumeric block for the single-file host
    // (issues #57/#62 — KaTeX switches typefaces, we remap). The
    // test provider truncates cp to gid 1:1, so the remap is visible
    // below (e.g. mathbf A -> U+1D400 -> 0xD400). The same-roman
    // renders in the issue are the host backend ignoring `font_id`
    // (`zatex-png/src/font.zig` maps every request to one font).
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const cases = [_]struct { src: []const u8, font: u16, cp: u16 }{
        .{ .src = "\\mathbf{A}", .font = 2, .cp = 0xD400 },
        .{ .src = "\\mathcal{A}", .font = 8, .cp = 0xD49C },
        .{ .src = "\\mathscr{A}", .font = 6, .cp = 0xD49C },
        .{ .src = "\\mathfrak{A}", .font = 5, .cp = 0xD504 },
        .{ .src = "\\mathsf{A}", .font = 3, .cp = 0xD5A0 },
        .{ .src = "\\mathtt{A}", .font = 4, .cp = 0xD670 },
        .{ .src = "\\mathbb{A}", .font = 7, .cp = 0xD538 },
        .{ .src = "\\Bbb{A}", .font = 7, .cp = 0xD538 },
        // `\boldsymbol` is `\bm` (issue #94, pinned 0.18.7):
        // bold-italic A -> U+1D468 -> 0xD468 on font 9.
        .{ .src = "\\boldsymbol{A}", .font = 9, .cp = 0xD468 },
        // Nested alphabets: the innermost command wins (KaTeX).
        .{ .src = "\\mathbf{\\mathcal{R}}", .font = 8, .cp = 0x211B },
        .{ .src = "\\mathcal{\\mathbf{R}}", .font = 2, .cp = 0xD411 },
    };
    for (cases) |c| {
        const l = try layoutOk(c.src, .{}, &runs_buf, &rules_buf, &glyphs_buf);
        try std.testing.expectEqual(@as(usize, 1), l.runs.len);
        try std.testing.expectEqual(c.font, l.runs[0].font_id);
        try std.testing.expectEqual(c.cp, l.runs[0].glyphs[0]);
    }
    // Digits ride the same request (`\mathbf{1}` keeps font 2).
    const d = try layoutOk("\\mathbf{1}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u16, 2), d.runs[0].font_id);
    // Dotless `\imath` requests U+0131, never ASCII `i` (the
    // identical render in the issue is backend font coverage).
    const i = try layoutOk("\\imath", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u16, 0x0131), i.runs[0].glyphs[0]);
}

test "issue33: matrix column gaps match KaTeX separation" {
    // KaTeX parity (pinned 0.18.7 `array.ts`): default columns carry
    // 0.5em each side (1em between, none outside); `array` adds outer
    // halves; `aligned` rl pairs touch; `cases` separates with 1em.
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const m = try layoutOk("\\begin{matrix}a&b\\end{matrix}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1500 + 1500), m.width);
    const a = try layoutOk("\\begin{array}{cc}a&b\\end{array}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 1500 + 1500 + 500), a.width);
    // `aligned` rl pairs touch (the `=` cell keeps its own Rel glue;
    // KaTeX shows the same empty-mord + thick space before `=`).
    const al = try layoutOk("\\begin{aligned}a&=b\\end{aligned}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 278 + 500 + 278 + 500), al.width);
    // `cases` wraps the env in a `\{` fence (500): env columns are
    // 500 + 1em gap + 500.
    const c = try layoutOk("\\begin{cases}a&b\\end{cases}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 500 + 1000 + 500), c.width);
}

test "issue33: tables center on the math axis" {
    // KaTeX centers tables on the axis (pinned 0.18.7 `delimcenter`
    // + axis strut); delimiters previously rode high because the
    // table sat on its first-row baseline.
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const p = try layoutOk("\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(p.height_above > 250);
    try std.testing.expectEqual(p.height_above - 250, p.depth_below + 250);
}

test "issue33: hline and hdashline render row rules" {
    // Row-leading rule commands belong to the row gap (KaTeX
    // `getHLines` parity); `\\hdashline` draws dashes. Mid-row rules
    // are misplaced (KaTeX parity error).
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [16]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    const h = try layoutOk("\\begin{array}{c}a\\\\\\hline b\\end{array}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), h.rules.len);
    try std.testing.expectEqual(h.width, h.rules[0].w);
    const d = try layoutOk("\\begin{array}{c}a\\\\\\hdashline b\\end{array}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(d.rules.len > 1);
    // Dashes tile the full table width in order.
    try std.testing.expectEqual(@as(i32, 0), d.rules[0].x);
    var end: i32 = 0;
    for (d.rules) |r| {
        try std.testing.expect(r.x >= end);
        end = r.x + @as(i32, @intCast(r.w));
    }
    try std.testing.expectEqual(@as(i32, @intCast(d.width)), end);
    var diag = Diag.empty();
    try std.testing.expectError(error.Invalid, layoutDiag("\\begin{matrix}a&\\hline b\\\\c&d\\end{matrix}", .{}, testProvider(), &runs_buf, &rules_buf, &glyphs_buf, &diag));
}

test "issue32: fraction shifts follow TeX rules 15b-e per style" {
    // KaTeX parity (pinned 0.18.7 `genfrac.ts`, Main metrics in
    // thousandths): text bar fractions use num2/denom2 (394/345) with
    // clearance θ; display uses num1/denom1 (677/686) with 3θ; atop
    // uses num3 (444) with 7θ/3θ. Stub extents are uniform (700/250),
    // rule thickness 40, axis 250.
    var runs_buf: [32]ir.Run = undefined;
    var rules_buf: [8]ir.Rule = undefined;
    var glyphs_buf: [128]u16 = undefined;
    // Text `\frac{a}{b}`: content is script-sized (S: 490/175 under
    // stub extents); the numerator clearance bump applies.
    // ns = 394 + (40 - ((394-175) - (250+20))) = 485; ds = 345.
    const t = try layoutOk("\\frac{a}{b}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), t.rules.len);
    try std.testing.expectEqual(@as(u32, 485 + 490), t.height_above);
    try std.testing.expectEqual(@as(u32, 345 + 175), t.depth_below);
    // Display `\dfrac{a}{b}` in text mode: content is text-sized,
    // shifts are num1/denom1 (677/686), clearance 3θ, no bumps.
    const d = try layoutOk("\\dfrac{a}{b}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 677 + 700), d.height_above);
    try std.testing.expectEqual(@as(u32, 686 + 250), d.depth_below);
    // Atop `\binom{n}{k}`: num3/denom2 (444/345), 3θ clearance met
    // exactly (no bump). Fence ink overflows the content box by
    // design when the provider offers no bigger variant
    // (`wrapFence`: instruments are promises, not extents).
    const b = try layoutOk("\\binom{n}{k}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 444 + 490), b.height_above);
    try std.testing.expectEqual(@as(u32, 345 + 175), b.depth_below);
    try std.testing.expectEqual(@as(usize, 0), b.rules.len);
}

test "issue31: accents never contribute width; wide accents span the base" {
    // KaTeX parity: narrow accents sit in a zero-width `accent-body`
    // (an accent wider than its base overhangs symmetrically); wide
    // (`\widehat` etc.) accents stretch to the nucleus span. Either
    // way the construction is exactly as wide as the nucleus.
    const P = struct {
        fn gid(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn adv(_: *const anyopaque, _: u16, glyph: u16) i32 {
            if (glyph == 0x5E or glyph == 0x7E or glyph == 0x2C7) return 900;
            return 500;
        }
        fn rule(_: *const anyopaque, _: u16, _: RuleKind) i32 {
            return 40;
        }
    };
    const prov: MetricsProvider = .{
        .ctx = &.{},
        .glyphId = P.gid,
        .advance = P.adv,
        .ruleThickness = P.rule,
    };
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const n = try layoutFull("\\hat{x}", .{}, prov, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500), n.width);
    const w = try layoutFull("\\widehat{AB}", .{}, prov, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1000), w.width);
    const t = try layoutFull("\\widetilde{AB}", .{}, prov, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1000), t.width);
    const c = try layoutFull("\\widecheck{AB}", .{}, prov, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 1000), c.width);
}

test "issue30: narrow accents tuck to within an x-height of the base" {
    // KaTeX parity (pinned 0.18.7 `accent.ts`): clearance =
    // min(body height, x-height); the accent ink bottom sits that far
    // below the body top — accents no longer float 120 units above.
    // Stub extents are uniform (700/250), x-height is 431.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const h = try layoutOk("\\hat{x}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 700 - 431 + 250 + 700), h.height_above);
    // Same rule for every narrow accent: dot, bar, breve, check, grave,
    // ring, tilde, vec all tuck identically under stub metrics (real
    // providers differentiate through each accent's own extents).
    const d = try layoutOk("\\dot{x}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(h.height_above, d.height_above);
    const v = try layoutOk("\\vec{F}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(h.height_above, v.height_above);
}

test "issue37: rule raise shifts the bar up, not down" {
    // KaTeX parity: `\rule[6pt]{2ex}{1ex}` raises a 1ex bar by 6pt
    // (`bottom:0.6em`); the bracket is a raise, never depth below the
    // baseline. ex = 500 units (documented approximation).
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("x\\rule[6pt]{2ex}{1ex}x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
    const r = l.rules[0];
    try std.testing.expectEqual(@as(u32, 1000), r.w);
    try std.testing.expectEqual(@as(u32, 500), r.h);
    // Bar bottom sits 600 above the baseline: y + h == base - 600.
    const base = @as(i32, @intCast(l.height_above));
    try std.testing.expectEqual(base - 600, r.y + @as(i32, @intCast(r.h)));
    const u = try layoutOk("x\\rule{2ex}{1ex}x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500), u.rules[0].h);
    const ubase = @as(i32, @intCast(u.height_above));
    try std.testing.expectEqual(ubase, u.rules[0].y + @as(i32, @intCast(u.rules[0].h)));
}

test "issue36: forced limits stack even in text style" {
    // KaTeX parity: `\lim\limits_x` stacks in text style (pinned 0.18.7
    // renders `mop op-limits`); only default limits need display style.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const l = try layoutOk("\\lim\\limits_x", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 3 * 500), l.width);
    try std.testing.expect(l.depth_below > 0);
    // `\nolimits` keeps display-style subs to the side.
    const n = try layoutOk("\\sum\\nolimits_{i} x", .{ .display_mode = true }, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(n.width > 500);
}

test "issue36: kern and overlap primitives measure like KaTeX" {
    // `\kern-2.5pt` (-250 units); laps take no width; `\mathclap`
    // centers zero-width content under its base.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const k = try layoutOk("I\\kern-2.5pt R", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 - 250 + 500), k.width);
    const ll = try layoutOk("\\llap{x}y", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500), ll.width);
    const rl = try layoutOk("\\rlap{\\,/}{=}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    // rlap ink (slash + thin space) takes no width; `=` keeps its own.
    try std.testing.expectEqual(@as(u32, 500), rl.width);
    const mc = try layoutOk("\\sum_{\\mathclap{1\\le i\\le n}} x_{i}", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expect(mc.width > 0);
    try std.testing.expect(mc.depth_below > 0);
}

test "issue36: not overlays the following symbol with no extra width" {
    // KaTeX parity (pinned 0.18.7): `\not` is a zero-width Rel overlay
    // (`\mathrel{\mathrlap\@not}\nobreak`); `\not =` is exactly as wide
    // as `=`, and `a\not\in b` keeps only the Rel side bearings.
    var runs_buf: [16]ir.Run = undefined;
    var rules_buf: [4]ir.Rule = undefined;
    var glyphs_buf: [64]u16 = undefined;
    const eq = try layoutOk("=", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    const ne = try layoutOk("\\not =", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(eq.width, ne.width);
    var saw_slash = false;
    for (ne.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 0x338) saw_slash = true;
        }
    }
    try std.testing.expect(saw_slash);
    const l = try layoutOk("a\\not\\in b", .{}, &runs_buf, &rules_buf, &glyphs_buf);
    try std.testing.expectEqual(@as(u32, 500 + 278 + 500 + 278 + 500), l.width);
}

fn testProvider() MetricsProvider {
    const S = struct {
        fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn ruleThickness(_: *const anyopaque, _: u16, _: RuleKind) i32 {
            return 40;
        }
    };
    return .{
        .ctx = &.{},
        .glyphId = S.glyphId,
        .advance = S.advance,
        .ruleThickness = S.ruleThickness,
    };
}
