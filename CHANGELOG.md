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
- Run shape `zatex_run_t` is 24 bytes (`x_scale` appended, issue
  #197); rules, layout, extents, and ink-box shapes are unchanged.
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
- Delimiter-scanning contract, issues #252/#277 (docs only, no ABI
  change): #252 left the canonical scanner spec
  (`docs/delimiter-scan.md`) with no trace in `zatex.h`, so hosts
  hand-rolled detection with divergence risk. Resolution is the
  host-owned side of the either/or — still no
  `zatex_detect`/`zatex_scan` entry point, by design. The contract is
  now discoverable from the header: `zatex.h` names the spec, the
  pinned conformance vectors
  (`packages/zatex/goldens/delimiter_vectors.json`), and the
  enforcing test (`packages/zatex/src/delimvectors.zig`), with
  explicit non-goals (core starts at extracted TeX; unclosed
  delimiters stay literal). Host recipe in `docs/install.md` §4;
  vectors untouched (pinned KaTeX — no golden changes).
- Option knobs added since the freeze (all default-off, additive):
  `min_rule_thickness_milli_em`, `strict` + `StrictLog`,
  preset `macros`, `global_group`, `leqno`, `fleqn`.

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
