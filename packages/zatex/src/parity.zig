//! Differential parity test: every row of the pinned-KaTeX sweep
//! (`goldens/katex_sweep.json`, KaTeX 0.18.7) must agree with this
//! engine on accept/reject, on `ParseError.position` for rejects, and
//! on normalized MathML tag structure for accepts.
//!
//! Regenerate goldens with `npm run sweep` in `tools/katex` (requires
//! network once for `npm ci`); this test only reads the JSON.
//!
//! Normalizations (documented equivalences, see `docs/tolerance.md`):
//! - envelope tags `math`/`semantics`/`annotation` carry no layout.
//! - `\font` commands emit an `mstyle mathvariant` wrapper while KaTeX
//!   pushes the variant onto leaves; the wrapper is dropped.
//! - `\href` emits an `mrow href` wrapper while KaTeX puts `href` on
//!   the child; the wrapper is dropped.
//! - single-child `mrow` shells drop: KaTeX merges runs before
//!   row-wrapping, so one-leaf groups pass through bare.
//! Attribute *values* (spacing widths, exact variants) are out of
//! scope: this test compares structure, not metrics.

const std = @import("std");
const zatex = @import("zatex");

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

/// True when the `<mrow>` opening at `lt` wraps exactly one child
/// element. KaTeX merges runs before row-wrapping (`buildExpression`
/// then `makeRow`), so single-leaf groups pass through bare; an
/// `mrow` around one child is grouping-transparent per MathML
/// semantics, so the shell drops like the other wrappers below.
fn singleChildMrow(src: []const u8, lt: usize) bool {
    var i = lt;
    var level: u32 = 0;
    var kids: u32 = 0;
    var started = false;
    while (i < src.len) {
        const l = std.mem.indexOfScalarPos(u8, src, i, '<') orelse return false;
        const g = std.mem.indexOfScalarPos(u8, src, l, '>') orelse return false;
        const raw = src[l + 1 .. g];
        i = g + 1;
        if (raw.len == 0) continue;
        const closing = raw[0] == '/';
        const body = if (closing) raw[1..] else raw;
        var e: usize = 0;
        while (e < body.len and body[e] != ' ' and body[e] != '\t' and
            body[e] != '\n' and body[e] != '\r' and body[e] != '/') : (e += 1) {}
        const name = body[0..e];
        if (name.len == 0 or name[0] == '!' or name[0] == '?') continue;
        const self_close = !closing and raw[raw.len - 1] == '/';
        if (!started) {
            if (closing) return false;
            started = true;
            level = 1;
            continue;
        }
        if (closing) {
            if (level == 0) return false;
            level -= 1;
            if (level == 0) return kids == 1;
            continue;
        }
        if (level == 1) kids += 1;
        if (!self_close) level += 1;
    }
    return false;
}

/// Reduce MathML to a canonical space-joined tag sequence, applying
/// the documented normalizations. Returns the normalized length.
fn normTags(src: []const u8, out: []u8) usize {
    var pos: usize = 0;
    var first = true;
    // Element depth (wrapper shells included) plus the depths at which
    // dropped wrapper shells opened. A wrapper's matching close is the
    // first close back down to its depth; children pass through.
    var depth: u32 = 0;
    var wrap_depths: [32]u32 = undefined;
    var nwraps: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        const lt = std.mem.indexOfScalarPos(u8, src, i, '<') orelse break;
        const gt = std.mem.indexOfScalarPos(u8, src, lt, '>') orelse break;
        const raw = src[lt + 1 .. gt];
        i = gt + 1;
        if (raw.len == 0) continue;
        const closing = raw[0] == '/';
        const body = if (closing) raw[1..] else raw;
        var nm_end: usize = 0;
        while (nm_end < body.len and body[nm_end] != ' ' and
            body[nm_end] != '\t' and body[nm_end] != '\n' and
            body[nm_end] != '\r' and body[nm_end] != '/') : (nm_end += 1)
        {}
        const name = body[0..nm_end];
        if (name.len == 0 or name[0] == '!' or name[0] == '?') continue;
        const self_close = !closing and raw[raw.len - 1] == '/';
        const is_wrapper = !closing and !self_close and
            ((std.mem.eql(u8, name, "mstyle") and std.mem.indexOf(u8, raw, "mathvariant") != null) or
            (std.mem.eql(u8, name, "mrow") and std.mem.indexOf(u8, raw, "href") != null) or
            (std.mem.eql(u8, name, "mrow") and singleChildMrow(src, lt)));
        if (is_wrapper) {
            // Drop the shell; children pass through. Nesting deeper
            // than the table fails loudly below (tags won't match).
            if (nwraps < wrap_depths.len) {
                wrap_depths[nwraps] = depth;
                nwraps += 1;
            }
            depth += 1;
            continue;
        }
        if (closing) {
            if (depth > 0) depth -= 1;
            var is_wrap_close = false;
            var wi: usize = 0;
            while (wi < nwraps) : (wi += 1) {
                if (wrap_depths[wi] == depth) {
                    wrap_depths[wi] = wrap_depths[nwraps - 1];
                    nwraps -= 1;
                    is_wrap_close = true;
                    break;
                }
            }
            if (is_wrap_close) continue;
        } else if (!self_close) {
            depth += 1;
        }
        if (std.mem.eql(u8, name, "math") or std.mem.eql(u8, name, "semantics") or
            std.mem.eql(u8, name, "annotation"))
        {
            continue;
        }
        if (!first) {
            if (pos < out.len) {
                out[pos] = ' ';
                pos += 1;
            }
        }
        first = false;
        const n = @min(name.len, out.len -| pos);
        @memcpy(out[pos .. pos + n], name[0..n]);
        pos += n;
    }
    return pos;
}

