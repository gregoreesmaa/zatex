# KaTeX support table (editable source)

Status of every KaTeX function: `accept` (with golden evidence),
`unsup` / `err-parity` (intentional rejects, with reject-row evidence),
or `TODO` (with owner issue). This is the single source of truth —
`docs/katex-syntax.md` is generated from it by
`tools/gen_doc_renders.py` (renders via `zatex-png` into `docs/renders/`;
expected render gaps live in `tools/doc_gaps.json`). Edit statuses here,
never in the mirror.

Row set, names, and order mirror KaTeX 0.18.7 `docs/support_table.md`
exactly, so the two tables compare side by side (upstream lists
`\underrightarrow` and `\vcenter` twice each; this table keeps one row
per function). Table↔sweep coverage is audited by `tools/katex/audit.mjs`.

## Symbols

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `!` | accept | goldens: overset, spacing |

| `\!` | accept | goldens: spacing, flite-negspace |

| `#` | accept | goldens: def, def-args |

| `\#` | accept | goldens: sym-escapes |

| `%` | accept | goldens: comment-basic, sym-escapes |

| `\%` | accept | goldens: sym-escapes |

| `&` | accept | goldens: matrix, aligned, alignedat |

| `\&` | accept | goldens: sym-escapes |

| `'` | accept | goldens: prime-only, prime-sup, primes |

| `\'` | accept | goldens: text, textaccent |

| `(` | accept | goldens: atom-open, big-series, bigl, atomgrid |

| `)` | accept | goldens: atom-open, bigl, cases, atomgrid |

| `\(…\)` | accept | goldens: frac, text, bigl |

| `\ ` | accept | goldens: ctrl-space |

| `\"` | accept | goldens: text, textaccent |

| `\$` | accept | goldens: sym-escapes |

| `\,` | accept | goldens: demo-fourier, int, int-display |

| `\.` | accept | goldens: text |

| `\:` | accept | goldens: spacing |

| `\;` | accept | goldens: spacing |

| `_` | accept | goldens: sub |

| `\_` | accept | goldens: sym-escapes |

| `\`` | accept | goldens: text, textaccent |

| `<` | accept | goldens: atom-rel, atomgrid |

| `\=` | accept | goldens: text |

| `>` | accept | goldens: atom-rel |

| `\>` | TODO | owner #14 |

| `[` | accept | goldens: sqrt-n, atom-open |

| `]` | accept | goldens: sqrt-n, atom-open |

| `{` | accept | goldens: accents, aligned, alignedat |

| `}` | accept | goldens: accents, aligned, alignedat, rej-malf-rbrace |

| `\{` | accept | goldens: big-series, sym-escapes |

| `\}` | accept | goldens: sym-escapes |

| `|` | accept | goldens: vert, array |

| `\|` | accept | goldens: array, leftright-dot, middle, flite-norm2 |

| `~` | accept | goldens: tie |

| `\~` | accept | goldens: text, textaccent |

| `\\ ` | accept | goldens: matrix, aligned, alignedat |

| `^` | accept | goldens: boxed, braces, demo-cauchy, atomgrid, flite-euler, rej-malf-sup |

| `\^` | accept | goldens: text |

## A

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\AA` | accept | goldens: text |

| `\aa` | accept | goldens: text |

| `\above` | TODO | owner #1 |

| `\abovewithdelims` | unsup | goldens: rej-unsup-abovewithdelims |

| `\acute` | accept | goldens: accents |

| `\AE` | accept | goldens: text |

| `\ae` | accept | goldens: text |

| `\alef` | TODO | owner #1 |

| `\alefsym` | TODO | owner #1 |

| `\aleph` | accept | goldens: sym-gal-1 |

| `{align}` | accept | goldens: aligned, alignedat, array |

| `{align*}` | accept | goldens: aligned, alignedat, array |

| `{aligned}` | accept | goldens: aligned, alignedat, array |

| `{alignat}` | accept | goldens: aligned, alignedat, array |

| `{alignat*}` | accept | goldens: aligned, alignedat, array |

| `{alignedat}` | accept | goldens: alignedat, aligned, array |

| `\allowbreak` | TODO | owner #1 |

| `\Alpha` | accept | goldens: sym-gal-0 |

| `\alpha` | accept | goldens: fonts2, let, sym-greek |

| `\amalg` | accept | goldens: sym-gal-1 |

| `\And` | TODO | owner #1 |

| `\and` | unsup | goldens: rej-unsup-and |

| `\ang` | unsup | goldens: rej-unsup-ang |

| `\angl` | TODO | owner #1 |

| `\angln` | TODO | owner #1 |

| `\angle` | accept | goldens: sym-gal-1 |

| `\approx` | accept | goldens: sym-gal-1 |

| `\approxeq` | accept | goldens: sym-gal-1 |

| `\approxcolon` | TODO | owner #1 |

| `\approxcoloncolon` | TODO | owner #1 |

| `\arccos` | accept | goldens: sym-gal-1 |

| `\arcctg` | TODO | owner #1 |

| `\arcsin` | accept | goldens: sym-gal-1 |

| `\arctan` | accept | goldens: sym-gal-1 |

| `\arctg` | TODO | owner #1 |

| `\arg` | accept | goldens: sym-gal-1 |

| `\argmax` | TODO | owner #1 |

| `\argmin` | TODO | owner #1 |

| `{array}` | accept | goldens: array, aligned, alignedat |

| `\array` | unsup | goldens: rej-unsup-array |

| `\arraystretch` | accept | goldens: array, def, aligned |

| `\Arrowvert` | unsup | goldens: rej-unsup-arrowvert |

| `\arrowvert` | unsup | goldens: rej-unsup-arrowvert-2 |

| `\ast` | accept | goldens: sym-gal-1 |

| `\asymp` | accept | goldens: sym-gal-1 |

| `\atop` | accept | goldens: atop |

| `\atopwithdelims` | unsup | goldens: rej-unsup-atopwithdelims |

## B

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\backepsilon` | TODO | owner #1 |

| `\backprime` | accept | goldens: sym-gal-1 |

| `\backsim` | TODO | owner #1 |

| `\backsimeq` | TODO | owner #1 |

| `\backslash` | accept | goldens: sym-gal-1 |

| `\bar` | accept | goldens: accents |

| `\barwedge` | TODO | owner #1 |

| `\Bbb` | TODO | owner #1 |

| `\Bbbk` | TODO | owner #1 |

| `\bbox` | unsup | goldens: rej-unsup-bbox |

| `\bcancel` | TODO | owner #7 |

| `\because` | TODO | owner #1 |

| `\begin` | accept | goldens: matrix, aligned, alignedat, flite-aligned, flite-abs, flite-det, rej-malf-unclosed-env |

| `\begingroup` | TODO | owner #1 |

| `\Beta` | accept | goldens: sym-gal-0 |

| `\beta` | accept | goldens: sym-greek |

| `\beth` | accept | goldens: sym-gal-1 |

| `\between` | TODO | owner #1 |

| `\bf` | TODO | owner #1 |

| `\bfseries` | unsup | goldens: rej-unsup-bfseries |

| `\big` | accept | goldens: big-series |

| `\Big` | accept | goldens: big-series |

| `\bigcap` | accept | goldens: sym-gal-1 |

| `\bigcirc` | TODO | owner #1 |

| `\bigcup` | accept | goldens: sym-gal-1 |

| `\bigg` | accept | goldens: big-series |

| `\Bigg` | accept | goldens: big-series |

| `\biggl` | TODO | owner #4 |

| `\Biggl` | TODO | owner #4 |

| `\biggm` | accept | goldens: vert |

| `\Biggm` | accept | goldens: vert |

| `\biggr` | TODO | owner #4 |

| `\Biggr` | TODO | owner #4 |

| `\bigl` | accept | goldens: bigl, smallmatrix |

| `\Bigl` | accept | goldens: demo-cfrac |

| `\bigm` | accept | goldens: vert |

| `\Bigm` | accept | goldens: vert |

| `\bigodot` | accept | goldens: sym-gal-1 |

| `\bigominus` | unsup | goldens: rej-unsup-bigominus |

| `\bigoplus` | accept | goldens: sym-gal-1 |

| `\bigoslash` | unsup | goldens: rej-unsup-bigoslash |

| `\bigotimes` | accept | goldens: sym-gal-1 |

| `\bigr` | accept | goldens: smallmatrix |

| `\Bigr` | accept | goldens: bigl, demo-cfrac |

