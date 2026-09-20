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

// ---------------------------------------------------------------------------
// CFF outline bounds: true ink boxes for the v4 `inkBounds` provider
// hook (issue #194 conformance corpus).
//
// Host-side like everything else here: the core never touches font
// files. Parses the CFF table (Type 2 charstrings) tracking only the
// current point and a bounding box — no rasterization, no floats:
// cubic extrema resolve by adaptive De Casteljau subdivision in 16.16
// fixed point (leaf chords bound the truth within 1/32 unit, so the
// rounded box matches a fontTools BoundsPen exactly on every fixture
// glyph; the conformance doc records the differential).
//
// Charstring ops covered: the moveto/lineto/curve families (opcodes
// 4-8, 21-27, 30-31, plus rcurveline/rlinecurve and the flex family),
// stems and hint/counter masks (stem counts only — mask bytes are
// skipped), subrs, shortint and 255-fixed numbers. Anything else
// (seac endchar, arithmetic/stack ops, blend, CID-keyed CFF) reports
// `error.UnsupportedTable`, and the caller falls back to the
// degenerate box — the core ignores degenerate boxes exactly, so this
// degrades to v3 behavior, never to a wrong box. `Font` gains no
// fields (CFF offsets re-parse per call; hosts cache per-glyph boxes).
// ---------------------------------------------------------------------------

fn u8at(b: []const u8, off: usize) Error!u8 {
    if (off >= b.len) return error.Truncated;
    return b[off];
}

fn readOff(b: []const u8, at: usize, size: u8) Error!u32 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < size) : (i += 1) v = (v << 8) | try u8at(b, at + i);
    return v;
}

const CffIndex = struct {
    count: u32,
    off_size: u8,
    offs: usize,
    data: usize,
};

fn cffIndex(bytes: []const u8, off: usize) Error!struct { idx: CffIndex, next: usize } {
    const count = try u16be(bytes, off);
    if (count == 0) return .{
        .idx = .{ .count = 0, .off_size = 0, .offs = 0, .data = off + 2 },
        .next = off + 2,
    };
    const os = try u8at(bytes, off + 2);
    if (os < 1 or os > 4) return error.UnsupportedTable;
    const offs = off + 3;
    const data = offs + (@as(usize, count) + 1) * os;
    if (data > bytes.len) return error.Truncated;
    const last = try readOff(bytes, offs + @as(usize, count) * os, os);
    if (last == 0) return error.UnsupportedTable;
    const next = data + last - 1;
    if (next > bytes.len) return error.Truncated;
    return .{ .idx = .{ .count = count, .off_size = os, .offs = offs, .data = data }, .next = next };
}

fn cffElem(bytes: []const u8, idx: CffIndex, i: u32) Error![]const u8 {
    if (i >= idx.count) return error.Truncated;
    const s = try readOff(bytes, idx.offs + @as(usize, i) * idx.off_size, idx.off_size);
    const e = try readOff(bytes, idx.offs + (@as(usize, i) + 1) * idx.off_size, idx.off_size);
    if (s == 0 or e < s) return error.UnsupportedTable;
    const a = idx.data + s - 1;
    const b = idx.data + e - 1;
    if (b > bytes.len or a > b) return error.Truncated;
    return bytes[a..b];
}

/// One DICT number (Top/Private encoding: shortint 28, longint 29;
/// real 30 never carries an offset, so it is rejected). `b0` is the
/// already-consumed first byte; `pos` reads any following bytes.
fn dictNum(prog: []const u8, b0: u8, pos: *usize) Error!i64 {
    if (b0 == 28) {
        const v = try i16be(prog, pos.*);
        pos.* += 2;
        return v;
    }
    if (b0 == 29) {
        const v = try u32be(prog, pos.*);
        pos.* += 4;
        return @as(i64, @as(i32, @bitCast(v)));
    }
    if (b0 >= 32 and b0 <= 246) {
        // Single-byte number: already consumed, nothing follows.
        return @as(i64, b0) - 139;
    }
    if (b0 >= 247 and b0 <= 250) {
        const b1 = try u8at(prog, pos.*);
        pos.* += 1;
        return (@as(i64, b0) - 247) * 256 + b1 + 108;
    }
    if (b0 >= 251 and b0 <= 254) {
        const b1 = try u8at(prog, pos.*);
        pos.* += 1;
        return -((@as(i64, b0) - 251) * 256 + b1 + 108);
    }
    if (b0 == 30) {
        // BCD real (FontMatrix, ItalicAngle, ...): consume nibbles
        // to the 0xF terminator. Offsets never need the value, so a
        // placeholder keeps the operand scan in sync.
        while (true) {
            if (pos.* >= prog.len) return error.Truncated;
            const byte = prog[pos.*];
            pos.* += 1;
            if (byte >> 4 == 0xF or byte & 0xF == 0xF) break;
        }
        return 0;
    }
    return error.UnsupportedTable;
}

