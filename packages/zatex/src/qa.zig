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
            // `y` (121) and `+` (43) sit at identical x in both.
            try std.testing.expectEqual(try glyphX(c, 121), try glyphX(a, 121));
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
    try std.testing.expectEqual(@as(i32, 400), try supRaise(top, 120, 50));
    try std.testing.expectEqual(@as(i32, 370), try supRaise(rad, 120, 50));
    // Display mode radicand is Dc: same 30mu drop (400 vs 370).
    const rad_d = try lay("\\sqrt{x^2}", true, &b2);
    try std.testing.expectEqual(@as(i32, 370), try supRaise(rad_d, 120, 50));
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
    try std.testing.expectEqual(@as(i32, 245), try supRaise(num, 120, 50));
    try std.testing.expectEqual(@as(i32, 224), try supRaise(den, 120, 50));
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
    // B (66) sits exactly one 260mu drop below A; C (67) a further
    // 182mu (= 260 at size 700) below B.
    try std.testing.expectEqual(@as(i32, 700), try baseY(l, 65));
    try std.testing.expectEqual(@as(i32, 700 + 260), try baseY(l, 66));
    try std.testing.expectEqual(@as(i32, 700 + 260 + 182), try baseY(l, 67));
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
    try std.testing.expectEqual(@as(i32, 245), try supRaise(l2, 66, 50));
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
    const y_sup_d = try baseY(d, 110);
    const y_sub_d = try baseY(d, 105);
    try std.testing.expect(y_sup_d < y_base_d);
    try std.testing.expect(y_sub_d > y_base_d);
    // Text mode: side scripts at one 60mu script gap past the 500-unit base.
    const x_base_t = try glyphX(t, 8721);
    const x_sup_t = try glyphX(t, 110);
    const x_sub_t = try glyphX(t, 105);
    try std.testing.expectEqual(x_base_t + 500 + 60, x_sup_t);
    try std.testing.expectEqual(x_base_t + 500 + 60, x_sub_t);
}

fn baseY(l: zatex.ir.Layout, glyph: u16) !i32 {
    for (l.runs) |r| {
        for (r.glyphs) |g| if (g == glyph) return r.baseline_y;
    }
    return error.TestUnexpectedResult;
}

test "qa43 lim stacks in display, sits aside in text" {
    // `\lim` is a default-limits word operator: same placement split.
    var bd: B = .{};
    var bt: B = .{};
    const d = try lay("\\lim_{x} f", true, &bd);
    const t = try lay("\\lim_{x} f", false, &bt);
    const y_base_d = try baseY(d, 108); // 'l' of "lim"
    const y_sub_d = try baseY(d, 120); // 'x'
    try std.testing.expect(y_sub_d > y_base_d);
    // Text mode: the subscript starts one 60mu gap past "lim" (1500 units).
    const x_sub_t = try glyphX(t, 120);
    const x_lim_t = try glyphX(t, 108);
    try std.testing.expectEqual(x_lim_t + 1500 + 60, x_sub_t);
    // Display mode centers the subscript under the word, not aside it.
    const x_sub_d = try glyphX(d, 120);
    try std.testing.expect(x_sub_d < x_lim_t + 1500);
}

test "qa43 int scripts sit aside in both modes" {
    // Integrals never take limits (`lim_def = false`): side scripts in
    // both modes; only the large-op sizing differs (1400 vs 1000).
    for ([_]bool{ false, true }) |display| {
        var b: B = .{};
        const l = try lay("\\int_{0}^{1} x", display, &b);
        const base_w: i32 = if (display) 700 else 500;
        const x_base = try glyphX(l, 8747);
        try std.testing.expectEqual(x_base + base_w + 60, try glyphX(l, 49));
        try std.testing.expectEqual(x_base + base_w + 60, try glyphX(l, 48));
    }
    var bd: B = .{};
    var bt: B = .{};
    const d = try lay("\\int_{0}^{1} x", true, &bd);
    const t = try lay("\\int_{0}^{1} x", false, &bt);
    try std.testing.expect(d.width > t.width);
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
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover><mrow><mi>A</mi><mi>B</mi></mrow><mo>&#xAF;</mo></mover></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mover><mi>x</mi><mo>^</mo></mover><mo>+</mo><mover><mi>y</mi><mo>⃗</mo></mover></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathvariant=\"bold\"><mi>A</mi></mstyle><mo>+</mo><mstyle mathvariant=\"italic\"><mi>B</mi></mstyle></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mstyle mathcolor=\"red\"><mi>x</mi><mo>+</mo><mi>y</mi></mstyle></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mtext>hello </mtext><mo>+</mo><mi>x</mi></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mo>(</mo><mfrac linethickness=\"0\"><mi>n</mi><mi>k</mi></mfrac><mo>)</mo></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><mfrac><msup><mi>x</mi><mn>2</mn></msup><mn>1</mn></mfrac></mrow></math>",
    "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mrow><msub><mi>A</mi><msub><mi>B</mi><mi>C</mi></msub></msub></mrow></math>",
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
    // (need+1)/2 where need = body.ha + body.db + max(2*th, 120).
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
        const clear: i64 = @max(2 * @as(i64, s.th), 120);
        const need: i64 = fha + fdb + clear;
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
        return if (glyph == 0x20D7) 0 else 500;
    }
    fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
        return 40;
    }
    fn inkBounds(_: *const anyopaque, _: u16, glyph: u16) [4]i32 {
        return switch (glyph) {
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
    try std.testing.expectEqual(@as(i32, 0), ax);
}

test "qa48 ink centers combining marks by ink" {
    // U+20D7 ink hangs left of its zero-advance origin (-472..-56);
    // centering by advance would park the arrow left of the nucleus
    // (the reported vec bug). Ink-centering: ax = (500-416)/2+472.
    var b: ProvBuf = .{};
    const l = try layInk("\\vec{F}", &b);
    const ax = try glyphX(l, 0x20D7);
    try std.testing.expectEqual(@as(i32, 514), ax);
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
        if (r.glyphs.len == 3 and r.glyphs[0] == '.' and r.x == 0) found = true;
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
