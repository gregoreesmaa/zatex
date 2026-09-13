# zatex-png screenshots (visual regression set)

`corpus.json` is the curated regression corpus: every `accept` row of the
pinned-KaTeX sweep corpus plus `edge-*` extras (nesting, tall delimiters,
text/math mixing, limits stacks) and `rej-*` rows covering the reject path.
`png/` holds the checked-in baseline renders at 48 px per em.

Regenerate: `screenshots/render.sh [outdir] [px]` (defaults to `png`, 48).
CI re-renders to a temp dir and byte-compares against `png/` — renders are
byte-deterministic (same input + same fixture font = identical bytes), so
any pixel drift fails the job, and the fresh PNGs upload as artifacts for
eyeballing under the PR.

Known exclusions: `rej-ctrl-slash` (`a\/b`, italic correction) is an accept
in the sweep corpus but the core engine rejects it — a core parity gap,
tracked outside this package; it is omitted here rather than marked reject.
