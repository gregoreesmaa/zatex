
# Unicode normalization expectation (issue #265)

**Contract: hosts pass NFC. The engine performs no normalization —
NFC and NFD are different inputs and lay out differently.**

Normalize once at your API boundary (before `layoutFull` /
`zatex_layout_utf8`), so every host turns logically identical input
into identical bytes and identical layout.

## What the engine does (verified @ `parse.zig` `lexRaw`/`utf8Len`/`decode`)

- Bytes decode to codepoints structurally: sequence length comes from
  the lead byte, continuation bits are not validated, overlongs and
  encoded surrogates are accepted as-is (e.g. `C0 AF` decodes to
  U+002F). Do not rely on this leniency — send well-formed NFC.
- Each codepoint becomes its own atom. ASCII letters/digits are then
  remapped to their styled face before the `glyphId` hook
  (`layout.zig` `mathAlpha`: `e` → U+1D452 under the default math
  face, with a raw-codepoint fallback when the styled glyph is
  missing); every other codepoint reaches the hook verbatim. There
  is no precomposition, no decomposition, no combining-mark
  attachment.
- Only structural failures reject: a bad lead byte or a truncated
  sequence fails `Invalid` with `Diag.message = "invalid utf-8"` and
  the byte offset (`Diag.offset`).

Measured with the identity test provider (advance 500 for every
glyph), so widths expose the token stream directly:

| input | engine result |
| --- | --- |
| NFC `é` (U+00E9) | 1 run, 1 glyph (U+E9), width 500 |
| NFD `e` + U+0301 | 2 runs, 2 glyphs (U+1D452 + U+0301), width 1000 |
| lone U+0301 | 1 run, 1 glyph (U+0301), width 500 |
| `FF` / `E2` | `Invalid`, `"invalid utf-8"`, offset 0 |
| `61 E2` (truncated) | `Invalid`, `"invalid utf-8"`, offset 1 |

The first two rows are the divergence this contract exists to
prevent: same logical character, different run counts and widths.

## What KaTeX does (pinned 0.18.7, `dist/katex.js`)

KaTeX converges the two forms for covered characters, in two steps:

1. The lexer attaches trailing `U+0300–U+036F` marks to the base
   character (the `[\u0300-\u036f]` range in `dist/katex.js`), so
   NFD `e` + U+0301 lexes as one token.
2. The parser expands precomposed Latin letters through its
   `unicodeSymbols` table (built with `String.normalize()` at module
   load, e.g. `"é"` → `"e\u0301"`), strips the trailing marks, and
   wraps the base symbol in an accent construction.

Verified by direct probe: NFC `é` and NFD `e` + U+0301 render
byte-identical HTML (accent construction: base `e` + accent body),
and byte-identical MathML (`<mover accent="true"><mi>e</mi>…`)
except the `<annotation encoding="application/x-tex">`, which
echoes the raw input bytes — so even KaTeX's MathML differs there.
(KaTeX also reports `unicodeTextInMathMode` under `strict: warn`
for these characters; the engine has no such warning — non-ASCII
math is `Ord` by design, see `docs/parity.md`.)

KaTeX coverage is not total: `é ê ñ ü` decompose to accent
constructions, `α` stays a single `mi`, CJK becomes `mtext` — and a
lone combining mark is a parse error (`Expected 'EOF', got '́'`),
where the engine lays it out as its own atom (row 3 above). That
last row is a known engine/KaTeX divergence: documented here, engine
behavior unchanged.

## Parity consequence

Neither input form matches KaTeX through the engine today: NFC `é`
reaches the provider as single codepoint U+00E9 (rendering depends
on the host font), NFD as two separate atoms (not an accent
construction). For KaTeX-identical accents use accent commands
(`\acute{e}`), which take the `layoutAccent` path pinned against
KaTeX. Raw accented Unicode is accepted and deterministic per form,
not KaTeX-identical.

## Host recipe

1. Normalize to NFC at the boundary. Swift:
   `string.precomposedStringWithCanonicalMapping`; Python:
   `unicodedata.normalize("NFC", s)`; JS: `s.normalize("NFC")`;
   otherwise ICU (`unorm2_normalize(UNORM2_COMPOSE)`).
2. Reject or replace lone combining marks before layout if your
   pipeline can produce them (editors rarely do; clipboard and
   programmatic concatenation can).
3. Feed the normalized bytes to the engine. Invalid UTF-8 still
   fails `Invalid` — keep the `throwOnError:false`-style fallback
   from `docs/parity.md` for that path.

