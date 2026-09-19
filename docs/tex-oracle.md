# docs/tex-oracle.md — Pure-TeX geometry oracle (issue #178)

Knuth-lineage second opinion on box/glue/kern *construction*: stock TeX
Live sets a math snippet to DVI, `dvitype` dumps absolute glyph/rule
positions, and `geometry.py` normalizes the dump to machine-comparable
JSON. It settles "did both engines build the same boxes" disputes
(fraction bars, scripts, delimiters) independent of KaTeX's
reimplementation choices.

## Scope rule (read first)

This oracle is **triage-grade, never a gate** — the same standing as
`docs/oracle-diff.md`:

1. **Never a required gate.** Pixel tests are banned from required gates
   (AGENTS.md §4); geometry counts are text, but the cross-font
   comparison below is still approximate by construction, so the
   workflow is informational (`continue-on-error`, never in any
   required-checks set).
2. **Never an oracle over pinned KaTeX.** KaTeX 0.18.7 remains the sole
   truth for accept/reject and geometry disputes. A MISMATCH means "ask
   why", never "change ZaTeX toward TeX".
3. **Counts compare, metrics never do.** TeX sets Computer Modern;
   ZaTeX measures the host's fonts (or the `irdump` stub advances).
   Advances cannot agree across font designs, so the diff compares
   construction only: glyph-placement count, rule count, and (as a
   diagnostic column) the glyph-code multiset.

## Layout

- `tools/tex-geometry/Dockerfile` — the container: pinned
  `debian:bookworm-slim` digest (same base pin as the oracle-diff
  images), stock Debian TeX Live (`latex` in DVI mode + `dvitype` from
  `texlive-base`, amsmath from `-latex-recommended`, rsfs metrics from
  `-fonts-recommended`), stdlib-only `python3` glue. No network at run
  time.
- `tools/tex-geometry/extract.sh` — the driver: `extract <texfile>
  <display:0|1> <out.json>` (plus a `batch <workdir>` mode mirroring
  `render-one.sh`, so one container covers the whole narrow corpus
  while a TeX error still sinks only its own row). The page style is
  `empty`: the compared property is the formula, and a folio would
  add a spurious glyph to every row. The raw `dvitype` dump is kept
  beside the JSON (`<id>.tex.dump`) for position-level diagnosis, as
  is a raw TeX *render* (`<id>.tex.png`, DVI route: `dvipdfmx` +
  `pdftoppm -png -r 300`, the same raster the luatex oracle uses) so
  the row can go through the shared pixel math below.
- `tools/tex-geometry/tex_score.py` — TeX pixel sims through
  `report.py`'s own `normalize_case` + `sim_pair` (crop+pad+rescale-128
  + centroid-align, block SSIM): raw `<id>.zatex.png` (zatex-png,
  always fresh) vs raw `<id>.tex.png`, writing normalized
  `norm/<id>.tex.png` plus `texsim.json`. Same math and calibration
  as the pixel table — relative triage numbers, never a gate.
  Cross-font spread dominates (CM vs host fonts), so a TeX sim reads
  against its row's LuaTeX sim (same font family, sibling route),
  never against 1.0. `tex_score.py --selfcheck` runs anywhere.
- `tools/tex-geometry/geometry.py` — dump → JSON. Stdlib only;
  `geometry --selfcheck` validates the parser against a canned dvitype
  fixture and runs anywhere (no daemon, no TeX).
- `tools/tex-geometry/corpus.json` — the narrow corpus: three
  oracle-diff rows (`agree-quad`, `frac-basic`, `agree-sum`), so the
  same formulas travel through both the pixel sweep and this oracle.
- `tools/tex-geometry/diff_geometry.py` — the diff: per-row
  `<id>.tex.json` vs `<id>.zatex.json` → `report.md` (worst-first).
  Exit 0 always.
- `tools/ir_dump.zig` (+ `zig build irdump` in `packages/zatex`) —
  the ZaTeX side: one formula → construction-count JSON on stderr
  (the gallery surface: CLI-free, file-free; the driver redirects
  `2>`). Stub metrics (advance 500, rule 40 — the `qa.zig` Stub), so
  the output is deterministic with no fonts and no network. A host
  tool: the shipped lib is untouched, invisible to the size gate.

## JSON schema (`geometry` output)

