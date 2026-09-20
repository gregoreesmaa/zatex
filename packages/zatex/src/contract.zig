//! ZaTeX shared contract: frozen v1 call-site shapes, additive growth.
//!
//! `zatex.zig` re-exports these names so the public API is unchanged;
//! internal modules import this file directly (no import cycles).
const std = @import("std");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

/// Hard caps. Part of the contract, not tunables.
pub const max_input_len: usize = 64 * 1024;
pub const max_nesting_depth: u8 = 32;
pub const max_expand: u32 = 1000; // KaTeX `maxExpand` default parity.

/// Layout knobs. Fields gain defaults, never lose them.
pub const LayoutOptions = struct {
    display_mode: bool = false,
    /// KaTeX `leqno`: display `\tag`s render left of the formula
    /// instead of right. Default false (right).
    leqno: bool = false,
    /// KaTeX `fleqn`: display math renders flush left with a 2em
    /// left margin (the whole construction shifts right by 2em in
    /// font units; the host still positions the block). Default
    /// false (no margin shift).
    fleqn: bool = false,
    /// KaTeX `minRuleThickness` in thousandths of an em (40 = the
    /// usual 0.04): floors every rule thickness the core requests
    /// (fraction bars, radicals, over/underlines, array and `\fbox`
    /// rules). 0 disables the floor (previous behavior); the type
    /// is unsigned because KaTeX ignores negative values.
    min_rule_thickness_milli_em: u16 = 0,
    /// KaTeX `strict`: `warn` (the KaTeX default) records
    /// non-LaTeX conveniences into `strict_log` (dropped when null
    /// — a native library has no console sink); `err` turns them
    /// into positioned `Invalid` failures; `ignore` takes the
    /// engine default silently. Custom handler functions have no
    /// native analog (no JS engine); hosts approximate them by
    /// inspecting `strict_log` per code.
    strict: StrictMode = .warn,
    /// Warn-mode sink for `strict` reports (caller-owned). Null
    /// drops warn reports; `count` still totals them when present.
    strict_log: ?*StrictLog = null,
    /// KaTeX `macros`: host-provided preset macros seeded into the
    /// definition table before parsing (bounded: at most
    /// `max_presets`). String bodies carry `#1..#9` params like
    /// in-source `\def` bodies; single-codepoint names are active
    /// characters; the alias form mirrors `\let` (with `noexpand`).
    /// Function-valued macros have no native analog (documented in
    /// `docs/parity.md`). Presets are per-call seeds: unlike KaTeX,
    /// `\gdef` never mutates this list (zero-alloc, reentrant) —
    /// hosts needing cross-call sharing pass the same slice again.
    macros: []const PresetMacro = &.{},
    /// KaTeX `globalGroup`: when true every definition escapes its
    /// group like `\gdef` (KaTeX parity for the opt-in). Default
    /// false (KaTeX default scoping: local groups, `\gdef` escapes).
    global_group: bool = false,
};

/// KaTeX `strict` modes (`boolean|string` values; function handlers
/// have no native analog — see `LayoutOptions.strict`).
pub const StrictMode = enum {
    ignore,
    warn,
    /// KaTeX `"error"` (spelled `err`: `error` is a keyword).
    err,
};

/// Non-LaTeX conveniences the `strict` knob reports. KaTeX 0.18.7
/// codes mappable to this engine; the remainder
/// (`mathVsTextUnits`, `unicodeTextInMathMode`, `unknownSymbol`,
/// `commentAtEnd`) is documented in `docs/parity.md`, not emitted.
pub const StrictCode = enum {
    /// `\htmlClass`/`\htmlId`/`\htmlStyle`/`\htmlData` (KaTeX
    /// `htmlExtension`).
    html_extension,
    /// `\\` (or `\newline`) in display mode (KaTeX
    /// `newLineInDisplayMode`): behavioral, never throws — error
    /// mode renders no break (already the engine shape: a zero
    /// box), warn/ignore keep it.
    new_line_in_display_mode,
    /// `&` past the `{array}` column spec (KaTeX `textEnv`).
    text_env,
    /// Text-mode accents (`\'`, `\"`, …) in math mode (KaTeX
    /// `mathVsTextAccents`).
    math_vs_text_accents,
    /// `\sout` in math mode (KaTeX `mathVsSout`).
    math_vs_sout,
};

