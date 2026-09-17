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
    // KaTeX `buildMathML` (issue #119, pinned 0.18.7): the body lives
    // in `<semantics>` with the raw TeX source as the
    // `application/x-tex` annotation (copy-tex / AT consumers read
    // the source back out of it).
    w.str("><semantics>");
    // The root row wraps a lone child unless it already presents
    // as a row (KaTeX `buildMathML`: single rowlike passes through).
    // An equation tag is the table itself (never `mrow`-wrapped).
    const wrap = switch (parse.nodeAt(&pc, root)) {
        .group => |g| g.len == 1 and !rendersRow(&pc, parse.kidsOf(&pc, g)[0]),
        .tag => false,
        else => true,
    };
    // Sole-threading (issue #94): the envelope row's lone child is
    // sole in its row, so a sole font body splices flat (KaTeX pushes
    // variants to leaves — the `.delim`/`.style` splice precedent).
    if (wrap) {
        w.str("<mrow>");
        w.nodeSole(root, .{ .fam = null, .script = false }, true) catch |e| return e;
        w.str("</mrow>");
    } else w.node(root, .{ .fam = null, .script = false }) catch |e| return e;
    w.str("<annotation encoding=\"application/x-tex\">");
    w.anno(source);
    w.str("</annotation></semantics></math>");
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
                // `mstyle` is an attribute shell, not a structural
                // position (issue #94): it stays off the stack, so
                // merging stays row-local through it and sole-font
                // digit runs fold like KaTeX (`\bf 12` → one `mn`).
                // Strict adjacency still gates every fold (tryRun),
                // so nothing merges across shells.
                if (!tag.nameEqual("mstyle")) st.push(tag.nameEqual("mrow"));
            } else if (tag.closing) {
                if (!tag.nameEqual("mstyle")) st.pop();
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

/// Whether an `mtext` run holds kern glue. KaTeX `kern` nodes build a
/// `SpaceNode`, which is *not* a `MathNode`, so `buildExpression` never
/// merges them (each keeps its own `mtext`); `spacing` nodes (`\ `, `~`)
/// and text runs build real `MathNode` `mtext`s, which merge freely.
/// Pinned by probe: `\>\>` stays two `mtext`s, `\ \ ` folds to one.
/// The set is exactly the characters the `.space` writer emits into
/// `mtext` for kern widths (thin U+2009, medium U+2005, thick U+2005 +
/// U+200A, negative thin U+2009 + separator, negative medium U+205F +
/// separator, negative thick U+2005 + separator — a base glue char
/// alone trips the scan). Interword NBSP (U+00A0, the `.nbsp` node) is
/// `spacing`-origin content and merges. Residual edge: a literal glue
/// character typed inside `\text` is `MathNode` content in KaTeX (it
/// merges) but refuses here; no corpus row covers it.
fn hasGlue(text: []const u8) bool {
    var i: usize = 0;
    while (i + 2 < text.len) {
        if (text[i] == 0xE2 and text[i + 1] == 0x80 and
            (text[i + 2] == 0x89 or text[i + 2] == 0x85 or text[i + 2] == 0x8A))
            return true;
        // Negative medium (U+205F) and the invisible separator
        // (U+2063) that rides every negative kern.
        if (text[i] == 0xE2 and text[i + 1] == 0x81 and
            (text[i + 2] == 0x9F or text[i + 2] == 0xA3))
            return true;
        i += 1;
    }
    return false;
}

/// Fold the run at `r` (`<nm>…</nm>` followers with equal open tags),
/// advancing `n`/`r` past it. Returns false when nothing merges.
fn tryRun(buf: []u8, n: *usize, r: *usize, comptime nm: []const u8) bool {
    const first = textSpan(buf, r.*, nm);
    if (first.close == 0) return false;
    // Kern-origin `mtext` runs never fold (see `hasGlue`). Only
    // `mtext` folds consult it; `mn` folds are unaffected.
    const check_glue = comptime std.mem.eql(u8, nm, "mtext");
    var cur = first;
    var count: usize = 1;
    var glue = check_glue and hasGlue(buf[first.text .. first.text + first.text_len]);
    while (true) {
        const nx = cur.next;
        if (nx >= buf.len or !matchOpen(buf, nx, nm)) break;
        const f = textSpan(buf, nx, nm);
        if (f.close == 0 or !std.mem.eql(u8, f.attrs, first.attrs)) break;
        if (check_glue and hasGlue(buf[f.text .. f.text + f.text_len])) glue = true;
        cur = f;
        count += 1;
    }
    if (count < 2 or glue) return false;
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
        .varlim => true,
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
        .frac => |f| return f.kind.fence != .none,
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

    /// Raw-source annotation content (issue #119): KaTeX
    /// `utils.escape` over the input bytes (`&<>"'` — byte-wise is
    /// exact because every escape target is ASCII and multibyte
    /// UTF-8 never contains ASCII bytes).
    fn anno(self: *Writer, src: []const u8) void {
        for (src) |b| {
            switch (b) {
                '&' => self.str("&amp;"),
                '<' => self.str("&lt;"),
                '>' => self.str("&gt;"),
                '"' => self.str("&quot;"),
                '\'' => self.str("&#x27;"),
                else => self.byte(b),
            }
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

    /// One raw `\includegraphics` token toward an `mglyph`
    /// attribute. Chars escape like KaTeX `utils_escape`
    /// (`&<>"'`); single-char controls in `#$%&~_^{}` resolve to
    /// the char itself (KaTeX `parseUrlGroup` unescape — `alt`
    /// passes `unescape = false` and keeps the backslash form);
    /// other controls re-emit backslash + name, braces and `^_&`
    /// literally. Markers vanish.
    fn graphicsTok(self: *Writer, tok: parse.Tok, unescape: bool) void {
        switch (tok.kind) {
            .char => {
                if (tok.cp == '\'') self.str("&#x27;") else self.escAttr(tok.cp);
            },
            .ctrl => {
                if (unescape and tok.name.len == 1) {
                    switch (tok.name[0]) {
                        '#', '$', '%', '&', '~', '_', '^', '{', '}' => {
                            self.escAttr(tok.name[0]);
                            return;
                        },
                        else => {},
                    }
                }
                self.byte('\\');
                for (tok.name) |b| self.escAttr(b);
            },
            .lbrace => self.byte('{'),
            .rbrace => self.byte('}'),
            .sup => self.byte('^'),
            .sub => self.byte('_'),
            .amp => self.str("&amp;"),
            .newline => {
                self.byte('\\');
                self.byte('\n');
            },
            else => {},
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

    /// Equation-tag cell: the body text parenthesized (`\tag`) or
    /// bare (`\tag*`). The `mrow` shell lets the merge pass fold a
    /// single-run body into one `mtext` (`(1)`); the sweep-side
    /// single-child drop removes the shell there, while an empty body
    /// keeps KaTeX's tripartite `( <mrow></mrow> )` shape (the explicit
    /// empty row blocks the fold).
    fn tagCell(self: *Writer, tg: anytype) Error!void {
        const t = parse.nodeAt(self.pc, tg.body).text;
        const toks = parse.toksOf(self.pc, t.toks);
        if (!tg.starred) self.str("<mrow><mtext>(</mtext>");
        const before = self.pos;
        try self.textRow(toks);
        if (self.pos == before) self.str("<mrow></mrow>");
        if (!tg.starred) self.str("<mtext>)</mtext></mrow>");
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

    /// Render a body whose group kids splice inline (no `mrow`
    /// wrapper): KaTeX `buildExpression` splices function bodies
    /// directly into the parent (`\phantom{bc}`, `\hphantom{bc}`).
    fn spliced(self: *Writer, id: Idx, face: Face) Error!void {
        switch (parse.nodeAt(self.pc, id)) {
            .group => |g| for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face),
            else => try self.node(id, face),
        }
    }

    /// Unwrap single-child groups to a lone atom codepoint (KaTeX
    /// `getBaseElem` over ordgroups for `isCharacterBox`); null for
    /// anything else. Lets `mclass` pull the atom out of its `mi`
    /// (`\mathpunct{x}` → `<mo>x</mo>`).
    fn singleAtom(pc: *const parse.ParseCtx, id: Idx) ?u21 {
        var cur = id;
        while (true) {
            switch (parse.nodeAt(pc, cur)) {
                .group => |g| {
                    const kids = parse.kidsOf(pc, g);
                    if (kids.len != 1) return null;
                    cur = kids[0];
                },
                .atom => |a| return a.cp,
                else => return null,
            }
        }
    }

    fn node(self: *Writer, id: Idx, face: Face) Error!void {
        return self.nodeSole(id, face, false);
    }

    /// Row-sole threading (issue #94): `sole` is true when this node
    /// is the lone child of its emitted row. A font whose multi-atom
    /// body is sole splices flat (KaTeX pushes variants to leaves);
    /// non-sole it rows its body like a brace group. Every other node
    /// ignores `sole`, so `node()` (false) preserves today's shapes
    /// exactly — only the envelope, `.group`, `.font`, and `.href`
    /// arms below pass anything else.
    fn nodeSole(self: *Writer, id: Idx, face: Face, sole: bool) Error!void {
        if (self.overflow) return error.NoSpace;
        const n = parse.nodeAt(self.pc, id);
        switch (n) {
            .atom => |a| self.atom(a.class, self.effFam(face, a.font), a.cp, a.textord, face.fam == null),
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
            .varlim => |v| {
                // KaTeX operatorname shape (pinned 0.18.7): the
                // built under/over body wrapped in an upright `mi`,
                // then the function-application marker.
                self.str("<mi>");
                try self.node(v.body, face);
                self.str("</mi>");
                self.str("<mo>");
                self.cp(0x2061);
                self.str("</mo>");
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
                // Row rule (KaTeX parity): a lone child renders bare
                // (keeping row-sole: a sole font splices flat through
                // it, issue #94), an empty group keeps its row, the
                // rest wrap in mrow.
                const kids = parse.kidsOf(self.pc, g);
                if (kids.len == 1) {
                    try self.nodeSole(kids[0], face, sole);
                } else {
                    self.str("<mrow>");
                    for (kids) |k| try self.node(k, face);
                    self.str("</mrow>");
                }
            },
            .frac => |f| {
                // KaTeX wraps every fence pair (choose/brace/brack)
                // in fence mo's (pinned 0.18.7, issue #93).
                switch (f.kind.fence) {
                    .none => {},
                    .parens => self.str("<mrow><mo fence=\"true\">(</mo>"),
                    .braces => self.str("<mrow><mo fence=\"true\">{</mo>"),
                    .brackets => self.str("<mrow><mo fence=\"true\">[</mo>"),
                }
                if (!f.kind.bar) self.str("<mfrac linethickness=\"0\">") else self.str("<mfrac>");
                try self.atStyle(self.style.numerator(), f.num, face);
                try self.atStyle(self.style.denominator(), f.den, face);
                self.str("</mfrac>");
                switch (f.kind.fence) {
                    .none => {},
                    .parens => self.str("<mo fence=\"true\">)</mo></mrow>"),
                    .braces => self.str("<mo fence=\"true\">}</mo></mrow>"),
                    .brackets => self.str("<mo fence=\"true\">]</mo></mrow>"),
                }
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
                // text is `msubsup` in MathML while the HTML stacks) —
                // except a star-armed `\operatorname` with explicit
                // `\limits`, which stacks in every style (issue #98);
                // single scripts follow the shared limit decision.
                const stacked = if (parse.opBase(self.pc, s.base)) |o| blk: {
                    if (has_sup and has_sub) {
                        break :blk (self.style.isDisplay() and o.limits != .off and
                            (o.limits == .on or o.lim_def)) or o.force_stack;
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
            .size => |s| {
                // KaTeX `sizing` mathmlBuilder: `<mstyle mathsize>`
                // with `makeEm` formatting (`+n.toFixed(4)+"em"`),
                // body spliced like `.style` above. Multiplier is
                // per-mille, so the strings below are exact.
                self.str("<mstyle mathsize=\"");
                self.str(switch (s.mult) {
                    500 => "0.5em",
                    600 => "0.6em",
                    700 => "0.7em",
                    800 => "0.8em",
                    900 => "0.9em",
                    1000 => "1em",
                    1200 => "1.2em",
                    1440 => "1.44em",
                    1728 => "1.728em",
                    2074 => "2.074em",
                    2488 => "2.488em",
                    else => "1em",
                });
                self.str("\">");
                switch (parse.nodeAt(self.pc, s.body)) {
                    .group => |g| for (parse.kidsOf(self.pc, g)) |k| try self.node(k, face),
                    else => try self.node(s.body, face),
                }
                self.str("</mstyle>");
            },
            .font => |f| {
                // Sole-threading (issue #94, pinned 0.18.7): a sole
                // multi-atom body splices flat (KaTeX pushes the
                // variant onto leaves — no row of its own); non-sole
                // it rows like a brace group. Lone bodies render bare
                // exactly like `.group` above, so single-atom fonts
                // never change shape.
                // Empty bodies (issue #111: the isolated-argument
                // quirk, `{\bf}`) render a bare empty row — KaTeX's
                // font builder emits `<mrow></mrow>` for an empty
                // ordgroup, with no variant shell around nothing.
                const fempty = switch (parse.nodeAt(self.pc, f.body)) {
                    .group => |g| parse.kidsOf(self.pc, g).len == 0,
                    else => false,
                };
                if (fempty) {
                    self.str("<mrow></mrow>");
                } else {
                    self.str("<mstyle mathvariant=\"");
                    self.str(variantFor(f.fam));
                    self.str("\">");
                    switch (parse.nodeAt(self.pc, f.body)) {
                        .group => |g| {
                            const kids = parse.kidsOf(self.pc, g);
                            if (kids.len == 1) {
                                try self.nodeSole(kids[0], .{ .fam = f.fam, .script = face.script }, sole);
                            } else {
                                if (!sole) self.str("<mrow>");
                                for (kids) |k| try self.node(k, .{ .fam = f.fam, .script = face.script });
                                if (!sole) self.str("</mrow>");
                            }
                        },
                        else => try self.node(f.body, .{ .fam = f.fam, .script = face.script }),
                    }
                    self.str("</mstyle>");
                }
            },
            // KaTeX parity (pinned 0.18.7, issue #51): poor-man's
            // bold is a text-shadow paint style on the same glyphs.
            .pmb => |p| {
                self.str("<mstyle style=\"text-shadow: 0.02em 0.01em 0.04px\">");
                try self.node(p.body, face);
                self.str("</mstyle>");
            },
            // Mirrored content (issue #97): KaTeX's flip is CSS-only,
            // so its MathML is the plain body — walk straight through.
            .reflect => |r| {
                try self.node(r.body, face);
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
            // Interword NBSP (KaTeX `spacing`-origin `mtext`): merges
            // with neighboring `mtext` runs, unlike kern glue.
            .nbsp => {
                self.str("<mtext>");
                self.cp(0x00A0);
                self.str("</mtext>");
            },
            .space => |u| {
                // Small spacings serialize as text (KaTeX `SpaceNode`
                // parity); only measurable glue stays an `mspace`.
                // Widths are the canonical `parse.space_*` constants
                // (issue 16). Zero glue (`\allowbreak`, `\nobreak`) is
                // the bare open+close `<mspace></mspace>` of KaTeX
                // `symbolsSpacing.ts` (never self-closed: the sweep
                // normalizer counts open and close tags alike).
                switch (u) {
                    0 => self.str("<mspace></mspace>"),
                    // KaTeX `SpaceNode` parity (pinned 0.18.7): ±1mu
                    // (0.0556em) is a hair space, like the
                    // thin/med/thick buckets below — `\mskip1mu`
                    // (e.g. in `\bmod`) is an `mtext`, never `mspace`.
                    56 => {
                        self.str("<mtext>");
                        self.cp(0x200A);
                        self.str("</mtext>");
                    },
                    -56 => {
                        self.str("<mtext>");
                        self.cp(0x200A);
                        self.cp(0x2063);
                        self.str("</mtext>");
                    },
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
                    -parse.space_thin => {
                        self.str("<mtext>");
                        self.cp(0x2009);
                        self.cp(0x2063);
                        self.str("</mtext>");
                    },
                    // Negative medium/thick kern (pinned 0.18.7 goldens
                    // `negmedspace`/`negthickspace`): like the positive
                    // widths but with the invisible separator appended
                    // (medium uses U+205F, thick reuses U+2005).
                    -parse.space_med => {
                        self.str("<mtext>");
                        self.cp(0x205F);
                        self.cp(0x2063);
                        self.str("</mtext>");
                    },
                    -parse.space_thick => {
                        self.str("<mtext>");
                        self.cp(0x2005);
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
            // KaTeX emits open+close (never self-closed — the sweep
            // normalizer counts both); same rule as zero glue above.
            .newline => self.str("<mspace linebreak=\"newline\"></mspace>"),
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
                // KaTeX `parseUrlGroup` + `utils.escape` (issue #123,
                // pinned 0.18.7): single-char controls unescape,
                // everything else emits escaped (`&<>"'`; non-ASCII
                // passes through) — the `graphicsTok` path verbatim.
                for (toks) |tk| {
                    if (tk.kind == .param) {
                        self.byte('#');
                    } else self.graphicsTok(tk, true);
                }
                self.str("\">");
                switch (parse.nodeAt(self.pc, h.body)) {
                    .group => |g| {
                        // Sole-threading (issue #94): our href shell
                        // drops in the parity normalizer, so a sole
                        // font body must splice flat here (pinned
                        // 0.18.7 `\href{u}{\bf AaBb}` has no inner row).
                        const kids = parse.kidsOf(self.pc, g);
                        for (kids) |k| try self.nodeSole(k, face, kids.len == 1);
                    },
                    else => try self.node(h.body, face),
                }
                self.str("</mrow>");
            },
            .htmlwrap => |b| try self.node(b, face),
            .tag => |tg| {
                // Display equation number (KaTeX `tag` MathML,
                // pinned 0.18.7): a tag ADOPTED by a numbering env
                // belongs to the env's own number column, so the
                // env renders alone with EMPTY number cells (the
                // tag text is dropped). A tag that stayed pending
                // (trailing the env, or claimed by no numbering
                // row) keeps the whole equation in a full-width
                // table with the tag text right. Empty side cells
                // stay open+close (the sweep normalizer counts both).
                const adopted_env: ?Idx =
                    if (self.pc.tag_adopted) tagNumEnv(self.pc, tg.formula) else null;
                if (adopted_env) |eid| {
                    try self.env(switch (parse.nodeAt(self.pc, eid)) {
                        .env => |e| e,
                        else => unreachable,
                    }, face);
                } else {
                    self.str("<mtable width=\"100%\"><mtr><mtd width=\"50%\"></mtd><mtd>");
                    try self.node(tg.formula, face);
                    self.str("</mtd><mtd width=\"50%\"></mtd><mtd>");
                    try self.tagCell(tg);
                    self.str("</mtd></mtr></mtable>");
                }
            },
            // KaTeX parity (pinned 0.18.7 `mclass`/`op` builders):
            // `\mathrel{x}` retypes the lone inner node to `mo`
            // (`<mo>x</mo>`); longer bodies wrap spliced kids with
            // no `mrow` (`\mathrel{ab}` → `<mo><mi>a</mi>…</mo>`).
            // `\mathbin`/`\mathclose`/`\mathopen` retype the same
            // way; `\mathord` retypes to `mi` instead (`\mathord{x}`
            // → `<mi>x</mi>`). `\mathop` is op-type, never a
            // character box: it ALWAYS wraps (`\mathop{x}` →
            // `<mo><mi>x</mi></mo>`, `\mathop{ab}` →
            // `<mo><mi>a</mi><mi>b</mi></mo>`). `\mathinner` is a
            // bare `mpadded` with spliced kids (`\mathinner{x}` →
            // `<mpadded><mi>x</mi></mpadded>`).
            .classwrap => |c| {
                // KaTeX `mclass` with an empty body is a bare tag
                // (`\mathpunct{}` → `<mo …></mo>`, no `mrow` inside).
                // A lone atom is pulled out of its `mi` (`\mathpunct{x}`
                // → `<mo>x</mo>`); longer bodies splice kid-by-kid with
                // no `mrow` (`\mathrel{ab}` → `<mo><mi>a</mi>…</mo>`).
                const empty = switch (parse.nodeAt(self.pc, c.body)) {
                    .group => |g| g.len == 0,
                    else => false,
                };
                if (c.class == .Inner) {
                    self.str("<mpadded>");
                } else if (c.class == .Ord) {
                    self.str("<mi>");
                } else {
                    self.str("<mo>");
                }
                if (!empty) {
                    if (c.class == .Op or c.class == .Inner) {
                        try self.spliced(c.body, face);
                    } else if (singleAtom(self.pc, c.body)) |atom_cp| {
                        self.escCp(atom_cp);
                    } else {
                        try self.spliced(c.body, face);
                    }
                }
                if (c.class == .Inner) {
                    self.str("</mpadded>");
                } else if (c.class == .Ord) {
                    self.str("</mi>");
                } else {
                    self.str("</mo>");
                }
            },
            .phantom => |p| {
                // KaTeX parity: `\hphantom` is `\smash{\phantom{…}}`
                // and `\vphantom` zeroes the width — the smashed axes
                // zero out inside an `mpadded` shell, while a plain
                // `\phantom` keeps both axes and needs no shell. Body
                // kids splice directly (`buildExpression`, no `mrow`).
                if (p.keep_h and p.keep_v) {
                    self.str("<mphantom>");
                    try self.spliced(p.body, face);
                    self.str("</mphantom>");
                } else {
                    self.str("<mpadded");
                    if (!p.keep_h) self.str(" width=\"0px\"");
                    if (!p.keep_v) self.str(" height=\"0px\" depth=\"0px\"");
                    self.str("><mphantom>");
                    try self.spliced(p.body, face);
                    self.str("</mphantom></mpadded>");
                }
            },
            .boxed => |b| {
                // KaTeX `\boxed` layers the enclose hbox mstyle, the
                // math-in-text mstyle, and the displaystyle style node
                // the parser adds inside those (see parse).
                self.str("<menclose notation=\"box\">");
                self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                try self.node(b, face);
                self.str("</mstyle></mstyle></menclose>");
            },
            .fbox => |b| {
                // KaTeX `\fbox` frames an hbox: one text-style mstyle
                // around the text body (the parser guarantees `.text`).
                self.str("<menclose notation=\"box\">");
                self.str("<mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                try self.node(b, face);
                self.str("</mstyle></menclose>");
            },
            // Dual-branch content (KaTeX `\html@mathml`): the MathML
            // emitter renders the semantic (`math`) branch.
            .htmlmathml => |h| try self.node(h.math, face),
            .cancel => |c| {
                // Issue #107: `\bcancel` strikes the other diagonal
                // (pinned 0.18.7 `downdiagonalstrike`).
                if (c.down) self.str("<menclose notation=\"downdiagonalstrike\">") else self.str("<menclose notation=\"updiagonalstrike\">");
                try self.node(c.body, face);
                self.str("</menclose>");
            },
            .xcancel => |b| {
                // KaTeX parity (pinned 0.18.7): both diagonals.
                self.str("<menclose notation=\"updiagonalstrike downdiagonalstrike\">");
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
            .cdlabel => |c| {
                // KaTeX `cdlabel` parity (pinned 0.18.7, issue #85):
                // `mstyle`/`mpadded`/`mrow` around the label group;
                // the left side overlaps (`lspace="-1width"`).
                self.str("<mstyle displaystyle=\"false\" scriptlevel=\"1\"><mpadded width=\"0\"");
                if (c.left) self.str(" lspace=\"-1width\"");
                self.str(" voffset=\"0.7em\"><mrow>");
                try self.node(c.body, face);
                self.str("</mrow></mpadded></mstyle>");
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
            .graphics => |g| {
                // KaTeX `includegraphics` mathmlBuilder (pinned
                // 0.18.7): `<mglyph alt valign? height width? src>`.
                // `valign`/`height` fold `totalheight` exactly like
                // the builder (`height` absorbs the depth); `width`
                // applies only when positive. Sizes format via
                // `makeEm` (`parse.fmtEm4`).
                self.str("<mglyph alt=\"");
                for (parse.toksOf(self.pc, g.alt)) |tk| self.graphicsTok(tk, false);
                self.str("\"");
                var nb: [16]u8 = undefined;
                if (g.th > 0) {
                    // Saturate the depth delta (absurd magnitudes
                    // only; clamped inputs cannot overflow i32).
                    const dd: i64 = @as(i64, g.h) - @as(i64, g.th);
                    const dc: i32 = @intCast(@min(@max(dd, -2000000000), 2000000000));
                    self.str(" valign=\"");
                    self.str(parse.fmtEm4(dc, &nb));
                    self.str("\"");
                }
                self.str(" height=\"");
                self.str(parse.fmtEm4(if (g.th > 0) g.th else g.h, &nb));
                self.str("\"");
                if (g.w > 0) {
                    self.str(" width=\"");
                    self.str(parse.fmtEm4(g.w, &nb));
                    self.str("\"");
                }
                self.str(" src=\"");
                for (parse.toksOf(self.pc, g.src)) |tk| self.graphicsTok(tk, true);
                self.str("\"></mglyph>");
            },
        }
        if (self.overflow) return error.NoSpace;
    }

    fn effFam(self: *Writer, face: Face, f: parse.FontFam) parse.FontFam {
        _ = self;
        return face.fam orelse f;
    }

    fn atom(self: *Writer, class: @import("symbols.zig").AtomClass, fam: parse.FontFam, c: u21, textord: bool, bare: bool) void {
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
                    // `\vdots` is a macro for `\varvdots\rule{0pt}{15pt}`
                    // (issue #109, pinned 0.18.7): the macro
                    // expansion is an ordgroup, so KaTeX wraps the
                    // textord leaf (`mi` with explicit normal) and
                    // the rule strut in an `mrow` of their own.
                    self.str("<mrow><mi mathvariant=\"normal\">");
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
                    // Directly-typed U+22EE funnels through KaTeX's
                    // `\vdots` macro (pinned 0.18.7, issue #109):
                    // ordgroup mrow around the textord mi and the
                    // rule strut, exactly like `\vdots` above.
                    self.str("<mrow><mi mathvariant=\"normal\">");
                    self.escCp(c);
                    self.str("</mi>");
                    self.str("<mpadded height=\"0em\" voffset=\"0em\">");
                    self.str("<mspace mathbackground=\"black\" width=\"0em\" height=\"1.5em\">");
                    self.str("</mspace></mpadded></mrow>");
                } else if (isDigit(c)) {
                    self.str("<mn>");
                    self.escCp(c);
                    self.str("</mn>");
                } else if (c == 0x2032) {
                    // `\prime`: KaTeX textord renders as mo WITH the
                    // variant (pinned 0.18.7 `<mo
                    // mathvariant="normal">`; symbolsOrd has no mo
                    // default, so it always emits). `\char"2032`
                    // shares this shape — KaTeX gives it `mi`, a
                    // nuance for a pathological input with no sweep
                    // row.
                    self.str("<mo mathvariant=\"normal\">");
                    self.escCp(c);
                    self.str("</mo>");
                } else if ((c == 0x0131 or c == 0x0237) and fam == .rm) {
                    // Dotless i/j with no explicit face carry an
                    // explicit normal variant (pinned 0.18.7: `<mi
                    // mathvariant="normal">ȷ</mi>`, while plain `j`
                    // stays bare). An explicit face wins (its wrapper
                    // supplies the variant), matching KaTeX's bold
                    // but bare-mathit shapes (issue #77).
                    self.str("<mi mathvariant=\"normal\">");
                    self.escCp(c);
                    self.str("</mi>");
                } else if (textord and bare) {
                    // KaTeX textord (issue #109, pinned 0.18.7
                    // symbolsOrd): `mi` with an explicit variant
                    // (normally "normal"; a face wrapper supplies its
                    // own instead, so faced atoms stay bare here).
                    self.str("<mi mathvariant=\"");
                    self.str(variantFor(fam));
                    self.str("\">");
                    self.escCp(c);
                    self.str("</mi>");
                } else {
                    // KaTeX mathord renders as mi unconditionally.
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
                self.str("<mo>&#x203E;</mo></mover>");
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
            .overset => try self.stackedOp(o.nucleus, o.extra, true, false, face),
            .underset => try self.stackedOp(o.nucleus, o.extra, false, false, face),
            .stackrel => try self.stackedOp(o.nucleus, o.extra, true, true, face),
            .xleft => try self.xarrow(0x2190, o, face),
            .xright => try self.xarrow(0x2192, o, face),
            .xboth => try self.xarrow(0x2194, o, face),
            .xhookleft => try self.xarrow(0x21A9, o, face),
            .xhookright => try self.xarrow(0x21AA, o, face),
            .xmapsto => try self.xarrow(0x21A6, o, face),
            .xtwoheadleft => try self.xarrow(0x219E, o, face),
            .xtwoheadright => try self.xarrow(0x21A0, o, face),
            .xdoubleleft => try self.xarrow(0x21D0, o, face),
            .xdoubleboth => try self.xarrow(0x21D4, o, face),
            .xdoubleright => try self.xarrow(0x21D2, o, face),
            .xleftharpoondown => try self.xarrow(0x21BD, o, face),
            .xleftharpoonup => try self.xarrow(0x21BC, o, face),
            .xleftrightharpoons => try self.xarrow(0x21CB, o, face),
            .xlongequal => try self.xarrow(0x003D, o, face),
            .xrightharpoondown => try self.xarrow(0x21C1, o, face),
            .xrightharpoonup => try self.xarrow(0x21C0, o, face),
            .xrightleftharpoons => try self.xarrow(0x21CC, o, face),
            .xtofrom => try self.xarrow(0x21C4, o, face),
            .overgroup => {
                self.str("<mover>");
                try self.node(o.nucleus, face);
                self.str("<mo>");
                self.cp(0x23E0);
                self.str("</mo></mover>");
            },
            .undergroup => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>");
                self.cp(0x23E1);
                self.str("</mo></munder>");
            },
            // Pinned 0.18.7 replicates an upstream quirk: the
            // linesegment accents have no MathML codepoint mapping,
            // so KaTeX emits the literal text `undefined`.
            .overlinesegment => {
                self.str("<mover>");
                try self.node(o.nucleus, face);
                self.str("<mo>undefined</mo></mover>");
            },
            .underlinesegment => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>undefined</mo></munder>");
            },
            .overleftharpoon => try self.arrowOver(o.nucleus, 0x21BC, face),
            .overrightharpoon => try self.arrowOver(o.nucleus, 0x21C0, face),
            .overRightarrow => try self.arrowOver(o.nucleus, 0x21D2, face),
            .underbar => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>");
                self.cp(0x203E);
                self.str("</mo></munder>");
            },
            .utilde => {
                self.str("<munder>");
                try self.node(o.nucleus, face);
                self.str("<mo>~</mo></munder>");
            },
            .angl => {
                // KaTeX parity (pinned 0.18.7): actuarial angle over
                // a text-scale body (the nucleus is a `.text` node,
                // so `node` supplies the inner `mtext` exactly).
                self.str("<menclose notation=\"actuarial\"><mstyle scriptlevel=\"0\" displaystyle=\"false\">");
                try self.node(o.nucleus, face);
                self.str("</mstyle></menclose>");
            },
        }
    }

    /// `\overset`/`\underset` (KaTeX parity): KaTeX desugars these to an
    /// op-with-body plus supsub inside an mclass, which renders as the
    /// base children wrapped flat in mo, stacked under/over the extra,
    /// and the whole thing wrapped in mi for Ord bases else mo
    /// (KaTeX `binrelClass`: only Bin/Rel bases stay mo).
    fn stackedOp(self: *Writer, nuc: Idx, extra: Idx, is_over: bool, force_rel: bool, face: Face) Error!void {
        const first: Idx = switch (parse.nodeAt(self.pc, nuc)) {
            .group => |g| blk: {
                const kids = parse.kidsOf(self.pc, g);
                break :blk if (kids.len > 0) kids[0] else nuc;
            },
            else => nuc,
        };
        // KaTeX parity: `\stackrel` forces the Rel wrapper
        // regardless of the base class (pinned 0.18.7
        // `functions/stacking.ts`); `\overset`/`\underset`
        // preserve it.
        const ord_base = !force_rel and switch (parse.nodeAt(self.pc, first)) {
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
            e.kind == .dcases or e.kind == .drcases or e.kind == .alignenv or
            e.kind == .alignat or e.kind == .equation or e.kind == .gather or
            e.kind == .split or e.kind == .cd;
        const script_cell = e.kind == .smallmatrix or e.kind == .subarray;
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
            // Numbering envs keep KaTeX's number columns: a leading
            // glue cell plus trailing glue and equation-number cells
            // per row (issues #83/#86/#87) — unless the row carries
            // `nonumber`/`notag` (#88). A tagged row keeps its
            // columns regardless: a row-local tag wins over the
            // row's own nonumber, and a leading outside-tag lands
            // on row 0 (even starred); the cells stay EMPTY either
            // way (tag text is dropped, #75).
            const numbered = parse.numEnvKind(e.kind) and
                ((e.numbered and !row.nonumber) or row.tagged);
            if (numbered) self.str("<mtd class=\"mtr-glue\"></mtd>");
            for (kids) |k| {
                self.str("<mtd><mstyle scriptlevel=\"");
                self.str(if (script_cell) "1" else "0");
                self.str("\" displaystyle=\"");
                self.str(if (disp_cell) "true" else "false");
                self.str("\">");
                try self.atStyle(cs, k, face);
                self.str("</mstyle></mtd>");
            }
            if (numbered) self.str("<mtd class=\"mtr-glue\"></mtd><mtd class=\"mml-eqn-num\"></mtd>");
            self.str("</mtr>");
        }
        self.str("</mtable>");
        if (script_cell) self.str("</mstyle>");
    }
};

/// The numbering env a hoisted tag wraps: when the tag formula is a
/// lone numbering env, KaTeX keeps the env's own table with EMPTY
/// number cells (issue #75). Returns the env node id, or null for
/// the full-width tag-table path.
fn tagNumEnv(pc: *const parse.ParseCtx, formula: Idx) ?Idx {
    const kid = switch (parse.nodeAt(pc, formula)) {
        .group => |g| blk: {
            const kids = parse.kidsOf(pc, g);
            if (kids.len != 1) return null;
            break :blk kids[0];
        },
        .env => formula,
        else => return null,
    };
    return switch (parse.nodeAt(pc, kid)) {
        .env => |e| if (parse.numEnvKind(e.kind)) kid else null,
        else => null,
    };
}

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
        .bolditalic => "bold-italic",
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

test "row-local tag keeps number cells despite nonumber (issue #75)" {
    // End-to-end shape (pinned 0.18.7): same-row tag + nonumber
    // keeps KaTeX's glue/eqn-num cells but the number cell stays
    // EMPTY (tag text is dropped over numbering envs); nonumber
    // alone drops the columns entirely.
    var pc = parse.ParseCtx.init("\\begin{align}x&=1\\tag{a}\\nonumber\\end{align}");
    const root = try parse.parse(&pc, true);
    var out: [1024]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "mtr-glue") != null);
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "mml-eqn-num") != null);
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "<mtext>") == null);
    var pc2 = parse.ParseCtx.init("\\begin{align}x&=1\\nonumber\\end{align}");
    const root2 = try parse.parse(&pc2, true);
    var out2: [1024]u8 = undefined;
    var w2 = Writer{ .pc = &pc2, .buf = &out2 };
    try w2.node(root2, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, out2[0..w2.pos], "mtr-glue") == null);
}

test "jmath and imath carry mathvariant normal like KaTeX (issue #77)" {
    // Pinned 0.18.7: `\jmath` → `<mi mathvariant="normal">ȷ</mi>`
    // (plain `j` stays bare `<mi>j</mi>`); an explicit face wins
    // (`\mathbf{\jmath}` → bold, `\mathit{\jmath}` → bare).
    var pc = parse.ParseCtx.init("\\jmath");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, out[0..w.pos], "<mi mathvariant=\"normal\">") != null);
    var pci = parse.ParseCtx.init("\\imath");
    const rooti = try parse.parse(&pci, false);
    var outi: [256]u8 = undefined;
    var wi = Writer{ .pc = &pci, .buf = &outi };
    try wi.node(rooti, .{ .fam = null, .script = false });
    try std.testing.expect(std.mem.indexOf(u8, outi[0..wi.pos], "<mi mathvariant=\"normal\">") != null);
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

test "kern mtext runs never merge, spacing runs do" {
    // KaTeX `kern` nodes build `SpaceNode`s (not `MathNode`s), so
    // `buildExpression` never folds them; `spacing`-origin NBSP
    // `mtext`s fold freely. The public `render` runs the merger.
    var out: [512]u8 = undefined;
    const kern = try render("\\>\\>", .{}, &out);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, kern, "<mtext>"));
    var out2: [512]u8 = undefined;
    const sp = try render("\\ \\ ", .{}, &out2);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, sp, "<mtext>"));
}