fn expectTags(expected: []const u8, actual: []const u8, id: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("\ntag mismatch [{s}]\n  katex: {s}\n  zatex: {s}\n", .{ id, expected, actual });
        return error.TestUnexpectedResult;
    }
}

test "sweep agreement with pinned KaTeX" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Goldens live outside the module package, so they load at
    // runtime; the build pins the test cwd to the project root.
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

    var runs: [1024]zatex.ir.Run = undefined;
    var rules: [128]zatex.ir.Rule = undefined;
    var glyphs: [8192]u16 = undefined;
    var mbuf: [65536]u8 = undefined;
    var kbuf: [65536]u8 = undefined;
    var abuf: [65536]u8 = undefined;

    var n_ok: usize = 0;
    var n_rej: usize = 0;
    var n_only: usize = 0;
    for (root.items) |item| {
        const o = item.object;
        const id = o.get("id").?.string;
        const tex = o.get("tex").?.string;
        const display = o.get("display").?.bool;
        const katex_ok = o.get("katex_ok").?.bool;
        const katex_only = o.get("katex_only").?.bool;
        const opts: zatex.LayoutOptions = .{ .display_mode = display };

        var diag = zatex.Diag.empty();
        const prov = stubProvider();
        const lay = zatex.layoutDiag(tex, opts, prov, &runs, &rules, &glyphs, &diag);
        if (katex_only) {
            // Documented divergence: only our declared behavior holds.
            const want = o.get("ours").?.string;
            if (lay) |_| {
                std.debug.print("\n[{s}] katex_only row unexpectedly accepted\n", .{id});
                return error.TestUnexpectedResult;
            } else |e| {
                if (!std.mem.eql(u8, want, @errorName(e))) {
                    std.debug.print("\n[{s}] want {s}, got {s}\n", .{ id, want, @errorName(e) });
                    return error.TestUnexpectedResult;
                }
                n_only += 1;
                continue;
            }
        }
        if (lay) |l1| {
            if (!katex_ok) {
                std.debug.print("\n[{s}] zatex accepts, katex rejects\n", .{id});
                return error.TestUnexpectedResult;
            }
            const mine = try zatex.mathml(tex, opts, &mbuf);
            const kmath = o.get("katex_mathml").?.string;
            const kn = normTags(kmath, &kbuf);
            const an = normTags(mine, &abuf);
            try expectTags(kbuf[0..kn], abuf[0..an], id);
            // Issue #20: the atom grid also pins stub-provider IR
            // widths — every grid row lays out nonempty (no spacing
            // collapse) and deterministically.
            if (std.mem.startsWith(u8, id, "atomgrid-")) {
                try std.testing.expect(l1.width > 0);
                var diag2 = zatex.Diag.empty();
                const l2 = try zatex.layoutDiag(tex, opts, prov, &runs, &rules, &glyphs, &diag2);
                try std.testing.expectEqual(l1.width, l2.width);
                try std.testing.expectEqual(l1.runs.len, l2.runs.len);
                try std.testing.expectEqual(l1.rules.len, l2.rules.len);
            }
            n_ok += 1;
        } else |e| {
            if (katex_ok) {
                std.debug.print("\n[{s}] zatex rejects ({s}), katex accepts\n", .{ id, @errorName(e) });
                return error.TestUnexpectedResult;
            }
            if (e != error.Invalid) {
                std.debug.print("\n[{s}] want Invalid, got {s}\n", .{ id, @errorName(e) });
                return error.TestUnexpectedResult;
            }
            // Position parity when KaTeX reports one; macro-table
            // errors carry none on either side.
            if (o.get("katex_pos")) |pos| {
                if (pos != .null) {
                    const want: u32 = @intCast(pos.integer);
                    if (diag.offset != want) {
                        std.debug.print("\n[{s}] pos want {d}, got {d}\n", .{ id, want, diag.offset });
                        return error.TestUnexpectedResult;
                    }
                }
            }
            n_rej += 1;
        }
    }
    std.debug.print("\nparity: {d} accept, {d} reject, {d} declared-divergence\n", .{ n_ok, n_rej, n_only });
}

