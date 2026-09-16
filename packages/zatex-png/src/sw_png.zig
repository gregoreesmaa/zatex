//! Minimal PNG encoder for the software backend: 8-bit RGBA,
//! filter-0 scanlines, zlib via `std.compress.flate`, one IDAT. No host
//! calls — portable across every OS the software backend serves.
const std = @import("std");

/// Write top-left row-major RGBA (`w` x `h`) to `path` as PNG.
pub fn writeRgba(alloc: std.mem.Allocator, path: []const u8, w: usize, h: usize, rgba: []const u8) !void {
    std.debug.assert(rgba.len >= w * h * 4);
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Filtered scanlines (filter type 0 = None per row).
    const stride = w * 4;
    const raw = try alloc.alloc(u8, h * (stride + 1));
    defer alloc.free(raw);
    var y: usize = 0;
    while (y < h) : (y += 1) {
        raw[y * (stride + 1)] = 0;
        @memcpy(raw[y * (stride + 1) + 1 ..][0..stride], rgba[y * stride ..][0..stride]);
    }

    // Deflate (zlib container) into a fixed buffer.
    const window = try alloc.alloc(u8, std.compress.flate.max_window_len);
    defer alloc.free(window);
    const comp_cap = raw.len + raw.len / 32 + 1024;
    const comp_buf = try alloc.alloc(u8, comp_cap);
    defer alloc.free(comp_buf);
    var fw = std.Io.Writer.fixed(comp_buf);
    var comp = try std.compress.flate.Compress.init(&fw, window, .zlib, .fastest);
    try comp.writer.writeAll(raw);
    try comp.finish();
    const comp_bytes = fw.buffered();

    // Assemble: signature + IHDR + IDAT + IEND.
    const total = 8 + (12 + 13) + (12 + comp_bytes.len) + 12;
    const png = try alloc.alloc(u8, total);
    defer alloc.free(png);
    @memcpy(png[0..8], &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });
    var pos: usize = 8;
    const ih = ihdr(w, h);
    pos = writeChunk(png, pos, "IHDR", &ih);
    pos = writeChunk(png, pos, "IDAT", comp_bytes);
    pos = writeChunk(png, pos, "IEND", &[_]u8{});
    std.debug.assert(pos == total);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = png });
}

fn ihdr(w: usize, h: usize) [13]u8 {
    var b: [13]u8 = undefined;
    std.mem.writeInt(u32, b[0..4], @intCast(w), .big);
    std.mem.writeInt(u32, b[4..8], @intCast(h), .big);
    b[8] = 8; // bit depth
    b[9] = 6; // color type: RGBA
    b[10] = 0; // compression
    b[11] = 0; // filter
    b[12] = 0; // interlace
    return b;
}

fn writeChunk(png: []u8, pos: usize, typ: *const [4]u8, body: []const u8) usize {
    std.mem.writeInt(u32, png[pos..][0..4], @intCast(body.len), .big);
    @memcpy(png[pos + 4 ..][0..4], typ);
    @memcpy(png[pos + 8 ..][0..body.len], body);
    const crc = std.hash.Crc32.hash(png[pos + 4 .. pos + 8 + body.len]);
    std.mem.writeInt(u32, png[pos + 8 + body.len ..][0..4], crc, .big);
    return pos + 12 + body.len;
}

test "png round-trips through a real decoder" {
    const alloc = std.testing.allocator;
    const w: usize = 5;
    const h: usize = 3;
    const rgba = try alloc.alloc(u8, w * h * 4);
    defer alloc.free(rgba);
    var i: usize = 0;
    while (i < w * h) : (i += 1) {
        rgba[i * 4] = @intCast((i * 37) & 0xFF);
        rgba[i * 4 + 1] = @intCast((i * 91 + 7) & 0xFF);
        rgba[i * 4 + 2] = @intCast((i * 13 + 101) & 0xFF);
        rgba[i * 4 + 3] = 255;
    }
    // Unique scratch dir per run: the sw/win/linux test binaries all
    // embed this test and `zig build test` runs them concurrently, so a
    // fixed path races (one binary read an empty file another had just
    // truncated). tmpDir's random sub_path is the uniqueness source;
    // both ends anchor at the process CWD so the relative path below
    // stays consistent wherever the runner executes us.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/sw_png_selftest.png", .{tmp.sub_path});
    try writeRgba(alloc, path, w, h, rgba);
    // Decode independently (stdlib zlib + filter 0) and compare bytes.
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const data = try std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, alloc, .limited(1 << 20));
    defer alloc.free(data);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 }, data[0..8]);
    // Walk chunks to the IDAT payload.
    var pos: usize = 8;
    var idat: []const u8 = &[_]u8{};
    while (pos < data.len) {
        const ln = std.mem.readInt(u32, data[pos..][0..4], .big);
        const typ = data[pos + 4 .. pos + 8];
        if (std.mem.eql(u8, typ, "IDAT")) idat = data[pos + 8 .. pos + 8 + ln];
        if (std.mem.eql(u8, typ, "IEND")) break;
        pos += 12 + ln;
    }
    try std.testing.expect(idat.len > 0);
    var in: std.Io.Reader = .fixed(idat);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var dec = std.compress.flate.Decompress.init(&in, .zlib, &window);
    const n = try dec.reader.streamRemaining(&aw.writer);
    const flat = aw.written();
    try std.testing.expectEqual(h * (w * 4 + 1), n);
    try std.testing.expectEqual(n, flat.len);
    var r: usize = 0;
    while (r < h) : (r += 1) {
        try std.testing.expectEqual(0, flat[r * (w * 4 + 1)]);
        try std.testing.expectEqualSlices(u8, rgba[r * w * 4 ..][0 .. w * 4], flat[r * (w * 4 + 1) + 1 ..][0 .. w * 4]);
    }
}
