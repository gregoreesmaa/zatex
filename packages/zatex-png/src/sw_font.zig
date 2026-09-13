//! CFF/Type2 outline reader for the software backend (`sw_backend.zig`).
//!
//! Parses the CFF table of OpenType/CFF fonts (the Latin Modern Math
//! fixture and the STIX Two fallback both are) and executes Type2
//! charstrings into absolute path segments. Operator semantics follow
//! Adobe Tech Note 5177, cross-checked against fontTools'
//! `psCharStrings` and the fixture's own operator histogram (all drawing
//! ops + hstem/vstem/hstemhm + hintmask/cntrmask + callsubr + endchar;
//! the arithmetic/flex/vv/hh/rcurveline family is implemented too so
//! other CFF fonts behave sanely).
//!
//! No allocation: works over caller bytes into a caller segment buffer.
//! CID-keyed fonts are rejected (neither of our fonts is CID-keyed).
const std = @import("std");

pub const Error = error{
    NotAFont,
    Truncated,
    UnsupportedFont,
    BadCharstring,
    OutOfSpace,
};

/// One path segment in font units (y-up, like CFF): a line stores its
/// endpoints in slots 0 and 3, a cubic Bezier stores all four points.
/// Relative Type2 operators are absolutized during execution.
pub const Seg = struct {
    x: [4]f64,
    y: [4]f64,
    is_curve: bool,
};

pub const CffFont = struct {
    bytes: []const u8,
    charstrings: Index,
    subrs: Index,
    gsubrs: Index,
    num_glyphs: usize,
};

/// An INDEX table as metadata only (no allocation): object `i` spans
/// `indexAt(i)`, computed on demand from the offset array.
pub const Index = struct {
    count: usize,
    off_size: u8,
    offsets: usize,
    base: usize,

    fn empty() Index {
        return .{ .count = 0, .off_size = 0, .offsets = 0, .base = 0 };
    }
};

fn u16be(b: []const u8, off: usize) Error!u16 {
    if (off + 2 > b.len) return error.Truncated;
    return (@as(u16, b[off]) << 8) | b[off + 1];
}

fn u32be(b: []const u8, off: usize) Error!u32 {
    if (off + 4 > b.len) return error.Truncated;
    return (@as(u32, b[off]) << 24) | (@as(u32, b[off + 1]) << 16) |
        (@as(u32, b[off + 2]) << 8) | b[off + 3];
}

fn readOff(b: []const u8, off: usize, size: u8) Error!usize {
    if (off + size > b.len) return error.Truncated;
    var v: usize = 0;
    var k: usize = 0;
    while (k < size) : (k += 1) v = (v << 8) | b[off + k];
    return v;
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
    return error.Truncated;
}

fn tag(a: u8, b: u8, c: u8, d: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, c) << 8) | d;
}

const ReadIndex = struct { idx: Index, next: usize };

/// Read the INDEX header at absolute `off`.
fn readIndex(bytes: []const u8, off: usize) Error!ReadIndex {
    const count = try u16be(bytes, off);
    if (count == 0) return .{ .idx = Index.empty(), .next = off + 2 };
    if (off + 2 >= bytes.len) return error.Truncated;
    const os = bytes[off + 2];
    if (os < 1 or os > 4) return error.UnsupportedFont;
    const offsets = off + 3;
    const base = offsets + (count + 1) * os;
    if (base < offsets or base > bytes.len) return error.Truncated;
    return .{
        .idx = .{ .count = count, .off_size = os, .offsets = offsets, .base = base },
        .next = base, // refined below once object extents are known
    };
}

const Span = struct { start: usize, end: usize };

fn indexAt(bytes: []const u8, idx: Index, i: usize) Error!Span {
    if (i >= idx.count) return error.Truncated;
    const a = try readOff(bytes, idx.offsets + i * idx.off_size, idx.off_size);
    const b = try readOff(bytes, idx.offsets + (i + 1) * idx.off_size, idx.off_size);
    if (a == 0 or b < a) return error.BadCharstring;
    const s = idx.base + a - 1;
    const e = idx.base + b - 1;
    if (e > bytes.len or s > e) return error.Truncated;
    return .{ .start = s, .end = e };
}

/// Absolute end of an INDEX's object data (for chaining to the next
/// structure): end of its last object, or `next` when empty.
fn indexEnd(bytes: []const u8, r: ReadIndex) Error!usize {
    if (r.idx.count == 0) return r.next;
    return (try indexAt(bytes, r.idx, r.idx.count - 1)).end;
}

const DictNum = struct { v: f64, next: usize };