test "text accents lay out: tilde command, braced args" {
    // `\\~` is an accent (not nbsp) and `\\'{a}` takes a braced arg
    // (KaTeX parity); both must lay out, not come back Invalid.
    var runs: [1024]zatex.ir.Run = undefined;
    var rules: [128]zatex.ir.Rule = undefined;
    var glyphs: [8192]u16 = undefined;
    var diag = zatex.Diag.empty();
    const a = try zatex.layoutDiag("\\text{\\~{a}}", .{}, stubProvider(), &runs, &rules, &glyphs, &diag);
    try std.testing.expect(a.width > 0);
    const b = try zatex.layoutDiag("\\text{\\'{a}}", .{}, stubProvider(), &runs, &rules, &glyphs, &diag);
    try std.testing.expect(b.width > 0);
}

test "lap family overlaps with zero width (issue #71)" {
    // Pinned KaTeX 0.18.7 proof: laps take no space; the body hangs
    // left (llap), right (rlap), or centered (clap) over its neighbors.
    // Stub advance is a flat 500, so the lapped body is 500 wide.
    const Case = struct { src: []const u8, body_x: i32 };
    const cases = [_]Case{
        .{ .src = "\\llap{x}y", .body_x = -500 },
        .{ .src = "\\rlap{x}y", .body_x = 0 },
        .{ .src = "\\clap{x}y", .body_x = -250 },
    };
    for (cases) |c| {
        var runs: [16]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [16]u16 = undefined;
        var diag = zatex.Diag.empty();
        const lay = try zatex.layoutDiag(c.src, .{}, stubProvider(), &runs, &rules, &glyphs, &diag);
        try std.testing.expectEqual(@as(u32, 500), lay.width);
        try std.testing.expectEqual(@as(usize, 2), lay.runs.len);
        try std.testing.expectEqual(c.body_x, lay.runs[0].x);
        try std.testing.expectEqual(@as(i32, 0), lay.runs[1].x);
    }
}

test "accent skew follows the KaTeX table (issue #70)" {
    // Pinned KaTeX 0.18.7 centers a math accent at nucleus-center +
    // full skew over single-symbol nuclei. The stub has no italic
    // hook, so the shift is exactly the table value (M: 83, y: 56);
    // multi-symbol nuclei stay centered (`\tilde{AB}` measures
    // dead-centered in KaTeX DOM).
    const Case = struct { src: []const u8, accent_x: i32 };
    const cases = [_]Case{
        .{ .src = "\\tilde{M}", .accent_x = 83 },
        .{ .src = "\\bar{y}", .accent_x = 56 },
        .{ .src = "\\tilde{AB}", .accent_x = 250 },
    };
    for (cases) |c| {
        var runs: [16]zatex.ir.Run = undefined;
        var rules: [4]zatex.ir.Rule = undefined;
        var glyphs: [16]u16 = undefined;
        var diag = zatex.Diag.empty();
        const lay = try zatex.layoutDiag(c.src, .{}, stubProvider(), &runs, &rules, &glyphs, &diag);
        try std.testing.expectEqual(@as(usize, 2), lay.runs.len);
        try std.testing.expectEqual(@as(i32, 0), lay.runs[0].x);
        try std.testing.expectEqual(c.accent_x, lay.runs[1].x);
    }
}

