//! ZaTeX MathML emitter: AST → MathML Core (thin structural walker).
//!
//! No layout math here, ever (AGENTS.md §2): this maps parse nodes to
//! MathML elements without measuring anything. Positions, sizes, and
//! spacing live only in `layout.zig`.
const std = @import("std");
const contract = @import("contract.zig");
const parse = @import("parse.zig");
const symbols = @import("symbols.zig");

const Error = contract.LayoutError;
const Idx = parse.Idx;
const NONE = parse.NONE;

/// Serialize one formula to MathML Core into caller-owned `out`.
pub fn render(source: []const u8, options: contract.LayoutOptions, out: []u8) Error![]const u8 {
    if (source.len > contract.max_input_len) return error.TooLong;
    var pc = parse.ParseCtx.init(source);
    const root = parse.parse(&pc, options.display_mode) catch |e| return e;
    var w = Writer{
        .pc = &pc,
        .buf = out,
        .style = if (options.display_mode) .D else .T,
    };
    w.str("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"");
    if (options.display_mode) w.str(" display=\"block\"");
    w.str(">");
    // The root row wraps a lone child unless it already presents
    // as a row (KaTeX `buildMathML`: single rowlike passes through).
    const wrap = switch (parse.nodeAt(&pc, root)) {
        .group => |g| g.len == 1 and !rendersRow(&pc, parse.kidsOf(&pc, g)[0]),
        else => true,
    };
    if (wrap) w.str("<mrow>");
    w.node(root, .{ .fam = null, .script = false }) catch |e| return e;
    if (wrap) w.str("</mrow>");
    w.str("</math>");
    if (w.overflow) return error.NoSpace;
    const n = mergeNot(out[0..w.pos]);
    return out[0..mergeRuns(out[0..n])];
}

/// Fold adjacent runs inside a row: `<mn>A</mn><mn>B</mn>` → `<mn>AB</mn>`,
/// and the same for `mtext` pairs with identical open tags (KaTeX
/// `buildExpression` parity). Merging is row-local: fraction children,
/// script bases, and other structural positions never merge, so an
/// element stack gates every fold. In-place; the result never grows.
fn mergeRuns(buf: []u8) usize {
    var st = MergeState{};
    var r: usize = 0;
    var n: usize = 0;
    while (r < buf.len) {
        var handled = false;
        if (buf[r] == '<') {
            const tag = scanTag(buf, r);
            if (tag.len == 0) {
                buf[n] = buf[r];
                n += 1;
                r += 1;
                continue;
            }
            if (!tag.closing and !tag.self_close) {
                if (st.inRow()) {
                    if (tag.nameEqual("mn")) {
                        if (tryRun(buf, &n, &r, "mn")) {
                            // Balanced span: no stack change.
                            handled = true;
                            continue;
                        }
                    } else if (tag.nameEqual("mtext")) {
                        if (tryRun(buf, &n, &r, "mtext")) {
                            handled = true;
                            continue;
                        }
                    }
                }
                st.push(tag.nameEqual("mrow"));
            } else if (tag.closing) {
                st.pop();
            }
            // Copy the whole tag.
            const tlen = tag.len;
            std.mem.copyForwards(u8, buf[n .. n + tlen], buf[r .. r + tlen]);
            n += tlen;
            r += tlen;
            handled = true;
        }
        if (!handled) {
            buf[n] = buf[r];
            n += 1;
            r += 1;
        }
    }
    return n;
}

/// Minimal open/close tag scan for the merge passes.
const Tag = struct {
    len: usize,
    name: []const u8,
    closing: bool,
    self_close: bool,

    fn nameEqual(self: Tag, comptime nm: []const u8) bool {
        return std.mem.eql(u8, self.name, nm);
    }
};

fn scanTag(buf: []const u8, at: usize) Tag {
    var t = Tag{ .len = 0, .name = "", .closing = false, .self_close = false };
    if (at >= buf.len or buf[at] != '<') return t;
    var i = at + 1;
    if (i < buf.len and buf[i] == '/') {
        t.closing = true;
        i += 1;
    }
    const ns = i;
    while (i < buf.len and buf[i] != ' ' and buf[i] != '\t' and
        buf[i] != '\n' and buf[i] != '\r' and buf[i] != '/' and buf[i] != '>')
    {
        i += 1;
    }
    t.name = buf[ns..i];
    if (t.name.len == 0) return Tag{ .len = 0, .name = "", .closing = false, .self_close = false };
    const gt = std.mem.indexOfScalarPos(u8, buf, i, '>') orelse return Tag{
        .len = 0,
        .name = "",
        .closing = false,
        .self_close = false,
    };
    if (!t.closing and gt > at + 1 and buf[gt - 1] == '/') t.self_close = true;
    t.len = gt + 1 - at;
    return t;
}

/// True when `buf[at..]` opens `nm` (`>` or space follows).
fn matchOpen(buf: []const u8, at: usize, comptime nm: []const u8) bool {
    const t = scanTag(buf, at);
    return t.len > 0 and !t.closing and !t.self_close and t.nameEqual(nm);
}

/// Fold the run at `r` (`<nm>…</nm>` followers with equal open tags),
/// advancing `n`/`r` past it. Returns false when nothing merges.
fn tryRun(buf: []u8, n: *usize, r: *usize, comptime nm: []const u8) bool {
    const first = textSpan(buf, r.*, nm);
    if (first.close == 0) return false;
    var cur = first;
    var count: usize = 1;
    while (true) {
        const nx = cur.next;
        if (nx >= buf.len or !matchOpen(buf, nx, nm)) break;
        const f = textSpan(buf, nx, nm);
        if (f.close == 0 or !std.mem.eql(u8, f.attrs, first.attrs)) break;
        cur = f;
        count += 1;
    }
    if (count < 2) return false;
    var w = n.*;
    std.mem.copyForwards(u8, buf[w .. w + first.open_len], buf[first.open .. first.open + first.open_len]);
    w += first.open_len;
    var c2 = first;
    while (true) {
        std.mem.copyForwards(u8, buf[w .. w + c2.text_len], buf[c2.text .. c2.text + c2.text_len]);
        w += c2.text_len;
        if (c2.next == cur.next) break;
        c2 = textSpan(buf, c2.next, nm);
    }
    const close_tag = "</" ++ nm ++ ">";
    std.mem.copyForwards(u8, buf[w .. w + close_tag.len], close_tag);
    w += close_tag.len;
    n.* = w;
    r.* = cur.next;
    return true;
}

/// Element stack for the merge passes (bounded depth; overflow
/// disables merging rather than corrupting output).
const MergeState = struct {
    depth: usize = 0,
    over: usize = 0,
    row: [64]bool = [_]bool{false} ** 64,

    fn push(self: *MergeState, is_row: bool) void {
        if (self.depth < self.row.len) {
            self.row[self.depth] = is_row;
            self.depth += 1;
        } else {
            self.over += 1;
        }
    }
    fn pop(self: *MergeState) void {
        if (self.over > 0) {
            self.over -= 1;
        } else if (self.depth > 0) {
            self.depth -= 1;
        }
    }
    fn inRow(self: *const MergeState) bool {
        return self.over == 0 and self.depth > 0 and self.row[self.depth - 1];
    }
};

/// One `<nm attrs>text</nm>` element's spans (`close == 0` if malformed).
const TextSpan = struct {
    open: usize,
    open_len: usize,
    text: usize,
    text_len: usize,
    close: usize,
    next: usize,
    attrs: []const u8,
};

/// Parse `<nm attrs>text</nm>` at `at` (must match matchOpen).
fn textSpan(buf: []const u8, at: usize, comptime nm: []const u8) TextSpan {
    var s = TextSpan{
        .open = at,
        .open_len = 0,
        .text = 0,
        .text_len = 0,
        .close = 0,
        .next = at,
        .attrs = "",
    };
    const gt = std.mem.indexOfScalarPos(u8, buf, at, '>') orelse return s;
    s.open_len = gt + 1 - at;
    s.attrs = buf[at + 3 .. gt];
    s.text = gt + 1;
    const close_tag = "</" ++ nm ++ ">";
    const cl = std.mem.indexOfPos(u8, buf, s.text, close_tag) orelse return s;
    s.text_len = cl - s.text;
    s.close = cl;
    s.next = cl + close_tag.len;
    return s;
}

/// Whether a node is a function operator for supsub-base rowing.
fn baseIsFuncOp(pc: *const parse.ParseCtx, id: Idx) bool {
    return switch (parse.nodeAt(pc, id)) {
        .op => |o| o.func,
        .opname => true,
        else => false,
    };
}

/// Whether a node presents as a row at top level (`mrow`/`mtable`),
/// mirroring KaTeX's rowlike check for the root wrapper.
fn rendersRow(pc: *const parse.ParseCtx, id: Idx) bool {
    switch (parse.nodeAt(pc, id)) {
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            if (kids.len == 1) return rendersRow(pc, kids[0]);
            return true;
        },
        .env, .substack => return true,
        .delim, .href => return true,
        // `genfrac` rows its fence expression whenever delimiters
        // are present (KaTeX `makeRow` parity).
        .frac => |f| return f.kind.parens,
        else => return false,
    }
}