const CffCtx = struct {
    bytes: []const u8,
    cs: CffIndex,
    local: ?CffIndex,
    global: ?CffIndex,
};

/// Operands of single-byte DICT op `want` (null when absent).
/// Escape 12,30 (ROS) rejects CID-keyed CFF outright: glyph ids do
/// not index CharStrings there. Long operand runs (BlueValues
/// arrays, ...) saturate the store: only the first two are kept and
/// the count is exact, so callers still validate their arity.
fn dictOp(prog: []const u8, want: u8) Error!?struct { n: usize, v: [2]i64 } {
    var ops: [2]i64 = .{ 0, 0 };
    var nops: usize = 0;
    var pos: usize = 0;
    while (pos < prog.len) {
        const b = prog[pos];
        pos += 1;
        if (b == 12) {
            if (pos >= prog.len) return error.Truncated;
            if (prog[pos] == 30) return error.UnsupportedTable;
            pos += 1;
            nops = 0;
            continue;
        }
        if (b <= 21) {
            if (b == want) return .{ .n = nops, .v = ops };
            nops = 0;
            continue;
        }
        if (b <= 27 or b == 31) return error.UnsupportedTable;
        const v = try dictNum(prog, b, &pos);
        if (nops < ops.len) ops[nops] = v;
        nops += 1;
    }
    return null;
}

fn cffCtx(f: Font) Error!CffCtx {
    const bytes = f.bytes;
    const base = tableOff(bytes, tag('C', 'F', 'F', ' ')) catch return error.UnsupportedTable;
    if (try u8at(bytes, base) != 1) return error.UnsupportedTable;
    const hdr = try u8at(bytes, base + 2);
    if (hdr < 4) return error.UnsupportedTable;
    var pos = base + hdr;
    pos = (try cffIndex(bytes, pos)).next; // Name
    const topi = try cffIndex(bytes, pos);
    pos = topi.next;
    if (topi.idx.count == 0) return error.UnsupportedTable;
    pos = (try cffIndex(bytes, pos)).next; // String
    const gsi = try cffIndex(bytes, pos);
    const top = try cffElem(bytes, topi.idx, 0);
    // Top DICT: CharStrings 17, Private 18 (size, offset).
    const cs = try dictOp(top, 17);
    if (cs == null or cs.?.n != 1 or cs.?.v[0] < 0) return error.UnsupportedTable;
    const cs_abs = base + @as(usize, @intCast(cs.?.v[0]));
    if (cs_abs >= bytes.len) return error.Truncated;
    const csi = (try cffIndex(bytes, cs_abs)).idx;
    var local: ?CffIndex = null;
    if (try dictOp(top, 18)) |pr| {
        if (pr.n != 2 or pr.v[0] < 0 or pr.v[1] < 0) return error.UnsupportedTable;
        // Size 0 declares no Private dict (converter fonts); only a
        // positive size carries a Subrs offset worth parsing.
        const size: usize = @intCast(pr.v[0]);
        if (size == 0) return .{
            .bytes = bytes,
            .cs = csi,
            .local = null,
            .global = if (gsi.idx.count == 0) null else gsi.idx,
        };
        const priv_abs = base + @as(usize, @intCast(pr.v[1]));
        if (priv_abs + size < priv_abs or priv_abs + size > bytes.len) return error.Truncated;
        // Private DICT: Subrs 19 (offset relative to Private start).
        if (try dictOp(bytes[priv_abs..][0..size], 19)) |sr| {
            if (sr.n != 1 or sr.v[0] < 0) return error.UnsupportedTable;
            const sub_abs = priv_abs + @as(usize, @intCast(sr.v[0]));
            if (sub_abs >= bytes.len) return error.Truncated;
            const li = (try cffIndex(bytes, sub_abs)).idx;
            if (li.count != 0) local = li;
        }
    }
    return .{
        .bytes = bytes,
        .cs = csi,
        .local = local,
        .global = if (gsi.idx.count == 0) null else gsi.idx,
    };
}

