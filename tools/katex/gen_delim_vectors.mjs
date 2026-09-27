// gen_delim_vectors.mjs — delimiter-scan conformance vectors (issue #252).
//
// Runs the PINNED KaTeX auto-render splitter (tools/katex/package.json,
// katex@0.18.7) over a curated input list and emits
// packages/zatex/goldens/delimiter_vectors.json. The vectors are the
// KaTeX-side proof for docs/delimiter-scan.md: every `guards:false`
// island is exactly what KaTeX's own splitAtDelimiters reports, and
// every `guards:true` island is that output with the ZaTeX guard layer
// (spec §4) applied by this script's reference implementation.
//
// Node's type-stripper refuses files under node_modules/, so the script
// copies the pinned splitter to a temp path outside node_modules and
// imports the copy; the copy's sha256 is recorded in the output meta.
//
// Usage: node gen_delim_vectors.mjs   (from tools/katex/)
// Freshness: CI re-runs this and fails on drift (sweep-freshness job).
import { createHash } from "node:crypto";
import { readFileSync, copyFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pinned = join(here, "node_modules/katex/contrib/auto-render/splitAtDelimiters.ts");
const pinnedBytes = readFileSync(pinned);
const sha = createHash("sha256").update(pinnedBytes).digest("hex");
const katexVersion = JSON.parse(
    readFileSync(join(here, "node_modules/katex/package.json"), "utf8"),
).version;

// Import the pinned file from outside node_modules (type-stripping
// restriction only; bytes are KaTeX's own — see `splitter_sha256`).
const stage = mkdtempSync(join(tmpdir(), "delimvec-"));
const staged = join(stage, "splitAtDelimiters.ts");
copyFileSync(pinned, staged);
const { default: splitAtDelimiters } = await import(staged);

// Delimiter tables. `katex_default` is auto-render.ts's own default
// list verbatim (pinned 0.18.7); `dollar` is the same list with the
// commented-out single-dollar entry enabled after `$$` — the table a
// dollar-supporting host scans with before applying guards.
const katexDefault = [
    { left: "$$", right: "$$", display: true },
    { left: "\\(", right: "\\)", display: false },
    { left: "\\begin{equation}", right: "\\end{equation}", display: true },
    { left: "\\begin{align}", right: "\\end{align}", display: true },
    { left: "\\begin{alignat}", right: "\\end{alignat}", display: true },
    { left: "\\begin{gather}", right: "\\end{gather}", display: true },
    { left: "\\begin{CD}", right: "\\end{CD}", display: true },
    { left: "\\[", right: "\\]", display: true },
];
const dollar = [
    { left: "$$", right: "$$", display: true },
    { left: "$", right: "$", display: false },
    { left: "\\(", right: "\\)", display: false },
    { left: "\\[", right: "\\]", display: true },
];
const tables = { katex_default: katexDefault, dollar };

// Guard layer (spec §4), dollar-inline islands only. Returns true when
// the island stays math, false when a guard keeps it literal.
function guardKeeps(text, start, end, left, right) {
    if (left !== "$") {
        // `$$`, `\(`, `\[`: only the escape guard applies.
        return start === 0 || text[start - 1] !== "\\";
    }
    // G-esc: `\$` opens literally.
    if (start > 0 && text[start - 1] === "\\") return false;
    // G-open (currency): `$` glued to a price stays literal.
    const afterOpen = text[start + 1] ?? "";
    const afterOpen2 = text[start + 2] ?? "";
    if (/[0-9]/.test(afterOpen)) return false;
    if (afterOpen === "." && /[0-9]/.test(afterOpen2)) return false;
    // G-close (currency): a closer glued to a trailing price digit
    // stays literal (`$100 and $200` never becomes an island).
    const closeIdx = end - right.length;
    const afterClose = text[closeIdx + right.length] ?? "";
    if (/[0-9]/.test(afterClose)) return false;
    return true;
}

// Mask `` `code` `` spans (spec §5): hosts strip code spans before
// scanning. Returns the masked text plus a map back to original bytes.
function maskCodeSpans(text) {
    let out = "";
    const map = []; // masked index -> original index
    let i = 0;
    while (i < text.length) {
        if (text[i] === "`") {
            const j = text.indexOf("`", i + 1);
            const end = j === -1 ? text.length : j + 1;
            for (let k = i; k < end; k++) {
                out += " ";
                map.push(k);
            }
            i = end;
        } else {
            out += text[i];
            map.push(i);
            i++;
        }
    }
    return { masked: out, map };
}

// Inputs. `mask_code` runs the code-span mask first (the vector text
// keeps the backticks; offsets are in original bytes).
const inputs = [
    // --- KaTeX-default table: raw splitter behavior ---
    { id: "disp-basic", delims: "katex_default", text: "hello $$x^2$$ world" },
    { id: "disp-unclosed", delims: "katex_default", text: "hello $$x^2 world" },
    { id: "inline-paren", delims: "katex_default", text: "hello \\(x+1\\) world" },
    { id: "inline-paren-unclosed", delims: "katex_default", text: "a \\(x b" },
    { id: "bracket", delims: "katex_default", text: "see \\[\\frac12\\] here" },
    { id: "dollar-ignored-by-default", delims: "katex_default", text: "costs $5 and $6" },
    { id: "ams-equation", delims: "katex_default", text: "read \\begin{equation}x^2\\end{equation} now" },
    { id: "ams-align", delims: "katex_default", text: "\\begin{align}a&=b\\end{align}" },
    { id: "brace-shield", delims: "katex_default", text: "hello \\(a { \\) } b\\) end" },
    { id: "escape-close", delims: "katex_default", text: "q \\(a \\} b\\) r", note: "A backslash-escaped closer is skipped, so the island runs to the next live closer." },
    { id: "adjacent-islands", delims: "katex_default", text: "$$a$$ and $$b$$" },
    { id: "disp-multiline-tex", delims: "katex_default", text: "start $$\\sum_{i=1}^n i$$ stop" },
    // --- Dollar table, no guards: raw KaTeX (odd but exact) ---
    { id: "dollar-basic", delims: "dollar", text: "let $x^2$ be" },
    { id: "dollar-mix", delims: "dollar", text: "$hello$world$$boo$$" },
    { id: "dollar-seq", delims: "dollar", text: "$hello$$world$$boo$" },
    { id: "dollar-escape-close", delims: "dollar", text: "$x = \\$5$" },
    // --- Dollar table with guards: the ZaTeX host contract ---
    { id: "guard-price-pair", delims: "dollar", guards: true, text: "$100 and $200" },
    { id: "guard-price-open", delims: "dollar", guards: true, text: "pay $0.00 and $x$ now", note: "G-open drops the price island; the orphaned $x$ closer stays literal too." },
    { id: "guard-price-dot", delims: "dollar", guards: true, text: "only $.99 or $x$ ok" },
    { id: "guard-price-mid", delims: "dollar", guards: true, text: "cost $5 for $x" },
    { id: "guard-escaped-open", delims: "dollar", guards: true, text: "a \\$b\\$ c $x$ d", note: "Guards filter KaTeX islands, never rescan: dropping the \\$-opened island orphans the $x$ closer, so the whole line stays literal." },
    { id: "guard-close-digit", delims: "dollar", guards: true, text: "take $x$2 or $y$" },
    { id: "guard-real-math", delims: "dollar", guards: true, text: "let $x^2$ and $a_1$ be" },
    { id: "guard-display-price", delims: "dollar", guards: true, text: "big $$x^2$$ and $$5$$ ok" },
    { id: "guard-unclosed", delims: "dollar", guards: true, text: "owe $5 today" },
    { id: "guard-code-span", delims: "dollar", guards: true, mask_code: true, text: "use `$x$` here and $y$ too" },
    { id: "guard-paren-zone", delims: "dollar", guards: true, text: "see \\(a\\) plus $b$ end" },
];

const amsRe = /^\\begin\{/;

// KaTeX render verdict for an island payload (the KaTeX-side proof for
// the `engine` flag): true = renders, false = throws with
// throwOnError. Imported from the pinned package's CJS entry.
const { default: katex } = await import("katex");
function katexAccepts(tex, display) {
    try {
        katex.renderToString(tex, { displayMode: display, throwOnError: true });
        return true;
    } catch {
        return false;
    }
}

function toIslands(text, segments, delimsName, guards) {
    const table = tables[delimsName];
    const islands = [];
    // Walk a cursor so repeated substrings resolve to the right bytes.
    let cursor = 0;
    for (const seg of segments) {
        if (seg.type !== "math") {
            cursor += seg.data.length;
            continue;
        }
        const raw = seg.rawData;
        const idx = text.indexOf(raw, cursor);
        if (idx === -1) throw new Error(`raw not found: ${raw}`);
        const end = idx + raw.length;
        cursor = end;
        if (guards) {
            const delim = table.find((d) => raw.startsWith(d.left) && raw.endsWith(d.right));
            if (!guardKeeps(text, idx, end, delim.left, delim.right)) continue;
        }
        const tex = amsRe.test(raw)
            ? raw
            : raw.slice(
                table.find((d) => raw.startsWith(d.left)).left.length,
                raw.length - table.find((d) => raw.endsWith(d.right) && raw.startsWith(d.left)).right.length,
            );
        const disp = seg.display;
        islands.push({ start: idx, end, display: disp, tex });
    }
    return islands;
}

// Expected ZaTeX engine verdict per input (every island in the vector
// shares it; vectors are curated so this holds). Generation FAILS when
// pinned KaTeX disagrees — the flag is KaTeX-proven, and the Zig
// validator (delimvectors.zig) then pins ZaTeX to the same verdict.
const engineExpect = {
    "brace-shield": "reject", // `\)` is not valid math-mode TeX
};

const vectors = inputs.map((v) => {
    let text = v.text;
    let unmap = null;
    if (v.mask_code) {
        const { masked, map } = maskCodeSpans(text);
        unmap = map;
        text = masked;
    }
    const segments = splitAtDelimiters(text, tables[v.delims]);
    let islands = toIslands(text, segments, v.delims, !!v.guards);
    if (unmap) {
        // Translate masked offsets back to original bytes; the tex
        // payload is re-sliced from the ORIGINAL text so code spans
        // can never leak into a payload.
        islands = islands.map((isl) => {
            const start = unmap[isl.start];
            const end = unmap[isl.end - 1] + 1;
            return { ...isl, start, end, tex: v.text.slice(start, end) };
        });
        // With masking the raw slice keeps its delimiters (code-span
        // vectors never use AMS tables), re-derive tex properly:
        const table = tables[v.delims];
        islands = islands.map((isl) => {
            const raw = v.text.slice(isl.start, isl.end);
            const d = table.find((dd) => raw.startsWith(dd.left) && raw.endsWith(dd.right));
            return { ...isl, tex: raw.slice(d.left.length, raw.length - d.right.length) };
        });
    }
    const expect = engineExpect[v.id] ?? "accept";
    for (const isl of islands) {
        const ka = katexAccepts(isl.tex, isl.display) ? "accept" : "reject";
        if (ka !== expect) {
            throw new Error(
                `${v.id}: KaTeX ${ka}s ${JSON.stringify(isl.tex)} but vector expects ${expect}`,
            );
        }
        isl.engine = expect;
    }
    const out_v = {
        id: v.id,
        text: v.text,
        delims: v.delims,
        guards: !!v.guards,
        mask_code: !!v.mask_code,
        islands,
    };
    if (v.note) out_v.note = v.note;
    return out_v;
});

const out = {
    meta: {
        katex: katexVersion,
        splitter: "contrib/auto-render/splitAtDelimiters.ts",
        splitter_sha256: sha,
        generator: "tools/katex/gen_delim_vectors.mjs",
        note: "guards:false islands are raw KaTeX splitter output; guards:true islands add the spec guard layer.",
    },
    delim_tables: tables,
    vectors,
};

writeFileSync(
    join(here, "..", "..", "packages/zatex/goldens/delimiter_vectors.json"),
    JSON.stringify(out, null, 1) + "\n",
);
console.log(`wrote ${vectors.length} vectors, ${vectors.reduce((n, v) => n + v.islands.length, 0)} islands (katex ${katexVersion}, splitter ${sha.slice(0, 12)})`);
