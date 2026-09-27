//! Real-font layout inspector (issue #264): one formula against the
//! blessed file provider, real runs/rules as JSON on stdout.
//!
//! `ir_dump` prints construction counts with stub metrics (every
//! advance 500 — geometrically meaningless). This tool answers the
//! host integrator's first question when pixels disagree with
//! expectations — "is the ENGINE's layout wrong, or my draw code?" —
//! by dumping the actual runs/rules the engine emits for a real face.
//!
//! Usage: `zig build inspect` (in packages/zatex) then
//!   `./zig-out/bin/inspect [--display] [--font PATH] "<tex>"`
//! The default face is the vendored Latin Modern Math, resolved
//! relative to the working directory like `zatex-png`'s default stack
//! (run from packages/zatex, or pass `--font`). JSON goes to stdout;
//! failures go to stderr with a nonzero exit. A host tool (like
//! `irdump`): the shipped lib is untouched, so the size gate cannot
//! see it.
const std = @import("std");
const zatex = @import("zatex");
const fileprovider = @import("fileprovider");

const default_font = "fixtures/fonts/latinmodern-math.otf";

/// JSON-escape `s` (including the quotes) into `out`; returns the slice.
// Over-allocates 6x (worst case `\u00XX` per byte) — the caller sizes it.
fn jsonEscape(s: []const u8, out: []u8) []u8 {
    var pos: usize = 0;
    out[pos] = '"';
    pos += 1;
    const hex = "0123456789abcdef";
    for (s) |c| switch (c) {
        '"' => {
            out[pos] = '\\';
            out[pos + 1] = '"';
            pos += 2;
        },
        '\\' => {
            out[pos] = '\\';
            out[pos + 1] = '\\';
            pos += 2;
        },
        '\n' => {
            out[pos] = '\\';
            out[pos + 1] = 'n';
            pos += 2;
        },
        '\t' => {
            out[pos] = '\\';
            out[pos + 1] = 't';
            pos += 2;
        },
        '\r' => {
            out[pos] = '\\';
            out[pos + 1] = 'r';
            pos += 2;
        },
        0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {
            out[pos] = '\\';
            out[pos + 1] = 'u';
            out[pos + 2] = '0';
            out[pos + 3] = '0';
            out[pos + 4] = hex[c >> 4];
            out[pos + 5] = hex[c & 15];
            pos += 6;
        },
        else => {
            out[pos] = c;
            pos += 1;
        },
    };
    out[pos] = '"';
    pos += 1;
    return out[0..pos];
}

pub fn main(min: std.process.Init.Minimal) !void {
    const alloc = std.heap.c_allocator;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var it = try std.process.Args.Iterator.initAllocator(min.args, alloc);
    defer it.deinit();
    _ = it.next(); // argv0

    var display = false;
    var font_path: []const u8 = default_font;
    var tex: ?[]const u8 = null;
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--display")) {
            display = true;
        } else if (std.mem.eql(u8, a, "--font")) {
            font_path = it.next() orelse {
                std.debug.print("usage: inspect [--display] [--font PATH] \"<tex>\"\n", .{});
                std.process.exit(2);
            };
        } else if (tex == null) {
            tex = a;
        } else {
            std.debug.print("usage: inspect [--display] [--font PATH] \"<tex>\"\n", .{});
            std.process.exit(2);
        }
    }
    const src = tex orelse {
        std.debug.print("usage: inspect [--display] [--font PATH] \"<tex>\"\n", .{});
        std.process.exit(2);
    };

    const font_bytes = std.Io.Dir.cwd().readFileAlloc(io, font_path, alloc, .limited(64 << 20)) catch {
        std.debug.print("inspect: cannot read font {s} (run from packages/zatex, or pass --font)\n", .{font_path});
        std.process.exit(1);
    };
    defer alloc.free(font_bytes);
    var fp = fileprovider.FileProvider.init(font_bytes) catch {
        std.debug.print("inspect: not a font: {s}\n", .{font_path});
        std.process.exit(1);
    };
    const provider = fp.provider();

    var runs: [1024]zatex.ir.Run = undefined;
    var rules: [128]zatex.ir.Rule = undefined;
    var glyphs: [32768]u16 = undefined;
    var diag = zatex.Diag.empty();
    const l = zatex.layoutDiag(
        src,
        .{ .display_mode = display },
        provider,
        &runs,
        &rules,
        &glyphs,
        &diag,
    ) catch |e| {
        std.debug.print("inspect: {s} at byte {d}: {s}\n", .{ @errorName(e), diag.offset, diag.message });
        std.process.exit(1);
    };

    const esc_buf = try alloc.alloc(u8, src.len * 6 + 2);
    const esc = jsonEscape(src, esc_buf);
    var out_buf: [65536]u8 = undefined;
    var out: std.Io.Writer = .fixed(&out_buf);
    const w = &out;
    try w.print("{{\"tex\":{s},\"display\":{s},\"width\":{d},\"height_above\":{d},\"depth_below\":{d},\"font\":{s},\"upm\":{d},\"runs\":[", .{
        esc,
        if (display) "true" else "false",
        l.width,
        l.height_above,
        l.depth_below,
        jsonEscape(font_path, try alloc.alloc(u8, font_path.len * 6 + 2)),
        fp.upm(),
    });
    for (l.runs, 0..) |r, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"font_id\":{d},\"size_units\":{d},\"x\":{d},\"baseline_y\":{d},\"x_scale\":{d},\"x_shear\":{d},\"mirrored\":{s},\"glyphs\":[", .{
            r.font_id, r.size_units, r.x, r.baseline_y, r.x_scale, r.x_shear,
            if (r.mirrored) "true" else "false",
        });
        for (r.glyphs, 0..) |g, j| {
            if (j > 0) try w.print(",", .{});
            try w.print("{d}", .{g});
        }
        try w.print("]", .{});
        if (r.color) |c| try w.print(",\"color\":{d}", .{c});
        try w.print("}}", .{});
    }
    try w.print("],\"rules\":[", .{});
    for (l.rules, 0..) |ru, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d}}}", .{ ru.x, ru.y, ru.w, ru.h });
    }
    try w.print("]}}\n", .{});
    const written = w.buffered();
    try std.Io.File.stdout().writeStreamingAll(io, written);
}
