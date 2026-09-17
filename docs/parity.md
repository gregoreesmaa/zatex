# docs/parity.md — KaTeX parity beyond the support table (issue #51)

The support table (`docs/support-table.md`, mirrored in
`docs/katex-syntax.md`) tracks per-function parity. This note tracks
everything else KaTeX documents: the sweep accept set as a whole, the
[options](https://katex.org/docs/options),
[error](https://katex.org/docs/error), and [font](https://katex.org/docs/font)
behaviors. KaTeX 0.18.7 is the reference throughout.

## Sweep accept set (verified)

- Corpus: `tools/katex/corpus.json` — 1586 rows (1325 accept, 261 reject).
- Goldens: `packages/zatex/goldens/katex_sweep.json` — 1586 cases.
- Table audit (`node audit.mjs` in `tools/katex`): 0 hard errors,
  123/123 `unsup` rows own reject rows, every QA-class sweep id has a
  table owner.
- Core suite (`zig build test` in `packages/zatex`): 25/25 steps,
  271/271 tests pass, including the pinned-KaTeX differential sweep
  (`parity.zig`: accept/reject agreement, reject-position equality,
  MathML tag-sequence agreement per `docs/tolerance.md`).
- Table status counts: 1013 `accept`, 127 `unsup`/`err-parity`
  (intentional rejects with reject-row evidence), 0 `TODO`. The
  audit is clean and the suite is green, so the mirror needs no
  regeneration beyond its normal flow.

## Options

| KaTeX option | ZaTeX status |
| --- | --- |
| `displayMode` | Parity: `LayoutOptions.display_mode` (inline `\textstyle` vs display `\displaystyle`, same operator-size rules). |
| `output` (`html`/`mathml`/`htmlAndMathml`) | Partial by design: MathML emitter exists (`zatex.mathml`, structural walk per AGENTS.md §2, including the `<semantics>` / `application/x-tex` source annotation KaTeX emits — the raw source is available at `render(source, …)`, so no metrics cross the walker); there is no HTML emitter — a native library has no DOM to feed, hosts compose their own views from the layout IR (`docs/ir.md`). |
| `leqno`, `fleqn` | Parity (geometry): `LayoutOptions.leqno` puts display `\tag`s left of the formula (default right); `LayoutOptions.fleqn` shifts display math right 2em and grows the width with it (flush-left with KaTeX's 2em margin — the host positions the block). KaTeX implements both as pure CSS classes on identical DOM/MathML (probed 0.18.7: same node order, `leqno`/`fleqn` classes); the geometric translation is the native equivalent. Env-internal number columns remain MathML-only (layout emits no number columns). |
| `throwOnError` | Native difference, intentional: the engine always throws (`LayoutError.Invalid` + `Diag`); there is no render-source-with-hover fallback because there is no HTML sink. Callers implement the fallback from the error — see "Error fallback (host recipe)" below. |
| `errorColor` | Native difference: no non-throwing render path, so no error paint in the engine; hosts rendering the fallback use `#cc0000` (KaTeX's `errorColor` default) by convention. |
| `macros` (preset map) | Partial: `LayoutOptions.macros` seeds a bounded (`max_presets` = 16) preset list — string bodies with `#1..#9` (arg counts inferred sequentially like KaTeX), single-codepoint active-character names, and `\let`-style alias + `noexpand` (the `MacroExpansion` object form). Remainder, named: function-valued macros have no native analog (no JS engine); `\gdef` never mutates the preset list (zero-alloc, reentrant — hosts share across calls by passing the same slice again); presets do not expand in `\text` bodies (in-source macros don't either — pre-existing). |
| `minRuleThickness` | Parity: `LayoutOptions.min_rule_thickness_milli_em` (thousandths of an em; 40 = KaTeX's usual 0.04) floors every rule thickness the core requests — provider weights via `RuleKind` plus the hardcoded 0.04em array-vline and `\fbox` weights. Unsigned by construction (KaTeX ignores negatives); 0 disables (previous behavior). |
| `colorIsTextColor` | Gap, minor: `\color` is the current KaTeX switch form (sweep: `color`, `color-hex`, `color-macro`); the pre-0.8 argument form is not offered. |
| `maxSize` | Native difference: no em cap; oversized requests fail as `NoSpace` against caller buffers instead of clamping. Bounded either way. |
| `maxExpand` | Parity: `contract.max_expand = 1000`, the KaTeX default; exceeding it is `ExpansionLimit`. |
| `strict` | Parity (subset): `LayoutOptions.strict` (`ignore`/`warn`/`err` = KaTeX `false`/`"warn"`/`"error"`, default `warn` like KaTeX) with `StrictLog` warn sink (caller-owned buffer; null drops warns — no console natively). Emitted codes: `html_extension`, `new_line_in_display_mode` (behavioral, never throws — error mode renders no break, already the zero-box shape), `text_env`, `math_vs_text_accents`, `math_vs_sout`. Error mode fails positioned `Invalid` (KaTeX's strict errors carry no position; ours names the offending token — documented). Remainder, named: function handlers (hosts branch on `StrictLog` codes instead); `mathVsTextUnits` (kern unit/mode checks unmodeled), `unicodeTextInMathMode`/`unknownSymbol` (non-ASCII math is `Ord` by design), `commentAtEnd` (trailing-`%` check absent). |
| `trust` | Native difference, intentional: `\href`/`\url` content passes through as data; there is no URL/protocol gate in the engine — the host that turns strings into links owns trust (a native library cannot know the host's URL policy). Host duties are inventoried under "Host security guidance" below. |
| `globalGroup` | Parity: KaTeX-default scoping is the engine rule (local groups; `\gdef`/`\xdef`/`\global`-prefixed escape; sweep locality rows `def-group-local` … `fence-def-nogroup`), plus the `global_group` opt-in for always-global definitions. |

## Error behaviors

- `ParseError` parity holds: every failure is `LayoutError.Invalid`
  with `Diag{offset, message}` — byte offset plus static message —
  and reject positions equal KaTeX's (`tolerance.md`, modulo the 24
  declared `katex_only` divergences, each asserted exactly: 22
  reject-position divergences plus `deep-nest` and `verb-in-macro`,
  which pinned KaTeX accepts).
- Messages are static by contract (no allocation, no source echo):
  fixed strings per failure kind — never KaTeX's dynamic echoes
  (function names as in `Got function \hbox with no arguments as
  subscript`, source snippets, 1-based positions). Wording is pinned
  by unit test (`zatex.zig` "Diag.message wording is pinned"); see
  `docs/tolerance.md` ("Static messages").
- The `throwOnError: false` render-source mode does not exist (see
  above); the XSS-escaping guidance on KaTeX's error doc is N/A native
  (no HTML sink; the C ABI surfaces bytes, hosts escape for their own
  sinks).

## Error fallback (host recipe)

KaTeX's `throwOnError: false` renders invalid input as its source in
`errorColor` with the error as hover text — and its accessibility
guidance requires hosts to surface the `ParseError` message as real
text (hover alone is unavailable to keyboard/screen-reader users).
The native recipe, from `Diag` (Zig: `layoutDiag`; C:
`zatex_layout_t.err_offset` + `err_msg`/`err_msg_len`, static storage
— always valid, never freed, NOT null-terminated):

1. On `Invalid`, render the source text and the `Diag.message` bytes
   as real text (never hover/title-tooltip alone).
2. Paint the fallback `#cc0000` (KaTeX's `errorColor` default).
3. The host owns escaping for its own sink (the bytes are raw UTF-8;
   an HTML host escapes them like any text).

## Host security guidance (embedding MathML)

KaTeX's `security.md` analog for native hosts. The engine never
executes, fetches, or links anything — but its MathML output carries
strings a host's sink may act on. Allowlist and filter at the sink.

- URL carriers (MathML only): `\href` emits `<mrow href="...">`;
  `\includegraphics` emits
  `<mglyph alt="..." [valign] height="..." [width] src="...">`.
  Both attributes pass the source text through with **no protocol
  gate**, so the host filters before linking (`javascript:`,
  `file:`, and friends) — the model is KaTeX's `trust` allowlist
  recipe (a protocol-allowlist predicate applied where links are
  created). Only MathML carries URLs: `\url` retains none
  (typeset as monospace text), and the layout/speech/PNG paths drop
  them (`\href` lays out its body only).
- Inline `style=` (exactly two): `\pmb` emits
  `<mstyle style="text-shadow: ...">`, `\fcolorbox` emits
  `<mpadded ... style="border: ..." mathbackground="...">`. A CSP
  banning inline styles, or a sanitizer stripping `style`, silently
  degrades these two constructs — the same failure KaTeX's doc
  warns about. Other `mstyle` attributes (`scriptlevel`,
  `displaystyle`) are structural and inert.
- `class=` (exactly three values): `vcenter` on `<mpadded>`
  (`\vcenter`), `mtr-glue` / `mml-eqn-num` on `<mtd>` (numbered
  display equations). Sanitizers stripping `class` break those
  constructs. No `katex-`-prefixed class is ever emitted, so
  KaTeX's class-prefix CSP guidance does not apply here.
- Errors: `Diag.message` is a static literal (it never echoes
  input); `Diag.offset` (Zig) / `err_offset` (C ABI) locates the
  failure. The injection risk is the host's own interpolation:
  embedding the source — or the MathML — into HTML without
  escaping replays the XSS pattern KaTeX's error doc warns about,
  so hosts escape for their own sinks.

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

1. Function coverage: 0 `TODO` rows in the support table — every
   KaTeX function is either `accept` with golden evidence or an
   intentional reject (`unsup`/`err-parity`) with reject-row
   evidence, tracked per function, not here.
2. Options gaps: `colorIsTextColor` (minor, not load-bearing
   for layout parity). `leqno`/`fleqn`, preset `macros`,
   `minRuleThickness`, `strict`, and `globalGroup` are closed (see
   the table above).
3. Intentional native differences (not gaps): always-throw errors, no
   HTML output, host-owned trust, caller-sized rendering.
