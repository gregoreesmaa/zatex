// rowdiff.mjs — support-table 1:1 audit (issue #73).
//
// Diffs pinned KaTeX 0.18.7 `support_table.md` row-by-row against
// `docs/support-table.md` with codepoint-exact function-name
// normalization. Pinned bundle arbiter notes live in the issue;
// this script checks the mechanical contract:
//
//   1. Row sets identical (modulo documented exceptions below):
//      zero missing, zero extra, zero duplicates.
//   2. Status truthfulness: zero `accept` rows for functions KaTeX
//      rejects, zero `TODO` rows for functions KaTeX supports, and
//      every `unsup`/`err-parity` row keeps reject-row evidence that
//      `audit.mjs` can resolve.
//   3. No bare `owner #N` tags: every TODO names a live issue plus a
//      plain-language group, `TODO (group, #NN)`.
//
// Normalization (both tables escape backslashes for markdown):
//   upstream ``\\!`` -> `\!`; ``\\\\ `` (line break + table space) ->
//   `\\`; `&#124;` -> `|`; ours are single-backslash code spans.
// Exit non-zero on any violation. No network, no dependencies.
import { readFileSync, writeFileSync } from "fs";

const upSrc = readFileSync("support_table.md", "utf8");
const ourSrc = readFileSync("../../docs/support-table.md", "utf8");

let errors = 0;
const fail = (msg) => {
  errors += 1;
  console.log(`ERROR: ${msg}`);
};

const GFM_PUNCT = new Set('!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~');
function gfmUnescape(s) {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "\\" && i + 1 < s.length && GFM_PUNCT.has(s[i + 1])) {
      out += s[i + 1];
      i++;
    } else {
      out += s[i];
    }
  }
  return out;
}

