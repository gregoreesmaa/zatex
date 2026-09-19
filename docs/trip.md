# docs/trip.md — Knuth's TRIP test, mapped to the ZaTeX contract (issue #177)

## Sources

The canonical TRIP tortures live in Knuth's TeX distribution, on CTAN at
`systems/knuth/dist/tex/`:

- `trip.tex` — the diabolical input (448 lines, verified 2026-09-19 against
  the CTAN mirror; opens `% This is a diabolical test file for TeX82`).
- `tripman.tex` — the manual describing what TRIP covers.
- `trip.log` / `trip.dvi` — the archived masters. The TRIP "oracle" is a
  byte comparison of a run's log and DVI against those masters.

TRIP tests **TeX-the-program**: tokenizer, fonts, registers, line breaking,
page building, hyphenation, math list building, macro expansion, file I/O,
and the interaction/error machinery around all of it.

## Scope rule (read first)

TRIP is never an oracle over pinned KaTeX. Per AGENTS.md §1 the
compatibility target is KaTeX: where TRIP (Knuth TeX behavior) and KaTeX
0.18.7 disagree, KaTeX wins and ZaTeX follows KaTeX. TRIP's value here is
as a checklist — it names the edge cases a math core must have *an*
answer for (accept with KaTeX's geometry, or reject with KaTeX's error
contract) — not as expected output. The math-side answers are pinned by
the sweep goldens and the `trip*` regression tests below, never by
`trip.log`.

## Section map

Line numbers are `trip.tex` (CTAN, 448 lines). "Evidence" is where ZaTeX
pins its answer today: sweep goldens, `qa.zig` tests, or the named doc.

