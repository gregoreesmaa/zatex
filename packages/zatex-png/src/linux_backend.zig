//! Linux backend: the portable software rasterizer (`sw_backend.zig`).
//!
//! Linux has no guaranteed system text stack, and linking host
//! FreeType/fontconfig would trade the zero-dependency core promise
//! for distro-specific `.so` drift (different rasterizers per distro =
//! different pixels per machine, against the deterministic-output
//! tenet). The software backend draws from the same font file the
//! metrics came from, so same input + same fixture = identical pixels
//! on every Linux host. This file stays a thin selection shim so a
//! future native backend (e.g. FreeType) can land here without
//! touching callers, `backend.zig`'s contract, or the layout core.
const sw = @import("sw_backend.zig");

pub const Font = sw.Font;
pub const Canvas = sw.Canvas;
pub const Run = sw.Run;
