# fixtures/ — test-only data (never linked into the core)

## fonts/latinmodern-math.otf

Reference font: Latin Modern Math v1.959 (2014-09-05) by B. Jackowski,
P. Strzelczyk, P. Pianowski, via the CTAN `lm-math` package:

- font: https://mirror.ctan.org/fonts/lm-math/opentype/latinmodern-math.otf
- sha256: `6075562b771f8b82f0c179e363389684f2dd09de30038269e2628e504bd7be0f`
- license: GUST Font License (`GUST-FONT-LICENSE.txt`, vendored alongside;
  an instance of the LPPL) — verified at vendoring time 2026-09-12.
- census: 1000 upm, 4802 glyphs, OpenType MATH table present.

Used only by host-side tests (`src/otmath.zig` reader tests, the
differential harness reference provider). The library core never reads
this file and never depends on it: `zig build test` is the only
consumer, and CI vendors it via checkout.