```json
{
  "tex": "x^2",
  "display": false,
  "tex_version": "TeX 3.141592653 (TeX Live 2022/Debian)",
  "dvi_units": {"num": 25400000, "den": 473628672, "mag": 1000},
  "fonts": {"22": "cmr7", "26": "cmmi10"},
  "glyphs": [{"font": 26, "code": 120}],
  "rules": [{"height": 262144, "width": 524288}],
  "counts": {"glyphs": 1, "rules": 1}
}
```

- `tex_version` is recorded per run (`tex --version`): the apt layer
  is not version-pinned beyond the base-image digest, so every output
  carries the exact engine that produced it instead of trusting the
  Dockerfile comment.
- `glyphs` counts every `set`/`put` char placement in order;
  positioning ops (`right`/`down`/kern) are ignored — construction,
  not metrics. `rules` counts `setrule`/`putrule` (height × width in
  DVI units; at mag 1000 one DVI unit is one sp).
- `font` is the `fntnum`-selected DVI font number at the placement
  (codes are font-slot codes, e.g. display-∑ is cmex slot 88);
  `fonts` maps those numbers to names from the `fntdef` lines
  (`fntdef` carries the opcode length class before the number —
  grounded against real TeX Live 2022 output, see
  `geometry --selfcheck`).
- Empty parse (zero glyphs) fails loudly instead of emitting zeros.

## Reproducibility

- Base-image digest pinned in the Dockerfile (resolved 2026-09-19;
  refresh recipe in the Dockerfile comment, same as
  `tools/oracle-diff/webshot/Dockerfile`).
- `tex_version` in every JSON (see above) — two runs with different
  TeX Lives are distinguishable, never silently merged.
- Canonical bytes: `json.dumps(..., sort_keys=True)`; the selfcheck
  asserts byte-identical re-serialization.
- Local run (needs the daemon):
  `docker build -t zatex-tex-geometry tools/tex-geometry`, then e.g.
  `docker run --rm --network none -v $PWD/work:/work
  zatex-tex-geometry /work/x.tex 0 /work/x.tex.json`.

## Published results

The committed triage report (`zig-out/oracle-diff/report.md`, the same
file the pixel sweep owns) carries a `Pure-TeX geometry oracle` section
with the narrow-corpus verdicts, so the TeX results are visible next to
the pixel rows instead of living only in a workflow artifact.
`tools/tex-geometry/append_report.py <report.md> <texgeo-dir>
[pngdir]` writes it from real CI data (the `tex-oracle` artifact's
`<id>.tex.json` + `<id>.zatex.json` + `texsim.json`): marker-delimited,
idempotent, and loud on missing sides. It also embeds the normalized
TeX renders (`![T](png/<id>.tex.png)`), which must be force-added next
to the report like the other engines' renders — the script refuses to
write the links unless the files already sit in `pngdir`, so a publish
can never leave dead images. Re-run it after any sweep that force-adds
a fresh pixel table, so the tex section is never stranded on a stale
table.

## CI wiring (`.github/workflows/tex-oracle.yml`)

Runs on push to `main`, pull requests, and `workflow_dispatch`, on
`ubuntu-latest` (the daemon runner), `continue-on-error: true` —
informational, never required. The TeX side is a stable reference:
renders restore from cache keyed by `hashFiles('tools/tex-geometry/**')`
and the docker build + extraction are skipped on a hit — engines stay
cold where a render already exists. The ZaTeX side (`irdump`) and the
diff always run fresh; saves are all-or-nothing after a successful
extract, and `workflow_dispatch` takes `force_refresh` to bypass:

1. `geometry.py --selfcheck` (no daemon needed).
2. `zig build irdump` (setup-zig 0.16.0) and dump the ZaTeX side of
   the narrow corpus.
3. `docker build` the image (proves the container still builds
   reproducibly) and `extract` the TeX side of the narrow corpus.
4. `diff_geometry.py` → `report.md`, uploaded as an artifact with both
   JSON sides.

## Non-goals

Replacing the KaTeX contract (AGENTS.md §1 still rules on
accept/reject); page-level layout; absolute positions (deliberately
uncompared — see above); pinning apt package versions beyond the base
digest (the runtime version record covers it); making this a required
check (stays informational until stable, and pixel-grade stability is
explicitly not the bar — construction agreement is).
