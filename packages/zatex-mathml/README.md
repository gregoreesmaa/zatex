# zatex-mathml — MathML emitter for ZaTeX

KaTeX-compatible MathML serialization over the `zatex` core's parse
tree. Thin structural walker: no layout math, no measuring, no font
metrics (AGENTS.md §2). Split out of the core so hosts that only lay
out (native runs, PNG) stop paying its ~55 KB.

Depend on it from your own Zig package with a path dependency:

```zig
.zatex_mathml = .{ .path = "path/to/zatex/packages/zatex-mathml" },
```

then `b.dependency("zatex_mathml", ...)` and import `zatex_mathml`:

```zig
const out = try zatex_mathml.render("x^2", .{}, &buf);
```

C hosts link `libzatex_mathml` (static or dynamic, alongside
`libzatex`) and call `zatex_mathml_utf8` (see
`src/zatex_mathml.h`); it returns bytes written or a negative
status with the core's status integers.

## Tests

```sh
# Full profile (default) plus the subset-envelope probe
cd packages/zatex-mathml && zig build test --summary all
```

Offline and dependency-less like the core: no fonts, no network.
Differential coverage against pinned KaTeX stays in the core suite
(`parity`, `qa`), which imports this package.