/// One `strict` warn-mode report: what and where (byte offset).
pub const StrictWarning = struct {
    code: StrictCode,
    pos: u32,
};

/// Caller-owned warn-mode sink: `buf` keeps the first reports,
/// `count` totals all reports (extras past the buffer drop but
/// still count).
pub const StrictLog = struct {
    buf: []StrictWarning,
    count: usize = 0,
};

/// One host-provided preset macro (KaTeX `macros` option entry).
/// `name` is `"foo"` for `\foo` (leading backslash stripped) or
/// the UTF-8 bytes of one codepoint for an active character.
/// Exactly one of `body` / `alias` selects the form: a LaTeX string
/// with `#1..#9` params (arg count inferred sequentially like
/// KaTeX), or a `\let`-style alias of `target` (`"\int"` or one
/// codepoint; `noexpand` mirrors the `MacroExpansion` object form).
pub const PresetMacro = struct {
    name: []const u8,
    body: []const u8 = "",
    alias: ?[]const u8 = null,
    noexpand: bool = false,
};

/// Hard cap on preset macros per call (part of the contract).
pub const max_presets: usize = 16;

/// Rule kinds the core may ask a thickness for. Declaration order is
/// the C ABI contract (`zatex.h` `rule_thickness` kind, bridged via
/// `@intFromEnum` in cabi.zig — not MATH-table order):
/// 0 = fraction_bar, 1 = radical, 2 = overline, 3 = underline.
/// Underlines reuse the overline weight today (KaTeX parity), so the
/// core never requests `underline` yet — it stays reserved.
pub const RuleKind = enum { fraction_bar, radical, overline, underline };

/// MathKern corner for script cut-ins (v3 hook below).
pub const KernCorner = enum(u32) {
    top_right = 0,
    top_left = 1,
    bottom_right = 2,
    bottom_left = 3,
};

