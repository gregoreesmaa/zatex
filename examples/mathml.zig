//! mathml.zig — minimal MathML host: serialize one formula to MathML.
//!
//! The MathML emitter is a thin structural walker over the core parse
//! tree: no layout math, no measuring, no font metrics (AGENTS.md §2).
const std = @import("std");
const zatex_mathml = @import("zatex_mathml");

pub fn main() !void {
    const tex: []const u8 = "\\frac{a}{b}+x^2";

    // Caller-owned buffer; `render` returns the bytes written.
    var out_buf: [65536]u8 = undefined;
    const out = zatex_mathml.render(tex, .{}, &out_buf) catch |e| {
        std.debug.print("mathml failed: {}\n", .{e});
        std.process.exit(1);
    };
    std.debug.print("{s}\n", .{out});
}
