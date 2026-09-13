# ZaTeX — a KaTeX-compatible LaTeX engine

> **The fastest math typesetting library for anywhere but the web.**

ZaTeX reads LaTeX math (the KaTeX-supported subset, working toward the full
[KaTeX support table](https://katex.org/docs/support_table.html)) and lays it
out natively in Zig: zero dependencies, zero heap allocations on the layout
path, deterministic output. One layout core feeds every output — a native
display list for embedding, MathML, PNG — with each emitter a thin walker
over the box tree, never a second layout engine.

KaTeX is excellent and remains the compatibility reference (its test corpus
and fonts pin our behavior). ZaTeX exists for where KaTeX cannot go: native
binaries with no JS runtime, no Node, no npm — microsecond layout inside
apps like [read](../read) that budget kilobytes, not megabytes.

## Packages

| Package | What | Path |
| --- | --- | --- |
| `zatex` (core) | Parser, macro expander, layout, MathML, C ABI. Portable Zig. | `packages/zatex-core/` |
| `zatex-png` | LaTeX → PNG CLI + visual regression set. macOS-only backend. Depends on the core, never the reverse. | `packages/zatex-png/` |

Shared at the root: `docs/` (contracts, policies, the syntax mirror),
`tools/` (KaTeX sweep harness, size gate, render helpers), `.github/`
(CI for all packages).

## Use it

Prerequisites: Zig 0.16.0, Python 3 (stdlib only), Node 22 (KaTeX sweep
only), macOS 14+ for `zatex-png`.

```sh
# Core: full test suite (incl. pinned-KaTeX differential sweep)
cd packages/zatex-core && zig build test --summary all

# PNG renderer + its tests
cd packages/zatex-png && zig build test --summary all

# Render one formula / the regression corpus
./zig-out/bin/zatex-png "x^2" out.png
./screenshots/render.sh

# From the repo root: host-cost gate + docs-mirror regen check
./tools/size_gate.sh
python3 tools/gen_doc_renders.py
```

Depend on the core from your own Zig package with a path dependency:

```zig
.zatex = .{ .path = "path/to/zatex/packages/zatex-core" },
```

then `b.dependency("zatex", ...)` and import the `zatex` (and `otmath`,
for the OpenType metrics reader) modules — the same shape
`packages/zatex-png/build.zig` uses.

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

## Layout

* `packages/zatex-core/src/` — library core (`zatex.zig` root, `ir.zig`
  output types, `mathml.zig`, `cabi.zig` + `zatex.h`).
* `packages/zatex-core/fixtures/` — test-only font fixture (never linked
  into the core). `packages/zatex-core/goldens/` — pinned-KaTeX sweep.
* `packages/zatex-png/src/` — CLI, CoreGraphics backend, font loader.
  `packages/zatex-png/screenshots/` — visual regression corpus + baselines.
* `docs/ir.md` — the layout IR: what every emitter consumes.
  `docs/katex-syntax.md` — KaTeX syntax mirror with a render per function.
  `docs/tolerance.md`, `docs/support-table.md` — test policy and scope.
* `tools/katex/` — pinned-KaTeX sweep harness (`corpus.json`, `sweep.mjs`).

See [AGENTS.md](AGENTS.md) for the contributor contract.

## Roadmap

Coverage is tracked as GitHub issues, one per KaTeX functionality group,
all verified against pinned KaTeX output. Direction of travel: `read`
replaces its external math-plugin slot with the ZaTeX `subset` profile.

## License

MIT — Copyright (c) 2026 Gregor Eesmaa. See [LICENSE](LICENSE).
