//! Host metrics conformance check (issue #194).
//!
//! A diagnostic corpus with reference-font (Latin Modern Math)
//! expectations, callable against an arbitrary host-constructed
//! provider at the C ABI level — no engine rebuild, no rendering.
//! Each probe that mismatches emits one named diagnostic line;
//! zero lines is a clean pass (`CheckResult.diagnostics`).
//!
//! The corpus reuses the calibration ground truth (`refhost.zig`
//! `calibration:` tests, the fontTools cross-checks in `otmath.zig`)
//! instead of inventing new numbers: zero-width combining marks,
//! slanted italic nuclei, capitals, `.notdef`, a tall delimiter,
//! the four rule weights, and representative ink boxes.
//!
//! Value pins are calibrated for `rm` (font 0) on the reference
//! stack. Other font ids run the same probes with the same
//! expectations: differences report by name (font, codepoint, got,
//! want) so multi-face hosts can triage them — e.g. a text face
//! without a MATH table legitimately reports no italic there, and
//! KaTeX-face advances mostly coincide with LM by design, except
//! noted cases (`~`).

const std = @import("std");
const contract = @import("contract.zig");
const ir = @import("ir.zig");
const parse = @import("parse.zig");
const engine = @import("layout.zig");

/// Upper bound on emitted diagnostic lines. The count is still exact
/// past the cap (and past the caller's buffer): lines that do not fit
/// are dropped, never truncated mid-line.
pub const max_diagnostics: usize = 40;

// ---------------------------------------------------------------------------
// Corpus (reference-font ground truth; see module doc).
// ---------------------------------------------------------------------------

/// Combining marks whose file advance is 0 (the 500-for-zero trap).
const zero_advance_cps: []const u21 = &.{
    0x20D7, 0x0300, 0x0301, 0x0302, 0x0303, 0x0308, 0x20D0, 0x20DB,
};

const AdvPin = struct {
    cp: u21,
    want: i32,
};

/// Exact advances at 1000 units (all fixtures are 1000 upm).
const advance_pins: []const AdvPin = &.{
    .{ .cp = 'A', .want = 750 },
    .{ .cp = 'F', .want = 653 },
    .{ .cp = '0', .want = 500 },
    .{ .cp = 0x221A, .want = 833 },
    .{ .cp = '(', .want = 389 },
    .{ .cp = 0x1D466, .want = 490 },
    .{ .cp = 0x1D465, .want = 572 },
    .{ .cp = 0x1D400, .want = 869 },
    .{ .cp = 0x203E, .want = 512 },
    .{ .cp = '~', .want = 556 },
};

const ItalicPin = struct {
    cp: u21,
    want: i32,
};

/// MATH italic corrections at 1000 units.
const italic_pins: []const ItalicPin = &.{
    .{ .cp = 0x1D466, .want = 28 },
    .{ .cp = '~', .want = 27 },
    .{ .cp = 'x', .want = 16 },
};

const InkPin = struct {
    cp: u21,
    want: [4]i32,
};

/// True ink boxes at 1000 units, y up (fontTools BoundsPen).
const ink_pins: []const InkPin = &.{
    .{ .cp = 0x20D7, .want = .{ -472, 521, -56, 711 } },
    .{ .cp = '~', .want = .{ 0, 193, 555, 307 } },
    .{ .cp = 0x02C7, .want = .{ 98, 516, 402, 692 } },
    .{ .cp = 0x221A, .want = .{ 73, -960, 853, 40 } },
};

const RulePin = struct {
    kind: contract.RuleKind,
    name: []const u8,
    want: i32,
};

/// MATH rule constants (all 40 in LM; a missing table falls back here).
const rule_pins: []const RulePin = &.{
    .{ .kind = .fraction_bar, .name = "fraction", .want = 40 },
    .{ .kind = .radical, .name = "radical", .want = 40 },
    .{ .kind = .overline, .name = "overbar", .want = 40 },
    .{ .kind = .underline, .name = "underbar", .want = 40 },
};

/// Every corpus codepoint must resolve (`.notdef` has its own probe).
const coverage_cps: []const u21 = &.{
    0x20D7, 0x0300, 0x0301, 0x0302, 0x0303, 0x0308, 0x20D0, 0x20DB,
    'A',  'F',  '0', 0x221A, '(', 0x1D466, 0x1D465, 0x1D400,
    0x203E, '~', 'x', 0x02C7,
};

