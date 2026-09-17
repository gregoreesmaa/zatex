//! QA coverage for test-coverage issues #40-48.
//!
//! Test-only module (never imported by the core): stub providers, integer
//! IR asserts, no pixels, no fonts, no network. Every relation below
//! asserts through the shared `invariants` helpers (never redefined per
//! call site, per the `invariants.zig` header contract); core-owned
//! decisions (`symbols.glueBetween`/`degradeBin`, `parse.useLimits`,
//! `parse.space_*` widths, `parse.Style.sizeUnits`) are reused as oracles,
//! never re-derived.
const std = @import("std");
const zatex = @import("zatex");
const inv = @import("invariants");
const speech = @import("speech");
const texser = @import("texser");

// ---------------------------------------------------------------------------
// Harness: stub providers, layout drivers, IR readers
// ---------------------------------------------------------------------------

/// Fixed stub metrics: advance 500, rule 40, uniform 700/250 extents
/// (the `LayCtx` default when the provider omits the extents hook).
const Stub = struct {
    fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
        return @truncate(cp);
    }
    fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
        return 500;
    }
    fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
        return 40;
    }
};

fn stubProvider() zatex.MetricsProvider {
    const S = struct {
        var dummy: u8 = 0;
    };
    return .{
        .ctx = &S.dummy,
        .glyphId = Stub.glyphId,
        .advance = Stub.advance,
        .ruleThickness = Stub.ruleThickness,
    };
}

const B = struct {
    runs: [1024]zatex.ir.Run = undefined,
    rules: [128]zatex.ir.Rule = undefined,
    glyphs: [8192]u16 = undefined,
};

fn lay(src: []const u8, display: bool, b: *B) !zatex.ir.Layout {
    var diag = zatex.Diag.empty();
    return zatex.layoutDiag(src, .{ .display_mode = display }, stubProvider(), &b.runs, &b.rules, &b.glyphs, &diag);
}

/// Absolute x of the first run containing `glyph` (the stub maps
/// codepoint to glyph id 1:1, so representatives stay distinguishable).
fn glyphX(l: zatex.ir.Layout, glyph: u16) !i32 {
    for (l.runs) |r| {
        for (r.glyphs) |g| if (g == glyph) return r.x;
    }
    return error.TestUnexpectedResult;
}

/// Baseline lift of a superscript pair: baseline(sup-base) minus
/// baseline(sup), resolved by glyph id through the stub provider.
fn supRaise(l: zatex.ir.Layout, base_glyph: u16, sup_glyph: u16) !i32 {
    var yb: ?i32 = null;
    var ys: ?i32 = null;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g == base_glyph and yb == null) yb = r.baseline_y;
            if (g == sup_glyph and ys == null) ys = r.baseline_y;
        }
    }
    return (yb orelse return error.TestUnexpectedResult) - (ys orelse return error.TestUnexpectedResult);
}

/// Generic canonical dump (mirrors `invariants.layoutText` field for
/// field, so full-profile and subset-profile layouts compare as text).
/// Cross-checked against `inv.layoutText` for full layouts below.
fn dumpAny(l: anytype, out: []u8) []u8 {
    var pos: usize = 0;
    const put = struct {
        fn ch(o: []u8, p: *usize, trunc: *bool, c: u8) void {
            if (p.* >= o.len) {
                trunc.* = true;
                return;
            }
            o[p.*] = c;
            p.* += 1;
        }
        fn int(o: []u8, p: *usize, trunc: *bool, v: i64) void {
            if (v < 0) {
                ch(o, p, trunc, '-');
                uint(o, p, trunc, @as(u64, @intCast(-v)));
            } else {
                uint(o, p, trunc, @as(u64, @intCast(v)));
            }
        }
        fn uint(o: []u8, p: *usize, trunc: *bool, v: u64) void {
            var tmp: [20]u8 = undefined;
            var n: usize = 0;
            var x = v;
            if (x == 0) {
                ch(o, p, trunc, '0');
                return;
            }
            while (x > 0) : (n += 1) {
                tmp[n] = '0' + @as(u8, @intCast(x % 10));
                x /= 10;
            }
            while (n > 0) : (n -= 1) ch(o, p, trunc, tmp[n - 1]);
        }
    };
    var trunc = false;
    put.int(out, &pos, &trunc, @as(i64, l.width));
    put.ch(out, &pos, &trunc, '/');
    put.int(out, &pos, &trunc, @as(i64, l.height_above));
    put.ch(out, &pos, &trunc, '/');
    put.int(out, &pos, &trunc, @as(i64, l.depth_below));
    put.ch(out, &pos, &trunc, '|');
    for (l.runs) |r| {
        put.int(out, &pos, &trunc, r.font_id);
        put.ch(out, &pos, &trunc, ',');
        put.int(out, &pos, &trunc, r.size_units);
        put.ch(out, &pos, &trunc, ',');
        put.int(out, &pos, &trunc, @as(i64, r.x));
        put.ch(out, &pos, &trunc, ',');
        put.int(out, &pos, &trunc, @as(i64, r.baseline_y));
        put.ch(out, &pos, &trunc, ':');
        for (r.glyphs) |g| {
            put.int(out, &pos, &trunc, g);
            put.ch(out, &pos, &trunc, '.');
        }
        put.ch(out, &pos, &trunc, ';');
    }
    put.ch(out, &pos, &trunc, '|');
    for (l.rules) |r| {
        put.int(out, &pos, &trunc, @as(i64, r.x));
        put.ch(out, &pos, &trunc, ',');
        put.int(out, &pos, &trunc, @as(i64, r.y));
        put.ch(out, &pos, &trunc, ',');
        put.int(out, &pos, &trunc, @as(i64, r.w));
        put.ch(out, &pos, &trunc, ',');
        put.int(out, &pos, &trunc, @as(i64, r.h));
        // Mirrors `invariants.layoutText` (issue #107 diagonal suffix).
        if (r.diag != .none) {
            put.ch(out, &pos, &trunc, ',');
            put.ch(out, &pos, &trunc, if (r.diag == .up) 'u' else 'd');
            put.ch(out, &pos, &trunc, ',');
            put.int(out, &pos, &trunc, @as(i64, r.thick));
        }
        put.ch(out, &pos, &trunc, ';');
    }
    if (trunc and pos >= 3) @memcpy(out[pos - 3 ..][0..3], "...");
    return out[0..pos];
}

test "qa dump mirrors invariants.layoutText" {
    var b: B = .{};
    const l = try lay("\\frac{a}{b}+x=y", false, &b);
    var a: [4096]u8 = undefined;
    var c: [4096]u8 = undefined;
    try std.testing.expectEqualStrings(inv.layoutText(l, &a), dumpAny(l, &c));
}

// ---------------------------------------------------------------------------
// Issue #40: metamorphic equalities (reference-free, via shared helpers)
// ---------------------------------------------------------------------------

test "qa40 color is geometry-transparent" {
    // Pins the #35 design up front: color must never alter width,
    // height, depth, baselines, or run/rule geometry. Asserted through
    // `expectSameGeometry` (paint ignored) AND `expectSameDump`
    // (canonical IR text carries no paint), integer units only — plus
    // an explicit paint-presence check so the test is never vacuous
    // (`expectSameLayout` would now fail: scoped color paints runs).
    const cases = [_][]const u8{
        "x+y",
        "a=b",
        "\\frac{a}{b}",
        "x^2_1",
        "\\sum_{i=1}^n i",
        "\\sqrt{x}+\\left(y\\right)",
    };
    for (cases) |src| {
        var cbuf: [256]u8 = undefined;
        const colored = try std.fmt.bufPrint(&cbuf, "\\color{{red}}{{{s}}}", .{src});
        for ([_]bool{ false, true }) |display| {
            var ba: B = .{};
            var bb: B = .{};
            const a = try lay(src, display, &ba);
            const c = try lay(colored, display, &bb);
            try inv.expectSameGeometry(a, c);
            // The paint must actually be there: every colored run
            // carries opaque red (0xFF0000FF RRGGBBAA).
            try std.testing.expect(c.runs.len > 0);
            for (c.runs) |r| try std.testing.expectEqual(@as(?u32, 0xFF0000FF), r.color);
            var da: [4096]u8 = undefined;
            var dc: [4096]u8 = undefined;
            try inv.expectSameDump(a, c, &da, &dc);
            // The declaration form (rest-of-group body) is transparent too.
            var dbuf: [256]u8 = undefined;
            const decl = try std.fmt.bufPrint(&dbuf, "\\color{{red}}{s}", .{src});
            var bd: B = .{};
            const d = try lay(decl, display, &bd);
            try inv.expectSameFootprint(a, d);
        }
    }
}

test "qa40 phantom preserves footprint and kerning" {
    // `Width(\phantom{A}+B) == Width(A+B)`: the phantom keeps its box
    // but emits nothing, so runs legitimately differ — footprint must
    // not, and the surviving atoms must sit at identical x positions
    // (adjacent kerning preserved).
    const pairs = [_][2][]const u8{
        .{ "\\phantom{x}+y", "x+y" },
        .{ "\\phantom{\\frac{a}{b}}+y", "\\frac{a}{b}+y" },
        .{ "\\phantom{x^2}+y", "x^2+y" },
    };
    for (pairs) |p| {
        for ([_]bool{ false, true }) |display| {
            var ba: B = .{};
            var bb: B = .{};
            const a = try lay(p[0], display, &ba);
            const c = try lay(p[1], display, &bb);
            try inv.expectSameFootprint(a, c);
            // `y` (mathit U+1D466 -> 0xD466) and `+` (43) sit at
            // identical x in both.
            try std.testing.expectEqual(try glyphX(c, 0xD466), try glyphX(a, 0xD466));
            try std.testing.expectEqual(try glyphX(c, 43), try glyphX(a, 43));
            // The phantom emits nothing: strictly fewer glyphs, same box.
            var na: usize = 0;
            for (a.runs) |r| na += r.glyphs.len;
            var nc: usize = 0;
            for (c.runs) |r| nc += r.glyphs.len;
            try std.testing.expect(na < nc);
        }
    }
}

test "qa40 fraction growth is monotonic" {
    // `Height(\frac{X}{Y})` never shrinks when terms are added to X or Y.
    const num_chain = [_][]const u8{
        "\\frac{a}{b}",
        "\\frac{a+c}{b}",
        "\\frac{a+c+e}{b}",
    };
    const den_chain = [_][]const u8{
        "\\frac{a}{b}",
        "\\frac{a}{b+c}",
        "\\frac{a}{b+c+d}",
    };
    for ([_][]const []const u8{ &num_chain, &den_chain }) |chain| {
        var prev: ?zatex.ir.Layout = null;
        var bufs: [3]B = .{ .{}, .{}, .{} };
        for (chain, 0..) |src, k| {
            const l = try lay(src, false, &bufs[k]);
            try inv.expectNonNegative(l);
            try inv.expectContained(l);
            if (prev) |p| try inv.expectGrowsOrEqual(p, l);
            prev = l;
        }
    }
    // Nesting a fraction inside both slots grows the box strictly.
    var b0: B = .{};
    var b1: B = .{};
    const small = try lay("\\frac{x}{y}", false, &b0);
    const big = try lay("\\frac{\\frac{p}{q}}{\\frac{r}{s}}", false, &b1);
    try inv.expectGrowsOrEqual(small, big);
    try std.testing.expect(big.height_above + big.depth_below > small.height_above + small.depth_below);
}

// ---------------------------------------------------------------------------
// Issue #41: 8x8 atom-class x 8-style spacing grid (512 cells)
// ---------------------------------------------------------------------------

const AtomRep = struct {
    tex: []const u8,
    class: zatex.symbols.AtomClass,
    name: []const u8,
};

const atom_reps = [_]AtomRep{
    .{ .tex = "x", .class = .Ord, .name = "Ord" },
    .{ .tex = "\\sum", .class = .Op, .name = "Op" },
    .{ .tex = "+", .class = .Bin, .name = "Bin" },
    .{ .tex = "=", .class = .Rel, .name = "Rel" },
    .{ .tex = "(", .class = .Open, .name = "Open" },
    .{ .tex = ")", .class = .Close, .name = "Close" },
    .{ .tex = ",", .class = .Punct, .name = "Punct" },
    .{ .tex = "\\frac{a}{b}", .class = .Inner, .name = "Inner" },
};

const StyleCtx = struct {
    name: []const u8,
    display: bool,
    size: i16,
    /// Wrapper split around the body (`pre + body + suf`); empty
    /// strings for bare bodies. Cramped contexts wrap in `\sqrt{}` so
    /// the radicand style (Dc/Tc/Sc/SSc) is ambient.
    pre: []const u8,
    suf: []const u8,
    /// The wrapper with an empty body (its width is the chrome
    /// constant); empty string when there is no wrapper.
    empty: []const u8,
};

const style_ctxs = [_]StyleCtx{
    .{ .name = "D", .display = true, .size = 1000, .pre = "", .suf = "", .empty = "" },
    .{ .name = "Dc", .display = true, .size = 1000, .pre = "\\sqrt{", .suf = "}", .empty = "\\sqrt{}" },
    .{ .name = "T", .display = false, .size = 1000, .pre = "", .suf = "", .empty = "" },
    .{ .name = "Tc", .display = false, .size = 1000, .pre = "\\sqrt{", .suf = "}", .empty = "\\sqrt{}" },
    .{ .name = "S", .display = false, .size = 700, .pre = "\\scriptstyle{", .suf = "}", .empty = "" },
    .{ .name = "Sc", .display = false, .size = 700, .pre = "\\scriptstyle{\\sqrt{", .suf = "}}", .empty = "\\scriptstyle{\\sqrt{}}" },
    .{ .name = "SS", .display = false, .size = 500, .pre = "\\scriptscriptstyle{", .suf = "}", .empty = "" },
    .{ .name = "SSc", .display = false, .size = 500, .pre = "\\scriptscriptstyle{\\sqrt{", .suf = "}}", .empty = "\\scriptscriptstyle{\\sqrt{}}" },
};

/// Wrap `body` as `pre + body + suf` into `out`.
fn applyWrap(out: []u8, pre: []const u8, body: []const u8, suf: []const u8) ![]const u8 {
    if (pre.len + body.len + suf.len > out.len) return error.TestUnexpectedResult;
    @memcpy(out[0..pre.len], pre);
    @memcpy(out[pre.len..][0..body.len], body);
    @memcpy(out[pre.len + body.len ..][0..suf.len], suf);
    return out[0 .. pre.len + body.len + suf.len];
}

const CellBuf = struct {
    runs: [64]zatex.ir.Run = undefined,
    rules: [16]zatex.ir.Rule = undefined,
    glyphs: [1024]u16 = undefined,
};

fn cellLay(src: []const u8, display: bool, b: *CellBuf) !zatex.ir.Layout {
    var diag = zatex.Diag.empty();
    return zatex.layoutDiag(src, .{ .display_mode = display }, stubProvider(), &b.runs, &b.rules, &b.glyphs, &diag);
}

test "qa41 atom spacing grid is 512 for 512" {
    // Every ordered atom-class pair in every TeX style: the measured
    // inter-atom gap must equal the core-owned `symbols.glueBetween`
    // decision (with `degradeBin`), scaled by the style size exactly as
    // `layoutGroup` scales it. Nonzero glue values coincide with the
    // shared `parse.space_*` mu widths (pinned by qa41 glue-space link).
    // NOTE on the issue premise: this engine keeps inter-atom spacing
    // uniform across styles (scaled by size) — script styles do NOT
    // suppress it (`symbols.glueBetween` docs: KaTeX keeps spacing in
    // all styles). The grid pins that uniform behavior; a suppression
    // change would fail all 192 script-style cells loudly.
    var n_gap: usize = 0;
    var n_ok: usize = 0;
    for (atom_reps) |L| {
        for (atom_reps) |R| {
            // Expected glue from the shared helpers (mirrors the
            // `layoutGroup` adjacency logic, never re-derived).
            var effL = L.class;
            if (effL == .Bin and zatex.symbols.degradeBin(null)) effL = .Ord;
            var effR = R.class;
            if (effR == .Bin and zatex.symbols.degradeBin(effL)) effR = .Ord;
            const glue1000: i32 = zatex.symbols.glueBetween(effL, effR);
            for (style_ctxs) |st| {
                const want = @divTrunc(glue1000 * @as(i32, st.size), 1000);
                var pair: [64]u8 = undefined;
                var pw: usize = 0;
                @memcpy(pair[pw..][0..L.tex.len], L.tex);
                pw += L.tex.len;
                pair[pw] = ' ';
                pw += 1;
                @memcpy(pair[pw..][0..R.tex.len], R.tex);
                pw += R.tex.len;
                const both = pair[0..pw];
                var src: [192]u8 = undefined;
                var sl: [192]u8 = undefined;
                var sr: [192]u8 = undefined;
                const ssrc = try applyWrap(&src, st.pre, both, st.suf);
                const ssl = try applyWrap(&sl, st.pre, L.tex, st.suf);
                const ssr = try applyWrap(&sr, st.pre, R.tex, st.suf);
                var bb: CellBuf = .{};
                var bl: CellBuf = .{};
                var br: CellBuf = .{};
                const lc = cellLay(ssrc, st.display, &bb) catch |e| {
                    // Gap hygiene: a legitimately-unrenderable cell is a
                    // DECLARED honest fallback (`Unsupported`), never a
                    // skip — anything else fails the cell loudly.
                    if (e == error.Unsupported) {
                        n_gap += 1;
                        std.debug.print("\ngap cell [{s}-{s} @ {s}]: Unsupported\n", .{ L.name, R.name, st.name });
                        continue;
                    }
                    std.debug.print("\ncell [{s}-{s} @ {s}] error {s}\n", .{ L.name, R.name, st.name, @errorName(e) });
                    return e;
                };
                const ll = try cellLay(ssl, st.display, &bl);
                const lr = try cellLay(ssr, st.display, &br);
                var chrome: i32 = 0;
                if (st.empty.len > 0) {
                    var be: CellBuf = .{};
                    chrome = @as(i32, @intCast((try cellLay(st.empty, st.display, &be)).width));
                }
                const gap = @as(i32, @intCast(lc.width)) - @as(i32, @intCast(ll.width)) - @as(i32, @intCast(lr.width)) + chrome;
                if (gap != want) {
                    std.debug.print("\ncell [{s}-{s} @ {s}]: gap {d}, want {d} ({s})\n", .{ L.name, R.name, st.name, gap, want, ssrc });
                    return error.TestUnexpectedResult;
                }
                n_ok += 1;
            }
        }
    }
    std.debug.print("\nspacing grid: {d} ok, {d} declared-gap\n", .{ n_ok, n_gap });
    try std.testing.expectEqual(@as(usize, 512), n_ok + n_gap);
    try std.testing.expect(n_ok > 500);
}

