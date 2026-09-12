//! MaTeX symbol tables: KaTeX support-table coverage for the core.
//!
//! Maps control-sequence names to Unicode codepoints plus TeX atom
//! classes (Ord/Op/Bin/Rel/Open/Close/Punct/Inner). The core positions
//! atoms with `glueBetween`; hosts resolve glyphs via the provider, so
//! these tables carry no font data.

/// TeX atom classes. Spacing between adjacent atoms derives from the
/// pair of classes (see `glueBetween`), matching TeX Book p.170 with
/// KaTeX's observable behavior.
pub const AtomClass = enum {
    Ord,
    Op,
    Bin,
    Rel,
    Open,
    Close,
    Punct,
    Inner,
};

/// One named symbol: its codepoint, atom class, and operator flags.
pub const Sym = struct {
    cp: u21,
    class: AtomClass,
    /// Large operator (sums, integrals): display sizing + limit rules.
    large_op: bool = false,
    /// Upright function name (`\sin`): set in roman, Op spacing.
    func: bool = false,
    /// Default limit placement for large operators.
    limits_default: bool = false,
};

const Entry = struct {
    name: []const u8,
    sym: Sym,
};

fn S(cp: u21, class: AtomClass) Sym {
    return .{ .cp = cp, .class = class };
}
fn L(cp: u21) Sym {
    return .{ .cp = cp, .class = .Op, .large_op = true, .limits_default = true };
}
fn I(cp: u21) Sym {
    return .{ .cp = cp, .class = .Op, .large_op = true, .limits_default = false };
}
fn F(cp: u21) Sym {
    return .{ .cp = cp, .class = .Op, .func = true };
}

/// Lowercase Greek. `\varepsilon` et al are variant forms, same class.
const greek_lower: []const Entry = &.{
    .{ .name = "alpha", .sym = S(0x03B1, .Ord) },
    .{ .name = "beta", .sym = S(0x03B2, .Ord) },
    .{ .name = "gamma", .sym = S(0x03B3, .Ord) },
    .{ .name = "delta", .sym = S(0x03B4, .Ord) },
    .{ .name = "epsilon", .sym = S(0x03F5, .Ord) },
    .{ .name = "varepsilon", .sym = S(0x03B5, .Ord) },
    .{ .name = "zeta", .sym = S(0x03B6, .Ord) },
    .{ .name = "eta", .sym = S(0x03B7, .Ord) },
    .{ .name = "theta", .sym = S(0x03B8, .Ord) },
    .{ .name = "vartheta", .sym = S(0x03D1, .Ord) },
    .{ .name = "iota", .sym = S(0x03B9, .Ord) },
    .{ .name = "kappa", .sym = S(0x03BA, .Ord) },
    .{ .name = "lambda", .sym = S(0x03BB, .Ord) },
    .{ .name = "mu", .sym = S(0x03BC, .Ord) },
    .{ .name = "nu", .sym = S(0x03BD, .Ord) },
    .{ .name = "xi", .sym = S(0x03BE, .Ord) },
    .{ .name = "pi", .sym = S(0x03C0, .Ord) },
    .{ .name = "varpi", .sym = S(0x03D6, .Ord) },
    .{ .name = "rho", .sym = S(0x03C1, .Ord) },
    .{ .name = "varrho", .sym = S(0x03F1, .Ord) },
    .{ .name = "sigma", .sym = S(0x03C3, .Ord) },
    .{ .name = "varsigma", .sym = S(0x03C2, .Ord) },
    .{ .name = "tau", .sym = S(0x03C4, .Ord) },
    .{ .name = "upsilon", .sym = S(0x03C5, .Ord) },
    .{ .name = "phi", .sym = S(0x03D5, .Ord) },
    .{ .name = "varphi", .sym = S(0x03C6, .Ord) },
    .{ .name = "chi", .sym = S(0x03C7, .Ord) },
    .{ .name = "psi", .sym = S(0x03C8, .Ord) },
    .{ .name = "omega", .sym = S(0x03C9, .Ord) },
};

