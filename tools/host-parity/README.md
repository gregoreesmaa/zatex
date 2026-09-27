# tools/host-parity — host render-parity kit (issue #258)

Layout goldens cannot catch host draw bugs: the engine output can be
byte-correct while the host blits every formula mirrored, and no
engine-side artifact distinguishes those two worlds. This kit packages
the repo's own pieces — a canonical TeX list, reference PNGs pinned to
a vendored face, the tolerance script — so a new host proves pixel
parity in an afternoon.

## Contents

- `corpus.json` — 24 canonical rows (`id`, `tex`, `display`,
  `expect`), from bare superscripts through matrices, accents,
  braces, and a rules-only edge case. Every row lays out with zero
  missing glyphs under the kit face (verified with the `inspect`
  tool, issue #264).
- `reference/` — the 24 PNGs, rendered by `zatex-png` with the pinned
  configuration below.
- `check.sh` — re-renders and compares; fails on real drift.

## Pinned configuration

- Renderer: `zatex-png` with `-Dbackend=software` (the portable pure-Zig
  rasterizer — no CoreText, no FreeType, no OS text stack).
- Face: the single vendored `packages/zatex/fixtures/fonts/
  latinmodern-math.otf` (`--font`), so file bytes — not system fonts —
  decide every pixel.
- Scale: 48 px per em (the screenshots baseline).

Same input + same face = byte-identical renders (verified by rendering
twice and `cmp`-ing). Comparison still uses `tools/compare_shots.py`
tolerances (dimensions exact, per-pixel delta ≤ 16, differing fraction
≤ 1%) rather than byte equality, so hosts on other machines or other
rasterizers compare structure, not bytes.

## Host recipe

1. Render `corpus.json` with your own stack at 48 px per em.
2. If you bundle the vendored face: `check.sh`-equivalent —
   `compare_shots.py reference/ yours/` must pass.
3. If you draw through system fonts (e.g. STIX Two Math): pin YOUR
   face, keep YOUR reference PNGs, and compare structure — glyph
   shapes legitimately differ across faces, but rows must all render
   (no tofu, no missing rules) and dimensions must track the
   reference within rounding.

When pixels disagree with expectations, isolate the world first: dump
the engine's own runs/rules with the `inspect` tool (issue #264). If
the dump is right, the bug is in host draw code — exactly the class
this kit exists to catch.

## Regenerating references

References change only when layout or the software backend
intentionally changes (never for cosmetic reasons):

```
./tools/host-parity/check.sh /tmp/shots-new     # renders fresh
# eyeball the diff, then:
cp /tmp/shots-new/*.png tools/host-parity/reference/
```

CI (`host-tooling` job) runs `check.sh` against a scratch directory
and fails on drift — the kit cannot rot.
