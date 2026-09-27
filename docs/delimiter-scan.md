# docs/delimiter-scan.md — canonical math-delimiter scanning (issue #252)

ZaTeX starts at already-extracted TeX, so every host reimplements math
detection independently — and every independent reimplementation
diverges on edge cases. This document is the one canonical rule, with
conformance vectors, so all hosts share KaTeX-consistent behavior.

Scope rule (read carefully): **KaTeX detects delimiters in contrib
auto-render, not in core.** Nothing here is a core API — the layout
engine still starts at extracted TeX. This spec plus
`packages/zatex/goldens/delimiter_vectors.json` come *before* any core
helper; a future helper must satisfy the vectors, never redefine them.

## 1. Base layer: exact KaTeX auto-render behavior

Pinned: KaTeX 0.18.7 (`tools/katex/package.json`),
`contrib/auto-render/splitAtDelimiters.ts`. The port from JS to TS
changed types only — the algorithm is byte-identical to 0.16.x (proof:
`diff` of the two sources, both fetched from the KaTeX repo; only
`string`/`number`/`DelimiterSpec` annotations differ).

### 1.1 Default delimiter table

From `auto-render.ts` verbatim (order matters — first match wins):

| left | right | display |
|---|---|---|
| `$$` | `$$` | true |
| `\(` | `\)` | false |
| `\begin{equation}` | `\end{equation}` | true |
| `\begin{align}` | `\end{align}` | true |
| `\begin{alignat}` | `\end{alignat}` | true |
| `\begin{gather}` | `\end{gather}` | true |
| `\begin{CD}` | `\end{CD}` | true |
| `\[` | `\]` | true |

Notably, single `$` is **not** in the defaults (KaTeX's own comment:
"LaTeX uses $…$, but it ruins the display of normal `$` in text").
A host that wants `$…$` appends `{left: "$", right: "$",
display: false}` **after** `$$` (order: `$` must come after `$$`).

### 1.2 Scan algorithm (normative)

`splitAtDelimiters(text, delimiters)`:

1. Find the leftmost occurrence of any left delimiter (regex
   alternation in table order). No match: the rest is literal text.
2. At the match, take the **first** table entry (in table order)
   whose left matches there. (So `$` at the head of `$$x$$` still
   picks `$$` when `$$` precedes `$` in the table — but picks `$`
   when `$` precedes `$$`.)
3. Scan for the right delimiter from the end of the left delimiter
   (`findEndOfMath`):
   - a right-delimiter match at brace level 0 ends the island;
   - `\` skips the next character (escaped closers never end);
   - `{`/`}` nest one level (closers inside braces never end);
   - no closer: **stop — the left delimiter and everything after it
     stay literal** (unclosed dollars are text, not errors).
4. The payload is the text between the delimiters — **except** for
   `\begin{…}` islands, whose payload keeps the full raw span
   (delimiters included).

Proven edge cases (from KaTeX's own
`contrib/auto-render/test/auto-render-spec.js`, each a vector):
brace-shielded closers, backslash-skipped closers, adjacent islands,
and the `$`/`$$` mixes (`$hello$world$$boo$$` → math, text, math;
`$hello$$world$$$boo$$` → three math islands).

Hosts also inherit auto-render's surroundings: `renderMathInElement`
skips `script`, `noscript`, `style`, `textarea`, `pre`, `code`,
`option` subtrees (plus host-configured ignored classes), and
code-span masking (§5) applies before scanning.

## 2. Guard layer: the ZaTeX `$` contract (extension)

KaTeX has **no** currency guards — `$100 and $200` under the `$`
table islands as `$100 and $`. Hosts that enable `$` MUST apply
these three guards so prices stay literal (§4 vectors prove each):

- **G-open (currency/escape):** an inline-`$` island is literal when
  the char before its left `$` is `\` (escaped opener), or the char
  after its left `$` is a digit, or a `.` followed by a digit
  (`$0.00`, `$.99` stay literal).
- **G-close (currency):** an inline-`$` island is literal when the
  char after its closing `$` is a digit (`$100 and $200` never
  islands: the closer is glued to `2`).
- **G-display/escape:** `$$`, `\(`, `\[` islands take no currency
  guards (unambiguous pairing), but an opener glued to a preceding
  `\` stays literal.

Deliberate non-rules (do NOT implement these):

- No "closer preceded by digit" rule: it would kill `$x^2$` and
  `$a_1$` — digit-final math is common and unambiguous once G-open
  has fired. (`$100 and $200` dies by G-close, not by what precedes
  the closer.)
- **Guards filter KaTeX islands; they never rescan.** Dropping an
  island orphans its delimiters: `a \$b\$ c $x$ d` yields *zero*
  islands (the `$` that would open `$x$` was consumed as the dropped
  island's closer). Rescanning would re-pair orphaned dollars into
  islands KaTeX never produced — the guard layer must stay a pure
  filter so hosts agree bit-for-bit.

## 3. Display-island pairing

`$$…$$` pairs by the base algorithm (table order puts `$$` first).
A lone `$` inside a `$$` island is payload, never an opener; an
unclosed `$$` leaves the rest literal like any unclosed opener.
`$hello$$world$$$boo$$` (three islands) is the conformance probe.

## 4. Conformance vectors

`packages/zatex/goldens/delimiter_vectors.json`, generated by
`tools/katex/gen_delim_vectors.mjs` from the pinned package:

- `meta.splitter_sha256` pins the exact splitter bytes run.
- `guards:false` islands are raw KaTeX splitter output (byte
  offsets into `text`, `tex` payload, `display` flag).
- `guards:true` islands add the §2 filter, applied by the
  generator's reference implementation.
- Every island carries `engine`: the KaTeX `renderToString`
  verdict (`throwOnError:true`) on its payload, asserted at
  generation time — generation fails if KaTeX disagrees.

`src/delimvectors.zig` (test-only, wired into `zig build test`)
replays every vector: offsets must reconstruct the text, islands
must be ordered and non-overlapping, and the ZaTeX engine verdict
on each payload (`layoutFull` with a stub provider) must equal the
KaTeX-proven `engine` flag — including `reject` (e.g. the
brace-shield payload `a { \) } b`, which KaTeX also rejects).

Regenerate: `cd tools/katex && npm ci && node
gen_delim_vectors.mjs`. CI (`sweep-freshness`) re-runs it and fails
on drift, same as the layout sweep.

## 5. Host recipe (markdown)

1. Split the document into code spans and prose; mask `` `code` ``
   spans (vector `guard-code-span`).
2. Skip auto-render's ignored tags/classes.
3. Run §1 with the host's table (default, or default + `$`).
4. If the table has `$`, apply §2 as a pure filter.
5. Feed each surviving payload to the engine with its `display`
   flag. Engine errors are host policy (render red, or fall back to
   literal) — detection is specified here, error UI is not.