/// Unassigned codepoint for the `.notdef` probe (issue #142: missing
/// maps to glyph 0 exactly).
const notdef_cp: u21 = 0x10FFFF;

/// Tall-delimiter probe: paren must grow at this height.
const variant_cp: u21 = '(';
const variant_height: i32 = 5000;

// ---------------------------------------------------------------------------
// Line writer (hand-rolled: keeps the shipped artifact small).
// ---------------------------------------------------------------------------

const Writer = struct {
    buf: []u8,
    pos: usize,
    count: usize,
    frozen: bool,

    fn line(w: *Writer, tmp: []const u8) void {
        w.count += 1;
        if (w.frozen) return;
        if (w.count > max_diagnostics) {
            w.frozen = true;
            return;
        }
        if (w.pos + tmp.len + 1 > w.buf.len) {
            w.frozen = true;
            return;
        }
        @memcpy(w.buf[w.pos..][0..tmp.len], tmp);
        w.pos += tmp.len;
        w.buf[w.pos] = '\n';
        w.pos += 1;
    }
};

const Line = struct {
    bytes: [160]u8 = undefined,
    len: usize = 0,

    fn text(l: *Line, s: []const u8) void {
        @memcpy(l.bytes[l.len..][0..s.len], s);
        l.len += s.len;
    }

    fn decU32(l: *Line, v: u32) void {
        var tmp: [10]u8 = undefined;
        var n: usize = 0;
        var x = v;
        if (x == 0) {
            tmp[0] = '0';
            n = 1;
        } else {
            var rev: [10]u8 = undefined;
            while (x > 0) : (n += 1) {
                rev[n] = @intCast(x % 10 + '0');
                x /= 10;
            }
            var i: usize = 0;
            while (i < n) : (i += 1) tmp[i] = rev[n - 1 - i];
        }
        l.text(tmp[0..n]);
    }

    fn decI32(l: *Line, v: i32) void {
        if (v < 0) {
            l.text("-");
            if (v == std.math.minInt(i32)) {
                // Total on hostile providers: no negation overflow.
                l.text("2147483648");
            } else {
                l.decU32(@intCast(-v));
            }
        } else {
            l.decU32(@intCast(v));
        }
    }

    fn cp(l: *Line, code: u21) void {
        l.text("U+");
        var tmp: [6]u8 = undefined;
        var n: usize = 0;
        var x: u32 = code;
        if (x == 0) {
            tmp[0] = '0';
            n = 1;
        } else {
            var rev: [6]u8 = undefined;
            while (x > 0) : (n += 1) {
                const d: u8 = @intCast(x & 0xF);
                rev[n] = if (d < 10) '0' + d else 'A' + (d - 10);
                x >>= 4;
            }
            var i: usize = 0;
            while (i < n) : (i += 1) tmp[i] = rev[n - 1 - i];
        }
        const digits = n;
        while (n < 4) : (n += 1) l.text("0");
        l.text(tmp[0..digits]);
    }
};

// ---------------------------------------------------------------------------
// Probes.
// ---------------------------------------------------------------------------

pub const CheckResult = struct {
    /// Diagnostic count (0 is a clean pass); exact past the line cap
    /// and past the caller's buffer.
    diagnostics: usize,
    /// Bytes written to `buf` (whole lines only).
    bytes: usize,
};

