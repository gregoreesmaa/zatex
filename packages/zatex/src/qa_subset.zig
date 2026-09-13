//! Subset-profile QA probes, issue #45 (subset half).
//!
//! Separate test binary compiled with `profile = "subset"`: the engine
//! sources belong to exactly one module per compilation, so the full-vs-
//! subset comparison rides on the checked-in `goldens/qa_profile_ir.json`
//! (this binary asserts the subset half, `qa.zig` the full half).
const std = @import("std");
const build_options = @import("build_options");
const contract = @import("contract.zig");
const ir = @import("ir.zig");
const parse = @import("parse.zig");
const symbols = @import("symbols.zig");
const engine = @import("layout.zig");

pub const profile: contract.Profile =
    std.meta.stringToEnum(contract.Profile, build_options.profile) orelse .full;

/// Subset `layoutDiag`: same wiring as `zatex.layoutDiag`.
fn layoutDiag(
    source: []const u8,
    options: contract.LayoutOptions,
    provider: contract.MetricsProvider,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
    diag: *contract.Diag,
) contract.LayoutError!ir.Layout {
    if (source.len > contract.max_input_len) return error.TooLong;
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, options.display_mode) catch |e| {
        diag.offset = if (pc.err_pos > source.len) @intCast(source.len) else pc.err_pos;
        diag.message = pc.err_msg;
        return e;
    };
    var lc = engine.LayCtx.init(&pc, provider);
    const style: parse.Style = if (options.display_mode) .D else .T;
    return engine.layout(&lc, root, style, runs, rules, glyphs);
}

fn stubProvider() contract.MetricsProvider {
    const S = struct {
        var dummy: u8 = 0;
        fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @truncate(cp);
        }
        fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn ruleThickness(_: *const anyopaque, _: u16, _: contract.RuleKind) i32 {
            return 40;
        }
    };
    return .{
        .ctx = &S.dummy,
        .glyphId = S.glyphId,
        .advance = S.advance,
        .ruleThickness = S.ruleThickness,
    };
}

const B = struct {
    runs: [1024]ir.Run = undefined,
    rules: [128]ir.Rule = undefined,
    glyphs: [8192]u16 = undefined,
};

fn lay(src: []const u8, display: bool, b: *B) !ir.Layout {
    var diag = contract.Diag.empty();
    return layoutDiag(src, .{ .display_mode = display }, stubProvider(), &b.runs, &b.rules, &b.glyphs, &diag);
}

fn dump(l: ir.Layout, out: []u8) []u8 {
    var pos: usize = 0;
    var trunc = false;
    const P = struct {
        fn ch(o: []u8, p: *usize, t: *bool, c: u8) void {
            if (p.* >= o.len) {
                t.* = true;
                return;
            }
            o[p.*] = c;
            p.* += 1;
        }
        fn int(o: []u8, p: *usize, t: *bool, v: i64) void {
            if (v < 0) {
                ch(o, p, t, '-');
                uint(o, p, t, @as(u64, @intCast(-v)));
            } else uint(o, p, t, @as(u64, @intCast(v)));
        }
        fn uint(o: []u8, p: *usize, t: *bool, v: u64) void {
            var tmp: [20]u8 = undefined;
            var n: usize = 0;
            var x = v;
            if (x == 0) {
                ch(o, p, t, '0');
                return;
            }
            while (x > 0) : (n += 1) {
                tmp[n] = '0' + @as(u8, @intCast(x % 10));
                x /= 10;
            }
            while (n > 0) : (n -= 1) ch(o, p, t, tmp[n - 1]);
        }
    };
    P.int(out, &pos, &trunc, @as(i64, l.width));
    P.ch(out, &pos, &trunc, '/');
    P.int(out, &pos, &trunc, @as(i64, l.height_above));
    P.ch(out, &pos, &trunc, '/');
    P.int(out, &pos, &trunc, @as(i64, l.depth_below));
    P.ch(out, &pos, &trunc, '|');
    for (l.runs) |r| {
        P.int(out, &pos, &trunc, r.font_id);
        P.ch(out, &pos, &trunc, ',');
        P.int(out, &pos, &trunc, r.size_units);
        P.ch(out, &pos, &trunc, ',');
        P.int(out, &pos, &trunc, @as(i64, r.x));
        P.ch(out, &pos, &trunc, ',');
        P.int(out, &pos, &trunc, @as(i64, r.baseline_y));
        P.ch(out, &pos, &trunc, ':');
        for (r.glyphs) |g| {
            P.int(out, &pos, &trunc, g);
            P.ch(out, &pos, &trunc, '.');
        }
        P.ch(out, &pos, &trunc, ';');
    }
    P.ch(out, &pos, &trunc, '|');
    for (l.rules) |r| {
        P.int(out, &pos, &trunc, @as(i64, r.x));
        P.ch(out, &pos, &trunc, ',');
        P.int(out, &pos, &trunc, @as(i64, r.y));
        P.ch(out, &pos, &trunc, ',');
        P.int(out, &pos, &trunc, @as(i64, r.w));
        P.ch(out, &pos, &trunc, ',');
        P.int(out, &pos, &trunc, @as(i64, r.h));
        P.ch(out, &pos, &trunc, ';');
    }
    if (trunc and pos >= 3) @memcpy(out[pos - 3 ..][0..3], "...");
    return out[0..pos];
}

