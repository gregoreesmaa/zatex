//! Outline seam: glyph ink as CFF segments, demuxed per stack face.
const std = @import("std");
const cff = @import("cff");
const fontstack = @import("fontstack");

pub const Outlines = struct {
    ptr: *const anyopaque,
    // Segments in per-face font units (y-up, like CFF), or null to skip ink.
    // Never errors: failure resolves to null (skip-ink totality).
    glyphSegs: *const fn (ptr: *const anyopaque, unified: u16, out: []cff.Seg) ?[]const cff.Seg,
    // Integer advance in thousandths of an em (500 fallback inside file impl).
    advance1000: *const fn (ptr: *const anyopaque, unified: u16) i32,
    // Per-face units-per-em (1000 when unknown; ink is skipped anyway then).
    upmOf: *const fn (ptr: *const anyopaque, unified: u16) u16,
    // Ink box in thousandths, y-up, origin-relative [l, b, r, t]; zeros on failure.
    inkThou: *const fn (ptr: *const anyopaque, unified: u16) [4]i32,
};

pub const StackFile = struct {
    path: []const u8, // CWD-relative (CLI runs from packages/zatex-svg/)
    role: fontstack.Role,
    required: bool = true,
};

/// Default fixture stack: same files, same roles, same order as the
/// `zatex-png` CLI (`packages/zatex-png/src/main.zig:27-47`), so SVG
/// ink comes from exactly the faces layout measured with. Paths are
/// CWD-relative for a CLI run from `packages/zatex-svg/`.
pub const CLI_STACK: []const StackFile = &.{
    .{ .path = "../zatex/fixtures/fonts/latinmodern-math.otf", .role = .lm },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Main-Regular.otf", .role = .main },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Main-Bold.otf", .role = .main_bold },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Main-Italic.otf", .role = .main_italic },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Main-BoldItalic.otf", .role = .main_bi },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Math-Italic.otf", .role = .math_italic },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_AMS-Regular.otf", .role = .ams },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_SansSerif-Regular.otf", .role = .sans },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Typewriter-Regular.otf", .role = .typewriter },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Caligraphic-Regular.otf", .role = .cal },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Fraktur-Regular.otf", .role = .frak },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Script-Regular.otf", .role = .script },
    .{ .path = "../zatex/fixtures/fonts/STIXTwoMath-overline.otf", .role = .stix },
    .{ .path = "/System/Library/Fonts/Supplemental/STIXTwoMath.otf", .role = .stix, .required = false },
    .{ .path = "/Library/Fonts/STIXTwoMath.otf", .role = .stix, .required = false },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Size1-Regular.otf", .role = .size1 },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Size2-Regular.otf", .role = .size2 },
};