/// Check `prov` at `font`; write newline-separated diagnostics into
/// `buf`. Layout smoke runs only when every hook probe is clean, so
/// absurd metrics fail named before they can reach the engine.
pub fn check(prov: contract.MetricsProvider, font: u16, buf: []u8) CheckResult {
    var w = Writer{ .buf = buf, .pos = 0, .count = 0, .frozen = false };

    for (coverage_cps) |code| {
        if (prov.glyphId(prov.ctx, font, code) == 0) {
            var l = Line{};
            l.text("coverage ");
            l.cp(code);
            l.text(" font ");
            l.decU32(font);
            l.text(": gid 0 (missing)");
            w.line(l.bytes[0..l.len]);
        }
    }

    for (zero_advance_cps) |code| {
        const gid = prov.glyphId(prov.ctx, font, code);
        if (gid == 0) continue;
        const got = prov.advance(prov.ctx, font, gid);
        if (got != 0) {
            var l = Line{};
            l.text("advance ");
            l.cp(code);
            l.text(": got ");
            l.decI32(got);
            l.text(", want 0");
            w.line(l.bytes[0..l.len]);
        }
    }

    for (advance_pins) |pin| {
        const gid = prov.glyphId(prov.ctx, font, pin.cp);
        if (gid == 0) continue;
        const got = prov.advance(prov.ctx, font, gid);
        if (got != pin.want) {
            var l = Line{};
            l.text("advance ");
            l.cp(pin.cp);
            l.text(": got ");
            l.decI32(got);
            l.text(", want ");
            l.decI32(pin.want);
            w.line(l.bytes[0..l.len]);
        }
    }

    if (prov.italicCorrection == null) {
        var l = Line{};
        l.text("italic hook: NULL (want MATH corrections)");
        w.line(l.bytes[0..l.len]);
    } else {
        for (italic_pins) |pin| {
            const gid = prov.glyphId(prov.ctx, font, pin.cp);
            if (gid == 0) continue;
            const got = prov.italicCorrection.?(prov.ctx, font, gid);
            if (got != pin.want) {
                var l = Line{};
                l.text("italic ");
                l.cp(pin.cp);
                l.text(": got ");
                l.decI32(got);
                l.text(", want ");
                l.decI32(pin.want);
                w.line(l.bytes[0..l.len]);
            }
        }
    }

    if (prov.inkBounds == null) {
        var l = Line{};
        l.text("ink hook: NULL (want ink boxes)");
        w.line(l.bytes[0..l.len]);
    } else {
        for (ink_pins) |pin| {
            const gid = prov.glyphId(prov.ctx, font, pin.cp);
            if (gid == 0) continue;
            const got = prov.inkBounds.?(prov.ctx, font, gid);
            if (!std.mem.eql(i32, &got, &pin.want)) {
                var l = Line{};
                l.text("ink ");
                l.cp(pin.cp);
                l.text(": got [");
                l.decI32(got[0]);
                l.text(" ");
                l.decI32(got[1]);
                l.text(" ");
                l.decI32(got[2]);
                l.text(" ");
                l.decI32(got[3]);
                l.text("], want [");
                l.decI32(pin.want[0]);
                l.text(" ");
                l.decI32(pin.want[1]);
                l.text(" ");
                l.decI32(pin.want[2]);
                l.text(" ");
                l.decI32(pin.want[3]);
                l.text("]");
                w.line(l.bytes[0..l.len]);
            }
        }
    }

    for (rule_pins) |pin| {
        const got = prov.ruleThickness(prov.ctx, font, pin.kind);
        if (got != pin.want) {
            var l = Line{};
            l.text("rules ");
            l.text(pin.name);
            l.text(": got ");
            l.decI32(got);
            l.text(", want ");
            l.decI32(pin.want);
            w.line(l.bytes[0..l.len]);
        }
    }

    {
        const got = prov.glyphId(prov.ctx, font, notdef_cp);
        if (got != 0) {
            var l = Line{};
            l.text("notdef ");
            l.cp(notdef_cp);
            l.text(": got ");
            l.decU32(got);
            l.text(", want 0");
            w.line(l.bytes[0..l.len]);
        }
    }

    if (prov.glyphVariant == null) {
        var l = Line{};
        l.text("variant hook: NULL (want taller variants)");
        w.line(l.bytes[0..l.len]);
    } else {
        const base = prov.glyphId(prov.ctx, font, variant_cp);
        if (base != 0) {
            const grown = prov.glyphVariant.?(prov.ctx, font, base, variant_height);
            if (grown == base) {
                var l = Line{};
                l.text("variant ");
                l.cp(variant_cp);
                l.text(": no growth at height ");
                l.decI32(variant_height);
                l.text(" (gid ");
                l.decU32(base);
                l.text(")");
                w.line(l.bytes[0..l.len]);
            }
        }
    }

    if (w.count > 0) {
        var l = Line{};
        l.text("layout: skipped (");
        l.decU32(@intCast(w.count));
        l.text(" prior diagnostics)");
        w.line(l.bytes[0..l.len]);
        return .{ .diagnostics = w.count, .bytes = w.pos };
    }

    smoke(&w, prov);
    return .{ .diagnostics = w.count, .bytes = w.pos };
}

