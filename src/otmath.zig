//! MaTeX OpenType reader: metrics hosts need for the provider.
//!
//! This is HOST-side code (tests, harnesses, embedders read their own
//! font files with it) — the layout core never touches font files and
//! never imports this module. Bounded, allocation-free, big-endian
//! parsing over caller-provided bytes: `head` (units per em), `maxp`
//! (glyph count), `cmap` formats 4/12 (codepoint → glyph), `hmtx`
//! (advances), and the OpenType `MATH` table (constants, vertical
//! variants, italic corrections).
//!
//! Constant indices below are positions in the binary MathConstants
//! table (verified byte-for-byte against fontTools for the reference
//! font; the layout — 4 plain u16 then i16 value records — is fixed
//! by the OpenType spec).
const std = @import("std");

pub const Error = error{
    NotAFont,
    UnsupportedTable,
    Truncated,
};

/// MathConstants indices used by the core (binary order).
pub const Const = enum(u8) {
    script_percent_down = 0,
    script_script_percent_down = 1,
    delimited_sub_min = 2,
    display_op_min = 3,
    axis_height = 5,
    subsup_gap_min = 15,
    space_after_script = 17,
    upper_limit_gap_min = 18,
    lower_limit_gap_min = 20,
    stack_gap_min = 26,
    stretch_stack_gap_above_min = 30,
    stretch_stack_gap_below_min = 31,
    frac_num_gap_min = 36,
    frac_rule = 38,
    frac_den_gap_min = 39,
    overbar_gap = 43,
    overbar_rule = 44,
    underbar_gap = 46,
    underbar_rule = 47,
    radical_gap = 49,
    radical_display_gap = 50,
    radical_rule = 51,

    fn offset(self: Const) usize {
        const k = @intFromEnum(self);
        if (k < 4) return @as(usize, k) * 2;
        return 8 + @as(usize, k - 4) * 4;
    }
};

pub const Font = struct {
    bytes: []const u8,
    upm: u16,
    num_glyphs: u16,
    cmap_off: usize,
    hmtx_off: usize,
    hmetrics: u16,
    math_off: usize, // 0 when the font has no MATH table
    const_off: usize, // MathConstants origin (valid iff math_off != 0)
    glyph_info_off: usize,
    variants_off: usize,
};

fn u16be(b: []const u8, off: usize) Error!u16 {
    if (off + 2 > b.len) return error.Truncated;
    return (@as(u16, b[off]) << 8) | b[off + 1];
}

fn i16be(b: []const u8, off: usize) Error!i16 {
    return @bitCast(try u16be(b, off));
}

fn u32be(b: []const u8, off: usize) Error!u32 {
    if (off + 4 > b.len) return error.Truncated;
    return (@as(u32, b[off]) << 24) | (@as(u32, b[off + 1]) << 16) |
        (@as(u32, b[off + 2]) << 8) | b[off + 3];
}

fn tableOff(bytes: []const u8, want: u32) Error!usize {
    if (bytes.len < 12) return error.Truncated;
    const n = try u16be(bytes, 4);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const base = 12 + i * 16;
        if (base + 16 > bytes.len) return error.Truncated;
        if (try u32be(bytes, base) == want) return try u32be(bytes, base + 8);
    }
    return error.UnsupportedTable;
}

fn tag(a: u8, b: u8, c: u8, d: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, c) << 8) | d;
}