| TRIP lines | Topic | Scope | ZaTeX answer |
| --- | --- | --- | --- |
| 1–10 | Tokenizer: `\catcode`, active chars, `\outer`, `\endlinechar` | OUT — the lexer is fixed (KaTeX has no `\catcode`) | Reject-position parity (`docs/tolerance.md`): every failure carries KaTeX's 0-based offset |
| 11–31 | Fonts: `\font`, `\fontdimen`, `\skewchar`, `\textfont`, `\mathchardef` | OUT — hosts supply metrics via `MetricsProvider` (`docs/ir.md`); no TFM in the core | In-scope sliver: rule weights via `RuleKind`, italic correction via provider cut-ins (probed in `refhost.zig`) |
| 32–53 | Registers and glue arithmetic: `\count`, `\dimen`, `\skip`, `\muskip`, `\advance`, `\multiply`, `\divide`, `fil`/`fill`/`filll` | IN (bounded form) — integer font units, no float, total on adversarial input (AGENTS.md §1) | `trip06`: giant `\kern`/`\mskip` stay total; lengths saturate at ±2e9, never wrap (`parse.zig:sizeToEm5`); expansion/nesting/input caps in `qa44` |
| 54–68 | Conditionals, penalties, `\mag`, `\delimiterfactor`, `\showboxbreadth/depth` | OUT — TeX conditionals (`\ifnum`, `\ifx`, `\ifcase`) are rejected on both sides (KaTeX has no `\if...`; ZaTeX `rej-unsup-ifx` parity); page penalties and `\mag` have no math-core analog | Reject parity via the sweep (`rej-unknown`-class rows); `\mag`/page penalties N/A by construction |
| 69–80 | Hyphenation: `\patterns`, `\hyphenation`, `\lccode`, `\language` | OUT — no paragraph builder, no hyphenator | `\text` bodies set unhyphenated (sweep `text-*` rows) |
| 81–84 | Math setup: `\scriptspace`, `\nulldelimiterspace`, `\mathcode`, `\overfullrule` | MIXED — mathcode/delcode atom mapping is IN via KaTeX rows; overfull rules are OUT (no page) | Support-table `\mathcode`-class rows; `\overfullrule` N/A |
| 85–99 | Expansion loop: `\xdef`, `\the`, `\number`, `\romannumeral`, `\uppercase`, `\write`, `\outputpenalty` | MIXED — `\edef`/`\xdef` resolve under the `maxExpand` budget (IN); register reads (`\the\count`), `\write`/streams, `\uppercase` on registers are OUT (no registers, no filesystem) | `trip01` (`\edef` + `\expandafter` + `\noexpand`); budget pins in `qa44` |
| 100–129 | Output routine, insertions, marks, `\halign` in output, `\showbox`, `\deadcycles` | OUT — no page builder, no output routine, no insertions/marks | Nothing to pin; `\shipout` N/A by construction |
| 130–168 | Leaders, `\cleaders`, `\mark`, paragraph inserts, `\vadjust`, `\special`, forced breaks | OUT — page/paragraph machinery | `\leaders` N/A; `\mark` N/A |
| 168–188 | Line breaking: `\adjdemerits`, `\linepenalty`, `\valign`, `\noalign`, `\hbadness`, demerit arithmetic | OUT — no line breaker | Demerits N/A; badness N/A |
| 189–210 | Discretionaries, ligatures/kerns, hyphenation torture, `\sfcode`, `\pretolerance`, display-math entry (`$$\eqno^{}$$`, `\mathsurround`) | OUT except the atom kern sliver — ligatures/hyphenation/paragraph math-wrap are OUT | Kern sliver: `qa41` inter-atom glue grid; `\mathsurround` N/A (KaTeX rejects → ZaTeX rejects, sweep `rej-*` parity) |
| 205–310 | **Math list building** (the in-scope heart): `\mathcode`, `\delcode`, active-char delimiters, `\eqno` error paths, `\mathsurround`, `\vcenter`, `\mathaccent`, scripts with `\raise`, `\displaystyle`/`\textstyle`, `\overline`/`\underline`, atom classes (`\mathop`…`\mathinner`), `\limits`/`\nolimits`, `\radical`, `\left…\right`, `\atop`/`\over`/`\above` (+`*withdelims`), `\mskip`/`\nonscript`, `\fam`, `\leqno`, `\predisplaysize` | IN via KaTeX parity — every primitive either has a support-table accept row (pinned geometry) or is a declared reject (KaTeX rejects → ZaTeX rejects) | `trip02` (`\over`/`\atop`/`\above` vs `\frac`); `trip03` (`\left…\right` growth); `trip04` (`\limits`/`\nolimits`); `trip05` (`\overline`/`\underline` rules); `trip10` (`\mathchoice` style branches); `qa43` (styles, limits, fraction shifts); sweep goldens for `\vcenter`, `\mskip`, `\mkern` |
| 300–325 | Boxes: `\lastbox`, `\showbox`, `\accent`, `\spaceskip`, `\penalty-2147483647/8` extremes | OUT as primitives; observability analog is IN | `\showbox` analog: the canonical IR text dump (`invariants.layoutText`, `qa dump` test); penalty extremes N/A (no page breaker) |
| 326–345 | Alignments: `\halign`, `\valign`, `\noalign`, `\omit`, `\span`, `\errmessage`, `\tabskip` | OUT as TeX primitives; KaTeX-level analog (`array`/`matrix`) is IN | Sweep `mat-*`/`array` goldens + `oracle-geometry matrix rows` test |
| 346–350 | Dimension overflow: `\dimen6=-'40000pt` must overflow, `\dimen5` octal edge | IN (inverted: our contract is totality, so extremes saturate/reject, never wrap or crash) | `trip06`: `parse.zig:sizeToEm5` clamps to ±2e9; fuzz probes hold |
| 350–402 | Macro/conditional torture: `\aftergroup`, `\csname`, `\ifcase`/`\ifx`, `\expandafter`, runaway arguments, `\muskip` arithmetic, `\leaders`, `\show`/`\meaning`/`\noexpand`, mode errors (`\moveleft\lastbox` in math) | MIXED — `\expandafter`/`\noexpand` chains and `\muskip` arithmetic are IN; runaways and mode errors are positioned `Invalid` (IN); `\csname`, conditionals, `\meaning`, `\aftergroup`, `\leaders` are OUT (KaTeX rejects → ZaTeX rejects); `\show` is a console no-op (IN) | `trip01` (expansion chains); `trip06` (`\muskip` giants); `trip07` (runaway + double-script rejects with offsets); `trip08` (`\errmessage`/`\message`/`\show` vanish); `parse.zig` "message, errmessage and show are console no-ops" |
| 402–417 | `\everymath`, `\delimiterfactor`, `\left(Aa\right\delimiter` | IN via KaTeX rows | `trip03`; sweep `delim-*` goldens |
| 411–431 | File I/O: `\openin`, `\read`, `\ifeof`, `\input tripos`, `\halign` trickery | OUT — no filesystem in the core | `\input` N/A (KaTeX rejects → ZaTeX rejects) |
| 431–448 | Shipout: `\setbox`, `\vadjust`, `\output`, `\maxdeadcycles`, `\write`, `\escapechar`, final `\showbox9`, `\end` | OUT — no shipout | Nothing to pin |
| tail comment | "things not tested": interaction, system-dependent file names, fatal errors, INITEX-impossible cases, fixed-point edge cases | OUT (explicitly, by Knuth too) | Quoted, not implemented |