/// Bounds-machine state: current point in font units, box in 16.16.
const BoundsSt = struct {
    x: i32,
    y: i32,
    stack: [48]i32,
    n: u8,
    have_width: bool,
    nstems: u32,
    /// Mask byte count, frozen at the first mask (fontTools parity:
    /// later stems do not resize earlier masks).
    mask_bytes: ?u32,
    x0: i64,
    y0: i64,
    x1: i64,
    y1: i64,
    any: bool,
};

fn bPush(st: *BoundsSt, v: i32) Error!void {
    if (st.n >= st.stack.len) return error.UnsupportedTable;
    st.stack[st.n] = v;
    st.n += 1;
}

fn bPop(st: *BoundsSt) Error!i32 {
    if (st.n == 0) return error.UnsupportedTable;
    st.n -= 1;
    return st.stack[st.n];
}

/// First stem/move/mask clears a leading width argument (fontTools
/// `popallWidth` parity: stems, rmoveto and masks strip on odd depth;
/// hmoveto/vmoveto strip on even depth — a lone [width] before
/// h/vmoveto is the common converter pattern).
fn widthClear(st: *BoundsSt, even_odd: u8) void {
    if (st.have_width) return;
    st.have_width = true;
    if (st.n % 2 == even_odd) {
        var i: usize = 0;
        while (i + 1 < st.n) : (i += 1) st.stack[i] = st.stack[i + 1];
        st.n -= 1;
    }
}

fn endpt(st: *BoundsSt, x: i64, y: i64) void {
    if (!st.any) {
        st.x0 = x;
        st.x1 = x;
        st.y0 = y;
        st.y1 = y;
        st.any = true;
        return;
    }
    st.x0 = @min(st.x0, x);
    st.x1 = @max(st.x1, x);
    st.y0 = @min(st.y0, y);
    st.y1 = @max(st.y1, y);
}

fn dot(st: *BoundsSt, x: i32, y: i32) void {
    endpt(st, @as(i64, x) << 16, @as(i64, y) << 16);
}

/// One cubic from the current point through three relative deltas.
/// Adaptive De Casteljau subdivision: a leaf whose control hull
/// exceeds the endpoint box by at most 1/32 unit contributes its
/// endpoints (the chord under-reads the truth by less than that).
fn curve(st: *BoundsSt, dx1: i32, dy1: i32, dx2: i32, dy2: i32, dx3: i32, dy3: i32) Error!void {
    const ax = @as(i64, st.x) << 16;
    const ay = @as(i64, st.y) << 16;
    const bx = ax +% (@as(i64, dx1) << 16);
    const by = ay +% (@as(i64, dy1) << 16);
    const cx = bx +% (@as(i64, dx2) << 16);
    const cy = by +% (@as(i64, dy2) << 16);
    const dx = cx +% (@as(i64, dx3) << 16);
    const dy = cy +% (@as(i64, dy3) << 16);
    try sub(st, ax, ay, bx, by, cx, cy, dx, dy, 0);
    st.x +%= dx1 +% dx2 +% dx3;
    st.y +%= dy1 +% dy2 +% dy3;
}

fn sub(st: *BoundsSt, ax: i64, ay: i64, bx: i64, by: i64, cx: i64, cy: i64, dx: i64, dy: i64, level: u8) Error!void {
    if (level >= 24) return error.UnsupportedTable;
    const hx0 = @min(@min(ax, bx), @min(cx, dx));
    const hx1 = @max(@max(ax, bx), @max(cx, dx));
    const hy0 = @min(@min(ay, by), @min(cy, dy));
    const hy1 = @max(@max(ay, by), @max(cy, dy));
    // Hull excess outside the endpoint box (both terms >= 0: the
    // hull always contains the endpoints).
    const ex = (@min(ax, dx) - hx0) + (hx1 - @max(ax, dx));
    const ey = (@min(ay, dy) - hy0) + (hy1 - @max(ay, dy));
    // Leaf chords under-read the truth by less than 1/256 unit, so
    // the rounded box flips only when the truth sits within 1/256
    // of a .5 tie (documented residue, verified per glyph).
    if (ex + ey <= 256) {
        endpt(st, ax, ay);
        endpt(st, dx, dy);
        return;
    }
    const abx = @divTrunc(ax + bx, 2);
    const aby = @divTrunc(ay + by, 2);
    const bcx = @divTrunc(bx + cx, 2);
    const bcy = @divTrunc(by + cy, 2);
    const cdx = @divTrunc(cx + dx, 2);
    const cdy = @divTrunc(cy + dy, 2);
    const abcx = @divTrunc(abx + bcx, 2);
    const abcy = @divTrunc(aby + bcy, 2);
    const bcdx = @divTrunc(bcx + cdx, 2);
    const bcdy = @divTrunc(bcy + cdy, 2);
    const mx = @divTrunc(abcx + bcdx, 2);
    const my = @divTrunc(abcy + bcdy, 2);
    try sub(st, ax, ay, abx, aby, abcx, abcy, mx, my, level + 1);
    try sub(st, mx, my, bcdx, bcdy, cdx, cdy, dx, dy, level + 1);
}