| `\bigsqcap` | unsup | goldens: rej-unsup-bigsqcap |

| `\bigsqcup` | TODO | owner #1 |

| `\bigstar` | TODO | owner #1 |

| `\bigtriangledown` | accept | goldens: sym-gal-1 |

| `\bigtriangleup` | accept | goldens: sym-gal-1 |

| `\biguplus` | accept | goldens: sym-gal-2 |

| `\bigvee` | accept | goldens: sym-gal-2 |

| `\bigwedge` | accept | goldens: sym-gal-2 |

| `\binom` | accept | goldens: binom, flite-binom |

| `\blacklozenge` | TODO | owner #1 |

| `\blacksquare` | TODO | owner #1 |

| `\blacktriangle` | TODO | owner #1 |

| `\blacktriangledown` | TODO | owner #1 |

| `\blacktriangleleft` | TODO | owner #1 |

| `\blacktriangleright` | TODO | owner #1 |

| `\bm` | TODO | owner #1 |

| `{Bmatrix}` | accept | goldens: aligned, alignedat, array |

| `{Bmatrix*}` | accept | goldens: aligned, alignedat, array |

| `{bmatrix}` | accept | goldens: bmatrix, aligned, alignedat |

| `{bmatrix*}` | accept | goldens: bmatrix, aligned, alignedat |

| `\bmod` | TODO | owner #1 |

| `\bold` | TODO | owner #1 |

| `\boldsymbol` | accept | goldens: fonts2 |

| `\bot` | accept | goldens: sym-gal-2 |

| `\bowtie` | accept | goldens: sym-gal-2 |

| `\Box` | TODO | owner #1 |

| `\boxdot` | accept | goldens: sym-gal-2 |

| `\boxed` | accept | goldens: boxed |

| `\boxminus` | accept | goldens: sym-gal-2 |

| `\boxplus` | accept | goldens: sym-gal-2 |

| `\boxtimes` | accept | goldens: sym-gal-2 |

| `\Bra` | accept | goldens: sym-greek3 |

| `\bra` | accept | goldens: sym-greek3 |

| `\braket` | accept | goldens: demo-cfrac, sym-greek3 |

| `\Braket` | accept | goldens: frac, bigl, demo-cfrac |

| `\brace` | TODO | owner #2 |

| `\bracevert` | unsup | goldens: rej-unsup-bracevert |

| `\brack` | TODO | owner #2 |

| `\breve` | accept | goldens: accents |

| `\buildrel` | unsup | goldens: rej-unsup-buildrel |

| `\bull` | TODO | owner #1 |

| `\bullet` | accept | goldens: sym-gal-2 |

| `\Bumpeq` | TODO | owner #1 |

| `\bumpeq` | TODO | owner #1 |

## C

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\C` | unsup | goldens: rej-unsup-c |

| `\cal` | TODO | owner #1 |

| `\cancel` | accept | goldens: cancel |

| `\cancelto` | unsup | goldens: rej-unsup-cancelto |

| `\Cap` | TODO | owner #1 |

| `\cap` | accept | goldens: sym-gal-2 |

| `{cases}` | accept | goldens: cases, text, aligned |

| `\cases` | unsup | goldens: rej-unsup-cases |

| `{CD}` | accept | goldens: aligned, alignedat, array |

| `\cdot` | accept | goldens: sym-gal-2 |

| `\cdotp` | accept | goldens: sym-gal-2 |

| `\cdots` | accept | goldens: demo-cfrac |

| `\ce` | TODO | owner #1 |

| `\cee` | unsup | goldens: rej-unsup-cee |

| `\centerdot` | accept | goldens: sym-gal-2 |

| `\cf` | unsup | goldens: rej-unsup-cf |

| `\cfrac` | accept | goldens: cfrac |

| `\char` | TODO | owner #1 |

| `\check` | accept | goldens: accents |

| `\ch` | TODO | owner #1 |

| `\checkmark` | accept | goldens: sym-gal-2 |

| `\Chi` | accept | goldens: sym-gal-0 |

| `\chi` | accept | goldens: sym-greek3 |

| `\choose` | accept | goldens: choose |

| `\circ` | accept | goldens: sym-gal-2 |

| `\circeq` | TODO | owner #1 |

| `\circlearrowleft` | TODO | owner #1 |

| `\circlearrowright` | TODO | owner #1 |

| `\circledast` | TODO | owner #1 |

| `\circledcirc` | TODO | owner #1 |

| `\circleddash` | TODO | owner #1 |

| `\circledR` | accept | goldens: sym-gal-2 |

| `\circledS` | accept | goldens: sym-gal-2 |

| `\class` | unsup | goldens: rej-unsup-class |

| `\cline` | unsup | goldens: rej-unsup-cline |

| `\clubs` | TODO | owner #1 |

| `\clubsuit` | accept | goldens: sym-gal-2 |

| `\cnums` | TODO | owner #1 |

| `\colon` | TODO | owner #1 |

| `\Colonapprox` | TODO | owner #1 |

| `\colonapprox` | TODO | owner #1 |

| `\coloncolon` | TODO | owner #1 |

| `\coloncolonapprox` | TODO | owner #1 |

| `\coloncolonequals` | TODO | owner #1 |

| `\coloncolonminus` | TODO | owner #1 |

| `\coloncolonsim` | TODO | owner #1 |

| `\Coloneq` | TODO | owner #1 |

| `\coloneq` | TODO | owner #1 |

| `\colonequals` | TODO | owner #1 |

| `\Coloneqq` | TODO | owner #1 |

| `\coloneqq` | TODO | owner #1 |

| `\colonminus` | TODO | owner #1 |

| `\Colonsim` | TODO | owner #1 |

| `\colonsim` | TODO | owner #1 |

| `\color` | accept | goldens: color, color-hex, color-macro |

| `\colorbox` | accept | goldens: colorbox |

| `\complement` | TODO | owner #1 |

| `\Complex` | TODO | owner #1 |

| `\cong` | accept | goldens: sym-gal-2 |

| `\Coppa` | unsup | goldens: rej-unsup-coppa |

| `\coppa` | unsup | goldens: rej-unsup-coppa-2 |

| `\coprod` | accept | goldens: sym-gal-2 |

| `\copyright` | TODO | owner #1 |

| `\cos` | accept | goldens: sin |

| `\cosec` | TODO | owner #1 |

| `\cosh` | accept | goldens: sym-gal-2 |

| `\cot` | accept | goldens: sym-gal-2 |

| `\cotg` | TODO | owner #1 |

| `\coth` | accept | goldens: sym-gal-3 |

| `\cr` | accept | goldens: matrix, aligned, alignedat |

| `\csc` | accept | goldens: sym-gal-3 |

| `\cssId` | unsup | goldens: rej-unsup-cssid |

| `\ctg` | TODO | owner #1 |

| `\cth` | TODO | owner #1 |

| `\Cup` | TODO | owner #1 |

| `\cup` | accept | goldens: sym-gal-3 |

| `\curlyeqprec` | TODO | owner #1 |

| `\curlyeqsucc` | TODO | owner #1 |

| `\curlyvee` | TODO | owner #1 |

| `\curlywedge` | TODO | owner #1 |

| `\curvearrowleft` | TODO | owner #1 |

| `\curvearrowright` | TODO | owner #1 |

## D

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\dag` | accept | goldens: sym-gal-3 |

| `\Dagger` | TODO | owner #1 |

| `\dagger` | accept | goldens: sym-gal-3 |

| `\daleth` | accept | goldens: sym-gal-3 |

| `\Darr` | TODO | owner #1 |

| `\dArr` | TODO | owner #1 |

| `\darr` | TODO | owner #1 |

| `\dashleftarrow` | TODO | owner #1 |

| `\dashrightarrow` | TODO | owner #1 |

| `\dashv` | accept | goldens: sym-gal-3 |

| `\dbinom` | accept | goldens: dbinom |

| `\dblcolon` | TODO | owner #1 |

| `{dcases}` | accept | goldens: text, aligned, alignedat |

| `\ddag` | accept | goldens: sym-gal-3 |

| `\ddagger` | accept | goldens: sym-gal-3 |

| `\ddddot` | accept | goldens: sym-accent-ddddot |

| `\dddot` | accept | goldens: sym-accent-dddot |

| `\ddot` | accept | goldens: vec-dot |

| `\ddots` | accept | goldens: sym-gal-3 |

