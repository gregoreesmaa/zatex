//! zatex-png: LaTeX -> PNG screenshots (single formula or corpus batch).
//!
//! Usage:
//!   zatex-png [--display] [--px N] [--font PATH] "<tex>" out.png
//!   zatex-png --corpus PATH --outdir DIR [--px N] [--font PATH]
//!
//! Batch renders every `accept` row of the corpus to `<id>.png` and
//! skips rejects; any accept row the engine fails exits nonzero.
//! Defaults: 48 px em and the vendored fixture stack (Latin Modern
//! Math first, then the KaTeX faces, then system STIX when present),
//! so same input renders identical pixels. `--font PATH` keeps the
//! legacy single-file host instead of the stack.
const std = @import("std");
const zatex = @import("zatex");
const Font = @import("font.zig").Font;
const render = @import("render.zig");

const usage =
    \\usage: zatex-png [--display] [--px N] [--font PATH] "<tex>" out.png
    \\       zatex-png --corpus PATH --outdir DIR [--px N] [--font PATH]
    \\
;

/// Default fixture stack (issue #92): same files, same roles, same
/// order as the core reference host, so CLI pixels match refhost
/// metrics exactly. Paths are CWD-relative like the old default.
const default_stack = [_]Font.StackFile{
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
    // Large operators (issue #101) load last so every existing
    // unified gid stays bit-identical.
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Size1-Regular.otf", .role = .size1 },
    .{ .path = "../zatex/fixtures/fonts/katex/KaTeX_Size2-Regular.otf", .role = .size2 },
};

pub fn main(min: std.process.Init.Minimal) !void {
    const alloc = std.heap.c_allocator;
    // initAllocator on every OS: the plain init() is a compile error on
    // Windows, and the allocator form is a no-op wrapper elsewhere.
    var it = try std.process.Args.Iterator.initAllocator(min.args, alloc);
    defer it.deinit();
    _ = it.next(); // argv0

    var display = false;
    var px_per_em: u32 = 48;
    var font_path: ?[]const u8 = null;
    var corpus_path: ?[]const u8 = null;
    var outdir: ?[]const u8 = null;
    var tex: ?[]const u8 = null;
    var out_png: ?[]const u8 = null;

    while (it.next()) |a| {
        const s: []const u8 = a;
        if (std.mem.eql(u8, s, "--display")) {
            display = true;
        } else if (std.mem.eql(u8, s, "--px")) {
            const v = it.next() orelse return usageError();
            px_per_em = std.fmt.parseInt(u32, v, 10) catch return usageError();
            if (px_per_em == 0 or px_per_em > 512) return usageError();
        } else if (std.mem.eql(u8, s, "--font")) {
            const v = it.next() orelse return usageError();
            font_path = v;
        } else if (std.mem.eql(u8, s, "--corpus")) {
            const v = it.next() orelse return usageError();
            corpus_path = v;
        } else if (std.mem.eql(u8, s, "--outdir")) {
            const v = it.next() orelse return usageError();
            outdir = v;
        } else if (tex == null and corpus_path == null) {
            tex = s;
        } else if (out_png == null and corpus_path == null) {
            out_png = s;
        } else {
            return usageError();
        }
    }

    var font: Font = undefined;
    if (font_path) |fp| {
        font = Font.load(alloc, fp) catch |e| {
            std.debug.print("zatex-png: cannot load font '{s}': {s}\n", .{ fp, @errorName(e) });
            return e;
        };
    } else {
        font = Font.loadStack(alloc, &default_stack) catch |e| {
            std.debug.print("zatex-png: cannot load fixture stack: {s}\n", .{@errorName(e)});
            return e;
        };
    }
    defer font.close();

    if (corpus_path) |cp| {
        const od = outdir orelse return usageError();
        return batch(alloc, &font, cp, od, px_per_em);
    }
    const src = tex orelse return usageError();
    const dst = out_png orelse return usageError();
    return single(&font, src, dst, display, px_per_em);
}

fn usageError() error{Usage} {
    std.debug.print("{s}", .{usage});
    return error.Usage;
}

fn single(font: *Font, src: []const u8, dst: []const u8, display: bool, px: u32) !void {
    const layout = zatex.layoutFull(src, .{ .display_mode = display }, font.provider(), runsBuf(), rulesBuf(), glyphsBuf()) catch |e| {
        std.debug.print("zatex-png: layout failed: {s}\n", .{@errorName(e)});
        return e;
    };
    try render.renderToPng(font, layout, px, 16, dst);
    std.debug.print("zatex-png: {s} ({d}x{d}+{d})\n", .{ dst, layout.width, layout.height_above, layout.depth_below });
}

