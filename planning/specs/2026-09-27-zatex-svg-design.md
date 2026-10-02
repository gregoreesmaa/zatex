# zatex-svg Design (2026-09-27)

LaTeX math → standalone SVG, as a new `packages/zatex-svg` package over the
`zatex` core. Status: approved for implementation (outlines route, below).

## Terminology (settles the font Q&A)

"Outlined paths" means extracting the font's own vector graphics — the
cubic Bézier outlines already in the font file (CFF/Type2 charstrings,
read through the `zatex` package's host-side `cff` build module —
host/tool code, never linked into the core dist lib, wired via
`zatex_dep.module("cff")`/`module("otmath")` exactly like `zatex-png`)
— and emitting them as SVG `<path d="...">` elements. There is no tracing, no bitmap
step, no curve approximation: the same mathematics the software
rasterizer in `zatex-png` fills, written out as path data with a
coordinate transform plus fixed-precision number formatting.

The rejected alternative was embedding the font source (`@font-face` +
`<text>`): the reference font is 720 KB on disk (~960 KB base64'd into
every SVG), subset-embedding needs a font *writer* that does not exist
in the repo, and viewer shaping/hinting would add variance. Outlines
are both smaller (KBs per formula) and more accurate (exact curves from
the same files the layout was measured with; zero viewer font risk).
Embedded-font `<text>` stays a documented follow-up (selectable text,
amortized size for multi-formula documents), not this PR.

## Goal

One formula in, one self-contained `.svg` out: byte-deterministic,
viewer-font-independent, geometrically exact to the core layout.

## Non-goals (this PR)

- C ABI (`zatex_svg_utf8` needs a provider + font-bytes design of its
  own; unlike MathML it cannot be self-contained — follow-up).
- Embedded/subset-font `<text>` mode (follow-up behind the same seam).
- PNG-style multi-backend matrix (SVG has no rasterizer; one walker).

## Architecture

Thin geometric walker over `ir.Layout` (runs + rules), mirroring
`packages/zatex-png/src/render.zig`. `AGENTS.md` §2 compliance:

- No layout math in the emitter: positions come from the core, the
  walker only scales/transcribes them.
- No `MetricsProvider` inside the emitter (measuring is impossible
  there by construction, same as MathML).
- Zero heap allocations: caller-owned `out` buffer plus caller-owned
  scratch; `NoSpace` on overflow, never panic.
- Deterministic: integer-unit `viewBox`, fixed-precision decimal
  writer (no platform float formatting), stable glyph/element order.