| `\DeclareMathOperator` | err-parity | reject rows: rej-declare-op |

| `\def` | accept | goldens: def, def-args, maxexpand-near-limit |

| `\definecolor` | err-parity | reject rows: definecolor |

| `\deg` | accept | goldens: sym-gal-3 |

| `\degree` | TODO | owner #1 |

| `\delta` | accept | goldens: sym-greek |

| `\Delta` | accept | goldens: sym-Greek |

| `\det` | accept | goldens: sym-gal-3 |

| `\Digamma` | unsup | goldens: rej-unsup-digamma |

| `\digamma` | accept | goldens: sym-gal-3 |

| `\dfrac` | accept | goldens: dfrac |

| `\diagdown` | TODO | owner #1 |

| `\diagup` | TODO | owner #1 |

| `\Diamond` | TODO | owner #1 |

| `\diamond` | accept | goldens: sym-gal-3 |

| `\diamonds` | TODO | owner #1 |

| `\diamondsuit` | accept | goldens: sym-gal-3 |

| `\dim` | accept | goldens: sym-gal-3 |

| `\displaylines` | unsup | goldens: rej-unsup-displaylines |

| `\displaystyle` | accept | goldens: displaystyle, sum, demo-cauchy |

| `\div` | accept | goldens: sym-gal-3 |

| `\divideontimes` | TODO | owner #1 |

| `\dot` | accept | goldens: vec-dot |

| `\Doteq` | TODO | owner #1 |

| `\doteq` | accept | goldens: sym-gal-3 |

| `\doteqdot` | TODO | owner #1 |

| `\dotplus` | TODO | owner #1 |

| `\dots` | accept | goldens: sym-gal-3 |

| `\dotsb` | TODO | owner #1 |

| `\dotsc` | TODO | owner #1 |

| `\dotsi` | accept | goldens: int, demo-fourier, demo-gauss |

| `\dotsm` | TODO | owner #1 |

| `\dotso` | TODO | owner #1 |

| `\doublebarwedge` | TODO | owner #1 |

| `\doublecap` | TODO | owner #1 |

| `\doublecup` | TODO | owner #1 |

| `\Downarrow` | accept | goldens: sym-gal-0 |

| `\downarrow` | accept | goldens: sym-gal-3 |

| `\downdownarrows` | TODO | owner #1 |

| `\downharpoonleft` | TODO | owner #1 |

| `\downharpoonright` | TODO | owner #1 |

| `{drcases}` | accept | goldens: text, aligned, alignedat |

## E

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\edef` | accept | goldens: def, def-args |

| `\ell` | accept | goldens: sym-gal-3 |

| `\else` | unsup | goldens: rej-unsup-else |

| `\em` | unsup | goldens: rej-unsup-em |

| `\emph` | TODO | owner #7 |

| `\empty` | TODO | owner #1 |

| `\emptyset` | accept | goldens: sym-gal-3 |

| `\enclose` | unsup | goldens: rej-unsup-enclose |

| `\end` | accept | goldens: matrix, aligned, alignedat |

| `\endgroup` | TODO | owner #1 |

| `\enspace` | TODO | owner #1 |

| `\Epsilon` | accept | goldens: sym-gal-0 |

| `\epsilon` | accept | goldens: sym-greek |

| `\eqalign` | unsup | goldens: rej-unsup-eqalign |

| `\eqalignno` | unsup | goldens: rej-unsup-eqalignno |

| `\eqcirc` | accept | goldens: sym-gal-3 |

| `\Eqcolon` | TODO | owner #1 |

| `\eqcolon` | TODO | owner #1 |

| `{equation}` | accept | goldens: aligned, alignedat, array |

| `{equation*}` | accept | goldens: aligned, alignedat, array |

| `{eqnarray}` | unsup | goldens: rej-unsup-eqnarray |

| `\Eqqcolon` | TODO | owner #1 |

| `\eqqcolon` | TODO | owner #1 |

| `\eqref` | unsup | goldens: rej-unsup-eqref |

| `\eqsim` | TODO | owner #1 |

| `\eqslantgtr` | TODO | owner #1 |

| `\eqslantless` | TODO | owner #1 |

| `\equalscolon` | TODO | owner #1 |

| `\equalscoloncolon` | TODO | owner #1 |

| `\equiv` | accept | goldens: sym-gal-3 |

| `\Eta` | accept | goldens: sym-gal-0 |

| `\eta` | accept | goldens: sym-greek |

| `\eth` | accept | goldens: sym-gal-3 |

| `\euro` | unsup | goldens: rej-unsup-euro |

| `\exist` | TODO | owner #1 |

| `\exists` | accept | goldens: sym-gal-4 |

| `\exp` | accept | goldens: sym-gal-4 |

| `\expandafter` | TODO | owner #1 |

## F

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\fallingdotseq` | TODO | owner #1 |

| `\fbox` | TODO | owner #7 |

| `\fcolorbox` | accept | goldens: fcolorbox, fcolorbox-empty |

| `\fi` | unsup | goldens: rej-unsup-fi |

| `\Finv` | accept | goldens: sym-gal-0 |

| `\flat` | accept | goldens: sym-gal-4 |

| `\footnotesize` | TODO | owner #1 |

| `\forall` | accept | goldens: sym-gal-4 |

| `\frac` | accept | goldens: frac, bigl, demo-cfrac, flite-quad, rej-malf-frac1, lenient-frac-empty |

| `\frak` | TODO | owner #1 |

| `\frown` | accept | goldens: sym-gal-4 |

| `\futurelet` | TODO | owner #7 |

## G

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\Game` | accept | goldens: sym-gal-0 |

| `\Gamma` | accept | goldens: sym-Greek |

| `\gamma` | accept | goldens: sym-greek |

| `{gather}` | accept | goldens: aligned, alignedat, array |

| `{gathered}` | accept | goldens: gathered, aligned, alignedat |

| `\gcd` | accept | goldens: sym-gal-4 |

| `\gdef` | accept | goldens: gdef-basic |

| `\ge` | accept | goldens: sym-gal-4 |

| `\geneuro` | unsup | goldens: rej-unsup-geneuro |

| `\geneuronarrow` | unsup | goldens: rej-unsup-geneuronarrow |

| `\geneurowide` | unsup | goldens: rej-unsup-geneurowide |

| `\genfrac` | accept | goldens: genfrac |

| `\geq` | accept | goldens: atom-rel, atomgrid |

| `\geqq` | TODO | owner #1 |

| `\geqslant` | TODO | owner #1 |

| `\gets` | accept | goldens: sym-gal-4 |

| `\gg` | accept | goldens: sym-gal-4 |

| `\ggg` | accept | goldens: sym-gal-4 |

| `\gggtr` | TODO | owner #1 |

| `\gimel` | accept | goldens: sym-gal-4 |

| `\global` | accept | goldens: def, def-args, newcommand-arg |

| `\gnapprox` | TODO | owner #1 |

| `\gneq` | TODO | owner #1 |

| `\gneqq` | TODO | owner #1 |

| `\gnsim` | TODO | owner #1 |

| `\grave` | accept | goldens: accents |

| `\gt` | TODO | owner #1 |

| `\gtrdot` | TODO | owner #1 |

| `\gtrapprox` | accept | goldens: sym-gal-4 |

| `\gtreqless` | TODO | owner #1 |

| `\gtreqqless` | TODO | owner #1 |

| `\gtrless` | TODO | owner #1 |

| `\gtrsim` | accept | goldens: sym-gal-4 |

| `\gvertneqq` | TODO | owner #1 |

## H

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\H` | accept | goldens: text |

| `\Harr` | TODO | owner #1 |

| `\hArr` | TODO | owner #1 |

| `\harr` | TODO | owner #1 |

| `\hat` | accept | goldens: hat, demo-fourier, sym-greek |

| `\hbar` | accept | goldens: sym-gal-4 |

| `\hbox` | TODO | owner #7 |

| `\hbox to <dimen>` | TODO | KaTeX accepts (sweep-proven); owner #7 |

| `\hdashline` | accept | goldens: matrix, aligned, alignedat |

| `\hearts` | TODO | owner #1 |

| `\heartsuit` | accept | goldens: sym-gal-4 |

| `\hfil` | unsup | goldens: rej-unsup-hfil |

| `\hfill` | unsup | goldens: rej-unsup-hfill |

| `\hline` | accept | goldens: matrix, aligned, alignedat |

| `\hom` | accept | goldens: sym-gal-4 |

