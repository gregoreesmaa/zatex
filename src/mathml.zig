//! MaTeX MathML emitter: AST → MathML Core (thin structural walker).
//!
//! No layout math here, ever (AGENTS.md §2): this maps parse nodes to
//! MathML elements without measuring anything. Positions, sizes, and
//! spacing live only in `layout.zig`.
const std = @import("std");
const contract = @import("contract.zig");
const parse = @import("parse.zig");

const Error = contract.LayoutError;
const Idx = parse.Idx;
const NONE = parse.NONE;

/// Serialize one formula to MathML Core into caller-owned `out`.
pub fn render(source: []const u8, options: contract.LayoutOptions, out: []u8) Error![]const u8 {
    if (source.len > contract.max_input_len) return error.TooLong;
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, options.display_mode) catch |e| return e;
    var w = Writer{ .pc = &pc, .buf = out };
    w.str("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"");
    if (options.display_mode) w.str(" display=\"block\"");
    w.str(">");
    w.node(root, .{ .fam = null, .script = false }) catch |e| return e;
    w.str("</math>");
    if (w.overflow) return error.NoSpace;
    return out[0..w.pos];
}

const Face = struct {
    fam: ?parse.FontFam,
    script: bool,
};

const Writer = struct {
    pc: *const parse.ParseCtx,
    buf: []u8,
    pos: usize = 0,
    overflow: bool = false,

    fn str(self: *Writer, s: []const u8) void {
        if (self.overflow) return;
        if (self.pos + s.len > self.buf.len) {
            self.overflow = true;
            return;
        }
        @memcpy(self.buf[self.pos .. self.pos + s.len], s);
        self.pos += s.len;
    }

    fn byte(self: *Writer, c: u8) void {
        if (self.overflow) return;
        if (self.pos + 1 > self.buf.len) {
            self.overflow = true;
            return;
        }
        self.buf[self.pos] = c;
        self.pos += 1;
    }

    fn cp(self: *Writer, c: u21) void {
        var tmp: [4]u8 = undefined;
        const n = encode(c, &tmp);
        self.str(tmp[0..n]);
    }

    /// `<0.333em`-style decimal for thousandths of an em.
    fn em(self: *Writer, thousandths: i32) void {
        var neg = false;
        var v = thousandths;
        if (v < 0) {
            neg = true;
            v = -v;
        }
        if (neg) self.byte('-');
        self.uint(@intCast(@divTrunc(v, 1000)));
        const frac = @mod(v, 1000);
        if (frac != 0) {
            self.byte('.');
            var f: [3]u8 = .{ '0', '0', '0' };
            var t = frac;
            f[2] = '0' + @as(u8, @intCast(@mod(t, 10)));
            t = @divTrunc(t, 10);
            f[1] = '0' + @as(u8, @intCast(@mod(t, 10)));
            t = @divTrunc(t, 10);
            f[0] = '0' + @as(u8, @intCast(@mod(t, 10)));
            var n: usize = 3;
            while (n > 0 and f[n - 1] == '0') n -= 1;
            self.str(f[0..n]);
        }
        self.str("em");
    }

    fn uint(self: *Writer, v: i32) void {
        var tmp: [12]u8 = undefined;
        var n: usize = 0;
        var x = v;
        if (x == 0) {
            self.byte('0');
            return;
        }
        while (x > 0) : (n += 1) {
            tmp[n] = '0' + @as(u8, @intCast(@mod(x, 10)));
            x = @divTrunc(x, 10);
        }
        while (n > 0) : (n -= 1) self.byte(tmp[n - 1]);
    }

    fn escCp(self: *Writer, c: u21) void {
        switch (c) {
            '&' => self.str("&amp;"),
            '<' => self.str("&lt;"),
            '>' => self.str("&gt;"),
            else => self.cp(c),
        }
    }

    fn node(self: *Writer, id: Idx, face: Face) Error!void {
        if (self.overflow) return error.NoSpace;
        const n = parse.nodeAt(self.pc, id);
        switch (n) {
            .atom => |a| self.atom(a.class, self.effFam(face, a.font), a.cp),
            .op => |o| {
                if (o.func) {
                    self.str("<mi>");
                    self.str(o.text);
                    self.str("</mi>");
                } else {
                    self.str("<mo>");
                    self.cp(o.cp);
                    self.str("</mo>");
                }
            },
            .opname => |o| {
                self.str("<mi>");
                const toks = parse.toksOf(self.pc, o.toks);
                for (toks) |tk| {
                    switch (tk.kind) {
                        .char => self.escCp(tk.cp),
                        .ctrl => {
                            if (tk.name.len == 1) self.escCp(tk.name[0]);
                        },
                        else => {},
                    }
                }
                self.str("</mi>");
            },
            .group => |g| {
                self.str("<mrow>");
                for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face);
                self.str("</mrow>");
            },
            .frac => |f| {
                if (f.kind.parens) self.str("<mrow><mo>(</mo>");
                if (!f.kind.bar) self.str("<mfrac linethickness=\"0\">") else self.str("<mfrac>");
                try self.node(f.num, face);
                try self.node(f.den, face);
                self.str("</mfrac>");
                if (f.kind.parens) self.str("<mo>)</mo></mrow>");
            },
            .sqrt => |s| {
                if (s.index == NONE) {
                    self.str("<msqrt>");
                    try self.node(s.radicand, face);
                    self.str("</msqrt>");
                } else {
                    self.str("<mroot>");
                    try self.node(s.radicand, face);
                    try self.node(s.index, face);
                    self.str("</mroot>");
                }
            },
            .supsub => |s| {
                if (s.sup != NONE and s.sub != NONE) {
                    self.str("<msubsup>");
                    try self.node(s.base, face);
                    try self.node(s.sub, face);
                    try self.node(s.sup, face);
                    self.str("</msubsup>");
                } else if (s.sup != NONE) {
                    self.str("<msup>");
                    try self.node(s.base, face);
                    try self.node(s.sup, face);
                    self.str("</msup>");
                } else {
                    self.str("<msub>");
                    try self.node(s.base, face);
                    try self.node(s.sub, face);
                    self.str("</msub>");
                }
            },
            .delim => |d| {
                self.str("<mrow>");
                if (d.left != 0) {
                    self.str("<mo fence=\"true\">");
                    self.cp(d.left);
                    self.str("</mo>");
                }
                try self.node(d.body, face);
                if (d.right != 0) {
                    self.str("<mo fence=\"true\">");
                    self.cp(d.right);
                    self.str("</mo>");
                }
                self.str("</mrow>");
            },
            .middle => |m| {
                self.str("<mo fence=\"true\">");
                self.cp(m.cp);
                self.str("</mo>");
            },
            .big => |b| {
                self.str("<mo>");
                self.cp(b.cp);
                self.str("</mo>");
            },
            .accent => |a| {
                self.str("<mover>");
                try self.node(a.nucleus, face);
                self.str("<mo>");
                self.cp(a.cp);
                self.str("</mo></mover>");
            },
            .over => |o| try self.over(o, face),
            .style => |s| {
                // `display`/`inline` only; cramped has no MathML form.
                const disp = s.style == .D or s.style == .Dc;
                if (disp) self.str("<mstyle displaystyle=\"true\">") else self.str("<mstyle displaystyle=\"false\">");
                try self.node(s.body, face);
                self.str("</mstyle>");
            },
            .font => |f| {
                self.str("<mstyle mathvariant=\"");
                self.str(variantFor(f.fam));
                self.str("\">");
                try self.node(f.body, .{ .fam = f.fam, .script = face.script });
                self.str("</mstyle>");
            },
            .text => |t| {
                self.str("<mtext>");
                const toks = parse.toksOf(self.pc, t.toks);
                var i: usize = 0;
                while (i < toks.len) : (i += 1) {
                    const tk = toks[i];
                    switch (tk.kind) {
                        .char => {
                            if (tk.cp == ' ') self.byte(' ') else self.escCp(tk.cp);
                        },
                        .lbrace => self.byte('{'),
                        .rbrace => self.byte('}'),
                        .newline => self.byte(' '),
                        .ctrl => {
                            const c = tk.name[0];
                            switch (c) {
                                '{', '}', '%', '&', '#', '_', '$', ',', ':', ';', '!', '|', '/' => self.escCp(c),
                                ' ', '~' => self.byte(' '),
                                else => {
                                    const acc = parse.textAccentCp(c) orelse return error.Invalid;
                                    if (i + 1 >= toks.len) return error.Invalid;
                                    const nx = toks[i + 1];
                                    if (nx.kind != .char) return error.Invalid;
                                    i += 1;
                                    self.escCp(parse.precompose(acc, nx.cp) orelse return error.Invalid);
                                },
                            }
                        },
                        else => return error.Invalid,
                    }
                }
                self.str("</mtext>");
            },
            .env => |e| try self.env(e, face),
            .substack => |r| {
                self.str("<mtable>");
                for (parse.rowsOf(self.pc, r.start, r.len)) |row| {
                    self.str("<mtr><mtd>");
                    const kids = parse.kidsOf(self.pc, .{ .start = row.start, .len = row.len });
                    for (kids) |k| try self.node(k, face);
                    self.str("</mtd></mtr>");
                }
                self.str("</mtable>");
            },
            .mathchoice => |c| try self.node(c[0], face),
            .space => |u| {
                self.str("<mspace width=\"");
                self.em(u);
                self.str("\"/>");
            },
            .vspace => |u| {
                self.str("<mspace height=\"");
                self.em(u);
                self.str("\"/>");
            },
            .newline => self.str("<mspace linebreak=\"newline\"/>"),
            .hline => {},
            .color => |b| try self.node(b, face),
            .href => |h| {
                self.str("<mrow href=\"");
                const toks = parse.toksOf(self.pc, h.target);
                for (toks) |tk| {
                    if (tk.kind == .char and tk.cp < 0x80) {
                        const c: u8 = @intCast(tk.cp);
                        if (c == '"') self.str("&quot;") else if (c == '&') self.str("&amp;") else self.byte(c);
                    }
                }
                self.str("\">");
                try self.node(h.body, face);
                self.str("</mrow>");
            },
            .htmlwrap => |b| try self.node(b, face),
            .phantom => |p| {
                self.str("<mphantom>");
                try self.node(p.body, face);
                self.str("</mphantom>");
            },
            .boxed => |b| {
                self.str("<menclose notation=\"box\">");
                try self.node(b, face);
                self.str("</menclose>");
            },
            .cancel => |b| {
                self.str("<menclose notation=\"updiagonalstrike\">");
                try self.node(b, face);
                self.str("</menclose>");
            },
            .lap => |l| {
                self.str("<mpadded width=\"0\">");
                try self.node(l.body, face);
                self.str("</mpadded>");
            },
            .smash => |s| try self.node(s.body, face),
            .raisebox => |r| {
                self.str("<mpadded voffset=\"");
                self.em(r.dh);
                self.str("\">");
                try self.node(r.body, face);
                self.str("</mpadded>");
            },
            .rule => |r| {
                self.str("<mspace width=\"");
                self.em(r.w);
                self.str("\" height=\"");
                self.em(r.h);
                self.str("\" depth=\"");
                self.em(r.dep);
                self.str("\"/>");
            },
        }
        if (self.overflow) return error.NoSpace;
    }

    fn effFam(self: *Writer, face: Face, f: parse.FontFam) parse.FontFam {
        _ = self;
        return face.fam orelse f;
    }

    fn atom(self: *Writer, class: @import("symbols.zig").AtomClass, fam: parse.FontFam, c: u21) void {
        _ = fam;
        switch (class) {
            .Bin, .Rel, .Open, .Close, .Punct, .Op => {
                self.str("<mo>");
                self.escCp(c);
                self.str("</mo>");
            },
            .Ord, .Inner => {
                if (isDigit(c)) {
                    self.str("<mn>");
                    self.escCp(c);
                    self.str("</mn>");
                } else if (isLetterLike(c)) {
                    self.str("<mi>");
                    self.escCp(c);
                    self.str("</mi>");
                } else {
                    self.str("<mo>");
                    self.escCp(c);
                    self.str("</mo>");
                }
            },
        }
    }

    fn over(self: *Writer, o: anytype, face: Face) Error!void {
        switch (o.kind) {
            .overline => {
                self.str("<mover>");
                try self.node(o.nucleus, face);
                self.str("<mo>&#xAF;</mo></mover>");
            },
            .underline => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>_</mo></munder>");
            },
            .overbrace => {
                self.str("<mover>");
                try self.node(o.nucleus, face);
                self.str("<mo>&#x23DE;</mo></mover>");
            },
            .underbrace => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>&#x23DF;</mo></munder>");
            },
            .overleft => try self.arrowOver(o.nucleus, 0x2190, face),
            .overright => try self.arrowOver(o.nucleus, 0x2192, face),
            .overboth => try self.arrowOver(o.nucleus, 0x2194, face),
            .underleft => try self.arrowUnder(o.nucleus, 0x2190, face),
            .underright => try self.arrowUnder(o.nucleus, 0x2192, face),
            .underboth => try self.arrowUnder(o.nucleus, 0x2194, face),
            .overset => {
                self.str("<mover>");
                try self.node(o.nucleus, face);
                try self.node(o.extra, face);
                self.str("</mover>");
            },
            .underset => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                try self.node(o.extra, face);
                self.str("</munder>");
            },
            .xleft => try self.xarrow(0x2190, o, face),
            .xright => try self.xarrow(0x2192, o, face),
            .xboth => try self.xarrow(0x2194, o, face),
            .xhookleft => try self.xarrow(0x21A9, o, face),
            .xhookright => try self.xarrow(0x21AA, o, face),
            .xmapsto => try self.xarrow(0x21A6, o, face),
            .xtwoheadleft => try self.xarrow(0x219E, o, face),
            .xtwoheadright => try self.xarrow(0x21A0, o, face),
        }
    }

    fn arrowOver(self: *Writer, nuc: Idx, gc: u21, face: Face) Error!void {
        self.str("<mover>");
        try self.node(nuc, face);
        self.str("<mo>");
        self.cp(gc);
        self.str("</mo></mover>");
    }

    fn arrowUnder(self: *Writer, nuc: Idx, gc: u21, face: Face) Error!void {
        self.str("<munder>");
        try self.node(nuc, face);
        self.str("<mo>");
        self.cp(gc);
        self.str("</mo></munder>");
    }

    fn xarrow(self: *Writer, gc: u21, o: anytype, face: Face) Error!void {
        // Above/below labels around the arrow nucleus.
        if (o.under != NONE) self.str("<munder>");
        self.str("<mover><mo>");
        self.cp(gc);
        self.str("</mo>");
        try self.node(o.extra, face);
        self.str("</mover>");
        if (o.under != NONE) {
            try self.node(o.under, face);
            self.str("</munder>");
        }
    }

    fn env(self: *Writer, e: anytype, face: Face) Error!void {
        self.str("<mtable>");
        const rows = parse.rowsOf(self.pc, e.rows_start, e.rows_len);
        for (rows) |row| {
            self.str("<mtr>");
            const kids = parse.kidsOf(self.pc, .{ .start = row.start, .len = row.len });
            for (kids) |k| {
                if (isHlineNode(self.pc, k)) continue;
                self.str("<mtd>");
                try self.node(k, face);
                self.str("</mtd>");
            }
            self.str("</mtr>");
        }
        self.str("</mtable>");
    }
};

