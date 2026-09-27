# ZaTeX host-facing changelog (issue #260)

ABI changes, new optional hooks, and deprecations — the entries a
host integrator needs to upgrade deliberately instead of by
surprise. **Maintainers: append here with every entry-point,
struct, or hook change** (additive or breaking), before merging.

## Unreleased — no GitHub releases yet

No versioned binaries are published yet (see issue #259); the
recipe lands with the first `v*` tag. Current source state for
hosts building from source:

- Library version `0.0.0` (`contract.version`, `build.zig.zon`);
  `zatex_version()` packs it as `major << 16 | minor << 8 | patch`.
  Pre-release: hosts should require an exact match, not a range.
- Provider version 4 (`contract.provider_version`). Hooks:
  required `glyphId` / `advance` / `ruleThickness`; optional
  `glyphVariant`, `italicCorrection`, `kernCorrection` (v3),
  `extents` + `inkBounds` (v4). NULL for an optional hook keeps
  exact previous behavior per construct (see the `MetricsProvider`
  contract in `contract.zig` for the per-hook NULL price).
- Entry points: `zatex_layout_utf8` (frozen v1, 20-byte run slots)
  and `zatex_layout_utf8_ex` (stride-negotiated, carries `x_scale`);
  `zatex_version`; `zatex_conform_metrics` (provider conformance
  check, issue #194 — run it when bringing up a new font).
- Run shape `zatex_run_t` is 28 bytes (`x_scale` appended, issue
  #197; `color` tail, issue #251); the layout shape gains an
  `err_code` tail (issue #273). Rules, extents, and ink-box shapes
  are unchanged.
- Unreleased additive ABI (issues #251, #262, #263; PR #268):
  `zatex_run_t` gains an optional 4-byte RGBA `color` tail at bytes
  24..28 (0 = ambient), written only when `runs_stride >= 28` —
  24-stride hosts stay bit-identical. New `zatex_capabilities()`
  bitmask (`X_SCALE | RUN_COLOR | NEED_COUNTS`); per-symbol `dlsym`
  probing still works. `STATUS_NO_SPACE` / `STATUS_LIMIT` now carry
  exact `nruns`/`nrules` needs (zeroed = exceeds engine capacity);
  NULL buffers act as sizing probes. Size baseline ratcheted
  320000 -> 320112 for this surface (precedent: 9e70d53).
- Layout corrections, issues #253/#254/#255 (PR #269, KaTeX-measured
  proof in the PR body): accent boxes stack with no minimum-gap
  floor (floor kept only for `\dddot`/`\ddddot` periods); large-op
  scripts stack off the rendered Size1/Size2 face; radical
  construction top IS the vinculum bar (KaTeX Rule 11). Visible
  geometry moves in accents/sums/sqrts; screenshot and parity-kit
  baselines re-rendered against the pinned KaTeX oracle. Size
  baseline ratcheted 320112 -> 323536 (KaTeX TFM data tables + one
  shared ink walker; precedent: 9e70d53).
- Caps (part of the contract): 256 runs / 64 rules per call,
  65536 input bytes, `maxExpand` 1000, nesting depth 32.
- Option knobs added since the freeze (all default-off, additive):
  `min_rule_thickness_milli_em`, `strict` + `StrictLog`,
  preset `macros`, `global_group`, `leqno`, `fleqn`.
- Unreleased additive ABI (issues #271, #272, #273):
  one run-tail field table behind every layout entry (issue #271;
  `run_tail_fields` in `cabi.zig`, superseding the per-field stride
  writes from #197/#203/#251 — behavior bit-identical, exercised
  over every stride 20..40). The stride parameter IS the size
  negotiation for run arrays (a first-field size cannot stride an
  array); `ZATEX_RUN_SIZE_V1` (20) / `ZATEX_RUN_SIZE_CUR` (28) name
  the only two published element sizes. Host action: none — old
  hosts are bit-identical; new tails will append table rows, never
  new branches.
- `x_scale` rounding contract (issue #272, decided — no wire
  change): u16 per-mille kept. The engine computes
  `trunc(span*1000/nat)` (truncation toward zero, clamped to u16);
  hosts truncate pen advances the same way and use
  `x_scale/1000.0` in double for raster scale. Float was rejected:
  it would only re-encode the truncated ratio with binary error,
  and the core stays integer-only. Pinned by test (1000-span over a
  600 advance lands exactly 1666, not 1667).
- Typed `err_code` on `zatex_layout_t` (issue #273, additive tail —
  old readers ignore it): one `ZATEX_ERR_*` value refines each
  status (`BAD_TEX`, `UNSUPPORTED_CMD` (reserved), `TOO_DEEP`,
  `OVERFLOW_INPUT`, `EXPANSION_LIMIT`, `OVERFLOW_RUNS/RULES/GLYPHS`
  with the issue-#263 needs, `NO_SPACE` with zeroed counts,
  `LIMIT`). New `ZATEX_CAP_ERR_CODE` bit guards reads: a dylib
  predating it never writes the field, so zero-initialize the
  layout struct and read the code only when the bit is set. Host
  action: recompile against the new header (pre-1.0 exact-match
  rule already requires it) and branch retries on the code instead
  of parsing `err_msg`.

## 2026-09 — stride-safe run contract (issue #203, seeded entry)

`x_scale` (issue #197) was appended to `CRun`, growing array
elements 20 → 24 bytes while the layout entry still strode by
`@sizeOf(CRun)`. Hosts compiled against the 20-byte struct silently
scrambled every run past the first against a new dylib (and past
`nruns > 213` wrote out of bounds) — no status code, pixel
scramble only. The installed dylib still strode 20, so the break
was latent until the next dylib update.

Fix (the current contract, additive): the v1 entry
`zatex_layout_utf8` strides 20 forever and never writes `x_scale`
(old hosts stay bit-identical across dylib updates); the new
`zatex_layout_utf8_ex` entry negotiates stride via the host's own
`sizeof` and writes `x_scale` only when the stride admits it.
Host action: hosts wanting `x_scale` `dlsym` the `_ex` entry and
fall back to the v1 entry when absent (old dylib) — see
`docs/install.md`. This is why the install recipe probes symbols
in that order.