/// One charstring number (opcodes dispatch below).
fn csNum(prog: []const u8, b0: u8, pos: *usize) Error!i32 {
    if (b0 >= 32 and b0 <= 246) return @as(i32, b0) - 139;
    if (b0 >= 247 and b0 <= 250) {
        const b1: i32 = try u8at(prog, pos.*);
        pos.* += 1;
        return (@as(i32, b0) - 247) * 256 + b1 + 108;
    }
    if (b0 >= 251 and b0 <= 254) {
        const b1: i32 = try u8at(prog, pos.*);
        pos.* += 1;
        return -((@as(i32, b0) - 251) * 256 + b1 + 108);
    }
    // 255: 16.16 fixed, rounded to the nearest unit.
    const w: i64 = @as(i32, @bitCast(try u32be(prog, pos.*)));
    pos.* += 4;
    if (w >= 0) return @intCast(@divTrunc(w + 32768, 65536));
    return @intCast(-@divTrunc(-w + 32768, 65536));
}

fn subrBias(count: u32) i32 {
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
}

fn runCs(ctx: *const CffCtx, prog: []const u8, st: *BoundsSt, depth: u8) Error!void {
    if (depth > 10) return error.UnsupportedTable;
    var pos: usize = 0;
    while (pos < prog.len) {
        const b = prog[pos];
        pos += 1;
        if (b == 28) {
            try bPush(st, try i16be(prog, pos));
            pos += 2;
            continue;
        }
        if (b >= 32) {
            try bPush(st, try csNum(prog, b, &pos));
            continue;
        }
        switch (b) {
            1, 3, 18, 23 => { // hstem, vstem, hstemhm, vstemhm
                widthClear(st, 1);
                if (st.n % 2 != 0) return error.UnsupportedTable;
                // Sequential subr calls re-execute stem ops: cap the
                // total so hostile bytes cannot overflow the counter.
                if (st.nstems > (1 << 20)) return error.UnsupportedTable;
                st.nstems += @as(u32, st.n) / 2;
                st.n = 0;
            },
            19, 20 => { // hintmask, cntrmask
                widthClear(st, 1);
                // Implied stems: bare stem pairs before a mask count
                // without an explicit stem op (fontTools countHints).
                if (st.n % 2 != 0) return error.UnsupportedTable;
                if (st.nstems > (1 << 20)) return error.UnsupportedTable;
                st.nstems += @as(u32, st.n) / 2;
                if (st.mask_bytes == null) st.mask_bytes = (st.nstems + 7) / 8;
                const skip = st.mask_bytes.?;
                if (pos + skip > prog.len) return error.Truncated;
                pos += skip;
                st.n = 0;
            },
            21 => { // rmoveto
                widthClear(st, 1);
                if (st.n != 2) return error.UnsupportedTable;
                st.x +%= st.stack[0];
                st.y +%= st.stack[1];
                dot(st, st.x, st.y);
                st.n = 0;
            },
            22 => { // hmoveto
                widthClear(st, 0);
                if (st.n != 1) return error.UnsupportedTable;
                st.x +%= st.stack[0];
                dot(st, st.x, st.y);
                st.n = 0;
            },
            4 => { // vmoveto
                widthClear(st, 0);
                if (st.n != 1) return error.UnsupportedTable;
                st.y +%= st.stack[0];
                dot(st, st.x, st.y);
                st.n = 0;
            },
            5 => { // rlineto
                if (st.n % 2 != 0) return error.UnsupportedTable;
                var i: usize = 0;
                while (i < st.n) : (i += 2) {
                    st.x +%= st.stack[i];
                    st.y +%= st.stack[i + 1];
                    dot(st, st.x, st.y);
                }
                st.n = 0;
            },
            6, 7 => { // hlineto, vlineto (alternating from h/v)
                var horiz = b == 6;
                for (st.stack[0..st.n]) |d| {
                    if (horiz) {
                        st.x +%= d;
                    } else {
                        st.y +%= d;
                    }
                    dot(st, st.x, st.y);
                    horiz = !horiz;
                }
                st.n = 0;
            },
            8 => { // rrcurveto
                if (st.n % 6 != 0) return error.UnsupportedTable;
                var i: usize = 0;
                while (i < st.n) : (i += 6) {
                    try curve(st, st.stack[i], st.stack[i + 1], st.stack[i + 2], st.stack[i + 3], st.stack[i + 4], st.stack[i + 5]);
                }
                st.n = 0;
            },
            24 => { // rcurveline: curves of six, then one line
                if (st.n < 8 or (st.n - 2) % 6 != 0) return error.UnsupportedTable;
                var i: usize = 0;
                while (i < st.n - 2) : (i += 6) {
                    try curve(st, st.stack[i], st.stack[i + 1], st.stack[i + 2], st.stack[i + 3], st.stack[i + 4], st.stack[i + 5]);
                }
                st.x +%= st.stack[st.n - 2];
                st.y +%= st.stack[st.n - 1];
                dot(st, st.x, st.y);
                st.n = 0;
            },
            25 => { // rlinecurve: lines, then one curve of six
                if (st.n < 8 or st.n % 2 != 0) return error.UnsupportedTable;
                var i: usize = 0;
                while (i < st.n - 6) : (i += 2) {
                    st.x +%= st.stack[i];
                    st.y +%= st.stack[i + 1];
                    dot(st, st.x, st.y);
                }
                try curve(st, st.stack[st.n - 6], st.stack[st.n - 5], st.stack[st.n - 4], st.stack[st.n - 3], st.stack[st.n - 2], st.stack[st.n - 1]);
                st.n = 0;
            },
            26 => { // vvcurveto: odd head is dx1, then groups of four
                var k: usize = 0;
                var dx1: i32 = 0;
                if (st.n % 2 == 1) {
                    dx1 = st.stack[0];
                    k = 1;
                }
                if ((st.n - k) % 4 != 0) return error.UnsupportedTable;
                while (k < st.n) : (k += 4) {
                    try curve(st, dx1, st.stack[k], st.stack[k + 1], st.stack[k + 2], 0, st.stack[k + 3]);
                    dx1 = 0;
                }
                st.n = 0;
            },
            27 => { // hhcurveto: odd head is dy1, then groups of four
                var k: usize = 0;
                var dy1: i32 = 0;
                if (st.n % 2 == 1) {
                    dy1 = st.stack[0];
                    k = 1;
                }
                if ((st.n - k) % 4 != 0) return error.UnsupportedTable;
                while (k < st.n) : (k += 4) {
                    try curve(st, st.stack[k], dy1, st.stack[k + 1], st.stack[k + 2], st.stack[k + 3], 0);
                    dy1 = 0;
                }
                st.n = 0;
            },
            30, 31 => { // vhcurveto, hvcurveto: alternating quartets
                var k: usize = 0;
                // Group orientation alternates starting vertical (30)
                // or horizontal (31); a lone trailing arg completes the
                // last curve along its end tangent (fontTools parity).
                var vert = b == 30;
                while (k < st.n) {
                    if (st.n - k < 4) return error.UnsupportedTable;
                    if (vert) {
                        var dyc: i32 = 0;
                        var end = k + 4;
                        if (st.n - end == 1) {
                            dyc = st.stack[st.n - 1];
                            end = st.n;
                        } else if (st.n - end != 0 and (st.n - end) % 4 != 0 and st.n - end < 4) {
                            return error.UnsupportedTable;
                        }
                        try curve(st, 0, st.stack[k], st.stack[k + 1], st.stack[k + 2], st.stack[k + 3], dyc);
                        k = end;
                    } else {
                        var dxc: i32 = 0;
                        var end = k + 4;
                        if (st.n - end == 1) {
                            dxc = st.stack[st.n - 1];
                            end = st.n;
                        } else if (st.n - end != 0 and (st.n - end) % 4 != 0 and st.n - end < 4) {
                            return error.UnsupportedTable;
                        }
                        try curve(st, st.stack[k], 0, st.stack[k + 1], st.stack[k + 2], dxc, st.stack[k + 3]);
                        k = end;
                    }
                    vert = !vert;
                }
                st.n = 0;
            },
            10, 29 => { // callsubr, callgsubr
                const num = try bPop(st);
                const subrs = if (b == 10) ctx.local else ctx.global;
                const idx = subrs orelse return error.UnsupportedTable;
                const which = num +% subrBias(idx.count);
                if (which < 0) return error.UnsupportedTable;
                try runCs(ctx, try cffElem(ctx.bytes, idx, @intCast(which)), st, depth + 1);
            },
            11 => { // return (malformed at top level)
                if (depth == 0) return error.UnsupportedTable;
                return;
            },
            14 => { // endchar: bare ends the outline; seac carries args
                if (st.n <= 1) {
                    st.n = 0;
                    return;
                }
                return error.UnsupportedTable;
            },
            12 => {
                if (pos >= prog.len) return error.Truncated;
                const e = prog[pos];
                pos += 1;
                switch (e) {
                    0 => {}, // dotsection: deprecated no-op
                    34 => { // hflex
                        if (st.n != 7) return error.UnsupportedTable;
                        const s = st.stack;
                        try curve(st, s[0], 0, s[1], s[2], s[3], 0);
                        try curve(st, s[4], 0, s[5], 0 -% s[2], s[6], 0);
                        st.n = 0;
                    },
                    35 => { // flex
                        if (st.n != 13) return error.UnsupportedTable;
                        const s = st.stack;
                        try curve(st, s[0], s[1], s[2], s[3], s[4], s[5]);
                        try curve(st, s[6], s[7], s[8], s[9], s[10], s[11]);
                        st.n = 0;
                    },
                    36 => { // hflex1
                        if (st.n != 9) return error.UnsupportedTable;
                        const s = st.stack;
                        const dy6 = 0 -% (s[1] +% s[3] +% s[5] +% s[7]);
                        try curve(st, s[0], s[1], s[2], s[3], s[4], 0);
                        try curve(st, s[5], 0, s[6], s[7], s[8], dy6);
                        st.n = 0;
                    },
                    37 => { // flex1
                        if (st.n != 11) return error.UnsupportedTable;
                        const s = st.stack;
                        const dx = s[0] +% s[2] +% s[4] +% s[6] +% s[8];
                        const dy = s[1] +% s[3] +% s[5] +% s[7] +% s[9];
                        var dx6 = s[10];
                        var dy6: i32 = 0;
                        const ax = if (dx == std.math.minInt(i32)) @as(u32, 0x80000000) else @abs(dx);
                        const ay = if (dy == std.math.minInt(i32)) @as(u32, 0x80000000) else @abs(dy);
                        if (ax > ay) {
                            dy6 = 0 -% dy;
                        } else {
                            dx6 = 0 -% dx;
                            dy6 = s[10];
                        }
                        try curve(st, s[0], s[1], s[2], s[3], s[4], s[5]);
                        try curve(st, s[6], s[7], s[8], s[9], dx6, dy6);
                        st.n = 0;
                    },
                    else => return error.UnsupportedTable,
                }
            },
            else => return error.UnsupportedTable,
        }
    }
}

