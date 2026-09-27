# zatex-svg — LaTeX math to standalone SVG

KaTeX-compatible LaTeX → self-contained SVG (outlined glyph paths,
no font dependency at view time) over the `zatex` core's box tree.
Thin geometric walker: no layout math, no measuring. Split out of
the core so its distribution library stays SVG-free.

Depend on it from your own Zig package with a path dependency:

```zig
.zatex_svg = .{ .path = "path/to/zatex/packages/zatex-svg" },
```

then `b.dependency("zatex_svg", ...)` and import `zatex_svg`:

```zig
const out = try zatex_svg.renderLayout(layout, ol, &segs, &buf);
```

## Usage

```
zatex-svg [--display] [--font PATH] "<tex>" out.svg
```

Run from `packages/zatex-svg/` (font paths are CWD-relative, same
assumption as `zatex-png`):

```sh
cd packages/zatex-svg && zig build
./zig-out/bin/zatex-svg "x^2" /tmp/x2.svg
./zig-out/bin/zatex-svg --display --font ../zatex/fixtures/fonts/latinmodern-math.otf "\frac{a}{b}" /tmp/frac.svg
```

Default: the vendored fixture stack (`CLI_STACK` in
`src/outlines.zig` — same files, same roles, same order as the
`zatex-png` CLI, so SVG ink comes from exactly the faces layout
measured with). `--font PATH` keeps the legacy single-file host
instead of the stack. Engine rejections surface as usage errors
with the diag offset/message (no new errors); fixed render caps
exhaust as honest `NoSpace`.

## Layout

- `src/main.zig` — CLI (`--display`, `--font`; pure argv parser
  with unit tests, no filesystem in tests).
- `src/svg.zig` — writer (`W`: fixed 2-decimal floats, lowercase
  hex), skeleton, paint helpers, the rules/runs walker
  (`renderLayout`), and the one-shot CLI glue (`render`). All
  walker unit tests live here.
- `src/outlines.zig` — `Outlines` seam + `StackOutlines` file
  implementation + `CLI_STACK`. All seam/file tests live here.
- `src/zatex_svg.zig` — package root: re-exports + `refAllDecls`
  over `svg.zig`, `outlines.zig`, `main.zig` (the single test root).

## Outline sources (backends-equivalent)

Glyph ink comes from the font files themselves — CFF/Type2
outlines via the `zatex` package's host-side `cff` module,
demuxed per stack face through `faceOf`, transforms baked into
path coordinates. One stack face per `CLI_STACK` row:

| Faces | Outline source | Status |
| --- | --- | --- |
| Latin Modern Math (`.lm`) | CFF via `cff.load` | Reference; every render measures and inks from it. |
| KaTeX faces (`.main`, `.main_bold`, `.main_italic`, `.main_bi`, `.math_italic`, `.ams`, `.sans`, `.typewriter`, `.cal`, `.frak`, `.script`, `.size1`, `.size2`) | CFF via `cff.load` | Ink for their codepoints; `zig build test` pins that every required face loads. |
| STIX Two Math (`.stix`: vendored overline + system fallbacks) | CFF when the file loads | Optional rows skip silently when absent. |

A face whose CFF will not load serves null segments / zero ink
(skip-ink totality — never an error), and the measuring provider
answers through the same stack, so measuring files == outline
files by construction.

## Verification boundary (this machine: macOS/arm64, Zig 0.16.0)

```sh
cd packages/zatex-svg && zig build test --summary all
```

- `zig build test`: green (walker, seam, arg-parse, determinism).
- CLI render (`./zig-out/bin/zatex-svg "x^2" /tmp/x2.svg`):
  `<svg …viewBox…` with `<path`, byte-identical across `--font`
  single-file and stack modes for LM-covered input.
- Cross-compile: not attempted (no notes yet).
