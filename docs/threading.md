# Threading contract (issue #261)

**`layoutFull` / `layoutDiag` (and the C entries built on them) are
reentrant and safe for concurrent layout on multiple threads, each
call with its own buffers. The metrics callbacks must tolerate
concurrent invocation. Nothing else needs external
synchronization — there are no engine locks because there is no
shared mutable state.**

## What is safe concurrently

- Any number of simultaneous `layoutFull` / `layoutDiag` /
  `layoutInner` calls, and simultaneous `zatex_layout_utf8` /
  `zatex_layout_utf8_ex` calls, on any threads — provided every
  call owns its buffers: `runs`, `rules`, `glyphs`, and (natively)
  `Diag`. Two calls sharing one buffer is a host race, not an
  engine bug: outputs borrow the caller's memory.
- `LayoutOptions` and the `macros` preset slice are read-only
  during the call. Reusing the same options/preset value across
  threads is safe; mutating it mid-call is not.
- Calling layout from inside a metrics callback is safe under the
  same rule (separate buffers) — the engine keeps no call-global
  state to recurse into.

Basis (verified against the sources, not assumed): a search of
`layout.zig`, `parse.zig`, `zatex.zig`, and `cabi.zig` finds no
file-scope mutable state. `ParseCtx` (`zatex.zig` `layoutInner`)
and `LayCtx` — including its fixed box/kid pools — are call-stack
locals; the C bridge's `runs_tmp` / `rules_tmp` overlays are stack
locals too. `err_msg` points at static string literals (immutable).
Zero heap allocations on the layout path means there is no
allocator to serialize on either.

## What the callbacks must tolerate

The engine may invoke the `MetricsProvider` hooks from any thread,
and from several threads at once. Every hook must therefore be
reentrant: no unsynchronized shared mutable state, no
thread-unsafe caching. The `ctx` pointer is shared across threads
by design — synchronizing whatever it points at is the host's job.
Pure-function providers (lookup tables, file-backed readers over
immutable bytes) satisfy this by construction; run the metrics
conformance check (`zatex_conform_metrics`, issue #194) per thread
once if you need proof a provider behaves under your threading
setup.

## The one exception: legacy `layout()`

The deprecated `layout()` wrapper is **not reentrant and not
thread-safe**. Its glyph slices borrow a shared process-wide
8K-glyph ring, so every `layout()` call from any caller may
overwrite every live `layout()` result (see the `layout`
doc comment in `zatex.zig`). Concurrent `layout()` calls race;
a previous result is valid only until the next `layout()` call
returns, and two live results can never coexist. New hosts pass
their own glyph buffer to `layoutFull` and never touch this path.
(`layoutFull` calls are unaffected by concurrent `layout()` calls
— the ring belongs to the wrapper alone.)

## What needs external synchronization

Only host-owned sharing: shared buffers, a mutable provider `ctx`,
or a host glyph cache filled from layout output. The engine itself
contributes nothing to synchronize — if your threads share nothing
but an immutable provider and per-call buffers, no lock is needed.