test "qa41 inter-atom glue uses the shared mu widths" {
    // Nonzero `glueBetween` outputs over all 64 ordered pairs are
    // exactly the shared `parse.space_*` widths (3/4/5mu): one mu
    // table, two call sites (atom pairs, explicit spaces).
    for (atom_reps) |L| {
        for (atom_reps) |R| {
            const g: i32 = zatex.symbols.glueBetween(L.class, R.class);
            if (g != 0) {
                const ok = g == zatex.parse.space_thin or g == zatex.parse.space_med or
                    g == zatex.parse.space_thick;
                if (!ok) {
                    std.debug.print("\nglue [{s}-{s}] = {d}, outside space_* family\n", .{ L.name, R.name, g });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
    // Explicit spaces measure exactly their `parse.space_*` widths.
    const spaces = [_]struct { tex: []const u8, want: i32 }{
        .{ .tex = "a\\,b", .want = zatex.parse.space_thin },
        .{ .tex = "a\\:b", .want = zatex.parse.space_med },
        .{ .tex = "a\\;b", .want = zatex.parse.space_thick },
        .{ .tex = "a\\ b", .want = zatex.parse.space_interword },
        .{ .tex = "a\\!b", .want = -zatex.parse.space_thin },
    };
    for (spaces) |s| {
        var ba: CellBuf = .{};
        var bb: CellBuf = .{};
        var bc: CellBuf = .{};
        const w_a = (try cellLay("a", false, &ba)).width;
        const w_b = (try cellLay("b", false, &bb)).width;
        const w_both = (try cellLay(s.tex, false, &bc)).width;
        // `a`/`b` are single 500-unit advances at size 1000.
        try std.testing.expectEqual(@as(u32, 500), w_a);
        try std.testing.expectEqual(@as(u32, 500), w_b);
        try std.testing.expectEqual(s.want, @as(i32, @intCast(w_both)) - 1000);
    }
}

// ---------------------------------------------------------------------------
// Issue #42: cramped styles (TeX Book Appendix G).
//
// The engine lowers superscript elevation by exactly 30mu in cramped
// styles (`layoutSupSub`: sup_mu 400/350/300 minus 30 when cramped).
// Radicands (`style.cramped()`) and denominators (`style.denominator()`)
// are cramped; numerators (`style.numerator()`) never are. All asserts
// are integer baseline offsets from the IR under the stub provider.
// ---------------------------------------------------------------------------

test "qa42 cramped_radicand_superscript" {
    // Appendix G radical rule: the radicand is set in the cramped
    // variant, so the `2` in `\sqrt{x^2}` sits 30mu lower than in
    // standalone `x^2` (text style T vs cramped Tc: 400 vs 370).
    var b0: B = .{};
    var b1: B = .{};
    var b2: B = .{};
    const top = try lay("x^2", false, &b0);
    const rad = try lay("\\sqrt{x^2}", false, &b1);
    try std.testing.expectEqual(@as(i32, 400), try supRaise(top, 0xD465, 50));
    try std.testing.expectEqual(@as(i32, 370), try supRaise(rad, 0xD465, 50));
    // Display mode radicand is Dc: same 30mu drop (400 vs 370).
    const rad_d = try lay("\\sqrt{x^2}", true, &b2);
    try std.testing.expectEqual(@as(i32, 370), try supRaise(rad_d, 0xD465, 50));
}

test "qa42 cramped_denominator_superscript" {
    // Appendix G fraction rule: the denominator is set in the cramped
    // variant of the smaller style while the numerator is uncramped.
    // Shifts scale by the ambient script size (S/Sc = 700): the `2` in
    // `\frac{x^2}{1}` rises 350mu at 0.7 scale = 245, while in
    // `\frac{1}{x^2}` it rises (350-30)mu at 0.7 scale = 224 — exactly
    // the 30mu cramped drop, size-scaled.
    var b0: B = .{};
    var b1: B = .{};
    const num = try lay("\\frac{x^2}{1}", false, &b0);
    const den = try lay("\\frac{1}{x^2}", false, &b1);
    try std.testing.expectEqual(@as(i32, 245), try supRaise(num, 0xD465, 50));
    try std.testing.expectEqual(@as(i32, 224), try supRaise(den, 0xD465, 50));
}

test "qa42 cramped_nested_subscript" {
    // Appendix G subscript rule: subscripts nest in (cramped) script
    // styles with a 260mu drop per level (scaled by the ambient size:
    // 260 at size 1000, 182 at size 700). `A_{B_C}` puts B one drop
    // below A and C a second, smaller drop below B.
    var b: B = .{};
    const l = try lay("A_{B_C}", false, &b);
    // A baseline = root height_above = 700 (stub extents, size 1000).
    try std.testing.expectEqual(@as(u32, 700), l.height_above);
    // B (mathit U+1D435 -> 0xD435) sits exactly one 260mu drop below
    // A; C (0xD436) a further 182mu (= 260 at size 700) below B.
    try std.testing.expectEqual(@as(i32, 700), try baseY(l, 0xD434));
    try std.testing.expectEqual(@as(i32, 700 + 260), try baseY(l, 0xD435));
    try std.testing.expectEqual(@as(i32, 700 + 260 + 182), try baseY(l, 0xD436));
    try std.testing.expectEqual(@as(u32, 260 + 182 + 125), l.depth_below);
    // DEVIATION NOTE (engine behavior pinned, not KaTeX-proven):
    // subscripts lay out in uncramped script styles (`style.script()`,
    // not `.cramped()`), so a sup nested inside a sub rises the full
    // uncramped amount: `A_{B^2}` lifts 350mu at the 0.7 script scale =
    // 245, where Appendix G cramped-subscript setting would give 320mu
    // at 0.7 = 224. The 245 value below locks the current behavior;
    // closing the 30mu gap is engine work (layout.zig, out of scope
    // for this test module).
    var b2: B = .{};
    const l2 = try lay("A_{B^2}", false, &b2);
    try std.testing.expectEqual(@as(i32, 245), try supRaise(l2, 0xD435, 50));
}

// ---------------------------------------------------------------------------
// Issue #43: display-vs-text mode matrix (`LayoutOptions.display_mode`)
// ---------------------------------------------------------------------------

test "qa43 sum limits stack in display, sit aside in text" {
    // KaTeX contract: `\sum` (default-limits operator) stacks limits
    // above/below in display mode and sets them as side scripts in text
    // mode (`parse.useLimits`, owned by the core).
    var bd: B = .{};
    var bt: B = .{};
    const d = try lay("\\sum_{i}^{n}", true, &bd);
    const t = try lay("\\sum_{i}^{n}", false, &bt);
    var dd: [4096]u8 = undefined;
    var dt: [4096]u8 = undefined;
    try std.testing.expect(!std.mem.eql(u8, dumpAny(d, &dd), dumpAny(t, &dt)));
    try std.testing.expect(d.height_above > t.height_above);
    const y_base_d = try baseY(d, 8721);
    const y_sup_d = try baseY(d, 0xD45B); // mathit n
    const y_sub_d = try baseY(d, 0xD456); // mathit i
    try std.testing.expect(y_sup_d < y_base_d);
    try std.testing.expect(y_sub_d > y_base_d);
    // Text mode: side scripts at one 60mu script gap past the 500-unit base.
    const x_base_t = try glyphX(t, 8721);
    const x_sup_t = try glyphX(t, 0xD45B);
    const x_sub_t = try glyphX(t, 0xD456);
    try std.testing.expectEqual(x_base_t + 500 + 60, x_sup_t);
    try std.testing.expectEqual(x_base_t + 500 + 60, x_sub_t);
}

fn baseY(l: zatex.ir.Layout, glyph: u16) !i32 {
    for (l.runs) |r| {
        for (r.glyphs) |g| if (g == glyph) return r.baseline_y;
    }
    return error.TestUnexpectedResult;
}

/// Provider font id of the first run containing `glyph`.
fn runFont(l: zatex.ir.Layout, glyph: u16) !u16 {
    for (l.runs) |r| {
        for (r.glyphs) |g| if (g == glyph) return r.font_id;
    }
    return error.TestUnexpectedResult;
}

/// Size units of the first run containing `glyph`.
fn runSize(l: zatex.ir.Layout, glyph: u16) !u16 {
    for (l.runs) |r| {
        for (r.glyphs) |g| if (g == glyph) return r.size_units;
    }
    return error.TestUnexpectedResult;
}

test "qa43 lim stacks in display, sits aside in text" {
    // `\lim` is a default-limits word operator: same placement split.
    var bd: B = .{};
    var bt: B = .{};
    const d = try lay("\\lim_{x} f", true, &bd);
    const t = try lay("\\lim_{x} f", false, &bt);
    const y_base_d = try baseY(d, 108); // 'l' of "lim" (opname, roman)
    const y_sub_d = try baseY(d, 0xD465); // mathit 'x'
    try std.testing.expect(y_sub_d > y_base_d);
    // Text mode: the subscript starts at the "lim" edge with no gap —
    // KaTeX leaves marginLeft null for non-symbol (word) bases, so the
    // old 60mu script gap was KaTeX-untrue here (issue #101).
    const x_sub_t = try glyphX(t, 0xD465);
    const x_lim_t = try glyphX(t, 108);
    try std.testing.expectEqual(x_lim_t + 1500, x_sub_t);
    // Display mode centers the subscript under the word, not aside it.
    const x_sub_d = try glyphX(d, 0xD465);
    try std.testing.expect(x_sub_d < x_lim_t + 1500);
}

test "qa43 int scripts sit aside in both modes" {
    // Integrals never take limits (`lim_def = false`): side scripts in
    // both modes; only the large-op face differs (size2 in display,
    // size1 in text — both at the ambient size, never scaled).
    for ([_]bool{ false, true }) |display| {
        var b: B = .{};
        const l = try lay("\\int_{0}^{1} x", display, &b);
        const base_w: i32 = 500;
        const x_base = try glyphX(l, 8747);
        try std.testing.expectEqual(x_base + base_w + 60, try glyphX(l, 49));
        try std.testing.expectEqual(x_base + base_w + 60, try glyphX(l, 48));
    }
    var bd: B = .{};
    var bt: B = .{};
    const d = try lay("\\int_{0}^{1} x", true, &bd);
    const t = try lay("\\int_{0}^{1} x", false, &bt);
    // Same ambient size, same stub advance: only the face differs, so
    // the stub boxes (and widths) coincide exactly (issue #101).
    try std.testing.expectEqual(t.width, d.width);
}

test "qa101 display large ops use size2, text uses size1" {
    // KaTeX (pinned 0.18.7 op builder): display symbol operators come
    // from Size2-Regular, every other style from Size1-Regular — at
    // the ambient size, never scaled. No scalar fits both (LM sum ink
    // 1.0em needs 1.4x, LM integral ink 1.111em needs 2x), so the core
    // routes faces instead of scaling (issue #101).
    const size1: u16 = @intFromEnum(zatex.FontId.size1);
    const size2: u16 = @intFromEnum(zatex.FontId.size2);
    var bd: B = .{};
    const d = try lay("\\sum", true, &bd);
    try std.testing.expectEqual(size2, try runFont(d, 8721));
    try std.testing.expectEqual(@as(u16, 1000), try runSize(d, 8721));
    var bt: B = .{};
    const t = try lay("\\sum", false, &bt);
    try std.testing.expectEqual(size1, try runFont(t, 8721));
    try std.testing.expectEqual(@as(u16, 1000), try runSize(t, 8721));
    var bi: B = .{};
    const i = try lay("\\int", true, &bi);
    try std.testing.expectEqual(size2, try runFont(i, 8747));
    try std.testing.expectEqual(@as(u16, 1000), try runSize(i, 8747));
}

test "qa101 substack rows clear by strut floors, no fixed gap" {
    // KaTeX subarray (arraystretch 0.5, script cells, pinned 0.18.7):
    // each row floors at the 0.42/0.18em strut and pitch is exactly
    // prev.db + next.ha — no extra gap. Stub script cells are
    // 490/175, so pitch = 180 + 490 = 670 (issue #101).
    var b: B = .{};
    const l = try lay("\\substack{a\\\\b}", false, &b);
    // One run per script-size row (rows sit on distinct baselines).
    var ys: [2]i32 = undefined;
    var n: usize = 0;
    for (l.runs) |r| {
        if (r.size_units == 700 and n < 2) {
            ys[n] = r.baseline_y;
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(i32, 670), ys[1] - ys[0]);
}

test "qa96 htmlmathml branches splice flat for spacing" {
    // KaTeX splices `\html@mathml` branches flat into the enclosing
    // row (no ordgroup shell — pinned 0.18.7): the mathtools colon
    // family (`\dblcolon`, `\approxcoloncolon`, ...) keeps its
    // Rel composition with no Rel–Ord thick glue (issue #96). Stub
    // advances are uniform 500, so `\approx` ends at 500 and the
    // -1.2mu kern lands the first colon at 433.
    var b: B = .{};
    const l = try lay("\\approxcoloncolon", false, &b);
    try std.testing.expectEqual(@as(i32, 433), try glyphX(l, 58));
    // Full span: 500 (approx) - 67 (kern) + 500 (colon) - 50 (kern)
    // + 500 (colon) = 1383 — any Rel–Ord thick glue would add 278.
    try std.testing.expectEqual(@as(u32, 1383), l.width);
    var bd: B = .{};
    const d = try lay("\\dblcolon", false, &bd);
    try std.testing.expectEqual(@as(u32, 950), d.width);
}

test "qa96 negations render AMS PUA glyphs, MathML keeps the arbiter" {
    // KaTeX renders precomposed AMS PUA glyphs in HTML (`\@nleqq`
    // = U+E011, `\@nleqslant` = U+E010, pinned 0.18.7) while
    // MathML carries the single codepoint (issue #73 arbiter, #96
    // shapes). The stub maps codepoints 1:1, so layout runs carry
    // the PUA codepoints distinctly; MathML stays byte-identical
    // to the old static path (`<mo>≰</mo>`).
    const cases = [_]struct { tex: []const u8, cp: u16 }{
        .{ .tex = "\\nleqq", .cp = 0xE011 },
        .{ .tex = "\\nleqslant", .cp = 0xE010 },
        .{ .tex = "\\lvertneqq", .cp = 0xE00C },
        .{ .tex = "\\ngeqq", .cp = 0xE00E },
    };
    for (cases) |c| {
        var b: B = .{};
        const l = try lay(c.tex, false, &b);
        var found = false;
        for (l.runs) |r| {
            for (r.glyphs) |g| {
                if (g == c.cp) found = true;
            }
        }
        try std.testing.expect(found);
    }
    var out: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo>≰</mo></mrow></math>",
        try zatex.mathml("\\nleqq", .{}, &out),
    );
}

test "qa96 groups stack contiguously by ink" {
    // KaTeX windows the 342-tall group SVG contiguously over the
    // nucleus (pinned 0.18.7 vlist: nucleus + 0.342, no clearance —
    // the SVG's own transparent top provides the daylight), so the
    // group ink bottom lands exactly on the nucleus top (issue
    // #96). Ink-stub LM bounds: overgroup ink bottom +657,
    // undergroup ink top -227; nucleus extents 700/250.
    var bo: ProvBuf = .{};
    const o = try layInk("\\overgroup{AB}", &bo);
    try std.testing.expectEqual(@as(u32, 1000), o.width);
    try std.testing.expectEqual(@as(u32, 743), o.height_above);
    var onuc: ?i32 = null;
    var ogrp: ?i32 = null;
    for (o.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 54324) onuc = r.baseline_y;
            if (g == 0x23E0) {
                ogrp = r.baseline_y;
                try std.testing.expectEqual(@as(u16, 2000), r.x_scale);
                try std.testing.expectEqual(@as(i32, 0), r.x);
            }
        }
    }
    // Group ink bottom (+657) lands exactly on the nucleus top
    // (+700): baselines sit 43 apart in any y orientation.
    try std.testing.expectEqual(@as(i32, 43), onuc.? - ogrp.?);
    var bu: ProvBuf = .{};
    const u = try layInk("\\undergroup{AB}", &bu);
    try std.testing.expectEqual(@as(u32, 1000), u.width);
    try std.testing.expectEqual(@as(u32, 273), u.depth_below);
    var unuc: ?i32 = null;
    var ugrp: ?i32 = null;
    for (u.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 54324) unuc = r.baseline_y;
            if (g == 0x23E1) {
                ugrp = r.baseline_y;
                try std.testing.expectEqual(@as(u16, 2000), r.x_scale);
                try std.testing.expectEqual(@as(i32, 0), r.x);
            }
        }
    }
    // Group ink top (-227) lands exactly on the nucleus bottom
    // (-250): baselines sit 23 apart in any y orientation.
    try std.testing.expectEqual(@as(i32, 23), ugrp.? - unuc.?);
}

test "qa96 segments are stroked to the span" {
    // KaTeX draws over/underlinesegment from SVG (pinned 0.18.7
    // `stretchy.ts`): a 40mu shaft with 40mu end caps in a
    // 522-tall image, windowed contiguously over a min 0.888em
    // span. The old path emitted the missing host glyph and
    // rendered nothing (issue #96). Stub nucleus AB: 1000 wide,
    // 700/250 extents.
    var b: ProvBuf = .{};
    const l = try layProv("\\overlinesegment{AB}", stubProvider(), &b);
    try std.testing.expectEqual(@as(u32, 1000), l.width);
    try std.testing.expectEqual(@as(u32, 1222), l.height_above);
    try std.testing.expectEqual(@as(u32, 250), l.depth_below);
    var bd: ProvBuf = .{};
    const d = try layProv("\\underlinesegment{AB}", stubProvider(), &bd);
    try std.testing.expectEqual(@as(u32, 1000), d.width);
    try std.testing.expectEqual(@as(u32, 700), d.height_above);
    try std.testing.expectEqual(@as(u32, 772), d.depth_below);
}

test "qa96 underbar is the underline rule over a text nucleus" {
    // KaTeX renders `\underbar` with the exact underline HTML
    // (pinned 0.18.7: same `katex-underline` span, same 0.04em
    // rule) but sets the body in text mode (issue #96): roman AB
    // under a full-width rule — the same rule row `\underline`
    // produces (1000 wide, depth 460), never the missing glyph.
    var a: B = .{};
    const l = try lay("\\underbar{AB}", false, &a);
    try std.testing.expectEqual(@as(u32, 1000), l.width);
    try std.testing.expectEqual(@as(u32, 460), l.depth_below);
    var roman = false;
    for (l.runs) |r| {
        if (r.glyphs.len == 2 and r.glyphs[0] == 65 and r.glyphs[1] == 66) roman = true;
    }
    try std.testing.expect(roman);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
    try std.testing.expectEqual(@as(u32, 1000), l.rules[0].w);
}

test "qa104 overarrows stretch to the nucleus span" {
    // KaTeX windows each shaft+head SVG over the content span
    // (pinned 0.18.7 `stretchy.ts`, minWidth 0.888em), so the arrow
    // box is exactly the nucleus width and the single host glyph
    // raster-stretches to it (same `x_scale` model as braces, issue
    // #104). Stub advances are uniform 500: AB spans 1000 (scale
    // 2000). Narrow nuclei keep the fixed glyph bit-identically.
    const cases = [_]struct { tex: []const u8, cp: u21 }{
        .{ .tex = "\\overrightarrow{AB}", .cp = 0x2192 },
        .{ .tex = "\\overleftarrow{AB}", .cp = 0x2190 },
        .{ .tex = "\\overleftrightarrow{AB}", .cp = 0x2194 },
        .{ .tex = "\\underrightarrow{AB}", .cp = 0x2192 },
        .{ .tex = "\\underleftrightarrow{AB}", .cp = 0x2194 },
        .{ .tex = "\\Overrightarrow{AB}", .cp = 0x21D2 },
        .{ .tex = "\\overgroup{AB}", .cp = 0x23E0 },
    };
    for (cases) |c| {
        var b: ProvBuf = .{};
        const l = try layProv(c.tex, stubProvider(), &b);
        try std.testing.expectEqual(@as(u32, 1000), l.width);
        var found = false;
        for (l.runs) |r| {
            for (r.glyphs) |g| {
                if (g != c.cp) continue;
                found = true;
                try std.testing.expectEqual(@as(u16, 2000), r.x_scale);
                try std.testing.expectEqual(@as(i32, 0), r.x);
            }
        }
        try std.testing.expect(found);
    }
    // Narrow nucleus: KaTeX minWidth 0.888em binds (pinned 0.18.7
    // `katexImagesData`), so the 500-wide stub glyph stretches to
    // 888 (scale 1776, issue #96).
    var bn: ProvBuf = .{};
    const n = try layProv("\\overrightarrow{i}", stubProvider(), &bn);
    try std.testing.expectEqual(@as(u32, 888), n.width);
    for (n.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 0x2192) {
                try std.testing.expectEqual(@as(u16, 1776), r.x_scale);
                try std.testing.expectEqual(@as(i32, 0), r.x);
            }
        }
    }
    // The tilde stretches to the span like the other wide accents
    // (KaTeX `preserveAspectRatio="none"`, issue #96): AB spans
    // 1000 over the 500 stub glyph (scale 2000).
    var bt: ProvBuf = .{};
    const t = try layProv("\\utilde{AB}", stubProvider(), &bt);
    try std.testing.expectEqual(@as(u32, 1000), t.width);
    for (t.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 0x007E) {
                try std.testing.expectEqual(@as(u16, 2000), r.x_scale);
                try std.testing.expectEqual(@as(i32, 0), r.x);
            }
        }
    }
}