## In-scope test index (every IN bit has a regression test)

| Test (`packages/zatex/src/qa.zig`) | TRIP anchor | What it pins |
| --- | --- | --- |
| `trip01 expandafter edef noexpand chains resolve` | ll.85–99, 355–370 | `\expandafter`/`\edef`/`\noexpand` resolve at expansion time under the `maxExpand` budget (budget itself: `qa44`); `\csname`/conditionals stay rejected both sides |
| `trip02 over atop above match frac geometry class` | ll.273–274 (`A\atop…`, `{A\hfil\over B}`) | `\over`/`\above` carry one rule like `\frac`; `\atop` carries none; `\over` spans `\frac` exactly |
| `trip03 left right delimiters grow monotonically` | ll.240–242, 417 | `\left…\right` accepts, holds `invariants`, and grows with content |
| `trip04 mathop forced limits stack in both modes` | ll.270–271 (`\mathop…\limits`, `\nolimits`) | Forced `\limits` stacks in every style, `\nolimits` always sits aside; the display/text contrast for default-limit operators (`\sum`, `\lim`) lives in `qa43` |
| `trip05 overline underline emit one rule` | l.265 (`\overline{…}`, `\underline{…}`) | Exactly one rule, spanning the nucleus |
| `trip06 giant dimensions stay total` | ll.346–350 (octal/`40000pt` overflow edges) | Oversized `\kern`/`\mskip` saturate, never wrap or trap; layout invariants hold |
| `trip07 runaway and double scripts fail positioned` | ll.348–355 (runaways), l.402 (mode errors) | Truncated macro args and `x^2^3` are `Invalid` with KaTeX's 0-based offset |
| `trip08 errmessage message show vanish` | ll.29, 326, 375–390 (`\show…`, `\errmessage`) | Console primitives consume input and emit no node (parse-level pin mirrored at layout) |
| `trip09 tag is the eqno analog` | ll.206, 254, 280, 298 (`\eqno`, `\leqno`) | TeX equation numbers are OUT; the KaTeX analog `\tag` hoists to the display root and only in display mode |
| `trip10 mathchoice picks the style branch` | l.442 (`\mathchoice{}a}{A|}{…}`) | The display/text branch renders per mode (Appendix-G style dispatch, KaTeX spelling) |
| `qa44` expansion/nesting/input caps | TRIP's recursive `\sh` loop (ll.85–88), deep nesting | `max_expand = 1000`, `max_nesting_depth = 32`, `max_input_len = 64 KiB` boundaries exact |
| `qa41` inter-atom glue grid | ll.265–269 (atom-class soup) | Glue widths come from the shared `symbols.glueBetween` table, never re-derived |
| `qa43` styles/limits/fraction shifts | ll.264, 270–274 | Display/text/cramped shifts, limit stacking, `\atop`-class geometry |

## Explicit non-goals

Full TeX compatibility (KaTeX remains the contract per AGENTS.md §1),
page breaking, DVI output, hyphenation, line breaking, insertions/marks,
the output routine, file I/O, TFM fonts, and interaction modes. The pure-TeX
geometry oracle (issue #178, `docs/tex-oracle.md`) covers the Knuth-lineage
second opinion where it matters — box/glue/kern construction — without
making TeX-the-program a gate.
