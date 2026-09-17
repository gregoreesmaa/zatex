//! ZaTeX layout core: AST → box tree → IR runs/rules.
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
const build_options = @import("build_options");
const contract = @import("contract.zig");
const ir = @import("ir.zig");
const parse = @import("parse.zig");
const symbols = @import("symbols.zig");

const active_profile: contract.Profile =
    std.meta.stringToEnum(contract.Profile, build_options.profile) orelse .full;

const Error = contract.LayoutError;
const Idx = parse.Idx;
const NONE = parse.NONE;

/// x-height in thousandths of an em (TeX-derived, KaTeX parity 0.4306):
/// accent clearance tucks to within one x-height of the base top
/// (issues #30, #38). Single source for every accent path.
const x_height_1000: i32 = 431;

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
    /// Diagonal strike box (`\cancel` family, issue #107): same
    /// metrics as the strike rect; emit draws the `ir.Rule.diag`
    /// corner-to-corner line instead of filling the rect.
    diag: struct {
        dir: ir.Diag,
        thick: u32,
    },
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
    /// Ambient paint (`\color` scope, issue #35); stamped at
    /// allocation, overridden for box backgrounds/frames.
    color: ?u32 = null,
    /// Horizontal raster scale in per-mille (1000 = identity), set by
    /// the core when a glyph must span a construction wider than its
    /// natural advance (wide accents, brace spans — issues #31/#37):
    /// the layout box keeps the construction width, the backend
    /// stretches the ink. Runs split on scale change like on color.
    x_scale: u16 = 1000,
    /// Faux-italic slant in per-mille (0 = upright), stamped by
    /// `layoutAtom` for dotless i/j under the default math face
    /// (issue #77): the backend shears the ink about the baseline.
    /// Runs split on shear change like on scale.
    x_shear: i16 = 0,
    /// Horizontally mirrored subtree (`\reflectbox` /
    /// `\mathreflectbox`, issue #97): geometry is the plain body
    /// box bit-identically (KaTeX's CSS flip changes paint, not
    /// layout); the emit walk mirrors the ink about the box center.
    mirror: bool = false,
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
    /// Ambient paint (`\color` scope, issue #35) plus its stack.
    cur_color: ?u32 = null,
    color_stack: [32]?u32 = undefined,
    ncolors: u8 = 0,
    /// Ambient font-size multiplier in per-mille (1000 = identity),
    /// set by `.size` nodes (`\tiny`…`\Huge`, issue #73). Absolute
    /// like KaTeX `havingSize` (nested sizes reset, never compound).
    cur_mult: u16 = 1000,

    /// Effective size units: TeX style size scaled by the ambient
    /// size multiplier. Identity (1000) reproduces `sizeUnits`
    /// bit-exactly (`u*1000/1000 == u`), so unsized layout is
    /// untouched by construction.
    fn effSize(self: *LayCtx, style: parse.Style) u16 {
        return @intCast(@divTrunc(@as(i32, style.sizeUnits()) * self.cur_mult, 1000));
    }

    pub fn init(pctx: *const parse.ParseCtx, provider: contract.MetricsProvider) LayCtx {
        return .{ .pctx = pctx, .provider = provider };
    }

    fn allocBox(self: *LayCtx, b: Box) Error!u16 {
        if (self.nboxes >= max_boxes) return error.NoSpace;
        const id = self.nboxes;
        self.boxes[id] = b;
        // Ambient paint stamps every box; box backgrounds/frames
        // override afterwards (issue #35).
        if (self.boxes[id].color == null) self.boxes[id].color = self.cur_color;
        self.nboxes += 1;
        return id;
    }

    fn pushColor(self: *LayCtx, c: ?u32) Error!void {
        if (self.ncolors >= self.color_stack.len) return error.NoSpace;
        self.color_stack[self.ncolors] = self.cur_color;
        self.ncolors += 1;
        self.cur_color = c;
    }

    fn popColor(self: *LayCtx) void {
        self.ncolors -= 1;
        self.cur_color = self.color_stack[self.ncolors];
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
        // KaTeX `minRuleThickness` parity: the caller floor (in
        // thousandths of an em, like provider weights) applies to
        // every requested thickness; 0 disables it bit-identically.
        // The floor is full-profile surface (subset entry points
        // always pass the 0 default): subset keeps the bare weight
        // so the extra max vanishes from its binary (size ratchet).
        const v = self.provider.ruleThickness(self.provider.ctx, font, kind);
        const base = if (v <= 0) 40 else v;
        if (comptime active_profile == .subset) return base;
        return @max(base, self.pctx.min_rule_floor);
    }
    /// Hardcoded 0.04em rule weights (array vlines, `\fbox` frames)
    /// under the same floor: the constant stands in for a provider
    /// weight KaTeX would floor too.
    fn constRule(self: *LayCtx, size: i32) i32 {
        // Subset keeps the bare constant (floor always 0 there);
        // see `ruleTh`.
        const w: i32 = if (comptime active_profile == .subset) 40 else @max(@as(i32, 40), self.pctx.min_rule_floor);
        return @divTrunc(w * size, 1000);
    }
    fn variant(self: *LayCtx, font: u16, glyph: u16, need: i32) u16 {
        if (self.provider.glyphVariant) |f| return f(self.provider.ctx, font, glyph, need);
        return glyph;
    }
    fn italicCorr(self: *LayCtx, font: u16, glyph: u16) i32 {
        if (self.provider.italicCorrection) |f| return f(self.provider.ctx, font, glyph);
        return 0;
    }
    fn kernCorr(self: *LayCtx, font: u16, glyph: u16, height: i32, corner: contract.KernCorner) i32 {
        if (self.provider.kernCorrection) |f| return f(self.provider.ctx, font, glyph, height, corner);
        return 0;
    }
    fn extents(self: *LayCtx, font: u16, glyph: u16) [2]i32 {
        if (self.provider.extents) |f| return f(self.provider.ctx, font, glyph);
        return .{ 700, 250 };
    }
    /// True ink box `[x_min, y_min, x_max, y_max]`, y up from the
    /// baseline, at 1000 units — or null when the provider has no v4
    /// `inkBounds` hook (callers keep exact v3 behavior then).
    fn ink(self: *LayCtx, font: u16, glyph: u16) ?[4]i32 {
        if (self.provider.inkBounds) |f| return f(self.provider.ctx, font, glyph);
        return null;
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
    // `fleqn` (KaTeX: display flush-left with a 2em margin): the
    // whole construction shifts right 2em and the width grows with
    // it, so hosts positioning the block keep the margin. Display
    // only; inline math is untouched.
    // `fleqn` is full-profile surface (subset entry points always
    // pass false): the margin folds to zero in subset binaries.
    const margin: i32 = if (active_profile == .full and lc.pctx.fleqn and style.isDisplay()) 2 * @as(i32, lc.effSize(style)) else 0;
    // Origin top-left; the root baseline sits at height_above.
    try emitBox(lc, &ec, box, margin, b.ha);
    ec.closeRun();
    const w: i32 = b.w + margin;
    return .{
        .width = if (w < 0) 0 else @intCast(w),
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
        // Built-limit operators lay out like the inner under/over
        // (Op spacing comes from `classOf` below).
        .varlim => |v| return layoutNode(lc, style, v.body),
        .group => |g| return layoutGroup(lc, style, g),
        .frac => |f| return layoutFrac(lc, style, f),
        .sqrt => |s| return layoutSqrt(lc, style, s),
        .supsub => |s| return layoutSupSub(lc, style, s),
        .delim => |d| return layoutDelim(lc, style, d),
        .middle => |m| return layoutFence(lc, style, m.cp, lc.fence_need, false),
        .big => |b| return layoutBig(lc, style, b),
        .accent => |a| return layoutAccent(lc, style, a),
        .over => |o| return layoutOver(lc, style, o),
        .style => |s| return layoutNode(lc, s.style, s.body),
        .size => |s| {
            const prev = lc.cur_mult;
            lc.cur_mult = s.mult;
            const b = try layoutNode(lc, style, s.body);
            lc.cur_mult = prev;
            return b;
        },
        .classwrap => |c| return layoutNode(lc, style, c.body),
        .font => |f| {
            const prev = lc.fam_subst;
            lc.fam_subst = f.fam;
            const b = try layoutNode(lc, style, f.body);
            lc.fam_subst = prev;
            return b;
        },
        // Poor-man's bold is a paint style (KaTeX text-shadow), so
        // layout is the bare body box, bit-identically.
        .pmb => |p| return layoutNode(lc, style, p.body),
        .reflect => |r| {
            // Mirrored content (issue #97): the layout box keeps the
            // body geometry bit-identically — only the emit walk
            // mirrors the ink, about this box's horizontal center.
            const b = try layoutNode(lc, style, r.body);
            const bb = lc.boxes[b];
            const s = try lc.allocKids(1);
            lc.bkids[s] = .{ .box = b, .dx = 0, .dy = 0 };
            return lc.allocBox(.{
                .w = bb.w,
                .ha = bb.ha,
                .db = bb.db,
                .kind = .{ .list = .{ .start = s, .len = 1 } },
                .invisible = false,
                .mirror = true,
            });
        },
        .circled => |c| {
            // Enclosing ring (issue #80, pinned 0.18.7 browser
            // pixels): KaTeX pins the U+25EF baseline to the body
            // baseline, so the body sits INSIDE the ring — a tall
            // body overflows the ring top while the ring stays put.
            // Body and ring center in the construction (`text-align:
            // center` on KaTeX's accent vlist; the ring then shifts
            // right by the nucleus skew), which is as wide as the
            // wider of body and ring. Decoded from the pinned DOM
            // and pixels: the vlist is exactly the ring (0.8889em
            // across bodies a/A/g), and the ring metrics are
            // Main-Regular U+25EF [d 0.19444, h 0.69444, w 1].
            // Skew mirrors our accents (single-symbol nuclei only),
            // minus italic correction.
            const body = try layoutNode(lc, style, c.body);
            const bb = lc.boxes[body];
            const size = lc.effSize(style);
            const font: u16 = @intFromEnum(contract.FontId.rm);
            const cg = lc.glyphId(font, 0x25EF);
            const caw = @divTrunc(lc.advance(font, cg) * size, 1000);
            const ce = lc.extents(font, cg);
            const caha = @divTrunc(ce[0] * size, 1000);
            const cadb = @divTrunc(ce[1] * size, 1000);
            const cb = try lc.allocBox(.{
                .w = caw,
                .ha = caha,
                .db = cadb,
                .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = cg } },
                .invisible = false,
            });
            const ng = nucleusFirstGlyph(lc, body);
            const ncp = nucleusFirstCp(lc.pctx, c.body);
            const single = nucleusIsSingle(lc.pctx, c.body);
            const askew: i32 = if (single and ng != null and ng.?.font == @intFromEnum(contract.FontId.math_italic))
                @divTrunc(symbols.mathItalicSkew(ncp) * @as(i32, size), 1000)
            else
                0;
            // Ring baseline height above the body baseline: zero.
            // KaTeX's vlist stacks the ring one ring-depth above the
            // body baseline and its relative `top: .2em` drops it
            // back (`accent.ts`); net zero to subpixel rounding
            // (pinned Chromium pixels: the glyph baselines coincide
            // within 0.2px), so the body sits inside the ring.
            const cdy: i32 = 0;
            const w = if (bb.w > caw) bb.w else caw;
            const s = try lc.allocKids(2);
            lc.bkids[s] = .{ .box = body, .dx = @divTrunc(w - bb.w, 2), .dy = 0 };
            lc.bkids[s + 1] = .{ .box = cb, .dx = @divTrunc(w - caw, 2) + askew, .dy = cdy };
            var ha = bb.ha;
            const catop = cdy + caha;
            if (catop > ha) ha = catop;
            var db = bb.db;
            const cabot = cadb - cdy;
            if (cabot > db) db = cabot;
            return lc.allocBox(.{
                .w = w,
                .ha = ha,
                .db = db,
                .kind = .{ .list = .{ .start = s, .len = 2 } },
                .invisible = false,
            });
        },
        .vcenter => |v| {
            // KaTeX parity (pinned 0.18.7 HTML, issue #51): shift
            // the body so the math axis halves its total — the same
            // rule as grown-fence centering, without the depth clamp
            // (a shallow body really does end above the baseline).
            const body = try layoutNode(lc, style, v.body);
            const bb = lc.boxes[body];
            const axis = @divTrunc(@as(i32, 250) * lc.effSize(style), 1000);
            const half = @divTrunc(bb.ha + bb.db + 1, 2);
            const s = try lc.allocKids(1);
            lc.bkids[s] = .{ .box = body, .dx = 0, .dy = axis + half - bb.ha };
            return lc.allocBox(.{
                .w = bb.w,
                .ha = axis + half,
                .db = half - axis,
                .kind = .{ .list = .{ .start = s, .len = 1 } },
                .invisible = false,
            });
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
            .w = scale(lc, u, style),
            .ha = 0,
            .db = 0,
            .kind = .{ .kern = {} },
            .invisible = false,
        }),
        // Interword NBSP measures exactly like its glue width
        // (`parse.space_interword`); only serialization differs.
        .nbsp => return lc.allocBox(.{
            .w = scale(lc, parse.space_interword, style),
            .ha = 0,
            .db = 0,
            .kind = .{ .kern = {} },
            .invisible = false,
        }),
        .vspace => |u| {
            const v = scale(lc, u, style);
            return lc.allocBox(.{
                .w = 0,
                .ha = if (v > 0) v else 0,
                .db = if (v < 0) -v else 0,
                .kind = .{ .kern = {} },
                .invisible = false,
            });
        },
        .newline => |nl| {
            // `\\[size]` (issues #140/#144): KaTeX sets the break
            // apart vertically; unsized breaks take no space.
            const v = scale(lc, nl.size, style);
            return lc.allocBox(.{
                .w = 0,
                .ha = if (v > 0) v else 0,
                .db = if (v < 0) -v else 0,
                .kind = .{ .kern = {} },
                .invisible = false,
            });
        },
        .hline => return lc.allocBox(.{
            .w = 0,
            .ha = 100,
            .db = 100,
            .kind = .{ .rule = {} },
            .invisible = false,
        }),
        .color => |c| {
            // Paint the body (KaTeX parity, issue #35): nested scopes
            // win; unresolvable specs keep the ambient paint.
            try lc.pushColor(parse.resolveColorSpec(lc.pctx, c.spec));
            const b = try layoutNode(lc, style, c.body);
            lc.popColor();
            return b;
        },
        // Native layout has no background channel: render the body
        // text, like `.text` (the MathML emitter keeps the box).
        .colorbox => |c| return layoutColorBox(lc, style, c),
        .href => |h| return layoutNode(lc, style, h.body),
        .htmlwrap => |b| return layoutNode(lc, style, b),
        .tag => |tg| return layoutTag(lc, style, tg),
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
        // Framed text measures like a box around its text body.
        .fbox => |b| return layoutBoxed(lc, style, b),
        // Dual-branch content lays out the visual (`html`) branch.
        .htmlmathml => |h| return layoutNode(lc, style, h.html),
        .cancel => |c| return layoutCancel(lc, style, c.body, c.down, false),
        .xcancel => |b| return layoutCancel(lc, style, b, false, true),
        .phase => |b| return layoutPhase(lc, style, b),
        .sout => |b| return layoutSout(lc, style, b),
        .lap => |l| return layoutLap(lc, style, l),
        // amscd side labels lay out inline at script size (the
        // bundle overlaps them at zero width — geometry follow-up,
        // issue #85; structure is what parity pins).
        .cdlabel => |c| return layoutNode(lc, style.script(), c.body),
        .not => |nt| return layoutNot(lc, style, nt),
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
            const dh = scale(lc, r.dh, style);
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
        .rule => |r| {
            // The bracket raises the bar (KaTeX `bottom:<raise>`): ink
            // spans [raise, raise + h] above the baseline (issue #37).
            const h = scale(lc, r.h, style);
            const up = scale(lc, r.raise, style);
            return lc.allocBox(.{
                .w = scale(lc, r.w, style),
                .ha = h + up,
                .db = -up,
                .kind = .{ .rule = {} },
                .invisible = false,
            });
        },
        .graphics => |g| {
            // Included image: no vector ink (the host paints the
            // source), so an empty box carrying the image metrics.
            // Depth comes from `totalheight` when positive (KaTeX
            // `htmlBuilder`: height above, total-minus-height
            // below). Non-positive widths/heights floor at zero
            // (KaTeX drops a non-positive `width`; negative
            // geometry has no box meaning).
            const w = @max(scale5(lc, g.w, style), 0);
            const h = @max(scale5(lc, g.h, style), 0);
            const dep = if (g.th > 0) scale5(lc, @as(i64, g.th) - @as(i64, g.h), style) else 0;
            return lc.allocBox(.{
                .w = w,
                .ha = h,
                .db = dep,
                .kind = .{ .empty = {} },
                .invisible = false,
            });
        },
    }
}

