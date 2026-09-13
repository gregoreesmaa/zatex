//! ZaTeX OpenType reader: metrics hosts need for the provider.
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
    stack_top_shift_up = 22,
    stack_bottom_shift_down = 24,
    stack_gap_min = 26,
    stretch_stack_gap_above_min = 30,
    stretch_stack_gap_below_min = 31,
    frac_num_shift_up = 32,
    frac_num_display_shift_up = 33,
    frac_den_shift_down = 34,
    frac_den_display_shift_down = 35,
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
            // Format 12: groups follow the 16-byte header (ngroups at
            // +12). No length gate: the header length is never zero.
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
/// (font units). When nothing is tall enough, the tallest variant
/// (assemblies are not parsed yet — documented in the IR guide).
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
    var tallest: u16 = glyph;
    var i: usize = 0;
    while (i < nvar) : (i += 1) {
        const vg = try u16be(b, recs + i * 4);
        const av = try u16be(b, recs + i * 4 + 2);
        tallest = vg;
        if (@as(i32, av) >= min_advance) return vg;
    }
    return tallest;
}

/// MathKern corner for script cut-ins (sup/sub positioning).
pub const KernCorner = enum {
    top_right,
    top_left,
    bottom_right,
    bottom_left,
};

/// MathKern cut-in for `glyph` at correction `height` (font units,
/// measured upward for top corners, downward for bottom corners).
/// Returns 0 when the font has no kern table, the glyph is uncovered,
/// or the corner is NULL — hosts treat 0 as "no cut-in". The vendored
/// reference font carries no MathKern table (verified offset 0), so
/// real-font calibration asserts graceful zeros while selection logic
/// is pinned by the synthetic fixture below.
pub fn kernCorrection(f: Font, glyph: u16, height: i32, corner: KernCorner) Error!i32 {
    if (f.math_off == 0) return error.UnsupportedTable;
    const b = f.bytes;
    // MathGlyphInfo holds four offsets (italics, top-accent,
    // extended-shape, kern); kern absent (0) means no cut-ins.
    const ki_rel = try u16be(b, f.glyph_info_off + 6);
    if (ki_rel == 0) return 0;
    const ki = f.glyph_info_off + ki_rel;
    const cov_rel = try u16be(b, ki);
    if (cov_rel == 0) return 0;
    const idx = (try coverageIndex(b, ki + cov_rel, glyph)) orelse return 0;
    const count = try u16be(b, ki + 2);
    if (idx >= count) return 0;
    const rec = ki + 4 + idx * 8;
    const corner_off: usize = switch (corner) {
        .top_right => 0,
        .top_left => 2,
        .bottom_right => 4,
        .bottom_left => 6,
    };
    const t_rel = try u16be(b, rec + corner_off);
    if (t_rel == 0) return 0;
    const t = ki + t_rel;
    const n = try u16be(b, t);
    // CorrectionHeight[n] are MathValueRecords (value i16 + device
    // u16); KernValues[n+1] follow as i16s. First height at or above
    // the query wins, else the last value (OpenType MATH semantics).
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const h = try i16be(b, t + 2 + i * 4);
        if (height <= h) break;
    }
    return try i16be(b, t + 2 + n * 4 + i * 2);
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
    // Beyond the tallest (.v7 gid 2499, 2991) falls back to it.
    try std.testing.expectEqual(@as(u16, 2499), try vertVariant(r.font, p0, 100000));
}

test "reference italic correction matches ground truth" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    const x = try glyphId(r.font, 'x');
    try std.testing.expectEqual(@as(i32, 16), try italicCorrection(r.font, x));
    const xi = try glyphId(r.font, 0x03BE);
    try std.testing.expectEqual(@as(i32, 0), try italicCorrection(r.font, xi));
}

test "reference stack/fraction/over/under constants match ground truth" {
    // fontTools cross-checks (issue #26): StackGap/FractionShift/
    // RadicalGap families in font units.
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    try std.testing.expectEqual(@as(i16, 444), try constant(r.font, .stack_top_shift_up));
    try std.testing.expectEqual(@as(i16, 345), try constant(r.font, .stack_bottom_shift_down));
    try std.testing.expectEqual(@as(i16, 120), try constant(r.font, .stack_gap_min));
    try std.testing.expectEqual(@as(i16, 200), try constant(r.font, .stretch_stack_gap_above_min));
    try std.testing.expectEqual(@as(i16, 167), try constant(r.font, .stretch_stack_gap_below_min));
    try std.testing.expectEqual(@as(i16, 394), try constant(r.font, .frac_num_shift_up));
    try std.testing.expectEqual(@as(i16, 677), try constant(r.font, .frac_num_display_shift_up));
    try std.testing.expectEqual(@as(i16, 345), try constant(r.font, .frac_den_shift_down));
    try std.testing.expectEqual(@as(i16, 686), try constant(r.font, .frac_den_display_shift_down));
    try std.testing.expectEqual(@as(i16, 40), try constant(r.font, .frac_num_gap_min));
    try std.testing.expectEqual(@as(i16, 40), try constant(r.font, .frac_den_gap_min));
    try std.testing.expectEqual(@as(i16, 40), try constant(r.font, .overbar_rule));
    try std.testing.expectEqual(@as(i16, 120), try constant(r.font, .overbar_gap));
    try std.testing.expectEqual(@as(i16, 40), try constant(r.font, .underbar_rule));
    try std.testing.expectEqual(@as(i16, 120), try constant(r.font, .underbar_gap));
    try std.testing.expectEqual(@as(i16, 50), try constant(r.font, .radical_gap));
    try std.testing.expectEqual(@as(i16, 148), try constant(r.font, .radical_display_gap));
    try std.testing.expectEqual(@as(i16, 160), try constant(r.font, .subsup_gap_min));
    try std.testing.expectEqual(@as(i16, 56), try constant(r.font, .space_after_script));
    try std.testing.expectEqual(@as(i16, 200), try constant(r.font, .upper_limit_gap_min));
    try std.testing.expectEqual(@as(i16, 167), try constant(r.font, .lower_limit_gap_min));
}

