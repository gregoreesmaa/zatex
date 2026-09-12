# MaTeX — a KaTeX-compatible LaTeX engine

> **The fastest math typesetting library for anywhere but the web.**

MaTeX reads LaTeX math (the KaTeX-supported subset, working toward the full
[KaTeX support table](https://katex.org/docs/support_table.html)) and lays it
out natively in Zig: zero dependencies, zero heap allocations on the layout
path, deterministic output. One layout core feeds every output the library
makes possible — a native display list for embedding, MathML, SVG, PNG —
without the library itself shipping any of those writers as tools.

## Why not KaTeX itself

KaTeX is excellent and remains the compatibility reference (its test corpus
and fonts pin our behavior). MaTeX exists for where KaTeX cannot go: native
binaries with no JS runtime, no Node, no npm — microsecond layout inside
apps like [read](../read) that budget kilobytes, not megabytes.

## Resource contract (mirrors `read`)

* **CPU**: layout is single-pass over caller buffers; hot path allocates
  nothing and spawns no threads.
* **RAM**: bounded pools, bounded input, bounded macro expansion
  (`maxExpand` parity with KaTeX: 1000). No unbounded recursion, ever.
* **GPU**: output is positioned glyph runs + rects — drawn through the
  host's glyph cache, never re-rasterized per frame.
* **Disk**: no bundled fonts in the core, no caches written by the library.
  The `subset` profile adds ≤ 8 KB of `__TEXT` to its host.
* **Energy**: lay out once per content hash; hosts cache by hash.

See [AGENTS.md](AGENTS.md) for the contributor contract and
[docs/ir.md](docs/ir.md) for the output contract.

## Layout

* `src/` — library core (`matex.zig` root, `ir.zig` output types).
* `docs/ir.md` — the layout IR: what every future emitter consumes.
* No wrapper CLIs by explicit decision: MathML/SVG/PNG writers are
  out-of-repo until the core is compliant. The IR keeps them possible.

## Roadmap

Coverage is tracked as GitHub issues, one per KaTeX functionality group,
all verified against pinned KaTeX output. Direction of travel: `read`
replaces its external math-plugin slot with the MaTeX `subset` profile.

## License

MIT — Copyright (c) 2026 Gregor Eesmaa. See [LICENSE](LICENSE).