function upNorm(raw) {
  // Table padding vs significant spaces: strip leading padding, then
  // unescape. A surviving trailing space is significant ONLY for the
  // two space-sensitive functions below; everywhere else it is padding
  // (e.g. `| \ce |`). No KaTeX function is a bare `\`, so a lone `\`
  // can only be the control-space cell `\\ ` post-unescape.
  let s = gfmUnescape(raw.replace(/^ +/, ""));
  s = s.replace(/&#124;/g, "|").replace(/&#060;/g, "<").replace(/&amp;/g, "&");
  if (s === "\\\\ ") return "\\\\"; // line-break row cell
  if (s === "\\ ") return s; // control-space row cell (space significant)
  return s.replace(/ +$/, ""); // garden-variety table padding
}

// Our rows: | `func` | status | evidence |. The func cell may itself
// contain `|` (e.g. `\|`), so split on pipes is wrong; the code span
// is literal (no markdown processing inside backticks).
function ourNorm(line) {
  const m = line.match(/^\|\s*`(.*)`\s*\|\s*([^|]*?)\s*\|\s*(.*?)\s*\|$/);
  if (!m) return null;
  return { func: m[1], status: m[2], ev: m[3] };
}

// Upstream rows: |Function|Rendered|Source|. No raw `|` inside cells
// (literal pipes are `&#124;`); every row fits on one line.
const up = new Map();
// Documented row-set exceptions (KaTeX-side-justified, keep in sync
// with the table header): upstream lists these twice; we keep one.
const DEDUP_OK = new Set(["\\underrightarrow", "\\vcenter"]);
for (const line of upSrc.split("\n")) {
  if (!line.startsWith("|")) continue;
  const cols = line.split("|");
  if (cols.length < 4) continue;
  const func = upNorm(cols[1]);
  if (func === "Symbol/Function" || /^:?-+:?$/.test(func)) continue;
  const rendered = cols[2].trim();
  const supported =
    func === "%" // renders empty output by design (issue #73)
      ? true
      : rendered !== "" && !rendered.includes("Not supported");
  if (up.has(func)) {
    // Upstream lists these twice (documented in our table header);
    // anything else duplicated upstream would hide here, so report it.
    if (!DEDUP_OK.has(func)) fail(`upstream duplicate row: ${JSON.stringify(func)}`);
    else console.log(`note: upstream duplicate (single row kept): ${JSON.stringify(func)}`);
  }
  up.set(func, { rendered, source: cols.slice(3).join("|"), supported });
}

// Upstream Rendered cells are stale-empty for the invisible primitives:
// the pinned bundle accepts all of these (verified 2026-09-14 against
// katex@0.18.7 with throwOnError: `\allowbreak x`, `x\nobreak y`,
// `\expandafter x`, `\futurelet\x{\alpha}\x`, `\let\a=b\a`,
// `\long\def\a{b}\a`, `\noexpand`, `x \relax y`), so our `accept` rows
// are bundle-true and the empty cell must not read as "rejects".
// Same carve-out shape as `%` below.
const INVISIBLE_OK = new Set([
  "\\allowbreak", "\\expandafter", "\\futurelet", "\\let",
  "\\long", "\\nobreak", "\\noexpand", "\\relax",
]);
// Upstream-prose-stale rows: the support table says "Not supported"
// but the pinned bundle accepts (bundle is arbiter per AGENTS.md).
//   - `{subarray}`: table row 1018 says Not supported; the bundle
//     renders `\begin{subarray}{c}a\\bb\end{subarray}` and the
//     `\sum_{\begin{subarray}...}` form (sweep subarray-c/subarray-l,
//     katex_ok, parity-green 2026-09-14). Our `accept` is bundle-true.
//   - `\hbox to <dimen>`: the upstream Rendered cell is empty, but
//     the bundle accepts `\hbox to 10pt{A}` (sweep hbox-to, katex_ok,
//     parity-green 2026-09-16) — both engines read it as `\hbox{t}`
//     with the rest spilling as math. Our `accept` is bundle-true.
const STALE_UPSTREAM = new Set(["{subarray}", "\\hbox to <dimen>"]);
// Extension-gated rows: the upstream table marks these supported,
// but support requires the mhchem contrib extension — the pinned
// CORE bundle rejects both (verified 2026-09-16, katex@0.18.7
// throwOnError: `Undefined control sequence: \ce`, same for `\pu`;
// sweep rej-unsup-ce/rej-unsup-pu record the core verdicts). ZaTeX
// core parity is therefore reject; our `unsup` rows are bundle-true
// and must not read as underclaims. Extension support is future work.
const EXTENSION_GATED = new Set(["\\ce", "\\pu"]);
// Our rows: | `func` | status | evidence |.
const ours = new Map();
for (const line of ourSrc.split("\n")) {
  if (!line.startsWith("| `")) continue;
  const row = ourNorm(line);
  if (!row) {
    fail(`unparseable row: ${line.slice(0, 80)}`);
    continue;
  }
  const { func, status, ev } = row;
  if (ours.has(func)) fail(`our duplicate row: ${JSON.stringify(func)}`);
  ours.set(func, { status, ev });
}

// 1. Row-set identity.
for (const f of [...up.keys()].sort()) {
  if (!ours.has(f)) fail(`missing row: ${JSON.stringify(f)}`);
}
for (const f of [...ours.keys()].sort()) {
  if (!up.has(f) && !DEDUP_OK.has(f)) fail(`extra row: ${JSON.stringify(f)}`);
}

// 2. Status truthfulness.
const VALID = new Set(["accept", "TODO", "unsup", "err-parity"]);
let nAccept = 0,
  nTodo = 0,
  nUnsup = 0;
for (const [f, row] of [...ours.entries()].sort()) {
  if (!VALID.has(row.status)) fail(`bad status ${JSON.stringify(row.status)} on ${JSON.stringify(f)}`);
  const u = up.get(f);
  if (!u) continue;
  if (row.status === "accept") {
    nAccept += 1;
    if (!u.supported && !INVISIBLE_OK.has(f) && !STALE_UPSTREAM.has(f))
      fail(`overclaim: ${JSON.stringify(f)} accept but KaTeX rejects`);
    if (!/goldens:/.test(row.ev)) fail(`accept row ${JSON.stringify(f)} lacks golden evidence`);
  } else if (row.status === "TODO") {
    nTodo += 1;
    if (!u.supported) fail(`wrong bucket: ${JSON.stringify(f)} TODO but KaTeX rejects (use unsup)`);
    if (!/^TODO \([^,()]+, #\d+\)/.test(row.ev))
      fail(`bare owner tag on ${JSON.stringify(f)}: ${JSON.stringify(row.ev)} (want TODO (group, #NN))`);
  } else {
    nUnsup += 1;
    if (u.supported && !EXTENSION_GATED.has(f))
      fail(`underclaim: ${JSON.stringify(f)} ${row.status} but KaTeX supports`);
    if (!/goldens:/.test(row.ev)) fail(`${row.status} row ${JSON.stringify(f)} lacks reject-row evidence`);
  }
}

console.log(`upstream rows: ${up.size} (${[...up.values()].filter((r) => r.supported).length} supported)`);
console.log(`our rows: ${ours.size} (accept ${nAccept}, TODO ${nTodo}, unsup/err-parity ${nUnsup})`);
{
  const dump = (m, extra) =>
    [...m.entries()].map(([k, v]) => ({ f: [...k].map((c) => c.codePointAt(0)), ...extra(v) }));
  writeFileSync(
    process.env.ROWDIFF_JSON || "/tmp/rowdiff.json",
    JSON.stringify(
      {
        missing: dump(
          new Map([...up].filter(([k]) => !ours.has(k))),
          (v) => ({ supported: v.supported })
        ),
        extra: dump(
          new Map([...ours].filter(([k]) => !up.has(k) && !DEDUP_OK.has(k))),
          (v) => ({ status: v.status })
        ),
      },
      null,
      1
    )
  );
}
process.exit(errors > 0 ? 1 : 0);
