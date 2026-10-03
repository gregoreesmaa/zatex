---
layout: page
title: ir.md — ZaTeX layout IR
---

# docs/ir.md — ZaTeX layout IR (output contract)

One layout core, many emitters. The core parses KaTeX-compatible input,
expands macros (bounded: `maxExpand` = 1000, KaTeX parity), lays out TeX
boxes, and emits a `ir.Layout`: glyph `Run`s plus `Rule` rects in
**integer font units** (`i32` positions, `u32` extents; `u16` glyph IDs
and sizes). Integer units keep output byte-deterministic across hosts —
no untracked float in the contract.

## Roles

* **Core** owns positions. It never draws, never rasterizes, never touches
  a font file. Glyph advances and variant/parts data arrive through the
  host's font-provider callback (metrics for the host's font, so output
  is always correct for the font actually drawn).
* **Hosts** (`read`, other apps) draw `Run`s through their own glyph
  cache/atlas and fill `Rule`s as rects. This is the fastest path: zero
  parsing and zero rasterization at showtime. A `Rule` with a non-`none`
  `diag` strokes a `thick`-wide butt-cap diagonal across its rect
  instead (`\cancel` family, issue #107) — hosts without line stroking
  skip those rules rather than filling the rect. Hosts with font file
  bytes skip hand-rolled parsing entirely via the blessed file-based
  provider (see `docs/file-provider.md`, issue #192); the gid-namespace
  handshake there decides when file gids may be drawn through a
  platform shaper.
* **Emitters** walk the same tree: MathML ships in
  `packages/zatex-mathml`, `packages/zatex-png` renders PNG
  (macOS-only backend), SVG ships in `packages/zatex-svg`.
  Emitters contain no layout math. Trust posture for embedding the
  MathML (sanitizer allowlist, CSP, URL filtering) lives in
  `docs/parity.md` ("Host security guidance") — the engine applies
  no protocol gate, the host owns it.

## Stable calling contract (frozen 2026-09-12)

`layout(source, options, provider, runs, rules) LayoutError!Layout` —
one pass, caller-owned buffers, zero allocations. `options` fields gain
defaults; `LayoutError` variants are added, never removed;
`MetricsProvider` callbacks arrive with a `provider_version` bump.
Hard caps are named constants (`max_input_len`, `max_nesting_depth`,
`max_expand`). Call-site shape is frozen; only additive growth.

## Host layout-cache guidance (issue #290)

The engine is zero-alloc and reentrant, but it always replays the
full parse+layout pipeline per call — an animation or resize loop
pays full price every frame (layout is ~50% of short-formula time).
Hosts that re-render the same formulas cache at the layout level;
the engine stays cache-free (no shared mutable state per
`docs/threading.md`), so the cache is host-owned.

**Cache key.** The layout output is a pure function of exactly:

1. the source bytes (`tex_bytes`),
2. the full `LayoutOptions` (`display_mode`, `leqno`, `fleqn`,
   `min_rule_thickness_milli_em`, `strict`, `global_group`, and the
   `macros` preset list — `strict: err` rejects inputs `warn`
   accepts, and presets/`globalGroup` change expansion),
3. the provider identity: `provider_version` plus a hash of the font
   files (or shaper state) behind the `MetricsProvider` — metrics
   are the only font truth the core sees,
4. the engine version (bump on upgrade).

Hash all four (`hash(tex_bytes, options, provider_version,
font_file_hashes, engine_version)`); on any miss, re-layout.

**Cached value.** Deep-copy the `Layout` scalar (`width`,
`height_above`, `depth_below`) plus the `runs` / `rules` arrays and
the `glyphs` backing store into host memory (the caller's buffers
are borrowed — see `docs/threading.md` — so the copy must own its
bytes), plus whatever the host derives downstream (viewport shifts,
atlas uploads, bitmap/SVG bytes). Cap the map (LRU, bounded count
or bytes); layout output is deterministic, so entries never go
stale except by key change.

**What reuses the cache.** Resize/pan/zoom reuses the layout entry:
geometry is in integer font units (resolution-independent), so only
the rasterization scale changes. A `display_mode` flip, an options
change, a font swap, or a provider upgrade is a different key —
never reuse across those.

## Provider exactness contract (host guide, issue #193)

Every numeric provider value is in thousandths of an em (1000 units =
1em at text size); the core scales to the ambient size itself with
truncation toward zero. Normative per-hook text lives in
`packages/zatex/src/contract.zig` (`MetricsProvider` doc comment) and
in `packages/zatex/src/zatex.h` field comments; what follows is the
host-oriented reading: what to return, what branches on it, and what
breaks when it is wrong.

| Hook | Return | Load-bearing consumers / failure symptom |
| ---- | ------ | ---------------------------------------- |
| `glyphId` | Host-namespace id; 0 = missing (issue #142) | Everything. 0 still lays out, so boxes/tofu always trace back here — log the (font, cp) pairs. |
| `advance` | hmtx advance in thousandths, trunc-zero — **bit-for-bit, including 0** for zero-width combining marks | Every run width. `layoutAccent` branches on `adv == 0` (ink-center vs advance-box); a nonzero fallback (e.g. 500) for a zero-width mark mis-centers the accent by ~half an em. |
| `ruleThickness` | Weight in thousandths; `<= 0` reads as 40 (plus the caller's `min_rule_thickness` floor) | Fraction bars, radicals, over/underlines and their clearances. Wrong weights thicken bars and shift gaps. |
| `extents` (null ok) | `[height_above, depth_below]` at 1000 units (`[0,0]` if blank); null derives the ink vertical slice when ink is present (issue #206: `ha = max(0, y1)`, `db = max(0, -y0)`), else uniform 700/250 | Every box height/depth; accent clearance `min(body, x-height 431)`; brace-label gaps; fence choice. True extents shift vertical clearance vs the reference. |
| `glyphVariant` (null ok) | Variant with extent `>= min_height` (thousandths), or the input glyph | Fences, radicals. Always-identity under-grows tall spans. |
| `italicCorrection` (null ok) | MATH italic correction in thousandths, trunc-zero; null = 0 (no RSB fallback: issue #206 rejects it — measured RSB anti-correlates with MATH corrections) | Accent shift over slanted nuclei: the core halves it and adds the KaTeX Math-Italic skew (single-symbol nuclei only). Wrong glyph or wrong units shift every such accent. |
| `kernCorrection` (null ok) | MathKern cut-in in thousandths; null/0 = none | Top-right tucks superscripts, bottom-right subscripts (clamped to the gap). Costs only looseness. |
| `inkBounds` (null ok) | `[x_min, y_min, x_max, y_max]` at 1000 units, **y up**, unclipped (negatives kept); all-zero = blank, ignored; ±1 float rounding ok | Accent ink-centering, low-accent lift (≥ 130 clear), wide-accent ink scaling, dot lift, brace-label/brace kerns, sqrt junction, `\not` centering. Null = exact v3 behavior per construct (priced in `contract.zig`). |

### Worked recipe: `\tilde{x}` and `\vec{v}` at text size

A new host must return these values — no engine reading required:

1. `advance` must be the font's real advance, including **0 for the
   combining arrow U+20D7** (`\vec`). Any nonzero fallback (500 is the
   classic) sends `\vec{v}` down the advance-box path instead of the
   ink-centering path `ax = (nucleus_w − ink_w) / 2 − ink_x0 + shift`.
   With U+20D7 ink `[-472, 521, -56, 711]` (width 416, hanging left of
   its zero origin), the correct offset recenters that 416-wide ink
   over the nucleus; the fallback centers a phantom 500-wide box.
2. `inkBounds` for `~` (`\tilde`) is `[0, 193, 555, 307]`, y up. The
   core lifts low accents so ink clears the nucleus top by ≥ 130:
   `ay = nucleus_top + 130 − 193`. For an `x` nucleus (top 700) that
   is `ay = 637` (total height 1337) — without the hook the accent
   would nestle to within 12 units of the nucleus.
3. `italicCorrection` is looked up on the **laid-out** glyph, so the
   host just reports the MATH table value per glyph id (scaled,
   trunc-zero); the core does the halving and the skew. `x` carries
   KaTeX skew 28, so the tilde run starts at +28 over the nucleus —
   report the raw correction and centering follows.

### Traceability (the `read` host's three bugs)

- **T1 — 500-for-zero-width fallback:** fixed by the `advance` row's
  "bit-for-bit, including 0" plus the `adv == 0` branch note.
- **T2 — italic lookup on the parse codepoint / unscaled units:**
  fixed by the `italicCorrection` row's laid-out-glyph + thousandths
  wording (`y`: text 8 vs math-italic U+1D466 28 = 10mu at text size).
- **T3 — ink frame guesses / unknown NULL cost:** fixed by the
  `inkBounds` row's y-up/unclipped wording plus the per-construct NULL
  price list in `contract.zig`.

## Stretched runs across the C ABI

`Run.x_scale` (per-mille horizontal scale, 1000 = identity) crosses
the C ABI as `zatex_run_t.x_scale` (issue #197: wide accents, braces,
arrows). Hosts stretch the run's ink AND its intra-run pen advances
by `x_scale`/1000 about the run origin (`x`, `baseline_y`) —
CoreText: save, translate to the origin, scale x, draw, restore.
Without it wide accents render at natural size, off-span.

Rounding contract (issue #272, decided: u16 per-mille kept — float
would only re-encode the truncated ratio with binary error, and the
core stays integer-only). The engine computes
`trunc(span*1000/nat)` — truncation toward zero, clamped to u16
(stretch-only paths keep 1000 unless the span exceeds the natural
width; fitting paths floor at 1). Hosts truncate pen advances the
same way (`(step*x_scale)/1000` in integer math, as zatex-png
`render.zig` does) and use `x_scale/1000.0` in double for raster
scale. Pinned by the `cabi x_scale is truncated per-mille` test
(1000-span over a 600 advance lands exactly 1666, not 1667).

Stride contract (issue #203): appending `x_scale` changed the array
stride (20 → 24 → 28 with the `color` tail, issue #251), so a new
dylib writing full structs into an old host's 20-byte slots would
scramble every run past the first. The `err_msg` "old readers ignore
the tail" rule holds for single structs only — never for array
elements. Instead the runs buffer is stride-negotiated:
`zatex_layout_utf8` is frozen as the v1 entry (20-byte
`zatex_run_v1_t` slots, prefix only, never `x_scale`, never `color` —
safe with any dylib/host mix, drawn unstretched in the ambient paint
exactly as before), and `zatex_layout_utf8_ex` takes the host's
element size (`sizeof(zatex_run_t)`): the engine writes the 20-byte
prefix always, `x_scale` only when the stride reaches byte 22, and
`color` (0xRRGGBBAA, 0 = ambient) only when it reaches byte 28,
leaving every other tail byte untouched; strides below 20 fail with
status 7 (limit). Hosts wanting the tails dlsym the `_ex` entry and
fall back to the v1 entry when absent (old dylib) — or negotiate
once via `zatex_capabilities()` (issue #262) and branch on
`ZATEX_CAP_X_SCALE`/`ZATEX_CAP_RUN_COLOR` instead of per-symbol
probing.

One mechanism (issue #271): the per-field stride writes from
#197/#203/#251 now live in a single field table (`run_tail_fields`
in `cabi.zig`, exercised by the `cabi run tails cross complete
fields only` test over every stride 20..40) — future tails append
table rows, never new branches. The stride parameter IS the size
negotiation for run arrays (a first-field size cannot stride an
array, so the run struct carries none — single structs grow
append-only instead). `ZATEX_RUN_SIZE_V1` (20) and
`ZATEX_RUN_SIZE_CUR` (28) name the only two sizes a published header
ever produced; old hosts stay bit-identical.

Space failures (issue #263): on status 6 (no_space) and 7 (limit),
`out->nruns`/`nrules` carry the counts the formula actually needs,
so hosts allocate exactly once instead of guess-and-double. Zeroed
counts mean the need exceeds the engine ceilings (fail with a
message) or the call never reached layout; a null runs/rules/glyphs
buffer is a sizing probe (status 6 with the needs). Glyph needs have
no field — after exact-sizing runs/rules, a second failure means the
glyph buffer is short, so grow it and retry.

## Errors across the C ABI

Zig callers read `Diag{offset, message}` from `layoutDiag`. C
callers read the same two facts from `zatex_layout_t`: `err_offset`
plus `err_msg`/`err_msg_len` (pointer + length into static storage —
always valid, never freed, NOT null-terminated; NULL/0 on success).
The message is what the host renders in its error fallback: source
text plus message bytes as real text (never hover/tooltip alone),
conventionally painted `#cc0000` — the full recipe lives in
`docs/parity.md` ("Error fallback (host recipe)"). `zatex_mathml_utf8`
(living in `packages/zatex-mathml`, alongside the core library)
returns only a status (bytes written or `-status`); hosts needing the
message call the layout entry for the same input.

Typed code (issue #273): `zatex_layout_t.err_code` refines `status`
with one `ZATEX_ERR_*` value (0 on success) so hosts branch on the
retry policy without parsing the message. The three `OVERFLOW_*`
codes compose with the need-counts above — they always carry the
exact needs in `nruns`/`nrules` (retry once, grown; the code names
the first short buffer in runs/rules/glyphs priority, and a
null-buffer probe names its first null the same way).
`ERR_NO_SPACE` carries zeroed counts (even maximum buffers cannot
succeed — fail with a message) and `ERR_LIMIT` names a request-shape
problem (over-ceiling caps, short stride). The field is append-only
(old readers ignore the tail); gate reads on
`ZATEX_CAP_ERR_CODE` and zero-initialize the layout struct, since a
dylib predating the bit never writes the field. Pinned by the
`cabi err_code refines status` test.

## Metrics conformance

`zatex_conform_metrics(metrics, font, buf, buf_cap)` runs a diagnostic
corpus against an arbitrary host provider at the C ABI level — no
engine rebuild, no rendering. It returns the diagnostic count (0 is a
clean pass; -1 is a usage error: null metrics, or a non-null buf with
zero cap). A non-null buf receives newline-separated diagnostics,
whole lines only, always NUL-terminated; a null buf counts without
writing, so the count is exact past any buffer. The same corpus is
available natively as `conform.check(provider, font, buf)`.

The corpus pins reference-font (Latin Modern Math) ground truth for
`rm` (font 0): zero-width combining marks (the 500-for-zero trap),
slanted italic nuclei, exact advances, `.notdef` mapping to glyph 0, a
growing paren variant, the four MATH rule weights, representative ink
boxes, and a two-formula layout smoke test. Other font ids run the
same probes; differences report by name (font, codepoint, got, want),
so multi-face hosts can triage them — e.g. a text face without a MATH
table legitimately reports no italic there.

Each mismatch names itself; the three historical provider bugs read:

* `italic hook: NULL (want MATH corrections)` — missing hook
* `advance U+20D7: got 500, want 0` — zero advance reported as 500
* `ink hook: NULL (want ink boxes)` — missing hook

The reference provider (`refhost.zig`) passes cleanly; its tests
reintroduce each bug and assert the named line, natively and through
the C entry.

## Reference rendering

Latin Modern Math is the reference font (Computer Modern look is part of
compatibility). Vendored only as a test fixture for differential goldens
against KaTeX — never in the core, never a link dependency.