/// One CFF DICT number (int or real) at absolute `pc`.
fn dictNum(bytes: []const u8, pc: usize) Error!DictNum {
    if (pc >= bytes.len) return error.Truncated;
    const b = bytes[pc];
    if (b >= 32 and b <= 246) {
        const v: f64 = @floatFromInt(@as(i32, b) - 139);
        return .{ .v = v, .next = pc + 1 };
    }
    if (b >= 247 and b <= 250) {
        if (pc + 1 >= bytes.len) return error.Truncated;
        const v: f64 = @floatFromInt((@as(i32, b) - 247) * 256 + bytes[pc + 1] + 108);
        return .{ .v = v, .next = pc + 2 };
    }
    if (b >= 251 and b <= 254) {
        if (pc + 1 >= bytes.len) return error.Truncated;
        const v: f64 = @floatFromInt(-(@as(i32, b) - 251) * 256 - bytes[pc + 1] - 108);
        return .{ .v = v, .next = pc + 2 };
    }
    if (b == 28) {
        if (pc + 2 >= bytes.len) return error.Truncated;
        const raw: i16 = @bitCast((@as(u16, bytes[pc + 1]) << 8) | bytes[pc + 2]);
        return .{ .v = @floatFromInt(raw), .next = pc + 3 };
    }
    if (b == 29) {
        if (pc + 4 >= bytes.len) return error.Truncated;
        const raw: i32 = @bitCast((@as(u32, bytes[pc + 1]) << 24) | (@as(u32, bytes[pc + 2]) << 16) |
            (@as(u32, bytes[pc + 3]) << 8) | bytes[pc + 4]);
        return .{ .v = @floatFromInt(raw), .next = pc + 5 };
    }
    if (b == 30) {
        var v: f64 = 0;
        var frac: f64 = 0.1;
        var neg = false;
        var exp: i32 = 0;
        var exp_neg = false;
        var in_frac = false;
        var in_exp = false;
        var i = pc + 1;
        var done = false;
        while (!done) {
            if (i >= bytes.len) return error.Truncated;
            const by = bytes[i];
            i += 1;
            const nibbles: [2]u4 = .{ @intCast(by >> 4), @intCast(by & 0x0F) };
            for (nibbles) |n| {
                if (n <= 9) {
                    const d: f64 = @floatFromInt(n);
                    if (in_exp) {
                        exp = exp * 10 + @as(i32, @intCast(n));
                    } else if (in_frac) {
                        v += d * frac;
                        frac *= 0.1;
                    } else {
                        v = v * 10 + d;
                    }
                } else if (n == 0xA) {
                    in_frac = true;
                } else if (n == 0xB) {
                    in_exp = true;
                    in_frac = false;
                } else if (n == 0xC) {
                    in_exp = true;
                    in_frac = false;
                    exp_neg = true;
                } else if (n == 0xD) {
                    if (in_exp or in_frac or v != 0) return error.UnsupportedFont;
                    neg = true;
                } else if (n == 0xE) {
                    return error.UnsupportedFont; // reserved nibble
                } else {
                    done = true;
                    break;
                }
            }
        }
        var e = if (exp_neg) -exp else exp;
        while (e > 0) : (e -= 1) v *= 10;
        while (e < 0) : (e += 1) v *= 0.1;
        if (neg) v = -v;
        return .{ .v = v, .next = i };
    }
    return error.UnsupportedFont;
}

const TopInfo = struct {
    charstrings: ?usize = null,
    priv_size: ?usize = null,
    priv_off: ?usize = null,
    is_cid: bool = false,
};

/// Scan a Top DICT byte range for the offsets the loader needs.
fn scanTop(bytes: []const u8, start: usize, end: usize) Error!TopInfo {
    var info = TopInfo{};
    var stack: [8]f64 = undefined;
    var n: usize = 0;
    var pc = start;
    while (pc < end) {
        const b = bytes[pc];
        if (b == 12) {
            if (pc + 1 >= end) return error.Truncated;
            if (bytes[pc + 1] == 30) info.is_cid = true; // ROS
            n = 0;
            pc += 2;
        } else if (b <= 21) {
            if (b == 17 and n >= 1) info.charstrings = @intFromFloat(stack[n - 1]);
            if (b == 18 and n >= 2) {
                info.priv_size = @intFromFloat(stack[n - 2]);
                info.priv_off = @intFromFloat(stack[n - 1]);
            }
            n = 0;
            pc += 1;
        } else {
            const d = try dictNum(bytes, pc);
            if (n < stack.len) {
                stack[n] = d.v;
                n += 1;
            }
            pc = d.next;
        }
    }
    return info;
}