fn errName(e: anyerror) []const u8 {
    if (e == error.Unsupported) return "Unsupported";
    if (e == error.Invalid) return "Invalid";
    if (e == error.TooDeep) return "TooDeep";
    if (e == error.TooLong) return "TooLong";
    if (e == error.ExpansionLimit) return "ExpansionLimit";
    if (e == error.NoSpace) return "NoSpace";
    if (e == error.OutOfMemory) return "OutOfMemory";
    return "error";
}

/// End-to-end wiring smoke through the provider: an accented nucleus
/// (exercises italic+ink paths) and a tall fence (exercises variant
/// selection). Structural only — geometry parity belongs to the sweep.
fn smoke(w: *Writer, prov: contract.MetricsProvider) void {
    var runs: [64]ir.Run = undefined;
    var rules: [16]ir.Rule = undefined;
    var glyphs: [512]u16 = undefined;

    _ = layoutOne("\\hat{y}", .{}, prov, &runs, &rules, &glyphs) catch |e| {
        var l = Line{};
        l.text("layout hat-y: ");
        l.text(errName(e));
        w.line(l.bytes[0..l.len]);
        return;
    };

    const tall = layoutOne(
        "\\\\left(\\\\frac{\\\\frac{a}{b}}{\\\\frac{c}{d}}\\\\right)",
        .{ .display_mode = true },
        prov,
        &runs,
        &rules,
        &glyphs,
    ) catch |e| {
        var l = Line{};
        l.text("layout tall-fence: ");
        l.text(errName(e));
        w.line(l.bytes[0..l.len]);
        return;
    };
    // Fences resolve through rm inside the engine; the direct
    // variant probe above already covers the checked font itself.
    const base = prov.glyphId(prov.ctx, 0, variant_cp);
    if (tall.runs.len == 0 or tall.runs[0].glyphs.len == 0 or tall.runs[0].glyphs[0] == base) {
        var l = Line{};
        l.text("layout tall-fence: no variant growth (gid ");
        if (tall.runs.len > 0 and tall.runs[0].glyphs.len > 0) {
            l.decU32(tall.runs[0].glyphs[0]);
        } else {
            l.text("none");
        }
        l.text(")");
        w.line(l.bytes[0..l.len]);
    }
}

/// `layoutFull` over caller buffers (same shape as `zatex.layoutInner`,
/// which lives above the import cycle and cannot be reached from here).
fn layoutOne(
    source: []const u8,
    options: contract.LayoutOptions,
    prov: contract.MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
) contract.LayoutError!ir.Layout {
    if (source.len > contract.max_input_len) return error.TooLong;
    var pc = parse.ParseCtx.init(source);
    const root = try parse.parseWith(&pc, options);
    var lc = engine.LayCtx.init(&pc, prov);
    const style: parse.Style = if (options.display_mode) .D else .T;
    return engine.layout(&lc, root, style, runs, rules, glyphs);
}

// ---------------------------------------------------------------------------
// Self-contained tests (stub providers; no font files).
// ---------------------------------------------------------------------------

const StubKind = enum {
    clean,
    null_italic,
    zero_italic,
    zero_advance_500,
    null_ink,
};

/// Dense test gids: corpus codepoints map to 1..N (exactly
/// invertible); everything else maps to a nonzero catch-all the
/// smoke formulas can lay out.
fn gidFor(code: u21) u16 {
    if (code == notdef_cp) return 0;
    for (coverage_cps, 0..) |c, i| if (c == code) return @intCast(i + 1);
    return @intCast(60000 + (code % 1000));
}

fn codeFor(glyph: u16) ?u21 {
    if (glyph == 0 or glyph > coverage_cps.len) return null;
    return coverage_cps[glyph - 1];
}

