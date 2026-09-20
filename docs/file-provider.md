# docs/file-provider.md — blessed file-based MetricsProvider (issue #192)

Every native host needs the same font-file truth to feed
`MetricsProvider`: cmap glyph ids, hmtx advances, MATH-table
corrections, outline ink boxes. Hand-rolled copies keep getting it
wrong (missing italic corrections, a 500 fallback that lies for
zero-width glyphs, missing ink bounds so zero-advance marks cannot
center by ink). The `fileprovider` module (in `packages/zatex`, next
to `otmath`/`fontstack`/`cff`) promotes the reference hosts' exact
logic into the library as one blessed constructor.

## When to use it

- Your host **has the font file bytes** (bundled, vendored, or loaded
  from disk): use the file provider. You get reference-identical
  metrics with no parsing of your own.
- Your host **shapes through a platform stack with no file access**
  (system font handle only): keep the callback ABI. The handshake
  below still applies in reverse — see "Platform-shaper hosts".

## Zig recipe

```zig
const fileprovider = @import("fileprovider");

// `bytes` is borrowed, never copied: it must outlive `fp`.
var fp = try fileprovider.FileProvider.init(bytes);
const prov = fp.provider();
const layout = try zatex.layoutFull(src, .{}, prov, &runs, &rules, &glyphs);
```

Semantics, pinned by tests in `src/fileprovider.zig`:

- **Advances are hmtx bit-for-bit**, including 0 for zero-width
  glyphs. There is no fallback: a CoreText-style "advance lookup
  failed" path must never substitute 500 — combining marks
  (U+0302, U+0303, U+20D7, …) advance 0 and center by ink instead.
- **Italic corrections are the MATH table bit-for-bit**
  (`MathItalicsCorrectionInfo`, scaled to 1000 units).
- **Ink is the CFF outline box** with outward rounding (floor the
  minima, ceil the maxima), unclipped, y-up from the baseline — the
  same `cff.inkBounds1000` conversion the software backend draws
  with, so measure == draw by construction. Expect at most ~1 unit
  of float slack per edge against a platform shaper's own rounding
  (the sw-vs-CoreText cross-check in `sw_backend.zig` holds ≤2 on
  every fixture glyph).
- **Extents are the vertical slice of that box**
  (`[ceil(top), ceil(-bottom)]`, clamped at 0).
- Rule constants, glyph variants, and kern cut-ins come from the
  font's MATH table through the same `fontstack` code the reference
  host uses. Every optional hook is filled, so the core always takes
  its refined paths (ink-centered accents, outline extents).

Degradation (total on adversarial input, never a panic):

- Bytes that are not a font: `init` returns `error.NotAFont` (and the
  other bounded `otmath` errors) — the host falls back to callbacks.
- A font **without a CFF table** (e.g. TrueType `glyf` outlines)
  still loads: cmap/hmtx/MATH keep answering, while ink reports
  all-zeros (the core treats that as absent — exact v3 behavior) and
  extents report the legacy 700/250 constant. Per-glyph `glyf` ink
  boxes are future work.
- A glyph whose outline overflows the 512-segment stack scratch (no
  fixture glyph does — asserted in `sw_backend.zig`) reports blank
  for that query, exactly as the software backend draws it.

## The gid-namespace handshake

File gids come from the font's cmap. A host that **draws through a
platform shaper** (CoreText, DirectWrite, FreeType) must confirm the
shaper speaks the same gid namespace before trusting file metrics —
else file gids draw wrong glyphs. Protocol (no new ABI: it uses the
existing `glyphId` callback):

1. For each codepoint in `fileprovider.handshake_probes`, read the
   engine gid (`provider.glyphId(ctx, font, cp)`, or
   `FileProvider.handshakeGid(cp)` on the Zig side).
2. Read the shaper's gid for the same codepoint
   (e.g. `CTFontGetGlyphsForCharacters`).
3. If every covered probe agrees, with at least one nonzero
   agreement, the namespaces match: lay out with file metrics and
   draw the resulting gids through the shaper.
4. On **any** disagreement (or no nonzero agreement), discard file
   metrics for that font and fall back to pure callbacks — shaper
   gids plus shaper advances. Never mix file gids with shaper
   advances; the two namespaces only agree after step 3 passes.

The Zig helper `handshakeMatches(&fp, shaperGid)` implements steps
1–4 (`false` means fall back). C hosts implement the same loop over
the C `glyph_id` hook; the probe list is part of the contract and
grows only by appending.

Rationale for the "at least one nonzero" clause: a probe the file
does not cover reads gid 0 on both sides, which proves nothing. A
file covering none of the probes cannot pass the handshake.

## ABI status

Additive to frozen v1, and the C ABI is byte-untouched: the file
provider fills the existing `MetricsProvider` hooks (v4 or below),
so `provider_version` stays 4 and `zatex.h`/`cabi.zig` gain nothing.
The new surface is a Zig module (`fileprovider`, plus the shared
`cff` reader); it is host-side code, never linked into the layout
core — the distribution size gate (`tools/size_gate.sh`) proves the
shipped artifact did not grow.