/// Scan a Private DICT byte range for the local-Subrs offset.
fn scanPrivate(bytes: []const u8, start: usize, end: usize) Error!?usize {
    var subrs: ?usize = null;
    var stack: [8]f64 = undefined;
    var n: usize = 0;
    var pc = start;
    while (pc < end) {
        const b = bytes[pc];
        if (b == 12) {
            if (pc + 1 >= end) return error.Truncated;
            n = 0;
            pc += 2;
        } else if (b <= 21) {
            if (b == 19 and n >= 1) subrs = @intFromFloat(stack[n - 1]);
            n = 0;
            pc += 1;
        } else {
            const d = try dictNum(bytes, pc);
            if (n < stack.len) {
                stack[n] = d.v;
                n += 1;
            }
            pc = d.next;
        }
    }
    return subrs;
}

/// Locate the CFF table and its CharStrings/Subrs INDEXes.
pub fn load(bytes: []const u8) Error!CffFont {
    if (bytes.len < 12) return error.Truncated;
    const sfnt = try u32be(bytes, 0);
    if (sfnt != 0x00010000 and sfnt != 0x4F54544F and
        sfnt != 0x74727565 and sfnt != 0x74797031)
    {
        return error.NotAFont;
    }
    const cff = tableOff(bytes, tag('C', 'F', 'F', ' ')) catch return error.NotAFont;
    if (cff + 4 > bytes.len) return error.Truncated;
    if (bytes[cff] != 1) return error.UnsupportedFont; // CFF major version
    const hdr_size: usize = bytes[cff + 2];
    if (hdr_size < 4 or cff + hdr_size > bytes.len) return error.Truncated;

    const name_idx = try readIndex(bytes, cff + hdr_size);
    const top_at = try indexEnd(bytes, name_idx);
    const top_idx = try readIndex(bytes, top_at);
    if (top_idx.idx.count != 1) return error.UnsupportedFont;
    const top_span = try indexAt(bytes, top_idx.idx, 0);
    const str_at = try indexEnd(bytes, top_idx);
    const str_idx = try readIndex(bytes, str_at);
    const gsub_at = try indexEnd(bytes, str_idx);
    const gsub_idx = try readIndex(bytes, gsub_at);

    const info = try scanTop(bytes, top_span.start, top_span.end);
    if (info.is_cid) return error.UnsupportedFont; // CID-keyed: no GID==index rule
    const cs_off = info.charstrings orelse return error.UnsupportedFont;
    const cs_idx = try readIndex(bytes, cff + cs_off);
    if (cs_idx.idx.count == 0) return error.UnsupportedFont;

    var lsub = Index.empty();
    if (info.priv_off) |po| {
        const ps = info.priv_size orelse return error.Truncated;
        if (cff + po + ps > bytes.len) return error.Truncated;
        if (try scanPrivate(bytes, cff + po, cff + po + ps)) |so| {
            lsub = (try readIndex(bytes, cff + po + so)).idx;
        }
    }
    return .{
        .bytes = bytes,
        .charstrings = cs_idx.idx,
        .subrs = lsub,
        .gsubrs = gsub_idx.idx,
        .num_glyphs = cs_idx.idx.count,
    };
}

