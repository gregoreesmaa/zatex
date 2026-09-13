//! Fixed-seed grammar fuzzer over parse → expand → layout (issue #23).
//!
//! In-process, zero-dependency, deterministic: a `DefaultPrng` with a
//! pinned seed renders nested tex from a small grammar (radicals,
//! fracs, delim scaling, scripts, tables, styles) into a stack buffer
//! and drives the stub-provider layout path. Every render must be
//! total (ok or an honest cap error — never a panic or hang) and
//! deterministic; ok layouts satisfy the shared `invariants` (shared
//! with the #24 probes, not redefined here). No allocator is used
//! anywhere: caller buffers only, per `docs/ir.md`. Coverage: caps are
//! asserted by name against `contract` (`max_input_len`,
//! `max_nesting_depth`, `max_expand`).
const std = @import("std");
const zatex = @import("zatex");
const inv = @import("invariants");

/// Fixed seed: the same corpus every run, on every machine.
const seed: u64 = 0x23F422;

fn stubProvider() zatex.MetricsProvider {
    const S = struct {
        fn glyphId(_: *const anyopaque, _: u16, cp: u21) u16 {
            return @intCast(cp & 0xFFFF);
        }
        fn advance(_: *const anyopaque, _: u16, _: u16) i32 {
            return 500;
        }
        fn ruleThickness(_: *const anyopaque, _: u16, _: zatex.RuleKind) i32 {
            return 40;
        }
    };
    return .{
        .ctx = &.{},
        .glyphId = S.glyphId,
        .advance = S.advance,
        .ruleThickness = S.ruleThickness,
    };
}

const Gen = struct {
    rnd: std.Random,
    buf: *[512]u8 = undefined,
    pos: usize = 0,
    /// Set after a word-command atom: the next letter-starting atom
    /// needs a separating space, else the lexer fuses them
    /// (`\alpha` + `x` = undefined `\alphax`).
    gap: bool = false,

    fn put(self: *Gen, s: []const u8) !void {
        if (self.gap and s.len > 0 and isAlpha(s[0])) {
            if (self.pos + 1 > self.buf.len) return error.NoSpace;
            self.buf[self.pos] = ' ';
            self.pos += 1;
        }
        self.gap = false;
        if (self.pos + s.len > self.buf.len) return error.NoSpace;
        @memcpy(self.buf[self.pos..][0..s.len], s);
        self.pos += s.len;
        if (isWordCommand(s)) self.gap = true;
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }

    fn isWordCommand(s: []const u8) bool {
        // Backslash + letters (greedy lexer): the atoms below that
        // need a trailing gap before a letter.
        const words = [_][]const u8{ "\\alpha", "\\infty", "\\leq", "\\sum", "\\int", "\\quad" };
        for (words) |w| if (std.mem.eql(u8, s, w)) return true;
        return false;
    }

    fn atom(self: *Gen) []const u8 {
        const atoms = [_][]const u8{
            "x", "y", "2", "\\alpha", "\\infty",
            "+",  "-",  "=",  "\\leq", "(",
            ")", ",",  "\\sum", "\\int", "\\,",
        };
        return atoms[self.rnd.uintLessThan(usize, atoms.len)];
    }

    /// Render one formula of nesting `depth` into `buf`; null when the
    /// bound bites (counted as a skip, never a failure).
    fn gen(self: *Gen, depth: u8, buf: *[512]u8) ?[]const u8 {
        self.buf = buf;
        self.pos = 0;
        self.emit(depth) catch return null;
        return buf[0..self.pos];
    }

    fn emit(self: *Gen, depth: u8) !void {
        if (depth == 0 or self.rnd.uintLessThan(u8, 100) < 35) {
            try self.put(self.atom());
            return;
        }
        switch (self.rnd.uintLessThan(u8, 13)) {
            0 => {
                try self.put("\\sqrt{");
                try self.emit(depth - 1);
                try self.put("}");
            },
            1 => {
                try self.put("\\frac{");
                try self.emit(depth - 1);
                try self.put("}{y}");
            },
            2 => {
                try self.put("\\frac{y}{");
                try self.emit(depth - 1);
                try self.put("}");
            },
            3 => {
                try self.put("{");
                try self.emit(depth - 1);
                try self.put("}^{2}");
            },
            4 => {
                try self.put("{");
                try self.emit(depth - 1);
                try self.put("}_{i}");
            },
            5 => {
                try self.put("\\left(");
                try self.emit(depth - 1);
                try self.put("\\right)");
            },
            6 => {
                try self.put("\\begin{matrix}");
                try self.emit(depth - 1);
                try self.put("&");
                try self.emit(depth - 1);
                try self.put("\\\\");
                try self.emit(depth - 1);
                try self.put("&");
                try self.emit(depth - 1);
                try self.put("\\end{matrix}");
            },
            7 => {
                try self.put("{\\displaystyle ");
                try self.emit(depth - 1);
                try self.put("}");
            },
            8 => {
                try self.put("\\sum_{");
                try self.emit(depth - 1);
                try self.put("}^{n}");
            },
            10 => {
                try self.put("\\overline{");
                try self.emit(depth - 1);
                try self.put("}");
            },
            11 => {
                try self.put("\\underline{");
                try self.emit(depth - 1);
                try self.put("}");
            },
            12 => {
                try self.put("\\overbrace{");
                try self.emit(depth - 1);
                try self.put("}^{n}");
            },
            else => {
                try self.put("{");
                try self.emit(depth - 1);
                try self.put("}");
            },
        }
    }

    /// Script-free flat h-list material (no nesting, one baseline).
    fn flat(self: *Gen, buf: *[256]u8) ?[]const u8 {
        const atoms = [_][]const u8{ "x", "y", "2", "\\alpha", "+", "=", "(", ")", ",", "{x}", "\\,", "\\quad" };
        var pos: usize = 0;
        var gap = false;
        const n = 1 + self.rnd.uintLessThan(usize, 10);
        var k: usize = 0;
        while (k < n) : (k += 1) {
            const a = atoms[self.rnd.uintLessThan(usize, atoms.len)];
            if (gap and a.len > 0 and isAlpha(a[0])) {
                if (pos + 1 > buf.len) return null;
                buf[pos] = ' ';
                pos += 1;
            }
            gap = isWordCommand(a);
            if (pos + a.len > buf.len) return null;
            @memcpy(buf[pos..][0..a.len], a);
            pos += a.len;
        }
        return buf[0..pos];
    }
};

