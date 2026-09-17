//! ZaTeX front end: lexer, macro expander, parser → AST.
//!
//! Bounded and allocation-free: tokens, nodes, macro bodies, and the
//! expansion pushback all live in fixed pools inside `ParseCtx` (one
//! stack value owned by the layout call). Macro expansion is
//! token-level with a hard `max_expand` budget (KaTeX parity: 1000).
const std = @import("std");
const contract = @import("contract.zig");
const symbols = @import("symbols.zig");

const Error = contract.LayoutError;

/// Read-only AST accessors for the layout core and emitters (the
/// pools live in `ParseCtx`; these keep that ownership explicit).
pub fn nodeAt(ctx: *const ParseCtx, id: Idx) Node {
    return ctx.nodes[id];
}
pub fn kidsOf(ctx: *const ParseCtx, r: Range) []const u16 {
    return ctx.kids[r.start .. r.start + r.len];
}
pub fn rowsOf(ctx: *const ParseCtx, start: u16, len: u16) []const Row {
    return ctx.rows[start .. start + len];
}
pub fn toksOf(ctx: *const ParseCtx, r: Range) []const Tok {
    return ctx.toks[r.start .. r.start + r.len];
}

/// Operator description for limit placement (shared by the layout
/// core and the MathML emitter — one decision, two writers).
pub const OpDesc = struct {
    cp: u21,
    large: bool,
    func: bool,
    limits: LimitsMode,
    lim_def: bool,
    /// Explicit `\limits` on a star-armed `\operatorname` forces
    /// stacking in every style — even text style with both scripts,
    /// where forced symbols stay side-set (KaTeX 0.18.7, issue #98).
    force_stack: bool = false,
};

/// See through transparent wrappers to the operator beneath.
pub fn opBase(ctx: *const ParseCtx, id: Idx) ?OpDesc {
    var cur = id;
    while (true) {
        switch (nodeAt(ctx, cur)) {
            .op => |o| return .{
                .cp = o.cp,
                .large = o.large,
                .func = o.func,
                .limits = o.limits,
                .lim_def = o.lim_def,
            },
            .style => |s| cur = s.body,
            // An Op wrapper is itself the operator (KaTeX \mathop
            // defaults limits:false — only explicit \limits stacks
            // it); other classes are transparent like .font/.color.
            .classwrap => |c| {
                if (c.class == .Op) return .{
                    .cp = 0,
                    .large = false,
                    .func = true,
                    .limits = c.limits,
                    .lim_def = false,
                };
                cur = c.body;
            },
            // A word operator stacks display scripts only for the
            // star form (`\operatorname*`, `\operatornamewithlimits`),
            // and an explicit `\limits` on an armed name forces
            // stacking in every style (KaTeX 0.18.7 placement matrix,
            // issue #98). Explicit `\limits` after a PLAIN name stays
            // inert (side-set in both styles), and armed stacking
            // never leaks to symbols (`\sum\limits`, `\lim\limits`
            // keep both scripts side-set in text style).
            .opname => |o| {
                if (o.forced) return .{
                    .cp = 0,
                    .large = false,
                    .func = true,
                    .limits = .on,
                    .lim_def = true,
                    .force_stack = true,
                };
                return .{
                    .cp = 0,
                    .large = false,
                    .func = true,
                    .limits = .auto,
                    .lim_def = o.limits == .on,
                };
            },
            // Built-limit operators stack like the star form (their
            // KaTeX source is `\operatorname*{...}`).
            .varlim => return .{
                .cp = 0,
                .large = false,
                .func = true,
                .limits = .auto,
                .lim_def = true,
            },
            .font => |f| cur = f.body,
            .color => |c| cur = c.body,
            .size => |s| cur = s.body,
            // A background box body is text tokens, never an operator.
            .colorbox => return null,
            .href => |h| cur = h.body,
            .htmlwrap => |b| cur = b,
            else => return null,
        }
    }
}

/// Limit-vs-side decision (KaTeX parity, pinned 0.18.7 `supsub.ts`):
/// forced `\limits` stacks in every style; default-limit operators
/// (`\sum`, `\lim`) stack only in display style; `\nolimits` and
/// integrals always go to the side.
pub fn useLimits(style: Style, o: OpDesc) bool {
    return switch (o.limits) {
        .on => true,
        .off => false,
        .auto => style.isDisplay() and o.lim_def,
    };
}

/// Canonical TeX glue widths in thousandths of an em (1mu = 1/18em).
/// Single source of truth for `.space`/`.nbsp` payloads (issue 16):
/// the parser produces them, `layout.zig` measures them, `mathml.zig`
/// serializes them. No other file may hard-code these widths.
pub const space_thin: i16 = 167; // 3mu: `\,` (negated for `\!`)
pub const space_med: i16 = 222; // 4mu: `\:`
pub const space_thick: i16 = 278; // 5mu: `\;`
/// Layout width of `.nbsp` (interword `\ `, `~`, text spaces). Never
/// a `.space` payload: computed kern (e.g. `\mskip6mu` = 333) must
/// serialize as measurable glue, not NBSP.
pub const space_interword: i16 = 333;
/// 2mu lead of KaTeX `\colon` (`\mskip2mu`).
pub const space_2mu: i16 = 111;
/// 6mu trail of KaTeX `\colon` (`\mskip6mu`): glue, never `.nbsp`,
/// though it shares `space_interword`'s numeric value.
pub const space_6mu: i16 = 333;

pub const Idx = u16;
pub const NONE: Idx = 0xFFFF;

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

pub const TokKind = enum(u8) {
    char,
    ctrl,
    sup,
    sub,
    lbrace,
    rbrace,
    amp,
    newline,
    param,
    /// Internal sentinel: pushed before re-parsed token ranges (e.g.
    /// `\genfrac` numerator) so the formula parser stops at the range
    /// end instead of continuing into the source.
    marker,
    end,
};

/// One lexical token. `name` borrows the source (or a static string);
/// `pos` is the source byte offset (use-site offset for expanded
/// tokens — KaTeX likewise reports macro-use positions).
pub const Tok = struct {
    kind: TokKind,
    cp: u21 = 0,
    name: []const u8 = "",
    arg: u3 = 0,
    pos: u32 = 0,
    /// True for tokens injected by macro expansion: they borrow the
    /// definition's bytes while `pos` carries the use site, so there
    /// is no source cursor a raw scanner (`\verb`) could trust.
    synth: bool = false,
    /// KaTeX `noexpand` parity (def.ts `letCommand`): an alias bound
    /// while its target has no macro definition surfaces the target
    /// verbatim at use — later definitions must NOT capture it, and
    /// macro expansion must skip it.
    noexpand: bool = false,
};

// ---------------------------------------------------------------------------
// Styles and fonts
// ---------------------------------------------------------------------------

/// TeX styles D T S SS × cramped. The layout core maps these to sizes
/// (1000/1000/700/500) and style-dependent shifts.
pub const Style = enum(u8) {
    D,
    Dc,
    T,
    Tc,
    S,
    Sc,
    SS,
    SSc,

    pub fn cramped(self: Style) Style {
        return switch (self) {
            .D => .Dc,
            .T => .Tc,
            .S => .Sc,
            .SS => .SSc,
            else => self,
        };
    }
    /// Style of superscripts/subscripts (TeX: D/T→S, S/SS→SS).
    pub fn script(self: Style) Style {
        return switch (self) {
            .D, .Dc, .T, .Tc => .S,
            .S, .Sc, .SS, .SSc => .SS,
        };
    }
    /// Numerator style (D→T, T→S, S/SS→SS), never cramped.
    pub fn numerator(self: Style) Style {
        return switch (self) {
            .D, .Dc => .T,
            .T, .Tc => .S,
            .S, .Sc, .SS, .SSc => .SS,
        };
    }
    /// Denominator style (cramped variant of the smaller style).
    pub fn denominator(self: Style) Style {
        return switch (self) {
            .D, .Dc => .Tc,
            .T, .Tc => .Sc,
            .S, .Sc, .SS, .SSc => .SSc,
        };
    }
    pub fn sizeUnits(self: Style) u16 {
        return switch (self) {
            .D, .Dc, .T, .Tc => 1000,
            .S, .Sc => 700,
            .SS, .SSc => 500,
        };
    }
    pub fn isDisplay(self: Style) bool {
        return self == .D or self == .Dc;
    }
};

/// Math font families (see `contract.FontId` for the provider mapping).
pub const FontFam = enum(u8) {
    rm,
    mathit,
    bold,
    sans,
    tt,
    frak,
    script,
    bb,
    cal,
    /// `\bm` (issue #73): KaTeX `mathvariant="bold-italic"`.
    bolditalic,
    /// `\mathsfit` (issue #137): KaTeX `mathvariant="sans-serif-italic"`.
    sansitalic,

    pub fn id(self: FontFam) u16 {
        return @intFromEnum(@as(contract.FontId, switch (self) {
            .rm => .rm,
            .mathit => .math_italic,
            .bold => .bold,
            .sans => .sans,
            .tt => .tt,
            .frak => .frak,
            .script => .script,
            .bb => .bb,
            .cal => .cal,
            .bolditalic => .bold_italic,
            .sansitalic => .sans_italic,
        }));
    }
};

// ---------------------------------------------------------------------------
// AST nodes
// ---------------------------------------------------------------------------

pub const Range = struct {
    start: u16,
    len: u16,
};

pub const Row = struct {
    start: u16,
    len: u16,
    /// `\nonumber`/`\notag` seen in this row: unstarred display
    /// envs drop the row's number columns (KaTeX `\@eqnsw`
    /// parity, issue #88). Defaults off; only `parseEnv` sets it.
    nonumber: bool = false,
    /// `\tag` seen in this row: a row-local tag wins over the row's
    /// own `\nonumber` (KaTeX hoists the tag before `\@eqnsw` drops
    /// the number columns — probed 0.18.7, issue #75). A tag in a
    /// *different* row does not rescue this row. Defaults off; only
    /// `parseEnv` sets it.
    tagged: bool = false,
};

/// Fence pair around a barless stacked fraction (KaTeX parity:
/// `\choose` wraps in parens, `\brace` in braces, `\brack` in
/// brackets — issue #93; the old `parens` bool drew parens for all
/// three). `.none` is a bare stack (`\atop`).
pub const FracFence = enum(u8) { none, parens, braces, brackets };

pub const FracKind = struct {
    bar: bool = true,
    fence: FracFence = .none,
    /// Rule thickness override in font units (0 = font default).
    thick: i32 = 0,
};

pub const LimitsMode = enum(u8) { auto, on, off };

pub const OverKind = enum(u8) {
    overline,
    underline,
    overbrace,
    underbrace,
    overbracket,
    underbracket,
    overleft,
    overright,
    overboth,
    underleft,
    underright,
    underboth,
    overset,
    underset,
    stackrel,
    xleft,
    xright,
    xboth,
    xhookleft,
    xhookright,
    xmapsto,
    xtwoheadleft,
    xtwoheadright,
    overgroup,
    undergroup,
    overlinesegment,
    underlinesegment,
    overleftharpoon,
    overrightharpoon,
    overRightarrow,
    underbar,
    utilde,
    xdoubleleft,
    xdoubleboth,
    xdoubleright,
    xleftharpoondown,
    xleftharpoonup,
    xleftrightharpoons,
    xlongequal,
    xrightharpoondown,
    xrightharpoonup,
    xrightleftharpoons,
    xtofrom,
    angl,
};

pub const EnvKind = enum(u8) {
    matrix,
    pmatrix,
    bmatrix,
    Bmatrix,
    vmatrix,
    Vmatrix,
    smallmatrix,
    array,
    aligned,
    alignedat,
    cases,
    dcases,
    drcases,
    rcases,
    gathered,
    subarray,
    // Display-only top-level environments (KaTeX amsmath parity,
    // issues #83/#85/#86/#87/#90): `align`/`alignat` lay out like
    // `aligned`/`alignedat`, `gather` like `gathered`, `split` like
    // `aligned` (display-gated), `equation` is a single centered
    // column, `cd` is amscd arrow syntax over centered columns.
    // Starred display forms share the kind; the `numbered` flag on
    // the `.env` node records the unstarred (glue-column) shape.
    alignenv,
    alignat,
    equation,
    gather,
    split,
    cd,
};

pub const LapKind = enum(u8) { llap, rlap, clap };

pub const Node = union(enum) {
    atom: struct {
        class: symbols.AtomClass,
        font: FontFam,
        cp: u21,
        /// KaTeX textord (issue #109): math-mode symbols from the
        /// text table (`\%`, Greek capitals, ...) plus every
        /// `\char` result. MathML renders these `mi` with an
        /// explicit variant (KaTeX symbolsOrd); layout spacing
        /// keeps `class` untouched.
        textord: bool = false,
    },
    /// Upright or symbolic operator; `text` holds word operators
    /// (`sin`, user `\operatorname`); empty for single-glyph ops.
    op: struct {
        cp: u21,
        large: bool,
        func: bool,
        limits: LimitsMode,
        /// Default limit placement for `auto` (KaTeX: sums/lim yes,
        /// integrals/sin no).
        lim_def: bool,
        text: []const u8,
    },
    group: Range,
    frac: struct {
        num: Idx,
        den: Idx,
        kind: FracKind,
    },
    sqrt: struct {
        radicand: Idx,
        index: Idx,
    },
    supsub: struct {
        base: Idx,
        sup: Idx,
        sub: Idx,
        /// True when the sup came only from primes (`x''^2` may still
        /// take `^`; KaTeX parity).
        prime_sup: bool,
    },
    delim: struct {
        left: u21,
        right: u21,
        body: Idx,
        /// Rule 15e fixed sizing (issue #112): `\genfrac` delimiters
        /// target delim1/delim2, never grown to content. `\left` and
        /// friends keep grown (`false`).
        fixed: bool = false,
    },
    middle: struct {
        cp: u21,
    },
    big: struct {
        cp: u21,
        level: u2,
        class: symbols.AtomClass,
    },
    accent: struct {
        cp: u21,
        wide: bool,
        nucleus: Idx,
    },
    over: struct {
        kind: OverKind,
        nucleus: Idx,
        extra: Idx,
        under: Idx,
    },
    style: struct {
        style: Style,
        body: Idx,
    },
    /// Font-size declaration (`\tiny`…`\Huge`, issue #73): `mult`
    /// is per-mille (500…2488, KaTeX `sizeMultipliers`). Absolute
    /// like KaTeX (nested sizes reset, not compound); layout scales
    /// via `LayCtx.cur_mult`, MathML emits `mstyle mathsize`.
    size: struct {
        mult: u16,
        body: Idx,
    },
    /// Atom-class wrapper (`\mathinner`/`\mathop`/`\mathrel`/
    /// `\mathpunct`, issue #51): transparent geometry, forced outer
    /// spacing class; an Op
    /// wrapper additionally takes explicit limits via `opBase`
    /// (KaTeX `\mathop` defaults limits:false — only `\limits`
    /// stacks it).
    classwrap: struct {
        class: symbols.AtomClass,
        body: Idx,
        limits: LimitsMode,
    },
    font: struct {
        fam: FontFam,
        body: Idx,
    },
    /// Poor-man's bold: KaTeX keeps the same glyphs and bolds via a
    /// text-shadow style (never a font switch).
    pmb: struct {
        body: Idx,
    },
    /// Circled math (`\textcircled` in math mode, issue #51): a
    /// circle overlay over the body (KaTeX `mover` with U+25EF).
    circled: struct {
        body: Idx,
    },
    /// Vertically centered box: the body is shifted so the math axis
    /// halves its height plus depth (KaTeX `mpadded`).
    vcenter: struct {
        body: Idx,
    },
    /// Horizontally mirrored content (`\reflectbox` over an hbox,
    /// `\mathreflectbox` over math, issue #97, pinned 0.18.7):
    /// geometry-transparent like `.pmb` — layout mirrors the ink
    /// about the box center (KaTeX's CSS flip), while MathML stays
    /// the plain body (KaTeX's MathML carries no flip marker either).
    reflect: struct {
        /// True for `\mathreflectbox` (math body), false for
        /// `\reflectbox` (hbox body): the serializer round-trips
        /// the source command from this.
        math: bool,
        body: Idx,
    },
    /// Token range (into the token arena) for `\text` bodies.
    text: struct {
        toks: Range,
        fam: FontFam,
    },
    env: struct {
        kind: EnvKind,
        rows_start: u16,
        rows_len: u16,
        spec_start: u16,
        spec_len: u16,
        /// Unstarred top-level display env (`align`, `alignat`,
        /// `equation`, `gather`): KaTeX keeps a leading number/glue
        /// column (`mtr-glue`), which the MathML emitter reproduces.
        /// Layout treats it as zero-width (no numbering engine).
        numbered: bool,
    },
    substack: Range,
    mathchoice: [4]Idx,
    opname: struct {
        toks: Range,
        limits: LimitsMode,
        /// Explicit `\limits` after a star-armed name (`*`,
        /// `withlimits`): stacking in every style (issue #98).
        forced: bool = false,
    },
    /// Limit operator with a built body (`\varinjlim` and family,
    /// KaTeX `macros.js`: `\operatorname*` over an under/over
    /// arrow or bar around upright "lim"). The body is always an
    /// `.over` node built here in parse; walkers render it like
    /// KaTeX's operatorname (`<mi>` wrap + apply-function marker)
    /// and lay it out like the inner over with Op spacing.
    varlim: struct {
        body: Idx,
    },
    /// Explicit glue in thousandths of an em (may be negative).
    /// Never interword space: `spacing`-origin NBSP is `.nbsp`
    /// (KaTeX `spacing` vs `kern` nodes — the MathML merger treats
    /// them differently, and computed glue such as `\mskip6mu`
    /// collides with `space_interword` by value).
    space: i16,
    /// Interword space (`\ `, `~`, `\space`, `\nobreakspace`):
    /// KaTeX `spacing`-origin `<mtext>&nbsp;</mtext>`, which merges
    /// with neighboring `mtext` runs. Measures like `space_interword`
    /// glue in layout; kept distinct so computed kern never aliases it.
    nbsp: void,
    vspace: i16,
    newline: void,
    /// Row rule (`\hline` solid, `\hdashline` dashed). Rules live in
    /// their own rows (KaTeX `getHLines` parity, issue #33).
    hline: struct {
        dashed: bool,
    },
    /// Foreground color: `spec` is the literal color-spec token
    /// range (`red`, `#f00`, `rgb(...)`). Layout renders `body`;
    /// the MathML emitter wraps it in `mstyle`.
    color: struct {
        body: Idx,
        spec: Range,
    },
    /// Background box (`\colorbox`, `\fcolorbox`): `body` is text
    /// tokens (KaTeX parses the body in text mode), `frame` is empty
    /// for `\colorbox`. Layout renders the body text.
    colorbox: struct {
        body: Range,
        bg: Range,
        frame: Range,
    },
    href: struct {
        body: Idx,
        target: Range,
    },
    htmlwrap: Idx,
    phantom: struct {
        body: Idx,
        keep_h: bool,
        keep_v: bool,
    },
    boxed: Idx,
    /// Framed text (`\fbox`): the body is always the `.text` node the
    /// handler builds from the hbox argument (KaTeX `enclose`
    /// `argTypes: ["hbox"]`), rendered under a single text-style
    /// `mstyle` — unlike `\boxed`, whose body is math.
    fbox: Idx,
    /// Dual-branch node (KaTeX `\html@mathml{h}{m}`): layout renders
    /// the `html` branch (the visual composition), the MathML
    /// emitter renders the `math` branch (the semantic text). The
    /// logo macros (`\TeX`, `\LaTeX`, `\KaTeX`) are `\textrm` +
    /// `\html@mathml` in KaTeX, so the math branch is a `.text` node
    /// over the plain name — observably `<mtext>KaTeX</mtext>`.
    htmlmathml: struct {
        html: Idx,
        math: Idx,
    },
    /// Single-diagonal strike: `down` is false for `\cancel`
    /// (bottom-left to top-right) and true for `\bcancel`
    /// (top-left to bottom-right, issue #107).
    cancel: struct {
        body: Idx,
        down: bool = false,
    },
    /// Both-diagonal strike (`\xcancel`), unlike `.cancel`.
    xcancel: Idx,
    sout: Idx,
    phase: Idx,
    lap: struct {
        body: Idx,
        kind: LapKind,
    },
    /// amscd vertical-arrow side label (`\cdleft`/`\cdright`,
    /// KaTeX `cdlabel`, pinned 0.18.7): `left` selects the
    /// left-side (overlapping) variant. Layout typesets the body
    /// inline at script size (the bundle's zero-width overlap is a
    /// geometry follow-up); MathML mirrors the bundle's
    /// `mstyle`/`mpadded`/`mrow` shape exactly.
    cdlabel: struct {
        body: Idx,
        left: bool,
    },
    /// Negation overlay (`\\not X`): the U+0338 slash struck over
    /// `base` (KaTeX `\\mathrel{\\mathrlap\\@not}`). Unlike `.lap`,
    /// the operand is bound so layout can center the slash on it.
    not: struct {
        base: Idx,
    },
    smash: struct {
        body: Idx,
        keep_t: bool,
        keep_b: bool,
    },
    raisebox: struct {
        body: Idx,
        dh: i16,
    },
    rule: struct {
        w: i16,
        h: i16,
        /// Vertical raise in thousandths of an em (KaTeX `\rule`
        /// bracket; may be negative). Not depth (issue #37).
        raise: i16,
    },
    /// Included graphic (`\includegraphics`, issue #73 owner #7):
    /// `src`/`alt` are raw token ranges (the `{url}` argument and
    /// the `alt` option value — backslash escapes resolve at emit
    /// time, KaTeX `parseUrlGroup`/`raw` parity). `w`/`h`/`th` are
    /// the `width`/`height`/`totalheight` options in
    /// hundred-thousandths of an em (1e-5; KaTeX `makeEm` prints
    /// four decimals, so the `.rule` thousandths currency cannot
    /// reproduce e.g. `width=1mu` = `0.0556em`). Defaults are
    /// `w = 0` (no `width` attribute), `h = 90000` (0.9em), `th = 0`
    /// (no `valign` attribute); like KaTeX, `width`/`totalheight`
    /// apply only when positive.
    graphics: struct {
        src: Range,
        alt: Range,
        w: i32,
        h: i32,
        th: i32,
    },
    /// Display equation tag (`\tag`, issue #73): hoisted to the whole
    /// equation from any position (pinned 0.18.7 — even `\frac`
    /// numerators). `body` is a `.text` node; `starred` drops the
    /// auto parentheses. Only ever wraps the parse root.
    tag: struct {
        formula: Idx,
        body: Idx,
        starred: bool,
    },
};

/// User macro definition: token-range body with `#1..#9` params, or a
/// `\let` alias for a single token.
const Def = struct {
    name: []const u8,
    nargs: u3,
    body: Range,
    is_alias: bool = false,
    alias_tok: Tok = .{ .kind = .end },
};

/// Fixed pool sizes. Large enough for real formulas, small enough for
/// a bounded stack frame (~100 KB total).
pub const max_nodes: usize = 768;
pub const max_kids: usize = 2048;
pub const max_toks: usize = 1536;
pub const max_pushback: usize = 384;
pub const max_defs: usize = 48;
pub const max_rows: usize = 192;

pub const ParseCtx = struct {
    src: []const u8,
    spos: u32,
    nodes: [max_nodes]Node = undefined,
    nnodes: u16 = 0,
    kids: [max_kids]u16 = undefined,
    nkids: u16 = 0,
    rows: [max_rows]Row = undefined,
    nrows: u16 = 0,
    toks: [max_toks]Tok = undefined,
    ntoks: u16 = 0,
    pb: [max_pushback]Tok = undefined,
    npb: u16 = 0,
    defs: [max_defs]Def = undefined,
    ndefs: u8 = 0,
    /// When true, whitespace lexes as `char(' ')` instead of being
    /// skipped (text-mode captures). Math captures leave it false.
    keep_spaces: bool = false,
    in_env: u8 = 0,
    /// `\nonumber`/`\notag` seen since the current row started
    /// (row-scoped like KaTeX's per-row `\@eqnsw` reset).
    row_nonumber: bool = false,
    /// `\tag` seen since the current row started (row-scoped like
    /// `row_nonumber`; a row-local tag keeps the row's number
    /// columns despite `\nonumber`, issue #75).
    row_tagged: bool = false,
    /// A numbering env adopted the hoisted tag into one of its rows
    /// (row-local tag, or a leading outside-tag defaulted to row 0).
    /// Only then does the MathML emitter drop the tag text and keep
    /// the env's own table; a tag that stayed pending (trailing the
    /// env, or adopted by no numbering row) renders under the
    /// full-width tag table instead (pinned 0.18.7, issue #75).
    tag_adopted: bool = false,
    in_fence: u8 = 0,
    expansions: u32 = 0,
    err_pos: u32 = 0,
    err_msg: []const u8 = "",
    /// Display mode of this parse (set by `parse()`; `\tag` reads it).
    display: bool = false,
    /// Hoisted equation tag (`\tag`, display only): body is a `.text`
    /// node, `NONE` when absent (a second `\tag` fails "Multiple \tag").
    tag_body: Idx = NONE,
    tag_starred: bool = false,

    pub fn init(src: []const u8) ParseCtx {
        return .{ .src = src, .spos = 0 };
    }

    pub fn fail(self: *ParseCtx, pos: u32, comptime msg: []const u8) Error {
        self.err_pos = pos;
        self.err_msg = msg;
        return error.Invalid;
    }

    fn allocNode(self: *ParseCtx, n: Node) Error!Idx {
        if (self.nnodes >= max_nodes) return error.NoSpace; // pool, not depth
        const id = self.nnodes;
        self.nodes[id] = n;
        self.nnodes += 1;
        return id;
    }

    fn allocKids(self: *ParseCtx, n: usize) Error!u16 {
        if (n > max_kids - self.nkids) return error.NoSpace; // pool, not depth
        const s = self.nkids;
        self.nkids += @intCast(n);
        return s;
    }

    fn allocToks(self: *ParseCtx, n: usize) Error!u16 {
        if (n > max_toks - self.ntoks) return error.ExpansionLimit;
        const s = self.ntoks;
        self.ntoks += @intCast(n);
        return s;
    }

    fn allocRow(self: *ParseCtx, r: Row) Error!u16 {
        if (self.nrows >= max_rows) return error.NoSpace; // pool, not depth
        const id = self.nrows;
        self.rows[id] = r;
        self.nrows += 1;
        return id;
    }

    fn push(self: *ParseCtx, t: Tok) Error!void {
        if (self.npb >= max_pushback) {
            self.err_pos = t.pos;
            self.err_msg = "macro expansion too large"; // pool exhaustion surfaces as NoSpace
            return error.NoSpace;
        }
        self.pb[self.npb] = t;
        self.npb += 1;
    }

    // -- byte lexer ----------------------------------------------------

    fn skipGap(self: *ParseCtx) void {
        while (self.spos < self.src.len) {
            const c = self.src[self.spos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.spos += 1;
            } else if (c == '%') {
                while (self.spos < self.src.len and self.src[self.spos] != '\n') self.spos += 1;
            } else break;
        }
    }

    fn lexRaw(self: *ParseCtx) Error!Tok {
        if (self.keep_spaces) {
            // Skip comments only; collapse whitespace runs to one space.
            while (self.spos < self.src.len and self.src[self.spos] == '%') {
                while (self.spos < self.src.len and self.src[self.spos] != '\n') self.spos += 1;
            }
            if (self.spos < self.src.len) {
                const c = self.src[self.spos];
                if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                    const start: u32 = self.spos;
                    while (self.spos < self.src.len) {
                        const d = self.src[self.spos];
                        if (d != ' ' and d != '\t' and d != '\r' and d != '\n') break;
                        self.spos += 1;
                    }
                    return .{ .kind = .char, .cp = ' ', .pos = start };
                }
            }
            if (self.spos >= self.src.len) return .{ .kind = .end, .pos = @intCast(self.src.len) };
        } else {
            self.skipGap();
        }
        if (self.spos >= self.src.len) return .{ .kind = .end, .pos = @intCast(self.src.len) };
        const start: u32 = self.spos;
        const c = self.src[self.spos];
        if (c == '\\') {
            self.spos += 1;
            if (self.spos < self.src.len and isLetter(self.src[self.spos])) {
                const ns = self.spos;
                while (self.spos < self.src.len and isLetter(self.src[self.spos])) self.spos += 1;
                return .{ .kind = .ctrl, .name = self.src[ns..self.spos], .pos = start };
            }
            if (self.spos >= self.src.len) {
                self.err_pos = start;
                self.err_msg = "trailing backslash";
                return error.Invalid;
            }
            const d = self.src[self.spos];
            self.spos += 1;
            if (d == '\n') return .{ .kind = .newline, .pos = start };
            if (d == '\r') {
                if (self.spos < self.src.len and self.src[self.spos] == '\n') self.spos += 1;
                return .{ .kind = .newline, .pos = start };
            }
            if (d == ' ' or d == '\t') return .{ .kind = .ctrl, .name = " ", .cp = ' ', .pos = start };
            // Single-character control sequence (`\%`, `\{`, ...).
            var buf: [4]u8 = undefined;
            buf[0] = d;
            _ = &buf;
            return .{ .kind = .ctrl, .cp = d, .name = self.src[self.spos - 1 .. self.spos], .pos = start };
        }
        if (c == '{') {
            self.spos += 1;
            return .{ .kind = .lbrace, .pos = start };
        }
        if (c == '}') {
            self.spos += 1;
            return .{ .kind = .rbrace, .pos = start };
        }
        if (c == '^') {
            self.spos += 1;
            return .{ .kind = .sup, .pos = start };
        }
        if (c == '_') {
            self.spos += 1;
            return .{ .kind = .sub, .pos = start };
        }
        if (c == '&') {
            self.spos += 1;
            return .{ .kind = .amp, .pos = start };
        }
        const len = utf8Len(c);
        if (len == 0 or self.spos + len > self.src.len) {
            self.err_pos = start;
            self.err_msg = "invalid utf-8";
            return error.Invalid;
        }
        const cp = decode(self.src[self.spos .. self.spos + len]);
        self.spos += @intCast(len);
        return .{ .kind = .char, .cp = cp, .pos = start };
    }

    // -- token stream with macro expansion ------------------------------

    pub fn next(self: *ParseCtx) Error!Tok {
        if (self.npb > 0) {
            self.npb -= 1;
            return self.pb[self.npb];
        }
        return self.lexRaw();
    }

    pub fn peek(self: *ParseCtx) Error!Tok {
        const t = try self.next();
        try self.push(t);
        return t;
    }

    fn findDef(self: *ParseCtx, name: []const u8) ?*Def {
        var i: u8 = 0;
        while (i < self.ndefs) : (i += 1) {
            if (tokNameEq(self.defs[i].name, name)) return &self.defs[i];
        }
        return null;
    }

    /// Capture tokens through the matching close brace. The opening
    /// `{` must already be consumed. `#1..#9` become params (`##`
    /// stays literal) — the same capture backs macro bodies, `\text`,
    /// and token-level macro arguments.
    fn captureToBrace(self: *ParseCtx, open_pos: u32) Error!Range {
        const start = try self.allocToks(0);
        var depth: u16 = 0;
        var count: u16 = 0;
        while (true) {
            const t = try self.next();
            switch (t.kind) {
                .end => return self.fail(open_pos, "expected '}' before end of input"),
                .lbrace => {
                    depth += 1;
                    _ = try self.allocToks(1);
                    self.toks[start + count] = t;
                    count += 1;
                },
                .rbrace => {
                    if (depth == 0) return .{ .start = start, .len = count };
                    depth -= 1;
                    _ = try self.allocToks(1);
                    self.toks[start + count] = t;
                    count += 1;
                },
                .char => {
                    if (t.cp == '#') {
                        const u = try self.next();
                        if (u.kind == .char and u.cp >= '1' and u.cp <= '9') {
                            _ = try self.allocToks(1);
                            self.toks[start + count] = .{
                                .kind = .param,
                                .arg = @intCast(u.cp - '1'),
                                .pos = t.pos,
                            };
                            count += 1;
                        } else if (u.kind == .char and u.cp == '#') {
                            _ = try self.allocToks(1);
                            self.toks[start + count] = t;
                            count += 1;
                        } else {
                            return self.fail(t.pos, "unexpected '#'");
                        }
                    } else {
                        _ = try self.allocToks(1);
                        self.toks[start + count] = t;
                        count += 1;
                    }
                },
                else => {
                    _ = try self.allocToks(1);
                    self.toks[start + count] = t;
                    count += 1;
                },
            }
        }
    }

    /// Capture one token-level macro argument: a braced group (as
    /// tokens) or a single token.
    fn captureArg(self: *ParseCtx) Error!Range {
        const t = try self.peek();
        if (t.kind == .lbrace) {
            _ = try self.next();
            return self.captureToBrace(t.pos);
        }
        _ = try self.next();
        if (t.kind == .end) return self.fail(t.pos, "expected argument");
        const start = try self.allocToks(1);
        self.toks[start] = t;
        return .{ .start = start, .len = 1 };
    }

    /// Expand a user-macro use. The control token was already consumed.
    fn expandUse(self: *ParseCtx, def: *Def, use_pos: u32) Error!void {
        if (def.is_alias) {
            self.expansions += 1;
            if (self.expansions > contract.max_expand) {
                self.err_pos = use_pos;
                self.err_msg = "macro expansion limit exceeded";
                return error.ExpansionLimit;
            }
            // KaTeX parity: an alias surfaces the bound token VERBATIM
            // (def.ts `letCommand` stores the original token object), so
            // a use of an alias to an undefined name fails at the
            // definition-site position, not the use site.
            var t = def.alias_tok;
            t.synth = true;
            return self.push(t);
        }
        var args: [9]Range = undefined;
        var i: u3 = 0;
        while (i < def.nargs) : (i += 1) args[i] = try self.captureArg();
        self.expansions += 1;
        if (self.expansions > contract.max_expand) {
            self.err_pos = use_pos;
            self.err_msg = "macro expansion limit exceeded";
            return error.ExpansionLimit;
        }
        // Push body reversed so stream order is preserved; params
        // splice their argument token ranges in order.
        var k = def.body.len;
        while (k > 0) {
            k -= 1;
            const bt = self.toks[def.body.start + k];
            if (bt.kind == .param) {
                if (bt.arg >= def.nargs) {
                    self.err_pos = use_pos;
                    self.err_msg = "macro parameter out of range";
                    return error.Invalid;
                }
                const ar = args[bt.arg];
                var j = ar.len;
                while (j > 0) {
                    j -= 1;
                    var at = self.toks[ar.start + j];
                    at.pos = use_pos;
                    at.synth = true;
                    try self.push(at);
                }
            } else {
                var nt = bt;
                nt.pos = use_pos;
                nt.synth = true;
                try self.push(nt);
            }
        }
    }

    /// Eagerly expand a token range (for `\\edef`/`\\xdef` bodies).
    /// Macro uses resolve now against current definitions; `.param`
    /// tokens pass through (they bind at use time); builtins copy
    /// verbatim; anything else is an undefined control sequence
    /// (KaTeX parity: eager expansion walks `\\def` names too, so a
    /// nested definition fails on its own name at define time).
    /// Budgets mirror lazy expansion (`expansions`, the token pool).
    fn eagerExpand(self: *ParseCtx, body: Range) Error!Range {
        const ExpFrame = struct { start: u16, len: u16, at: u16, args: [9]Range, nargs: u3, has_args: bool };
        var stack: [65]ExpFrame = undefined;
        stack[0] = .{ .start = body.start, .len = body.len, .at = 0, .args = undefined, .nargs = 0, .has_args = false };
        var nstack: u8 = 1;
        const out_start = try self.allocToks(0);
        var out_len: u16 = 0;
        while (nstack > 0) {
            const f = &stack[nstack - 1];
            if (f.at >= f.len) {
                nstack -= 1;
                continue;
            }
            const t = self.toks[f.start + f.at];
            f.at += 1;
            if (t.kind == .param and f.has_args) {
                // Splice the captured argument: any `.param` inside
                // belongs to an outer definition and passes through
                // when its own frame emits it.
                if (t.arg >= f.nargs) {
                    self.err_pos = t.pos;
                    self.err_msg = "macro parameter out of range";
                    return error.Invalid;
                }
                if (nstack >= stack.len) {
                    self.err_pos = t.pos;
                    self.err_msg = "macro expansion limit exceeded";
                    return error.ExpansionLimit;
                }
                const ar = f.args[t.arg];
                stack[nstack] = .{ .start = ar.start, .len = ar.len, .at = 0, .args = undefined, .nargs = 0, .has_args = false };
                nstack += 1;
                continue;
            }
            if (t.kind == .ctrl) {
                var cur_tok = t;
                var cur_name = t.name;
                var guard: u8 = 0;
                while (self.findDef(cur_name)) |d| {
                    if (!d.is_alias) break;
                    self.expansions += 1;
                    if (self.expansions > contract.max_expand or guard >= max_defs) {
                        self.err_pos = t.pos;
                        self.err_msg = "macro expansion limit exceeded";
                        return error.ExpansionLimit;
                    }
                    guard += 1;
                    cur_tok = d.alias_tok;
                    if (cur_tok.kind != .ctrl) break;
                    cur_name = cur_tok.name;
                }
                const rd = if (cur_tok.kind == .ctrl) self.findDef(cur_name) else null;
                if (rd) |def| {
                    self.expansions += 1;
                    if (self.expansions > contract.max_expand) {
                        self.err_pos = t.pos;
                        self.err_msg = "macro expansion limit exceeded";
                        return error.ExpansionLimit;
                    }
                    if (nstack >= stack.len) {
                        self.err_pos = t.pos;
                        self.err_msg = "macro expansion limit exceeded";
                        return error.ExpansionLimit;
                    }
                    var args: [9]Range = undefined;
                    var ai: u3 = 0;
                    while (ai < def.nargs) : (ai += 1) {
                        if (f.at >= f.len) return self.fail(t.pos, "expected argument");
                        const a0 = f.start + f.at;
                        if (self.toks[a0].kind == .lbrace) {
                            var depth: u16 = 1;
                            var j: u16 = 1;
                            while (true) {
                                if (f.at + j >= f.len) return self.fail(t.pos, "expected '}' before end of input");
                                const q = self.toks[f.start + f.at + j];
                                if (q.kind == .lbrace) depth += 1;
                                if (q.kind == .rbrace) {
                                    depth -= 1;
                                    if (depth == 0) break;
                                }
                                j += 1;
                            }
                            args[ai] = .{ .start = a0 + 1, .len = j - 1 };
                            f.at += j + 1;
                        } else {
                            args[ai] = .{ .start = a0, .len = 1 };
                            f.at += 1;
                        }
                    }
                    stack[nstack] = .{ .start = def.body.start, .len = def.body.len, .at = 0, .args = args, .nargs = def.nargs, .has_args = true };
                    nstack += 1;
                    continue;
                }
                if (!isBuiltin(cur_name)) return self.fail(cur_tok.pos, "undefined control sequence");
                _ = try self.allocToks(1);
                self.toks[out_start + out_len] = cur_tok;
                out_len += 1;
                continue;
            }
            _ = try self.allocToks(1);
            self.toks[out_start + out_len] = t;
            out_len += 1;
        }
        return .{ .start = out_start, .len = out_len };
    }
};

fn isLetter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '@';
}

pub fn tokNameEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

fn utf8Len(c: u8) u3 {
    if (c < 0x80) return 1;
    if (c & 0xE0 == 0xC0) return 2;
    if (c & 0xF0 == 0xE0) return 3;
    if (c & 0xF8 == 0xF0) return 4;
    return 0;
}

fn decode(b: []const u8) u21 {
    if (b.len == 1) return b[0];
    if (b.len == 2) return (@as(u21, b[0] & 0x1F) << 6) | (b[1] & 0x3F);
    if (b.len == 3) return (@as(u21, b[0] & 0x0F) << 12) | (@as(u21, b[1] & 0x3F) << 6) | (b[2] & 0x3F);
    return (@as(u21, b[0] & 0x07) << 18) | (@as(u21, b[1] & 0x3F) << 12) | (@as(u21, b[2] & 0x3F) << 6) | (b[3] & 0x3F);
}

test "lexer splits control sequences and symbols" {
    var ctx = ParseCtx.init("x\\alpha^2");
    const t0 = try ctx.next();
    try std.testing.expect(t0.kind == .char and t0.cp == 'x');
    const t1 = try ctx.next();
    try std.testing.expect(t1.kind == .ctrl and tokNameEq(t1.name, "alpha"));
    try std.testing.expectEqual(@as(u32, 1), t1.pos);
    const t2 = try ctx.next();
    try std.testing.expect(t2.kind == .sup);
    const t3 = try ctx.next();
    try std.testing.expect(t3.kind == .char and t3.cp == '2');
}

test "% starts a comment to end of line" {
    var ctx = ParseCtx.init("a% junk\nb");
    _ = try ctx.next();
    const t = try ctx.next();
    try std.testing.expect(t.kind == .char and t.cp == 'b');
}

test "utf-8 decodes to codepoints" {
    var ctx = ParseCtx.init("\u{03B1}");
    const t = try ctx.next();
    try std.testing.expect(t.kind == .char and t.cp == 0x03B1);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const build_options = @import("build_options");
const active_profile: contract.Profile =
    std.meta.stringToEnum(contract.Profile, build_options.profile) orelse .full;

/// Gate non-subset primitives: in the `subset` profile they vanish
/// (error.Unsupported so hosts fall back); in `full` this is a
/// comptime no-op eliminated with the branch.
fn subsetGate(comptime ok_in_subset: bool) Error!void {
    if (comptime active_profile == .subset) {
        if (!ok_in_subset) return error.Unsupported;
    }
}

/// Comptime-known profile flag: `if (full_only and ...)` prunes the
/// full-only dispatch branch (and every helper it alone reaches) out
/// of subset binaries at compile time (size ratchet). The subset-side
/// `isFullOnly*Name` tables below preserve the `Unsupported` contract
/// for exactly those names, so observable behavior never changes.
const full_only: bool = active_profile == .full;

/// Definition primitives, stripped from subset dispatch (see
/// `full_only`): user macros cannot shadow these (the definition
/// chain precedes expansion), so the subset check sits first. Public
/// so the subset contract test pins every name.
pub const full_only_def_names: []const []const u8 = &.{
    "newcommand", "renewcommand", "providecommand", "def", "gdef",
    "edef", "xdef", "global", "long", "noexpand", "expandafter",
    "futurelet", "let",
};

fn isFullOnlyDefName(name: []const u8) bool {
    for (full_only_def_names) |d| if (tokNameEq(name, d)) return true;
    return false;
}

/// `parseCtrl`-chain commands, stripped from subset dispatch (see
/// `full_only`). Predicate families reuse the dispatch predicates, so
/// they cannot drift; user macros still shadow these (the subset
/// check sits after macro expansion). Public so the subset contract
/// test pins every name.
pub const full_only_ctrl_names: []const []const u8 = &.{
    "genfrac", "left", "middle", "mathinner", "mathop", "mathrel",
    "mathpunct", "mathbin", "mathclose", "mathopen", "mathord",
    "colon", "ordinarycolon", "vcentcolon", "dblcolon", "coloneqq",
    "Coloneqq", "coloneq", "Coloneq", "eqqcolon", "Eqqcolon", "eqcolon",
    "Eqcolon", "colonapprox", "Colonapprox", "colonsim", "Colonsim",
    "simcolon", "simcoloncolon", "approxcolon", "approxcoloncolon",
    "coloncolon", "colonequals", "coloncolonequals", "equalscolon",
    "equalscoloncolon", "colonminus", "coloncolonminus", "minuscolon",
    "minuscoloncolon", "coloncolonapprox", "coloncolonsim", "ratio",
    "char", "@char", "@firstoftwo", "@secondoftwo", "@ifnextchar", "@ifstar", "TextOrMath", "html@mathml", "rq", "lBrace", "rBrace", "minuso", "angl", "angln",
    "xcancel", "bmod", "pod", "pmod", "copyright", "textcopyright", "verb", "color", "textcolor",
    "colorbox", "fcolorbox", "href", "url", "includegraphics", "stackrel",
    "htmlClass", "htmlId",
    "htmlStyle", "htmlData", "operatorname", "operatornamewithlimits",
    "dotsi", "mod", "KaTeX", "LaTeX", "TeX", "substack",
    "mathchoice", "smash", "raisebox", "rule", "boxed", "fbox",
    "phantom", "hphantom", "vphantom", "bra", "ket", "Bra", "Ket",
    "braket", "Braket", "Set",
    "mathstrut", "llap", "rlap", "clap", "mathllap", "mathrlap",
    "mathclap", "cancel", "bcancel", "sout", "phase", "textcircled",
    "nobreakspace", "space", "vspace", "overset", "underset", "stackrel", "not",
    "begin", "vcenter", "displaystyle", "textstyle", "scriptstyle",
    "scriptscriptstyle", "tiny", "sixptsize", "scriptsize",
    "footnotesize", "small", "normalsize", "large", "Large", "LARGE",
    "huge", "Huge",
    "begingroup", "endgroup", "hbox", "mathreflectbox", "reflectbox",
    "set", "varinjlim", "varliminf", "varlimsup", "varprojlim",
    "tag",
};

fn isFullOnlyCtrlName(name: []const u8) bool {
    if (symbols.lookupAccent(name) != null) return true;
    if (parseOverName(name) != null) return true;
    if (isBigName(name)) return true;
    for (full_only_ctrl_names) |c| if (tokNameEq(name, c)) return true;
    return false;
}

/// `begingroup` opens a scope like `{` but closable only by
/// `\endgroup` (KaTeX parity: `}` inside one is an error and vice
/// versa — strict pairing, pinned 0.18.7).
const Frame = enum { top, group, begingroup, leftright, envcell, bracket };

const CellTerm = enum { amp, newline, end, right };

/// Parse entry: one formula → root group node (wrapped in `.tag`
/// when `\tag` hoisted one).
pub fn parse(ctx: *ParseCtx, display: bool) Error!Idx {
    ctx.display = display;
    const root = try parseFormula(ctx, 0, .top, null);
    const t = try ctx.next();
    if (t.kind != .end) return ctx.fail(t.pos, "unexpected input");
    if (ctx.tag_body == NONE) return root;
    return ctx.allocNode(.{ .tag = .{
        .formula = root,
        .body = ctx.tag_body,
        .starred = ctx.tag_starred,
    } });
}

/// Equation tag (`\tag`, `\tag*`, issue #73): display-mode only,
/// hoisted to the whole equation from any position (pinned 0.18.7 —
/// even `\frac` numerators). Records into the context and emits no
/// node (a second `\tag` fails "Multiple \tag"); `parse()` wraps
/// the root. The body parses like `\hbox` (bare atoms accepted;
/// KaTeX rejects `^` there, and `\tag 1x` is legal).
fn parseTag(ctx: *ParseCtx, t: Tok) Error!?Idx {
    const pk = try ctx.peek();
    const starred = pk.kind == .char and pk.cp == '*';
    if (starred) _ = try ctx.next();
    if (!ctx.display) return ctx.fail(t.pos, "\\tag works only in display equations");
    if (ctx.tag_body != NONE) return ctx.fail(t.pos, "Multiple \\tag");
    const toks = try parseBracedToks(ctx, t, false);
    // A nested `\tag` is still "Multiple \tag" (it would parse as
    // the builtin), not a text-mode error — unless the user shadowed
    // `\tag` with a macro, which would expand first (issue #75).
    if (ctx.findDef("tag") == null) {
        var ni: u16 = 0;
        while (ni < toks.len) : (ni += 1) {
            const ntk = ctx.toks[toks.start + ni];
            if (ntk.kind == .ctrl and tokNameEq(ntk.name, "tag"))
                return ctx.fail(ntk.pos, "Multiple \\tag");
        }
    }
    // Nested `\text{...}` renders flat inside tags (issue #75).
    const flat = try spliceNestedText(ctx, toks);
    // Text-mode branch selection (issue #163): `\\TextOrMath` keeps
    // its first argument here (math mode keeps the second).
    const sel = try selectBranchToks(ctx, flat, false);
    try checkTextToks(ctx, sel);
    ctx.tag_body = try ctx.allocNode(.{ .text = .{ .toks = sel, .fam = .rm } });
    ctx.tag_starred = starred;
    ctx.row_tagged = true;
    return null;
}

/// Charge one macro expansion against `maxExpand` (KaTeX parity:
/// every builtin-macro use counts there too, issues #161-163).
fn chargeExpansion(ctx: *ParseCtx, use_pos: u32) Error!void {
    ctx.expansions += 1;
    if (ctx.expansions > contract.max_expand) {
        ctx.err_pos = use_pos;
        ctx.err_msg = "macro expansion limit exceeded";
        return error.ExpansionLimit;
    }
}

/// Push a captured argument's tokens back onto the stream (KaTeX
/// macro-result parity: the kept branch parses as enclosing-row
/// siblings at original positions).
fn pushKeptArg(ctx: *ParseCtx, arg: Range) Error!void {
    var i: usize = arg.len;
    while (i > 0) {
        i -= 1;
        try ctx.push(ctx.toks[@as(usize, arg.start) + i]);
    }
}

/// Single-token text equality for `\\@ifnextchar` (KaTeX parity:
/// `args[0][0].text === nextToken.text`): kinds must match, then
/// characters compare by codepoint, control words by name.
fn tokTextEq(a: Tok, b: Tok) bool {
    if (a.kind != b.kind) return false;
    return switch (a.kind) {
        .char => a.cp == b.cp,
        .ctrl => tokNameEq(a.name, b.name),
        .param => a.arg == b.arg,
        else => true,
    };
}

/// Two-branch selector macros (KaTeX `macros.ts`, issues #161-163):
/// `\\@firstoftwo{A}{B}` keeps A, `\\@secondoftwo{A}{B}` keeps B,
/// `\\TextOrMath{A}{B}` keeps B in math mode (text ranges filter to
/// A earlier via `selectBranchToks`), `\\@ifnextchar{S}{T}{E}`
/// keeps T iff the next unexpanded non-space token matches the
/// single token S (else E, never consuming the probe), and
/// `\\@ifstar{T}{E}` runs through `\\@ifnextchar` exactly like KaTeX
/// (`\\@ifnextchar *{\\@firstoftwo{T}}`, so a matched `*` is consumed
/// as the inner `\\@firstoftwo`'s dropped second argument).
/// Nullable like `\\tag`/`\\relax` (a kept side-effect-only branch
/// propagates null): the formula loop skips, argument positions fail
/// exactly as for those. Each use charges `maxExpand`.
fn parseSelectorMacro(ctx: *ParseCtx, depth: u8, t: Tok) Error!?Idx {
    try chargeExpansion(ctx, t.pos);
    if (tokNameEq(t.name, "@ifstar")) {
        const a = try ctx.captureArg();
        try pushExpansionArg(ctx, t, "\\@ifnextchar *{\\@firstoftwo{", a, "}}");
        return parseSingle(ctx, depth);
    }
    if (tokNameEq(t.name, "@ifnextchar")) {
        const sym = try ctx.captureArg();
        const ifb = try ctx.captureArg();
        const elb = try ctx.captureArg();
        // KaTeX `consumeSpaces`: spaces vanish, the probed token
        // never does (math lexing drops whitespace runs already;
        // only pushed-back space chars survive to here).
        while (true) {
            const s = try ctx.peek();
            if (s.kind != .char or s.cp != ' ') break;
            _ = try ctx.next();
        }
        const nxt = try ctx.peek();
        const keep = if (sym.len == 1 and tokTextEq(ctx.toks[sym.start], nxt)) ifb else elb;
        try pushKeptArg(ctx, keep);
        return parseSingle(ctx, depth);
    }
    const a = try ctx.captureArg();
    const b = try ctx.captureArg();
    if (tokNameEq(t.name, "TextOrMath")) {
        try pushKeptArg(ctx, b);
    } else {
        try pushKeptArg(ctx, if (tokNameEq(t.name, "@firstoftwo")) a else b);
    }
    return parseSingle(ctx, depth);
}

/// Parse a row of atoms until the frame terminator. Returns a group.
/// `infix_stop` (issue #94): when non-null, an `\over`-family token
/// ends the loop WITHOUT being consumed (the flag reports it), so a
/// declaration rest stops at the infix (`\bf a\over b` bolds the
/// numerator only — pinned KaTeX 0.18.7 splits the parsed-so-far
/// body). Null keeps the legacy consume-through split. Only the
/// old-style font-declaration arm passes non-null; every other call
/// site (including the infix denominator) passes null.
fn parseFormula(ctx: *ParseCtx, depth: u8, frame: Frame, infix_stop: ?*bool) Error!Idx {
    var buf: [512]u16 = undefined;
    var n: usize = 0;
    var bdepth: u8 = 0;
    const put = struct {
        fn p(b: *[512]u16, nn: *usize, id: Idx) Error!void {
            if (nn.* >= 512) return error.NoSpace;
            b[nn.*] = id;
            nn.* += 1;
        }
    }.p;
    while (true) {
        const t = try ctx.peek();
        if (t.kind == .marker) {
            _ = try ctx.next();
            break;
        }
        if (frame == .bracket and t.kind == .char and t.cp == ']') {
            if (bdepth == 0) {
                _ = try ctx.next();
                break;
            }
            bdepth -= 1;
        }
        if (frame == .bracket and t.kind == .char and t.cp == '[') bdepth += 1;
        switch (t.kind) {
            .end => {
                if (frame != .top) return ctx.fail(t.pos, "unexpected end of input");
                _ = try ctx.next();
                break;
            },
            .rbrace => {
                if (frame == .begingroup) return ctx.fail(t.pos, "expected '\\endgroup'");
                if (frame != .group) return ctx.fail(t.pos, "unexpected '}'");
                _ = try ctx.next();
                break;
            },
            .amp => {
                if (frame != .envcell) return ctx.fail(t.pos, "unexpected '&'");
                break;
            },
            .newline => {
                if (frame == .envcell) break;
                _ = try ctx.next();
                try put(&buf, &n, try ctx.allocNode(.{ .newline = {} }));
            },
            .ctrl => {
                if (isName(t, "end")) {
                    if (frame != .envcell) return ctx.fail(t.pos, "unexpected '\\end'");
                    break;
                }
                if (isName(t, "right")) {
                    if (frame != .leftright and frame != .envcell) return ctx.fail(t.pos, "unexpected '\\right'");
                    if (frame == .leftright) break;
                    // Inside an env cell, \right closes an inner \left
                    // only — but inner \left consumes its own \right,
                    // so reaching here means unbalanced.
                    return ctx.fail(t.pos, "unexpected '\\right'");
                }
                if (isName(t, "endgroup")) {
                    // Strict pairing with `\\begingroup` (KaTeX
                    // parity, pinned 0.18.7): only a `begingroup`
                    // frame may close here. Subset fails fast (the
                    // name is full-only; this loop sits ahead of the
                    // ctrl-dispatch gate).
                    try subsetGate(false);
                    if (frame != .begingroup) return ctx.fail(t.pos, "unexpected '\\endgroup'");
                    _ = try ctx.next();
                    break;
                }
                if (isName(t, "egroup")) {
                    // `\\egroup` is `}` (KaTeX `\\let\\egroup=}` parity,
                    // issue #134): closes `{`/`\\bgroup` groups only —
                    // never `\\begingroup` (strict pairing, the
                    // `\\begingroup a\\egroup` probe) — mirroring the
                    // `.rbrace` arm above. Both profiles: grouping is
                    // core syntax, so no subset gate (unlike
                    // `\\endgroup` just above).
                    if (frame == .begingroup) return ctx.fail(t.pos, "expected '\\endgroup'");
                    if (frame != .group) return ctx.fail(t.pos, "unexpected '}'");
                    _ = try ctx.next();
                    break;
                }
                if (isName(t, "cr")) {
                    if (frame != .envcell) return ctx.fail(t.pos, "unexpected '\\cr'");
                    break;
                }
                if (isInfix(t)) {
                    // `\over`-family splits the current row: kids so
                    // far are the numerator. `\above` is full-only.
                    // A declaration rest (non-null `infix_stop`) stops
                    // here unconsumed instead — the outer loop owns the
                    // split, so the declaration covers the numerator
                    // only (issue #94, pinned KaTeX 0.18.7).
                    if (infix_stop) |st| {
                        st.* = true;
                        break;
                    }
                    _ = try ctx.next();
                    if (tokNameEq(t.name, "above")) try subsetGate(false) else try subsetGate(true);
                    const num = try finishGroup(ctx, buf[0..n]);
                    const frac_id = try parseInfix(ctx, depth, frame, t, num);
                    n = 0;
                    try put(&buf, &n, frac_id);
                    // parseInfix consumed through the frame end.
                    break;
                }
                if (isName(t, "limits") or isName(t, "nolimits")) {
                    _ = try ctx.next();
                    if (n == 0) return ctx.fail(t.pos, "'\\limits' must follow an operator");
                    const last = buf[n - 1];
                    switch (ctx.nodes[last]) {
                        .op => |*o| o.limits = if (isName(t, "limits")) .on else .off,
                        // Explicit `\limits`/`\nolimits` after an Op
                        // wrapper mutates it (KaTeX Parser.ts accepts
                        // limit controls after any `op`); other
                        // classes keep rejecting below.
                        .classwrap => |*c| if (c.class == .Op) {
                            c.limits = if (isName(t, "limits")) .on else .off;
                        } else return ctx.fail(t.pos, "'\\limits' must follow an operator"),
                        // Explicit `\limits` after a star-armed word
                        // operator arms forced stacking in every style
                        // (KaTeX 0.18.7, issue #98); after a plain
                        // name it stays inert (side-set in both
                        // styles), as does `\nolimits` everywhere.
                        // Built-limit operators are already
                        // star-like (their `opBase` stacks).
                        .opname => |*o| if (isName(t, "limits") and o.limits == .on) {
                            o.forced = true;
                        },
                        .varlim => {},
                        else => return ctx.fail(t.pos, "'\\limits' must follow an operator"),
                    }
                    // Scripts after `\limits` attach to the same
                    // operator (`\int\limits_a^b`, KaTeX parity).
                    if (try attachScripts(ctx, depth, last)) |id| buf[n - 1] = id;
                    continue;
                }
                if (full_only and (isName(t, "color") or isName(t, "textcolor"))) {
                    // `\color` is a declaration: its body is the rest
                    // of the enclosing group (braces around the next
                    // atom do NOT scope it). Only `\textcolor` takes a
                    // scoped single group-or-atom body (KaTeX parity).
                    _ = try ctx.next();
                    const spec = try captureColorSpec(ctx);
                    if (isName(t, "textcolor")) {
                        const body = try parseGroupOrAtom(ctx, depth);
                        try put(&buf, &n, try ctx.allocNode(.{
                            .color = .{ .body = body, .spec = spec },
                        }));
                        continue;
                    }
                    // Issue #110 (pinned KaTeX 0.18.7): like the
                    // old-style font rest, a color rest stops at an
                    // infix (`\color{red}a\\over b` colors the
                    // numerator only) — the #94 stop flag + put/continue.
                    var stopped = false;
                    const rest = try parseFormula(ctx, depth, frame, &stopped);
                    const decl = try ctx.allocNode(.{
                        .color = .{ .body = rest, .spec = spec },
                    });
                    if (stopped) {
                        try put(&buf, &n, decl);
                        continue;
                    }
                    // parseFormula consumed the frame end; wrap rest.
                    if (n >= 512) return error.NoSpace;
                    var nb: [512]u16 = undefined;
                    @memcpy(nb[0..n], buf[0..n]);
                    nb[n] = decl;
                    return finishGroup(ctx, nb[0 .. n + 1]);
                }
                if (full_only and (isStyleName(t.name))) {
                    _ = try ctx.next();
                    const st = styleFor(t.name);
                    // Issue #110: style rests stop at infixes too
                    // (`\displaystyle a\\over b` styles the numerator
                    // only) — same #94 mechanism as color above. (Size
                    // declarations keep consuming through: KaTeX sizes
                    // the whole frac.)
                    var stopped = false;
                    const rest = try parseFormula(ctx, depth, frame, &stopped);
                    const styled = try ctx.allocNode(.{ .style = .{ .style = st, .body = rest } });
                    if (stopped) {
                        try put(&buf, &n, styled);
                        continue;
                    }
                    // parseFormula consumed the frame end; wrap rest.
                    const g = try finishGroup(ctx, buf[0..n]);
                    _ = g;
                    // Rebuild: prefix + styled (rest already includes
                    // everything after the style command).
                    var nb: [512]u16 = undefined;
                    @memcpy(nb[0..n], buf[0..n]);
                    nb[n] = styled;
                    return finishGroup(ctx, nb[0 .. n + 1]);
                }
                if (full_only and sizeMultFor(t.name) != null) {
                    // Size declaration (KaTeX `sizing`: declaration
                    // scoping = rest of enclosing group). Mirrors the
                    // style-decl rebuild above; absolute multiplier
                    // (KaTeX `havingSize` resets, never compounds).
                    _ = try ctx.next();
                    const mult = sizeMultFor(t.name).?;
                    const rest = try parseFormula(ctx, depth, frame, null);
                    const g = try finishGroup(ctx, buf[0..n]);
                    _ = g;
                    const sized = try ctx.allocNode(.{ .size = .{ .mult = mult, .body = rest } });
                    var nb: [512]u16 = undefined;
                    @memcpy(nb[0..n], buf[0..n]);
                    nb[n] = sized;
                    return finishGroup(ctx, nb[0 .. n + 1]);
                }
                if (oldStyleDeclFam(t.name)) |fam| {
                    // Old-style font declarations (KaTeX parity, pinned
                    // 0.18.7, issue #94): `\bf` etc. take NO argument —
                    // their body is the rest of the enclosing group
                    // (braces around the next atom do NOT scope them).
                    // New-style `\mathbf` etc. keep the single
                    // group-or-atom body (parseCtrl below). Unlike
                    // color/style/size above, the rest stops at an
                    // infix (`\bf a\over b` bolds the numerator only),
                    // so a stopped rest joins the row and the loop
                    // continues into the split; otherwise the frame end
                    // was consumed and the row rebuilds like above.
                    // Ungated: the subset profile allows these commands
                    // (same `.font` node, core machinery only).
                    _ = try ctx.next();
                    var stopped = false;
                    const rest = try parseFormula(ctx, depth, frame, &stopped);
                    const decl = try ctx.allocNode(.{ .font = .{ .fam = fam, .body = rest } });
                    if (stopped) {
                        try put(&buf, &n, decl);
                        continue;
                    }
                    if (n >= 512) return error.NoSpace;
                    var nb: [512]u16 = undefined;
                    @memcpy(nb[0..n], buf[0..n]);
                    nb[n] = decl;
                    return finishGroup(ctx, nb[0 .. n + 1]);
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| try put(&buf, &n, id);
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| try put(&buf, &n, id);
            },
        }
    }
    return finishGroup(ctx, buf[0..n]);
}

fn finishGroup(ctx: *ParseCtx, kids: []const u16) Error!Idx {
    const s = try ctx.allocKids(kids.len);
    @memcpy(ctx.kids[s .. s + kids.len], kids);
    return ctx.allocNode(.{ .group = .{ .start = s, .len = @intCast(kids.len) } });
}

/// Synthesize an rm `.text` node over literal characters (KaTeX
/// `\html@mathml` math branches, `\copyright`): the MathML text path
/// renders the tokens as one `mtext`, and layout measures them as
/// text — exactly as if the user had typed `\text{…}`. Positions are
/// the use-site offset (the lexer's convention for expanded tokens).
fn textLit(ctx: *ParseCtx, cmd_pos: u32, s: []const u8) Error!Idx {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const len = utf8Len(s[i]);
        if (len == 0 or i + len > s.len) return error.Invalid;
        n += 1;
        i += len;
    }
    const start = try ctx.allocToks(n);
    i = 0;
    var k: usize = 0;
    while (i < s.len) : (k += 1) {
        const len = utf8Len(s[i]);
        ctx.toks[start + k] = .{ .kind = .char, .cp = decode(s[i .. i + len]), .pos = cmd_pos };
        i += len;
    }
    return ctx.allocNode(.{ .text = .{ .toks = .{ .start = start, .len = @intCast(n) }, .fam = .rm } });
}

/// Prepend an empty group inside a cell group (aligned-environment
/// parity, see `parseEnv`). Cells are always groups; anything else
/// passes through untouched.
fn prependEmptyGroup(ctx: *ParseCtx, cell: Idx) Error!Idx {
    const g = switch (ctx.nodes[cell]) {
        .group => |gr| gr,
        else => return cell,
    };
    const empty = try ctx.allocNode(.{ .group = .{ .start = 0, .len = 0 } });
    const s = try ctx.allocKids(@as(usize, g.len) + 1);
    ctx.kids[s] = empty;
    @memcpy(ctx.kids[s + 1 .. s + 1 + g.len], ctx.kids[g.start .. g.start + g.len]);
    return ctx.allocNode(.{ .group = .{ .start = s, .len = g.len + 1 } });
}

fn isName(t: Tok, name: []const u8) bool {
    return t.kind == .ctrl and tokNameEq(t.name, name);
}

fn isInfix(t: Tok) bool {
    if (t.kind != .ctrl) return false;
    return tokNameEq(t.name, "over") or tokNameEq(t.name, "atop") or
        tokNameEq(t.name, "choose") or tokNameEq(t.name, "brace") or
        tokNameEq(t.name, "brack") or tokNameEq(t.name, "above");
}

fn infixKind(t: Tok) FracKind {
    var kind = FracKind{ .bar = true };
    if (tokNameEq(t.name, "atop")) kind.bar = false;
    if (tokNameEq(t.name, "choose")) {
        kind.bar = false;
        kind.fence = .parens;
    }
    // Issue #93: `\\brace`/`\\brack` are their own fences, not
    // parens (KaTeX wraps `{n\\brace k}` in curly braces).
    if (tokNameEq(t.name, "brace")) {
        kind.bar = false;
        kind.fence = .braces;
    }
    if (tokNameEq(t.name, "brack")) {
        kind.bar = false;
        kind.fence = .brackets;
    }
    return kind;
}

/// `\over`-family: caller already consumed the command; parse the
/// denominator through the frame end and build the frac node.
fn parseInfix(ctx: *ParseCtx, depth: u8, frame: Frame, t: Tok, num: Idx) Error!Idx {
    var kind = infixKind(t);
    if (tokNameEq(t.name, "above")) kind.thick = try parseDimenArg(ctx, t);
    const den = try parseFormula(ctx, depth, frame, null);
    return finishInfix(ctx, t, num, den, kind.thick);
}

fn finishInfix(ctx: *ParseCtx, t: Tok, num: Idx, den: Idx, thick: i32) Error!Idx {
    var kind = infixKind(t);
    kind.thick = thick;
    // `\above` with a non-positive bar means NO rule (issue #105,
    // pinned 0.18.7 — `a\above0pt b` is barless like `\atop`).
    if (tokNameEq(t.name, "above") and thick <= 0) kind.bar = false;
    return ctx.allocNode(.{ .frac = .{ .num = num, .den = den, .kind = kind } });
}

/// Parse one atom with optional `^`/`_`/`'` suffixes. Returns null
/// for side-effect commands (macro definitions) that emit no node.
fn parseAtom(ctx: *ParseCtx, depth: u8) Error!?Idx {
    const base = (try parseSingle(ctx, depth)) orelse return null;
    return attachScripts(ctx, depth, base);
}

/// One atom without suffixes (used for script and accent arguments:
/// `x^a_b` attaches both scripts to `x` — KaTeX parity).
fn parseSingleNoSuffix(ctx: *ParseCtx, depth: u8) Error!?Idx {
    return parseSingle(ctx, depth);
}

/// A braced group (full formula) or a single suffix-free atom.
/// Argument-position flavor (issue #111, pinned KaTeX 0.18.7). KaTeX
/// parses an isolated single token with `parseGroup("atom")`: a bare
/// declaration takes an empty body there (the `\frac\bf{a}b` quirk —
/// numerator `font` with an empty ordgroup, `{a}` the denominator, `b`
/// trailing). Script arguments and the `\sqrt` radicand parse on the
/// live stream with `parseGroup(name)`: a bare function without
/// `allowedInArgument` throws at its token, and `\relax` (an
/// `internal` node) is skipped.
const ArgMode = enum { atom, sup, sub, sqrt };

/// KaTeX functions WITHOUT `allowedInArgument` (pinned 0.18.7): bare
/// in a `^`/`_`/`\sqrt` argument they throw `with no arguments as …`
/// at their token. Direct functions fail at the token (corpus `rej-`
/// rows pin the position); `macro` entries reject via their expansion,
/// whose positions point inside KaTeX's expanded buffer and are
/// ungateable (corpus `katex_only` rows pin accept/reject only).
/// Everything absent here parses exactly as today — that fallthrough
/// IS the allow-path (KaTeX's `allowedInArgument` owners: new-style
/// fonts, the genfrac family, integrals, `\relax`, `\verb`, text-mode
/// families, plus the symbol-only macro arms).
fn bareFnInArg(name: []const u8) bool {
    // Over/under/extensible constructs take the shared dispatch
    // predicate (every spelling but the KaTeX-unknown `\angl`
    // extension is a reject-class function there).
    if (parseOverName(name)) |kind| return kind != .angl;
    const bad = [_][]const u8{
        // Old-style declarations (rest-of-group in formula position
        // only — issue #94).
        "rm", "sf", "tt", "bf", "it", "cal",
        "boldsymbol", "bm", "pmb",
        "sqrt",
        "color", "textcolor", "href", "url", "rule", "hbox",
        "kern", "mkern", "mskip", "hskip",
        "vcenter", "mathchoice", "smash", "raisebox", "fbox",
        "phantom", "vphantom", "mathllap", "mathrlap", "mathclap",
        "cancel", "bcancel", "sout", "textcircled",
        "htmlClass", "htmlId", "htmlStyle", "htmlData",
        "operatornamewithlimits",
        "mathinner", "mathop", "mathrel", "mathpunct",
        "mathbin", "mathclose", "mathopen", "mathord",
        // Definition/prefix primitives: KaTeX's entry check fires
        // before any handler, so no side effect leaks.
        "newcommand", "renewcommand", "providecommand",
        "def", "gdef", "edef", "xdef",
        "global", "long", "noexpand", "expandafter", "futurelet", "let",
        "nonumber", "notag", "tag",
        // Macro-class: KaTeX rejects via the expansion.
        "boxed", "dotsi", "substack", "hphantom",
        "llap", "rlap", "clap", "hspace", "bmod", "operatorname",
        "minuso", "underbar",
        // Spacing-emulation arms (KaTeX macros expanding to
        // `\mskip`/`\hskip`).
        "quad", "qquad", "enskip",
        "thinspace", "medspace", "thickspace",
        "negthinspace", "negmedspace", "negthickspace", "enspace",
    };
    for (bad) |b| if (tokNameEq(b, name)) return true;
    return false;
}

/// The six integrals are KaTeX's only operator-class names with
/// `allowedInArgument` (pinned 0.18.7 `op.ts`): `x_\int` accepts.
fn isScriptIntegral(name: []const u8) bool {
    const ints = [_][]const u8{ "int", "iint", "iiint", "oint", "oiint", "oiiint" };
    for (ints) |o| if (tokNameEq(o, name)) return true;
    return false;
}

fn parseGroupOrAtom(ctx: *ParseCtx, depth: u8) Error!Idx {
    return parseGroupOrAtomMode(ctx, depth, .atom, 0);
}

/// `op_pos` is the `^`/`_` operator (script modes fail there when no
/// group follows); unused by `.atom` and `.sqrt`, which fail at the
/// offending token instead.
fn parseGroupOrAtomMode(ctx: *ParseCtx, depth: u8, mode: ArgMode, op_pos: u32) Error!Idx {
    // Island bodies re-enter math with text-lexed tokens (issue
    // #81): math lexing drops whitespace runs, so argument scanning
    // skips the surviving `char(' ')` tokens too. Math-lexed input
    // never carries them, so plain math parses bit-identically.
    while (true) {
        const s = try ctx.peek();
        if (s.kind != .char or s.cp != ' ') break;
        _ = try ctx.next();
    }
    const t = try ctx.peek();
    if (t.kind == .lbrace) {
        _ = try ctx.next();
        return parseFormula(ctx, depth + 1, .group, null);
    }
    // Depth guard: every nesting level passes through here or a group.
    if (depth >= contract.max_nesting_depth) {
        return tooDeep(ctx, t.pos);
    }
    if (mode == .atom) {
        // The `\frac\bf{a}b` quirk (issue #111): in an isolated
        // argument a bare declaration takes an empty body and consumes
        // nothing further (KaTeX `scanArgument` isolation + the
        // zero-argument font handler). User macros still shadow.
        if (t.kind == .ctrl) {
            if (oldStyleDeclFam(t.name)) |fam| {
                if (t.name.len > 0 and !t.noexpand and ctx.findDef(t.name) == null) {
                    _ = try ctx.next();
                    const empty = try ctx.allocNode(.{ .group = .{ .start = 0, .len = 0 } });
                    return ctx.allocNode(.{ .font = .{ .fam = fam, .body = empty } });
                }
            }
        }
        const maybe = try parseSingle(ctx, depth + 1);
        return maybe orelse ctx.fail(t.pos, "expected argument");
    }
    return parseScriptAtom(ctx, depth, mode, op_pos);
}

/// Parse one script/`\sqrt`-radicand argument on the live stream
/// (KaTeX `parseGroup(name)` + the `internal`-skip loop, pinned
/// 0.18.7, issue #111). `op_pos` is the `^`/`_` operator (script
/// modes fail there when no group follows); `\sqrt` mode fails at the
/// offending token instead.
fn parseScriptAtom(ctx: *ParseCtx, depth: u8, mode: ArgMode, op_pos: u32) Error!Idx {
    while (true) {
        const t = try ctx.peek();
        switch (t.kind) {
            .lbrace => {
                _ = try ctx.next();
                return parseFormula(ctx, depth + 1, .group, null);
            },
            .ctrl => {
                const name = t.name;
                // User macros shadow everything (KaTeX gullet expands
                // first); the expansion re-enters this loop, so a
                // macro expanding to a bare function still throws.
                if (name.len > 0 and !t.noexpand) {
                    if (ctx.findDef(name)) |def| {
                        _ = try ctx.next();
                        try ctx.expandUse(def, t.pos);
                        continue;
                    }
                }
                // `\limits`/`\nolimits` are implicit (KaTeX
                // `implicitCommands`): no group follows them.
                if (tokNameEq(name, "limits") or tokNameEq(name, "nolimits")) {
                    if (mode == .sqrt)
                        return ctx.fail(t.pos, "expected group as argument to '\\sqrt'");
                    if (mode == .sup)
                        return ctx.fail(op_pos, "expected group after '^'");
                    return ctx.fail(op_pos, "expected group after '_'");
                }
                if (isScriptIntegral(name)) {
                    // The six integrals carry KaTeX
                    // `allowedInArgument` — the only names the
                    // fallthrough would misroute (operator class).
                    const r = try parseSingle(ctx, depth + 1);
                    if (r == null) continue;
                    return r.?;
                }
                if (bareFnInArg(name)) return scriptFnFail(ctx, t.pos, mode);
                // Accent names live in the symbol table too, but KaTeX
                // parses the accent functions first — so does this.
                if (symbols.lookupAccent(name) != null) return scriptFnFail(ctx, t.pos, mode);
                if (symbols.lookup(name)) |sym| {
                    // Every operator-class symbol is a KaTeX function
                    // (integrals were allowed above); plain symbols
                    // parse as atoms.
                    if (sym.class == .Op) return scriptFnFail(ctx, t.pos, mode);
                    const r = try parseSingle(ctx, depth + 1);
                    if (r == null) continue;
                    return r.?;
                }
                if (symbols.lookupDelim(name) != null) {
                    const r = try parseSingle(ctx, depth + 1);
                    if (r == null) continue;
                    return r.?;
                }
                if (name.len == 1) {
                    const c = name[0];
                    switch (c) {
                        '{', '}', '$', '%', '&', '#', '_', '|', ' ' => {
                            const r = try parseSingle(ctx, depth + 1);
                            if (r == null) continue;
                            return r.?;
                        },
                        // Spacing/newline escapes are KaTeX macros or
                        // the `\\` function — all reject in scripts.
                        ',', ':', '>', ';', '!', '\\' => return scriptFnFail(ctx, t.pos, mode),
                        else => {
                            // Text accents are KaTeX functions;
                            // single-letter symbols (`\S`) and unknown
                            // names keep the existing path (symbol or
                            // `undefined control sequence`).
                            if (textAccentCp(c) != null) return scriptFnFail(ctx, t.pos, mode);
                            const r = try parseSingle(ctx, depth + 1);
                            if (r == null) continue;
                            return r.?;
                        },
                    }
                }
                // Anything else parses exactly as today (unknown names
                // keep `undefined control sequence` at the token).
                const r = try parseSingle(ctx, depth + 1);
                if (r == null) continue;
                return r.?;
            },
            // Lone `^`/`_`/`&`/`}`, or end of input, start no group
            // (KaTeX `parseGroup` returns null there): a script
            // operator points at itself; `\sqrt` points at the token.
            .sup, .sub, .amp, .rbrace, .end => {
                if (mode == .sqrt)
                    return ctx.fail(t.pos, "expected group as argument to '\\sqrt'");
                if (mode == .sup)
                    return ctx.fail(op_pos, "expected group after '^'");
                return ctx.fail(op_pos, "expected group after '_'");
            },
            else => {
                // Non-control tokens parse exactly as today.
                const r = try parseSingle(ctx, depth + 1);
                if (r == null) continue;
                return r.?;
            },
        }
    }
}

/// KaTeX `with no arguments as …` (issue #111): the message shape is
/// KaTeX's minus the function name (house style keeps messages
/// static, as with `undefined control sequence`); positions are exact.
fn scriptFnFail(ctx: *ParseCtx, pos: u32, mode: ArgMode) Error {
    return switch (mode) {
        .sup => ctx.fail(pos, "function with no arguments as superscript"),
        .sub => ctx.fail(pos, "function with no arguments as subscript"),
        .sqrt => ctx.fail(pos, "function with no arguments as argument to '\\sqrt'"),
        .atom => unreachable,
    };
}

fn tooDeep(ctx: *ParseCtx, pos: u32) Error {
    ctx.err_pos = pos;
    ctx.err_msg = "nesting too deep";
    return error.TooDeep;
}

fn parseSingle(ctx: *ParseCtx, depth: u8) Error!?Idx {
    if (depth >= contract.max_nesting_depth) {
        const t = try ctx.peek();
        return tooDeep(ctx, t.pos);
    }
    const t = try ctx.next();
    switch (t.kind) {
        .char => {
            // Captured whitespace never reaches math (text captures
            // own it); guard anyway.
            if (t.cp == ' ') return null;
            // TeX parameter character: only legal inside macro
            // definitions (handled by the token capturer); KaTeX
            // rejects it in math mode.
            if (t.cp == '#') return ctx.fail(t.pos, "unexpected '#'");
            // KaTeX has no `$` delimiters inside math input.
            if (t.cp == '$') return ctx.fail(t.pos, "can't use '$' in math mode");
            if (t.cp == '~') {
                const id: ?Idx = try ctx.allocNode(.{ .nbsp = {} });
                return id;
            }
            if (t.cp == '\'') {
                // KaTeX parity: `'` starts no atom — at expression
                // level (row start, braced groups) it is an
                // empty-base prime (`parseAtom` with a null base
                // feeds the suffix loop; pinned 0.18.7). In
                // group-required position (`x^'`) KaTeX rejects;
                // `parseGroupOrAtom` filters those before reaching
                // here, and `attachScripts` consumes suffixed ones.
                const prime = try ctx.allocNode(.{ .atom = .{
                    .class = .Ord,
                    .font = .rm,
                    .cp = 0x2032,
                    .textord = true,
                } });
                const base = try ctx.allocNode(.{ .group = .{ .start = 0, .len = 0 } });
                return try ctx.allocNode(.{ .supsub = .{
                    .base = base,
                    .sup = prime,
                    .sub = NONE,
                    .prime_sup = true,
                } });
            }
            const cls = symbols.asciiClass(t.cp) orelse .Ord;
            const font: FontFam = if (t.cp >= '0' and t.cp <= '9')
                .rm
            else if ((t.cp >= 'a' and t.cp <= 'z') or (t.cp >= 'A' and t.cp <= 'Z'))
                .mathit
            else
                .rm;
            const id: ?Idx = try ctx.allocNode(.{ .atom = .{ .class = cls, .font = font, .cp = t.cp, .textord = symbols.isTextordCp(t.cp) } });
            return id;
        },
        .lbrace => {
            const id: ?Idx = try parseFormula(ctx, depth + 1, .group, null);
            return id;
        },
        .sup => return ctx.fail(t.pos, "expected base before '^'"),
        .sub => return ctx.fail(t.pos, "expected base before '_'"),
        .amp => return ctx.fail(t.pos, "unexpected '&'"),
        .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
        .newline => {
            const id: ?Idx = try ctx.allocNode(.{ .newline = {} });
            return id;
        },
        .param => return ctx.fail(t.pos, "unexpected '#'"),
        .marker => return ctx.fail(t.pos, "unexpected input"),
        .end => return ctx.fail(t.pos, "unexpected end of input"),
        .ctrl => {
            // Macro definitions are side effects (no node).
            if (t.name.len > 1) {
                // Subset profile: the definition branches below vanish
                // at compile time (`full_only`); fail fast here so the
                // `Unsupported` contract (and positions) never change.
                if (comptime active_profile == .subset) {
                    if (isFullOnlyDefName(t.name)) return error.Unsupported;
                }
                if (full_only and (tokNameEq(t.name, "newcommand") or tokNameEq(t.name, "renewcommand") or
                    tokNameEq(t.name, "providecommand")))
                {
                    try parseNewCommand(ctx, t, tokNameEq(t.name, "renewcommand"), tokNameEq(t.name, "providecommand"));
                    return null;
                }
                if (full_only and (tokNameEq(t.name, "def") or tokNameEq(t.name, "gdef"))) {
                    try parseDef(ctx, t);
                    return null;
                }
                if (full_only and (tokNameEq(t.name, "edef") or tokNameEq(t.name, "xdef"))) {
                    try parseEdef(ctx, t);
                    return null;
                }
                if (full_only and (tokNameEq(t.name, "global"))) {
                    try parseGlobal(ctx, t);
                    return null;
                }
                if (full_only and (tokNameEq(t.name, "long"))) {
                    // KaTeX prefix parity (def.ts): `\long` is ignored
                    // (no `\par` exists), but the next token must open
                    // a macro assignment like after `\global`.
                    try parseGlobal(ctx, t);
                    return null;
                }
                if (tokNameEq(t.name, "relax")) {
                    // No-op primitive (KaTeX relax.ts, text+math): no node.
                    return null;
                }
                if (tokNameEq(t.name, "nonumber") or tokNameEq(t.name, "notag")) {
                    // KaTeX parity (`macros.js`, pinned 0.18.7):
                    // `\nonumber` = `\gdef\@eqnsw{0}`, `\notag` an
                    // alias. Numbered display envs drop the row's
                    // number columns; elsewhere there is nothing to
                    // suppress. Accepted in both modes, even outside
                    // numbering contexts, like the bundle. Issue #88.
                    ctx.row_nonumber = true;
                    return null;
                }
                if (tokNameEq(t.name, "allowbreak") or tokNameEq(t.name, "nobreak")) {
                    // KaTeX spacing functions render a bare `<mspace/>`
                    // (symbolsSpacing.ts); zero glue here.
                    return try ctx.allocNode(.{ .space = 0 });
                }
                if (full_only and (tokNameEq(t.name, "noexpand"))) {
                    // KaTeX parity (macros.ts): the next token, read raw,
                    // is suppressed when it names a user macro (treated
                    // as `\relax`); anything else parses normally.
                    // A trailing `\noexpand` is accepted (it hoists
                    // nothing), matching the bundle.
                    const u = try ctx.next();
                    if (u.kind == .end) return null;
                    if (u.kind == .ctrl) {
                        // KaTeX `isExpandable`: only a macro that would
                        // actually expand is suppressed; builtins,
                        // symbols, undefined names, and `noexpand`-marked
                        // aliases parse normally.
                        if (ctx.findDef(u.name)) |d| {
                            if (!d.is_alias or !d.alias_tok.noexpand) return null;
                        }
                    }
                    try ctx.push(u);
                    return parseSingle(ctx, depth);
                }
                if (full_only and (tokNameEq(t.name, "expandafter"))) {
                    // KaTeX parity (macros.ts): hold the next token raw,
                    // expand the one after it a single level, then parse
                    // the held token first.
                    const held = try ctx.next();
                    const nxt = try ctx.next();
                    if (nxt.kind == .ctrl) {
                        if (ctx.findDef(nxt.name)) |def| {
                            try ctx.expandUse(def, nxt.pos);
                            try ctx.push(held);
                            return parseSingle(ctx, depth);
                        }
                    }
                    try ctx.push(nxt);
                    try ctx.push(held);
                    return parseSingle(ctx, depth);
                }
                if (full_only and (tokNameEq(t.name, "futurelet"))) {
                    try parseFuturelet(ctx, t);
                    return null;
                }
                if (full_only and (tokNameEq(t.name, "let"))) {
                    try parseLet(ctx, t);
                    return null;
                }
            }
            // User macros shadow builtins. A `noexpand`-marked token
            // (alias bound to a then-undefined macro) skips expansion
            // and parses as its face value, matching KaTeX.
            if (t.name.len > 0 and isMacroName(t) and !t.noexpand) {
                if (ctx.findDef(t.name)) |def| {
                    try ctx.expandUse(def, t.pos);
                    return parseSingle(ctx, depth);
                }
            }
            // Equation tags are side effects (no node; hoisted at
            // `parse()`). Handled here — after macro expansion, so a
            // user `\tag` macro shadows the builtin — rather than in
            // `parseCtrl`, which cannot return null.
            if (full_only and tokNameEq(t.name, "tag")) return parseTag(ctx, t);
            // Selector macros (issues #161-163): nullable like
            // `\\tag` above (a kept side-effect-only branch
            // propagates null), after macro expansion so user
            // definitions shadow the builtins. The subset gate below
            // reports them `Unsupported` via `full_only_ctrl_names`.
            if (full_only and (tokNameEq(t.name, "@firstoftwo") or tokNameEq(t.name, "@secondoftwo") or
                tokNameEq(t.name, "@ifnextchar") or tokNameEq(t.name, "@ifstar") or
                tokNameEq(t.name, "TextOrMath")))
            {
                return parseSelectorMacro(ctx, depth, t);
            }
            // Subset profile: the full-only `parseCtrl` branches below
            // vanish at compile time (`full_only`); fail fast here so
            // the `Unsupported` contract (and positions) never change.
            // Sits after macro expansion so shadowing still works.
            if (comptime active_profile == .subset) {
                if (isFullOnlyCtrlName(t.name)) return error.Unsupported;
            }
            const id: ?Idx = try parseCtrl(ctx, depth, t);
            return id;
        },
    }
}

fn isMacroName(t: Tok) bool {
    // Single-character names always go through macro lookup too
    // (`\let` can alias anything); multi-letter names likewise.
    return t.kind == .ctrl;
}

/// Attach `^`/`_`/`'` suffixes to a base node.
fn attachScripts(ctx: *ParseCtx, depth: u8, base: Idx) Error!?Idx {
    var sup_parts: [9]Idx = undefined;
    var nsup: u8 = 0;
    var prime_made = false;
    var sub: Idx = NONE;
    while (true) {
        const p = try ctx.peek();
        if (p.kind == .sup) {
            _ = try ctx.next();
            if (nsup > 0 and !prime_made) return ctx.fail(p.pos, "double superscript");
            // KaTeX parity: a missing group at EOF points at the
            // operator (`x^` → 1), not at end of input.
            if ((try ctx.peek()).kind == .end) return ctx.fail(p.pos, "expected group after '^'");
            // KaTeX parity: `'`/`\rq` start no atom — in
            // group-required position the missing group points at
            // the operator too (`x^'` rejects at `^`, pinned
            // 0.18.7).
            const q = try ctx.peek();
            if ((q.kind == .char and q.cp == '\'') or (q.kind == .ctrl and tokNameEq(q.name, "rq")))
                return ctx.fail(p.pos, "expected group after '^'");
            const s = try parseGroupOrAtomMode(ctx, depth, .sup, p.pos);
            if (prime_made) {
                if (nsup >= 9) return ctx.fail(p.pos, "superscript too complex");
                sup_parts[nsup] = s;
                nsup += 1;
                prime_made = false;
            } else {
                sup_parts[0] = s;
                nsup = 1;
            }
        } else if (p.kind == .sub) {
            _ = try ctx.next();
            if (sub != NONE) return ctx.fail(p.pos, "double subscript");
            // KaTeX parity: a missing group at EOF points at the
            // operator (`x_` → 1), not at end of input.
            if ((try ctx.peek()).kind == .end) return ctx.fail(p.pos, "expected group after '_'");
            // Same atomless-`'`/`\rq` rule as `^` above.
            const q2 = try ctx.peek();
            if ((q2.kind == .char and q2.cp == '\'') or (q2.kind == .ctrl and tokNameEq(q2.name, "rq")))
                return ctx.fail(p.pos, "expected group after '_'");
            sub = try parseGroupOrAtomMode(ctx, depth, .sub, p.pos);
        } else if ((p.kind == .char and p.cp == '\'') or (p.kind == .ctrl and tokNameEq(p.name, "rq"))) {
            // KaTeX parity: `\rq` is the `'` macro — after a base it
            // runs this same suffix-prime path (pinned 0.18.7).
            // Subset profile: `\\rq` is a full-only name (the `'`
            // spelling stays core syntax) — fail fast like the
            // ctrl-dispatch gate.
            if (p.kind == .ctrl) try subsetGate(false);
            _ = try ctx.next();
            // KaTeX parity: a prime after an explicit superscript is a
            // double superscript (`x^2'` rejects; `x'^2` merges).
            if (nsup > 0 and !prime_made) return ctx.fail(p.pos, "double superscript");
            if (nsup >= 9) return ctx.fail(p.pos, "superscript too complex");
            sup_parts[nsup] = try ctx.allocNode(.{ .atom = .{
                .class = .Ord,
                .font = .rm,
                .cp = 0x2032,
                .textord = true,
            } });
            nsup += 1;
            prime_made = true;
        } else break;
    }
    if (nsup == 0 and sub == NONE) return base;
    var sup: Idx = NONE;
    if (nsup == 1) {
        sup = sup_parts[0];
    } else if (nsup > 1) {
        const s = try ctx.allocKids(nsup);
        @memcpy(ctx.kids[s .. s + nsup], sup_parts[0..nsup]);
        sup = try ctx.allocNode(.{ .group = .{ .start = s, .len = nsup } });
    }
    const id: ?Idx = try ctx.allocNode(.{ .supsub = .{
        .base = base,
        .sup = sup,
        .sub = sub,
        .prime_sup = prime_made and nsup > 0,
    } });
    return id;
}

/// Parse one environment cell: a formula stopping at `&`, `\\`,
/// `\cr`, `\end`, or `\right`. Returns the cell group and terminator.
fn parseCell(ctx: *ParseCtx, depth: u8) Error!struct { cell: Idx, term: CellTerm, term_pos: u32 } {
    var buf: [512]u16 = undefined;
    var n: usize = 0;
    while (true) {
        const t = try ctx.peek();
        switch (t.kind) {
            .end => return ctx.fail(t.pos, "unexpected end of input"),
            .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
            .amp => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .amp, .term_pos = t.pos };
            },
            .newline => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline, .term_pos = t.pos };
            },
            .ctrl => {
                if (isName(t, "end") or isName(t, "right") or isName(t, "cr") or isName(t, "newline")) {
                    // `\cr` and `\newline` are row separators like `\\`:
                    // consume them (issue #51 robustness — the token
                    // must not reach the next cell; `\newline` breaks
                    // env rows per pinned KaTeX, issue #79).
                    // `\end`/`\right` stay for the caller.
                    if (isName(t, "cr") or isName(t, "newline")) _ = try ctx.next();
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = if (isName(t, "amp")) .amp else if (isName(t, "end")) .end else if (isName(t, "right")) .right else .newline, .term_pos = t.pos };
                }
                // `\\` is the row separator inside environments (the
                // lexer yields it as `.ctrl("\\")`, never `.newline`).
                if (tokNameEq(t.name, "\\")) {
                    _ = try ctx.next();
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline, .term_pos = t.pos };
                }
                // Gap-position rule (KaTeX `getHLines` parity): a rule
                // command opening a cell belongs to the row gap, not
                // the cell, so it contributes no cell content.
                // Rule commands never belong to a cell (the row loop
                // consumes row-leading rules into gap rows); mid-cell
                // they are misplaced (KaTeX parity, issue #33).
                if (n == 0 and (tokNameEq(t.name, "hline") or tokNameEq(t.name, "hdashline"))) {
                    if (tokNameEq(t.name, "hline")) return ctx.fail(t.pos, "\\hline valid only within array environment");
                    return ctx.fail(t.pos, "\\hdashline valid only within array environment");
                }
                if (isInfix(t)) {
                    _ = try ctx.next();
                    if (tokNameEq(t.name, "above")) try subsetGate(false) else try subsetGate(true);
                    const num = try finishGroup(ctx, buf[0..n]);
                    var thick: i32 = 0;
                    if (tokNameEq(t.name, "above")) thick = try parseDimenArg(ctx, t);
                    const rest = try parseCellRest(ctx, depth);
                    const frac_id = try finishInfix(ctx, t, num, rest.cell, thick);
                    buf[0] = frac_id;
                    n = 1;
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = rest.term, .term_pos = t.pos };
                }
                if (isName(t, "limits") or isName(t, "nolimits")) {
                    _ = try ctx.next();
                    if (n == 0) return ctx.fail(t.pos, "'\\limits' must follow an operator");
                    const last = buf[n - 1];
                    switch (ctx.nodes[last]) {
                        .op => |*o| o.limits = if (isName(t, "limits")) .on else .off,
                        // Explicit `\limits`/`\nolimits` after an Op
                        // wrapper mutates it (KaTeX Parser.ts accepts
                        // limit controls after any `op`); other
                        // classes keep rejecting below.
                        .classwrap => |*c| if (c.class == .Op) {
                            c.limits = if (isName(t, "limits")) .on else .off;
                        } else return ctx.fail(t.pos, "'\\limits' must follow an operator"),
                        // Explicit `\limits` after a star-armed word
                        // operator arms forced stacking in every style
                        // (KaTeX 0.18.7, issue #98); after a plain
                        // name it stays inert (side-set in both
                        // styles), as does `\nolimits` everywhere.
                        // Built-limit operators are already
                        // star-like (their `opBase` stacks).
                        .opname => |*o| if (isName(t, "limits") and o.limits == .on) {
                            o.forced = true;
                        },
                        .varlim => {},
                        else => return ctx.fail(t.pos, "'\\limits' must follow an operator"),
                    }
                    // Scripts after `\limits` attach to the same
                    // operator (`\int\limits_a^b`, KaTeX parity).
                    if (try attachScripts(ctx, depth, last)) |id| buf[n - 1] = id;
                    continue;
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
        }
    }
}

/// Parse the remainder of a cell after an infix command (through the
/// cell terminator, which is left for the caller to consume... no —
/// consumed here and reported).
fn parseCellRest(ctx: *ParseCtx, depth: u8) Error!struct { cell: Idx, term: CellTerm } {
    var buf: [512]u16 = undefined;
    var n: usize = 0;
    while (true) {
        const t = try ctx.peek();
        switch (t.kind) {
            .end => return ctx.fail(t.pos, "unexpected end of input"),
            .rbrace => return ctx.fail(t.pos, "unexpected '}'"),
            .amp => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .amp };
            },
            .newline => {
                _ = try ctx.next();
                return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
            },
            .ctrl => {
                if (isName(t, "end") or isName(t, "right") or isName(t, "cr") or isName(t, "newline")) {
                    // Same `\cr`/`\newline` consume as the cell path
                    // (issues #51/#79).
                    if (isName(t, "cr") or isName(t, "newline")) _ = try ctx.next();
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = if (isName(t, "end")) .end else if (isName(t, "right")) .right else .newline };
                }
                if (tokNameEq(t.name, "\\")) {
                    _ = try ctx.next();
                    return .{ .cell = try finishGroup(ctx, buf[0..n]), .term = .newline };
                }
                // Same misplacement rule on the infix-rest path.
                if (n == 0 and (tokNameEq(t.name, "hline") or tokNameEq(t.name, "hdashline"))) {
                    if (tokNameEq(t.name, "hline")) return ctx.fail(t.pos, "\\hline valid only within array environment");
                    return ctx.fail(t.pos, "\\hdashline valid only within array environment");
                }
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
            else => {
                const maybe = try parseAtom(ctx, depth);
                if (maybe) |id| {
                    if (n >= 512) return error.NoSpace;
                    buf[n] = id;
                    n += 1;
                }
            },
        }
    }
}

/// Push a builtin-macro expansion (KaTeX `macros.js` parity) as
/// synthetic tokens, LIFO so the template's first token parses next.
/// The template lexes with the shared byte lexer over its own static
/// bytes (token names borrow the template literal), so the expansion
/// quotes the pinned bundle verbatim; every token carries the use
/// site `pos` and `synth` (KaTeX reports macro-use positions).
/// Bounded: templates hold fewer than 64 tokens and `push` enforces
/// the pushback pool. Like `\iff`/`\plim`, callers then return
/// `parseSingle`, so the expansion parses as enclosing-row siblings.
/// Raw-token caveat (shared with `parseDimenArg`): tokens after the
/// macro name are read unexpanded, so a user macro feeding a builtin
/// expansion's scanner does not unfold the way KaTeX's expander
/// would. Nothing in the sweep covers that shape.
/// Lex one template run and push it last-first (the pushback stack
/// pops last-pushed-first). Template tokens are synth at the use
/// site, like `pushExpansion`.
fn pushTemplateToks(ctx: *ParseCtx, use: Tok, template: []const u8) Error!void {
    const saved_src = ctx.src;
    const saved_spos = ctx.spos;
    const saved_keep = ctx.keep_spaces;
    defer {
        ctx.src = saved_src;
        ctx.spos = saved_spos;
        ctx.keep_spaces = saved_keep;
    }
    ctx.src = template;
    ctx.spos = 0;
    ctx.keep_spaces = false;
    // Lex the whole run into the token arena first (last-first
    // push needs it all buffered): templates are bounded by the
    // arena's 1536 cap like every other capture — the old 64-slot
    // stack buffer overflowed on `\minuso` (pinned 0.18.7).
    const start = try ctx.allocToks(0);
    var n: u16 = 0;
    while (true) {
        const tk = try ctx.lexRaw();
        if (tk.kind == .end) break;
        _ = try ctx.allocToks(1);
        ctx.toks[start + n] = tk;
        n += 1;
    }
    var i = n;
    while (i > 0) {
        i -= 1;
        var tk = ctx.toks[start + i];
        tk.pos = use.pos;
        tk.synth = true;
        try ctx.push(tk);
    }
}

fn pushExpansion(ctx: *ParseCtx, use: Tok, template: []const u8) Error!void {
    try pushTemplateToks(ctx, use, template);
}

/// Like `pushExpansion`, but splices an already-captured argument
/// token run between a prefix and a suffix template (KaTeX `\pod` /
/// `\pmod`, pinned 0.18.7 `macros.js`). The pieces parse as
/// enclosing-row siblings — flat, never a `.group` shell — exactly
/// as hand-written input would. Captured tokens keep their own
/// positions (KaTeX parses the expanded stream at original
/// locations); only template tokens are synth at the use site.
fn pushExpansionArg(ctx: *ParseCtx, use: Tok, prefix: []const u8, arg: Range, suffix: []const u8) Error!void {
    try pushTemplateToks(ctx, use, suffix);
    var i: usize = arg.len;
    while (i > 0) {
        i -= 1;
        try ctx.push(ctx.toks[@as(usize, arg.start) + i]);
    }
    try pushTemplateToks(ctx, use, prefix);
}

/// Push captured tokens last-first, dropping top-level whitespace
/// (KaTeX's tokenizer skips spaces in math mode, but
/// space-preserving captures keep them; a bare argument like
/// `\frac 1 2` then chokes on the space — issue #89). Nested
/// spaces survive (`\text{a b}` keeps its space).
fn pushRangeClean(ctx: *ParseCtx, arg: Range, from: usize, to: usize) Error!void {
    const n = to - from;
    if (n > 1536) return error.NoSpace;
    var skip: [24]u64 = .{0} ** 24;
    var bdepth: usize = 0;
    var j: usize = 0;
    while (j < n) : (j += 1) {
        const tk = ctx.toks[@as(usize, arg.start) + from + j];
        if (tk.kind == .lbrace) {
            bdepth += 1;
        } else if (tk.kind == .rbrace) {
            bdepth -|= 1;
        } else if (tk.kind == .char and tk.cp == ' ' and bdepth == 0) {
            skip[j / 64] |= (@as(u64, 1) << @intCast(j % 64));
        }
    }
    var k: usize = n;
    while (k > 0) {
        k -= 1;
        if ((skip[k / 64] & (@as(u64, 1) << @intCast(k % 64))) != 0) continue;
        try ctx.push(ctx.toks[@as(usize, arg.start) + from + k]);
    }
}

/// Scan a captured argument for top-level bars. Records at most 8
/// split points (`at`) with their kinds (`dbl`); returns the split
/// count. With `dbl` set, a `|` char followed by another `|` char
/// collapses to one double split (KaTeX's `\@ifnextchar` mimic)
/// and a `\|` command is a double split on its own; without it
/// (lowercase `\set`, whose KaTeX `middleDouble` is empty) every
/// `|` char is single and `\|` stays literal.
fn scanBars(ctx: *ParseCtx, arg: Range, dbl: bool) struct { at: [8]usize, dbl: [8]bool, n: usize } {
    var at: [8]usize = undefined;
    var isdbl: [8]bool = undefined;
    var n: usize = 0;
    var bdepth: usize = 0;
    var k: usize = 0;
    while (k < arg.len) : (k += 1) {
        const tk = ctx.toks[@as(usize, arg.start) + k];
        if (tk.kind == .lbrace) {
            bdepth += 1;
        } else if (tk.kind == .rbrace) {
            bdepth -|= 1;
        } else if (bdepth == 0 and n < at.len) {
            if (tk.kind == .char and tk.cp == '|') {
                if (dbl and k + 1 < arg.len) {
                    const nx = ctx.toks[@as(usize, arg.start) + k + 1];
                    if (nx.kind == .char and nx.cp == '|') {
                        at[n] = k;
                        isdbl[n] = true;
                        n += 1;
                        k += 1;
                        continue;
                    }
                }
                at[n] = k;
                isdbl[n] = false;
                n += 1;
            } else if (dbl and tk.kind == .ctrl and tokNameEq(tk.name, "|")) {
                at[n] = k;
                isdbl[n] = true;
                n += 1;
            }
        }
    }
    return .{ .at = at, .dbl = isdbl, .n = n };
}

/// Expand a `\set`-family argument around its top-level bars
/// (KaTeX `bra@ket`/`bra@set`): `prefix`, then segments joined by
/// the bar templates, then `suffix`. `first_only` replaces just the
/// first bar (lowercase `\set`, capital `\Set`); otherwise every
/// bar is replaced (`\Braket`). Bar tokens span 1 (`|`) or 2
/// (`||`) tokens; `\|` is one token.
fn pushBarSplit(
    ctx: *ParseCtx,
    use: Tok,
    arg: Range,
    prefix: []const u8,
    mid_single: []const u8,
    mid_double: []const u8,
    suffix: []const u8,
    first_only: bool,
    dbl: bool,
) Error!void {
    const bars = scanBars(ctx, arg, dbl);
    // `first_only` replaces just the first bar; later bars ride
    // along literally inside the tail segment.
    const nsplit: usize = if (bars.n == 0) 0 else if (first_only) 1 else bars.n;
    // Width of a bar in tokens: `||` spans 2, `|` and `\|` span 1.
    const barWidth = struct {
        fn w(c: *ParseCtx, a: Range, at: usize, is_dbl: bool) usize {
            if (is_dbl and c.toks[@as(usize, a.start) + at].kind == .char) return 2;
            return 1;
        }
    }.w;
    try pushTemplateToks(ctx, use, suffix);
    var s: usize = nsplit;
    while (true) {
        // Segment s spans (bar_s end)..(bar_{s+1} start).
        const seg_from: usize = if (s == 0) 0 else bars.at[s - 1] + barWidth(ctx, arg, bars.at[s - 1], bars.dbl[s - 1]);
        const seg_to: usize = if (s < nsplit) bars.at[s] else arg.len;
        try pushRangeClean(ctx, arg, seg_from, seg_to);
        if (s == 0) break;
        try pushTemplateToks(ctx, use, if (bars.dbl[s - 1]) mid_double else mid_single);
        s -= 1;
    }
    try pushTemplateToks(ctx, use, prefix);
}

/// One `\char`-base digit value (KaTeX `digitToNumber`: 0-9a-fA-F),
/// or null when the token stops the scan. Only character tokens
/// continue a number; anything else (control words included) ends it.
fn charDigitVal(t: Tok, base: u32) ?u64 {
    if (t.kind != .char or t.cp > 127) return null;
    const c: u8 = @intCast(t.cp);
    const d: u64 = if (c >= '0' and c <= '9')
        c - '0'
    else if (c >= 'a' and c <= 'f')
        c - 'a' + 10
    else if (c >= 'A' and c <= 'F')
        c - 'A' + 10
    else
        return null;
    if (d >= base) return null;
    return d;
}

/// Saturating `num * base + d` (u64): `\char` overflow can only
/// surface as "invalid code point", never wrap.
fn charAccum(num: u64, base: u32, d: u64) u64 {
    const b: u64 = base;
    if (num > (std.math.maxInt(u64) - d) / b) return std.math.maxInt(u64);
    return num * b + d;
}

/// `\char` result: KaTeX `\@char` returns a `textord` node — an
/// Ord-class roman atom, exactly like a symbol-table hit.
fn charAtom(ctx: *ParseCtx, cp: u21) Error!Idx {
    return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = cp, .textord = true } });
}

/// `\char` (KaTeX `macros.js` + `\@char` parity): decimal, `'octal`,
/// `"hex, or `` ` `` plus one token. A control word after the
/// backtick contributes its first name byte (KaTeX reads
/// `charCodeAt(1)` past the backslash); anything but end-of-input is
/// a character, including braces and `^`/`_`/`&` (their source
/// spellings). Astral characters differ deliberately: KaTeX takes
/// the UTF-16 lead unit (`charCodeAt(0)`), this engine the full
/// codepoint — a lone-surrogate MathML text node is never the
/// right answer. Math mode only: `\text` validation rejects
/// multi-letter commands, as for every other math command.
fn parseCharPrimitive(ctx: *ParseCtx, cmd: Tok) Error!Idx {
    var base: u32 = 10;
    var first = try ctx.next();
    if (first.kind == .char and (first.cp == '\'' or first.cp == '"' or first.cp == '`')) {
        if (first.cp == '\'') base = 8 else if (first.cp == '"') base = 16;
        if (first.cp == '`') {
            const bt = try ctx.next();
            const cp: u21 = switch (bt.kind) {
                .char => bt.cp,
                .ctrl => if (bt.name.len > 0) bt.name[0] else return ctx.fail(bt.pos, "\\char` missing argument"),
                .lbrace => '{',
                .rbrace => '}',
                .sup => '^',
                .sub => '_',
                .amp => '&',
                .newline => '\n',
                .param => '#',
                else => return ctx.fail(bt.pos, "\\char` missing argument"),
            };
            return charAtom(ctx, cp);
        }
        first = try ctx.next();
    }
    const d0 = charDigitVal(first, base) orelse {
        if (base == 8) return ctx.fail(first.pos, "invalid base-8 digit");
        if (base == 16) return ctx.fail(first.pos, "invalid base-16 digit");
        return ctx.fail(first.pos, "invalid base-10 digit");
    };
    var num = charAccum(0, base, d0);
    while (true) {
        const q = try ctx.peek();
        const d = charDigitVal(q, base) orelse break;
        _ = try ctx.next();
        num = charAccum(num, base, d);
    }
    // KaTeX funnels through `\@char{<decimal>}`; the range check is
    // its "invalid code point" error.
    if (num > 0x10FFFF) return ctx.fail(cmd.pos, "\\@char with invalid code point");
    return charAtom(ctx, @intCast(num));
}

// ---------------------------------------------------------------------------
// Control-sequence dispatch
// ---------------------------------------------------------------------------

fn parseCtrl(ctx: *ParseCtx, depth: u8, t: Tok) Error!Idx {
    // Single-character names (`\%`, `\,`, `\'`, ...).
    if (t.name.len == 1) return parseSingleCharCtrl(ctx, depth, t);
    const name = t.name;

    if (tokNameEq(name, "frac")) return parseFracLike(ctx, depth, .{ .bar = true });
    // Display fractions wrap in a style node (KaTeX parity: the
    // `mstyle` sits outside the fraction — and outside `\dbinom`'s
    // parentheses — while layout inherits metrics from the ambient).
    if (tokNameEq(name, "dfrac")) return parseStyledFrac(ctx, depth, .D, .{ .bar = true });
    if (tokNameEq(name, "tfrac")) return parseStyledFrac(ctx, depth, .T, .{ .bar = true });
    if (tokNameEq(name, "cfrac")) return parseStyledFrac(ctx, depth, .D, .{ .bar = true });
    if (tokNameEq(name, "binom")) return parseFracLike(ctx, depth, .{ .bar = false, .fence = .parens });
    if (tokNameEq(name, "dbinom")) {
        return parseStyledFrac(ctx, depth, .D, .{ .bar = false, .fence = .parens });
    }
    if (tokNameEq(name, "tbinom")) {
        // KaTeX parity: text-style binomial (the `\dbinom` shape in
        // text style — pinned 0.18.7).
        return parseStyledFrac(ctx, depth, .T, .{ .bar = false, .fence = .parens });
    }
    if (full_only and (tokNameEq(name, "genfrac"))) {
        return parseGenfrac(ctx, depth, t);
    }
    if (tokNameEq(name, "sqrt")) return parseSqrt(ctx, depth);
    if (full_only and (tokNameEq(name, "left"))) {
        return parseLeftRight(ctx, depth, t);
    }
    if (full_only and (tokNameEq(name, "middle"))) {
        // KaTeX parity: the delimiter parses first (a missing one
        // fails there); the fence check reports at the delimiter.
        const dpos = (try ctx.peek()).pos;
        const cp = try parseDelimSpec(ctx);
        if (ctx.in_fence == 0) return ctx.fail(dpos, "'\\middle' outside '\\left'");
        return ctx.allocNode(.{ .middle = .{ .cp = cp } });
    }
    if (tokNameEq(name, "right")) return ctx.fail(t.pos, "unexpected '\\right'");
    if (full_only and (isBigName(name))) {
        return parseBig(ctx, name, t);
    }
    const accent = if (full_only) symbols.lookupAccent(name) else null;
    if (accent) |a| {
        const nuc = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .accent = .{ .cp = a.cp, .wide = a.wide, .nucleus = nuc } });
    }
    const over = if (full_only) parseOverName(name) else null;
    if (over) |kind| {
        return parseOver(ctx, depth, t, kind);
    }
    if (full_only and (tokNameEq(name, "overset") or tokNameEq(name, "underset") or
        tokNameEq(name, "stackrel")))
    {
        // KaTeX parity: `\stackrel` takes the same two arguments
        // as `\overset` but forces Rel (pinned 0.18.7
        // `functions/stacking.ts`: `mclass: "mrel"` — MathML is
        // `<mo><mover><mo>base</mo>top</mover></mo>` regardless of
        // the base class; `stackedOp` takes a force flag).
        const sup = try parseGroupOrAtom(ctx, depth);
        const base = try parseGroupOrAtom(ctx, depth);
        const kind: OverKind = if (tokNameEq(name, "overset")) .overset else if (tokNameEq(name, "underset")) .underset else .stackrel;
        return ctx.allocNode(.{ .over = .{ .kind = kind, .nucleus = base, .extra = sup, .under = NONE } });
    }
    if (full_only and (tokNameEq(name, "not"))) {
        // Bound-operand overlay (KaTeX `\mathrel{\mathrlap\@not}`):
        // binding `base` lets layout center the U+0338 slash on it
        // (an unbound rlap cannot see the sibling width). The Rel
        // class keeps the outer side bearings (`\not =` is as wide
        // as `=`). The MathML renderer folds the slash textually onto
        // the base element.
        const base = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .not = .{ .base = base } });
    }
    if (full_only and (tokNameEq(name, "begin"))) {
        return parseEnv(ctx, depth, t);
    }
    if (tokNameEq(name, "end")) return ctx.fail(t.pos, "unexpected '\\end'");
    if (tokNameEq(name, "endgroup")) return ctx.fail(t.pos, "unexpected '\\endgroup'");
    if (tokNameEq(name, "egroup")) return ctx.fail(t.pos, "unexpected '}'");
    if (tokNameEq(name, "bgroup")) {
        // `{` by another name (KaTeX `\\let\\bgroup={` parity, issue
        // #134 — `t` is already consumed): opens a `.group` frame the
        // formula loop closes on `}` or `\\egroup`, never on
        // `\\endgroup` (strict pairing, like the `.lbrace` arm of
        // `parseSingle`). Both profiles: grouping is core syntax.
        return parseFormula(ctx, depth + 1, .group, null);
    }
    if (full_only and (tokNameEq(name, "begingroup"))) {
        // Scope opener like `{` (KaTeX parity, pinned 0.18.7 — `t`
        // is already consumed), but the frame closes only on
        // `\\endgroup` (strict pairing — see the formula-loop arms).
        return parseFormula(ctx, depth + 1, .begingroup, null);
    }
    // Rule commands only open rows (consumed by the environment row
    // loop, KaTeX `getHLines` parity); anywhere else they are
    // misplaced (KaTeX parity messages, issue #33).
    if (tokNameEq(name, "hline")) return ctx.fail(t.pos, "\\hline valid only within array environment");
    if (tokNameEq(name, "hdashline")) return ctx.fail(t.pos, "\\hdashline valid only within array environment");
    if (tokNameEq(name, "cr")) return ctx.fail(t.pos, "unexpected '\\cr'");
    if (tokNameEq(name, "text")) {
        const toks = try parseBracedToks(ctx, t, true);
        return parseTextBody(ctx, depth, toks, .rm);
    }
    if (tokNameEq(name, "hbox")) {
        // KaTeX parity: `\hbox` takes an hbox argument like `\text`
        // (bare atoms accepted — pinned 0.18.7), but `\mbox` is
        // undefined in the bundle (math and text mode alike), so it
        // stays out (table `unsup`, `rej-unsup-mbox`).
        const toks = try parseBracedToks(ctx, t, false);
        return parseTextBody(ctx, depth, toks, .rm);
    }
    if (textFontFamFor(name)) |fam| {
        const toks = try parseBracedToks(ctx, t, true);
        return parseTextBody(ctx, depth, toks, fam);
    }
    if (fontFamFor(name)) |fam| {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .font = .{ .fam = fam, .body = body } });
    }
    if (tokNameEq(name, "boldsymbol")) {
        // `\boldsymbol` IS `\bm` (issue #94, pinned 0.18.7:
        // bold-italic letters, bold digits — probed identical on
        // letters, digits, Greek, and symbols alike).
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .font = .{ .fam = .bolditalic, .body = body } });
    }
    if (tokNameEq(name, "pmb")) {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .pmb = .{ .body = body } });
    }
    if (full_only and (tokNameEq(name, "vcenter"))) {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .vcenter = .{ .body = body } });
    }
    if (full_only and (tokNameEq(name, "mathinner") or tokNameEq(name, "mathop") or tokNameEq(name, "mathrel") or tokNameEq(name, "mathpunct") or tokNameEq(name, "mathbin") or tokNameEq(name, "mathclose") or tokNameEq(name, "mathopen") or tokNameEq(name, "mathord"))) {
        const body = try parseGroupOrAtom(ctx, depth);
        const class: symbols.AtomClass = if (tokNameEq(name, "mathop")) .Op else if (tokNameEq(name, "mathrel")) .Rel else if (tokNameEq(name, "mathpunct")) .Punct else if (tokNameEq(name, "mathbin")) .Bin else if (tokNameEq(name, "mathclose")) .Close else if (tokNameEq(name, "mathopen")) .Open else if (tokNameEq(name, "mathord")) .Ord else .Inner;
        return ctx.allocNode(.{ .classwrap = .{ .class = class, .body = body, .limits = .auto } });
    }
    if (full_only and (tokNameEq(name, "colon"))) {
        // KaTeX macro parity (macros.ts): `\colon` =
        // `\nobreak\mskip2mu\mathpunct{}\mathchoice{\mkern-3mu}{\mkern-3mu}{}{}{:}\mskip6mu\relax`.
        // Built directly (the `\mod` precedent — no builtin-macro
        // table exists): the trail is 6mu glue (`.space`), never
        // `.nbsp`, and both `\mathchoice` text branches are `-3mu`.
        const nobrk = try ctx.allocNode(.{ .space = 0 });
        const lead = try ctx.allocNode(.{ .space = space_2mu });
        const empty = try ctx.allocNode(.{ .group = .{ .start = 0, .len = 0 } });
        const punct = try ctx.allocNode(.{ .classwrap = .{ .class = .Punct, .body = empty, .limits = .auto } });
        const neg = try ctx.allocNode(.{ .space = -space_thin });
        const choice = try ctx.allocNode(.{ .mathchoice = .{ neg, neg, empty, empty } });
        const mark = try ctx.allocNode(.{ .atom = .{ .class = .Rel, .font = .rm, .cp = ':' } });
        const core = try finishGroup(ctx, &.{mark});
        const trail = try ctx.allocNode(.{ .space = space_6mu });
        return finishGroup(ctx, &.{ nobrk, lead, punct, choice, core, trail });
    }
    if (full_only and (tokNameEq(name, "ordinarycolon"))) {
        // KaTeX macro parity: `\ordinarycolon` = `:`.
        try ctx.push(.{ .kind = .char, .cp = ':', .pos = t.pos, .synth = true });
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "vcentcolon") or tokNameEq(name, "ratio"))) {
        // KaTeX macro parity: `\vcentcolon` =
        // `\mathrel{\mathop\ordinarycolon}` (vertical centering is
        // HTML-side; the MathML shape is the triple-`mo` nesting the
        // reparse produces). `\ratio` is the colonequals.sty alias.
        try pushExpansion(ctx, t, "\\mathrel{\\mathop\\ordinarycolon}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "html@mathml"))) {
        // KaTeX internal (mathtools alternates): the HTML branch
        // builds the HTML tree, the MathML branch the MathML tree.
        // Both parse (error parity — a broken HTML branch still
        // rejects); layout walks the visual branch like KaTeX, the
        // MathML emitter the `math` one. The node is opaque to
        // character-box retyping, so an outer `\mathbin` wraps
        // instead of retyping (`\minuso` → `<mo><mi>⦵</mi></mo>`,
        // pinned 0.18.7).
        const html_branch = try parseGroupOrAtom(ctx, depth);
        const mathml_branch = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .htmlmathml = .{ .html = html_branch, .math = mathml_branch } });
    }
    if (full_only and (tokNameEq(name, "char"))) {
        return parseCharPrimitive(ctx, t);
    }
    if (full_only and (tokNameEq(name, "@char"))) {
        // KaTeX internal (`\@char{65}`, produced by the `\char`
        // macro): grouped-or-single decimal digits (spaces skipped)
        // → textord. Anything else is "non-numeric"; above U+10FFFF
        // is an invalid code point.
        const pk = try ctx.peek();
        const r = try parseBracedToks(ctx, t, false);
        const apos = if (pk.kind == .lbrace) pk.pos else ctx.toks[r.start].pos;
        var num: u64 = 0;
        var digits = false;
        var i: u16 = 0;
        while (i < r.len) : (i += 1) {
            const tk = ctx.toks[r.start + i];
            if (tk.kind == .char and tk.cp == ' ') continue;
            if (tk.kind != .char or tk.cp < '0' or tk.cp > '9')
                return ctx.fail(apos, "\\@char has non-numeric argument");
            digits = true;
            num = charAccum(num, 10, tk.cp - '0');
        }
        if (!digits) return ctx.fail(apos, "\\@char has non-numeric argument");
        if (num > 0x10FFFF) return ctx.fail(apos, "\\@char with invalid code point");
        return charAtom(ctx, @intCast(num));
    }
    if (full_only and (tokNameEq(name, "dblcolon") or tokNameEq(name, "coloncolon"))) {
        // KaTeX mathtools parity: `\dblcolon` =
        // `\html@mathml{\mathrel{\vcentcolon\mathrel{\mkern-.9mu}\vcentcolon}}{\mathop{\char"2237}}`.
        // `\coloncolon` is the colonequals.sty alias.
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-.9mu}\\vcentcolon}}{\\mathop{\\char\"2237}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "coloneqq") or tokNameEq(name, "colonequals"))) {
        // KaTeX mathtools parity: `\coloneqq` =
        // `\html@mathml{\mathrel{\vcentcolon\mathrel{\mkern-1.2mu}=}}{\mathop{\char"2254}}`.
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}=}}{\\mathop{\\char\"2254}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Coloneqq") or tokNameEq(name, "coloncolonequals"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}=}}{\\mathop{\\char\"2237\\char\"3d}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "coloneq") or tokNameEq(name, "colonminus"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}\\mathrel{-}}}{\\mathop{\\char\"3a\\char\"2212}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Coloneq") or tokNameEq(name, "coloncolonminus"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}\\mathrel{-}}}{\\mathop{\\char\"2237\\char\"2212}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "eqqcolon") or tokNameEq(name, "equalscolon"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{=\\mathrel{\\mkern-1.2mu}\\vcentcolon}}{\\mathop{\\char\"2255}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Eqqcolon") or tokNameEq(name, "equalscoloncolon"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{=\\mathrel{\\mkern-1.2mu}\\dblcolon}}{\\mathop{\\char\"3d\\char\"2237}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "eqcolon") or tokNameEq(name, "minuscolon"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\mathrel{-}\\mathrel{\\mkern-1.2mu}\\vcentcolon}}{\\mathop{\\char\"2239}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Eqcolon") or tokNameEq(name, "minuscoloncolon"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\mathrel{-}\\mathrel{\\mkern-1.2mu}\\dblcolon}}{\\mathop{\\char\"2212\\char\"2237}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "colonapprox"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}\\approx}}{\\mathop{\\char\"3a\\char\"2248}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "simcolon"))) {
        // colonequals.sty (no `\html@mathml` alternate upstream):
        // `\mathrel{\sim\mathrel{\mkern-1.2mu}\vcentcolon}`.
        try pushExpansion(ctx, t, "\\mathrel{\\sim\\mathrel{\\mkern-1.2mu}\\vcentcolon}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "approxcolon"))) {
        // colonequals.sty (no `\html@mathml` alternate upstream):
        // `\mathrel{\approx\mathrel{\mkern-1.2mu}\vcentcolon}`.
        try pushExpansion(ctx, t, "\\mathrel{\\approx\\mathrel{\\mkern-1.2mu}\\vcentcolon}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Colonapprox") or tokNameEq(name, "coloncolonapprox"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}\\approx}}{\\mathop{\\char\"2237\\char\"2248}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "colonsim"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}\\sim}}{\\mathop{\\char\"3a\\char\"223c}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Colonsim") or tokNameEq(name, "coloncolonsim"))) {
        try pushExpansion(ctx, t, "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}\\sim}}{\\mathop{\\char\"2237\\char\"223c}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "simcoloncolon"))) {
        // No `\html@mathml` alternate upstream: the kerned pair is
        // the MathML tree.
        try pushExpansion(ctx, t, "\\mathrel{\\sim\\mathrel{\\mkern-1.2mu}\\dblcolon}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "approxcoloncolon"))) {
        try pushExpansion(ctx, t, "\\mathrel{\\approx\\mathrel{\\mkern-1.2mu}\\dblcolon}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "nleqq") or tokNameEq(name, "nleqslant") or tokNameEq(name, "ngeqq") or tokNameEq(name, "ngeqslant"))) {
        // KaTeX parity (pinned 0.18.7 `macros.js`): negated relations
        // render AMS PUA precomposed glyphs in HTML (`\@nleqq` =
        // U+E011, ...) while MathML carries the single precomposed
        // codepoint (issue #73 arbiter, #96 shapes). The math branch
        // reuses the alias static (`\nleq` = U+2270), so MathML is
        // byte-identical to the old static path.
        const html_at: []const u8 = if (tokNameEq(name, "nleqq")) "\\@nleqq" else if (tokNameEq(name, "nleqslant")) "\\@nleqslant" else if (tokNameEq(name, "ngeqq")) "\\@ngeqq" else "\\@ngeqslant";
        const math_alias: []const u8 = if (t.name[1] == 'l') "\\nleq" else "\\ngeq";
        var tpl: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&tpl, "\\html@mathml{{{s}}}{{{s}}}", .{ html_at, math_alias }) catch return error.NoSpace;
        try pushExpansion(ctx, t, text);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "lvertneqq") or tokNameEq(name, "gvertneqq"))) {
        // Same dual-branch shape as above (issue #96).
        const html_at: []const u8 = if (tokNameEq(name, "lvertneqq")) "\\@lvertneqq" else "\\@gvertneqq";
        const math_alias: []const u8 = if (tokNameEq(name, "lvertneqq")) "\\lneqq" else "\\gneqq";
        var tpl: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&tpl, "\\html@mathml{{{s}}}{{{s}}}", .{ html_at, math_alias }) catch return error.NoSpace;
        try pushExpansion(ctx, t, text);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "nshortmid") or tokNameEq(name, "nshortparallel") or tokNameEq(name, "nsubseteqq") or tokNameEq(name, "nsupseteqq"))) {
        // Same dual-branch shape as above (issue #96).
        const html_at: []const u8 = if (tokNameEq(name, "nshortmid")) "\\@nshortmid" else if (tokNameEq(name, "nshortparallel")) "\\@nshortparallel" else if (tokNameEq(name, "nsubseteqq")) "\\@nsubseteqq" else "\\@nsupseteqq";
        const math_alias: []const u8 = if (tokNameEq(name, "nshortmid")) "\\nmid" else if (tokNameEq(name, "nshortparallel")) "\\nparallel" else if (tokNameEq(name, "nsubseteqq")) "\\nsubseteq" else "\\nsupseteq";
        var tpl: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&tpl, "\\html@mathml{{{s}}}{{{s}}}", .{ html_at, math_alias }) catch return error.NoSpace;
        try pushExpansion(ctx, t, text);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "varsubsetneq") or tokNameEq(name, "varsubsetneqq") or tokNameEq(name, "varsupsetneq") or tokNameEq(name, "varsupsetneqq"))) {
        // Same dual-branch shape as above (issue #96).
        const html_at: []const u8 = if (tokNameEq(name, "varsubsetneq")) "\\@varsubsetneq" else if (tokNameEq(name, "varsubsetneqq")) "\\@varsubsetneqq" else if (tokNameEq(name, "varsupsetneq")) "\\@varsupsetneq" else "\\@varsupsetneqq";
        const math_alias: []const u8 = if (tokNameEq(name, "varsubsetneq")) "\\subsetneq" else if (tokNameEq(name, "varsubsetneqq")) "\\subsetneqq" else if (tokNameEq(name, "varsupsetneq")) "\\supsetneq" else "\\supsetneqq";
        var tpl: [80]u8 = undefined;
        const text = std.fmt.bufPrint(&tpl, "\\html@mathml{{{s}}}{{{s}}}", .{ html_at, math_alias }) catch return error.NoSpace;
        try pushExpansion(ctx, t, text);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "rq"))) {
        // KaTeX macro parity: `\rq` = `'` (a prime: empty-base
        // `^{\prime}` at row start, superscript after a base — the
        // pushed char runs the exact `'` path, pinned 0.18.7).
        try ctx.push(.{ .kind = .char, .cp = '\'', .pos = t.pos, .synth = true });
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "lBrace"))) {
        // KaTeX parity: `\lBrace` =
        // `\html@mathml{\mathopen{\{\mkern-3.2mu[}}{\mathopen{\char`⦃}}`.
        try pushExpansion(ctx, t, "\\html@mathml{\\mathopen{\\{\\mkern-3.2mu[}}{\\mathopen{\\char`⦃}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "rBrace"))) {
        // KaTeX parity: `\rBrace` =
        // `\html@mathml{\mathclose{]\mkern-3.2mu\}}}{\mathclose{\char`⦄}}`.
        try pushExpansion(ctx, t, "\\html@mathml{\\mathclose{]\\mkern-3.2mu\\}}}{\\mathclose{\\char`⦄}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "minuso"))) {
        // KaTeX parity: `\minuso` is the `macros.ts` template
        // verbatim (pinned 0.18.7) — like `\Colon`, built by true
        // token expansion (nested `\mathbin`, `\mathrlap`,
        // `\mathchoice`, `\circ`, `\char` run their own handlers),
        // so the pools see the same load as hand-written input and
        // no macro table exists anywhere. The MathML branch
        // carries the glyph directly (`{\char`⦵}`), so MathML is
        // `<mo><mi>⦵</mi></mo>` while layout walks the visual
        // branch like KaTeX.
        try pushExpansion(ctx, t, "\\mathbin{\\html@mathml{{\\mathrlap{\\mathchoice{\\kern{0.145em}}{\\kern{0.145em}}{\\kern{0.1015em}}{\\kern{0.0725em}}\\circ}{-}}}{\\char`⦵}}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "angln"))) {
        // KaTeX macro parity: `\angln` = `{\angl n}`.
        try pushExpansion(ctx, t, "{\\angl n}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "xcancel"))) {
        // KaTeX parity: `\xcancel` strikes both diagonals (unlike
        // `\cancel`/`\bcancel`, which strike one).
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .xcancel = body });
    }
    if (full_only and (tokNameEq(name, "copyright"))) {
        // KaTeX macro parity (macros.ts): `\copyright` =
        // `\TextOrMath{\textcopyright}{\text{\textcopyright}}` with
        // `\textcopyright` = `\html@mathml{\textcircled{c}}{\char`©}`
        // — observably `<mtext>©</mtext>`, built directly (the
        // `\colon` precedent): the `\text`-mode macro chain belongs
        // to the text batch, and renders these same tokens.
        return textLit(ctx, t.pos, "©");
    }
    if (full_only and (tokNameEq(name, "textcopyright"))) {
        // KaTeX parity (`macros.ts`, issue #132): `\textcopyright` =
        // `\html@mathml{\textcircled{c}}{\char`©}` — observably the
        // `\char` textord in MathML (`<mi mathvariant="normal">©</mi>`,
        // pinned 0.18.7 probe), exactly what `charAtom` builds (the
        // `\char` test pins the shape). Text mode resolves through
        // the `text_cmds` table instead (same codepoint, mtext).
        return charAtom(ctx, 0x00A9);
    }
    if (full_only and (tokNameEq(name, "verb"))) {
        return parseVerb(ctx, t);
    }
    if (full_only and (tokNameEq(name, "color") or tokNameEq(name, "textcolor"))) {
        const spec = try captureColorSpec(ctx);
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .color = .{ .body = body, .spec = spec } });
    }
    if (full_only and (tokNameEq(name, "colorbox") or tokNameEq(name, "fcolorbox"))) {
        // `\fcolorbox{frame}{background}{body}`; `\colorbox` omits frame.
        var frame: Range = .{ .start = 0, .len = 0 };
        if (tokNameEq(name, "fcolorbox")) frame = try captureColorSpec(ctx);
        const bg = try captureColorSpec(ctx);
        const raw = try parseBracedToks(ctx, t, true);
        const toks = try selectBranchToks(ctx, raw, false);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .colorbox = .{ .body = toks, .bg = bg, .frame = frame } });
    }
    if (full_only and (tokNameEq(name, "href"))) {
        const target = try ctx.captureArg();
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .href = .{ .body = body, .target = target } });
    }
    if (full_only and (tokNameEq(name, "url"))) {
        const raw = try captureSpacedArg(ctx);
        // Math flavor: `\\url` arguments expand in math mode in KaTeX
        // (pinned `\\TextOrMath` probe), even though the capture
        // validates as text afterwards.
        const toks = try selectBranchToks(ctx, raw, true);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .tt } });
    }
    if (full_only and (tokNameEq(name, "includegraphics"))) {
        // KaTeX `functions/includegraphics.ts` (pinned 0.18.7): an
        // optional `[raw]` key=value list (`alt`, `width`,
        // `height`, `totalheight`) plus a required `{url}` source,
        // built only under trust. Trust has no engine counterpart
        // (the `\href` precedent): the command always builds.
        var opt = GraphicsOpt{
            .w = 0,
            .h = graphics_default_h,
            .th = 0,
            .alt = .{ .start = 0, .len = 0 },
        };
        const pk = try ctx.peek();
        if (pk.kind == .char and pk.cp == '[') {
            _ = try ctx.next();
            const r = try scanBracketArg(ctx);
            opt = try parseGraphicsOpts(ctx, r, t.pos);
        }
        const src = try scanUrlArg(ctx);
        return ctx.allocNode(.{ .graphics = .{
            .src = src,
            .alt = opt.alt,
            .w = opt.w,
            .h = opt.h,
            .th = opt.th,
        } });
    }
    if (full_only and (tokNameEq(name, "htmlClass") or tokNameEq(name, "htmlId") or
        tokNameEq(name, "htmlStyle") or tokNameEq(name, "htmlData")))
    {
        _ = try ctx.captureArg();
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .htmlwrap = body });
    }
    if (full_only and (tokNameEq(name, "operatorname") or tokNameEq(name, "operatornamewithlimits"))) {
        // `\operatornamewithlimits` is the legacy alias of the star
        // form (KaTeX parity): both stack display scripts.
        var limits: LimitsMode = if (tokNameEq(name, "operatornamewithlimits")) .on else .off;
        const pk = try ctx.peek();
        if (pk.kind == .char and pk.cp == '*') {
            _ = try ctx.next();
            limits = .on;
        }
        const raw = try ctx.captureArg();
        // Math flavor: `\\operatorname` arguments parse in math mode
        // in KaTeX (it is a macro over `\\operatorname@`; pinned
        // `\\TextOrMath` probe), even though the capture validates as
        // text afterwards.
        const toks = try selectBranchToks(ctx, raw, true);
        try checkTextToks(ctx, toks);
        return ctx.allocNode(.{ .opname = .{ .toks = toks, .limits = limits } });
    }
    if (full_only and (tokNameEq(name, "dotsi"))) {
        // KaTeX macro parity: `\dotsi` = `\,\cdots` (negative thin
        // space + centered dots, for integrals).
        const sp = try ctx.allocNode(.{ .space = -space_thin });
        const dots = try ctx.allocNode(.{ .atom = .{ .class = .Inner, .font = .rm, .cp = 0x22EF } });
        return finishGroup(ctx, &.{ sp, dots });
    }
    if (full_only and (tokNameEq(name, "mod"))) {
        // KaTeX macro parity: `\mod` = style-choice leading space
        // (18mu display, 12mu otherwise) + upright "mod" + thin space
        // + argument. `\allowbreak` has no engine counterpart (no line
        // breaking) and is skipped. 1mu = 1000/18 em thousandths.
        const s18 = try ctx.allocNode(.{ .space = 1000 });
        const s12 = try ctx.allocNode(.{ .space = 667 });
        const choice = try ctx.allocNode(.{ .mathchoice = .{ s18, s12, s12, s12 } });
        const m = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 'm' } });
        const o = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 'o' } });
        const d = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 'd' } });
        const thin = try ctx.allocNode(.{ .space = space_thin });
        const arg = try parseGroupOrAtom(ctx, depth);
        return finishGroup(ctx, &.{ choice, m, o, d, thin, arg });
    }
    if (full_only and (tokNameEq(name, "bmod"))) {
        // KaTeX macro parity (`macros.js`, pinned 0.18.7):
        // `\bmod` = `\mathchoice{\mskip1mu}{\mskip1mu}{\mskip5mu}{\mskip5mu}`
        // (`mtext` hair-kern, never `mspace` — `SpaceNode`) +
        // `\mathbin{\rm mod}` + the same kern, via true token
        // expansion (the `\minuso` precedent): the pieces parse as
        // enclosing-row siblings — flat, never a `.group` shell —
        // exactly as hand-written input would. `\mathrm{mod}` is
        // our engine's spelling of KaTeX's `{\rm mod}` declaration
        // (`\rm` takes one atom here, so the declaration form would
        // leak `od` out of the `\mathbin` upright).
        try pushExpansion(ctx, t, "\\mathchoice{\\mskip1mu}{\\mskip1mu}{\\mskip5mu}{\\mskip5mu}\\mathbin{\\mathrm{mod}}\\mathchoice{\\mskip1mu}{\\mskip1mu}{\\mskip5mu}{\\mskip5mu}");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "pod"))) {
        // KaTeX macro parity (`macros.js`, pinned 0.18.7):
        // `\pod{#1}` = `\allowbreak` (a bare zero `mspace`) +
        // style-choice space (18mu display, 8mu otherwise) + `(#1)`,
        // via token expansion with the captured argument spliced
        // between prefix and suffix (flat siblings, no shell).
        const arg = try parseBracedToks(ctx, t, false);
        try pushExpansionArg(ctx, t, "\\allowbreak\\mathchoice{\\mkern18mu}{\\mkern8mu}{\\mkern8mu}{\\mkern8mu}(", arg, ")");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "pmod"))) {
        // KaTeX macro parity (`macros.js`, pinned 0.18.7):
        // `\pmod{#1}` = `\pod` of `{\rm mod}` + 6mu kern + the
        // argument, via token expansion (flat siblings, no shell).
        // `\mathrm{mod}` spells the `{\rm mod}` declaration (the
        // `\bmod` note above).
        const arg = try parseBracedToks(ctx, t, false);
        try pushExpansionArg(ctx, t, "\\allowbreak\\mathchoice{\\mkern18mu}{\\mkern8mu}{\\mkern8mu}{\\mkern8mu}({\\mathrm{mod}}\\mkern6mu", arg, ")");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "set"))) {
        // KaTeX macro parity (`macros.js` `\bra@set`, pinned
        // 0.18.7): `\{\,#1\,\}` with the body split at the first
        // top-level `|` into `\mid`-joined halves (`\set{x|y}`).
        // Later pipes stay literal (pinned bundle). Braced or bare
        // argument alike.
        const arg = try parseBracedToks(ctx, t, false);
        try pushBarSplit(ctx, t, arg, "\\{\\,", "\\mid", "\\mid", "\\,\\}", true, false);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Set"))) {
        // KaTeX macro parity (`macros.js` `\bra@set`, pinned
        // 0.18.7): `\Set` = `\left\{\:` + body + `\:\right\}`
        // with the FIRST top-level bar replaced — `|` becomes
        // `\;\middle\vert\;`, `\|` (or `||`) becomes
        // `\;\middle\Vert\;` — and later bars stay literal.
        const arg = try parseBracedToks(ctx, t, false);
        try pushBarSplit(ctx, t, arg, "\\left\\{\\:", "\\;\\middle\\vert\\;", "\\;\\middle\\Vert\\;", "\\:\\right\\}", true, true);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "Braket"))) {
        // KaTeX macro parity (`macros.js` `\bra@ket`, pinned
        // 0.18.7): `\Braket` = `\left\langle` + body +
        // `\right\rangle` with EVERY top-level bar replaced by
        // `\,\middle\vert\,` (`\|` and `||` fold to the same).
        const arg = try parseBracedToks(ctx, t, false);
        try pushBarSplit(ctx, t, arg, "\\left\\langle", "\\,\\middle\\vert\\,", "\\,\\middle\\vert\\,", "\\right\\rangle", false, true);
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "braket"))) {
        // KaTeX macro parity (`macros.js`, pinned 0.18.7):
        // `\braket{#1}` = `\mathinner{\langle{#1}\rangle}` — one
        // argument, no bar splitting (a `|` stays literal).
        const arg = try parseBracedToks(ctx, t, false);
        try pushTemplateToks(ctx, t, "}\\rangle}");
        try pushRangeClean(ctx, arg, 0, arg.len);
        try pushTemplateToks(ctx, t, "\\mathinner{\\langle{");
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "varinjlim") or tokNameEq(name, "varprojlim") or
        tokNameEq(name, "varliminf") or tokNameEq(name, "varlimsup")))
    {
        // KaTeX macro parity (`macros.js`, pinned 0.18.7):
        // `\varinjlim` = `\DOTSB\operatorname*{\underrightarrow{lim}}`
        // (left arrow, underline, overline for the siblings).
        // `\DOTSB` only steers a following `\dots` (no MathML
        // trace), so just the operatorname remains — built directly
        // because `.opname` holds raw text tokens, never a parsed
        // under/over body.
        const kind: OverKind = if (tokNameEq(name, "varinjlim"))
            .underright
        else if (tokNameEq(name, "varprojlim"))
            .underleft
        else if (tokNameEq(name, "varliminf"))
            .underline
        else
            .overline;
        const l = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 'l' } });
        const ii = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 'i' } });
        const mm = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 'm' } });
        const nuc = try finishGroup(ctx, &.{ l, ii, mm });
        const body = try ctx.allocNode(.{ .over = .{ .kind = kind, .nucleus = nuc, .extra = NONE, .under = NONE } });
        return ctx.allocNode(.{ .varlim = .{ .body = body } });
    }
    if (full_only and (tokNameEq(name, "reflectbox"))) {
        // KaTeX parity (pinned 0.18.7, issue #97): `\reflectbox`
        // takes an hbox argument — the same `parseTextBody` path as
        // `\hbox`, so `$...$` math islands work — under a textstyle
        // reset. The `.reflect` marker mirrors the ink about the box
        // center at layout (KaTeX's CSS flip); MathML stays the
        // plain content, as does KaTeX's.
        const toks = try parseBracedToks(ctx, t, false);
        const inner = try parseTextBody(ctx, depth, toks, .rm);
        const body = try ctx.allocNode(.{ .reflect = .{ .math = false, .body = inner } });
        return ctx.allocNode(.{ .style = .{ .style = .T, .body = body } });
    }
    if (full_only and (tokNameEq(name, "mathreflectbox"))) {
        // KaTeX parity (pinned 0.18.7, issue #97): `\mathreflectbox`
        // takes math content; same `.reflect` mirror marker as
        // `\reflectbox` above, plain-content MathML like KaTeX's.
        const inner = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .reflect = .{ .math = true, .body = inner } });
    }
    if (full_only and (tokNameEq(name, "KaTeX") or tokNameEq(name, "LaTeX") or tokNameEq(name, "TeX"))) {
        // Logo macros (KaTeX 0.18.7 `macros.js`, all `\textrm` +
        // `\html@mathml{<html>}{<name>}`): the html branch below is
        // the kerned visual composition (upright letters, the
        // top-aligned scriptsize A raised by T_h - 0.7*A_h =
        // 0.206667em, E lowered by 0.5ex; widths in thousandths of an
        // em), which layout renders. The math branch (plain name as
        // text) is what the MathML emitter renders.
        const mkLetter = struct {
            fn mk(c: *ParseCtx, cp: u21) Error!Idx {
                return c.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = cp } });
            }
        }.mk;
        const mkKern = struct {
            fn mk(c: *ParseCtx, w: i16) Error!Idx {
                return c.allocNode(.{ .space = w });
            }
        }.mk;
        const a_glyph = try mkLetter(ctx, 'A');
        const raised_a = try ctx.allocNode(.{ .raisebox = .{
            .body = try ctx.allocNode(.{ .style = .{ .style = .S, .body = a_glyph } }),
            .dh = 207,
        } });
        const lowered_e = try ctx.allocNode(.{ .raisebox = .{
            .body = try mkLetter(ctx, 'E'),
            .dh = -238,
        } });
        // The `\TeX` tail shared by all three logos.
        const tex_tail = [_]Idx{
            try mkLetter(ctx, 'T'),
            try mkKern(ctx, -167),
            lowered_e,
            try mkKern(ctx, -125),
            try mkLetter(ctx, 'X'),
        };
        const is_tex = tokNameEq(name, "TeX");
        const is_katex = tokNameEq(name, "KaTeX");
        const html = if (is_tex)
            try finishGroup(ctx, &tex_tail)
        else blk: {
            const head = [_]Idx{
                try mkLetter(ctx, if (is_katex) 'K' else 'L'),
                try mkKern(ctx, if (is_katex) -170 else -360),
                raised_a,
                try mkKern(ctx, -150),
            };
            var kids: [head.len + tex_tail.len]Idx = undefined;
            @memcpy(kids[0..head.len], &head);
            @memcpy(kids[head.len..], &tex_tail);
            break :blk try finishGroup(ctx, &kids);
        };
        const math = try textLit(ctx, t.pos, if (is_tex) "TeX" else if (is_katex) "KaTeX" else "LaTeX");
        return ctx.allocNode(.{ .htmlmathml = .{ .html = html, .math = math } });
    }
    if (full_only and (tokNameEq(name, "substack"))) {
        return parseSubstack(ctx, depth, t);
    }
    if (full_only and (tokNameEq(name, "mathchoice"))) {
        var c: [4]Idx = undefined;
        c[0] = try parseGroupOrAtom(ctx, depth);
        c[1] = try parseGroupOrAtom(ctx, depth);
        c[2] = try parseGroupOrAtom(ctx, depth);
        c[3] = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .mathchoice = c });
    }
    if (full_only and (tokNameEq(name, "smash"))) {
        return parseSmash(ctx, depth);
    }
    if (full_only and (tokNameEq(name, "raisebox"))) {
        const dh = try parseDimenArg(ctx, t);
        // KaTeX parity: the body is an hbox (text mode), not math —
        // math commands inside are rejected, as in `\text`.
        const raw = try parseBracedToks(ctx, t, false);
        const toks = try selectBranchToks(ctx, raw, false);
        try checkTextToks(ctx, toks);
        const body = try ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
        return ctx.allocNode(.{ .raisebox = .{ .body = body, .dh = dh } });
    }
    if (full_only and (tokNameEq(name, "rule"))) {
        return parseRule(ctx, depth);
    }
    if (full_only and (tokNameEq(name, "boxed"))) {
        const math = try parseGroupOrAtom(ctx, depth);
        // KaTeX desugars `\boxed{X}` to `\fbox{$\displaystyle{X}$}`;
        // the displaystyle is real (layout-affecting), so it becomes
        // a style node.
        const disp = try ctx.allocNode(.{ .style = .{ .style = .D, .body = math } });
        return ctx.allocNode(.{ .boxed = disp });
    }
    if (full_only and (tokNameEq(name, "fbox"))) {
        // KaTeX `enclose` takes an hbox here (text mode): math
        // commands inside are rejected, as in `\text` (the raisebox
        // precedent — never math, contra the old math-body shape).
        const raw = try parseBracedToks(ctx, t, true);
        const toks = try selectBranchToks(ctx, raw, false);
        try checkTextToks(ctx, toks);
        const body = try ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
        return ctx.allocNode(.{ .fbox = body });
    }
    if (full_only and (tokNameEq(name, "phantom") or tokNameEq(name, "hphantom") or tokNameEq(name, "vphantom"))) {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .phantom = .{
            .body = body,
            // `\phantom` keeps both axes; `\hphantom` width only;
            // `\vphantom` height/depth only.
            .keep_h = !tokNameEq(name, "vphantom"),
            .keep_v = !tokNameEq(name, "hphantom"),
        } });
    }
    if (full_only and (tokNameEq(name, "bra") or tokNameEq(name, "ket") or
        tokNameEq(name, "Bra") or tokNameEq(name, "Ket")))
    {
        // Bra-ket notation (KaTeX 0.18.7): lowercase forms use
        // fixed-size fences in an Inner atom (`\bra{X}` = ⟨X∣);
        // capitals auto-size exactly like `\left\langle X \right\vert`
        // (byte-identical KaTeX output), so they desugar to fence nodes.
        const body = try parseGroupOrAtom(ctx, depth);
        const big = name[0] < 'a';
        const is_bra = name[1] == 'r';
        const fence: u21 = 0x27E8;
        const bar: u21 = 0x2223;
        if (!big) {
            const kids = [_]Idx{
                try ctx.allocNode(.{ .atom = .{
                    .class = if (is_bra) .Open else .Ord,
                    .font = .rm,
                    .cp = if (is_bra) fence else bar,
                } }),
                body,
                try ctx.allocNode(.{ .atom = .{
                    .class = if (is_bra) .Ord else .Close,
                    .font = .rm,
                    .cp = if (is_bra) bar else 0x27E9,
                } }),
            };
            const group = try finishGroup(ctx, &kids);
            return ctx.allocNode(.{ .classwrap = .{ .class = .Inner, .body = group, .limits = .auto } });
        }
        return ctx.allocNode(.{ .delim = .{
            .left = if (is_bra) fence else bar,
            .right = if (is_bra) bar else 0x27E9,
            .body = body,
        } });
    }
    if (full_only and (tokNameEq(name, "mathstrut"))) {
        // KaTeX parity: `\mathstrut` renders exactly like
        // `\vphantom{(}` (verified against pinned 0.18.7 output).
        const body = try ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '(' } });
        return ctx.allocNode(.{ .phantom = .{ .body = body, .keep_h = false, .keep_v = true } });
    }
    if (full_only and (tokNameEq(name, "llap") or tokNameEq(name, "rlap") or tokNameEq(name, "clap") or
        tokNameEq(name, "mathllap") or tokNameEq(name, "mathrlap") or tokNameEq(name, "mathclap")))
    {
        const math_body = tokNameEq(name, "mathllap") or tokNameEq(name, "mathrlap") or tokNameEq(name, "mathclap");
        // KaTeX parity: `\llap` and friends render contents in text
        // mode (`\mathllap{\textrm{#1}}`); only the `math*` primitives
        // take math bodies.
        const body = if (math_body)
            try parseGroupOrAtom(ctx, depth)
        else blk: {
            const raw = try parseBracedToks(ctx, t, false);
            const toks = try selectBranchToks(ctx, raw, false);
            try checkTextToks(ctx, toks);
            break :blk try ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
        };
        const kind: LapKind =
            if (tokNameEq(name, "llap") or tokNameEq(name, "mathllap")) .llap
            else if (tokNameEq(name, "rlap") or tokNameEq(name, "mathrlap")) .rlap
            else .clap;
        return ctx.allocNode(.{ .lap = .{ .body = body, .kind = kind } });
    }
    if (full_only and (tokNameEq(name, "cancel") or tokNameEq(name, "bcancel"))) {
        const body = try parseGroupOrAtom(ctx, depth);
        // Issue #107: `\bcancel` strikes the other diagonal — it needs
        // its own direction (it used to alias `.cancel`, so MathML and
        // texser both said `\cancel` for it).
        return ctx.allocNode(.{ .cancel = .{ .body = body, .down = tokNameEq(name, "bcancel") } });
    }
    if (full_only and (tokNameEq(name, "iff") or tokNameEq(name, "implies") or tokNameEq(name, "impliedby"))) {
        // KaTeX macro parity (macros.ts): `\\iff` expands to
        // `\\DOTSB\\;⟺\\;` (single arrows for `\\implies`/
        // `\\impliedby`); `\\DOTSB` only steers a following `\\dots`
        // (no MathML trace). True token-level expansion — the pushed
        // `\\;` and arrow parse as siblings in the ENCLOSING row, so
        // no group node (and its spurious `mrow`) ever exists. The
        // middles are the real `\\Long…` symbols (already Rel atoms),
        // so user redefinitions of those apply exactly as in KaTeX.
        // Pushed last-first (LIFO): lead `\\;` pops first and its node
        // is this call's single return; the rest follow as siblings.
        const mid: []const u8 = if (tokNameEq(name, "implies")) "Longrightarrow" else if (tokNameEq(name, "impliedby")) "Longleftarrow" else "Longleftrightarrow";
        try ctx.push(.{ .kind = .ctrl, .name = ";", .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .ctrl, .name = mid, .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .ctrl, .name = ";", .pos = t.pos, .synth = true });
        // LIFO: the last-pushed lead `\;` pops first; parse it here
        // and let the arrow + trail follow as row siblings. The two
        // `\;` nodes are identical, so pop order between them is
        // unobservable — what matters is the arrow lands between.
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and tokNameEq(name, "plim")) {
        // KaTeX macro parity (macros.ts): `\plim` expands to
        // `\DOTSB\mathop{\operatorname{plim}}\limits`; `\DOTSB`
        // only steers a following `\dots` (no MathML trace). True
        // token-level expansion like `\iff` above — pushed last-first
        // (LIFO) so `\mathop` pops first and its node (with `\limits`
        // attached by the row loop) is this call's single return.
        try ctx.push(.{ .kind = .ctrl, .name = "limits", .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .rbrace, .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .rbrace, .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .char, .cp = 'm', .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .char, .cp = 'i', .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .char, .cp = 'l', .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .char, .cp = 'p', .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .lbrace, .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .ctrl, .name = "operatorname", .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .lbrace, .pos = t.pos, .synth = true });
        try ctx.push(.{ .kind = .ctrl, .name = "mathop", .pos = t.pos, .synth = true });
        return (try parseSingle(ctx, depth)).?;
    }
    if (full_only and (tokNameEq(name, "sout"))) {
        // Math-mode strikeout (KaTeX parity, allowed with a
        // strict-mode warning there): horizontal rule like cancel.
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .sout = body });
    }
    if (full_only and (tokNameEq(name, "phase"))) {
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .phase = body });
    }
    if (full_only and (tokNameEq(name, "textcircled"))) {
        // Math-mode circled (KaTeX parity: strict-mode warning
        // there, never a reject): full-only like math `\sout`
        // while the `\text` token path stays subset-free.
        const body = try parseGroupOrAtom(ctx, depth);
        return ctx.allocNode(.{ .circled = .{ .body = body } });
    }
    if (tokNameEq(name, "quad")) return ctx.allocNode(.{ .space = 1000 });
    if (tokNameEq(name, "qquad")) return ctx.allocNode(.{ .space = 2000 });
    if (tokNameEq(name, "enskip")) return ctx.allocNode(.{ .space = 500 });
    // Named muskip aliases (issue #73, KaTeX macros.ts parity):
    // `\thinspace` = `\,`, `\medspace` = `\:`, `\thickspace` = `\;`,
    // `\negthinspace` = `\!`, `\negmedspace` = -4mu, `\negthickspace`
    // = -5mu, `\enspace` = 0.5em kern, `\>` = medium space (the
    // single-char arm already covers `\\>`; this names it for the
    // table). MathML tags follow from the shared `.space` walker.
    if (tokNameEq(name, "thinspace")) return ctx.allocNode(.{ .space = space_thin });
    if (tokNameEq(name, "medspace")) return ctx.allocNode(.{ .space = space_med });
    if (tokNameEq(name, "thickspace")) return ctx.allocNode(.{ .space = space_thick });
    if (tokNameEq(name, "negthinspace")) return ctx.allocNode(.{ .space = -space_thin });
    if (tokNameEq(name, "negmedspace")) return ctx.allocNode(.{ .space = -222 });
    if (tokNameEq(name, "negthickspace")) return ctx.allocNode(.{ .space = -278 });
    if (tokNameEq(name, "enspace")) return ctx.allocNode(.{ .space = 500 });
    if (tokNameEq(name, "newline")) return ctx.allocNode(.{ .newline = {} });
    if (tokNameEq(name, "hspace") or tokNameEq(name, "kern") or
        tokNameEq(name, "hskip") or tokNameEq(name, "mkern") or tokNameEq(name, "mskip"))
    {
        const pk = try ctx.peek();
        if (pk.kind == .char and pk.cp == '*') _ = try ctx.next();
        const v = try parseDimenArg(ctx, t);
        return ctx.allocNode(.{ .space = v });
    }
    if (full_only and (tokNameEq(name, "nobreakspace") or tokNameEq(name, "space"))) {
        // KaTeX spacing-group symbols render `<mtext>&nbsp;</mtext>`
        // exactly like `\ ` (`.nbsp`); full-only (issue #73).
        return ctx.allocNode(.{ .nbsp = {} });
    }
    if (full_only and (tokNameEq(name, "vspace"))) {
        const v = try parseDimenArg(ctx, t);
        return ctx.allocNode(.{ .vspace = v });
    }

    // Symbol table (Greek, operators, relations, ...).
    if (symbols.lookup(name)) |sym| {
        if (sym.large_op or sym.func) {
            const text: []const u8 = if (sym.func) name else "";
            const cp: u21 = if (sym.func) 0 else sym.cp;
            return ctx.allocNode(.{ .op = .{
                .cp = cp,
                .large = sym.large_op,
                .func = sym.func,
                .limits = .auto,
                .lim_def = sym.limits_default,
                .text = text,
            } });
        }
        return ctx.allocNode(.{ .atom = .{ .class = sym.class, .font = .rm, .cp = sym.cp, .textord = symbols.isTextord(name) } });
    }
    if (symbols.lookupDelim(name)) |d| {
        // Bare delimiter (no `\left`): fixed-size atom in the
        // delimiter's own class (KaTeX symbol-table group).
        return ctx.allocNode(.{ .atom = .{ .class = d.cls, .font = .rm, .cp = d.cp } });
    }
    return ctx.fail(t.pos, "undefined control sequence");
}

// ---------------------------------------------------------------------------
// Single-character control sequences
// ---------------------------------------------------------------------------

fn parseSingleCharCtrl(ctx: *ParseCtx, depth: u8, t: Tok) Error!Idx {
    const c: u8 = t.name[0];
    switch (c) {
        '{' => return ctx.allocNode(.{ .atom = .{ .class = .Open, .font = .rm, .cp = '{' } }),
        '}' => return ctx.allocNode(.{ .atom = .{ .class = .Close, .font = .rm, .cp = '}' } }),
        '$' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '$', .textord = true } }),
        '%' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '%', .textord = true } }),
        '&' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '&', .textord = true } }),
        '#' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '#', .textord = true } }),
        '_' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = '_', .textord = true } }),
        '|' => return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = 0x2016, .textord = true } }),
        ' ' => return ctx.allocNode(.{ .nbsp = {} }),
        ',' => return ctx.allocNode(.{ .space = space_thin }),
        ':' => return ctx.allocNode(.{ .space = space_med }),
        // KaTeX `\>` is a medium space (issue #38: med-space row).
        '>' => return ctx.allocNode(.{ .space = space_med }),
        ';' => return ctx.allocNode(.{ .space = space_thick }),
        '!' => return ctx.allocNode(.{ .space = -space_thin }),
        // No `\/` arm: KaTeX has no italic-correction escape, in math
        // or text mode — it falls through to "undefined control sequence".
        '\\' => return ctx.allocNode(.{ .newline = {} }),
        else => {},
    }
    // Text accents (`\'`, `\"`, ...) in math mode build accent nodes
    // (KaTeX parity: allowed outside strict mode, with the spacing
    // accent glyph as label). `\t`, `\d`, `\b` have no math-mode
    // accent form and keep the precomposed lowering below.
    if (textAccentCp(c)) |acc| {
        const a = try parseGroupOrAtom(ctx, depth);
        if (mathTextAccentCp(c)) |spacing| {
            return ctx.allocNode(.{ .accent = .{ .cp = spacing, .wide = false, .nucleus = a } });
        }
        return applyTextAccent(ctx, t.pos, acc, a);
    }
    // Single-letter named symbols (`\S`, `\aa`, ...) live in the same
    // table as multi-letter names (KaTeX parity, full profile only).
    if (comptime active_profile == .full) {
        if (symbols.lookup(t.name)) |sym| {
            return ctx.allocNode(.{ .atom = .{ .class = sym.class, .font = .rm, .cp = sym.cp, .textord = symbols.isTextord(t.name) } });
        }
    }
    return ctx.fail(t.pos, "undefined control sequence");
}

/// Spacing accent label for math-mode text accents (KaTeX
/// `accent`-group symbols in text mode). Also the overlay glyph for
/// text-mode accents with no precomposed form (issues #36, #38).
pub fn mathTextAccentCp(c: u8) ?u21 {
    for (symbols.all_math_text_accents) |e| if (e.c == c) return e.cp;
    return null;
}

pub fn textAccentCp(c: u8) ?u21 {
    return switch (c) {
        '\'' => 0x0301,
        '`' => 0x0300,
        '^' => 0x0302,
        '"' => 0x0308,
        '~' => 0x0303,
        '=' => 0x0304,
        '.' => 0x0307,
        'u' => 0x0306,
        'v' => 0x030C,
        'H' => 0x030B,
        't' => 0x0361,
        'c' => 0x0327,
        'd' => 0x0323,
        'b' => 0x0331,
        'r' => 0x030A,
        else => null,
    };
}

/// Apply a text accent to a single-letter argument. Common
/// Latin precompositions map to single codepoints; anything else is
/// rejected (KaTeX parity is approximate here — the sweep pins it).
fn applyTextAccent(ctx: *ParseCtx, pos: u32, acc: u21, arg: Idx) Error!Idx {
    const base: u21 = switch (ctx.nodes[arg]) {
        .atom => |a| a.cp,
        .group => |g| blk: {
            if (g.len != 1) return ctx.fail(pos, "accent supports single letters");
            break :blk switch (ctx.nodes[ctx.kids[g.start]]) {
                .atom => |a| a.cp,
                else => return ctx.fail(pos, "accent supports single letters"),
            };
        },
        else => return ctx.fail(pos, "accent supports single letters"),
    };
    if (precompose(acc, base)) |cp| {
        return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = cp } });
    }
    return ctx.fail(pos, "unsupported accent combination");
}

pub fn precompose(acc: u21, base: u21) ?u21 {
    const Key = struct { acc: u21, base: u21, cp: u21 };
    const table: []const Key = &.{
        .{ .acc = 0x0301, .base = 'a', .cp = 0x00E1 }, .{ .acc = 0x0301, .base = 'e', .cp = 0x00E9 },
        .{ .acc = 0x0301, .base = 'i', .cp = 0x00ED }, .{ .acc = 0x0301, .base = 'o', .cp = 0x00F3 },
        .{ .acc = 0x0301, .base = 'u', .cp = 0x00FA }, .{ .acc = 0x0301, .base = 'y', .cp = 0x00FD },
        .{ .acc = 0x0301, .base = 'A', .cp = 0x00C1 }, .{ .acc = 0x0301, .base = 'E', .cp = 0x00C9 },
        .{ .acc = 0x0301, .base = 'I', .cp = 0x00CD }, .{ .acc = 0x0301, .base = 'O', .cp = 0x00D3 },
        .{ .acc = 0x0301, .base = 'U', .cp = 0x00DA },
        .{ .acc = 0x0300, .base = 'a', .cp = 0x00E0 }, .{ .acc = 0x0300, .base = 'e', .cp = 0x00E8 },
        .{ .acc = 0x0300, .base = 'i', .cp = 0x00EC }, .{ .acc = 0x0300, .base = 'o', .cp = 0x00F2 },
        .{ .acc = 0x0300, .base = 'u', .cp = 0x00F9 }, .{ .acc = 0x0300, .base = 'A', .cp = 0x00C0 },
        .{ .acc = 0x0300, .base = 'E', .cp = 0x00C8 }, .{ .acc = 0x0300, .base = 'I', .cp = 0x00CC },
        .{ .acc = 0x0300, .base = 'O', .cp = 0x00D2 }, .{ .acc = 0x0300, .base = 'U', .cp = 0x00D9 },
        .{ .acc = 0x0302, .base = 'a', .cp = 0x00E2 }, .{ .acc = 0x0302, .base = 'e', .cp = 0x00EA },
        .{ .acc = 0x0302, .base = 'i', .cp = 0x00EE }, .{ .acc = 0x0302, .base = 'o', .cp = 0x00F4 },
        .{ .acc = 0x0302, .base = 'u', .cp = 0x00FB }, .{ .acc = 0x0302, .base = 'A', .cp = 0x00C2 },
        .{ .acc = 0x0302, .base = 'E', .cp = 0x00CA }, .{ .acc = 0x0302, .base = 'I', .cp = 0x00CE },
        .{ .acc = 0x0302, .base = 'O', .cp = 0x00D4 }, .{ .acc = 0x0302, .base = 'U', .cp = 0x00DB },
        .{ .acc = 0x0308, .base = 'a', .cp = 0x00E4 }, .{ .acc = 0x0308, .base = 'e', .cp = 0x00EB },
        .{ .acc = 0x0308, .base = 'i', .cp = 0x00EF }, .{ .acc = 0x0308, .base = 'o', .cp = 0x00F6 },
        .{ .acc = 0x0308, .base = 'u', .cp = 0x00FC }, .{ .acc = 0x0308, .base = 'y', .cp = 0x00FF },
        .{ .acc = 0x0308, .base = 'A', .cp = 0x00C4 }, .{ .acc = 0x0308, .base = 'E', .cp = 0x00CB },
        .{ .acc = 0x0308, .base = 'I', .cp = 0x00CF }, .{ .acc = 0x0308, .base = 'O', .cp = 0x00D6 },
        .{ .acc = 0x0308, .base = 'U', .cp = 0x00DC },
        .{ .acc = 0x0303, .base = 'a', .cp = 0x00E3 }, .{ .acc = 0x0303, .base = 'o', .cp = 0x00F5 },
        .{ .acc = 0x0303, .base = 'n', .cp = 0x00F1 }, .{ .acc = 0x0303, .base = 'A', .cp = 0x00C3 },
        .{ .acc = 0x0303, .base = 'O', .cp = 0x00D5 }, .{ .acc = 0x0303, .base = 'N', .cp = 0x00D1 },
        .{ .acc = 0x030A, .base = 'a', .cp = 0x00E5 }, .{ .acc = 0x030A, .base = 'A', .cp = 0x00C5 },
        .{ .acc = 0x0327, .base = 'c', .cp = 0x00E7 }, .{ .acc = 0x0327, .base = 'C', .cp = 0x00C7 },
        .{ .acc = 0x030C, .base = 'c', .cp = 0x010D }, .{ .acc = 0x030C, .base = 's', .cp = 0x0161 },
        .{ .acc = 0x030C, .base = 'z', .cp = 0x017E }, .{ .acc = 0x030C, .base = 'C', .cp = 0x010C },
        .{ .acc = 0x030C, .base = 'S', .cp = 0x0160 }, .{ .acc = 0x030C, .base = 'Z', .cp = 0x017D },
        .{ .acc = 0x0306, .base = 'a', .cp = 0x0103 }, .{ .acc = 0x0306, .base = 'g', .cp = 0x011F },
        .{ .acc = 0x0304, .base = 'a', .cp = 0x0101 }, .{ .acc = 0x0304, .base = 'e', .cp = 0x0113 },
        .{ .acc = 0x0304, .base = 'i', .cp = 0x012B }, .{ .acc = 0x0304, .base = 'o', .cp = 0x014D },
        .{ .acc = 0x0304, .base = 'u', .cp = 0x016B },
        .{ .acc = 0x0307, .base = 'z', .cp = 0x017C }, .{ .acc = 0x0307, .base = 'Z', .cp = 0x017B },
        .{ .acc = 0x030B, .base = 'o', .cp = 0x0151 }, .{ .acc = 0x030B, .base = 'u', .cp = 0x0171 },
        .{ .acc = 0x030B, .base = 'O', .cp = 0x0150 }, .{ .acc = 0x030B, .base = 'U', .cp = 0x0170 },
        .{ .acc = 0x0323, .base = 'a', .cp = 0x1EA0 }, .{ .acc = 0x0323, .base = 'e', .cp = 0x1EB8 },
    };
    for (table) |e| if (e.acc == acc and e.base == base) return e.cp;
    return null;
}

// ---------------------------------------------------------------------------
// Style commands, fonts, over/under
// ---------------------------------------------------------------------------

fn isStyleName(name: []const u8) bool {
    return tokNameEq(name, "displaystyle") or tokNameEq(name, "textstyle") or
        tokNameEq(name, "scriptstyle") or tokNameEq(name, "scriptscriptstyle");
}

fn styleFor(name: []const u8) Style {
    if (tokNameEq(name, "displaystyle")) return .D;
    if (tokNameEq(name, "textstyle")) return .T;
    if (tokNameEq(name, "scriptstyle")) return .S;
    return .SS;
}

/// Font-size declarations (KaTeX `sizeFuncs` order, index 1–11;
/// per-mille multipliers from `sizeMultipliers`).
fn sizeMultFor(name: []const u8) ?u16 {
    if (tokNameEq(name, "tiny")) return 500;
    if (tokNameEq(name, "sixptsize")) return 600;
    if (tokNameEq(name, "scriptsize")) return 700;
    if (tokNameEq(name, "footnotesize")) return 800;
    if (tokNameEq(name, "small")) return 900;
    if (tokNameEq(name, "normalsize")) return 1000;
    if (tokNameEq(name, "large")) return 1200;
    if (tokNameEq(name, "Large")) return 1440;
    if (tokNameEq(name, "LARGE")) return 1728;
    if (tokNameEq(name, "huge")) return 2074;
    if (tokNameEq(name, "Huge")) return 2488;
    return null;
}

fn fontFamFor(name: []const u8) ?FontFam {
    // Math-mode families take math arguments (`\mathbf{\alpha}`).
    if (tokNameEq(name, "mathrm") or tokNameEq(name, "rm")) return .rm;
    if (tokNameEq(name, "mathit") or tokNameEq(name, "it") or
        tokNameEq(name, "mathnormal")) return .mathit;
    if (tokNameEq(name, "mathbf") or tokNameEq(name, "bf") or
        tokNameEq(name, "bold")) return .bold;
    if (tokNameEq(name, "mathsf") or tokNameEq(name, "sf")) return .sans;
    // `\mathsfit` sans-serif italic (issue #137, KaTeX `font.ts` +
    // `buildMathML.ts` `sans-serif-italic`). Core like `\mathsf`.
    if (tokNameEq(name, "mathsfit")) return .sansitalic;
    if (tokNameEq(name, "mathtt") or tokNameEq(name, "tt")) return .tt;
    if (tokNameEq(name, "mathfrak") or tokNameEq(name, "frak")) return .frak;
    if (tokNameEq(name, "mathscr")) return .script;
    if (tokNameEq(name, "mathbb") or tokNameEq(name, "Bbb")) return .bb;
    if (tokNameEq(name, "mathcal") or tokNameEq(name, "cal")) return .cal;
    // `\bm` bold-italic (issue #73, KaTeX `mathvariant="bold-italic"`).
    if (tokNameEq(name, "bm")) return .bolditalic;
    return null;
}

/// Old-style declarations: the six names KaTeX parses with zero
/// arguments (issue #94, pinned 0.18.7) — they scope over the rest of
/// the enclosing group instead of taking one group-or-atom. Every
/// other `fontFamFor` name (`\mathbf`, `\mathcal`, `\bm`, ...) keeps
/// its single argument (parseCtrl arm above stays for those and for
/// single-atom nests like scripts).
fn oldStyleDeclFam(name: []const u8) ?FontFam {
    if (tokNameEq(name, "rm")) return .rm;
    if (tokNameEq(name, "it")) return .mathit;
    if (tokNameEq(name, "bf")) return .bold;
    if (tokNameEq(name, "sf")) return .sans;
    if (tokNameEq(name, "tt")) return .tt;
    if (tokNameEq(name, "cal")) return .cal;
    return null;
}

/// Text-mode families take text arguments (`\textbf{a+b}` is an
/// `mtext`, and `\textbf{\alpha}` is a KaTeX error). `\textsl` is
/// absent: KaTeX rejects it as undefined.
fn textFontFamFor(name: []const u8) ?FontFam {
    if (tokNameEq(name, "textrm") or tokNameEq(name, "textup") or
        tokNameEq(name, "textnormal") or tokNameEq(name, "textmd")) return .rm;
    if (tokNameEq(name, "textit") or tokNameEq(name, "emph")) return .mathit;
    if (tokNameEq(name, "textbf")) return .bold;
    if (tokNameEq(name, "textsf")) return .sans;
    if (tokNameEq(name, "texttt")) return .tt;
    return null;
}

fn parseOverName(name: []const u8) ?OverKind {
    if (tokNameEq(name, "overline")) return .overline;
    if (tokNameEq(name, "underline")) return .underline;
    if (tokNameEq(name, "overbrace")) return .overbrace;
    if (tokNameEq(name, "underbrace")) return .underbrace;
    if (tokNameEq(name, "overbracket")) return .overbracket;
    if (tokNameEq(name, "underbracket")) return .underbracket;
    if (tokNameEq(name, "overleftarrow")) return .overleft;
    if (tokNameEq(name, "overrightarrow")) return .overright;
    if (tokNameEq(name, "overleftrightarrow")) return .overboth;
    if (tokNameEq(name, "underleftarrow")) return .underleft;
    if (tokNameEq(name, "underrightarrow")) return .underright;
    if (tokNameEq(name, "underleftrightarrow")) return .underboth;
    if (tokNameEq(name, "xleftarrow")) return .xleft;
    if (tokNameEq(name, "xrightarrow")) return .xright;
    if (tokNameEq(name, "xleftrightarrow")) return .xboth;
    if (tokNameEq(name, "xhookleftarrow")) return .xhookleft;
    if (tokNameEq(name, "xhookrightarrow")) return .xhookright;
    if (tokNameEq(name, "xmapsto")) return .xmapsto;
    if (tokNameEq(name, "xtwoheadleftarrow")) return .xtwoheadleft;
    if (tokNameEq(name, "xtwoheadrightarrow")) return .xtwoheadright;
    if (tokNameEq(name, "angl")) return .angl;
    if (tokNameEq(name, "overgroup")) return .overgroup;
    if (tokNameEq(name, "undergroup")) return .undergroup;
    if (tokNameEq(name, "overlinesegment")) return .overlinesegment;
    if (tokNameEq(name, "underlinesegment")) return .underlinesegment;
    if (tokNameEq(name, "overleftharpoon")) return .overleftharpoon;
    if (tokNameEq(name, "overrightharpoon")) return .overrightharpoon;
    if (tokNameEq(name, "Overrightarrow")) return .overRightarrow;
    if (tokNameEq(name, "underbar")) return .underbar;
    if (tokNameEq(name, "utilde")) return .utilde;
    if (tokNameEq(name, "xLeftarrow")) return .xdoubleleft;
    if (tokNameEq(name, "xLeftrightarrow")) return .xdoubleboth;
    if (tokNameEq(name, "xRightarrow")) return .xdoubleright;
    if (tokNameEq(name, "xleftharpoondown")) return .xleftharpoondown;
    if (tokNameEq(name, "xleftharpoonup")) return .xleftharpoonup;
    if (tokNameEq(name, "xleftrightharpoons")) return .xleftrightharpoons;
    if (tokNameEq(name, "xlongequal")) return .xlongequal;
    if (tokNameEq(name, "xrightharpoondown")) return .xrightharpoondown;
    if (tokNameEq(name, "xrightharpoonup")) return .xrightharpoonup;
    if (tokNameEq(name, "xrightleftharpoons")) return .xrightleftharpoons;
    if (tokNameEq(name, "xtofrom")) return .xtofrom;
    return null;
}

fn parseOver(ctx: *ParseCtx, depth: u8, t: Tok, kind: OverKind) Error!Idx {
    if (kind == .underbar or kind == .angl) {
        // KaTeX parity (pinned 0.18.7): `\underbar` and `\angl`
        // set their bodies in text mode — math commands reject,
        // like `\text`.
        const raw = try parseBracedToks(ctx, t, false);
        const toks = try selectBranchToks(ctx, raw, false);
        try checkTextToks(ctx, toks);
        const nuc = try ctx.allocNode(.{ .text = .{ .toks = toks, .fam = .rm } });
        return ctx.allocNode(.{ .over = .{
            .kind = kind,
            .nucleus = nuc,
            .extra = NONE,
            .under = NONE,
        } });
    }
    switch (kind) {
        .xleft, .xright, .xboth, .xhookleft, .xhookright, .xmapsto, .xtwoheadleft, .xtwoheadright, .xdoubleleft, .xdoubleboth, .xdoubleright, .xleftharpoondown, .xleftharpoonup, .xleftrightharpoons, .xlongequal, .xrightharpoondown, .xrightharpoonup, .xrightleftharpoons, .xtofrom => {
            var under: Idx = NONE;
            const pk = try ctx.peek();
            if (pk.kind == .char and pk.cp == '[') {
                _ = try ctx.next();
                const r = try parseFormula(ctx, depth, .bracket, null);
                under = r;
            }
            const above = try parseGroupOrAtom(ctx, depth);
            return ctx.allocNode(.{ .over = .{
                .kind = kind,
                .nucleus = NONE,
                .extra = above,
                .under = under,
            } });
        },
        else => {
            const nuc = try parseGroupOrAtom(ctx, depth);
            return ctx.allocNode(.{ .over = .{
                .kind = kind,
                .nucleus = nuc,
                .extra = NONE,
                .under = NONE,
            } });
        },
    }
}

// ---------------------------------------------------------------------------
// Fractions, roots, fences
// ---------------------------------------------------------------------------

fn parseFracLike(ctx: *ParseCtx, depth: u8, kind: FracKind) Error!Idx {
    try subsetGate(true);
    const num = try parseGroupOrAtom(ctx, depth);
    const den = try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .frac = .{ .num = num, .den = den, .kind = kind } });
}

fn parseSqrt(ctx: *ParseCtx, depth: u8) Error!Idx {
    try subsetGate(true);
    var index: Idx = NONE;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        index = try parseFormula(ctx, depth, .bracket, null);
    }
    // KaTeX parity: without an index the radicand is a `primitive`
    // argument — a bare `'`/`\rq` starts no atom there
    // (`\sqrt'` rejects; with an index it is a normal argument and
    // accepts, pinned 0.18.7).
    if (index == NONE) {
        const q = try ctx.peek();
        if ((q.kind == .char and q.cp == '\'') or (q.kind == .ctrl and tokNameEq(q.name, "rq"))) {
            // KaTeX parity: `\\rq` is a builtin macro for `'` (pinned
            // 0.18.7 `defineMacro("\\rq", "'")`), and builtin-macro
            // expansion tokens carry definition-string positions —
            // the expanded `'` reports 0, while a typed `'` reports
            // its source offset (`\\sqrt\\rq` → 0, `\\sqrt'` → 5).
            const pos: u32 = if (q.kind == .ctrl) 0 else q.pos;
            return ctx.fail(pos, "expected group");
        }
    }
    // KaTeX parity: with an index the radicand is an isolated
    // argument (the `\sqrt[3]\bf` quirk accepts); without one it is a
    // `primitive` — bare functions throw `as argument to '\sqrt'`.
    const rad = if (index == NONE)
        try parseGroupOrAtomMode(ctx, depth, .sqrt, 0)
    else
        try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .sqrt = .{ .radicand = rad, .index = index } });
}

/// Read one delimiter specification: a bare char, `\|`, or a named
/// delimiter command. `.` means "no fence" (u21 0).
fn parseDelimSpec(ctx: *ParseCtx) Error!u21 {
    const t = try ctx.next();
    switch (t.kind) {
        .char => {
            if (t.cp == '.') return 0;
            return switch (t.cp) {
                '(', ')', '[', ']', '{', '}', '|', '/', '<', '>' => t.cp,
                else => ctx.fail(t.pos, "expected delimiter"),
            };
        },
        .ctrl => {
            if (t.name.len == 1) {
                const c = t.name[0];
                switch (c) {
                    '|', '/' => return c,
                    '\\' => return 0x005C,
                    '{' => return '{',
                    '}' => return '}',
                    else => return ctx.fail(t.pos, "expected delimiter"),
                }
            }
            if (symbols.lookupDelim(t.name)) |d| return d.cp;
            return ctx.fail(t.pos, "expected delimiter");
        },
        else => return ctx.fail(t.pos, "expected delimiter"),
    }
}

fn parseLeftRight(ctx: *ParseCtx, depth: u8, t: Tok) Error!Idx {
    const left = try parseDelimSpec(ctx);
    ctx.in_fence += 1;
    const body = try parseFormula(ctx, depth, .leftright, null);
    ctx.in_fence -= 1;
    // parseFormula stopped before `\right` (unconsumed).
    const r = try ctx.next();
    if (r.kind != .ctrl or !tokNameEq(r.name, "right")) return ctx.fail(r.pos, "expected '\\right'");
    _ = t;
    const right = try parseDelimSpec(ctx);
    return ctx.allocNode(.{ .delim = .{ .left = left, .right = right, .body = body } });
}

fn isBigName(name: []const u8) bool {
    const prefixes = [_][]const u8{ "bigl", "bigm", "bigr", "Bigl", "Bigm", "Bigr", "biggl", "biggm", "biggr", "Biggl", "Biggm", "Biggr", "big", "Big", "bigg", "Bigg" };
    for (prefixes) |p| if (tokNameEq(name, p)) return true;
    return false;
}

fn parseBig(ctx: *ParseCtx, name: []const u8, t: Tok) Error!Idx {
    // Level from the prefix (`big`/`Big`/`bigg`/`Bigg`), class from
    // the `l`/`m`/`r` suffix (absent = Ord).
    var level: u2 = 0;
    if (name[0] == 'B') level = 1;
    var rest = name[3..];
    if (name[0] == 'b' and rest.len > 0 and rest[0] == 'g') {
        level = 2;
        rest = rest[1..];
    }
    if (name[0] == 'B' and rest.len > 0 and (rest[0] == 'g' or (rest.len > 1 and rest[1] == 'g'))) {
        level = 3;
        rest = rest[1..];
        if (rest.len > 0 and rest[0] == 'g') rest = rest[0..0]; // "Bigg"
    }
    var class: symbols.AtomClass = .Ord;
    if (rest.len == 1) class = suffixClass(rest[0]) else if (rest.len != 0) {
        return ctx.fail(t.pos, "undefined control sequence");
    }
    // Delimiter spec (`.` is not allowed here — KaTeX rejects `\big.`).
    const dt = try ctx.next();
    const cp: u21 = switch (dt.kind) {
        .char => switch (dt.cp) {
            '(', ')', '[', ']', '{', '}', '|', '/', '<', '>' => dt.cp,
            else => return ctx.fail(dt.pos, "expected delimiter"),
        },
        .ctrl => blk: {
            if (dt.name.len == 1) {
                const c = dt.name[0];
                break :blk switch (c) {
                    '|', '/' => @as(u21, c),
                    '\\' => @as(u21, 0x005C),
                    '{' => @as(u21, '{'),
                    '}' => @as(u21, '}'),
                    else => return ctx.fail(dt.pos, "expected delimiter"),
                };
            }
            break :blk (symbols.lookupDelim(dt.name) orelse return ctx.fail(dt.pos, "expected delimiter")).cp;
        },
        else => return ctx.fail(dt.pos, "expected delimiter"),
    };
    return ctx.allocNode(.{ .big = .{ .cp = cp, .level = level, .class = class } });
}

fn suffixClass(c: u8) symbols.AtomClass {
    return switch (c) {
        'l' => .Open,
        'm' => .Rel,
        'r' => .Close,
        else => .Ord,
    };
}

// ---------------------------------------------------------------------------
// Dimensions
// ---------------------------------------------------------------------------

/// Parse a dimension argument (braced tokens or bare `2.5ex`).
/// Result in thousandths of an em, clamped to i16.
fn parseDimenArg(ctx: *ParseCtx, cmd: Tok) Error!i16 {
    const pk = try ctx.peek();
    if (pk.kind == .lbrace) {
        _ = try ctx.next();
        const r = try ctx.captureToBrace(pk.pos);
        return dimenFromToks(ctx, r, cmd.pos);
    }
    // Bare dimension: number chars, then at most two unit letters.
    // KaTeX parity: the unit is exactly `[a-z]{2}`; anything after it
    // belongs to the following input (`\kern2pt c` kerns 2pt, then `c`).
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    var nletters: usize = 0;
    while (n < buf.len) {
        const q = try ctx.peek();
        if (q.kind != .char) break;
        const c = q.cp;
        if (c > 0x7F) break;
        const is_letter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
        if (is_letter) {
            if (nletters >= 2) break;
            nletters += 1;
        } else {
            const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-';
            if (!ok) break;
        }
        _ = try ctx.next();
        buf[n] = @intCast(c);
        n += 1;
    }
    if (n == 0) return ctx.fail(cmd.pos, "expected dimension");
    return dimenFromBytes(buf[0..n], cmd.pos, ctx);
}

fn dimenFromToks(ctx: *ParseCtx, r: Range, pos: u32) Error!i16 {
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    var i: u16 = 0;
    while (i < r.len) : (i += 1) {
        const tk = ctx.toks[r.start + i];
        if (tk.kind != .char or tk.cp > 0x7F) return ctx.fail(tk.pos, "expected dimension");
        const c: u8 = @intCast(tk.cp);
        const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-' or
            (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
        if (!ok) return ctx.fail(tk.pos, "expected dimension");
        if (n >= buf.len) return ctx.fail(tk.pos, "dimension too long");
        buf[n] = c;
        n += 1;
    }
    return dimenFromBytes(buf[0..n], pos, ctx);
}

fn dimenFromBytes(b: []const u8, pos: u32, ctx: *ParseCtx) Error!i16 {
    var i: usize = 0;
    var neg = false;
    if (i < b.len and (b[i] == '+' or b[i] == '-')) {
        neg = b[i] == '-';
        i += 1;
    }
    var int: i64 = 0;
    var frac: i64 = 0;
    var fdiv: i64 = 1;
    var digits = false;
    while (i < b.len and b[i] >= '0' and b[i] <= '9') : (i += 1) {
        int = int * 10 + (b[i] - '0');
        digits = true;
    }
    if (i < b.len and b[i] == '.') {
        i += 1;
        while (i < b.len and b[i] >= '0' and b[i] <= '9' and fdiv < 1000000) : (i += 1) {
            frac = frac * 10 + (b[i] - '0');
            fdiv *= 10;
            digits = true;
        }
        while (i < b.len and b[i] >= '0' and b[i] <= '9') : (i += 1) {}
    }
    if (!digits) return ctx.fail(pos, "expected dimension");
    // Unit: exactly two lowercase letters (KaTeX `[a-z]{2}` — `PT` is
    // rejected). Anything after them belongs to the following input
    // and is ignored here.
    if (i + 2 > b.len) return ctx.fail(pos, "expected dimension");
    const unit = b[i .. i + 2];
    // Thousandths of an em per unit (1em = 10pt at the reference size).
    const per_em: i64 = if (std.mem.eql(u8, unit, "em"))
        1000
    else if (std.mem.eql(u8, unit, "ex"))
        500 // ≈ x-height; documented approximation
    else if (std.mem.eql(u8, unit, "mu"))
        1000
    else if (std.mem.eql(u8, unit, "pt"))
        100
    else if (std.mem.eql(u8, unit, "pc"))
        1200
    else if (std.mem.eql(u8, unit, "in"))
        7227
    else if (std.mem.eql(u8, unit, "bp"))
        100
    else if (std.mem.eql(u8, unit, "cm"))
        2845
    else if (std.mem.eql(u8, unit, "mm"))
        285
    else if (std.mem.eql(u8, unit, "dd"))
        107
    else if (std.mem.eql(u8, unit, "cc"))
        1288
    else if (std.mem.eql(u8, unit, "sp"))
        0
    else
        return ctx.fail(pos, "unknown unit");
    var v: i64 = int * per_em + @divTrunc(frac * per_em, fdiv);
    // mu widths round to the nearest thousandth (KaTeX measures in em
    // floats: 3mu = 0.1667em is a thin space, so `\mkern3mu` must hit
    // `space_thin` = 167 exactly, not truncate to 166).
    if (std.mem.eql(u8, unit, "mu")) v = @divTrunc(v + 9, 18);
    if (neg) v = -v;
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    return @intCast(v);
}

/// Hundred-thousandths of an em (1e-5): the `\includegraphics`
/// size currency. KaTeX `makeEm` prints four decimals, so sizes
/// round-trip through here bit-exactly for every realistic input
/// (see `graphicsSize`); layout scales them with `scale5`.
pub const em5_per_em: i32 = 100000;

/// Default `\includegraphics` height: KaTeX `{number: 0.9,
/// unit: "em"}` ("sorta character sized").
pub const graphics_default_h: i32 = 90000;

/// Format an em5 value as the shortest exact decimal with its unit
/// (`20075` → `0.20075em`, `100000` → `1em`, `0` → `0em`).
/// Needs 14 bytes of buffer.
pub fn fmtEm5(v: i32, buf: []u8) []u8 {
    var neg = false;
    var a: i64 = v;
    if (a < 0) {
        neg = true;
        a = -a;
    }
    var n: usize = 0;
    if (neg) {
        buf[0] = '-';
        n = 1;
    }
    var ip: i64 = @divTrunc(a, em5_per_em);
    var tmp: [8]u8 = undefined;
    var nd: usize = 0;
    if (ip == 0) {
        tmp[0] = '0';
        nd = 1;
    } else {
        while (ip > 0) : (nd += 1) {
            tmp[nd] = '0' + @as(u8, @intCast(@mod(ip, 10)));
            ip = @divTrunc(ip, 10);
        }
    }
    while (nd > 0) : (nd -= 1) {
        buf[n] = tmp[nd - 1];
        n += 1;
    }
    var fr: i64 = @mod(a, em5_per_em);
    if (fr != 0) {
        var fdig: [5]u8 = .{ '0', '0', '0', '0', '0' };
        var k: usize = 5;
        while (k > 0) : (k -= 1) {
            fdig[k - 1] = '0' + @as(u8, @intCast(@mod(fr, 10)));
            fr = @divTrunc(fr, 10);
        }
        var nf: usize = 5;
        while (nf > 0 and fdig[nf - 1] == '0') nf -= 1;
        buf[n] = '.';
        n += 1;
        @memcpy(buf[n .. n + nf], fdig[0..nf]);
        n += nf;
    }
    buf[n] = 'e';
    buf[n + 1] = 'm';
    return buf[0 .. n + 2];
}

/// Format an em5 value the way KaTeX `makeEm` does: round to four
/// decimals (half away from zero), strip trailing zeros, add the
/// unit (`10038` → `0.1004em`, `90000` → `0.9em`). Needs 14 bytes.
pub fn fmtEm4(v: i32, buf: []u8) []u8 {
    var q = @divTrunc(v, 10);
    const r = @rem(v, 10);
    if (r >= 5 or r <= -5) q += if (q < 0 or (q == 0 and v < 0)) @as(i32, -1) else @as(i32, 1);
    // q is ten-thousandths of an em (1e-4); render like fmtEm5.
    var neg = false;
    var a: i64 = q;
    if (a < 0) {
        neg = true;
        a = -a;
    }
    var n: usize = 0;
    if (neg) {
        buf[0] = '-';
        n = 1;
    }
    var ip: i64 = @divTrunc(a, 10000);
    var tmp: [8]u8 = undefined;
    var nd: usize = 0;
    if (ip == 0) {
        tmp[0] = '0';
        nd = 1;
    } else {
        while (ip > 0) : (nd += 1) {
            tmp[nd] = '0' + @as(u8, @intCast(@mod(ip, 10)));
            ip = @divTrunc(ip, 10);
        }
    }
    while (nd > 0) : (nd -= 1) {
        buf[n] = tmp[nd - 1];
        n += 1;
    }
    var fr: i64 = @mod(a, 10000);
    if (fr != 0) {
        var fdig: [4]u8 = .{ '0', '0', '0', '0' };
        var k: usize = 4;
        while (k > 0) : (k -= 1) {
            fdig[k - 1] = '0' + @as(u8, @intCast(@mod(fr, 10)));
            fr = @divTrunc(fr, 10);
        }
        var nf: usize = 4;
        while (nf > 0 and fdig[nf - 1] == '0') nf -= 1;
        buf[n] = '.';
        n += 1;
        @memcpy(buf[n .. n + nf], fdig[0..nf]);
        n += nf;
    }
    buf[n] = 'e';
    buf[n + 1] = 'm';
    return buf[0 .. n + 2];
}

/// Exact em factor of a `\includegraphics` size unit as mult/div
/// (KaTeX `ptPerUnit`/`relativeUnit` over `ptPerEm` = 10 at the
/// reference size — the same reference `dimenFromBytes` assumes —
/// plus `ex` = 0.431 and `em`/`mu` from the metrics). `bp`
/// doubles as the bare-number unit (KaTeX `sizeData`).
fn graphicsUnit(unit: []const u8) ?struct { mult: i64, div: i64 } {
    if (std.mem.eql(u8, unit, "em")) return .{ .mult = 1, .div = 1 };
    if (std.mem.eql(u8, unit, "ex")) return .{ .mult = 431, .div = 1000 };
    if (std.mem.eql(u8, unit, "mu")) return .{ .mult = 1, .div = 18 };
    if (std.mem.eql(u8, unit, "pt")) return .{ .mult = 1, .div = 10 };
    if (std.mem.eql(u8, unit, "pc")) return .{ .mult = 6, .div = 5 };
    if (std.mem.eql(u8, unit, "in")) return .{ .mult = 7227, .div = 1000 };
    if (std.mem.eql(u8, unit, "bp")) return .{ .mult = 803, .div = 8000 };
    if (std.mem.eql(u8, unit, "cm")) return .{ .mult = 7227, .div = 2540 };
    if (std.mem.eql(u8, unit, "mm")) return .{ .mult = 7227, .div = 25400 };
    if (std.mem.eql(u8, unit, "dd")) return .{ .mult = 619, .div = 5785 };
    if (std.mem.eql(u8, unit, "cc")) return .{ .mult = 7428, .div = 5785 };
    if (std.mem.eql(u8, unit, "nd")) return .{ .mult = 137, .div = 1284 };
    if (std.mem.eql(u8, unit, "nc")) return .{ .mult = 137, .div = 107 };
    if (std.mem.eql(u8, unit, "sp")) return .{ .mult = 1, .div = 655360 };
    if (std.mem.eql(u8, unit, "px")) return .{ .mult = 803, .div = 8000 };
    return null;
}

fn isLower2(s: []const u8) bool {
    return s.len == 2 and s[0] >= 'a' and s[0] <= 'z' and s[1] >= 'a' and s[1] <= 'z';
}

/// Millionths × mult/div → em5 with KaTeX `sizeData` field
/// semantics: the `width`/`totalheight` attributes apply when the
/// raw `number` is positive — even when it rounds to zero (`1sp`
/// emits `width="0em"`). A positive-but-rounded-to-zero value
/// floors at 1 (which still formats as `0em`); zero and
/// negatives stay exactly zero.
fn sizeToEm5(v: i64, mult: i64, div: i64) i32 {
    const e = scaleEm5(v, mult, div);
    if (v > 0 and e == 0) return 1;
    return e;
}

/// Millionths × mult/div → em5, half away from zero via i128,
/// clamped to ±2e9 (about ±20000em; KaTeX floats larger
/// magnitudes into `makeEm` noise).
fn scaleEm5(num1e6: i64, mult: i64, div: i64) i32 {
    const n: i128 = @as(i128, num1e6) * @as(i128, mult);
    const d: i128 = @as(i128, div) * 10;
    var q = @divTrunc(n, d);
    const r = @rem(n, d);
    const half: i128 = @divTrunc(d, 2) + @mod(d, 2);
    if (r >= half or r <= -half) {
        q += if (q < 0 or (q == 0 and n < 0)) @as(i128, -1) else @as(i128, 1);
    }
    if (q > 2000000000) q = 2000000000;
    if (q < -2000000000) q = -2000000000;
    return @intCast(q);
}

/// Decimal int-part + fraction digits → millionths, rounding the
/// 7th fraction digit half away from zero. Saturates past 12
/// integer digits.
fn numTo1e6(int: i64, frac: []const u8) i64 {
    var fdiv: i64 = 1;
    var fv: i64 = 0;
    var i: usize = 0;
    while (i < frac.len and i < 6) : (i += 1) {
        fv = fv * 10 + (frac[i] - '0');
        fdiv *= 10;
    }
    var v = int * 1000000 + @divTrunc(fv * 1000000, fdiv);
    if (frac.len > 6 and frac[6] >= '5') v += 1;
    return v;
}

/// One decimal-number candidate: int value, fraction slice,
/// number end. `big` flags 12+ integer digits (saturated).
const NumCand = struct {
    iv: i64,
    big: bool,
    fs: usize,
    fl: usize,
    end: usize,
};

/// One decimal number at `text[j..]`: `(\d+(\.\d*)?|\.\d+)`.
/// Candidates, longest first — with fraction, then (backtracked)
/// bare int — mirroring the regex engine, which only backtracks
/// the optional `(\.\d*)?`. Nulls when no number starts at `j`.
fn scanNumber(text: []const u8, j: usize) [2]?NumCand {
    var cands: [2]?NumCand = .{ null, null };
    if (j >= text.len) return cands;
    if (text[j] >= '0' and text[j] <= '9') {
        var b = j;
        var iv: i64 = 0;
        var ndig: usize = 0;
        while (b < text.len and text[b] >= '0' and text[b] <= '9') : (b += 1) {
            if (ndig < 12) {
                iv = iv * 10 + (text[b] - '0');
                ndig += 1;
            }
        }
        const bend = b;
        if (b < text.len and text[b] == '.') {
            const fs = b + 1;
            b += 1;
            while (b < text.len and text[b] >= '0' and text[b] <= '9') : (b += 1) {}
            cands[0] = .{ .iv = iv, .big = ndig >= 12, .fs = fs, .fl = b - fs, .end = b };
        }
        cands[1] = .{ .iv = iv, .big = ndig >= 12, .fs = 0, .fl = 0, .end = bend };
    } else if (text[j] == '.') {
        var b = j + 1;
        const ds = b;
        while (b < text.len and text[b] >= '0' and text[b] <= '9') : (b += 1) {}
        if (b == ds) return cands;
        cands[0] = .{ .iv = 0, .big = false, .fs = ds, .fl = b - ds, .end = b };
    }
    return cands;
}

/// Candidate triple → millionths (sign applied by the caller).
fn candTo1e6(text: []const u8, cand: NumCand) i64 {
    const fslice: []const u8 = if (cand.fl > 0) text[cand.fs .. cand.fs + cand.fl] else &.{};
    return numTo1e6(cand.iv, fslice);
}

/// KaTeX `sizeData` (pinned 0.18.7 `functions/includegraphics.ts`)
/// in integer arithmetic: a bare number means bp; otherwise the
/// first left-to-right match of
/// `([-+]?) *(\d+(\.\d*)?|\.\d+) *([a-z]{2})` wins (so `1.2.3em`
/// reads as 2.3em, exactly like the regex engine). Result in em5.
fn graphicsSize(text: []const u8, pos: u32, ctx: *ParseCtx) Error!i32 {
    // Bare-number fast path (`^[-+]? *(\d+(\.\d*)?|\.\d+)$`).
    {
        var j: usize = 0;
        var neg = false;
        if (j < text.len and (text[j] == '+' or text[j] == '-')) {
            neg = text[j] == '-';
            j += 1;
        }
        while (j < text.len and text[j] == ' ') j += 1;
        const cands = scanNumber(text, j);
        for (cands) |c| {
            const cand = c orelse continue;
            if (cand.end != text.len) continue;
            if (cand.big) return sizeToEm5(if (neg) -1 else 1, std.math.maxInt(i32), 1);
            var v = candTo1e6(text, cand);
            if (neg) v = -v;
            const u = graphicsUnit("bp").?;
            return sizeToEm5(v, u.mult, u.div);
        }
    }
    // Unit scan: first start position with a full match wins.
    var s: usize = 0;
    while (s < text.len) : (s += 1) {
        var j = s;
        var neg = false;
        if (j < text.len and (text[j] == '+' or text[j] == '-')) {
            neg = text[j] == '-';
            j += 1;
        }
        while (j < text.len and text[j] == ' ') j += 1;
        for (scanNumber(text, j)) |c| {
            const cand = c orelse continue;
            var k = cand.end;
            while (k < text.len and text[k] == ' ') k += 1;
            if (k + 2 > text.len or !isLower2(text[k .. k + 2])) continue;
            const u = graphicsUnit(text[k .. k + 2]) orelse
                return ctx.fail(pos, "invalid unit in \\includegraphics");
            if (cand.big) return sizeToEm5(if (neg) -1 else 1, std.math.maxInt(i32), 1);
            var v = candTo1e6(text, cand);
            if (neg) v = -v;
            return sizeToEm5(v, u.mult, u.div);
        }
    }
    return ctx.fail(pos, "invalid size in \\includegraphics");
}

// ---------------------------------------------------------------------------
// `\text` bodies, `\genfrac`, `\smash`, `\rule`, `\substack`
// ---------------------------------------------------------------------------

/// Token → KaTeX `parseStringGroup` text (token `.text`
/// concatenation): `\foo` keeps its backslash, braces and `^_&`
/// pass through literally, `\\<newline>` is backslash + newline.
/// Markers vanish (zero-width sentinels); anything else
/// unreachable in these scans is skipped. `error.NoSpace` when
/// the option text outgrows the buffer (bounded input).
fn appendTokText(tok: Tok, buf: []u8, n: *usize) Error!void {
    switch (tok.kind) {
        .char => {
            var cbuf: [4]u8 = undefined;
            const m = std.unicode.utf8Encode(tok.cp, &cbuf) catch return error.NoSpace;
            if (n.* + m > buf.len) return error.NoSpace;
            @memcpy(buf[n.* .. n.* + m], cbuf[0..m]);
            n.* += m;
        },
        .ctrl => {
            if (n.* + 1 + tok.name.len > buf.len) return error.NoSpace;
            buf[n.*] = '\\';
            n.* += 1;
            @memcpy(buf[n.* .. n.* + tok.name.len], tok.name);
            n.* += tok.name.len;
        },
        .lbrace => {
            if (n.* + 1 > buf.len) return error.NoSpace;
            buf[n.*] = '{';
            n.* += 1;
        },
        .rbrace => {
            if (n.* + 1 > buf.len) return error.NoSpace;
            buf[n.*] = '}';
            n.* += 1;
        },
        .sup => {
            if (n.* + 1 > buf.len) return error.NoSpace;
            buf[n.*] = '^';
            n.* += 1;
        },
        .sub => {
            if (n.* + 1 > buf.len) return error.NoSpace;
            buf[n.*] = '_';
            n.* += 1;
        },
        .amp => {
            if (n.* + 1 > buf.len) return error.NoSpace;
            buf[n.*] = '&';
            n.* += 1;
        },
        .newline => {
            if (n.* + 2 > buf.len) return error.NoSpace;
            buf[n.*] = '\\';
            buf[n.* + 1] = '\n';
            n.* += 2;
        },
        else => {},
    }
}

/// ASCII whitespace plus U+00A0 (the JS `trim` set reachable
/// through our lexer: `keep_spaces` collapses runs to U+0020).
fn trimGraphicsWs(s: []const u8) []const u8 {
    var a: usize = 0;
    var b: usize = s.len;
    while (a < b) {
        if (s[a] == ' ' or s[a] == '\t' or s[a] == '\n' or s[a] == '\r' or
            s[a] == 0x0B or s[a] == 0x0C) a += 1 else if (a + 1 < b and s[a] == 0xC2 and s[a + 1] == 0xA0) a += 2 else break;
    }
    while (b > a) {
        if (s[b - 1] == ' ' or s[b - 1] == '\t' or s[b - 1] == '\n' or s[b - 1] == '\r' or
            s[b - 1] == 0x0B or s[b - 1] == 0x0C) b -= 1 else if (b - 1 > a and s[b - 2] == 0xC2 and s[b - 1] == 0xA0) b -= 2 else break;
    }
    return s[a..b];
}

/// Whitespace-ish raw token for `alt` value trimming (mirrors
/// `trimGraphicsWs` at the token level).
fn isGraphicsWsTok(tok: Tok) bool {
    if (tok.kind != .char) return false;
    return tok.cp == ' ' or tok.cp == '\t' or tok.cp == '\n' or tok.cp == '\r' or
        tok.cp == 0x0B or tok.cp == 0x0C or tok.cp == 0xA0;
}

/// Scan a `[...]` optional argument's raw tokens (KaTeX
/// `scanArgument(true)` + `parseStringGroup`): the `[` is already
/// consumed; `{...}` nest; the first depth-0 `]` ends; a depth-0
/// `}` errors; end of input wants `']'`. Spaces survive.
fn scanBracketArg(ctx: *ParseCtx) Error!Range {
    const saved = ctx.keep_spaces;
    ctx.keep_spaces = true;
    const start = try ctx.allocToks(0);
    var count: u16 = 0;
    var depth: u16 = 0;
    while (true) {
        const k = try ctx.next();
        switch (k.kind) {
            .end => {
                ctx.keep_spaces = saved;
                return ctx.fail(k.pos, "expected ']' before end of input");
            },
            .lbrace => {
                depth += 1;
                _ = try ctx.allocToks(1);
                ctx.toks[start + count] = k;
                count += 1;
            },
            .rbrace => {
                if (depth == 0) {
                    ctx.keep_spaces = saved;
                    return ctx.fail(k.pos, "extra '}' in optional argument");
                }
                depth -= 1;
                _ = try ctx.allocToks(1);
                ctx.toks[start + count] = k;
                count += 1;
            },
            .char => {
                if (k.cp == ']' and depth == 0) {
                    ctx.keep_spaces = saved;
                    return .{ .start = start, .len = count };
                }
                _ = try ctx.allocToks(1);
                ctx.toks[start + count] = k;
                count += 1;
            },
            else => {
                _ = try ctx.allocToks(1);
                ctx.toks[start + count] = k;
                count += 1;
            },
        }
    }
}

/// Scan the `{url}` argument (KaTeX undelimited `consumeArg` +
/// `parseStringGroup`): `{...}` groups nest with the outer pair
/// stripped (`{{a}}` → `{a}`); otherwise one raw token; a lone
/// `}` errors; end of input wants `'}'`. Spaces survive inside
/// braces. No `#` param interpretation, no macro expansion (the
/// `\href` precedent).
fn scanUrlArg(ctx: *ParseCtx) Error!Range {
    const t = try ctx.peek();
    if (t.kind == .lbrace) {
        _ = try ctx.next();
        const saved = ctx.keep_spaces;
        ctx.keep_spaces = true;
        const start = try ctx.allocToks(0);
        var count: u16 = 0;
        var depth: u16 = 0;
        while (true) {
            const k = try ctx.next();
            switch (k.kind) {
                .end => {
                    ctx.keep_spaces = saved;
                    return ctx.fail(k.pos, "expected '}' before end of input");
                },
                .lbrace => {
                    depth += 1;
                    _ = try ctx.allocToks(1);
                    ctx.toks[start + count] = k;
                    count += 1;
                },
                .rbrace => {
                    if (depth == 0) {
                        ctx.keep_spaces = saved;
                        return .{ .start = start, .len = count };
                    }
                    depth -= 1;
                    _ = try ctx.allocToks(1);
                    ctx.toks[start + count] = k;
                    count += 1;
                },
                else => {
                    _ = try ctx.allocToks(1);
                    ctx.toks[start + count] = k;
                    count += 1;
                },
            }
        }
    }
    _ = try ctx.next();
    if (t.kind == .end) return ctx.fail(t.pos, "expected argument");
    if (t.kind == .rbrace) return ctx.fail(t.pos, "extra '}'");
    const start = try ctx.allocToks(1);
    ctx.toks[start] = t;
    return .{ .start = start, .len = 1 };
}

const GraphicsOpt = struct {
    w: i32,
    h: i32,
    th: i32,
    alt: Range,
};

/// One comma segment of the option list. `=` splits with text
/// semantics (KaTeX `String.split`): anything but exactly one
/// `=` is silently skipped. Keys match trimmed; `alt` stores the
/// trimmed value token range, sizes parse via `graphicsSize`.
fn graphicsOptSeg(ctx: *ParseCtx, start: u16, len: usize, cmd_pos: u32, o: *GraphicsOpt) Error!void {
    if (len == 0) return;
    var eq: ?usize = null;
    var neq: usize = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const tk = ctx.toks[start + i];
        if (tk.kind == .char and tk.cp == '=') {
            neq += 1;
            eq = i;
        }
    }
    if (neq != 1) return;
    const ei = eq.?;
    var kbuf: [128]u8 = undefined;
    var kn: usize = 0;
    var j: usize = 0;
    while (j < ei) : (j += 1) try appendTokText(ctx.toks[start + j], &kbuf, &kn);
    const key = trimGraphicsWs(kbuf[0..kn]);
    if (std.mem.eql(u8, key, "alt")) {
        var vs = ei + 1;
        var ve = len;
        while (vs < ve and isGraphicsWsTok(ctx.toks[start + vs])) vs += 1;
        while (ve > vs and isGraphicsWsTok(ctx.toks[start + ve - 1])) ve -= 1;
        o.alt = .{ .start = @intCast(start + vs), .len = @intCast(ve - vs) };
        return;
    }
    var vbuf: [512]u8 = undefined;
    var vn: usize = 0;
    j = ei + 1;
    while (j < len) : (j += 1) try appendTokText(ctx.toks[start + j], &vbuf, &vn);
    const val = trimGraphicsWs(vbuf[0..vn]);
    if (std.mem.eql(u8, key, "width")) {
        o.w = try graphicsSize(val, cmd_pos, ctx);
        return;
    }
    if (std.mem.eql(u8, key, "height")) {
        o.h = try graphicsSize(val, cmd_pos, ctx);
        return;
    }
    if (std.mem.eql(u8, key, "totalheight")) {
        o.th = try graphicsSize(val, cmd_pos, ctx);
        return;
    }
    return ctx.fail(cmd_pos, "invalid key in \\includegraphics");
}

/// Split the scanned option tokens at depth-0 commas (KaTeX
/// `attributeStr.split(",")`) and fold the segments left to
/// right (later keys win).
fn parseGraphicsOpts(ctx: *ParseCtx, r: Range, cmd_pos: u32) Error!GraphicsOpt {
    var o = GraphicsOpt{
        .w = 0,
        .h = graphics_default_h,
        .th = 0,
        .alt = .{ .start = 0, .len = 0 },
    };
    var seg: usize = 0;
    while (true) {
        var end = seg;
        var depth: u16 = 0;
        while (end < r.len) {
            const tk = ctx.toks[r.start + end];
            if (tk.kind == .lbrace) {
                depth += 1;
            } else if (tk.kind == .rbrace) {
                if (depth > 0) depth -= 1;
            } else if (tk.kind == .char and tk.cp == ',' and depth == 0) {
                break;
            }
            end += 1;
        }
        try graphicsOptSeg(ctx, r.start + @as(u16, @intCast(seg)), end - seg, cmd_pos, &o);
        if (end >= r.len) break;
        seg = end + 1;
    }
    return o;
}

/// Braced token capture with `\text`-style validation of the braces.
/// Spaces survive the capture (text mode); the flag is restored after.
fn parseBracedToks(ctx: *ParseCtx, cmd: Tok, comptime need_brace: bool) Error!Range {
    const pk = try ctx.peek();
    if (pk.kind == .lbrace) {
        _ = try ctx.next();
        const prev = ctx.keep_spaces;
        ctx.keep_spaces = true;
        const r = ctx.captureToBrace(pk.pos) catch |e| {
            ctx.keep_spaces = prev;
            return e;
        };
        ctx.keep_spaces = prev;
        return r;
    }
    if (need_brace) return ctx.fail(cmd.pos, "expected '{'");
    return ctx.captureArg();
}

/// Token capture with spaces preserved (for `\url`).
fn captureSpacedArg(ctx: *ParseCtx) Error!Range {
    const prev = ctx.keep_spaces;
    ctx.keep_spaces = true;
    const r = ctx.captureArg() catch |e| {
        ctx.keep_spaces = prev;
        return e;
    };
    ctx.keep_spaces = prev;
    return r;
}

/// Color-spec capture (`\color`, `\textcolor`, boxes): like
/// `captureToBrace` but fully literal — no `#1` parameter processing
/// — so hex specs (`#f00`) survive. A lone no-argument user macro
/// (`\newcommand{\c}{red}\color{\c}{x}`) resolves to its body.
fn captureColorSpec(ctx: *ParseCtx) Error!Range {
    const t = try ctx.peek();
    if (t.kind != .lbrace) {
        const r = try ctx.captureArg();
        try validateColorSpec(ctx, r, ctx.toks[r.start].pos);
        return r;
    }
    _ = try ctx.next();
    const prev = ctx.keep_spaces;
    ctx.keep_spaces = true;
    var r = captureLiteral(ctx) catch |e| {
        ctx.keep_spaces = prev;
        return e;
    };
    ctx.keep_spaces = prev;
    if (r.len == 1) {
        const tk = ctx.toks[r.start];
        if (tk.kind == .ctrl) {
            if (ctx.findDef(tk.name)) |d| {
                if (!d.is_alias and d.nargs == 0) r = d.body;
            }
        }
    }
    try validateColorSpec(ctx, r, t.pos);
    return r;
}

fn isHexDigit(cp: u21) bool {
    return (cp >= '0' and cp <= '9') or
        (cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F');
}

fn isColorWord(cp: u21) bool {
    return (cp >= '0' and cp <= '9') or
        (cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z');
}

/// KaTeX color rule (probed): a bare word passes through unchecked,
/// `#` needs 3 or 6 hex digits, and everything else — empty specs,
/// spaces, `rgb(...)`, control sequences — is "Invalid color".
/// Failure carries the spec brace position (KaTeX parity).
fn hexVal(cp: u21) ?u32 {
    if (cp >= '0' and cp <= '9') return cp - '0';
    if (cp >= 'a' and cp <= 'f') return cp - 'a' + 10;
    if (cp >= 'A' and cp <= 'F') return cp - 'A' + 10;
    return null;
}

/// CSS basic keywords (plus common aliases) by 0xRRGGBB.
const named_colors = [_]struct { name: []const u8, rgb: u32 }{
    .{ .name = "black", .rgb = 0x000000 },
    .{ .name = "silver", .rgb = 0xC0C0C0 },
    .{ .name = "gray", .rgb = 0x808080 },
    .{ .name = "grey", .rgb = 0x808080 },
    .{ .name = "white", .rgb = 0xFFFFFF },
    .{ .name = "maroon", .rgb = 0x800000 },
    .{ .name = "red", .rgb = 0xFF0000 },
    .{ .name = "purple", .rgb = 0x800080 },
    .{ .name = "fuchsia", .rgb = 0xFF00FF },
    .{ .name = "magenta", .rgb = 0xFF00FF },
    .{ .name = "green", .rgb = 0x008000 },
    .{ .name = "lime", .rgb = 0x00FF00 },
    .{ .name = "olive", .rgb = 0x808000 },
    .{ .name = "yellow", .rgb = 0xFFFF00 },
    .{ .name = "navy", .rgb = 0x000080 },
    .{ .name = "blue", .rgb = 0x0000FF },
    .{ .name = "teal", .rgb = 0x008080 },
    .{ .name = "aqua", .rgb = 0x00FFFF },
    .{ .name = "cyan", .rgb = 0x00FFFF },
    .{ .name = "orange", .rgb = 0xFFA500 },
};

/// Resolve a validated color spec to 0xRRGGBBAA paint (issue #35):
/// `#rgb` / `#rrggbb` hex plus the CSS basic keywords
/// (case-insensitive). Other bare words are valid per KaTeX (the
/// browser resolves them) but have no native value here — null means
/// the host renders its ambient paint.
pub fn resolveColorSpec(pc: *const ParseCtx, r: Range) ?u32 {
    const toks = pc.toks[r.start .. r.start + r.len];
    if (toks.len == 0) return null;
    if (toks[0].kind == .char and toks[0].cp == '#') {
        var v: u32 = 0;
        if (toks.len == 4) {
            for (toks[1..]) |tk| {
                if (tk.kind != .char) return null;
                const d = hexVal(tk.cp) orelse return null;
                v = (v << 4) | d;
                v = (v << 4) | d;
            }
            return (v << 8) | 0xFF;
        }
        if (toks.len == 7) {
            for (toks[1..]) |tk| {
                if (tk.kind != .char) return null;
                const d = hexVal(tk.cp) orelse return null;
                v = (v << 4) | d;
            }
            return (v << 8) | 0xFF;
        }
        return null;
    }
    var buf: [16]u8 = undefined;
    if (toks.len > buf.len) return null;
    for (toks, 0..) |tk, i| {
        if (tk.kind != .char or tk.cp > 0x7F) return null;
        buf[i] = std.ascii.toLower(@as(u8, @intCast(tk.cp)));
    }
    const w = buf[0..toks.len];
    for (named_colors) |nc| {
        if (std.mem.eql(u8, nc.name, w)) return (nc.rgb << 8) | 0xFF;
    }
    return null;
}

fn validateColorSpec(ctx: *ParseCtx, r: Range, brace_pos: u32) Error!void {
    const toks = ctx.toks[r.start .. r.start + r.len];
    if (toks.len == 0) return ctx.fail(brace_pos, "invalid color");
    if (toks[0].kind == .char and toks[0].cp == '#') {
        const n = toks.len - 1;
        if (n != 3 and n != 6) return ctx.fail(brace_pos, "invalid color");
        for (toks[1..]) |tk| {
            if (tk.kind != .char or !isHexDigit(tk.cp))
                return ctx.fail(brace_pos, "invalid color");
        }
        return;
    }
    for (toks) |tk| {
        if (tk.kind != .char or !isColorWord(tk.cp))
            return ctx.fail(brace_pos, "invalid color");
    }
}

/// Capture tokens through the matching close brace with no
/// interpretation whatsoever. The opening `{` is already consumed.
fn captureLiteral(self: *ParseCtx) Error!Range {
    const start = try self.allocToks(0);
    var depth: u16 = 0;
    var count: u16 = 0;
    while (true) {
        const t = try self.next();
        switch (t.kind) {
            .end => return self.fail(t.pos, "expected '}' before end of input"),
            .lbrace => {
                depth += 1;
                _ = try self.allocToks(1);
                self.toks[start + count] = t;
                count += 1;
            },
            .rbrace => {
                if (depth == 0) return .{ .start = start, .len = count };
                depth -= 1;
                _ = try self.allocToks(1);
                self.toks[start + count] = t;
                count += 1;
            },
            else => {
                _ = try self.allocToks(1);
                self.toks[start + count] = t;
                count += 1;
            },
        }
    }
}

/// `\verb` / `\verb*`: the delimiter is the literal byte after the
/// command (an optional `*` toggles visible spaces). Content is raw —
/// no comments, no escapes — up to the next delimiter, and newlines
/// end the scan (KaTeX parity). Materialized as `.char` tokens in a
/// monospace text node, so downstream emitters need no new paths.
fn parseVerb(ctx: *ParseCtx, t: Tok) Error!Idx {
    // The delimiter scan reads raw source bytes at the lexer's cursor,
    // which is only meaningful for a freshly lexed token: expanded
    // tokens borrow definition bytes, and re-parsed ranges (markers)
    // leave the cursor after the whole construct.
    const tok_end = t.pos + 1 + @as(u32, @intCast(t.name.len));
    if (t.synth or ctx.npb > 0 or ctx.spos != tok_end)
        return ctx.fail(t.pos, "'\\verb' inside macro expansion is not supported");
    var p: usize = ctx.spos;
    var star = false;
    if (p < ctx.src.len and ctx.src[p] == '*') {
        star = true;
        p += 1;
    }
    if (p >= ctx.src.len)
        return ctx.fail(t.pos, "'\\verb' ended by end of line instead of matching delimiter");
    const dl = utf8Len(ctx.src[p]);
    if (dl == 0 or p + dl > ctx.src.len) {
        ctx.err_pos = @intCast(p);
        ctx.err_msg = "invalid utf-8";
        return error.Invalid;
    }
    const delim = decode(ctx.src[p .. p + dl]);
    p += dl;
    const start = try ctx.allocToks(0);
    var count: u16 = 0;
    while (true) {
        if (p >= ctx.src.len)
            return ctx.fail(t.pos, "'\\verb' ended by end of line instead of matching delimiter");
        const b = ctx.src[p];
        if (b == '\n')
            return ctx.fail(t.pos, "'\\verb' ended by end of line instead of matching delimiter");
        const l = utf8Len(b);
        if (l == 0 or p + l > ctx.src.len) {
            ctx.err_pos = @intCast(p);
            ctx.err_msg = "invalid utf-8";
            return error.Invalid;
        }
        const cp = decode(ctx.src[p .. p + l]);
        if (cp == delim) {
            p += l;
            break;
        }
        _ = try ctx.allocToks(1);
        ctx.toks[start + count] = .{
            .kind = .char,
            .cp = if (star and cp == ' ') 0x2423 else cp,
            .pos = @intCast(p),
        };
        count += 1;
        p += l;
    }
    ctx.spos = @intCast(p);
    return ctx.allocNode(.{ .text = .{
        .toks = .{ .start = start, .len = count },
        .fam = .tt,
    } });
}

/// One `captureArg`-shaped argument inside an already-captured token
/// array: a balanced `{...}` group (delimiters excluded from the
/// inner range) or a single token. Returns the inner token span plus
/// the index just past the argument. Structural tokens that cannot
/// stand alone (`.end`/`.marker`, a stray `.rbrace`, an unbalanced
/// group) are malformed (null) — the caller leaves the construct for
/// `checkTextToks` to reject.
fn arrayArg(ctx: *ParseCtx, base: usize, len: usize, at: usize) ?struct {
    inner_start: usize,
    inner_len: usize,
    end: usize,
} {
    if (at >= len) return null;
    const tk = ctx.toks[base + at];
    if (tk.kind == .lbrace) {
        var d: usize = 1;
        var e = at + 1;
        while (e < len and d > 0) : (e += 1) {
            const tk2 = ctx.toks[base + e];
            if (tk2.kind == .lbrace) d += 1 else if (tk2.kind == .rbrace) d -= 1;
        }
        if (d > 0) return null;
        return .{ .inner_start = at + 1, .inner_len = (e - 1) - (at + 1), .end = e };
    }
    switch (tk.kind) {
        .end, .marker, .rbrace => return null,
        else => return .{ .inner_start = at, .inner_len = 1, .end = at + 1 },
    }
}

/// Select the kept branch of two-argument selector macros in a flat
/// captured text range (KaTeX text-mode expansion parity, pinned
/// 0.18.7, issues #161/#163): `\\@firstoftwo` keeps its first
/// argument, `\\@secondoftwo` its second (mode-independent, like the
/// math-stream handlers), and `\\TextOrMath` keeps its first
/// argument in text contexts. With `math_side`, `\\TextOrMath` keeps
/// its second: `\\url`/`\\operatorname` arguments expand in math
/// mode in KaTeX (pinned probes), even though this engine validates
/// those captures as text afterwards. The dropped branch's tokens
/// are never copied (never parsed); only brace boundaries are
/// scanned. A malformed construct is left in place for
/// `checkTextToks` to reject. Repeats to fixpoint; every pass drops
/// at least the command token, so passes are bounded by the range
/// length. The subset profile returns the range untouched (these
/// names stay `Unsupported` there). Flat only: `\\text`-family
/// bodies resolve selectors in `collectTextPieces` instead, where
/// `$`/`\\(`/`\\)` math islands keep their mode.
fn selectBranchToks(ctx: *ParseCtx, r: Range, comptime math_side: bool) Error!Range {
    if (comptime active_profile != .full) return r;
    var work = r;
    while (true) {
        const base: usize = @as(usize, work.start);
        var found: ?struct { at: usize, inner_start: usize, inner_len: usize, end: usize } = null;
        var k: usize = 0;
        while (k < work.len) : (k += 1) {
            const tk = ctx.toks[base + k];
            if (tk.kind != .ctrl) continue;
            const is_first = tokNameEq(tk.name, "@firstoftwo");
            const is_second = tokNameEq(tk.name, "@secondoftwo");
            const is_tom = tokNameEq(tk.name, "TextOrMath");
            if (!is_first and !is_second and !is_tom) continue;
            const a1 = arrayArg(ctx, base, work.len, k + 1) orelse continue;
            const a2 = arrayArg(ctx, base, work.len, a1.end) orelse continue;
            const keep_b = is_second or (is_tom and math_side);
            const ai = if (keep_b) a2 else a1;
            found = .{ .at = k, .inner_start = ai.inner_start, .inner_len = ai.inner_len, .end = a2.end };
            break;
        }
        const f = found orelse return work;
        const rest = work.len - (f.end - f.at) + f.inner_len;
        const out = try ctx.allocToks(rest);
        const ob: usize = out;
        @memcpy(ctx.toks[ob .. ob + f.at], ctx.toks[base .. base + f.at]);
        @memcpy(ctx.toks[ob + f.at .. ob + f.at + f.inner_len], ctx.toks[base + f.inner_start .. base + f.inner_start + f.inner_len]);
        @memcpy(ctx.toks[ob + f.at + f.inner_len .. ob + rest], ctx.toks[base + f.end .. base + work.len]);
        work = .{ .start = out, .len = @intCast(rest) };
    }
}

fn checkTextToks(ctx: *ParseCtx, r: Range) Error!void {
    var i: u16 = 0;
    while (i < r.len) : (i += 1) {
        const tk = ctx.toks[r.start + i];
        switch (tk.kind) {
            .char, .lbrace, .rbrace, .newline => {
                // KaTeX re-enters math mode on `$` inside `\text`;
                // without math-in-text support the byte is rejected.
                if (tk.kind == .char and tk.cp == '$')
                    return ctx.fail(tk.pos, "can't use '$' in text mode");
            },
            .ctrl => {
                // Single-character escapes (`\%`, `\_`, ...), spacing,
                // accents, and (full profile) text-mode commands (`\i`,
                // `\textdollar`, ...) are allowed in text; math commands
                // are not.
                const is_text_cmd = if (comptime active_profile == .full)
                    symbols.lookupText(tk.name) != null or symbols.lookupTextArg(tk.name) != null
                else
                    false;
                if (tk.name.len != 1) {
                    if (!is_text_cmd)
                        return ctx.fail(tk.pos, "can't use math command in text mode");
                    continue;
                }
                const c = tk.name[0];
                switch (c) {
                    '{', '}', '%', '&', '#', '_', '$', ' ', ',', ':', ';', '!', '>', '~', '|', '\'', '`', '^', '"', '=', '.', 'u', 'v', 'H', 't', 'c', 'd', 'b', 'r' => {},
                    else => if (!is_text_cmd)
                        return ctx.fail(tk.pos, "can't use math command in text mode"),
                }
            },
            .sup, .sub => return ctx.fail(tk.pos, "can't use '^'/'_' in text mode"),
            .amp => return ctx.fail(tk.pos, "can't use '&' in text mode"),
            .param => return ctx.fail(tk.pos, "unexpected '#'"),
            .marker, .end => return ctx.fail(tk.pos, "unexpected end of text"),
        }
    }
}

/// Copy a token slice into the toks arena.
fn stashToks(ctx: *ParseCtx, toks: []const Tok) Error!Range {
    if (toks.len > 0xFFFF) return error.NoSpace;
    const s = try ctx.allocToks(toks.len);
    const base: usize = s;
    @memcpy(ctx.toks[base .. base + toks.len], toks);
    return .{ .start = s, .len = @intCast(toks.len) };
}

/// Flatten complete nested `\text{...}` groups in a captured token
/// range to their inner tokens (KaTeX renders nested text flat —
/// pinned 0.18.7 probes, issue #75). Repeats until no complete
/// group remains (each pass removes a wrapper, so passes are
/// bounded by the range length). A bare `\text` without a braced
/// group, or an unbalanced group, is left for the caller to reject.
fn spliceNestedText(ctx: *ParseCtx, r: Range) Error!Range {
    var work = r;
    while (true) {
        const base: usize = @as(usize, work.start);
        var found: ?struct { at: usize, end: usize } = null;
        var k: usize = 0;
        while (k < work.len) : (k += 1) {
            const tk = ctx.toks[base + k];
            if (tk.kind == .ctrl and tokNameEq(tk.name, "text") and k + 1 < work.len and
                ctx.toks[base + k + 1].kind == .lbrace)
            {
                var d: usize = 1;
                var e = k + 2;
                while (e < work.len and d > 0) : (e += 1) {
                    const tk2 = ctx.toks[base + e];
                    if (tk2.kind == .lbrace) d += 1 else if (tk2.kind == .rbrace) d -= 1;
                }
                if (d == 0) {
                    found = .{ .at = k, .end = e };
                    break;
                }
            }
        }
        const f = found orelse return work;
        // The splice drops exactly the wrapper (`\text`, `{`, `}`)
        // and keeps the inner tokens.
        const inner_len = f.end - (f.at + 2) - 1;
        const rest = work.len - 3;
        const out = try ctx.allocToks(rest);
        const ob: usize = out;
        @memcpy(ctx.toks[ob .. ob + f.at], ctx.toks[base .. base + f.at]);
        @memcpy(ctx.toks[ob + f.at .. ob + f.at + inner_len], ctx.toks[base + f.at + 2 .. base + f.end - 1]);
        @memcpy(ctx.toks[ob + f.at + inner_len .. ob + rest], ctx.toks[base + f.end .. base + work.len]);
        work = .{ .start = out, .len = @intCast(rest) };
    }
}

/// Index of the first `\tag` control token in a captured text
/// range, at any depth (KaTeX hoists `\tag` from text bodies even
/// nested in braces — pinned 0.18.7 probes, issue #75).
fn findTextTag(ctx: *ParseCtx, r: Range) ?usize {
    var k: usize = 0;
    while (k < r.len) : (k += 1) {
        const tk = ctx.toks[@as(usize, r.start) + k];
        if (tk.kind == .ctrl and tokNameEq(tk.name, "tag")) return k;
    }
    return null;
}

/// Hoist one `\tag` out of a captured text range: push its tokens
/// back and run the real `parseTag` (identical star/bare/braced
/// semantics, including "Multiple \tag"), returning the range with
/// the construct excised. `ti` indexes the `\tag` token.
fn hoistTextTag(ctx: *ParseCtx, r: Range, ti: usize) Error!Range {
    const base: usize = @as(usize, r.start);
    var j = ti + 1;
    // Optional star immediately after (parseTag peeks, no skipping).
    if (j < r.len and ctx.toks[base + j].kind == .char and ctx.toks[base + j].cp == '*') j += 1;
    // Argument end by parseBracedToks(false) rules: a braced group
    // or exactly one token (captureArg takes a single token, never
    // skipping spaces).
    var end: usize = undefined;
    if (j < r.len and ctx.toks[base + j].kind == .lbrace) {
        var depth: usize = 1;
        end = j + 1;
        while (end < r.len and depth > 0) : (end += 1) {
            const tk = ctx.toks[base + end];
            if (tk.kind == .lbrace) depth += 1 else if (tk.kind == .rbrace) depth -= 1;
        }
        // Captured ranges are brace-balanced by construction.
        if (depth > 0) return ctx.fail(ctx.toks[base + j].pos, "expected '}'");
    } else {
        if (j >= r.len) return ctx.fail(ctx.toks[base + ti].pos, "expected argument");
        end = j + 1;
    }
    // Push the construct back minus `\tag` itself (parseTag takes
    // the consumed control token and reads star/argument live).
    var k = end;
    while (k > ti + 1) {
        k -= 1;
        try ctx.push(ctx.toks[base + k]);
    }
    _ = try parseTag(ctx, ctx.toks[base + ti]);
    const rest = r.len - (end - ti);
    const out = try ctx.allocToks(rest);
    const obase: usize = out;
    @memcpy(ctx.toks[obase .. obase + ti], ctx.toks[base .. base + ti]);
    @memcpy(ctx.toks[obase + ti .. obase + rest], ctx.toks[base + end .. base + r.len]);
    return .{ .start = out, .len = @intCast(rest) };
}

/// One collected text-body piece: a literal token span (merged
/// with adjacent spans) or a parsed node (math segment, nested
/// group — both break merging, matching KaTeX's flat `mtext`
/// runs).
const TextPiece = union(enum) { span: Range, node: Idx };

/// Build a text node from captured body tokens (issues #75/#81):
/// `\tag` hoists from anywhere in the range (display) or rejects
/// (inline), nested `\text{...}` groups recurse with their own `$`
/// pairing, and `$` toggles math segments (KaTeX text-parser
/// parity, pinned 0.18.7). Adjacent literal spans merge into one
/// `.text` node (KaTeX renders nested text flat); math pieces parse
/// as textstyle formulas. Empty bodies become an empty group (the
/// bundle's `<mrow></mrow>`), and a single piece returns directly.
fn parseTextBody(ctx: *ParseCtx, depth: u8, toks: Range, fam: FontFam) Error!Idx {
    var work = toks;
    while (findTextTag(ctx, work)) |ti| {
        // Subset profile: `\tag` is a full-only name (the math-mode
        // call site gates it); fail bare `Unsupported` like the
        // subset gate, at the same contract.
        if (comptime active_profile == .subset) return error.Unsupported;
        work = try hoistTextTag(ctx, work, ti);
    }
    var pieces: [64]TextPiece = undefined;
    var np: usize = 0;
    try collectTextPieces(ctx, depth, work, fam, &pieces, &np);
    // Materialize: validate literal spans, keep nodes as-is.
    var out: [64]u16 = undefined;
    var no: usize = 0;
    for (pieces[0..np]) |p| {
        switch (p) {
            .span => |r| {
                try checkTextToks(ctx, r);
                if (no >= out.len) return error.NoSpace;
                out[no] = try ctx.allocNode(.{ .text = .{ .toks = r, .fam = fam } });
                no += 1;
            },
            .node => |id| {
                if (no >= out.len) return error.NoSpace;
                out[no] = id;
                no += 1;
            },
        }
    }
    if (no == 0) return finishGroup(ctx, &.{});
    if (no == 1) return out[0];
    const row = try ctx.allocKids(no);
    @memcpy(ctx.kids[row .. row + no], out[0..no]);
    return ctx.allocNode(.{ .group = .{ .start = row, .len = @intCast(no) } });
}

/// Append a literal span, merging into a trailing span piece
/// (KaTeX's flat `mtext` runs, pinned 0.18.7).
fn pushTextSpan(ctx: *ParseCtx, pieces: *[64]TextPiece, np: *usize, span: Range) Error!void {
    if (span.len == 0) return;
    if (np.* > 0) {
        switch (pieces.*[np.* - 1]) {
            .span => |prev| {
                const base: usize = @as(usize, prev.start);
                const add: usize = @as(usize, span.start);
                const total = prev.len + span.len;
                const out = try ctx.allocToks(total);
                const ob: usize = out;
                @memcpy(ctx.toks[ob .. ob + prev.len], ctx.toks[base .. base + prev.len]);
                @memcpy(ctx.toks[ob + prev.len .. ob + total], ctx.toks[add .. add + span.len]);
                pieces.*[np.* - 1] = .{ .span = .{ .start = out, .len = @intCast(total) } };
                return;
            },
            .node => {},
        }
    }
    if (np.* >= pieces.len) return error.NoSpace;
    pieces.*[np.*] = .{ .span = span };
    np.* += 1;
}

/// Collect the pieces of a tag-free text range: `$` pairs outside
/// control-led groups become math nodes; nested `\text{...}` groups
/// recurse into the same list (their inner `$` stays scoped —
/// pinned probes — while pure-text innards merge across); plain
/// groups pair `$` across. Ranges reference the arena; callers copy
/// when filtering.
fn collectTextPieces(
    ctx: *ParseCtx,
    depth: u8,
    work: Range,
    fam: FontFam,
    pieces: *[64]TextPiece,
    np: *usize,
) Error!void {
    const base: usize = @as(usize, work.start);
    var k: usize = 0;
    var start: usize = 0;
    // Flush the pending literal span [start, k) as one piece.
    const flush = struct {
        fn f(c: *ParseCtx, w: Range, from: usize, to: usize, ps: *[64]TextPiece, n: *usize) Error!void {
            if (from == to) return;
            const span = try stashToks(c, c.toks[@as(usize, w.start) + from .. @as(usize, w.start) + to]);
            try pushTextSpan(c, ps, n, span);
        }
    }.f;
    while (k < work.len) {
        const tk = ctx.toks[base + k];
        // An empty group unbound to a control token is an empty row
        // (KaTeX `<mrow></mrow>` parity, issue #75 — e.g. the residue
        // of a hoisted `\tag`); it breaks text merging, while
        // non-empty groups stay transparent.
        if (tk.kind == .lbrace and k + 1 < work.len and
            ctx.toks[base + k + 1].kind == .rbrace and
            (k == 0 or ctx.toks[base + k - 1].kind != .ctrl))
        {
            try flush(ctx, work, start, k, pieces, np);
            if (np.* >= pieces.len) return error.NoSpace;
            pieces.*[np.*] = .{ .node = try finishGroup(ctx, &.{}) };
            np.* += 1;
            k += 2;
            start = k;
            continue;
        }
        // Selector macros (issues #161/#163, text flavor):
        // `\\@firstoftwo` keeps its first argument, `\\@secondoftwo`
        // its second, `\\TextOrMath` its first. The kept branch
        // collects into this same piece list (so `$` islands and
        // nested `\\text` inside keep their meaning); the dropped
        // branch is skipped unread. A malformed construct falls
        // through to the literal arms below, and `checkTextToks`
        // rejects it. Subset profile: these names stay `Unsupported`
        // (validation rejects them; see `selectBranchToks`).
        if (full_only and tk.kind == .ctrl and
            (tokNameEq(tk.name, "@firstoftwo") or tokNameEq(tk.name, "@secondoftwo") or
            tokNameEq(tk.name, "TextOrMath")))
        {
            if (arrayArg(ctx, base, work.len, k + 1)) |a1| {
                if (arrayArg(ctx, base, work.len, a1.end)) |a2| {
                    try flush(ctx, work, start, k, pieces, np);
                    const ai = if (tokNameEq(tk.name, "@secondoftwo")) a2 else a1;
                    const kept = Range{
                        .start = @intCast(base + ai.inner_start),
                        .len = @intCast(ai.inner_len),
                    };
                    try collectTextPieces(ctx, depth, kept, fam, pieces, np);
                    k = a2.end;
                    start = a2.end;
                    continue;
                }
            }
        }
        // A braced group bound to a control token is atomic: nested
        // `\text{...}` recurses (same list, so merging still
        // applies); any other stays literal for `checkTextToks`.
        if (tk.kind == .ctrl and k + 1 < work.len and ctx.toks[base + k + 1].kind == .lbrace) {
            var d: usize = 1;
            var e = k + 2;
            while (e < work.len and d > 0) : (e += 1) {
                const tk2 = ctx.toks[base + e];
                if (tk2.kind == .lbrace) d += 1 else if (tk2.kind == .rbrace) d -= 1;
            }
            if (d > 0) return ctx.fail(tk.pos, "expected '}'");
            if (tokNameEq(tk.name, "text")) {
                // A nested `\text{...}` is its own unit: pure-text
                // innards splice their tokens for cross-boundary
                // merging (the bundle's flat `mtext`); anything with
                // math stays an opaque node (pinned 0.18.7 probes).
                try flush(ctx, work, start, k, pieces, np);
                const inner = try stashToks(ctx, ctx.toks[base + k + 2 .. base + e - 1]);
                const sub = try parseTextBody(ctx, depth, inner, fam);
                switch (ctx.nodes[sub]) {
                    .text => |st| try pushTextSpan(ctx, pieces, np, st.toks),
                    else => {
                        if (np.* >= pieces.len) return error.NoSpace;
                        pieces.*[np.*] = .{ .node = sub };
                        np.* += 1;
                    },
                }
                k = e;
                start = e;
                continue;
            }
            k = e;
            continue;
        }
        // `\(`...`\)` math islands (KaTeX parity, pinned 0.18.7,
        // issue #81): the same shape as the `$` islands below — the
        // inner range re-enters math at text style, so fractions and
        // nested `\text` work inside. An unclosed `\(` rejects (KaTeX
        // "Expected '\\)'"; the EOF-vs-opener position gap rides a
        // `katex_only` row like unclosed `$`). A stray `\)` never
        // opens an island, so it falls through to the span and
        // `checkTextToks` rejects it (KaTeX "Mismatched \\)" carries
        // no position, so the kind alone agrees).
        if (tk.kind == .ctrl and tokNameEq(tk.name, "(")) {
            var e = k + 1;
            var found = false;
            while (e < work.len) : (e += 1) {
                const tk2 = ctx.toks[base + e];
                if (tk2.kind == .ctrl and e + 1 < work.len and ctx.toks[base + e + 1].kind == .lbrace) {
                    var d: usize = 1;
                    e += 2;
                    while (e < work.len and d > 0) : (e += 1) {
                        const tk3 = ctx.toks[base + e];
                        if (tk3.kind == .lbrace) d += 1 else if (tk3.kind == .rbrace) d -= 1;
                    }
                    e -= 1;
                    continue;
                }
                if (tk2.kind == .ctrl and tokNameEq(tk2.name, ")")) {
                    found = true;
                    break;
                }
            }
            if (!found) return ctx.fail(tk.pos, "expected '\\)'");
            try flush(ctx, work, start, k, pieces, np);
            const seg = try stashToks(ctx, ctx.toks[base + k + 1 .. base + e]);
            const math = try parseTokenRange(ctx, depth, seg);
            if (np.* >= pieces.len) return error.NoSpace;
            pieces.*[np.*] = .{ .node = try ctx.allocNode(.{ .style = .{ .style = .T, .body = math } }) };
            np.* += 1;
            k = e + 1;
            start = k;
            continue;
        }
        if (tk.kind == .char and tk.cp == '$') {
            var e = k + 1;
            var found = false;
            while (e < work.len) : (e += 1) {
                const tk2 = ctx.toks[base + e];
                if (tk2.kind == .ctrl and e + 1 < work.len and ctx.toks[base + e + 1].kind == .lbrace) {
                    var d: usize = 1;
                    e += 2;
                    while (e < work.len and d > 0) : (e += 1) {
                        const tk3 = ctx.toks[base + e];
                        if (tk3.kind == .lbrace) d += 1 else if (tk3.kind == .rbrace) d -= 1;
                    }
                    e -= 1;
                    continue;
                }
                if (tk2.kind == .char and tk2.cp == '$') {
                    found = true;
                    break;
                }
            }
            // An unclosed `$` rejects (KaTeX "Expected '$'"; the
            // position gap rides a `katex_only` row, issue #81).
            if (!found) return ctx.fail(tk.pos, "expected '$'");
            try flush(ctx, work, start, k, pieces, np);
            const seg = try stashToks(ctx, ctx.toks[base + k + 1 .. base + e]);
            const math = try parseTokenRange(ctx, depth, seg);
            if (np.* >= pieces.len) return error.NoSpace;
            pieces.*[np.*] = .{ .node = try ctx.allocNode(.{ .style = .{ .style = .T, .body = math } }) };
            np.* += 1;
            k = e + 1;
            start = k;
            continue;
        }
        k += 1;
    }
    try flush(ctx, work, start, work.len, pieces, np);
}

fn parseGenfrac(ctx: *ParseCtx, depth: u8, cmd: Tok) Error!Idx {
    const l = try ctx.captureArg();
    const r = try ctx.captureArg();
    const thick_t = try ctx.captureArg();
    const style_t = try ctx.captureArg();
    const num_t = try ctx.captureArg();
    const den_t = try ctx.captureArg();
    const left = try singleDelimArg(ctx, l, cmd.pos);
    const right = try singleDelimArg(ctx, r, cmd.pos);
    // An explicit non-positive bar (`{0pt}`, `{-1pt}`) means NO rule
    // (issue #105, pinned 0.18.7 — barless like `\binom`); an EMPTY
    // bar keeps the default rule.
    var bar = true;
    var thick: i32 = 0;
    if (thick_t.len > 0) {
        thick = try dimenFromToks(ctx, thick_t, cmd.pos);
        if (thick <= 0) bar = false;
    }
    var fstyle: ?Style = null;
    if (style_t.len > 0) {
        if (style_t.len != 1) return ctx.fail(cmd.pos, "expected style number");
        const d = ctx.toks[style_t.start];
        if (d.kind != .char) return ctx.fail(cmd.pos, "expected style number");
        fstyle = switch (d.cp) {
            '0' => .D,
            '1' => .T,
            '2' => .S,
            '3' => .SS,
            else => return ctx.fail(cmd.pos, "expected style number"),
        };
    }
    const num = try parseTokenRange(ctx, depth, num_t);
    const den = try parseTokenRange(ctx, depth, den_t);
    var body = try ctx.allocNode(.{ .frac = .{
        .num = num,
        .den = den,
        .kind = .{ .bar = bar, .thick = thick },
    } });
    if (left != 0 or right != 0) {
        body = try ctx.allocNode(.{ .delim = .{ .left = left, .right = right, .body = body, .fixed = true } });
    }
    // The style `mstyle` sits outside delimiters (KaTeX parity).
    if (fstyle) |st| {
        body = try ctx.allocNode(.{ .style = .{ .style = st, .body = body } });
    }
    return body;
}

/// Display fraction: a style node outside the fraction (the `mstyle`
/// sits outside `\dbinom` parentheses too; layout inherits metrics).
fn parseStyledFrac(ctx: *ParseCtx, depth: u8, style: Style, kind: FracKind) Error!Idx {
    const f = try parseFracLike(ctx, depth, kind);
    return ctx.allocNode(.{ .style = .{ .style = style, .body = f } });
}

fn singleDelimArg(ctx: *ParseCtx, r: Range, pos: u32) Error!u21 {
    if (r.len == 0) return 0;
    if (r.len != 1) return ctx.fail(pos, "expected delimiter");
    const tk = ctx.toks[r.start];
    switch (tk.kind) {
        .char => {
            if (tk.cp == '.') return 0;
            return switch (tk.cp) {
                '(', ')', '[', ']', '{', '}', '|', '/', '<', '>' => tk.cp,
                else => ctx.fail(tk.pos, "expected delimiter"),
            };
        },
        .ctrl => {
            if (tk.name.len == 1) {
                const c = tk.name[0];
                switch (c) {
                    '|', '/' => return c,
                    '\\' => return 0x005C,
                    '{' => return '{',
                    '}' => return '}',
                    else => return ctx.fail(tk.pos, "expected delimiter"),
                }
            }
            if (symbols.lookupDelim(tk.name)) |d| return d.cp;
            return ctx.fail(tk.pos, "expected delimiter");
        },
        else => return ctx.fail(tk.pos, "expected delimiter"),
    }
}

/// Parse a captured token range as a formula (used by `\genfrac`).
fn parseTokenRange(ctx: *ParseCtx, depth: u8, r: Range) Error!Idx {
    try ctx.push(.{ .kind = .marker });
    var i = r.len;
    while (i > 0) {
        i -= 1;
        try ctx.push(ctx.toks[r.start + i]);
    }
    return parseFormula(ctx, depth, .top, null);
}

fn parseSmash(ctx: *ParseCtx, depth: u8) Error!Idx {
    // Default: smash both. `[t]` smashes the top only, `[b]` the depth
    // only, `[tb]` both explicitly. An empty or invalid option smashes
    // nothing (KaTeX parity: it breaks on the first invalid letter but
    // still accepts the command).
    var keep_t = false;
    var keep_b = false;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        var has_t = false;
        var has_b = false;
        var any = false;
        var valid = true;
        while (true) {
            const o = try ctx.next();
            if (o.kind == .char and o.cp == ']') break;
            if (o.kind == .end) return ctx.fail(pk.pos, "expected ']'");
            if (valid and o.kind == .char and (o.cp == 't' or o.cp == 'b')) {
                any = true;
                if (o.cp == 't') has_t = true else has_b = true;
            } else {
                valid = false;
            }
        }
        if (!valid or !any) {
            keep_t = true;
            keep_b = true;
        } else {
            keep_t = has_b and !has_t;
            keep_b = has_t and !has_b;
        }
    }
    const body = try parseGroupOrAtom(ctx, depth);
    return ctx.allocNode(.{ .smash = .{ .body = body, .keep_t = keep_t, .keep_b = keep_b } });
}

test "bare kern stops at the two-letter unit" {
    // KaTeX parity (sweep `hspace` case): `\kern2pt c` kerns 2pt and
    // leaves `c` for the formula.
    var ctx = ParseCtx.init("a\\kern2pt c");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 3), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "smash option leniency matches KaTeX" {
    // `[t]` smashes the top only; empty/invalid options smash nothing
    // but still parse.
    var c1 = ParseCtx.init("\\smash[t]{x}");
    const r1 = try parse(&c1, false);
    switch (c1.nodes[r1]) {
        .group => |g| switch (c1.nodes[c1.kids[g.start]]) {
            .smash => |s| {
                try std.testing.expect(!s.keep_t);
                try std.testing.expect(s.keep_b);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    var c2 = ParseCtx.init("\\smash[x]{y}");
    const r2 = try parse(&c2, false);
    switch (c2.nodes[r2]) {
        .group => |g| switch (c2.nodes[c2.kids[g.start]]) {
            .smash => |s| {
                try std.testing.expect(s.keep_t);
                try std.testing.expect(s.keep_b);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
}

fn parseRule(ctx: *ParseCtx, depth: u8) Error!Idx {
    // The bracket is a vertical RAISE (KaTeX `bottom:<raise>`), never
    // depth below the baseline (issue #37).
    var raise: i16 = 0;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        const r = try parseFormula(ctx, depth, .bracket, null);
        // The bracket frame yields a group; interpret a bare dimension
        // from its single atom when possible.
        raise = try ruleDimenFromGroup(ctx, r, pk.pos);
    }
    const w = try parseDimenArg(ctx, pk);
    const h = try parseDimenArg(ctx, pk);
    return ctx.allocNode(.{ .rule = .{ .w = w, .h = h, .raise = raise } });
}

fn ruleDimenFromGroup(ctx: *ParseCtx, g: Idx, pos: u32) Error!i16 {
    // Accept plain dimensions (`1pt`) or empty (= 0).
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    const kids: []const u16 = switch (ctx.nodes[g]) {
        .group => |gr| ctx.kids[gr.start .. gr.start + gr.len],
        else => return ctx.fail(pos, "expected dimension"),
    };
    for (kids) |id| {
        const a: u21 = switch (ctx.nodes[id]) {
            .atom => |at| at.cp,
            .space => continue,
            else => return ctx.fail(pos, "expected dimension"),
        };
        if (a > 0x7F) return ctx.fail(pos, "expected dimension");
        const c: u8 = @intCast(a);
        const ok = (c >= '0' and c <= '9') or c == '.' or c == '+' or c == '-' or
            (c >= 'a' and c <= 'z');
        if (!ok) return ctx.fail(pos, "expected dimension");
        if (n >= buf.len) return ctx.fail(pos, "dimension too long");
        buf[n] = c;
        n += 1;
    }
    if (n == 0) return 0;
    return dimenFromBytes(buf[0..n], pos, ctx);
}

/// `\substack{a \\ b \\ ...}`: centered rows, no `\begin`.
fn parseSubstack(ctx: *ParseCtx, depth: u8, cmd: Tok) Error!Idx {
    const pk = try ctx.peek();
    if (pk.kind != .lbrace) return ctx.fail(cmd.pos, "expected '{'");
    _ = try ctx.next();
    const rows_start = ctx.nrows;
    var rowbuf: [64]u16 = undefined;
    var nrow: usize = 0;
    var finished = false;
    while (!finished) {
        var buf: [512]u16 = undefined;
        var n: usize = 0;
        while (true) {
            const t = try ctx.peek();
            switch (t.kind) {
                .end => return ctx.fail(t.pos, "unexpected end of input"),
                .rbrace => {
                    _ = try ctx.next();
                    finished = true;
                    break;
                },
                .newline => {
                    _ = try ctx.next();
                    break;
                },
                .amp => return ctx.fail(t.pos, "unexpected '&'"),
                else => {
                    if (t.kind == .ctrl and isName(t, "cr")) {
                        _ = try ctx.next();
                        break;
                    }
                    // `\\` is the row separator (lexed as `.ctrl("\\")`).
                    if (t.kind == .ctrl and tokNameEq(t.name, "\\")) {
                        _ = try ctx.next();
                        break;
                    }
                    const maybe = try parseAtom(ctx, depth);
                    if (maybe) |id| {
                        if (n >= 512) return error.NoSpace;
                        buf[n] = id;
                        n += 1;
                    }
                },
            }
        }
        const cell = try finishGroup(ctx, buf[0..n]);
        const ks = try ctx.allocKids(1);
        ctx.kids[ks] = cell;
        if (nrow >= 64) return error.NoSpace;
        rowbuf[nrow] = try ctx.allocRow(.{ .start = ks, .len = 1 });
        nrow += 1;
    }
    return ctx.allocNode(.{ .substack = .{
        .start = rows_start,
        .len = @intCast(nrow),
    } });
}

// ---------------------------------------------------------------------------
// Macro definitions
// ---------------------------------------------------------------------------

/// `\newcommand{\name}[n]{body}` and siblings.
fn parseNewCommand(ctx: *ParseCtx, cmd: Tok, renew: bool, provide: bool) Error!void {
    const nt = try ctx.next();
    var name: []const u8 = "";
    if (nt.kind == .lbrace) {
        const inner = try ctx.next();
        if (inner.kind != .ctrl or inner.name.len == 0) return ctx.fail(inner.pos, "expected control sequence");
        name = inner.name;
        const cl = try ctx.next();
        if (cl.kind != .rbrace) return ctx.fail(cl.pos, "expected '}'");
    } else if (nt.kind == .ctrl and nt.name.len > 0) {
        name = nt.name;
    } else {
        return ctx.fail(nt.pos, "expected control sequence");
    }
    var nargs: u3 = 0;
    const pk = try ctx.peek();
    if (pk.kind == .char and pk.cp == '[') {
        _ = try ctx.next();
        const d = try ctx.next();
        if (d.kind != .char or d.cp < '0' or d.cp > '9') return ctx.fail(d.pos, "expected argument count");
        nargs = @intCast(d.cp - '0');
        const cl = try ctx.next();
        if (cl.kind != .char or cl.cp != ']') return ctx.fail(cl.pos, "expected ']'");
    }
    const body = try ctx.captureArg();
    // Validate parameter numbers at definition time.
    var i: u16 = 0;
    while (i < body.len) : (i += 1) {
        const bt = ctx.toks[body.start + i];
        if (bt.kind == .param and bt.arg >= nargs) {
            return ctx.fail(bt.pos, "macro parameter out of range");
        }
    }
    const defined = ctx.findDef(name) != null;
    const builtin = isBuiltin(name);
    if (provide) {
        if (defined or builtin) return;
    } else if (renew) {
        if (!defined and !builtin) return ctx.fail(cmd.pos, "not defined; use '\\newcommand'");
    } else {
        if (defined or builtin) return ctx.fail(cmd.pos, "already defined; use '\\renewcommand'");
    }
    if (defined) {
        const d = ctx.findDef(name).?;
        d.nargs = nargs;
        d.body = body;
        d.is_alias = false;
        return;
    }
    if (ctx.ndefs >= max_defs) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "too many macros";
        return error.ExpansionLimit;
    }
    ctx.defs[ctx.ndefs] = .{ .name = name, .nargs = nargs, .body = body };
    ctx.ndefs += 1;
}

/// `\def\name#1#2{body}`.
// Install (or overwrite) a definition. Shared by def/gdef and
// edef/xdef (every definition is already global).
fn storeDef(ctx: *ParseCtx, cmd: Tok, name: []const u8, nargs: u3, body: Range) Error!void {
    if (ctx.findDef(name)) |d| {
        d.nargs = nargs;
        d.body = body;
        d.is_alias = false;
        return;
    }
    if (ctx.ndefs >= max_defs) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "too many macros";
        return error.ExpansionLimit;
    }
    ctx.defs[ctx.ndefs] = .{ .name = name, .nargs = nargs, .body = body };
    ctx.ndefs += 1;
}

// edef/xdef (identical: every definition is already global). The
// body expands now against current definitions; parameters stay
// symbolic for use time (KaTeX parity).
fn parseEdef(ctx: *ParseCtx, cmd: Tok) Error!void {
    const nt = try ctx.next();
    if (nt.kind != .ctrl or nt.name.len == 0) return ctx.fail(nt.pos, "expected control sequence");
    var nargs: u3 = 0;
    while (true) {
        const q = try ctx.peek();
        if (q.kind == .char and q.cp == '#') {
            _ = try ctx.next();
            const d = try ctx.next();
            if (d.kind != .char or d.cp != '1' + @as(u21, nargs)) return ctx.fail(d.pos, "parameters must be sequential");
            nargs += 1;
            if (nargs > 9) return ctx.fail(d.pos, "too many parameters");
        } else break;
    }
    const raw = try ctx.captureArg();
    const body = try ctx.eagerExpand(raw);
    return storeDef(ctx, cmd, nt.name, nargs, body);
}

// The global prefix (KaTeX parity): the next token must open a
// definition (def family, let); anything else is rejected.
// Definitions are already global, so this is a parse-level gate.
fn parseGlobal(ctx: *ParseCtx, cmd: Tok) Error!void {
    _ = cmd;
    const nt = try ctx.next();
    if (nt.kind != .ctrl or nt.name.len <= 1) return ctx.fail(nt.pos, "invalid token after macro prefix");
    if (tokNameEq(nt.name, "global")) return parseGlobal(ctx, nt);
    if (tokNameEq(nt.name, "long")) return parseGlobal(ctx, nt);
    if (tokNameEq(nt.name, "def") or tokNameEq(nt.name, "gdef")) return parseDef(ctx, nt);
    if (tokNameEq(nt.name, "edef") or tokNameEq(nt.name, "xdef")) return parseEdef(ctx, nt);
    if (tokNameEq(nt.name, "let")) return parseLet(ctx, nt);
    return ctx.fail(nt.pos, "invalid token after macro prefix");
}

fn parseDef(ctx: *ParseCtx, cmd: Tok) Error!void {
    const nt = try ctx.next();
    if (nt.kind != .ctrl or nt.name.len == 0) return ctx.fail(nt.pos, "expected control sequence");
    var nargs: u3 = 0;
    while (true) {
        const q = try ctx.peek();
        if (q.kind == .char and q.cp == '#') {
            _ = try ctx.next();
            const d = try ctx.next();
            if (d.kind != .char or d.cp != '1' + @as(u21, nargs)) return ctx.fail(d.pos, "parameters must be sequential");
            nargs += 1;
            if (nargs > 9) return ctx.fail(d.pos, "too many parameters");
        } else break;
    }
    const body = try ctx.captureArg();
    return storeDef(ctx, cmd, nt.name, nargs, body);
}

/// KaTeX `letCommand` parity: an alias target with no macro
/// definition at bind time is marked `noexpand`, so the use site
/// surfaces it verbatim (later definitions do not capture it).
fn markAliasNoexpand(ctx: *ParseCtx, tgt: *Tok) void {
    tgt.noexpand = tgt.kind == .ctrl and ctx.findDef(tgt.name) == null;
}

/// `\let\new=\old` / `\let\new\old`.
fn parseLet(ctx: *ParseCtx, cmd: Tok) Error!void {
    const nt = try ctx.next();
    if (nt.kind != .ctrl or nt.name.len == 0) return ctx.fail(nt.pos, "expected control sequence");
    var tgt = try ctx.next();
    if (tgt.kind == .char and tgt.cp == '=') tgt = try ctx.next();
    if (tgt.kind == .end or tgt.kind == .param) return ctx.fail(tgt.pos, "expected token after '\\let'");
    markAliasNoexpand(ctx, &tgt);
    if (ctx.findDef(nt.name)) |d| {
        d.nargs = 0;
        d.is_alias = true;
        d.alias_tok = tgt;
        return;
    }
    if (ctx.ndefs >= max_defs) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "too many macros";
        return error.ExpansionLimit;
    }
    ctx.defs[ctx.ndefs] = .{ .name = nt.name, .nargs = 0, .body = .{ .start = 0, .len = 0 }, .is_alias = true, .alias_tok = tgt };
    ctx.ndefs += 1;
}

/// `\futurelet<cs><tok><tok>` (KaTeX def.ts): bind `<cs>` to the
/// second token without expanding anything, then reparse from the
/// first. Undefined tokens bind fine (like `\let`); they fail at
/// their own positions when reparsed, matching the bundle.
fn parseFuturelet(ctx: *ParseCtx, cmd: Tok) Error!void {
    const nt = try ctx.next();
    // Any control sequence binds, including `\{`-style singletons
    // (KaTeX `checkControlSequence` only rejects non-ctrl tokens
    // like bare braces, which never arrive here as `.ctrl`).
    if (nt.kind != .ctrl or nt.name.len == 0) {
        return ctx.fail(nt.pos, "expected control sequence");
    }
    // `.end` binds like any token (KaTeX `popToken` past input yields
    // EOF, which then ends the parse); only `.param` is rejected here.
    const mid = try ctx.next();
    if (mid.kind == .param) return ctx.fail(mid.pos, "unexpected token");
    var tok = try ctx.next();
    if (tok.kind == .param) return ctx.fail(tok.pos, "unexpected token");
    markAliasNoexpand(ctx, &tok);
    if (ctx.findDef(nt.name)) |d| {
        d.nargs = 0;
        d.is_alias = true;
        d.alias_tok = tok;
    } else {
        if (ctx.ndefs >= max_defs) {
            ctx.err_pos = cmd.pos;
            ctx.err_msg = "too many macros";
            return error.ExpansionLimit;
        }
        ctx.defs[ctx.ndefs] = .{ .name = nt.name, .nargs = 0, .body = .{ .start = 0, .len = 0 }, .is_alias = true, .alias_tok = tok };
        ctx.ndefs += 1;
    }
    try ctx.push(tok);
    try ctx.push(mid);
}


/// Names the engine implements natively (for `\newcommand` guards).
fn isBuiltin(name: []const u8) bool {
    // Every stripped command counts as defined (KaTeX `\newcommand`
    // refuses them, `\renewcommand` accepts them); consulting the
    // gate tables keeps this in sync for free.
    if (isFullOnlyCtrlName(name)) return true;
    if (isFullOnlyDefName(name)) return true;
    if (symbols.lookup(name) != null) return true;
    if (symbols.lookupDelim(name) != null) return true;
    if (symbols.lookupAccent(name) != null) return true;
    if (isStyleName(name)) return true;
    if (fontFamFor(name) != null) return true;
    if (parseOverName(name) != null) return true;
    if (isBigName(name)) return true;
    const prims: []const []const u8 = &.{
        "frac", "dfrac", "tfrac", "cfrac", "binom", "dbinom", "genfrac",
        "sqrt", "left", "right", "middle", "begin", "end", "hline", "cr",
        "bgroup", "egroup",
        "text", "mbox", "boldsymbol", "pmb", "vcenter", "color", "href", "url", "includegraphics",
        "htmlClass",
        "htmlId", "htmlStyle", "htmlData", "operatorname", "substack",
        "mathchoice", "smash", "raisebox", "rule", "boxed", "fbox",
        "KaTeX", "LaTeX", "TeX", "operatornamewithlimits", "mathstrut",
        "bra", "ket", "Bra", "Ket", "braket", "Braket",
        "set", "Set", "nonumber", "notag",
        "phantom", "hphantom", "vphantom", "llap", "rlap", "clap",
        "cancel", "bcancel", "sout", "phase", "textcircled", "quad", "qquad", "enskip", "hspace", "vspace",
        "kern", "mkern", "mskip", "hskip", "newcommand", "renewcommand",
        "providecommand", "def", "gdef", "edef", "xdef", "global", "long", "relax",
        "allowbreak", "nobreak", "nobreakspace", "space", "noexpand", "expandafter",
        "futurelet", "let", "over", "atop", "choose", "brace",
        "brack", "limits", "nolimits", "not", "overset", "underset", "stackrel",
        "tag",
    };
    for (prims) |p| if (tokNameEq(p, name)) return true;
    const envs: []const []const u8 = &.{
        "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix",
        "smallmatrix", "array", "aligned", "alignedat", "cases", "dcases",
        "drcases", "rcases", "gathered", "subarray",
        "align", "alignat", "equation", "gather", "split", "CD",
    };
    for (envs) |e| if (tokNameEq(e, name)) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Environments
// ---------------------------------------------------------------------------

/// Envs whose MathML table owns equation-number columns (shared
/// with `mathml.zig` and the `.numbered` computation below): only
/// these adopt a pending tag into a row. `split`, `CD`, and the
/// matrix family leave it pending (pinned 0.18.7, issue #75).
pub fn numEnvKind(kind: EnvKind) bool {
    return switch (kind) {
        .alignenv, .alignat, .equation, .gather => true,
        else => false,
    };
}

fn parseEnv(ctx: *ParseCtx, depth: u8, cmd: Tok) Error!Idx {
    // Environment name: `{matrix}` — letter chars.
    const lb = try ctx.next();
    if (lb.kind != .lbrace) return ctx.fail(lb.pos, "expected '{' after '\\begin'");
    var nbuf: [40]u8 = undefined;
    var nn: usize = 0;
    while (true) {
        const q = try ctx.next();
        if (q.kind == .rbrace) break;
        if (q.kind != .char or q.cp > 0x7F) return ctx.fail(q.pos, "expected environment name");
        const c: u8 = @intCast(q.cp);
        // A trailing `*` rides along raw (the `\end` check below
        // compares raw names, so begin/end stars must match exactly).
        if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '*')) return ctx.fail(q.pos, "expected environment name");
        if (nn >= nbuf.len) return ctx.fail(q.pos, "environment name too long");
        nbuf[nn] = c;
        nn += 1;
    }
    // KaTeX amsmath parity: the six matrix envs take a trailing star
    // (same rendering; starred forms take one optional [l|c|r] column
    // alignment below). A star anywhere else is unknown — KaTeX
    // rejects `aligned*`, `cases*`, bare `*` the same way.
    const starred = nn > 0 and nbuf[nn - 1] == '*';
    const base = if (starred) nbuf[0 .. nn - 1] else nbuf[0..nn];
    const kind: EnvKind = if (tokNameEq(base, "matrix"))
        .matrix
    else if (tokNameEq(base, "pmatrix"))
        .pmatrix
    else if (tokNameEq(base, "bmatrix"))
        .bmatrix
    else if (tokNameEq(base, "Bmatrix"))
        .Bmatrix
    else if (tokNameEq(base, "vmatrix"))
        .vmatrix
    else if (tokNameEq(base, "Vmatrix"))
        .Vmatrix
    else if (tokNameEq(base, "smallmatrix"))
        .smallmatrix
    else if (tokNameEq(base, "array"))
        .array
    else if (tokNameEq(base, "aligned"))
        .aligned
    else if (tokNameEq(base, "alignedat"))
        .alignedat
    else if (tokNameEq(base, "cases"))
        .cases
    else if (tokNameEq(base, "dcases"))
        .dcases
    else if (tokNameEq(base, "drcases"))
        .drcases
    else if (tokNameEq(base, "rcases"))
        .rcases
    else if (tokNameEq(base, "gathered"))
        .gathered
    else if (tokNameEq(base, "subarray"))
        .subarray
    else if (tokNameEq(base, "align"))
        .alignenv
    else if (tokNameEq(base, "alignat"))
        .alignat
    else if (tokNameEq(base, "equation"))
        .equation
    else if (tokNameEq(base, "gather"))
        .gather
    else if (tokNameEq(base, "split"))
        .split
    else if (tokNameEq(base, "CD"))
        .cd
    else
        // KaTeX parity: reported at the `{name}` group opener.
        return ctx.fail(lb.pos, "unknown environment");
    // Display-only top-level environments (KaTeX amsmath parity,
    // issues #83/#85/#86/#87/#90): `align`, `alignat`, `equation`,
    // `gather`, `split`, `CD` reject inline with KaTeX's message,
    // reported at `\begin` (matches the pinned-bundle position).
    const display_only = switch (kind) {
        .alignenv, .alignat, .equation, .gather, .split, .cd => true,
        else => false,
    };
    if (display_only and !ctx.display) {
        ctx.err_pos = cmd.pos;
        ctx.err_msg = "can be used only in display mode";
        return error.Invalid;
    }
    const matrix_star = starred and switch (kind) {
        .matrix, .pmatrix, .bmatrix, .Bmatrix, .vmatrix, .Vmatrix => true,
        else => false,
    };
    // KaTeX parity: starred matrix envs share rendering; starred
    // display envs (`align*`, `alignat*`, `equation*`, `gather*`)
    // drop the number column. A star anywhere else is unknown.
    const display_star = starred and switch (kind) {
        .alignenv, .alignat, .equation, .gather => true,
        else => false,
    };
    if (starred and !matrix_star and !display_star) return ctx.fail(lb.pos, "unknown environment");

    // Column spec for `{array}` / `{alignedat}`.
    var spec: [16]u16 = undefined;
    var nspec: usize = 0;
    if (kind == .array) {
        const sl = try ctx.next();
        if (sl.kind != .lbrace) return ctx.fail(sl.pos, "expected column spec");
        while (true) {
            const q = try ctx.next();
            if (q.kind == .rbrace) break;
            if (q.kind != .char) return ctx.fail(q.pos, "expected column spec");
            const code: u16 = switch (q.cp) {
                'l' => 0,
                'c' => 1,
                'r' => 2,
                '|' => 3,
                else => return ctx.fail(q.pos, "expected column spec"),
            };
            if (nspec >= spec.len) return ctx.fail(q.pos, "too many columns");
            spec[nspec] = code;
            nspec += 1;
        }
        if (nspec == 0) return ctx.fail(cmd.pos, "empty column spec");
    } else if (kind == .alignedat or kind == .alignat) {
        const sl = try ctx.next();
        if (sl.kind != .lbrace) return ctx.fail(sl.pos, "expected column count");
        var count: usize = 0;
        var any = false;
        while (true) {
            const q = try ctx.next();
            if (q.kind == .rbrace) break;
            if (q.kind != .char or q.cp < '0' or q.cp > '9') return ctx.fail(q.pos, "expected column count");
            count = count * 10 + (q.cp - '0');
            any = true;
        }
        if (!any or count == 0 or count > 8) return ctx.fail(cmd.pos, "expected column count");
        // rl pairs.
        var k: usize = 0;
        while (k < count) : (k += 1) {
            if (nspec + 2 > spec.len) return ctx.fail(cmd.pos, "too many columns");
            spec[nspec] = 2;
            spec[nspec + 1] = 0;
            nspec += 2;
        }
    } else if (kind == .subarray) {
        // Required single-letter alignment (KaTeX parity, issue #73):
        // `{c}`/`{l}`, or bare `c`/`l`. Every group char must agree
        // (`{cc}` centers, `{cl}` rejects); `{}` defaults centered.
        // Anything else rejects like KaTeX ("Unknown column
        // alignment"); the layout column-count error below covers `&`.
        const a = try ctx.next();
        var ac: u8 = 'c';
        if (a.kind == .lbrace) {
            var any = false;
            while (true) {
                const q = try ctx.next();
                if (q.kind == .rbrace) break;
                if (q.kind != .char or (q.cp != 'c' and q.cp != 'l'))
                    return ctx.fail(q.pos, "unknown column alignment");
                if (any and q.cp != @as(u21, ac)) return ctx.fail(q.pos, "expected column alignment");
                ac = @intCast(q.cp);
                any = true;
            }
        } else if (a.kind == .char and (a.cp == 'c' or a.cp == 'l')) {
            ac = @intCast(a.cp);
        } else return ctx.fail(a.pos, "unknown column alignment");
        spec[0] = if (ac == 'l') @as(u16, 0) else 1;
        nspec = 1;
    }
    if (matrix_star) {
        // One optional [l|c|r] alignment for every column (default
        // centered): stored as a single spec code, expanded by
        // layoutEnv. KaTeX parity: unknown letters reject.
        spec[0] = 1;
        nspec = 1;
        const pk = try ctx.peek();
        if (pk.kind == .char and pk.cp == '[') {
            _ = try ctx.next();
            const a = try ctx.next();
            spec[0] = if (a.kind == .char) switch (a.cp) {
                'l' => @as(u16, 0),
                'c' => 1,
                'r' => 2,
                else => return ctx.fail(a.pos, "expected column alignment"),
            } else return ctx.fail(a.pos, "expected column alignment");
            const cl = try ctx.next();
            if (cl.kind != .char or cl.cp != ']') return ctx.fail(cl.pos, "expected ']'");
        }
    }

    ctx.in_env += 1;
    // `\nonumber` is row-scoped (KaTeX resets `\@eqnsw` per row):
    // a nested env neither inherits nor leaks the outer row's flag.
    const saved_nonumber = ctx.row_nonumber;
    ctx.row_nonumber = false;
    const saved_tagged = ctx.row_tagged;
    ctx.row_tagged = false;
    // Row spans are stashed locally and materialized densely at the
    // end: nested environments allocate pool rows while cells parse,
    // so the pool is not contiguous mid-parse.
    var spans: [64]Row = undefined;
    var nspans: usize = 0;
    var rowbuf: [64]u16 = undefined;
    var nrowbuf: usize = 0;
    var done = false;
    while (!done) {
        // KaTeX `getHLines` parity (issue #33): rule commands opening
        // a row become their own gap rows, in order. Anywhere else in
        // a row they are misplaced (rejected inside `parseCell`).
        var pending: [8]bool = undefined;
        var npending: usize = 0;
        while (nrowbuf == 0) {
            const pk = try ctx.peek();
            if (pk.kind != .ctrl) break;
            const dash: bool = if (tokNameEq(pk.name, "hline"))
                false
            else if (tokNameEq(pk.name, "hdashline"))
                true
            else
                break;
            if (npending >= pending.len) return error.NoSpace;
            pending[npending] = dash;
            npending += 1;
            _ = try ctx.next();
        }
        const c = try parseCell(ctx, depth);
        for (pending[0..npending]) |dash| {
            if (nspans >= 64) return error.NoSpace;
            const hnode = try ctx.allocNode(.{ .hline = .{ .dashed = dash } });
            const hs = try ctx.allocKids(1);
            ctx.kids[hs] = hnode;
            spans[nspans] = .{ .start = hs, .len = 1 };
            nspans += 1;
        }
        if (nrowbuf >= 64) return error.NoSpace;
        // A trailing rule row takes no content row after it (`\hline`
        // before `\end` is a bottom border, not a border plus an
        // empty row).
        const empty_trailer = npending > 0 and nspans > 0 and
            (c.term == .end or c.term == .right) and isEmptyCellGroup(ctx, c.cell);
        if (!empty_trailer) {
            // amsmath parity (`\start@aligned`): every second cell of
            // an aligned row opens with an empty group so a leading
            // operator keeps binary spacing (and its MathML row).
            // Applies to the top-level `align`/`alignat`/`split`
            // twins, which share the rl-pair layout.
            var cell = c.cell;
            if ((kind == .aligned or kind == .alignedat or kind == .alignenv or
                kind == .alignat or kind == .split) and nrowbuf % 2 == 1)
            {
                cell = try prependEmptyGroup(ctx, cell);
            }
            rowbuf[nrowbuf] = cell;
            nrowbuf += 1;
        }
        switch (c.term) {
            .amp => {
                // KaTeX parity (issue #86): `equation` is a single
                // column — `&` rejects ("Too many tab characters").
                if (kind == .equation) {
                    ctx.err_pos = c.term_pos;
                    ctx.err_msg = "too many tab characters";
                    return error.Invalid;
                }
            },
            .newline => {
                if (nspans >= 64) return error.NoSpace;
                spans[nspans] = try stashRow(ctx, rowbuf[0..nrowbuf]);
                spans[nspans].nonumber = ctx.row_nonumber;
                spans[nspans].tagged = ctx.row_tagged;
                if (ctx.row_tagged and numEnvKind(kind)) ctx.tag_adopted = true;
                ctx.row_nonumber = false;
                // Numbering rows consume a pending tag; other envs
                // let it leak to the enclosing row (issue #75).
                if (numEnvKind(kind)) ctx.row_tagged = false;
                nspans += 1;
                nrowbuf = 0;
            },
            .end, .right => {
                // `\end{name}` — consume and verify. Errors report at
                // the `\end` (KaTeX parity).
                const etok = try ctx.next(); // \end
                const elb = try ctx.next();
                if (elb.kind != .lbrace) return ctx.fail(elb.pos, "expected '{' after '\\end'");
                var ebuf: [32]u8 = undefined;
                var en: usize = 0;
                while (true) {
                    const q = try ctx.next();
                    if (q.kind == .rbrace) break;
                    if (q.kind != .char or q.cp > 0x7F) return ctx.fail(q.pos, "expected environment name");
                    if (en >= ebuf.len) return ctx.fail(q.pos, "environment name too long");
                    ebuf[en] = @intCast(q.cp);
                    en += 1;
                }
                if (!tokNameEq(ebuf[0..en], nbuf[0..nn])) return ctx.fail(etok.pos, "mismatched '\\end'");
                if (c.term == .right) return ctx.fail(etok.pos, "unexpected '\\right'");
                // Final row (may be empty after a trailing `\\`).
                if (nrowbuf > 0 or nspans == 0) {
                    if (nspans >= 64) return error.NoSpace;
                    spans[nspans] = try stashRow(ctx, rowbuf[0..nrowbuf]);
                    spans[nspans].nonumber = ctx.row_nonumber;
                    spans[nspans].tagged = ctx.row_tagged;
                    if (ctx.row_tagged and numEnvKind(kind)) ctx.tag_adopted = true;
                    ctx.row_nonumber = false;
                    // Numbering rows consume a pending tag (see above).
                    if (numEnvKind(kind)) ctx.row_tagged = false;
                    nspans += 1;
                    nrowbuf = 0;
                }
                done = true;
            },
        }
    }
    // A tag seen before begin (a leading outside-tag) belongs to
    // row 0 when no row inside claimed one; a trailing outside-tag
    // arrives after this point and marks nothing (pinned 0.18.7,
    // issue #75).
    if (saved_tagged) {
        var any_tagged = false;
        for (spans[0..nspans]) |s| any_tagged = any_tagged or s.tagged;
        if (!any_tagged and nspans > 0) {
            spans[0].tagged = true;
            if (numEnvKind(kind)) ctx.tag_adopted = true;
        }
    }
    ctx.in_env -= 1;
    ctx.row_nonumber = saved_nonumber;
    // A tag seen inside a non-numbering env stays pending for the
    // enclosing row (textual containment, issue #75); numbering rows
    // consume it when they close, so OR (never clear) here.
    ctx.row_tagged = saved_tagged or ctx.row_tagged;
    if (kind == .cd) {
        // amscd assembly (KaTeX `parseCD` parity, issue #85):
        // `&` never separates CD columns (the generic loop above
        // may have split some), so each row's cell groups flatten
        // into one item list and re-split at `@` arrows.
        var r: usize = 0;
        while (r < nspans) : (r += 1) {
            spans[r] = try assembleCDRow(ctx, spans[r], r % 2 == 1, cmd.pos);
        }
        // KaTeX unconditionally pushes a final empty row after the
        // loop (every CD table ends in `<mtr></mtr>`).
        if (nspans >= 64) return error.NoSpace;
        spans[nspans] = try stashRow(ctx, &.{});
        nspans += 1;
    }
    // Materialize rows densely now that nested parsing is done.
    const rows_start = ctx.nrows;
    for (spans[0..nspans]) |sp| _ = try ctx.allocRow(sp);
    const spec_start = try ctx.allocKids(nspec);
    @memcpy(ctx.kids[spec_start .. spec_start + nspec], spec[0..nspec]);
    const env_id = try ctx.allocNode(.{ .env = .{
        .kind = kind,
        .rows_start = rows_start,
        .rows_len = @intCast(nspans),
        .spec_start = spec_start,
        .spec_len = @intCast(nspec),
        // Unstarred top-level display envs keep KaTeX's leading
        // number/glue column (issues #83/#86/#87).
        .numbered = numEnvKind(kind) and !display_star,
    } });
    // Delimiter pairing for matrix variants. `cases` is a leftright
    // with a null right delimiter (KaTeX parity: no trailing mo).
    const fence: ?struct { l: u21, r: u21 } = switch (kind) {
        .pmatrix => .{ .l = '(', .r = ')' },
        .bmatrix => .{ .l = '[', .r = ']' },
        .Bmatrix => .{ .l = '{', .r = '}' },
        .vmatrix => .{ .l = '|', .r = '|' },
        .Vmatrix => .{ .l = 0x2016, .r = 0x2016 },
        .cases => .{ .l = '{', .r = 0 },
        .dcases => .{ .l = '{', .r = 0 },
        .drcases => .{ .l = 0, .r = '}' },
        .rcases => .{ .l = 0, .r = '}' },
        else => null,
    };
    if (fence) |f| {
        return ctx.allocNode(.{ .delim = .{ .left = f.l, .right = f.r, .body = env_id } });
    }
    return env_id;
}

/// Codepoint of an `.atom` node, else null (CD arrow scan).
fn cdAtomCp(ctx: *ParseCtx, id: Idx) ?u21 {
    return switch (ctx.nodes[id]) {
        .atom => |a| a.cp,
        else => null,
    };
}

/// True for a bare `@` atom starting a CD arrow (KaTeX
/// `isStartOfArrow`: a textord `@`, i.e. top-level, never nested).
fn cdIsAt(ctx: *ParseCtx, id: Idx) bool {
    return cdAtomCp(ctx, id) == '@';
}

/// Parse one CD arrow; `i` points at `@` on entry and past the last
/// consumed item on exit. Labels collect parsed nodes (issue #85).
fn parseCDArrow(ctx: *ParseCtx, items: []const u16, i: *usize, pos: u32) Error!Idx {
    i.* += 1;
    if (i.* >= items.len) return ctx.fail(pos, "expected arrow after '@'");
    const ac = cdAtomCp(ctx, items[i.*]) orelse {
        return ctx.fail(pos, "expected one of \"<>AV=|.\" after @");
    };
    const arrow_pos = pos;
    switch (ac) {
        '>', '<', 'A', 'V' => {
            // Two labels, each terminated by the arrow character
            // (KaTeX `parseCD`: `@>{over}>{under}>`). A nested `@`
            // or a missing terminator fails like the bundle.
            var labs: [2]Idx = undefined;
            var li: usize = 0;
            while (li < 2) : (li += 1) {
                var lbuf: [256]u16 = undefined;
                var nlab: usize = 0;
                while (true) {
                    i.* += 1;
                    if (i.* >= items.len) return ctx.fail(arrow_pos, "missing arrow character to complete a CD arrow");
                    if (cdIsAt(ctx, items[i.*])) return ctx.fail(arrow_pos, "missing arrow character to complete a CD arrow");
                    if (cdAtomCp(ctx, items[i.*]) == ac) break;
                    if (nlab >= lbuf.len) return error.NoSpace;
                    lbuf[nlab] = items[i.*];
                    nlab += 1;
                }
                labs[li] = try finishGroup(ctx, lbuf[0..nlab]);
            }
            i.* += 1;
            if (ac == '>' or ac == '<') {
                // Horizontal arrows are extensible with over/under
                // labels (the `\xrightarrow`/`\xleftarrow` shape).
                // KaTeX always passes both labels (possibly empty),
                // so its MathML is always `munderover` — mirror that
                // exactly rather than dropping empty labels.
                return ctx.allocNode(.{ .over = .{
                    .kind = if (ac == '>') .xright else .xleft,
                    .nucleus = NONE,
                    .extra = labs[0],
                    .under = labs[1],
                } });
            }
            // Vertical arrows (`\Big\uparrow`/`\Big\downarrow` with
            // `\cdleft`/`\cdright` side labels and a `\cdparent`
            // row, KaTeX `cdArrow`): the cell groups left label,
            // arrow, right label in order.
            const big = try ctx.allocNode(.{ .big = .{
                .cp = if (ac == 'A') @as(u21, 0x2191) else @as(u21, 0x2193),
                .level = 1,
                .class = .Ord,
            } });
            const left = try ctx.allocNode(.{ .cdlabel = .{ .body = labs[0], .left = true } });
            const right = try ctx.allocNode(.{ .cdlabel = .{ .body = labs[1], .left = false } });
            const inner = [_]u16{ left, big, right };
            const frag = try finishGroup(ctx, &inner);
            const outer = [_]u16{frag};
            return finishGroup(ctx, &outer);
        },
        '=' => {
            // KaTeX `cdArrow` calls `\cdlongequal` with no labels:
            // the MathML is `mover` plus one bare `mpadded` (the
            // xarrow emitter's both-missing arm), never an `mrow`.
            i.* += 1;
            return ctx.allocNode(.{ .over = .{
                .kind = .xlongequal,
                .nucleus = NONE,
                .extra = NONE,
                .under = NONE,
            } });
        },
        '|' => {
            i.* += 1;
            // KaTeX `cdArrow`: `\Big\Vert` (same node as the
            // `\Big\Vert` spelling: level 1, Ord).
            return ctx.allocNode(.{ .big = .{ .cp = 0x2016, .level = 1, .class = .Ord } });
        },
        '.' => {
            // KaTeX `cdArrow`: a textord space (its MathML is an
            // `mi` holding U+0020, matched here by a space atom).
            i.* += 1;
            return ctx.allocNode(.{ .atom = .{ .class = .Ord, .font = .rm, .cp = ' ' } });
        },
        else => return ctx.fail(arrow_pos, "expected one of \"<>AV=|.\" after @"),
    }
}

/// amscd row assembly (KaTeX `parseCD` parity, issue #85): flatten
/// the row's cell groups into one item list, split at `@` arrows
/// into alternating cells and arrows. Even rows keep every cell;
/// odd (vertical-arrow) rows keep arrows plus middle cells only.
fn assembleCDRow(ctx: *ParseCtx, span: Row, odd: bool, pos: u32) Error!Row {
    const cells = ctx.kids[span.start .. span.start + span.len];
    // Rule-gap rows pass through untouched.
    if (cells.len == 1) {
        if (ctx.nodes[cells[0]] == .hline) return span;
    }
    var items: [512]u16 = undefined;
    var nitems: usize = 0;
    for (cells) |cell| {
        switch (ctx.nodes[cell]) {
            .group => |g| {
                const kids = ctx.kids[g.start .. g.start + g.len];
                for (kids) |k| {
                    if (nitems >= items.len) return error.NoSpace;
                    items[nitems] = k;
                    nitems += 1;
                }
            },
            else => {
                if (nitems >= items.len) return error.NoSpace;
                items[nitems] = cell;
                nitems += 1;
            },
        }
    }
    var segs: [64]u16 = undefined; // cells
    var nsegs: usize = 0;
    var arrows: [64]u16 = undefined;
    var narrows: usize = 0;
    var cur: [512]u16 = undefined;
    var ncur: usize = 0;
    var i: usize = 0;
    while (i < nitems) {
        if (cdIsAt(ctx, items[i])) {
            if (nsegs >= segs.len or narrows >= arrows.len) return error.NoSpace;
            segs[nsegs] = try finishGroup(ctx, cur[0..ncur]);
            nsegs += 1;
            ncur = 0;
            arrows[narrows] = try parseCDArrow(ctx, items[0..nitems], &i, pos);
            narrows += 1;
        } else {
            if (ncur >= cur.len) return error.NoSpace;
            cur[ncur] = items[i];
            ncur += 1;
            i += 1;
        }
    }
    if (nsegs >= segs.len) return error.NoSpace;
    segs[nsegs] = try finishGroup(ctx, cur[0..ncur]);
    nsegs += 1;
    var out: [128]u16 = undefined;
    var nout: usize = 0;
    if (!odd) {
        var k: usize = 0;
        while (k < narrows) : (k += 1) {
            out[nout] = segs[k];
            nout += 1;
            out[nout] = arrows[k];
            nout += 1;
        }
        out[nout] = segs[narrows];
        nout += 1;
    } else {
        // Odd rows drop the leading cell (KaTeX `row.shift()`)
        // and the trailing cell (never pushed).
        var k: usize = 0;
        while (k < narrows) : (k += 1) {
            out[nout] = arrows[k];
            nout += 1;
            if (k < narrows - 1) {
                out[nout] = segs[k + 1];
                nout += 1;
            }
        }
        // An arrow-less odd row is empty (its cell is dropped).
        if (narrows == 0) {
            const empty = try finishGroup(ctx, &.{});
            out[nout] = empty;
            nout += 1;
        }
    }
    var row = try stashRow(ctx, out[0..nout]);
    row.nonumber = span.nonumber;
    row.tagged = span.tagged;
    return row;
}

/// Whether a parsed cell is an empty group (a row trailer with no
/// content, e.g. after a trailing row rule).
fn isEmptyCellGroup(ctx: *ParseCtx, id: Idx) bool {
    return switch (ctx.nodes[id]) {
        .group => |g| g.len == 0,
        else => false,
    };
}

/// Copy one row's cell list into the kids pool; the `Row` span is
/// materialized into the rows pool by the caller at the end.
fn stashRow(ctx: *ParseCtx, cells: []const u16) Error!Row {
    const s = try ctx.allocKids(cells.len);
    @memcpy(ctx.kids[s .. s + cells.len], cells);
    return .{ .start = s, .len = @intCast(cells.len) };
}

test "parse single symbol and group" {
    var ctx = ParseCtx.init("x");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "parse sup-sub with primes" {
    var ctx = ParseCtx.init("x''^2_1");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .supsub => {},
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "double superscript is invalid" {
    var ctx = ParseCtx.init("x^2^3");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "tag hoists to the equation root in display mode" {
    // Pinned KaTeX 0.18.7: `\tag` is display-only, hoists from any
    // position (even `\frac` numerators), and a second tag fails.
    var ctx = ParseCtx.init("\\tag{1}x");
    const root = try parse(&ctx, true);
    switch (ctx.nodes[root]) {
        .tag => |tg| {
            try std.testing.expect(!tg.starred);
            switch (ctx.nodes[tg.formula]) {
                .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
                else => return error.TestUnexpectedResult,
            }
            switch (ctx.nodes[tg.body]) {
                .text => |t| {
                    const toks = toksOf(&ctx, t.toks);
                    try std.testing.expectEqual(@as(usize, 1), toks.len);
                    try std.testing.expectEqual(@as(u21, '1'), toks[0].cp);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Trailing and nested tags hoist the same way (the tag itself
    // contributes no atom to the row).
    var ctx2 = ParseCtx.init("x\\tag{1}");
    const root2 = try parse(&ctx2, true);
    switch (ctx2.nodes[root2]) {
        .tag => |tg| switch (ctx2.nodes[tg.formula]) {
            .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    var ctx3 = ParseCtx.init("\\sqrt{\\tag*{a}x}");
    const root3 = try parse(&ctx3, true);
    switch (ctx3.nodes[root3]) {
        .tag => |tg| {
            try std.testing.expect(tg.starred);
            switch (ctx3.nodes[tg.formula]) {
                .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Hoisting reaches `\frac` numerators too, and a lone tag tags
    // the empty equation (both accept in KaTeX).
    var ctx3b = ParseCtx.init("\\frac{\\tag{1}a}{b}");
    const root3b = try parse(&ctx3b, true);
    switch (ctx3b.nodes[root3b]) {
        .tag => |tg| switch (ctx3b.nodes[tg.formula]) {
            .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    var ctx3c = ParseCtx.init("\\tag{1}");
    const root3c = try parse(&ctx3c, true);
    switch (ctx3c.nodes[root3c]) {
        .tag => {},
        else => return error.TestUnexpectedResult,
    }
    // Braceless single-token bodies are legal (`\tag 1x`).
    var ctx4 = ParseCtx.init("\\tag 1x");
    const root4 = try parse(&ctx4, true);
    switch (ctx4.nodes[root4]) {
        .tag => {},
        else => return error.TestUnexpectedResult,
    }
    // Text mode rejects with KaTeX's exact message; a second tag
    // fails even in display mode.
    var ctx5 = ParseCtx.init("\\tag{1}x");
    try std.testing.expectError(error.Invalid, parse(&ctx5, false));
    try std.testing.expectEqualStrings("\\tag works only in display equations", ctx5.err_msg);
    var ctx6 = ParseCtx.init("\\tag{1}\\tag{2}x");
    try std.testing.expectError(error.Invalid, parse(&ctx6, true));
    try std.testing.expectEqualStrings("Multiple \\tag", ctx6.err_msg);
    // A nested tag reports "Multiple \tag" too (never a text-mode
    // error), at the inner tag (issue #75).
    var ctx6b = ParseCtx.init("\\tag{a\\tag{b}}x");
    try std.testing.expectError(error.Invalid, parse(&ctx6b, true));
    try std.testing.expectEqualStrings("Multiple \\tag", ctx6b.err_msg);
    // A user `\tag` macro shadows the builtin (expansion precedes
    // the tag arm, like every other builtin).
    var ctx7 = ParseCtx.init("\\renewcommand{\\tag}{X}\\tag");
    const root7 = try parse(&ctx7, true);
    switch (ctx7.nodes[root7]) {
        .group => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(ctx7.tag_body == NONE);
}

test "unbalanced brace is invalid" {
    var ctx = ParseCtx.init("{x");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "newcommand then use parses" {
    var ctx = ParseCtx.init("\\newcommand{\\f}{x}\\f");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "gdef defines like def" {
    var ctx = ParseCtx.init("\\gdef\\g{y}\\g");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| try std.testing.expectEqual(@as(u16, 1), g.len),
        else => return error.TestUnexpectedResult,
    }
}

test "starred matrix envs take alignment, other stars reject" {
    // KaTeX amsmath parity (issue #51): pmatrix*/matrix* accept with
    // one optional [l|c|r] spec (default centered); aligned*/cases*
    // and mismatched begin/end stars reject like KaTeX.
    const Case = struct {
        fn envOf(src: []const u8) !struct { kind: EnvKind, spec: u16 } {
            var ctx = ParseCtx.init(src);
            const root = try parse(&ctx, false);
            const env_id = switch (ctx.nodes[root]) {
                // Delimited envs (pmatrix et al) wrap the env node.
                .group => |g| switch (ctx.nodes[ctx.kids[g.start]]) {
                    .delim => |d| d.body,
                    else => ctx.kids[g.start],
                },
                else => return error.TestUnexpectedResult,
            };
            return switch (ctx.nodes[env_id]) {
                .env => |e| .{
                    .kind = e.kind,
                    .spec = if (e.spec_len == 1) kidsOf(&ctx, .{ .start = e.spec_start, .len = 1 })[0] else 9,
                },
                else => error.TestUnexpectedResult,
            };
        }
    };
    const a = try Case.envOf("\\begin{pmatrix*}[r]x\\end{pmatrix*}");
    try std.testing.expectEqual(EnvKind.pmatrix, a.kind);
    try std.testing.expectEqual(@as(u16, 2), a.spec);
    const b = try Case.envOf("\\begin{matrix*}x\\end{matrix*}");
    try std.testing.expectEqual(EnvKind.matrix, b.kind);
    try std.testing.expectEqual(@as(u16, 1), b.spec);
    var c = ParseCtx.init("\\begin{aligned*}x\\end{aligned*}");
    try std.testing.expectError(error.Invalid, parse(&c, false));
    var d = ParseCtx.init("\\begin{matrix}x\\end{matrix*}");
    try std.testing.expectError(error.Invalid, parse(&d, false));
    var e = ParseCtx.init("\\begin{matrix*}[x]y\\end{matrix*}");
    try std.testing.expectError(error.Invalid, parse(&e, false));
}

test "class wrappers, dotsi and mod expand" {
    // Issue #51 batch A: \mathinner/\mathop/\mathrel wrap the body
    // with a forced class; \dotsi is thin-negative-space + cdots;
    // \mod is style-choice space + upright "mod" + thin + argument
    // (KaTeX macro parity).
    const W = struct {
        fn wrapOf(src: []const u8) !struct { cls: symbols.AtomClass, is_group: bool } {
            var ctx = ParseCtx.init(src);
            const root = try parse(&ctx, false);
            const id = switch (ctx.nodes[root]) {
                .group => |g| if (g.len == 1) ctx.kids[g.start] else return error.TestUnexpectedResult,
                else => return error.TestUnexpectedResult,
            };
            return switch (ctx.nodes[id]) {
                .classwrap => |c| .{ .cls = c.class, .is_group = false },
                .group => .{ .cls = .Ord, .is_group = true },
                else => error.TestUnexpectedResult,
            };
        }
    };
    const r = try W.wrapOf("\\mathrel{x}");
    try std.testing.expectEqual(symbols.AtomClass.Rel, r.cls);
    const o = try W.wrapOf("\\mathop{x}");
    try std.testing.expectEqual(symbols.AtomClass.Op, o.cls);
    const i = try W.wrapOf("\\mathinner{x}");
    try std.testing.expectEqual(symbols.AtomClass.Inner, i.cls);
    const d = try W.wrapOf("\\dotsi");
    try std.testing.expect(d.is_group);
    const m = try W.wrapOf("\\mod b");
    try std.testing.expect(m.is_group);
}

test "macro loop hits expansion limit" {
    var ctx = ParseCtx.init("\\def\\a{\\a}\\a");
    try std.testing.expectError(error.ExpansionLimit, parse(&ctx, false));
}

test "redefining a builtin needs renewcommand" {
    var ctx = ParseCtx.init("\\newcommand{\\sum}{x}");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "unknown control sequence is invalid" {
    var ctx = ParseCtx.init("\\nope");
    const r = parse(&ctx, false);
    try std.testing.expectError(error.Invalid, r);
    try std.testing.expectEqual(@as(u32, 0), ctx.err_pos);
}

test "matrix ampersands and newlines split cells" {
    var ctx = ParseCtx.init("\\begin{matrix} a & b \\\\ c & d \\end{matrix}");
    const root = try parse(&ctx, false);
    const env_id = switch (ctx.nodes[root]) {
        .group => |g| blk: {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            break :blk ctx.kids[g.start];
        },
        else => return error.TestUnexpectedResult,
    };
    switch (ctx.nodes[env_id]) {
        .env => |e| {
            try std.testing.expectEqual(@as(u16, 2), e.rows_len);
            for (rowsOf(&ctx, e.rows_start, e.rows_len)) |row| {
                try std.testing.expectEqual(@as(u16, 2), row.len);
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "newline breaks env rows, stays mspace in running math (issue #79)" {
    // Pinned KaTeX 0.18.7: `\newline` is a row separator inside env
    // cells (like `\\`), but a content node (mspace) in running math.
    var ctx = ParseCtx.init("\\begin{matrix}a\\newline b\\end{matrix}");
    const root = try parse(&ctx, false);
    const env_id = switch (ctx.nodes[root]) {
        .group => |g| ctx.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctx.nodes[env_id]) {
        .env => |e| try std.testing.expectEqual(@as(u16, 2), e.rows_len),
        else => return error.TestUnexpectedResult,
    }
    var ctx2 = ParseCtx.init("a\\newline b");
    const root2 = try parse(&ctx2, false);
    const g2 = switch (ctx2.nodes[root2]) {
        .group => |g| g,
        else => return error.TestUnexpectedResult,
    };
    var saw_newline = false;
    for (ctx2.kids[g2.start .. g2.start + g2.len]) |k| {
        if (ctx2.nodes[k] == .newline) saw_newline = true;
    }
    try std.testing.expect(saw_newline);
}

test "verb scans to delimiter as monospace text" {
    var ctx = ParseCtx.init("\\verb|x|");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .text => |tx| {
                    try std.testing.expectEqual(FontFam.tt, tx.fam);
                    const toks = toksOf(&ctx, tx.toks);
                    try std.testing.expectEqual(@as(u16, 1), tx.toks.len);
                    try std.testing.expect(toks[0].kind == .char and toks[0].cp == 'x');
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "verb star shows spaces visibly" {
    var ctx = ParseCtx.init("\\verb*|a b|");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            const toks = toksOf(&ctx, switch (ctx.nodes[ctx.kids[g.start]]) {
                .text => |tx| tx.toks,
                else => return error.TestUnexpectedResult,
            });
            try std.testing.expectEqual(@as(usize, 3), toks.len);
            try std.testing.expectEqual(@as(u21, 0x2423), toks[1].cp);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "verb rejects unclosed and multiline scans" {
    var c1 = ParseCtx.init("\\verb|x");
    try std.testing.expectError(error.Invalid, parse(&c1, false));
    var c2 = ParseCtx.init("\\verb|a\nb|");
    try std.testing.expectError(error.Invalid, parse(&c2, false));
}

test "verb inside macro expansion is rejected" {
    var ctx = ParseCtx.init("\\newcommand{\\v}{\\verb|x|}\\v");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "braced color still scopes over the rest of the group" {
    // KaTeX parity (sweep `color` case): `\color` is a declaration even
    // when the next atom is braced; only `\textcolor` scopes.
    var ctx = ParseCtx.init("\\color{red}{x}+y");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    switch (ctx.nodes[c.body]) {
                        .group => |bg| try std.testing.expectEqual(@as(u16, 3), bg.len),
                        else => return error.TestUnexpectedResult,
                    }
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unbraced color scopes over the rest of the group" {
    var ctx = ParseCtx.init("\\color{red}x+y");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    switch (ctx.nodes[c.body]) {
                        .group => |bg| try std.testing.expectEqual(@as(u16, 3), bg.len),
                        else => return error.TestUnexpectedResult,
                    }
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "color accepts hex specs and textcolor alias" {
    var ctx = ParseCtx.init("\\color{#f00}{x}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    const toks = toksOf(&ctx, c.spec);
                    try std.testing.expectEqual(@as(usize, 4), toks.len);
                    try std.testing.expect(toks[0].kind == .char and toks[0].cp == '#');
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    var c2 = ParseCtx.init("\\textcolor{blue}{x}");
    const r2 = try parse(&c2, false);
    switch (c2.nodes[r2]) {
        .group => |g| {
            switch (c2.nodes[c2.kids[g.start]]) {
                .color => {},
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "color spec resolves a no-arg macro" {
    var ctx = ParseCtx.init("\\newcommand{\\myred}{red}\\color{\\myred}{x}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .color => |c| {
                    const toks = toksOf(&ctx, c.spec);
                    try std.testing.expectEqual(@as(usize, 3), toks.len);
                    try std.testing.expect(toks[0].kind == .char and toks[0].cp == 'r');
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "colorbox and fcolorbox parse text bodies" {
    var ctx = ParseCtx.init("\\colorbox{yellow}{a+b}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .colorbox => |c| {
                    try std.testing.expectEqual(@as(u16, 0), c.frame.len);
                    try std.testing.expect(toksOf(&ctx, c.bg).len == 6);
                    try std.testing.expect(toksOf(&ctx, c.body).len == 3);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    var c2 = ParseCtx.init("\\fcolorbox{red}{#ff0}{x}");
    const r2 = try parse(&c2, false);
    switch (c2.nodes[r2]) {
        .group => |g| {
            switch (c2.nodes[c2.kids[g.start]]) {
                .colorbox => |c| try std.testing.expect(c.frame.len > 0),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "text fonts take text arguments" {
    var ctx = ParseCtx.init("\\textbf{a+b}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .text => |tx| try std.testing.expectEqual(FontFam.bold, tx.fam),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Math commands are not allowed in text-font arguments (KaTeX parity).
    var c2 = ParseCtx.init("\\textbf{\\alpha}");
    try std.testing.expectError(error.Invalid, parse(&c2, false));
    // `\\textsl` is undefined in KaTeX.
    var c3 = ParseCtx.init("\\textsl{x}");
    try std.testing.expectError(error.Invalid, parse(&c3, false));
}

test "scripts after limits attach to the operator" {
    var ctx = ParseCtx.init("\\int\\limits_a^b");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .supsub => |s| {
                    switch (ctx.nodes[s.base]) {
                        .op => |o| try std.testing.expectEqual(LimitsMode.on, o.limits),
                        else => return error.TestUnexpectedResult,
                    }
                    try std.testing.expect(s.sup != NONE and s.sub != NONE);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "dollar in text mode is invalid" {
    var ctx = ParseCtx.init("\\text{a$b}");
    try std.testing.expectError(error.Invalid, parse(&ctx, false));
}

test "color specs follow the KaTeX validity rule" {
    // Bare words (even unknown ones) and 3/6-digit hex pass through.
    const ok_cases = [_][]const u8{
        "\\color{red}{x}",
        "\\color{notacolor}{x}",
        "\\color{#f00}{x}",
        "\\color{#ff00aa}{x}",
        "\\colorbox{red}{x}",
    };
    for (ok_cases) |src| {
        var ctx = ParseCtx.init(src);
        _ = try parse(&ctx, false);
    }
    // Empty specs, spaces, `rgb(...)`, and control sequences fail at
    // the spec brace (KaTeX parity: offset 6 below).
    const bad_cases = [_][]const u8{
        "\\color{}{x}",
        "\\color{red green}{x}",
        "\\color{rgb(1,0,0)}{x}",
        "\\color{\\%}{x}",
        "\\color{\\nosuchmacro}{x}",
        "\\colorbox{#ff}{x}",
    };
    for (bad_cases) |src| {
        var ctx = ParseCtx.init(src);
        const r = parse(&ctx, false);
        try std.testing.expectError(error.Invalid, r);
    }
    var ctx = ParseCtx.init("\\color{red green}{x}");
    _ = parse(&ctx, false) catch {};
    try std.testing.expectEqual(@as(u32, 6), ctx.err_pos);
}


test "display-only envs accept in display, reject inline (issues #83/#85/#86/#87/#90)" {
    // Pinned KaTeX 0.18.7: align/alignat/equation/gather/split/CD
    // accept in display mode and reject inline with "{name} can be
    // used only in display mode."
    const EnvCase = struct { src: []const u8, kind: EnvKind, numbered: bool };
    const ok_cases = [_]EnvCase{
        .{ .src = "\\begin{align}x&=1\\\\y&=2\\end{align}", .kind = .alignenv, .numbered = true },
        .{ .src = "\\begin{align*}x&=1\\end{align*}", .kind = .alignenv, .numbered = false },
        .{ .src = "\\begin{alignat}{2}x&=1&y&=2\\end{alignat}", .kind = .alignat, .numbered = true },
        .{ .src = "\\begin{alignat*}{2}x&=1\\end{alignat*}", .kind = .alignat, .numbered = false },
        .{ .src = "\\begin{equation}x=1\\end{equation}", .kind = .equation, .numbered = true },
        .{ .src = "\\begin{equation*}x=1\\end{equation*}", .kind = .equation, .numbered = false },
        .{ .src = "\\begin{gather}x=1\\\\y=2\\end{gather}", .kind = .gather, .numbered = true },
        .{ .src = "\\begin{gather*}x=1\\end{gather*}", .kind = .gather, .numbered = false },
        .{ .src = "\\begin{split}x&=1\\\\y&=2\\end{split}", .kind = .split, .numbered = false },
        .{ .src = "\\begin{CD}A@>>>B\\end{CD}", .kind = .cd, .numbered = false },
    };
    for (ok_cases) |c| {
        var ctx = ParseCtx.init(c.src);
        const root = try parse(&ctx, true);
        const env_id = switch (ctx.nodes[root]) {
            .group => |g| ctx.kids[g.start],
            else => return error.TestUnexpectedResult,
        };
        switch (ctx.nodes[env_id]) {
            .env => |e| {
                try std.testing.expectEqual(c.kind, e.kind);
                try std.testing.expectEqual(c.numbered, e.numbered);
            },
            else => return error.TestUnexpectedResult,
        }
        // Inline rejects with KaTeX's message at `\begin`.
        var ctxi = ParseCtx.init(c.src);
        try std.testing.expectError(error.Invalid, parse(&ctxi, false));
        try std.testing.expectEqualStrings("can be used only in display mode", ctxi.err_msg);
        try std.testing.expectEqual(@as(u32, 0), ctxi.err_pos);
    }
    // `equation` is a single column: `&` rejects at the tab.
    var ctx_amp = ParseCtx.init("\\begin{equation}x&=1\\end{equation}");
    try std.testing.expectError(error.Invalid, parse(&ctx_amp, true));
    try std.testing.expectEqual(@as(u32, 17), ctx_amp.err_pos);
    // `split` nests inside `equation` like the bundle.
    var ctx_nest = ParseCtx.init("\\begin{equation}\\begin{split}x&=1\\end{split}\\end{equation}");
    const nest_root = try parse(&ctx_nest, true);
    const nest_env = switch (ctx_nest.nodes[nest_root]) {
        .group => |g| ctx_nest.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctx_nest.nodes[nest_env]) {
        .env => |e| try std.testing.expectEqual(EnvKind.equation, e.kind),
        else => return error.TestUnexpectedResult,
    }
}

test "CD arrows assemble cells and arrows (issue #85)" {
    // Even row: cell, arrow, cell. The horizontal arrow carries its
    // labels as an extensible over-node.
    var ctx = ParseCtx.init("\\begin{CD}A@>a>b>B\\end{CD}");
    const root = try parse(&ctx, true);
    const cd_env = switch (ctx.nodes[root]) {
        .group => |g| ctx.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctx.nodes[cd_env]) {
        .env => |e| {
            try std.testing.expectEqual(EnvKind.cd, e.kind);
            // One content row plus KaTeX's trailing empty row.
            try std.testing.expectEqual(@as(u16, 2), e.rows_len);
            const rows = rowsOf(&ctx, e.rows_start, e.rows_len);
            const kids = kidsOf(&ctx, .{ .start = rows[0].start, .len = rows[0].len });
            try std.testing.expectEqual(@as(u16, 3), @as(u16, @intCast(kids.len)));
            switch (ctx.nodes[kids[1]]) {
                .over => |o| {
                    try std.testing.expectEqual(OverKind.xright, o.kind);
                    // Both labels ride along (possibly empty groups —
                    // KaTeX always passes both, yielding `munderover`).
                    switch (ctx.nodes[o.extra]) {
                        .group => {},
                        else => return error.TestUnexpectedResult,
                    }
                    switch (ctx.nodes[o.under]) {
                        .group => {},
                        else => return error.TestUnexpectedResult,
                    }
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Bad arrow characters and incomplete arrows reject.
    const bad_cases = [_][]const u8{
        "\\begin{CD}A@?B\\end{CD}",
        "\\begin{CD}A@>B\\end{CD}",
        "\\begin{CD}A@\\end{CD}",
    };
    for (bad_cases) |src| {
        var c = ParseCtx.init(src);
        try std.testing.expectError(error.Invalid, parse(&c, true));
    }
}

test "nonumber and notag are inert no-ops (issue #88)" {
    const ok_cases = [_][]const u8{
        "x\\nonumber",
        "x\\notag",
        "\\begin{align}x&=1\\nonumber\\\\y&=2\\end{align}",
        "\\begin{align}x&=1\\notag\\end{align}",
        "\\begin{equation}x=1\\nonumber\\end{equation}",
    };
    // Standalone commands accept in both modes; env cases need display.
    for (ok_cases) |src| {
        var ctxd = ParseCtx.init(src);
        _ = try parse(&ctxd, true);
    }
    for (ok_cases[0..2]) |src| {
        var ctxt = ParseCtx.init(src);
        _ = try parse(&ctxt, false);
    }
    // `\nonumber` marks its own row only (KaTeX `\@eqnsw` parity):
    // row 0 bare, row 1 numbered.
    var ctxr = ParseCtx.init("\\begin{align}x&=1\\nonumber\\\\y&=2\\end{align}");
    const rr = try parse(&ctxr, true);
    const re = switch (ctxr.nodes[rr]) {
        .group => |g| ctxr.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctxr.nodes[re]) {
        .env => |e| {
            const rows = rowsOf(&ctxr, e.rows_start, e.rows_len);
            try std.testing.expectEqual(@as(u16, 2), e.rows_len);
            try std.testing.expect(rows[0].nonumber);
            try std.testing.expect(!rows[1].nonumber);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "row-local tag wins over nonumber, cross-row tag does not (issue #75)" {
    // Same row `\tag` + `\nonumber` (either order): KaTeX keeps the
    // row's number columns — the tag hoists before `\@eqnsw` drops
    // them (probed 0.18.7). A tag in a *different* row is no rescue.
    for ([_][]const u8{
        "\\begin{align}x&=1\\tag{a}\\nonumber\\end{align}",
        "\\begin{align}x&=1\\nonumber\\tag{a}\\end{align}",
    }) |src| {
        var ctx = ParseCtx.init(src);
        const root = try parse(&ctx, true);
        // `\tag` wraps the root: unwrap `.tag` → group → env.
        const inner = switch (ctx.nodes[root]) {
            .tag => |t| t.formula,
            else => return error.TestUnexpectedResult,
        };
        const re = switch (ctx.nodes[inner]) {
            .group => |g| ctx.kids[g.start],
            else => return error.TestUnexpectedResult,
        };
        switch (ctx.nodes[re]) {
            .env => |e| {
                const rows = rowsOf(&ctx, e.rows_start, e.rows_len);
                try std.testing.expectEqual(@as(u16, 1), e.rows_len);
                try std.testing.expect(rows[0].nonumber);
                try std.testing.expect(rows[0].tagged);
            },
            else => return error.TestUnexpectedResult,
        }
    }
    // Leading outside-tag lands on row 0 (even starred), a
    // trailing outside-tag marks nothing (pinned 0.18.7).
    const lead_cases = [_]struct { src: []const u8, r0: bool, r1: bool }{
        .{ .src = "\\tag{a}\\begin{align*}x&=1\\\\y&=2\\end{align*}", .r0 = true, .r1 = false },
        .{ .src = "\\begin{align*}x&=1\\\\y&=2\\end{align*}\\tag{a}", .r0 = false, .r1 = false },
        .{ .src = "\\tag{a}\\begin{align*}x&=1\\nonumber\\\\y&=2\\end{align*}", .r0 = true, .r1 = false },
        .{ .src = "\\begin{align*}x&=1\\tag{a}\\\\y&=2\\end{align*}", .r0 = true, .r1 = false },
        .{ .src = "\\begin{align*}x&=1\\\\y&=2\\tag{a}\\end{align*}", .r0 = false, .r1 = true },
    };
    for (lead_cases) |lc| {
        var ctx = ParseCtx.init(lc.src);
        const root = try parse(&ctx, true);
        const inner = switch (ctx.nodes[root]) {
            .tag => |t| t.formula,
            else => return error.TestUnexpectedResult,
        };
        const re = switch (ctx.nodes[inner]) {
            .group => |g| ctx.kids[g.start],
            else => return error.TestUnexpectedResult,
        };
        switch (ctx.nodes[re]) {
            .env => |e| {
                const rows = rowsOf(&ctx, e.rows_start, e.rows_len);
                try std.testing.expectEqual(@as(u16, 2), e.rows_len);
                try std.testing.expectEqual(lc.r0, rows[0].tagged);
                try std.testing.expectEqual(lc.r1, rows[1].tagged);
            },
            else => return error.TestUnexpectedResult,
        }
    }
    // A tag nested in a matrix cell still belongs to the enclosing
    // numbering row (textual containment, pinned 0.18.7), and the
    // env adopts it (tag text dropped, number columns kept).
    var ctxn = ParseCtx.init("\\begin{align*}\\begin{matrix}\\tag{a}x\\end{matrix}&=1\\\\y&=2\\end{align*}");
    const rn = try parse(&ctxn, true);
    try std.testing.expect(ctxn.tag_adopted);
    const innern = switch (ctxn.nodes[rn]) {
        .tag => |t| t.formula,
        else => return error.TestUnexpectedResult,
    };
    const en = switch (ctxn.nodes[innern]) {
        .group => |g| ctxn.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctxn.nodes[en]) {
        .env => |e| {
            const rows = rowsOf(&ctxn, e.rows_start, e.rows_len);
            try std.testing.expectEqual(@as(u16, 2), e.rows_len);
            try std.testing.expect(rows[0].tagged);
            try std.testing.expect(!rows[1].tagged);
        },
        else => return error.TestUnexpectedResult,
    }
    // A trailing outside-tag is never adopted.
    var ctxt = ParseCtx.init("\\begin{align*}x&=1\\\\y&=2\\end{align*}\\tag{a}");
    _ = try parse(&ctxt, true);
    try std.testing.expect(!ctxt.tag_adopted);
    // Tag in row 0, `\nonumber` in row 1: row 1 stays bare.
    var ctx2 = ParseCtx.init("\\begin{align}x&=1\\tag{a}\\\\y&=2\\nonumber\\end{align}");
    const r2 = try parse(&ctx2, true);
    const inner2 = switch (ctx2.nodes[r2]) {
        .tag => |t| t.formula,
        else => return error.TestUnexpectedResult,
    };
    const e2 = switch (ctx2.nodes[inner2]) {
        .group => |g| ctx2.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctx2.nodes[e2]) {
        .env => |e| {
            const rows = rowsOf(&ctx2, e.rows_start, e.rows_len);
            try std.testing.expectEqual(@as(u16, 2), e.rows_len);
            try std.testing.expect(rows[0].tagged);
            try std.testing.expect(!rows[0].nonumber);
            try std.testing.expect(rows[1].nonumber);
            try std.testing.expect(!rows[1].tagged);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "Set Braket braket expand per KaTeX (issues #84/#89)" {
    const ok_cases = [_][]const u8{
        "\\braket{\\phi|\\psi}",
        "\\braket{ab}",
        "\\Braket{\\phi|\\psi}",
        "\\Braket{a|b|c}",
        "\\Braket{a||b}",
        "\\Set{x|x<5}",
        "\\Set{a\\|b}",
        "\\set{x|x<5}",
        // Bare frac args survive the split-path re-push (#89).
        "\\set{x|x\\frac12}",
        "\\set{x\\frac12}",
        "\\Set{x|x\\frac12}",
    };
    for (ok_cases) |src| {
        var ctx = ParseCtx.init(src);
        _ = try parse(&ctx, true);
    }
    // `\\braket` keeps the pipe literal inside fixed fences: one
    // Inner-wrapped group with three kids (fence, body, fence).
    var ctx = ParseCtx.init("\\braket{ab}");
    const root = try parse(&ctx, true);
    const bk_id = switch (ctx.nodes[root]) {
        .group => |g| ctx.kids[g.start],
        else => return error.TestUnexpectedResult,
    };
    switch (ctx.nodes[bk_id]) {
        .classwrap => {},
        else => return error.TestUnexpectedResult,
    }
}

test "text bodies hoist tag, nest, and shift math (issues #75/#81)" {
    // Pinned KaTeX 0.18.7: `\tag` hoists from text bodies (even
    // nested in braces), nested `\text` merges flat, and `$`
    // toggles math segments.
    const ok_cases = [_][]const u8{
        "\\text{\\tag{1}}x",
        "\\tag{\\text{a}}x",
        "\\text{a\\tag{1}}x",
        "\\text{a\\tag 1x}",
        "\\text{a{\\tag{1}}b}x",
        "\\text{a$b$c}",
        "\\text{\\text{a}}",
        "\\text{x\\text{ab}c}",
        "\\text{x\\text{a$b$}c}",
        "\\textbf{a\\tag{1}}x",
    };
    for (ok_cases) |src| {
        var ctx = ParseCtx.init(src);
        _ = try parse(&ctx, true);
    }
    // `\tag` hoisted means set (and the text keeps the rest).
    var ctx = ParseCtx.init("\\text{a\\tag{1}}x");
    _ = try parse(&ctx, true);
    try std.testing.expect(ctx.tag_body != NONE);
    // Inline `\tag`-in-text still rejects like the bundle.
    var ctxi = ParseCtx.init("\\text{a\\tag{1}}x");
    try std.testing.expectError(error.Invalid, parse(&ctxi, false));
    try std.testing.expectEqualStrings("\\tag works only in display equations", ctxi.err_msg);
    // Unclosed `$` rejects (position gap rides `katex_only`).
    var ctxu = ParseCtx.init("\\text{a$b}");
    try std.testing.expectError(error.Invalid, parse(&ctxu, false));
}



test "textcopyright math+text parity (issue #132)" {
    // Math mode: the `\\char` textord KaTeX observes
    // (`<mi mathvariant="normal">©</mi>`, pinned 0.18.7 probe).
    var ctx = ParseCtx.init("\\textcopyright");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .atom => |a| {
                    try std.testing.expect(a.textord);
                    try std.testing.expectEqual(@as(u21, 0x00A9), a.cp);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Text mode: the same codepoint through the text table (mtext,
    // like `\\textregistered`).
    for ([_][]const u8{ "\\text{\\textcopyright}", "\\textbf{\\textcopyright}" }) |src| {
        var ctxt = ParseCtx.init(src);
        _ = try parse(&ctxt, false);
    }
}

test "bgroup/egroup group like braces (issue #134)" {
    const ok_cases = [_][]const u8{
        "\\bgroup a}",
        "\\bgroup a\\egroup",
        "{\\bgroup a}}",
        "\\frac\\bgroup a}{b}",
    };
    for (ok_cases) |src| {
        var ctx = ParseCtx.init(src);
        _ = try parse(&ctx, false);
    }
    // `\\bgroup a}` shapes exactly like `{a}`: one group kid holding the atom.
    for ([_][]const u8{ "\\bgroup a}", "{a}" }) |src| {
        var ctx = ParseCtx.init(src);
        const root = try parse(&ctx, false);
        switch (ctx.nodes[root]) {
            .group => |g| {
                try std.testing.expectEqual(@as(u16, 1), g.len);
                switch (ctx.nodes[ctx.kids[g.start]]) {
                    .group => |inner| {
                        try std.testing.expectEqual(@as(u16, 1), inner.len);
                        switch (ctx.nodes[ctx.kids[inner.start]]) {
                            .atom => |a| try std.testing.expectEqual(@as(u21, 'a'), a.cp),
                            else => return error.TestUnexpectedResult,
                        }
                    },
                    else => return error.TestUnexpectedResult,
                }
            },
            else => return error.TestUnexpectedResult,
        }
    }
    // Rejects mirror `}`/`\\begingroup` pairing at KaTeX positions
    // (pinned 0.18.7 probes).
    const rej_cases = [_]struct { src: []const u8, pos: u32 }{
        .{ .src = "\\egroup", .pos = 0 },
        .{ .src = "\\bgroup", .pos = 7 },
        .{ .src = "{a\\egroup}", .pos = 9 },
        .{ .src = "\\bgroup a\\endgroup}", .pos = 9 },
    };
    for (rej_cases) |c| {
        var ctxr = ParseCtx.init(c.src);
        try std.testing.expectError(error.Invalid, parse(&ctxr, false));
        try std.testing.expectEqual(c.pos, ctxr.err_pos);
    }
    // `\\newcommand` refuses the grouping primitives like KaTeX.
    var ctxn = ParseCtx.init("\\newcommand{\\bgroup}{x}");
    try std.testing.expectError(error.Invalid, parse(&ctxn, false));
}

test "mathsfit is sans-serif italic (issue #137)" {
    var ctx = ParseCtx.init("\\mathsfit{AaBb}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .font => |f| try std.testing.expectEqual(FontFam.sansitalic, f.fam),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Single-atom form takes the atom; `\\mathsf` is untouched.
    var ctxa = ParseCtx.init("\\mathsfit\\alpha");
    _ = try parse(&ctxa, false);
    var ctxs = ParseCtx.init("\\mathsf{H}");
    const roots = try parse(&ctxs, false);
    switch (ctxs.nodes[roots]) {
        .group => |g| switch (ctxs.nodes[ctxs.kids[g.start]]) {
            .font => |f| try std.testing.expectEqual(FontFam.sans, f.fam),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
}

test "firstoftwo/secondoftwo keep their branch (issue #161)" {
    // The kept branch parses as siblings; the dropped branch is
    // never parsed — even undefined commands there accept.
    const ok_cases = [_][]const u8{
        "\\@firstoftwo{a}{b}",
        "\\@secondoftwo{a}{b}",
        "\\@firstoftwo{a}{\\undefinedcommand}",
        "\\@secondoftwo{\\undefinedcommand}{b}",
        "\\@firstoftwo{{a}b}{c}",
        "\\text{\\@firstoftwo{a}{b}}",
        "\\text{\\@secondoftwo{a}{b}}",
    };
    for (ok_cases) |src| {
        var ctx = ParseCtx.init(src);
        _ = try parse(&ctx, false);
    }
    // `\\@firstoftwo{a}{b}` leaves exactly `a`.
    var ctx = ParseCtx.init("\\@firstoftwo{a}{b}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .atom => |a| try std.testing.expectEqual(@as(u21, 'a'), a.cp),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // A missing second argument rejects at end of input like KaTeX.
    var ctxm = ParseCtx.init("\\@firstoftwo{a}");
    try std.testing.expectError(error.Invalid, parse(&ctxm, false));
    try std.testing.expectEqual(@as(u32, 15), ctxm.err_pos);
}

test "ifnextchar/ifstar lookahead (issue #162)" {
    // Match keeps the if-branch and never consumes the probe.
    const match_cases = [_]struct { src: []const u8, first: u21, n: u16 }{
        .{ .src = "\\@ifnextchar{a}{T}{E}a", .first = 'T', .n = 2 },
        .{ .src = "\\@ifnextchar{a}{T}{E}b", .first = 'E', .n = 2 },
        .{ .src = "\\@ifnextchar{a}{T}{E} a", .first = 'T', .n = 2 },
        .{ .src = "\\@ifnextchar\\alpha{T}{E}\\alpha", .first = 'T', .n = 2 },
        .{ .src = "\\@ifstar{T}{E}*", .first = 'T', .n = 1 },
        .{ .src = "\\@ifstar{T}{E}x", .first = 'E', .n = 2 },
        .{ .src = "\\@ifstar{T}{E}", .first = 'E', .n = 1 },
    };
    for (match_cases) |c| {
        var ctx = ParseCtx.init(c.src);
        const root = try parse(&ctx, false);
        switch (ctx.nodes[root]) {
            .group => |g| {
                try std.testing.expectEqual(c.n, g.len);
                switch (ctx.nodes[ctx.kids[g.start]]) {
                    .atom => |a| try std.testing.expectEqual(c.first, a.cp),
                    else => return error.TestUnexpectedResult,
                }
            },
            else => return error.TestUnexpectedResult,
        }
    }
    // A missing third argument rejects at end of input like KaTeX.
    var ctxu = ParseCtx.init("\\@ifnextchar{a}{T}");
    try std.testing.expectError(error.Invalid, parse(&ctxu, false));
    try std.testing.expectEqual(@as(u32, 18), ctxu.err_pos);
}

test "TextOrMath picks the math branch in math (issue #163)" {
    // Math mode keeps the second argument.
    var ctx = ParseCtx.init("\\TextOrMath{a}{b}");
    const root = try parse(&ctx, false);
    switch (ctx.nodes[root]) {
        .group => |g| {
            try std.testing.expectEqual(@as(u16, 1), g.len);
            switch (ctx.nodes[ctx.kids[g.start]]) {
                .atom => |a| try std.testing.expectEqual(@as(u21, 'b'), a.cp),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    // Text mode keeps the first, inline and nested; math nesting
    // re-enters normally.
    const ok_cases = [_][]const u8{
        "\\text{\\TextOrMath{a}{b}}",
        "\\text{x\\TextOrMath{a}{b}y}",
        "\\text{\\TextOrMath{{a}b}{c}}",
        "\\frac{\\TextOrMath{a}{b}}{c}",
        "\\TextOrMath{\\frac12}{x}",
    };
    for (ok_cases) |src| {
        var ctxt = ParseCtx.init(src);
        _ = try parse(&ctxt, false);
    }
    // The text side keeps `a` as text.
    var ctxt = ParseCtx.init("\\text{\\TextOrMath{a}{b}}");
    const roott = try parse(&ctxt, false);
    switch (ctxt.nodes[roott]) {
        .group => |g| switch (ctxt.nodes[ctxt.kids[g.start]]) {
            .text => |tx| {
                const tk = ctxt.toks[tx.toks.start];
                try std.testing.expect(tk.kind == .char and tk.cp == 'a');
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    // A missing second argument rejects at end of input like KaTeX.
    var ctxm = ParseCtx.init("\\TextOrMath{a}");
    try std.testing.expectError(error.Invalid, parse(&ctxm, false));
    try std.testing.expectEqual(@as(u32, 14), ctxm.err_pos);
}