/// File-backed `Outlines`: one `fontstack` face per file plus the
/// face's parsed CFF font (`null` when `cff.load` rejects the file —
/// that face then serves null segs / zero ink, never an error).
/// Byte ownership stays with the caller: `addFile` borrows `bytes`
/// exactly like `fontstack.Stack.addFile` does.
pub const StackOutlines = struct {
    stack: fontstack.Stack = .{},
    cffs: [fontstack.max_faces]?cff.CffFont = [_]?cff.CffFont{null} ** fontstack.max_faces,

    pub fn addFile(self: *StackOutlines, role: fontstack.Role, bytes: []const u8) !void {
        try self.stack.addFile(role, bytes);
        self.cffs[self.stack.nfaces - 1] = cff.load(bytes) catch null;
    }

    pub fn iface(self: *const StackOutlines) Outlines {
        return .{
            .ptr = @ptrCast(self),
            .glyphSegs = glyphSegs,
            .advance1000 = advance1000,
            .upmOf = upmOf,
            .inkThou = inkThou,
        };
    }

    fn glyphSegs(ptr: *const anyopaque, unified: u16, out: []cff.Seg) ?[]const cff.Seg {
        const self: *const StackOutlines = @ptrCast(@alignCast(ptr));
        const r = self.stack.faceOf(unified) orelse return null;
        const slot = &self.cffs[r.index];
        if (slot.* == null) return null;
        return cff.outline(&slot.*.?, r.gid, out) catch return null;
    }

    fn advance1000(ptr: *const anyopaque, unified: u16) i32 {
        const self: *const StackOutlines = @ptrCast(@alignCast(ptr));
        return self.stack.advance1000(unified);
    }

    fn upmOf(ptr: *const anyopaque, unified: u16) u16 {
        const self: *const StackOutlines = @ptrCast(@alignCast(ptr));
        const r = self.stack.faceOf(unified) orelse return 1000;
        return self.stack.faces[r.index].font.upm;
    }

    fn inkThou(ptr: *const anyopaque, unified: u16) [4]i32 {
        const self: *const StackOutlines = @ptrCast(@alignCast(ptr));
        const r = self.stack.faceOf(unified) orelse return .{ 0, 0, 0, 0 };
        const slot = &self.cffs[r.index];
        if (slot.* == null) return .{ 0, 0, 0, 0 };
        const upm = self.stack.faces[r.index].font.upm;
        if (upm == 0) return .{ 0, 0, 0, 0 };
        // Stack-local scratch (cff's own 8K-segments precedent covers
        // the fixture's worst glyph several times over); too-small
        // resolves to zeros, never an error.
        var scratch: [8192]cff.Seg = undefined;
        const bb = cff.outlineBbox(&slot.*.?, r.gid, &scratch) catch return .{ 0, 0, 0, 0 };
        const b = bb orelse return .{ 0, 0, 0, 0 };
        return .{
            thou(b[0], upm),
            thou(b[1], upm),
            thou(b[2], upm),
            thou(b[3], upm),
        };
    }

    /// Font-unit float to core thousandths, truncating toward zero;
    /// unrepresentable inputs saturate instead of trapping.
    fn thou(v: f64, upm: u16) i32 {
        const q = @trunc(v * 1000.0 / @as(f64, @floatFromInt(upm)));
        if (!std.math.isFinite(q)) return 0;
        if (q >= 2147483647.0) return 2147483647;
        if (q <= -2147483648.0) return -2147483648;
        return @intFromFloat(q);
    }
};

test "scaffold outlines compiles" {
    try std.testing.expect(true);
}

test "stub outlines serve fixed segs" {
    const S = struct {
        var segbuf: [2]cff.Seg = .{
            .{ .x = .{ 0, 0, 0, 100 }, .y = .{ 0, 0, 0, 0 }, .is_curve = false },
            .{ .x = .{ 100, 0, 0, 100 }, .y = .{ 0, 0, 0, 100 }, .is_curve = true },
        };
        fn segs(_: *const anyopaque, _: u16, _: []cff.Seg) ?[]const cff.Seg { return &segbuf; }
        fn adv(_: *const anyopaque, _: u16) i32 { return 500; }
        fn upm(_: *const anyopaque, _: u16) u16 { return 1000; }
        fn ink(_: *const anyopaque, _: u16) [4]i32 { return .{ 0, 0, 100, 100 }; }
        var tag: u8 = 0;
    };
    const ol = Outlines{ .ptr = &S.tag, .glyphSegs = S.segs, .advance1000 = S.adv, .upmOf = S.upm, .inkThou = S.ink };
    var tmp: [8]cff.Seg = undefined;
    const got = ol.glyphSegs(ol.ptr, 42, &tmp).?;
    try std.testing.expectEqual(@as(usize, 2), got.len);
    try std.testing.expectEqual(@as(i32, 500), ol.advance1000(ol.ptr, 42));
}

fn readOutlineTestFile(path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        path,
        std.testing.allocator,
        .limited(8 * 1024 * 1024),
    );
}

