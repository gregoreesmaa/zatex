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
Known upstream-prose-stale rows (pinned bundle accepts, so this table
does too — bundle is arbiter): `{subarray}` (upstream row 1018 says
"Not supported"; sweep subarray-c/subarray-l prove katex_ok) and
``\hbox to <dimen>`` (upstream Rendered cell is empty, but the bundle
accepts it — both engines read `\hbox to 10pt{A}` as `\hbox{t}` with
the rest spilling as math; sweep hbox-to proves katex_ok).
Extension-gated rows (`\ce`, `\pu`): upstream marks them supported,
but support requires the mhchem contrib extension — the pinned core
bundle rejects both (`Undefined control sequence`), so this table
(and the engine) honestly report `unsup` with reject-row evidence.
Extension support is future work.
Scoping decision (issue #98): `\htmlClass`, `\htmlData`, `\htmlId`,
`\htmlStyle` stay `accept` as transparent wrappers — the HTML span
annotation has no native-layout meaning, and KaTeX's own MathML output
drops it too (sweep t-html* rows agree tag-for-tag with the bare body).
`\includegraphics` stays `accept`: MathML emits the `<mglyph>` element
KaTeX emits (sweep graphics-* rows agree; representative shapes pinned
byte-exact in `qa` goldens) while layout reserves the metric box for
the host to paint — image loading stays out of the core per the
zero-dependency tenet, so PNG renders show the reserved space, never
fetched pixels. Neither row claims pixels the core cannot produce.

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

| `'` | accept | goldens: prime-only, prime-sup, primes, prime-sup-rq, prime-sup-quote, prime-sub |

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

| `\>` | accept | goldens: gt-space |

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

| `\above` | accept | goldens: above |

| `\abovewithdelims` | unsup | goldens: rej-unsup-abovewithdelims |

| `\acute` | accept | goldens: accents |

| `\AE` | accept | goldens: text |

| `\ae` | accept | goldens: text |

| `\alef` | accept | goldens: sym-alef |

| `\alefsym` | accept | goldens: sym-alefsym |

| `\aleph` | accept | goldens: sym-gal-1 |

| `{align}` | accept | goldens: disp-align, disp-align-star |

| `{align*}` | accept | goldens: disp-align-star |

| `{aligned}` | accept | goldens: aligned, alignedat, array |

| `{alignat}` | accept | goldens: disp-alignat, disp-alignat-star, disp-alignat-noarg |

| `{alignat*}` | accept | goldens: disp-alignat-star |

| `{alignedat}` | accept | goldens: alignedat, aligned, array |

| `\allowbreak` | accept | goldens: arb-allowbreak |

| `\Alpha` | accept | goldens: sym-gal-0 |

| `\alpha` | accept | goldens: fonts2, let, sym-greek |

| `\amalg` | accept | goldens: sym-gal-1 |

| `\And` | accept | goldens: sym-And |

| `\and` | unsup | goldens: rej-unsup-and |

| `\ang` | unsup | goldens: rej-unsup-ang |

| `\angl` | accept | goldens: angl |

| `\angln` | accept | goldens: angln |

| `\angle` | accept | goldens: sym-gal-1 |

| `\approx` | accept | goldens: sym-gal-1 |

| `\approxeq` | accept | goldens: sym-gal-1 |

| `\approxcolon` | accept | goldens: t-approxcolon |

| `\approxcoloncolon` | accept | goldens: t-approxcoloncolon |

| `\arccos` | accept | goldens: sym-gal-1 |

| `\arcctg` | accept | goldens: arcctg |

| `\arcsin` | accept | goldens: sym-gal-1 |

| `\arctan` | accept | goldens: sym-gal-1 |

| `\arctg` | accept | goldens: arctg |

| `\arg` | accept | goldens: sym-gal-1 |

| `\argmax` | accept | goldens: argmax |

| `\argmin` | accept | goldens: argmin |

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
| `\backepsilon` | accept | goldens: sym-backepsilon |

| `\backprime` | accept | goldens: sym-gal-1 |

| `\backsim` | accept | goldens: sym-backsim |

| `\backsimeq` | accept | goldens: sym-backsimeq |

| `\backslash` | accept | goldens: sym-gal-1 |

| `\bar` | accept | goldens: accents |

| `\barwedge` | accept | goldens: sym-barwedge |

| `\Bbb` | accept | goldens: Bbb |

| `\Bbbk` | accept | goldens: sym-Bbbk |

| `\bbox` | unsup | goldens: rej-unsup-bbox |

| `\bcancel` | accept | goldens: bcancel |

| `\because` | accept | goldens: sym-because |

| `\begin` | accept | goldens: matrix, aligned, alignedat, flite-aligned, flite-abs, flite-det, rej-malf-unclosed-env |

| `\begingroup` | accept | goldens: begingroup, begingroup-unclosed, begingroup-mismatch |

| `\Beta` | accept | goldens: sym-gal-0 |

| `\beta` | accept | goldens: sym-greek |

| `\beth` | accept | goldens: sym-gal-1 |

| `\between` | accept | goldens: sym-between |

| `\bf` | accept | goldens: bf |

| `\bfseries` | unsup | goldens: rej-unsup-bfseries |

| `\big` | accept | goldens: big-series |

| `\Big` | accept | goldens: big-series |

| `\bigcap` | accept | goldens: sym-gal-1 |

| `\bigcirc` | accept | goldens: sym-bigcirc |

| `\bigcup` | accept | goldens: sym-gal-1 |

| `\bigg` | accept | goldens: big-series |

| `\Bigg` | accept | goldens: big-series |

| `\biggl` | accept | goldens: biggl |

| `\Biggl` | accept | goldens: Biggl |

| `\biggm` | accept | goldens: vert |

| `\Biggm` | accept | goldens: vert |

| `\biggr` | accept | goldens: biggr |

| `\Biggr` | accept | goldens: Biggr |

| `\bigl` | accept | goldens: bigl, smallmatrix, prime-bigl |

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

| `\bigsqcup` | accept | goldens: sym-bigsqcup |

| `\bigstar` | accept | goldens: sym-bigstar |

| `\bigtriangledown` | accept | goldens: sym-gal-1 |

| `\bigtriangleup` | accept | goldens: sym-gal-1 |

| `\biguplus` | accept | goldens: sym-gal-2 |

| `\bigvee` | accept | goldens: sym-gal-2 |

| `\bigwedge` | accept | goldens: sym-gal-2 |

| `\binom` | accept | goldens: binom, flite-binom |

| `\blacklozenge` | accept | goldens: sym-blacklozenge |

| `\blacksquare` | accept | goldens: sym-blacksquare |

| `\blacktriangle` | accept | goldens: sym-blacktriangle |

| `\blacktriangledown` | accept | goldens: sym-blacktriangledown |

| `\blacktriangleleft` | accept | goldens: sym-blacktriangleleft |

| `\blacktriangleright` | accept | goldens: sym-blacktriangleright |

| `\bm` | accept | goldens: t-bm |

| `{Bmatrix}` | accept | goldens: aligned, alignedat, array |

| `{Bmatrix*}` | accept | goldens: aligned, alignedat, array |

| `{bmatrix}` | accept | goldens: bmatrix, aligned, alignedat |

| `{bmatrix*}` | accept | goldens: bmatrix, aligned, alignedat |

| `\bmod` | accept | goldens: bmod, bmod-bare |

| `\bold` | accept | goldens: t-bold |

| `\boldsymbol` | accept | goldens: fonts2 |

| `\bot` | accept | goldens: sym-gal-2 |

| `\bowtie` | accept | goldens: sym-gal-2 |

| `\Box` | accept | goldens: sym-Box |

| `\boxdot` | accept | goldens: sym-gal-2 |

| `\boxed` | accept | goldens: boxed |

| `\boxminus` | accept | goldens: sym-gal-2 |

| `\boxplus` | accept | goldens: sym-gal-2 |

| `\boxtimes` | accept | goldens: sym-gal-2 |

| `\Bra` | accept | goldens: sym-greek3 |

| `\bra` | accept | goldens: sym-greek3 |

| `\braket` | accept | goldens: braket-basic, braket-nobar |

| `\Braket` | accept | goldens: Braket-basic, Braket-two, Braket-dbl |

| `\brace` | accept | goldens: brace |

| `\bracevert` | unsup | goldens: rej-unsup-bracevert |

| `\brack` | accept | goldens: brack |

| `\breve` | accept | goldens: accents |

| `\buildrel` | unsup | goldens: rej-unsup-buildrel |

| `\bull` | accept | goldens: sym-bull |

| `\bullet` | accept | goldens: sym-gal-2 |

| `\Bumpeq` | accept | goldens: sym-Bumpeq |

| `\bumpeq` | accept | goldens: sym-bumpeq |

## C

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\C` | unsup | goldens: rej-unsup-c |

| `\cal` | accept | goldens: cal |

| `\cancel` | accept | goldens: cancel |

| `\cancelto` | unsup | goldens: rej-unsup-cancelto |

| `\Cap` | accept | goldens: sym-Cap |

| `\cap` | accept | goldens: sym-gal-2 |

| `{cases}` | accept | goldens: cases, text, aligned |

| `\cases` | unsup | goldens: rej-unsup-cases |

| `{CD}` | accept | goldens: disp-cd-h, disp-cd-hlabels, disp-cd-v, disp-cd-eq, disp-cd-vert, disp-cd-dot, disp-cd-badarrow, disp-cd-incomplete |

| `\cdot` | accept | goldens: sym-gal-2 |

| `\cdotp` | accept | goldens: sym-gal-2 |

| `\cdots` | accept | goldens: demo-cfrac |

| `\ce` | unsup | goldens: rej-unsup-ce |

| `\cee` | unsup | goldens: rej-unsup-cee |

| `\centerdot` | accept | goldens: sym-gal-2 |

| `\cf` | unsup | goldens: rej-unsup-cf |

| `\cfrac` | accept | goldens: cfrac |

| `\char` | accept | goldens: t-char |

| `\check` | accept | goldens: accents |

| `\ch` | accept | goldens: ch |

| `\checkmark` | accept | goldens: sym-gal-2 |

| `\Chi` | accept | goldens: sym-gal-0 |

| `\chi` | accept | goldens: sym-greek3 |

| `\choose` | accept | goldens: choose |

| `\circ` | accept | goldens: sym-gal-2 |

| `\circeq` | accept | goldens: sym-circeq |

| `\circlearrowleft` | accept | goldens: sym-circlearrowleft |

| `\circlearrowright` | accept | goldens: sym-circlearrowright |

| `\circledast` | accept | goldens: sym-circledast |

| `\circledcirc` | accept | goldens: sym-circledcirc |

| `\circleddash` | accept | goldens: sym-circleddash |

| `\circledR` | accept | goldens: sym-gal-2 |

| `\circledS` | accept | goldens: sym-gal-2 |

| `\class` | unsup | goldens: rej-unsup-class |

| `\cline` | unsup | goldens: rej-unsup-cline |

| `\clubs` | accept | goldens: sym-clubs |

| `\clubsuit` | accept | goldens: sym-gal-2 |

| `\cnums` | accept | goldens: sym-cnums |

| `\colon` | accept | goldens: t-colon |

| `\Colonapprox` | accept | goldens: t-Colonapprox |

| `\colonapprox` | accept | goldens: t-colonapprox |

| `\coloncolon` | accept | goldens: t-coloncolon |

| `\coloncolonapprox` | accept | goldens: t-coloncolonapprox |

| `\coloncolonequals` | accept | goldens: t-coloncolonequals |

| `\coloncolonminus` | accept | goldens: t-coloncolonminus |

| `\coloncolonsim` | accept | goldens: t-coloncolonsim |

| `\Coloneq` | accept | goldens: t-Coloneq |

| `\coloneq` | accept | goldens: t-coloneq |

| `\colonequals` | accept | goldens: t-colonequals |

| `\Coloneqq` | accept | goldens: t-Coloneqq |

| `\coloneqq` | accept | goldens: t-coloneqq |

| `\colonminus` | accept | goldens: t-colonminus |

| `\Colonsim` | accept | goldens: t-Colonsim |

| `\colonsim` | accept | goldens: t-colonsim |

| `\color` | accept | goldens: color, color-hex, color-macro, color-over-split |

| `\colorbox` | accept | goldens: colorbox |

| `\complement` | accept | goldens: sym-complement |

| `\Complex` | accept | goldens: sym-Complex |

| `\cong` | accept | goldens: sym-gal-2 |

| `\Coppa` | unsup | goldens: rej-unsup-coppa |

| `\coppa` | unsup | goldens: rej-unsup-coppa-2 |

| `\coprod` | accept | goldens: sym-gal-2 |

| `\copyright` | accept | goldens: t-copyright |

| `\cos` | accept | goldens: sin |

| `\cosec` | accept | goldens: cosec |

| `\cosh` | accept | goldens: sym-gal-2 |

| `\cot` | accept | goldens: sym-gal-2 |

| `\cotg` | accept | goldens: cotg |

| `\coth` | accept | goldens: sym-gal-3 |

| `\cr` | accept | goldens: matrix, aligned, alignedat |

| `\csc` | accept | goldens: sym-gal-3 |

| `\cssId` | unsup | goldens: rej-unsup-cssid |

| `\ctg` | accept | goldens: ctg |

| `\cth` | accept | goldens: cth |

| `\Cup` | accept | goldens: sym-Cup |

| `\cup` | accept | goldens: sym-gal-3 |

| `\curlyeqprec` | accept | goldens: sym-curlyeqprec |

| `\curlyeqsucc` | accept | goldens: sym-curlyeqsucc |

| `\curlyvee` | accept | goldens: sym-curlyvee |

| `\curlywedge` | accept | goldens: sym-curlywedge |

| `\curvearrowleft` | accept | goldens: sym-curvearrowleft |

| `\curvearrowright` | accept | goldens: sym-curvearrowright |

## D

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\dag` | accept | goldens: sym-gal-3 |

| `\Dagger` | accept | goldens: sym-Dagger |

| `\dagger` | accept | goldens: sym-gal-3 |

| `\daleth` | accept | goldens: sym-gal-3 |

| `\Darr` | accept | goldens: sym-Darr |

| `\dArr` | accept | goldens: sym-dArr |

| `\darr` | accept | goldens: sym-darr |

| `\dashleftarrow` | accept | goldens: sym-dashleftarrow |

| `\dashrightarrow` | accept | goldens: sym-dashrightarrow |

| `\dashv` | accept | goldens: sym-gal-3 |

| `\dbinom` | accept | goldens: dbinom |

| `\dblcolon` | accept | goldens: t-dblcolon |

| `{dcases}` | accept | goldens: text, aligned, alignedat |

| `\ddag` | accept | goldens: sym-gal-3 |

| `\ddagger` | accept | goldens: sym-gal-3 |

| `\ddddot` | accept | goldens: sym-accent-ddddot |

| `\dddot` | accept | goldens: sym-accent-dddot |

| `\ddot` | accept | goldens: vec-dot |

| `\ddots` | accept | goldens: sym-gal-3 |

| `\DeclareMathOperator` | err-parity | goldens: rej-declare-op |

| `\def` | accept | goldens: def, def-args, maxexpand-near-limit |

| `\definecolor` | err-parity | goldens: definecolor |

| `\deg` | accept | goldens: sym-gal-3 |

| `\degree` | accept | goldens: sym-degree |

| `\delta` | accept | goldens: sym-greek |

| `\Delta` | accept | goldens: sym-Greek |

| `\det` | accept | goldens: sym-gal-3 |

| `\Digamma` | unsup | goldens: rej-unsup-digamma |

| `\digamma` | accept | goldens: sym-gal-3 |

| `\dfrac` | accept | goldens: dfrac |

| `\diagdown` | accept | goldens: sym-diagdown |

| `\diagup` | accept | goldens: sym-diagup |

| `\Diamond` | accept | goldens: sym-Diamond |

| `\diamond` | accept | goldens: sym-gal-3 |

| `\diamonds` | accept | goldens: sym-diamonds |

| `\diamondsuit` | accept | goldens: sym-gal-3 |

| `\dim` | accept | goldens: sym-gal-3 |

| `\displaylines` | unsup | goldens: rej-unsup-displaylines |

| `\displaystyle` | accept | goldens: displaystyle, displaystyle-over-split, sum, demo-cauchy |

| `\div` | accept | goldens: sym-gal-3 |

| `\divideontimes` | accept | goldens: sym-divideontimes |

| `\dot` | accept | goldens: vec-dot |

| `\Doteq` | accept | goldens: sym-Doteq |

| `\doteq` | accept | goldens: sym-gal-3 |

| `\doteqdot` | accept | goldens: sym-doteqdot |

| `\dotplus` | accept | goldens: sym-dotplus |

| `\dots` | accept | goldens: sym-gal-3 |

| `\dotsb` | accept | goldens: sym-dotsb |

| `\dotsc` | accept | goldens: sym-dotsc |

| `\dotsi` | accept | goldens: int, demo-fourier, demo-gauss |

| `\dotsm` | accept | goldens: sym-dotsm |

| `\dotso` | accept | goldens: sym-dotso |

| `\doublebarwedge` | accept | goldens: sym-doublebarwedge |

| `\doublecap` | accept | goldens: sym-doublecap |

| `\doublecup` | accept | goldens: sym-doublecup |

| `\Downarrow` | accept | goldens: sym-gal-0 |

| `\downarrow` | accept | goldens: sym-gal-3 |

| `\downdownarrows` | accept | goldens: sym-downdownarrows |

| `\downharpoonleft` | accept | goldens: sym-downharpoonleft |

| `\downharpoonright` | accept | goldens: sym-downharpoonright |

| `{drcases}` | accept | goldens: text, aligned, alignedat |

## E

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\edef` | accept | goldens: def, def-args |

| `\ell` | accept | goldens: sym-gal-3 |

| `\else` | unsup | goldens: rej-unsup-else |

| `\em` | unsup | goldens: rej-unsup-em |

| `\emph` | accept | goldens: emph |

| `\empty` | accept | goldens: sym-empty |

| `\emptyset` | accept | goldens: sym-gal-3 |

| `\enclose` | unsup | goldens: rej-unsup-enclose |

| `\end` | accept | goldens: matrix, aligned, alignedat |

| `\endgroup` | accept | goldens: begingroup, endgroup-stray, endgroup-in-brace |

| `\enspace` | accept | goldens: enspace |

| `\Epsilon` | accept | goldens: sym-gal-0 |

| `\epsilon` | accept | goldens: sym-greek |

| `\eqalign` | unsup | goldens: rej-unsup-eqalign |

| `\eqalignno` | unsup | goldens: rej-unsup-eqalignno |

| `\eqcirc` | accept | goldens: sym-gal-3 |

| `\Eqcolon` | accept | goldens: t-Eqcolon |

| `\eqcolon` | accept | goldens: t-eqcolon |

| `{equation}` | accept | goldens: disp-equation, disp-equation-amp |

| `{equation*}` | accept | goldens: disp-equation-star |

| `{eqnarray}` | unsup | goldens: rej-unsup-eqnarray |

| `\Eqqcolon` | accept | goldens: t-Eqqcolon |

| `\eqqcolon` | accept | goldens: t-eqqcolon |

| `\eqref` | unsup | goldens: rej-unsup-eqref |

| `\eqsim` | accept | goldens: sym-eqsim |

| `\eqslantgtr` | accept | goldens: sym-eqslantgtr |

| `\eqslantless` | accept | goldens: sym-eqslantless |

| `\equalscolon` | accept | goldens: t-equalscolon |

| `\equalscoloncolon` | accept | goldens: t-equalscoloncolon |

| `\equiv` | accept | goldens: sym-gal-3 |

| `\errmessage` | accept | goldens: errmessage-basic |

| `\Eta` | accept | goldens: sym-gal-0 |

| `\eta` | accept | goldens: sym-greek |

| `\eth` | accept | goldens: sym-gal-3 |

| `\euro` | unsup | goldens: rej-unsup-euro |

| `\exist` | accept | goldens: sym-exist |

| `\exists` | accept | goldens: sym-gal-4 |

| `\exp` | accept | goldens: sym-gal-4 |

| `\expandafter` | accept | goldens: arb-expandafter |

## F

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\fallingdotseq` | accept | goldens: sym-fallingdotseq |

| `\fbox` | accept | goldens: t-fbox |

| `\fcolorbox` | accept | goldens: fcolorbox, fcolorbox-empty |

| `\fi` | unsup | goldens: rej-unsup-fi |

| `\Finv` | accept | goldens: sym-gal-0 |

| `\flat` | accept | goldens: sym-gal-4 |

| `\footnotesize` | accept | goldens: footnotesize |

| `\forall` | accept | goldens: sym-gal-4 |

| `\frac` | accept | goldens: frac, bigl, demo-cfrac, flite-quad, rej-malf-frac1, lenient-frac-empty, prime-frac |

| `\frak` | accept | goldens: t-frak |

| `\frown` | accept | goldens: sym-gal-4 |

| `\futurelet` | accept | goldens: arb-futurelet, arb-futurelet-undef |

## G

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\Game` | accept | goldens: sym-gal-0 |

| `\Gamma` | accept | goldens: sym-Greek |

| `\gamma` | accept | goldens: sym-greek |

| `{gather}` | accept | goldens: disp-gather, disp-gather-star |

| `{gathered}` | accept | goldens: gathered, aligned, alignedat |

| `\gcd` | accept | goldens: sym-gal-4 |

| `\gdef` | accept | goldens: gdef-basic |

| `\ge` | accept | goldens: sym-gal-4 |

| `\geneuro` | unsup | goldens: rej-unsup-geneuro |

| `\geneuronarrow` | unsup | goldens: rej-unsup-geneuronarrow |

| `\geneurowide` | unsup | goldens: rej-unsup-geneurowide |

| `\genfrac` | accept | goldens: genfrac |

| `\geq` | accept | goldens: atom-rel, atomgrid |

| `\geqq` | accept | goldens: sym-geqq |

| `\geqslant` | accept | goldens: sym-geqslant |

| `\gets` | accept | goldens: sym-gal-4 |

| `\gg` | accept | goldens: sym-gal-4 |

| `\ggg` | accept | goldens: sym-gal-4 |

| `\gggtr` | accept | goldens: sym-gggtr |

| `\gimel` | accept | goldens: sym-gal-4 |

| `\global` | accept | goldens: def, def-args, newcommand-arg, arb-global-bad |

| `\gnapprox` | accept | goldens: sym-gnapprox |

| `\gneq` | accept | goldens: sym-gneq |

| `\gneqq` | accept | goldens: sym-gneqq |

| `\gnsim` | accept | goldens: sym-gnsim |

| `\grave` | accept | goldens: accents |

| `\gt` | accept | goldens: sym-gt |

| `\gtrdot` | accept | goldens: sym-gtrdot |

| `\gtrapprox` | accept | goldens: sym-gal-4 |

| `\gtreqless` | accept | goldens: sym-gtreqless |

| `\gtreqqless` | accept | goldens: sym-gtreqqless |

| `\gtrless` | accept | goldens: sym-gtrless |

| `\gtrsim` | accept | goldens: sym-gal-4 |

| `\gvertneqq` | accept | goldens: sym-gvertneqq |

## H

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\H` | accept | goldens: text |

| `\Harr` | accept | goldens: sym-Harr |

| `\hArr` | accept | goldens: sym-hArr |

| `\harr` | accept | goldens: sym-harr |

| `\hat` | accept | goldens: hat, demo-fourier, sym-greek, prime-hat |

| `\hbar` | accept | goldens: sym-gal-4 |

| `\hbox` | accept | goldens: hbox, hbox-to |

| `\hbox to <dimen>` | accept | goldens: hbox-to |

| `\hdashline` | accept | goldens: matrix, aligned, alignedat |

| `\hearts` | accept | goldens: sym-hearts |

| `\heartsuit` | accept | goldens: sym-gal-4 |

| `\hfil` | unsup | goldens: rej-unsup-hfil |

| `\hfill` | unsup | goldens: rej-unsup-hfill |

| `\hline` | accept | goldens: matrix, aligned, alignedat |

| `\hom` | accept | goldens: sym-gal-4 |

| `\hookleftarrow` | accept | goldens: sym-gal-4 |

| `\hookrightarrow` | accept | goldens: sym-gal-4 |

| `\hphantom` | accept | goldens: t-hphantom |

| `\href` | accept | goldens: href |

| `\hskip` | accept | goldens: hskip |

| `\hslash` | accept | goldens: sym-gal-4 |

| `\hspace` | accept | goldens: hspace |

| `\htmlClass` | accept | goldens: htmlClass |

| `\htmlData` | accept | goldens: htmlData |

| `\htmlId` | accept | goldens: htmlId |

| `\htmlStyle` | accept | goldens: htmlStyle |

| `\huge` | accept | goldens: huge |

| `\Huge` | accept | goldens: Huge |

## I

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\i` | accept | goldens: text |

| `\idotsint` | unsup | goldens: rej-unsup-idotsint |

| `\iddots` | unsup | goldens: rej-unsup-iddots |

| `\if` | unsup | goldens: rej-unsup-if |

| `\iff` | accept | goldens: iff |

| `\ifmode` | unsup | goldens: rej-unsup-ifmode |

| `\ifx` | unsup | goldens: rej-unsup-ifx |

| `\iiiint` | unsup | goldens: rej-unsup-iiiint |

| `\iiint` | accept | goldens: sym-gal-4 |

| `\iint` | accept | goldens: sym-gal-4 |

| `\Im` | accept | goldens: sym-gal-0 |

| `\image` | accept | goldens: sym-image |

| `\imageof` | accept | goldens: sym-imageof |

| `\imath` | accept | goldens: sym-gal-4 |

| `\impliedby` | accept | goldens: impliedby |

| `\implies` | accept | goldens: implies |

| `\in` | accept | goldens: not, text |

| `\includegraphics` | accept | goldens: graphics |

| `\inf` | accept | goldens: sym-gal-4 |

| `\infin` | accept | goldens: sym-infin |

| `\infty` | accept | goldens: demo-fourier, demo-gauss |

| `\injlim` | accept | goldens: injlim |

| `\int` | accept | goldens: int, demo-fourier, demo-gauss, flite-gauss-half |

| `\intercal` | accept | goldens: sym-intercal |

| `\intop` | accept | goldens: sym-intop |

| `\Iota` | accept | goldens: sym-gal-0 |

| `\iota` | accept | goldens: sym-greek2 |

| `\isin` | accept | goldens: sym-isin |

| `\it` | accept | goldens: it |

| `\itshape` | unsup | goldens: rej-unsup-itshape |

## JK

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\j` | accept | goldens: text |

| `\jmath` | accept | goldens: sym-gal-4 |

| `\Join` | accept | goldens: sym-gal-0 |

| `\Kappa` | accept | goldens: sym-gal-0 |

| `\kappa` | accept | goldens: sym-greek2 |

| `\KaTeX` | accept | goldens: t-KaTeX |

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

| `\Larr` | accept | goldens: sym-Larr |

| `\lArr` | accept | goldens: sym-lArr |

| `\larr` | accept | goldens: sym-larr |

| `\large` | accept | goldens: large |

| `\Large` | accept | goldens: Large |

| `\LARGE` | accept | goldens: LARGE |

| `\LaTeX` | accept | goldens: t-LaTeX |

| `\lBrace` | accept | goldens: lbrace, rbrace |

| `\lbrace` | accept | goldens: sym-lbrace |

| `\lbrack` | accept | goldens: sym-lbrack |

| `\lceil` | accept | goldens: delim-named |

| `\ldotp` | accept | goldens: sym-gal-5 |

| `\ldots` | accept | goldens: sym-gal-5 |

| `\le` | accept | goldens: sym-gal-5 |

| `\leadsto` | accept | goldens: sym-leadsto |

| `\left` | accept | goldens: dfrac, demo-cauchy, leftright, atomgrid, rej-malf-left |

| `\leftarrow` | accept | goldens: sym-gal-5 |

| `\Leftarrow` | accept | goldens: sym-gal-0 |

| `\LeftArrow` | unsup | goldens: rej-unsup-leftarrow |

| `\leftarrowtail` | accept | goldens: sym-leftarrowtail |

| `\leftharpoondown` | accept | goldens: sym-gal-5 |

| `\leftharpoonup` | accept | goldens: sym-gal-5 |

| `\leftleftarrows` | accept | goldens: sym-leftleftarrows |

| `\Leftrightarrow` | accept | goldens: sym-gal-0 |

| `\leftrightarrow` | accept | goldens: sym-gal-5 |

| `\leftrightarrows` | accept | goldens: sym-leftrightarrows |

| `\leftrightharpoons` | accept | goldens: sym-leftrightharpoons |

| `\leftrightsquigarrow` | accept | goldens: sym-leftrightsquigarrow |

| `\leftroot` | unsup | goldens: rej-unsup-leftroot |

| `\leftthreetimes` | accept | goldens: sym-leftthreetimes |

| `\leq` | accept | goldens: atom-rel, demo-cauchy, atomgrid |

| `\leqalignno` | unsup | goldens: rej-unsup-leqalignno |

| `\leqq` | accept | goldens: sym-leqq |

| `\leqslant` | accept | goldens: sym-leqslant |

| `\lessapprox` | accept | goldens: sym-gal-5 |

| `\lessdot` | accept | goldens: sym-lessdot |

| `\lesseqgtr` | accept | goldens: sym-lesseqgtr |

| `\lesseqqgtr` | accept | goldens: sym-lesseqqgtr |

| `\lessgtr` | accept | goldens: sym-lessgtr |

| `\lesssim` | accept | goldens: sym-gal-5 |

| `\let` | accept | goldens: let, arb-let-alias-undef, arb-let-alias-shadow |

| `\lfloor` | accept | goldens: delim-named |

| `\lg` | accept | goldens: sym-gal-5 |

| `\lgroup` | accept | goldens: sym-lgroup |

| `\lhd` | accept | goldens: sym-gal-5 |

| `\lim` | accept | goldens: lim, lim-display, flite-elimit |

| `\liminf` | accept | goldens: sym-gal-5 |

| `\limits` | accept | goldens: lim, lim-display, limits-force |

| `\limsup` | accept | goldens: sym-gal-5 |

| `\ll` | accept | goldens: sym-gal-5 |

| `\llap` | accept | goldens: lap, lap-llap-sub |

| `\llbracket` | accept | goldens: sym-llbracket |

| `\llcorner` | accept | goldens: sym-gal-5 |

| `\Lleftarrow` | accept | goldens: sym-Lleftarrow |

| `\lll` | accept | goldens: sym-gal-5 |

| `\llless` | accept | goldens: sym-llless |

| `\lmoustache` | accept | goldens: sym-lmoustache |

| `\ln` | accept | goldens: sym-gal-5 |

| `\lnapprox` | accept | goldens: sym-lnapprox |

| `\lneq` | accept | goldens: sym-lneq |

| `\lneqq` | accept | goldens: sym-lneqq |

| `\lnot` | accept | goldens: sym-gal-5 |

| `\lnsim` | accept | goldens: sym-lnsim |

| `\log` | accept | goldens: log |

| `\long` | accept | goldens: arb-long, arb-long-bad |

| `\Longleftarrow` | accept | goldens: sym-gal-0 |

| `\longleftarrow` | accept | goldens: sym-gal-5 |

| `\Longleftrightarrow` | accept | goldens: sym-gal-0 |

| `\longleftrightarrow` | accept | goldens: sym-gal-5 |

| `\longmapsto` | accept | goldens: sym-longmapsto |

| `\Longrightarrow` | accept | goldens: sym-gal-0 |

| `\longrightarrow` | accept | goldens: sym-gal-5 |

| `\looparrowleft` | accept | goldens: sym-looparrowleft |

| `\looparrowright` | accept | goldens: sym-looparrowright |

| `\lor` | accept | goldens: sym-gal-5 |

| `\lower` | unsup | goldens: rej-unsup-lower |

| `\lozenge` | accept | goldens: sym-lozenge |

| `\lparen` | accept | goldens: sym-lparen |

| `\Lrarr` | accept | goldens: sym-Lrarr |

| `\lrArr` | accept | goldens: sym-lrArr |

| `\lrarr` | accept | goldens: sym-lrarr |

| `\lrcorner` | accept | goldens: sym-gal-6 |

| `\lq` | accept | goldens: sym-lq |

| `\Lsh` | accept | goldens: sym-Lsh |

| `\lt` | accept | goldens: sym-lt |

| `\ltimes` | accept | goldens: sym-ltimes |

| `\lVert` | accept | goldens: sym-gal-5 |

| `\lvert` | accept | goldens: sym-gal-6 |

| `\lvertneqq` | accept | goldens: sym-lvertneqq |

## M

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\maltese` | accept | goldens: sym-gal-6 |

| `\mapsfrom` | accept | goldens: sym-mapsfrom |

| `\mapsto` | accept | goldens: sym-gal-6 |

| `\mathbb` | accept | goldens: fonts, text |

| `\mathbf` | accept | goldens: fonts, flite-dot, flite-maxwell |

| `\mathbin` | accept | goldens: t-mathbin |

| `\mathcal` | accept | goldens: fonts |

| `\mathchoice` | accept | goldens: mathchoice, demo-fourier, int |

| `\mathclap` | accept | goldens: lap-clap-sub, lap-clap-sub-text, lap-clap-sup |

| `\mathclose` | accept | goldens: t-mathclose |

| `\mathellipsis` | accept | goldens: sym-mathellipsis |

| `\mathfrak` | accept | goldens: fonts2 |

| `\mathinner` | accept | goldens: text, t-mathinner, t-mathinner-group |

| `\mathit` | accept | goldens: fonts |

| `\mathllap` | accept | goldens: demo-fourier, int, int-display |

| `\mathnormal` | accept | goldens: mathnormal |

| `\mathop` | accept | goldens: sym-gal-8, t-mathop, t-mathop-group |

| `\mathopen` | accept | goldens: t-mathopen |

| `\mathord` | accept | goldens: t-mathord |

| `\mathpunct` | accept | goldens: t-mathpunct |

| `\mathreflectbox` | accept | goldens: mathreflectbox |

| `\mathrel` | accept | goldens: sym-escapes |

| `\mathrlap` | accept | goldens: demo-fourier, int, int-display |

| `\mathring` | accept | goldens: sym-accent-mathring |

| `\mathrm` | accept | goldens: fonts |

| `\mathscr` | accept | goldens: fonts |

| `\mathsf` | accept | goldens: fonts2 |

| `\mathsterling` | accept | goldens: sym-mathsterling |

| `\mathstrut` | accept | goldens: sqrt, demo-cfrac, demo-gauss |

| `\mathtip` | unsup | goldens: rej-unsup-mathtip |

| `\mathtt` | accept | goldens: fonts2 |

| `\matrix` | err-parity | goldens: rej-env-mismatch |

| `{matrix}` | accept | goldens: matrix, aligned, alignedat |

| `{matrix*}` | accept | goldens: matrix, aligned, alignedat |

| `\max` | accept | goldens: sym-gal-6 |

| `\mbox` | unsup | goldens: rej-unsup-mbox |

| `\md` | unsup | goldens: rej-unsup-md |

| `\mdseries` | unsup | goldens: rej-unsup-mdseries |

| `\measuredangle` | accept | goldens: sym-gal-6 |

| `\medspace` | accept | goldens: medspace |

| `\message` | accept | goldens: message-basic, message-text, rej-message-rbrace |

| `\mho` | accept | goldens: sym-gal-6 |

| `\mid` | accept | goldens: big-series, sym-escapes, sym-gal-6, flite-bayes |

| `\middle` | accept | goldens: middle, vert, demo-cauchy |

| `\min` | accept | goldens: sym-gal-6 |

| `\minuscolon` | accept | goldens: t-minuscolon |

| `\minuscoloncolon` | accept | goldens: t-minuscoloncolon |

| `\minuso` | accept | goldens: minuso, minuso-bare |

| `\mit` | unsup | goldens: rej-unsup-mit |

| `\mkern` | accept | goldens: mkern |

| `\mmlToken` | unsup | goldens: rej-unsup-mmltoken |

| `\mod` | accept | goldens: sym-gal-3 |

| `\models` | accept | goldens: sym-gal-6 |

| `\moveleft` | unsup | goldens: rej-unsup-moveleft |

| `\moveright` | unsup | goldens: rej-unsup-moveright |

| `\mp` | accept | goldens: sym-gal-6 |

| `\mskip` | accept | goldens: mskip |

| `\mspace` | unsup | goldens: rej-unsup-mspace |

| `\Mu` | accept | goldens: sym-gal-0 |

| `\mu` | accept | goldens: sym-greek2 |

| `\multicolumn` | unsup | goldens: rej-unsup-multicolumn |

| `{multiline}` | unsup | goldens: rej-unsup-multiline |

| `\multimap` | accept | goldens: sym-multimap |

## N

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\N` | accept | goldens: sym-N |

| `\nabla` | accept | goldens: sym-gal-6, flite-maxwell |

| `\natnums` | accept | goldens: sym-natnums |

| `\natural` | accept | goldens: sym-gal-6 |

| `\negmedspace` | accept | goldens: negmedspace |

| `\ncong` | accept | goldens: sym-ncong |

| `\ne` | accept | goldens: sym-gal-6 |

| `\nearrow` | accept | goldens: sym-gal-6 |

| `\neg` | accept | goldens: sym-gal-6 |

| `\negthickspace` | accept | goldens: negthickspace |

| `\negthinspace` | accept | goldens: negthinspace |

| `\neq` | accept | goldens: atom-rel, atomgrid |

| `\newcommand` | accept | goldens: newcommand, color-macro, newcommand-arg, rej-newcommand-default |

| `\newenvironment` | unsup | goldens: rej-unsup-newenvironment |

| `\Newextarrow` | unsup | goldens: rej-unsup-newextarrow |

| `\newline` | accept | goldens: newline |

| `\nexists` | accept | goldens: sym-gal-6 |

| `\ngeq` | accept | goldens: sym-ngeq |

| `\ngeqq` | accept | goldens: sym-ngeqq |

| `\ngeqslant` | accept | goldens: sym-ngeqslant |

| `\ngtr` | accept | goldens: sym-ngtr |

| `\ni` | accept | goldens: sym-gal-6 |

| `\nleftarrow` | accept | goldens: sym-nleftarrow |

| `\nLeftarrow` | accept | goldens: sym-nLeftarrow |

| `\nLeftrightarrow` | accept | goldens: sym-nLeftrightarrow |

| `\nleftrightarrow` | accept | goldens: sym-nleftrightarrow |

| `\nleq` | accept | goldens: sym-nleq |

| `\nleqq` | accept | goldens: sym-nleqq |

| `\nleqslant` | accept | goldens: sym-nleqslant |

| `\nless` | accept | goldens: sym-nless |

| `\nmid` | accept | goldens: sym-gal-6 |

| `\nobreak` | accept | goldens: arb-nobreak |

| `\nobreakspace` | accept | goldens: sym-nobreakspace |

| `\noexpand` | accept | goldens: arb-noexpand, arb-noexpand-end |

| `\nolimits` | accept | goldens: lim, nolimits, lim-display |

| `\nonumber` | accept | goldens: disp-nonumber-align, nonumber-out |

| `\normalfont` | unsup | goldens: rej-unsup-normalfont |

| `\normalsize` | accept | goldens: normalsize |

| `\not` | accept | goldens: not |

| `\notag` | accept | goldens: disp-notag-align, notag-out |

| `\notin` | accept | goldens: sym-notin |

| `\notni` | accept | goldens: sym-notni |

| `\nparallel` | accept | goldens: sym-nparallel |

| `\nprec` | accept | goldens: sym-nprec |

| `\npreceq` | accept | goldens: sym-npreceq |

| `\nRightarrow` | accept | goldens: sym-nRightarrow |

| `\nrightarrow` | accept | goldens: sym-nrightarrow |

| `\nshortmid` | accept | goldens: sym-nshortmid |

| `\nshortparallel` | accept | goldens: sym-nshortparallel |

| `\nsim` | accept | goldens: sym-nsim |

| `\nsubseteq` | accept | goldens: sym-nsubseteq |

| `\nsubseteqq` | accept | goldens: sym-nsubseteqq |

| `\nsucc` | accept | goldens: sym-nsucc |

| `\nsucceq` | accept | goldens: sym-nsucceq |

| `\nsupseteq` | accept | goldens: sym-nsupseteq |

| `\nsupseteqq` | accept | goldens: sym-nsupseteqq |

| `\ntriangleleft` | accept | goldens: sym-ntriangleleft |

| `\ntrianglelefteq` | accept | goldens: sym-ntrianglelefteq |

| `\ntriangleright` | accept | goldens: sym-ntriangleright |

| `\ntrianglerighteq` | accept | goldens: sym-ntrianglerighteq |

| `\Nu` | accept | goldens: sym-gal-0 |

| `\nu` | accept | goldens: sym-greek2 |

| `\nVDash` | accept | goldens: sym-nVDash |

| `\nVdash` | accept | goldens: sym-nVdash |

| `\nvDash` | accept | goldens: sym-nvDash |

| `\nvdash` | accept | goldens: sym-nvdash |

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

| `\oiiint` | accept | goldens: sym-oiiint |

| `\oiint` | accept | goldens: sym-oiint |

| `\oint` | accept | goldens: oint |

| `\oldstyle` | unsup | goldens: rej-unsup-oldstyle |

| `\omega` | accept | goldens: sym-greek3 |

| `\Omega` | accept | goldens: sym-Greek |

| `\Omicron` | accept | goldens: sym-Omicron |

| `\omicron` | accept | goldens: sym-omicron |

| `\ominus` | accept | goldens: sym-gal-6 |

| `\operatorname` | accept | goldens: operatorname, operatorname-star, operatorname-plain-limits |

| `\operatorname*` | accept | goldens: operatorname, limits-force, operatorname-star, operatorname-star-limits |

| `\operatornamewithlimits` | accept | goldens: limits-force, operatorname-withlimits-limits |

| `\oplus` | accept | goldens: sym-gal-6 |

| `\or` | unsup | goldens: rej-unsup-or |

| `\origof` | accept | goldens: sym-origof |

| `\oslash` | accept | goldens: sym-gal-6 |

| `\otimes` | accept | goldens: sym-gal-6 |

| `\over` | accept | goldens: over |

| `\overbrace` | accept | goldens: text, braces |

| `\overbracket` | accept | goldens: text |

| `\overgroup` | accept | goldens: overgroup |

| `\overleftarrow` | accept | goldens: arrows-over |

| `\overleftharpoon` | accept | goldens: overleftharpoon |

| `\overleftrightarrow` | accept | goldens: overleftrightarrow |

| `\overline` | accept | goldens: overline, text, prime-overline |

| `\overlinesegment` | accept | goldens: overlinesegment |

| `\overparen` | unsup | goldens: rej-unsup-overparen |

| `\Overrightarrow` | accept | goldens: Overrightarrow |

| `\overrightarrow` | accept | goldens: arrows-over |

| `\overrightharpoon` | accept | goldens: overrightharpoon |

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

| `\pitchfork` | accept | goldens: sym-pitchfork |

| `\plim` | accept | goldens: plim |

| `\plusmn` | accept | goldens: sym-plusmn |

| `\pm` | accept | goldens: sym-gal-7, flite-quad |

| `\pmatrix` | unsup | goldens: rej-unsup-pmatrix |

| `{pmatrix}` | accept | goldens: pmatrix, aligned, alignedat |

| `{pmatrix*}` | accept | goldens: pmatrix, aligned, alignedat |

| `\pmb` | accept | goldens: sym-greek2 |

| `\pmod` | accept | goldens: pmod, pmod-nested |

| `\pod` | accept | goldens: pod, pod-nested, pod-noarg |

| `\pounds` | accept | goldens: sym-gal-7 |

| `\Pr` | accept | goldens: sym-gal-0 |

| `\prec` | accept | goldens: sym-gal-7 |

| `\precapprox` | accept | goldens: sym-precapprox |

| `\preccurlyeq` | accept | goldens: sym-preccurlyeq |

| `\preceq` | accept | goldens: sym-gal-7 |

| `\precnapprox` | accept | goldens: sym-precnapprox |

| `\precneqq` | accept | goldens: sym-precneqq |

| `\precnsim` | accept | goldens: sym-precnsim |

| `\precsim` | accept | goldens: sym-precsim |

| `\prime` | accept | goldens: sym-gal-7 |

| `\prod` | accept | goldens: prod |

| `\projlim` | accept | goldens: projlim |

| `\propto` | accept | goldens: sym-gal-7 |

| `\providecommand` | accept | goldens: providecommand, text |

| `\psi` | accept | goldens: sym-greek3 |

| `\Psi` | accept | goldens: sym-Greek |

| `\pu` | unsup | goldens: rej-unsup-pu |

## QR

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\Q` | unsup | goldens: rej-unsup-q |

| `\qquad` | accept | goldens: spacing |

| `\quad` | accept | goldens: spacing |

| `\R` | accept | goldens: sym-R |

| `\r` | accept | goldens: text |

| `\raise` | unsup | goldens: rej-unsup-raise |

| `\raisebox` | accept | goldens: raisebox, raisebox-island, raisebox-dollar |

| `\rang` | accept | goldens: big-series, delim-named, sym-gal-7 |

| `\rangle` | accept | goldens: big-series, delim-named |

| `\Rarr` | accept | goldens: sym-Rarr |

| `\rArr` | accept | goldens: sym-rArr |

| `\rarr` | accept | goldens: sym-rarr |

| `\ratio` | accept | goldens: t-ratio |

| `\rBrace` | accept | goldens: lbrace, rbrace |

| `\rbrace` | accept | goldens: sym-rbrace |

| `\rbrack` | accept | goldens: sym-rbrack |

| `{rcases}` | accept | goldens: text, aligned, alignedat |

| `\rceil` | accept | goldens: delim-named |

| `\Re` | accept | goldens: sym-gal-0 |

| `\real` | accept | goldens: sym-real |

| `\Reals` | accept | goldens: sym-Reals |

| `\reals` | accept | goldens: sym-reals |

| `\ref` | unsup | goldens: rej-unsup-ref |

| `\reflectbox` | accept | goldens: reflectbox |

| `\relax` | accept | goldens: arb-relax |

| `\renewcommand` | accept | goldens: def, renewcommand, def-args |

| `\renewenvironment` | unsup | goldens: rej-unsup-renewenvironment |

| `\require` | unsup | goldens: rej-unsup-require |

| `\restriction` | accept | goldens: sym-restriction |

| `\rfloor` | accept | goldens: delim-named |

| `\rgroup` | accept | goldens: sym-rgroup |

| `\rhd` | accept | goldens: sym-gal-7 |

| `\Rho` | accept | goldens: sym-gal-0 |

| `\rho` | accept | goldens: sym-greek2 |

| `\right` | accept | goldens: dfrac, demo-cauchy, leftright, atomgrid, rej-malf-right |

| `\Rightarrow` | accept | goldens: sym-gal-0 |

| `\rightarrow` | accept | goldens: sym-gal-7 |

| `\rightarrowtail` | accept | goldens: sym-rightarrowtail |

| `\rightharpoondown` | accept | goldens: sym-gal-7 |

| `\rightharpoonup` | accept | goldens: sym-gal-7 |

| `\rightleftarrows` | accept | goldens: sym-rightleftarrows |

| `\rightleftharpoons` | accept | goldens: sym-gal-7 |

| `\rightrightarrows` | accept | goldens: sym-rightrightarrows |

| `\rightsquigarrow` | accept | goldens: sym-rightsquigarrow |

| `\rightthreetimes` | accept | goldens: sym-rightthreetimes |

| `\risingdotseq` | accept | goldens: sym-risingdotseq |

| `\rlap` | accept | goldens: lap-rlap-sub |

| `\rm` | accept | goldens: rm |

| `\rmoustache` | accept | goldens: sym-rmoustache |

| `\root` | unsup | goldens: rej-unsup-root |

| `\rotatebox` | unsup | goldens: rej-unsup-rotatebox |

| `\rparen` | accept | goldens: sym-rparen |

| `\rq` | accept | goldens: rq-x, rq-bare, lq-rq |

| `\rrbracket` | accept | goldens: sym-rrbracket |

| `\Rrightarrow` | accept | goldens: sym-Rrightarrow |

| `\Rsh` | accept | goldens: sym-Rsh |

| `\rtimes` | accept | goldens: sym-rtimes |

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

| `\scriptsize` | accept | goldens: scriptsize |

| `\scriptstyle` | accept | goldens: frac, bigl, demo-cfrac |

| `\sdot` | accept | goldens: sym-sdot |

| `\searrow` | accept | goldens: sym-gal-7 |

| `\sec` | accept | goldens: sym-gal-7 |

| `\sect` | accept | goldens: text |

| `\set` | accept | goldens: set, set-bar, set-bare-bar, set-barefrac |

| `\Set` | accept | goldens: Set-basic, Set-dbl, Set-barefrac |

| `\setlength` | unsup | goldens: rej-unsup-setlength |

| `\setminus` | accept | goldens: sym-gal-7 |

| `\sf` | accept | goldens: sf |

| `\sharp` | accept | goldens: sym-gal-7 |

| `\shortmid` | accept | goldens: sym-shortmid |

| `\shortparallel` | accept | goldens: sym-shortparallel |

| `\shoveleft` | unsup | goldens: rej-unsup-shoveleft |

| `\shoveright` | unsup | goldens: rej-unsup-shoveright |

| `\show` | accept | goldens: show-basic, show-eof, show-rbrace, show-text |

| `\sideset` | unsup | goldens: rej-unsup-sideset |

| `\Sigma` | accept | goldens: sym-Greek |

| `\sigma` | accept | goldens: sym-greek3 |

| `\sim` | accept | goldens: sym-gal-7 |

| `\simcolon` | accept | goldens: t-simcolon |

| `\simcoloncolon` | accept | goldens: t-simcoloncolon |

| `\simeq` | accept | goldens: sym-gal-7 |

| `\sin` | accept | goldens: sin |

| `\sinh` | accept | goldens: sym-gal-7 |

| `\sixptsize` | accept | goldens: sixptsize |

| `\sh` | accept | goldens: sh |

| `\skew` | unsup | goldens: rej-unsup-skew |

| `\skip` | unsup | goldens: rej-unsup-skip |

| `\sl` | unsup | goldens: rej-unsup-sl |

| `\small` | accept | goldens: small |

| `\smallfrown` | accept | goldens: sym-smallfrown |

| `\smallint` | accept | goldens: sym-smallint |

| `{smallmatrix}` | accept | goldens: smallmatrix, aligned, alignedat |

| `\smallsetminus` | accept | goldens: sym-smallsetminus |

| `\smallsmile` | accept | goldens: sym-smallsmile |

| `\smash` | accept | goldens: smash, demo-cauchy, leftright |

| `\smile` | accept | goldens: sym-gal-8 |

| `\smiley` | unsup | goldens: rej-unsup-smiley |

| `\sout` | accept | goldens: text |

| `\Space` | unsup | goldens: rej-unsup-space |

| `\space` | accept | goldens: sym-space |

| `\spades` | accept | goldens: sym-spades |

| `\spadesuit` | accept | goldens: sym-gal-8 |

| `\sphericalangle` | accept | goldens: sym-gal-8 |

| `{split}` | accept | goldens: disp-split-eq, disp-split-alone |

| `\sqcap` | accept | goldens: sym-gal-8 |

| `\sqcup` | accept | goldens: sym-gal-8 |

| `\square` | accept | goldens: sym-square |

| `\sqrt` | accept | goldens: sqrt, demo-cfrac, demo-gauss, flite-nestrad, flite-normal, rej-malf-sqrtb, prime-sqrt, prime-sqrt-rq, prime-sqrt-opt |

| `\sqsubset` | accept | goldens: sym-gal-8 |

| `\sqsubseteq` | accept | goldens: sym-gal-8 |

| `\sqsupset` | accept | goldens: sym-gal-8 |

| `\sqsupseteq` | accept | goldens: sym-gal-8 |

| `\ss` | accept | goldens: text |

| `\stackrel` | accept | goldens: stackrel, stackrel-rel |

| `\star` | accept | goldens: sym-gal-8 |

| `\Stigma` | unsup | goldens: rej-unsup-stigma |

| `\stigma` | unsup | goldens: rej-unsup-stigma-2 |

| `\strut` | unsup | goldens: rej-unsup-strut |

| `\style` | unsup | goldens: rej-unsup-style |

| `\sub` | accept | goldens: sym-sub |

| `{subarray}` | accept | goldens: subarray-c, subarray-l |

| `\sube` | accept | goldens: sym-sube |

| `\Subset` | accept | goldens: sym-Subset |

| `\subset` | accept | goldens: sym-gal-8 |

| `\subseteq` | accept | goldens: sym-gal-8 |

| `\subseteqq` | accept | goldens: sym-subseteqq |

| `\subsetneq` | accept | goldens: sym-gal-8 |

| `\subsetneqq` | accept | goldens: sym-subsetneqq |

| `\substack` | accept | goldens: substack, sum, demo-cauchy |

| `\succ` | accept | goldens: sym-gal-8 |

| `\succapprox` | accept | goldens: sym-succapprox |

| `\succcurlyeq` | accept | goldens: sym-succcurlyeq |

| `\succeq` | accept | goldens: sym-gal-8 |

| `\succnapprox` | accept | goldens: sym-succnapprox |

| `\succneqq` | accept | goldens: sym-succneqq |

| `\succnsim` | accept | goldens: sym-succnsim |

| `\succsim` | accept | goldens: sym-succsim |

| `\sum` | accept | goldens: sum, demo-cauchy, demo-sumsq, atomgrid, flite-series, sum-limits-both-text |

| `\sup` | accept | goldens: sym-gal-8 |

| `\supe` | accept | goldens: sym-supe |

| `\Supset` | accept | goldens: sym-Supset |

| `\supset` | accept | goldens: sym-gal-8 |

| `\supseteq` | accept | goldens: sym-gal-8 |

| `\supseteqq` | accept | goldens: sym-supseteqq |

| `\supsetneq` | accept | goldens: sym-gal-8 |

| `\supsetneqq` | accept | goldens: sym-supsetneqq |

| `\surd` | accept | goldens: sym-gal-8 |

| `\swarrow` | accept | goldens: sym-gal-8 |

## T

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\tag` | accept | goldens: tag, tag-display, tag-in-text, tag-text-body, tag-text-mid, tag-text-bare, tag-text-nested, tag-nonumber-same-row, tag-row0-nonumber-row1, disp-tag-leading-align, disp-tag-trailing-align-star, disp-matrix-tag, disp-split-tag |

| `\tag*` | accept | goldens: tag-star, tag-star-display |

| `\tan` | accept | goldens: sym-gal-8 |

| `\tanh` | accept | goldens: sym-gal-8 |

| `\Tau` | accept | goldens: sym-gal-0 |

| `\tau` | accept | goldens: sym-greek3 |

| `\tbinom` | accept | goldens: tbinom |

| `\TeX` | accept | goldens: t-TeX |

| `\text` | accept | goldens: text, sym-escapes, text-math, text-nest, text-merge, text-nested-math, text-paren, text-paren-multi, text-paren-nested-text |

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

| `\textmd` | accept | goldens: textmd |

| `\textnormal` | accept | goldens: textnormal |

| `\textquotedblleft` | accept | goldens: text |

| `\textquotedblright` | accept | goldens: text |

| `\textquoteleft` | accept | goldens: text |

| `\textquoteright` | accept | goldens: text |

| `\textregistered` | accept | goldens: text, sym-gal-8 |

| `\textrm` | accept | goldens: textrm |

| `\textsc` | unsup | goldens: rej-unsup-textsc |

| `\textsf` | accept | goldens: textsf |

| `\textsl` | err-parity | goldens: textsl |

| `\textsterling` | accept | goldens: text |

| `\textstyle` | accept | goldens: sum, demo-cauchy, demo-sumsq |

| `\texttip` | unsup | goldens: rej-unsup-texttip |

| `\texttt` | accept | goldens: texttt |

| `\textunderscore` | accept | goldens: text |

| `\textup` | accept | goldens: textup |

| `\textvisiblespace` | unsup | goldens: rej-unsup-textvisiblespace |

| `\tfrac` | accept | goldens: tfrac |

| `\tg` | accept | goldens: tg |

| `\th` | accept | goldens: th |

| `\therefore` | accept | goldens: sym-therefore |

| `\Theta` | accept | goldens: sym-Greek |

| `\theta` | accept | goldens: sym-greek |

| `\thetasym` | accept | goldens: sym-thetasym |

| `\thickapprox` | accept | goldens: sym-thickapprox |

| `\thicksim` | accept | goldens: sym-thicksim |

| `\thickspace` | accept | goldens: thickspace |

| `\thinspace` | accept | goldens: thinspace |

| `\tilde` | accept | goldens: accents |

| `\times` | accept | goldens: sym-gal-8, flite-maxwell |

| `\Tiny` | unsup | goldens: rej-unsup-tiny |

| `\tiny` | accept | goldens: tiny |

| `\to` | accept | goldens: lim, lim-display |

| `\toggle` | unsup | goldens: rej-unsup-toggle |

| `\top` | accept | goldens: sym-gal-9 |

| `\triangle` | accept | goldens: sym-triangle |

| `\triangledown` | accept | goldens: sym-triangledown |

| `\triangleleft` | accept | goldens: sym-gal-9 |

| `\trianglelefteq` | accept | goldens: sym-trianglelefteq |

| `\triangleq` | accept | goldens: sym-triangleq |

| `\triangleright` | accept | goldens: sym-gal-9 |

| `\trianglerighteq` | accept | goldens: sym-trianglerighteq |

| `\tt` | accept | goldens: tt |

| `\twoheadleftarrow` | accept | goldens: sym-twoheadleftarrow |

| `\twoheadrightarrow` | accept | goldens: sym-twoheadrightarrow |

## U

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\u` | accept | goldens: text |

| `\Uarr` | accept | goldens: sym-Uarr |

| `\uArr` | accept | goldens: sym-uArr |

| `\uarr` | accept | goldens: sym-uarr |

| `\ulcorner` | accept | goldens: sym-gal-9 |

| `\underbar` | accept | goldens: underbar |

| `\underbrace` | accept | goldens: text, braces |

| `\underbracket` | accept | goldens: text |

| `\undergroup` | accept | goldens: undergroup |

| `\underleftarrow` | accept | goldens: underleftarrow |

| `\underleftrightarrow` | accept | goldens: underleftrightarrow |

| `\underrightarrow` | accept | goldens: underrightarrow |

| `\underline` | accept | goldens: text, underline |

| `\underlinesegment` | accept | goldens: underlinesegment |

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

| `\upharpoonleft` | accept | goldens: sym-upharpoonleft |

| `\upharpoonright` | accept | goldens: sym-upharpoonright |

| `\uplus` | accept | goldens: sym-gal-9 |

| `\uproot` | unsup | goldens: rej-unsup-uproot |

| `\upshape` | unsup | goldens: rej-unsup-upshape |

| `\Upsilon` | accept | goldens: sym-gal-1 |

| `\upsilon` | accept | goldens: sym-greek3 |

| `\upuparrows` | accept | goldens: sym-upuparrows |

| `\urcorner` | accept | goldens: sym-gal-9 |

| `\url` | accept | goldens: url |

| `\utilde` | accept | goldens: utilde |

## V

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\v` | accept | goldens: text |

| `\varcoppa` | unsup | goldens: rej-unsup-varcoppa |

| `\varDelta` | accept | goldens: sym-varDelta |

| `\varepsilon` | accept | goldens: sym-greek |

| `\varGamma` | accept | goldens: sym-varGamma |

| `\varinjlim` | accept | goldens: varinjlim |

| `\varkappa` | accept | goldens: sym-varkappa |

| `\varLambda` | accept | goldens: sym-varLambda |

| `\varliminf` | accept | goldens: varliminf |

| `\varlimsup` | accept | goldens: varlimsup |

| `\varnothing` | accept | goldens: sym-gal-9 |

| `\varOmega` | accept | goldens: sym-varOmega |

| `\varPhi` | accept | goldens: sym-varPhi |

| `\varphi` | accept | goldens: sym-greek3 |

| `\varPi` | accept | goldens: sym-varPi |

| `\varpi` | accept | goldens: sym-greek2 |

| `\varprojlim` | accept | goldens: varprojlim |

| `\varpropto` | accept | goldens: sym-varpropto |

| `\varPsi` | accept | goldens: sym-varPsi |

| `\varrho` | accept | goldens: sym-greek2 |

| `\varSigma` | accept | goldens: sym-varSigma |

| `\varsigma` | accept | goldens: sym-greek3 |

| `\varstigma` | unsup | goldens: rej-unsup-varstigma |

| `\varsubsetneq` | accept | goldens: sym-varsubsetneq |

| `\varsubsetneqq` | accept | goldens: sym-varsubsetneqq |

| `\varsupsetneq` | accept | goldens: sym-varsupsetneq |

| `\varsupsetneqq` | accept | goldens: sym-varsupsetneqq |

| `\varTheta` | accept | goldens: sym-varTheta |

| `\vartheta` | accept | goldens: sym-greek |

| `\vartriangle` | accept | goldens: sym-vartriangle |

| `\vartriangleleft` | accept | goldens: sym-vartriangleleft |

| `\vartriangleright` | accept | goldens: sym-vartriangleright |

| `\varUpsilon` | accept | goldens: sym-varUpsilon |

| `\varXi` | accept | goldens: sym-varXi |

| `\vcentcolon` | accept | goldens: t-vcentcolon |

| `\vcenter` | accept | goldens: frac, bigl, demo-cauchy |

| `\Vdash` | accept | goldens: sym-Vdash |

| `\vDash` | accept | goldens: sym-vDash |

| `\vdash` | accept | goldens: sym-gal-9 |

| `\vdots` | accept | goldens: sym-gal-9 |

| `\vec` | accept | goldens: vec-dot |

| `\vee` | accept | goldens: sym-gal-9 |

| `\veebar` | accept | goldens: sym-veebar |

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

| `\Vvdash` | accept | goldens: sym-Vvdash |

## W

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\wedge` | accept | goldens: sym-gal-9 |

| `\weierp` | accept | goldens: sym-weierp |

| `\widecheck` | accept | goldens: sym-accent-widecheck |

| `\widehat` | accept | goldens: widehat |

| `\wideparen` | unsup | goldens: rej-unsup-wideparen |

| `\widetilde` | accept | goldens: sym-accent-widetilde |

| `\wp` | accept | goldens: sym-gal-9 |

| `\wr` | accept | goldens: sym-gal-9 |

## X

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\xcancel` | accept | goldens: xcancel |

| `\xdef` | accept | goldens: def, def-args |

| `\Xi` | accept | goldens: sym-Greek |

| `\xi` | accept | goldens: demo-fourier, hat, sym-greek2 |

| `\xhookleftarrow` | accept | goldens: xhookleftarrow |

| `\xhookrightarrow` | accept | goldens: xhookrightarrow |

| `\xLeftarrow` | accept | goldens: xLeftarrow |

| `\xleftarrow` | accept | goldens: xarrow |

| `\xleftharpoondown` | accept | goldens: xleftharpoondown |

| `\xleftharpoonup` | accept | goldens: xleftharpoonup |

| `\xLeftrightarrow` | accept | goldens: xLeftrightarrow |

| `\xleftrightarrow` | accept | goldens: xleftrightarrow |

| `\xleftrightharpoons` | accept | goldens: xleftrightharpoons |

| `\xlongequal` | accept | goldens: xlongequal |

| `\xmapsto` | accept | goldens: xmapsto |

| `\xRightarrow` | accept | goldens: xRightarrow |

| `\xrightarrow` | accept | goldens: xarrow |

| `\xrightharpoondown` | accept | goldens: xrightharpoondown |

| `\xrightharpoonup` | accept | goldens: xrightharpoonup |

| `\xrightleftharpoons` | accept | goldens: xrightleftharpoons |

| `\xtofrom` | accept | goldens: xtofrom |

| `\xtwoheadleftarrow` | accept | goldens: xtwoheadleftarrow |

| `\xtwoheadrightarrow` | accept | goldens: xtwoheadrightarrow |

## YZ

| Function | Status | Evidence / owner |
| --- | --- | --- |
| `\yen` | accept | goldens: sym-gal-9 |

| `\Z` | accept | goldens: sym-Z |

| `\Zeta` | accept | goldens: sym-gal-1 |

| `\zeta` | accept | goldens: sym-greek |

---
Totals: 1007 accept, 6 err-parity, 123 unsup, 0 TODO.
