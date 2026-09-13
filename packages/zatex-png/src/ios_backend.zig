//! iOS backend: CoreGraphics/CoreText, shared with macOS.
//!
//! CoreGraphics, CoreText, and ImageIO all exist on iOS with the same
//! entry points `cg.zig` binds, so iOS reuses the reference
//! implementation directly. Compiling for iOS needs the Xcode iOS SDK
//! (`zig build -Dtarget=aarch64-ios` with `xcrun --sdk iphoneos` paths;
//! this machine has CommandLineTools only, so the arm below is wired
//! but its compile check runs on SDK CI runners — see README).
const cg = @import("cg_backend.zig");

pub const Font = cg.Font;
pub const Canvas = cg.Canvas;
pub const Run = cg.Run;