| `\hookleftarrow` | accept | goldens: sym-gal-4 |

| `\hookrightarrow` | accept | goldens: sym-gal-4 |

| `\hphantom` | TODO | owner #7 |

| `\href` | accept | goldens: href |

| `\hskip` | TODO | owner #1 |

| `\hslash` | accept | goldens: sym-gal-4 |

| `\hspace` | accept | goldens: hspace |

| `\htmlClass` | TODO | owner #7 |

| `\htmlData` | TODO | owner #7 |

| `\htmlId` | TODO | owner #7 |

| `\htmlStyle` | TODO | owner #7 |

| `\huge` | TODO | owner #1 |

| `\Huge` | TODO | owner #1 |

## I

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\i` | accept | goldens: text |

| `\idotsint` | unsup | goldens: rej-unsup-idotsint |

| `\iddots` | unsup | goldens: rej-unsup-iddots |

| `\if` | unsup | goldens: rej-unsup-if |

| `\iff` | TODO | owner #1 |

| `\ifmode` | unsup | goldens: rej-unsup-ifmode |

| `\ifx` | unsup | goldens: rej-unsup-ifx |

| `\iiiint` | unsup | goldens: rej-unsup-iiiint |

| `\iiint` | accept | goldens: sym-gal-4 |

| `\iint` | accept | goldens: sym-gal-4 |

| `\Im` | accept | goldens: sym-gal-0 |

| `\image` | TODO | owner #1 |

| `\imageof` | TODO | owner #1 |

| `\imath` | accept | goldens: sym-gal-4 |

| `\impliedby` | TODO | owner #1 |

| `\implies` | TODO | owner #1 |

| `\in` | accept | goldens: not, text |

| `\includegraphics` | TODO | owner #7 |

| `\inf` | accept | goldens: sym-gal-4 |

| `\infin` | TODO | owner #1 |

| `\infty` | accept | goldens: demo-fourier, demo-gauss |

| `\injlim` | TODO | owner #1 |

| `\int` | accept | goldens: int, demo-fourier, demo-gauss, flite-gauss-half |

| `\intercal` | TODO | owner #1 |

| `\intop` | TODO | owner #1 |

| `\Iota` | accept | goldens: sym-gal-0 |

| `\iota` | accept | goldens: sym-greek2 |

| `\isin` | TODO | owner #1 |

| `\it` | TODO | owner #1 |

| `\itshape` | unsup | goldens: rej-unsup-itshape |

## JK

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\j` | accept | goldens: text |

| `\jmath` | accept | goldens: sym-gal-4 |

| `\Join` | accept | goldens: sym-gal-0 |

| `\Kappa` | accept | goldens: sym-gal-0 |

| `\kappa` | accept | goldens: sym-greek2 |

| `\KaTeX` | TODO | owner #1 |

| `\ker` | accept | goldens: sym-gal-4 |

| `\kern` | accept | goldens: hspace |

| `\Ket` | accept | goldens: sym-greek3 |

| `\ket` | accept | goldens: sym-greek3 |

| `\Koppa` | unsup | goldens: rej-unsup-koppa |

| `\koppa` | unsup | goldens: rej-unsup-koppa-2 |

## L

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\L` | unsup | goldens: rej-unsup-l |

| `\l` | unsup | goldens: rej-unsup-l-2 |

| `\Lambda` | accept | goldens: sym-Greek |

| `\lambda` | accept | goldens: sym-greek2 |

| `\label` | unsup | goldens: rej-unsup-label |

| `\land` | accept | goldens: sym-gal-5 |

| `\lang` | accept | goldens: delim-named, sym-gal-5 |

| `\langle` | accept | goldens: big-series, delim-named |

| `\Larr` | TODO | owner #1 |

| `\lArr` | TODO | owner #1 |

| `\larr` | TODO | owner #1 |

| `\large` | TODO | owner #1 |

| `\Large` | TODO | owner #1 |

| `\LARGE` | TODO | owner #1 |

| `\LaTeX` | TODO | owner #1 |

| `\lBrace` | TODO | owner #1 |

| `\lbrace` | TODO | owner #1 |

| `\lbrack` | TODO | owner #1 |

| `\lceil` | accept | goldens: delim-named |

| `\ldotp` | accept | goldens: sym-gal-5 |

| `\ldots` | accept | goldens: sym-gal-5 |

| `\le` | accept | goldens: sym-gal-5 |

| `\leadsto` | TODO | owner #1 |

| `\left` | accept | goldens: dfrac, demo-cauchy, leftright, atomgrid, rej-malf-left |

| `\leftarrow` | accept | goldens: sym-gal-5 |

| `\Leftarrow` | accept | goldens: sym-gal-0 |

| `\LeftArrow` | unsup | goldens: rej-unsup-leftarrow |

| `\leftarrowtail` | TODO | owner #1 |

| `\leftharpoondown` | accept | goldens: sym-gal-5 |

| `\leftharpoonup` | accept | goldens: sym-gal-5 |

| `\leftleftarrows` | TODO | owner #1 |

| `\Leftrightarrow` | accept | goldens: sym-gal-0 |

| `\leftrightarrow` | accept | goldens: sym-gal-5 |

| `\leftrightarrows` | TODO | owner #1 |

| `\leftrightharpoons` | TODO | owner #1 |

| `\leftrightsquigarrow` | TODO | owner #1 |

| `\leftroot` | unsup | goldens: rej-unsup-leftroot |

| `\leftthreetimes` | TODO | owner #1 |

| `\leq` | accept | goldens: atom-rel, demo-cauchy, atomgrid |

| `\leqalignno` | unsup | goldens: rej-unsup-leqalignno |

| `\leqq` | TODO | owner #1 |

| `\leqslant` | TODO | owner #1 |

| `\lessapprox` | accept | goldens: sym-gal-5 |

| `\lessdot` | TODO | owner #1 |

| `\lesseqgtr` | TODO | owner #1 |

| `\lesseqqgtr` | TODO | owner #1 |

| `\lessgtr` | TODO | owner #1 |

| `\lesssim` | accept | goldens: sym-gal-5 |

| `\let` | accept | goldens: let |

| `\lfloor` | accept | goldens: delim-named |

| `\lg` | accept | goldens: sym-gal-5 |

| `\lgroup` | TODO | owner #4 |

| `\lhd` | accept | goldens: sym-gal-5 |

| `\lim` | accept | goldens: lim, lim-display, flite-elimit |

| `\liminf` | accept | goldens: sym-gal-5 |

| `\limits` | accept | goldens: lim, lim-display, limits-force |

| `\limsup` | accept | goldens: sym-gal-5 |

| `\ll` | accept | goldens: sym-gal-5 |

| `\llap` | accept | goldens: demo-fourier, int, int-display |

| `\llbracket` | TODO | owner #1 |

| `\llcorner` | accept | goldens: sym-gal-5 |

| `\Lleftarrow` | TODO | owner #1 |

| `\lll` | accept | goldens: sym-gal-5 |

| `\llless` | TODO | owner #1 |

| `\lmoustache` | TODO | owner #4 |

| `\ln` | accept | goldens: sym-gal-5 |

| `\lnapprox` | TODO | owner #1 |

| `\lneq` | TODO | owner #1 |

| `\lneqq` | TODO | owner #1 |

| `\lnot` | accept | goldens: sym-gal-5 |

| `\lnsim` | TODO | owner #1 |

| `\log` | accept | goldens: log |

| `\long` | TODO | owner #7 |

| `\Longleftarrow` | accept | goldens: sym-gal-0 |

| `\longleftarrow` | accept | goldens: sym-gal-5 |

| `\Longleftrightarrow` | accept | goldens: sym-gal-0 |

| `\longleftrightarrow` | accept | goldens: sym-gal-5 |

| `\longmapsto` | TODO | owner #1 |

| `\Longrightarrow` | accept | goldens: sym-gal-0 |

| `\longrightarrow` | accept | goldens: sym-gal-5 |

| `\looparrowleft` | TODO | owner #1 |

| `\looparrowright` | TODO | owner #1 |

| `\lor` | accept | goldens: sym-gal-5 |

| `\lower` | unsup | goldens: rej-unsup-lower |

| `\lozenge` | TODO | owner #1 |

| `\lparen` | TODO | owner #1 |

| `\Lrarr` | TODO | owner #1 |

| `\lrArr` | TODO | owner #1 |

| `\lrarr` | TODO | owner #1 |

| `\lrcorner` | accept | goldens: sym-gal-6 |

| `\lq` | TODO | owner #1 |

| `\Lsh` | TODO | owner #1 |

| `\lt` | TODO | owner #1 |

| `\ltimes` | TODO | owner #1 |

| `\lVert` | accept | goldens: sym-gal-5 |

| `\lvert` | accept | goldens: sym-gal-6 |

| `\lvertneqq` | TODO | owner #1 |

## M

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\maltese` | accept | goldens: sym-gal-6 |