test "computed kern never aliases interword nbsp" {
    // `\mskip6mu` is 333-thousandths glue (`<mspace>`), not NBSP —
    // the value collision that motivated the `.nbsp` node split.
    var out: [256]u8 = undefined;
    const s = try render("\\mskip6mu", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mspace width=\"0.333em\"/>") != null);
    var out2: [256]u8 = undefined;
    const n = try render("\\ ", .{}, &out2);
    try std.testing.expect(std.mem.indexOf(u8, n, "<mtext>\xc2\xa0</mtext>") != null);
}

test "mu widths round to KaTeX SpaceNode buckets" {
    // 3mu = 0.1667em is a thin space: truncation gave 166
    // (`<mspace>`), rounding gives 167 (`space_thin`, `<mtext>`).
    var out: [256]u8 = undefined;
    const neg = try render("\\mkern-3mu", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, neg, "<mtext>\xe2\x80\x89\xe2\x81\xa3</mtext>") != null);
    var out2: [256]u8 = undefined;
    const pos = try render("\\mskip3mu", .{}, &out2);
    try std.testing.expect(std.mem.indexOf(u8, pos, "<mtext>\xe2\x80\x89</mtext>") != null);
}

test "colon builds the KaTeX macro composition" {
    // `\nobreak\mskip2mu\mathpunct{}\mathchoice{\mkern-3mu}…{:}\mskip6mu`
    // (KaTeX `macros.ts`), tag-identical to the pinned sweep row.
    var pc = parse.ParseCtx.init("\\colon");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mrow><mspace></mspace><mspace width=\"0.111em\"/><mo></mo><mtext>\xe2\x80\x89\xe2\x81\xa3</mtext><mo>:</mo><mspace width=\"0.333em\"/></mrow>", out[0..w.pos]);
}

