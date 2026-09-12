//! MaTeX layout core: AST → box tree → IR runs/rules.
//!
//! The only place layout math lives (AGENTS.md §2): inter-atom glue,
//! script shifts, fraction/radical/delimiter geometry, table grids.
//! Emitters (IR flattening here, MathML elsewhere) are thin walkers.
//!
//! All positions are integer font units at the ambient size (1000 =
//! 1 em). Glyph advances come from the host provider and scale with
//! size; shifts and clearances are fixed thousandths-of-em constants
//! documented at each site (TeX-derived, simplified micro-typography).
const std = @import("std");
const contract = @import("contract.zig");
const ir = @import("ir.zig");
const parse = @import("parse.zig");
const symbols = @import("symbols.zig");

const Error = contract.LayoutError;
const Idx = parse.Idx;
const NONE = parse.NONE;

// ---------------------------------------------------------------------------
// Boxes
// ---------------------------------------------------------------------------

pub const BKid = struct {
    box: u16,
    dx: i32,
    /// Baseline shift UP from the parent baseline (may be negative).
    dy: i32,
};

pub const BoxKind = union(enum) {
    glyph: struct {
        font: u16,
        size: u16,
        glyph: u16,
    },
    kern: void,
    rule: void,
    list: parse.Range,
    empty: void,
};

pub const Box = struct {
    w: i32,
    ha: i32,
    db: i32,
    kind: BoxKind,
    /// Phantom subtrees keep their dimensions but emit nothing.
    invisible: bool = false,
};

pub const max_boxes: usize = 640;
pub const max_bkids: usize = 1536;

pub const LayCtx = struct {
    boxes: [max_boxes]Box = undefined,
    nboxes: u16 = 0,
    bkids: [max_bkids]BKid = undefined,
    nbkids: u16 = 0,
    pctx: *const parse.ParseCtx,
    provider: contract.MetricsProvider,
    /// Minimum fence height requested by an enclosing `\left..\right`
    /// (consumed by `\middle`), in font units.
    fence_need: i32 = 0,
    /// Nearest enclosing font override (`\mathrm{...}` etc.).
    fam_subst: ?parse.FontFam = null,

    pub fn init(pctx: *const parse.ParseCtx, provider: contract.MetricsProvider) LayCtx {
        return .{ .pctx = pctx, .provider = provider };
    }

    fn allocBox(self: *LayCtx, b: Box) Error!u16 {
        if (self.nboxes >= max_boxes) return error.NoSpace;
        const id = self.nboxes;
        self.boxes[id] = b;
        self.nboxes += 1;
        return id;
    }

    fn allocKids(self: *LayCtx, n: usize) Error!u16 {
        if (n > max_bkids - self.nbkids) return error.NoSpace;
        const s = self.nbkids;
        self.nbkids += @intCast(n);
        return s;
    }

    fn glyphId(self: *LayCtx, font: u16, cp: u21) u16 {
        return self.provider.glyphId(self.provider.ctx, font, cp);
    }
    fn advance(self: *LayCtx, font: u16, glyph: u16) i32 {
        return self.provider.advance(self.provider.ctx, font, glyph);
    }
    fn ruleTh(self: *LayCtx, font: u16, kind: contract.RuleKind) i32 {
        const v = self.provider.ruleThickness(self.provider.ctx, font, kind);
        return if (v <= 0) 40 else v;
    }
    fn variant(self: *LayCtx, font: u16, glyph: u16, need: i32) u16 {
        if (self.provider.glyphVariant) |f| return f(self.provider.ctx, font, glyph, need);
        return glyph;
    }
    fn italicCorr(self: *LayCtx, font: u16, glyph: u16) i32 {
        if (self.provider.italicCorrection) |f| return f(self.provider.ctx, font, glyph);
        return 0;
    }
    fn extents(self: *LayCtx, font: u16, glyph: u16) [2]i32 {
        if (self.provider.extents) |f| return f(self.provider.ctx, font, glyph);
        return .{ 700, 250 };
    }
};

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

/// Lay out a parsed formula root into caller buffers.
pub fn layout(
    lc: *LayCtx,
    root: Idx,
    style: parse.Style,
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
) Error!ir.Layout {
    const box = try layoutNode(lc, style, root);
    const b = lc.boxes[box];
    var ec = EmitCtx{ .runs = runs, .rules = rules, .glyphs = glyphs };
    // Origin top-left; the root baseline sits at height_above.
    try emitBox(lc, &ec, box, 0, b.ha);
    ec.closeRun();
    return .{
        .width = if (b.w < 0) 0 else @intCast(b.w),
        .height_above = if (b.ha < 0) 0 else @intCast(b.ha),
        .depth_below = if (b.db < 0) 0 else @intCast(b.db),
        .runs = ec.runs[0..ec.nr],
        .rules = ec.rules[0..ec.nl],
    };
}

// ---------------------------------------------------------------------------
// Node layout
// ---------------------------------------------------------------------------

fn layoutNode(lc: *LayCtx, style: parse.Style, id: Idx) Error!u16 {
    const n = parse.nodeAt(lc.pctx, id);
    switch (n) {
        .atom => |a| return layoutAtom(lc, style, a.class, effFont(lc, a.font), a.cp),
        .op => |o| return layoutOp(lc, style, o),
        .opname => |o| return layoutOpName(lc, style, o),
        .group => |g| return layoutGroup(lc, style, g),
        .frac => |f| return layoutFrac(lc, style, f),
        .sqrt => |s| return layoutSqrt(lc, style, s),
        .supsub => |s| return layoutSupSub(lc, style, s),
        .delim => |d| return layoutDelim(lc, style, d),
        .middle => |m| return layoutFence(lc, style, m.cp, lc.fence_need),
        .big => |b| return layoutBig(lc, style, b),
        .accent => |a| return layoutAccent(lc, style, a),
        .over => |o| return layoutOver(lc, style, o),
        .style => |s| return layoutNode(lc, s.style, s.body),
        .font => |f| {
            const prev = lc.fam_subst;
            lc.fam_subst = f.fam;
            const b = try layoutNode(lc, style, f.body);
            lc.fam_subst = prev;
            return b;
        },
        .text => |t| return layoutText(lc, style, t),
        .env => |e| return layoutEnv(lc, style, e),
        .substack => |r| return layoutSubstack(lc, style, r),
        .mathchoice => |c| {
            const k: usize = switch (style) {
                .D, .Dc => 0,
                .T, .Tc => 1,
                .S, .Sc => 2,
                .SS, .SSc => 3,
            };
            return layoutNode(lc, style, c[k]);
        },
        .space => |u| return lc.allocBox(.{
            .w = scale(u, style),
            .ha = 0,
            .db = 0,
            .kind = .{ .kern = {} },
            .invisible = false,
        }),
        .vspace => |u| {
            const v = scale(u, style);
            return lc.allocBox(.{
                .w = 0,
                .ha = if (v > 0) v else 0,
                .db = if (v < 0) -v else 0,
                .kind = .{ .kern = {} },
                .invisible = false,
            });
        },
        .newline => return lc.allocBox(.{
            .w = 0,
            .ha = 0,
            .db = 0,
            .kind = .{ .kern = {} },
            .invisible = false,
        }),
        .hline => return lc.allocBox(.{
            .w = 0,
            .ha = 100,
            .db = 100,
            .kind = .{ .rule = {} },
            .invisible = false,
        }),
        .color => |b| return layoutNode(lc, style, b),
        .href => |h| return layoutNode(lc, style, h.body),
        .htmlwrap => |b| return layoutNode(lc, style, b),
        .phantom => |p| {
            const b = try layoutNode(lc, style, p.body);
            const bb = lc.boxes[b];
            return lc.allocBox(.{
                .w = if (p.keep_h) bb.w else 0,
                .ha = if (p.keep_v) bb.ha else 0,
                .db = if (p.keep_v) bb.db else 0,
                .kind = bb.kind,
                .invisible = true,
            });
        },
        .boxed => |b| return layoutBoxed(lc, style, b),
        .cancel => |b| return layoutCancel(lc, style, b),
        .lap => |l| return layoutLap(lc, style, l),
        .smash => |s| {
            const b = try layoutNode(lc, style, s.body);
            const bb = lc.boxes[b];
            return lc.allocBox(.{
                .w = bb.w,
                .ha = if (s.keep_t) bb.ha else 0,
                .db = if (s.keep_b) bb.db else 0,
                .kind = bb.kind,
                .invisible = bb.invisible,
            });
        },
        .raisebox => |r| {
            const b = try layoutNode(lc, style, r.body);
            const bb = lc.boxes[b];
            const dh = scale(r.dh, style);
            const s = try lc.allocKids(1);
            lc.bkids[s] = .{ .box = b, .dx = 0, .dy = dh };
            return lc.allocBox(.{
                .w = bb.w,
                .ha = bb.ha + dh,
                .db = bb.db - dh,
                .kind = .{ .list = .{ .start = s, .len = 1 } },
                .invisible = false,
            });
        },
        .rule => |r| return lc.allocBox(.{
            .w = scale(r.w, style),
            .ha = scale(r.h, style),
            .db = scale(r.dep, style),
            .kind = .{ .rule = {} },
            .invisible = false,
        }),
    }
}