test "subset profile identity" {
    try std.testing.expectEqual(contract.Profile.subset, profile);
}

/// Full-only construct markers (substring, reason): a sweep accept the
/// subset profile cannot render must name at least one. Reviewed list —
/// every entry must explain >= 1 divergent row (stale entries fail, and
/// rows without a marker fail). Omitted deliberately: commands the
/// subset profile accepts (`\text`, `\quad`, `\hspace`, `\dfrac`,
/// `\binom`, ...) — allowlisting those would hide regressions.
const full_only_markers = [_]struct { mark: []const u8, why: []const u8 }{
    .{ .mark = "\\left", .why = "sized fences are full-only" },
    .{ .mark = "\\big", .why = "unsized big fences are full-only" },
    .{ .mark = "\\Big", .why = "unsized big fences are full-only" },
    .{ .mark = "\\begin", .why = "environments are full-only" },
    .{ .mark = "\\color", .why = "color specs are full-only" },
    .{ .mark = "\\textcolor", .why = "scoped color is full-only" },
    .{ .mark = "colorbox", .why = "background boxes are full-only" },
    .{ .mark = "\\displaystyle", .why = "style declarations are full-only" },
    .{ .mark = "\\textstyle", .why = "style declarations are full-only" },
    .{ .mark = "\\scriptstyle", .why = "style declarations are full-only" },
    .{ .mark = "\\scriptscriptstyle", .why = "style declarations are full-only" },
    .{ .mark = "\\phantom", .why = "phantoms are full-only" },
    .{ .mark = "\\href", .why = "hyperlinks are full-only" },
    .{ .mark = "\\url", .why = "hyperlinks are full-only" },
    .{ .mark = "\\boxed", .why = "boxes are full-only" },
    .{ .mark = "\\smash", .why = "smash/raisebox/rule are full-only" },
    .{ .mark = "\\raisebox", .why = "smash/raisebox/rule are full-only" },
    .{ .mark = "\\rule", .why = "smash/raisebox/rule are full-only" },
    .{ .mark = "\\cancel", .why = "cancel/lap are full-only" },
    .{ .mark = "llap", .why = "cancel/lap are full-only" },
    .{ .mark = "\\operatorname", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\substack", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\mathchoice", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\overset", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\overline", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\underline", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\overbrace", .why = "over/under-constructs are full-only" },
    .{ .mark = "arrow", .why = "extensible arrows are full-only" },
    .{ .mark = "\\not", .why = "negation is full-only" },
    .{ .mark = "\\genfrac", .why = "generalized fractions are full-only" },
    .{ .mark = "\\def", .why = "macro definitions are full-only" },
    .{ .mark = "\\newcommand", .why = "macro definitions are full-only" },
    .{ .mark = "\\renewcommand", .why = "macro definitions are full-only" },
    .{ .mark = "\\providecommand", .why = "macro definitions are full-only" },
    .{ .mark = "\\gdef", .why = "macro definitions are full-only" },
    .{ .mark = "\\let", .why = "macro definitions are full-only" },
    .{ .mark = "\\verb", .why = "verbatim is full-only" },
    .{ .mark = "\\hat", .why = "math accents are full-only" },
    .{ .mark = "\\widehat", .why = "math accents are full-only" },
    .{ .mark = "\\tilde", .why = "math accents are full-only" },
    .{ .mark = "\\widetilde", .why = "math accents are full-only" },
    .{ .mark = "\\vec", .why = "math accents are full-only" },
    .{ .mark = "\\dddot", .why = "math accents are full-only" },
    .{ .mark = "\\ddddot", .why = "math accents are full-only" },
    .{ .mark = "\\mathring", .why = "math accents are full-only" },
    .{ .mark = "\\widecheck", .why = "math accents are full-only" },
};

