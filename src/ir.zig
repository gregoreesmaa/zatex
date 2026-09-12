//! ZaTeX layout IR: the output contract every emitter consumes.
//!
//! The layout core produces positioned glyph runs plus rects (fraction
//! bars, radicals, over/underlines) in integer font units. Hosts draw
//! runs through their own glyph cache and fonts; future MathML/SVG/PNG
//! writers walk this same structure. See docs/ir.md.

/// One positioned run of glyphs from a single host font at one size.
/// Coordinates are integer font units; y is the alphabetic baseline.
pub const Run = struct {
    font_id: u16,
    size_units: u16,
    x: i32,
    baseline_y: i32,
    glyphs: []const u16,
};

/// One filled rect in font units (fraction bars, radical vincula, rules).
pub const Rule = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
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
