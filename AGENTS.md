# AGENTS.md — Guidelines for AI Coding Agents on `ZaTeX`

ZaTeX is a native Zig implementation of KaTeX-compatible LaTeX math
typesetting. Every agent working on this repository MUST follow these
principles (adapted from `read`: same discipline, new domain).

## 1. Mission & Tenets

* **Compatibility target is KaTeX, not LaTeX.** The
  [KaTeX support table](https://katex.org/docs/support_table.html) is the
  scope. Anything KaTeX rejects, ZaTeX rejects (same error contract).
* **Native performance.** Zero heap allocations on the layout path
  (parse, expand, lay out over caller-provided buffers). Bounded input,
  bounded stack depth, bounded macro expansion (`maxExpand` = 1000,
  parity with KaTeX). Total on adversarial input — fuzz it.
* **Zero dependencies.** No JS engine, no font files in the core, no
  network, no threads in the library. Hosts provide fonts and metrics
  through the provider callback (see `docs/ir.md`).
* **Deterministic output.** Same input + same font metrics = byte-identical
  layout. Integer font units internally; no untracked float.
* **Binary footprint.** One engine, one profile: hosts link the full
  library. The shipped static artifact never grows past the committed
  baseline (`tools/size_gate.sh` enforces it); future CLI budgets are
  set by measurement at M1, then frozen.

## 2. Immutable Mechanics

* KaTeX's observable contract is non-negotiable: input accepted/rejected,
  `displayMode`/`textstyle` behavior, `maxExpand`, `throwOnError`
  semantics. If our output differs from pinned KaTeX, our code is wrong —
  never "fix" the golden.
* One layout core, many emitters. Measuring and geometry live in exactly
  one place (`layout.zig`); shared decisions (limit placement via
  `parse.opBase`/`useLimits`, glue widths via `parse.space_*`) are owned
  by the core and reused, never re-derived. Geometric emitters (native
  runs, later SVG/PNG) are thin walkers over the box tree. The MathML
  emitter is a thin *structural* walker over the AST (KaTeX builds its
  MathML from its parse tree too — the positioned box tree has already
  lost the semantics MathML needs); it takes no `MetricsProvider`, so
  measuring there is impossible by construction. No layout math in
  emitters, ever (resolution of issue #16, owner-signed by closing it).

## 3. Design Standards

* Reference font: Latin Modern Math (Computer Modern descendant — the look
  is part of compatibility). Vendored only as a test fixture and, later,
  as embedded subsets in out-of-repo tools — never in the core. Hosts
  fall back to system math fonts (e.g. STIX Two Math on macOS) when the
  fixture is absent; order is vendored-first, system-second
  (see `src/refhost.zig`, issue #8).
* Error style: KaTeX `ParseError` parity (message + position), surfaced as
  Zig errors with byte offsets.

## 4. Verification Protocol

Before pushing any code:

1. `zig build test` — 100% pass, including differential tests against
   pinned KaTeX output where the harness exists.
2. Size check via `./tools/size_gate.sh` — the shipped static artifact
   must not grow past the committed baseline.
3. No golden changes without the KaTeX-side proof attached.

Screenshot-style pixel tests are banned from required gates (same rule as
`read`): compare layout IR / MathML text, never rendered pixels.