/// True ink box `[x_min, y_min, x_max, y_max]` in font units, y up
/// from the baseline. Blank outlines report all zeros; glyphs whose
/// outlines use unsupported constructs report `UnsupportedTable`
/// (callers fall back to the degenerate box).
pub fn glyphBounds(f: Font, glyph: u16) Error![4]i32 {
    if (glyph >= f.num_glyphs) return error.Truncated;
    const ctx = try cffCtx(f);
    const prog = try cffElem(ctx.bytes, ctx.cs, glyph);
    var st = BoundsSt{
        .x = 0,
        .y = 0,
        .stack = undefined,
        .n = 0,
        .have_width = false,
        .nstems = 0,
        .mask_bytes = null,
        .x0 = 0,
        .y0 = 0,
        .x1 = 0,
        .y1 = 0,
        .any = false,
    };
    try runCs(&ctx, prog, &st, 0);
    if (!st.any) return .{ 0, 0, 0, 0 };
    // Round half up out of 16.16, then scale to 1000 units exactly
    // like the advance path (all fixtures are 1000 upm, so pins are
    // exact; odd upms truncate identically).
    const r: [4]i64 = .{
        @divFloor(st.x0 + 32768, 65536),
        @divFloor(st.y0 + 32768, 65536),
        @divFloor(st.x1 + 32768, 65536),
        @divFloor(st.y1 + 32768, 65536),
    };
    var out: [4]i32 = undefined;
    for (r, 0..) |v, i| {
        const s = @divTrunc(v * 1000, f.upm);
        const c = std.math.clamp(s, @as(i64, std.math.minInt(i32)), @as(i64, std.math.maxInt(i32)));
        out[i] = @intCast(c);
    }
    return out;
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

const LoadedFont = struct { bytes: []u8, font: Font };

fn loadPath(path: []const u8) !LoadedFont {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        path,
        std.testing.allocator,
        .limited(4 * 1024 * 1024),
    );
    return .{ .bytes = bytes, .font = try load(bytes) };
}