fn hasMarker(tex: []const u8) ?usize {
    for (full_only_markers, 0..) |m, k| {
        if (std.mem.indexOf(u8, tex, m.mark) != null) return k;
    }
    return null;
}

test "qa45s golden dumps match subset" {
    // Subset half of the profile-equality probe: every row of the
    // checked-in golden renders byte-identically under subset gates.
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
            std.debug.print("\n[{s}] subset rejects golden row ({s})\n", .{ id, @errorName(e) });
            return error.TestUnexpectedResult;
        };
        var db: [16384]u8 = undefined;
        const got = dump(l, &db);
        if (!std.mem.eql(u8, want, got)) {
            std.debug.print("\ngolden mismatch [{s}]\n--- golden ---\n{s}\n--- subset ---\n{s}\n--- end ---\n", .{ id, want, got });
            return error.TestUnexpectedResult;
        }
        n += 1;
    }
    std.debug.print("\nprofiles(subset): {d} golden rows identical\n", .{n});
}

test "qa45s subset fallback is honest and allowlisted" {
    // The allowlist half: every non-katex_only sweep row the subset
    // profile rejects must fail with an honest fallback (`Unsupported`
    // for gated commands, `Invalid` for subset-missing symbols — never
    // anything else) AND name a reviewed full-only marker. Every
    // subset-accepted row must be in the golden map (no silent extra
    // coverage), and subset must never accept what the sweep rejects.
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
    const golden_raw = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "goldens/qa_profile_ir.json",
        alloc,
        .limited(4 * 1024 * 1024),
    );
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, goldens, .{});
    const golden_parsed = try std.json.parseFromSlice(std.json.Value, alloc, golden_raw, .{});
    const root = parsed.value.object.get("cases").?.array;
    const grows = golden_parsed.value.object.get("rows").?.array;
    var used: [full_only_markers.len]bool = .{false} ** full_only_markers.len;
    var n_golden: usize = 0;
    var n_allow: usize = 0;
    var n_rej: usize = 0;
    var n_uncovered: usize = 0;
    for (root.items) |item| {
        const o = item.object;
        const id = o.get("id").?.string;
        const tex = o.get("tex").?.string;
        const display = o.get("display").?.bool;
        const katex_ok = o.get("katex_ok").?.bool;
        const katex_only = o.get("katex_only").?.bool;
        if (katex_only) continue; // declared divergence: parity owns it.
        var b: B = .{};
        if (lay(tex, display, &b)) |_| {
            if (!katex_ok) {
                std.debug.print("\n[{s}] subset accepts what the sweep rejects\n", .{id});
                return error.TestUnexpectedResult;
            }
            var in_map = false;
            for (grows.items) |g| {
                if (std.mem.eql(u8, g.object.get("id").?.string, id)) {
                    in_map = true;
                    break;
                }
            }
            if (!in_map) {
                std.debug.print("\n[{s}] subset accept missing from golden map\n", .{id});
                return error.TestUnexpectedResult;
            }
            n_golden += 1;
        } else |se| {
            if (katex_ok) {
                if (se != error.Unsupported and se != error.Invalid) {
                    std.debug.print("\n[{s}] subset dishonest error {s}\n", .{ id, @errorName(se) });
                    return error.TestUnexpectedResult;
                }
                if (hasMarker(tex)) |mk| {
                    used[mk] = true;
                    n_allow += 1;
                } else {
                    std.debug.print("\n[{s}] subset-{s} with no allowlisted marker: {s}\n", .{ id, @errorName(se), tex });
                    n_uncovered += 1;
                }
            } else {
                n_rej += 1;
            }
        }
    }
    var n_stale: usize = 0;
    for (full_only_markers, 0..) |m, k| {
        if (!used[k]) {
            std.debug.print("\nstale allowlist marker: {s} ({s})\n", .{ m.mark, m.why });
            n_stale += 1;
        }
    }
    std.debug.print("\nprofiles(subset): {d} golden, {d} allowlisted, {d} reject-both, {d} uncovered\n", .{ n_golden, n_allow, n_rej, n_uncovered });
    try std.testing.expectEqual(@as(usize, 0), n_stale);
    try std.testing.expectEqual(@as(usize, 0), n_uncovered);
}
