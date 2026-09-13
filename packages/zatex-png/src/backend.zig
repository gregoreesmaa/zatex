//! Backend selection: exactly one file per OS implements the small
//! canvas + font-handle interface (`Font`, `Canvas`, `Run`) that the
//! portable code in `render.zig` / `font.zig` programs to. Porting to a
//! new OS means adding one file and one arm below — the callers, the
//! coordinate mapping, and the layout core never change.
//!
//! Canvas coordinates are caller floats in pixels, origin bottom-left,
//! y-up. The portable mapping in `render.zig` owns the core-to-canvas
//! flip (and its test); backends only consume bottom-left rects and
//! baselines, which every 2D API (Quartz, Cairo, Skia, Direct2D) draws
//! natively.
//!
//! `-Dbackend=` overrides the default: `auto` (CoreGraphics on Apple
//! OSes, portable software rasterizer elsewhere), `cg` (Apple only),
//! or `software` (any OS — how Linux/Windows/Android renders are
//! verified on a macOS host, and how the Linux oracle image builds).
const std = @import("std");
const builtin = @import("builtin");
const forced: []const u8 = @import("build_options").backend;

pub const impl = blk: {
    if (std.mem.eql(u8, forced, "cg")) {
        if (builtin.os.tag != .macos and builtin.os.tag != .ios)
            @compileError("zatex-png: -Dbackend=cg needs an Apple OS (CoreGraphics)");
        break :blk @import("cg_backend.zig");
    }
    if (std.mem.eql(u8, forced, "software")) break :blk @import("sw_backend.zig");
    if (!std.mem.eql(u8, forced, "auto"))
        @compileError("zatex-png: -Dbackend must be auto|cg|software");
    // Zig models Android as Linux + an android ABI (there is no
    // `.android` OS tag), so it is detected before the OS switch.
    if (builtin.abi.isAndroid()) break :blk @import("android_backend.zig");
    break :blk switch (builtin.os.tag) {
        .macos => @import("cg_backend.zig"),
        .ios => @import("ios_backend.zig"),
        .linux => @import("linux_backend.zig"),
        .windows => @import("windows_backend.zig"),
        else => @compileError("zatex-png: no backend for this OS yet (the layout core in packages/zatex stays portable)"),
    };
};

// Interface contract every backend file honors, checked at comptime so
// a new backend fails fast on a missing decl rather than with a
// confusing error at its first use site.
comptime {
    const I = impl;
    if (!@hasDecl(I, "Font") or !@hasDecl(I, "Canvas") or !@hasDecl(I, "Run")) {
        @compileError("zatex-png backend must expose Font, Canvas, and Run");
    }
    if (!@hasDecl(I.Font, "load") or !@hasDecl(I.Font, "close") or
        !@hasDecl(I.Font, "extents1000") or !@hasDecl(I.Font, "inkBounds1000"))
    {
        @compileError("zatex-png backend Font must expose load/close/extents1000/inkBounds1000");
    }
    if (!@hasDecl(I.Canvas, "create") or !@hasDecl(I.Canvas, "close") or
        !@hasDecl(I.Canvas, "setFill") or !@hasDecl(I.Canvas, "fillRect") or
        !@hasDecl(I.Canvas, "beginRun") or !@hasDecl(I.Canvas, "writePng"))
    {
        @compileError("zatex-png backend Canvas must expose create/close/setFill/fillRect/beginRun/writePng");
    }
    if (!@hasDecl(I.Run, "drawGlyph") or !@hasDecl(I.Run, "end")) {
        @compileError("zatex-png backend Run must expose drawGlyph/end");
    }
}