test "every CLI stack face cff.loads" {
    // Fixture-dir precedent (zatex-png font.zig:181): the test runner
    // makes no CWD promise, so required entries resolve through the
    // build-provided fixture dir; absolute system fallbacks read as-is.
    try std.testing.expectEqual(@as(usize, 17), CLI_STACK.len);
    try std.testing.expectEqual(fontstack.Role.lm, CLI_STACK[0].role);
    try std.testing.expectEqual(fontstack.Role.size2, CLI_STACK[CLI_STACK.len - 1].role);
    const dir = std.fs.path.dirname(@import("build_options").fixture_font) orelse ".";
    const marker = "fixtures/fonts/";
    var pathbuf: [1024]u8 = undefined;
    for (CLI_STACK) |entry| {
        const full = if (std.mem.indexOf(u8, entry.path, marker)) |at|
            try std.fmt.bufPrint(&pathbuf, "{s}/{s}", .{ dir, entry.path[at + marker.len ..] })
        else
            entry.path;
        const bytes = readOutlineTestFile(full) catch |e| {
            if (!entry.required) continue;
            std.debug.print("required CLI_STACK face missing: {s} ({s})\n", .{ entry.path, @errorName(e) });
            return e;
        };
        defer std.testing.allocator.free(bytes);
        const cf = cff.load(bytes) catch |e| {
            std.debug.print("CLI_STACK face cff.load failed: {s} ({s})\n", .{ entry.path, @errorName(e) });
            return e;
        };
        try std.testing.expect(cf.num_glyphs > 0);
    }
}

test "stack outlines demux faces and skip unknown" {
    const dir = std.fs.path.dirname(@import("build_options").fixture_font) orelse ".";
    var p0: [1024]u8 = undefined;
    var p1: [1024]u8 = undefined;
    const lm_path = try std.fmt.bufPrint(&p0, "{s}/latinmodern-math.otf", .{dir});
    const main_path = try std.fmt.bufPrint(&p1, "{s}/katex/KaTeX_Main-Regular.otf", .{dir});
    const lm_bytes = try readOutlineTestFile(lm_path);
    defer std.testing.allocator.free(lm_bytes);
    const main_bytes = try readOutlineTestFile(main_path);
    defer std.testing.allocator.free(main_bytes);
    var so = StackOutlines{};
    try so.addFile(.lm, lm_bytes);
    try so.addFile(.main, main_bytes);
    const ol = so.iface();
    // FontId.rm == 0: 'A' stays on the LM face.
    const gid_a = so.stack.glyphIdFor(0, 'A');
    try std.testing.expect(gid_a != 0);
    try std.testing.expectEqual(fontstack.Role.lm, so.stack.roleOf(gid_a));
    var segbuf: [512]cff.Seg = undefined;
    const segs = ol.glyphSegs(ol.ptr, gid_a, &segbuf).?;
    try std.testing.expect(segs.len > 0);
    try std.testing.expect(ol.advance1000(ol.ptr, gid_a) > 0);
    try std.testing.expectEqual(so.stack.faces[0].font.upm, ol.upmOf(ol.ptr, gid_a));
    const ink = ol.inkThou(ol.ptr, gid_a);
    try std.testing.expect(ink[2] > ink[0] and ink[3] > ink[1]);
    // KaTeX-only codepoint demuxes to the Main face with real ink.
    const gid_macron = so.stack.glyphIdFor(0, 0x02C9);
    try std.testing.expect(gid_macron != 0);
    try std.testing.expectEqual(fontstack.Role.main, so.stack.roleOf(gid_macron));
    try std.testing.expect(ol.glyphSegs(ol.ptr, gid_macron, &segbuf).?.len > 0);
    // faceOf-miss id: null segs, 500 advance, 1000 upm, zero ink.
    try std.testing.expect(ol.glyphSegs(ol.ptr, 0xFFFF, &segbuf) == null);
    try std.testing.expectEqual(@as(i32, 500), ol.advance1000(ol.ptr, 0xFFFF));
    try std.testing.expectEqual(@as(u16, 1000), ol.upmOf(ol.ptr, 0xFFFF));
    try std.testing.expectEqual([4]i32{ 0, 0, 0, 0 }, ol.inkThou(ol.ptr, 0xFFFF));
    // Edge calls never error: a zero-length seg buffer (OutOfSpace
    // inside) resolves to null rather than failing.
    var empty: [0]cff.Seg = .{};
    try std.testing.expect(ol.glyphSegs(ol.ptr, gid_a, &empty) == null);
    // A face whose CFF would not load serves null ink too.
    so.cffs[0] = null;
    try std.testing.expect(ol.glyphSegs(ol.ptr, gid_a, &segbuf) == null);
    try std.testing.expectEqual([4]i32{ 0, 0, 0, 0 }, ol.inkThou(ol.ptr, gid_a));
}