/// Load (not copy) a font from memory. Accepts TrueType and CFF
/// OpenType (`0x00010000`, `OTTO`, `true`, `typ1`).
pub fn load(bytes: []const u8) Error!Font {
    if (bytes.len < 12) return error.Truncated;
    const sfnt = try u32be(bytes, 0);
    if (sfnt != 0x00010000 and sfnt != 0x4F54544F and sfnt != 0x74727565 and sfnt != 0x74797031) {
        return error.NotAFont;
    }
    const head = tableOff(bytes, tag('h', 'e', 'a', 'd')) catch return error.NotAFont;
    const maxp = tableOff(bytes, tag('m', 'a', 'x', 'p')) catch return error.NotAFont;
    const cmap = tableOff(bytes, tag('c', 'm', 'a', 'p')) catch return error.NotAFont;
    const hmtx = tableOff(bytes, tag('h', 'm', 't', 'x')) catch return error.NotAFont;
    const hhea = tableOff(bytes, tag('h', 'h', 'e', 'a')) catch return error.NotAFont;
    const upm = try u16be(bytes, head + 18);
    if (upm == 0) return error.NotAFont;
    const num_glyphs = try u16be(bytes, maxp + 4);
    const hmetrics = try u16be(bytes, hhea + 34);
    var math_off: usize = 0;
    var const_off: usize = 0;
    var glyph_info_off: usize = 0;
    var variants_off: usize = 0;
    if (tableOff(bytes, tag('M', 'A', 'T', 'H'))) |mo| {
        if (try u32be(bytes, mo) == 0x00010000) {
            const co = try u16be(bytes, mo + 4);
            const gio = try u16be(bytes, mo + 6);
            const vo = try u16be(bytes, mo + 8);
            if (co != 0 and gio != 0 and vo != 0) {
                math_off = mo;
                const_off = mo + co;
                glyph_info_off = mo + gio;
                variants_off = mo + vo;
            }
        }
    } else |_| {}
    return .{
        .bytes = bytes,
        .upm = upm,
        .num_glyphs = num_glyphs,
        .cmap_off = cmap,
        .hmtx_off = hmtx,
        .hmetrics = hmetrics,
        .math_off = math_off,
        .const_off = const_off,
        .glyph_info_off = glyph_info_off,
        .variants_off = variants_off,
    };
}

/// MathConstants value in font units (i16).
pub fn constant(f: Font, c: Const) Error!i16 {
    if (f.math_off == 0) return error.UnsupportedTable;
    if (@intFromEnum(c) < 4) {
        return @bitCast(try u16be(f.bytes, f.const_off + c.offset()));
    }
    return try i16be(f.bytes, f.const_off + c.offset());
}

/// Codepoint → glyph id (0 = missing). Tries cmap formats 12 then 4.
pub fn glyphId(f: Font, cp: u21) Error!u16 {
    const b = f.bytes;
    const n = try u16be(b, f.cmap_off + 2);
    var best12: usize = 0;
    var best4: usize = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const rec = f.cmap_off + 4 + i * 8;
        const plat = try u16be(b, rec);
        const enc = try u16be(b, rec + 2);
        const off = try u32be(b, rec + 4);
        // Prefer Windows Unicode full (3,10); then any Unicode cmap.
        if (plat == 3 and enc == 10) {
            best12 = f.cmap_off + off;
            break;
        }
        const fmt = u16be(b, f.cmap_off + off) catch continue;
        if (fmt == 12 and best12 == 0) best12 = f.cmap_off + off;
        if (fmt == 4 and best4 == 0) best4 = f.cmap_off + off;
    }
    if (best12 != 0) {
        if (try u16be(b, best12) == 12) {
            if (try u32be(b, best12 + 4) == 0) {
                const ng = try u32be(b, best12 + 12);
                var g: usize = 0;
                while (g < ng) : (g += 1) {
                    const base = best12 + 16 + g * 12;
                    const first = try u32be(b, base);
                    const last = try u32be(b, base + 4);
                    if (cp >= first and cp <= last) {
                        const gid = try u32be(b, base + 8) + (cp - first);
                        if (gid >= f.num_glyphs) return 0;
                        return @intCast(gid);
                    }
                }
                return 0;
            }
        }
    }
    if (best4 != 0) return cmap4(b, best4, cp, f.num_glyphs);
    return error.UnsupportedTable;
}