/// Scale thousandths-of-em by the effective size (style size times
/// the ambient `\tiny`…`\Huge` multiplier).
fn scale(lc: *LayCtx, u: i16, style: parse.Style) i32 {
    return @divTrunc(@as(i32, u) * lc.effSize(style), 1000);
}

/// Scale a per-row `\\[size]` gap (thousandths of an em, possibly
/// negative) into ambient units (issues #140/#144).
fn scaleRowGap(gap: i16, size: u16) i32 {
    return @divTrunc(@as(i32, gap) * @as(i32, size), 1000);
}

/// Scale hundred-thousandths-of-em by the effective size (the
/// `scale` twin for `\includegraphics` sizes, which keep four
/// decimals where `.rule` thousandths cannot). i64 in, saturated
/// i32 out.
fn scale5(lc: *LayCtx, v: i64, style: parse.Style) i32 {
    const q = @divTrunc(v * @as(i64, lc.effSize(style)), 100000);
    if (q > std.math.maxInt(i32)) return std.math.maxInt(i32);
    if (q < std.math.minInt(i32)) return std.math.minInt(i32);
    return @intCast(q);
}

fn effFont(lc: *LayCtx, f: parse.FontFam) parse.FontFam {
    return lc.fam_subst orelse f;
}

/// Mathematical Alphanumeric remap (issues #57/#62): KaTeX selects a
/// different physical font per family (Math-Italic, Main-Bold, ...);
/// a single OpenType math host carries those styles in the SMP
/// Mathematical Alphanumeric block instead, so the core remaps ASCII
/// letters/digits there when the effective family is a math variant.
/// Codepoints the blocks lack pass through, matching KaTeX's own
/// rendering: digits under mathit (no italic digits exist — KaTeX's
/// Math-Italic digits are upright) and fraktur digits (no block).
/// Letter exceptions follow Unicode's LGC preassignments, which
/// KaTeX's fonts honor: mathit h is the Planck slot U+210E; script,
/// fraktur and double-struck capitals with singleton assignments keep
/// them; script small e/g/o keep theirs. Greek is out of scope (the
/// issues ask for ASCII only). Returns null when no remap applies;
/// the caller falls back to the raw codepoint when the host lacks
/// the glyph (gid 0 — verified partial in the LM fixture, which has
/// no script small a/e), so partial host coverage degrades to
/// today's rendering instead of tofu.
fn mathAlpha(fam: parse.FontFam, cp: u21) ?u21 {
    if (alphaExc(fam, cp)) |e| return e;
    if (cp >= 'A' and cp <= 'Z') {
        const b = alphaBase(fam, 0) orelse return null;
        return b + (cp - 'A');
    }
    if (cp >= 'a' and cp <= 'z') {
        const b = alphaBase(fam, 1) orelse return null;
        return b + (cp - 'a');
    }
    if (cp >= '0' and cp <= '9') {
        const b = alphaBase(fam, 2) orelse return null;
        return b + (cp - '0');
    }
    return null;
}

/// Block base per family for columns A-Z/a-z/0-9 (0 = no block —
/// digits under mathit, fraktur digits and script digits: KaTeX
/// renders those upright, and the blocks have none). Kept as data,
/// not switch arms, so the subset profile pays __const bytes (free)
/// instead of __TEXT jump tables (gated).
fn alphaBase(fam: parse.FontFam, col: u2) ?u21 {
    const row: [3]u21 = switch (fam) {
        .rm => .{ 0, 0, 0 },
        .mathit => .{ 0x1D434, 0x1D44E, 0 },
        .bold => .{ 0x1D400, 0x1D41A, 0x1D7CE },
        .sans => .{ 0x1D5A0, 0x1D5BA, 0x1D7E2 },
        .tt => .{ 0x1D670, 0x1D68A, 0x1D7F6 },
        .frak => .{ 0x1D504, 0x1D51E, 0 },
        .bb => .{ 0x1D538, 0x1D552, 0x1D7D8 },
        // Bold-italic capitals/logographic live at U+1D468/U+1D482.
        // No Unicode digit block exists, so digits keep the host
        // bold-italic font (KaTeX falls back to bold there —
        // accepted edge, same class as the mathit-digit note above).
        .bolditalic => .{ 0x1D468, 0x1D482, 0 },
        // .cal shares the script alphabet: MathML already unifies it
        // to the "script" variant (`variantFor`), and one host font
        // holds one script alphabet (KaTeX keeps two physical fonts —
        // accepted divergence, same class as the single-file host).
        .script, .cal => .{ 0x1D49C, 0x1D4B6, 0 },
    };
    const b = row[col];
    return if (b == 0) null else b;
}

/// Singleton LGC preassignments (names verified against Python
/// unicodedata, not memory): mathit h is the Planck slot U+210E;
/// script, fraktur and double-struck capitals with preassigned
/// singletons keep them, as do script small e/g/o.
fn alphaExc(fam: parse.FontFam, cp: u21) ?u21 {
    switch (fam) {
        .mathit => if (cp == 'h') return 0x210E,
        .frak => switch (cp) {
            'C' => return 0x212D,
            'H' => return 0x210C,
            'I' => return 0x2111,
            'R' => return 0x211C,
            'Z' => return 0x2128,
            else => {},
        },
        .bb => switch (cp) {
            'C' => return 0x2102,
            'H' => return 0x210D,
            'N' => return 0x2115,
            'P' => return 0x2119,
            'Q' => return 0x211A,
            'R' => return 0x211D,
            'Z' => return 0x2124,
            else => {},
        },
        .script, .cal => {
            switch (cp) {
                'B' => return 0x212C,
                'E' => return 0x2130,
                'F' => return 0x2131,
                'H' => return 0x210B,
                'I' => return 0x2110,
                'L' => return 0x2112,
                'M' => return 0x2133,
                'R' => return 0x211B,
                'e' => return 0x212F,
                'g' => return 0x210A,
                'o' => return 0x2134,
                else => {},
            }
        },
        else => {},
    }
    return null;
}