// Stack scratch for one layout (engine ceilings: 256 runs / 64 rules).
var runs_mem: [256]zatex.ir.Run = undefined;
var rules_mem: [64]zatex.ir.Rule = undefined;
var glyphs_mem: [4096]u16 = undefined;

fn runsBuf() []zatex.ir.Run {
    return &runs_mem;
}
fn rulesBuf() []zatex.ir.Rule {
    return &rules_mem;
}
fn glyphsBuf() []u16 {
    return &glyphs_mem;
}

fn batch(
    alloc: std.mem.Allocator,
    font: *Font,
    corpus_path: []const u8,
    outdir: []const u8,
    px: u32,
) !void {
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const corpus = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        corpus_path,
        alloc,
        .limited(4 * 1024 * 1024),
    ) catch |e| {
        std.debug.print("zatex-png: cannot read corpus '{s}': {s}\n", .{ corpus_path, @errorName(e) });
        return e;
    };
    defer alloc.free(corpus);
    std.Io.Dir.cwd().createDirPath(threaded.io(), outdir) catch |e| {
        std.debug.print("zatex-png: cannot create '{s}': {s}\n", .{ outdir, @errorName(e) });
        return e;
    };

    var rendered: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;
    var pos: usize = 0;
    var ubuf: [2048]u8 = undefined;
    var namebuf: [128]u8 = undefined;
    var pathbuf: [512]u8 = undefined;
    while (nextRow(corpus, &pos)) |row| {
        if (!std.mem.eql(u8, row.expect, "accept")) {
            skipped += 1;
            continue;
        }
        const src = unescape(row.tex, &ubuf) catch {
            std.debug.print("zatex-png: bad escape in row '{s}', skipped\n", .{row.id});
            skipped += 1;
            continue;
        };
        const layout = zatex.layoutFull(
            src,
            .{ .display_mode = row.display },
            font.provider(),
            runsBuf(),
            rulesBuf(),
            glyphsBuf(),
        ) catch |e| {
            std.debug.print("zatex-png: row '{s}' failed ({s}), skipped\n", .{ row.id, @errorName(e) });
            failed += 1;
            continue;
        };
        const name = sanitizeId(row.id, &namebuf);
        const dst = std.fmt.bufPrint(&pathbuf, "{s}/{s}.png", .{ outdir, name }) catch {
            std.debug.print("zatex-png: path too long for row '{s}', skipped\n", .{row.id});
            skipped += 1;
            continue;
        };
        render.renderToPng(font, layout, px, 16, dst) catch |e| {
            std.debug.print("zatex-png: row '{s}' write failed ({s})\n", .{ row.id, @errorName(e) });
            failed += 1;
            continue;
        };
        rendered += 1;
    }
    std.debug.print("png-batch: rendered={d} skipped={d} failed={d} out={s}\n", .{ rendered, skipped, failed, outdir });
    if (failed > 0) return error.BatchFailed;
}

/// Filesystem-safe row name: alphanumerics plus `-_.`, else `_`.
fn sanitizeId(id: []const u8, out: []u8) []u8 {
    var n: usize = 0;
    for (id) |c| {
        if (n >= out.len) break;
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '-' or c == '_' or c == '.';
        out[n] = if (ok) c else '_';
        n += 1;
    }
    if (n == 0 and out.len > 0) {
        out[0] = '_';
        n = 1;
    }
    return out[0..n];
}

const Row = struct {
    id: []const u8,
    tex: []const u8,
    display: bool,
    expect: []const u8,
};

/// Same fixed-shape corpus scanner as the MathML gallery (zero
/// dependencies beat a JSON parser here too).
fn nextRow(buf: []const u8, pos: *usize) ?Row {
    const id_key = "\"id\"";
    const at = std.mem.indexOfPos(u8, buf, pos.*, id_key) orelse return null;
    var p = at + id_key.len;
    const id = takeString(buf, &p) orelse return null;
    const tex_key = "\"tex\"";
    p = (std.mem.indexOfPos(u8, buf, p, tex_key) orelse return null) + tex_key.len;
    const tex = takeString(buf, &p) orelse return null;
    const disp_key = "\"display\"";
    p = (std.mem.indexOfPos(u8, buf, p, disp_key) orelse return null) + disp_key.len;
    skipWs(buf, &p);
    var display = false;
    if (std.mem.startsWith(u8, buf[p..], "true")) {
        display = true;
        p += 4;
    } else if (std.mem.startsWith(u8, buf[p..], "false")) {
        p += 5;
    } else return null;
    const exp_key = "\"expect\"";
    p = (std.mem.indexOfPos(u8, buf, p, exp_key) orelse return null) + exp_key.len;
    const expect = takeString(buf, &p) orelse return null;
    pos.* = p;
    return .{ .id = id, .tex = tex, .display = display, .expect = expect };
}