test "reference bracket/brace/sum variants grow monotonically" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    const br = try glyphId(r.font, '[');
    try std.testing.expectEqual(@as(u16, 60), br);
    try std.testing.expectEqual(br, try vertVariant(r.font, br, 500));
    try std.testing.expectEqual(@as(u16, 2461), try vertVariant(r.font, br, 2000));
    const brace = try glyphId(r.font, '{');
    try std.testing.expectEqual(@as(u16, 92), brace);
    try std.testing.expectEqual(@as(u16, 2459), try vertVariant(r.font, brace, 2000));
    const sum = try glyphId(r.font, 0x2211);
    try std.testing.expectEqual(@as(u16, 3060), sum);
    try std.testing.expectEqual(sum, try vertVariant(r.font, sum, 500));
    try std.testing.expectEqual(@as(u16, 3074), try vertVariant(r.font, sum, 1200));
    // Beyond the tallest falls back to it (no assemblies parsed).
    try std.testing.expectEqual(@as(u16, 3074), try vertVariant(r.font, sum, 100000));
}

test "reference font carries no kern table: cut-ins are zero" {
    // fontTools confirms MathKernInfo is absent in Latin Modern Math,
    // so every corner/height must read back graceful zeros.
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    const x = try glyphId(r.font, 'x');
    const sum = try glyphId(r.font, 0x2211);
    for ([_]u16{ x, sum }) |gid| {
        for ([_]KernCorner{ .top_right, .top_left, .bottom_right, .bottom_left }) |c| {
            for ([_]i32{ 0, 100, 1000 }) |h| {
                try std.testing.expectEqual(@as(i32, 0), try kernCorrection(r.font, gid, h, c));
            }
        }
    }
}

// Minimal synthetic font with a MathKern table: pins corner routing
// and height selection without depending on any real font carrying
// kern data (none vendored does).
const KernFixture = struct {
    buf: [512]u8 = .{0} ** 512,
    pos: usize = 0,

    fn w16(self: *KernFixture, v: u16) void {
        self.buf[self.pos] = @intCast(v >> 8);
        self.buf[self.pos + 1] = @intCast(v & 0xFF);
        self.pos += 2;
    }

    fn w32(self: *KernFixture, v: u32) void {
        self.w16(@intCast(v >> 16));
        self.w16(@intCast(v & 0xFFFF));
    }

    fn bytes(self: *KernFixture) []const u8 {
        return self.buf[0..self.pos];
    }
};

