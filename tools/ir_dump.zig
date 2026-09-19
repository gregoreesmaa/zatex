//! IR dump helper for the pure-TeX geometry oracle (issue #178):
//! `tools/tex-geometry/corpus.json` -> one JSON object per formula on
//! stdout (`{"tex","display","glyphs","rules","width",...}`), so
//! `diff_geometry.py` can compare ZaTeX box *construction* against the
//! TeX DVI dump. Informational triage only, never a gate (AGENTS.md
//! §4): pinned KaTeX remains truth; counts compare, metrics never do
//! (the stub advances below are not a font).
//!
//! Usage: `zig build irdump && ./zig-out/bin/irdump [--display] "<tex>"`
//! (JSON goes to stdout; failures go to stderr with a nonzero exit so
//! the driver reports the row as missing instead of comparing zeros.)
const std = @import("std");
const zatex = @import("zatex");

/// Fixed stub metrics (the `qa.zig` Stub: advance 500, rule 40,
/// glyph id = codepoint). Deterministic, no fonts, no network.
const Stub = struct {
    fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
        return @truncate(cp);
    }
    fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
        return 500;
    }
    fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
        return 40;
    }
};

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
    // initAllocator on every OS: the plain init() is a compile error on
    // Windows, and the allocator form is a no-op wrapper elsewhere
    // (same shape as `zatex-png`'s CLI).
    var it = try std.process.Args.Iterator.initAllocator(min.args, alloc);
    defer it.deinit();
    _ = it.next(); // argv0

    var display = false;
    var tex: ?[]const u8 = null;
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--display")) {
            display = true;
        } else if (tex == null) {
            tex = a;
        } else {
            std.debug.print("usage: irdump [--display] \"<tex>\"\n", .{});
            std.process.exit(2);
        }
    }
    const src = tex orelse {
        std.debug.print("usage: irdump [--display] \"<tex>\"\n", .{});
        std.process.exit(2);
    };

    var dummy: u8 = 0;
    const provider = zatex.MetricsProvider{
        .ctx = &dummy,
        .glyphId = Stub.glyphId,
        .advance = Stub.advance,
        .ruleThickness = Stub.ruleThickness,
    };
    var runs: [1024]zatex.ir.Run = undefined;
    var rules: [128]zatex.ir.Rule = undefined;
    var glyphs: [8192]u16 = undefined;
    var diag = zatex.Diag.empty();
    const l = zatex.layoutDiag(src, .{ .display_mode = display }, provider, &runs, &rules, &glyphs, &diag) catch |e| {
        std.debug.print("irdump: {s} at byte {d}: {s}\n", .{ @errorName(e), diag.offset, diag.message });
        std.process.exit(1);
    };
    var n_glyphs: usize = 0;
    for (l.runs) |r| n_glyphs += r.glyphs.len;

    // One JSON object on stderr (the gallery surface: CLI-free,
    // file-free; the driver redirects `2>` like the gallery job).
    const esc_buf = try alloc.alloc(u8, src.len * 6 + 2);
    const esc = jsonEscape(src, esc_buf);
    std.debug.print("{{\"tex\":{s},\"display\":{s},\"glyphs\":{d},\"rules\":{d},\"width\":{d},\"height_above\":{d},\"depth_below\":{d}}}\n", .{
        esc,
        if (display) "true" else "false",
        n_glyphs,
        l.rules.len,
        l.width,
        l.height_above,
        l.depth_below,
    });
}