fn skipWs(buf: []const u8, p: *usize) void {
    while (p.* < buf.len and (buf[p.*] == ' ' or buf[p.*] == '\t' or buf[p.*] == '\n' or buf[p.*] == '\r' or buf[p.*] == ':')) : (p.* += 1) {}
}

fn takeString(buf: []const u8, p: *usize) ?[]const u8 {
    while (p.* < buf.len and buf[p.*] != '"') : (p.* += 1) {}
    if (p.* >= buf.len) return null;
    p.* += 1;
    const start = p.*;
    while (p.* < buf.len) {
        if (buf[p.*] == '\\') {
            p.* += 2;
            continue;
        }
        if (buf[p.*] == '"') break;
        p.* += 1;
    }
    if (p.* >= buf.len) return null;
    const s = buf[start..p.*];
    p.* += 1;
    return s;
}

fn unescape(s: []const u8, out: []u8) ![]u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] != '\\' or i + 1 >= s.len) {
            if (n >= out.len) return error.NoSpace;
            out[n] = s[i];
            n += 1;
            i += 1;
            continue;
        }
        i += 1;
        switch (s[i]) {
            '"', '\\', '/' => {
                if (n >= out.len) return error.NoSpace;
                out[n] = s[i];
                n += 1;
                i += 1;
            },
            'n' => {
                if (n >= out.len) return error.NoSpace;
                out[n] = '\n';
                n += 1;
                i += 1;
            },
            't' => {
                if (n >= out.len) return error.NoSpace;
                out[n] = '\t';
                n += 1;
                i += 1;
            },
            'r' => {
                if (n >= out.len) return error.NoSpace;
                out[n] = '\r';
                n += 1;
                i += 1;
            },
            'b' => {
                if (n >= out.len) return error.NoSpace;
                out[n] = 0x08;
                n += 1;
                i += 1;
            },
            'f' => {
                if (n >= out.len) return error.NoSpace;
                out[n] = 0x0C;
                n += 1;
                i += 1;
            },
            'u' => {
                if (i + 4 >= s.len) return error.Invalid;
                const cp = try std.fmt.parseInt(u21, s[i + 1 .. i + 5], 16);
                i += 5;
                n += try std.unicode.utf8Encode(cp, out[n..]);
            },
            else => return error.Invalid,
        }
    }
    return out[0..n];
}

test "unescape handles sweep escapes" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("\\frac{a}{b}", try unescape("\\\\frac{a}{b}", &buf));
    try std.testing.expectEqualStrings("a\"b", try unescape("a\\\"b", &buf));
    try std.testing.expectEqualStrings("x", try unescape("\\u0078", &buf));
}

test "sanitizeId keeps safe names" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("demo-fourier", sanitizeId("demo-fourier", &buf));
    try std.testing.expectEqualStrings("a_b.c", sanitizeId("a_b.c", &buf));
    try std.testing.expectEqualStrings("a_b", sanitizeId("a/b", &buf));
}

test "nextRow scans the fixed corpus shape" {
    const doc =
        \\[{ "id": "r1", "tex": "x^2", "display": false, "expect": "accept" },
        \\ { "id": "r2", "tex": "\\frac12", "display": true, "expect": "reject" }]
    ;
    var pos: usize = 0;
    const a = nextRow(doc, &pos).?;
    try std.testing.expectEqualStrings("r1", a.id);
    try std.testing.expectEqualStrings("x^2", a.tex);
    try std.testing.expect(!a.display);
    const b = nextRow(doc, &pos).?;
    try std.testing.expectEqualStrings("r2", b.id);
    try std.testing.expect(b.display);
    try std.testing.expectEqualStrings("reject", b.expect);
    try std.testing.expect(nextRow(doc, &pos) == null);
}

test "font stack tests execute" {
    std.testing.refAllDecls(@import("font.zig"));
}
