//! ZaTeX shared contract: frozen v1 call-site shapes, additive growth.
//!
//! `zatex.zig` re-exports these names so the public API is unchanged;
//! internal modules import this file directly (no import cycles).
const std = @import("std");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

pub const Profile = enum { subset, full };

/// Hard caps. Part of the contract, not tunables.
pub const max_input_len: usize = 64 * 1024;
pub const max_nesting_depth: u8 = 32;
pub const max_expand: u32 = 1000; // KaTeX `maxExpand` default parity.

/// Layout knobs. Fields gain defaults, never lose them.
pub const LayoutOptions = struct {
    display_mode: bool = false,
};

/// Rule kinds the core may ask a thickness for.
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
/// Optional hooks (default null) unlock typographic refinements when
/// the host can supply them; the core is correct without them:
/// - `glyphVariant` returns a taller variant of `glyph` whose extent
///   is at least `min_height`, or the input glyph when unknown.
/// - `italicCorrection` returns the italic correction of `glyph`.
/// - `kernCorrection` (v3) returns the MathKern cut-in of `glyph` at
///   correction `height` for `corner`; the core applies top-right
///   cut-ins to superscripts and bottom-right cut-ins to subscripts.
/// - `inkBounds` (v4) returns the true ink box of `glyph` as
///   `[x_min, y_min, x_max, y_max]` at 1000 units, y UP from the
///   baseline (unclipped: parts below/left of the origin stay
///   negative). The core uses it only for accent placement: centering
///   zero-advance combining marks by ink (e.g. U+20D7 whose ink hangs
///   left of the origin) and lifting low-sitting accents (e.g. `~`)
///   clear of the nucleus. Null behaves exactly as v3.
pub const provider_version: u32 = 4;
pub const MetricsProvider = struct {
    ctx: *const anyopaque,
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
    Unsupported, // outside subset/profile scope → caller falls back
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
};
