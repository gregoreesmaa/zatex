//! Subset-profile envelope probe (own test root: this file only runs
//! in the subset-profile binary, where the emitter keeps the bare
//! envelope — see `mathml.zig`).
const std = @import("std");
const zm = @import("zatex_mathml");

test "subset profile keeps the bare envelope" {
    var out: [512]u8 = undefined;
    const s = try zm.render("x^2", .{}, &out);
    // No semantics/annotation shell under subset.
    try std.testing.expect(std.mem.indexOf(u8, s, "<semantics>") == null);
    try std.testing.expect(std.mem.indexOf(u8, s, "annotation") == null);
    try std.testing.expect(std.mem.startsWith(u8, s, "<math "));
    try std.testing.expect(std.mem.endsWith(u8, s, "</math>"));
    // The formula itself still renders.
    try std.testing.expect(std.mem.indexOf(u8, s, "<msup>") != null);
}