fn layoutOnce(src: []const u8, display: bool, runs: []zatex.ir.Run, rules: []zatex.ir.Rule, glyphs: []u16) zatex.LayoutError!zatex.ir.Layout {
    var diag = zatex.Diag.empty();
    return zatex.layoutDiag(src, .{ .display_mode = display }, stubProvider(), runs, rules, glyphs, &diag);
}

/// Invariant failures print the reproducer plus the IR text (never
/// pixels), then fail.
fn failWithSrc(src: []const u8, l: zatex.ir.Layout, e: anyerror) anyerror {
    var tbuf: [2048]u8 = undefined;
    std.debug.print("\ninvariant failed on: {s}\n  ir: {s}\n", .{ src, inv.layoutText(l, &tbuf) });
    return e;
}

test "grammar fuzz: totality and invariants over nested constructs" {
    var prng = std.Random.DefaultPrng.init(seed);
    var g = Gen{ .rnd = prng.random() };
    var n_ok: usize = 0;
    var n_cap: usize = 0;
    var n_skip: usize = 0;
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        var buf: [512]u8 = undefined;
        const src = g.gen(3, &buf) orelse {
            n_skip += 1;
            continue;
        };
        // Inline and display: limit placement and sizing both run.
        for ([_]bool{ false, true }) |display| {
            var ra: [128]zatex.ir.Run = undefined;
            var la: [32]zatex.ir.Rule = undefined;
            var ga: [2048]u16 = undefined;
            var rb: [128]zatex.ir.Run = undefined;
            var lb: [32]zatex.ir.Rule = undefined;
            var gb: [2048]u16 = undefined;
            const r1 = layoutOnce(src, display, &ra, &la, &ga);
            const r2 = layoutOnce(src, display, &rb, &lb, &gb);
            const opts: zatex.LayoutOptions = .{ .display_mode = display };
            if (r1) |l1| {
                // Totality: the second run agrees.
                const l2 = try r2;
                inv.expectSameLayout(l1, l2) catch |e| {
                    return failWithSrc(src, l1, e);
                };
                inv.expectNonNegative(l1) catch |e| {
                    return failWithSrc(src, l1, e);
                };
                inv.expectContained(l1) catch |e| {
                    return failWithSrc(src, l1, e);
                };
                // The MathML emitter is total on the same input too.
                var ma: [4096]u8 = undefined;
                var mb: [4096]u8 = undefined;
                const m1 = try zatex.mathml(src, opts, &ma);
                const m2 = try zatex.mathml(src, opts, &mb);
                try std.testing.expectEqualStrings(m1, m2);
                n_ok += 1;
            } else |e1| {
                // Honest caps are expected outcomes; anything else (in
                // particular Invalid on grammar-valid input) fails loudly
                // with the reproducer attached.
                if (e1 == error.Invalid) {
                    std.debug.print("\nfuzz Invalid on grammar input: {s}\n", .{src});
                    return error.TestUnexpectedResult;
                }
                try std.testing.expectError(e1, r2);
                n_cap += 1;
            }
        }
    }
    std.debug.print("\nfuzz: {d} ok, {d} cap-limited, {d} over-budget skips\n", .{ n_ok, n_cap, n_skip });
    try std.testing.expect(n_ok > 2400);
}

