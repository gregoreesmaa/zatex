//! Windows backend: the portable software rasterizer (`sw_backend.zig`).
//!
//! A native DirectWrite backend remains possible (it would live in this
//! file behind the same `Backend` interface: IDWriteFontFace for ink
//! extents + rasterization, WIC for PNG), but the software backend
//! already serves Windows with zero host dependencies and identical
//! pixels to every other software-backend OS, so DirectWrite is a
//! future optimization, not a porting requirement. Plan notes:
//! DirectWrite measures in DIPs over its own font files — extents must
//! be re-checked against `otmath` advances like the CoreText cross-check
//! in `sw_backend.zig`'s test before any switch.
const sw = @import("sw_backend.zig");

pub const Font = sw.Font;
pub const Canvas = sw.Canvas;
pub const Run = sw.Run;
