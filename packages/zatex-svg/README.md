# zatex-svg — LaTeX math to standalone SVG

Standalone, self-contained SVG (outlined glyph paths) over the `zatex`
core's box tree. Thin geometric walker: no layout math, no measuring.
Split out of the core so its distribution library stays SVG-free.

Depend on it from your own Zig package with a path dependency:

```zig
.zatex_svg = .{ .path = "path/to/zatex/packages/zatex-svg" },
```

then `b.dependency("zatex_svg", ...)` and import `zatex_svg`:

```zig
const out = try zatex_svg.renderLayout(layout, ol, &segs, &buf);
```

## Tests

```sh
cd packages/zatex-svg && zig build test --summary all
```

Scaffold status: stubs only (`renderLayout`/`render` return
`error.NoSpace`). Tasks 2–4 replace them with the writer, outline
seam, and walker core.