const Stub = struct {
    kind: StubKind = .clean,

    fn provider(s: *Stub) contract.MetricsProvider {
        return .{
            .ctx = @ptrCast(s),
            .glyphId = gid,
            .advance = adv,
            .ruleThickness = rule,
            .glyphVariant = variant,
            .italicCorrection = if (s.kind == .null_italic) null else italic,
            .kernCorrection = kern,
            .extents = ext,
            .inkBounds = if (s.kind == .null_ink) null else ink,
        };
    }

    fn gid(ctx: *const anyopaque, font: u16, code: u21) u16 {
        _ = ctx;
        _ = font;
        return gidFor(code);
    }

    fn adv(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
        const s: *const Stub = @ptrCast(@alignCast(ctx));
        _ = font;
        const code = codeFor(glyph) orelse return 500;
        for (zero_advance_cps) |z| if (code == z) {
            if (s.kind == .zero_advance_500) return 500;
            return 0;
        };
        for (advance_pins) |pin| if (code == pin.cp) return pin.want;
        return 500;
    }

    fn rule(ctx: *const anyopaque, font: u16, kind: contract.RuleKind) i32 {
        _ = ctx;
        _ = font;
        _ = kind;
        return 40;
    }

    fn variant(ctx: *const anyopaque, font: u16, glyph: u16, min_height: i32) u16 {
        _ = ctx;
        _ = font;
        _ = min_height;
        // The paren grows; everything else is already tall enough.
        if (glyph == gidFor(variant_cp)) return glyph + 1000;
        return glyph;
    }

    fn italic(ctx: *const anyopaque, font: u16, glyph: u16) i32 {
        const s: *const Stub = @ptrCast(@alignCast(ctx));
        _ = font;
        if (s.kind == .zero_italic) return 0;
        const code = codeFor(glyph) orelse return 0;
        for (italic_pins) |pin| if (code == pin.cp) return pin.want;
        return 0;
    }

    fn kern(ctx: *const anyopaque, font: u16, glyph: u16, height: i32, corner: contract.KernCorner) i32 {
        _ = ctx;
        _ = font;
        _ = glyph;
        _ = height;
        _ = corner;
        return 0;
    }

    fn ext(ctx: *const anyopaque, font: u16, glyph: u16) [2]i32 {
        _ = ctx;
        _ = font;
        _ = glyph;
        return .{ 700, 250 };
    }

    fn ink(ctx: *const anyopaque, font: u16, glyph: u16) [4]i32 {
        _ = ctx;
        _ = font;
        const code = codeFor(glyph) orelse return .{ 0, 0, 0, 0 };
        for (ink_pins) |pin| if (code == pin.cp) return pin.want;
        return .{ 0, 0, 0, 0 };
    }
};

fn checkText(s: *Stub, font: u16, buf: []u8) struct {
    n: usize,
    text: []u8,
} {
    const res = check(s.provider(), font, buf);
    return .{ .n = res.diagnostics, .text = buf[0..res.bytes] };
}

test "conform: crafted clean provider passes" {
    var s = Stub{ .kind = .clean };
    var buf: [4096]u8 = undefined;
    const r = checkText(&s, 0, &buf);
    try std.testing.expectEqual(@as(usize, 0), r.n);
}

test "conform: NULL italic hook fails named" {
    var s = Stub{ .kind = .null_italic };
    var buf: [4096]u8 = undefined;
    const r = checkText(&s, 0, &buf);
    try std.testing.expect(r.n > 0);
    try std.testing.expect(std.mem.indexOf(u8, r.text, "italic hook: NULL (want MATH corrections)") != null);
}

test "conform: present-but-zero italic fails named" {
    // A hook that answers 0 for a slanted nucleus is distinct from
    // a missing hook: null C hooks bridge to null natively (named
    // above), while a present-but-zero hook trips the value pin.
    var s = Stub{ .kind = .zero_italic };
    var buf: [4096]u8 = undefined;
    const r = checkText(&s, 0, &buf);
    try std.testing.expect(r.n > 0);
    try std.testing.expect(std.mem.indexOf(u8, r.text, "italic U+1D466: got 0, want 28") != null);
}

test "conform: 500-for-zero advances fail named" {
    var s = Stub{ .kind = .zero_advance_500 };
    var buf: [4096]u8 = undefined;
    const r = checkText(&s, 0, &buf);
    try std.testing.expect(r.n > 0);
    try std.testing.expect(std.mem.indexOf(u8, r.text, "advance U+20D7: got 500, want 0") != null);
}

test "conform: NULL ink hook fails named" {
    var s = Stub{ .kind = .null_ink };
    var buf: [4096]u8 = undefined;
    const r = checkText(&s, 0, &buf);
    try std.testing.expect(r.n > 0);
    try std.testing.expect(std.mem.indexOf(u8, r.text, "ink hook: NULL (want ink boxes)") != null);
}