test "qa104 x-arrows stretch to the label span" {
    // KaTeX stretches x-arrow shafts to the label width (pinned
    // 0.18.7 `stretchy.ts`, minWidth 1.469em): the glyph
    // raster-stretches to the label span (issue #104). Stub advances
    // are uniform 500, scaled by the script size: [ab]{cd} spans
    // 2*350 = 700 (scale 1400).
    var b: ProvBuf = .{};
    const l = try layProv("\\xrightarrow[ab]{cd}", stubProvider(), &b);
    try std.testing.expectEqual(@as(u32, 700), l.width);
    var found = false;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g != 0x2192) continue;
            found = true;
            try std.testing.expectEqual(@as(u16, 1400), r.x_scale);
            try std.testing.expectEqual(@as(i32, 0), r.x);
        }
    }
    try std.testing.expect(found);
}

test "qa43 fraction shifts differ per mode" {
    // TeX Rules 15b-e (issue #32): display shifts are num1/denom1
    // (677/686, the reference font's MATH constants) with 3θ
    // clearance; text shifts are num2/denom2 (394/345) with θ
    // clearance, bumped when content would collide. Shifts live in
    // the ambient size while numerator/denominator glyphs lay out in
    // script styles — stub 'a'/'b' are 700/250 at size 1000:
    // display: ns=677, no bump (gap 157 ≥ 120), ha=677+700=1377;
    //   ds=686, no bump (gap 216 ≥ 120), db=686+250=936.
    // text: ns=394→485 (bumped: gap -51 < 40), ha=485+490=975;
    //   ds=345, no bump (gap 85 ≥ 40), db=345+175=520.
    var bd: B = .{};
    var bt: B = .{};
    const d = try lay("\\frac{a}{b}", true, &bd);
    const t = try lay("\\frac{a}{b}", false, &bt);
    try std.testing.expectEqual(@as(u32, 740), d.width);
    try std.testing.expectEqual(@as(u32, 1377), d.height_above);
    try std.testing.expectEqual(@as(u32, 936), d.depth_below);
    try std.testing.expectEqual(@as(u32, 590), t.width);
    try std.testing.expectEqual(@as(u32, 975), t.height_above);
    try std.testing.expectEqual(@as(u32, 520), t.depth_below);
    try std.testing.expectEqual(@as(usize, 1), d.rules.len);
    try std.testing.expectEqual(@as(u32, 40), d.rules[0].h);
}

test "qa43 overbrace and underbrace baselines per mode" {
    // Brace overs/unders lay out identically in both modes (no
    // display-sensitive sizing on this path): the matrix pins the exact
    // integer baselines per mode rather than assuming a difference.
    // KaTeX stacks the label (`mover`/`munder`, verified against pinned
    // 0.18.7): the box is the nucleus span (1944 = 500+222+500+222+500;
    // the brace glyph centers and never widens it, issue #37), the
    // brace rides at gap 150, and the script-size label stacks above:
    // over: brace ha = 700+150+250+700 = 1800, label top at
    //   1800+150+175+490 = 2615, depth 250.
    // under: mirrored, depth = 1350+150+490+175 = 2165, height 700.
    for ([_]bool{ false, true }) |display| {
        var bo: B = .{};
        var bu: B = .{};
        const o = try lay("\\overbrace{a+b}^{n}", display, &bo);
        try std.testing.expectEqual(@as(u32, 1944), o.width);
        try std.testing.expectEqual(@as(u32, 2615), o.height_above);
        try std.testing.expectEqual(@as(u32, 250), o.depth_below);
        const u = try lay("\\underbrace{a+b}_{n}", display, &bu);
        try std.testing.expectEqual(@as(u32, 1944), u.width);
        try std.testing.expectEqual(@as(u32, 700), u.height_above);
        try std.testing.expectEqual(@as(u32, 2165), u.depth_below);
    }
    // And byte-identical across modes, not just equal scalars.
    var b1: B = .{};
    var b2: B = .{};
    var b3: B = .{};
    var b4: B = .{};
    const o_d = try lay("\\overbrace{a+b}^{n}", true, &b1);
    const o_t = try lay("\\overbrace{a+b}^{n}", false, &b2);
    var d1: [8192]u8 = undefined;
    var d2: [8192]u8 = undefined;
    try inv.expectSameDump(o_d, o_t, &d1, &d2);
    const u_d = try lay("\\underbrace{a+b}_{n}", true, &b3);
    const u_t = try lay("\\underbrace{a+b}_{n}", false, &b4);
    var d3: [8192]u8 = undefined;
    var d4: [8192]u8 = undefined;
    try inv.expectSameDump(u_d, u_t, &d3, &d4);
}

test "qa43 mode never changes the accept set" {
    // Cross-check against the pinned sweep like `parity.zig`: every row
    // must agree on accept/reject in BOTH modes, and (for declared rows)
    // match the pinned KaTeX verdict. Mode changes geometry, never the
    // accept set.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const goldens = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "goldens/katex_sweep.json",
        alloc,
        .limited(4 * 1024 * 1024),
    );
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, goldens, .{});
    const root = parsed.value.object.get("cases").?.array;
    var n_same_ok: usize = 0;
    var n_same_rej: usize = 0;
    for (root.items) |item| {
        const o = item.object;
        const id = o.get("id").?.string;
        const tex = o.get("tex").?.string;
        const katex_ok = o.get("katex_ok").?.bool;
        const katex_only = o.get("katex_only").?.bool;
        var b_d: B = .{};
        var b_t: B = .{};
        var dd = zatex.Diag.empty();
        var dt = zatex.Diag.empty();
        const rd = zatex.layoutDiag(tex, .{ .display_mode = true }, stubProvider(), &b_d.runs, &b_d.rules, &b_d.glyphs, &dd);
        const rt = zatex.layoutDiag(tex, .{ .display_mode = false }, stubProvider(), &b_t.runs, &b_t.rules, &b_t.glyphs, &dt);
        const ok_d = if (rd) |_| true else |_| false;
        const ok_t = if (rt) |_| true else |_| false;
        // `\tag` is KaTeX's only display-gated command (pinned
        // 0.18.7: accepts in display, `\tag works only in display
        // equations` otherwise), so tag rows agree per-mode with the
        // pin (`parity.zig` checks each row in its own mode, and the
        // tag unit test pins both error messages) rather than across
        // modes here.
        if (std.mem.eql(u8, id, "tag") or std.mem.startsWith(u8, id, "tag-")) continue;
        // Display-only environments (issues #83/#85/#86/#87/#90):
        // KaTeX itself accepts these rows in display mode and
        // rejects them inline, so cross-mode agreement cannot hold
        // by design. `parity.zig` checks each row in its own mode.
        if (std.mem.startsWith(u8, id, "disp-")) continue;
        if (ok_d != ok_t) {
            std.debug.print("\n[{s}] mode changes accept set: display={} text={}\n", .{ id, ok_d, ok_t });
            return error.TestUnexpectedResult;
        }
        if (katex_only) {
            const want = o.get("ours").?.string;
            if (ok_d) {
                std.debug.print("\n[{s}] katex_only row unexpectedly accepted\n", .{id});
                return error.TestUnexpectedResult;
            }
            const e: anyerror = if (rd) |_| unreachable else |err| err;
            if (!std.mem.eql(u8, want, @errorName(e))) {
                std.debug.print("\n[{s}] want {s}, got {s}\n", .{ id, want, @errorName(e) });
                return error.TestUnexpectedResult;
            }
            n_same_rej += 1;
            continue;
        }
        if (ok_d != katex_ok) {
            std.debug.print("\n[{s}] accept mismatch vs pin: ours={} katex={}\n", .{ id, ok_d, katex_ok });
            return error.TestUnexpectedResult;
        }
        if (ok_d) {
            n_same_ok += 1;
        } else {
            n_same_rej += 1;
        }
    }
    std.debug.print("\nmode matrix: {d} accept both, {d} reject both\n", .{ n_same_ok, n_same_rej });
}

// ---------------------------------------------------------------------------
// Issue #44: exact adversarial caps (fixed inputs, KaTeX-mirroring pins)
// ---------------------------------------------------------------------------

test "qa44 expansion bomb trips exactly at maxExpand" {
    // `contract.max_expand` is 1000 by name (KaTeX `maxExpand` parity,
    // AGENTS.md section 1; same bar as `fuzz.zig`'s cap-name asserts).
    try std.testing.expectEqual(@as(u32, 1000), zatex.max_expand);
    // The self-loop bomb: honest `ExpansionLimit` with the exact message
    // and the use-site byte offset (rewritten onto every pushed token,
    // so the offset is the `\a` use at byte 10, KaTeX `ParseError`
    // 0-based convention per `parity.zig`).
    var b: B = .{};
    var diag = zatex.Diag.empty();
    const r = zatex.layoutDiag("\\def\\a{\\a}\\a", .{}, stubProvider(), &b.runs, &b.rules, &b.glyphs, &diag);
    try std.testing.expectError(error.ExpansionLimit, r);
    try std.testing.expectEqualStrings("macro expansion limit exceeded", diag.message);
    try std.testing.expectEqual(@as(u32, 10), diag.offset);
    // KaTeX contrast, pinned against vendored 0.18.7 (`tools/katex`,
    // no network): KaTeX reports "Too many expansions: infinite loop
    // or need to increase maxExpand setting" with NO position. Our
    // message text is therefore engine-observable, NOT KaTeX-exact —
    // message parity is engine work (parse.zig, out of scope here).
}

test "qa44 expansion boundary is exact at 1000 uses" {
    // `\def\a{}` expands to nothing: each `\a` use costs exactly one
    // expansion and zero nodes, isolating the counter. 1000 uses land
    // exactly on budget (accepted); the 1001st use (byte offset
    // 8 + 2*1000 = 2008) trips it. Inputs end in ` x` (space-separated:
    // the lexer would fuse a trailing `\a`+`x` into undefined `\ax`,
    // and a macro expanding to empty at end of input is rejected —
    // quirks noted below), keeping the boundary measurement clean.
    var ok_buf: [8 + 2 * 1000 + 2]u8 = undefined;
    @memcpy(ok_buf[0..8], "\\def\\a{}");
    for (0..1000) |k| @memcpy(ok_buf[8 + 2 * k ..][0..2], "\\a");
    @memcpy(ok_buf[8 + 2 * 1000 ..][0..2], " x");
    var b0: B = .{};
    const l = try lay(&ok_buf, false, &b0);
    try std.testing.expectEqual(@as(u32, 500), l.width);
    var bad_buf: [8 + 2 * 1001 + 2]u8 = undefined;
    @memcpy(bad_buf[0..8], "\\def\\a{}");
    for (0..1001) |k| @memcpy(bad_buf[8 + 2 * k ..][0..2], "\\a");
    @memcpy(bad_buf[8 + 2 * 1001 ..][0..2], " x");
    var b1: B = .{};
    var diag = zatex.Diag.empty();
    const r = zatex.layoutDiag(&bad_buf, .{}, stubProvider(), &b1.runs, &b1.rules, &b1.glyphs, &diag);
    try std.testing.expectError(error.ExpansionLimit, r);
    try std.testing.expectEqualStrings("macro expansion limit exceeded", diag.message);
    try std.testing.expectEqual(@as(u32, 2008), diag.offset);
    // QUIRK NOTE (engine behavior, KaTeX-divergent): `\def\a{}\a` —
    // trailing use expanding to empty at end of input — is `Invalid`
    // ("unexpected end of input" at EOF); KaTeX accepts it. Engine fix
    // lives in parse.zig (out of scope for this test module).
}

test "qa44 nesting bomb trips exactly at max_nesting_depth" {
    // `contract.max_nesting_depth` is 32 by name. KaTeX has no depth
    // cap (40 bare `{` is `Invalid` "Expected '}', got 'EOF'" at offset
    // 40 there); our bounded-depth rejection is the AGENTS.md section 1
    // totality tenet, pinned here with the `parity.zig` 0-based offset
    // convention instead.
    try std.testing.expectEqual(@as(u8, 32), zatex.max_nesting_depth);
    var deep: [40]u8 = undefined;
    @memset(&deep, '{');
    var b: B = .{};
    var diag = zatex.Diag.empty();
    const r = zatex.layoutDiag(&deep, .{}, stubProvider(), &b.runs, &b.rules, &b.glyphs, &diag);
    try std.testing.expectError(error.TooDeep, r);
    try std.testing.expectEqualStrings("nesting too deep", diag.message);
    try std.testing.expectEqual(@as(u32, 32), diag.offset);
    // Boundary: 31 balanced groups nest fine (innermost content parses
    // at depth 31 < 32); the 32nd level trips the guard at its token
    // (offset 32 either way: the 33rd `{`, or the `x` at depth 32).
    var ok_in: [31 * 2 + 1]u8 = undefined;
    @memset(ok_in[0..31], '{');
    ok_in[31] = 'x';
    @memset(ok_in[32..], '}');
    var b0: B = .{};
    _ = try lay(&ok_in, false, &b0);
    var bad_in: [32 * 2 + 1]u8 = undefined;
    @memset(bad_in[0..32], '{');
    bad_in[32] = 'x';
    @memset(bad_in[33..], '}');
    var b1: B = .{};
    var diag1 = zatex.Diag.empty();
    const r1 = zatex.layoutDiag(&bad_in, .{}, stubProvider(), &b1.runs, &b1.rules, &b1.glyphs, &diag1);
    try std.testing.expectError(error.TooDeep, r1);
    try std.testing.expectEqual(@as(u32, 32), diag1.offset);
}

test "qa44 input length boundary is exact at max_input_len" {
    // `contract.max_input_len` is 64 KiB by name; the `>` gate in
    // `layoutInner` caps it. `%` comments lex to nothing, so a comment
    // tail pads an otherwise-trivial `x` to the exact boundary with
    // tiny caller buffers. KaTeX has no input cap (it would accept all
    // three); the cap error is asserted BY NAME per the issue.
    try std.testing.expectEqual(@as(usize, 64 * 1024), zatex.max_input_len);
    var under: [zatex.max_input_len - 1]u8 = undefined;
    under[0] = 'x';
    under[1] = '%';
    @memset(under[2..], 'y');
    var b0: B = .{};
    const l0 = try lay(&under, false, &b0);
    try std.testing.expectEqual(@as(u32, 500), l0.width);
    var exact: [zatex.max_input_len]u8 = undefined;
    exact[0] = 'x';
    exact[1] = '%';
    @memset(exact[2..], 'y');
    var b1: B = .{};
    const l1 = try lay(&exact, false, &b1);
    try std.testing.expectEqual(@as(u32, 500), l1.width);
    var over: [zatex.max_input_len + 1]u8 = undefined;
    over[0] = 'x';
    over[1] = '%';
    @memset(over[2..], 'y');
    var b2: B = .{};
    try std.testing.expectError(error.TooLong, lay(&over, false, &b2));
}

// ---------------------------------------------------------------------------
// Issue #45: subset-vs-full profile byte-identical IR over the sweep
// ---------------------------------------------------------------------------

test "qa45 full profile matches the cross-profile golden" {
    // Cross-profile half owned by this (full) binary: every row of the
    // checked-in `goldens/qa_profile_ir.json` (subset-renderable sweep
    // accepts with canonical IR dumps) must render byte-identically
    // under the full profile. The subset binary (`qa_subset`) asserts
    // the same file under subset gates plus the allowlist half, so a
    // green pair means byte-identical IR across profiles with every
    // divergence allowlisted and reviewed.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const raw = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "goldens/qa_profile_ir.json",
        alloc,
        .limited(4 * 1024 * 1024),
    );
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    const rows = parsed.value.object.get("rows").?.array;
    try std.testing.expect(rows.items.len > 0);
    var n: usize = 0;
    for (rows.items) |item| {
        const o = item.object;
        const id = o.get("id").?.string;
        const tex = o.get("tex").?.string;
        const display = o.get("display").?.bool;
        const want = o.get("ir").?.string;
        var b: B = .{};
        const l = lay(tex, display, &b) catch |e| {
            std.debug.print("\n[{s}] full rejects golden row ({s})\n", .{ id, @errorName(e) });
            return error.TestUnexpectedResult;
        };
        var db: [16384]u8 = undefined;
        try expectGolden(id, want, dumpAny(l, &db));
        n += 1;
    }
    std.debug.print("\nprofiles(full): {d} golden rows identical\n", .{n});
}

// ---------------------------------------------------------------------------
// Issue #46: sweep accepted-count ratchet (coverage never regresses)
// ---------------------------------------------------------------------------

test "qa46 accepted count never regresses below the floor" {
    // Distinct from freshness ("goldens match the pin"): the ratchet
    // fails loudly if engine coverage SHRINKS. Reads the checked-in
    // floor next to the sweep JSON only — no network. The floor rises
    // deliberately with KaTeX-side proof (AGENTS.md section 4).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const goldens = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "goldens/katex_sweep.json",
        alloc,
        .limited(4 * 1024 * 1024),
    );
    const floor_raw = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "goldens/katex_sweep_floor.json",
        alloc,
        .limited(4096),
    );
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, goldens, .{});
    const floor_parsed = try std.json.parseFromSlice(std.json.Value, alloc, floor_raw, .{});
    const root = parsed.value.object.get("cases").?.array;
    const floor = floor_parsed.value.object.get("accepted_floor").?.integer;
    const sweep_version = parsed.value.object.get("katex_version").?.string;
    const floor_version = floor_parsed.value.object.get("katex_version").?.string;
    try std.testing.expectEqualStrings(sweep_version, floor_version);
    var accepted: usize = 0;
    var total: usize = 0;
    for (root.items) |item| {
        const o = item.object;
        if (o.get("katex_only").?.bool) continue;
        const tex = o.get("tex").?.string;
        const display = o.get("display").?.bool;
        total += 1;
        var b: B = .{};
        var diag = zatex.Diag.empty();
        if (zatex.layoutDiag(tex, .{ .display_mode = display }, stubProvider(), &b.runs, &b.rules, &b.glyphs, &diag)) |_| {
            accepted += 1;
        } else |_| {}
    }
    std.debug.print("\nratchet: accepted {d}/{d}, floor {d}\n", .{ accepted, total, floor });
    if (@as(i64, @intCast(accepted)) < floor) {
        std.debug.print("\nCOVERAGE REGRESSION: accepted {d} < floor {d}\n", .{ accepted, floor });
        return error.TestUnexpectedResult;
    }
}

// ---------------------------------------------------------------------------
// Issue #47: exact-string MathML + speech goldens, texser round trip
// ---------------------------------------------------------------------------

