
# ZaTeX — KaTeX-compatible math, native in Zig

> **The fastest math typesetting library for anywhere but the web.**

ZaTeX reads LaTeX math and lays it out natively: **zero dependencies,
zero heap allocations** on the layout path, **deterministic**
byte-identical output. One layout core feeds every output — native
display list, MathML, SVG, PNG — each emitter a thin walker, never a
second layout engine.

KaTeX is excellent and remains the compatibility reference (pinned
0.18.7). ZaTeX exists for where KaTeX cannot go: native binaries with
no JS runtime — microsecond layout inside apps that budget kilobytes,
not megabytes.

| ![fraction](renders/frac.png) | ![sum](renders/sum.png) | ![sqrt](renders/sqrt.png) | ![integral](renders/int.png) | ![matrix](renders/matrix.png) | ![continued fraction](renders/cfrac.png) |
| --- | --- | --- | --- | --- | --- |
| `\frac a b` | `\sum` | `\sqrt` | `\int` | `matrix` | `\cfrac` |

## Start here

- **[Install + load recipe](install.md)** — versioned binaries, `dlopen` order, building from source.
- **[Layout IR](ir.md)** — the output contract every emitter consumes (runs + rules, integer units).
- **[KaTeX parity](parity.md)** — options/error/font behavior beyond the support table.
- **[Support table](support-table.md)** — per-function coverage (editable source).
- **[Syntax mirror](katex-syntax.md)** — a render of every accepted function.
- **[Examples](https://github.com/gregoreesmaa/zatex/tree/main/examples)** — minimal hosts: C, Zig, CLI, MathML, SVG.

## Embed

```sh
# Render one formula (run from packages/zatex-png: font paths are CWD-relative)
cd packages/zatex-png && zig build
./zig-out/bin/zatex-png "x^2" out.png
./zig-out/bin/zatex-png --display "\sum_{i=1}^n i^2 = \frac{n(n+1)(2n+1)}{6}" sum.png
```

```zig
// Zig API: layout over caller-owned buffers, no allocation inside
var diag = zatex.Diag.empty();
const layout = try zatex.layoutDiag(tex, .{}, provider, &runs, &rules, &glyphs, &diag);
```

```c
// C ABI: stride-negotiated entry, exact-match version gate
zatex_layout_utf8_ex(tex, len, false, &metrics, runs, nruns, sizeof(runs[0]),
                     rules, nrules, glyphs, nglyphs, &out);
```

## Contracts

- **Compatibility target is KaTeX, not LaTeX.** Anything KaTeX 0.18.7
  rejects, ZaTeX rejects (same error contract).
- **Resource contract:** single-pass layout, bounded input (64 KiB),
  bounded expansion (`maxExpand` = 1000), bounded nesting (32); no
  threads, no network, no bundled fonts. Shipped artifact
  size-ratcheted (`tools/size_gate.sh`).
- **Host duties:** metrics provider, NFC input ([unicode](unicode.md)),
  threading ([threading](threading.md)), delimiter scanning
  ([delimiter-scan](delimiter-scan.md)).

## Deep docs

File provider ([file-provider](file-provider.md)) ·
error tolerance ([tolerance](tolerance.md)) ·
oracle sweeps ([oracle-diff](oracle-diff.md), [tex-oracle](tex-oracle.md)) ·
TRIP mapping ([trip](trip.md)) ·
host changelog ([CHANGELOG.md](https://github.com/gregoreesmaa/zatex/blob/main/CHANGELOG.md)) ·
contributors ([AGENTS.md](https://github.com/gregoreesmaa/zatex/blob/main/AGENTS.md)).
