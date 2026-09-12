# docs/ir.md — MaTeX layout IR (output contract)

One layout core, many emitters. The core parses KaTeX-compatible input,
expands macros (bounded: `maxExpand` = 1000, KaTeX parity), lays out TeX
boxes, and emits a `ir.Layout`: glyph `Run`s plus `Rule` rects in
**integer font units** (`i32` positions, `u32` extents; `u16` glyph IDs
and sizes). Integer units keep output byte-deterministic across hosts —
no untracked float in the contract.

## Roles

* **Core** owns positions. It never draws, never rasterizes, never touches
  a font file. Glyph advances and variant/parts data arrive through the
  host's font-provider callback (metrics for the host's font, so output
  is always correct for the font actually drawn).
* **Hosts** (`read`, other apps) draw `Run`s through their own glyph
  cache/atlas and fill `Rule`s as rects. This is the fastest path: zero
  parsing and zero rasterization at showtime.
* **Future emitters** (out of repo by decision) walk the same tree:
  MathML first, SVG later, PNG last. Emitters contain no layout math.

## Reference rendering

Latin Modern Math is the reference font (Computer Modern look is part of
compatibility). Vendored only as a test fixture for differential goldens
against KaTeX — never in the core, never a link dependency.
