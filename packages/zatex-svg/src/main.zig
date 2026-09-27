//! zatex-svg CLI: LaTeX math -> standalone SVG on stdout.
const std = @import("std");

const usage =
    \\usage: zatex-svg [--display] [--font PATH] "<tex>"
    \\
;

pub fn main() !void {
    std.debug.print("{s}", .{usage});
}

test "scaffold cli compiles" {
    try std.testing.expect(true);
}