const golden47 = [_][]const u8{
    "x+y=z",
    "\\frac{a}{b}",
    "\\sqrt{x}",
    "\\sqrt[n]{x+1}",
    "\\sum_{i=1}^{n} i",
    "\\lim_{x} f(x)",
    "\\int_{0}^{1} x",
    "x^{2}+y_{1}",
    "\\alpha+\\beta",
    "\\frac{1}{1+\\frac{1}{x}}",
    "\\begin{matrix}a&b\\\\c&d\\end{matrix}",
    "\\left(x\\right)",
    "\\overline{AB}",
    "\\hat{x}+\\vec{y}",
    "\\mathbf{A}+\\mathit{B}",
    "\\color{red}{x}+y",
    "\\text{hello }+x",
    "\\binom{n}{k}",
    "\\frac{x^2}{1}",
    "A_{B_C}",
    "\\includegraphics{a}",
    "\\includegraphics[width=1mu,height=1bp]{a}",
    "\\includegraphics[height=2pt,totalheight=3pt]{a}",
    "\\includegraphics[alt=x]{a}",
};

fn expectGolden(id: []const u8, golden: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, golden, actual)) {
        // Textual diff, never a screenshot: both sides printed in full.
        std.debug.print("\ngolden mismatch [{s}]\n--- golden ---\n{s}\n--- actual ---\n{s}\n--- end ---\n", .{ id, golden, actual });
        return error.TestUnexpectedResult;
    }
}

const golden_mathml = [_][]const u8{
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mi>x</mi><mo>+</mo><mi>y</mi><mo>=</mo><mi>z</mi></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mfrac><mi>a</mi><mi>b</mi></mfrac></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msqrt><mi>x</mi></msqrt></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mroot><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow><mi>n</mi></mroot></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msubsup><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></msubsup><mi>i</mi></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msub><mrow><mi>lim</mi><mo>⁡</mo></mrow><mi>x</mi></msub><mi>f</mi><mo>(</mo><mi>x</mi><mo>)</mo></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msubsup><mo>∫</mo><mn>0</mn><mn>1</mn></msubsup><mi>x</mi></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><msub><mi>y</mi><mn>1</mn></msub></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mi>α</mi><mo>+</mo><mi>β</mi></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mfrac><mn>1</mn><mrow><mn>1</mn><mo>+</mo><mfrac><mn>1</mn><mi>x</mi></mfrac></mrow></mfrac></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mtable><mtr><mtd><mstyle scriptlevel=\"0\" displaystyle=\"false\"><mi>a</mi></mstyle></mtd><mtd><mstyle scriptlevel=\"0\" displaystyle=\"false\"><mi>b</mi></mstyle></mtd></mtr><mtr><mtd><mstyle scriptlevel=\"0\" displaystyle=\"false\"><mi>c</mi></mstyle></mtd><mtd><mstyle scriptlevel=\"0\" displaystyle=\"false\"><mi>d</mi></mstyle></mtd></mtr></mtable></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo fence=\"true\">(</mo><mi>x</mi><mo fence=\"true\">)</mo></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover><mrow><mi>A</mi><mi>B</mi></mrow><mo>&#x203E;</mo></mover></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover><mi>x</mi><mo>^</mo></mover><mo>+</mo><mover><mi>y</mi><mo>⃗</mo></mover></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathvariant=\"bold\"><mi>A</mi></mstyle><mo>+</mo><mstyle mathvariant=\"italic\"><mi>B</mi></mstyle></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathcolor=\"red\"><mi>x</mi><mo>+</mo><mi>y</mi></mstyle></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mtext>hello </mtext><mo>+</mo><mi>x</mi></mrow></math>",
    // Issue #93: KaTeX wraps fenced stacks in fence mo's (pinned
    // 0.18.7: `<mo fence="true">(</mo>` for `\binom{n}{k}`).
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo fence=\"true\">(</mo><mfrac linethickness=\"0\"><mi>n</mi><mi>k</mi></mfrac><mo fence=\"true\">)</mo></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mfrac><msup><mi>x</mi><mn>2</mn></msup><mn>1</mn></mfrac></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msub><mi>A</mi><msub><mi>B</mi><mi>C</mi></msub></msub></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mglyph alt=\"\" height=\"0.9em\" src=\"a\"></mglyph></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mglyph alt=\"\" height=\"0.1004em\" width=\"0.0556em\" src=\"a\"></mglyph></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mglyph alt=\"\" valign=\"-0.1em\" height=\"0.3em\" src=\"a\"></mglyph></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mglyph alt=\"x\" height=\"0.9em\" src=\"a\"></mglyph></mrow></math>",
};
const golden_speech = [_][]const u8{
    "x, plus, y, equals, z",
    "fraction, numerator, a, denominator, b, end fraction",
    "square root of, x, end root",
    "n, root of, x, plus, 1, end root",
    "sum, from, i, equals, 1, to, n, i",
    "lim, subscript, x, end subscript, f, left parenthesis, x, right parenthesis",
    "integral, from, 0, to, 1, x",
    "x, superscript, 2, end superscript, plus, y, subscript, 1, end subscript",
    "alpha, plus, beta",
    "fraction, numerator, 1, denominator, 1, plus, fraction, numerator, 1, denominator, x, end fraction, end fraction",
    "matrix, row, a, b, row, c, d, end matrix",
    "left, parenthesis, x, right, parenthesis",
    "A, B, overbar",
    "x, hat, plus, y, vector",
    "A, plus, B",
    "x, plus, y",
    "h, e, l, l, o,  , plus, x",
    "n, choose, k",
    "fraction, numerator, x, superscript, 2, end superscript, denominator, 1, end fraction",
    "A, subscript, B, subscript, C, end subscript, end subscript",
    "image",
    "image",
    "image",
    "x",
};
const golden_texser = [_][]const u8{
    "x+y=z",
    "\\frac{a}{b}",
    "\\sqrt{x}",
    "\\sqrt[n]{x+1}",
    "\\sum^{n}_{i=1}i",
    "\\operatorname{lim}_{x}f(x)",
    "\\int^{1}_{0}x",
    "x^{2}+y_{1}",
    "\\alpha+\\beta",
    "\\frac{1}{1+\\frac{1}{x}}",
    "\\begin{matrix}a&b\\\\c&d\\end{matrix}",
    "\\left(x\\right)",
    "\\overline{AB}",
    "\\hat{x}+\\vec{y}",
    "\\mathbf{A}+\\mathit{B}",
    "\\color{red}{x}+y",
    "\\text{hello }+x",
    "\\binom{n}{k}",
    "\\frac{x^2}{1}",
    "A_{B_C}",
    "\\includegraphics{a}",
    "\\includegraphics[width=0.05556em,height=0.10038em]{a}",
    "\\includegraphics[height=0.2em,totalheight=0.3em]{a}",
    "\\includegraphics[alt=x]{a}",
};

test "qa47 mathml exact-string goldens" {
    // Locks the #26/#27 semantic work (speech strings, copy-as-LaTeX
    // annotations): exact MathML bytes over limits, fractions,
    // radicals, tables, fonts, and annotations. Text diffs only.
    for (golden47, golden_mathml) |src, want| {
        var buf: [16384]u8 = undefined;
        const got = try zatex.mathml(src, .{}, &buf);
        try expectGolden(src, want, got);
    }
}

test "qa47 speech exact-string goldens" {
    // Exact speech strings ("Fraction with numerator ..." style via
    // the speech walker), same representative set.
    for (golden47, golden_speech) |src, want| {
        var buf: [4096]u8 = undefined;
        const got = try speech.speak(src, false, &buf);
        try expectGolden(src, want, got);
    }
}

test "qa47 texser serializes the golden set" {
    // Exact serializer bytes (locks copy-as-LaTeX spellings, including
    // normalizations like `\\sum^{n}_{i=1}i` and `\\operatorname{lim}`).
    for (golden47, golden_texser) |src, want| {
        var buf: [4096]u8 = undefined;
        const got = try texser.serialize(src, false, &buf);
        try expectGolden(src, want, got);
    }
}

test "qa47 texser round trip preserves IR" {
    // parse -> serialize -> parse yields identical IR on the set.
    for (golden47) |src| {
        var tbuf: [4096]u8 = undefined;
        const tex = try texser.serialize(src, false, &tbuf);
        var b0: B = .{};
        var b1: B = .{};
        const l0 = try lay(src, false, &b0);
        const l1 = try lay(tex, false, &b1);
        var d0: [8192]u8 = undefined;
        var d1: [8192]u8 = undefined;
        const t0 = dumpAny(l0, &d0);
        const t1 = dumpAny(l1, &d1);
        if (!std.mem.eql(u8, t0, t1)) {
            std.debug.print("\nround-trip IR mismatch [{s}] via [{s}]\n--- first ---\n{s}\n--- second ---\n{s}\n--- end ---\n", .{ src, tex, t0, t1 });
            return error.TestUnexpectedResult;
        }
    }
}

// Issue #48: provider scaling (anti-hardcoding)
// ---------------------------------------------------------------------------

const TallNarrow = struct {
    // "Tall/narrow" metrics: tight advances, tall extents, thick rules.
    fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
        return @truncate(cp);
    }
    fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
        return 300;
    }
    fn ruleThickness(_: *const anyopaque, _: u16, kind: zatex.RuleKind) i32 {
        return switch (kind) {
            .fraction_bar => 90,
            .radical => 90,
            .overline => 50,
            .underline => 50,
        };
    }
    fn extents(_: *const anyopaque, _: u16, _: u16) [2]i32 {
        return .{ 900, 450 };
    }
    fn italicCorrection(_: *const anyopaque, _: u16, _: u16) i32 {
        return 60;
    }
};

const ShortWide = struct {
    // "Short/wide" metrics: loose advances, flat extents, thin rules.
    fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
        return @truncate(cp);
    }
    fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
        return 700;
    }
    fn ruleThickness(_: *const anyopaque, _: u16, kind: zatex.RuleKind) i32 {
        return switch (kind) {
            .fraction_bar => 20,
            .radical => 20,
            .overline => 16,
            .underline => 16,
        };
    }
    fn extents(_: *const anyopaque, _: u16, _: u16) [2]i32 {
        return .{ 500, 100 };
    }
    fn italicCorrection(_: *const anyopaque, _: u16, _: u16) i32 {
        return 10;
    }
};

fn tallProvider() zatex.MetricsProvider {
    const S = struct {
        var dummy: u8 = 0;
    };
    return .{
        .ctx = &S.dummy,
        .glyphId = TallNarrow.glyphId,
        .advance = TallNarrow.advance,
        .ruleThickness = TallNarrow.ruleThickness,
        .extents = TallNarrow.extents,
        .italicCorrection = TallNarrow.italicCorrection,
    };
}

fn wideProvider() zatex.MetricsProvider {
    const S = struct {
        var dummy: u8 = 0;
    };
    return .{
        .ctx = &S.dummy,
        .glyphId = ShortWide.glyphId,
        .advance = ShortWide.advance,
        .ruleThickness = ShortWide.ruleThickness,
        .extents = ShortWide.extents,
        .italicCorrection = ShortWide.italicCorrection,
    };
}

const ProvBuf = struct {
    runs: [64]zatex.ir.Run = undefined,
    rules: [16]zatex.ir.Rule = undefined,
    glyphs: [1024]u16 = undefined,
};

fn layProv(src: []const u8, prov: zatex.MetricsProvider, b: *ProvBuf) !zatex.ir.Layout {
    var diag = zatex.Diag.empty();
    return zatex.layoutDiag(src, .{}, prov, &b.runs, &b.rules, &b.glyphs, &diag);
}

test "qa48 fraction geometry moves with provider metrics" {
    // Recomputed from the inputs per the core formulas (`layoutFrac`,
    // TeX Rules 15b-e): bar h = ruleThickness(.fraction_bar);
    // axis = 250mu fixed (engine constant, NOT provider-driven — see
    // note); text shifts num2/denom2 (394/345, ambient size) with θ
    // clearance, bumped when content would collide. Numerator /
    // denominator glyphs lay out at script scale (0.7), so their
    // extents enter at 7/10. Both sets asserted exactly, and the two
    // layouts must DIFFER (a constant hardcoded to one set fails the
    // other by construction).
    // tall/narrow (adv 300, ext 900/450, bar 90): script extents
    //   210/630/315; gap_n = (394-315)-(250+45) = -216 < 90 so
    //   ns = 394+306 = 700, ha = 700+630 = 1330; gap_d =
    //   (250-45)-(630-345) = -80 < 90 so ds = 345+170 = 515,
    //   db = 515+315 = 830; width 210+240 = 450.
    // short/wide (adv 700, ext 500/100, bar 20): script extents
    //   490/350/70; gap_n = 64 ≥ 20 so ns = 394, ha = 744;
    //   gap_d = 235 ≥ 20 so ds = 345, db = 415; width 730.
    const sets = [_]struct {
        prov: zatex.MetricsProvider,
        adv: i32,
        ha: i32,
        db: i32,
        th: i32,
        name: []const u8,
    }{
        .{ .prov = tallProvider(), .adv = 300, .ha = 900, .db = 450, .th = 90, .name = "tall/narrow" },
        .{ .prov = wideProvider(), .adv = 700, .ha = 500, .db = 100, .th = 20, .name = "short/wide" },
    };
    var dumps: [2][]const u8 = undefined;
    var dump_bufs: [2][4096]u8 = .{ undefined, undefined };
    for (sets, 0..) |s, k| {
        var b: ProvBuf = .{};
        const l = try layProv("\\frac{a}{b}", s.prov, &b);
        // Script-scale (S = 700) numerator/denominator extents.
        const nw: i64 = @divTrunc(@as(i64, s.adv) * 700, 1000);
        const nha: i64 = @divTrunc(@as(i64, s.ha) * 700, 1000);
        const ndb: i64 = @divTrunc(@as(i64, s.db) * 700, 1000);
        const axis: i64 = 250;
        const clear: i64 = s.th;
        var ns: i64 = 394;
        const gap_n: i64 = (ns - ndb) - (axis + @divTrunc(@as(i64, s.th), 2));
        if (gap_n < clear) ns += clear - gap_n;
        var ds: i64 = 345;
        const gap_d: i64 = (axis - @divTrunc(@as(i64, s.th), 2)) - (nha - ds);
        if (gap_d < clear) ds += clear - gap_d;
        try std.testing.expectEqual(@as(u32, @intCast(nw + 2 * 120)), l.width);
        try std.testing.expectEqual(@as(u32, @intCast(ns + nha)), l.height_above);
        try std.testing.expectEqual(@as(u32, @intCast(ds + ndb)), l.depth_below);
        try std.testing.expectEqual(@as(usize, 1), l.rules.len);
        try std.testing.expectEqual(@as(u32, @intCast(s.th)), l.rules[0].h);
        dumps[k] = dumpAny(l, &dump_bufs[k]);
    }
    try std.testing.expect(!std.mem.eql(u8, dumps[0], dumps[1]));
    // Tall-set exact numbers must NOT match the wide layout: the
    // hardcoded-constant killer, asserted directly (tall width 450 and
    // bar 90 vs wide 730 and 20).
    var bw: ProvBuf = .{};
    const lw = try layProv("\\frac{a}{b}", wideProvider(), &bw);
    try std.testing.expect(lw.width != 450);
    try std.testing.expect(lw.rules[0].h != 90);
}

test "qa48 accent gap moves with provider metrics" {
    // Recomputed from the inputs per `layoutAccent` (KaTeX `accent.ts`
    // clearance, issue #30): the accent tucks to within an x-height
    // (431mu engine constant) of the body top — ay = nb.ha -
    // min(nb.ha, xh) + adb, ha = ay + aha, all from the extents hook;
    // the accent x carries half the italic correction (provider hook).
    // tall/narrow: ay = 900-431+450 = 919, ha = 919+900 = 1819.
    // short/wide: ay = 500-431+100 = 169, ha = 169+500 = 669.
    const sets = [_]struct {
        prov: zatex.MetricsProvider,
        adv: i32,
        ha: i32,
        db: i32,
        skew: i32,
        name: []const u8,
    }{
        .{ .prov = tallProvider(), .adv = 300, .ha = 900, .db = 450, .skew = 60, .name = "tall/narrow" },
        .{ .prov = wideProvider(), .adv = 700, .ha = 500, .db = 100, .skew = 10, .name = "short/wide" },
    };
    var dumps: [2][]const u8 = undefined;
    var dump_bufs: [2][4096]u8 = .{ undefined, undefined };
    for (sets, 0..) |s, k| {
        var b: ProvBuf = .{};
        const l = try layProv("\\hat{x}", s.prov, &b);
        const xh: i64 = 431;
        const clearance: i64 = if (s.ha < xh) s.ha else xh;
        const ay: i64 = s.ha - clearance + s.db;
        try std.testing.expectEqual(@as(u32, @intCast(s.adv)), l.width);
        try std.testing.expectEqual(@as(u32, @intCast(ay + s.ha)), l.height_above);
        try std.testing.expectEqual(@as(u32, @intCast(s.db)), l.depth_below);
        dumps[k] = dumpAny(l, &dump_bufs[k]);
    }
    try std.testing.expect(!std.mem.eql(u8, dumps[0], dumps[1]));
}

test "qa48 delimiter extents move with provider metrics" {
    // Recomputed from the inputs per `layoutDelim`/`layoutFence`: the
    // grown fence centers on the fixed 250mu axis with half extent
    // (need+1)/2 where need is the TeX `make_left_right` target
    // (KaTeX `delimiters.js`, issue #102): max body distance from the
    // axis grown by delimiterFactor 901/500 with a 5pt shortfall.
    // NOTE: the axis itself (250mu) is an engine constant with no
    // provider hook — providers move fences through rule thickness and
    // body extents, which is what this test varies.
    const sets = [_]struct {
        prov: zatex.MetricsProvider,
        adv: i32,
        ha: i32,
        db: i32,
        th: i32,
        name: []const u8,
    }{
        .{ .prov = tallProvider(), .adv = 300, .ha = 900, .db = 450, .th = 90, .name = "tall/narrow" },
        .{ .prov = wideProvider(), .adv = 700, .ha = 500, .db = 100, .th = 20, .name = "short/wide" },
    };
    var dumps: [2][]const u8 = undefined;
    var dump_bufs: [2][4096]u8 = .{ undefined, undefined };
    for (sets, 0..) |s, k| {
        var b: ProvBuf = .{};
        const l = try layProv("\\left(\\frac{a}{b}\\right)", s.prov, &b);
        // Body = the fraction (script-scale numerator/denominator,
        // TeX Rules 15b-e shifts with clearance bumps, as above).
        const nw: i64 = @divTrunc(@as(i64, s.adv) * 700, 1000);
        const nha: i64 = @divTrunc(@as(i64, s.ha) * 700, 1000);
        const ndb: i64 = @divTrunc(@as(i64, s.db) * 700, 1000);
        const axis: i64 = 250;
        const fclear: i64 = s.th;
        var fns: i64 = 394;
        const fgap_n: i64 = (fns - ndb) - (axis + @divTrunc(@as(i64, s.th), 2));
        if (fgap_n < fclear) fns += fclear - fgap_n;
        var fds: i64 = 345;
        const fgap_d: i64 = (axis - @divTrunc(@as(i64, s.th), 2)) - (nha - fds);
        if (fgap_d < fclear) fds += fclear - fgap_d;
        const fha: i64 = fns + nha;
        const fdb: i64 = fds + ndb;
        const dist_a: i64 = fha - axis;
        const dist_b: i64 = fdb + axis;
        const max_dist: i64 = @max(dist_a, dist_b);
        const grow: i64 = @divTrunc(max_dist * 901, 500);
        const span: i64 = 2 * max_dist - 500;
        const need: i64 = @max(grow, span);
        const half: i64 = @divTrunc(need + 1, 2);
        // Fences (and the max with the body) set the outer box.
        const want_ha: i64 = @max(fha, axis + half);
        const want_db: i64 = @max(fdb, half - axis);
        try std.testing.expectEqual(@as(u32, @intCast(want_ha)), l.height_above);
        try std.testing.expectEqual(@as(u32, @intCast(want_db)), l.depth_below);
        const want_w: i64 = 2 * s.adv + (nw + 2 * 120);
        try std.testing.expectEqual(@as(u32, @intCast(want_w)), l.width);
        dumps[k] = dumpAny(l, &dump_bufs[k]);
    }
    try std.testing.expect(!std.mem.eql(u8, dumps[0], dumps[1]));
}



