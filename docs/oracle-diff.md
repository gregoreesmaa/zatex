# docs/oracle-diff.md — On-demand multi-engine differential renders (issue #39)

`tools/diff-oracles.sh` renders each corpus case in ZaTeX plus 3
independent oracle engines and emits `zig-out/oracle-diff/report.md`
(rows sorted worst-first) so investigator attention goes where ZaTeX
stands alone. It pre-sorts a review queue; it decides nothing.

## Non-goals (read before citing this tool)

1. **Never a CI gate.** Pixel tests are banned from required gates
   (AGENTS.md §4). The workflow is `workflow_dispatch`-only, uploads the
   markdown as an artifact, and is not in any required-checks set.
2. **Never an oracle over pinned KaTeX.** KaTeX 0.18.7 remains the sole
   truth for accept/reject and geometry disputes. `score(c) = max`
   similarity exists so that closeness to *at least one* engine clears a
   row; a 2-vs-1 oracle vote settles nothing.
3. **Oracle disagreement is data, not a verdict.** Rows whose oracles
   disagree among themselves are tagged `spec-ambiguous` — that marks
   spec ambiguity (each engine chose differently), never a ZaTeX bug,
   and nobody "fixes" ZaTeX toward one arbitrary opinion on those rows.

## Engines (all pinned by image digest, no network at run time)

| Service | Engine | How |
| --- | --- | --- |
| `katex-shot` | KaTeX 0.18.7 (the reference) | headless Chromium screenshot (`tools/oracle-diff/webshot/`) |
| `mathjax-shot` | MathJax v3 | headless Chromium screenshot (same image, other entrypoint) |
| `luatex-shot` | TeX Live `pdflatex` → `pdftoppm -png -r 300` | Knuth-lineage opinion (`tools/oracle-diff/texlive/`) |
| `zatex-shot` | This checkout | `zatex-png --px 48` built from the `/repo` mount (`tools/oracle-diff/zatex/`) |

`docker compose -f tools/oracle-diff/compose.yml` builds all 4 services;
every service runs with `network_mode: none`. Base-image digests are
pinned in the Dockerfiles (resolved 2026-09-13; refresh recipe in
`webshot/Dockerfile`). The `zatex` image bakes only the pinned Zig
toolchain — the ZaTeX code under test is the repo mount, so one image
sweeps any checkout.

## Fonts and DPI

Cases enter via mounted files; fonts resolve Latin Modern Math fixture
first, STIX Two fallback — the same order `refhost.zig` uses.
`tools/diff-oracles.sh` stages both into `tools/oracle-diff/fonts/`
(the LM fixture is copied from the repo; STIX Two Math is picked up
from well-known host paths when present).

Two documented approximations (triage-grade, not proof-grade):

- The **web oracles render with their bundled web fonts** (KaTeX /
  MathJax ship their own), not the LM fixture — forcing them onto LM
  would mis-map their glyph ids. The LuaTeX oracle renders Computer
  Modern, the design Latin Modern remakes, so the LuaTeX↔ZaTeX pair
  shares outlines. Font-stack spread is exactly why the score is a max
  and why the `spec-ambiguous` tag exists.
- Absolute scale differs per engine (CSS px × deviceScaleFactor,
  `pdftoppm -r 300`, `--px 48`); the normalization below equalizes it.
  Absolute-size divergences are out of scope here — layout-IR tests own
  those.

## Normalization and scoring (`tools/oracle-diff/report.py`, stdlib only)

Per case: tight-crop each render to its ink bbox (luminance threshold),
pad with a uniform white margin (10px), uniform-rescale (aspect kept)
to height 128, center on the union canvas, compare grayscale with block
SSIM (tolerant to antialiasing, sensitive to structural shifts like
misaligned fraction bars or drifting accents).

- `score(c) = max_i sim(ZaTeX_c, Oracle_i_c)` — low max ⇒ solo outlier
  ⇒ investigate first. Rows sort by score ascending.
- `spread(c) = min` oracle↔oracle similarity; `spread < 0.90` tags the
  row `spec-ambiguous`.
- Each row shows the LaTeX source, the score, all 3 per-oracle
  similarities, the spread, and the 4 normalized renders.

## Sanity check

The curated fixture (`tools/oracle-diff/corpus.json`) covers the known
#30–#38 divergences (accents, wide accents, fractions, matrices, fonts,
colors, spacing, missing glyphs) plus boring-agreement rows. After a
real sweep, the bottom (high-score) rows should be the agreement cases
and the top rows should reproduce the #30–#38 divergences — if the
funnel points elsewhere first, suspect the tool before the engine.

## Verification boundary

`report.py --selfcheck` (SSIM math unit checks + synthetic end-to-end
fixture report: sorting, scoring, ambiguous tagging) runs anywhere;
`docker compose config` validates the sweep plumbing without a daemon.
Full sweeps need the daemon (`tools/diff-oracles.sh` builds the images).
