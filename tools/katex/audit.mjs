// audit.mjs — support-table coverage audit (issue #21).
//
// Maps every `docs/support-table.md` Evidence claim to sweep ids in
// `corpus.json` / `goldens/katex_sweep.json` and reports the gaps:
//   - dangling `goldens:` refs (no such sweep id)          -> ERROR
//   - `unsup` rows with no reject row in the corpus        -> ERROR
//   - sweep ids with no table owner (exact ref, -display/
//     -inline suffix strip, or id-prefix collection)       -> ERROR
//   - TODO rows (unimplemented functions)                  -> checklist
//
// Checklist tool, not a CI gate: TODO gaps close as features land.
// Exit non-zero on hard errors only.
import { readFileSync } from "fs";

const corpus = JSON.parse(readFileSync("corpus.json", "utf8"));
const goldens = JSON.parse(
  readFileSync("../../packages/zatex/goldens/katex_sweep.json", "utf8")
);
const table = readFileSync("../../docs/support-table.md", "utf8");

const cids = new Set(corpus.map((c) => c.id));
const gids = new Set(goldens.cases.map((c) => c.id));
let errors = 0;
const fail = (msg) => {
  errors += 1;
  console.log(`ERROR: ${msg}`);
};

// 1. Goldens must cover the whole corpus (sweep freshness, offline check).
for (const id of cids) if (!gids.has(id)) fail(`corpus id ${id} missing from goldens`);

// 2. Table refs must resolve: exact id, or collection prefix `name-`.
const refTokens = new Set();
for (const m of table.matchAll(/goldens: ([^\n|]+)/g))
  for (const tok of m[1].split(",")) refTokens.add(tok.trim());
for (const tok of [...refTokens].sort()) {
  const ok = cids.has(tok) || [...cids].some((id) => id.startsWith(tok + "-"));
  if (!ok) fail(`dangling goldens ref: ${tok}`);
  if ([...cids].some((id) => id.startsWith(tok + "-")))
    console.log(
      `collection: ${tok} covers ${
        [...cids].filter((id) => id.startsWith(tok + "-")).length
      } ids`
    );
}

// 3. Every unsup row must own a reject row.
const unsupRows = [...table.matchAll(/\| `([^`]+)` \| unsup \| ([^\n|]*) \|/g)];
let owned = 0;
for (const [, name, ev] of unsupRows) {
  const m = ev.match(/goldens: ([\w-]+)/);
  if (!m || !cids.has(m[1])) {
    fail(`unsup row ${name} has no reject row`);
  } else owned += 1;
}
console.log(`unsup rows with reject rows: ${owned}/${unsupRows.length}`);

// 4. QA-class sweep ids must have table owners: exact refs, collection
// prefixes, or -display/-inline twins of an owned base id. Anything else
// uncovered is reported for follow-up (pre-existing rows predate owners).
const CLASS_PREFIXES = ["atomgrid-", "flite-", "rej-malf-", "lenient-", "maxexpand-near-"];
const covered = new Set();
for (const tok of refTokens) {
  if (cids.has(tok)) covered.add(tok);
  for (const id of cids) if (id.startsWith(tok + "-")) covered.add(id);
}
// Ids with no natural function row: owned here as documented classes.
const CLASS_OWNERS = {
  "rej-malf-brak": "unknown-command class (cf. pre-existing rej-unknown)",
  "rej-malf-brak-display": "unknown-command class (cf. pre-existing rej-unknown)",
  "rej-malf-sub": "sub-operator contract (cf. ^ row: rej-malf-sup)",
  "rej-malf-sub-display": "sub-operator contract (cf. ^ row: rej-malf-sup)",
  "lenient-trailing-bin": "Bin-degradation leniency (cf. atomgrid collection)",
  "lenient-trailing-bin-display": "Bin-degradation leniency (cf. atomgrid collection)",
};
for (const id of cids) {
  const base = id.replace(/-(display|inline)$/, "");
  if (cids.has(base) && covered.has(base)) covered.add(id);
  if (id in CLASS_OWNERS) covered.add(id);
}
const qaUncovered = [...cids]
  .filter((id) => CLASS_PREFIXES.some((p) => id.startsWith(p)) && !covered.has(id))
  .sort();
if (qaUncovered.length > 0) fail(`QA sweep ids with no table owner: ${qaUncovered.join(", ")}`);
else console.log(`all QA-class sweep ids have table owners`);
const preexisting = [...cids].filter((id) => !covered.has(id)).sort();
console.log(`pre-existing ids without owners (follow-up): ${preexisting.length}`);

// 5. TODO checklist (unimplemented functions; not errors).
const todos = [...table.matchAll(/\| `([^`]+)` \| TODO \| ([^\n|]*) \|/g)];
console.log(`TODO functions remaining: ${todos.length}`);

process.exit(errors > 0 ? 1 : 0);