/// Scale thousandths-of-em by the style size.
fn scale(u: i16, style: parse.Style) i32 {
    return @divTrunc(@as(i32, u) * style.sizeUnits(), 1000);
}

fn effFont(lc: *LayCtx, f: parse.FontFam) parse.FontFam {
    return lc.fam_subst orelse f;
}

fn layoutAtom(lc: *LayCtx, style: parse.Style, class: symbols.AtomClass, fam: parse.FontFam, cp: u21) Error!u16 {
    _ = class;
    const size = style.sizeUnits();
    const font = fam.id();
    const g = lc.glyphId(font, cp);
    const adv = lc.advance(font, g);
    const w = @divTrunc(adv * size, 1000);
    const e = lc.extents(font, g);
    return lc.allocBox(.{
        .w = w,
        .ha = @divTrunc(e[0] * size, 1000),
        .db = @divTrunc(e[1] * size, 1000),
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
}

/// Jennings-style row layout with inter-atom glue and Bin degradation.
fn layoutGroup(lc: *LayCtx, style: parse.Style, g: parse.Range) Error!u16 {
    const kids = parse.kidsOf(lc.pctx, g);
    // Count first for a single kids allocation.
    var parts: [512]BKid = undefined;
    var nparts: usize = 0;
    var x: i32 = 0;
    var ha: i32 = 0;
    var db: i32 = 0;
    var prev: ?symbols.AtomClass = null;
    var i: usize = 0;
    while (i < kids.len) : (i += 1) {
        const id = kids[i];
        const cls = classOf(lc.pctx, id);
        if (cls) |c| {
            var eff = c;
            if (eff == .Bin and symbols.degradeBin(prev)) eff = .Ord;
            if (prev) |p| {
                const gl = @divTrunc(@as(i32, symbols.glueBetween(p, eff)) * style.sizeUnits(), 1000);
                if (gl != 0) {
                    const kb = try lc.allocBox(.{
                        .w = gl,
                        .ha = 0,
                        .db = 0,
                        .kind = .{ .kern = {} },
                        .invisible = false,
                    });
                    if (nparts >= 512) return error.NoSpace;
                    parts[nparts] = .{ .box = kb, .dx = x, .dy = 0 };
                    nparts += 1;
                    x += gl;
                }
            }
            const b = try layoutNode(lc, style, id);
            const bb = lc.boxes[b];
            if (nparts >= 512) return error.NoSpace;
            parts[nparts] = .{ .box = b, .dx = x, .dy = 0 };
            nparts += 1;
            x += bb.w;
            if (bb.ha > ha) ha = bb.ha;
            if (bb.db > db) db = bb.db;
            prev = eff;
        } else {
            // Transparent glue: layout without touching adjacency.
            const b = try layoutNode(lc, style, id);
            const bb = lc.boxes[b];
            if (nparts >= 512) return error.NoSpace;
            parts[nparts] = .{ .box = b, .dx = x, .dy = 0 };
            nparts += 1;
            x += bb.w;
            if (bb.ha > ha) ha = bb.ha;
            if (bb.db > db) db = bb.db;
        }
    }
    const s = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s .. s + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = x,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

/// Spacing class of a node, or null for transparent glue.
fn classOf(pc: *const parse.ParseCtx, id: Idx) ?symbols.AtomClass {
    const n = parse.nodeAt(pc, id);
    switch (n) {
        .atom => |a| return a.class,
        .op => return .Op,
        .opname => return .Op,
        // Braced groups act as Ord (TeX Book p.170).
        .group => return .Ord,
        .frac => return .Inner,
        .sqrt => return .Ord,
        .supsub => |s| return classOf(pc, s.base),
        .delim => return .Inner,
        .middle => return .Rel,
        .big => |b| return b.class,
        .accent => |a| return classOf(pc, a.nucleus) orelse .Ord,
        .over => return .Ord,
        .style => |s| return classOf(pc, s.body),
        .font => |f| return classOf(pc, f.body),
        .text => return .Ord,
        .env => return .Ord,
        .substack => return .Ord,
        .mathchoice => return .Ord,
        .space, .vspace, .newline => return null,
        .hline => return null,
        .color => |b| return classOf(pc, b),
        .href => |h| return classOf(pc, h.body),
        .htmlwrap => |b| return classOf(pc, b),
        .phantom => |p| return classOf(pc, p.body),
        .boxed => return .Ord,
        .cancel => |b| return classOf(pc, b),
        .lap => |l| return classOf(pc, l.body),
        .smash => |s| return classOf(pc, s.body),
        .raisebox => |r| return classOf(pc, r.body),
        .rule => return .Ord,
    }
}

fn layoutOp(lc: *LayCtx, style: parse.Style, o: anytype) Error!u16 {
    if (o.func) {
        // Word operator in roman (`sin`, `lim`, ...).
        return layoutWord(lc, style.sizeUnits(), .rm, o.text);
    }
    // Single-glyph operator, possibly large.
    const size: u16 = if (o.large and style.isDisplay())
        @intCast(@divTrunc(@as(i32, style.sizeUnits()) * 14, 10))
    else
        style.sizeUnits();
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g = lc.glyphId(font, o.cp);
    const adv = lc.advance(font, g);
    const e = lc.extents(font, g);
    return lc.allocBox(.{
        .w = @divTrunc(adv * size, 1000),
        .ha = @divTrunc(e[0] * size, 1000),
        .db = @divTrunc(e[1] * size, 1000),
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
}

/// Lay out word glyphs as a single box; returns the box id.
fn layoutWord(lc: *LayCtx, size: u16, fam: parse.FontFam, text: []const u8) Error!u16 {
    const font = fam.id();
    var parts: [64]BKid = undefined;
    var nparts: usize = 0;
    var x: i32 = 0;
    var ha: i32 = 0;
    var db: i32 = 0;
    for (text) |c| {
        const g = lc.glyphId(font, c);
        const adv = lc.advance(font, g);
        const w = @divTrunc(adv * size, 1000);
        const e = lc.extents(font, g);
        const b = try lc.allocBox(.{
            .w = w,
            .ha = @divTrunc(e[0] * size, 1000),
            .db = @divTrunc(e[1] * size, 1000),
            .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
            .invisible = false,
        });
        if (nparts >= 64) return error.NoSpace;
        parts[nparts] = .{ .box = b, .dx = x, .dy = 0 };
        nparts += 1;
        const bb = lc.boxes[b];
        x += bb.w;
        if (bb.ha > ha) ha = bb.ha;
        if (bb.db > db) db = bb.db;
    }
    const s = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s .. s + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = x,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

fn layoutOpName(lc: *LayCtx, style: parse.Style, o: anytype) Error!u16 {
    const size = style.sizeUnits();
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    const toks = parse.toksOf(lc.pctx, o.toks);
    for (toks) |tk| {
        switch (tk.kind) {
            .char => {
                if (tk.cp > 0x7F or n >= buf.len) return error.Invalid;
                buf[n] = @intCast(tk.cp);
                n += 1;
            },
            .ctrl => {
                if (tk.name.len != 1 or n >= buf.len) return error.Invalid;
                buf[n] = tk.name[0];
                n += 1;
            },
            else => return error.Invalid,
        }
    }
    return layoutWord(lc, size, .rm, buf[0..n]);
}

// ---------------------------------------------------------------------------
// Scripts, fractions, roots
// ---------------------------------------------------------------------------

/// Unwrap transparent nodes to find an operator base, if any.
fn opBase(pc: *const parse.ParseCtx, id: Idx) ?struct {
    cp: u21,
    large: bool,
    func: bool,
    limits: parse.LimitsMode,
    lim_def: bool,
} {
    var cur = id;
    while (true) {
        switch (parse.nodeAt(pc, cur)) {
            .op => |o| return .{
                .cp = o.cp,
                .large = o.large,
                .func = o.func,
                .limits = o.limits,
                .lim_def = o.lim_def,
            },
            .style => |s| cur = s.body,
            .font => |f| cur = f.body,
            .color => |b| cur = b,
            .href => |h| cur = h.body,
            .htmlwrap => |b| cur = b,
            else => return null,
        }
    }
}

/// Limit-vs-side decision for an operator base (KaTeX: `auto` stacks
/// above/below in display style for large ops and limit-words, and
/// goes to the side otherwise; `\limits`/`\nolimits` force it).
fn useLimits(style: parse.Style, o: anytype) bool {
    switch (o.limits) {
        .on => return true,
        .off => return false,
        .auto => return style.isDisplay() and (o.large or (o.func and o.lim_def)),
    }
}

fn layoutLimits(lc: *LayCtx, style: parse.Style, s: anytype) Error!u16 {
    const size = style.sizeUnits();
    const base = try layoutNode(lc, style, s.base);
    const bb = lc.boxes[base];
    const sc = style.script();
    var sup: u16 = 0;
    var sub: u16 = 0;
    var sw: i32 = 0;
    var sha: i32 = 0;
    var sdb: i32 = 0;
    var uw: i32 = 0;
    var uha: i32 = 0;
    var udb: i32 = 0;
    var has_sup = false;
    var has_sub = false;
    if (s.sup != NONE) {
        sup = try layoutNode(lc, sc, s.sup);
        const sb = lc.boxes[sup];
        sw = sb.w;
        sha = sb.ha;
        sdb = sb.db;
        has_sup = true;
    }
    if (s.sub != NONE) {
        sub = try layoutNode(lc, sc, s.sub);
        const sb = lc.boxes[sub];
        uw = sb.w;
        uha = sb.ha;
        udb = sb.db;
        has_sub = true;
    }
    const gap: i32 = @divTrunc((@as(i32, 150) * size), 1000);
    var w = bb.w;
    if (sw > w) w = sw;
    if (uw > w) w = uw;
    var parts: [3]BKid = undefined;
    var nparts: usize = 0;
    parts[0] = .{ .box = base, .dx = @divTrunc(w - bb.w, 2), .dy = 0 };
    nparts = 1;
    var ha = bb.ha;
    var db = bb.db;
    if (has_sup) {
        const sy = bb.ha + gap + sdb;
        parts[nparts] = .{ .box = sup, .dx = @divTrunc(w - sw, 2), .dy = sy };
        nparts += 1;
        ha = sy + sha;
    }
    if (has_sub) {
        const sy = -(bb.db + gap + uha);
        parts[nparts] = .{ .box = sub, .dx = @divTrunc(w - uw, 2), .dy = sy };
        nparts += 1;
        db = -sy + udb;
    }
    const sk = try lc.allocKids(nparts);
    @memcpy(lc.bkids[sk .. sk + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = sk, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

fn layoutSupSub(lc: *LayCtx, style: parse.Style, s: anytype) Error!u16 {
    if (opBase(lc.pctx, s.base)) |o| {
        if (useLimits(style, o)) return layoutLimits(lc, style, s);
    }
    const size = style.sizeUnits();
    const base = try layoutNode(lc, style, s.base);
    const bb = lc.boxes[base];
    const sc_style = style.script();
    const sc_size = sc_style.sizeUnits();
    var sup: u16 = 0;
    var sub: u16 = 0;
    var sup_w: i32 = 0;
    var sup_ha: i32 = 0;
    var sup_db: i32 = 0;
    var sub_w: i32 = 0;
    var sub_ha: i32 = 0;
    var sub_db: i32 = 0;
    var has_sup = false;
    var has_sub = false;
    if (s.sup != NONE) {
        sup = try layoutNode(lc, sc_style, s.sup);
        const sb = lc.boxes[sup];
        sup_w = sb.w;
        sup_ha = sb.ha;
        sup_db = sb.db;
        has_sup = true;
    }
    if (s.sub != NONE) {
        sub = try layoutNode(lc, sc_style, s.sub);
        const sb = lc.boxes[sub];
        sub_w = sb.w;
        sub_ha = sb.ha;
        sub_db = sb.db;
        has_sub = true;
    }
    // Shifts in thousandths of an em (TeX-derived), scaled to size.
    var sup_mu: i32 = switch (style) {
        .D, .Dc, .T, .Tc => 400,
        .S, .Sc => 350,
        .SS, .SSc => 300,
    };
    if (style == .Dc or style == .Tc or style == .Sc or style == .SSc) sup_mu -= 30;
    const sup_up: i32 = @divTrunc(sup_mu * size, 1000);
    const sub_down: i32 = @divTrunc((@as(i32, 260) * size), 1000);
    const script_gap: i32 = 60;
    _ = sc_size;
    const sx = bb.w + @divTrunc(script_gap * size, 1000);
    var parts: [3]BKid = undefined;
    var nparts: usize = 0;
    parts[0] = .{ .box = base, .dx = 0, .dy = 0 };
    nparts = 1;
    var ha = bb.ha;
    var db = bb.db;
    if (has_sup) {
        parts[nparts] = .{ .box = sup, .dx = sx, .dy = sup_up };
        nparts += 1;
        const top = sup_up + sup_ha;
        if (top > ha) ha = top;
        const sbot = sup_up - sup_db;
        _ = sbot;
    }
    if (has_sub) {
        parts[nparts] = .{ .box = sub, .dx = sx, .dy = -sub_down };
        nparts += 1;
        const bot = sub_down + sub_db;
        if (bot > db) db = bot;
    }
    const sw = if (sup_w > sub_w) sup_w else sub_w;
    const s2 = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s2 .. s2 + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = sx + sw,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s2, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

fn layoutFrac(lc: *LayCtx, style: parse.Style, f: anytype) Error!u16 {
    const size = style.sizeUnits();
    const base: parse.Style = switch (f.kind.fstyle) {
        0 => style,
        1 => .D,
        2 => .T,
        3 => .S,
    };
    const num = try layoutNode(lc, base.numerator(), f.num);
    const den = try layoutNode(lc, base.denominator(), f.den);
    const nb = lc.boxes[num];
    const dbx = lc.boxes[den];
    var th = f.kind.thick;
    if (th == 0) th = lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar);
    const axis = @divTrunc((@as(i32, 250) * size), 1000);
    const pad: i32 = 120;
    var content = if (nb.w > dbx.w) nb.w else dbx.w;
    content += 2 * pad;
    const gap: i32 = if (3 * th > 100) 3 * th else 100;
    if (!f.kind.bar) {
        // Atop/binom: stack with a fixed gap, no rule.
        const vgap: i32 = @divTrunc((@as(i32, 280) * size), 1000);
        const s = try lc.allocKids(2);
        const num_y = vgap + nb.db;
        const den_y = -(vgap + dbx.ha);
        lc.bkids[s] = .{ .box = num, .dx = @divTrunc(content - nb.w, 2), .dy = num_y };
        lc.bkids[s + 1] = .{ .box = den, .dx = @divTrunc(content - dbx.w, 2), .dy = den_y };
        var b = try lc.allocBox(.{
            .w = content,
            .ha = num_y + nb.ha,
            .db = -den_y + dbx.db,
            .kind = .{ .list = .{ .start = s, .len = 2 } },
            .invisible = false,
        });
        if (f.kind.parens) b = try wrapParens(lc, style, b);
        return b;
    }
    const num_y = axis + gap + nb.db;
    const den_y = -(axis + gap + dbx.ha);
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = num, .dx = @divTrunc(content - nb.w, 2), .dy = num_y };
    lc.bkids[s + 1] = .{ .box = den, .dx = @divTrunc(content - dbx.w, 2), .dy = den_y };
    const rb = try lc.allocBox(.{
        .w = content,
        .ha = @divTrunc(th + 1, 2),
        .db = th - @divTrunc(th + 1, 2),
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    lc.bkids[s + 2] = .{ .box = rb, .dx = 0, .dy = axis };
    return lc.allocBox(.{
        .w = content,
        .ha = num_y + nb.ha,
        .db = -den_y + dbx.db,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

fn wrapParens(lc: *LayCtx, style: parse.Style, inner: u16) Error!u16 {
    const ib = lc.boxes[inner];
    const lp = try layoutFence(lc, style, '(', 0);
    const rp = try layoutFence(lc, style, ')', 0);
    const lb = lc.boxes[lp];
    const rb = lc.boxes[rp];
    const gap: i32 = 100;
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = lp, .dx = 0, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = inner, .dx = lb.w + gap, .dy = 0 };
    lc.bkids[s + 2] = .{ .box = rp, .dx = lb.w + gap + ib.w + gap, .dy = 0 };
    var ha = ib.ha;
    var db = ib.db;
    if (lb.ha > ha) ha = lb.ha;
    if (lb.db > db) db = lb.db;
    if (rb.ha > ha) ha = rb.ha;
    if (rb.db > db) db = rb.db;
    return lc.allocBox(.{
        .w = lb.w + gap + ib.w + gap + rb.w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

fn layoutSqrt(lc: *LayCtx, style: parse.Style, s: anytype) Error!u16 {
    const size = style.sizeUnits();
    const rad = try layoutNode(lc, style, s.radicand);
    const rb = lc.boxes[rad];
    const th = lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar);
    const gap = 2 * th + @divTrunc((@as(i32, 40) * size), 1000);
    // Radical sign, grown through the variant hook when available.
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g0 = lc.glyphId(font, 0x221A);
    const need = rb.ha + rb.db + gap;
    const g = lc.variant(font, g0, @divTrunc(need * 1000, size));
    const gadv = lc.advance(font, g);
    const ge = lc.extents(font, g);
    const gw = @divTrunc(gadv * size, 1000);
    const gha = @divTrunc(ge[0] * size, 1000);
    const gdb = @divTrunc(ge[1] * size, 1000);
    // Rule sits above the radicand; the radical rises to meet it.
    const rule_top = rb.ha + gap + th;
    const kern: i32 = @divTrunc((@as(i32, 50) * size), 1000);
    const over: i32 = @divTrunc((@as(i32, 40) * size), 1000);
    const rad_x = gw + kern;
    const content_w = rad_x + rb.w + over;
    const rule_y = rule_top - @divTrunc(th, 2);
    const s1 = try lc.allocKids(3);
    // Radical glyph positioned so its top meets the rule.
    const rad_dy = rule_top - gha;
    const gb = try lc.allocBox(.{
        .w = gw,
        .ha = gha,
        .db = gdb,
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
    lc.bkids[s1] = .{ .box = gb, .dx = 0, .dy = rad_dy };
    lc.bkids[s1 + 1] = .{ .box = rad, .dx = rad_x, .dy = 0 };
    const ruleb = try lc.allocBox(.{
        .w = rb.w + over + kern,
        .ha = @divTrunc(th + 1, 2),
        .db = th - @divTrunc(th + 1, 2),
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    lc.bkids[s1 + 2] = .{ .box = ruleb, .dx = rad_x - kern, .dy = rule_y };
    var ha = rule_top;
    var db = rb.db;
    const gtop = rad_dy + gha;
    if (gtop > ha) ha = gtop;
    const gbot = -(rad_dy - gdb);
    if (gbot > db) db = gbot;
    var total_w = content_w;
    // Optional root index, set small at the upper left.
    if (s.index != NONE) {
        const idx = try layoutNode(lc, style.script(), s.index);
        const ib = lc.boxes[idx];
        // Prepend: shift existing parts right — rebuild with 4 kids.
        const s2 = try lc.allocKids(4);
        const idx_w = @divTrunc(ib.w * 6, 10);
        lc.bkids[s2] = .{ .box = idx, .dx = 0, .dy = rule_top - ib.db - @divTrunc((@as(i32, 100) * size), 1000) };
        lc.bkids[s2 + 1] = .{ .box = gb, .dx = idx_w, .dy = rad_dy };
        lc.bkids[s2 + 2] = .{ .box = rad, .dx = idx_w + rad_x, .dy = 0 };
        lc.bkids[s2 + 3] = .{ .box = ruleb, .dx = idx_w + rad_x - kern, .dy = rule_y };
        total_w = idx_w + content_w;
        const itop = rule_top - @divTrunc((@as(i32, 100) * size), 1000) + ib.ha;
        if (itop > ha) ha = itop;
        return lc.allocBox(.{
            .w = total_w,
            .ha = ha,
            .db = db,
            .kind = .{ .list = .{ .start = s2, .len = 4 } },
            .invisible = false,
        });
    }
    return lc.allocBox(.{
        .w = total_w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s1, .len = 3 } },
        .invisible = false,
    });
}

// ---------------------------------------------------------------------------
// Fences, accents, overs
// ---------------------------------------------------------------------------

/// One fence glyph sized to at least `need` (total height) when the
/// variant hook can supply it; otherwise the natural glyph centered
/// on the math axis.
fn layoutFence(lc: *LayCtx, style: parse.Style, cp: u21, need: i32) Error!u16 {
    const size = style.sizeUnits();
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g0 = lc.glyphId(font, cp);
    const g = if (need > 0) lc.variant(font, g0, @divTrunc(need * 1000, size)) else g0;
    const adv = lc.advance(font, g);
    const w = @divTrunc(adv * size, 1000);
    const e = lc.extents(font, g);
    var ha = @divTrunc(e[0] * size, 1000);
    var db = @divTrunc(e[1] * size, 1000);
    if (need > 0) {
        // Center the grown fence on the math axis.
        const axis = @divTrunc((@as(i32, 250) * size), 1000);
        const half = @divTrunc(need + 1, 2);
        ha = axis + half;
        db = half - axis;
        if (db < 0) db = 0;
    }
    return lc.allocBox(.{
        .w = w,
        .ha = ha,
        .db = db,
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
}

fn layoutDelim(lc: *LayCtx, style: parse.Style, d: anytype) Error!u16 {
    const prev_need = lc.fence_need;
    // Measure pass (middles at natural size), then the real pass with
    // `\middle` separators grown to the full fence height.
    lc.fence_need = 0;
    const probe = try layoutNode(lc, style, d.body);
    const pb = lc.boxes[probe];
    const th = lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar);
    const clear = if (2 * th > 120) 2 * th else 120;
    const need = pb.ha + pb.db + clear;
    lc.fence_need = need;
    const body = try layoutNode(lc, style, d.body);
    const bb = lc.boxes[body];
    lc.fence_need = prev_need;
    const s = try lc.allocKids(3);
    var x: i32 = 0;
    var ha = bb.ha;
    var db = bb.db;
    if (d.left != 0) {
        const f = try layoutFence(lc, style, d.left, need);
        const fb = lc.boxes[f];
        // layoutFence centers grown fences on the math axis, so dy=0
        // aligns the fence center with the body axis.
        lc.bkids[s] = .{ .box = f, .dx = 0, .dy = 0 };
        x += fb.w;
        if (fb.ha > ha) ha = fb.ha;
        if (fb.db > db) db = fb.db;
    } else {
        lc.bkids[s] = .{ .box = try emptyBox(lc), .dx = 0, .dy = 0 };
    }
    lc.bkids[s + 1] = .{ .box = body, .dx = x, .dy = 0 };
    x += bb.w;
    if (d.right != 0) {
        const f = try layoutFence(lc, style, d.right, need);
        const fb = lc.boxes[f];
        lc.bkids[s + 2] = .{ .box = f, .dx = x, .dy = 0 };
        x += fb.w;
        if (fb.ha > ha) ha = fb.ha;
        if (fb.db > db) db = fb.db;
    } else {
        lc.bkids[s + 2] = .{ .box = try emptyBox(lc), .dx = x, .dy = 0 };
    }
    return lc.allocBox(.{
        .w = x,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

fn emptyBox(lc: *LayCtx) Error!u16 {
    return lc.allocBox(.{
        .w = 0,
        .ha = 0,
        .db = 0,
        .kind = .{ .empty = {} },
        .invisible = false,
    });
}

fn layoutBig(lc: *LayCtx, style: parse.Style, b: anytype) Error!u16 {
    const size = style.sizeUnits();
    const mult = symbols.bigStep(b.level);
    const gsize: u16 = @intCast(@divTrunc(@as(i32, size) * mult, 1000));
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g = lc.glyphId(font, b.cp);
    const adv = lc.advance(font, g);
    const e = lc.extents(font, g);
    return lc.allocBox(.{
        .w = @divTrunc(adv * gsize, 1000),
        .ha = @divTrunc(e[0] * gsize, 1000),
        .db = @divTrunc(e[1] * gsize, 1000),
        .kind = .{ .glyph = .{ .font = font, .size = gsize, .glyph = g } },
        .invisible = false,
    });
}

fn layoutAccent(lc: *LayCtx, style: parse.Style, a: anytype) Error!u16 {
    const size = style.sizeUnits();
    const nuc = try layoutNode(lc, style, a.nucleus);
    const nb = lc.boxes[nuc];
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g = lc.glyphId(font, a.cp);
    const adv = lc.advance(font, g);
    const e = lc.extents(font, g);
    const aw = @divTrunc(adv * size, 1000);
    const aha = @divTrunc(e[0] * size, 1000);
    const adb = @divTrunc(e[1] * size, 1000);
    const gap: i32 = @divTrunc((@as(i32, 120) * size), 1000);
    const skew = lc.italicCorr(font, lc.glyphId(font, nucleusFirstCp(lc.pctx, a.nucleus)));
    const ab = try lc.allocBox(.{
        .w = aw,
        .ha = aha,
        .db = adb,
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
    const w = if (nb.w > aw) nb.w else aw;
    const ax = @divTrunc(nb.w - aw, 2) + @divTrunc(skew, 2);
    const ay = nb.ha + gap + adb;
    const s = try lc.allocKids(2);
    lc.bkids[s] = .{ .box = nuc, .dx = @divTrunc(w - nb.w, 2), .dy = 0 };
    lc.bkids[s + 1] = .{ .box = ab, .dx = @divTrunc(w - nb.w, 2) + ax, .dy = ay };
    return lc.allocBox(.{
        .w = w,
        .ha = ay + aha,
        .db = nb.db,
        .kind = .{ .list = .{ .start = s, .len = 2 } },
        .invisible = false,
    });
}

/// First codepoint of a nucleus, for italic-correction lookup.
fn nucleusFirstCp(pc: *const parse.ParseCtx, id: Idx) u21 {
    const n = parse.nodeAt(pc, id);
    switch (n) {
        .atom => |a| return a.cp,
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            if (kids.len > 0) return nucleusFirstCp(pc, kids[0]);
            return 'x';
        },
        .supsub => |s| return nucleusFirstCp(pc, s.base),
        .font => |f| return nucleusFirstCp(pc, f.body),
        .style => |s| return nucleusFirstCp(pc, s.body),
        else => return 'x',
    }
}

fn overGlyph(kind: parse.OverKind) u21 {
    return switch (kind) {
        .overbrace => 0x23DE,
        .underbrace => 0x23DF,
        .overleft, .xleft => 0x2190,
        .overright, .xright => 0x2192,
        .overboth, .xboth => 0x2194,
        .underleft => 0x2190,
        .underright => 0x2192,
        .underboth => 0x2194,
        .xhookleft => 0x21A9,
        .xhookright => 0x21AA,
        .xmapsto => 0x21A6,
        .xtwoheadleft => 0x219E,
        .xtwoheadright => 0x21A0,
        else => 0,
    };
}

fn layoutOver(lc: *LayCtx, style: parse.Style, o: anytype) Error!u16 {
    const size = style.sizeUnits();
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const th = lc.ruleTh(font, .overline);
    const gap: i32 = @divTrunc((@as(i32, 150) * size), 1000);
    switch (o.kind) {
        .overline, .underline => {
            const nuc = try layoutNode(lc, style, o.nucleus);
            const nb = lc.boxes[nuc];
            const rb = try lc.allocBox(.{
                .w = nb.w,
                .ha = @divTrunc(th + 1, 2),
                .db = th - @divTrunc(th + 1, 2),
                .kind = .{ .rule = {} },
                .invisible = false,
            });
            const s = try lc.allocKids(2);
            if (o.kind == .overline) {
                const ry = nb.ha + gap + @divTrunc(th, 2);
                lc.bkids[s] = .{ .box = nuc, .dx = 0, .dy = 0 };
                lc.bkids[s + 1] = .{ .box = rb, .dx = 0, .dy = ry };
                return lc.allocBox(.{
                    .w = nb.w,
                    .ha = ry + @divTrunc(th + 1, 2),
                    .db = nb.db,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            } else {
                const ry = -(nb.db + gap + @divTrunc(th, 2));
                lc.bkids[s] = .{ .box = nuc, .dx = 0, .dy = 0 };
                lc.bkids[s + 1] = .{ .box = rb, .dx = 0, .dy = ry };
                return lc.allocBox(.{
                    .w = nb.w,
                    .ha = nb.ha,
                    .db = -ry + th,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            }
        },
        .overset, .underset => {
            const nuc = try layoutNode(lc, style, o.nucleus);
            const nb = lc.boxes[nuc];
            const sup = try layoutNode(lc, style.script(), o.extra);
            const sb = lc.boxes[sup];
            const w = if (nb.w > sb.w) nb.w else sb.w;
            const nx = @divTrunc(w - nb.w, 2);
            const sx = @divTrunc(w - sb.w, 2);
            const s = try lc.allocKids(2);
            if (o.kind == .overset) {
                const sy = nb.ha + gap + sb.db;
                lc.bkids[s] = .{ .box = nuc, .dx = nx, .dy = 0 };
                lc.bkids[s + 1] = .{ .box = sup, .dx = sx, .dy = sy };
                return lc.allocBox(.{
                    .w = w,
                    .ha = sy + sb.ha,
                    .db = nb.db,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            } else {
                const sy = -(nb.db + gap + sb.ha);
                lc.bkids[s] = .{ .box = nuc, .dx = nx, .dy = 0 };
                lc.bkids[s + 1] = .{ .box = sup, .dx = sx, .dy = sy };
                return lc.allocBox(.{
                    .w = w,
                    .ha = nb.ha,
                    .db = -sy + sb.db,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            }
        },
        else => {
            // Brace / arrow overs: glyph above or below the nucleus,
            // extensible-arrow labels in script style.
            const is_under = o.kind == .underbrace or o.kind == .underleft or
                o.kind == .underright or o.kind == .underboth;
            const is_x = o.kind == .xleft or o.kind == .xright or o.kind == .xboth or
                o.kind == .xhookleft or o.kind == .xhookright or o.kind == .xmapsto or
                o.kind == .xtwoheadleft or o.kind == .xtwoheadright;
            const gc = overGlyph(o.kind);
            const gg = lc.glyphId(font, gc);
            const gadv = lc.advance(font, gg);
            const ge = lc.extents(font, gg);
            const gw = @divTrunc(gadv * size, 1000);
            const gha = @divTrunc(ge[0] * size, 1000);
            const gdb = @divTrunc(ge[1] * size, 1000);
            const gb = try lc.allocBox(.{
                .w = gw,
                .ha = gha,
                .db = gdb,
                .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = gg } },
                .invisible = false,
            });
            if (is_x) {
                const above = try layoutNode(lc, style.script(), o.extra);
                const ab = lc.boxes[above];
                var below_w: i32 = 0;
                var below_ha: i32 = 0;
                var below_db: i32 = 0;
                var below: u16 = 0;
                var has_below = false;
                if (o.under != NONE) {
                    below = try layoutNode(lc, style.script(), o.under);
                    const bb2 = lc.boxes[below];
                    below_w = bb2.w;
                    below_ha = bb2.ha;
                    below_db = bb2.db;
                    has_below = true;
                }
                var w = gw;
                if (ab.w > w) w = ab.w;
                if (below_w > w) w = below_w;
                const s = try lc.allocKids(if (has_below) 3 else 2);
                const gy: i32 = 0;
                const ay = gha + gap + ab.db;
                lc.bkids[s] = .{ .box = gb, .dx = @divTrunc(w - gw, 2), .dy = gy };
                lc.bkids[s + 1] = .{ .box = above, .dx = @divTrunc(w - ab.w, 2), .dy = ay };
                const ha = ay + ab.ha;
                var db = gdb;
                if (has_below) {
                    const by = -(gdb + gap + below_ha);
                    lc.bkids[s + 2] = .{ .box = below, .dx = @divTrunc(w - below_w, 2), .dy = by };
                    db = -by + below_db;
                }
                return lc.allocBox(.{
                    .w = w,
                    .ha = ha,
                    .db = db,
                    .kind = .{ .list = .{ .start = s, .len = if (has_below) 3 else 2 } },
                    .invisible = false,
                });
            }
            const nuc = try layoutNode(lc, style, o.nucleus);
            const nb = lc.boxes[nuc];
            const w = if (nb.w > gw) nb.w else gw;
            const s = try lc.allocKids(2);
            if (!is_under) {
                const gy = nb.ha + gap + gdb;
                lc.bkids[s] = .{ .box = nuc, .dx = @divTrunc(w - nb.w, 2), .dy = 0 };
                lc.bkids[s + 1] = .{ .box = gb, .dx = @divTrunc(w - gw, 2), .dy = gy };
                return lc.allocBox(.{
                    .w = w,
                    .ha = gy + gha,
                    .db = nb.db,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            } else {
                const gy = -(nb.db + gap + gha);
                lc.bkids[s] = .{ .box = nuc, .dx = @divTrunc(w - nb.w, 2), .dy = 0 };
                lc.bkids[s + 1] = .{ .box = gb, .dx = @divTrunc(w - gw, 2), .dy = gy };
                return lc.allocBox(.{
                    .w = w,
                    .ha = nb.ha,
                    .db = -gy + gdb,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            }
        },
    }
}

// ---------------------------------------------------------------------------
// Text, environments, boxes
// ---------------------------------------------------------------------------

fn layoutText(lc: *LayCtx, style: parse.Style, t: anytype) Error!u16 {
    const size = style.sizeUnits();
    const fam = lc.fam_subst orelse t.fam;
    const font = fam.id();
    var parts: [256]BKid = undefined;
    var nparts: usize = 0;
    var x: i32 = 0;
    var ha: i32 = 0;
    var db: i32 = 0;
    const toks = parse.toksOf(lc.pctx, t.toks);
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        const tk = toks[i];
        var cp: u21 = 0;
        var is_space = false;
        switch (tk.kind) {
            .char => {
                if (tk.cp == ' ') {
                    is_space = true;
                } else {
                    cp = tk.cp;
                }
            },
            .lbrace => cp = '{',
            .rbrace => cp = '}',
            .newline => is_space = true,
            .ctrl => {
                const c = tk.name[0];
                switch (c) {
                    '{', '}', '%', '&', '#', '_', '$', ',', ':', ';', '!', '|', '/' => cp = c,
                    ' ' => is_space = true,
                    '~' => is_space = true,
                    else => {
                        // Text accent: precompose with the next char.
                        const acc = parse.textAccentCp(c) orelse return error.Invalid;
                        if (i + 1 >= toks.len) return error.Invalid;
                        const nx = toks[i + 1];
                        if (nx.kind != .char) return error.Invalid;
                        i += 1;
                        cp = parse.precompose(acc, nx.cp) orelse return error.Invalid;
                    },
                }
            },
            else => return error.Invalid,
        }
        if (is_space) {
            const sw = @divTrunc((@as(i32, 333) * size), 1000);
            const kb = try lc.allocBox(.{
                .w = sw,
                .ha = 0,
                .db = 0,
                .kind = .{ .kern = {} },
                .invisible = false,
            });
            if (nparts >= 256) return error.NoSpace;
            parts[nparts] = .{ .box = kb, .dx = x, .dy = 0 };
            nparts += 1;
            x += sw;
            continue;
        }
        const g = lc.glyphId(font, cp);
        const adv = lc.advance(font, g);
        const w = @divTrunc(adv * size, 1000);
        const e = lc.extents(font, g);
        const b = try lc.allocBox(.{
            .w = w,
            .ha = @divTrunc(e[0] * size, 1000),
            .db = @divTrunc(e[1] * size, 1000),
            .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
            .invisible = false,
        });
        if (nparts >= 256) return error.NoSpace;
        parts[nparts] = .{ .box = b, .dx = x, .dy = 0 };
        nparts += 1;
        const bb = lc.boxes[b];
        x += bb.w;
        if (bb.ha > ha) ha = bb.ha;
        if (bb.db > db) db = bb.db;
    }
    const s = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s .. s + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = x,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

const CellBox = struct {
    id: u16,
    w: i32,
    ha: i32,
    db: i32,
    is_rule: bool,
};

fn layoutEnv(lc: *LayCtx, style: parse.Style, e: anytype) Error!u16 {
    const size = style.sizeUnits();
    const rows = parse.rowsOf(lc.pctx, e.rows_start, e.rows_len);
    // First pass: lay out cells, find column count.
    var cells: [64][8]CellBox = undefined;
    var ncols_per_row: [64]usize = undefined;
    var nrows: usize = 0;
    var ncols: usize = 0;
    for (rows) |r| {
        if (nrows >= 64) return error.NoSpace;
        const kids = parse.kidsOf(lc.pctx, parse.Range{ .start = r.start, .len = r.len });
        var c: usize = 0;
        for (kids) |id| {
            if (c >= 8) return error.NoSpace;
            if (isHline(lc.pctx, id)) {
                cells[nrows][c] = .{ .id = 0, .w = 0, .ha = 0, .db = 0, .is_rule = true };
            } else {
                const b = try layoutNode(lc, if (e.kind == .smallmatrix) parse.Style.S else parse.Style.T, id);
                const bb = lc.boxes[b];
                cells[nrows][c] = .{ .id = b, .w = bb.w, .ha = bb.ha, .db = bb.db, .is_rule = false };
            }
            c += 1;
        }
        ncols_per_row[nrows] = c;
        if (c > ncols) ncols = c;
        nrows += 1;
    }
    if (nrows == 0 or ncols == 0) {
        return lc.allocBox(.{
            .w = 0,
            .ha = 0,
            .db = 0,
            .kind = .{ .empty = {} },
            .invisible = false,
        });
    }
    // Column alignment.
    var col_align: [8]u8 = undefined; // 0=l 1=c 2=r
    var vlines: [9]bool = .{false} ** 9; // vline before col i (ncols = after last)
    switch (e.kind) {
        .array, .alignedat => {
            const spec = parse.kidsOf(lc.pctx, parse.Range{ .start = e.spec_start, .len = e.spec_len });
            var col: usize = 0;
            for (spec) |code| {
                if (code == 3) {
                    if (col <= 8) vlines[col] = true;
                } else {
                    if (col < 8) col_align[col] = @intCast(code);
                    col += 1;
                }
            }
            while (col < 8) : (col += 1) col_align[col] = 1;
            if (col != ncols) {
                // Rows may carry fewer cells (pad) but not more.
                if (ncols > col) return error.Invalid;
                ncols = col;
            }
        },
        .aligned => {
            var col: usize = 0;
            while (col < 8) : (col += 1) col_align[col] = if (col % 2 == 0) 2 else 0;
        },
        .cases => {
            col_align[0] = 0;
            var col: usize = 1;
            while (col < 8) : (col += 1) col_align[col] = 0;
        },
        else => {
            var col: usize = 0;
            while (col < 8) : (col += 1) col_align[col] = 1;
        },
    }
    // Column widths.
    var colw: [8]i32 = .{0} ** 8;
    var r: usize = 0;
    while (r < nrows) : (r += 1) {
        var c: usize = 0;
        while (c < ncols_per_row[r]) : (c += 1) {
            if (!cells[r][c].is_rule and cells[r][c].w > colw[c]) colw[c] = cells[r][c].w;
        }
    }
    const half_sep: i32 = @divTrunc((@as(i32, 250) * size), 1000);
    const row_gap: i32 = if (e.kind == .smallmatrix) @divTrunc((@as(i32, 140) * size), 1000) else @divTrunc((@as(i32, 280) * size), 1000);
    const vline_w: i32 = @divTrunc((@as(i32, 40) * size), 1000);
    // Total width.
    var total_w: i32 = 0;
    var c: usize = 0;
    while (c < ncols) : (c += 1) {
        total_w += colw[c] + 2 * half_sep;
        if (vlines[c + 1]) total_w += vline_w;
    }
    if (vlines[0]) total_w += vline_w;
    // Row vertical extents.
    var row_ha: [64]i32 = undefined;
    var row_db: [64]i32 = undefined;
    r = 0;
    while (r < nrows) : (r += 1) {
        var h: i32 = 0;
        var d: i32 = 0;
        var cc: usize = 0;
        var any_rule = false;
        while (cc < ncols_per_row[r]) : (cc += 1) {
            if (cells[r][cc].is_rule) {
                any_rule = true;
            } else {
                if (cells[r][cc].ha > h) h = cells[r][cc].ha;
                if (cells[r][cc].db > d) d = cells[r][cc].db;
            }
        }
        if (any_rule and ncols_per_row[r] == 1) {
            h = 100;
            d = 100;
        }
        row_ha[r] = h;
        row_db[r] = d;
    }
    // Baselines from the top.
    var row_base: [64]i32 = undefined;
    var y: i32 = 0;
    r = 0;
    while (r < nrows) : (r += 1) {
        y += row_ha[r];
        row_base[r] = y;
        y += row_db[r] + row_gap;
    }
    const total_h = y - row_gap;
    // Emit.
    var parts: [256]BKid = undefined;
    var nparts: usize = 0;
    const emit = struct {
        fn put(
            p: *[256]BKid,
            np: *usize,
            id: u16,
            dx: i32,
            dy: i32,
        ) Error!void {
            if (np.* >= 256) return error.NoSpace;
            p[np.*] = .{ .box = id, .dx = dx, .dy = dy };
            np.* += 1;
        }
    }.put;
    // Column x origins.
    var colx: [8]i32 = undefined;
    var cx: i32 = 0;
    if (vlines[0]) cx += vline_w;
    c = 0;
    while (c < ncols) : (c += 1) {
        colx[c] = cx + half_sep;
        cx += colw[c] + 2 * half_sep;
        if (vlines[c + 1]) cx += vline_w;
    }
    r = 0;
    while (r < nrows) : (r += 1) {
        const base = total_h - row_base[r];
        var cc: usize = 0;
        while (cc < ncols_per_row[r]) : (cc += 1) {
            const cell = cells[r][cc];
            if (cell.is_rule) {
                const rb = try lc.allocBox(.{
                    .w = total_w,
                    .ha = @divTrunc((@as(i32, 40) * size) + 1, 1000),
                    .db = 0,
                    .kind = .{ .rule = {} },
                    .invisible = false,
                });
                try emit(&parts, &nparts, rb, 0, base);
                continue;
            }
            const dx: i32 = switch (col_align[cc]) {
                0 => colx[cc],
                2 => colx[cc] + colw[cc] - cell.w,
                else => colx[cc] + @divTrunc(colw[cc] - cell.w, 2),
            };
            try emit(&parts, &nparts, cell.id, dx, base);
        }
        // Vertical rules for this row span.
        if (e.kind == .array or e.kind == .alignedat) {
            var vc: usize = 0;
            while (vc <= ncols) : (vc += 1) {
                if (!vlines[vc]) continue;
                const vx: i32 = if (vc == 0) 0 else colx[vc - 1] + colw[vc - 1] + half_sep;
                const vb = try lc.allocBox(.{
                    .w = vline_w,
                    .ha = row_ha[r],
                    .db = row_db[r],
                    .kind = .{ .rule = {} },
                    .invisible = false,
                });
                try emit(&parts, &nparts, vb, vx, base);
            }
        }
    }
    const s = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s .. s + nparts], parts[0..nparts]);
    // dy convention: baseline shift UP from parent baseline. Row
    // baselines are absolute here; the table baseline is the FIRST
    // row baseline (TeX: arrays center on the axis — v1 uses the
    // first-row baseline, documented).
    const table_base = total_h - row_base[0];
    // Shift everything so the first row baseline is at table_base...
    // parts already use `base` = table-relative; the table box
    // baseline = table_base with ha=db split:
    return lc.allocBox(.{
        .w = total_w,
        .ha = total_h - table_base,
        .db = table_base,
        .kind = .{ .list = .{ .start = s, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

fn isHline(pc: *const parse.ParseCtx, id: Idx) bool {
    const n = parse.nodeAt(pc, id);
    switch (n) {
        .hline => return true,
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            return kids.len == 1 and isHline(pc, kids[0]);
        },
        else => return false,
    }
}

fn layoutSubstack(lc: *LayCtx, style: parse.Style, r: parse.Range) Error!u16 {
    _ = style;
    const rows = parse.rowsOf(lc.pctx, r.start, r.len);
    var parts: [128]BKid = undefined;
    var nparts: usize = 0;
    const gap: i32 = 140;
    // First pass for widths.
    var widths: [64]i32 = undefined;
    var ids: [64]u16 = undefined;
    var heights: [64][2]i32 = undefined;
    var n: usize = 0;
    for (rows) |row| {
        if (n >= 64) return error.NoSpace;
        const kids = parse.kidsOf(lc.pctx, parse.Range{ .start = row.start, .len = row.len });
        // Each substack row holds exactly one cell group; anything
        // else (empty trailing rows) packs as a plain row.
        const b = if (kids.len == 1) try layoutNode(lc, .S, kids[0]) else blk: {
            const ks = try lc.allocKids(kids.len);
            var x: i32 = 0;
            var ha: i32 = 0;
            var db: i32 = 0;
            for (kids, 0..) |kid, j| {
                const cb = try layoutNode(lc, .S, kid);
                const cbb = lc.boxes[cb];
                lc.bkids[@as(usize, ks) + j] = .{ .box = cb, .dx = x, .dy = 0 };
                x += cbb.w;
                if (cbb.ha > ha) ha = cbb.ha;
                if (cbb.db > db) db = cbb.db;
            }
            break :blk try lc.allocBox(.{
                .w = x,
                .ha = ha,
                .db = db,
                .kind = .{ .list = .{ .start = ks, .len = @intCast(kids.len) } },
                .invisible = false,
            });
        };
        const bb = lc.boxes[b];
        ids[n] = b;
        widths[n] = bb.w;
        heights[n] = .{ bb.ha, bb.db };
        n += 1;
    }
    var w: i32 = 0;
    for (widths[0..n]) |cw| {
        if (cw > w) w = cw;
    }
    // Stack from the top; baseline = first row baseline.
    var y: i32 = 0;
    var k: usize = 0;
    var bases: [64]i32 = undefined;
    while (k < n) : (k += 1) {
        y += heights[k][0];
        bases[k] = y;
        y += heights[k][1] + gap;
    }
    const total = y - gap;
    const first_base = total - bases[0];
    k = 0;
    while (k < n) : (k += 1) {
        if (nparts >= 128) return error.NoSpace;
        parts[nparts] = .{ .box = ids[k], .dx = @divTrunc(w - widths[k], 2), .dy = total - bases[k] };
        nparts += 1;
    }
    const s = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s .. s + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = w,
        .ha = total - first_base,
        .db = first_base,
        .kind = .{ .list = .{ .start = s, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

fn layoutBoxed(lc: *LayCtx, style: parse.Style, id: Idx) Error!u16 {
    const size = style.sizeUnits();
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    const pad: i32 = @divTrunc((@as(i32, 300) * size), 1000);
    const th: i32 = @divTrunc((@as(i32, 40) * size), 1000);
    const w = bb.w + 2 * pad;
    const ha = bb.ha + pad;
    const db = bb.db + pad;
    const s = try lc.allocKids(5);
    lc.bkids[s] = .{ .box = b, .dx = pad, .dy = 0 };
    const top = try lc.allocBox(.{
        .w = w,
        .ha = th,
        .db = 0,
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const bot = try lc.allocBox(.{
        .w = w,
        .ha = 0,
        .db = th,
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const side = try lc.allocBox(.{
        .w = th,
        .ha = ha,
        .db = db,
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    lc.bkids[s + 1] = .{ .box = top, .dx = 0, .dy = ha };
    lc.bkids[s + 2] = .{ .box = bot, .dx = 0, .dy = -db + th };
    lc.bkids[s + 3] = .{ .box = side, .dx = 0, .dy = 0 };
    lc.bkids[s + 4] = .{ .box = side, .dx = w - th, .dy = 0 };
    return lc.allocBox(.{
        .w = w,
        .ha = ha + th,
        .db = db + th,
        .kind = .{ .list = .{ .start = s, .len = 5 } },
        .invisible = false,
    });
}

fn layoutCancel(lc: *LayCtx, style: parse.Style, id: Idx) Error!u16 {
    // v1: horizontal rule through the vertical middle (the IR has no
    // diagonal strokes; MathML uses menclose notation="updiagonalstrike").
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    const th = lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar);
    const mid = @divTrunc(bb.ha - bb.db, 2);
    const rb = try lc.allocBox(.{
        .w = bb.w,
        .ha = @divTrunc(th + 1, 2),
        .db = th - @divTrunc(th + 1, 2),
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const s = try lc.allocKids(2);
    lc.bkids[s] = .{ .box = b, .dx = 0, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = rb, .dx = 0, .dy = mid };
    return lc.allocBox(.{
        .w = bb.w,
        .ha = bb.ha,
        .db = bb.db,
        .kind = .{ .list = .{ .start = s, .len = 2 } },
        .invisible = false,
    });
}

fn layoutLap(lc: *LayCtx, style: parse.Style, l: anytype) Error!u16 {
    const b = try layoutNode(lc, style, l.body);
    const bb = lc.boxes[b];
    const dx: i32 = switch (l.kind) {
        .rlap => 0,
        .llap => -bb.w,
        .clap => -@divTrunc(bb.w, 2),
    };
    const s = try lc.allocKids(1);
    lc.bkids[s] = .{ .box = b, .dx = dx, .dy = 0 };
    return lc.allocBox(.{
        .w = 0,
        .ha = bb.ha,
        .db = bb.db,
        .kind = .{ .list = .{ .start = s, .len = 1 } },
        .invisible = false,
    });
}

// ---------------------------------------------------------------------------
// IR emission (thin walker — no layout math)
// ---------------------------------------------------------------------------

const EmitCtx = struct {
    runs: []ir.Run,
    rules: []ir.Rule,
    glyphs: []u16,
    nr: usize = 0,
    nl: usize = 0,
    ng: usize = 0,
    open_font: u16 = 0,
    open_size: u16 = 0,
    open_y: i32 = 0,
    /// Expected pen x for run continuation.
    open_x: i32 = 0,
    open_run_x: i32 = 0,
    open_start: usize = 0,
    has_open: bool = false,

    fn closeRun(self: *EmitCtx) void {
        if (!self.has_open) return;
        if (self.ng > self.open_start) {
            self.runs[self.nr] = .{
                .font_id = self.open_font,
                .size_units = self.open_size,
                .x = self.open_run_x,
                .baseline_y = self.open_y,
                .glyphs = self.glyphs[self.open_start..self.ng],
            };
            self.nr += 1;
        }
        self.has_open = false;
    }
};

fn emitBox(lc: *LayCtx, ec: *EmitCtx, id: u16, x: i32, base: i32) Error!void {
    const b = lc.boxes[id];
    switch (b.kind) {
        .glyph => |g| {
            if (!b.invisible) {
                // Break runs on position gaps: expected pen must equal x.
                if (ec.has_open and (ec.open_font != g.font or ec.open_size != g.size or ec.open_y != base or ec.open_x != x)) {
                    ec.closeRun();
                }
                if (!ec.has_open) {
                    if (ec.nr >= ec.runs.len) return error.NoSpace;
                    ec.open_font = g.font;
                    ec.open_size = g.size;
                    ec.open_y = base;
                    ec.open_start = ec.ng;
                    ec.open_run_x = x;
                    ec.has_open = true;
                }
                if (ec.ng >= ec.glyphs.len) return error.NoSpace;
                ec.glyphs[ec.ng] = g.glyph;
                ec.ng += 1;
                ec.open_x = x + b.w;
            }
        },
        .kern, .empty => {},
        .rule => {
            if (!b.invisible) {
                ec.closeRun();
                if (ec.nl >= ec.rules.len) return error.NoSpace;
                ec.rules[ec.nl] = .{
                    .x = x,
                    .y = base - b.ha,
                    .w = if (b.w < 0) 0 else @intCast(b.w),
                    .h = if (b.ha + b.db < 0) 0 else @intCast(b.ha + b.db),
                };
                ec.nl += 1;
            }
        },
        .list => |r| {
            const kids = lc.bkids[r.start .. r.start + r.len];
            for (kids) |k| {
                // Invisibility propagates to children.
                if (b.invisible) {
                    try emitInvisible(lc, ec, k.box, x + k.dx, base - k.dy);
                } else {
                    try emitBox(lc, ec, k.box, x + k.dx, base - k.dy);
                }
            }
        },
    }
}

/// Walk an invisible subtree for dimension-independent validation
/// (emits nothing).
fn emitInvisible(lc: *LayCtx, ec: *EmitCtx, id: u16, x: i32, base: i32) Error!void {
    const b = lc.boxes[id];
    switch (b.kind) {
        .list => |r| {
            const kids = lc.bkids[r.start .. r.start + r.len];
            for (kids) |k| try emitInvisible(lc, ec, k.box, x + k.dx, base - k.dy);
        },
        else => {},
    }
}
