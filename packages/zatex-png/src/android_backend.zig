//! Android backend: the portable software rasterizer (`sw_backend.zig`).
//!
//! The NDK offers no stable text-shaping/raster API (minikin is not
//! public API and shifts per release), so a native backend would mean
//! bundling FreeType anyway — at which point the zero-dependency
//! software backend wins outright: same pixels as every other
//! software-backend OS, no JNI, no per-device font drift.
const sw = @import("sw_backend.zig");

pub const Font = sw.Font;
pub const Canvas = sw.Canvas;
pub const Run = sw.Run;