fn cmap4(b: []const u8, off: usize, cp: u21, num_glyphs: u16) Error!u16 {
    if (cp > 0xFFFF) return 0;
    const c = @as(u16, @intCast(cp));
    const seg_x2 = try u16be(b, off + 6);
    const nseg = seg_x2 / 2;
    const end_base = off + 14;
    const start_base = end_base + 2 + nseg * 2;
    const delta_base = start_base + nseg * 2;
    const range_base = delta_base + nseg * 2;
    // Binary search end codes.
    var lo: usize = 0;
    var hi: usize = nseg;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const end = try u16be(b, end_base + mid * 2);
        if (c > end) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo >= nseg) return 0;
    const start = try u16be(b, start_base + lo * 2);
    if (c < start) return 0;
    const delta = try i16be(b, delta_base + lo * 2);
    const range_off = try u16be(b, range_base + lo * 2);
    var gid: u32 = 0;
    if (range_off == 0) {
        gid = @as(u32, @bitCast(@as(i32, c) + delta)) & 0xFFFF;
    } else {
        const idx = range_base + lo * 2 + range_off + (c - start) * 2;
        gid = try u16be(b, idx);
        if (gid != 0) gid = (gid + @as(u32, @bitCast(@as(i32, delta)))) & 0xFFFF;
    }
    if (gid >= num_glyphs) return 0;
    return @intCast(gid);
}

/// Horizontal advance in font units.
pub fn advance(f: Font, glyph: u16) Error!i32 {
    if (glyph >= f.num_glyphs) return error.Truncated;
    const b = f.bytes;
    if (glyph < f.hmetrics) {
        return try u16be(b, f.hmtx_off + @as(usize, glyph) * 4);
    }
    const last = if (f.hmetrics == 0) 0 else f.hmetrics - 1;
    return try u16be(b, f.hmtx_off + @as(usize, last) * 4);
}

/// Coverage check: format 1 (list) or 2 (ranges).
fn inCoverage(b: []const u8, cov_off: usize, glyph: u16) Error!bool {
    const fmt = try u16be(b, cov_off);
    if (fmt == 1) {
        const n = try u16be(b, cov_off + 2);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (try u16be(b, cov_off + 4 + i * 2) == glyph) return true;
        }
        return false;
    }
    if (fmt == 2) {
        const n = try u16be(b, cov_off + 2);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const base = cov_off + 4 + i * 6;
            if (glyph >= try u16be(b, base) and glyph <= try u16be(b, base + 2)) return true;
        }
        return false;
    }
    return error.UnsupportedTable;
}

/// Coverage index of a glyph (for parallel arrays), or null.
fn coverageIndex(b: []const u8, cov_off: usize, glyph: u16) Error!?usize {
    const fmt = try u16be(b, cov_off);
    if (fmt == 1) {
        const n = try u16be(b, cov_off + 2);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (try u16be(b, cov_off + 4 + i * 2) == glyph) return i;
        }
        return null;
    }
    if (fmt == 2) {
        const n = try u16be(b, cov_off + 2);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const base = cov_off + 4 + i * 6;
            const first = try u16be(b, base);
            const last = try u16be(b, base + 2);
            const idx = try u16be(b, base + 4);
            if (glyph >= first and glyph <= last) return idx + (glyph - first);
        }
        return null;
    }
    return error.UnsupportedTable;
}

/// First vertical variant of `glyph` with advance ≥ `min_advance`
/// (font units), or `glyph` itself. Powers `\left..\right` growth.
pub fn vertVariant(f: Font, glyph: u16, min_advance: i32) Error!u16 {
    if (f.math_off == 0) return error.UnsupportedTable;
    const b = f.bytes;
    const vo = f.variants_off;
    const vert_cov = vo + (try u16be(b, vo + 2));
    const idx = (try coverageIndex(b, vert_cov, glyph)) orelse return glyph;
    const count = try u16be(b, vo + 6);
    if (idx >= count) return glyph;
    const con_off_off = vo + 10 + idx * 2;
    const con_rel = try u16be(b, con_off_off);
    if (con_rel == 0) return glyph;
    const con = vo + con_rel;
    // VertGlyphConstruction: assembly offset (con+0, may be NULL),
    // VariantCount (con+2), then records at con+4.
    const nvar = try u16be(b, con + 2);
    if (nvar == 0) return glyph;
    const recs = con + 4;
    var i: usize = 0;
    while (i < nvar) : (i += 1) {
        const vg = try u16be(b, recs + i * 4);
        const av = try u16be(b, recs + i * 4 + 2);
        if (@as(i32, av) >= min_advance) return vg;
    }
    return glyph;
}