/// Fold `\not` overlays: a bare U+0338 element followed by an
/// `mo`/`mi`/`mn` element merges the slash after the next element's
/// first character (KaTeX `buildExpression` parity). In-place; the
/// result is always shorter.
fn mergeNot(buf: []u8) usize {
    // `\not` renders `<mo>` (Rel overlay); a literal U+0338 character
    // in input stays `<mi>` (Ord atom). Both fold the same way.
    const marks = [_][]const u8{ "<mo>\xcc\xb8</mo>", "<mi>\xcc\xb8</mi>" };
    var r: usize = 0;
    var n: usize = 0;
    while (r < buf.len) {
        var mark_len: usize = 0;
        for (marks) |m| {
            if (r + m.len <= buf.len and std.mem.eql(u8, buf[r .. r + m.len], m)) {
                mark_len = m.len;
                break;
            }
        }
        if (mark_len > 0) {
            const after = r + mark_len;
            // Next element must open as mo/mi/mn (never self-closed;
            // our mo/mi/mn opens carry no attributes, so `>` follows).
            if (after + 4 < buf.len and buf[after] == '<' and buf[after + 1] != '/') {
                const nm = buf[after + 1 .. after + 3];
                if (buf[after + 3] == '>' and
                    (std.mem.eql(u8, nm, "mo") or std.mem.eql(u8, nm, "mi") or
                        std.mem.eql(u8, nm, "mn")))
                {
                    const gt = std.mem.indexOfScalarPos(u8, buf, after, '>') orelse {
                        std.mem.copyForwards(u8, buf[n .. n + buf.len - r], buf[r..]);
                        return n + buf.len - r;
                    };
                    const tb = gt + 1;
                    // End of the first text scalar (or entity) inside.
                    var te = tb;
                    if (te < buf.len and buf[te] == '&') {
                        te = std.mem.indexOfScalarPos(u8, buf, te, ';') orelse buf.len;
                        te = @min(te + 1, buf.len);
                    } else if (te < buf.len) {
                        te += utf8Width(buf[te]);
                        te = @min(te, buf.len);
                    }
                    // Copy open tag + first scalar, splice the mark in.
                    std.mem.copyForwards(u8, buf[n .. n + (tb - after)], buf[after..tb]);
                    n += tb - after;
                    std.mem.copyForwards(u8, buf[n .. n + (te - tb)], buf[tb..te]);
                    n += te - tb;
                    buf[n] = 0xCC;
                    buf[n + 1] = 0xB8;
                    n += 2;
                    r = te;
                    continue;
                }
            }
        }
        buf[n] = buf[r];
        n += 1;
        r += 1;
    }
    return n;
}

