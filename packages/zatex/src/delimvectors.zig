//! Delimiter-scan conformance vectors (issue #252): test-only replay.
//!
//! `goldens/delimiter_vectors.json` is generated from the PINNED KaTeX
//! auto-render splitter (see `tools/katex/gen_delim_vectors.mjs` and
//! `docs/delimiter-scan.md`). This module replays every vector against
//! the EXISTING engine only — it adds no scanner and no core API (the
//! spec demands vectors-before-helper):
//!
//! - island byte offsets must reconstruct the vector text, be ordered
//!   and non-overlapping, and match a row of the named delimiter
//!   table (payload between delimiters, or the full raw span for
//!   `\begin{…}` islands, exactly like KaTeX);
//! - the engine verdict on each payload (`layoutFull` under a stub
//!   provider) must equal the KaTeX-proven `engine` flag — accept AND
//!   reject alike (the brace-shield payload is invalid TeX in both).
const std = @import("std");
const zatex = @import("zatex");

// Goldens live beside the package and load relative to the test
// runner's CWD (same convention as `parity.zig`/`qa.zig`: the build
// wires `setCwd(b.path("."))`, so this resolves to
// `packages/zatex/goldens/delimiter_vectors.json`).
const vectors_path = "goldens/delimiter_vectors.json";

const Delim = struct {
    left: []const u8,
    right: []const u8,
    display: bool,
};

const Island = struct {
    start: usize,
    end: usize,
    display: bool,
    tex: []const u8,
    engine: []const u8,
};

const Vector = struct {
    id: []const u8,
    text: []const u8,
    delims: []const u8,
    guards: bool,
    mask_code: bool = false,
    islands: []Island,
    note: ?[]const u8 = null,
};

const Tables = struct {
    katex_default: []Delim,
    dollar: []Delim,
};

const Meta = struct {
    katex: []const u8,
    splitter: []const u8,
    splitter_sha256: []const u8,
    generator: []const u8,
    note: []const u8,
};

const Doc = struct {
    meta: Meta,
    delim_tables: Tables,
    vectors: []Vector,
};

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

fn tableFor(doc: Doc, name: []const u8) []Delim {
    if (std.mem.eql(u8, name, "katex_default")) return doc.delim_tables.katex_default;
    if (std.mem.eql(u8, name, "dollar")) return doc.delim_tables.dollar;
    std.debug.panic("unknown delimiter table: {s}", .{name});
}

test "delimiter vectors replay: offsets, tables, engine verdicts" {
    const alloc = std.testing.allocator;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const vectors_json = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        vectors_path,
        alloc,
        .limited(1 << 20),
    );
    defer alloc.free(vectors_json);
    const parsed = try std.json.parseFromSlice(Doc, alloc, vectors_json, .{});
    defer parsed.deinit();
    const doc = parsed.value;

    // Pinned-KaTeX tripwire: a splitter upgrade must consciously
    // refresh the vectors (via the generator), the spec, and these
    // counts together — never exactly one of them.
    try std.testing.expectEqualStrings("0.18.7", doc.meta.katex);
    try std.testing.expectEqual(@as(usize, 27), doc.vectors.len);

    var dummy: u8 = 0;
    const prov = zatex.MetricsProvider{
        .ctx = &dummy,
        .glyphId = Stub.glyphId,
        .advance = Stub.advance,
        .ruleThickness = Stub.ruleThickness,
    };

    var total_islands: usize = 0;
    var seen_ids = std.StringHashMap(void).init(alloc);
    defer seen_ids.deinit();
    for (doc.vectors) |v| {
        try std.testing.expect((try seen_ids.fetchPut(v.id, {})) == null);
        const table = tableFor(doc, v.delims);
        var prev_end: usize = 0;
        for (v.islands) |isl| {
            // Ordered, non-overlapping, inside the text.
            try std.testing.expect(isl.start >= prev_end);
            try std.testing.expect(isl.end <= v.text.len);
            try std.testing.expect(isl.start <= isl.end);
            prev_end = isl.end;
            const raw = v.text[isl.start..isl.end];

            // Matches one table row: payload between delimiters, or
            // the full raw span for `\begin{…}` islands (KaTeX keeps
            // the environment in the payload — see the spec §1.2).
            var matched = false;
            for (table) |d| {
                if (!std.mem.startsWith(u8, raw, d.left)) continue;
                if (!std.mem.endsWith(u8, raw, d.right)) continue;
                if (std.mem.startsWith(u8, isl.tex, "\\begin{")) {
                    if (!std.mem.eql(u8, raw, isl.tex)) continue;
                } else {
                    if (raw.len != d.left.len + isl.tex.len + d.right.len) continue;
                    if (!std.mem.eql(u8, raw[d.left.len .. raw.len - d.right.len], isl.tex)) continue;
                }
                try std.testing.expectEqual(d.display, isl.display);
                matched = true;
                break;
            }
            if (!matched) std.debug.panic("vector {s}: island {d}..{d} matches no {s} row", .{ v.id, isl.start, isl.end, v.delims });

            // Engine verdict equals the KaTeX-proven flag.
            var runs: [256]zatex.ir.Run = undefined;
            var rules: [64]zatex.ir.Rule = undefined;
            var glyphs: [4096]u16 = undefined;
            const verdict = if (zatex.layoutFull(
                isl.tex,
                .{ .display_mode = isl.display },
                prov,
                &runs,
                &rules,
                &glyphs,
            )) |_| "accept" else |_| "reject";
            try std.testing.expectEqualStrings(isl.engine, verdict);
            total_islands += 1;
        }
    }
    // Non-vacuous tripwire: vectors must keep proving islands exist.
    try std.testing.expectEqual(@as(usize, 25), total_islands);
}