SVG positions are y-down like the core, so they need no flip (unlike
PNG's Quartz y-up flip in `render.zig`). Glyph *ink* does: `cff.Seg`
is y-up like CFF, so every outline segment's y negates about the
baseline during transcription — an implementer reading "no mirror"
literally would emit upside-down glyphs.

## Components (`packages/zatex-svg/`)

- `build.zig` / `build.zig.zon` — path-dependency on `../zatex`
  (same shape as `zatex-mathml`); core never depends back. Dist libs
  ship `ReleaseSmall` static + dynamic.
- `src/zatex_svg.zig` — package root: re-exports, wires `refAllDecls`
  test roots (per `tools/check_test_roots.sh`).
- `src/svg.zig` — the walker: `renderLayout(layout, outlines, out)`
  plus one-shot `render(source, options, provider, outlineProvider,
  run/rule/glyph bufs, out)`. The one-shot is CLI glue, not emitter
  surface: it carries a stated same-files agreement (the measuring
  provider and the outline faces are the same files), so no
  `MetricsProvider` lives inside the emitter proper per §2.
- `src/outlines.zig` — `OutlineProvider` callback seam (glyph →
  segments into caller buffer; stub-testable) plus the blessed
  stack-backed file implementation over the host-side `cff`/`otmath`
  modules. `Run.glyphs` are unified host-namespace ids (`base + face
  gid`), while `cff.outline` takes a face-local CFF index — so the
  blessed implementation holds one `CffFont` per stack face and demuxes
  via `faceOf`, exactly like PNG's per-face `drawFace`. Rule: outline
  files must be the files the provider measured with (same rule as
  `zatex-png/src/font.zig`); single-face outlines are wrong for
  multi-face formulas (AMS, bold, Size1/Size2 live on other faces).
  Missing glyph skips ink but steps the pen by the `500` fallback
  (unowned id or `advance` failure), scaled by `size_units`/`x_scale`
  with `divTrunc` — the exact PNG rule. Per-glyph outline failure
  (`BadCharstring`, seg-buffer `OutOfSpace`) never surfaces: skip ink,
  keep stepping (PNG's `catch return` totality); only startup
  file-load failure is a CLI usage error. The plan must verify every
  default-stack face `cff.load`s; goldens stay on CFF-backed faces.
- `src/main.zig` — thin CLI: `zatex-svg [--display] [--font PATH]
  "<tex>" out.svg`. Delta from `zatex-png` is explicit: `--display`
  and `--font` kept, no `--px` (vector), no `--corpus` batch mode
  (follow-up #3). Default is the same 17-entry fixture stack, same
  CWD-relative `../zatex/fixtures/...` assumption from
  `packages/zatex-svg/`; `--font PATH` keeps the legacy single-file
  host.
- Test roots mirror mathml's single-root `refAllDecls` shape (one
  walker, not PNG's five-root backend matrix). Build passes
  `.cabi=false` to the `zatex` dependency (no C entry this PR, but a
  host linking `libzatex.a` + `libzatex_svg.a` must not see duplicated
  core exports — the same duplication rationale as mathml);
  `build.zig.zon` gets a fresh `fingerprint`. `check_test_roots.sh`
  scans flat `src/*.zig`, so all walker sources stay flat and the
  script's package loop gains `packages/zatex-svg`.
- `src/goldens/` — checked-in `.svg` snapshots for byte-compare tests.
- `README.md` — usage, layout map, verification boundary.

## SVG mapping (pinned requirements)

- Skeleton: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="…"
  width="…em" height="…em">`, element order **rules then runs** (PNG
  paint order — colorbox backgrounds overlap ink), `stroke-linecap`
  butt on diag strikes per `docs/ir.md`.
- `viewBox="minX 0 totalW totalH"`, all integer font units:
  `left`/`right` replicate PNG's `leftShiftUnits`/`rightShiftUnits`
  walk (integer advances, ink left/right, shear extremes via
  ink top/bottom, mirrored branches, rule rect edges);
  `minX = −left`, `totalW = width + left + right`,
  `totalH = height_above + depth_below`. No vertical expansion
  (matches PNG). `width`/`height` are `units/1000` em.
- Glyphs → `<path>` with **baked** coordinates (no per-glyph
  `transform` — baking keeps determinism in our writer and avoids
  viewer transform rounding). Per point, mirroring PNG's
  `drawGlyph`/`flatten` order exactly, with the y-negation folded in
  (SVG y-down, baseline at `oy`, per-face `upm`, `s = size_units/upm`,
  `kx = x_scale/1000`, `kh = x_shear/1000` (both IR fields are
  per-mille), `mx = mirrored ? −1 : 1`):
  `X = ox + mx·s·kx·x + mx·kh·(y·s)`,
  `Y = oy − s·y` — shear applies at the segment level before curve
  subdivision, mirror negates both x-scale and slant.
- Outline scaling is `outline_font_units × size_units / upm`
  (PNG's `scale = size_px / upm` with SVG units standing in for px).
- Paint: per-run `<g fill>` from `0xRRGGBBAA` (null = black) **and**
  per-rule paint the same way — rules carry their own `color`
  (`setPaint` parity). Hex lowercase; opacity is `A/255`.
- `Rule` (`diag == .none`) → `<rect>`; `diag != .none` (`\cancel`
  family) → corner-to-corner `<line>` with `stroke-width = thick`.
- Numbers: fixed-precision decimal writer — 2 places after the point,
  round-half-away-from-zero, trailing zeros stripped, `−0` normalized
  to `0`. Snapshots enforce the policy byte-for-byte.
- No source echo: nothing textual is emitted (all paths/rects), so no
  XML escaper ships in this PR. `TooLong` guard on input length.

## Error handling

Core `LayoutError` set reused end-to-end — all 7 variants:
`Unsupported`, `Invalid` (+ offset via the one-shot path), `TooDeep`,
`TooLong`, `ExpansionLimit`, `NoSpace` (any buffer exhaustion incl.
tiny-`out` probes), `OutOfMemory` (reserved; mapped to `NoSpace` at
any boundary, the mathml `cabi.zig` precedent). No new error kinds:
per-glyph outline failures resolve to skip-ink totality inside the
walker, never to errors.

## Testing (heavy)

- Unit tests per file: number writer vectors, escaping, viewBox +
  overflow shifts, color/diag/scale/shear/mirror mapping, provider
  seam with stubs (missing glyph, zero advance, adversarial).
- Golden snapshots: ~30–50 formulas (frac, sqrt nesting, sum/limits,
  accents incl. wide, colors/boxes, cancel, matrices, scripts)
  byte-compared against checked-in `.svg`. Goldens assert no absolute
  paths (fixture path arrives via `build_options`, absolute by
  construction) and stay on CFF-backed faces.
- Error matrix: all 7 `LayoutError` variants incl. tiny-buffer
  `NoSpace`; determinism (same input twice → identical bytes, plus
  rules-before-runs order, em-dims formatting, and a
  mirrored+sheared+scaled glyph vector — the three transforms compose,
  which is where a bake-order bug hides);
  adversarial/fuzz totality (same seed/pieces shape as the core).
- Gates: `zig build test --summary all` in the new package (a new
  *step* in ci.yml's single `test` job, not a new job),
  `tools/check_test_roots.sh` extended to `packages/zatex-svg`,
  core `tools/size_gate.sh` unaffected (it measures only the core
  `libz*.a`; the new package's own ReleaseSmall libs have no gate —
  stated, not silent).

## PR scope

Branch `feat/zatex-svg` → PR against `main`: package + CLI + tests +
CI job in `.github/workflows/ci.yml` + `README.md` package-table row
+ `docs/ir.md` "SVG is future" → shipped update. No golden changes
needed (new package owns its goldens).

## Follow-ups (not this PR)

1. C ABI entry with provider + font-bytes design.
2. Embedded-font `<text>` mode (selectable text use case).
3. Corpus batch mode for the CLI if manual verification wants it.

---

**Next**: your review of this spec; then the implementation plan via the writing-plans skill.