| `\mapsfrom` | TODO | owner #1 |

| `\mapsto` | accept | goldens: sym-gal-6 |

| `\mathbb` | accept | goldens: fonts, text |

| `\mathbf` | accept | goldens: fonts, flite-dot, flite-maxwell |

| `\mathbin` | TODO | owner #1 |

| `\mathcal` | accept | goldens: fonts |

| `\mathchoice` | accept | goldens: mathchoice, demo-fourier, int |

| `\mathclap` | accept | goldens: sum, demo-cauchy, demo-sumsq |

| `\mathclose` | TODO | owner #1 |

| `\mathellipsis` | TODO | owner #1 |

| `\mathfrak` | accept | goldens: fonts2 |

| `\mathinner` | accept | goldens: text |

| `\mathit` | accept | goldens: fonts |

| `\mathllap` | accept | goldens: demo-fourier, int, int-display |

| `\mathnormal` | TODO | owner #1 |

| `\mathop` | accept | goldens: sym-gal-8 |

| `\mathopen` | TODO | owner #1 |

| `\mathord` | TODO | owner #1 |

| `\mathpunct` | TODO | owner #1 |

| `\mathreflectbox` | TODO | owner #1 |

| `\mathrel` | accept | goldens: sym-escapes |

| `\mathrlap` | accept | goldens: demo-fourier, int, int-display |

| `\mathring` | accept | goldens: sym-accent-mathring |

| `\mathrm` | accept | goldens: fonts |

| `\mathscr` | accept | goldens: fonts |

| `\mathsf` | accept | goldens: fonts2 |

| `\mathsterling` | TODO | owner #1 |

| `\mathstrut` | accept | goldens: sqrt, demo-cfrac, demo-gauss |

| `\mathtip` | unsup | goldens: rej-unsup-mathtip |

| `\mathtt` | accept | goldens: fonts2 |

| `\matrix` | err-parity | reject rows: rej-env-mismatch |

| `{matrix}` | accept | goldens: matrix, aligned, alignedat |

| `{matrix*}` | accept | goldens: matrix, aligned, alignedat |

| `\max` | accept | goldens: sym-gal-6 |

| `\mbox` | unsup | goldens: rej-unsup-mbox |

| `\md` | unsup | goldens: rej-unsup-md |

| `\mdseries` | unsup | goldens: rej-unsup-mdseries |

| `\measuredangle` | accept | goldens: sym-gal-6 |

| `\medspace` | TODO | owner #1 |

| `\mho` | accept | goldens: sym-gal-6 |

| `\mid` | accept | goldens: big-series, sym-escapes, sym-gal-6, flite-bayes |

| `\middle` | accept | goldens: middle, vert, demo-cauchy |

| `\min` | accept | goldens: sym-gal-6 |

| `\minuscolon` | TODO | owner #1 |

| `\minuscoloncolon` | TODO | owner #1 |

| `\minuso` | TODO | owner #1 |

| `\mit` | unsup | goldens: rej-unsup-mit |

| `\mkern` | TODO | owner #1 |

| `\mmlToken` | unsup | goldens: rej-unsup-mmltoken |

| `\mod` | accept | goldens: sym-gal-3 |

| `\models` | accept | goldens: sym-gal-6 |

| `\moveleft` | unsup | goldens: rej-unsup-moveleft |

| `\moveright` | unsup | goldens: rej-unsup-moveright |

| `\mp` | accept | goldens: sym-gal-6 |

| `\mskip` | TODO | owner #1 |

| `\mspace` | unsup | goldens: rej-unsup-mspace |

| `\Mu` | accept | goldens: sym-gal-0 |

| `\mu` | accept | goldens: sym-greek2 |

| `\multicolumn` | unsup | goldens: rej-unsup-multicolumn |

| `{multiline}` | unsup | goldens: rej-unsup-multiline |

| `\multimap` | TODO | owner #1 |

## N

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\N` | TODO | owner #1 |

| `\nabla` | accept | goldens: sym-gal-6, flite-maxwell |

| `\natnums` | TODO | owner #1 |

| `\natural` | accept | goldens: sym-gal-6 |

| `\negmedspace` | TODO | owner #1 |

| `\ncong` | TODO | owner #1 |

| `\ne` | accept | goldens: sym-gal-6 |

| `\nearrow` | accept | goldens: sym-gal-6 |

| `\neg` | accept | goldens: sym-gal-6 |

| `\negthickspace` | TODO | owner #1 |

| `\negthinspace` | TODO | owner #1 |

| `\neq` | accept | goldens: atom-rel, atomgrid |

| `\newcommand` | accept | goldens: newcommand, color-macro, newcommand-arg |

| `\newenvironment` | unsup | goldens: rej-unsup-newenvironment |

| `\Newextarrow` | unsup | goldens: rej-unsup-newextarrow |

| `\newline` | TODO | owner #1 |

| `\nexists` | accept | goldens: sym-gal-6 |

| `\ngeq` | TODO | owner #1 |

| `\ngeqq` | TODO | owner #1 |

| `\ngeqslant` | TODO | owner #1 |

| `\ngtr` | TODO | owner #1 |

| `\ni` | accept | goldens: sym-gal-6 |

| `\nleftarrow` | TODO | owner #1 |

| `\nLeftarrow` | TODO | owner #1 |

| `\nLeftrightarrow` | TODO | owner #1 |

| `\nleftrightarrow` | TODO | owner #1 |

| `\nleq` | TODO | owner #1 |

| `\nleqq` | TODO | owner #1 |

| `\nleqslant` | TODO | owner #1 |

| `\nless` | TODO | owner #1 |

| `\nmid` | accept | goldens: sym-gal-6 |

| `\nobreak` | TODO | owner #1 |

| `\nobreakspace` | TODO | owner #1 |

| `\noexpand` | TODO | owner #1 |

| `\nolimits` | accept | goldens: lim, nolimits, lim-display |

| `\nonumber` | accept | goldens: aligned, alignedat, array |

| `\normalfont` | unsup | goldens: rej-unsup-normalfont |

| `\normalsize` | TODO | owner #1 |

| `\not` | accept | goldens: not |

| `\notag` | accept | goldens: aligned, alignedat, array |

| `\notin` | TODO | owner #1 |

| `\notni` | TODO | owner #1 |

| `\nparallel` | TODO | owner #1 |

| `\nprec` | TODO | owner #1 |

| `\npreceq` | TODO | owner #1 |

| `\nRightarrow` | TODO | owner #1 |

| `\nrightarrow` | TODO | owner #1 |

| `\nshortmid` | TODO | owner #1 |

| `\nshortparallel` | TODO | owner #1 |

| `\nsim` | TODO | owner #1 |

| `\nsubseteq` | TODO | owner #1 |

| `\nsubseteqq` | TODO | owner #1 |

| `\nsucc` | TODO | owner #1 |

| `\nsucceq` | TODO | owner #1 |

| `\nsupseteq` | TODO | owner #1 |

| `\nsupseteqq` | TODO | owner #1 |

| `\ntriangleleft` | TODO | owner #1 |

| `\ntrianglelefteq` | TODO | owner #1 |

| `\ntriangleright` | TODO | owner #1 |

| `\ntrianglerighteq` | TODO | owner #1 |

| `\Nu` | accept | goldens: sym-gal-0 |

| `\nu` | accept | goldens: sym-greek2 |

| `\nVDash` | TODO | owner #1 |

| `\nVdash` | TODO | owner #1 |

| `\nvDash` | TODO | owner #1 |

| `\nvdash` | TODO | owner #1 |

| `\nwarrow` | accept | goldens: sym-gal-6 |

## O

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\O` | accept | goldens: text |

| `\o` | accept | goldens: text |

| `\odot` | accept | goldens: sym-gal-6 |

| `\OE` | accept | goldens: text |

| `\oe` | accept | goldens: text |

| `\officialeuro` | unsup | goldens: rej-unsup-officialeuro |

| `\oiiint` | TODO | owner #3 |