test "qa48 fcolorbox frame surrounds background" {
    // KaTeX fbox model: content + 3pt (300mu) padding, frame one rule
    // thickness outside the background. Stub 'A' is 500/700/250,
    // bar 40: bg is 1100 wide, 1000 above, 550 below; the frame adds
    // 40 on every side (outer 1180/1040/590). Pins the dy-sign fix:
    // top bar spans y 0..40, bottom 1590..1630, sides 0..1630.
    var b: B = .{};
    const l = try lay("\\fcolorbox{red}{aqua}{A}", false, &b);
    try std.testing.expectEqual(@as(u32, 1180), l.width);
    try std.testing.expectEqual(@as(u32, 1040), l.height_above);
    try std.testing.expectEqual(@as(u32, 590), l.depth_below);
    try std.testing.expectEqual(@as(usize, 5), l.rules.len);
    // bg, top, bottom, left, right (emission order).
    const want = [_][4]i64{
        .{ 0, 40, 1100, 1550 },
        .{ -40, 0, 1180, 40 },
        .{ -40, 1590, 1180, 40 },
        .{ -40, 0, 40, 1630 },
        .{ 1100, 0, 40, 1630 },
    };
    for (l.rules, want) |r, w| {
        try std.testing.expectEqual(w[0], r.x);
        try std.testing.expectEqual(w[1], r.y);
        try std.testing.expectEqual(@as(u32, @intCast(w[2])), r.w);
        try std.testing.expectEqual(@as(u32, @intCast(w[3])), r.h);
    }
}

const InkStub = struct {
    // Stub advances with LM-like ink bounds on accent glyphs (bounds
    // measured from the reference font); every other glyph reports a
    // degenerate box, which the core must ignore exactly.
    fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
        return @truncate(cp);
    }
    fn advance(_: *const anyopaque, _: u16, glyph: u16) i32 {
        // Combining vec has no advance, like the real font.
        if (glyph == 0x20D7) return 0;
        // Surd advance is LM-like (833) so the sqrt junction test
        // exercises the ink-overhang path (issue #56).
        if (glyph == 0x221A) return 833;
        return 500;
    }
    fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
        return 40;
    }
    fn inkBounds(_: *const anyopaque, _: u16, glyph: u16) [4]i32 {
        return switch (glyph) {
            // Caron ink is narrower than its advance (wide side
            // bearings), like the LM Math fixture: issue #58.
            0x02C7 => .{ 90, 500, 410, 700 },
            // Brace ink edges measured from the LM fixture outlines
            // via fontTools BoundsPen (upm 1000): U+23DE ink sits
            // 539mu above its baseline; U+23DF ink hangs 109mu above
            // its baseline (issue #55).
            0x23DE => .{ 0, 539, 492, 783 },
            0x23DF => .{ 0, -353, 492, -109 },
            // LM group parens (issue #96; measured from the vendored
            // latinmodern-math.otf via fontTools BoundsPen).
            0x23E0 => .{ 0, 657, 546, 829 },
            0x23E1 => .{ 0, -399, 546, -227 },
            // Base radical ink (LM-measured): right edge overhangs
            // the 833 advance by 20mu (issue #56).
            0x221A => .{ 73, -960, 853, 40 },
            '~' => .{ 0, 193, 555, 307 },
            0x20D7 => .{ -472, 521, -56, 711 },
            '.' => .{ 86, 0, 192, 106 },
            0x02D9 => .{ 85, 551, 192, 657 },
            else => .{ 0, 0, 0, 0 },
        };
    }
};

fn inkProvider() zatex.MetricsProvider {
    const S = struct {
        var dummy: u8 = 0;
    };
    return .{
        .ctx = &S.dummy,
        .glyphId = InkStub.glyphId,
        .advance = InkStub.advance,
        .ruleThickness = InkStub.ruleThickness,
        .inkBounds = InkStub.inkBounds,
    };
}

fn layInk(src: []const u8, b: *ProvBuf) !zatex.ir.Layout {
    var diag = zatex.Diag.empty();
    return zatex.layoutDiag(src, .{}, inkProvider(), &b.runs, &b.rules, &b.glyphs, &diag);
}

test "qa48 ink lift raises low accents clear" {
    // Tilde ink bottom (+193) would nestle into the nucleus under the
    // v3 rule (ay = 700-431+250 = 519, bottom at 519+193 = 712 barely
    // above the 700 top); the v4 hook lifts it to a uniform 130mu
    // daylight: ay = 700+130-193 = 637, height 637+700 = 1337.
    // Calibrated against KaTeX ground-truth pixels (tilde ~160mu).
    var b: ProvBuf = .{};
    const l = try layInk("\\tilde{x}", &b);
    try std.testing.expectEqual(@as(u32, 500), l.width);
    try std.testing.expectEqual(@as(u32, 1337), l.height_above);
    try std.testing.expectEqual(@as(u32, 250), l.depth_below);
    const ax = try glyphX(l, '~');
    // Issue #70: the tilde centers at nucleus-center + KaTeX skew
    // (28mu for math-italic `x`), so the run starts at 28, not 0.
    try std.testing.expectEqual(@as(i32, 28), ax);
}

test "qa48 ink centers combining marks by ink" {
    // U+20D7 ink hangs left of its zero-advance origin (-472..-56);
    // centering by advance would park the arrow left of the nucleus
    // (the reported vec bug). Ink-centering: ax = (500-416)/2+472.
    var b: ProvBuf = .{};
    const l = try layInk("\\vec{F}", &b);
    const ax = try glyphX(l, 0x20D7);
    // Issue #70: (500-416)/2+472 centers the ink; the KaTeX table
    // skew for math-italic `F` (83mu) rides on top.
    try std.testing.expectEqual(@as(i32, 597), ax);
}

test "qa48 ink dots stack with daylight" {
    // Dot-run row (3 periods, 1500 wide) centers over the nucleus and
    // lifts to the same 130mu floor (period ink bottom +0).
    var b: ProvBuf = .{};
    const l = try layInk("\\dddot{x}", &b);
    try std.testing.expectEqual(@as(u32, 1500), l.width);
    try std.testing.expectEqual(@as(u32, 1530), l.height_above);
    var found = false;
    for (l.runs) |r| {
        // Issue #70: the row centers at nucleus-center + KaTeX skew
        // (28mu for math-italic `x`), so it starts at 28, not 0.
        if (r.glyphs.len == 3 and r.glyphs[0] == '.' and r.x == 28) found = true;
    }
    try std.testing.expect(found);
}

test "qa48 ink degenerate box behaves as v3" {
    // Glyphs outside the ink table (degenerate zeros) lay out exactly
    // as with a null hook: bit-identical IR.
    var b1: ProvBuf = .{};
    const hooked = try layInk("\\hat{x}", &b1);
    var b2: B = .{};
    const plain = try lay("\\hat{x}", false, &b2);
    try inv.expectSameLayout(hooked, plain);
}

test "qa48 span stretches wide accents and braces" {
    // Wide accents and brace spans raster-stretch one glyph to the
    // construction width (issues #31/#37): the layout box keeps the
    // span, the run stamps the per-mille factor. Stub advances are
    // uniform 500: AB spans 1000 (scale 2000), the a+b nucleus spans
    // 1944 (scale 3888). Narrow accents keep identity (1000).
    var b1: ProvBuf = .{};
    const w = try layProv("\\widecheck{AB}", stubProvider(), &b1);
    var wscale: ?u16 = null;
    for (w.runs) |r| {
        for (r.glyphs) |g| { if (g == 0x02C7) wscale = r.x_scale; }
    }
    try std.testing.expectEqual(@as(?u16, 2000), wscale);
    var b2: ProvBuf = .{};
    const o = try layProv("\\overbrace{a+b}", stubProvider(), &b2);
    var bscale: ?u16 = null;
    for (o.runs) |r| {
        for (r.glyphs) |g| { if (g == 0x23DE) bscale = r.x_scale; }
    }
    try std.testing.expectEqual(@as(?u16, 3888), bscale);
    var b3: ProvBuf = .{};
    const n = try layProv("\\hat{x}", stubProvider(), &b3);
    for (n.runs) |r| try std.testing.expectEqual(@as(u16, 1000), r.x_scale);
}

test "qa49 wide accent ink spans the nucleus" {
    // Issue #58: the caron advance (500) already covers the AB span
    // (1000), so advance-stretch never fired and the 320-wide ink sat
    // centered inside. KaTeX stretches wide accents to 100% of the
    // nucleus span, so the core scales INK to the span: 1000/320 =
    // 3125 per-mille, origin at -281 so scaled ink [0, 1000] covers
    // AB exactly (-281 + 90*3125/1000 = 0, -281 + 410*3125/1000 =
    // 1000). Without ink metrics (stub provider) the advance-box
    // behavior above is unchanged.
    var b: ProvBuf = .{};
    const l = try layInk("\\widecheck{AB}", &b);
    var found = false;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g != 0x02C7) continue;
            found = true;
            try std.testing.expectEqual(@as(u16, 3125), r.x_scale);
            try std.testing.expectEqual(@as(i32, -281), r.x);
        }
    }
    try std.testing.expect(found);
}

test "qa50 math alphanumeric remap" {
    // Issues #57/#62: math-variant families resolve ASCII to the SMP
    // block (the stub truncates cp to gid 1:1, so the remap is
    // directly visible): mathit x -> U+1D465, mathbf A -> U+1D400,
    // mathbf 1 -> U+1D7CE; rm and mathit digits pass through (KaTeX
    // renders Math-Italic digits upright — the block has none).
    var b1: ProvBuf = .{};
    const l1 = try layProv("x", stubProvider(), &b1);
    try std.testing.expectEqual(@as(u16, @truncate(@as(u21, 0x1D465))), l1.runs[0].glyphs[0]);
    var b2: ProvBuf = .{};
    const l2 = try layProv("\\mathbf{A1}", stubProvider(), &b2);
    try std.testing.expectEqual(@as(u16, @truncate(@as(u21, 0x1D400))), l2.runs[0].glyphs[0]);
    try std.testing.expectEqual(@as(u16, @truncate(@as(u21, 0x1D7CF))), l2.runs[0].glyphs[1]);
    var b3: ProvBuf = .{};
    const l3 = try layProv("\\mathit{1}", stubProvider(), &b3);
    try std.testing.expectEqual(@as(u16, '1'), l3.runs[0].glyphs[0]);
}

test "qa51 brace kern is ink to ink" {
    // Issue #55: the brace↔nucleus kern is 0.1em ink-to-ink (KaTeX
    // `horizBrace.ts`), not 150mu off the extents box. Stub extents
    // are 700/250 for every glyph; the ink stub carries the LM brace
    // edges (0x23DE ink bottom +539, 0x23DF ink top -109), so with
    // nucleus ha/db 700/250: over gy = 700+100-539 = 261 in a
    // 961-high construction (brace baseline 700, nucleus 961);
    // under gy = -(250+100-109) = -241 in a 491-deep one (brace
    // baseline 941, nucleus 700). Null-hook providers keep the
    // legacy 150mu rule (all other tests).
    var b1: ProvBuf = .{};
    const o = try layInk("\\overbrace{x}", &b1);
    var oy_brace: ?i32 = null;
    var oy_nuc: ?i32 = null;
    for (o.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 0x23DE) oy_brace = r.baseline_y;
            if (g == 0xD465) oy_nuc = r.baseline_y;
        }
    }
    try std.testing.expectEqual(@as(?i32, 700), oy_brace);
    try std.testing.expectEqual(@as(?i32, 961), oy_nuc);
    var b2: ProvBuf = .{};
    const u = try layInk("\\underbrace{x}", &b2);
    var uy_brace: ?i32 = null;
    var uy_nuc: ?i32 = null;
    for (u.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 0x23DF) uy_brace = r.baseline_y;
            if (g == 0xD465) uy_nuc = r.baseline_y;
        }
    }
    try std.testing.expectEqual(@as(?i32, 941), uy_brace);
    try std.testing.expectEqual(@as(?i32, 700), uy_nuc);
}

test "qa52 sqrt vinculum overlaps the surd" {
    // Issue #56 (KaTeX `sqrtMain` single-path parity): with ink
    // metrics the bar starts one rule thickness (40mu) inside the
    // hook's right ink edge (853), clamped to the 833 advance, so
    // rect and glyph rasterize as one joined stroke: dx =
    // 883-50-20 = 813, width = 500+40+50+20 = 610. Null-hook
    // providers keep the legacy advance-edge start (dx 833).
    var b: ProvBuf = .{};
    const l = try layInk("\\sqrt{x}", &b);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
    try std.testing.expectEqual(@as(i32, 813), l.rules[0].x);
    try std.testing.expectEqual(@as(u32, 610), l.rules[0].w);
}

test "qa53 negative kern overlaps runs" {
    // Issue #63: `I\\kern-2.5pt R` (-250mu at quad=10pt) must hand
    // the negative glue to the backend as overlapping run origins —
    // the R run starts at 500-250 = 250, inside the I run. (The
    // sweep outlier itself was the upright-glyph shape gap closed by
    // the #57 remap: zatex-vs-katex rose 0.306 -> 0.870 on resweep.)
    var b: ProvBuf = .{};
    const l = try layProv("I\\kern-2.5pt R", stubProvider(), &b);
    var xi: ?i32 = null;
    var xr: ?i32 = null;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g == @as(u16, @truncate(@as(u21, 0x1D43C)))) xi = r.x;
            if (g == @as(u16, @truncate(@as(u21, 0x1D445)))) xr = r.x;
        }
    }
    try std.testing.expectEqual(@as(?i32, 0), xi);
    try std.testing.expectEqual(@as(?i32, 250), xr);
}

test "qa54 mathop sides scripts unless forced" {
    // Issue #51 (KaTeX \mathop parity, pinned 0.18.7 op.ts): a bare
    // Op wrapper is limits:false — scripts sit aside in BOTH modes,
    // so display and text boxes match; explicit \limits stacks in
    // both modes, and \limits after \mathrel is rejected ("Limit
    // controls must follow a math operator").
    var b1: B = .{};
    const d = try lay("\\mathop{x}_{y}", true, &b1);
    var b2: B = .{};
    const t = try lay("\\mathop{x}_{y}", false, &b2);
    try std.testing.expectEqual(t.width, d.width);
    try std.testing.expectEqual(t.height_above, d.height_above);
    try std.testing.expectEqual(t.depth_below, d.depth_below);
    var b3: B = .{};
    const dl = try lay("\\mathop{x}\\limits_{y}", true, &b3);
    var b4: B = .{};
    const tl = try lay("\\mathop{x}\\limits_{y}", false, &b4);
    try std.testing.expect(dl.depth_below > d.depth_below);
    try std.testing.expectEqual(dl.depth_below, tl.depth_below);
    var b5: B = .{};
    var diag = zatex.Diag.empty();
    const r = zatex.layoutDiag("\\mathrel{x}\\limits_{y}", .{}, stubProvider(), &b5.runs, &b5.rules, &b5.glyphs, &diag);
    try std.testing.expectError(error.Invalid, r);
}

test "qa55 operatorname star takes display limits" {
    // Issue #51 (KaTeX \operatorname* parity, pinned 0.18.7): the
    // star stacks scripts below in display mode only; text mode
    // keeps side scripts.
    var b1: B = .{};
    const d = try lay("\\operatorname*{asin}_{y}", true, &b1);
    var b2: B = .{};
    const t = try lay("\\operatorname*{asin}_{y}", false, &b2);
    try std.testing.expect(d.depth_below > t.depth_below);
}

test "qa56 operatornamewithlimits parses as star" {
    // Issue #51 (KaTeX \operatornamewithlimits parity): the legacy
    // alias behaves exactly like the star form.
    var b1: B = .{};
    const d = try lay("\\operatornamewithlimits{asin}_{y}", true, &b1);
    var b2: B = .{};
    const t = try lay("\\operatornamewithlimits{asin}_{y}", false, &b2);
    try std.testing.expect(d.depth_below > t.depth_below);
}

test "qa57 limits after operatorname is inert" {
    // Issue #51 (KaTeX parity, pinned 0.18.7 placement matrix):
    // explicit \limits/\nolimits after \operatorname parses but never
    // moves scripts: display stays side, identical to the bare form.
    var b1: B = .{};
    const d = try lay("\\operatorname{asin}\\limits_{y}", true, &b1);
    var b2: B = .{};
    const p = try lay("\\operatorname{asin}_{y}", true, &b2);
    try std.testing.expectEqual(p.depth_below, d.depth_below);
}

test "qa58 katex logo geometry" {
    // Issue #51 (KaTeX \KaTeX parity): K, raised scriptsize A, T,
    // lowered E, X with negative kerns (raise amounts from KaTeX
    // 0.18.7: A top-aligned via T_h - 0.7*A_h, E down 0.5ex).
    var b: B = .{};
    const l = try lay("\\KaTeX", false, &b);
    var yk: ?i32 = null;
    var ya: ?i32 = null;
    var ye: ?i32 = null;
    var sa: ?u16 = null;
    for (l.runs) |r| {
        for (r.glyphs) |g| {
            if (g == 'K') yk = r.baseline_y;
            if (g == 'A') {
                ya = r.baseline_y;
                sa = r.size_units;
            }
            if (g == 'E') ye = r.baseline_y;
        }
    }
    try std.testing.expect(yk != null and ya != null and ye != null);
    try std.testing.expect(ya.? < yk.?);
    try std.testing.expect(ye.? > yk.?);
    try std.testing.expectEqual(@as(?u16, 700), sa);
}

test "qa59 latex and tex logos parse" {
    // Issue #51 (KaTeX \LaTeX / \TeX parity): the sibling logos lay
    // out (same raised-A / lowered-E construction as \KaTeX).
    var b1: B = .{};
    _ = try lay("\\LaTeX", false, &b1);
    var b2: B = .{};
    _ = try lay("\\TeX", false, &b2);
}

test "qa60 mathstrut is a zero-width paren strut" {
    // Issue #51 (KaTeX \mathstrut parity): vertical extent of `(`
    // with no width of its own.
    var b1: B = .{};
    const s = try lay("\\mathstrut", false, &b1);
    try std.testing.expectEqual(@as(u32, 0), s.width);
    try std.testing.expect(s.height_above > 0 and s.depth_below > 0);
    var b2: B = .{};
    _ = try lay("\\sqrt{\\mathstrut a}", false, &b2);
}

