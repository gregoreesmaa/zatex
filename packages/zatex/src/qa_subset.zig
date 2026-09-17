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
    // Issue #73 symbol batch first, longest-first: hasMarker returns
    // the FIRST hit, so a general marker (e.g. `\triangle`) must never
    // precede a specific one it shadows (`\triangledown`) or the
    // shadowed entry reads stale. Keep this order when adding rows.
    .{ .mark = "\\leftrightsquigarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\blacktriangleright", .why = "AMS relations are full-only" },
    .{ .mark = "\\blacktriangledown", .why = "textord symbols are full-only" },
    .{ .mark = "\\blacktriangleleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\leftrightharpoons", .why = "AMS relations are full-only" },
    .{ .mark = "\\scriptscriptstyle", .why = "style declarations are full-only" },
    .{ .mark = "\\twoheadrightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\circlearrowright", .why = "AMS relations are full-only" },
    .{ .mark = "\\downharpoonright", .why = "AMS relations are full-only" },
    .{ .mark = "\\ntrianglerighteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\rightrightarrows", .why = "AMS relations are full-only" },
    .{ .mark = "\\twoheadleftarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\vartriangleright", .why = "AMS relations are full-only" },
    .{ .mark = "\\circlearrowleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\curvearrowright", .why = "AMS relations are full-only" },
    .{ .mark = "\\downharpoonleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\leftrightarrows", .why = "AMS relations are full-only" },
    .{ .mark = "\\nLeftrightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\nleftrightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\ntrianglelefteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\rightleftarrows", .why = "AMS relations are full-only" },
    .{ .mark = "\\rightsquigarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\rightthreetimes", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\trianglerighteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\vartriangleleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\curvearrowleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\dashrightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\doublebarwedge", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\downdownarrows", .why = "AMS relations are full-only" },
    .{ .mark = "\\leftleftarrows", .why = "AMS relations are full-only" },
    .{ .mark = "\\leftthreetimes", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\looparrowright", .why = "AMS relations are full-only" },
    .{ .mark = "\\ntriangleright", .why = "AMS relations are full-only" },
    .{ .mark = "\\providecommand", .why = "macro definitions are full-only" },
    .{ .mark = "\\rightarrowtail", .why = "AMS relations are full-only" },
    .{ .mark = "\\trianglelefteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\upharpoonright", .why = "AMS relations are full-only" },
    .{ .mark = "\\blacktriangle", .why = "textord symbols are full-only" },
    .{ .mark = "\\dashleftarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\divideontimes", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\fallingdotseq", .why = "AMS relations are full-only" },
    .{ .mark = "\\leftarrowtail", .why = "AMS relations are full-only" },
    .{ .mark = "\\looparrowleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\ntriangleleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\shortparallel", .why = "AMS relations are full-only" },
    .{ .mark = "\\smallsetminus", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\upharpoonleft", .why = "AMS relations are full-only" },
    .{ .mark = "\\blacklozenge", .why = "textord symbols are full-only" },
    .{ .mark = "\\displaystyle", .why = "style declarations are full-only" },
    .{ .mark = "\\mathellipsis", .why = "inner symbols are full-only" },
    .{ .mark = "\\mathsterling", .why = "textord symbols are full-only" },
    .{ .mark = "\\nobreakspace", .why = "spacing symbols are full-only" },
    .{ .mark = "\\operatorname", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\renewcommand", .why = "macro definitions are full-only" },
    .{ .mark = "\\risingdotseq", .why = "AMS relations are full-only" },
    .{ .mark = "\\triangledown", .why = "textord symbols are full-only" },
    .{ .mark = "\\underbracket", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\Rrightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\backepsilon", .why = "AMS relations are full-only" },
    .{ .mark = "\\blacksquare", .why = "textord symbols are full-only" },
    .{ .mark = "\\circledcirc", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\circleddash", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\curlyeqprec", .why = "AMS relations are full-only" },
    .{ .mark = "\\curlyeqsucc", .why = "AMS relations are full-only" },
    .{ .mark = "\\eqslantless", .why = "AMS relations are full-only" },
    .{ .mark = "\\nRightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\nrightarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\overbracket", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\preccurlyeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\precnapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\restriction", .why = "AMS relations are full-only" },
    .{ .mark = "\\scriptstyle", .why = "style declarations are full-only" },
    .{ .mark = "\\succcurlyeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\succnapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\textcircled", .why = "math-mode circled is full-only" },
    .{ .mark = "\\thickapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\vartriangle", .why = "AMS relations are full-only" },
    .{ .mark = "\\Lleftarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\circledast", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\complement", .why = "textord symbols are full-only" },
    .{ .mark = "\\curlywedge", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\eqslantgtr", .why = "AMS relations are full-only" },
    .{ .mark = "\\gtreqqless", .why = "AMS relations are full-only" },
    .{ .mark = "\\lesseqqgtr", .why = "AMS relations are full-only" },
    .{ .mark = "\\longmapsto", .why = "AMS relations are full-only" },
    .{ .mark = "\\mathchoice", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\nLeftarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\newcommand", .why = "macro definitions are full-only" },
    .{ .mark = "\\nleftarrow", .why = "AMS relations are full-only" },
    .{ .mark = "\\precapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\smallfrown", .why = "AMS relations are full-only" },
    .{ .mark = "\\smallsmile", .why = "AMS relations are full-only" },
    .{ .mark = "\\subsetneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\succapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\supsetneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\upuparrows", .why = "AMS relations are full-only" },
    .{ .mark = "\\textcopyright", .why = "textord symbols are full-only" },
    .{ .mark = "\\@secondoftwo", .why = "selector macros are full-only" },
    .{ .mark = "\\@firstoftwo", .why = "selector macros are full-only" },
    .{ .mark = "\\@ifnextchar", .why = "selector macros are full-only" },
    .{ .mark = "\\TextOrMath", .why = "selector macros are full-only" },
    .{ .mark = "\\@ifstar", .why = "selector macros are full-only" },
    .{ .mark = "\\copyright", .why = "textord symbols are full-only" },
    .{ .mark = "\\mathpunct", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\htmlClass", .why = "html extensions are full-only" },
    .{ .mark = "\\htmlStyle", .why = "html extensions are full-only" },
    .{ .mark = "\\backsimeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\doublecap", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\doublecup", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\gtreqless", .why = "AMS relations are full-only" },
    .{ .mark = "\\lesseqgtr", .why = "AMS relations are full-only" },
    .{ .mark = "\\nparallel", .why = "AMS relations are full-only" },
    .{ .mark = "\\nsubseteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\nsupseteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\overbrace", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\pitchfork", .why = "AMS relations are full-only" },
    .{ .mark = "\\subseteqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\supseteqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\textcolor", .why = "scoped color is full-only" },
    .{ .mark = "\\textstyle", .why = "style declarations are full-only" },
    .{ .mark = "\\therefore", .why = "AMS relations are full-only" },
    .{ .mark = "\\triangleq", .why = "AMS relations are full-only" },
    .{ .mark = "\\overlinesegment", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\underlinesegment", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\underline", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\varpropto", .why = "AMS relations are full-only" },
    .{ .mark = "\\widecheck", .why = "math accents are full-only" },
    .{ .mark = "\\widetilde", .why = "math accents are full-only" },
    .{ .mark = "\\htmlData", .why = "html extensions are full-only" },
    .{ .mark = "\\barwedge", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\bigsqcup", .why = "large-operator symbols are full-only" },
    .{ .mark = "\\curlyvee", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\diagdown", .why = "textord symbols are full-only" },
    .{ .mark = "\\doteqdot", .why = "AMS relations are full-only" },
    .{ .mark = "\\geqslant", .why = "AMS relations are full-only" },
    .{ .mark = "\\gnapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\intercal", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\leqslant", .why = "AMS relations are full-only" },
    .{ .mark = "\\lnapprox", .why = "AMS relations are full-only" },
    .{ .mark = "\\mathring", .why = "math accents are full-only" },
    .{ .mark = "\\multimap", .why = "AMS relations are full-only" },
    .{ .mark = "\\noexpand", .why = "expansion primitives are full-only" },
    .{ .mark = "\\overline", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\precneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\precnsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\raisebox", .why = "smash/raisebox/rule are full-only" },
    .{ .mark = "\\shortmid", .why = "AMS relations are full-only" },
    .{ .mark = "\\smallint", .why = "large-operator symbols are full-only" },
    .{ .mark = "\\substack", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\succneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\succnsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\thicksim", .why = "AMS relations are full-only" },
    .{ .mark = "\\triangle", .why = "textord symbols are full-only" },
    .{ .mark = "\\varkappa", .why = "textord symbols are full-only" },
    .{ .mark = "\\hphantom", .why = "phantoms are full-only" },
    .{ .mark = "\\bcancel", .why = "cancel/lap are full-only" },
    .{ .mark = "\\xmapsto", .why = "extensible arrows are full-only" },
    .{ .mark = "\\Diamond", .why = "textord symbols are full-only" },
    .{ .mark = "\\backsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\because", .why = "AMS relations are full-only" },
    .{ .mark = "\\between", .why = "AMS relations are full-only" },
    .{ .mark = "\\bigcirc", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\bigstar", .why = "textord symbols are full-only" },
    .{ .mark = "\\dotplus", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\genfrac", .why = "generalized fractions are full-only" },
    .{ .mark = "\\gtrless", .why = "AMS relations are full-only" },
    .{ .mark = "\\imageof", .why = "AMS relations are full-only" },
    .{ .mark = "\\leadsto", .why = "AMS relations are full-only" },
    .{ .mark = "\\lessdot", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\lessgtr", .why = "AMS relations are full-only" },
    .{ .mark = "\\lozenge", .why = "textord symbols are full-only" },
    .{ .mark = "\\npreceq", .why = "AMS relations are full-only" },
    .{ .mark = "\\nsucceq", .why = "AMS relations are full-only" },
    .{ .mark = "\\omicron", .why = "mathord symbols are full-only" },
    .{ .mark = "\\overset", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\phantom", .why = "phantoms are full-only" },
    .{ .mark = "\\precsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\succsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\vcenter", .why = "vcenter/phase are full-only" },
    .{ .mark = "\\widehat", .why = "math accents are full-only" },
    .{ .mark = "colorbox", .why = "background boxes are full-only" },
    .{ .mark = "\\Bumpeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\Subset", .why = "AMS relations are full-only" },
    .{ .mark = "\\Supset", .why = "AMS relations are full-only" },
    .{ .mark = "\\Vvdash", .why = "AMS relations are full-only" },
    .{ .mark = "\\bumpeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\cancel", .why = "cancel/lap are full-only" },
    .{ .mark = "\\xcancel", .why = "cancel/lap are full-only" },
    .{ .mark = "\\circeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\ddddot", .why = "math accents are full-only" },
    .{ .mark = "\\degree", .why = "textord symbols are full-only" },
    .{ .mark = "\\diagup", .why = "textord symbols are full-only" },
    .{ .mark = "\\gtrdot", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\llless", .why = "AMS relations are full-only" },
    .{ .mark = "\\ltimes", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\nVDash", .why = "AMS relations are full-only" },
    .{ .mark = "\\nVdash", .why = "AMS relations are full-only" },
    .{ .mark = "\\nvDash", .why = "AMS relations are full-only" },
    .{ .mark = "\\nvdash", .why = "AMS relations are full-only" },
    .{ .mark = "\\oiiint", .why = "large-operator symbols are full-only" },
    .{ .mark = "\\origof", .why = "AMS relations are full-only" },
    .{ .mark = "\\rtimes", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\square", .why = "textord symbols are full-only" },
    .{ .mark = "\\veebar", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\biggl", .why = "sized fences are full-only" },
    .{ .mark = "\\biggr", .why = "sized fences are full-only" },
    .{ .mark = "\\htmlId", .why = "html extensions are full-only" },
    .{ .mark = "\\Doteq", .why = "AMS relations are full-only" },
    .{ .mark = "\\Vdash", .why = "AMS relations are full-only" },
    .{ .mark = "\\begingroup", .why = "scoping is full-only" },
    .{ .mark = "\\above", .why = "infix fractions are full-only" },
    .{ .mark = "\\hbox", .why = "boxes are full-only" },
    .{ .mark = "\\mathreflectbox", .why = "boxes are full-only" },
    .{ .mark = "\\reflectbox", .why = "boxes are full-only" },
    .{ .mark = "\\set", .why = "set notation is full-only" },
    .{ .mark = "\\Set", .why = "set notation is full-only (issue #89)" },
    .{ .mark = "\\Braket", .why = "braket notation is full-only (issue #84)" },
    .{ .mark = "\\braket", .why = "braket notation is full-only (issue #84)" },
    .{ .mark = "\\varinjlim", .why = "limit variants are full-only" },
    .{ .mark = "\\varliminf", .why = "limit variants are full-only" },
    .{ .mark = "\\varlimsup", .why = "limit variants are full-only" },
    .{ .mark = "\\varprojlim", .why = "limit variants are full-only" },
    .{ .mark = "\\overgroup", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\overleftharpoon", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\Overrightarrow", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\overrightharpoon", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\underbar", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\undergroup", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\utilde", .why = "over/under-constructs are full-only" },
    .{ .mark = "\\begin", .why = "environments are full-only" },
    .{ .mark = "\\boxed", .why = "boxes are full-only" },
    .{ .mark = "\\color", .why = "color specs are full-only" },
    .{ .mark = "\\dddot", .why = "math accents are full-only" },
    .{ .mark = "\\eqsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\gggtr", .why = "AMS relations are full-only" },
    .{ .mark = "\\gneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\gnsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\intop", .why = "large-operator symbols are full-only" },
    .{ .mark = "\\lneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\lnsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\ncong", .why = "AMS relations are full-only" },
    .{ .mark = "\\nless", .why = "AMS relations are full-only" },
    .{ .mark = "\\nprec", .why = "AMS relations are full-only" },
    .{ .mark = "\\nsucc", .why = "AMS relations are full-only" },
    .{ .mark = "\\oiint", .why = "large-operator symbols are full-only" },
    .{ .mark = "\\phase", .why = "vcenter/phase are full-only" },
    .{ .mark = "\\smash", .why = "smash/raisebox/rule are full-only" },
    .{ .mark = "\\space", .why = "spacing symbols are full-only" },
    .{ .mark = "\\tilde", .why = "math accents are full-only" },
    .{ .mark = "\\vDash", .why = "AMS relations are full-only" },
    .{ .mark = "\\KaTeX", .why = "logo macros are full-only" },
    .{ .mark = "\\LaTeX", .why = "logo macros are full-only" },
    .{ .mark = "\\colon", .why = "spacing macros are full-only" },
    .{ .mark = "\\gdef", .why = "macro definitions are full-only" },
    .{ .mark = "\\geqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\gneq", .why = "AMS relations are full-only" },
    .{ .mark = "\\href", .why = "hyperlinks are full-only" },
    .{ .mark = "\\includegraphics", .why = "graphics are full-only" },
    .{ .mark = "\\stackrel", .why = "stackrel is full-only" },
    .{ .mark = "\\left", .why = "sized fences are full-only" },
    .{ .mark = "\\leqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\lneq", .why = "AMS relations are full-only" },
    .{ .mark = "\\ngeq", .why = "AMS relations are full-only" },
    .{ .mark = "\\ngtr", .why = "AMS relations are full-only" },
    .{ .mark = "\\nleq", .why = "AMS relations are full-only" },
    .{ .mark = "\\nsim", .why = "AMS relations are full-only" },
    .{ .mark = "\\rule", .why = "smash/raisebox/rule are full-only" },
    .{ .mark = "\\sout", .why = "strikeout is full-only" },
    .{ .mark = "\\verb", .why = "verbatim is full-only" },
    .{ .mark = "\\xleftharpoondown", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xleftharpoonup", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xleftrightharpoons", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xlongequal", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xrightharpoondown", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xrightharpoonup", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xrightleftharpoons", .why = "extensible arrows are full-only" },
    .{ .mark = "\\xtofrom", .why = "extensible arrows are full-only" },
    .{ .mark = "arrow", .why = "extensible arrows are full-only" },
    .{ .mark = "\\angln", .why = "actuarial symbols are full-only" },
    .{ .mark = "\\angl", .why = "actuarial symbols are full-only" },
    .{ .mark = "\\lBrace", .why = "white-brace delimiters are full-only" },
    .{ .mark = "\\rBrace", .why = "white-brace delimiters are full-only" },
    .{ .mark = "\\minuso", .why = "composed operators are full-only" },
    .{ .mark = "\\bmod", .why = "mod operators are full-only" },
    .{ .mark = "\\pmod", .why = "mod operators are full-only" },
    .{ .mark = "\\pod", .why = "mod operators are full-only" },
    .{ .mark = "\\And", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\Big", .why = "unsized big fences are full-only" },
    .{ .mark = "\\Box", .why = "textord symbols are full-only" },
    .{ .mark = "\\Cap", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\Cup", .why = "AMS binary operators are full-only" },
    .{ .mark = "\\Lsh", .why = "AMS relations are full-only" },
    .{ .mark = "\\Rsh", .why = "AMS relations are full-only" },

    .{ .mark = "\\def", .why = "macro definitions are full-only" },
    .{ .mark = "\\hat", .why = "math accents are full-only" },
    .{ .mark = "\\let", .why = "macro definitions are full-only" },
    .{ .mark = "\\not", .why = "negation is full-only" },
    .{ .mark = "\\tag", .why = "equation tags are full-only" },
    .{ .mark = "\\url", .why = "hyperlinks are full-only" },
    .{ .mark = "\\vec", .why = "math accents are full-only" },
    .{ .mark = "\\mathclap", .why = "cancel/lap are full-only" },
    .{ .mark = "\\rlap", .why = "cancel/lap are full-only" },
    .{ .mark = "llap", .why = "cancel/lap are full-only" },
    .{ .mark = "\\fbox", .why = "boxes are full-only" },
    .{ .mark = "\\gt", .why = "AMS relations are full-only" },
    .{ .mark = "\\lt", .why = "AMS relations are full-only" },
    .{ .mark = "\\TeX", .why = "logo macros are full-only" },
    // Issue #73 symbol batch (appended longest-first: `hasMarker`
    // returns the first substring hit, so e.g. `\varsubsetneqq` must
    // precede `\varsubsetneq`, `\Reals` precede `\R`, `\sube`
    // precede `\sub`). Classes pinned against KaTeX 0.18.7 MathML;
    // `alias spellings` marks names whose codepoint the subset
    // profile already covers under another (base-table) name.
    .{ .mark = "\\nshortparallel", .why = "AMS relations are full-only" },
    .{ .mark = "\\varsubsetneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\varsupsetneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\varsubsetneq", .why = "alias spellings are full-only" },
    .{ .mark = "\\varsupsetneq", .why = "alias spellings are full-only" },
    .{ .mark = "\\varUpsilon", .why = "alias spellings are full-only" },
    .{ .mark = "\\llbracket", .why = "delimiters are full-only" },
    .{ .mark = "\\impliedby", .why = "spacing macros are full-only" },
    .{ .mark = "\\lvertneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\nshortmid", .why = "alias spellings are full-only" },
    .{ .mark = "\\rrbracket", .why = "delimiters are full-only" },
    .{ .mark = "\\varLambda", .why = "alias spellings are full-only" },
    .{ .mark = "\\gvertneqq", .why = "AMS relations are full-only" },
    .{ .mark = "\\mapsfrom", .why = "AMS relations are full-only" },
    .{ .mark = "\\thetasym", .why = "alias spellings are full-only" },
    .{ .mark = "\\varDelta", .why = "alias spellings are full-only" },
    .{ .mark = "\\varGamma", .why = "alias spellings are full-only" },
    .{ .mark = "\\varOmega", .why = "alias spellings are full-only" },
    .{ .mark = "\\varSigma", .why = "alias spellings are full-only" },
    .{ .mark = "\\varTheta", .why = "alias spellings are full-only" },
    .{ .mark = "\\Complex", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\Omicron", .why = "mathord symbols are full-only" },
    .{ .mark = "\\alefsym", .why = "alias spellings are full-only" },
    .{ .mark = "\\diamonds", .why = "alias spellings are full-only" },
    .{ .mark = "\\natnums", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\implies", .why = "spacing macros are full-only" },
    .{ .mark = "\\weierp", .why = "alias spellings are full-only" },
    .{ .mark = "\\Dagger", .why = "alias spellings are full-only" },
    .{ .mark = "\\hearts", .why = "alias spellings are full-only" },
    .{ .mark = "\\spades", .why = "alias spellings are full-only" },
    .{ .mark = "\\plusmn", .why = "alias spellings are full-only" },
    .{ .mark = "\\varPhi", .why = "alias spellings are full-only" },
    .{ .mark = "\\varPsi", .why = "alias spellings are full-only" },
    .{ .mark = "\\Bbbk", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\Lrarr", .why = "alias spellings are full-only" },
    .{ .mark = "\\Reals", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\clubs", .why = "alias spellings are full-only" },
    .{ .mark = "\\cnums", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\dotsb", .why = "alias spellings are full-only" },
    .{ .mark = "\\dotsc", .why = "alias spellings are full-only" },
    .{ .mark = "\\dotsm", .why = "alias spellings are full-only" },
    .{ .mark = "\\dotso", .why = "alias spellings are full-only" },
    .{ .mark = "\\empty", .why = "alias spellings are full-only" },
    .{ .mark = "\\exist", .why = "alias spellings are full-only" },
    .{ .mark = "\\image", .why = "alias spellings are full-only" },
    .{ .mark = "\\infin", .why = "alias spellings are full-only" },
    .{ .mark = "\\lrArr", .why = "alias spellings are full-only" },
    .{ .mark = "\\lrarr", .why = "alias spellings are full-only" },
    .{ .mark = "\\reals", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\varPi", .why = "alias spellings are full-only" },
    .{ .mark = "\\varXi", .why = "alias spellings are full-only" },
    .{ .mark = "\\Darr", .why = "alias spellings are full-only" },
    .{ .mark = "\\Harr", .why = "alias spellings are full-only" },
    .{ .mark = "\\Larr", .why = "alias spellings are full-only" },
    .{ .mark = "\\Rarr", .why = "alias spellings are full-only" },
    .{ .mark = "\\Uarr", .why = "alias spellings are full-only" },
    .{ .mark = "\\alef", .why = "alias spellings are full-only" },
    .{ .mark = "\\bull", .why = "alias spellings are full-only" },
    .{ .mark = "\\dArr", .why = "alias spellings are full-only" },
    .{ .mark = "\\darr", .why = "alias spellings are full-only" },
    .{ .mark = "\\hArr", .why = "alias spellings are full-only" },
    .{ .mark = "\\harr", .why = "alias spellings are full-only" },
    .{ .mark = "\\isin", .why = "alias spellings are full-only" },
    .{ .mark = "\\lArr", .why = "alias spellings are full-only" },
    .{ .mark = "\\larr", .why = "alias spellings are full-only" },
    .{ .mark = "\\rArr", .why = "alias spellings are full-only" },
    .{ .mark = "\\rarr", .why = "alias spellings are full-only" },
    .{ .mark = "\\real", .why = "alias spellings are full-only" },
    .{ .mark = "\\sdot", .why = "alias spellings are full-only" },
    .{ .mark = "\\sube", .why = "alias spellings are full-only" },
    .{ .mark = "\\supe", .why = "alias spellings are full-only" },
    .{ .mark = "\\uArr", .why = "alias spellings are full-only" },
    .{ .mark = "\\uarr", .why = "alias spellings are full-only" },
    .{ .mark = "\\iff", .why = "spacing macros are full-only" },
    .{ .mark = "\\sub", .why = "alias spellings are full-only" },
    .{ .mark = "\\lq", .why = "mathord symbols are full-only" },
    .{ .mark = "\\rq", .why = "prime-quote symbols are full-only" },
    .{ .mark = "\\N", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\R", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\Z", .why = "blackboard symbols are full-only" },
    .{ .mark = "\\plim", .why = "operatorname/substack/mathchoice are full-only" },
    .{ .mark = "\\mathbin", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\mathclose", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\mathopen", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\mathord", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\footnotesize", .why = "size commands are full-only" },
    .{ .mark = "\\normalsize", .why = "size commands are full-only" },
    .{ .mark = "\\scriptsize", .why = "size commands are full-only" },
    .{ .mark = "\\sixptsize", .why = "size commands are full-only" },
    .{ .mark = "\\LARGE", .why = "size commands are full-only" },
    .{ .mark = "\\Large", .why = "size commands are full-only" },
    .{ .mark = "\\large", .why = "size commands are full-only" },
    .{ .mark = "\\small", .why = "size commands are full-only" },
    .{ .mark = "\\Huge", .why = "size commands are full-only" },
    .{ .mark = "\\huge", .why = "size commands are full-only" },
    .{ .mark = "\\tiny", .why = "size commands are full-only" },
    // Colon-family batch (mathtools `\\html@mathml` alternates via
    // `\\char`, plus `\\vcentcolon`/`\\mathop`/`\\mathinner`; the
    // lowercase `\\colon*` pairs ride the existing `\\colon` marker.
    // Longest-first per the list rule above.
    .{ .mark = "\\approxcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\equalscolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\eqqcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\eqcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\minuscolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\vcentcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\Eqqcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\dblcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\simcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\Eqcolon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\mathinner", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\mathop", .why = "atom-class wrappers are full-only" },
    .{ .mark = "\\Colon", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\ratio", .why = "colon-pair macros are full-only" },
    .{ .mark = "\\char", .why = "char primitives are full-only" },
};

fn hasMarker(tex: []const u8) ?usize {
    for (full_only_markers, 0..) |m, k| {
        if (std.mem.indexOf(u8, tex, m.mark) != null) return k;
    }
    return null;
}

fn expectUnsupportedName(name: []const u8) !void {
    var src: [64]u8 = undefined;
    src[0] = '\\';
    @memcpy(src[1 .. 1 + name.len], name);
    var b: B = .{};
    try std.testing.expectError(error.Unsupported, lay(src[0 .. 1 + name.len], false, &b));
}

test "qa45s full-only names fail Unsupported in subset" {
    // Pins the `full_only` stripping contract: every stripped command
    // fails with `Unsupported` (never `Invalid`), so hosts keep their
    // fallback behavior byte-for-byte. Explicit lists come straight
    // from `parse.full_only_*_names`; predicate families (accents,
    // over-constructs, big fences) share their dispatch predicates,
    // so samples pin the wiring.
    for (parse.full_only_def_names) |n| try expectUnsupportedName(n);
    for (parse.full_only_ctrl_names) |n| try expectUnsupportedName(n);
    for ([_][]const u8{
        "hat", "tilde", "vec", "bar", "dot", "ddot", "acute", "grave",
        "breve", "check", "widehat", "widetilde", "overline",
        "underline", "overbrace", "underbrace", "overleftarrow",
        "overrightarrow", "xleftarrow", "xrightarrow", "big", "Big",
        "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl",
        "biggr", "bigm", "Bigm",
    }) |n| try expectUnsupportedName(n);
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




