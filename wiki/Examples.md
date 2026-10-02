# Examples — minimal ZaTeX hosts

One formula, every embedding surface. Copy-paste starters, all wired in
CI so they cannot rot.

| File | Surface | Run |
| --- | --- | --- |
| [`hello_formula.c`](hello_formula.c) | C ABI (`libzatex` + file provider) | `cd packages/zatex && zig build hello && ./zig-out/bin/hello-formula` |
| [`layout.zig`](layout.zig) | Zig API (`layoutDiag` over caller buffers) | copy into your package with the `zatex` dep |
| [`mathml.zig`](mathml.zig) | MathML emitter (`zatex_mathml.render`) | copy into your package with the `zatex_mathml` dep |
| [`render.sh`](render.sh) | CLI gallery (PNG + SVG per formula) | `./examples/render.sh [outdir]` |

The PNG/SVG CLIs also render directly:

```sh
# PNG (run from packages/zatex-png: font paths are CWD-relative)
cd packages/zatex-png && zig build
./zig-out/bin/zatex-png "x^2" out.png
./zig-out/bin/zatex-png --display "\sum_{i=1}^n i^2" sum.png

# SVG (run from packages/zatex-svg, same CWD assumption)
cd ../zatex-svg && zig build
./zig-out/bin/zatex-svg "x^2" x2.svg
```