/// Host-supplied font metrics. The core never touches font files: glyph
/// identity, advances, and rule weights arrive here in integer font
/// units. `font` is the host's own namespace, opaque to the core.
///
/// Denomination: every numeric hook value is in thousandths of an em
/// (1000 units = 1em at text size). The core scales each value to the
/// ambient size itself with truncation toward zero. Determinism is
/// input + metrics: the same hooks returning the same values produce
/// byte-identical layout.
///
/// Per-hook exactness contract (issue #193) — what is load-bearing,
/// which layout decisions branch on the value, and what misrendering
/// a wrong value produces. Normative for hosts; `docs/ir.md` carries
/// the host-oriented guide with the `\tilde{x}` / `\vec{v}` recipe.
///
/// - `glyphId`: glyph id for (`font`, `codepoint`) in the host's
///   namespace; 0 means missing (issue #142). Load-bearing
///   everywhere: 0 still lays out (using that hook's advance/extents
///   for 0), so boxes/tofu on screen always trace back here.
/// - `advance`: the font's horizontal advance (hmtx) scaled to
///   thousandths, truncation toward zero — bit-for-bit, INCLUDING 0
///   for zero-width combining marks (e.g. U+20D7). Load-bearing for
///   every run width; `layoutAccent` branches on `adv == 0`: zero
///   takes the ink-centering path
///   (`ax = (nucleus_w - ink_w) / 2 - ink_x0 + shift`), nonzero the
///   advance-box rule (`ax = (nucleus_w - adv_w) / 2 + shift`). A
///   nonzero missing-glyph fallback (a "reasonable" 500!) takes the
///   wrong branch and mis-centers the accent by roughly half an em —
///   the worked `\vec{v}` example in `docs/ir.md`. This is
///   traceability sentence T1: the `read` host's 500-for-zero-width
///   fallback bug is this sentence's violation.
/// - `ruleThickness`: rule weight in thousandths; values <= 0 read as
///   40, and `LayoutOptions.min_rule_thickness_milli_em` floors the
///   result on top (0 disables the floor). Load-bearing for fraction
///   bars, radicals, over/underlines and the clearances derived from
///   them. Wrong weights thicken bars and shift bar-to-body gaps.
/// - `extents`: `[height_above, depth_below]` of `glyph` at 1000
///   units; blank glyphs report `[0, 0]`. Null keeps the uniform
///   700/250 approximation bit-identically (deterministic; hosts with
///   outline metrics should supply the real extents). Load-bearing
///   for every glyph box height/depth: accent clearance
///   (`min(body height, x-height 431)`), the brace-label legacy gaps,
///   fence target comparison. True extents shift vertical clearance
///   versus the reference — untracked lore before this contract.
/// - `glyphVariant`: a taller variant of `glyph` whose extent is at
///   least `min_height` (thousandths), or the input glyph when
///   unknown. Null returns the input glyph bit-identically.
///   Load-bearing for fences (`need > 0`) and radicals. Always-
///   identity keeps tall fences/radicals under-grown (clipped or
///   overlapped spans); a wrong-face glyph misdraws.
/// - `italicCorrection`: the OpenType MATH italic-correction value
///   scaled to thousandths, truncation toward zero. The core looks it
///   up on the LAID-OUT nucleus glyph (post-substitution, not the
///   parse codepoint), halves it, and adds KaTeX's Math-Italic skew
///   for single-symbol math-italic nuclei
///   (`symbols.mathItalicSkew`; upright and unlisted nuclei shift 0).
///   Null reads 0 (upright accents, bit-identical). Failure symptom:
///   a parse-codepoint lookup sees text `y` (correction 8) instead of
///   math-italic U+1D466 (28), shifting `\hat{y}` by 10mu at text
///   size; unscaled font units skew every slanted-nucleus accent.
///   This is traceability sentence T2: the `read` host's italic
///   lookup/units bug is this sentence's violation.
/// - `kernCorrection` (v3): the MathKern cut-in of `glyph` at
///   correction `height` for `corner` (OpenType MATH semantics: first
///   CorrectionHeight at or above the query wins, else the last
///   value), scaled to thousandths. The core applies top-right
///   cut-ins to superscripts and bottom-right cut-ins to subscripts,
///   each clamped to `[0, gap]`; other corners are reserved (return
///   0). Null/0 means no cut-in, bit-identical — failure costs only
///   looser scripts, never overlap.
/// - `inkBounds` (v4): the true ink box of `glyph` as
///   `[x_min, y_min, x_max, y_max]` at 1000 units, y UP from the
///   baseline, unclipped (parts below/left of the origin stay
///   negative); +/-1 rounding from float outlines is acceptable, and
///   all-zero means blank (the core ignores it). Load-bearing
///   consumers: accent ink-centering for `adv == 0` combining marks
///   (U+20D7 ink `[-472, 521, -56, 711]` hangs left of its origin);
///   low-accent lift (accent ink must clear the nucleus top by at
///   least 130: `ay = max(ay, nucleus_top + 130 - ink_bottom)` —
///   `~` ink bottom +193 would otherwise nestle into the nucleus);
///   wide-accent ink scaling (KaTeX `preserveAspectRatio="none"`
///   parity: ink, not the advance box, spans the nucleus); dot-stack
///   lift (`\ddot` family via `.` ink); brace-label outer kern (0.2em
///   off ink vs the 150mu legacy rule off the extents box);
///   over/underbrace 0.1em ink-to-ink kern; the sqrt surd-hook
///   junction (the vinculum starts one rule thickness inside the
///   hook's right ink edge, clamped to `[ink left, advance]`); `\not`
///   slash ink-centering. Null costs exactly the v3 behavior per
///   construct above — a host reading "optional" can price NULL from
///   this list. This is traceability sentence T3: the `read` host's
///   ink-frame / NULL-cost bug is this sentence's violation.
///
/// Hosts validate their provider with the metrics conformance check
/// (issue #194): `conform.check` natively, `zatex_conform_metrics`
/// at the C ABI level — a diagnostic corpus with reference-font
/// expectations that names each mismatch (missing hooks, wrong
/// advances, bad ink boxes). The reference provider passes cleanly;
/// see `docs/ir.md` ("Metrics conformance").
pub const provider_version: u32 = 4;
pub const MetricsProvider = struct {
    ctx: *const anyopaque,
    /// Glyph id for (`font`, `codepoint`) in the host's namespace.
    /// Id 0 means missing (issue #142): the core lays out the run
    /// with the provider's advance/extents for 0 anyway, so hosts
    /// seeing boxes/tofu should check which (font, codepoint) pairs
    /// come back 0 — that is the whole coverage diagnostic. The
    /// reference host (`refhost.zig`) resolves vendored Latin Modern
    /// Math first, system STIX Two Math second; anything 0 in both
    /// is genuinely uncovered (see the font troubleshooting note in
    /// `docs/parity.md`).
    glyphId: *const fn (ctx: *const anyopaque, font: u16, codepoint: u21) u16,
    advance: *const fn (ctx: *const anyopaque, font: u16, glyph: u16) i32,
    ruleThickness: *const fn (ctx: *const anyopaque, font: u16, kind: RuleKind) i32,
    /// [height_above, depth_below] of `glyph` at 1000 units. When null
    /// the core uses a uniform 700/250 approximation (deterministic;
    /// hosts with outline metrics should supply the real extents).
    /// All hook values are denominated at 1000 units; the core scales
    /// them to the ambient size itself.
    extents: ?*const fn (ctx: *const anyopaque, font: u16, glyph: u16) [2]i32 = null,
    glyphVariant: ?*const fn (ctx: *const anyopaque, font: u16, glyph: u16, min_height: i32) u16 = null,
    italicCorrection: ?*const fn (ctx: *const anyopaque, font: u16, glyph: u16) i32 = null,
    kernCorrection: ?*const fn (ctx: *const anyopaque, font: u16, glyph: u16, height: i32, corner: KernCorner) i32 = null,
    inkBounds: ?*const fn (ctx: *const anyopaque, font: u16, glyph: u16) [4]i32 = null,
};