test "grammar fuzz: sqrt nesting grows monotonically" {
    // Each level owns its source and output buffers; wrapping never
    // shrinks the ink box.
    const fixed = [_][]const u8{ "x", "x+y", "\\frac{a}{b}" };
    for (fixed) |b0| {
        var nest: Nest = .{};
        nest.push(b0) catch continue;
        var d: u8 = 0;
        while (d < 3) : (d += 1) {
            nest.wrapSqrt() catch continue;
        }
        try nest.expectGrown();
    }
    var prng = std.Random.DefaultPrng.init(seed ^ 0x9e37);
    var g = Gen{ .rnd = prng.random() };
    var k: usize = 0;
    while (k < 20) : (k += 1) {
        var bbuf: [512]u8 = undefined;
        const base = g.gen(1, &bbuf) orelse continue;
        // Copy out of the scratch buffer: levels below borrow it.
        var nest: Nest = .{};
        nest.push(base) catch continue;
        nest.wrapSqrt() catch continue;
        nest.wrapSqrt() catch continue;
        try nest.expectGrown();
    }
}

const Nest = struct {
    srcs: [4][512]u8 = undefined,
    lens: [4]usize = .{ 0, 0, 0, 0 },
    top: usize = 0,
    runs: [4][128]zatex.ir.Run = undefined,
    rules: [4][32]zatex.ir.Rule = undefined,
    glyphs: [4][2048]u16 = undefined,

    fn push(self: *Nest, src: []const u8) !void {
        if (src.len > self.srcs[0].len) return error.NoSpace;
        @memcpy(self.srcs[0][0..src.len], src);
        self.lens[0] = src.len;
        self.top = 1;
    }

    fn wrapSqrt(self: *Nest) !void {
        if (self.top >= self.srcs.len) return error.NoSpace;
        const prev = self.srcs[self.top - 1][0..self.lens[self.top - 1]];
        const dst = &self.srcs[self.top];
        var pos: usize = 0;
        for ([_][]const u8{ "\\sqrt{", prev, "}" }) |s| {
            if (pos + s.len > dst.len) return error.NoSpace;
            @memcpy(dst[pos..][0..s.len], s);
            pos += s.len;
        }
        self.lens[self.top] = pos;
        self.top += 1;
    }

    fn expectGrown(self: *Nest) !void {
        var lays: [4]zatex.ir.Layout = undefined;
        var k: usize = 0;
        while (k < self.top) : (k += 1) {
            lays[k] = try layoutOnce(
                self.srcs[k][0..self.lens[k]],
                false,
                &self.runs[k],
                &self.rules[k],
                &self.glyphs[k],
            );
            try inv.expectNonNegative(lays[k]);
            try inv.expectContained(lays[k]);
            if (k > 0) try inv.expectGrowsOrEqual(lays[k - 1], lays[k]);
        }
    }
};

test "grammar fuzz: flat hlists keep one baseline" {
    var prng = std.Random.DefaultPrng.init(seed ^ 0x51f7);
    var g = Gen{ .rnd = prng.random() };
    var checked: usize = 0;
    var i: usize = 0;
    while (i < 300) : (i += 1) {
        var buf: [256]u8 = undefined;
        const src = g.flat(&buf) orelse continue;
        var runs: [64]zatex.ir.Run = undefined;
        var rules: [8]zatex.ir.Rule = undefined;
        var glyphs: [512]u16 = undefined;
        const l = try layoutOnce(src, false, &runs, &rules, &glyphs);
        try inv.expectNonNegative(l);
        if (l.runs.len > 0) {
            const y0 = l.runs[0].baseline_y;
            for (l.runs) |r| try std.testing.expectEqual(y0, r.baseline_y);
            checked += 1;
        }
    }
    try std.testing.expect(checked > 250);
}

test "caps honesty: TooLong, TooDeep, ExpansionLimit, NoSpace are exact" {
    // contract caps, referenced by name (never magic numbers here).
    var big: [zatex.max_input_len + 1]u8 = .{'x'} ** (zatex.max_input_len + 1);
    var runs: [8]zatex.ir.Run = undefined;
    var rules: [4]zatex.ir.Rule = undefined;
    var glyphs: [32]u16 = undefined;
    try std.testing.expectError(error.TooLong, layoutOnce(&big, false, &runs, &rules, &glyphs));
    var deep: [zatex.max_nesting_depth + 8]u8 = undefined;
    @memset(&deep, '{');
    try std.testing.expectError(error.TooDeep, layoutOnce(&deep, false, &runs, &rules, &glyphs));
    try std.testing.expectError(error.ExpansionLimit, layoutOnce("\\def\\a{\\a}\\a", false, &runs, &rules, &glyphs));
    // max_expand parity: the counter matches KaTeX's default budget.
    try std.testing.expectEqual(@as(u32, 1000), zatex.max_expand);
    var runs1: [1]zatex.ir.Run = undefined;
    var rules8: [8]zatex.ir.Rule = undefined;
    var glyphs64: [64]u16 = undefined;
    try std.testing.expectError(
        error.NoSpace,
        layoutOnce("\\frac{a}{b}+x", false, &runs1, &rules8, &glyphs64),
    );
}
