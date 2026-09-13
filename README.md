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
| `zatex` (core) | Parser, macro expander, layout, MathML, C ABI. Portable Zig. | `packages/zatex/` |
| `zatex-png` | LaTeX → PNG CLI + visual regression set. One backend per OS (CoreGraphics on Apple, portable software rasterizer elsewhere). Depends on the core, never the reverse. | `packages/zatex-png/` |

Shared at the root: `docs/` (contracts, policies, the syntax mirror),
`tools/` (KaTeX sweep harness, size gate, render helpers), `.github/`
(CI for all packages).

## Use it

Prerequisites: Zig 0.16.0; `zatex-png` builds anywhere (CoreGraphics backend on macOS/iOS, zero-dependency software backend on Linux/Windows/Android).

```sh
# Core: full test suite (incl. pinned-KaTeX differential sweep)
cd packages/zatex && zig build test --summary all

# PNG renderer + its tests
cd packages/zatex-png && zig build test --summary all

# Render one formula / the regression corpus
./zig-out/bin/zatex-png "x^2" out.png
./screenshots/render.sh

# From the repo root: host-cost gate
./tools/size_gate.sh
```

Depend on the core from your own Zig package with a path dependency:

```zig
.zatex = .{ .path = "path/to/zatex/packages/zatex" },
```

then `b.dependency("zatex", ...)` and import the `zatex` (and `otmath`,
for the OpenType metrics reader) modules — the same shape
`packages/zatex-png/build.zig` uses.

## Tests and docs

Normal use is Zig-only and dependency-less: no runtimes, no package
managers, no network, no font installs. The test font is vendored
(`packages/zatex/fixtures/`, test-only, never linked into the core)
and the KaTeX expectations are checked in as JSON goldens
(`packages/zatex/goldens/`), so everything below runs offline:

* `zig build test` in `packages/zatex` — core suite, including the
  pinned-KaTeX differential sweep against the checked-in goldens.
* `zig build test` in `packages/zatex-png` — CLI logic, backend
  coordinate-mapping tests, plus the software-backend suite (CFF
  interpreter, rasterizer, PNG, CoreText cross-check); rendering
  itself is exercised via the CLI.
* `./tools/size_gate.sh` — subset-profile host-cost gate (macOS-only:
  it measures Mach-O `__TEXT` with the system `size` tool).
* `zatex-png` renders (`./zig-out/bin/zatex-png "x^2" out.png`,
  `./screenshots/render.sh`) — one backend per OS behind a small
  `Backend` interface (`-Dbackend=auto|cg|software`); the layout core
  stays portable and backend-free. Backends:

| OS | Backend | Status |
| --- | --- | --- |
| macOS | CoreGraphics (`cg_backend.zig`) | Reference; CI renders + compares. |
| iOS | CoreGraphics (`ios_backend.zig`, re-export) | Wired; needs Xcode iOS SDK to compile-check (SDK CI runner). |
| Linux | Software rasterizer (`linux_backend.zig`) | Builds + renders; layout dimensions bit-equal to CoreGraphics, pixels geometrically exact but unhinted (see `packages/zatex-png/README.md`). |
| Windows | Software rasterizer (`windows_backend.zig`) | Cross-compiles; DirectWrite stays a future optimization. |
| Android | Software rasterizer (`android_backend.zig`) | File compiles; full link needs NDK libc (NDK CI runner). |

Two maintainer-only workflows need third-party runtimes. Both run in
CI, so contributors never have to touch them:

* `npm run sweep` in `tools/katex` (Node) — regenerates the goldens
  from pinned KaTeX 0.18.7; CI fails on drift.
* Screenshot/docs helpers (`tools/compare_shots.py`,
  `tools/gen_doc_renders.py` — Python 3 stdlib) — visual regression
  comparison and the `docs/katex-syntax.md` render mirror; CI fails on
  drift.

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

* `packages/zatex/src/` — library core (`zatex.zig` root, `ir.zig`
  output types, `mathml.zig`, `cabi.zig` + `zatex.h`).
* `packages/zatex/fixtures/` — test-only font fixture (never linked
  into the core). `packages/zatex/goldens/` — pinned-KaTeX sweep.
* `packages/zatex-png/src/` — CLI, CoreGraphics backend, font loader.
  `packages/zatex-png/screenshots/` — visual regression corpus + baselines.
* `docs/ir.md` — the layout IR: what every emitter consumes.
  `docs/support-table.md` — KaTeX coverage status per function (the single
  editable source). `docs/katex-syntax.md` — its generated render mirror
  (do not edit; generated from the support table, renders by `zatex-png`).
  `docs/tolerance.md` — differential test policy.
* `tools/katex/` — pinned-KaTeX sweep harness (`corpus.json`, `sweep.mjs`).

See [AGENTS.md](AGENTS.md) for the contributor contract.

## Roadmap

Coverage is tracked as GitHub issues, one per KaTeX functionality group,
all verified against pinned KaTeX output. Direction of travel: `read`
replaces its external math-plugin slot with the ZaTeX `subset` profile.

## License

MIT — Copyright (c) 2026 Gregor Eesmaa. See [LICENSE](LICENSE).