const Interp = struct {
    font: *const CffFont,
    segs: []Seg,
    nsegs: usize = 0,
    stack: [64]f64 = undefined,
    nstack: usize = 0,
    transient: [32]f64 = [_]f64{0} ** 32,
    x: f64 = 0,
    y: f64 = 0,
    sx: f64 = 0,
    sy: f64 = 0,
    need_close: bool = false,
    width_done: bool = false,
    stems: u32 = 0,
    depth: u8 = 0,
    done: bool = false,
    frame_end: bool = false,
    rand_state: u32 = 0x12345678,

    fn push(self: *Interp, v: f64) Error!void {
        if (self.nstack >= self.stack.len) return error.BadCharstring;
        self.stack[self.nstack] = v;
        self.nstack += 1;
    }

    fn pop(self: *Interp) Error!f64 {
        if (self.nstack == 0) return error.BadCharstring;
        self.nstack -= 1;
        return self.stack[self.nstack];
    }

    fn clear(self: *Interp) void {
        self.nstack = 0;
    }

    fn emitLine(self: *Interp, x1: f64, y1: f64) Error!void {
        if (self.nsegs >= self.segs.len) return error.OutOfSpace;
        if (x1 == self.x and y1 == self.y) return; // degenerate: no winding
        self.segs[self.nsegs] = .{
            .x = .{ self.x, 0, 0, x1 },
            .y = .{ self.y, 0, 0, y1 },
            .is_curve = false,
        };
        self.nsegs += 1;
        self.x = x1;
        self.y = y1;
        self.need_close = true;
    }

    fn emitCurve(self: *Interp, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) Error!void {
        if (self.nsegs >= self.segs.len) return error.OutOfSpace;
        self.segs[self.nsegs] = .{
            .x = .{ self.x, x1, x2, x3 },
            .y = .{ self.y, y1, y2, y3 },
            .is_curve = true,
        };
        self.nsegs += 1;
        self.x = x3;
        self.y = y3;
        self.need_close = true;
    }

    fn moveTo(self: *Interp, x: f64, y: f64) Error!void {
        // Implicitly close the outgoing contour (fills close subpaths;
        // the closing edge carries winding, so it is emitted for real).
        if (self.need_close and (self.x != self.sx or self.y != self.sy)) {
            if (self.nsegs >= self.segs.len) return error.OutOfSpace;
            self.segs[self.nsegs] = .{
                .x = .{ self.x, 0, 0, self.sx },
                .y = .{ self.y, 0, 0, self.sy },
                .is_curve = false,
            };
            self.nsegs += 1;
        }
        self.need_close = false;
        self.x = x;
        self.y = y;
        self.sx = x;
        self.sy = y;
    }

    /// Strip the optional width argument on the first stem/moveto/mask
    /// op (odd stack depth means width is present), then count stems.
    fn stemHead(self: *Interp) Error!void {
        if (!self.width_done) {
            if (self.nstack % 2 == 1) {
                std.mem.copyForwards(f64, self.stack[0 .. self.nstack - 1], self.stack[1..self.nstack]);
                self.nstack -= 1;
            }
            self.width_done = true;
        }
        if (self.nstack % 2 == 1) return error.BadCharstring;
        self.stems += @intCast(self.nstack / 2);
        self.clear();
    }

    fn moveHead(self: *Interp, want: usize) Error!void {
        if (!self.width_done) {
            if (self.nstack == want + 1) {
                std.mem.copyForwards(f64, self.stack[0 .. self.nstack - 1], self.stack[1..self.nstack]);
                self.nstack -= 1;
            }
            self.width_done = true;
        }
        if (self.nstack != want) return error.BadCharstring;
    }

    fn drawHead(self: *Interp) void {
        self.width_done = true;
    }

    fn rand01(self: *Interp) f64 {
        // xorshift32, deterministic across runs by construction.
        var s = self.rand_state;
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        self.rand_state = s;
        return @as(f64, @floatFromInt(s >> 8)) / 16777216.0;
    }

    fn subrBias(count: usize) i32 {
        if (count < 1240) return 107;
        if (count < 33900) return 1131;
        return 32768;
    }

    fn callSubr(self: *Interp, table: Index, num: f64) Error!void {
        if (table.count == 0) return error.BadCharstring;
        const idx = @as(i64, @intFromFloat(num)) + subrBias(table.count);
        if (idx < 0 or idx >= table.count) return error.BadCharstring;
        if (self.depth >= 10) return error.BadCharstring;
        const span = try indexAt(self.font.bytes, table, @intCast(idx));
        self.depth += 1;
        defer self.depth -= 1;
        self.frame_end = false;
        try self.run(span.start, span.end);
        self.frame_end = false;
    }

    fn flexCurve(self: *Interp, dx1: f64, dy1: f64, dx2: f64, dy2: f64, dx3: f64, dy3: f64) Error!void {
        try self.emitCurve(self.x + dx1, self.y + dy1, self.x + dx1 + dx2, self.y + dy1 + dy2, self.x + dx1 + dx2 + dx3, self.y + dy1 + dy2 + dy3);
    }

    fn run(self: *Interp, pc0: usize, end: usize) Error!void {
        const bytes = self.font.bytes;
        var pc = pc0;
        while (!self.done and !self.frame_end and pc < end) {
            const b = bytes[pc];
            pc += 1;
            if (b >= 32 and b <= 246) {
                try self.push(@floatFromInt(@as(i32, b) - 139));
            } else if (b >= 247 and b <= 250) {
                if (pc >= end) return error.Truncated;
                try self.push(@floatFromInt((@as(i32, b) - 247) * 256 + bytes[pc] + 108));
                pc += 1;
            } else if (b >= 251 and b <= 254) {
                if (pc >= end) return error.Truncated;
                try self.push(@floatFromInt(-(@as(i32, b) - 251) * 256 - bytes[pc] - 108));
                pc += 1;
            } else if (b == 28) {
                if (pc + 1 >= end) return error.Truncated;
                const raw: i16 = @bitCast((@as(u16, bytes[pc]) << 8) | bytes[pc + 1]);
                try self.push(@floatFromInt(raw));
                pc += 2;
            } else if (b == 255) {
                if (pc + 3 >= end) return error.Truncated;
                const raw: i32 = @bitCast((@as(u32, bytes[pc]) << 24) | (@as(u32, bytes[pc + 1]) << 16) |
                    (@as(u32, bytes[pc + 2]) << 8) | bytes[pc + 3]);
                try self.push(@as(f64, @floatFromInt(raw)) / 65536.0);
                pc += 4;
            } else if (b == 12) {
                if (pc >= end) return error.Truncated;
                const e = bytes[pc];
                pc += 1;
                try self.escape(e);
            } else {
                pc = try self.op(b, pc, end);
            }
        }
    }

    fn args(self: *Interp) []f64 {
        return self.stack[0..self.nstack];
    }

    fn op(self: *Interp, b: u8, pc: usize, end: usize) Error!usize {
        var next = pc;
        switch (b) {
            1, 3, 18, 23 => { // hstem, vstem, hstemhm, vstemhm
                try self.stemHead();
            },
            19, 20 => { // hintmask, cntrmask: stems then mask bytes
                try self.stemHead();
                const nbytes = (self.stems + 7) / 8;
                if (next + nbytes > end) return error.Truncated;
                next += nbytes;
            },
            21 => { // rmoveto
                try self.moveHead(2);
                const a = self.args();
                const nx = self.x + a[0];
                const ny = self.y + a[1];
                try self.moveTo(nx, ny);
                self.clear();
            },
            22 => { // hmoveto
                try self.moveHead(1);
                const a = self.args();
                try self.moveTo(self.x + a[0], self.y);
                self.clear();
            },
            4 => { // vmoveto
                try self.moveHead(1);
                const a = self.args();
                try self.moveTo(self.x, self.y + a[0]);
                self.clear();
            },
            5 => { // rlineto
                self.drawHead();
                const a = self.args();
                if (a.len < 2 or a.len % 2 == 1) return error.BadCharstring;
                var i: usize = 0;
                while (i < a.len) : (i += 2) try self.emitLine(self.x + a[i], self.y + a[i + 1]);
                self.clear();
            },
            6 => { // hlineto
                self.drawHead();
                const a = self.args();
                if (a.len < 1) return error.BadCharstring;
                var horiz = true;
                for (a) |d| {
                    if (horiz) try self.emitLine(self.x + d, self.y) else try self.emitLine(self.x, self.y + d);
                    horiz = !horiz;
                }
                self.clear();
            },
            7 => { // vlineto
                self.drawHead();
                const a = self.args();
                if (a.len < 1) return error.BadCharstring;
                var vert = true;
                for (a) |d| {
                    if (vert) try self.emitLine(self.x, self.y + d) else try self.emitLine(self.x + d, self.y);
                    vert = !vert;
                }
                self.clear();
            },
            8 => { // rrcurveto
                self.drawHead();
                const a = self.args();
                if (a.len < 6 or a.len % 6 != 0) return error.BadCharstring;
                var i: usize = 0;
                while (i < a.len) : (i += 6) {
                    try self.emitCurve(self.x + a[i], self.y + a[i + 1], self.x + a[i] + a[i + 2], self.y + a[i + 1] + a[i + 3], self.x + a[i] + a[i + 2] + a[i + 4], self.y + a[i + 1] + a[i + 3] + a[i + 5]);
                }
                self.clear();
            },
            10 => { // callsubr
                try self.callSubr(self.font.subrs, try self.pop());
            },
            29 => { // callgsubr
                try self.callSubr(self.font.gsubrs, try self.pop());
            },
            11 => { // return: end the current subr frame
                if (self.depth == 0) {
                    self.done = true; // lenient: stray top-level return ends
                } else {
                    self.frame_end = true;
                }
            },
            14 => { // endchar: 0 args ends; a lone width arg ends
                // too (.notdef is [width, endchar]); anything else is
                // the deprecated seac form, which Type2 forbids.
                if (!self.width_done) {
                    if (self.nstack == 1) self.clear();
                    self.width_done = true;
                }
                if (self.nstack != 0) return error.BadCharstring;
                self.done = true;
            },
            24 => { // rcurveline: curves then a final line
                self.drawHead();
                const a = self.args();
                if (a.len < 8 or (a.len - 2) % 6 != 0) return error.BadCharstring;
                var i: usize = 0;
                while (i + 2 < a.len) : (i += 6) {
                    try self.emitCurve(self.x + a[i], self.y + a[i + 1], self.x + a[i] + a[i + 2], self.y + a[i + 1] + a[i + 3], self.x + a[i] + a[i + 2] + a[i + 4], self.y + a[i + 1] + a[i + 3] + a[i + 5]);
                }
                try self.emitLine(self.x + a[a.len - 2], self.y + a[a.len - 1]);
                self.clear();
            },
            25 => { // rlinecurve: lines then a final curve
                self.drawHead();
                const a = self.args();
                if (a.len < 8 or (a.len - 6) % 2 != 0) return error.BadCharstring;
                var i: usize = 0;
                while (i + 6 < a.len) : (i += 2) try self.emitLine(self.x + a[i], self.y + a[i + 1]);
                const j = a.len - 6;
                try self.emitCurve(self.x + a[j], self.y + a[j + 1], self.x + a[j] + a[j + 2], self.y + a[j + 1] + a[j + 3], self.x + a[j] + a[j + 2] + a[j + 4], self.y + a[j + 1] + a[j + 3] + a[j + 5]);
                self.clear();
            },
            26 => { // vvcurveto: dx1? {dya dxb dyb dyc}+
                self.drawHead();
                const a = self.args();
                var i: usize = 0;
                var dx1: f64 = 0;
                if (a.len % 2 == 1) {
                    if (a.len < 5) return error.BadCharstring;
                    dx1 = a[0];
                    i = 1;
                }
                if ((a.len - i) % 4 != 0) return error.BadCharstring;
                while (i < a.len) : (i += 4) {
                    try self.emitCurve(self.x + dx1, self.y + a[i], self.x + dx1 + a[i + 1], self.y + a[i] + a[i + 2], self.x + dx1 + a[i + 1], self.y + a[i] + a[i + 2] + a[i + 3]);
                    dx1 = 0;
                }
                self.clear();
            },
            27 => { // hhcurveto: dy1? {dxa dxb dyb dxc}+
                self.drawHead();
                const a = self.args();
                var i: usize = 0;
                var dy1: f64 = 0;
                if (a.len % 2 == 1) {
                    if (a.len < 5) return error.BadCharstring;
                    dy1 = a[0];
                    i = 1;
                }
                if ((a.len - i) % 4 != 0) return error.BadCharstring;
                while (i < a.len) : (i += 4) {
                    try self.emitCurve(self.x + a[i], self.y + dy1, self.x + a[i] + a[i + 1], self.y + dy1 + a[i + 2], self.x + a[i] + a[i + 1] + a[i + 3], self.y + dy1 + a[i + 2]);
                    dy1 = 0;
                }
                self.clear();
            },
            30 => { // vhcurveto: v,h,v,h... curves, optional trailing arg
                self.drawHead();
                try self.vhCurve(false);
            },
            31 => { // hvcurveto: h,v,h,v... curves, optional trailing arg
                self.drawHead();
                try self.vhCurve(true);
            },
            else => return error.BadCharstring, // 0,2,9,13,15,16,17: reserved/CFF2
        }
        return next;
    }

    /// Shared vh/hvcurveto driver: alternating curves starting vertical
    /// (vh) or horizontal (hv), with an optional trailing single that
    /// extends the final endpoint along the curve's last axis.
    /// Successive deltas accumulate: end = cur + d1 + d2 + d3.
    fn vhCurve(self: *Interp, horiz_first: bool) Error!void {
        const a = self.args();
        var i: usize = 0;
        var horiz = horiz_first;
        // Leading groups of 4 while more than one curve-plus-tail remains.
        while (a.len - i > 5) {
            if (a.len - i < 4) return error.BadCharstring;
            if (horiz) {
                // (dxa,dxb,dyb,dyc): end=(x+dxa+dxb, y+dyb+dyc).
                try self.emitCurve(self.x + a[i], self.y, self.x + a[i] + a[i + 1], self.y + a[i + 2], self.x + a[i] + a[i + 1], self.y + a[i + 2] + a[i + 3]);
            } else {
                // (dya,dxb,dyb,dxc): end=(x+dxb+dxc, y+dya+dyb).
                try self.emitCurve(self.x, self.y + a[i], self.x + a[i + 1], self.y + a[i] + a[i + 2], self.x + a[i + 1] + a[i + 3], self.y + a[i] + a[i + 2]);
            }
            i += 4;
            horiz = !horiz;
        }
        // Final curve: 4 args, or 5 with the trailing tangent `t`, which
        // is the last successive delta along the final axis.
        const rest = a.len - i;
        if (rest != 4 and rest != 5) return error.BadCharstring;
        if (horiz) {
            // (dxa,dxb,dyb,dyc[,dxc]): end=(x+dxa+dxb+dxc, y+dyb+dyc).
            const dxc: f64 = if (rest == 5) a[i + 4] else 0;
            try self.emitCurve(self.x + a[i], self.y, self.x + a[i] + a[i + 1], self.y + a[i + 2], self.x + a[i] + a[i + 1] + dxc, self.y + a[i + 2] + a[i + 3]);
        } else {
            // (dya,dxb,dyb,dxc[,dyc]): end=(x+dxb+dxc, y+dya+dyb+dyc).
            const dyc: f64 = if (rest == 5) a[i + 4] else 0;
            try self.emitCurve(self.x, self.y + a[i], self.x + a[i + 1], self.y + a[i] + a[i + 2], self.x + a[i + 1] + a[i + 3], self.y + a[i] + a[i + 2] + dyc);
        }
        self.clear();
    }

    fn escape(self: *Interp, e: u8) Error!void {
        switch (e) {
            0 => {}, // dotsection: deprecated no-op
            3, 4, 15 => { // and, or, eq (binary)
                const b = try self.pop();
                const a = try self.pop();
                try self.push(switch (e) {
                    3 => if (a != 0 and b != 0) 1 else 0,
                    4 => if (a != 0 or b != 0) 1 else 0,
                    else => if (a == b) 1 else 0,
                });
            },
            5 => { // not (unary)
                const a = try self.pop();
                try self.push(if (a == 0) 1 else 0);
            },
            9, 14 => { // abs, neg
                const a = try self.pop();
                try self.push(if (e == 9) @abs(a) else -a);
            },
            10, 11, 24 => { // add, sub, mul
                const b = try self.pop();
                const a = try self.pop();
                try self.push(switch (e) {
                    10 => a + b,
                    11 => a - b,
                    else => a * b,
                });
            },
            12 => { // div
                const b = try self.pop();
                const a = try self.pop();
                if (b == 0) return error.BadCharstring;
                try self.push(a / b);
            },
            26 => { // sqrt
                const a = try self.pop();
                if (a < 0) return error.BadCharstring;
                try self.push(@sqrt(a));
            },
            18 => { // drop
                _ = try self.pop();
            },
            27, 28 => { // dup, exch
                if (self.nstack < 1) return error.BadCharstring;
                if (e == 27) {
                    try self.push(self.stack[self.nstack - 1]);
                } else {
                    if (self.nstack < 2) return error.BadCharstring;
                    const t = self.stack[self.nstack - 1];
                    self.stack[self.nstack - 1] = self.stack[self.nstack - 2];
                    self.stack[self.nstack - 2] = t;
                }
            },
            29 => { // index
                const ni = try self.pop();
                const k: usize = @intFromFloat(@max(0, ni));
                if (k >= self.nstack) return error.BadCharstring;
                try self.push(self.stack[self.nstack - 1 - k]);
            },
            30 => { // roll
                const jj = try self.pop();
                const nn = try self.pop();
                const n: usize = @intFromFloat(@max(0, nn));
                if (n > self.nstack or n == 0) return error.BadCharstring;
                var j = @mod(@as(i64, @intFromFloat(jj)), @as(i64, @intCast(n)));
                while (j > 0) : (j -= 1) {
                    const t = self.stack[self.nstack - 1];
                    std.mem.copyBackwards(f64, self.stack[self.nstack - n + 1 .. self.nstack], self.stack[self.nstack - n .. self.nstack - 1]);
                    self.stack[self.nstack - n] = t;
                }
                while (j < 0) : (j += 1) {
                    const t = self.stack[self.nstack - n];
                    std.mem.copyForwards(f64, self.stack[self.nstack - n .. self.nstack - 1], self.stack[self.nstack - n + 1 .. self.nstack]);
                    self.stack[self.nstack - 1] = t;
                }
            },
            20, 21 => { // put, get (transient array)
                if (e == 20) {
                    const ii = try self.pop();
                    const v = try self.pop();
                    const k: usize = @intFromFloat(ii);
                    if (k >= self.transient.len) return error.BadCharstring;
                    self.transient[k] = v;
                } else {
                    const ii = try self.pop();
                    const k: usize = @intFromFloat(ii);
                    if (k >= self.transient.len) return error.BadCharstring;
                    try self.push(self.transient[k]);
                }
            },
            22 => { // ifelse
                const v2 = try self.pop();
                const v1 = try self.pop();
                const s2 = try self.pop();
                const s1 = try self.pop();
                try self.push(if (v1 > v2) s1 else s2);
            },
            23 => { // random
                try self.push(self.rand01());
            },
            34 => { // hflex: dx1 dx2 dy2 dx3 dx4 dx5 dx6
                self.drawHead();
                const a = self.args();
                if (a.len != 7) return error.BadCharstring;
                try self.flexCurve(a[0], 0, a[1], a[2], a[3], 0);
                try self.flexCurve(a[4], 0, a[5], -a[2], a[6], 0);
                self.clear();
            },
            35 => { // flex: 12 deltas + fd
                self.drawHead();
                const a = self.args();
                if (a.len != 13) return error.BadCharstring;
                try self.flexCurve(a[0], a[1], a[2], a[3], a[4], a[5]);
                try self.flexCurve(a[6], a[7], a[8], a[9], a[10], a[11]);
                self.clear();
            },
            36 => { // hflex1: dx1 dy1 dx2 dy2 dx3 dx4 dx5 dy5 dx6
                self.drawHead();
                const a = self.args();
                if (a.len != 9) return error.BadCharstring;
                try self.flexCurve(a[0], a[1], a[2], a[3], a[4], 0);
                try self.flexCurve(a[5], 0, a[6], a[7], a[8], -(a[1] + a[3] + a[7]));
                self.clear();
            },
            37 => { // flex1: dx1 dy1 .. dx5 dy5 d6
                self.drawHead();
                const a = self.args();
                if (a.len != 11) return error.BadCharstring;
                const dx = a[0] + a[2] + a[4] + a[6] + a[8];
                const dy = a[1] + a[3] + a[5] + a[7] + a[9];
                var dx6 = a[10];
                var dy6 = a[10];
                if (@abs(dx) > @abs(dy)) {
                    dy6 = -dy;
                } else {
                    dx6 = -dx;
                }
                try self.flexCurve(a[0], a[1], a[2], a[3], a[4], a[5]);
                try self.flexCurve(a[6], a[7], a[8], a[9], dx6, dy6);
                self.clear();
            },
            else => return error.BadCharstring, // 8,13 store/load + unknowns
        }
    }
};

