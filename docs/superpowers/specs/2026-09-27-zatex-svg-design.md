# zatex-svg Design (2026-09-27)

LaTeX math → standalone SVG, as a new `packages/zatex-svg` package over the
`zatex` core. Status: approved for implementation (outlines route, below).

## Terminology (settles the font Q&A)

"Outlined paths" means extracting the font's own vector graphics — the
cubic Bézier outlines already in the font file (CFF/Type2 charstrings,
read through the core's shared host-side `cff` module) — and emitting
them as SVG `<path d="...">` elements. There is no tracing, no bitmap
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

SVG is y-down like the core, so there is no coordinate mirror (unlike
PNG's Quartz y-up flip in `render.zig`).

## Components (`packages/zatex-svg/`)

- `build.zig` / `build.zig.zon` — path-dependency on `../zatex`
  (same shape as `zatex-mathml`); core never depends back. Dist libs
  ship `ReleaseSmall` static + dynamic.
- `src/zatex_svg.zig` — package root: re-exports, wires `refAllDecls`
  test roots (per `tools/check_test_roots.sh`).
- `src/svg.zig` — the walker: `renderLayout(layout, outlines, out)`
  plus one-shot `render(source, options, provider, outlineProvider,
  run/rule/glyph bufs, out)`.
- `src/outlines.zig` — `OutlineProvider` callback seam (glyph →
  segments into caller buffer; stub-testable) plus the blessed
  file-backed implementation over the core's host-side `cff`/`otmath`
  modules. Rule: outline files must be the files the provider measured
  with (same rule as `zatex-png/src/font.zig`). Missing glyph skips
  ink but steps the pen (same rule as PNG).
- `src/main.zig` — thin CLI: `zatex-svg [--display] [--font PATH]
  "<tex>" out.svg` (same flags shape as `zatex-png`).
- `src/goldens/` — checked-in `.svg` snapshots for byte-compare tests.
- `README.md` — usage, layout map, verification boundary.

## SVG mapping (requirements, exact helpers to the plan)

- `viewBox` in integer font units covering ink (core y-down box),
  with PNG-style left/right overflow shifts so `\llap`/`\minuso`-type
  ink is not clipped; `width`/`height` in `em`.
- Glyphs → `<path>`; per-run `<g fill="#RRGGBB" fill-opacity="…">`
  from the core's `0xRRGGBBAA` (null = black).
- `Rule` (`diag == .none`) → `<rect>`; `diag != .none` (`\cancel`
  family) → `<line>` with `stroke-width = thick` corner-to-corner.
- `x_scale` → scale transform about the run origin; `x_shear` →
  skew; `mirrored` → horizontal flip about the glyph origin (core
  pre-maps origins; the walker only flips ink, same split as PNG).
- XML-escaping for any text content (`<annotation>`-style source
  echo if included); `TooLong` guard on input length.

## Error handling

Core `LayoutError` set reused end-to-end (`Invalid` + offset via the
one-shot path, `TooDeep`, `TooLong`, `ExpansionLimit`, `NoSpace` on
any buffer exhaustion incl. tiny-`out` probes). No new error kinds.

## Testing (heavy)

- Unit tests per file: number writer vectors, escaping, viewBox +
  overflow shifts, color/diag/scale/shear/mirror mapping, provider
  seam with stubs (missing glyph, zero advance, adversarial).
- Golden snapshots: ~30–50 formulas (frac, sqrt nesting, sum/limits,
  accents incl. wide, colors/boxes, cancel, matrices, scripts)
  byte-compared against checked-in `.svg`.
- Error matrix: every `LayoutError` variant incl. tiny-buffer
  `NoSpace`; determinism (same input twice → identical bytes);
  adversarial/fuzz totality (same seed/pieces shape as the core).
- Gates: `zig build test --summary all` in the new package,
  `tools/check_test_roots.sh` extended to `packages/zatex-svg`,
  core `tools/size_gate.sh` unaffected (SVG never links into the
  core dist lib).

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