| `\oiint` | TODO | owner #3 |

| `\oint` | accept | goldens: oint |

| `\oldstyle` | unsup | goldens: rej-unsup-oldstyle |

| `\omega` | accept | goldens: sym-greek3 |

| `\Omega` | accept | goldens: sym-Greek |

| `\Omicron` | TODO | owner #1 |

| `\omicron` | TODO | owner #1 |

| `\ominus` | accept | goldens: sym-gal-6 |

| `\operatorname` | accept | goldens: operatorname, operatorname-star |

| `\operatorname*` | accept | goldens: operatorname, limits-force, operatorname-star |

| `\operatornamewithlimits` | accept | goldens: limits-force |

| `\oplus` | accept | goldens: sym-gal-6 |

| `\or` | unsup | goldens: rej-unsup-or |

| `\origof` | TODO | owner #1 |

| `\oslash` | accept | goldens: sym-gal-6 |

| `\otimes` | accept | goldens: sym-gal-6 |

| `\over` | accept | goldens: over |

| `\overbrace` | accept | goldens: text, braces |

| `\overbracket` | accept | goldens: text |

| `\overgroup` | TODO | owner #5 |

| `\overleftarrow` | accept | goldens: arrows-over |

| `\overleftharpoon` | TODO | owner #1 |

| `\overleftrightarrow` | TODO | owner #5 |

| `\overline` | accept | goldens: overline, text |

| `\overlinesegment` | TODO | owner #5 |

| `\overparen` | unsup | goldens: rej-unsup-overparen |

| `\Overrightarrow` | TODO | owner #1 |

| `\overrightarrow` | accept | goldens: arrows-over |

| `\overrightharpoon` | TODO | owner #1 |

| `\overset` | accept | goldens: overset |

| `\overwithdelims` | unsup | goldens: rej-unsup-overwithdelims |

| `\owns` | accept | goldens: sym-gal-7 |

## P

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\P` | accept | goldens: text |

| `\pagecolor` | unsup | goldens: rej-unsup-pagecolor |

| `\parallel` | accept | goldens: sym-gal-7 |

| `\part` | unsup | goldens: rej-unsup-part |

| `\partial` | accept | goldens: sym-gal-7, flite-maxwell |

| `\perp` | accept | goldens: sym-gal-7 |

| `\phantom` | accept | goldens: phantom, sym-Greek |

| `\phase` | accept | goldens: sym-gal-2 |

| `\Phi` | accept | goldens: sym-Greek |

| `\phi` | accept | goldens: demo-cfrac, sym-greek3 |

| `\Pi` | accept | goldens: sym-Greek |

| `\pi` | accept | goldens: demo-cfrac, demo-fourier, demo-gauss |

| `{picture}` | unsup | goldens: rej-unsup-picture |

| `\pitchfork` | TODO | owner #1 |

| `\plim` | TODO | owner #1 |

| `\plusmn` | TODO | owner #1 |

| `\pm` | accept | goldens: sym-gal-7, flite-quad |

| `\pmatrix` | unsup | goldens: rej-unsup-pmatrix |

| `{pmatrix}` | accept | goldens: pmatrix, aligned, alignedat |

| `{pmatrix*}` | accept | goldens: pmatrix, aligned, alignedat |

| `\pmb` | accept | goldens: sym-greek2 |

| `\pmod` | TODO | owner #1 |

| `\pod` | TODO | owner #1 |

| `\pounds` | accept | goldens: sym-gal-7 |

| `\Pr` | accept | goldens: sym-gal-0 |

| `\prec` | accept | goldens: sym-gal-7 |

| `\precapprox` | TODO | owner #1 |

| `\preccurlyeq` | TODO | owner #1 |

| `\preceq` | accept | goldens: sym-gal-7 |

| `\precnapprox` | TODO | owner #1 |

| `\precneqq` | TODO | owner #1 |

| `\precnsim` | TODO | owner #1 |

| `\precsim` | TODO | owner #1 |

| `\prime` | accept | goldens: sym-gal-7 |

| `\prod` | accept | goldens: prod |

| `\projlim` | TODO | owner #1 |

| `\propto` | accept | goldens: sym-gal-7 |

| `\providecommand` | accept | goldens: providecommand, text |

| `\psi` | accept | goldens: sym-greek3 |

| `\Psi` | accept | goldens: sym-Greek |

| `\pu` | TODO | owner #1 |

## QR

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\Q` | unsup | goldens: rej-unsup-q |

| `\qquad` | accept | goldens: spacing |

| `\quad` | accept | goldens: spacing |

| `\R` | TODO | owner #1 |

| `\r` | accept | goldens: text |

| `\raise` | unsup | goldens: rej-unsup-raise |

| `\raisebox` | accept | goldens: raisebox |

| `\rang` | accept | goldens: big-series, delim-named, sym-gal-7 |

| `\rangle` | accept | goldens: big-series, delim-named |

| `\Rarr` | TODO | owner #1 |

| `\rArr` | TODO | owner #1 |

| `\rarr` | TODO | owner #1 |

| `\ratio` | TODO | owner #1 |

| `\rBrace` | TODO | owner #1 |

| `\rbrace` | TODO | owner #1 |

| `\rbrack` | TODO | owner #1 |

| `{rcases}` | accept | goldens: text, aligned, alignedat |

| `\rceil` | accept | goldens: delim-named |

| `\Re` | accept | goldens: sym-gal-0 |

| `\real` | TODO | owner #1 |

| `\Reals` | TODO | owner #1 |

| `\reals` | TODO | owner #1 |

| `\ref` | unsup | goldens: rej-unsup-ref |

| `\reflectbox` | TODO | owner #1 |

| `\relax` | TODO | owner #1 |

| `\renewcommand` | accept | goldens: def, renewcommand, def-args |

| `\renewenvironment` | unsup | goldens: rej-unsup-renewenvironment |

| `\require` | unsup | goldens: rej-unsup-require |

| `\restriction` | TODO | owner #1 |

| `\rfloor` | accept | goldens: delim-named |

| `\rgroup` | TODO | owner #4 |

| `\rhd` | accept | goldens: sym-gal-7 |

| `\Rho` | accept | goldens: sym-gal-0 |

| `\rho` | accept | goldens: sym-greek2 |

| `\right` | accept | goldens: dfrac, demo-cauchy, leftright, atomgrid, rej-malf-right |

| `\Rightarrow` | accept | goldens: sym-gal-0 |

| `\rightarrow` | accept | goldens: sym-gal-7 |

| `\rightarrowtail` | TODO | owner #1 |

| `\rightharpoondown` | accept | goldens: sym-gal-7 |

| `\rightharpoonup` | accept | goldens: sym-gal-7 |

| `\rightleftarrows` | TODO | owner #1 |

| `\rightleftharpoons` | accept | goldens: sym-gal-7 |

| `\rightrightarrows` | TODO | owner #1 |

| `\rightsquigarrow` | TODO | owner #1 |

| `\rightthreetimes` | TODO | owner #1 |

| `\risingdotseq` | TODO | owner #1 |

| `\rlap` | accept | goldens: demo-fourier, int, int-display |

| `\rm` | TODO | owner #1 |

| `\rmoustache` | TODO | owner #4 |

| `\root` | unsup | goldens: rej-unsup-root |

| `\rotatebox` | unsup | goldens: rej-unsup-rotatebox |

| `\rparen` | TODO | owner #1 |

| `\rq` | TODO | owner #1 |

| `\rrbracket` | TODO | owner #1 |

| `\Rrightarrow` | TODO | owner #1 |

| `\Rsh` | TODO | owner #1 |

| `\rtimes` | TODO | owner #1 |

| `\Rule` | unsup | goldens: rej-unsup-rule |

| `\rule` | accept | goldens: rule |

| `\rVert` | accept | goldens: sym-gal-7 |

| `\rvert` | accept | goldens: sym-gal-7 |