/// Italic correction in font units (0 when uncovered).
pub fn italicCorrection(f: Font, glyph: u16) Error!i32 {
    if (f.math_off == 0) return error.UnsupportedTable;
    const b = f.bytes;
    const info_rel = try u16be(b, f.glyph_info_off);
    const info = f.glyph_info_off + info_rel;
    const cov_rel = try u16be(b, info);
    if (cov_rel == 0) return 0;
    const idx = (try coverageIndex(b, info + cov_rel, glyph)) orelse return 0;
    const count = try u16be(b, info + 2);
    if (idx >= count) return 0;
    // ItalicsCorrection is count × MathValueRecord (value i16 + device u16).
    return try i16be(b, info + 4 + idx * 4);
}

// ---------------------------------------------------------------------------
// Tests against the vendored reference font (fontTools cross-checked).
// ---------------------------------------------------------------------------

/// Vendored reference font, read from the working tree by tests only
/// (the reader itself only ever sees caller-provided bytes).
const ref_path = "fixtures/fonts/latinmodern-math.otf";

fn loadRef() !struct { bytes: []u8, font: Font } {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        ref_path,
        std.testing.allocator,
        .limited(4 * 1024 * 1024),
    );
    return .{ .bytes = bytes, .font = try load(bytes) };
}

test "reference font loads with expected census" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    try std.testing.expectEqual(@as(u16, 1000), r.font.upm);
    try std.testing.expectEqual(@as(u16, 4802), r.font.num_glyphs);
    try std.testing.expect(r.font.math_off != 0);
}

test "reference constants match fontTools ground truth" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    try std.testing.expectEqual(@as(i16, 40), try constant(r.font, .frac_rule));
    try std.testing.expectEqual(@as(i16, 250), try constant(r.font, .axis_height));
    try std.testing.expectEqual(@as(i16, 40), try constant(r.font, .radical_rule));
    try std.testing.expectEqual(@as(i16, 1300), try constant(r.font, .delimited_sub_min));
    try std.testing.expectEqual(@as(i16, 1300), try constant(r.font, .display_op_min));
}

test "reference cmap resolves key codepoints" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    try std.testing.expectEqual(@as(u16, 9), try glyphId(r.font, '('));
    try std.testing.expectEqual(@as(u16, 89), try glyphId(r.font, 'x'));
    try std.testing.expect(try glyphId(r.font, 0x2211) != 0); // summation
    try std.testing.expect(try glyphId(r.font, 0x221A) != 0); // radical
    try std.testing.expect(try glyphId(r.font, 0x03B1) != 0); // alpha
    try std.testing.expect(try glyphId(r.font, 0x0302) != 0); // combining hat
    try std.testing.expect(try glyphId(r.font, 0x0338) != 0); // combining slash
    try std.testing.expectEqual(@as(u16, 0), try glyphId(r.font, 0x10FFFF));
}

test "reference paren variants grow monotonically" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    const p0 = try glyphId(r.font, '(');
    // Natural vertical extent 997: min below it keeps the base glyph.
    try std.testing.expectEqual(p0, try vertVariant(r.font, p0, 500));
    // min 2000 lands between .v4 (1793) and .v5 (2093) → gid 2455.
    const v5 = try vertVariant(r.font, p0, 2000);
    try std.testing.expectEqual(@as(u16, 2455), v5);
    // Beyond the tallest (.v7, 2991) keeps the base glyph.
    try std.testing.expectEqual(p0, try vertVariant(r.font, p0, 100000));
}

test "reference italic correction matches ground truth" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    const x = try glyphId(r.font, 'x');
    try std.testing.expectEqual(@as(i32, 16), try italicCorrection(r.font, x));
    const xi = try glyphId(r.font, 0x03BE);
    try std.testing.expectEqual(@as(i32, 0), try italicCorrection(r.font, xi));
}
