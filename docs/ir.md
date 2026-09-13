# docs/ir.md — ZaTeX layout IR (output contract)

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
* **Emitters** walk the same tree: MathML ships in the core,
  `packages/zatex-png` renders PNG (macOS-only backend), SVG is future.
  Emitters contain no layout math.

## Stable calling contract (frozen 2026-09-12)

`layout(source, options, provider, runs, rules) LayoutError!Layout` —
one pass, caller-owned buffers, zero allocations. `options` fields gain
defaults; `LayoutError` variants are added, never removed;
`MetricsProvider` callbacks arrive with a `provider_version` bump.
Hard caps are named constants (`max_input_len`, `max_nesting_depth`,
`max_expand`). Call-site shape is frozen; only additive growth.

## Reference rendering

Latin Modern Math is the reference font (Computer Modern look is part of
compatibility). Vendored only as a test fixture for differential goldens
against KaTeX — never in the core, never a link dependency.
