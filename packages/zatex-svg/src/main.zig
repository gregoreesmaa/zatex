//! zatex-svg CLI: LaTeX math -> standalone SVG (outlined paths).
//!
//! Usage:
//!   zatex-svg [--display] [--font PATH] "<tex>" out.svg
//!
//! Default: the vendored fixture stack (`CLI_STACK` in outlines.zig —
//! same files, same roles, same order as the `zatex-png` CLI, so SVG
//! ink comes from exactly the faces layout measured with). Paths are
//! CWD-relative, so run from `packages/zatex-svg/` (same assumption
//! as `zatex-png`). `--font PATH` keeps the legacy single-file host
//! instead of the stack.
const std = @import("std");
const zatex = @import("zatex");
const fontstack = @import("fontstack");
const cff = @import("cff");
const outlines_mod = @import("outlines.zig");
const svg = @import("svg.zig");

const usage =
    \\usage: zatex-svg [--display] [--font PATH] "<tex>" out.svg
    \\
;

const Args = struct {
    display_mode: bool = false,
    font_path: ?[]const u8 = null,
    tex: ?[]const u8 = null,
    out_path: ?[]const u8 = null,
};

// Pure argv parser (no filesystem — unit-tested below): `--display`
// flips display mode, `--font PATH` captures the single-file host
// path, then exactly two positionals (`tex`, `out.svg`). Anything
// else (missing values, unknown flags, extra positionals) is a usage
// error.
fn parseArgs(argv: []const []const u8) error{Usage}!Args {
    var a = Args{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const s = argv[i];
        if (std.mem.eql(u8, s, "--display")) {
            a.display_mode = true;
        } else if (std.mem.eql(u8, s, "--font")) {
            i += 1;
            if (i >= argv.len) return error.Usage;
            a.font_path = argv[i];
        } else if (std.mem.startsWith(u8, s, "--")) {
            return error.Usage;
        } else if (a.tex == null) {
            a.tex = s;
        } else if (a.out_path == null) {
            a.out_path = s;
        } else {
            return error.Usage;
        }
    }
    if (a.tex == null or a.out_path == null) return error.Usage;
    return a;
}

pub fn main(min: std.process.Init.Minimal) !void {
    const alloc = std.heap.c_allocator;
    // initAllocator on every OS: the plain init() is a compile error on
    // Windows, and the allocator form is a no-op wrapper elsewhere
    // (zatex-png precedent).
    var it = try std.process.Args.Iterator.initAllocator(min.args, alloc);
    defer it.deinit();
    _ = it.next(); // argv0

    // Bounded argv copy into the pure parser (unit-tested below, no
    // filesystem): overflow is a usage error, never truncation.
    var argv: [32][]const u8 = undefined;
    var n: usize = 0;
    while (it.next()) |a| {
        if (n >= argv.len) return usageError();
        argv[n] = a;
        n += 1;
    }
    const args = parseArgs(argv[0..n]) catch return usageError();
    const src = args.tex orelse return usageError();
    const dst = args.out_path orelse return usageError();

    // Every file's bytes stay alive for the stack's borrow (the stack
    // and the CFF faces both borrow these slices).
    var so = outlines_mod.StackOutlines{};
    var bufs: [fontstack.max_faces][]u8 = undefined;
    var nbufs: usize = 0;
    defer {
        for (bufs[0..nbufs]) |b| alloc.free(b);
    }

    if (args.font_path) |fp| {
        // Legacy single-file host (font.zig:34-41 precedent): the one
        // face answers everything — outlines via cff.load over the
        // file bytes, metrics via the single-face stack.
        loadOne(alloc, fp, .lm, &so, &bufs, &nbufs) catch |e| {
            std.debug.print("zatex-svg: cannot load font '{s}': {s}\n", .{ fp, @errorName(e) });
            return e;
        };
    } else {
        for (outlines_mod.CLI_STACK) |entry| {
            loadOne(alloc, entry.path, entry.role, &so, &bufs, &nbufs) catch |e| {
                if (!entry.required) continue;
                std.debug.print("zatex-svg: cannot load fixture stack: {s}\n", .{@errorName(e)});
                return e;
            };
        }
        if (so.stack.nfaces == 0) {
            std.debug.print("zatex-svg: cannot load fixture stack: FontLoad\n", .{});
            return error.FontLoad;
        }
    }

    // Same-files agreement (svg.render docs): the measuring provider
    // answers through the very stack the outlines demux through, so
    // measuring files == outline files by construction (one stack,
    // no copy: `Face` borrows the file bytes).
    const prov = so.stack.provider();
    const ol = so.iface();

    // Fixed caps; exhaustion is an honest NoSpace usage error below.
    const runs = try alloc.alloc(zatex.ir.Run, 2048);
    defer alloc.free(runs);
    const rules = try alloc.alloc(zatex.ir.Rule, 512);
    defer alloc.free(rules);
    const glyphs = try alloc.alloc(u16, 16384);
    defer alloc.free(glyphs);
    const segs = try alloc.alloc(cff.Seg, 8192);
    defer alloc.free(segs);
    const out = try alloc.alloc(u8, 1024 * 1024);
    defer alloc.free(out);

    var diag = zatex.Diag.empty();
    const doc = svg.render(
        src,
        .{ .display_mode = args.display_mode },
        prov,
        ol,
        runs,
        rules,
        glyphs,
        segs,
        out,
        &diag,
    ) catch |e| {
        // No new errors: every engine rejection (including engine-scope
        // Unsupported) surfaces here as a usage error with the diag
        // offset/message — the same bytes a host renders as real text
        // in its error fallback (zatex-png parity).
        std.debug.print("zatex-svg: render failed: {s} at offset {d}: {s}\n", .{ @errorName(e), diag.offset, diag.message });
        return e;
    };

    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    std.Io.Dir.cwd().writeFile(threaded.io(), .{ .sub_path = dst, .data = doc }) catch |e| {
        std.debug.print("zatex-svg: cannot write '{s}': {s}\n", .{ dst, @errorName(e) });
        return e;
    };
    std.debug.print("zatex-svg: {s} ({d} bytes)\n", .{ dst, doc.len });
}

