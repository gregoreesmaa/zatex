//! ZaTeX layout IR: the output contract every emitter consumes.
//!
//! The layout core produces positioned glyph runs plus rects (fraction
//! bars, radicals, over/underlines) in integer font units. Hosts draw
//! runs through their own glyph cache and fonts; future MathML/SVG/PNG
//! writers walk this same structure. See docs/ir.md.

/// One positioned run of glyphs from a single host font at one size.
/// Coordinates are integer font units; y is the alphabetic baseline.
/// `color` is 0xRRGGBBAA paint (`\color` scope, issue #35); null means
/// the ambient (host default) paint. Runs never merge across colors.
pub const Run = struct {
    font_id: u16,
    size_units: u16,
    x: i32,
    baseline_y: i32,
    glyphs: []const u16,
    color: ?u32 = null,
    /// Horizontal raster scale in per-mille (1000 = identity): wide
    /// accents and brace spans stretch one glyph to the construction
    /// width (issues #31/#37). Additive: existing constructions omit
    /// it and render unstretched.
    x_scale: u16 = 1000,
    /// Faux-italic slant in per-mille (0 = upright): the backend
    /// shifts ink right by `x_shear` thousandths of the height above
    /// the baseline. Set by the core for dotless i/j under the
    /// default math face, whose upright host glyph stands in for
    /// KaTeX's math-italic ȷ/ı (issue #77). Additive like `x_scale`.
    x_shear: i16 = 0,
    /// Horizontally mirrored ink (`\reflectbox` / `\mathreflectbox`,
    /// issue #97): the backend flips each glyph about its own origin
    /// (KaTeX's CSS flip). The core pre-maps every run origin through
    /// the mirror, so backends never do coordinate math; rules in a
    /// mirrored subtree arrive pre-mirrored as plain rects. Runs
    /// never merge across the mirror boundary. Additive: existing
    /// constructions omit it and render unmirrored.
    mirrored: bool = false,
};

/// One filled rect in font units (fraction bars, radical vincula, rules).
/// `color` paints `\colorbox` backgrounds and `\fcolorbox` frames
/// (issue #35); null means the ambient paint.
pub const Rule = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    color: ?u32 = null,
};

/// A fully laid-out formula: its ink box plus all marks.
pub const Layout = struct {
    width: u32,
    height_above: u32,
    depth_below: u32,
    runs: []const Run,
    rules: []const Rule,

    pub fn empty() Layout {
        return .{
            .width = 0,
            .height_above = 0,
            .depth_below = 0,
            .runs = &.{},
            .rules = &.{},
        };
    }
};
