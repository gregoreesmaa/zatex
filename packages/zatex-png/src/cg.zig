//! Manual CoreGraphics/CoreText/ImageIO bindings (no @cImport).
//!
//! Zig 0.16's bundled Clang rejects current macOS SDK headers, so the
//! renderer declares the dozen stable C entry points it needs instead
//! of translating umbrella headers. core-only rule: this file lives in
//! zatex-png and must never be imported by the core.
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .macos) @compileError("zatex-png: macOS-only (CoreGraphics backend)");
}

// CoreFoundation (all refs are opaque; caller CFReleases everything).
pub const CFStringRef = ?*anyopaque;
pub const CFURLRef = ?*anyopaque;
pub const CFDictionaryRef = ?*anyopaque;
pub const CFTypeRef = ?*anyopaque;
pub const CFIndex = isize;

pub const kCFStringEncodingUTF8: u32 = 0x08000100;

pub extern fn CFRelease(cf: CFTypeRef) void;
pub extern fn CFStringCreateWithCString(
    alloc: ?*anyopaque,
    cStr: [*:0]const u8,
    encoding: u32,
) CFStringRef;
pub extern fn CFURLCreateFromFileSystemRepresentation(
    alloc: ?*anyopaque,
    buffer: [*]const u8,
    bufLen: CFIndex,
    isDirectory: bool,
) CFURLRef;

// CoreGraphics.
pub const CGColorSpaceRef = ?*anyopaque;
pub const CGContextRef = ?*anyopaque;
pub const CGImageRef = ?*anyopaque;
pub const CGFontRef = ?*anyopaque;
pub const CGDataProviderRef = ?*anyopaque;

pub const CGPoint = extern struct {
    x: f64,
    y: f64,
};
pub const CGSize = extern struct {
    width: f64,
    height: f64,
};
pub const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,
};

/// PremultipliedFirst + 32-bit little-endian (RGBA byte order on arm64).
pub const bitmap_info: u32 = (2 << 12) | 2;

pub extern fn CGColorSpaceCreateDeviceRGB() CGColorSpaceRef;
pub extern fn CGBitmapContextCreate(
    data: ?*anyopaque,
    width: usize,
    height: usize,
    bitsPerComponent: usize,
    bytesPerRow: usize,
    space: CGColorSpaceRef,
    bitmapInfo: u32,
) CGContextRef;
pub extern fn CGContextSetRGBFillColor(
    c: CGContextRef,
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
) void;
pub extern fn CGContextFillRect(c: CGContextRef, rect: CGRect) void;
pub extern fn CGContextTranslateCTM(c: CGContextRef, tx: f64, ty: f64) void;
pub extern fn CGContextScaleCTM(c: CGContextRef, sx: f64, sy: f64) void;
pub extern fn CGBitmapContextCreateImage(c: CGContextRef) CGImageRef;
pub extern fn CGDataProviderCreateWithFilename(filename: [*:0]const u8) CGDataProviderRef;
pub extern fn CGFontCreateWithDataProvider(provider: CGDataProviderRef) CGFontRef;

// CoreText.
pub const CTFontRef = ?*anyopaque;
pub const CGGlyph = u16;

pub extern fn CTFontCreateWithGraphicsFont(
    graphicsFont: CGFontRef,
    size: f64,
    matrix: ?*const anyopaque,
    attributes: CFDictionaryRef,
) CTFontRef;
pub extern fn CTFontDrawGlyphs(
    font: CTFontRef,
    glyphs: [*]const CGGlyph,
    positions: [*]const CGPoint,
    count: usize,
    context: CGContextRef,
) void;
pub const kCTFontOrientationDefault: c_uint = 0;
pub extern fn CTFontGetBoundingRectsForGlyphs(
    font: CTFontRef,
    orientation: c_uint,
    glyphs: [*]const CGGlyph,
    boundingRects: [*]CGRect,
    count: CFIndex,
) CGRect;

// ImageIO.
pub const CGImageDestinationRef = ?*anyopaque;

pub extern fn CGImageDestinationCreateWithURL(
    url: CFURLRef,
    fileType: CFStringRef,
    count: usize,
    options: CFDictionaryRef,
) CGImageDestinationRef;
pub extern fn CGImageDestinationAddImage(
    dest: CGImageDestinationRef,
    image: CGImageRef,
    properties: CFDictionaryRef,
) void;
pub extern fn CGImageDestinationFinalize(dest: CGImageDestinationRef) bool;