const greek_upper: []const Entry = &.{
    .{ .name = "Alpha", .sym = S(0x0391, .Ord) },
    .{ .name = "Beta", .sym = S(0x0392, .Ord) },
    .{ .name = "Gamma", .sym = S(0x0393, .Ord) },
    .{ .name = "Delta", .sym = S(0x0394, .Ord) },
    .{ .name = "Epsilon", .sym = S(0x0395, .Ord) },
    .{ .name = "Zeta", .sym = S(0x0396, .Ord) },
    .{ .name = "Eta", .sym = S(0x0397, .Ord) },
    .{ .name = "Theta", .sym = S(0x0398, .Ord) },
    .{ .name = "Iota", .sym = S(0x0399, .Ord) },
    .{ .name = "Kappa", .sym = S(0x039A, .Ord) },
    .{ .name = "Lambda", .sym = S(0x039B, .Ord) },
    .{ .name = "Mu", .sym = S(0x039C, .Ord) },
    .{ .name = "Nu", .sym = S(0x039D, .Ord) },
    .{ .name = "Xi", .sym = S(0x039E, .Ord) },
    .{ .name = "Pi", .sym = S(0x03A0, .Ord) },
    .{ .name = "Rho", .sym = S(0x03A1, .Ord) },
    .{ .name = "Sigma", .sym = S(0x03A3, .Ord) },
    .{ .name = "Tau", .sym = S(0x03A4, .Ord) },
    .{ .name = "Upsilon", .sym = S(0x03A5, .Ord) },
    .{ .name = "Phi", .sym = S(0x03A6, .Ord) },
    .{ .name = "Chi", .sym = S(0x03A7, .Ord) },
    .{ .name = "Psi", .sym = S(0x03A8, .Ord) },
    .{ .name = "Omega", .sym = S(0x03A9, .Ord) },
    .{ .name = "digamma", .sym = S(0x03DC, .Ord) },
};

