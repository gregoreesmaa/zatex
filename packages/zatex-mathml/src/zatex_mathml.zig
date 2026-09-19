//! zatex-mathml — KaTeX-compatible MathML emitter over the zatex core.
//!
//! Thin structural walker over the core parse tree (AGENTS.md §2):
//! no layout math, no measuring, no `MetricsProvider`. Owns the Zig
//! `render` entry plus the `zatex_mathml_utf8` C entry (see
//! `zatex_mathml.h`). Depends on the `zatex` package for parsing;
//! the core never depends back, so its distribution library stays
//! MathML-free.
const std = @import("std");
const zatex = @import("zatex");
const mathml_mod = @import("mathml.zig");

pub const LayoutOptions = zatex.LayoutOptions;
pub const LayoutError = zatex.LayoutError;

// C ABI (cabi.zig): exports ride along with the lib.
comptime {
    _ = @import("cabi.zig");
}

/// MathML Core serialization of one formula into caller-owned `out`.
/// Pure structural mapping over the parse tree — no layout math.
pub const render = mathml_mod.render;

test {
    // Force every test-bearing source into analysis so its tests
    // execute (the mechanism tools/check_test_roots.sh enforces).
    std.testing.refAllDecls(@import("mathml.zig"));
    std.testing.refAllDecls(@import("cabi.zig"));
}