## S

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\S` | accept | goldens: text |

| `\Sampi` | unsup | goldens: rej-unsup-sampi |

| `\sampi` | unsup | goldens: rej-unsup-sampi-2 |

| `\sc` | unsup | goldens: rej-unsup-sc |

| `\scalebox` | unsup | goldens: rej-unsup-scalebox |

| `\scr` | unsup | goldens: rej-unsup-scr |

| `\scriptscriptstyle` | accept | goldens: frac, bigl, demo-cfrac |

| `\scriptsize` | TODO | owner #1 |

| `\scriptstyle` | accept | goldens: frac, bigl, demo-cfrac |

| `\sdot` | TODO | owner #1 |

| `\searrow` | accept | goldens: sym-gal-7 |

| `\sec` | accept | goldens: sym-gal-7 |

| `\sect` | accept | goldens: text |

| `\set` | TODO | owner #1 |

| `\Set` | accept | goldens: frac, bigl, demo-cfrac |

| `\setlength` | unsup | goldens: rej-unsup-setlength |

| `\setminus` | accept | goldens: sym-gal-7 |

| `\sf` | TODO | owner #1 |

| `\sharp` | accept | goldens: sym-gal-7 |

| `\shortmid` | TODO | owner #1 |

| `\shortparallel` | TODO | owner #1 |

| `\shoveleft` | unsup | goldens: rej-unsup-shoveleft |

| `\shoveright` | unsup | goldens: rej-unsup-shoveright |

| `\sideset` | unsup | goldens: rej-unsup-sideset |

| `\Sigma` | accept | goldens: sym-Greek |

| `\sigma` | accept | goldens: sym-greek3 |

| `\sim` | accept | goldens: sym-gal-7 |

| `\simcolon` | TODO | owner #1 |

| `\simcoloncolon` | TODO | owner #1 |

| `\simeq` | accept | goldens: sym-gal-7 |

| `\sin` | accept | goldens: sin |

| `\sinh` | accept | goldens: sym-gal-7 |

| `\sixptsize` | TODO | owner #1 |

| `\sh` | TODO | owner #1 |

| `\skew` | unsup | goldens: rej-unsup-skew |

| `\skip` | unsup | goldens: rej-unsup-skip |

| `\sl` | unsup | goldens: rej-unsup-sl |

| `\small` | TODO | owner #1 |

| `\smallfrown` | TODO | owner #1 |

| `\smallint` | TODO | owner #1 |

| `{smallmatrix}` | accept | goldens: smallmatrix, aligned, alignedat |

| `\smallsetminus` | TODO | owner #1 |

| `\smallsmile` | TODO | owner #1 |

| `\smash` | accept | goldens: smash, demo-cauchy, leftright |

| `\smile` | accept | goldens: sym-gal-8 |

| `\smiley` | unsup | goldens: rej-unsup-smiley |

| `\sout` | accept | goldens: text |

| `\Space` | unsup | goldens: rej-unsup-space |

| `\space` | TODO | owner #1 |

| `\spades` | TODO | owner #1 |

| `\spadesuit` | accept | goldens: sym-gal-8 |

| `\sphericalangle` | accept | goldens: sym-gal-8 |

| `{split}` | accept | goldens: aligned, alignedat, array |

| `\sqcap` | accept | goldens: sym-gal-8 |

| `\sqcup` | accept | goldens: sym-gal-8 |

| `\square` | TODO | owner #1 |

| `\sqrt` | accept | goldens: sqrt, demo-cfrac, demo-gauss, flite-nestrad, flite-normal, rej-malf-sqrtb |

| `\sqsubset` | accept | goldens: sym-gal-8 |

| `\sqsubseteq` | accept | goldens: sym-gal-8 |

| `\sqsupset` | accept | goldens: sym-gal-8 |

| `\sqsupseteq` | accept | goldens: sym-gal-8 |

| `\ss` | accept | goldens: text |

| `\stackrel` | TODO | owner #1 |

| `\star` | accept | goldens: sym-gal-8 |

| `\Stigma` | unsup | goldens: rej-unsup-stigma |

| `\stigma` | unsup | goldens: rej-unsup-stigma-2 |

| `\strut` | unsup | goldens: rej-unsup-strut |

| `\style` | unsup | goldens: rej-unsup-style |

| `\sub` | TODO | owner #1 |

| `{subarray}` | TODO | KaTeX accepts with alignment arg (sweep-proven); owner #14 |

| `\sube` | TODO | owner #1 |

| `\Subset` | TODO | owner #1 |

| `\subset` | accept | goldens: sym-gal-8 |

| `\subseteq` | accept | goldens: sym-gal-8 |

| `\subseteqq` | TODO | owner #1 |

| `\subsetneq` | accept | goldens: sym-gal-8 |

| `\subsetneqq` | TODO | owner #1 |

| `\substack` | accept | goldens: substack, sum, demo-cauchy |

| `\succ` | accept | goldens: sym-gal-8 |

| `\succapprox` | TODO | owner #1 |

| `\succcurlyeq` | TODO | owner #1 |

| `\succeq` | accept | goldens: sym-gal-8 |

| `\succnapprox` | TODO | owner #1 |

| `\succneqq` | TODO | owner #1 |

| `\succnsim` | TODO | owner #1 |

| `\succsim` | TODO | owner #1 |

| `\sum` | accept | goldens: sum, demo-cauchy, demo-sumsq, atomgrid, flite-series |

| `\sup` | accept | goldens: sym-gal-8 |

| `\supe` | TODO | owner #1 |

| `\Supset` | TODO | owner #1 |

| `\supset` | accept | goldens: sym-gal-8 |

| `\supseteq` | accept | goldens: sym-gal-8 |

| `\supseteqq` | TODO | owner #1 |

| `\supsetneq` | accept | goldens: sym-gal-8 |

| `\supsetneqq` | TODO | owner #1 |

| `\surd` | accept | goldens: sym-gal-8 |

| `\swarrow` | accept | goldens: sym-gal-8 |

## T

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\tag` | TODO | owner #1 |

| `\tag*` | TODO | owner #1 |

| `\tan` | accept | goldens: sym-gal-8 |

| `\tanh` | accept | goldens: sym-gal-8 |

| `\Tau` | accept | goldens: sym-gal-0 |

| `\tau` | accept | goldens: sym-greek3 |

| `\tbinom` | TODO | owner #2 |

| `\TeX` | TODO | owner #1 |

| `\text` | accept | goldens: text, sym-escapes |

| `\textasciitilde` | accept | goldens: text |

| `\textasciicircum` | accept | goldens: text |

| `\textbackslash` | accept | goldens: text |

| `\textbar` | accept | goldens: text |

| `\textbardbl` | accept | goldens: text |

| `\textbf` | accept | goldens: textbf |

| `\textbraceleft` | accept | goldens: text |

| `\textbraceright` | accept | goldens: text |

| `\textcircled` | accept | goldens: text |

| `\textcolor` | accept | goldens: textcolor |

| `\textdagger` | accept | goldens: text |

| `\textdaggerdbl` | accept | goldens: text |

| `\textdegree` | accept | goldens: text |

| `\textdollar` | accept | goldens: text |

| `\textellipsis` | accept | goldens: text |

| `\textemdash` | accept | goldens: text |

| `\textendash` | accept | goldens: text |

| `\textgreater` | accept | goldens: text |

| `\textit` | accept | goldens: textit |

| `\textless` | accept | goldens: text |

| `\textmd` | TODO | owner #1 |

| `\textnormal` | accept | goldens: textnormal |

| `\textquotedblleft` | accept | goldens: text |

| `\textquotedblright` | accept | goldens: text |

| `\textquoteleft` | accept | goldens: text |

| `\textquoteright` | accept | goldens: text |

| `\textregistered` | accept | goldens: text, sym-gal-8 |

| `\textrm` | accept | goldens: textrm |

| `\textsc` | unsup | goldens: rej-unsup-textsc |

| `\textsf` | accept | goldens: textsf |

| `\textsl` | err-parity | reject rows: textsl |

| `\textsterling` | accept | goldens: text |

| `\textstyle` | accept | goldens: sum, demo-cauchy, demo-sumsq |

| `\texttip` | unsup | goldens: rej-unsup-texttip |

| `\texttt` | accept | goldens: texttt |

| `\textunderscore` | accept | goldens: text |

| `\textup` | TODO | owner #1 |

| `\textvisiblespace` | unsup | goldens: rej-unsup-textvisiblespace |

| `\tfrac` | accept | goldens: tfrac |

| `\tg` | TODO | owner #1 |

| `\th` | TODO | owner #1 |

| `\therefore` | TODO | owner #1 |

| `\Theta` | accept | goldens: sym-Greek |

| `\theta` | accept | goldens: sym-greek |

| `\thetasym` | TODO | owner #1 |

| `\thickapprox` | TODO | owner #1 |

| `\thicksim` | TODO | owner #1 |

| `\thickspace` | TODO | owner #1 |