const operators: []const Entry = &.{
    // Large operators with limits by default.
    .{ .name = "sum", .sym = L(0x2211) },
    .{ .name = "prod", .sym = L(0x220F) },
    .{ .name = "coprod", .sym = L(0x2210) },
    .{ .name = "bigcup", .sym = L(0x22C3) },
    .{ .name = "bigcap", .sym = L(0x22C2) },
    .{ .name = "bigvee", .sym = L(0x22C1) },
    .{ .name = "bigwedge", .sym = L(0x22C0) },
    .{ .name = "bigoplus", .sym = L(0x2A01) },
    .{ .name = "bigotimes", .sym = L(0x2A02) },
    .{ .name = "bigodot", .sym = L(0x2A00) },
    .{ .name = "biguplus", .sym = L(0x2A04) },
    .{ .name = "lim", .sym = L(0x6C) }, // "lim" set as text, cp unused
    // Large operators without limits by default.
    .{ .name = "int", .sym = I(0x222B) },
    .{ .name = "iint", .sym = I(0x222C) },
    .{ .name = "iiint", .sym = I(0x222D) },
    .{ .name = "oint", .sym = I(0x222E) },
    // Limit-style function names (limits by default, never large).
    .{ .name = "sup", .sym = .{ .cp = 0x73, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "inf", .sym = .{ .cp = 0x69, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "max", .sym = .{ .cp = 0x6D, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "min", .sym = .{ .cp = 0x6D, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "limsup", .sym = .{ .cp = 0x6C, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "liminf", .sym = .{ .cp = 0x6C, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "det", .sym = .{ .cp = 0x64, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "gcd", .sym = .{ .cp = 0x67, .class = .Op, .func = true, .limits_default = true } },
    .{ .name = "Pr", .sym = .{ .cp = 0x50, .class = .Op, .func = true, .limits_default = true } },
    // Upright function names.
    .{ .name = "sin", .sym = F(0x73) },
    .{ .name = "cos", .sym = F(0x63) },
    .{ .name = "tan", .sym = F(0x74) },
    .{ .name = "sec", .sym = F(0x73) },
    .{ .name = "csc", .sym = F(0x63) },
    .{ .name = "cot", .sym = F(0x63) },
    .{ .name = "arcsin", .sym = F(0x61) },
    .{ .name = "arccos", .sym = F(0x61) },
    .{ .name = "arctan", .sym = F(0x61) },
    .{ .name = "sinh", .sym = F(0x73) },
    .{ .name = "cosh", .sym = F(0x63) },
    .{ .name = "tanh", .sym = F(0x74) },
    .{ .name = "coth", .sym = F(0x63) },
    .{ .name = "log", .sym = F(0x6C) },
    .{ .name = "ln", .sym = F(0x6C) },
    .{ .name = "lg", .sym = F(0x6C) },
    .{ .name = "exp", .sym = F(0x65) },
    .{ .name = "dim", .sym = F(0x64) },
    .{ .name = "ker", .sym = F(0x6B) },
    .{ .name = "deg", .sym = F(0x64) },
    .{ .name = "arg", .sym = F(0x61) },
    .{ .name = "hom", .sym = F(0x68) },
    // Binary operators.
    .{ .name = "pm", .sym = S(0x00B1, .Bin) },
    .{ .name = "mp", .sym = S(0x2213, .Bin) },
    .{ .name = "times", .sym = S(0x00D7, .Bin) },
    .{ .name = "div", .sym = S(0x00F7, .Bin) },
    .{ .name = "cdot", .sym = S(0x22C5, .Bin) },
    .{ .name = "ast", .sym = S(0x2217, .Bin) },
    .{ .name = "star", .sym = S(0x22C6, .Bin) },
    .{ .name = "circ", .sym = S(0x2218, .Bin) },
    .{ .name = "bullet", .sym = S(0x2219, .Bin) },
    .{ .name = "cap", .sym = S(0x2229, .Bin) },
    .{ .name = "cup", .sym = S(0x222A, .Bin) },
    .{ .name = "vee", .sym = S(0x2228, .Bin) },
    .{ .name = "wedge", .sym = S(0x2227, .Bin) },
    .{ .name = "oplus", .sym = S(0x2295, .Bin) },
    .{ .name = "ominus", .sym = S(0x2296, .Bin) },
    .{ .name = "otimes", .sym = S(0x2297, .Bin) },
    .{ .name = "oslash", .sym = S(0x2298, .Bin) },
    .{ .name = "odot", .sym = S(0x2299, .Bin) },
    .{ .name = "dagger", .sym = S(0x2020, .Bin) },
    .{ .name = "ddagger", .sym = S(0x2021, .Bin) },
    .{ .name = "amalg", .sym = S(0x2A3F, .Bin) },
    .{ .name = "setminus", .sym = S(0x2216, .Bin) },
    .{ .name = "wr", .sym = S(0x2240, .Bin) },
    .{ .name = "diamond", .sym = S(0x22C4, .Bin) },
    .{ .name = "bigtriangleup", .sym = S(0x25B3, .Bin) },
    .{ .name = "bigtriangledown", .sym = S(0x25BD, .Bin) },
    .{ .name = "triangleleft", .sym = S(0x25C1, .Bin) },
    .{ .name = "triangleright", .sym = S(0x25B7, .Bin) },
    .{ .name = "lhd", .sym = S(0x22B2, .Bin) },
    .{ .name = "rhd", .sym = S(0x22B3, .Bin) },
    .{ .name = "unlhd", .sym = S(0x22B4, .Bin) },
    .{ .name = "unrhd", .sym = S(0x22B5, .Bin) },
    .{ .name = "uplus", .sym = S(0x228E, .Bin) },
    .{ .name = "sqcap", .sym = S(0x2293, .Bin) },
    .{ .name = "sqcup", .sym = S(0x2294, .Bin) },
    .{ .name = "cdotp", .sym = S(0x00B7, .Bin) },
    .{ .name = "centerdot", .sym = S(0x00B7, .Bin) },
    .{ .name = "land", .sym = S(0x2227, .Bin) },
    .{ .name = "lor", .sym = S(0x2228, .Bin) },
    .{ .name = "boxplus", .sym = S(0x229E, .Bin) },
    .{ .name = "boxtimes", .sym = S(0x22A0, .Bin) },
    .{ .name = "boxminus", .sym = S(0x229F, .Bin) },
    .{ .name = "boxdot", .sym = S(0x22A1, .Bin) },
    // Relations.
    .{ .name = "leq", .sym = S(0x2264, .Rel) },
    .{ .name = "le", .sym = S(0x2264, .Rel) },
    .{ .name = "geq", .sym = S(0x2265, .Rel) },
    .{ .name = "ge", .sym = S(0x2265, .Rel) },
    .{ .name = "neq", .sym = S(0x2260, .Rel) },
    .{ .name = "ne", .sym = S(0x2260, .Rel) },
    .{ .name = "equiv", .sym = S(0x2261, .Rel) },
    .{ .name = "approx", .sym = S(0x2248, .Rel) },
    .{ .name = "simeq", .sym = S(0x2243, .Rel) },
    .{ .name = "sim", .sym = S(0x223C, .Rel) },
    .{ .name = "cong", .sym = S(0x2245, .Rel) },
    .{ .name = "asymp", .sym = S(0x224D, .Rel) },
    .{ .name = "doteq", .sym = S(0x2250, .Rel) },
    .{ .name = "propto", .sym = S(0x221D, .Rel) },
    .{ .name = "models", .sym = S(0x22A7, .Rel) },
    .{ .name = "in", .sym = S(0x2208, .Rel) },
    .{ .name = "ni", .sym = S(0x220B, .Rel) },
    .{ .name = "owns", .sym = S(0x220B, .Rel) },
    .{ .name = "subset", .sym = S(0x2282, .Rel) },
    .{ .name = "supset", .sym = S(0x2283, .Rel) },
    .{ .name = "subseteq", .sym = S(0x2286, .Rel) },
    .{ .name = "supseteq", .sym = S(0x2287, .Rel) },
    .{ .name = "sqsubset", .sym = S(0x228F, .Rel) },
    .{ .name = "sqsupset", .sym = S(0x2290, .Rel) },
    .{ .name = "sqsubseteq", .sym = S(0x2291, .Rel) },
    .{ .name = "sqsupseteq", .sym = S(0x2292, .Rel) },
    .{ .name = "mid", .sym = S(0x2223, .Rel) },
    .{ .name = "parallel", .sym = S(0x2225, .Rel) },
    .{ .name = "nmid", .sym = S(0x2224, .Rel) },
    .{ .name = "perp", .sym = S(0x22A5, .Rel) },
    .{ .name = "vdash", .sym = S(0x22A2, .Rel) },
    .{ .name = "dashv", .sym = S(0x22A3, .Rel) },
    .{ .name = "prec", .sym = S(0x227A, .Rel) },
    .{ .name = "succ", .sym = S(0x227B, .Rel) },
    .{ .name = "preceq", .sym = S(0x227C, .Rel) },
    .{ .name = "succeq", .sym = S(0x227D, .Rel) },
    .{ .name = "ll", .sym = S(0x226A, .Rel) },
    .{ .name = "gg", .sym = S(0x226B, .Rel) },
    .{ .name = "lll", .sym = S(0x22D8, .Rel) },
    .{ .name = "ggg", .sym = S(0x22D9, .Rel) },
    .{ .name = "subsetneq", .sym = S(0x228A, .Rel) },
    .{ .name = "supsetneq", .sym = S(0x228B, .Rel) },
    .{ .name = "approxeq", .sym = S(0x224A, .Rel) },
    .{ .name = "eqcirc", .sym = S(0x2256, .Rel) },
    .{ .name = "lesssim", .sym = S(0x2272, .Rel) },
    .{ .name = "gtrsim", .sym = S(0x2273, .Rel) },
    .{ .name = "lessapprox", .sym = S(0x2A85, .Rel) },
    .{ .name = "gtrapprox", .sym = S(0x2A86, .Rel) },
    .{ .name = "bowtie", .sym = S(0x22C8, .Rel) },
    .{ .name = "frown", .sym = S(0x2322, .Rel) },
    .{ .name = "smile", .sym = S(0x2323, .Rel) },
    .{ .name = "Join", .sym = S(0x22C8, .Rel) },
    // Arrows (relations).
    .{ .name = "to", .sym = S(0x2192, .Rel) },
    .{ .name = "gets", .sym = S(0x2190, .Rel) },
    .{ .name = "leftarrow", .sym = S(0x2190, .Rel) },
    .{ .name = "rightarrow", .sym = S(0x2192, .Rel) },
    .{ .name = "Leftarrow", .sym = S(0x21D0, .Rel) },
    .{ .name = "Rightarrow", .sym = S(0x21D2, .Rel) },
    .{ .name = "leftrightarrow", .sym = S(0x2194, .Rel) },
    .{ .name = "Leftrightarrow", .sym = S(0x21D4, .Rel) },
    .{ .name = "mapsto", .sym = S(0x21A6, .Rel) },
    .{ .name = "longleftarrow", .sym = S(0x27F5, .Rel) },
    .{ .name = "longrightarrow", .sym = S(0x27F6, .Rel) },
    .{ .name = "Longleftarrow", .sym = S(0x27F8, .Rel) },
    .{ .name = "Longrightarrow", .sym = S(0x27F9, .Rel) },
    .{ .name = "longleftrightarrow", .sym = S(0x27F7, .Rel) },
    .{ .name = "Longleftrightarrow", .sym = S(0x27FA, .Rel) },
    .{ .name = "hookleftarrow", .sym = S(0x21A9, .Rel) },
    .{ .name = "hookrightarrow", .sym = S(0x21AA, .Rel) },
    .{ .name = "leftharpoonup", .sym = S(0x21BC, .Rel) },
    .{ .name = "rightharpoonup", .sym = S(0x21C0, .Rel) },
    .{ .name = "leftharpoondown", .sym = S(0x21BD, .Rel) },
    .{ .name = "rightharpoondown", .sym = S(0x21C1, .Rel) },
    .{ .name = "rightleftharpoons", .sym = S(0x21CC, .Rel) },
    .{ .name = "uparrow", .sym = S(0x2191, .Rel) },
    .{ .name = "downarrow", .sym = S(0x2193, .Rel) },
    .{ .name = "updownarrow", .sym = S(0x2195, .Rel) },
    .{ .name = "Uparrow", .sym = S(0x21D1, .Rel) },
    .{ .name = "Downarrow", .sym = S(0x21D3, .Rel) },
    .{ .name = "Updownarrow", .sym = S(0x21D5, .Rel) },
    .{ .name = "nearrow", .sym = S(0x2197, .Rel) },
    .{ .name = "searrow", .sym = S(0x2198, .Rel) },
    .{ .name = "swarrow", .sym = S(0x2199, .Rel) },
    .{ .name = "nwarrow", .sym = S(0x2196, .Rel) },
    // Punctuation / misc ords.
    .{ .name = "infty", .sym = S(0x221E, .Ord) },
    .{ .name = "nabla", .sym = S(0x2207, .Ord) },
    .{ .name = "partial", .sym = S(0x2202, .Ord) },
    .{ .name = "angle", .sym = S(0x2220, .Ord) },
    .{ .name = "measuredangle", .sym = S(0x2221, .Ord) },
    .{ .name = "sphericalangle", .sym = S(0x2222, .Ord) },
    .{ .name = "forall", .sym = S(0x2200, .Ord) },
    .{ .name = "exists", .sym = S(0x2203, .Ord) },
    .{ .name = "nexists", .sym = S(0x2204, .Ord) },
    .{ .name = "neg", .sym = S(0x00AC, .Ord) },
    .{ .name = "lnot", .sym = S(0x00AC, .Ord) },
    .{ .name = "top", .sym = S(0x22A4, .Ord) },
    .{ .name = "bot", .sym = S(0x22A5, .Ord) },
    .{ .name = "emptyset", .sym = S(0x2205, .Ord) },
    .{ .name = "varnothing", .sym = S(0x2205, .Ord) },
    .{ .name = "aleph", .sym = S(0x2135, .Ord) },
    .{ .name = "beth", .sym = S(0x2136, .Ord) },
    .{ .name = "gimel", .sym = S(0x2137, .Ord) },
    .{ .name = "daleth", .sym = S(0x2138, .Ord) },
    .{ .name = "hbar", .sym = S(0x210F, .Ord) },
    .{ .name = "hslash", .sym = S(0x210F, .Ord) },
    .{ .name = "imath", .sym = S(0x0131, .Ord) },
    .{ .name = "jmath", .sym = S(0x0237, .Ord) },
    .{ .name = "ell", .sym = S(0x2113, .Ord) },
    .{ .name = "wp", .sym = S(0x2118, .Ord) },
    .{ .name = "Re", .sym = S(0x211C, .Ord) },
    .{ .name = "Im", .sym = S(0x2111, .Ord) },
    .{ .name = "mho", .sym = S(0x2127, .Ord) },
    .{ .name = "Finv", .sym = S(0x2132, .Ord) },
    .{ .name = "Game", .sym = S(0x2141, .Ord) },
    .{ .name = "surd", .sym = S(0x221A, .Ord) },
    .{ .name = "prime", .sym = S(0x2032, .Ord) },
    .{ .name = "backprime", .sym = S(0x2035, .Ord) },
    .{ .name = "eth", .sym = S(0x00F0, .Ord) },
    .{ .name = "clubsuit", .sym = S(0x2663, .Ord) },
    .{ .name = "diamondsuit", .sym = S(0x2662, .Ord) },
    .{ .name = "heartsuit", .sym = S(0x2661, .Ord) },
    .{ .name = "spadesuit", .sym = S(0x2660, .Ord) },
    .{ .name = "sharp", .sym = S(0x266F, .Ord) },
    .{ .name = "flat", .sym = S(0x266D, .Ord) },
    .{ .name = "natural", .sym = S(0x266E, .Ord) },
    .{ .name = "checkmark", .sym = S(0x2713, .Ord) },
    .{ .name = "circledR", .sym = S(0x00AE, .Ord) },
    .{ .name = "circledS", .sym = S(0x24C8, .Ord) },
    .{ .name = "maltese", .sym = S(0x2720, .Ord) },
    .{ .name = "S", .sym = S(0x00A7, .Ord) },
    .{ .name = "P", .sym = S(0x00B6, .Ord) },
    .{ .name = "pounds", .sym = S(0x00A3, .Ord) },
    .{ .name = "yen", .sym = S(0x00A5, .Ord) },
    .{ .name = "copyright", .sym = S(0x00A9, .Ord) },
    .{ .name = "textregistered", .sym = S(0x00AE, .Ord) },
    .{ .name = "dots", .sym = S(0x2026, .Inner) },
    .{ .name = "ldots", .sym = S(0x2026, .Inner) },
    .{ .name = "cdots", .sym = S(0x22EF, .Inner) },
    .{ .name = "vdots", .sym = S(0x22EE, .Inner) },
    .{ .name = "ddots", .sym = S(0x22F1, .Inner) },
    .{ .name = "colon", .sym = S(0x003A, .Punct) },
    .{ .name = "ldotp", .sym = S(0x002E, .Punct) },
    .{ .name = "cdotp", .sym = S(0x00B7, .Punct) },
};

/// ASCII characters with fixed atom classes.
pub fn asciiClass(cp: u21) ?AtomClass {
    return switch (cp) {
        '+' => .Bin,
        '-' => .Bin,
        '*' => .Bin,
        '=' => .Rel,
        '<' => .Rel,
        '>' => .Rel,
        '(' => .Open,
        '[' => .Open,
        ')' => .Close,
        ']' => .Close,
        ',' => .Punct,
        ';' => .Punct,
        '?' => .Close, // KaTeX: ? is Close? TeX treats ? as Close. Yes.
        '!' => .Close, // TeX: ! is Close.
        ':' => .Rel, // TeX mathcode: : is Rel.
        '|' => .Ord, // KaTeX: | is Ord (use \vert/\mid for rel/delim).
        '.' => .Ord,
        '/' => .Ord,
        else => null,
    };
}

/// Look up a control-sequence name. Returns null for unknown names
/// (callers report KaTeX-parity `Invalid`).
pub fn lookup(name: []const u8) ?Sym {
    for (greek_lower) |e| if (eq(e.name, name)) return e.sym;
    for (greek_upper) |e| if (eq(e.name, name)) return e.sym;
    for (operators) |e| if (eq(e.name, name)) return e.sym;
    return null;
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

/// Glue between two adjacent atoms, in 1/1000-em units at size 1000.
/// TeX Book p.170: thin (3mu) / med (4mu) / thick (5mu); no space in
/// script styles (KaTeX keeps thin in scripts? KaTeX applies spacing
/// in all styles — keep uniform, document).
/// 1mu = 1/18 em: thin=167, med=222, thick=278.
pub fn glueBetween(left: AtomClass, right: AtomClass) u16 {
    // No space involving Ord-Ord, Op-Op, etc. by default.
    const thick: u16 = 278; // 5mu
    const med: u16 = 222; // 4mu
    const thin: u16 = 167; // 3mu
    // Rel pairs with anything (except nothing pairs): thick.
    if (left == .Rel or right == .Rel) {
        // TeX excludes some Rel pairs? No: Rel-* and *-Rel are thick
        // except when the other side cannot take space (Open/Close/
        // Punct handled below per TeX: no space between Rel and
        // Open? Actually TeX table: Rel-Open IS thick? TeX Book: space
        // is inserted unless in the "no space" list: Ord-Op? Let me
        // encode the standard no-space exceptions explicitly.
        if (left == .Open or right == .Close or left == .Punct or right == .Punct) {
            // TeX: (Rel,Open)? The table row Rel: columns Ord Op Bin
            // Rel Open Close Punct Inner = thick thick * thick thick
            // thick 0 thick. So Rel-Close and Rel-Punct get space!
            // Only Punct on the left or ... row Punct: all 0.
            if (left == .Punct) return 0;
            if (right == .Punct and left != .Rel) return 0;
            return thick;
        }
        return thick;
    }
    if (left == .Punct or right == .Punct) return 0;
    if (left == .Open or right == .Close) return 0;
    if (left == .Bin or right == .Bin) {
        // Bin-Op, Bin-Inner etc: med. Bin next to Open/Rel/Punct/Op/
        // Bin degrades to Ord (handled by caller via degradeBin).
        return med;
    }
    if (left == .Op or right == .Op) {
        // Op-Ord / Ord-Op: thin. Op-Op: 0? TeX: Op-Op = thin? The
        // table row Op: Ord=thin? Actually: (Op,Ord)=thin, (Ord,Op)=
        // thin only in display/text; Op-Op=thin? TeX table: Op row:
        // Ord thin, Op thin, Bin *, Rel thick, Open 0, Close 0,
        // Punct 0, Inner thin. Keep uniform thin.
        if (left == .Inner or right == .Inner) return thin;
        if (left == .Op and right == .Op) return thin;
        return thin;
    }
    if (left == .Inner or right == .Inner) {
        // Inner-Ord = thin? TeX Inner row: Ord thin? Inner-Ord=thin
        // only display/text... use thin for Ord/Inner pairs.
        if (left == .Ord or right == .Ord) return thin;
        return 0;
    }
    return 0;
}

/// A Bin atom degrades to Ord when it cannot be binary: first in a
/// list, or directly after Bin/Op/Rel/Open/Punct (TeX Book p.170).
pub fn degradeBin(prev: ?AtomClass) bool {
    const p = prev orelse return true;
    return switch (p) {
        .Bin, .Op, .Rel, .Open, .Punct => true,
        .Ord, .Close, .Inner => false,
    };
}

/// Delimiter commands: name → codepoint. `.` and `|` are handled by
/// the parser directly.
pub fn lookupDelim(name: []const u8) ?u21 {
    const delims: []const struct { name: []const u8, cp: u21 } = &.{
        .{ .name = "langle", .cp = 0x27E8 },
        .{ .name = "rangle", .cp = 0x27E9 },
        .{ .name = "lvert", .cp = 0x007C },
        .{ .name = "rvert", .cp = 0x007C },
        .{ .name = "vert", .cp = 0x007C },
        .{ .name = "lVert", .cp = 0x2016 },
        .{ .name = "rVert", .cp = 0x2016 },
        .{ .name = "Vert", .cp = 0x2016 },
        .{ .name = "lfloor", .cp = 0x230A },
        .{ .name = "rfloor", .cp = 0x230B },
        .{ .name = "lceil", .cp = 0x2308 },
        .{ .name = "rceil", .cp = 0x2309 },
        .{ .name = "ulcorner", .cp = 0x231C },
        .{ .name = "urcorner", .cp = 0x231D },
        .{ .name = "llcorner", .cp = 0x231E },
        .{ .name = "lrcorner", .cp = 0x231F },
        .{ .name = "uparrow", .cp = 0x2191 },
        .{ .name = "downarrow", .cp = 0x2193 },
        .{ .name = "updownarrow", .cp = 0x2195 },
        .{ .name = "Uparrow", .cp = 0x21D1 },
        .{ .name = "Downarrow", .cp = 0x21D3 },
        .{ .name = "Updownarrow", .cp = 0x21D5 },
        .{ .name = "backslash", .cp = 0x005C },
        .{ .name = "lang", .cp = 0x27E8 },
        .{ .name = "rang", .cp = 0x27E9 },
    };
    for (delims) |d| if (eq(d.name, name)) return d.cp;
    return null;
}

/// Combining accents: name → combining codepoint. `wide` marks the
/// stretchy family (`\widehat` etc.) which grows with the nucleus.
pub const Accent = struct {
    cp: u21,
    wide: bool,
};

pub fn lookupAccent(name: []const u8) ?Accent {
    const accents: []const struct { name: []const u8, cp: u21, wide: bool } = &.{
        .{ .name = "hat", .cp = 0x0302, .wide = false },
        .{ .name = "widehat", .cp = 0x0302, .wide = true },
        .{ .name = "check", .cp = 0x030C, .wide = false },
        .{ .name = "widecheck", .cp = 0x030C, .wide = true },
        .{ .name = "grave", .cp = 0x0300, .wide = false },
        .{ .name = "acute", .cp = 0x0301, .wide = false },
        .{ .name = "tilde", .cp = 0x0303, .wide = false },
        .{ .name = "widetilde", .cp = 0x0303, .wide = true },
        .{ .name = "bar", .cp = 0x0304, .wide = false },
        .{ .name = "breve", .cp = 0x0306, .wide = false },
        .{ .name = "vec", .cp = 0x20D7, .wide = false },
        .{ .name = "dot", .cp = 0x0307, .wide = false },
        .{ .name = "ddot", .cp = 0x0308, .wide = false },
        .{ .name = "dddot", .cp = 0x20DB, .wide = false },
        .{ .name = "ddddot", .cp = 0x20DC, .wide = false },
        .{ .name = "mathring", .cp = 0x030A, .wide = false },
    };
    for (accents) |a| if (eq(a.name, name)) return .{ .cp = a.cp, .wide = a.wide };
    return null;
}

/// Fixed-size delimiter steps for the `\bigl` family: style index →
/// size multiplier in thousandths (TeX big=1.2, Big=1.8, bigg=2.4,
/// Bigg=3.0 baselines... KaTeX scales similarly).
pub fn bigStep(level: u2) u16 {
    return switch (level) {
        0 => 1200,
        1 => 1800,
        2 => 2400,
        3 => 3000,
    };
}

test "greek lookup hits both cases" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u21, 0x03B1), lookup("alpha").?.cp);
    try std.testing.expectEqual(@as(u21, 0x03A9), lookup("Omega").?.cp);
    try std.testing.expectEqual(@as(u21, 0x03D5), lookup("phi").?.cp);
    try std.testing.expectEqual(@as(u21, 0x03C6), lookup("varphi").?.cp);
}

test "unknown names miss" {
    const std = @import("std");
    try std.testing.expect(lookup("nope") == null);
    try std.testing.expect(lookup("") == null);
}

test "large operators carry limit defaults" {
    const std = @import("std");
    try std.testing.expect(lookup("sum").?.limits_default);
    try std.testing.expect(!lookup("int").?.limits_default);
    try std.testing.expect(lookup("lim").?.limits_default);
    try std.testing.expect(lookup("sin").?.func);
}

test "bin degrades at list head and after open" {
    const std = @import("std");
    try std.testing.expect(degradeBin(null));
    try std.testing.expect(degradeBin(.Open));
    try std.testing.expect(degradeBin(.Rel));
    try std.testing.expect(!degradeBin(.Ord));
    try std.testing.expect(!degradeBin(.Close));
}

test "rel spacing is thick, ord-ord is zero" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u16, 278), glueBetween(.Ord, .Rel));
    try std.testing.expectEqual(@as(u16, 0), glueBetween(.Ord, .Ord));
    try std.testing.expectEqual(@as(u16, 222), glueBetween(.Ord, .Bin));
}