test "qa62 bra ket are fixed inner fences" {
    // Issue #51 (KaTeX bra-ket parity): `\bra`/`\ket` use fixed-size
    // fences in an Inner atom (no sizing, bar is an Ord). Pinned
    // 0.18.7 proof: Inner renders a bare `mpadded` (never `mrow`) —
    // `\bra{\psi}` →
    // `<mrow><mpadded><mo stretchy="false">⟨</mo><mi>ψ</mi><mi mathvariant="normal">∣</mi></mpadded></mrow>`
    // (attributes out of scope: this golden pins tags and text).
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\bra{\\psi}", .{}, &buf);
    try expectGolden("\\bra{\\psi}", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mpadded><mo>⟨</mo><mi>ψ</mi><mi>∣</mi></mpadded></mrow></math>", got);
    var buf2: [4096]u8 = undefined;
    const got2 = try zatex.mathml("\\ket{\\psi}", .{}, &buf2);
    try expectGolden("\\ket{\\psi}", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mpadded><mi>∣</mi><mi>ψ</mi><mo>⟩</mo></mpadded></mrow></math>", got2);
}

test "qa64 display cases use displaystyle cells" {
    // Issue #51 (KaTeX dcases/drcases parity): display-cases cells
    // set limits-taking operators with stacked scripts, unlike the
    // textstyle cells of cases/rcases.
    var b1: B = .{};
    const d = try lay("\\begin{dcases}\\sum_x a\\end{dcases}", false, &b1);
    var b2: B = .{};
    const c = try lay("\\begin{cases}\\sum_x a\\end{cases}", false, &b2);
    try std.testing.expect(d.depth_below > c.depth_below);
    var b3: B = .{};
    const dr = try lay("\\begin{drcases}\\sum_x a\\end{drcases}", false, &b3);
    var b4: B = .{};
    const r = try lay("\\begin{rcases}\\sum_x a\\end{rcases}", false, &b4);
    try std.testing.expect(dr.depth_below > r.depth_below);
}

test "qa66 edef snapshots expansion" {
    // Issue #51 (KaTeX \edef parity): the body expands at definition
    // time, so later redefinition does not affect the snapshot.
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\def\\foo{a}\\edef\\fcopy{\\foo}\\def\\foo{}\\fcopy", .{}, &buf);
    try expectGolden("edef", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mi>a</mi></mrow></math>", got);
    // Parameters stay symbolic through the snapshot and bind at use.
    var buf2: [4096]u8 = undefined;
    const got2 = try zatex.mathml("\\edef\\add#1#2{#1+#2}\\add 2 3", .{}, &buf2);
    try expectGolden("edef-params", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mn>2</mn><mo>+</mo><mn>3</mn></mrow></math>", got2);
    // Nested parameterized uses resolve inside the snapshot.
    var buf3: [4096]u8 = undefined;
    const got3 = try zatex.mathml("\\def\\id#1{#1}\\edef\\a{\\id{xy}}\\a", .{}, &buf3);
    try expectGolden("edef-nested", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mi>x</mi><mi>y</mi></mrow></math>", got3);
    // Undefined names fail at define time (KaTeX parity).
    var b: B = .{};
    const r = lay("\\edef\\a{\\foo}\\a", false, &b);
    try std.testing.expectError(error.Invalid, r);
}

test "qa67 xdef defines globally expanded" {
    // Issue #51 (KaTeX \xdef parity): global edef snapshots like
    // \edef (all engine definitions are already global).
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\def\\foo{a}\\xdef\\fcopy{\\foo}\\def\\foo{}\\fcopy", .{}, &buf);
    try expectGolden("xdef", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mi>a</mi></mrow></math>", got);
}

test "qa69 textregistered is text registered" {
    // Issue #51 (KaTeX parity): `\textregistered` works inside
    // `\text` (single ® glyph, exactly KaTeX's MathML spelling).
    var b: B = .{};
    _ = try lay("\\text{\\textregistered}", false, &b);
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\text{\\textregistered}", .{}, &buf);
    try expectGolden("textregistered", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mtext>®</mtext></mrow></math>", got);
}

test "qa70 textcircled encloses the body on the baseline (issue #80)" {
    // KaTeX parity (pinned 0.18.7 browser pixels): `\textcircled`
    // lays out as an enclosure, not a floating accent — the U+25EF
    // baseline coincides with the body baseline, so the body sits
    // inside the ring (a: pads 21px/17px of a 72px ring; a tall
    // body overflows the ring top while the ring stays put). The
    // ring sits at the span left with no centering, and the span
    // widens to the ring when narrower. Stub metrics (advance 500,
    // extents 700/250): ring and letter share one baseline, the
    // construction is 700 tall and 250 deep, and letter and ring
    // runs both start at x = 0.
    var b1: B = .{};
    const circ = try lay("\\text{\\textcircled a}", false, &b1);
    var b2: B = .{};
    const bare = try lay("\\text{a}", false, &b2);
    try std.testing.expectEqual(@as(u32, 700), circ.height_above);
    try std.testing.expectEqual(bare.height_above, circ.height_above);
    try std.testing.expectEqual(bare.depth_below, circ.depth_below);
    try std.testing.expectEqual(@as(usize, 2), circ.runs.len);
    try std.testing.expectEqual(@as(u16, 'a'), circ.runs[0].glyphs[0]);
    try std.testing.expectEqual(@as(u16, 0x25EF), circ.runs[1].glyphs[0]);
    try std.testing.expectEqual(@as(i32, 0), circ.runs[0].x);
    try std.testing.expectEqual(@as(i32, 0), circ.runs[1].x);
    try std.testing.expectEqual(circ.runs[0].baseline_y, circ.runs[1].baseline_y);
    // A wider-than-ring span stays left-aligned (the overlay
    // centered it): the letter run and the ring run both start
    // at x = 0.
    var bw: B = .{};
    const wide = try lay("\\text{\\textcircled{ab}}", false, &bw);
    try std.testing.expectEqual(@as(u32, 1000), wide.width);
    try std.testing.expectEqual(@as(usize, 2), wide.runs.len);
    try std.testing.expectEqual(@as(i32, 0), wide.runs[0].x);
    try std.testing.expectEqual(@as(i32, 0), wide.runs[1].x);
    try std.testing.expectEqual(@as(u16, 0x25EF), wide.runs[1].glyphs[0]);
    // Issue #70: TeX control-word space skipping — the unbraced form
    // `\textcircled a` typesets no phantom space inside the span, so
    // it lays out exactly like the braced form.
    var b3: B = .{};
    const braced = try lay("\\text{\\textcircled{a}}", false, &b3);
    try std.testing.expectEqual(braced.width, circ.width);
    try std.testing.expectEqual(braced.runs.len, circ.runs.len);
    for (braced.runs, circ.runs) |r1, r2| {
        try std.testing.expectEqual(r1.x, r2.x);
        try std.testing.expectEqualSlices(u16, r1.glyphs, r2.glyphs);
    }
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\text{\\textcircled a}", .{}, &buf);
    try expectGolden("textcircled", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mrow><mover accent=\"true\"><mrow><mtext>a</mtext></mrow><mo>◯</mo></mover></mrow></mrow></math>", got);
}

test "qa114 islands take space-separated args like math" {
    // KaTeX parity: island bodies re-enter MATH, where whitespace
    // never reaches argument scanning (`\\text{\\(\\frac a b\\)}`
    // accepts in pinned 0.18.7). The stashed text tokens keep
    // `char(' ')`, so argument position must skip them — unbraced
    // `\\frac a b` then lays out exactly like `\\frac{a}{b}` in
    // both island spellings.
    var b1: B = .{};
    const spaced = try lay("\\text{\\(\\frac a b\\)}", false, &b1);
    var b2: B = .{};
    const braced = try lay("\\text{\\(\\frac{a}{b}\\)}", false, &b2);
    try std.testing.expectEqual(@as(usize, 1), spaced.rules.len);
    try std.testing.expectEqual(braced.width, spaced.width);
    try std.testing.expectEqual(braced.height_above, spaced.height_above);
    var b3: B = .{};
    const dsp = try lay("\\text{$\\frac a b$}", false, &b3);
    try std.testing.expectEqual(@as(usize, 1), dsp.rules.len);
    try std.testing.expectEqual(braced.width, dsp.width);
}

test "qa113 textcircled ring sits on the body baseline" {
    // KaTeX-pixel proof (pinned 0.18.7 browser render): the U+25EF
    // ring baseline coincides with the body baseline — the body
    // sits INSIDE the ring (a: pads 21px/17px of a 72px ring match
    // dy=0 exactly), and a tall body (b) overflows the ring top
    // while the ring stays put. Stub metrics (advance 500,
    // extents 700/250): ring and letter share one baseline, the
    // construction is 700 tall and 250 deep.
    var b1: B = .{};
    const circ = try lay("\\text{\\textcircled a}", false, &b1);
    try std.testing.expectEqual(@as(usize, 2), circ.runs.len);
    try std.testing.expectEqual(circ.runs[0].baseline_y, circ.runs[1].baseline_y);
    try std.testing.expectEqual(@as(u32, 700), circ.height_above);
    try std.testing.expectEqual(@as(u32, 250), circ.depth_below);
    var b2: B = .{};
    const m = try lay("\\textcircled{a}", false, &b2);
    try std.testing.expectEqual(@as(usize, 2), m.runs.len);
    try std.testing.expectEqual(m.runs[0].baseline_y, m.runs[1].baseline_y);
    try std.testing.expectEqual(@as(u32, 700), m.height_above);
}

test "qa71 sout strikes text" {
    // Issue #51 (KaTeX parity): `\sout` in text draws one rule
    // across the whole argument.
    var b: B = .{};
    const l = try lay("\\text{\\sout{abc}}", false, &b);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
    try std.testing.expectEqual(@as(u32, 1500), l.rules[0].w);
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\text{\\sout{abc}}", .{}, &buf);
    try expectGolden("sout-text", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mrow><menclose notation=\"horizontalstrike\"><mrow><mtext>abc</mtext></mrow></menclose></mrow></mrow></math>", got);
}

test "qa73 overbracket draws a square bracket" {
    // Issue #51 (KaTeX parity): rule-drawn top bracket with legs,
    // 1.6em minimum span, sup label above like overbrace.
    var b1: B = .{};
    _ = try lay("\\overbracket{x+1}^{n}", false, &b1);
    var b2: B = .{};
    const bare = try lay("x+1", false, &b2);
    var b3: B = .{};
    const br = try lay("\\overbracket{x+1}", false, &b3);
    // Absolute KaTeX geometry (pinned stretchy.ts: legs 290 + bar
    // 120 + 30 transparent crown + 100 kern, rule-drawn so stub
    // and host fonts agree exactly).
    try std.testing.expectEqual(bare.height_above + 540, br.height_above);
    try std.testing.expectEqual(bare.depth_below, br.depth_below);
    var b4: B = .{};
    const narrow = try lay("\\overbracket{i}", false, &b4);
    try std.testing.expectEqual(@as(u32, 1600), narrow.width);
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\overbracket{x+1}", .{}, &buf);
    try expectGolden("overbracket", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow><mo>&#x23B4;</mo></mover></mrow></math>", got);
}

test "qa79 math-mode textcircled is a mover" {
    // Issue #80 (KaTeX parity): math-mode \textcircled is accepted
    // (strict warning in KaTeX, not a reject) and builds a mover
    // with the circle operator; natively it is the same enclosing
    // ring as text mode — stub-exact: 700 tall, ring run on the
    // letter baseline at x = 0.
    var b1: B = .{};
    const c = try lay("\\textcircled{a}", false, &b1);
    try std.testing.expectEqual(@as(u32, 700), c.height_above);
    try std.testing.expectEqual(@as(u32, 500), c.width);
    try std.testing.expectEqual(@as(usize, 2), c.runs.len);
    try std.testing.expectEqual(@as(u16, 0x25EF), c.runs[1].glyphs[0]);
    try std.testing.expectEqual(@as(i32, 0), c.runs[1].x);
    try std.testing.expectEqual(c.runs[0].baseline_y, c.runs[1].baseline_y);
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\textcircled{a}", .{}, &buf);
    try expectGolden("circled-math", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover accent=\"true\"><mi>a</mi><mo>◯</mo></mover></mrow></math>", got);
}

test "qa78 cr is a full row-separator alias" {
    // Issue #51 (KaTeX parity): \cr separates env rows exactly like
    // \\ — trailing, leading, and consecutive separators all match.
    var b1: B = .{};
    const c = try lay("\\begin{matrix}a\\cr b\\end{matrix}", false, &b1);
    var b2: B = .{};
    const s = try lay("\\begin{matrix}a\\\\b\\end{matrix}", false, &b2);
    try std.testing.expectEqual(s.width, c.width);
    try std.testing.expectEqual(s.height_above, c.height_above);
    try std.testing.expectEqual(s.depth_below, c.depth_below);
    var b3: B = .{};
    const ct = try lay("\\begin{matrix}a\\cr\\end{matrix}", false, &b3);
    var b4: B = .{};
    const st = try lay("\\begin{matrix}a\\\\\\end{matrix}", false, &b4);
    try std.testing.expectEqual(st.height_above, ct.height_above);
    try std.testing.expectEqual(st.depth_below, ct.depth_below);
    var b5: B = .{};
    const cc = try lay("\\begin{matrix}a\\cr\\cr b\\end{matrix}", false, &b5);
    var b6: B = .{};
    const sc = try lay("\\begin{matrix}a\\\\\\\\b\\end{matrix}", false, &b6);
    try std.testing.expectEqual(sc.height_above, cc.height_above);
    try std.testing.expectEqual(sc.depth_below, cc.depth_below);
    // Stray \cr outside an env is rejected (KaTeX: undefined
    // sequence) with the use-site offset.
    var b7: B = .{};
    var diag = zatex.Diag.empty();
    const r = zatex.layoutDiag("a\\cr b", .{}, stubProvider(), &b7.runs, &b7.rules, &b7.glyphs, &diag);
    try std.testing.expectError(error.Invalid, r);
    try std.testing.expectEqualStrings("unexpected '\\cr'", diag.message);
    try std.testing.expectEqual(@as(u32, 1), diag.offset);
    // Same alias inside \substack rows.
    var b8: B = .{};
    const cb = try lay("\\sum_{\\substack{a\\cr b}}", false, &b8);
    var b9: B = .{};
    const sb = try lay("\\sum_{\\substack{a\\\\b}}", false, &b9);
    try std.testing.expectEqual(sb.height_above, cb.height_above);
    try std.testing.expectEqual(sb.depth_below, cb.depth_below);
}

test "qa77 phase pads for the phasor angle" {
    // Issue #51 (KaTeX parity): angleHeight pad on the left, depth
    // grows by lineWeight + clearance, menclose phasorangle.
    var b1: B = .{};
    const v = try lay("\\phase{30}", false, &b1);
    var b2: B = .{};
    const bare = try lay("30", false, &b2);
    // lineWeight 60 + clearance 0.35ex (x-height 431): depth grows.
    try std.testing.expectEqual(bare.depth_below + 60 + 150, v.depth_below);
    // Padding is angleHeight/2 + lineWeight off the content width.
    const H = bare.height_above + bare.depth_below + 60 + 150;
    try std.testing.expectEqual(bare.width + H / 2 + 60, v.width);
    // The mark also underlines the span: one full-width bottom bar
    // (KaTeX phasePath fills the bottom edge, 80mu tall).
    try std.testing.expectEqual(@as(usize, 1), v.rules.len);
    try std.testing.expectEqual(v.width, v.rules[0].w);
    try std.testing.expectEqual(@as(u32, 80), v.rules[0].h);
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\phase{30}", .{}, &buf);
    try expectGolden("phase", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><menclose notation=\"phasorangle\"><mrow><mn>30</mn></mrow></menclose></mrow></math>", got);
}

test "qa76 vcenter centers on the math axis" {
    // Issue #51 (KaTeX parity): the content is shifted so the math
    // axis halves it — height minus depth is exactly twice the axis
    // (250mu), total preserved, mpadded in MathML.
    var b1: B = .{};
    const v = try lay("\\vcenter{x}", false, &b1);
    try std.testing.expectEqual(v.height_above - v.depth_below, @as(u32, 500));
    var b2: B = .{};
    const bare = try lay("x", false, &b2);
    try std.testing.expectEqual(bare.height_above + bare.depth_below, v.height_above + v.depth_below);
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\vcenter{x}", .{}, &buf);
    try expectGolden("vcenter", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mpadded class=\"vcenter\"><mi>x</mi></mpadded></mrow></math>", got);
}

test "qa75 pmb keeps metrics, marks bold" {
    // Issue #51 (KaTeX parity): \pmb is a text-shadow style, not a
    // font switch — same box as the bare content, mstyle wrapper.
    var b1: B = .{};
    const p = try lay("\\pmb{x+1}", false, &b1);
    var b2: B = .{};
    const bare = try lay("x+1", false, &b2);
    try std.testing.expectEqual(bare.width, p.width);
    try std.testing.expectEqual(bare.height_above, p.height_above);
    try std.testing.expectEqual(bare.depth_below, p.depth_below);
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\pmb{x}", .{}, &buf);
    try expectGolden("pmb", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle style=\"text-shadow: 0.02em 0.01em 0.04px\"><mi>x</mi></mstyle></mrow></math>", got);
}

test "qa74 underbracket mirrors below" {
    // Issue #51 (KaTeX parity): bottom bracket with sub label below.
    var b1: B = .{};
    _ = try lay("\\underbracket{x}_{y}", false, &b1);
    var b2: B = .{};
    const bare = try lay("x", false, &b2);
    var b3: B = .{};
    const br = try lay("\\underbracket{x}", false, &b3);
    // Absolute KaTeX geometry (pinned stretchy.ts: legs 290 + bar
    // 120 + 100 kern, no crown below).
    try std.testing.expectEqual(bare.depth_below + 510, br.depth_below);
    try std.testing.expectEqual(bare.height_above, br.height_above);
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\underbracket{x}", .{}, &buf);
    try expectGolden("underbracket", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><munder><mi>x</mi><mo>&#x23B5;</mo></munder></mrow></math>", got);
}

test "qa73 subarray takes c-l alignment" {
    // Issue #73 (pinned KaTeX 0.18.7 is truth: `{c}`/`{l}` align the
    // single column, `{r}` and mixed groups reject, `&` rejects with
    // "only one column"): script cells like smallmatrix, one spec
    // code, column-count clamp in layoutEnv. Cells lay out at script
    // size (stub advance scales 500 -> 350), so the `a` row sits at
    // the column origin when left and centered in the `bb` row
    // otherwise: 194 vs 194 + (700 - 350) / 2 = 369.
    var b1: B = .{};
    const l = try lay("\\begin{subarray}{l}a\\\\bb\\end{subarray}", false, &b1);
    try std.testing.expectEqual(@as(i32, 194), l.runs[0].x);
    var b2: B = .{};
    const c = try lay("\\begin{subarray}{c}a\\\\bb\\end{subarray}", false, &b2);
    try std.testing.expectEqual(@as(i32, 369), c.runs[0].x);
    try std.testing.expectEqual(l.width, c.width);
    var b3: B = .{};
    var diag = zatex.Diag.empty();
    try std.testing.expectError(error.Invalid, zatex.layoutDiag("\\begin{subarray}{r}a\\end{subarray}", .{}, stubProvider(), &b3.runs, &b3.rules, &b3.glyphs, &diag));
    var b4: B = .{};
    var diag2 = zatex.Diag.empty();
    try std.testing.expectError(error.Invalid, zatex.layoutDiag("\\begin{subarray}{c}a&b\\end{subarray}", .{}, stubProvider(), &b4.runs, &b4.rules, &b4.glyphs, &diag2));
}

test "qa73 tag tables the equation with parens" {
    // Issue #73 (pinned KaTeX 0.18.7 `tag` MathML): the display-only
    // equation number rides in a full-width table; `\tag`
    // parenthesizes, `\tag*` does not. The `mrow` shell around `(1)`
    // is grouping-transparent (the parity normalizer drops
    // single-child rows). Layout puts real paren ink after a
    // `\qquad` gap: stub advance is a flat 500, so `(` sits at
    // 500 (formula) + 2000 (gap) = 2500 and the row is 4000 wide.
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\tag{1}x", .{ .display_mode = true }, &buf);
    try expectGolden("tag-display", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><mtable width=\"100%\"><mtr><mtd width=\"50%\"></mtd><mtd><mi>x</mi></mtd><mtd width=\"50%\"></mtd><mtd><mrow><mtext>(1)</mtext></mrow></mtd></mtr></mtable></math>", got);
    var buf2: [4096]u8 = undefined;
    const got2 = try zatex.mathml("\\tag*{a}x", .{ .display_mode = true }, &buf2);
    try expectGolden("tag-star-display", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><mtable width=\"100%\"><mtr><mtd width=\"50%\"></mtd><mtd><mi>x</mi></mtd><mtd width=\"50%\"></mtd><mtd><mtext>a</mtext></mtd></mtr></mtable></math>", got2);
    var b1: B = .{};
    const l1 = try lay("\\tag{1}x", true, &b1);
    try std.testing.expectEqual(@as(i32, 2500), try glyphX(l1, '('));
    try std.testing.expectEqual(@as(u32, 4000), l1.width);
    var b2: B = .{};
    const l2 = try lay("\\tag*{a}x", true, &b2);
    var found_paren = false;
    for (l2.runs) |r| {
        for (r.glyphs) |g| {
            if (g == '(' or g == ')') found_paren = true;
        }
    }
    try std.testing.expect(!found_paren);
}

test "qa72 sout strikes math" {
    // Issue #51 (KaTeX parity): math-mode `\sout` is a horizontal
    // strike (menclose horizontalstrike, like `\cancel` diagonal).
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\sout{abc}", .{}, &buf);
    try expectGolden("sout-math", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><menclose notation=\"horizontalstrike\"><mrow><mi>a</mi><mi>b</mi><mi>c</mi></mrow></menclose></mrow></math>", got);
}

test "qa68 global prefix takes definitions" {
    // Issue #51 (KaTeX \global parity): the prefix applies to the
    // next definition (`\def` here) and rejects anything else.
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\global\\def\\add#1#2{#1+#2} \\add 2 3", .{}, &buf);
    try expectGolden("global", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mn>2</mn><mo>+</mo><mn>3</mn></mrow></math>", got);
    var b: B = .{};
    const r = lay("\\global x", false, &b);
    try std.testing.expectError(error.Invalid, r);
}

test "qa65 right cases fence on the right" {
    // Issue #51 (KaTeX rcases/drcases parity): the brace closes on
    // the right with no opening fence.
    var buf: [8192]u8 = undefined;
    const got = try zatex.mathml("\\begin{rcases}a\\end{rcases}", .{}, &buf);
    try std.testing.expect(std.mem.indexOf(u8, got, "<mo fence=\"true\">}</mo>") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "{") == null);
    var buf2: [8192]u8 = undefined;
    _ = try zatex.mathml("\\begin{drcases}a\\end{drcases}", .{}, &buf2);
}

test "qa63 sized bra ket are fences" {
    // Issue #51 (KaTeX `\Bra`/`\Ket` parity): capital forms size
    // like `\left\langle … \right\vert` (verified identical KaTeX
    // output), so they serialize as fence delimiters.
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\Bra{\\psi}", .{}, &buf);
    try expectGolden("\\Bra{\\psi}", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo fence=\"true\">⟨</mo><mi>ψ</mi><mo fence=\"true\">∣</mo></mrow></math>", got);
    var buf2: [4096]u8 = undefined;
    const got2 = try zatex.mathml("\\Ket{\\psi}", .{}, &buf2);
    try expectGolden("\\Ket{\\psi}", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo fence=\"true\">∣</mo><mi>ψ</mi><mo fence=\"true\">⟩</mo></mrow></math>", got2);
}

test "qa61 lbrace works after left" {
    // Issue #51 (KaTeX delimiter parity): `\{`-class braces are
    // valid `\left`/`\right` delimiters.
    var b1: B = .{};
    _ = try lay("\\left\\lbrace x \\right.", false, &b1);
    var b2: B = .{};
    const bare = try lay("x", false, &b2);
    var b3: B = .{};
    const fenced = try lay("\\left\\lbrace x \\right.", false, &b3);
    try std.testing.expect(fenced.width >= bare.width);
}


test "qa80 lap family overlaps with zero width" {
    // Issue #71 (pinned KaTeX 0.18.7 is truth: `\llap` is
    // `mpadded lspace="-1width" width="0px"`, `\mathclap` is
    // `lspace="-0.5width"`): the core was already KaTeX-exact here —
    // the visible `lap.png`/`mathclap.png` divergence was the raster
    // backend clipping left-overflow ink (fixed in render.zig, which
    // shifts the canvas so the leftmost ink lands on pad). Pin the
    // geometry: stub advance is 500, so representatives are exact.
    var b1: B = .{};
    const ll = try lay("\\llap{x}y", false, &b1);
    try std.testing.expectEqual(@as(u32, 500), ll.width);
    try std.testing.expectEqual(@as(usize, 2), ll.runs.len);
    try std.testing.expectEqual(@as(i32, -500), ll.runs[0].x);
    try std.testing.expectEqual(@as(i32, 0), ll.runs[1].x);
    // Run order follows box order: the lapped text-mode `x` first.
    try std.testing.expectEqual(@as(usize, 1), ll.runs[0].glyphs.len);
    try std.testing.expectEqual(@as(u16, 'x'), ll.runs[0].glyphs[0]);
    var b2: B = .{};
    const rl = try lay("\\rlap{ab}y", false, &b2);
    try std.testing.expectEqual(@as(u32, 500), rl.width);
    try std.testing.expectEqual(@as(i32, 0), rl.runs[0].x);
    try std.testing.expectEqual(@as(i32, 0), rl.runs[1].x);
    var b3: B = .{};
    const mc = try lay("\\mathclap{ab}", false, &b3);
    try std.testing.expectEqual(@as(u32, 0), mc.width);
    try std.testing.expectEqual(@as(usize, 1), mc.runs.len);
    // Centered: content [-1000, 0], middle at the zero-width origin.
    try std.testing.expectEqual(@as(i32, -500), mc.runs[0].x);
}

test "qa81 dotless i/j shear for faux math-italic (issue #77)" {
    // Pinned KaTeX 0.18.7 renders `\\jmath`/`\\imath` in the
    // math-italic face; host fonts carry upright dotless glyphs, so
    // the core stamps a 1:4 faux-italic shear (the Computer Modern
    // math-italic slant) on the run and backends slant the ink about
    // the baseline. Plain letters and explicit faces stay upright,
    // and shear boundaries split runs like color and scale.
    var b1: B = .{};
    const jm = try lay("\\jmath", false, &b1);
    try std.testing.expectEqual(@as(usize, 1), jm.runs.len);
    try std.testing.expectEqual(@as(u16, 0x237), jm.runs[0].glyphs[0]);
    try std.testing.expectEqual(@as(i16, 250), jm.runs[0].x_shear);
    var b2: B = .{};
    const im = try lay("\\imath", false, &b2);
    try std.testing.expectEqual(@as(i16, 250), im.runs[0].x_shear);
    var b3: B = .{};
    const j = try lay("j", false, &b3);
    try std.testing.expectEqual(@as(i16, 0), j.runs[0].x_shear);
    var b4: B = .{};
    const bf = try lay("\\mathbf{\\jmath}", false, &b4);
    try std.testing.expectEqual(@as(i16, 0), bf.runs[0].x_shear);
    var b5: B = .{};
    const mix = try lay("j\\jmath", false, &b5);
    try std.testing.expectEqual(@as(usize, 2), mix.runs.len);
    try std.testing.expectEqual(@as(i16, 0), mix.runs[0].x_shear);
    try std.testing.expectEqual(@as(i16, 250), mix.runs[1].x_shear);
}

test "qa82 infix brace/brack are their own fences (issue #93)" {
    // KaTeX parity (pinned 0.18.7): `{n\\brace k}` wraps in curly
    // braces and `{n\\brack k}` in square brackets — the old
    // `parens` bool drew parens for all three. Stub-exact: four
    // runs (fence, num, den, fence); MathML matches KaTeX's fence
    // mo's glyph-for-glyph.
    var b1: B = .{};
    const br = try lay("{n\\brace k}", false, &b1);
    try std.testing.expectEqual(@as(usize, 4), br.runs.len);
    try std.testing.expectEqual(@as(u16, '{'), br.runs[0].glyphs[0]);
    try std.testing.expectEqual(@as(u16, '}'), br.runs[3].glyphs[0]);
    var b2: B = .{};
    const bk = try lay("{n\\brack k}", false, &b2);
    try std.testing.expectEqual(@as(usize, 4), bk.runs.len);
    try std.testing.expectEqual(@as(u16, '['), bk.runs[0].glyphs[0]);
    try std.testing.expectEqual(@as(u16, ']'), bk.runs[3].glyphs[0]);
    var buf: [4096]u8 = undefined;
    const gotb = try zatex.mathml("{n\\brace k}", .{}, &buf);
    try expectGolden("infix-brace", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo fence=\"true\">{</mo><mfrac linethickness=\"0\"><mi>n</mi><mi>k</mi></mfrac><mo fence=\"true\">}</mo></mrow></math>", gotb);
    var buf2: [4096]u8 = undefined;
    const gotk = try zatex.mathml("{n\\brack k}", .{}, &buf2);
    try expectGolden("infix-brack", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo fence=\"true\">[</mo><mfrac linethickness=\"0\"><mi>n</mi><mi>k</mi></mfrac><mo fence=\"true\">]</mo></mrow></math>", gotk);
}

test "qa83 old-style font declarations scope the rest of the group (issue #94)" {
    // KaTeX parity (pinned 0.18.7): `\bf` et al take NO argument —
    // they scope over the rest of the enclosing group (braces around
    // the next atom do NOT scope them: `\sf{A}B` is all sans). The
    // declaration stops at an infix (`\bf a\over b` bolds the
    // numerator only) and at the group end (`{\bf Aa}Bb` leaves Bb
    // bare). `\boldsymbol` is `\bm` (bold-italic, never bold).
    var b1: B = .{};
    const l = try lay("\\bf AaBb12", false, &b1);
    // Every run requests the bold host font; the SMP remap is visible
    // through the truncating stub (bold A -> U+1D400 -> 0xD400).
    try std.testing.expect(l.runs.len >= 1);
    var nglyphs: usize = 0;
    for (l.runs) |r| {
        try std.testing.expectEqual(@as(u16, 2), r.font_id);
        nglyphs += r.glyphs.len;
    }
    try std.testing.expectEqual(@as(usize, 6), nglyphs);
    try std.testing.expectEqual(@as(u16, 0xD400), l.runs[0].glyphs[0]);
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\bf AaBb12", .{}, &buf);
    try expectGolden("decl-bf", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathvariant=\"bold\"><mi>A</mi><mi>a</mi><mi>B</mi><mi>b</mi><mn>12</mn></mstyle></mrow></math>", got);
    var buf2: [4096]u8 = undefined;
    const gotg = try zatex.mathml("{\\bf Aa}Bb", .{}, &buf2);
    try expectGolden("decl-group", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathvariant=\"bold\"><mrow><mi>A</mi><mi>a</mi></mrow></mstyle><mi>B</mi><mi>b</mi></mrow></math>", gotg);
    var buf3: [4096]u8 = undefined;
    const goto = try zatex.mathml("\\bf a\\over b", .{}, &buf3);
    try expectGolden("decl-over", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mfrac><mstyle mathvariant=\"bold\"><mi>a</mi></mstyle><mi>b</mi></mfrac></mrow></math>", goto);
    var buf4: [4096]u8 = undefined;
    const gotb = try zatex.mathml("\\boldsymbol{AaBb}", .{}, &buf4);
    try expectGolden("decl-boldsymbol", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathvariant=\"bold-italic\"><mi>A</mi><mi>a</mi><mi>B</mi><mi>b</mi></mstyle></mrow></math>", gotb);
}

test "qa84 genfrac zero bar omits the rule (issue #105)" {
    // KaTeX parity (pinned 0.18.7): an explicit non-positive bar
    // (`{0pt}`, `{-1pt}`, `\above0pt`) means NO rule — barless like
    // `\binom` (atop spacing, `linethickness="0"`); an EMPTY bar
    // keeps the default rule. Vertical construction matches
    // `\binom` exactly (pinned KaTeX: both 0.7454em tall).
    // `\dfrac` already matches KaTeX (rule 40 units = 0.04em in both
    // styles — pinned here, not changed).
    var b1: B = .{};
    const g = try lay("\\genfrac(){0pt}{1}{a}{b}", false, &b1);
    try std.testing.expectEqual(@as(usize, 0), g.rules.len);
    // Same construction as `\binom` (Rule 15e fixed fences, issue
    // #112) lays out bit-identically: the T style wrapper is
    // geometry-transparent in ambient text style. `\left` grows
    // instead and now differs (taller box).
    var b2: B = .{};
    const bi = try lay("\\binom{a}{b}", false, &b2);
    try std.testing.expectEqual(bi.width, g.width);
    try std.testing.expectEqual(bi.height_above, g.height_above);
    try std.testing.expectEqual(bi.depth_below, g.depth_below);
    var b3: B = .{};
    const ab = try lay("a\\above0pt b", false, &b3);
    try std.testing.expectEqual(@as(usize, 0), ab.rules.len);
    var b4: B = .{};
    const df = try lay("\\dfrac{a}{b}", false, &b4);
    var b5: B = .{};
    const fr = try lay("\\frac{a}{b}", false, &b5);
    try std.testing.expectEqual(@as(usize, 1), df.rules.len);
    try std.testing.expectEqual(fr.rules[0].h, df.rules[0].h);
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\genfrac(){0pt}{1}{a}{b}", .{}, &buf);
    try expectGolden("genfrac-0pt", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle displaystyle=\"false\"><mrow><mo fence=\"true\">(</mo><mfrac linethickness=\"0\"><mi>a</mi><mi>b</mi></mfrac><mo fence=\"true\">)</mo></mrow></mstyle></mrow></math>", got);
}

test "qa85 reflectbox mirrors ink about the box center (issue #97)" {
    // KaTeX parity (pinned 0.18.7): `\reflectbox` / `\mathreflectbox`
    // flip the ink (CSS scaleX(-1)) while the layout box stays
    // bit-identical to the unmirrored twin. Runs carry mirrored=true
    // with pre-mapped origins; rules arrive as plain pre-mirrored
    // rects; MathML is the plain content (KaTeX marks no flip).
    var b1: B = .{};
    const m = try lay("\\mathreflectbox{R}", false, &b1);
    var b2: B = .{};
    const u = try lay("R", false, &b2);
    try std.testing.expectEqual(u.width, m.width);
    try std.testing.expectEqual(u.height_above, m.height_above);
    try std.testing.expectEqual(u.depth_below, m.depth_below);
    try std.testing.expectEqual(@as(usize, 1), u.runs.len);
    try std.testing.expectEqual(@as(usize, 1), m.runs.len);
    try std.testing.expect(!u.runs[0].mirrored);
    try std.testing.expect(m.runs[0].mirrored);
    try std.testing.expectEqualSlices(u16, u.runs[0].glyphs, m.runs[0].glyphs);
    // Origins mirror about the box center: x' = 2*axis - x.
    const axis: i32 = @divTrunc(@as(i32, @intCast(m.width)), 2);
    try std.testing.expectEqual(2 * axis - u.runs[0].x, m.runs[0].x);
    // A double mirror is the identity: nested CSS flips compose to a
    // translation, and here both axes coincide, so nothing moves.
    var b3: B = .{};
    const d = try lay("\\mathreflectbox{\\mathreflectbox{R}}", false, &b3);
    try std.testing.expectEqual(@as(usize, 1), d.runs.len);
    try std.testing.expect(!d.runs[0].mirrored);
    try std.testing.expectEqual(u.runs[0].x, d.runs[0].x);
    // Rules mirror as plain rects: [x, x+w] -> [2A-x-w, 2A-x].
    var b4: B = .{};
    const mf = try lay("\\mathreflectbox{\\frac{a}{b}}", false, &b4);
    var b5: B = .{};
    const uf = try lay("\\frac{a}{b}", false, &b5);
    try std.testing.expectEqual(@as(usize, 1), uf.rules.len);
    try std.testing.expectEqual(@as(usize, 1), mf.rules.len);
    const faxis: i32 = @divTrunc(@as(i32, @intCast(mf.width)), 2);
    const ur = uf.rules[0];
    const mr = mf.rules[0];
    try std.testing.expectEqual(ur.w, mr.w);
    try std.testing.expectEqual(ur.h, mr.h);
    try std.testing.expectEqual(2 * faxis - ur.x - @as(i32, @intCast(ur.w)), mr.x);
    try std.testing.expectEqual(ur.y, mr.y);
    // MathML goldens: plain content, KaTeX-shaped (probed 0.18.7 —
    // the flip is CSS-only, so neither side marks it).
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\mathreflectbox{x^2}", .{}, &buf);
    try expectGolden("mathreflectbox", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msup><mi>x</mi><mn>2</mn></msup></mrow></math>", got);
    var buf2: [4096]u8 = undefined;
    const got2 = try zatex.mathml("\\reflectbox{R}", .{}, &buf2);
    try expectGolden("reflectbox", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle displaystyle=\"false\"><mtext>R</mtext></mstyle></mrow></math>", got2);
    // `$...$` math islands parse inside `\reflectbox` (the `\hbox`
    // path): KaTeX wraps the island in a second textstyle reset.
    var buf3: [4096]u8 = undefined;
    const got3 = try zatex.mathml("\\reflectbox{$x^2$}", .{}, &buf3);
    try expectGolden("reflectbox-math", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle displaystyle=\"false\"><mstyle displaystyle=\"false\"><msup><mi>x</mi><mn>2</mn></msup></mstyle></mstyle></mrow></math>", got3);
    // The box body lays out like `\hbox` (same textbody path): same
    // box, same glyph multiset, origins mirrored about the center.
    var b6: B = .{};
    const rb = try lay("\\reflectbox{$x^2$}", false, &b6);
    var b7: B = .{};
    const hb = try lay("\\hbox{$x^2$}", false, &b7);
    try std.testing.expectEqual(hb.width, rb.width);
    try std.testing.expectEqual(hb.height_above, rb.height_above);
    try std.testing.expectEqual(hb.depth_below, rb.depth_below);
    try std.testing.expectEqual(hb.rules.len, rb.rules.len);
    var hn: usize = 0;
    for (hb.runs) |r| hn += r.glyphs.len;
    var rn: usize = 0;
    for (rb.runs) |r| {
        rn += r.glyphs.len;
        try std.testing.expect(r.mirrored);
    }
    try std.testing.expectEqual(hn, rn);
    const raxis: i32 = @divTrunc(@as(i32, @intCast(rb.width)), 2);
    for (rb.runs) |r| {
        for (r.glyphs) |g| {
            const hx = try glyphX(hb, g);
            try std.testing.expectEqual(2 * raxis - hx, r.x);
        }
    }
}

test "qa86 operatorname forced limits stack in every style (issue #98)" {
    // KaTeX parity (pinned 0.18.7 placement matrix): a star-armed
    // `\operatorname` (`*`, `withlimits`) with explicit `\limits`
    // stacks in every style — even text style with both scripts,
    // where forced symbols stay side-set. Explicit `\limits` after
    // a PLAIN name stays inert.
    var buf: [4096]u8 = undefined;
    const got = try zatex.mathml("\\operatorname*{lim}\\limits_{x}", .{}, &buf);
    try expectGolden("operatorname-star-limits", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><munder><mrow><mi>lim</mi><mo>\u{2061}</mo></mrow><mi>x</mi></munder></mrow></math>", got);
    var buf2: [4096]u8 = undefined;
    const got2 = try zatex.mathml("\\operatorname*{lim}\\limits_{x}^{n}", .{}, &buf2);
    try expectGolden("operatorname-star-limits-both", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><munderover><mrow><mi>lim</mi><mo>\u{2061}</mo></mrow><mi>x</mi><mi>n</mi></munderover></mrow></math>", got2);
    var buf3: [4096]u8 = undefined;
    const got3 = try zatex.mathml("\\operatorname*{lim}\\limits^{x}", .{}, &buf3);
    try expectGolden("operatorname-star-limits-sup", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover><mrow><mi>lim</mi><mo>\u{2061}</mo></mrow><mi>x</mi></mover></mrow></math>", got3);
    // Guards: unforced star stays side-set inline, stacks in display;
    // plain names ignore explicit limits; forced symbols stay
    // side-set for both scripts inline.
    var buf4: [4096]u8 = undefined;
    const got4 = try zatex.mathml("\\operatorname*{lim}_{x}", .{}, &buf4);
    try expectGolden("operatorname-star-text", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msub><mrow><mi>lim</mi><mo>\u{2061}</mo></mrow><mi>x</mi></msub></mrow></math>", got4);
    var buf5: [4096]u8 = undefined;
    const got5 = try zatex.mathml("\\operatorname{lim}\\limits_{x}", .{}, &buf5);
    try expectGolden("operatorname-plain-limits", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msub><mrow><mi>lim</mi><mo>\u{2061}</mo></mrow><mi>x</mi></msub></mrow></math>", got5);
    var buf6: [4096]u8 = undefined;
    const got6 = try zatex.mathml("\\sum\\limits_{i}^{n}", .{}, &buf6);
    try expectGolden("sum-limits-both-text", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msubsup><mo>\u{2211}</mo><mi>i</mi><mi>n</mi></msubsup></mrow></math>", got6);
    var buf7: [4096]u8 = undefined;
    const got7 = try zatex.mathml("\\operatornamewithlimits{lim}\\limits_{x}", .{}, &buf7);
    try expectGolden("operatorname-withlimits-limits", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><munder><mrow><mi>lim</mi><mo>\u{2061}</mo></mrow><mi>x</mi></munder></mrow></math>", got7);
    // Layout: forced-inline stacks exactly like star-display (same
    // limits box either way), while unforced star-inline stays side.
    var b1: B = .{};
    const f = try lay("\\operatorname*{lim}\\limits_{x}", false, &b1);
    var b2: B = .{};
    const d = try lay("\\operatorname*{lim}_{x}", true, &b2);
    try std.testing.expectEqual(d.width, f.width);
    try std.testing.expectEqual(d.height_above, f.height_above);
    try std.testing.expectEqual(d.depth_below, f.depth_below);
    try std.testing.expectEqual(d.runs.len, f.runs.len);
    var b3: B = .{};
    const s = try lay("\\operatorname*{lim}_{x}", false, &b3);
    try std.testing.expect(s.depth_below < f.depth_below);
    try std.testing.expect(s.width > f.width);
}

test "qa87 clap subscripts center on the script anchor (issue #78)" {
    // KaTeX parity (pinned 0.18.7): a lap subscript is a zero-width
    // box (`mpadded lspace="-0.5width" width="0px"`) whose content
    // centers on the side-script anchor at the script drop. Anchor
    // and drop follow the pinned script contracts (qa43 60mu gap,
    // qa42 260mu drop); this test locks the LAP-relative geometry —
    // exact centering, shared drop, zero construct width — so the
    // PR-#74-era misplacement (content at the base origin, undropped)
    // can never return. Sweep lap-clap-* rows pin the MathML side.
    var bp: B = .{};
    const p = try lay("\\sum_{n}", false, &bp);
    const anchor = try glyphX(p, 0xD45B); // mathit n
    try std.testing.expectEqual(@as(i32, 560), anchor); // base 500 + 60mu gap
    const adv = @as(i32, @intCast(p.width)) - anchor; // 350: script advance
    var b1: B = .{};
    const l = try lay("\\sum_{\\mathclap{1\\le i\\le n}} x_{i}", false, &b1);
    const y_base = try baseY(l, 0x2211); // sum
    // Every content glyph shares the script drop ...
    for ([_]u16{ 0x31, 0x2264, 0xD456, 0xD45B }) |g| {
        try std.testing.expectEqual(y_base + 260, try baseY(l, g));
    }
    // ... and the content centers exactly on the anchor: first
    // origin plus last end mirror about it (stub-exact: -703 and
    // 1473 + 350 over anchor 560).
    const first = try glyphX(l, 0x31);
    const last = try glyphX(l, 0xD45B);
    try std.testing.expectEqual(2 * anchor, first + last + adv);
    // The zero-width sub adds no construct width past the anchor ...
    var b2: B = .{};
    const q = try lay("\\sum_{\\mathclap{x}}", false, &b2);
    try std.testing.expectEqual(@as(u32, @intCast(anchor)), q.width);
    // ... while the follower still lays out past it.
    try std.testing.expect(try glyphX(l, 0xD465) > anchor); // mathit x
}

test "qa88 paren math islands re-enter math in text (issue #81)" {
    // KaTeX parity (pinned 0.18.7): `\(...\)` inside `\text` is a
    // math island like `$...$` — same `.style{.T}` node, so fractions
    // lay out as math (frac rule) and nested `\text` merges back.
    // Sweep text-paren-* rows pin the MathML side.
    var b1: B = .{};
    const l = try lay("\\text{a\\(\\frac12\\)b}", false, &b1);
    try std.testing.expectEqual(@as(usize, 1), l.rules.len);
    try std.testing.expectEqual(@as(i32, 0), try glyphX(l, 97)); // text a first
    var b2: B = .{};
    const m = try lay("\\text{a\\(b\\)c\\(d\\)e}", false, &b2);
    try std.testing.expectEqual(@as(u32, 2500), m.width);
    // Edges reject like KaTeX: unclosed `\(` ("Expected '\\)'"),
    // stray `\)` ("Mismatched \\)"), `$` inside the island.
    var b3: B = .{};
    try std.testing.expectError(error.Invalid, lay("\\text{\\(x}", false, &b3));
    var b4: B = .{};
    try std.testing.expectError(error.Invalid, lay("\\text{a\\)b}", false, &b4));
    var b5: B = .{};
    try std.testing.expectError(error.Invalid, lay("\\text{\\(a$b\\)}", false, &b5));
}







test "qa107 cancel strikes corner-to-corner" {
    // Issue #107 (pinned 0.18.7 `stretchyEnclose`): `\cancel` strikes
    // up (bottom-left to top-right), `\bcancel` down, `\xcancel` both —
    // corner-to-corner 0.046em butt-cap diagonals over the padded box,
    // with zero metric change (the vlist keeps the inner box; the side
    // pad laps with zero net advance). Single-character bodies (KaTeX
    // `isCharacterBox`) grow 0.2em top and bottom; every other body
    // grows 0.2em on each side instead. Stub metrics pin the integer
    // geometry bit-for-bit (text style: pad 200, stroke 46).
    const T = struct {
        fn dump(src: []const u8, b: *B, out: []u8) ![]u8 {
            const l = try lay(src, false, b);
            return dumpAny(l, out);
        }
    };
    var b: B = .{};
    var out: [1024]u8 = undefined;
    // Exact goldens: single-char up/down, multi-char both, styled
    // multi, tall multi, mirror flip, neighbor composition.
    try std.testing.expectEqualStrings("500/700/250|1,1000,0,700:54373.;|0,-200,500,1350,u,46;", try T.dump("\\cancel{x}", &b, &out));
    try std.testing.expectEqualStrings("500/700/250|1,1000,0,700:54373.;|0,-200,500,1350,d,46;", try T.dump("\\bcancel{x}", &b, &out));
    try std.testing.expectEqualStrings("1000/700/250|1,1000,0,700:54324.54325.;|-200,0,1400,950,u,46;-200,0,1400,950,d,46;", try T.dump("\\xcancel{AB}", &b, &out));
    try std.testing.expectEqualStrings("500/700/250|9,1000,0,700:54425.;|-200,0,900,950,u,46;", try T.dump("\\cancel{\\boldsymbol{x}}", &b, &out));
    try std.testing.expectEqualStrings("590/975/520|0,700,120,490:49.;0,700,120,1320:50.;|0,705,590,40;-200,0,990,1495,u,46;", try T.dump("\\cancel{\\frac12}", &b, &out));
    try std.testing.expectEqualStrings("500/700/250|1,1000,500,700:54373.;|0,-200,500,1350,d,46;", try T.dump("\\mathreflectbox{\\cancel{x}}", &b, &out));
    try std.testing.expectEqualStrings("1944/700/250|1,1000,0,700:54373.;0,1000,722,700:43.;1,1000,1444,700:54374.;|0,-200,500,1350,u,46;", try T.dump("\\cancel{x}+y", &b, &out));
    // Zero metric change: the strike never moves the footprint.
    for ([_][2][]const u8{ .{ "\\cancel{x}", "x" }, .{ "\\bcancel{x}", "x" }, .{ "\\xcancel{AB}", "AB" }, .{ "\\cancel{\\frac12}", "\\frac12" } }) |pair| {
        const struck = try lay(pair[0], false, &b);
        // NOTE: `B` buffers are reused; copy the footprint before the
        // second lay overwrites the borrowed slices (scalars only).
        const sw = struck.width;
        const sh = struck.height_above;
        const sd = struck.depth_below;
        const bare = try lay(pair[1], false, &b);
        try std.testing.expectEqual(bare.width, sw);
        try std.testing.expectEqual(bare.height_above, sh);
        try std.testing.expectEqual(bare.depth_below, sd);
    }
    // Single/multi classification (KaTeX `cancel-pad` probe battery,
    // pinned 0.18.7): singles grow vertically only, multis widen only.
    const singles = [_][]const u8{ "x", "+", "=", "\\alpha", "\\infty", "{x}", "\\mathrm{x}", "\\mathbf{x}", "\\vert", "\\langle", "\\prime", "\\color{red}{x}" };
    for (singles) |body| {
        var src: [64]u8 = undefined;
        const tex = try std.fmt.bufPrint(&src, "\\cancel{{{s}}}", .{body});
        const l = try lay(tex, false, &b);
        try std.testing.expectEqual(@as(usize, 1), l.rules.len);
        const r = l.rules[0];
        try std.testing.expectEqual(zatex.ir.Diag.up, r.diag);
        try std.testing.expectEqual(@as(u32, 46), r.thick);
        try std.testing.expectEqual(l.width, r.w);
        try std.testing.expectEqual(l.height_above + l.depth_below + 400, r.h);
    }
    const multis = [_][]const u8{ "\\mathord{+}", "\\mathbin{x}", "\\hat{x}", "\\boldsymbol{x}", "\\sqrt{x}", "\\,", "\\text{x}", "\\sin", "x^2", "\\frac12", "AB", "\\;", "\\;x", "++" };
    for (multis) |body| {
        var src: [64]u8 = undefined;
        const tex = try std.fmt.bufPrint(&src, "\\cancel{{{s}}}", .{body});
        const l = try lay(tex, false, &b);
        // Tall bodies bring their own bar rules (`\frac`, `\sqrt`);
        // the strike is the one diagonal rule.
        var strike: ?zatex.ir.Rule = null;
        for (l.rules) |rr| {
            if (rr.diag == .none) continue;
            try std.testing.expectEqual(@as(?zatex.ir.Rule, null), strike);
            strike = rr;
        }
        const r = strike orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(zatex.ir.Diag.up, r.diag);
        try std.testing.expectEqual(@as(u32, 46), r.thick);
        try std.testing.expectEqual(l.width + 400, r.w);
        try std.testing.expectEqual(l.height_above + l.depth_below, r.h);
    }
}

test "qa108 angl border box" {
    // Issue #108 (pinned 0.18.7 enclose angl branch + stretchyEnclose):
    // the actuarial mark is a top + right border around the padded
    // nucleus: top pad 4 rule-thicknesses, bottom pad max(0, 0.25em -
    // depth), side pads 0.03889em plus the margin-right 0.03889em off
    // the right border. Unlike cancel the mark ADDS metrics (the vlist
    // keeps the border box). Stub text metrics pin the integers
    // (text style: t=40, pads 38/77; the dumps below).
    var b: B = .{};
    var out: [1024]u8 = undefined;
    const T = struct {
        fn dump(src: []const u8, bufs: *B, obuf: []u8) ![]u8 {
            const l = try lay(src, false, bufs);
            return dumpAny(l, obuf);
        }
    };
    try std.testing.expectEqualStrings("615/860/250|0,1000,38,860:110.;|0,0,615,40;575,0,40,1110;", try T.dump("\\angl{n}", &b, &out));
    try std.testing.expectEqualStrings("1115/860/250|0,1000,38,860:65.66.;|0,0,1115,40;1075,0,40,1110;", try T.dump("\\angl{AB}", &b, &out));
    try std.testing.expectEqualStrings("115/160/250||0,0,115,40;75,0,40,410;", try T.dump("\\angl{}", &b, &out));
    try std.testing.expectEqualStrings("615/860/250|0,1000,38,860:110.;|0,0,615,40;575,0,40,1110;", try T.dump("\\angln", &b, &out));
    // Structural shape over several nuclei: exactly two plain rules —
    // a full-width top bar and a full-height right bar — and the
    // border-box footprint.
    for ([_][]const u8{ "n", "AB", "x+y", "gj", "{}" }) |body| {
        var src: [64]u8 = undefined;
        const tex = try std.fmt.bufPrint(&src, "\\angl{{{s}}}", .{body});
        const l = try lay(tex, false, &b);
        try std.testing.expectEqual(@as(usize, 2), l.rules.len);
        const top = l.rules[0];
        const right = l.rules[1];
        try std.testing.expectEqual(zatex.ir.Diag.none, top.diag);
        try std.testing.expectEqual(zatex.ir.Diag.none, right.diag);
        // Top bar: full padded width, t thick, top edge on the border top.
        try std.testing.expectEqual(@as(i32, 0), top.x);
        try std.testing.expectEqual(l.width, top.w);
        try std.testing.expectEqual(@as(u32, 40), top.h);
        try std.testing.expectEqual(@as(i32, 0), top.y);
        // Right bar: t wide at the right edge, full border-box height.
        try std.testing.expectEqual(@as(i32, @intCast(l.width)) - 40, right.x);
        try std.testing.expectEqual(@as(u32, 40), right.w);
        try std.testing.expectEqual(@as(i32, 0), right.y);
        try std.testing.expectEqual(l.height_above + l.depth_below, right.h);
        // The mark grows the nucleus: 4t above, side pads 38/77.
        try std.testing.expect(l.height_above >= 160);
        try std.testing.expect(l.width >= 115);
    }
}

test "qa112 binom fences use Rule 15e sizing" {
    // Issue #112 (pinned 0.18.7 genfrac Rule 15e + delimsizing): the
    // whole barless family targets a FIXED height — delim1 (2.39em) in
    // display, delim2 (1.01em text, 1.157em script) elsewhere — picked
    // through the variant hook and axis-centered, abutting the
    // content. `\binom{a}{b}` and `\genfrac(){0pt}{1}{a}{b}` lay out
    // byte-identical boxes now (were 1588 vs 1656 CLI px); tall
    // content takes the max on both paths. Stub text metrics pin the
    // integers (no variants: the 1010 target always wins).
    var b: B = .{};
    var out: [2048]u8 = undefined;
    const T = struct {
        fn dump(src: []const u8, bufs: *B, obuf: []u8) ![]u8 {
            const l = try lay(src, false, bufs);
            return dumpAny(l, obuf);
        }
        fn dumpD(src: []const u8, bufs: *B, obuf: []u8) ![]u8 {
            const l = try lay(src, true, bufs);
            return dumpAny(l, obuf);
        }
    };
    // Text style: content (934+520) exceeds the 1010 target, so the
    // stack rules; fences abut it with no paren gap (was +100/side).
    try std.testing.expectEqualStrings("1590/934/520|0,1000,0,934:40.;1,700,620,490:54350.;1,700,620,1279:54351.;0,1000,1090,934:41.;|", try T.dump("\\binom{a}{b}", &b, &out));
    try std.testing.expectEqualStrings("1590/934/520|0,1000,0,934:40.;1,700,620,490:54350.;1,700,620,1279:54351.;0,1000,1090,934:41.;|", try T.dump("\\genfrac(){0pt}{1}{a}{b}", &b, &out));
    try std.testing.expectEqualStrings("1590/934/520|0,1000,0,934:40.;1,700,620,490:54350.;1,700,620,1279:54351.;0,1000,1090,934:41.;|", try T.dump("a\\choose b", &b, &out));
    try std.testing.expectEqualStrings("1590/934/520|0,1000,0,934:123.;1,700,620,490:54350.;1,700,620,1279:54351.;0,1000,1090,934:125.;|", try T.dump("a\\brace b", &b, &out));
    try std.testing.expectEqualStrings("1590/934/520|0,1000,0,934:91.;1,700,620,490:54350.;1,700,620,1279:54351.;0,1000,1090,934:93.;|", try T.dump("a\\brack b", &b, &out));
    // Tall content takes the max, identically on both paths.
    try std.testing.expectEqualStrings("3184/1039/520|0,1000,0,1039:40.;1,700,620,595:54350.;0,500,1012,350:50.;0,700,1417,595:43.;1,700,1922,595:54351.;0,500,2314,350:50.;1,700,1417,1384:54352.;0,1000,2684,1039:41.;|", try T.dump("\\binom{a^2+b^2}{c}", &b, &out));
    try std.testing.expectEqualStrings("3184/1039/520|0,1000,0,1039:40.;1,700,620,595:54350.;0,500,1012,350:50.;0,700,1417,595:43.;1,700,1922,595:54351.;0,500,2314,350:50.;1,700,1417,1384:54352.;0,1000,2684,1039:41.;|", try T.dump("\\genfrac(){0pt}{1}{a^2+b^2}{c}", &b, &out));
    // Display style: the 2390 target rules (1445+945), identically.
    try std.testing.expectEqualStrings("1740/1445/945|0,1000,0,1445:40.;1,1000,620,768:54350.;1,1000,620,2131:54351.;0,1000,1240,1445:41.;|", try T.dump("\\dbinom{a}{b}", &b, &out));
    try std.testing.expectEqualStrings("1740/1445/945|0,1000,0,1445:40.;1,1000,620,768:54350.;1,1000,620,2131:54351.;0,1000,1240,1445:41.;|", try T.dumpD("\\genfrac(){0pt}{0}{a}{b}", &b, &out));
    // Fences abut the content: left paren at x=0, stack at the paren
    // advance (500 stub units), right paren past the stack.
    {
        const l = try lay("\\binom{a}{b}", false, &b);
        try std.testing.expectEqual(@as(i32, 0), try glyphX(l, 40));
        try std.testing.expectEqual(@as(i32, 620), try glyphX(l, 54350));
        try std.testing.expectEqual(@as(i32, 1090), try glyphX(l, 41));
        try std.testing.expectEqual(@as(i32, 1590), l.width);
    }
}
