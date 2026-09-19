//! Gallery renderer (issue 13): `tools/katex/corpus.json` → one browsable
//! MathML HTML page on stdout. Browsers render MathML natively, so there
//! is no rasterizer, no screenshot, no new dependency — and per
//! AGENTS.md §4 this stays an informational eyeball aid, never a
//! required gate. Pinned KaTeX output (`goldens/katex_sweep.json`)
//! remains truth; if the gallery and the sweep ever disagree, the
//! gallery is wrong.
//!
//! The corpus is the checklist: adding support for a function adds its
//! row to `corpus.json`, which adds its section here automatically.
//! CI (`gallery` job) renders head and base and uploads both; reviewers
//! compare the artifacts, never pixels in a gate.
//!
//! Usage: `zig build gallery && ./zig-out/bin/gallery 2> gallery.html`
//! (HTML goes to stderr via `std.debug.print`; the one CLI-free,
//! file-free surface this tool needs.)
const std = @import("std");
const zatex = @import("zatex");
const zatex_mathml = @import("zatex_mathml");

const corpus = @embedFile("katex/corpus.json");

pub fn main() !void {
    const p = std.debug.print;
    p(
        \\<!DOCTYPE html>
        \\<html lang="en"><head><meta charset="utf-8">
        \\<title>ZaTeX gallery (informational — pinned KaTeX output is truth)</title>
        \\<style>body{{font-family:sans-serif;max-width:60em;margin:2em auto}}pre{{background:#f4f4f4;padding:.5em;overflow-x:auto}}.err{{color:#a00}}section{{border-top:1px solid #ccc;padding:1em 0}}</style>
        \\</head><body>
        \\<h1>ZaTeX gallery</h1>
        \\<p>Informational only, never a gate (AGENTS.md §4). Same source + same metrics renders byte-identical MathML; eyeball diffs against the base-commit gallery, not truth.</p>
        \\
    , .{});

    var rows: usize = 0;
    var pos: usize = 0;
    var ubuf: [2048]u8 = undefined;
    var mbuf: [65536]u8 = undefined;
    while (nextRow(corpus, &pos)) |row| {
        rows += 1;
        const tex = try unescape(row.tex, &ubuf);
        p("<section><h2>", .{});
        htmlEsc(row.id);
        p("</h2><pre>", .{});
        htmlEsc(tex);
        p("</pre><p>display={} expect={s}</p>\n", .{ row.display, row.expect });
        p("<!-- row:", .{});
        htmlEsc(row.id);
        if (zatex_mathml.render(tex, .{ .display_mode = row.display }, &mbuf)) |math| {
            p("-->\n{s}\n", .{math});
        } else |e| {
            p("--><p class=\"err\">error.{s}</p>", .{@errorName(e)});
        }
        p("<!-- /row:", .{});
        htmlEsc(row.id);
        p("--></section>\n", .{});
    }
    p("<footer><p>{d} rows.</p></footer></body></html>\n", .{rows});
}

const Row = struct {
    id: []const u8,
    tex: []const u8,
    display: bool,
    expect: []const u8,
};

/// Scan the next `{{"id": …, "tex": …, "display": …, "expect": …}}`
/// object. The corpus is machine-generated with a fixed shape, so a
/// targeted scanner beats a general JSON parser (zero dependencies).
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

/// Raw (still-escaped) JSON string value starting at `p` (which must
/// point at or before the opening quote); advances past the closing
/// quote. Handles `\"` so embedded quotes don't end the scan.
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

/// JSON-unescape one corpus string into `out` (handles the escapes
/// sweep.mjs emits: `\\`, `\"`, `\/`, `\n`, `\t`, `\r`, `\b`, `\f`,
/// `\uXXXX`). Corpus strings are short ASCII; the caller buffer must
/// hold 3x the raw length.
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

fn htmlEsc(s: []const u8) void {
    const p = std.debug.print;
    for (s) |c| switch (c) {
        '&' => p("&amp;", .{}),
        '<' => p("&lt;", .{}),
        '>' => p("&gt;", .{}),
        '"' => p("&quot;", .{}),
        else => p("{c}", .{c}),
    };
}