fn layoutAtom(lc: *LayCtx, style: parse.Style, class: symbols.AtomClass, fam: parse.FontFam, cp: u21) Error!u16 {
    _ = class;
    const size = lc.effSize(style);
    const font = fam.id();
    const rcp = mathAlpha(fam, cp) orelse cp;
    var g = lc.glyphId(font, rcp);
    // Host lacks the styled glyph (gid 0): fall back to the raw
    // codepoint rather than tofu (partial LM coverage, e.g. no
    // script small a/e — verified against the fixture cmap).
    if (g == 0 and rcp != cp) g = lc.glyphId(font, cp);
    const adv = lc.advance(font, g);
    const w = @divTrunc(adv * size, 1000);
    const e = lc.extents(font, g);
    // Dotless i/j under the default math face stand in for KaTeX's
    // math-italic ȷ/ı (issue #77): the host glyph is upright, so the
    // run shears it at the Computer Modern math-italic slant (1:4).
    // An explicit face wins (its wrapper supplies the variant).
    const shear: i16 = if ((cp == 0x131 or cp == 0x237) and fam == .rm) 250 else 0;
    return lc.allocBox(.{
        .w = w,
        .ha = @divTrunc(e[0] * size, 1000),
        .db = @divTrunc(e[1] * size, 1000),
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
        .x_shear = shear,
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
                const gl = @divTrunc(@as(i32, symbols.glueBetween(p, eff)) * lc.effSize(style), 1000);
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

/// Spacing class of a `\html@mathml` branch: KaTeX splices the
/// branch flat into the enclosing row (no ordgroup shell — pinned
/// 0.18.7: `\approxcoloncolon` shows no Rel–Ord thick glue), so a
/// braced single-composition branch exposes its content class for
/// spacing (issue #96). Multi-kid and logo branches keep today's
/// behavior (their first kid is Ord, as before).
fn htmlMathmlClass(pc: *const parse.ParseCtx, id: Idx) ?symbols.AtomClass {
    const n = parse.nodeAt(pc, id);
    if (n == .group) {
        const kids = parse.kidsOf(pc, n.group);
        if (kids.len == 0) return .Ord;
        return classOf(pc, kids[0]);
    }
    return classOf(pc, id);
}

/// Spacing class of a node, or null for transparent glue.
fn classOf(pc: *const parse.ParseCtx, id: Idx) ?symbols.AtomClass {
    const n = parse.nodeAt(pc, id);
    switch (n) {
        .atom => |a| return a.class,
        .op => return .Op,
        .opname => return .Op,
        .varlim => return .Op,
        // Braced groups act as Ord (TeX Book p.170).
        .group => return .Ord,
        .frac => return .Inner,
        .sqrt => return .Ord,
        .supsub => |s| return classOf(pc, s.base),
        .delim => return .Inner,
        .middle => return .Rel,
        .big => |b| return b.class,
        .accent => |a| return classOf(pc, a.nucleus) orelse .Ord,
        // KaTeX parity: `\stackrel` forces Rel; every other
        // over/under preserves Ord here (pinned 0.18.7).
        .over => |o| return if (o.kind == .stackrel) .Rel else .Ord,
        .style => |s| return classOf(pc, s.body),
        .size => |s| return classOf(pc, s.body),
        .classwrap => |c| return c.class,
        .font => |f| return classOf(pc, f.body),
        .pmb => |p| return classOf(pc, p.body),
        .reflect => |r| return classOf(pc, r.body),
        .vcenter => |v| return classOf(pc, v.body),
        .circled => |c| return classOf(pc, c.body),
        .text => return .Ord,
        .env => return .Ord,
        .substack => return .Ord,
        .mathchoice => return .Ord,
        .space, .vspace, .newline, .nbsp => return null,
        .hline => return null,
        .color => |c| return classOf(pc, c.body),
        .colorbox => return .Ord,
        .href => |h| return classOf(pc, h.body),
        // Spacing-transparent to the formula (a root-level tag never
        // takes inter-atom glue).
        .tag => |tg| return classOf(pc, tg.formula),
        .htmlwrap => |b| return classOf(pc, b),
        .phantom => |p| return classOf(pc, p.body),
        .boxed => return .Ord,
        .fbox => return .Ord,
        .htmlmathml => |h| return htmlMathmlClass(pc, h.html),
        .cancel => |c| return classOf(pc, c.body),
        .xcancel => |b| return classOf(pc, b),
        .phase => |b| return classOf(pc, b),
        .sout => |b| return classOf(pc, b),
        .lap => |l| return classOf(pc, l.body),
        .cdlabel => |c| return classOf(pc, c.body),
        // KaTeX wraps `\not` in `\mathrel` unconditionally.
        .not => return .Rel,
        .smash => |s| return classOf(pc, s.body),
        .raisebox => |r| return classOf(pc, r.body),
        .rule => return .Ord,
        .graphics => return .Ord,
    }
}

/// `\colorbox` / `\fcolorbox` (KaTeX parity, issue #35): text with a
/// padded background rule plus, for `\fcolorbox`, frame rules.
/// `\fboxsep` is 3pt; the frame is one rule thickness outside the
/// background. Unresolvable specs keep geometry but emit no paint
/// (the host renders ambient).
fn layoutColorBox(lc: *LayCtx, style: parse.Style, c: anytype) Error!u16 {
    const size = lc.effSize(style);
    const tb = try layoutText(lc, style, .{ .toks = c.body, .fam = parse.FontFam.rm });
    const t = lc.boxes[tb];
    const pad = @divTrunc(@as(i32, 300) * size, 1000);
    const bg = parse.resolveColorSpec(lc.pctx, c.bg);
    const has_frame = c.frame.len > 0;
    const frame = if (has_frame) parse.resolveColorSpec(lc.pctx, c.frame) else null;
    const th = @divTrunc(lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar) * size, 1000);
    const bgw = t.w + 2 * pad;
    const bgha = t.ha + pad;
    const bgdb = t.db + pad;
    const nkids: usize = 1 + (if (bg != null) @as(usize, 1) else 0) + (if (frame != null) @as(usize, 4) else 0);
    const s = try lc.allocKids(@intCast(nkids));
    var n: u16 = 0;
    if (bg) |bc| {
        const bb = try lc.allocBox(.{
            .w = bgw,
            .ha = bgha,
            .db = bgdb,
            .kind = .{ .rule = {} },
            .invisible = false,
            .color = bc,
        });
        lc.bkids[s + n] = .{ .box = bb, .dx = 0, .dy = 0 };
        n += 1;
    }
    lc.bkids[s + n] = .{ .box = tb, .dx = pad, .dy = 0 };
    n += 1;
    if (frame) |fc| {
        const top = try lc.allocBox(.{
            .w = bgw + 2 * th,
            .ha = th,
            .db = 0,
            .kind = .{ .rule = {} },
            .invisible = false,
            .color = fc,
        });
        // dy is baseline-shift UP (emit subtracts it): the top bar's
        // bottom edge sits on the background top edge, the bottom
        // bar's top edge on the background bottom edge, and the sides
        // span the full outer box symmetrically (dy = 0).
        lc.bkids[s + n] = .{ .box = top, .dx = -th, .dy = bgha };
        n += 1;
        const bot = try lc.allocBox(.{
            .w = bgw + 2 * th,
            .ha = 0,
            .db = th,
            .kind = .{ .rule = {} },
            .invisible = false,
            .color = fc,
        });
        lc.bkids[s + n] = .{ .box = bot, .dx = -th, .dy = -bgdb };
        n += 1;
        const side_ha = bgha + th;
        const side_db = bgdb + th;
        const left = try lc.allocBox(.{
            .w = th,
            .ha = side_ha,
            .db = side_db,
            .kind = .{ .rule = {} },
            .invisible = false,
            .color = fc,
        });
        lc.bkids[s + n] = .{ .box = left, .dx = -th, .dy = 0 };
        n += 1;
        const right = try lc.allocBox(.{
            .w = th,
            .ha = side_ha,
            .db = side_db,
            .kind = .{ .rule = {} },
            .invisible = false,
            .color = fc,
        });
        lc.bkids[s + n] = .{ .box = right, .dx = bgw, .dy = 0 };
        n += 1;
    }
    const fw = if (frame != null) bgw + 2 * th else bgw;
    const fha = if (frame != null) bgha + th else bgha;
    const fdb = if (frame != null) bgdb + th else bgdb;
    return lc.allocBox(.{
        .w = fw,
        .ha = fha,
        .db = fdb,
        .kind = .{ .list = .{ .start = s, .len = @intCast(n) } },
        .invisible = false,
    });
}

fn layoutOp(lc: *LayCtx, style: parse.Style, o: anytype) Error!u16 {
    if (o.func) {
        // Word operator in roman (`sin`, `lim`, ...). KaTeX defines the
        // limit inf/sup family as two words with a thin space
        // (`\liminf` = `\operatorname*{lim\,inf}`, issue #36).
        if (symbols.splitLimitOp(o.text)) |halves| {
            return layoutSplitWord(lc, lc.effSize(style), .rm, halves[0], halves[1]);
        }
        return layoutWord(lc, lc.effSize(style), .rm, o.text);
    }
    // Single-glyph operator, possibly large. KaTeX draws symbol
    // operators from Size1-Regular, swapping to Size2-Regular in
    // display style (issue #101) — at the ambient size, never scaled.
    // (No scalar fits both: LM sum ink needs 1.4x, LM integral 2x.)
    const size: u16 = lc.effSize(style);
    const font: u16 = @intFromEnum(if (o.large and style.isDisplay())
        contract.FontId.size2
    else
        contract.FontId.size1);
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

/// Two roman words joined by a thin kern (KaTeX `\,` = 3mu).
fn layoutSplitWord(lc: *LayCtx, size: u16, fam: parse.FontFam, a: []const u8, b: []const u8) Error!u16 {
    const wa = try layoutWord(lc, size, fam, a);
    const wb = try layoutWord(lc, size, fam, b);
    const ab = lc.boxes[wa];
    const bb = lc.boxes[wb];
    const gap: i32 = @divTrunc(@as(i32, 167) * size, 1000);
    const kb = try lc.allocBox(.{
        .w = gap,
        .ha = 0,
        .db = 0,
        .kind = .{ .kern = {} },
        .invisible = false,
    });
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = wa, .dx = 0, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = kb, .dx = ab.w, .dy = 0 };
    lc.bkids[s + 2] = .{ .box = wb, .dx = ab.w + gap, .dy = 0 };
    var ha = ab.ha;
    var db = ab.db;
    if (bb.ha > ha) ha = bb.ha;
    if (bb.db > db) db = bb.db;
    return lc.allocBox(.{
        .w = ab.w + gap + bb.w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

fn layoutOpName(lc: *LayCtx, style: parse.Style, o: anytype) Error!u16 {
    const size = lc.effSize(style);
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

fn layoutLimits(lc: *LayCtx, style: parse.Style, s: anytype) Error!u16 {
    const size = lc.effSize(style);
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
    var word_base = false;
    if (parse.opBase(lc.pctx, s.base)) |o| {
        if (parse.useLimits(style, o)) return layoutLimits(lc, style, s);
        word_base = o.func;
    }
    const size = lc.effSize(style);
    const base = try layoutNode(lc, style, s.base);
    const bb = lc.boxes[base];
    const sc_style = style.script();
    const sc_size = lc.effSize(sc_style);
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
    // KaTeX parity: a script on a horizontal brace is a brace *label*,
    // centered above (`\overbrace{..}^`) or below (`\underbrace{..}_`)
    // the brace span — never a side script. Matches the MathML
    // emitter, which nests these as `mover`/`munder` (pinned 0.18.7).
    // A lone side script (sub on overbrace / sup on underbrace) keeps
    // the ordinary side path below, as `msub`/`msup` do.
    switch (parse.nodeAt(lc.pctx, s.base)) {
        .over => |o| {
            const stack_sup = (o.kind == .overbrace or o.kind == .overbracket) and s.sup != NONE;
            const stack_sub = (o.kind == .underbrace or o.kind == .underbracket) and s.sub != NONE;
            if (stack_sup or stack_sub) {
                // KaTeX outer kern (pinned 0.18.7 `horizBrace.ts`,
                // issue #55): the label clears the brace INK by 0.2em.
                // Derive the ink edge from the base box when the hook
                // reports it; null keeps the legacy box + 150mu rule
                // bit-identically.
                const rfont: u16 = @intFromEnum(contract.FontId.rm);
                const is_bracket = o.kind == .overbracket or o.kind == .underbracket;
                const bgly = lc.glyphId(rfont, overGlyph(o.kind));
                var sup_top: ?i32 = null;
                var sub_bot: ?i32 = null;
                // Rule-drawn brackets fill their box edge to edge, so
                // the ink top/bottom IS the box top/bottom (KaTeX 0.2em
                // outer kern applies off it, no glyph lookup involved)
                // — except the overbracket's 30mu transparent crown:
                // the label kerns off the bar top.
                if (is_bracket) {
                    if (stack_sup) sup_top = bb.ha - @divTrunc(@as(i32, if (o.kind == .overbracket) 30 else 0) * lc.effSize(style), 1000);
                    if (stack_sub) sub_bot = bb.db;
                }
                if (!is_bracket and lc.ink(rfont, bgly) != null) {
                    const bib = lc.ink(rfont, bgly).?;
                    if (bib[3] > bib[1]) {
                        const bsize = lc.effSize(style);
                        const be = lc.extents(rfont, bgly);
                        const bha = @divTrunc(be[0] * bsize, 1000);
                        const bdb = @divTrunc(be[1] * bsize, 1000);
                        const iy0 = @divTrunc(bib[1] * bsize, 1000);
                        const iy1 = @divTrunc(bib[3] * bsize, 1000);
                        if (stack_sup) sup_top = bb.ha - bha + iy1;
                        if (stack_sub) sub_bot = bb.db - bdb - iy0;
                    }
                }
                return layoutBraceLabel(lc, style, base, bb, sup, sup_w, sup_ha, sup_db, s.sup != NONE, sup_top, sub, sub_w, sub_ha, sub_db, s.sub != NONE, sub_bot);
            }
        },
        else => {},
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
    // KaTeX leaves the script marginLeft null for non-symbol (word)
    // bases, so `\lim`-style word operators take no leading gap
    // (issue #101). Single-glyph bases keep the legacy 60mu gap.
    const script_gap: i32 = if (word_base) 0 else 60;
    _ = sc_size;
    const sx = bb.w + @divTrunc(script_gap * size, 1000);
    // MathKern cut-ins (provider v3): top-right tucks superscripts,
    // bottom-right tucks subscripts. The nucleus representative follows
    // the accent precedent (roman font + first codepoint). Clamped to
    // [0, gap]: adversarial hooks can neither overlap scripts nor push
    // them outward. Null hooks read 0: output is bit-identical.
    const kgap: i32 = sx - bb.w;
    const kglyph = lc.glyphId(@intFromEnum(contract.FontId.rm), nucleusFirstCp(lc.pctx, s.base));
    const cut_sup = if (has_sup)
        @min(@max(lc.kernCorr(@intFromEnum(contract.FontId.rm), kglyph, sup_up, .top_right), 0), kgap)
    else
        0;
    const cut_sub = if (has_sub)
        @min(@max(lc.kernCorr(@intFromEnum(contract.FontId.rm), kglyph, sub_down, .bottom_right), 0), kgap)
    else
        0;
    var parts: [3]BKid = undefined;
    var nparts: usize = 0;
    parts[0] = .{ .box = base, .dx = 0, .dy = 0 };
    nparts = 1;
    var ha = bb.ha;
    var db = bb.db;
    if (has_sup) {
        parts[nparts] = .{ .box = sup, .dx = sx - cut_sup, .dy = sup_up };
        nparts += 1;
        const top = sup_up + sup_ha;
        if (top > ha) ha = top;
        // A deep sup can hang below the baseline (tall content in the
        // superscript): the depth must cover it.
        if (sup_db > sup_up and sup_db - sup_up > db) db = sup_db - sup_up;
    }
    if (has_sub) {
        parts[nparts] = .{ .box = sub, .dx = sx - cut_sub, .dy = -sub_down };
        nparts += 1;
        const bot = sub_down + sub_db;
        if (bot > db) db = bot;
        // A tall sub can reach above the baseline (tall content in the
        // subscript): the height must cover it.
        if (sub_ha > sub_down and sub_ha - sub_down > ha) ha = sub_ha - sub_down;
    }
    // Right edges account the tuck; identical to the old `sx + sw`
    // when both cuts are 0 (kgap > 0 keeps the base edge inside).
    var w = bb.w;
    if (has_sup and sx - cut_sup + sup_w > w) w = sx - cut_sup + sup_w;
    if (has_sub and sx - cut_sub + sub_w > w) w = sx - cut_sub + sub_w;
    const s2 = try lc.allocKids(nparts);
    @memcpy(lc.bkids[s2 .. s2 + nparts], parts[0..nparts]);
    return lc.allocBox(.{
        .w = w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s2, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

/// Brace-label stacking for `\overbrace{..}^` / `\underbrace{..}_`
/// (KaTeX nests these as `mover`/`munder`): each present script is
/// centered on the brace span with the overset gap (150mu, same rule
/// as `layoutOver`). The caller guarantees at least one present
/// script; a lone side script never reaches here.
fn layoutBraceLabel(
    lc: *LayCtx,
    style: parse.Style,
    base: u16,
    bb: Box,
    sup: u16,
    sup_w: i32,
    sup_ha: i32,
    sup_db: i32,
    has_sup: bool,
    sup_top: ?i32,
    sub: u16,
    sub_w: i32,
    sub_ha: i32,
    sub_db: i32,
    has_sub: bool,
    sub_bot: ?i32,
) Error!u16 {
    const size = lc.effSize(style);
    // KaTeX outer kern is 0.2em off the brace ink (issue #55); the
    // legacy 150mu off the extents box applies only when the caller
    // has no ink edge (null hook), bit-identically.
    const sup_gap: i32 = @divTrunc(@as(i32, if (sup_top != null) 200 else 150) * size, 1000);
    const sub_gap: i32 = @divTrunc(@as(i32, if (sub_bot != null) 200 else 150) * size, 1000);
    var w = bb.w;
    if (has_sup and sup_w > w) w = sup_w;
    if (has_sub and sub_w > w) w = sub_w;
    const n: usize = 1 + (if (has_sup) @as(usize, 1) else 0) + (if (has_sub) @as(usize, 1) else 0);
    const k = try lc.allocKids(n);
    lc.bkids[k] = .{ .box = base, .dx = @divTrunc(w - bb.w, 2), .dy = 0 };
    var ha = bb.ha;
    var db = bb.db;
    var i: usize = 1;
    if (has_sup) {
        const sy = (sup_top orelse bb.ha) + sup_gap + sup_db;
        lc.bkids[k + i] = .{ .box = sup, .dx = @divTrunc(w - sup_w, 2), .dy = sy };
        ha = sy + sup_ha;
        i += 1;
    }
    if (has_sub) {
        const sy = -((sub_bot orelse bb.db) + sub_gap + sub_ha);
        lc.bkids[k + i] = .{ .box = sub, .dx = @divTrunc(w - sub_w, 2), .dy = sy };
        db = -sy + sub_db;
    }
    return lc.allocBox(.{
        .w = w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = k, .len = @intCast(n) } },
        .invisible = false,
    });
}

fn layoutFrac(lc: *LayCtx, style: parse.Style, f: anytype) Error!u16 {
    const size = lc.effSize(style);
    // Display fractions arrive pre-wrapped in a style node, so the
    // ambient style already carries the fraction's sizing.
    const num = try layoutNode(lc, style.numerator(), f.num);
    const den = try layoutNode(lc, style.denominator(), f.den);
    const nb = lc.boxes[num];
    const dbx = lc.boxes[den];
    const th0 = lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar);
    var th = f.kind.thick;
    if (th == 0) th = th0;
    const axis = @divTrunc((@as(i32, 250) * size), 1000);
    const pad: i32 = 120;
    var content = if (nb.w > dbx.w) nb.w else dbx.w;
    content += 2 * pad;
    // TeX Rules 15b-e (KaTeX `genfrac.ts`, Main metrics in thousandths
    // of an em — the reference font agrees to the unit, see
    // `otmath` ground truth): style-dependent numerator/denominator
    // shifts plus a minimum clearance, bumped when tall content
    // would collide. One fix covers the whole fraction family
    // (issue #32).
    const disp = style.isDisplay();
    var ns: i32 = undefined;
    var ds: i32 = undefined;
    var clear: i32 = undefined;
    if (f.kind.bar) {
        if (disp) {
            ns = 677;
            ds = 686;
            clear = 3 * th;
        } else {
            ns = 394;
            ds = 345;
            clear = th;
        }
        ns = @divTrunc(ns * size, 1000);
        ds = @divTrunc(ds * size, 1000);
        clear = @divTrunc(clear * size, 1000);
        // Rule 15d/e: keep `clear` between content and the bar.
        const gap_n = (ns - nb.db) - (axis + @divTrunc(th, 2));
        if (gap_n < clear) ns += clear - gap_n;
        const gap_d = (axis - @divTrunc(th, 2)) - (dbx.ha - ds);
        if (gap_d < clear) ds += clear - gap_d;
    } else {
        if (disp) {
            ns = 677;
            ds = 686;
            clear = 7 * th0;
        } else {
            ns = 444;
            ds = 345;
            clear = 3 * th0;
        }
        ns = @divTrunc(ns * size, 1000);
        ds = @divTrunc(ds * size, 1000);
        clear = @divTrunc(clear * size, 1000);
        // Rule 15b/c: keep `clear` between numerator and denominator,
        // split evenly.
        const cand = (ns - nb.db) - (dbx.ha - ds);
        if (cand < clear) {
            const bump = @divTrunc(clear - cand + 1, 2);
            ns += bump;
            ds += bump;
        }
    }
    if (!f.kind.bar) {
        // Atop/binom: stacked shifts, no rule.
        const s = try lc.allocKids(2);
        lc.bkids[s] = .{ .box = num, .dx = @divTrunc(content - nb.w, 2), .dy = ns };
        lc.bkids[s + 1] = .{ .box = den, .dx = @divTrunc(content - dbx.w, 2), .dy = -ds };
        var b = try lc.allocBox(.{
            .w = content,
            .ha = ns + nb.ha,
            .db = ds + dbx.db,
            .kind = .{ .list = .{ .start = s, .len = 2 } },
            .invisible = false,
        });
        switch (f.kind.fence) {
            .none => {},
            .parens => b = try wrapFence(lc, style, b, '(', ')'),
            .braces => b = try wrapFence(lc, style, b, '{', '}'),
            .brackets => b = try wrapFence(lc, style, b, '[', ']'),
        }
        return b;
    }
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = num, .dx = @divTrunc(content - nb.w, 2), .dy = ns };
    lc.bkids[s + 1] = .{ .box = den, .dx = @divTrunc(content - dbx.w, 2), .dy = -ds };
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
        .ha = ns + nb.ha,
        .db = ds + dbx.db,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

/// TeX Rule 15e (KaTeX `genfrac.ts`, cmex sigma20/21 in thousandths
/// of an em): barless-stack fences target a FIXED height — delim1 in
/// display, delim2 elsewhere — never grown to content.
fn rule15eNeed(style: parse.Style) i32 {
    return switch (style) {
        .D, .Dc => 2390,
        .T, .Tc => 1010,
        .S, .Sc, .SS, .SSc => 1157,
    };
}

/// Fence pair around a barless stack (`\\choose`/`\\brace`/`\\brack`,
/// the `\\binom` family): Rule 15e fixed-size delimiters, axis
/// centered, abutting the content (issue #112 — KaTeX runs identical
/// machinery for the whole family and for `\\genfrac` delimiters, so
/// `\\binom{a}{b}` and `\\genfrac(){0pt}{1}{a}{b}` agree).
fn wrapFence(lc: *LayCtx, style: parse.Style, inner: u16, left: u21, right: u21) Error!u16 {
    const ib = lc.boxes[inner];
    const size = lc.effSize(style);
    const need = @divTrunc(rule15eNeed(style) * size, 1000);
    const lp = try layoutFence(lc, style, left, need, true);
    const rp = try layoutFence(lc, style, right, need, true);
    const lb = lc.boxes[lp];
    const rb = lc.boxes[rp];
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = lp, .dx = 0, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = inner, .dx = lb.w, .dy = 0 };
    lc.bkids[s + 2] = .{ .box = rp, .dx = lb.w + ib.w, .dy = 0 };
    var ha = ib.ha;
    var db = ib.db;
    if (lb.ha > ha) ha = lb.ha;
    if (lb.db > db) db = lb.db;
    if (rb.ha > ha) ha = rb.ha;
    if (rb.db > db) db = rb.db;
    return lc.allocBox(.{
        .w = lb.w + ib.w + rb.w,
        .ha = ha,
        .db = db,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

fn layoutSqrt(lc: *LayCtx, style: parse.Style, s: anytype) Error!u16 {
    const size = lc.effSize(style);
    // TeX sets the radicand in cramped style (D' in display): sups
    // inside rise 30mu less. Also makes Dc reachable for the atom grid.
    const rad = try layoutNode(lc, style.cramped(), s.radicand);
    const rb = lc.boxes[rad];
    // KaTeX parity, pinned 0.18.7 `sqrt.js` (TeXbook Rule 11): theta is
    // the default rule thickness; phi is the x-height in display styles,
    // theta otherwise. The vinculum uses the radical rule
    // (`sqrtRuleThickness`, 0.04em on the fixture) — not the fraction
    // bar, which grows to 0.049 in script styles while the vinculum
    // does not.
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const th = lc.ruleTh(font, .fraction_bar);
    const rw = lc.ruleTh(font, .radical);
    const phi = if (style.isDisplay()) @divTrunc(x_height_1000 * size, 1000) else th;
    const clearance0 = th + @divTrunc(phi, 4);
    // Radical sign, grown through the variant hook when available.
    // i64 with saturation: adversarial providers may return huge
    // rules or extents, and layout must stay total (never panic).
    const g0 = lc.glyphId(font, 0x221A);
    const need64: i64 = @as(i64, rb.ha) + rb.db + clearance0 + th;
    const arg64 = @divTrunc(need64 * 1000, size);
    const argcut = std.math.clamp(arg64, @as(i64, std.math.minInt(i32)), @as(i64, std.math.maxInt(i32)));
    const g = lc.variant(font, g0, @intCast(argcut));
    const gadv = lc.advance(font, g);
    const ge = lc.extents(font, g);
    const gw = @divTrunc(gadv * size, 1000);
    const gha = @divTrunc(ge[0] * size, 1000);
    const gdb = @divTrunc(ge[1] * size, 1000);
    // An oversized radical splits its excess half above (the clearance
    // grows, lifting the rule) and half below — KaTeX's `delimDepth`
    // adjustment, so the tail never takes the whole overshoot.
    const delim_depth: i64 = @as(i64, gha) + gdb - rw;
    var clearance = clearance0;
    if (delim_depth > @as(i64, rb.ha) + rb.db + clearance0) {
        const grown = @divTrunc(delim_depth + clearance0 - rb.ha - rb.db, 2);
        const growncut = std.math.clamp(grown, @as(i64, std.math.minInt(i32)), @as(i64, std.math.maxInt(i32)));
        clearance = @intCast(growncut);
    }
    // Rule sits above the radicand; the radical rises to meet it.
    const rule_top = rb.ha + clearance + rw;
    const kern: i32 = @divTrunc((@as(i32, 50) * size), 1000);
    const over: i32 = @divTrunc((@as(i32, 40) * size), 1000);
    const rad_x = gw + kern;
    const content_w = rad_x + rb.w + over;
    const rule_y = rule_top - @divTrunc(rw, 2);
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
    // Junction (issue #56, KaTeX `sqrtMain` single-path parity): the
    // vinculum must OVERLAP the surd hook ink, not abut the advance
    // edge — an abutting rect + glyph rasterizes a light seam. KaTeX
    // draws bar and surd as one path with the bar starting inside the
    // hook overhang, so with ink metrics the bar starts one rule
    // thickness inside the hook's right ink edge, clamped to [ink
    // left, advance]. Null-hook providers keep the legacy
    // advance-edge start bit-identically. Weight is deliberately
    // untouched (option (a): KaTeX-numeric 0.04em parity per AGENTS.md;
    // the LM fixture's thicker surd strokes are host-font character).
    const join: i32 = blk: {
        if (lc.ink(font, g)) |sib| {
            if (sib[3] > sib[1] and sib[2] > sib[0]) {
                const six1 = @divTrunc(sib[2] * size, 1000);
                const six0 = @divTrunc(sib[0] * size, 1000);
                const start = @min(gw, @max(six0, six1 - rw));
                break :blk gw - start;
            }
        }
        break :blk 0;
    };
    const rule_dx = rad_x - kern - join;
    const rule_w = rb.w + over + kern + join;
    lc.bkids[s1] = .{ .box = gb, .dx = 0, .dy = rad_dy };
    lc.bkids[s1 + 1] = .{ .box = rad, .dx = rad_x, .dy = 0 };
    const ruleb = try lc.allocBox(.{
        .w = rule_w,
        .ha = @divTrunc(rw + 1, 2),
        .db = rw - @divTrunc(rw + 1, 2),
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    lc.bkids[s1 + 2] = .{ .box = ruleb, .dx = rule_dx, .dy = rule_y };
    var ha = rule_top;
    var db = rb.db;
    const gtop = rad_dy + gha;
    if (gtop > ha) ha = gtop;
    const gbot = -(rad_dy - gdb);
    if (gbot > db) db = gbot;
    var total_w = content_w;
    // Optional root index (KaTeX parity, pinned 0.18.7 `sqrt.js`, TeX
    // `\r@@t`): always scriptscript, raised 0.6 x (body height minus
    // body depth), tucked with +5mu / -10mu side bearings. The -10mu
    // tuck can push a narrow index's body left of the ink box, so the
    // whole construction normalizes right instead (`pad`); internal
    // index-vs-body geometry stays KaTeX-exact, and the non-negativity
    // invariant holds by construction.
    if (s.index != NONE) {
        const idx = try layoutNode(lc, style.script().script(), s.index);
        const ib = lc.boxes[idx];
        const lead = @divTrunc(@as(i32, 5) * size, 18);
        const trail = @divTrunc(@as(i32, 10) * size, 18);
        const body_dx = lead + ib.w - trail;
        const pad = if (body_dx < 0) -body_dx else 0;
        const idx_dy = @divTrunc(@as(i32, 6) * (ha - db), 10);
        // Prepend: shift existing parts right — rebuild with 4 kids.
        const s2 = try lc.allocKids(4);
        lc.bkids[s2] = .{ .box = idx, .dx = pad + lead, .dy = idx_dy };
        lc.bkids[s2 + 1] = .{ .box = gb, .dx = pad + body_dx, .dy = rad_dy };
        lc.bkids[s2 + 2] = .{ .box = rad, .dx = pad + body_dx + rad_x, .dy = 0 };
        lc.bkids[s2 + 3] = .{ .box = ruleb, .dx = pad + body_dx + rule_dx, .dy = rule_y };
        total_w = pad + body_dx + content_w;
        const itop = idx_dy + ib.ha;
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

/// One fence glyph for `need` (total height, TeX `make_left_right`
/// target). KaTeX `traverseSequence` tries the Main-face base
/// delimiter first (pinned 0.18.7 `delimiters.js`): when it covers
/// `need` it is emitted at natural extents, never grown nor centered
/// (issue #102 — the Main design carries the heavier KaTeX stroke).
/// Otherwise the rm glyph grows through the variant hook and the box
/// centers on the math axis.
fn layoutFence(lc: *LayCtx, style: parse.Style, cp: u21, need: i32, variant_box: bool) Error!u16 {
    const size = lc.effSize(style);
    const main_font: u16 = @intFromEnum(contract.FontId.main);
    const mg = lc.glyphId(main_font, cp);
    if (mg != 0) {
        const me = lc.extents(main_font, mg);
        const mha = @divTrunc(me[0] * size, 1000);
        const mdb = @divTrunc(me[1] * size, 1000);
        if (mha + mdb > need) {
            const madv = lc.advance(main_font, mg);
            return lc.allocBox(.{
                .w = @divTrunc(madv * size, 1000),
                .ha = mha,
                .db = mdb,
                .kind = .{ .glyph = .{ .font = main_font, .size = size, .glyph = mg } },
                .invisible = false,
            });
        }
    }
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g0 = lc.glyphId(font, cp);
    const g = if (need > 0) lc.variant(font, g0, @divTrunc(need * 1000, size)) else g0;
    const adv = lc.advance(font, g);
    const w = @divTrunc(adv * size, 1000);
    const e = lc.extents(font, g);
    var ha = @divTrunc(e[0] * size, 1000);
    var db = @divTrunc(e[1] * size, 1000);
    if (need > 0) {
        // Center the grown fence on the math axis. Rule 15e fences
        // (issue #112) box the picked variant instead of the target —
        // KaTeX's span follows its `delimsizing sizeN` glyph, so with
        // a real font the box is the ~1.2em size-1 paren, not the
        // 1.01em target; without variants the target always wins, so
        // stub integers never move.
        var total = need;
        if (variant_box) {
            const vt = ha + db;
            if (vt > total) total = vt;
        }
        const axis = @divTrunc((@as(i32, 250) * size), 1000);
        const half = @divTrunc(total + 1, 2);
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
    // `\middle` separators grown to the full fence height. Rule 15e
    // fixed delimiters (`\genfrac`, issue #112) skip the probe —
    // `\middle` requires `\left`, so none can occur — and target the
    // fixed height instead of growing to content.
    var need: i32 = undefined;
    if (d.fixed) {
        need = @divTrunc(rule15eNeed(style) * lc.effSize(style), 1000);
    } else {
        // TeX `make_left_right` target (KaTeX `delimiters.js`,
        // issue #102): the fence covers the body's max distance
        // from the axis, grown by delimiterFactor 901/500 with a
        // 5pt (500mu at 10pt/em) shortfall allowance.
        lc.fence_need = 0;
        const probe = try layoutNode(lc, style, d.body);
        const pb = lc.boxes[probe];
        const size = lc.effSize(style);
        const axis = @divTrunc(@as(i32, 250) * size, 1000);
        const dist_a = pb.ha - axis;
        const dist_b = pb.db + axis;
        const max_dist = if (dist_a > dist_b) dist_a else dist_b;
        const shortfall = @divTrunc(@as(i32, 500) * size, 1000);
        const grow = @divTrunc(max_dist * 901, 500);
        const span = 2 * max_dist - shortfall;
        need = if (grow > span) grow else span;
        lc.fence_need = need;
    }
    const body = try layoutNode(lc, style, d.body);
    const bb = lc.boxes[body];
    lc.fence_need = prev_need;
    const s = try lc.allocKids(3);
    var x: i32 = 0;
    var ha = bb.ha;
    var db = bb.db;
    if (d.left != 0) {
        const f = try layoutFence(lc, style, d.left, need, d.fixed);
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
        const f = try layoutFence(lc, style, d.right, need, d.fixed);
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
    const size = lc.effSize(style);
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

/// Raster stretch factor (per-mille) to span `span` with a glyph of
/// natural width `nat`: stretch-only, so narrow constructions keep
/// the centered fixed glyph bit-identically (issues #31/#37).
fn spanScale(span: i32, nat: i32) u16 {
    if (nat <= 0 or span <= nat) return 1000;
    const q = @divTrunc(span * 1000, nat);
    return if (q > 65535) 65535 else @intCast(q);
}

fn layoutAccent(lc: *LayCtx, style: parse.Style, a: anytype) Error!u16 {
    const size = lc.effSize(style);
    const nuc = try layoutNode(lc, style, a.nucleus);
    const nb = lc.boxes[nuc];
    // Narrow accents resolve through the Main face (issue #103):
    // KaTeX sets every accent from Main, whose designs our reference
    // font does not match (Main ^ ink is half the LM width). Wide
    // accents keep rm: their assembly is pinned separately (#31).
    const font: u16 = if (a.wide)
        @intFromEnum(contract.FontId.rm)
    else
        @intFromEnum(contract.FontId.main);
    const g = lc.glyphId(font, a.cp);
    const adv = lc.advance(font, g);
    const e = lc.extents(font, g);
    const aw = @divTrunc(adv * size, 1000);
    const aha = @divTrunc(e[0] * size, 1000);
    const adb = @divTrunc(e[1] * size, 1000);
    // KaTeX clearance (pinned 0.18.7 `accent.ts`): the accent tucks to
    // within an x-height of the body top — clearance = min(body
    // height, x-height), so tall bases (issue #30: `M`, `\theta`)
    // carry the accent near their cap, not 120 units above it.
    const xh = @divTrunc(x_height_1000 * size, 1000);
    const clearance = if (nb.ha < xh) nb.ha else xh;
    // KaTeX accent placement (pinned 0.18.7 `accent` builder, issue
    // #70): the accent centers at nucleus-center + skew, where skew is
    // the base glyph's full metrics skew — not half. Two lookups feed
    // it: the italic correction of the LAID-OUT nucleus glyph (the
    // parse codepoint still names the ASCII base, whose correction
    // differs: LM text `M` has none, math-italic U+1D440 has 102), plus
    // KaTeX's Math-Italic skew table for slanted nuclei (LM Math and
    // KaTeX advances agree to the unit, so the CM-derived shifts
    // transfer). Upright and unlisted nuclei keep shift 0, exactly as
    // KaTeX's zero-skew metrics do.
    const ng = nucleusFirstGlyph(lc, nuc);
    const ic1000: i32 = if (ng) |found| lc.italicCorr(found.font, found.glyph) else 0;
    const ic = @divTrunc(ic1000 * @as(i32, size), 1000);
    // KaTeX gates the shift on shifty accents over single-symbol
    // nuclei only: wide (`\widetilde` etc.) and multi-symbol
    // (`\tilde{AB}`) nuclei stay centered.
    const shifty = !a.wide and nucleusIsSingle(lc.pctx, a.nucleus);
    const ncp = nucleusFirstCp(lc.pctx, a.nucleus);
    const kskew1000: i32 = if (shifty and ng != null and ng.?.font == @intFromEnum(contract.FontId.math_italic))
        symbols.mathItalicSkew(ncp)
    else
        0;
    const kskew = @divTrunc(kskew1000 * @as(i32, size), 1000);
    const shift: i32 = if (shifty) @divTrunc(ic, 2) + kskew else 0;
    // v4 ink refinement (null hook = exact v3 behavior): the clipped
    // extents above lose where ink really starts, so low-sitting
    // accents (`~`, ink bottom +193mu) would nestle into the nucleus
    // while high ones (`^`, ink bottom +562mu) clear it. Calibrated
    // against pinned KaTeX 0.18.7 ground-truth pixels (check 94, hat
    // 125, dot 141, vec 94, tilde ~160mu): accent ink must clear the
    // nucleus top by at least `min_gap` (130mu), and zero-advance
    // combining marks (U+20D7 ink hangs left of its origin) center by
    // ink, not advance.
    const min_gap: i32 = @divTrunc(@as(i32, 130) * size, 1000);
    const ink = lc.ink(font, g);
    var ink_ax: ?i32 = null;
    var ink_lift: ?i32 = null;
    if (ink) |ib| {
        const ix0 = @divTrunc(ib[0] * size, 1000);
        const iy0 = @divTrunc(ib[1] * size, 1000);
        const ix1 = @divTrunc(ib[2] * size, 1000);
        if (ix1 > ix0) {
            const inkw = ix1 - ix0;
            if (adv == 0) ink_ax = @divTrunc(nb.w - inkw, 2) - ix0 + shift;
            ink_lift = nb.ha + min_gap - iy0;
        }
    }
    // KaTeX parity (pinned 0.18.7 `defineMacro`): `\dddot` / `\ddddot`
    // stack three / four period glyphs, not the combining marks
    // U+20DB/U+20DC. The row behaves like one accent glyph below.
    const n_dots: usize = if (a.cp == 0x20DB) 3 else if (a.cp == 0x20DC) 4 else 0;
    var dot_boxes: [4]u16 = undefined;
    var dot_aw: i32 = aw;
    var dot_aha: i32 = aha;
    var dot_adb: i32 = adb;
    if (n_dots > 0) {
        const dg = lc.glyphId(font, '.');
        const dadv = @divTrunc(lc.advance(font, dg) * size, 1000);
        const de = lc.extents(font, dg);
        dot_aw = dadv * @as(i32, @intCast(n_dots));
        dot_aha = @divTrunc(de[0] * size, 1000);
        dot_adb = @divTrunc(de[1] * size, 1000);
        for (dot_boxes[0..n_dots], 0..) |*db, i| {
            db.* = try lc.allocBox(.{
                .w = dadv,
                .ha = dot_aha,
                .db = dot_adb,
                .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = dg } },
                .invisible = false,
            });
            _ = i;
        }
    }
    const ab = try lc.allocBox(.{
        .w = aw,
        .ha = aha,
        .db = adb,
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
    // KaTeX widths (issue #31): a narrow accent lives in a zero-width
    // `accent-body` (a wider-than-base accent overhangs symmetrically)
    // and a wide accent stretches to the nucleus span via the run
    // raster scale (the layout box keeps the span; the backend
    // stretches the ink). Either way the construction is exactly as
    // wide as the nucleus.
    const w = nb.w;
    var ax = ink_ax orelse @divTrunc(nb.w - aw, 2) + shift;
    if (a.wide and n_dots == 0) {
        // KaTeX parity (pinned 0.18.7): wide accents are SVGs stretched
        // to 100% of the nucleus span (`preserveAspectRatio="none"`),
        // so the accent INK spans the nucleus — not the advance box
        // (issue #58: the caron advance already covers AB, so
        // advance-stretch never fired and the check covered only part
        // of the nucleus). With ink metrics, scale ink to the span and
        // center it; without them keep the advance-box rule below
        // bit-identically.
        var ink_sc: u16 = 1000;
        if (ink) |ib| {
            const jx0 = @divTrunc(ib[0] * size, 1000);
            const jx1 = @divTrunc(ib[2] * size, 1000);
            if (jx1 > jx0) {
                const jsc = spanScale(nb.w, jx1 - jx0);
                if (jsc > 1000) {
                    ink_sc = jsc;
                    ax = @divTrunc(nb.w, 2) + shift -
                        @divTrunc((jx0 + jx1) * @as(i32, jsc), 2000);
                }
            }
        }
        if (ink_sc > 1000) {
            lc.boxes[ab].x_scale = ink_sc;
            lc.boxes[ab].w = nb.w;
        } else {
            const sc = spanScale(nb.w, aw);
            if (sc > 1000) {
                lc.boxes[ab].x_scale = sc;
                lc.boxes[ab].w = nb.w;
                ax = shift;
            }
        }
    }
    var ay = nb.ha - clearance + adb;
    if (ink_lift) |lift| {
        // Ink must clear the nucleus top (uniform floor; the base
        // rule already clears it for high-sitting accents, so this
        // only ever lifts low ones).
        if (lift > ay) ay = lift;
    }
    if (n_dots > 0) {
        // Dot runs center like oversets: the box is the wider of the
        // nucleus and the row, both centered, so no run ever starts
        // left of the ink box (non-negativity invariant). Period ink
        // sits on its baseline, so the row takes the same minimum-gap
        // lift as low accents when the hook reports ink.
        const dw = if (nb.w > dot_aw) nb.w else dot_aw;
        const dax = @divTrunc(dw - dot_aw, 2) + shift;
        var day = nb.ha - clearance + dot_adb;
        if (lc.ink(font, lc.glyphId(font, '.'))) |pib| {
            const piy0 = @divTrunc(pib[1] * size, 1000);
            const pix1 = @divTrunc(pib[2] * size, 1000);
            if (pix1 > @divTrunc(pib[0] * size, 1000)) {
                const plift = nb.ha + min_gap - piy0;
                if (plift > day) day = plift;
            }
        }
        const s = try lc.allocKids(1 + n_dots);
        lc.bkids[s] = .{ .box = nuc, .dx = @divTrunc(dw - nb.w, 2), .dy = 0 };
        const dadv_each = @divTrunc(dot_aw, @as(i32, @intCast(n_dots)));
        for (dot_boxes[0..n_dots], 0..) |db, i| {
            lc.bkids[s + 1 + i] = .{
                .box = db,
                .dx = dax + dadv_each * @as(i32, @intCast(i)),
                .dy = day,
            };
        }
        return lc.allocBox(.{
            .w = dw,
            .ha = day + dot_aha,
            .db = nb.db,
            .kind = .{ .list = .{ .start = s, .len = @intCast(1 + n_dots) } },
            .invisible = false,
        });
    }
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

/// First laid-out glyph of a nucleus box, for metric lookups that must
/// see the substituted glyph (issue #70): parse codepoints still name
/// the ASCII base (`M`), but the box carries the math-italic glyph
/// (U+1D440) whose italic correction differs (102 vs 0 for LM `M`).
fn nucleusFirstGlyph(lc: *LayCtx, id: u16) ?struct { font: u16, glyph: u16 } {
    const b = lc.boxes[id];
    switch (b.kind) {
        .glyph => |g| return .{ .font = g.font, .glyph = g.glyph },
        .list => |r| {
            const kids = lc.bkids[r.start .. r.start + r.len];
            for (kids) |k| {
                if (nucleusFirstGlyph(lc, k.box)) |found| return found;
            }
            return null;
        },
        .kern, .empty, .rule, .diag => return null,
    }
}

/// Whether a nucleus is one bare symbol (issue #70): KaTeX applies
/// accent skew only then, leaving everything else centered. Pinned
/// 0.18.7 DOM proof: `\tilde M` shifts +1.62px (full skew) while
/// `\tilde{AB}`, `\tilde{x^2}`, and `\tilde{\mathit{M}}` all measure
/// dead-centered (≤0.02px) — only brace-group singletons unwrap, and
/// font/style/supsub/wrapper nuclei block the shift.
fn nucleusIsSingle(pc: *const parse.ParseCtx, id: Idx) bool {
    const n = parse.nodeAt(pc, id);
    switch (n) {
        .atom => return true,
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            return kids.len == 1 and nucleusIsSingle(pc, kids[0]);
        },
        else => return false,
    }
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
        .size => |s| return nucleusFirstCp(pc, s.body),
        .classwrap => |c| return nucleusFirstCp(pc, c.body),
        .pmb => |p| return nucleusFirstCp(pc, p.body),
        .reflect => |r| return nucleusFirstCp(pc, r.body),
        .vcenter => |v| return nucleusFirstCp(pc, v.body),
        .circled => |c| return nucleusFirstCp(pc, c.body),
        .sout => |b| return nucleusFirstCp(pc, b),
        .phase => |b| return nucleusFirstCp(pc, b),
        else => return 'x',
    }
}

fn overGlyph(kind: parse.OverKind) u21 {
    return switch (kind) {
        .overbrace => 0x23DE,
        .underbrace => 0x23DF,
        .overbracket => 0x23B4,
        .underbracket => 0x23B5,
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
        .overgroup => 0x23E0,
        .undergroup => 0x23E1,
        // No host glyph: KaTeX's MathML has no mapping either and
        // emits the literal text `undefined` (pinned 0.18.7 quirk,
        // mirrored by the emitter); layout uses the missing glyph.
        .overlinesegment, .underlinesegment => 0,
        .overleftharpoon, .xleftharpoonup => 0x21BC,
        .overrightharpoon, .xrightharpoonup => 0x21C0,
        .overRightarrow, .xdoubleright => 0x21D2,
        .underbar => 0x203E,
        .utilde => 0x007E,
        .xdoubleleft => 0x21D0,
        .xdoubleboth => 0x21D4,
        .xleftharpoondown => 0x21BD,
        .xleftrightharpoons => 0x21CB,
        .xlongequal => 0x003D,
        .xrightharpoondown => 0x21C1,
        .xrightleftharpoons => 0x21CC,
        .xtofrom => 0x21C4,
        else => 0,
    };
}

fn layoutOver(lc: *LayCtx, style: parse.Style, o: anytype) Error!u16 {
    const size = lc.effSize(style);
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const th = lc.ruleTh(font, .overline);
    const gap: i32 = @divTrunc((@as(i32, 150) * size), 1000);
    switch (o.kind) {
        // KaTeX renders `\underbar` with the exact underline
        // construction (pinned 0.18.7: same `katex-underline` span,
        // same 0.04em rule), not a font glyph (issue #96).
        .overline, .underline, .underbar => {
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
        .overset, .underset, .stackrel => {
            const nuc = try layoutNode(lc, style, o.nucleus);
            const nb = lc.boxes[nuc];
            const sup = try layoutNode(lc, style.script(), o.extra);
            const sb = lc.boxes[sup];
            const w = if (nb.w > sb.w) nb.w else sb.w;
            const nx = @divTrunc(w - nb.w, 2);
            const sx = @divTrunc(w - sb.w, 2);
            const s = try lc.allocKids(2);
            if (o.kind == .overset or o.kind == .stackrel) {
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
        .angl => {
            return layoutAngl(lc, style, o.nucleus);
        },
        else => {
            // Brace / arrow overs: glyph above or below the nucleus,
            // extensible-arrow labels in script style.
            if (o.kind == .overlinesegment or o.kind == .underlinesegment) {
                // KaTeX parity (pinned 0.18.7 `stretchy.ts`, issue
                // #96): segments are stroked like square brackets —
                // there is no host glyph (the old path emitted the
                // missing glyph, rendering nothing). The SVG image is
                // 522 tall with a 40mu shaft (y 241..281) and 40mu
                // end caps spanning y 94..428, windowed contiguously
                // over the nucleus (min span 0.888em).
                const is_under = o.kind == .underlinesegment;
                const nuc = try layoutNode(lc, style, o.nucleus);
                const nb = lc.boxes[nuc];
                const minw = @divTrunc(@as(i32, 888) * size, 1000);
                const w = if (nb.w > minw) nb.w else minw;
                const bar40 = @divTrunc(@as(i32, 40) * size, 1000);
                const cap_lo = @divTrunc(@as(i32, 94) * size, 1000);
                const cap_hi = @divTrunc(@as(i32, 334) * size, 1000);
                const img522 = @divTrunc(@as(i32, 522) * size, 1000);
                const shaft_lo = @divTrunc(@as(i32, 241) * size, 1000);
                const shaft = try lc.allocBox(.{
                    .w = w,
                    .ha = @divTrunc(bar40 + 1, 2),
                    .db = bar40 - @divTrunc(bar40 + 1, 2),
                    .kind = .{ .rule = {} },
                    .invisible = false,
                });
                const cap = try lc.allocBox(.{
                    .w = bar40,
                    .ha = cap_hi,
                    .db = 0,
                    .kind = .{ .rule = {} },
                    .invisible = false,
                });
                const s = try lc.allocKids(4);
                const nx = @divTrunc(w - nb.w, 2);
                lc.bkids[s] = .{ .box = nuc, .dx = nx, .dy = 0 };
                const sh_db = lc.boxes[shaft].db;
                const sh_ha = lc.boxes[shaft].ha;
                if (!is_under) {
                    lc.bkids[s + 1] = .{ .box = shaft, .dx = 0, .dy = nb.ha + shaft_lo + sh_db };
                    lc.bkids[s + 2] = .{ .box = cap, .dx = 0, .dy = nb.ha + cap_lo };
                    lc.bkids[s + 3] = .{ .box = cap, .dx = w - bar40, .dy = nb.ha + cap_lo };
                    return lc.allocBox(.{
                        .w = w,
                        .ha = nb.ha + img522,
                        .db = nb.db,
                        .kind = .{ .list = .{ .start = s, .len = 4 } },
                        .invisible = false,
                    });
                } else {
                    lc.bkids[s + 1] = .{ .box = shaft, .dx = 0, .dy = -(nb.db + shaft_lo + sh_ha) };
                    lc.bkids[s + 2] = .{ .box = cap, .dx = 0, .dy = -(nb.db + cap_lo + cap_hi) };
                    lc.bkids[s + 3] = .{ .box = cap, .dx = w - bar40, .dy = -(nb.db + cap_lo + cap_hi) };
                    return lc.allocBox(.{
                        .w = w,
                        .ha = nb.ha,
                        .db = nb.db + img522,
                        .kind = .{ .list = .{ .start = s, .len = 4 } },
                        .invisible = false,
                    });
                }
            }
            if (o.kind == .overbracket or o.kind == .underbracket) {
                // KaTeX parity (pinned 0.18.7 `stretchy.ts`, issue
                // #51): square brackets are drawn from strokes, not a
                // font glyph — minimum span 1.6em, 0.1em clearance off
                // the nucleus. The SVG paths decompose exactly: legs
                // 290mu + bar 120mu, plus 30mu transparent above the
                // over-bar (overbracket height 440, underbracket 410),
                // so growth over the nucleus is 540mu over / 510mu
                // under.
                const is_under = o.kind == .underbracket;
                const nuc = try layoutNode(lc, style, o.nucleus);
                const nb = lc.boxes[nuc];
                const minw = @divTrunc(@as(i32, 1600) * size, 1000);
                const w = if (nb.w > minw) nb.w else minw;
                const sth = @divTrunc(@as(i32, 120) * size, 1000);
                const cgap = @divTrunc(@as(i32, 100) * size, 1000);
                const drop = @divTrunc(@as(i32, 290) * size, 1000);
                const tpad = if (is_under) 0 else @divTrunc(@as(i32, 30) * size, 1000);
                const bar = try lc.allocBox(.{
                    .w = w,
                    .ha = sth,
                    .db = 0,
                    .kind = .{ .rule = {} },
                    .invisible = false,
                });
                const leg = try lc.allocBox(.{
                    .w = sth,
                    .ha = drop,
                    .db = 0,
                    .kind = .{ .rule = {} },
                    .invisible = false,
                });
                const s = try lc.allocKids(4);
                const nx = @divTrunc(w - nb.w, 2);
                lc.bkids[s] = .{ .box = nuc, .dx = nx, .dy = 0 };
                if (!is_under) {
                    const ly = nb.ha + cgap;
                    lc.bkids[s + 1] = .{ .box = bar, .dx = 0, .dy = ly + drop };
                    lc.bkids[s + 2] = .{ .box = leg, .dx = 0, .dy = ly };
                    lc.bkids[s + 3] = .{ .box = leg, .dx = w - sth, .dy = ly };
                    return lc.allocBox(.{
                        .w = w,
                        .ha = ly + drop + sth + tpad,
                        .db = nb.db,
                        .kind = .{ .list = .{ .start = s, .len = 4 } },
                        .invisible = false,
                    });
                } else {
                    const ly = -(nb.db + cgap);
                    lc.bkids[s + 1] = .{ .box = bar, .dx = 0, .dy = ly - drop - sth };
                    lc.bkids[s + 2] = .{ .box = leg, .dx = 0, .dy = ly - drop };
                    lc.bkids[s + 3] = .{ .box = leg, .dx = w - sth, .dy = ly - drop };
                    return lc.allocBox(.{
                        .w = w,
                        .ha = nb.ha,
                        .db = -ly + drop + sth,
                        .kind = .{ .list = .{ .start = s, .len = 4 } },
                        .invisible = false,
                    });
                }
            }
            const is_under = o.kind == .underbrace or o.kind == .underleft or
                o.kind == .underright or o.kind == .underboth or o.kind == .undergroup or
                o.kind == .underlinesegment or o.kind == .underbar or o.kind == .utilde;
            const is_x = o.kind == .xleft or o.kind == .xright or o.kind == .xboth or
                o.kind == .xhookleft or o.kind == .xhookright or o.kind == .xmapsto or
                o.kind == .xtwoheadleft or o.kind == .xtwoheadright or o.kind == .xdoubleleft or
                o.kind == .xdoubleboth or o.kind == .xdoubleright or o.kind == .xleftharpoondown or
                o.kind == .xleftharpoonup or o.kind == .xleftrightharpoons or o.kind == .xlongequal or
                o.kind == .xrightharpoondown or o.kind == .xrightharpoonup or
                o.kind == .xrightleftharpoons or o.kind == .xtofrom;
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
                // A missing over-label (CD `@=`, whose KaTeX
                // `\cdlongequal` call passes no labels) contributes
                // an empty box; every other x-arrow carries a group.
                const above = if (o.extra != NONE)
                    try layoutNode(lc, style.script(), o.extra)
                else blk: {
                    const s = try lc.allocKids(0);
                    break :blk try lc.allocBox(.{
                        .w = 0,
                        .ha = 0,
                        .db = 0,
                        .kind = .{ .list = .{ .start = s, .len = 0 } },
                        .invisible = false,
                    });
                };
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
                // Extensible x-arrows (issue #104): KaTeX windows the
                // shaft SVG over the label span (pinned 0.18.7
                // `stretchy.ts`), so the glyph raster-stretches to it
                // (same `spanScale`/`x_scale` model as braces below).
                const gsc = spanScale(w, gw);
                const gdx: i32 = if (gsc > 1000) 0 else @divTrunc(w - gw, 2);
                if (gsc > 1000) {
                    lc.boxes[gb].x_scale = gsc;
                    lc.boxes[gb].w = w;
                }
                const s = try lc.allocKids(if (has_below) 3 else 2);
                const gy: i32 = 0;
                const ay = gha + gap + ab.db;
                lc.bkids[s] = .{ .box = gb, .dx = gdx, .dy = gy };
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
            // KaTeX stretches the brace to the nucleus span: the box is
            // the nucleus width and the single host glyph raster-stretches
            // to it (stretch-only: a wider fixed glyph keeps the old
            // centered/clamped behavior). Over/under arrows, groups, the
            // double arrow, single harpoons, and the under-bar stretch
            // the same way (issue #104): KaTeX windows each shaft+head
            // SVG over the content span (pinned 0.18.7 `stretchy.ts`,
            // minWidth 0.888em — already covered since the host arrow
            // advance meets it). The tilde keeps its fixed wide-accent
            // behavior and the segment kinds have no host glyph.
            const is_brace = o.kind == .overbrace or o.kind == .underbrace;
            const is_group = o.kind == .overgroup or o.kind == .undergroup;
            const is_tilde = o.kind == .utilde;
            const stretchy = switch (o.kind) {
                .overleft, .overright, .overboth,
                .underleft, .underright, .underboth,
                .overgroup, .undergroup,
                .overleftharpoon, .overrightharpoon,
                .overRightarrow, .utilde,
                => true,
                else => false,
            };
            // KaTeX minWidth 0.888em for the windowed-SVG overs
            // (pinned 0.18.7 `katexImagesData`); the tilde sizes at
            // 100% like the other wide accents, and braces keep
            // their exact span (issue #96).
            const minw = @divTrunc(@as(i32, 888) * size, 1000);
            var w = if (is_brace) nb.w else if (nb.w > gw) nb.w else gw;
            if (stretchy and !is_tilde and w < minw) w = minw;
            // A fixed host glyph wider than the span cannot center
            // without leaving the ink box (negative run x breaks the
            // non-negativity invariant); clamp it at the left edge —
            // it overhangs right, toward the following material.
            var gx = if (is_brace) @max(@divTrunc(w - gw, 2), 0) else @divTrunc(w - gw, 2);
            if (is_brace or stretchy) {
                const sc = spanScale(w, gw);
                if (sc > 1000) {
                    lc.boxes[gb].x_scale = sc;
                    lc.boxes[gb].w = w;
                    gx = 0;
                }
            }
            const s = try lc.allocKids(2);
            // KaTeX clearance (pinned 0.18.7 `horizBrace.ts`, issue
            // #55): brace↔nucleus kern is 0.1em ink-to-ink. The host
            // brace glyph carries empty space below/above its ink
            // (LM U+23DE ink bottom sits 539mu above its baseline, so
            // the extents rule compounded to 0.69em of daylight), so
            // with ink metrics the brace baseline drops until the ink
            // edge lands exactly 100mu from the nucleus. Arrows and
            // null-hook providers keep the legacy rule bit-identically.
            const bgap: i32 = @divTrunc(@as(i32, 100) * size, 1000);
            // Groups stack contiguously (KaTeX vlist = nucleus +
            // 0.342em: no clearance — the SVG's own transparent top
            // provides the daylight); braces keep the 0.1em
            // ink-to-ink kern (issue #96).
            const eff_bgap: i32 = if (is_group) 0 else bgap;
            const bink = if (is_brace or is_group) lc.ink(font, gg) else null;
            const bink_ok = if (bink) |bib| bib[3] > bib[1] else false;
            if (!is_under) {
                var gy = nb.ha + gap + gdb;
                if (bink_ok) {
                    const iy0 = @divTrunc(bink.?[1] * size, 1000);
                    gy = nb.ha + eff_bgap - iy0;
                }
                lc.bkids[s] = .{ .box = nuc, .dx = @divTrunc(w - nb.w, 2), .dy = 0 };
                lc.bkids[s + 1] = .{ .box = gb, .dx = gx, .dy = gy };
                return lc.allocBox(.{
                    .w = w,
                    .ha = gy + gha,
                    .db = nb.db,
                    .kind = .{ .list = .{ .start = s, .len = 2 } },
                    .invisible = false,
                });
            } else {
                var gy = -(nb.db + gap + gha);
                if (bink_ok) {
                    const iy1 = @divTrunc(bink.?[3] * size, 1000);
                    gy = -(nb.db + eff_bgap + iy1);
                }
                lc.bkids[s] = .{ .box = nuc, .dx = @divTrunc(w - nb.w, 2), .dy = 0 };
                lc.bkids[s + 1] = .{ .box = gb, .dx = gx, .dy = gy };
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

// Emit one pending text span decoration: circled accent or strike
// rule (shared by the in-loop check and the end flush).
// Returns how much wider the span became (a wider-than-span circle
// pushes following text right); the caller adds it to the cursor.
fn emitTextSpan(lc: *LayCtx, font: u16, size: u16, px0: i32, is_circle: bool,
    x: i32, ha: *i32, db: *i32, parts: *[256]BKid, nparts: *usize, p0: usize) Error!i32 {
    if (is_circle) {
        // Enclosing ring (issue #80, pinned 0.18.7 browser pixels):
        // same model as the math-mode `.circled` arm — the U+25EF
        // baseline coincides with the span baseline, so the body
        // sits INSIDE the ring and a tall body overflows the ring
        // top while the ring stays put. Body and ring center in
        // the max-width construction (`text-align: center` on
        // KaTeX's accent vlist; pixel proof: symmetric 33/31px
        // side pads). The span widens to the ring when narrower.
        // Text glyphs carry no KaTeX skew, so the ring centers
        // with no shift.
        const cg = lc.glyphId(font, 0x25EF);
        const cadv = lc.advance(font, cg);
        const caw = @divTrunc(cadv * size, 1000);
        const ce = lc.extents(font, cg);
        const caha = @divTrunc(ce[0] * size, 1000);
        const cadb = @divTrunc(ce[1] * size, 1000);
        const cb = try lc.allocBox(.{
            .w = caw,
            .ha = caha,
            .db = cadb,
            .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = cg } },
            .invisible = false,
        });
        const span_w = x - px0;
        const box_w = if (span_w > caw) span_w else caw;
        // Center the already-emitted body parts (indices p0..)
        // under the ring; the ring centers too. Nested span parts
        // shift along, keeping their relative layout.
        const shift = @divTrunc(box_w - span_w, 2);
        if (shift > 0) {
            var k: usize = p0;
            while (k < nparts.*) : (k += 1) parts.*[k].dx += shift;
        }
        // Ring baseline height above the span baseline: zero (body
        // baseline), centered like KaTeX's vlist.
        const cady: i32 = 0;
        if (nparts.* >= 256) return error.NoSpace;
        parts.*[nparts.*] = .{ .box = cb, .dx = px0 + @divTrunc(box_w - caw, 2), .dy = cady };
        nparts.* += 1;
        const catop = cady + caha;
        if (catop > ha.*) ha.* = catop;
        const cabot = cadb - cady;
        if (cabot > db.*) db.* = cabot;
        return box_w - span_w;
    } else {
        // Strike rule across the span at half x-height (same
        // geometry as the math sout node).
        const th = @divTrunc(@as(i32, 80) * size, 1000);
        const strike = @divTrunc(x_height_1000 * size, 2000);
        const rb = try lc.allocBox(.{
            .w = x - px0,
            .ha = @divTrunc(th + 1, 2),
            .db = th - @divTrunc(th + 1, 2),
            .kind = .{ .rule = {} },
            .invisible = false,
        });
        if (nparts.* >= 256) return error.NoSpace;
        parts.*[nparts.*] = .{ .box = rb, .dx = px0, .dy = strike };
        nparts.* += 1;
        const rtop = strike + @divTrunc(th + 1, 2);
        if (rtop > ha.*) ha.* = rtop;
        return 0;
    }
}

fn layoutText(lc: *LayCtx, style: parse.Style, t: anytype) Error!u16 {
    const size = lc.effSize(style);
    const fam = lc.fam_subst orelse t.fam;
    const font = fam.id();
    var parts: [256]BKid = undefined;
    var nparts: usize = 0;
    var x: i32 = 0;
    var ha: i32 = 0;
    var db: i32 = 0;
    // Pending strike/circle spans (textcircled, sout): each entry
    // decorates the slice [x0, current x) once the argument end index
    // is reached. Bounded depth; deeper nesting is NoSpace.
    var pend_x0: [4]i32 = undefined;
    var pend_end: [4]usize = undefined;
    var pend_circle: [4]bool = undefined;
    var pend_p0: [4]usize = undefined;
    var npend: u8 = 0;
    const toks = parse.toksOf(lc.pctx, t.toks);
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        while (npend > 0 and pend_end[npend - 1] <= i) {
            npend -= 1;
            x += try emitTextSpan(lc, font, size, pend_x0[npend], pend_circle[npend],
                x, &ha, &db, &parts, &nparts, pend_p0[npend]);
        }
        const tk = toks[i];
        var cp: u21 = 0;
        var is_space = false;
        switch (tk.kind) {
            .char => {
                // `~` is a non-breaking space in text (KaTeX parity);
                // the `\~` accent command is handled below.
                if (tk.cp == ' ' or tk.cp == '~') {
                    is_space = true;
                } else {
                    cp = tk.cp;
                }
            },
            // Grouping braces are transparent in text (KaTeX parity);
            // `\{` / `\}` stay literal via the `.ctrl` arm below.
            .lbrace, .rbrace => continue,
            .newline => is_space = true,
            .ctrl => {
                // Text-mode command (`\i`, `\textdollar`, ...; full
                // profile only).
                if (comptime active_profile == .full) {
                    // Argument-taking text commands: circled overlay
                    // and strikeout queue a pending span over a char
                    // or braced group argument (KaTeX parity: a missing
                    // argument rejects, an empty group is fine).
                    if (symbols.lookupTextArg(tk.name)) |ta| {
                        var j = i + 1;
                        if (j < toks.len and toks[j].kind == .lbrace) {
                            var depth: usize = 1;
                            j += 1;
                            while (j < toks.len and depth > 0) : (j += 1) {
                                if (toks[j].kind == .lbrace) depth += 1;
                                if (toks[j].kind == .rbrace) depth -= 1;
                            }
                            if (depth > 0) return error.Invalid;
                        } else {
                            // Skip interword space (TeX control-word
                            // space skipping): the argument is the next
                            // real token. The skipped spaces vanish —
                            // resume iteration at the argument so no
                            // phantom space is typeset inside the span
                            // (issue #70: it offset `\textcircled b`).
                            while (j < toks.len and (toks[j].kind == .newline or
                                (toks[j].kind == .char and toks[j].cp == ' '))) j += 1;
                            if (j >= toks.len) return error.Invalid;
                            if (npend >= pend_x0.len) return error.NoSpace;
                            pend_x0[npend] = x;
                            pend_end[npend] = j + 1;
                            pend_circle[npend] = ta == .circled;
                            pend_p0[npend] = nparts;
                            npend += 1;
                            i = j - 1;
                            continue;
                        }
                        if (npend >= pend_x0.len) return error.NoSpace;
                        pend_x0[npend] = x;
                        pend_end[npend] = j;
                        pend_circle[npend] = ta == .circled;
                        pend_p0[npend] = nparts;
                        npend += 1;
                        continue;
                    }
                }
                const tcp = if (comptime active_profile == .full)
                    symbols.lookupText(tk.name)
                else
                    null;
                if (tcp) |c2| {
                    cp = c2;
                } else {
                    const c = tk.name[0];
                    switch (c) {
                        '{', '}', '%', '&', '#', '_', '$', '|', '/' => cp = c,
                        // Spacing commands in text mode are spacing
                        // (KaTeX `mspace`), never literal `,`/`:`/`;`
                        // glyphs (issues #36, #38).
                        ',', ':', ';', '!', '>' => {
                            const w: i16 = switch (c) {
                                ',' => parse.space_thin,
                                ':', '>' => parse.space_med,
                                ';' => parse.space_thick,
                                else => -parse.space_thin,
                            };
                            const kw = @divTrunc(@as(i32, w) * size, 1000);
                            const kb = try lc.allocBox(.{
                                .w = kw,
                                .ha = 0,
                                .db = 0,
                                .kind = .{ .kern = {} },
                                .invisible = false,
                            });
                            if (nparts >= 256) return error.NoSpace;
                            parts[nparts] = .{ .box = kb, .dx = x, .dy = 0 };
                            nparts += 1;
                            x += kw;
                            continue;
                        },
                        ' ' => is_space = true,
                        else => {
                            // Text accent: precompose with the next
                            // char; KaTeX also takes a braced single
                            // letter (`\'{a}`).
                            const acc = parse.textAccentCp(c) orelse return error.Invalid;
                            if (i + 1 >= toks.len) return error.Invalid;
                            var nx = toks[i + 1];
                            if (nx.kind == .lbrace) {
                                if (i + 3 >= toks.len) return error.Invalid;
                                if (toks[i + 2].kind != .char or toks[i + 3].kind != .rbrace)
                                    return error.Invalid;
                                nx = toks[i + 2];
                                i += 2;
                            }
                            if (nx.kind != .char) return error.Invalid;
                            i += 1;
                            if (parse.precompose(acc, nx.cp)) |pcp| {
                                cp = pcp;
                            } else {
                                // No precomposed form (KaTeX accepts every
                                // letter here and overlays the accent):
                                // emit the base plus a zero-advance spacing
                                // accent above it (below for cedilla).
                                const scp = parse.mathTextAccentCp(c) orelse return error.Invalid;
                                const below = acc == 0x0327;
                                const bg = lc.glyphId(font, nx.cp);
                                const badv = lc.advance(font, bg);
                                const bw = @divTrunc(badv * size, 1000);
                                const be = lc.extents(font, bg);
                                const bha = @divTrunc(be[0] * size, 1000);
                                const bdb = @divTrunc(be[1] * size, 1000);
                                const bb = try lc.allocBox(.{
                                    .w = bw,
                                    .ha = bha,
                                    .db = bdb,
                                    .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = bg } },
                                    .invisible = false,
                                });
                                if (nparts >= 256) return error.NoSpace;
                                parts[nparts] = .{ .box = bb, .dx = x, .dy = 0 };
                                nparts += 1;
                                x += bw;
                                if (bha > ha) ha = bha;
                                if (bdb > db) db = bdb;
                                const ag = lc.glyphId(font, scp);
                                const aadv = lc.advance(font, ag);
                                const aw = @divTrunc(aadv * size, 1000);
                                const ae = lc.extents(font, ag);
                                const aha = @divTrunc(ae[0] * size, 1000);
                                const adb = @divTrunc(ae[1] * size, 1000);
                                const ab = try lc.allocBox(.{
                                    .w = aw,
                                    .ha = aha,
                                    .db = adb,
                                    .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = ag } },
                                    .invisible = false,
                                });
                                // KaTeX clearance shape: the accent tucks to
                                // within an x-height of the base top.
                                const xh = @divTrunc(x_height_1000 * size, 1000);
                                const clear = if (bha < xh) bha else xh;
                                const adx = x - bw + @divTrunc(bw - aw, 2);
                                const ady = if (below)
                                    -(bdb + clear + aha)
                                else
                                    bha - clear + adb;
                                if (nparts >= 256) return error.NoSpace;
                                parts[nparts] = .{ .box = ab, .dx = adx, .dy = ady };
                                nparts += 1;
                                const atop = ady + aha;
                                if (atop > ha) ha = atop;
                                const abot = adb - ady;
                                if (abot > db) db = abot;
                                continue;
                            }
                        },
                    }
                }
            },
            else => return error.Invalid,
        }
        if (is_space) {
            const sw = @divTrunc((@as(i32, parse.space_interword) * size), 1000);
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
    // Flush spans ending exactly at the text end (the in-loop
    // check only runs for live indices).
    while (npend > 0) {
        npend -= 1;
        x += try emitTextSpan(lc, font, size, pend_x0[npend], pend_circle[npend],
            x, &ha, &db, &parts, &nparts, pend_p0[npend]);
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

/// Display equation tag (`\tag`, issue #73): the formula box with
/// the tag text after a `\qquad` gap. The core has no page width, so
/// KaTeX's right-margin alignment degrades to a fixed 2em separation;
/// both share the baseline. The non-star parentheses are paren glyph
/// boxes here (the MathML emitter writes them as `mtext`; same shared
/// `starred` decision, medium-appropriate rendering).
fn layoutTag(lc: *LayCtx, style: parse.Style, tg: anytype) Error!u16 {
    const fb = try layoutNode(lc, style, tg.formula);
    const tb = try layoutNode(lc, style, tg.body);
    const fam: parse.FontFam = lc.fam_subst orelse .rm;
    // Formula, `\qquad` gap, then the parenthesized tag (`\tag*`
    // skips the parens). Order: `(`, body, `)`. Under `leqno` the
    // tag block leads instead (KaTeX left-tags, issue #120).
    var ids: [4]u16 = undefined;
    var nids: usize = 0;
    // `leqno` is full-profile surface (subset entry points always
    // pass false): the tag always trails in subset binaries.
    const left: bool = if (comptime active_profile == .full) lc.pctx.leqno else false;
    if (!left) {
        ids[0] = fb;
        nids = 1;
    }
    if (!tg.starred) {
        ids[nids] = try layoutAtom(lc, style, .Ord, fam, '(');
        nids += 1;
    }
    ids[nids] = tb;
    nids += 1;
    if (!tg.starred) {
        ids[nids] = try layoutAtom(lc, style, .Ord, fam, ')');
        nids += 1;
    }
    const fb_pos: usize = if (left) blk: {
        ids[nids] = fb;
        nids += 1;
        break :blk nids - 1;
    } else 0;
    // The gap sits between the formula and the tag block, on the
    // formula's outer side (after it by default, before it left).
    const gap_before: usize = if (left) fb_pos else 1;
    var parts: [4]BKid = undefined;
    var nparts: usize = 0;
    var x: i32 = 0;
    var ha: i32 = 0;
    var db: i32 = 0;
    for (ids[0..nids], 0..) |id, k| {
        if (k == gap_before) x += scale(lc, 2000, style);
        const b = lc.boxes[id];
        parts[nparts] = .{ .box = id, .dx = x, .dy = 0 };
        nparts += 1;
        x += b.w;
        if (b.ha > ha) ha = b.ha;
        if (b.db > db) db = b.db;
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
    dash: bool,
};

fn layoutEnv(lc: *LayCtx, style: parse.Style, e: anytype) Error!u16 {
    const size = lc.effSize(style);
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
            if (hlineDashed(lc.pctx, id)) |dash| {
                cells[nrows][c] = .{ .id = 0, .w = 0, .ha = 0, .db = 0, .is_rule = true, .dash = dash };
            } else {
                // Display-cases cells are displaystyle (KaTeX parity);
                // smallmatrix is scriptstyle; top-level display envs
                // (align/equation/gather/CD/split) are displaystyle
                // like their KaTeX `styling` wrappers; everything
                // else textstyle.
                const cell_style = if (e.kind == .smallmatrix or e.kind == .subarray)
                    parse.Style.S
                else if (e.kind == .dcases or e.kind == .drcases or e.kind == .alignenv or
                    e.kind == .alignat or e.kind == .equation or e.kind == .gather or
                    e.kind == .split or e.kind == .cd)
                    parse.Style.D
                else
                    parse.Style.T;
                const b = try layoutNode(lc, cell_style, id);
                const bb = lc.boxes[b];
                cells[nrows][c] = .{ .id = b, .w = bb.w, .ha = bb.ha, .db = bb.db, .is_rule = false, .dash = false };
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
        .array, .alignedat, .alignat => {
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
            // The fill above clobbers `col`; the spec count is what
            // clamps short rows (issue #33: every array laid out 8
            // columns, leaving dead whitespace on the right).
            const speccols = col;
            while (col < 8) : (col += 1) col_align[col] = 1;
            if (speccols != ncols) {
                // Rows may carry fewer cells (pad) but not more.
                if (ncols > speccols) return error.Invalid;
                ncols = speccols;
            }
        },
        .aligned, .alignenv, .split => {
            var col: usize = 0;
            while (col < 8) : (col += 1) col_align[col] = if (col % 2 == 0) 2 else 0;
        },
        .cases, .dcases, .drcases, .rcases => {
            col_align[0] = 0;
            var col: usize = 1;
            while (col < 8) : (col += 1) col_align[col] = 0;
        },
        .subarray => {
            // One required [c|l] code (parse stores a single spec);
            // KaTeX parity: more than one column rejects.
            const spec1 = parse.kidsOf(lc.pctx, parse.Range{ .start = e.spec_start, .len = e.spec_len });
            const fill: u8 = if (spec1.len == 1) @intCast(spec1[0]) else 1;
            var col: usize = 0;
            while (col < 8) : (col += 1) col_align[col] = fill;
            if (ncols > 1) return error.Invalid;
        },
        else => {
            // Starred matrix envs store one [l|c|r] code for every
            // column (parse default: centered); unstarred forms carry
            // no spec and stay centered.
            const spec1 = parse.kidsOf(lc.pctx, parse.Range{ .start = e.spec_start, .len = e.spec_len });
            const fill: u8 = if (spec1.len == 1) @intCast(spec1[0]) else 1;
            var col: usize = 0;
            while (col < 8) : (col += 1) col_align[col] = fill;
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
    // `\arraystretch` scaling (issue #141): the 0.28em base gap
    // scales with the env factor (smallmatrix/subarray fix 0.5, so
    // their 0.14em falls out unchanged). i64 headroom: size and the
    // factor are both small, but their product need not be.
    const row_gap: i32 = blk: {
        const g: i64 = @divTrunc(@as(i64, 280) * @as(i64, size) * @as(i64, e.stretch), 1000000);
        break :blk if (g > std.math.maxInt(i32)) std.math.maxInt(i32) else @intCast(g);
    };
    // Hardcoded 0.04em vline weight under the `minRuleThickness`
    // floor (issue #118): identical to the bare constant when the
    // floor is 0 (the default).
    const vline_w: i32 = lc.constRule(size);
    // KaTeX column separation (pinned 0.18.7 `array.ts`, issue #33):
    // each column carries a pre/post gap; `array` additionally pads
    // the outer edges. Defaults are 0.5em each side (1em between
    // columns, none outside); `aligned` rl pairs touch with 1em
    // between pairs; `alignedat` has none; `cases` separates its
    // columns with 1em; `smallmatrix` uses thickspace at script size.
    const dsep: i32 = @divTrunc((@as(i32, 500) * size), 1000);
    const qsep: i32 = @as(i32, size); // 1em quad in ambient units
    const ssep: i32 = @divTrunc((@as(i32, 194) * size), 1000);
    var pre: [8]i32 = .{0} ** 8;
    var post: [8]i32 = .{0} ** 8;
    var outer: i32 = 0;
    switch (e.kind) {
        .array => {
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                pre[i] = dsep;
                post[i] = dsep;
            }
            outer = dsep;
        },
        .smallmatrix, .subarray => {
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                pre[i] = ssep;
                post[i] = ssep;
            }
        },
        .aligned, .alignenv, .split => {
            var i: usize = 2;
            while (i < 8) : (i += 2) pre[i] = qsep;
        },
        .cases, .dcases, .drcases, .rcases => post[0] = qsep,
        .alignedat, .alignat, .gathered, .equation, .gather => {},
        .cd => {
            // amscd parity (pinned 0.18.7): `\enskip` between
            // columns, i.e. 0.25em pre + 0.25em post each side.
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                pre[i] = @divTrunc(size, 4);
                post[i] = @divTrunc(size, 4);
            }
        },
        else => {
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                pre[i] = dsep;
                post[i] = dsep;
            }
        },
    }
    // Total width.
    var total_w: i32 = outer;
    var c: usize = 0;
    while (c < ncols) : (c += 1) {
        total_w += pre[c] + colw[c] + post[c];
        if (vlines[c + 1]) total_w += vline_w;
    }
    if (vlines[0]) total_w += vline_w;
    total_w += outer;
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
    // Row dy shifts, rebased so the table centers on the math axis
    // (KaTeX parity, issue #33): the first-row baseline used to
    // anchor the table, which rode delimiters high. `first_up` is the
    // first-row baseline height above the parent baseline.
    var row_base: [64]i32 = undefined;
    var y: i32 = 0;
    const r0 = row_ha[0];
    r = 0;
    while (r < nrows) : (r += 1) {
        y += row_ha[r];
        row_base[r] = r0 - y;
        // Each row adds its own `\\[size]` gap after the shared
        // base gap (KaTeX `rowGaps`, issues #140/#144); the trailing
        // row's gap comes back off below, like the base gap.
        y += row_db[r] + row_gap + scaleRowGap(rows[r].gap_after, size);
    }
    const total_h = y - row_gap - scaleRowGap(rows[nrows - 1].gap_after, size);
    const axis = @divTrunc((@as(i32, 250) * size), 1000);
    const first_up = axis + @divTrunc(total_h, 2) - r0;
    r = 0;
    while (r < nrows) : (r += 1) row_base[r] += first_up;
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
    var cx: i32 = outer;
    if (vlines[0]) cx += vline_w;
    c = 0;
    while (c < ncols) : (c += 1) {
        colx[c] = cx + pre[c];
        cx += pre[c] + colw[c] + post[c];
        if (vlines[c + 1]) cx += vline_w;
    }
    r = 0;
    while (r < nrows) : (r += 1) {
        const base = row_base[r];
        var cc: usize = 0;
        while (cc < ncols_per_row[r]) : (cc += 1) {
            const cell = cells[r][cc];
            if (cell.is_rule) {
                // Row rules span the table at the provider rule
                // thickness; `\hdashline` tiles dashes (KaTeX parity).
                const th = @divTrunc(lc.ruleTh(@intFromEnum(contract.FontId.rm), .fraction_bar) * size, 1000);
                if (cell.dash) {
                    const dl = 3 * th;
                    const gp = 2 * th;
                    var x: i32 = 0;
                    while (x < total_w) {
                        var w = dl;
                        if (x + w > total_w) w = total_w - x;
                        const db2 = try lc.allocBox(.{
                            .w = w,
                            .ha = @divTrunc(th + 1, 2),
                            .db = th - @divTrunc(th + 1, 2),
                            .kind = .{ .rule = {} },
                            .invisible = false,
                        });
                        try emit(&parts, &nparts, db2, x, base);
                        x += w + gp;
                    }
                } else {
                    const rb = try lc.allocBox(.{
                        .w = total_w,
                        .ha = @divTrunc(th + 1, 2),
                        .db = th - @divTrunc(th + 1, 2),
                        .kind = .{ .rule = {} },
                        .invisible = false,
                    });
                    try emit(&parts, &nparts, rb, 0, base);
                }
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
                const vx: i32 = if (vc == 0) 0 else colx[vc - 1] + colw[vc - 1] + post[vc - 1];
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
    // dy convention: baseline shift UP from parent baseline; row
    // shifts above are already axis-rebased, so the box is symmetric
    // about the math axis (KaTeX parity, issue #33).
    const box_ha = axis + @divTrunc(total_h, 2);
    return lc.allocBox(.{
        .w = total_w,
        .ha = box_ha,
        .db = total_h - box_ha,
        .kind = .{ .list = .{ .start = s, .len = @intCast(nparts) } },
        .invisible = false,
    });
}

/// Row-rule detection: a bare rule node, or a group wrapping exactly
/// one (rule rows are stashed bare; the group form covers legacy
/// single-rule cells). Returns dashedness (issue #33).
fn hlineDashed(pc: *const parse.ParseCtx, id: Idx) ?bool {
    const n = parse.nodeAt(pc, id);
    switch (n) {
        .hline => |h| return h.dashed,
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            if (kids.len != 1) return null;
            return hlineDashed(pc, kids[0]);
        },
        else => return null,
    }
}

fn layoutSubstack(lc: *LayCtx, style: parse.Style, r: parse.Range) Error!u16 {
    const rows = parse.rowsOf(lc.pctx, r.start, r.len);
    var parts: [128]BKid = undefined;
    var nparts: usize = 0;
    // KaTeX subarray (arraystretch 0.5, script cells, issue #101):
    // each row floors at the 0.42/0.18em strut and pitch is exactly
    // prev.db + next.ha — no extra gap.
    const size = lc.effSize(style);
    const strut_ha = @divTrunc(@as(i32, 420) * size, 1000);
    const strut_db = @divTrunc(@as(i32, 180) * size, 1000);
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
        heights[n] = .{ @max(bb.ha, strut_ha), @max(bb.db, strut_db) };
        n += 1;
    }
    var w: i32 = 0;
    for (widths[0..n]) |cw| {
        if (cw > w) w = cw;
    }
    // Stack dy shifts from the first-row baseline in place; the emit
    // loop below stays a plain load per row.
    var y: i32 = 0;
    const b0 = heights[0][0];
    var k: usize = 0;
    var bases: [64]i32 = undefined;
    while (k < n) : (k += 1) {
        y += heights[k][0];
        bases[k] = b0 - y;
        y += heights[k][1];
        // `\\[size]` between substack rows (issues #140/#144); the
        // last row's gap never applies (no following row).
        if (k + 1 < n) y += scaleRowGap(rows[k].gap_after, size);
    }
    const total = y;
    const first_base = total - b0;
    k = 0;
    while (k < n) : (k += 1) {
        if (nparts >= 128) return error.NoSpace;
        parts[nparts] = .{ .box = ids[k], .dx = @divTrunc(w - widths[k], 2), .dy = bases[k] };
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
    const size = lc.effSize(style);
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    const pad: i32 = @divTrunc((@as(i32, 300) * size), 1000);
    const th: i32 = lc.constRule(size);
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

/// KaTeX `isCharacterBox` (pinned 0.18.7 `buildCommon`: unwrap
/// single-child ordgroups and single-body colors, then true for
/// mathord/textord/atom): single-character strike bodies grow the
/// strike box 0.2em top and bottom, every other body 0.2em on each
/// side instead. Our `.atom` (any class: `+`, `=`, `\vert` count —
/// probed SINGLE) is the character node; math font wrappers unwrap
/// like KaTeX's font-at-symbol application, except `\boldsymbol` /
/// `\bm` (probed MULTI — the bold-italic `.font` stays opaque).
/// Sizing, text, scripts, boxes, and spacing wrappers never unwrap.
fn isSingleChar(pctx: *const parse.ParseCtx, id: Idx) bool {
    var cur = id;
    while (true) {
        switch (parse.nodeAt(pctx, cur)) {
            .atom => return true,
            .group => |g| {
                const kids = parse.kidsOf(pctx, g);
                if (kids.len != 1) return false;
                cur = kids[0];
            },
            .color => |c| cur = c.body,
            .font => |f| {
                if (f.fam == .bolditalic) return false;
                cur = f.body;
            },
            else => return false,
        }
    }
}

/// Actuarial angle mark (`\angl`, issue #108, pinned 0.18.7 enclose
/// angl branch + `stretchyEnclose`): top + right borders around the
/// padded nucleus (the `.angl` CSS box, not an SVG). The border box
/// spans the nucleus grown by 4 rule-thicknesses on top and
/// max(0, 0.25em − depth) below; horizontally the nucleus keeps the
/// `.anglpad` 0.03889em each side, plus the `.angl` margin-right
/// 0.03889em breathing room off the right border. Unlike the cancel
/// strikes the mark ADDS metrics (the vlist keeps the border box).
/// Border thickness scales linearly with the effective size (script
/// styles keep 0.04em; KaTeX's 0.049 size-class bump for real fonts
/// is below a pixel at doc scale and not modeled).
fn layoutAngl(lc: *LayCtx, style: parse.Style, id: Idx) Error!u16 {
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    const size = lc.effSize(style);
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const t: i32 = @max(1, @divTrunc(lc.ruleTh(font, .fraction_bar) * @as(i32, size), 1000));
    const topPad = 4 * t;
    const botPad = @max(@as(i32, 0), scale(lc, 250, style) - bb.db);
    const padL = scale5(lc, 3889, style);
    const padR = scale5(lc, 7778, style);
    const markTop = bb.ha + topPad;
    const markBot = bb.db + botPad;
    const totalW = bb.w + padL + padR;
    const top = try lc.allocBox(.{
        .w = totalW,
        .ha = t,
        .db = 0,
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const right = try lc.allocBox(.{
        .w = t,
        .ha = markTop,
        .db = markBot,
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = b, .dx = padL, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = top, .dx = 0, .dy = markTop - t };
    lc.bkids[s + 2] = .{ .box = right, .dx = totalW - t, .dy = 0 };
    return lc.allocBox(.{
        .w = totalW,
        .ha = markTop,
        .db = markBot,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

fn layoutCancel(lc: *LayCtx, style: parse.Style, id: Idx, down: bool, both: bool) Error!u16 {
    // Corner-to-corner diagonals (issue #107, pinned 0.18.7
    // `stretchyEnclose`): one `Rule.diag` per strike over the padded
    // box, zero metric change (the vlist keeps the inner box; the
    // side pad laps with zero net advance). `down` selects the
    // `\bcancel` diagonal, `both` adds the second for `\xcancel`.
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    const single = isSingleChar(lc.pctx, id);
    const pad = scale(lc, 200, style);
    const vpad = if (single) pad else 0;
    const hpad = if (single) 0 else pad;
    const thick: u32 = @intCast(@max(1, scale(lc, 46, style)));
    const rw = bb.w + 2 * hpad;
    const rha = bb.ha + vpad;
    const rdb = bb.db + vpad;
    const nDiag: usize = if (both) 2 else 1;
    const s = try lc.allocKids(1 + nDiag);
    // The body stays at the advance origin (KaTeX keeps the inner box
    // put); the strike laps `hpad` past it on each side with zero net
    // advance, like `cancel-lap` undoing `cancel-pad`.
    lc.bkids[s] = .{ .box = b, .dx = 0, .dy = 0 };
    // Strike rule, then (for `\xcancel`) its mirror diagonal.
    const first: ir.Diag = if (down) .down else .up;
    lc.bkids[s + 1] = .{
        .box = try lc.allocBox(.{
            .w = rw,
            .ha = rha,
            .db = rdb,
            .kind = .{ .diag = .{ .dir = first, .thick = thick } },
            .invisible = false,
        }),
        .dx = -hpad,
        // The pad lives in the rule box's own ha/db (rha/rdb), so
        // the kid rides at dy=0: top lands vpad above the body top,
        // bottom vpad below the body bottom.
        .dy = 0,
    };
    if (both) {
        const second: ir.Diag = if (down) .up else .down;
        lc.bkids[s + 2] = .{
            .box = try lc.allocBox(.{
                .w = rw,
                .ha = rha,
                .db = rdb,
                .kind = .{ .diag = .{ .dir = second, .thick = thick } },
                .invisible = false,
            }),
            .dx = -hpad,
            .dy = 0,
        };
    }
    return lc.allocBox(.{
        .w = bb.w,
        .ha = bb.ha,
        .db = bb.db,
        .kind = .{ .list = .{ .start = s, .len = @intCast(1 + nDiag) } },
        .invisible = false,
    });
}

/// Phasor angle (`\phase{X}`, issue #51): KaTeX draws a full-height
/// diagonal in SVG with `angleHeight = h+d+lineWeight+clearance`,
/// `paddingLeft = angleHeight/2+lineWeight`, the mark bottom sitting
/// lineWeight+clearance below the content (pinned 0.18.7 enclose).
/// The path also fills the bottom edge, so an 80mu underline bar
/// spans the box with its bottom on the mark bottom.
/// The IR has no diagonal strokes, so the mark is a U+2220 glyph
/// squashed to KaTeX's 2:1 slope (`x_scale` 500) and bottom-anchored
/// on the vertex; all box metrics follow the KaTeX formula exactly.
/// On tiny bodies the pad widens to the mark width (KaTeX's SVG is
/// clipped, never overlapping — the metrics stay overlap-free too).
fn layoutPhase(lc: *LayCtx, style: parse.Style, id: Idx) Error!u16 {
    const size: u16 = style.sizeUnits();
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    // 0.6pt at base sizing (KaTeX `havingBaseSizing`: never scaled
    // by \Huge-style size changes).
    const lw: i32 = 60;
    const clr = @divTrunc(@as(i32, 35) * @divTrunc(x_height_1000 * size, 1000), 100);
    const hgt = bb.ha + bb.db + lw + clr;
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const g = lc.glyphId(font, 0x2220);
    const gw = @divTrunc(lc.advance(font, g) * size, 1000);
    const ge = lc.extents(font, g);
    const gha = @divTrunc(ge[0] * size, 1000);
    const gdb = @divTrunc(ge[1] * size, 1000);
    const mw = @divTrunc(gw + 1, 2);
    var pad = @divTrunc(hgt, 2) + lw;
    if (mw > pad) pad = mw;
    const ndb = bb.db + lw + clr;
    const ab = try lc.allocBox(.{
        .w = mw,
        .ha = gha,
        .db = gdb,
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = g } },
        .invisible = false,
    });
    lc.boxes[ab].x_scale = 500;
    // KaTeX `phasePath` fills the SVG bottom edge across the full
    // span: an 80mu underline bar whose bottom meets the mark bottom.
    const btw: i32 = 80;
    const bar = try lc.allocBox(.{
        .w = pad + bb.w,
        .ha = btw,
        .db = 0,
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const s = try lc.allocKids(3);
    lc.bkids[s] = .{ .box = b, .dx = pad, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = ab, .dx = 0, .dy = gdb - ndb };
    lc.bkids[s + 2] = .{ .box = bar, .dx = 0, .dy = -ndb };
    var ha = bb.ha;
    const mtop = gdb - ndb + gha;
    if (mtop > ha) ha = mtop;
    return lc.allocBox(.{
        .w = pad + bb.w,
        .ha = ha,
        .db = ndb,
        .kind = .{ .list = .{ .start = s, .len = 3 } },
        .invisible = false,
    });
}

/// Negation overlay (`\not X`, issue #36): the U+0338 slash struck
/// over the bound base at the same baseline. The reference slash ink
/// hangs left of its origin (text combining design), so the v4 ink
/// hook centers it on the base; without the hook the advance middle
/// is the fallback (never worse than the old left-edge draw). Clamped
/// at the left edge like brace clamping when the ink is wider.
// Strikeout (issue #51): horizontal rule at half x-height (KaTeX
// enclose sout shifts the line by -0.5*xHeight, with the visible
// .08em CSS border setting the weight). Unlike cancel the rule can
// poke above shallow bodies, so the height grows to cover it
// (canvas sizing reads ha/db).
fn layoutSout(lc: *LayCtx, style: parse.Style, id: Idx) Error!u16 {
    const b = try layoutNode(lc, style, id);
    const bb = lc.boxes[b];
    const size = lc.effSize(style);
    const th = @divTrunc(@as(i32, 80) * size, 1000);
    const strike = @divTrunc(x_height_1000 * size, 2000);
    const rb = try lc.allocBox(.{
        .w = bb.w,
        .ha = @divTrunc(th + 1, 2),
        .db = th - @divTrunc(th + 1, 2),
        .kind = .{ .rule = {} },
        .invisible = false,
    });
    const s = try lc.allocKids(2);
    lc.bkids[s] = .{ .box = b, .dx = 0, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = rb, .dx = 0, .dy = strike };
    const top = strike + @divTrunc(th + 1, 2);
    return lc.allocBox(.{
        .w = bb.w,
        .ha = if (bb.ha > top) bb.ha else top,
        .db = bb.db,
        .kind = .{ .list = .{ .start = s, .len = 2 } },
        .invisible = false,
    });
}

fn layoutNot(lc: *LayCtx, style: parse.Style, n: anytype) Error!u16 {
    const size = lc.effSize(style);
    const font: u16 = @intFromEnum(contract.FontId.rm);
    const base = try layoutNode(lc, style, n.base);
    const bb = lc.boxes[base];
    const sg = lc.glyphId(font, 0x0338);
    const sadv = @divTrunc(lc.advance(font, sg) * size, 1000);
    const se = lc.extents(font, sg);
    const sha = @divTrunc(se[0] * size, 1000);
    const sdb = @divTrunc(se[1] * size, 1000);
    const sb = try lc.allocBox(.{
        .w = sadv,
        .ha = sha,
        .db = sdb,
        .kind = .{ .glyph = .{ .font = font, .size = size, .glyph = sg } },
        .invisible = false,
    });
    var dx = @divTrunc(bb.w - sadv, 2);
    if (lc.ink(font, sg)) |ib| {
        const ix0 = @divTrunc(ib[0] * size, 1000);
        const ix1 = @divTrunc(ib[2] * size, 1000);
        if (ix1 > ix0) dx = @divTrunc(bb.w - (ix1 - ix0), 2) - ix0;
    }
    dx = @max(dx, 0);
    const s = try lc.allocKids(2);
    lc.bkids[s] = .{ .box = base, .dx = 0, .dy = 0 };
    lc.bkids[s + 1] = .{ .box = sb, .dx = dx, .dy = 0 };
    return lc.allocBox(.{
        .w = bb.w,
        .ha = if (bb.ha > sha) bb.ha else sha,
        .db = if (bb.db > sdb) bb.db else sdb,
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
    open_color: ?u32 = null,
    open_scale: u16 = 1000,
    open_shear: i16 = 0,
    open_mirrored: bool = false,
    open_y: i32 = 0,
    /// Expected pen x for run continuation.
    open_x: i32 = 0,
    open_run_x: i32 = 0,
    open_start: usize = 0,
    has_open: bool = false,
    /// Mirror map for emitted x: `x' = x + m_off`, or `x' = m_off - x`
    /// under an odd `\reflectbox` nesting (issue #97). Reflections
    /// compose to x -> +/-x + c, so one flag plus one offset stays
    /// exact for arbitrary nesting (a double flip is a translation).
    m_neg: bool = false,
    m_off: i32 = 0,

    fn closeRun(self: *EmitCtx) void {
        if (!self.has_open) return;
        if (self.ng > self.open_start) {
            self.runs[self.nr] = .{
                .font_id = self.open_font,
                .size_units = self.open_size,
                .x = self.open_run_x,
                .baseline_y = self.open_y,
                .glyphs = self.glyphs[self.open_start..self.ng],
                .color = self.open_color,
                .x_scale = self.open_scale,
                .x_shear = self.open_shear,
                .mirrored = self.open_mirrored,
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
                // The mirror map (issue #97) moves the glyph origin;
                // the backend flips the ink about that origin when
                // the map is negating.
                const ex = if (ec.m_neg) ec.m_off - x else x + ec.m_off;
                // Break runs on position gaps: expected pen must equal x.
                // Color, raster-scale, shear, and mirror boundaries
                // split runs too (issues #35, #31, #77, #97).
                if (ec.has_open and (ec.open_font != g.font or ec.open_size != g.size or ec.open_color != b.color or ec.open_scale != b.x_scale or ec.open_shear != b.x_shear or ec.open_mirrored != ec.m_neg or ec.open_y != base or ec.open_x != ex)) {
                    ec.closeRun();
                }
                if (!ec.has_open) {
                    if (ec.nr >= ec.runs.len) return error.NoSpace;
                    ec.open_font = g.font;
                    ec.open_size = g.size;
                    ec.open_color = b.color;
                    ec.open_scale = b.x_scale;
                    ec.open_shear = b.x_shear;
                    ec.open_mirrored = ec.m_neg;
                    ec.open_y = base;
                    ec.open_start = ec.ng;
                    ec.open_run_x = ex;
                    ec.has_open = true;
                }
                if (ec.ng >= ec.glyphs.len) return error.NoSpace;
                ec.glyphs[ec.ng] = g.glyph;
                ec.ng += 1;
                ec.open_x = ex + b.w;
            }
        },
        .kern, .empty => {},
        .rule => {
            if (!b.invisible) {
                ec.closeRun();
                if (ec.nl >= ec.rules.len) return error.NoSpace;
                const w: u32 = if (b.w < 0) 0 else @intCast(b.w);
                // Mirror the rect about the active axis (issue #97):
                // [x, x+w] maps to [m_off-x-w, m_off-x].
                const ex = if (ec.m_neg) ec.m_off - x - @as(i32, @intCast(w)) else x + ec.m_off;
                ec.rules[ec.nl] = .{
                    .x = ex,
                    .y = base - b.ha,
                    .w = w,
                    .h = if (b.ha + b.db < 0) 0 else @intCast(b.ha + b.db),
                    .color = b.color,
                };
                ec.nl += 1;
            }
        },
        .diag => |d| {
            // Diagonal strike (issue #107): same rect mapping as a
            // plain rule; the mirror map flips the strike (issue #97 —
            // a vertical-axis flip swaps the diagonal).
            if (!b.invisible) {
                ec.closeRun();
                if (ec.nl >= ec.rules.len) return error.NoSpace;
                const w: u32 = if (b.w < 0) 0 else @intCast(b.w);
                const ex = if (ec.m_neg) ec.m_off - x - @as(i32, @intCast(w)) else x + ec.m_off;
                const dir: ir.Diag = if (ec.m_neg)
                    switch (d.dir) {
                        .up => .down,
                        .down => .up,
                        .none => .none,
                    }
                else
                    d.dir;
                ec.rules[ec.nl] = .{
                    .x = ex,
                    .y = base - b.ha,
                    .w = w,
                    .h = if (b.ha + b.db < 0) 0 else @intCast(b.ha + b.db),
                    .color = b.color,
                    .diag = dir,
                    .thick = d.thick,
                };
                ec.nl += 1;
            }
        },
        .list => |r| {
            // A mirror box (issue #97) flips about its own horizontal
            // center in ORIGINAL coordinates, ahead of the accumulated
            // outer map (CSS nests outer-to-inner): with old map
            // s*x+c, the new map is s*(2*axis-x)+c. Saved and
            // restored, so siblings keep the outer map.
            const saved_neg = ec.m_neg;
            const saved_off = ec.m_off;
            if (b.mirror) {
                const axis = x + @divTrunc(b.w, 2);
                ec.m_off += if (ec.m_neg) -2 * axis else 2 * axis;
                ec.m_neg = !ec.m_neg;
            }
            const kids = lc.bkids[r.start .. r.start + r.len];
            for (kids) |k| {
                // Invisibility propagates to children.
                if (b.invisible) {
                    try emitInvisible(lc, ec, k.box, x + k.dx, base - k.dy);
                } else {
                    try emitBox(lc, ec, k.box, x + k.dx, base - k.dy);
                }
            }
            ec.m_neg = saved_neg;
            ec.m_off = saved_off;
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