fn loadRef() !LoadedFont {
    return loadPath(ref_path);
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

test "reference ink boxes match fontTools ground truth" {
    // CFF outline bounds against BoundsPen (issue #194 corpus pins):
    // combining marks with zero advance, slanted nuclei, capitals,
    // the surd, and the over/under brace pair.
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    const cases = [_]struct { cp: u21, want: [4]i32 }{
        .{ .cp = 0x20D7, .want = .{ -472, 521, -56, 711 } },
        .{ .cp = '~', .want = .{ 0, 193, 555, 307 } },
        .{ .cp = 0x02C7, .want = .{ 98, 516, 402, 692 } },
        .{ .cp = 0x221A, .want = .{ 73, -960, 853, 40 } },
        .{ .cp = '.', .want = .{ 86, 0, 192, 106 } },
        .{ .cp = 0x02D9, .want = .{ 85, 551, 192, 657 } },
        .{ .cp = 0x23DE, .want = .{ 0, 539, 492, 783 } },
        .{ .cp = 0x23DF, .want = .{ 0, -353, 492, -109 } },
        .{ .cp = 'A', .want = .{ 32, 0, 717, 716 } },
    };
    for (cases) |c| {
        const gid = try glyphId(r.font, c.cp);
        try std.testing.expect(gid != 0);
        try std.testing.expectEqual(c.want, try glyphBounds(r.font, gid));
    }
}

test "ink boxes validate across faces" {
    // Same interpreter, different CFFs: KaTeX Main caron/vec and the
    // one-glyph STIX overline subset (fontTools cross-checked).
    const m = try loadPath("fixtures/fonts/katex/KaTeX_Main-Regular.otf");
    defer std.testing.allocator.free(m.bytes);
    try std.testing.expectEqual(
        [4]i32{ 114, 513, 385, 644 },
        try glyphBounds(m.font, try glyphId(m.font, 0x02C7)),
    );
    try std.testing.expectEqual(
        [4]i32{ -471, 517, -29, 714 },
        try glyphBounds(m.font, try glyphId(m.font, 0x20D7)),
    );
    const s = try loadPath("fixtures/fonts/STIXTwoMath-overline.otf");
    defer std.testing.allocator.free(s.bytes);
    try std.testing.expectEqual(
        [4]i32{ 0, 792, 512, 839 },
        try glyphBounds(s.font, try glyphId(s.font, 0x203E)),
    );
}

// Minimal synthetic sfnt+CFF: pins the fallback triggers
// (reserved opcode, seac endchar, missing CFF table) and the happy
// path on hand-laid bytes, with no fixture files involved. The CFF
// below is byte-mapped in the test.
const CffFixture = struct {
    buf: [256]u8 = .{0} ** 256,
    pos: usize = 0,

    fn w8(self: *CffFixture, v: u8) void {
        self.buf[self.pos] = v;
        self.pos += 1;
    }

    fn w16(self: *CffFixture, v: u16) void {
        self.w8(@intCast(v >> 8));
        self.w8(@intCast(v & 0xFF));
    }

    fn w32(self: *CffFixture, v: u32) void {
        self.w16(@intCast(v >> 16));
        self.w16(@intCast(v & 0xFFFF));
    }

    fn bytes(self: *CffFixture) []const u8 {
        return self.buf[0..self.pos];
    }

    fn table(self: *CffFixture, tagv: u32, at: usize) void {
        const base = 12 + at * 16;
        self.buf[base] = @intCast(tagv >> 24);
        self.buf[base + 1] = @intCast((tagv >> 16) & 0xFF);
        self.buf[base + 2] = @intCast((tagv >> 8) & 0xFF);
        self.buf[base + 3] = @intCast(tagv & 0xFF);
        self.buf[base + 8] = @intCast(self.pos >> 24);
        self.buf[base + 9] = @intCast((self.pos >> 16) & 0xFF);
        self.buf[base + 10] = @intCast((self.pos >> 8) & 0xFF);
        self.buf[base + 11] = @intCast(self.pos & 0xFF);
    }

    fn build(self: *CffFixture, with_cff: bool) void {
        const ntab: u16 = if (with_cff) 6 else 5;
        self.w32(0x00010000);
        self.w16(ntab);
        self.w16(0);
        self.w16(0);
        self.w16(0);
        for (0..ntab) |_| {
            self.w32(0);
            self.w32(0);
            self.w32(0);
            self.w32(0);
        }
        var at: usize = 0;
        // head: upm 1000 at +18.
        self.table(0x68656164, at);
        at += 1;
        for (0..9) |_| self.w16(0);
        self.w16(1000);
        // maxp: 3 glyphs at +4.
        self.table(0x6D617870, at);
        at += 1;
        self.w32(0);
        self.w16(3);
        // cmap: present but never parsed here.
        self.table(0x636D6170, at);
        at += 1;
        self.w16(0);
        self.w16(0);
        // hmtx: 3 advances.
        self.table(0x686D7478, at);
        at += 1;
        self.w16(500);
        self.w16(500);
        self.w16(500);
        // hhea: 3 metrics at +34.
        self.table(0x68686561, at);
        at += 1;
        for (0..17) |_| self.w16(0);
        self.w16(3);
        if (!with_cff) return;
        self.table(0x43464620, at);
        // CFF: header + Name("X") + Top(CharStrings=21) + empty
        // String/GlobalSubrs + 3 CharStrings:
        // g0 reserved opcode, g1 seac-form endchar,
        // g2 rmoveto(10,20) rlineto(30,40) endchar.
        const cff = [_]u8{
            0x01, 0x00, 0x04, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x02, 0x58,
            0x00, 0x01, 0x01, 0x01, 0x03, 0xA0, 0x11,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x03, 0x01, 0x01, 0x03, 0x08, 0x0F,
            0x94, 0x09,
            0x94, 0x94, 0x94, 0x94, 0x0E,
            0x95, 0x9F, 0x15, 0xA9, 0xB3, 0x05, 0x0E,
        };
        for (cff) |b| self.w8(b);
    }
};

test "synthetic CFF bounds: happy path and fallback triggers" {
    var fx = CffFixture{};
    fx.build(true);
    const font = try load(fx.bytes());
    // Reserved opcode and seac-form endchar report unsupported (the
    // caller falls back to the degenerate box, never a wrong one).
    try std.testing.expectError(error.UnsupportedTable, glyphBounds(font, 0));
    try std.testing.expectError(error.UnsupportedTable, glyphBounds(font, 1));
    // Hand-laid outline: exact box, no fixture files.
    try std.testing.expectEqual([4]i32{ 10, 20, 40, 60 }, try glyphBounds(font, 2));
    // No CFF table at all: unsupported, not a crash.
    var bare = CffFixture{};
    bare.build(false);
    const plain = try load(bare.bytes());
    try std.testing.expectError(error.UnsupportedTable, glyphBounds(plain, 2));
}

test "blank and unsupported outlines report honestly" {
    const r = try loadRef();
    defer std.testing.allocator.free(r.bytes);
    // space draws nothing: the degenerate box, exactly per contract.
    try std.testing.expectEqual(
        [4]i32{ 0, 0, 0, 0 },
        try glyphBounds(r.font, try glyphId(r.font, ' ')),
    );
    // .notdef carries only a width: blank, so zeros as well.
    try std.testing.expectEqual(
        [4]i32{ 0, 0, 0, 0 },
        try glyphBounds(r.font, 0),
    );
    try std.testing.expectError(error.Truncated, glyphBounds(r.font, 9999));
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