fn utf8Width(lead: u8) usize {
    if (lead < 0x80) return 1;
    if (lead & 0xE0 == 0xC0) return 2;
    if (lead & 0xF0 == 0xE0) return 3;
    if (lead & 0xF8 == 0xF0) return 4;
    return 1;
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
    /// Ambient TeX style, threaded exactly like the layout core
    /// (scripts shrink, fractions split, environments reset). Drives
    /// limit placement; unit tests default to text style.
    style: parse.Style = .T,

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

    fn escAttr(self: *Writer, c: u21) void {
        if (c == '"') {
            self.str("&quot;");
        } else if (c < 0x80) {
            const b: u8 = @intCast(c);
            switch (b) {
                '&' => self.str("&amp;"),
                '<' => self.str("&lt;"),
                '>' => self.str("&gt;"),
                else => self.byte(b),
            }
        } else {
            self.cp(c);
        }
    }

    /// Text-token range to mtext content (shared by `\text` and boxes).
    // One text accent + base (shared by textBody and sout spans).
    fn textAccentTok(self: *Writer, toks: []const parse.Tok, i: *usize, c: u8) Error!void {
        // Braced single letters too.
        const acc = parse.textAccentCp(c) orelse return error.Invalid;
        if (i.* + 1 >= toks.len) return error.Invalid;
        var nx = toks[i.* + 1];
        if (nx.kind == .lbrace) {
            if (i.* + 3 >= toks.len) return error.Invalid;
            if (toks[i.* + 2].kind != .char or toks[i.* + 3].kind != .rbrace)
                return error.Invalid;
            nx = toks[i.* + 2];
            i.* += 2;
        }
        if (nx.kind != .char) return error.Invalid;
        i.* += 1;
        if (parse.precompose(acc, nx.cp)) |pcp| {
            self.escCp(pcp);
        } else {
            // No precomposed form: base + combining mark
            // (KaTeX emits mover here; inside mtext
            // the combining form renders the same).
            if (parse.mathTextAccentCp(c) == null) return error.Invalid;
            self.escCp(nx.cp);
            self.escCp(acc);
        }
    }

    // Span of an argument-taking text command at toks[i] (the
    // command): inner [s, e) plus the first index after the arg.
    fn textArgSpan(toks: []const parse.Tok, i: usize) Error!struct { s: usize, e: usize, after: usize } {
        var j = i + 1;
        if (j < toks.len and toks[j].kind == .lbrace) {
            var depth: usize = 1;
            j += 1;
            const s = j;
            while (j < toks.len and depth > 0) : (j += 1) {
                if (toks[j].kind == .lbrace) depth += 1;
                if (toks[j].kind == .rbrace) depth -= 1;
            }
            if (depth > 0) return error.Invalid;
            return .{ .s = s, .e = j - 1, .after = j };
        }
        // Skip interword space (TeX control-word space skipping).
        while (j < toks.len and (toks[j].kind == .newline or
            (toks[j].kind == .char and toks[j].cp == ' '))) j += 1;
        if (j >= toks.len) return error.Invalid;
        return .{ .s = j, .e = j + 1, .after = j + 1 };
    }

    // Argument-taking text commands (textcircled, sout): KaTeX
    // parity (pinned 0.18.7, issue #51 review) builds these
    // STRUCTURALLY — menclose strike / mover circle — never with
    // combining characters. The body re-enters text emission, so
    // nesting resolves through the same dispatch; an empty body
    // keeps KaTeX's empty row.
    fn textArg(self: *Writer, toks: []const parse.Tok, i: *usize, ta: symbols.TextArg) Error!void {
        const sp = try textArgSpan(toks, i.*);
        if (ta == .circled) {
            self.str("<mover accent=\"true\"><mrow>");
            try self.textBody(toks[sp.s..sp.e], true);
            self.str("</mrow><mo>◯</mo></mover>");
        } else {
            self.str("<menclose notation=\"horizontalstrike\"><mrow>");
            try self.textBody(toks[sp.s..sp.e], true);
            self.str("</mrow></menclose>");
        }
        i.* = sp.after - 1;
    }

    // True when the range holds an argument-taking text command
    // (pure classification, no errors — cannot drift the accept set).
    fn hasStructural(toks: []const parse.Tok) bool {
        for (toks) |tk| {
            if (tk.kind == .ctrl and symbols.lookupTextArg(tk.name) != null) return true;
        }
        return false;
    }

    // Text row (KaTeX parity, issue #51 review): a range with
    // structural commands wraps in `mrow`; pure text material emits
    // bare (one `mtext` run, or nothing for braces-only — the caller
    // row-wraps that to KaTeX's empty row). Single-fragment rows
    // normalize away in the parity gate, matching KaTeX's
    // run-merge-then-row rule.
    fn textRow(self: *Writer, toks: []const parse.Tok) Error!void {
        if (!hasStructural(toks)) return self.textBody(toks, true);
        self.str("<mrow>");
        try self.textBody(toks, true);
        self.str("</mrow>");
    }

    // Fragmenting text emission: text runs become `mtext` leaves
    // while argument-taking commands (sout/circled) emit
    // structurally inline. With `managed == false` the caller owns
    // the `mtext` shell (non-rm variants, colorbox bodies) and runs
    // emit inline exactly as before.
    fn textBody(self: *Writer, toks: []const parse.Tok, managed: bool) Error!void {
        var i: usize = 0;
        var open = false;
        while (i < toks.len) : (i += 1) {
            const tk = toks[i];
            switch (tk.kind) {
                // Grouping braces are transparent in text (KaTeX parity).
                .lbrace, .rbrace => {},
                .ctrl => {
                    if (symbols.lookupTextArg(tk.name)) |ta| {
                        if (managed and open) {
                            self.str("</mtext>");
                            open = false;
                        }
                        try self.textArg(toks, &i, ta);
                        continue;
                    }
                    if (managed and !open) {
                        self.str("<mtext>");
                        open = true;
                    }
                    // Full-profile text commands (layout parity).
                    if (symbols.lookupText(tk.name)) |tcp| {
                        self.escCp(tcp);
                        continue;
                    }
                    const c = tk.name[0];
                    switch (c) {
                        '{', '}', '%', '&', '#', '_', '$', '|', '/' => self.escCp(c),
                        // Spacing commands are Unicode spaces (KaTeX 0.18.7
                        // `mtext` runs: thin U+2009, med U+2005, thick
                        // U+2005+U+200A, neg-thin U+2009+U+2063).
                        ',' => self.escCp(0x2009),
                        ':', '>' => self.escCp(0x2005),
                        ';' => {
                            self.escCp(0x2005);
                            self.escCp(0x200A);
                        },
                        '!' => {
                            self.escCp(0x2009);
                            self.escCp(0x2063);
                        },
                        ' ' => self.byte(' '),
                        else => try self.textAccentTok(toks, &i, c),
                    }
                },
                else => {
                    if (managed and !open) {
                        self.str("<mtext>");
                        open = true;
                    }
                    switch (tk.kind) {
                        .char => {
                            // `~` is U+00A0 in text (KaTeX parity); the `\~`
                            // accent command is handled above.
                            if (tk.cp == ' ') {
                                self.byte(' ');
                            } else if (tk.cp == '~') {
                                self.escCp(0xA0);
                            } else self.escCp(tk.cp);
                        },
                        .newline => self.byte(' '),
                        else => return error.Invalid,
                    }
                },
            }
        }
        if (managed and open) self.str("</mtext>");
    }

    /// Literal color-spec token range to an attribute value.
    fn colorSpec(self: *Writer, r: parse.Range) Error!void {
        const toks = parse.toksOf(self.pc, r);
        for (toks) |tk| {
            switch (tk.kind) {
                .char => {
                    if (tk.cp == ' ') self.byte(' ') else self.escAttr(tk.cp);
                },
                .ctrl => {
                    if (tk.name.len == 1) {
                        const c: u8 = tk.name[0];
                        self.escAttr(c);
                    } else {
                        self.str(tk.name);
                    }
                },
                .lbrace => self.byte('{'),
                .rbrace => self.byte('}'),
                else => return error.Invalid,
            }
        }
    }

    /// Render one node at an explicit style (mirrors the layout
    /// core's style threading; restores the ambient style after).
    fn atStyle(self: *Writer, st: parse.Style, id: Idx, face: Face) Error!void {
        const outer = self.style;
        self.style = st;
        try self.node(id, face);
        self.style = outer;
    }

    fn node(self: *Writer, id: Idx, face: Face) Error!void {
        if (self.overflow) return error.NoSpace;
        const n = parse.nodeAt(self.pc, id);
        switch (n) {
            .atom => |a| self.atom(a.class, self.effFam(face, a.font), a.cp),
            .op => |o| {
                if (o.func) {
                    self.str("<mi>");
                    // Two-word limit operators join with a thin space
                    // (KaTeX `<mi mathvariant="normal">lim\u{2009}inf</mi>`,
                    // pinned 0.18.7; issue #36).
                    if (symbols.splitLimitOp(o.text)) |halves| {
                        self.str(halves[0]);
                        self.escCp(0x2009);
                        self.str(halves[1]);
                    } else {
                        self.str(o.text);
                    }
                    self.str("</mi>");
                    // Function application marker (KaTeX parity).
                    self.str("<mo>");
                    self.cp(0x2061);
                    self.str("</mo>");
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
                self.str("<mo>");
                self.cp(0x2061);
                self.str("</mo>");
            },
            .group => |g| {
                // Row rule (KaTeX parity): a lone child renders bare,
                // an empty group keeps its row, the rest wrap in mrow.
                const kids = parse.kidsOf(self.pc, g);
                if (kids.len == 1) {
                    try self.node(kids[0], face);
                } else {
                    self.str("<mrow>");
                    for (kids) |k| try self.node(k, face);
                    self.str("</mrow>");
                }
            },
            .frac => |f| {
                if (f.kind.parens) self.str("<mrow><mo>(</mo>");
                if (!f.kind.bar) self.str("<mfrac linethickness=\"0\">") else self.str("<mfrac>");
                try self.atStyle(self.style.numerator(), f.num, face);
                try self.atStyle(self.style.denominator(), f.den, face);
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
                    try self.atStyle(self.style.script(), s.index, face);
                    self.str("</mroot>");
                }
            },
            .supsub => |s| {
                const has_sup = s.sup != NONE;
                const has_sub = s.sub != NONE;
                // KaTeX parity (pinned 0.18.7 `supsub.ts` mathmlBuilder):
                // with both scripts present, `munderover` needs display
                // style even for forced `\limits` (`\int\limits_0^1` in
                // text is `msubsup` in MathML while the HTML stacks);
                // single scripts follow the shared limit decision.
                const stacked = if (parse.opBase(self.pc, s.base)) |o| blk: {
                    if (has_sup and has_sub) {
                        break :blk self.style.isDisplay() and o.limits != .off and
                            (o.limits == .on or o.lim_def);
                    }
                    break :blk parse.useLimits(self.style, o);
                } else false;
                const sc = self.style.script();
                // A function base rows its name with the application
                // marker (KaTeX `parentIsSupSub` parity).
                const row_base = baseIsFuncOp(self.pc, s.base);
                // KaTeX `horizBrace` parity: a sup on an overbrace (or a
                // sub on an underbrace) wraps the whole brace node plus
                // scripts in one mover/munder, children in base/sub/sup
                // order. The cross cases stay plain msup/msub.
                const brace_over: ?bool = switch (parse.nodeAt(self.pc, s.base)) {
                    .over => |o| switch (o.kind) {
                        .overbrace, .overbracket => true,
                        .underbrace, .underbracket => false,
                        else => null,
                    },
                    else => null,
                };
                if (brace_over) |is_over| {
                    if (has_sup == is_over) {
                        self.str(if (is_over) "<mover>" else "<munder>");
                        try self.node(s.base, face);
                        if (has_sub) try self.atStyle(sc, s.sub, face);
                        if (has_sup) try self.atStyle(sc, s.sup, face);
                        self.str(if (is_over) "</mover>" else "</munder>");
                    } else if (has_sup and has_sub) {
                        self.str("<msubsup>");
                        try self.node(s.base, face);
                        try self.atStyle(sc, s.sub, face);
                        try self.atStyle(sc, s.sup, face);
                        self.str("</msubsup>");
                    } else if (has_sup) {
                        self.str("<msup>");
                        try self.node(s.base, face);
                        try self.atStyle(sc, s.sup, face);
                        self.str("</msup>");
                    } else {
                        self.str("<msub>");
                        try self.node(s.base, face);
                        try self.atStyle(sc, s.sub, face);
                        self.str("</msub>");
                    }
                } else if (has_sup and has_sub) {
                    self.str(if (stacked) "<munderover>" else "<msubsup>");
                    if (row_base) self.str("<mrow>");
                    try self.node(s.base, face);
                    if (row_base) self.str("</mrow>");
                    try self.atStyle(sc, s.sub, face);
                    try self.atStyle(sc, s.sup, face);
                    self.str(if (stacked) "</munderover>" else "</msubsup>");
                } else if (has_sup) {
                    self.str(if (stacked) "<mover>" else "<msup>");
                    if (row_base) self.str("<mrow>");
                    try self.node(s.base, face);
                    if (row_base) self.str("</mrow>");
                    try self.atStyle(sc, s.sup, face);
                    self.str(if (stacked) "</mover>" else "</msup>");
                } else {
                    self.str(if (stacked) "<munder>" else "<msub>");
                    if (row_base) self.str("<mrow>");
                    try self.node(s.base, face);
                    if (row_base) self.str("</mrow>");
                    try self.atStyle(sc, s.sub, face);
                    self.str(if (stacked) "</munder>" else "</msub>");
                }
            },
            .delim => |d| {
                self.str("<mrow>");
                if (d.left != 0) {
                    self.str("<mo fence=\"true\">");
                    self.cp(d.left);
                    self.str("</mo>");
                }
                // Fence bodies splice flat (KaTeX parity): no inner row.
                switch (parse.nodeAt(self.pc, d.body)) {
                    .group => |g| {
                        for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face);
                    },
                    else => try self.node(d.body, face),
                }
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
                if (a.cp == 0x20DB or a.cp == 0x20DC) {
                    // Dot accents have no font glyph in KaTeX: the MathML
                    // fallback renders literal dot runs inside a strut box.
                    self.str("<mi><mover><mo>");
                    try self.node(a.nucleus, face);
                    self.str("</mo><mpadded voffset=\"-0.1ex\">");
                    self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                    self.str("<mstyle mathsize=\"1em\">");
                    self.str("<mtext>");
                    self.str(if (a.cp == 0x20DB) "..." else "....");
                    self.str("</mtext></mstyle></mstyle></mpadded></mover></mi>");
                } else {
                    self.str("<mover>");
                    try self.node(a.nucleus, face);
                    self.str("<mo>");
                    self.cp(a.cp);
                    self.str("</mo></mover>");
                }
            },
            .over => |o| try self.over(o, face),
            .style => |s| {
                // `display`/`inline` only; cramped has no MathML form.
                // KaTeX splices a group body's children directly into
                // the mstyle (no mrow wrapper); other bodies render bare.
                const disp = s.style == .D or s.style == .Dc;
                if (disp) self.str("<mstyle displaystyle=\"true\">") else self.str("<mstyle displaystyle=\"false\">");
                const outer = self.style;
                self.style = s.style;
                switch (parse.nodeAt(self.pc, s.body)) {
                    .group => |g| for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face),
                    else => try self.node(s.body, face),
                }
                self.style = outer;
                self.str("</mstyle>");
            },
            .font => |f| {
                self.str("<mstyle mathvariant=\"");
                self.str(variantFor(f.fam));
                self.str("\">");
                try self.node(f.body, .{ .fam = f.fam, .script = face.script });
                self.str("</mstyle>");
            },
            // KaTeX parity (pinned 0.18.7, issue #51): poor-man's
            // bold is a text-shadow paint style on the same glyphs.
            .pmb => |p| {
                self.str("<mstyle style=\"text-shadow: 0.02em 0.01em 0.04px\">");
                try self.node(p.body, face);
                self.str("</mstyle>");
            },
            // Math-mode circled (issue #51 review, pinned 0.18.7):
            // mover with the circle operator, body row like KaTeX.
            .circled => |c| {
                self.str("<mover accent=\"true\">");
                try self.node(c.body, face);
                self.str("<mo>◯</mo></mover>");
            },
            .vcenter => |v| {
                self.str("<mpadded class=\"vcenter\">");
                try self.node(v.body, face);
                self.str("</mpadded>");
            },
            .text => |t| {
                if (t.fam == .rm) {
                    try self.textRow(parse.toksOf(self.pc, t.toks));
                } else {
                    self.str("<mtext mathvariant=\"");
                    self.str(variantFor(t.fam));
                    self.str("\">");
                    try self.textBody(parse.toksOf(self.pc, t.toks), false);
                    self.str("</mtext>");
                }
            },
            .env => |e| try self.env(e, face),
            .substack => |r| {
                // KaTeX `subarray` parity: script cells with per-cell
                // mstyle, and the whole small table wrapped so the row
                // gap stays small (`arraystretch < 1` rule).
                self.str("<mstyle scriptlevel=\"1\"><mtable>");
                for (parse.rowsOf(self.pc, r.start, r.len)) |row| {
                    self.str("<mtr><mtd><mstyle scriptlevel=\"1\" displaystyle=\"false\">");
                    const kids = parse.kidsOf(self.pc, .{ .start = row.start, .len = row.len });
                    for (kids) |k| try self.atStyle(.S, k, face);
                    self.str("</mstyle></mtd></mtr>");
                }
                self.str("</mtable></mstyle>");
            },
            .mathchoice => |c| try self.node(c[0], face),
            .space => |u| {
                // Small spacings serialize as text (KaTeX parity);
                // only measurable glue stays an `mspace`. Widths are
                // the canonical `parse.space_*` constants (issue 16).
                switch (u) {
                    parse.space_thin => {
                        self.str("<mtext>");
                        self.cp(0x2009);
                        self.str("</mtext>");
                    },
                    parse.space_med => {
                        self.str("<mtext>");
                        self.cp(0x2005);
                        self.str("</mtext>");
                    },
                    parse.space_thick => {
                        self.str("<mtext>");
                        self.cp(0x2005);
                        self.cp(0x200A);
                        self.str("</mtext>");
                    },
                    parse.space_interword => {
                        self.str("<mtext>");
                        self.cp(0x00A0);
                        self.str("</mtext>");
                    },
                    -parse.space_thin => {
                        self.str("<mtext>");
                        self.cp(0x2009);
                        self.cp(0x2063);
                        self.str("</mtext>");
                    },
                    else => {
                        self.str("<mspace width=\"");
                        self.em(u);
                        self.str("\"/>");
                    },
                }
            },
            .vspace => |u| {
                self.str("<mspace height=\"");
                self.em(u);
                self.str("\"/>");
            },
            .newline => self.str("<mspace linebreak=\"newline\"/>"),
            .hline => {},
            .color => |c| {
                // KaTeX builds the body as a flat expression (no row),
                // whether declaration or scoped form.
                self.str("<mstyle mathcolor=\"");
                try self.colorSpec(c.spec);
                self.str("\">");
                switch (parse.nodeAt(self.pc, c.body)) {
                    .group => |g| for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face),
                    else => try self.node(c.body, face),
                }
                self.str("</mstyle>");
            },
            .colorbox => |c| {
                // Fixed KaTeX box metrics: no layout math, just markup.
                self.str("<mpadded width=\"+6pt\" height=\"+6pt\" lspace=\"3pt\" voffset=\"3pt\"");
                if (c.frame.len > 0) {
                    self.str(" style=\"border: 0.04em solid ");
                    try self.colorSpec(c.frame);
                    self.byte('"');
                }
                self.str(" mathbackground=\"");
                try self.colorSpec(c.bg);
                self.str("\">");
                self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                const toks = parse.toksOf(self.pc, c.body);
                if (toks.len == 0) {
                    self.str("<mrow></mrow>");
                } else {
                    self.str("<mtext>");
                    try self.textBody(toks, false);
                    self.str("</mtext>");
                }
                self.str("</mstyle></mpadded>");
            },
            .href => |h| {
                // KaTeX puts the href on the child and builds the body
                // flat (no row); the normalizer drops our shell.
                self.str("<mrow href=\"");
                const toks = parse.toksOf(self.pc, h.target);
                for (toks) |tk| {
                    if (tk.kind == .char and tk.cp < 0x80) {
                        const c: u8 = @intCast(tk.cp);
                        if (c == '"') self.str("&quot;") else if (c == '&') self.str("&amp;") else self.byte(c);
                    }
                }
                self.str("\">");
                switch (parse.nodeAt(self.pc, h.body)) {
                    .group => |g| for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face),
                    else => try self.node(h.body, face),
                }
                self.str("</mrow>");
            },
            .htmlwrap => |b| try self.node(b, face),
            // KaTeX parity (pinned 0.18.7): \mathop{x} -> <mo>x</mo>,
            // \mathrel{x} -> <mo>x</mo>; \mathinner{x} is a bare
            // <mpadded> there, structurally identical to <mrow>,
            // which is what this emitter knows.
            .classwrap => |c| {
                if (c.class == .Inner) self.str("<mrow>") else self.str("<mo>");
                try self.node(c.body, face);
                if (c.class == .Inner) self.str("</mrow>") else self.str("</mo>");
            },
            .phantom => |p| {
                self.str("<mphantom>");
                try self.node(p.body, face);
                self.str("</mphantom>");
            },
            .boxed => |b| {
                // KaTeX `\fbox` layers an hbox mstyle and a math-in-text
                // mstyle (both text-style); `\boxed` adds its
                // displaystyle style node inside those (see parse).
                self.str("<menclose notation=\"box\">");
                self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                try self.node(b, face);
                self.str("</mstyle></mstyle></menclose>");
            },
            .cancel => |b| {
                self.str("<menclose notation=\"updiagonalstrike\">");
                try self.node(b, face);
                self.str("</menclose>");
            },
            .sout => |b| {
                self.str("<menclose notation=\"horizontalstrike\">");
                try self.node(b, face);
                self.str("</menclose>");
            },
            .phase => |b| {
                self.str("<menclose notation=\"phasorangle\">");
                try self.node(b, face);
                self.str("</menclose>");
            },
            .not => |nt| {
                // Mark-first element order, exactly what the old rlap
                // overlay produced, so `mergeNot` fuses KaTeX-identical
                // output (`<mo>=</mo>` + mark → `<mo>=mark</mo>`). The
                // mark bytes match `mergeNot`'s mark list.
                self.str("<mo>\xcc\xb8</mo>");
                try self.node(nt.base, face);
                return;
            },
            .lap => |l| {
                // KaTeX offsets laps via lspace (rlap needs none).
                self.str("<mpadded");
                switch (l.kind) {
                    .llap => self.str(" lspace=\"-1width\""),
                    .clap => self.str(" lspace=\"-0.5width\""),
                    .rlap => {},
                }
                self.str(" width=\"0px\">");
                try self.node(l.body, face);
                self.str("</mpadded>");
            },
            .smash => |s| {
                // KaTeX wraps the body in mpadded, zeroing the smashed
                // sides (`keep_*` is the complement: kept sides stay).
                self.str("<mpadded");
                if (!s.keep_t) self.str(" height=\"0px\"");
                if (!s.keep_b) self.str(" depth=\"0px\"");
                self.str(">");
                try self.node(s.body, face);
                self.str("</mpadded>");
            },
            .raisebox => |r| {
                // KaTeX parity: the hbox body renders as text under a
                // text-style mstyle inside the shifted mpadded.
                self.str("<mpadded voffset=\"");
                self.em(r.dh);
                self.str("\"><mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                try self.node(r.body, face);
                self.str("</mstyle></mpadded>");
            },
            .rule => |r| {
                // KaTeX wraps the rule mspace in a shift mpadded. The
                // background is the ambient color (black here — the
                // writer tracks no ambient color; values are out of
                // tag scope).
                self.str("<mpadded height=\"");
                self.em(r.raise);
                self.str("\" voffset=\"");
                self.em(r.raise);
                self.str("\">");
                self.str("<mspace mathbackground=\"black\" width=\"");
                self.em(r.w);
                self.str("\" height=\"");
                self.em(r.h);
                self.str("\"></mspace></mpadded>");
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
            // KaTeX `atom` ParseNodes (every symbol group except
            // mathord/textord) render as mo — inner symbols included.
            .Bin, .Rel, .Open, .Close, .Punct, .Op, .Inner => {
                if (c >= 0x231C and c <= 0x231F) {
                    // Corner delimiters nest textord-in-mo in KaTeX
                    // (the inner mi carries mathvariant normal).
                    self.str("<mo><mi mathvariant=\"normal\">");
                    self.escCp(c);
                    self.str("</mi></mo>");
                } else if (c == 0x22EE) {
                    // `\vdots` is a macro for `\varvdots\rule{0pt}{15pt}`;
                    // KaTeX renders the rule as a fixed strut inside
                    // its own mrow (ordgroup parity).
                    self.str("<mrow><mi>");
                    self.escCp(c);
                    self.str("</mi>");
                    self.str("<mpadded height=\"0em\" voffset=\"0em\">");
                    self.str("<mspace mathbackground=\"black\" width=\"0em\" height=\"1.5em\">");
                    self.str("</mspace></mpadded></mrow>");
                } else {
                    self.str("<mo>");
                    self.escCp(c);
                    self.str("</mo>");
                }
            },
            .Ord => {
                if (c == 0x22EE) {
                    // Directly-typed U+22EE takes KaTeX's `\vdots` macro
                    // shape (mi plus the rule strut).
                    self.str("<mi>");
                    self.escCp(c);
                    self.str("</mi>");
                    self.str("<mpadded height=\"0em\" voffset=\"0em\">");
                    self.str("<mspace mathbackground=\"black\" width=\"0em\" height=\"1.5em\">");
                    self.str("</mspace></mpadded>");
                } else if (isDigit(c)) {
                    self.str("<mn>");
                    self.escCp(c);
                    self.str("</mn>");
                } else if (c == 0x2032) {
                    // `\prime`: KaTeX textord renders as mo (verified
                    // against KaTeX 0.18.7 dist source).
                    self.str("<mo>");
                    self.escCp(c);
                    self.str("</mo>");
                } else {
                    // KaTeX mathord/textord render as mi unconditionally.
                    self.str("<mi>");
                    self.escCp(c);
                    self.str("</mi>");
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
            .overbracket => {
                self.str("<mover>");
                try self.node(o.nucleus, face);
                self.str("<mo>&#x23B4;</mo></mover>");
            },
            .underbracket => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>&#x23B5;</mo></munder>");
            },
            .overleft => try self.arrowOver(o.nucleus, 0x2190, face),
            .overright => try self.arrowOver(o.nucleus, 0x2192, face),
            .overboth => try self.arrowOver(o.nucleus, 0x2194, face),
            .underleft => try self.arrowUnder(o.nucleus, 0x2190, face),
            .underright => try self.arrowUnder(o.nucleus, 0x2192, face),
            .underboth => try self.arrowUnder(o.nucleus, 0x2194, face),
            .overset => try self.stackedOp(o.nucleus, o.extra, true, face),
            .underset => try self.stackedOp(o.nucleus, o.extra, false, face),
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

    /// `\overset`/`\underset` (KaTeX parity): KaTeX desugars these to an
    /// op-with-body plus supsub inside an mclass, which renders as the
    /// base children wrapped flat in mo, stacked under/over the extra,
    /// and the whole thing wrapped in mi for Ord bases else mo
    /// (KaTeX `binrelClass`: only Bin/Rel bases stay mo).
    fn stackedOp(self: *Writer, nuc: Idx, extra: Idx, is_over: bool, face: Face) Error!void {
        const first: Idx = switch (parse.nodeAt(self.pc, nuc)) {
            .group => |g| blk: {
                const kids = parse.kidsOf(self.pc, g);
                break :blk if (kids.len > 0) kids[0] else nuc;
            },
            else => nuc,
        };
        const ord_base = switch (parse.nodeAt(self.pc, first)) {
            .atom => |a| a.class != .Bin and a.class != .Rel,
            else => true,
        };
        self.str(if (ord_base) "<mi>" else "<mo>");
        self.str(if (is_over) "<mover>" else "<munder>");
        self.str("<mo>");
        switch (parse.nodeAt(self.pc, nuc)) {
            .group => |g| for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face),
            else => try self.node(nuc, face),
        }
        self.str("</mo>");
        try self.atStyle(self.style.script(), extra, face);
        self.str(if (is_over) "</mover>" else "</munder>");
        self.str(if (ord_base) "</mi>" else "</mo>");
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
        // Extensible arrows (KaTeX `xArrow` parity): one
        // munderover/mover/munder whose labels each sit in an mpadded.
        // (KaTeX sets width/lspace attributes; attribute values are out
        // of scope for the tag comparison.)
        const sc = self.style.script();
        const has_over = o.extra != NONE;
        const has_under = o.under != NONE;
        self.str(if (has_over and has_under) "<munderover>"
            else if (has_under) "<munder>"
            else "<mover>");
        self.str("<mo>");
        self.cp(gc);
        self.str("</mo>");
        if (has_under) {
            self.str("<mpadded>");
            try self.atStyle(sc, o.under, face);
            self.str("</mpadded>");
        }
        if (has_over) {
            self.str("<mpadded>");
            try self.atStyle(sc, o.extra, face);
            self.str("</mpadded>");
        } else if (!has_under) {
            self.str("<mpadded></mpadded>");
        }
        self.str(if (has_over and has_under) "</munderover>"
            else if (has_under) "</munder>"
            else "</mover>");
    }

    fn env(self: *Writer, e: anytype, face: Face) Error!void {
        // KaTeX `parseArray` parity: every cell is a styling node
        // (display cells for aligned-family/gathered, script for
        // smallmatrix, text otherwise), whose MathML is an mstyle
        // wrapping the cell group under the normal row rule.
        const disp_cell = e.kind == .aligned or e.kind == .alignedat or e.kind == .gathered or
            e.kind == .dcases or e.kind == .drcases;
        const script_cell = e.kind == .smallmatrix;
        // Small tables keep a small row gap (KaTeX `arraystretch<1`).
        if (script_cell) self.str("<mstyle scriptlevel=\"1\">");
        // KaTeX `rowlines` parity (issue #33): rule rows between
        // content rows become gap entries (`solid`/`dashed`/`none`).
        // Leading/trailing rules have no gap to attach to (KaTeX wraps
        // those in `menclose`; not modeled).
        const rows = parse.rowsOf(self.pc, e.rows_start, e.rows_len);
        var gap_marks: [64]?bool = .{null} ** 64;
        var ncontent: usize = 0;
        var pending_rule: ?bool = null;
        var any_rule = false;
        for (rows) |row| {
            const kids = parse.kidsOf(self.pc, .{ .start = row.start, .len = row.len });
            if (kids.len == 1) {
                if (hlineDashed(self.pc, kids[0])) |dash| {
                    any_rule = true;
                    if (pending_rule == null) pending_rule = dash;
                    continue;
                }
            }
            if (ncontent > 0 and ncontent <= 64) gap_marks[ncontent - 1] = pending_rule;
            pending_rule = null;
            ncontent += 1;
        }
        if (any_rule) {
            self.str("<mtable rowlines=\"");
            var g: usize = 0;
            while (g + 1 < ncontent and g < 64) : (g += 1) {
                if (g > 0) self.str(" ");
                if (gap_marks[g]) |dash| {
                    self.str(if (dash) "dashed" else "solid");
                } else {
                    self.str("none");
                }
            }
            self.str("\">");
        } else {
            self.str("<mtable>");
        }
        const cs: parse.Style = if (disp_cell) .D else if (script_cell) .S else .T;
        for (rows) |row| {
            const kids = parse.kidsOf(self.pc, .{ .start = row.start, .len = row.len });
            // Rule rows fold into `rowlines` above; they emit no `mtr`
            // (KaTeX parity).
            if (kids.len == 1 and isHlineNode(self.pc, kids[0])) continue;
            self.str("<mtr>");
            for (kids) |k| {
                self.str("<mtd><mstyle scriptlevel=\"");
                self.str(if (script_cell) "1" else "0");
                self.str("\" displaystyle=\"");
                self.str(if (disp_cell) "true" else "false");
                self.str("\">");
                try self.atStyle(cs, k, face);
                self.str("</mstyle></mtd>");
            }
            self.str("</mtr>");
        }
        self.str("</mtable>");
        if (script_cell) self.str("</mstyle>");
    }
};

/// Row-rule detection (mirrors the layout core): bare rule node or a
/// group wrapping exactly one. Returns dashedness (issue #33).
fn hlineDashed(pc: *const parse.ParseCtx, id: Idx) ?bool {
    switch (parse.nodeAt(pc, id)) {
        .hline => |h| return h.dashed,
        .group => |g| {
            const kids = parse.kidsOf(pc, g);
            if (kids.len != 1) return null;
            return hlineDashed(pc, kids[0]);
        },
        else => return null,
    }
}

fn isHlineNode(pc: *const parse.ParseCtx, id: Idx) bool {
    return hlineDashed(pc, id) != null;
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

/// `Ord` codepoints KaTeX types as `textord` and therefore serializes
/// as `mi` (not `mo`): quantifiers, daggers, bars, suits, and friends.
/// Pinned against KaTeX 0.18.7 `symbols.js`; symbol sweep rows guard it.
fn isIdentSymbol(c: u21) bool {
    return switch (c) {
        0x00A3, 0x00A5, 0x00A7, 0x00AC, 0x00AE, 0x00B6, 0x00F0, 0x03DD,
        0x2020, 0x2021, 0x2035, 0x210F, 0x2111, 0x211C, 0x2127, 0x2132,
        0x2135, 0x2136, 0x2137, 0x2138, 0x2141, 0x2200, 0x2202, 0x2203,
        0x2204, 0x2205, 0x2207, 0x221A, 0x221E, 0x2220, 0x2221, 0x2222,
        0x2223, 0x2225, 0x22A4, 0x22A5, 0x24C8, 0x2660, 0x2661, 0x2662,
        0x2663, 0x266D, 0x266E, 0x266F, 0x2713, 0x2720, 0x0338,
        => true,
        else => false,
    };
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

test "text tilde command precomposes, it is not nbsp" {
    // Regression: `.ctrl '~'` took the nbsp arm while `.char '~'`
    // emitted a visible glyph — exactly swapped. KaTeX emits bare ã
    // (grouping braces are transparent in text mode).
    var pc = parse.ParseCtx.init("\\text{\\~{a}}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mtext>\xc3\xa3</mtext>", out[0..w.pos]);
}

test "text braced accent arg precomposes like the bare form" {
    // KaTeX accepts `\'{a}` as well as `\'a`, both rendering á.
    var pc = parse.ParseCtx.init("\\text{\\'{a}}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mtext>\xc3\xa1</mtext>", out[0..w.pos]);
}

test "text dot accent without precomposed form emits base plus combining mark" {
    // KaTeX accepts `\text{\.{a}}` (pinned 0.18.7 renders an overlaid
    // accent via `mover`); inside `mtext` the combining form renders the
    // same glyph (`a` + U+0307).
    var pc = parse.ParseCtx.init("\\text{\\.{a}}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mtext>a\xcc\x87</mtext>", out[0..w.pos]);
}

test "text thin space is U+2009, matching KaTeX" {
    var pc = parse.ParseCtx.init("\\text{a\\,b}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mtext>a\xe2\x80\x89b</mtext>", out[0..w.pos]);
}

test "text tilde char is nbsp, matching KaTeX" {
    var pc = parse.ParseCtx.init("\\text{a~b}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "a\xc2\xa0b") != null);
}

test "color wraps body in mathcolor mstyle" {
    var pc = parse.ParseCtx.init("\\color{#f00}{x}+y");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    const s = out[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, s, "<mstyle mathcolor=\"#f00\">") != null);
}

test "colorbox emits padded background box" {
    var pc = parse.ParseCtx.init("\\fcolorbox{red}{yellow}{x}");
    const root = try parse.parse(&pc, false);
    var out: [1024]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    const s = out[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, s, "mathbackground=\"yellow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "border: 0.04em solid red") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mtext>x</mtext>") != null);
}

test "textord symbols emit mi, vdots keeps its strut" {
    var pc = parse.ParseCtx.init("\\infty+\\forall\\vdots");
    const root = try parse.parse(&pc, false);
    var out: [1024]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    const s = out[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, s, "<mi>\xe2\x88\x9e</mi>") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mi>\xe2\x88\x80</mi>") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mpadded height=\"0em\" voffset=\"0em\">") != null);
}