/// Read one font file into caller-kept bytes and add it to the
/// stack under `role` (font.zig `addFile` precedent: the stack and
/// the CFF face both borrow `bytes`, so the caller keeps them alive).
fn loadOne(
    alloc: std.mem.Allocator,
    path: []const u8,
    role: fontstack.Role,
    so: *outlines_mod.StackOutlines,
    bufs: *[fontstack.max_faces][]u8,
    nbufs: *usize,
) !void {
    if (nbufs.* >= bufs.len) return error.FontLoad;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        path,
        alloc,
        .limited(8 * 1024 * 1024),
    ) catch return error.FontLoad;
    errdefer alloc.free(bytes);
    try so.addFile(role, bytes);
    bufs[nbufs.*] = bytes;
    nbufs.* += 1;
}

fn usageError() error{Usage} {
    std.debug.print("{s}", .{usage});
    return error.Usage;
}

test "--display flips display_mode" {
    const a = try parseArgs(&.{ "--display", "x^2", "out.svg" });
    try std.testing.expect(a.display_mode);
    try std.testing.expectEqualStrings("x^2", a.tex.?);
    try std.testing.expectEqualStrings("out.svg", a.out_path.?);
    try std.testing.expect(a.font_path == null);
}

test "plain tex keeps inline display_mode" {
    const a = try parseArgs(&.{ "x^2", "out.svg" });
    try std.testing.expect(!a.display_mode);
    try std.testing.expect(a.font_path == null);
}

test "--font captures path" {
    const a = try parseArgs(&.{ "--font", "f.otf", "x^2", "out.svg" });
    try std.testing.expectEqualStrings("f.otf", a.font_path.?);
    try std.testing.expectEqualStrings("x^2", a.tex.?);
    try std.testing.expectEqualStrings("out.svg", a.out_path.?);
}

test "missing args are usage errors" {
    try std.testing.expectError(error.Usage, parseArgs(&.{}));
    try std.testing.expectError(error.Usage, parseArgs(&.{"x^2"}));
    try std.testing.expectError(error.Usage, parseArgs(&.{"--display"}));
    try std.testing.expectError(error.Usage, parseArgs(&.{ "--font", "f.otf", "x^2" }));
}

test "--font without a value is a usage error" {
    try std.testing.expectError(error.Usage, parseArgs(&.{"--font"}));
    try std.testing.expectError(error.Usage, parseArgs(&.{ "--display", "--font" }));
}

test "extra positionals and unknown flags are usage errors" {
    try std.testing.expectError(error.Usage, parseArgs(&.{ "a", "b", "c" }));
    try std.testing.expectError(error.Usage, parseArgs(&.{ "--px", "48", "x^2", "out.svg" }));
}
