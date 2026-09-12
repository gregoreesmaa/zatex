const fs = require('fs');
const src = fs.readFileSync('node_modules/katex/dist/katex.mjs', 'utf8');
// defineSymbol(mode, family, type, char, name, accept)
// char is like "\u221e" or a literal; name is like "\\infty" or a literal.
const re = /defineSymbol\((math|text|ams),\s*([A-Za-z]+),\s*([A-Za-z]+),\s*"((?:\\u[0-9a-fA-F]+|\\.|[^"\\])*)",\s*"((?:\\.|[^"\\])*)"/g;
const k = {};
let m;
while ((m = re.exec(src))) {
  const mode = m[1], fam = m[2], type = m[3];
  const chRaw = m[4], nameRaw = m[5];
  const unesc = (s) => s.replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/\\(.)/g, '$1');
  const ch = unesc(chRaw);
  const nm = unesc(nameRaw).replace(/^\\/, '');
  const cps = [...ch];
  if (cps.length !== 1) continue;
  k[nm] = { type, cp: cps[0].codePointAt(0), fam };
}
fs.writeFileSync('/tmp/katex_syms.json', JSON.stringify(k));
console.log(Object.keys(k).length, 'katex symbols');
