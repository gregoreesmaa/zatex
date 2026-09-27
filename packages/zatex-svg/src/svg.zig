//! SVG emitter: geometric walker over `zatex.ir.Layout`.
// Scaffold: replaced by Tasks 2-4.
const std = @import("std");
const zatex = @import("zatex");
const cff = @import("cff");
const outlines_mod = @import("outlines.zig");

// Scaffold: replaced by Tasks 2-4.
pub fn renderLayout(
    layout: zatex.ir.Layout,
    ol: outlines_mod.Outlines,
    segs: []cff.Seg,
    out: []u8,
) zatex.LayoutError![]u8 {
    _ = layout;
    _ = ol;
    _ = segs;
    _ = out;
    return error.NoSpace;
}

// Scaffold: replaced by Tasks 2-4.
pub fn render(
    source: []const u8,
    options: zatex.LayoutOptions,
    prov: zatex.MetricsProvider,
    ol: outlines_mod.Outlines,
    runs: []zatex.ir.Run,
    rules: []zatex.ir.Rule,
    glyphs: []u16,
    segs: []cff.Seg,
    out: []u8,
    diag: *zatex.Diag,
) zatex.LayoutError![]u8 {
    _ = source;
    _ = options;
    _ = prov;
    _ = ol;
    _ = runs;
    _ = rules;
    _ = glyphs;
    _ = segs;
    _ = out;
    _ = diag;
    return error.NoSpace;
}

test "scaffold svg compiles" {
    try std.testing.expect(true);
}