test "display sums stack, integrals do not" {
    var out: [512]u8 = undefined;
    const d = try render("\\sum_a^b", .{ .display_mode = true }, &out);
    try std.testing.expect(std.mem.indexOf(u8, d, "<munderover>") != null);
    var out2: [512]u8 = undefined;
    const t = try render("\\sum_a^b", .{}, &out2);
    try std.testing.expect(std.mem.indexOf(u8, t, "<msubsup>") != null);
    var out3: [512]u8 = undefined;
    const i = try render("\\int_a^b", .{ .display_mode = true }, &out3);
    try std.testing.expect(std.mem.indexOf(u8, i, "<msubsup>") != null);
    var out4: [512]u8 = undefined;
    const f = try render("\\int\\limits_a^b", .{ .display_mode = true }, &out4);
    try std.testing.expect(std.mem.indexOf(u8, f, "<munderover>") != null);
}

test "not overlays onto the following symbol" {
    var out: [256]u8 = undefined;
    const s = try render("\\not\\in", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mo>\xe2\x88\x88\xcc\xb8</mo>") != null);
}

test "builtin func-ops and textord corners match KaTeX tags" {
    var pc = parse.ParseCtx.init("\\liminf\\ln\\lnot\\lll\\llcorner");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    const s = out[0..w.pos];
    try std.testing.expectEqualStrings(
        // `liminf` carries KaTeX's thin space (pinned 0.18.7 MathML
        // `lim\u{2009}inf`, issue #36); the old `liminf` spelling was
        // wrong per the KaTeX-side proof.
        "<mrow><mi>lim\u{2009}inf</mi><mo>\u{2061}</mo>" ++
            "<mi>ln</mi><mo>\u{2061}</mo>" ++
            "<mi>\u{ac}</mi><mo>\u{22d8}</mo>" ++
            "<mo><mi mathvariant=\"normal\">\u{231e}</mi></mo></mrow>",
        s);
}
test "verb and text fonts emit variant mtext" {
    var pc = parse.ParseCtx.init("\\verb|x|+\\textbf{ab}");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    const s = out[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, s, "<mtext mathvariant=\"monospace\">x</mtext>") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mtext mathvariant=\"bold\">ab</mtext>") != null);
}
