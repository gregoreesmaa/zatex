//! layout.zig — minimal Zig host: lay out one formula, print the runs/rules.
//!
//! Run from `packages/zatex` (font paths are CWD-relative there):
//!   zig run ../../examples/layout.zig --main-pkg-path ../../examples --deps ...
//! Simplest: copy this file into your package and add the `zatex` dep.
//! See also `hello_formula.c` (C ABI) and `render.sh` (CLI batch).
const std = @import("std");
const zatex = @import("zatex");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    const tex: []const u8 = "\\frac{a}{b}+x^2";

    // 1. Metrics provider: hosts answer glyph advances etc. from their
    //    own fonts. Tests use the vendored fixture stack (refhost);
    //    real hosts wire system fonts (see docs/ir.md + docs/install.md).
    const provider = @import("refhost").testProvider(alloc);

    // 2. Caller-owned buffers: no allocation inside the engine.
    var runs_buf: [256]zatex.ir.Run = undefined;
    var rules_buf: [64]zatex.ir.Rule = undefined;
    var glyphs_buf: [4096]u16 = undefined;

    // 3. Lay out. `layoutDiag` carries the KaTeX-parity byte offset +
    //    message on `error.Invalid`.
    var diag = zatex.Diag.empty();
    const layout = zatex.layoutDiag(
        tex,
        .{},
        provider,
        &runs_buf,
        &rules_buf,
        &glyphs_buf,
        &diag,
    ) catch |e| {
        std.debug.print("layout failed: {} at byte {}: {s}\n", .{ e, diag.offset, diag.message });
        std.process.exit(1);
    };

    // 4. Draw (here: print). Runs reference `glyphs_buf` by slices;
    //    rules are filled rects in integer font units, y down from the
    //    formula top-left (see docs/ir.md).
    std.debug.print("formula: {s}\n", .{tex});
    std.debug.print("extents: width={} above={} below={} runs={} rules={}\n", .{
        layout.width, layout.height_above, layout.depth_below,
        layout.runs.len,  layout.rules.len,
    });
    for (layout.runs, 0..) |run, i| {
        std.debug.print("run {}: font={} size={} x={} baseline={} glyphs={any}\n", .{
            i, run.font_id, run.size_units, run.x, run.baseline_y, run.glyphs,
        });
    }
    for (layout.rules, 0..) |rule, i| {
        std.debug.print("rule {}: x={} y={} w={} h={}\n", .{
            i, rule.x, rule.y, rule.w, rule.h,
        });
    }
}