test "mathpunct wraps in mo, empty body stays bare" {
    var pc = parse.ParseCtx.init("\\mathpunct{x}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mo>x</mo>", out[0..w.pos]);
    var pc2 = parse.ParseCtx.init("\\mathpunct{}");
    const root2 = try parse.parse(&pc2, false);
    var out2: [256]u8 = undefined;
    var w2 = Writer{ .pc = &pc2, .buf = &out2 };
    try w2.node(root2, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mo></mo>", out2[0..w2.pos]);
}

test "mathop always wraps, mathinner is mpadded" {
    // Pinned 0.18.7: `\mathop` is op-type (never a character box),
    // `\mathinner` a bare `mpadded` — both splice, never retype.
    var pc = parse.ParseCtx.init("\\mathop{x}");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mo><mi>x</mi></mo>", out[0..w.pos]);
    var pc2 = parse.ParseCtx.init("\\mathop{ab}");
    const root2 = try parse.parse(&pc2, false);
    var out2: [256]u8 = undefined;
    var w2 = Writer{ .pc = &pc2, .buf = &out2 };
    try w2.node(root2, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mo><mi>a</mi><mi>b</mi></mo>", out2[0..w2.pos]);
    var pc3 = parse.ParseCtx.init("\\mathinner{x}");
    const root3 = try parse.parse(&pc3, false);
    var out3: [256]u8 = undefined;
    var w3 = Writer{ .pc = &pc3, .buf = &out3 };
    try w3.node(root3, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mpadded><mi>x</mi></mpadded>", out3[0..w3.pos]);
}

test "vcentcolon nests triple mo, coloneqq is one op char" {
    // Pinned 0.18.7: `\vcentcolon` = `\mathrel{\mathop\ordinarycolon}`;
    // `\coloneqq` takes the `\html@mathml` MathML branch
    // `\mathop{\char"2254}` (U+2254 ≔).
    var pc = parse.ParseCtx.init("\\vcentcolon");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mo><mo><mo>:</mo></mo></mo>", out[0..w.pos]);
    var pc2 = parse.ParseCtx.init("\\coloneqq");
    const root2 = try parse.parse(&pc2, false);
    var out2: [256]u8 = undefined;
    var w2 = Writer{ .pc = &pc2, .buf = &out2 };
    try w2.node(root2, .{ .fam = null, .script = false });
    // Issue #109 (pinned 0.18.7 `<mo><mi
    // mathvariant="normal">≔</mi></mo>`): the inner `\char` is a
    // textord, so it carries the variant.
    try std.testing.expectEqualStrings("<mo><mi mathvariant=\"normal\">\xe2\x89\x94</mi></mo>", out2[0..w2.pos]);
}

test "char scans decimal octal hex and backtick" {
    // KaTeX `\char` forms: decimal, `'octal`, `"hex, backtick char.
    var pc = parse.ParseCtx.init("\\char\"2254");
    const root = try parse.parse(&pc, false);
    var out: [256]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    // Issue #109 (pinned 0.18.7 `<mi
    // mathvariant="normal">≔</mi>`): every `\char` result is a
    // textord, so it carries the variant.
    try std.testing.expectEqualStrings("<mi mathvariant=\"normal\">\xe2\x89\x94</mi>", out[0..w.pos]);
    var pc2 = parse.ParseCtx.init("\\char65\\char'101\\char`a\\@char{66}");
    const root2 = try parse.parse(&pc2, false);
    var out2: [256]u8 = undefined;
    var w2 = Writer{ .pc = &pc2, .buf = &out2 };
    try w2.node(root2, .{ .fam = null, .script = false });
    // Issue #109: pinned KaTeX 0.18.7 wraps `\char` output as
    // `<mi mathvariant="normal">…</mi>` (verified via KaTeX probe).
    try std.testing.expectEqualStrings("<mrow><mi mathvariant=\"normal\">A</mi><mi mathvariant=\"normal\">A</mi><mi mathvariant=\"normal\">a</mi><mi mathvariant=\"normal\">B</mi></mrow>", out2[0..w2.pos]);
}

test "char rejects bad digits and code points" {
    var pc = parse.ParseCtx.init("\\char\"ZZ");
    try std.testing.expectError(error.Invalid, parse.parse(&pc, false));
    var pc2 = parse.ParseCtx.init("\\char");
    try std.testing.expectError(error.Invalid, parse.parse(&pc2, false));
    var pc3 = parse.ParseCtx.init("\\char`");
    try std.testing.expectError(error.Invalid, parse.parse(&pc3, false));
    var pc4 = parse.ParseCtx.init("\\@char{abc}");
    try std.testing.expectError(error.Invalid, parse.parse(&pc4, false));
    var pc5 = parse.ParseCtx.init("\\@char{99999999}");
    try std.testing.expectError(error.Invalid, parse.parse(&pc5, false));
    var pc6 = parse.ParseCtx.init("\\char\"110000");
    try std.testing.expectError(error.Invalid, parse.parse(&pc6, false));
}

test "phantoms smash through an mpadded shell, kids spliced" {
    // `\hphantom` is `\smash{\phantom{…}}` and `\vphantom` zeroes
    // the width (KaTeX `phantom.ts` pins); bodies splice without
    // an `mrow`, like `buildExpression`.
    var pc = parse.ParseCtx.init("a\\hphantom{bc}d");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mrow><mi>a</mi><mpadded height=\"0px\" depth=\"0px\"><mphantom><mi>b</mi><mi>c</mi></mphantom></mpadded><mi>d</mi></mrow>", out[0..w.pos]);
    var pc2 = parse.ParseCtx.init("\\vphantom{bc}");
    const root2 = try parse.parse(&pc2, false);
    var out2: [512]u8 = undefined;
    var w2 = Writer{ .pc = &pc2, .buf = &out2 };
    try w2.node(root2, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mpadded width=\"0px\"><mphantom><mi>b</mi><mi>c</mi></mphantom></mpadded>", out2[0..w2.pos]);
    var pc3 = parse.ParseCtx.init("\\phantom{bc}");
    const root3 = try parse.parse(&pc3, false);
    var out3: [512]u8 = undefined;
    var w3 = Writer{ .pc = &pc3, .buf = &out3 };
    try w3.node(root3, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<mphantom><mi>b</mi><mi>c</mi></mphantom>", out3[0..w3.pos]);
}

test "fbox frames a text hbox under one mstyle" {
    var pc = parse.ParseCtx.init("\\fbox{Hi}");
    const root = try parse.parse(&pc, false);
    var out: [512]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    try std.testing.expectEqualStrings("<menclose notation=\"box\"><mstyle scriptlevel=\"0\" displaystyle=\"false\"><mtext>Hi</mtext></mstyle></menclose>", out[0..w.pos]);
}

test "copyright and logos emit their KaTeX math-branch text" {
    // `\copyright` is `\text{\textcopyright}` observably;
    // the logos are `\textrm` + `\html@mathml{<html>}{<name>}`.
    for ([_][2][]const u8{
        .{ "\\copyright", "<mtext>\xc2\xa9</mtext>" },
        .{ "\\KaTeX", "<mtext>KaTeX</mtext>" },
        .{ "\\LaTeX", "<mtext>LaTeX</mtext>" },
        .{ "\\TeX", "<mtext>TeX</mtext>" },
    }) |c| {
        var pc = parse.ParseCtx.init(c[0]);
        const root = try parse.parse(&pc, false);
        var out: [256]u8 = undefined;
        var w = Writer{ .pc = &pc, .buf = &out };
        try w.node(root, .{ .fam = null, .script = false });
        try std.testing.expectEqualStrings(c[1], out[0..w.pos]);
    }
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
    // Issue #109 (pinned 0.18.7 `<mi mathvariant="normal">∞</mi>`,
    // `<mi mathvariant="normal">∀</mi>`): textords carry the variant.
    var pc = parse.ParseCtx.init("\\infty+\\forall\\vdots");
    const root = try parse.parse(&pc, false);
    var out: [1024]u8 = undefined;
    var w = Writer{ .pc = &pc, .buf = &out };
    try w.node(root, .{ .fam = null, .script = false });
    const s = out[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, s, "<mi mathvariant=\"normal\">\xe2\x88\x9e</mi>") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "<mi mathvariant=\"normal\">\xe2\x88\x80</mi>") != null);
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

test "color and style rests stop at over infixes" {
    // Issue #110 (pinned 0.18.7): declaration rests split at the
    // infix like the #94 font rest — numerator only, denominator
    // plain — braced or not. Size declarations keep consuming
    // through (whole frac), unchanged.
    var out: [512]u8 = undefined;
    const c = try render("\\color{red}a\\over b", .{}, &out);
    try std.testing.expectEqualStrings("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><semantics><mrow><mfrac><mstyle mathcolor=\"red\"><mi>a</mi></mstyle><mi>b</mi></mfrac></mrow><annotation encoding=\"application/x-tex\">\\color{red}a\\over b</annotation></semantics></math>", c);
    var out2: [512]u8 = undefined;
    const cb = try render("{\\color{red}a\\over b}", .{}, &out2);
    try std.testing.expectEqualStrings("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><semantics><mrow><mfrac><mstyle mathcolor=\"red\"><mi>a</mi></mstyle><mi>b</mi></mfrac></mrow><annotation encoding=\"application/x-tex\">{\\color{red}a\\over b}</annotation></semantics></math>", cb);
    var out3: [512]u8 = undefined;
    const d = try render("\\displaystyle a\\over b", .{}, &out3);
    try std.testing.expectEqualStrings("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><semantics><mrow><mfrac><mstyle displaystyle=\"true\"><mi>a</mi></mstyle><mi>b</mi></mfrac></mrow><annotation encoding=\"application/x-tex\">\\displaystyle a\\over b</annotation></semantics></math>", d);
}

test "cancel directions match KaTeX menclose notations" {
    // Issue #107 (pinned 0.18.7): `\cancel` strikes up, `\bcancel`
    // down (it used to alias `\cancel` and serialize up), `\xcancel`
    // both.
    var out: [512]u8 = undefined;
    const c = try render("\\cancel{x}", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, c, "<menclose notation=\"updiagonalstrike\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "downdiagonalstrike") == null);
    var out2: [512]u8 = undefined;
    const b = try render("\\bcancel{x}", .{}, &out2);
    try std.testing.expect(std.mem.indexOf(u8, b, "<menclose notation=\"downdiagonalstrike\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, b, "updiagonalstrike") == null);
    var out3: [512]u8 = undefined;
    const x = try render("\\xcancel{x}", .{}, &out3);
    try std.testing.expect(std.mem.indexOf(u8, x, "<menclose notation=\"updiagonalstrike downdiagonalstrike\">") != null);
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
            // Issue #109 (pinned 0.18.7 `<mi
            // mathvariant="normal">¬</mi>`): `\lnot` is a textord.
            "<mi mathvariant=\"normal\">\u{ac}</mi><mo>\u{22d8}</mo>" ++
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

test "semantics annotation carries the raw source (issue #119)" {
    // Pinned 0.18.7 bytes (KaTeX `renderToString(..., {output:
    // 'mathml'})`; same bytes sit in `goldens/katex_sweep.json`):
    // the body wraps in `<semantics>` and the raw source lands in
    // the `application/x-tex` annotation, XML-escaped.
    var out: [1024]u8 = undefined;
    const s = try render("x^2", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, s, "<semantics><mrow>") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        s,
        "<annotation encoding=\"application/x-tex\">x^2</annotation>",
    ) != null);
    try std.testing.expect(std.mem.endsWith(u8, s, "</semantics></math>"));
    var out2: [1024]u8 = undefined;
    const s2 = try render("\\frac{1}{2}", .{}, &out2);
    try std.testing.expect(std.mem.indexOf(
        u8,
        s2,
        "<annotation encoding=\"application/x-tex\">\\frac{1}{2}</annotation>",
    ) != null);
    var out3: [1024]u8 = undefined;
    const s3 = try render("x<y>z", .{}, &out3);
    try std.testing.expect(std.mem.indexOf(
        u8,
        s3,
        "<annotation encoding=\"application/x-tex\">x&lt;y&gt;z</annotation>",
    ) != null);
}

test "href target escapes like KaTeX utils.escape (issue #123)" {
    // Pinned 0.18.7 (`renderToString(..., {trust: true})`):
    // `\href{a<b>"c&d}{x}` → `href="a&lt;b&gt;&quot;c&amp;d"`,
    // `'` → `&#x27;`, non-ASCII passes through (never dropped),
    // `\%`-style controls unescape, unknown controls keep the
    // backslash.
    var out: [1024]u8 = undefined;
    const s = try render("\\href{a<b>\"c&d}{x}", .{}, &out);
    try std.testing.expect(std.mem.indexOf(u8, s, "href=\"a&lt;b&gt;&quot;c&amp;d\"") != null);
    var out2: [1024]u8 = undefined;
    const s2 = try render("\\href{a'b}{x}", .{}, &out2);
    try std.testing.expect(std.mem.indexOf(u8, s2, "href=\"a&#x27;b\"") != null);
    var out3: [1024]u8 = undefined;
    const s3 = try render("\\href{é}{x}", .{}, &out3);
    try std.testing.expect(std.mem.indexOf(u8, s3, "href=\"\xc3\xa9\"") != null);
    var out4: [1024]u8 = undefined;
    const s4 = try render("\\href{a\\%b\\_c}{x}", .{}, &out4);
    try std.testing.expect(std.mem.indexOf(u8, s4, "href=\"a%b_c\"") != null);
}