test "kern corner routing and height selection" {
    // Hand-laid MATH bytes (see kernCorrection): coverage {7}, one
    // record with TR heights [100, 300] -> kerns [10, 20, 30] and BR
    // heights [200] -> kerns [5, 15]; TL/BL NULL.
    var f = KernFixture{};
    // --- sfnt header: version + 6 tables ---
    f.w32(0x00010000);
    f.w16(6);
    f.w16(0);
    f.w16(0);
    f.w16(0);
    const dir_at = f.pos;
    // Reserve 6 x 16-byte records (tag, checksum, offset, length).
    const tags = [_]u32{ 0x68656164, 0x6D617870, 0x636D6170, 0x686D7478, 0x68686561, 0x4D415448 };
    for (tags) |t| {
        f.w32(t);
        f.w32(0);
        f.w32(0);
        f.w32(0);
    }
    var starts: [6]usize = .{ 0, 0, 0, 0, 0, 0 };
    var lens: [6]usize = .{ 0, 0, 0, 0, 0, 0 };
    // head: upm at +18.
    starts[0] = f.pos;
    for (0..9) |_| f.w16(0);
    f.w16(1000);
    lens[0] = f.pos - starts[0];
    // maxp: numglyphs at +4.
    starts[1] = f.pos;
    f.w32(0);
    f.w16(8);
    lens[1] = f.pos - starts[1];
    // cmap: one (3,10) -> format12 group [0x78, 0x78] -> gid 7.
    starts[2] = f.pos;
    f.w16(0);
    f.w16(1);
    f.w16(3);
    f.w16(10);
    f.w32(20);
    // pad to subtable at cmap+20
    while (f.pos < starts[2] + 20) f.w16(0);
    f.w16(12);
    f.w16(0);
    f.w32(28);
    f.w32(0);
    f.w32(1);
    f.w32(0x78);
    f.w32(0x78);
    f.w32(7);
    lens[2] = f.pos - starts[2];
    // hmtx: 2 advances.
    starts[3] = f.pos;
    f.w16(600);
    f.w16(700);
    lens[3] = f.pos - starts[3];
    // hhea: hmetrics at +34.
    starts[4] = f.pos;
    for (0..17) |_| f.w16(0);
    f.w16(2);
    lens[4] = f.pos - starts[4];
    // MATH: version + const/glyphinfo/variants offsets.
    starts[5] = f.pos;
    const math_at = f.pos;
    f.w32(0x00010000);
    f.w16(190); // const (padding zeros: nothing reads it here)
    f.w16(10); // glyphinfo (content follows immediately)
    f.w16(200); // variants (dummy: load stores the offset only)
    // glyphinfo at math+12: ital/accent/ext/kern offsets.
    const gio = f.pos;
    _ = gio;
    f.w16(0);
    f.w16(0);
    f.w16(0);
    const kern_rel_at = f.pos;
    f.w16(0); // patched to kern table below
    // kern info table.
    const ki = f.pos;
    const cov_rel_at = f.pos;
    f.w16(0); // patched: coverage follows records
    f.w16(1); // one record
    const tr_rel_at = f.pos;
    f.w16(0);
    f.w16(0); // TL NULL
    const br_rel_at = f.pos;
    f.w16(0);
    f.w16(0); // BL NULL
    // coverage format1 {7}.
    const cov = f.pos;
    f.w16(1);
    f.w16(1);
    f.w16(7);
    // TR table: heights [100, 300] -> kerns [10, 20, 30].
    const tr = f.pos;
    f.w16(2);
    f.w16(100);
    f.w16(0);
    f.w16(300);
    f.w16(0);
    f.w16(10);
    f.w16(20);
    f.w16(30);
    // BR table: heights [200] -> kerns [5, 15].
    const br = f.pos;
    f.w16(1);
    f.w16(200);
    f.w16(0);
    f.w16(5);
    f.w16(15);
    // variants dummy.
    while (f.pos < math_at + 200) f.w16(0);
    f.w16(0);
    lens[5] = f.pos - starts[5];
    // Patch directory + internals.
    for (0..6) |k| {
        const at = dir_at + k * 16 + 8;
        f.buf[at] = @intCast(starts[k] >> 24);
        f.buf[at + 1] = @intCast((starts[k] >> 16) & 0xFF);
        f.buf[at + 2] = @intCast((starts[k] >> 8) & 0xFF);
        f.buf[at + 3] = @intCast(starts[k] & 0xFF);
        const ln = dir_at + k * 16 + 12;
        f.buf[ln] = @intCast(lens[k] >> 24);
        f.buf[ln + 1] = @intCast((lens[k] >> 16) & 0xFF);
        f.buf[ln + 2] = @intCast((lens[k] >> 8) & 0xFF);
        f.buf[ln + 3] = @intCast(lens[k] & 0xFF);
    }
    const patch = struct {
        fn u16at(buf: *[512]u8, at: usize, v: usize) void {
            buf[at] = @intCast(v >> 8);
            buf[at + 1] = @intCast(v & 0xFF);
        }
    }.u16at;
    patch(&f.buf, kern_rel_at, ki - (math_at + 10));
    patch(&f.buf, cov_rel_at, cov - ki);
    patch(&f.buf, tr_rel_at, tr - ki);
    patch(&f.buf, br_rel_at, br - ki);
    const font = try load(f.bytes());
    try std.testing.expectEqual(@as(u16, 7), try glyphId(font, 'x'));
    // TR selection: at-or-below first height, between, above last.
    try std.testing.expectEqual(@as(i32, 10), try kernCorrection(font, 7, 0, .top_right));
    try std.testing.expectEqual(@as(i32, 10), try kernCorrection(font, 7, 100, .top_right));
    try std.testing.expectEqual(@as(i32, 20), try kernCorrection(font, 7, 101, .top_right));
    try std.testing.expectEqual(@as(i32, 20), try kernCorrection(font, 7, 300, .top_right));
    try std.testing.expectEqual(@as(i32, 30), try kernCorrection(font, 7, 301, .top_right));
    // BR selection.
    try std.testing.expectEqual(@as(i32, 5), try kernCorrection(font, 7, 200, .bottom_right));
    try std.testing.expectEqual(@as(i32, 15), try kernCorrection(font, 7, 201, .bottom_right));
    // NULL corners and uncovered glyphs read zero.
    try std.testing.expectEqual(@as(i32, 0), try kernCorrection(font, 7, 100, .top_left));
    try std.testing.expectEqual(@as(i32, 0), try kernCorrection(font, 7, 100, .bottom_left));
    try std.testing.expectEqual(@as(i32, 0), try kernCorrection(font, 3, 100, .top_right));
}
