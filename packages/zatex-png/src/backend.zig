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
const builtin = @import("builtin");

pub const impl = switch (builtin.os.tag) {
    .macos, .ios => @import("cg_backend.zig"),
    else => @compileError("zatex-png: no backend for this OS yet (the layout core in packages/zatex stays portable)"),
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
        !@hasDecl(I.Font, "extents1000"))
    {
        @compileError("zatex-png backend Font must expose load/close/extents1000");
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
