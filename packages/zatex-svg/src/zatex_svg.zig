//! zatex-svg — LaTeX math to standalone SVG (outlined glyph paths).
const std = @import("std");

pub const svg = @import("svg.zig");
pub const outlines = @import("outlines.zig");
pub const renderLayout = svg.renderLayout;
pub const measureLayout = svg.measureLayout;
pub const render = svg.render;

test {
    std.testing.refAllDecls(@import("svg.zig"));
    std.testing.refAllDecls(@import("outlines.zig"));
    std.testing.refAllDecls(@import("main.zig"));
}
