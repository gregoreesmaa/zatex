# AGENTS.md — Guidelines for AI Coding Agents on `MaTeX`

MaTeX is a native Zig implementation of KaTeX-compatible LaTeX math
typesetting. Every agent working on this repository MUST follow these
principles (adapted from `read`: same discipline, new domain).

## 1. Mission & Tenets

* **Compatibility target is KaTeX, not LaTeX.** The
  [KaTeX support table](https://katex.org/docs/support_table.html) is the
  scope. Anything KaTeX rejects, MaTeX rejects (same error contract).
* **Native performance.** Zero heap allocations on the layout path
  (parse, expand, lay out over caller-provided buffers). Bounded input,
  bounded stack depth, bounded macro expansion (`maxExpand` = 1000,
  parity with KaTeX). Total on adversarial input — fuzz it.
* **Zero dependencies.** No JS engine, no font files in the core, no
  network, no threads in the library. Hosts provide fonts and metrics
  through the provider callback (see `docs/ir.md`).
* **Deterministic output.** Same input + same font metrics = byte-identical
  layout. Integer font units internally; no untracked float.
* **Binary footprint.** The `subset` profile (what `read` will link) adds
  at most 8 KB of `__TEXT` to its host. Full-profile and future CLI
  budgets are set by measurement at M1, then frozen.

## 2. Immutable Mechanics

* KaTeX's observable contract is non-negotiable: input accepted/rejected,
  `displayMode`/`textstyle` behavior, `maxExpand`, `throwOnError`
  semantics. If our output differs from pinned KaTeX, our code is wrong —
  never "fix" the golden.
* One layout core, many emitters. Layout logic lives in exactly one place;
  output writers (native runs, MathML, later SVG/PNG) are thin walkers
  over the box tree. No layout math in emitters, ever.

## 3. Design Standards

* Reference font: Latin Modern Math (Computer Modern descendant — the look
  is part of compatibility). Vendored only as a test fixture and, later,
  as embedded subsets in out-of-repo tools — never in the core.
* Error style: KaTeX `ParseError` parity (message + position), surfaced as
  Zig errors with byte offsets.

## 4. Verification Protocol

Before pushing any code:

1. `zig build test` — 100% pass, including differential tests against
   pinned KaTeX output where the harness exists.
2. Size check for the touched profile (subset-profile growth accounted
   against the 8 KB host budget).
3. No golden changes without the KaTeX-side proof attached.

Screenshot-style pixel tests are banned from required gates (same rule as
`read`): compare layout IR / MathML text, never rendered pixels.
