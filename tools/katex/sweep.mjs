import { createRequire } from 'module';
import { readFileSync, writeFileSync } from 'fs';
const require = createRequire(import.meta.url + '/__parent');
const katex = require('katex');
const pkg = require('katex/package.json');
const cases = JSON.parse(readFileSync('corpus.json', 'utf8'));

const out = { katex_version: pkg.version, cases: [] };
for (const c of cases) {
  const row = {
    id: c.id,
    tex: c.tex,
    display: !!c.display,
    ours: c.ours || null,
    katex_only: !!c.katex_only,
    note: c.note || null,
  };
  try {
    const mathml = katex.renderToString(c.tex, {
      displayMode: !!c.display,
      output: 'mathml',
      throwOnError: true,
      trust: true,
      maxExpand: 1000,
    });
    const m = mathml.match(/<math[\s\S]*<\/math>/);
    const math = m ? m[0] : mathml;
    row.katex_ok = true;
    row.katex_mathml = math;
  } catch (e) {
    row.katex_ok = false;
    // Raw numeric position from the error object (message may omit it).
    row.katex_pos = e && typeof e.position === 'number' ? e.position : null;
    row.katex_error = String((e && e.message) || e).slice(0, 220);
  }
  out.cases.push(row);
}
const accepted = out.cases.filter((c) => c.katex_ok).length;
writeFileSync(process.argv[2] || '../../packages/zatex/goldens/katex_sweep.json', JSON.stringify(out, null, 1));
console.log(`katex ${pkg.version}: ${accepted}/${out.cases.length} accepted`);