/// Every failure the engine can ever report. Variants are added, never
/// removed or repurposed; `OutOfMemory` is reserved (the core allocates
/// nothing) so the set never reshapes under callers.
pub const LayoutError = error{
    Unsupported, // outside engine scope → caller falls back
    Invalid, // malformed input (KaTeX ParseError parity)
    TooDeep, // max_nesting_depth exceeded
    TooLong, // max_input_len exceeded
    ExpansionLimit, // max_expand exceeded
    NoSpace, // capacity exceeded: caller buffers, or fixed engine pools
    OutOfMemory, // reserved; the core allocates nothing
};

/// KaTeX `ParseError` parity: byte offset plus a static message.
/// Positions are byte offsets into `source`, matching KaTeX's
/// character offsets for ASCII input.
pub const Diag = struct {
    offset: u32,
    message: []const u8,

    pub fn empty() Diag {
        return .{ .offset = 0, .message = "" };
    }
};

/// Core font families. The `u16` value is what the core passes as
/// `font` to the provider; hosts map these to their own fonts.
/// Families gain variants, never renumber.
pub const FontId = enum(u16) {
    rm = 0,
    math_italic = 1,
    bold = 2,
    sans = 3,
    tt = 4,
    frak = 5,
    script = 6,
    bb = 7,
    cal = 8,
    /// `\bm` bold-italic (issue #73): appended, never renumbered.
    bold_italic = 9,
    /// Narrow accents (issue #103): KaTeX renders every accent from
    /// its Main face, whose designs (hat ink half the LM width) the
    /// reference font does not match. Appended, never renumbered.
    main = 10,
    /// Large operators (issue #101): KaTeX draws symbol operators
    /// from Size1-Regular, swapping to Size2-Regular in display
    /// style — no scalar approximates both (sum needs 1.4x, integrals
    /// need 2x). Appended, never renumbered.
    size1 = 11,
    size2 = 12,
    /// `\mathsfit` sans-serif italic (issue #137): KaTeX's
    /// SansSerif-Italic face (`mathvariant="sans-serif-italic"`).
    /// Appended, never renumbered.
    sans_italic = 13,
};
