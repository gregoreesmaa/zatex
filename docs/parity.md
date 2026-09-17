# docs/parity.md — KaTeX parity beyond the support table (issue #51)

The support table (`docs/support-table.md`, mirrored in
`docs/katex-syntax.md`) tracks per-function parity. This note tracks
everything else KaTeX documents: the sweep accept set as a whole, the
[options](https://katex.org/docs/options),
[error](https://katex.org/docs/error), and [font](https://katex.org/docs/font)
behaviors. KaTeX 0.18.7 is the reference throughout.

## Sweep accept set (verified)

- Corpus: `tools/katex/corpus.json` — 858 rows (687 accept, 171 reject).
- Goldens: `packages/zatex/goldens/katex_sweep.json` — 858 cases.
- Table audit (`node audit.mjs` in `tools/katex`): 0 hard errors,
  121/121 `unsup` rows own reject rows, every QA-class sweep id has a
  table owner.
- Core suite (`zig build test` in `packages/zatex`): 23/23 steps,
  170/170 tests pass, including the pinned-KaTeX differential sweep
  (`parity.zig`: accept/reject agreement, reject-position equality,
  MathML tag-sequence agreement per `docs/tolerance.md`).
- Table status counts: 552 `accept`, 121 `unsup`/`err-parity`
  (intentional rejects with reject-row evidence), 459 `TODO` with owner
  issues. No status changes were needed for this issue: the audit is
  clean and the suite is green, so the mirror needs no regeneration
  beyond its normal flow.

## Options

| KaTeX option | ZaTeX status |
| --- | --- |
| `displayMode` | Parity: `LayoutOptions.display_mode` (inline `\textstyle` vs display `\displaystyle`, same operator-size rules). |
| `output` (`html`/`mathml`/`htmlAndMathml`) | Partial by design: MathML emitter exists (`zatex.mathml`, structural walk per AGENTS.md §2, including the `<semantics>` / `application/x-tex` source annotation KaTeX emits — the raw source is available at `render(source, …)`, so no metrics cross the walker); there is no HTML emitter — a native library has no DOM to feed, hosts compose their own views from the layout IR (`docs/ir.md`). |
| `leqno`, `fleqn` | Gap: no tag/equation-number support, no flush-left mode (no owner issue yet — file one when `\tag` is scoped). |
| `throwOnError` | Native difference, intentional: the engine always throws (`LayoutError.Invalid` + `Diag`); there is no render-source-with-hover fallback because there is no HTML sink. Callers implement fallback from the error. |
| `errorColor` | N/A: follows from `throwOnError` above (no non-throwing render path). |
| `macros` (preset map) | Gap, minor: in-source `\def`/`\newcommand`/`\gdef`/`\providecommand` all work (sweep-proven); there is no options-level preset map — callers prepend a `\def` preamble to the source for the same effect. |
| `minRuleThickness` | Gap, minor: rule weights come from the font MATH table via the provider (`RuleKind`); no caller floor override. |
| `colorIsTextColor` | Gap, minor: `\color` is the current KaTeX switch form (sweep: `color`, `color-hex`, `color-macro`); the pre-0.8 argument form is not offered. |
| `maxSize` | Native difference: no em cap; oversized requests fail as `NoSpace` against caller buffers instead of clamping. Bounded either way. |
| `maxExpand` | Parity: `contract.max_expand = 1000`, the KaTeX default; exceeding it is `ExpansionLimit`. |
| `strict` | Gap: no strict/warn/ignore modes for non-LaTeX conveniences (e.g. `\\` in display mode follows the engine default; there is no faithfulness-mode switch). |
| `trust` | Native difference, intentional: `\href`/`\url` content passes through as data; there is no URL/protocol gate in the engine — the host that turns strings into links owns trust (a native library cannot know the host's URL policy). |
| `globalGroup` | No knob: definitions scope per KaTeX default (local groups; `\gdef` escapes, sweep: `gdef-basic`). |

## Error behaviors

- `ParseError` parity holds: every failure is `LayoutError.Invalid`
  with `Diag{offset, message}` — byte offset plus static message —
  and reject positions equal KaTeX's (`tolerance.md`, modulo the 5
  declared `katex_only` divergences, each asserted exactly).
- The `throwOnError: false` render-source mode does not exist (see
  above); the XSS-escaping guidance on KaTeX's error doc is N/A native
  (no HTML sink; the C ABI surfaces bytes, hosts escape for their own
  sinks).

## Font behaviors

- No bundled fonts in the core (AGENTS.md tenet); hosts supply metrics
  through the provider callback (`MetricsProvider`: glyph ids,
  advances, rule weights, ink extents, variants, italic corrections,
  MathKern cut-ins). The reference host (`refhost.zig`) resolves
  vendored Latin Modern Math first, system STIX Two Math second.
- TeX units resolve in the parser (`em`, `ex`, `mu`, `pt`, `in`, `cm`,
  … — `parse.zig` unit table, sweep-proven per function); there is no
  browser-px rescaling and no 1.21× surrounding-context sizing —
  sizing is the caller's `px_per_em` (CLI default 48).
- Web font delivery (`ttf`/`woff`/`woff2`, `fonts/` folder config) is
  N/A native; the analog (which file the host opens) is the provider
  plus the refhost order above.
- Font-alphabet commands (`\mathbb`, `\mathbf`, …) map to core font
  families (`FontId`) for the host to resolve — coverage of each
  command is per-function table scope (issue #34), not this note.

## Host troubleshooting (issue #142)

- Boxes/tofu on screen mean the provider returned glyph id 0
  (= missing, see `glyphId` in `contract.zig` / `glyph_id` in
  `zatex.h`): the core lays the run out anyway, so nothing errors —
  log which (`font`, codepoint) pairs come back 0 to enumerate
  coverage. The reference host (`refhost.zig`) resolves vendored
  Latin Modern Math first, system STIX Two Math second; a pair that
  is 0 in both is genuinely uncovered (the refhost coverage-test
  pattern shows how to sweep a corpus for misses).
- Math-island detection is host-side: the core takes raw TeX and
  `parse.zig` rejects `$` inside math input — there is no
  auto-render in the core; hosts own delimiter scanning.

## Remaining gaps (exact)

1. Function coverage: 459 `TODO` rows in the support table (owner
   issues #1, #2, #4, #7, #14 and friends) — that is the umbrella's
   long tail, tracked per function, not here.
2. Options gaps: `leqno`/`fleqn`, preset `macros` map,
   `minRuleThickness`, `colorIsTextColor`, `strict` — all minor,
   none load-bearing for layout parity; file issues when scoped.
3. Intentional native differences (not gaps): always-throw errors, no
   HTML output, host-owned trust, caller-sized rendering.