| `\thinspace` | TODO | owner #1 |

| `\tilde` | accept | goldens: accents |

| `\times` | accept | goldens: sym-gal-8, flite-maxwell |

| `\Tiny` | unsup | goldens: rej-unsup-tiny |

| `\tiny` | TODO | owner #1 |

| `\to` | accept | goldens: lim, lim-display |

| `\toggle` | unsup | goldens: rej-unsup-toggle |

| `\top` | accept | goldens: sym-gal-9 |

| `\triangle` | TODO | owner #1 |

| `\triangledown` | TODO | owner #1 |

| `\triangleleft` | accept | goldens: sym-gal-9 |

| `\trianglelefteq` | TODO | owner #1 |

| `\triangleq` | TODO | owner #1 |

| `\triangleright` | accept | goldens: sym-gal-9 |

| `\trianglerighteq` | TODO | owner #1 |

| `\tt` | TODO | owner #1 |

| `\twoheadleftarrow` | TODO | owner #1 |

| `\twoheadrightarrow` | TODO | owner #1 |

## U

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\u` | accept | goldens: text |

| `\Uarr` | TODO | owner #1 |

| `\uArr` | TODO | owner #1 |

| `\uarr` | TODO | owner #1 |

| `\ulcorner` | accept | goldens: sym-gal-9 |

| `\underbar` | TODO | owner #1 |

| `\underbrace` | accept | goldens: text, braces |

| `\underbracket` | accept | goldens: text |

| `\undergroup` | TODO | owner #5 |

| `\underleftarrow` | TODO | owner #5 |

| `\underleftrightarrow` | TODO | owner #5 |

| `\underrightarrow` | TODO | owner #5 |

| `\underline` | accept | goldens: text, underline |

| `\underlinesegment` | TODO | owner #5 |

| `\underparen` | unsup | goldens: rej-unsup-underparen |

| `\underset` | accept | goldens: overset |

| `\unicode` | unsup | goldens: rej-unsup-unicode |

| `\unlhd` | accept | goldens: sym-gal-9 |

| `\unrhd` | accept | goldens: sym-gal-9 |

| `\up` | unsup | goldens: rej-unsup-up |

| `\Uparrow` | accept | goldens: sym-gal-0 |

| `\uparrow` | accept | goldens: sym-gal-9 |

| `\Updownarrow` | accept | goldens: sym-gal-1 |

| `\updownarrow` | accept | goldens: sym-gal-9 |

| `\upharpoonleft` | TODO | owner #1 |

| `\upharpoonright` | TODO | owner #1 |

| `\uplus` | accept | goldens: sym-gal-9 |

| `\uproot` | unsup | goldens: rej-unsup-uproot |

| `\upshape` | unsup | goldens: rej-unsup-upshape |

| `\Upsilon` | accept | goldens: sym-gal-1 |

| `\upsilon` | accept | goldens: sym-greek3 |

| `\upuparrows` | TODO | owner #1 |

| `\urcorner` | accept | goldens: sym-gal-9 |

| `\url` | accept | goldens: url |

| `\utilde` | TODO | owner #5 |

## V

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\v` | accept | goldens: text |

| `\varcoppa` | unsup | goldens: rej-unsup-varcoppa |

| `\varDelta` | TODO | owner #1 |

| `\varepsilon` | accept | goldens: sym-greek |

| `\varGamma` | TODO | owner #1 |

| `\varinjlim` | TODO | owner #1 |

| `\varkappa` | TODO | owner #1 |

| `\varLambda` | TODO | owner #1 |

| `\varliminf` | TODO | owner #1 |

| `\varlimsup` | TODO | owner #1 |

| `\varnothing` | accept | goldens: sym-gal-9 |

| `\varOmega` | TODO | owner #1 |

| `\varPhi` | TODO | owner #1 |

| `\varphi` | accept | goldens: sym-greek3 |

| `\varPi` | TODO | owner #1 |

| `\varpi` | accept | goldens: sym-greek2 |

| `\varprojlim` | TODO | owner #1 |

| `\varpropto` | TODO | owner #1 |

| `\varPsi` | TODO | owner #1 |

| `\varrho` | accept | goldens: sym-greek2 |

| `\varSigma` | TODO | owner #1 |

| `\varsigma` | accept | goldens: sym-greek3 |

| `\varstigma` | unsup | goldens: rej-unsup-varstigma |

| `\varsubsetneq` | TODO | owner #1 |

| `\varsubsetneqq` | TODO | owner #1 |

| `\varsupsetneq` | TODO | owner #1 |

| `\varsupsetneqq` | TODO | owner #1 |

| `\varTheta` | TODO | owner #1 |

| `\vartheta` | accept | goldens: sym-greek |

| `\vartriangle` | TODO | owner #1 |

| `\vartriangleleft` | TODO | owner #1 |

| `\vartriangleright` | TODO | owner #1 |

| `\varUpsilon` | TODO | owner #1 |

| `\varXi` | TODO | owner #1 |

| `\vcentcolon` | TODO | owner #1 |

| `\vcenter` | accept | goldens: frac, bigl, demo-cauchy |

| `\Vdash` | TODO | owner #1 |

| `\vDash` | TODO | owner #1 |

| `\vdash` | accept | goldens: sym-gal-9 |

| `\vdots` | accept | goldens: sym-gal-9 |

| `\vec` | accept | goldens: vec-dot |

| `\vee` | accept | goldens: sym-gal-9 |

| `\veebar` | TODO | owner #1 |

| `\verb` | accept | goldens: frac, bigl, demo-cfrac |

| `\Vert` | accept | goldens: sym-gal-1 |

| `\vert` | accept | goldens: vert |

| `\vfil` | unsup | goldens: rej-unsup-vfil |

| `\vfill` | unsup | goldens: rej-unsup-vfill |

| `\vline` | unsup | goldens: rej-unsup-vline |

| `{Vmatrix}` | accept | goldens: aligned, alignedat, array |

| `{Vmatrix*}` | accept | goldens: aligned, alignedat, array |

| `{vmatrix}` | accept | goldens: vmatrix, aligned, alignedat |

| `{vmatrix*}` | accept | goldens: vmatrix, aligned, alignedat |

| `\vphantom` | accept | goldens: overline |

| `\Vvdash` | TODO | owner #1 |

## W

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\wedge` | accept | goldens: sym-gal-9 |

| `\weierp` | TODO | owner #1 |

| `\widecheck` | accept | goldens: sym-accent-widecheck |

| `\widehat` | accept | goldens: widehat |

| `\wideparen` | unsup | goldens: rej-unsup-wideparen |

| `\widetilde` | accept | goldens: sym-accent-widetilde |

| `\wp` | accept | goldens: sym-gal-9 |

| `\wr` | accept | goldens: sym-gal-9 |

## X

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\xcancel` | TODO | owner #7 |

| `\xdef` | accept | goldens: def, def-args |

| `\Xi` | accept | goldens: sym-Greek |

| `\xi` | accept | goldens: demo-fourier, hat, sym-greek2 |

| `\xhookleftarrow` | TODO | owner #1 |

| `\xhookrightarrow` | TODO | owner #1 |

| `\xLeftarrow` | TODO | owner #1 |

| `\xleftarrow` | accept | goldens: xarrow |

| `\xleftharpoondown` | TODO | owner #1 |

| `\xleftharpoonup` | TODO | owner #1 |

| `\xLeftrightarrow` | TODO | owner #1 |

| `\xleftrightarrow` | TODO | owner #1 |

| `\xleftrightharpoons` | TODO | owner #1 |

| `\xlongequal` | TODO | owner #1 |

| `\xmapsto` | TODO | owner #1 |

| `\xRightarrow` | TODO | owner #1 |

| `\xrightarrow` | accept | goldens: xarrow |

| `\xrightharpoondown` | TODO | owner #1 |

| `\xrightharpoonup` | TODO | owner #1 |

| `\xrightleftharpoons` | TODO | owner #1 |

| `\xtofrom` | TODO | owner #1 |

| `\xtwoheadleftarrow` | TODO | owner #1 |

| `\xtwoheadrightarrow` | TODO | owner #1 |

## YZ

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\yen` | accept | goldens: sym-gal-9 |

| `\Z` | TODO | owner #1 |

| `\Zeta` | accept | goldens: sym-gal-1 |

| `\zeta` | accept | goldens: sym-greek |

---
Totals: 552 accept, 4 err-parity, 121 unsup, 459 TODO.
