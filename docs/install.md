---
layout: page
title: Install and load recipe: ZaTeX versioned binaries
---

# Install and load recipe: ZaTeX versioned binaries (issue #259)

Each `v*` tag publishes versioned binaries for every package as
GitHub release assets (built by `.github/workflows/release.yml`);
this is the blessed path from release asset to working host setup.
No more hand-rolled install locations or per-host dlopen snowflakes.

Status: issue #259 is closed (the release workflow above exists),
but no `v*` tag has been pushed yet, so no release assets exist.
The first `v*` tag publishes the first binaries; until then every
host builds from source and pins per §4 below.

## 1. Get the asset

Targets are `<arch>-<os>` for `x86_64` / `aarch64` × `linux` /
`macos` / `windows`, and every release carries a `SHA256SUMS` file.
Verify with it before installing. The asset pattern throughout is
`libzatex-<tag>-<target>.<ext>` (same shape for every library).
One exception: `zatex-png` ships no `x86_64-macos` binary — the
macOS CLI needs the Xcode SDK, so it builds natively on the release
runner and only that runner's arch is published (today:
`aarch64-macos`).

Libraries (link statically, or ship the dynamic library with your
app — either is a complete engine: zero dependencies, no bundled
fonts). The core's header is `zatex-<tag>.h`; `zatex_mathml-<tag>.h`
goes with `libzatex_mathml`; `zatex_fileprovider-<tag>.h` documents
the blessed provider surface for hosts building the bridge from
source (`packages/zatex/build.zig` `hello` step). `zatex-svg` is a
pure Zig module plus CLI, so it ships libraries but no C header.

| Target | `libzatex` static | `libzatex` dynamic |
| --- | --- | --- |
| `x86_64-linux` / `aarch64-linux` | `libzatex-vX.Y.Z-<target>.a` | `libzatex-vX.Y.Z-<target>.so` |
| `x86_64-macos` / `aarch64-macos` | `libzatex-vX.Y.Z-<target>.a` | `libzatex-vX.Y.Z-<target>.dylib` |
| `x86_64-windows` / `aarch64-windows` | `libzatex-vX.Y.Z-<target>-static.lib` | `libzatex-vX.Y.Z-<target>.dll` + `libzatex-vX.Y.Z-<target>-import.lib` |

`libzatex_mathml` and `libzatex_svg` follow the same shape with
their own infix (`libzatex_mathml-vX.Y.Z-<target>.{a,so,dylib}`,
`...-static.lib` / `.dll` + `-import.lib` on Windows).

On Windows link either the static archive or the DLL's import
library — never both in one binary (duplicate symbols). The import
library is link-time only; ship the `.dll` with your app.

CLI tools (single-file, zero-dependency binaries):

| Tool | Linux / macOS asset | Windows asset | Notes |
| --- | --- | --- | --- |
| `zatex-png` | `zatex-png-vX.Y.Z-<target>` | `zatex-png-vX.Y.Z-<target>.exe` | macOS builds use the CoreGraphics backend (runner arch only, no `x86_64-macos` asset); Linux/Windows builds use the portable software backend (same layout dimensions — see `packages/zatex-png/README.md`). |
| `zatex-svg` | `zatex-svg-vX.Y.Z-<target>` | `zatex-svg-vX.Y.Z-<target>.exe` | Outlined-path SVG, no font dependency at view time. |

Run CLIs from the package directory (font paths are CWD-relative —
see `packages/zatex-png/README.md` and
`packages/zatex-svg/README.md`).

## 2. Where to install (blessed order)

Ship the dylib **inside your app bundle** and probe in this order:

1. Bundle-relative first: `Contents/Frameworks/` (or `Resources/`,
   as `read` does today) via `@rpath` / `@loader_path`. This is
   the setup that survives system updates and parallel installs.
2. `/usr/local/lib/libzatex.dylib` (or `.so`) — the shared
   fallback for hosts that run outside a bundle.
3. Absent everywhere: run **without** the engine. An absent dylib
   is a clean fallback (math renders as source text or is
   skipped), never a crash — do not `dlopen` a path you have not
   probed for, and never abort the host when layout is
   unavailable.

## 3. Load recipe (`dlopen` + symbol probe order)

```c
void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL); // NULL → engine absent, take the fallback
// Prefer the stride-negotiated entry; fall back to frozen v1 (issue #203).
layout_ex_fn ex = (layout_ex_fn)dlsym(h, "zatex_layout_utf8_ex");
layout_fn base = (layout_fn)dlsym(h, "zatex_layout_utf8"); // must exist on any good dylib
// Gate on version: pre-1.0 requires an exact match (see CHANGELOG.md).
uint32_t (*ver)(void) = dlsym(h, "zatex_version");
```

Then, per call:

- With `_ex`: pass `sizeof(your run struct)` as the stride
  (`sizeof(zatex_run_t)`, 28 today) to receive the `x_scale` and
  `color` tails. With the v1 entry: pass arrays of the frozen
  20-byte `zatex_run_v1_t` — never a `zatex_run_t` array (stride
  20 over 28-byte slots warns and scrambles).
- Zero-initialize `zatex_layout_t` before each call and negotiate
  `zatex_capabilities()` once: read `err_code` only when
  `ZATEX_CAP_ERR_CODE` is set (an old dylib never writes the
  field). Branch retry logic on the code (`OVERFLOW_*` carries the
  `nruns`/`nrules` needs — retry once, grown; `NO_SPACE` with
  zeroed counts means fail with a message).
- Optional but recommended on first load: `zatex_conform_metrics`
  against your provider (issue #194) — a nonzero diagnostic count
  names the hook values to fix before you draw anything.
- Threading: concurrent layout calls are safe with per-call
  buffers; the callbacks must tolerate concurrent invocation
  (see `docs/threading.md`).
- Input: normalize to NFC at your boundary (see
  `docs/unicode.md`).

## 4. Delimiter scanning (host-owned, issues #252/#277)

The engine starts at already-extracted TeX: there is deliberately no
`zatex_detect`/`zatex_scan` entry point in `zatex.h`. Every host scans
its own prose for math islands, and every independent reimplementation
diverges — so all hosts follow one canonical rule instead of sharing
code:

- Spec: `docs/delimiter-scan.md` (pinned KaTeX 0.18.7 auto-render
  behavior, plus the ZaTeX `$` currency-guard layer and the host
  recipe: mask code spans, skip ignored tags, scan, filter, feed each
  payload to the engine with its `display` flag).
- Conformance suite: `packages/zatex/goldens/delimiter_vectors.json`
  (pinned KaTeX output, never redefined — regenerate only via
  `tools/katex/gen_delim_vectors.mjs`), enforced by
  `packages/zatex/src/delimvectors.zig` in `zig build test`.
- Non-goals: the core never sees prose, code spans, or unclosed
  fences (unclosed delimiters stay literal text, never errors), and
  engine errors stay host policy (render red or fall back to literal
  — see `docs/parity.md` "Error fallback").

## 5. Building from source (the only path until the first tag)

Zig 0.16.0, `cd packages/zatex && zig build` → `zig-out/lib/`
(`libzatex.a` + `libzatex.dylib`/`.so`) with `src/zatex.h` as the
header. Pin the source by tag once tags exist — never by `main` —
and record the tag where you record the `zatex_version()` you
validated against. Until the first `v*` tag, pin by commit SHA
instead:

```sh
git fetch origin
git checkout <sha>  # the commit you validated
(cd packages/zatex && zig build)
sha256sum packages/zatex/zig-out/lib/libzatex.* packages/zatex/src/zatex.h
git rev-parse HEAD  # record this SHA alongside the checksums
```

Keep the SHA, the checksums, and the `zatex_version()` word in one
place (e.g. your lockfile): re-verify all three on every engine
update. After the first `v*` tag this recipe stays valid, with the
tag replacing the SHA and the release `SHA256SUMS` replacing the
local checksums.

## 6. Host CI: the scripted test double (issue #274)

Do not hand-roll engine stubs. `cd packages/zatex &&
zig build test-double` produces `zig-out/test-double/` holding
`libzatex_test.a`, `libzatex_test.dylib` (or `.so`), `zatex.h`,
and `zatex_testdouble.h`. The double exports the same symbols as
the engine with deterministic scripted responses — no layout
math, and your metrics hooks are never called (NULL hooks are
fine, so the double also proves you handle a hook-free path).

Point your loader at the double and drive the four scripts from
`zatex_testdouble.h`:

```c
void *h = dlopen("libzatex_test.dylib", RTLD_NOW | RTLD_LOCAL);
// same dlsym order as section 3 (the double exports every entry)
layout_ex_fn ex = (layout_ex_fn)dlsym(h, "zatex_layout_utf8_ex");

// 1. OK path: ZATEX_TD_HELLO lays out (3 runs, 1 rule, fixed
//    extents) — assert status 0 and draw it like a real formula.
// 2. Grow-and-retry: ZATEX_TD_NOSPACE returns 6 with nruns/nrules
//    needs and leaves your buffers untouched — assert the needs,
//    realloc to them, and retry.
// 3. Over-ceiling: ZATEX_TD_LIMIT returns 7 with needs past the
//    256-run / 64-rule ceilings — assert you fail with a message
//    instead of retrying forever.
// 4. Bad input: ZATEX_TD_BAD returns 2 with err_offset 5 and a
//    static message — assert you render the source plus the
//    message bytes as real text (the throwOnError:false fallback).
```

Any other input is status 2 (the double only speaks its script),
font 0 is a clean `zatex_conform_metrics` pass while any other
font carries one diagnostic (cover both), and capabilities report
all three bits. Keep the double out of release builds: gate the
`dlopen` path on a test build flag so production can never load
scripted geometry.