fn isHlineNode(pc: *const parse.ParseCtx, id: Idx) bool {
    switch (parse.nodeAt(pc, id)) {
        .hline => return true,
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            return kids.len == 1 and isHlineNode(pc, kids[0]);
        },
        else => return false,
    }
}

fn variantFor(fam: parse.FontFam) []const u8 {
    return switch (fam) {
        .rm => "normal",
        .mathit => "italic",
        .bold => "bold",
        .sans => "sans-serif",
        .tt => "monospace",
        .frak => "fraktur",
        .script => "script",
        .bb => "double-struck",
        .cal => "script",
    };
}

fn isDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}

fn isLetterLike(c: u21) bool {
    if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')) return true;
    if (c >= 0x391 and c <= 0x3A9) return true; // Greek uppercase
    if (c >= 0x3B1 and c <= 0x3C9) return true; // Greek lowercase
    if (c == 0x3D5 or c == 0x3D1 or c == 0x3D6 or c == 0x3F1 or c == 0x3F5 or c == 0x3DC) return true;
    if (c == 0x131 or c == 0x237 or c == 0x2113 or c == 0x2118) return true;
    return false;
}

fn encode(c: u21, out: *[4]u8) usize {
    if (c < 0x80) {
        out[0] = @intCast(c);
        return 1;
    } else if (c < 0x800) {
        out[0] = @intCast(0xC0 | (c >> 6));
        out[1] = @intCast(0x80 | (c & 0x3F));
        return 2;
    } else if (c < 0x10000) {
        out[0] = @intCast(0xE0 | (c >> 12));
        out[1] = @intCast(0x80 | ((c >> 6) & 0x3F));
        out[2] = @intCast(0x80 | (c & 0x3F));
        return 3;
    } else {
        out[0] = @intCast(0xF0 | (c >> 18));
        out[1] = @intCast(0x80 | ((c >> 12) & 0x3F));
        out[2] = @intCast(0x80 | ((c >> 6) & 0x3F));
        out[3] = @intCast(0x80 | (c & 0x3F));
        return 4;
    }
}

test "frac renders mfrac" {
    var pc = parse.ParseCtx.init("\\frac12");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "<mfrac>") != null);
}

test "sum renders msubsup structurally" {
    var pc = parse.ParseCtx.init("\\sum_{i=1}^{n}");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "<msubsup>") != null);
}