/// Execute a glyph's charstring into `out`, returning the used prefix.
/// Blank glyphs (space) yield an empty slice; unknown glyph ids error.
pub fn outline(font: *const CffFont, glyph: u16, out: []Seg) Error![]Seg {
    if (glyph >= font.num_glyphs) return error.BadCharstring;
    const span = try indexAt(font.bytes, font.charstrings, glyph);
    var ip = Interp{ .font = font, .segs = out };
    try ip.run(span.start, span.end);
    // Type2 has no closepath operator: close the final contour here
    // (earlier contours close at each moveto) so the fill sees every
    // winding edge.
    if (ip.need_close and (ip.x != ip.sx or ip.y != ip.sy)) {
        if (ip.nsegs >= out.len) return error.OutOfSpace;
        out[ip.nsegs] = .{
            .x = .{ ip.x, 0, 0, ip.sx },
            .y = .{ ip.y, 0, 0, ip.sy },
            .is_curve = false,
        };
        ip.nsegs += 1;
    }
    return out[0..ip.nsegs];
}

/// Ink bounding box of a glyph in font units (y-up), or null when the
/// glyph draws nothing. `scratch` must hold the largest glyph path
/// (8K segments covers the fixture's worst case several times over).
pub fn outlineBbox(font: *const CffFont, glyph: u16, scratch: []Seg) Error!?[4]f64 {
    const segs = try outline(font, glyph, scratch);
    if (segs.len == 0) return null;
    var x0 = std.math.inf(f64);
    var y0 = std.math.inf(f64);
    var x1 = -std.math.inf(f64);
    var y1 = -std.math.inf(f64);
    for (segs) |s| {
        // Lines store endpoints in slots 0 and 3; curves use all four.
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            if (!s.is_curve and (k == 1 or k == 2)) continue;
            x0 = @min(x0, s.x[k]);
            y0 = @min(y0, s.y[k]);
            x1 = @max(x1, s.x[k]);
            y1 = @max(y1, s.y[k]);
        }
    }
    return .{ x0, y0, x1, y1 };
}

test "cff loads the fixture with 4802 glyphs and subrs" {
    const alloc = std.testing.allocator;
    const path = @import("build_options").fixture_font;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(32 * 1024 * 1024));
    defer alloc.free(bytes);
    const font = try load(bytes);
    try std.testing.expectEqual(4802, font.num_glyphs);
    try std.testing.expect(font.subrs.count > 0);
    try std.testing.expectEqual(0, font.gsubrs.count);
}

test "every fixture glyph executes without error" {
    var scratch: [8192]Seg = undefined;
    const alloc = std.testing.allocator;
    const path = @import("build_options").fixture_font;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(32 * 1024 * 1024));
    defer alloc.free(bytes);
    const font = try load(bytes);
    var g: usize = 0;
    var blanks: usize = 0;
    while (g < font.num_glyphs) : (g += 1) {
        const segs = try outline(&font, @intCast(g), &scratch);
        if (segs.len == 0) blanks += 1;
    }
    // The fixture has blank glyphs (space, nonspacing marks); most must
    // draw. Bounds are wide on purpose — this is a no-crash sweep, and
    // exact bboxes are checked against CoreText in sw_backend's test.
    try std.testing.expect(blanks < font.num_glyphs / 2);
}
