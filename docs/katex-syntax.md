# KaTeX syntax mirror (generated — do not edit)

A render of every accepted function, generated from `docs/support-table.md` by `tools/gen_doc_renders.py` (renders via `zatex-png` into `docs/renders/`; expected render gaps live in `tools/doc_gaps.json`). Status, evidence, and ownership live in the support table — edit that, never this file. Examples use KaTeX's own equations (Source column of the vendored pinned table, else its Rendered column); rows whose KaTeX example this engine cannot render yet are gap-listed with KaTeX's equation.

## Symbols

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `!` | `n!` | ![](renders/bang.png) |  |
| `\!` | `a\!b` | ![](renders/bang-2.png) |  |
| `#` | `\def\sqr#1{#1^2} \sqr{y}` | ![](renders/hash.png) |  |
| `\#` | `\#` | ![](renders/hash-2.png) |  |
| `%` | `a% note\nb` | ![](renders/pct.png) |  |
| `\%` | `\%` | ![](renders/pct-2.png) |  |
| `&` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/amp.png) |  |
| `\&` | `\&` | ![](renders/amp-2.png) |  |
| `'` | `'` | ![](renders/prime.png) |  |
| `\'` | `\text{\'{a}}` | ![](renders/prime-2.png) |  |
| `(` | `(` | ![](renders/lp.png) |  |
| `)` | `)` | ![](renders/rp.png) |  |
| `\(…\)` | `\text{\(\frac a b\)}` | ![](renders/lpdotsrp.png) | Delimiters for math islands inside `\text`; top-level `\(x\)` rejects like pinned KaTeX |
| `\ ` | `a\ b` | ![](renders/ctrlspace.png) |  |
| `\"` | `\text{\"{a}}` | ![](renders/quot.png) |  |
| `\$` | `\$` | ![](renders/dollar.png) | KaTeX shows `\text{\textdollar}`; this form exercises `\$` |
| `\,` | `a\,\,{b}` | ![](renders/comma.png) |  |
| `\.` | `\text{\.{a}}` | ![](renders/dot.png) |  |
| `\:` | `a\:\:{b}` | ![](renders/colon.png) |  |
| `\;` | `a\n\;\;{b}` | ![](renders/semi.png) |  |
| `_` | `x_i` | ![](renders/us.png) |  |
| `\_` | `\_` | ![](renders/us-2.png) |  |
| `` \` `` | ``\text{\`{a}}`` | ![](renders/fn.png) |  |
| `<` | `<` | ![](renders/lt.png) |  |
| `\=` | `\text{\={a}}` | ![](renders/eq.png) |  |
| `>` | `>` | ![](renders/gt.png) |  |
| `\>` | `a\>\>{b}` | ![](renders/gt-2.png) |  |
| `[` | `[` | ![](renders/fn-2.png) |  |
| `]` | `]` | ![](renders/fn-3.png) |  |
| `{` | `{a}` | ![](renders/fn-4.png) |  |
| `}` | `{a}` | ![](renders/fn-5.png) |  |
| `\{` | `\{` | ![](renders/fn-6.png) |  |
| `\}` | `\}` | ![](renders/fn-7.png) |  |
| `&#124;` | `\vert` | ![](renders/pipe.png) |  |
| `\&#124;` | `\&#124;x\&#124;` | ![](renders/pipe-2.png) | KaTeX shows `\Vert`; this form exercises `\&#124;` |
| `~` | `\text{no~no~no~breaks}` | ![](renders/tilde.png) |  |
| `\~` | `\text{\~{a}}` | ![](renders/tilde-2.png) |  |
| `\\ ` | `\begin{matrix}a\\b\end{matrix}` | ![](renders/dblbackslash.png) |  |
| `^` | `x^i` | ![](renders/pow.png) |  |
| `\^` | `\text{\^{a}}` | ![](renders/pow-2.png) |  |

## A

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\AA` | `\text{\AA}` | ![](renders/aa.png) |  |
| `\aa` | `\text{\aa}` | ![](renders/aa-2.png) |  |
| `\above` | `{a \above{2pt} b+1}` | ![](renders/above.png) |  |
| `\abovewithdelims` | — | — | goldens: rej-unsup-abovewithdelims |
| `\acute` | `\acute e` | ![](renders/acute.png) |  |
| `\AE` | `\text{\AE}` | ![](renders/ae.png) |  |
| `\ae` | `\text{\ae}` | ![](renders/ae-2.png) |  |
| `\alef` | `\alef` | ![](renders/alef.png) |  |
| `\alefsym` | `\alefsym` | ![](renders/alefsym.png) |  |
| `\aleph` | `\aleph` | ![](renders/aleph.png) |  |
| `{align}` | `\begin{align}\na&=b+c \\\nd+e&=f\n\end{align}` | ![](renders/align.png) |  |
| `{align*}` | `\begin{align*}\na&=b+c \\\nd+e&=f\n\end{align*}` | ![](renders/alignstar.png) |  |
| `{aligned}` | `\begin{aligned}\na&=b+c \\\nd+e&=f\n\end{aligned}` | ![](renders/aligned.png) |  |
| `{alignat}` | `\begin{alignat}{2}\n10&x+ &3&y = 2 \\\n 3&x+&13&y = 4\n\end{alignat}` | ![](renders/alignat.png) |  |
| `{alignat*}` | `\begin{alignat*}{2}\n10&x+ &3&y = 2 \\\n 3&x+&13&y = 4\n\end{alignat*}` | ![](renders/alignatstar.png) |  |
| `{alignedat}` | `\begin{alignedat}{2}\n10&x+ &3&y = 2 \\\n 3&x+&13&y = 4\n\end{alignedat}` | ![](renders/alignedat.png) |  |
| `\allowbreak` | `x \allowbreak y` | ![](renders/allowbreak.png) |  |
| `\Alpha` | `\Alpha` | ![](renders/alpha.png) |  |
| `\alpha` | `\alpha` | ![](renders/alpha-2.png) |  |
| `\amalg` | `\amalg` | ![](renders/amalg.png) |  |
| `\And` | `\And` | ![](renders/and.png) |  |
| `\and` | — | — | goldens: rej-unsup-and |
| `\ang` | — | — | goldens: rej-unsup-ang |
| `\angl` | `a_{\angl n}` | ![](renders/angl.png) |  |
| `\angln` | `a_\angln` | ![](renders/angln.png) |  |
| `\angle` | `\angle` | ![](renders/angle.png) |  |
| `\approx` | `\approx` | ![](renders/approx.png) |  |
| `\approxeq` | `\approxeq` | ![](renders/approxeq.png) |  |
| `\approxcolon` | `\approxcolon` | ![](renders/approxcolon.png) |  |
| `\approxcoloncolon` | `\approxcoloncolon` | ![](renders/approxcoloncolon.png) |  |
| `\arccos` | `\arccos` | ![](renders/arccos.png) |  |
| `\arcctg` | `\arcctg` | ![](renders/arcctg.png) |  |
| `\arcsin` | `\arcsin` | ![](renders/arcsin.png) |  |
| `\arctan` | `\arctan` | ![](renders/arctan.png) |  |
| `\arctg` | `\arctg` | ![](renders/arctg.png) |  |
| `\arg` | `\arg` | ![](renders/arg.png) |  |
| `\argmax` | `\argmax` | ![](renders/argmax.png) |  |
| `\argmin` | `\argmin` | ![](renders/argmin.png) |  |
| `{array}` | `\begin{array}{cc}\na & b \\\nc & d\n\end{array}` | ![](renders/array.png) |  |
| `\array` | — | — | goldens: rej-unsup-array |
| `\arraystretch` | `\def\arraystretch{1.5}\n\begin{array}{cc}\na & b \\\nc & d\n\end{array}` | ![](renders/arraystretch.png) |  |
| `\Arrowvert` | — | — | goldens: rej-unsup-arrowvert |
| `\arrowvert` | — | — | goldens: rej-unsup-arrowvert-2 |
| `\ast` | `\ast` | ![](renders/ast.png) |  |
| `\asymp` | `\asymp` | ![](renders/asymp.png) |  |
| `\atop` | `{a \atop b}` | ![](renders/atop.png) |  |
| `\atopwithdelims` | — | — | goldens: rej-unsup-atopwithdelims |

## B

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\backepsilon` | `\backepsilon` | ![](renders/backepsilon.png) |  |
| `\backprime` | `\backprime` | ![](renders/backprime.png) |  |
| `\backsim` | `\backsim` | ![](renders/backsim.png) |  |
| `\backsimeq` | `\backsimeq` | ![](renders/backsimeq.png) |  |
| `\backslash` | `\backslash` | ![](renders/backslash.png) |  |
| `\bar` | `\bar{y}` | ![](renders/bar.png) |  |
| `\barwedge` | `\barwedge` | ![](renders/barwedge.png) |  |
| `\Bbb` | `\Bbb{ABC}` | ![](renders/bbb.png) |  |
| `\Bbbk` | `\Bbbk` | ![](renders/bbbk.png) |  |
| `\bbox` | — | — | goldens: rej-unsup-bbox |
| `\bcancel` | `\bcancel{5}` | ![](renders/bcancel.png) |  |
| `\because` | `\because` | ![](renders/because.png) |  |
| `\begin` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/begin.png) |  |
| `\begingroup` | `\begingroup x\endgroup` | ![](renders/begingroup.png) |  |
| `\Beta` | `\Beta` | ![](renders/beta.png) |  |
| `\beta` | `\beta` | ![](renders/beta-2.png) |  |
| `\beth` | `\beth` | ![](renders/beth.png) |  |
| `\between` | `\between` | ![](renders/between.png) |  |
| `\bf` | `\bf AaBb12` | ![](renders/bf.png) |  |
| `\bfseries` | — | — | goldens: rej-unsup-bfseries |
| `\bgroup` | `\bgroup x}` | ![](renders/bgroup.png) |  |
| `\big` | `\big(\big)` | ![](renders/big.png) |  |
| `\Big` | `\Big(\Big)` | ![](renders/big-2.png) |  |
| `\bigcap` | `\bigcap` | ![](renders/bigcap.png) |  |
| `\bigcirc` | `\bigcirc` | ![](renders/bigcirc.png) |  |
| `\bigcup` | `\bigcup` | ![](renders/bigcup.png) |  |
| `\bigg` | `\bigg(\bigg)` | ![](renders/bigg.png) |  |
| `\Bigg` | `\Bigg(\Bigg)` | ![](renders/bigg-2.png) |  |
| `\biggl` | `\biggl(` | ![](renders/biggl.png) |  |
| `\Biggl` | `\Biggl(` | ![](renders/biggl-2.png) |  |
| `\biggm` | `\biggm\vert` | ![](renders/biggm.png) |  |
| `\Biggm` | `\Biggm\vert` | ![](renders/biggm-2.png) |  |
| `\biggr` | `\biggr)` | ![](renders/biggr.png) |  |
| `\Biggr` | `\Biggr)` | ![](renders/biggr-2.png) |  |
| `\bigl` | `\bigl(` | ![](renders/bigl.png) |  |
| `\Bigl` | `\Bigl(` | ![](renders/bigl-2.png) |  |
| `\bigm` | `\bigm\vert` | ![](renders/bigm.png) |  |
| `\Bigm` | `\Bigm\vert` | ![](renders/bigm-2.png) |  |
| `\bigodot` | `\bigodot` | ![](renders/bigodot.png) |  |
| `\bigominus` | — | — | goldens: rej-unsup-bigominus |
| `\bigoplus` | `\bigoplus` | ![](renders/bigoplus.png) |  |
| `\bigoslash` | — | — | goldens: rej-unsup-bigoslash |
| `\bigotimes` | `\bigotimes` | ![](renders/bigotimes.png) |  |
| `\bigr` | `\bigr)` | ![](renders/bigr.png) |  |
| `\Bigr` | `\Bigr)` | ![](renders/bigr-2.png) |  |
| `\bigsqcap` | — | — | goldens: rej-unsup-bigsqcap |
| `\bigsqcup` | `\bigsqcup` | ![](renders/bigsqcup.png) |  |
| `\bigstar` | `\bigstar` | ![](renders/bigstar.png) |  |
| `\bigtriangledown` | `\bigtriangledown` | ![](renders/bigtriangledown.png) |  |
| `\bigtriangleup` | `\bigtriangleup` | ![](renders/bigtriangleup.png) |  |
| `\biguplus` | `\biguplus` | ![](renders/biguplus.png) |  |
| `\bigvee` | `\bigvee` | ![](renders/bigvee.png) |  |
| `\bigwedge` | `\bigwedge` | ![](renders/bigwedge.png) |  |
| `\binom` | `\binom n k` | ![](renders/binom.png) |  |
| `\blacklozenge` | `\blacklozenge` | ![](renders/blacklozenge.png) |  |
| `\blacksquare` | `\blacksquare` | ![](renders/blacksquare.png) |  |
| `\blacktriangle` | `\blacktriangle` | ![](renders/blacktriangle.png) |  |
| `\blacktriangledown` | `\blacktriangledown` | ![](renders/blacktriangledown.png) |  |
| `\blacktriangleleft` | `\blacktriangleleft` | ![](renders/blacktriangleleft.png) |  |
| `\blacktriangleright` | `\blacktriangleright` | ![](renders/blacktriangleright.png) |  |
| `\bm` | `\bm{AaBb}` | ![](renders/bm.png) |  |
| `{Bmatrix}` | `\begin{Bmatrix}\na & b \\\nc & d\n\end{Bmatrix}` | ![](renders/bmatrix.png) |  |
| `{Bmatrix*}` | `\begin{Bmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{Bmatrix*}` | ![](renders/bmatrixstar.png) |  |
| `{bmatrix}` | `\begin{bmatrix}\na & b \\\nc & d\n\end{bmatrix}` | ![](renders/bmatrix-2.png) |  |
| `{bmatrix*}` | `\begin{bmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{bmatrix*}` | ![](renders/bmatrixstar-2.png) |  |
| `\bmod` | `a \bmod b` | ![](renders/bmod.png) |  |
| `\bold` | `\bold{AaBb123}` | ![](renders/bold.png) |  |
| `\boldsymbol` | `\boldsymbol{AaBb}` | ![](renders/boldsymbol.png) |  |
| `\bot` | `\bot` | ![](renders/bot.png) |  |
| `\bowtie` | `\bowtie` | ![](renders/bowtie.png) |  |
| `\Box` | `\Box` | ![](renders/box.png) |  |
| `\boxdot` | `\boxdot` | ![](renders/boxdot.png) |  |
| `\boxed` | `\boxed{ab}` | ![](renders/boxed.png) |  |
| `\boxminus` | `\boxminus` | ![](renders/boxminus.png) |  |
| `\boxplus` | `\boxplus` | ![](renders/boxplus.png) |  |
| `\boxtimes` | `\boxtimes` | ![](renders/boxtimes.png) |  |
| `\Bra` | `\Bra{\psi}` | ![](renders/bra.png) |  |
| `\bra` | `\bra{\psi}` | ![](renders/bra-2.png) |  |
| `\braket` | `\braket{\phi&#124;\psi}` | ![](renders/braket.png) |  |
| `\Braket` | `\Braket{\phi&#124;\frac12&#124;\psi}` | ![](renders/braket-2.png) |  |
| `\brace` | `{n\brace k}` | ![](renders/brace.png) |  |
| `\bracevert` | — | — | goldens: rej-unsup-bracevert |
| `\brack` | `{n\brack k}` | ![](renders/brack.png) |  |
| `\breve` | `\breve{eu}` | ![](renders/breve.png) |  |
| `\buildrel` | — | — | goldens: rej-unsup-buildrel |
| `\bull` | `\bull` | ![](renders/bull.png) |  |
| `\bullet` | `\bullet` | ![](renders/bullet.png) |  |
| `\Bumpeq` | `\Bumpeq` | ![](renders/bumpeq.png) |  |
| `\bumpeq` | `\bumpeq` | ![](renders/bumpeq-2.png) |  |

## C

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\C` | — | — | goldens: rej-unsup-c |
| `\cal` | `\cal AaBb123` | ![](renders/cal.png) |  |
| `\cancel` | `\cancel{5}` | ![](renders/cancel.png) |  |
| `\cancelto` | — | — | goldens: rej-unsup-cancelto |
| `\Cap` | `\Cap` | ![](renders/cap.png) |  |
| `\cap` | `\cap` | ![](renders/cap-2.png) |  |
| `{cases}` | `\begin{cases}\na &\text{if } b  \\\nc &\text{if } d\n\end{cases}` | ![](renders/cases.png) |  |
| `\cases` | — | — | goldens: rej-unsup-cases |
| `{CD}` | `\begin{CD}\nA  @>a>>  B  \\\n@VbVV    @AAcA \\\nC  @=     D\n\end{CD}` | ![](renders/cd.png) |  |
| `\cdot` | `\cdot` | ![](renders/cdot.png) |  |
| `\cdotp` | `\cdotp` | ![](renders/cdotp.png) |  |
| `\cdots` | `\cdots` | ![](renders/cdots.png) |  |
| `\ce` | — | — | goldens: rej-unsup-ce |
| `\cee` | — | — | goldens: rej-unsup-cee |
| `\centerdot` | `a\centerdot b` | ![](renders/centerdot.png) |  |
| `\cf` | — | — | goldens: rej-unsup-cf |
| `\cfrac` | `\cfrac{2}{1+\cfrac{2}{1+\cfrac{2}{1}}}` | ![](renders/cfrac.png) |  |
| `\char` | `\char"263a` | ![](renders/char.png) |  |
| `\check` | `\check{oe}` | ![](renders/check.png) |  |
| `\ch` | `\ch` | ![](renders/ch.png) |  |
| `\checkmark` | `\checkmark` | ![](renders/checkmark.png) |  |
| `\Chi` | `\Chi` | ![](renders/chi.png) |  |
| `\chi` | `\chi` | ![](renders/chi-2.png) |  |
| `\choose` | `{n+1 \choose k+2}` | ![](renders/choose.png) |  |
| `\circ` | `\circ` | ![](renders/circ.png) |  |
| `\circeq` | `\circeq` | ![](renders/circeq.png) |  |
| `\circlearrowleft` | `\circlearrowleft` | ![](renders/circlearrowleft.png) |  |
| `\circlearrowright` | `\circlearrowright` | ![](renders/circlearrowright.png) |  |
| `\circledast` | `\circledast` | ![](renders/circledast.png) |  |
| `\circledcirc` | `\circledcirc` | ![](renders/circledcirc.png) |  |
| `\circleddash` | `\circleddash` | ![](renders/circleddash.png) |  |
| `\circledR` | `\circledR` | ![](renders/circledr.png) |  |
| `\circledS` | `\circledS` | ![](renders/circleds.png) |  |
| `\clap` | `\clap{x}y` | ![](renders/clap.png) |  |
| `\class` | — | — | goldens: rej-unsup-class |
| `\cline` | — | — | goldens: rej-unsup-cline |
| `\clubs` | `\clubs` | ![](renders/clubs.png) |  |
| `\clubsuit` | `\clubsuit` | ![](renders/clubsuit.png) |  |
| `\cnums` | `\cnums` | ![](renders/cnums.png) |  |
| `\colon` | `\colon` | ![](renders/colon-2.png) |  |
| `\Colonapprox` | `\Colonapprox` | ![](renders/colonapprox.png) |  |
| `\colonapprox` | `\colonapprox` | ![](renders/colonapprox-2.png) |  |
| `\coloncolon` | `\coloncolon` | ![](renders/coloncolon.png) |  |
| `\coloncolonapprox` | `\coloncolonapprox` | ![](renders/coloncolonapprox.png) |  |
| `\coloncolonequals` | `\coloncolonequals` | ![](renders/coloncolonequals.png) |  |
| `\coloncolonminus` | `\coloncolonminus` | ![](renders/coloncolonminus.png) |  |
| `\coloncolonsim` | `\coloncolonsim` | ![](renders/coloncolonsim.png) |  |
| `\Coloneq` | `\Coloneq` | ![](renders/coloneq.png) |  |
| `\coloneq` | `\coloneq` | ![](renders/coloneq-2.png) |  |
| `\colonequals` | `\colonequals` | ![](renders/colonequals.png) |  |
| `\Coloneqq` | `\Coloneqq` | ![](renders/coloneqq.png) |  |
| `\coloneqq` | `\coloneqq` | ![](renders/coloneqq-2.png) |  |
| `\colonminus` | `\colonminus` | ![](renders/colonminus.png) |  |
| `\Colonsim` | `\Colonsim` | ![](renders/colonsim.png) |  |
| `\colonsim` | `\colonsim` | ![](renders/colonsim-2.png) |  |
| `\color` | `\color{#0000FF} AaBb123` | ![](renders/color.png) |  |
| `\colorbox` | `\colorbox{red}{Black on red}` | ![](renders/colorbox.png) |  |
| `\complement` | `\complement` | ![](renders/complement.png) |  |
| `\Complex` | `\Complex` | ![](renders/complex.png) |  |
| `\cong` | `\cong` | ![](renders/cong.png) |  |
| `\Coppa` | — | — | goldens: rej-unsup-coppa |
| `\coppa` | — | — | goldens: rej-unsup-coppa-2 |
| `\coprod` | `\coprod` | ![](renders/coprod.png) |  |
| `\copyright` | `\copyright` | ![](renders/copyright.png) |  |
| `\cos` | `\cos` | ![](renders/cos.png) |  |
| `\cosec` | `\cosec` | ![](renders/cosec.png) |  |
| `\cosh` | `\cosh` | ![](renders/cosh.png) |  |
| `\cot` | `\cot` | ![](renders/cot.png) |  |
| `\cotg` | `\cotg` | ![](renders/cotg.png) |  |
| `\coth` | `\coth` | ![](renders/coth.png) |  |
| `\cr` | `\begin{matrix}\na & b \cr\nc & d\n\end{matrix}` | ![](renders/cr.png) |  |
| `\csc` | `\csc` | ![](renders/csc.png) |  |
| `\cssId` | — | — | goldens: rej-unsup-cssid |
| `\ctg` | `\ctg` | ![](renders/ctg.png) |  |
| `\cth` | `\cth` | ![](renders/cth.png) |  |
| `\Cup` | `\Cup` | ![](renders/cup.png) |  |
| `\cup` | `\cup` | ![](renders/cup-2.png) |  |
| `\curlyeqprec` | `\curlyeqprec` | ![](renders/curlyeqprec.png) |  |
| `\curlyeqsucc` | `\curlyeqsucc` | ![](renders/curlyeqsucc.png) |  |
| `\curlyvee` | `\curlyvee` | ![](renders/curlyvee.png) |  |
| `\curlywedge` | `\curlywedge` | ![](renders/curlywedge.png) |  |
| `\curvearrowleft` | `\curvearrowleft` | ![](renders/curvearrowleft.png) |  |
| `\curvearrowright` | `\curvearrowright` | ![](renders/curvearrowright.png) |  |

## D

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\dag` | `\dag` | ![](renders/dag.png) |  |
| `\Dagger` | `\Dagger` | ![](renders/dagger.png) |  |
| `\dagger` | `\dagger` | ![](renders/dagger-2.png) |  |
| `\daleth` | `\daleth` | ![](renders/daleth.png) |  |
| `\Darr` | `\Darr` | ![](renders/darr.png) |  |
| `\dArr` | `\dArr` | ![](renders/darr-2.png) |  |
| `\darr` | `\darr` | ![](renders/darr-3.png) |  |
| `\dashleftarrow` | `\dashleftarrow` | ![](renders/dashleftarrow.png) |  |
| `\dashrightarrow` | `\dashrightarrow` | ![](renders/dashrightarrow.png) |  |
| `\dashv` | `\dashv` | ![](renders/dashv.png) |  |
| `\dbinom` | `\dbinom n k` | ![](renders/dbinom.png) |  |
| `\dblcolon` | `\dblcolon` | ![](renders/dblcolon.png) |  |
| `{dcases}` | `\begin{dcases}\na &\text{if } b  \\\nc &\text{if } d\n\end{dcases}` | ![](renders/dcases.png) |  |
| `\ddag` | `\ddag` | ![](renders/ddag.png) |  |
| `\ddagger` | `\ddagger` | ![](renders/ddagger.png) |  |
| `\ddddot` | `\ddddot x` | ![](renders/ddddot.png) |  |
| `\dddot` | `\dddot x` | ![](renders/dddot.png) |  |
| `\ddot` | `\ddot x` | ![](renders/ddot.png) |  |
| `\ddots` | `\ddots` | ![](renders/ddots.png) |  |
| `\DeclareMathOperator` | — | — | goldens: rej-declare-op |
| `\def` | `\def\foo{x^2} \foo + \foo` | ![](renders/def.png) |  |
| `\definecolor` | — | — | goldens: definecolor |
| `\deg` | `\deg` | ![](renders/deg.png) |  |
| `\degree` | `\degree` | ![](renders/degree.png) |  |
| `\delta` | `\delta` | ![](renders/delta.png) |  |
| `\Delta` | `\Delta` | ![](renders/delta-2.png) |  |
| `\det` | `\det` | ![](renders/det.png) |  |
| `\Digamma` | — | — | goldens: rej-unsup-digamma |
| `\digamma` | `\digamma` | ![](renders/digamma.png) |  |
| `\dfrac` | `\dfrac{a-1}{b-1}` | ![](renders/dfrac.png) |  |
| `\diagdown` | `\diagdown` | ![](renders/diagdown.png) |  |
| `\diagup` | `\diagup` | ![](renders/diagup.png) |  |
| `\Diamond` | `\Diamond` | ![](renders/diamond.png) |  |
| `\diamond` | `\diamond` | ![](renders/diamond-2.png) |  |
| `\diamonds` | `\diamonds` | ![](renders/diamonds.png) |  |
| `\diamondsuit` | `\diamondsuit` | ![](renders/diamondsuit.png) |  |
| `\dim` | `\dim` | ![](renders/dim.png) |  |
| `\displaylines` | — | — | goldens: rej-unsup-displaylines |
| `\displaystyle` | `\displaystyle\sum_0^n` | ![](renders/displaystyle.png) |  |
| `\div` | `\div` | ![](renders/div.png) |  |
| `\divideontimes` | `\divideontimes` | ![](renders/divideontimes.png) |  |
| `\dot` | `\dot x` | ![](renders/dot-2.png) |  |
| `\Doteq` | `\Doteq` | ![](renders/doteq.png) |  |
| `\doteq` | `\doteq` | ![](renders/doteq-2.png) |  |
| `\doteqdot` | `\doteqdot` | ![](renders/doteqdot.png) |  |
| `\dotplus` | `\dotplus` | ![](renders/dotplus.png) |  |
| `\dots` | `x_1 + \dots + x_n` | ![](renders/dots.png) |  |
| `\dotsb` | `x_1 +\dotsb + x_n` | ![](renders/dotsb.png) |  |
| `\dotsc` | `x,\dotsc,y` | ![](renders/dotsc.png) |  |
| `\dotsi` | `\int_{A_1}\int_{A_2}\dotsi` | ![](renders/dotsi.png) |  |
| `\dotsm` | `x_1 x_2 \dotsm x_n` | ![](renders/dotsm.png) |  |
| `\dotso` | `\dotso` | ![](renders/dotso.png) |  |
| `\doublebarwedge` | `\doublebarwedge` | ![](renders/doublebarwedge.png) |  |
| `\doublecap` | `\doublecap` | ![](renders/doublecap.png) |  |
| `\doublecup` | `\doublecup` | ![](renders/doublecup.png) |  |
| `\Downarrow` | `\Downarrow` | ![](renders/downarrow.png) |  |
| `\downarrow` | `\downarrow` | ![](renders/downarrow-2.png) |  |
| `\downdownarrows` | `\downdownarrows` | ![](renders/downdownarrows.png) |  |
| `\downharpoonleft` | `\downharpoonleft` | ![](renders/downharpoonleft.png) |  |
| `\downharpoonright` | `\downharpoonright` | ![](renders/downharpoonright.png) |  |
| `{drcases}` | `\begin{drcases}\na &\text{if } b  \\\nc &\text{if } d\n\end{drcases}` | ![](renders/drcases.png) |  |

## E

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\edef` | `\def\foo{a}\edef\fcopy{\foo}\def\foo{}\fcopy` | ![](renders/edef.png) |  |
| `\egroup` | `x{a\egroup` | ![](renders/egroup.png) |  |
| `\ell` | `\ell` | ![](renders/ell.png) |  |
| `\else` | — | — | goldens: rej-unsup-else |
| `\em` | — | — | goldens: rej-unsup-em |
| `\emph` | `\emph{x}` | ![](renders/emph.png) |  |
| `\empty` | `\empty` | ![](renders/empty.png) |  |
| `\emptyset` | `\emptyset` | ![](renders/emptyset.png) |  |
| `\enclose` | — | — | goldens: rej-unsup-enclose |
| `\end` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/end.png) |  |
| `\endgroup` | `\begingroup x\endgroup` | ![](renders/endgroup.png) |  |
| `\enskip` | `x\enskip y` | ![](renders/enskip.png) |  |
| `\enspace` | `a\enspace b` | ![](renders/enspace.png) |  |
| `\Epsilon` | `\Epsilon` | ![](renders/epsilon.png) |  |
| `\epsilon` | `\epsilon` | ![](renders/epsilon-2.png) |  |
| `\eqalign` | — | — | goldens: rej-unsup-eqalign |
| `\eqalignno` | — | — | goldens: rej-unsup-eqalignno |
| `\eqcirc` | `\eqcirc` | ![](renders/eqcirc.png) |  |
| `\Eqcolon` | `\Eqcolon` | ![](renders/eqcolon.png) |  |
| `\eqcolon` | `\eqcolon` | ![](renders/eqcolon-2.png) |  |
| `{equation}` | `\begin{equation}\na = b + c\n\end{equation}` | ![](renders/equation.png) |  |
| `{equation*}` | `\begin{equation*}\na = b + c\n\end{equation*}` | ![](renders/equationstar.png) |  |
| `{eqnarray}` | — | — | goldens: rej-unsup-eqnarray |
| `\Eqqcolon` | `\Eqqcolon` | ![](renders/eqqcolon.png) |  |
| `\eqqcolon` | `\eqqcolon` | ![](renders/eqqcolon-2.png) |  |
| `\eqref` | — | — | goldens: rej-unsup-eqref |
| `\eqsim` | `\eqsim` | ![](renders/eqsim.png) |  |
| `\eqslantgtr` | `\eqslantgtr` | ![](renders/eqslantgtr.png) |  |
| `\eqslantless` | `\eqslantless` | ![](renders/eqslantless.png) |  |
| `\equalscolon` | `\equalscolon` | ![](renders/equalscolon.png) |  |
| `\equalscoloncolon` | `\equalscoloncolon` | ![](renders/equalscoloncolon.png) |  |
| `\equiv` | `\equiv` | ![](renders/equiv.png) |  |
| `\Eta` | `\Eta` | ![](renders/eta.png) |  |
| `\eta` | `\eta` | ![](renders/eta-2.png) |  |
| `\eth` | `\eth` | ![](renders/eth.png) |  |
| `\euro` | — | — | goldens: rej-unsup-euro |
| `\exist` | `\exist` | ![](renders/exist.png) |  |
| `\exists` | `\exists` | ![](renders/exists.png) |  |
| `\exp` | `\exp` | ![](renders/exp.png) |  |
| `\expandafter` | `x \expandafter y` | ![](renders/expandafter.png) |  |

## F

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\@firstoftwo` | `\@firstoftwo{a}{b}` | ![](renders/firstoftwo.png) |  |
| `\fallingdotseq` | `\fallingdotseq` | ![](renders/fallingdotseq.png) |  |
| `\fbox` | `\fbox{Hi there!}` | ![](renders/fbox.png) |  |
| `\fcolorbox` | `\fcolorbox{red}{aqua}{A}` | ![](renders/fcolorbox.png) |  |
| `\fi` | — | — | goldens: rej-unsup-fi |
| `\Finv` | `\Finv` | ![](renders/finv.png) |  |
| `\flat` | `\flat` | ![](renders/flat.png) |  |
| `\footnotesize` | `\footnotesize footnotesize` | ![](renders/footnotesize.png) |  |
| `\forall` | `\forall` | ![](renders/forall.png) |  |
| `\frac` | `\frac a b` | ![](renders/frac.png) |  |
| `\frak` | `\frak{AaBb}` | ![](renders/frak.png) |  |
| `\frown` | `\frown` | ![](renders/frown.png) |  |
| `\futurelet` | `\def\foo{A}\futurelet\a\foo\foo` | ![](renders/futurelet.png) |  |

## G

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\Game` | `\Game` | ![](renders/game.png) |  |
| `\Gamma` | `\Gamma` | ![](renders/gamma.png) |  |
| `\gamma` | `\gamma` | ![](renders/gamma-2.png) |  |
| `{gather}` | `\begin{gather}\na=b \\ \ne=b+c\n\end{gather}` | ![](renders/gather.png) |  |
| `{gather*}` | `\begin{gather*}a\\b\end{gather*}` | ![](renders/gatherstar.png) |  |
| `{gathered}` | `\begin{gathered}\na=b \\ \ne=b+c\n\end{gathered}` | ![](renders/gathered.png) |  |
| `\gcd` | `\gcd` | ![](renders/gcd.png) |  |
| `\gdef` | `\gdef\sqr#1{#1^2} \sqr{y} + \sqr{y}` | ![](renders/gdef.png) |  |
| `\ge` | `\ge` | ![](renders/ge.png) |  |
| `\geneuro` | — | — | goldens: rej-unsup-geneuro |
| `\geneuronarrow` | — | — | goldens: rej-unsup-geneuronarrow |
| `\geneurowide` | — | — | goldens: rej-unsup-geneurowide |
| `\genfrac` | `\genfrac ( ] {2pt}{0}a{a+1}` | ![](renders/genfrac.png) |  |
| `\geq` | `\geq` | ![](renders/geq.png) |  |
| `\geqq` | `\geqq` | ![](renders/geqq.png) |  |
| `\geqslant` | `\geqslant` | ![](renders/geqslant.png) |  |
| `\gets` | `\gets` | ![](renders/gets.png) |  |
| `\gg` | `\gg` | ![](renders/gg.png) |  |
| `\ggg` | `\ggg` | ![](renders/ggg.png) |  |
| `\gggtr` | `\gggtr` | ![](renders/gggtr.png) |  |
| `\gimel` | `\gimel` | ![](renders/gimel.png) |  |
| `\global` | `\global\def\add#1#2{#1+#2} \add 2 3` | ![](renders/global.png) |  |
| `\gnapprox` | `\gnapprox` | ![](renders/gnapprox.png) |  |
| `\gneq` | `\gneq` | ![](renders/gneq.png) |  |
| `\gneqq` | `\gneqq` | ![](renders/gneqq.png) |  |
| `\gnsim` | `\gnsim` | ![](renders/gnsim.png) |  |
| `\grave` | `\grave{eu}` | ![](renders/grave.png) |  |
| `\gt` | `a \gt b` | ![](renders/gt-3.png) |  |
| `\gtrdot` | `\gtrdot` | ![](renders/gtrdot.png) |  |
| `\gtrapprox` | `\gtrapprox` | ![](renders/gtrapprox.png) |  |
| `\gtreqless` | `\gtreqless` | ![](renders/gtreqless.png) |  |
| `\gtreqqless` | `\gtreqqless` | ![](renders/gtreqqless.png) |  |
| `\gtrless` | `\gtrless` | ![](renders/gtrless.png) |  |
| `\gtrsim` | `\gtrsim` | ![](renders/gtrsim.png) |  |
| `\gvertneqq` | `\gvertneqq` | ![](renders/gvertneqq.png) |  |

## H

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\H` | `\text{\H{a}}` | ![](renders/h.png) |  |
| `\Harr` | `\Harr` | ![](renders/harr.png) |  |
| `\hArr` | `\hArr` | ![](renders/harr-2.png) |  |
| `\harr` | `\harr` | ![](renders/harr-3.png) |  |
| `\hat` | `\hat{\theta}` | ![](renders/hat.png) |  |
| `\hbar` | `\hbar` | ![](renders/hbar.png) |  |
| `\hbox` | `\hbox{$x^2$}` | ![](renders/hbox.png) |  |
| `\hbox to <dimen>` | `\hbox to 10pt{A}` | ![](renders/hboxdashtodashltdimengt.png) |  |
| `\hdashline` | `\begin{matrix}\na & b \\\n\hdashline\nc & d\n\end{matrix}` | ![](renders/hdashline.png) |  |
| `\hearts` | `\hearts` | ![](renders/hearts.png) |  |
| `\heartsuit` | `\heartsuit` | ![](renders/heartsuit.png) |  |
| `\hfil` | — | — | goldens: rej-unsup-hfil |
| `\hfill` | — | — | goldens: rej-unsup-hfill |
| `\hline` | `\begin{matrix}\na & b \\ \hline\nc & d\n\end{matrix}` | ![](renders/hline.png) |  |
| `\hom` | `\hom` | ![](renders/hom.png) |  |
| `\hookleftarrow` | `\hookleftarrow` | ![](renders/hookleftarrow.png) |  |
| `\hookrightarrow` | `\hookrightarrow` | ![](renders/hookrightarrow.png) |  |
| `\hphantom` | `a\hphantom{bc}d` | ![](renders/hphantom.png) |  |
| `\href` | `\href{https://github.com/gregoreesmaa/zatex}{\mathrm{Z\!^AT\!_EX}}` | ![](renders/href.png) |  |
| `\hskip` | `w\hskip1em i\hskip2em d` | ![](renders/hskip.png) |  |
| `\hslash` | `\hslash` | ![](renders/hslash.png) |  |
| `\hspace` | `s\hspace7ex k` | ![](renders/hspace.png) |  |
| `\htmlClass` | `\htmlClass{foo}{x}` | ![](renders/htmlclass.png) |  |
| `\htmlData` | `\htmlData{foo=a, bar=b}{x}` | ![](renders/htmldata.png) |  |
| `\htmlId` | `\htmlId{bar}{x}` | ![](renders/htmlid.png) |  |
| `\htmlStyle` | `\htmlStyle{color: red;}{x}` | ![](renders/htmlstyle.png) |  |
| `\huge` | `\huge huge` | ![](renders/huge.png) |  |
| `\Huge` | `\Huge Huge` | ![](renders/huge-2.png) |  |

## I

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\@ifnextchar` | `\@ifnextchar{a}{T}{E}a` | ![](renders/ifnextchar.png) |  |
| `\@ifstar` | `\@ifstar{T}{E}*` | ![](renders/ifstar.png) |  |
| `\i` | `\text{\i}` | ![](renders/i.png) |  |
| `\idotsint` | — | — | goldens: rej-unsup-idotsint |
| `\iddots` | — | — | goldens: rej-unsup-iddots |
| `\if` | — | — | goldens: rej-unsup-if |
| `\iff` | `A\iff B` | ![](renders/iff.png) |  |
| `\ifmode` | — | — | goldens: rej-unsup-ifmode |
| `\ifx` | — | — | goldens: rej-unsup-ifx |
| `\iiiint` | — | — | goldens: rej-unsup-iiiint |
| `\iiint` | `\iiint` | ![](renders/iiint.png) |  |
| `\iint` | `\iint` | ![](renders/iint.png) |  |
| `\Im` | `\Im` | ![](renders/im.png) |  |
| `\image` | `\image` | ![](renders/image.png) |  |
| `\imageof` | `\imageof` | ![](renders/imageof.png) |  |
| `\imath` | `\imath` | ![](renders/imath.png) |  |
| `\impliedby` | `P\impliedby Q` | ![](renders/impliedby.png) |  |
| `\implies` | `P\implies Q` | ![](renders/implies.png) |  |
| `\in` | `\in` | ![](renders/in.png) |  |
| `\includegraphics` | `\includegraphics[height=0.8em, totalheight=0.9em, width=0.9em, alt=KA logo]{https://cdn.kastatic.org/images/apple-touch-icon-57x57-precomposed.new.png}` | ![](renders/includegraphics.png) |  |
| `\inf` | `\inf` | ![](renders/inf.png) |  |
| `\infin` | `\infin` | ![](renders/infin.png) |  |
| `\infty` | `\infty` | ![](renders/infty.png) |  |
| `\injlim` | `\injlim` | ![](renders/injlim.png) |  |
| `\int` | `\int` | ![](renders/int.png) |  |
| `\intercal` | `\intercal` | ![](renders/intercal.png) |  |
| `\intop` | `\intop` | ![](renders/intop.png) |  |
| `\Iota` | `\Iota` | ![](renders/iota.png) |  |
| `\iota` | `\iota` | ![](renders/iota-2.png) |  |
| `\isin` | `\isin` | ![](renders/isin.png) |  |
| `\it` | `{\it AaBb}` | ![](renders/it.png) |  |
| `\itshape` | — | — | goldens: rej-unsup-itshape |

## JK

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\j` | `\text{\j}` | ![](renders/j.png) |  |
| `\jmath` | `\jmath` | ![](renders/jmath.png) |  |
| `\Join` | `\Join` | ![](renders/join.png) |  |
| `\Kappa` | `\Kappa` | ![](renders/kappa.png) |  |
| `\kappa` | `\kappa` | ![](renders/kappa-2.png) |  |
| `\KaTeX` | `\KaTeX` | ![](renders/katex.png) |  |
| `\ker` | `\ker` | ![](renders/ker.png) |  |
| `\kern` | `I\kern-2.5pt R` | ![](renders/kern.png) |  |
| `\Ket` | `\Ket{\psi}` | ![](renders/ket.png) |  |
| `\ket` | `\ket{\psi}` | ![](renders/ket-2.png) |  |
| `\Koppa` | — | — | goldens: rej-unsup-koppa |
| `\koppa` | — | — | goldens: rej-unsup-koppa-2 |

## L

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\L` | — | — | goldens: rej-unsup-l |
| `\l` | — | — | goldens: rej-unsup-l-2 |
| `\Lambda` | `\Lambda` | ![](renders/lambda.png) |  |
| `\lambda` | `\lambda` | ![](renders/lambda-2.png) |  |
| `\label` | — | — | goldens: rej-unsup-label |
| `\land` | `\land` | ![](renders/land.png) |  |
| `\lang` | `\lang A\rangle` | ![](renders/lang.png) |  |
| `\langle` | `\langle A\rangle` | ![](renders/langle.png) |  |
| `\Larr` | `\Larr` | ![](renders/larr.png) |  |
| `\lArr` | `\lArr` | ![](renders/larr-2.png) |  |
| `\larr` | `\larr` | ![](renders/larr-3.png) |  |
| `\large` | `\large large` | ![](renders/large.png) |  |
| `\Large` | `\Large Large` | ![](renders/large-2.png) |  |
| `\LARGE` | `\LARGE LARGE` | ![](renders/large-3.png) |  |
| `\LaTeX` | `\LaTeX` | ![](renders/latex.png) |  |
| `\lBrace` | `\lBrace` | ![](renders/lbrace.png) |  |
| `\lbrace` | `\lbrace` | ![](renders/lbrace-2.png) |  |
| `\lbrack` | `\lbrack` | ![](renders/lbrack.png) |  |
| `\lceil` | `\lceil` | ![](renders/lceil.png) |  |
| `\ldotp` | `\ldotp` | ![](renders/ldotp.png) |  |
| `\ldots` | `\ldots` | ![](renders/ldots.png) |  |
| `\le` | `\le` | ![](renders/le.png) |  |
| `\leadsto` | `\leadsto` | ![](renders/leadsto.png) |  |
| `\left` | `\left\lbrace \dfrac ab \right.` | ![](renders/left.png) |  |
| `\leftarrow` | `\leftarrow` | ![](renders/leftarrow.png) |  |
| `\Leftarrow` | `\Leftarrow` | ![](renders/leftarrow-2.png) |  |
| `\LeftArrow` | — | — | goldens: rej-unsup-leftarrow |
| `\leftarrowtail` | `\leftarrowtail` | ![](renders/leftarrowtail.png) |  |
| `\leftharpoondown` | `\leftharpoondown` | ![](renders/leftharpoondown.png) |  |
| `\leftharpoonup` | `\leftharpoonup` | ![](renders/leftharpoonup.png) |  |
| `\leftleftarrows` | `\leftleftarrows` | ![](renders/leftleftarrows.png) |  |
| `\Leftrightarrow` | `\Leftrightarrow` | ![](renders/leftrightarrow.png) |  |
| `\leftrightarrow` | `\leftrightarrow` | ![](renders/leftrightarrow-2.png) |  |
| `\leftrightarrows` | `\leftrightarrows` | ![](renders/leftrightarrows.png) |  |
| `\leftrightharpoons` | `\leftrightharpoons` | ![](renders/leftrightharpoons.png) |  |
| `\leftrightsquigarrow` | `\leftrightsquigarrow` | ![](renders/leftrightsquigarrow.png) |  |
| `\leftroot` | — | — | goldens: rej-unsup-leftroot |
| `\leftthreetimes` | `\leftthreetimes` | ![](renders/leftthreetimes.png) |  |
| `\leq` | `\leq` | ![](renders/leq.png) |  |
| `\leqalignno` | — | — | goldens: rej-unsup-leqalignno |
| `\leqq` | `\leqq` | ![](renders/leqq.png) |  |
| `\leqslant` | `\leqslant` | ![](renders/leqslant.png) |  |
| `\lessapprox` | `\lessapprox` | ![](renders/lessapprox.png) |  |
| `\lessdot` | `\lessdot` | ![](renders/lessdot.png) |  |
| `\lesseqgtr` | `\lesseqgtr` | ![](renders/lesseqgtr.png) |  |
| `\lesseqqgtr` | `\lesseqqgtr` | ![](renders/lesseqqgtr.png) |  |
| `\lessgtr` | `\lessgtr` | ![](renders/lessgtr.png) |  |
| `\lesssim` | `\lesssim` | ![](renders/lesssim.png) |  |
| `\let` | `\let\c=\alpha\c` | ![](renders/let.png) |  |
| `\lfloor` | `\lfloor` | ![](renders/lfloor.png) |  |
| `\lg` | `\lg` | ![](renders/lg.png) |  |
| `\lgroup` | `\lgroup` | ![](renders/lgroup.png) |  |
| `\lhd` | `\lhd` | ![](renders/lhd.png) |  |
| `\lim` | `\lim` | ![](renders/lim.png) |  |
| `\liminf` | `\liminf` | ![](renders/liminf.png) |  |
| `\limits` | `\lim\limits_x` | ![](renders/limits.png) |  |
| `\limsup` | `\limsup` | ![](renders/limsup.png) |  |
| `\ll` | `\ll` | ![](renders/ll.png) |  |
| `\llap` | `{=}\llap{/\,}` | ![](renders/llap.png) |  |
| `\llbracket` | `\llbracket` | ![](renders/llbracket.png) |  |
| `\llcorner` | `\llcorner` | ![](renders/llcorner.png) |  |
| `\Lleftarrow` | `\Lleftarrow` | ![](renders/lleftarrow.png) |  |
| `\lll` | `\lll` | ![](renders/lll.png) |  |
| `\llless` | `\llless` | ![](renders/llless.png) |  |
| `\lmoustache` | `\lmoustache` | ![](renders/lmoustache.png) |  |
| `\ln` | `\ln` | ![](renders/ln.png) |  |
| `\lnapprox` | `\lnapprox` | ![](renders/lnapprox.png) |  |
| `\lneq` | `\lneq` | ![](renders/lneq.png) |  |
| `\lneqq` | `\lneqq` | ![](renders/lneqq.png) |  |
| `\lnot` | `\lnot` | ![](renders/lnot.png) |  |
| `\lnsim` | `\lnsim` | ![](renders/lnsim.png) |  |
| `\log` | `\log` | ![](renders/log.png) |  |
| `\long` | `\long\def\foo{A}\foo` | ![](renders/long.png) |  |
| `\Longleftarrow` | `\Longleftarrow` | ![](renders/longleftarrow.png) |  |
| `\longleftarrow` | `\longleftarrow` | ![](renders/longleftarrow-2.png) |  |
| `\Longleftrightarrow` | `\Longleftrightarrow` | ![](renders/longleftrightarrow.png) |  |
| `\longleftrightarrow` | `\longleftrightarrow` | ![](renders/longleftrightarrow-2.png) |  |
| `\longmapsto` | `\longmapsto` | ![](renders/longmapsto.png) |  |
| `\Longrightarrow` | `\Longrightarrow` | ![](renders/longrightarrow.png) |  |
| `\longrightarrow` | `\longrightarrow` | ![](renders/longrightarrow-2.png) |  |
| `\looparrowleft` | `\looparrowleft` | ![](renders/looparrowleft.png) |  |
| `\looparrowright` | `\looparrowright` | ![](renders/looparrowright.png) |  |
| `\lor` | `\lor` | ![](renders/lor.png) |  |
| `\lower` | — | — | goldens: rej-unsup-lower |
| `\lozenge` | `\lozenge` | ![](renders/lozenge.png) |  |
| `\lparen` | `\lparen` | ![](renders/lparen.png) |  |
| `\Lrarr` | `\Lrarr` | ![](renders/lrarr.png) |  |
| `\lrArr` | `\lrArr` | ![](renders/lrarr-2.png) |  |
| `\lrarr` | `\lrarr` | ![](renders/lrarr-3.png) |  |
| `\lrcorner` | `\lrcorner` | ![](renders/lrcorner.png) |  |
| `\lq` | `\lq` | ![](renders/lq.png) |  |
| `\Lsh` | `\Lsh` | ![](renders/lsh.png) |  |
| `\lt` | `\lt` | ![](renders/lt-2.png) |  |
| `\ltimes` | `\ltimes` | ![](renders/ltimes.png) |  |
| `\lVert` | `\lVert` | ![](renders/lvert.png) |  |
| `\lvert` | `\lvert` | ![](renders/lvert-2.png) |  |
| `\lvertneqq` | `\lvertneqq` | ![](renders/lvertneqq.png) |  |

## M

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\maltese` | `\maltese` | ![](renders/maltese.png) |  |
| `\mapsfrom` | `\mapsfrom` | ![](renders/mapsfrom.png) |  |
| `\mapsto` | `\mapsto` | ![](renders/mapsto.png) |  |
| `\mathbb` | `\mathbb{AB}` | ![](renders/mathbb.png) |  |
| `\mathbf` | `\mathbf{AaBb123}` | ![](renders/mathbf.png) |  |
| `\mathbin` | `a\mathbin{!}b` | ![](renders/mathbin.png) |  |
| `\mathcal` | `\mathcal{AaBb123}` | ![](renders/mathcal.png) |  |
| `\mathchoice` | `a\mathchoice{\,}{\,\,}{\,\,\,}{\,\,\,\,}b` | ![](renders/mathchoice.png) |  |
| `\mathclap` | `\sum_{\mathclap{1\le i\le n}} x_{i}` | ![](renders/mathclap.png) |  |
| `\mathclose` | `a + (b\mathclose\gt + c` | ![](renders/mathclose.png) |  |
| `\mathellipsis` | `\mathellipsis` | ![](renders/mathellipsis.png) |  |
| `\mathfrak` | `\mathfrak{AaBb}` | ![](renders/mathfrak.png) |  |
| `\mathinner` | `ab\mathinner{\text{inside}}cd` | ![](renders/mathinner.png) |  |
| `\mathit` | `\mathit{AaBb}` | ![](renders/mathit.png) |  |
| `\mathllap` | `{=}\mathllap{/\,}` | ![](renders/mathllap.png) |  |
| `\mathnormal` | `\mathnormal{AaBb}` | ![](renders/mathnormal.png) |  |
| `\mathop` | `\mathop{\star}_a^b` | ![](renders/mathop.png) |  |
| `\mathopen` | `a + \mathopen\lt b) + c` | ![](renders/mathopen.png) |  |
| `\mathord` | `1\mathord{,}234{,}567` | ![](renders/mathord.png) |  |
| `\mathpunct` | `A\mathpunct{-}B` | ![](renders/mathpunct.png) |  |
| `\mathreflectbox` | `\mathreflectbox{x^2}` | ![](renders/mathreflectbox.png) |  |
| `\mathrel` | `a \mathrel{\#} b` | ![](renders/mathrel.png) |  |
| `\mathrlap` | `\mathrlap{\,/}{=}` | ![](renders/mathrlap.png) |  |
| `\mathring` | `\mathring{a}` | ![](renders/mathring.png) |  |
| `\mathrm` | `\mathrm{AaBb123}` | ![](renders/mathrm.png) |  |
| `\mathscr` | `\mathscr{AaBb123}` | ![](renders/mathscr.png) |  |
| `\mathsf` | `\mathsf{AaBb123}` | ![](renders/mathsf.png) |  |
| `\mathsfit` | `\mathsfit{AaBb}` | ![](renders/mathsfit.png) |  |
| `\mathsterling` | `\mathsterling` | ![](renders/mathsterling.png) |  |
| `\mathstrut` | `\sqrt{\mathstrut a}` | ![](renders/mathstrut.png) |  |
| `\mathtip` | — | — | goldens: rej-unsup-mathtip |
| `\mathtt` | `\mathtt{AaBb123}` | ![](renders/mathtt.png) |  |
| `\matrix` | — | — | goldens: rej-env-mismatch |
| `{matrix}` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/matrix.png) |  |
| `{matrix*}` | `\begin{matrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{matrix*}` | ![](renders/matrixstar.png) |  |
| `\max` | `\max` | ![](renders/max.png) |  |
| `\mbox` | — | — | goldens: rej-unsup-mbox |
| `\md` | — | — | goldens: rej-unsup-md |
| `\mdseries` | — | — | goldens: rej-unsup-mdseries |
| `\measuredangle` | `\measuredangle` | ![](renders/measuredangle.png) |  |
| `\medspace` | `a\medspace b` | ![](renders/medspace.png) |  |
| `\mho` | `\mho` | ![](renders/mho.png) |  |
| `\mid` | `\{x∈ℝ\mid x>0\}` | ![](renders/mid.png) |  |
| `\middle` | `P\left(A\middle\vert B\right)` | ![](renders/middle.png) |  |
| `\min` | `\min` | ![](renders/min.png) |  |
| `\minuscolon` | `\minuscolon` | ![](renders/minuscolon.png) |  |
| `\minuscoloncolon` | `\minuscoloncolon` | ![](renders/minuscoloncolon.png) |  |
| `\minuso` | `\minuso` | ![](renders/minuso.png) |  |
| `\mit` | — | — | goldens: rej-unsup-mit |
| `\mkern` | `a\mkern18mu b` | ![](renders/mkern.png) |  |
| `\mmlToken` | — | — | goldens: rej-unsup-mmltoken |
| `\mod` | `3\equiv 5 \mod 2` | ![](renders/mod.png) |  |
| `\models` | `\models` | ![](renders/models.png) |  |
| `\moveleft` | — | — | goldens: rej-unsup-moveleft |
| `\moveright` | — | — | goldens: rej-unsup-moveright |
| `\mp` | `\mp` | ![](renders/mp.png) |  |
| `\mskip` | `a\mskip{10mu}b` | ![](renders/mskip.png) |  |
| `\mspace` | — | — | goldens: rej-unsup-mspace |
| `\Mu` | `\Mu` | ![](renders/mu.png) |  |
| `\mu` | `\mu` | ![](renders/mu-2.png) |  |
| `\multicolumn` | — | — | goldens: rej-unsup-multicolumn |
| `{multiline}` | — | — | goldens: rej-unsup-multiline |
| `\multimap` | `\multimap` | ![](renders/multimap.png) |  |

## N

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\N` | `\N` | ![](renders/n.png) |  |
| `\nabla` | `\nabla` | ![](renders/nabla.png) |  |
| `\natnums` | `\natnums` | ![](renders/natnums.png) |  |
| `\natural` | `\natural` | ![](renders/natural.png) |  |
| `\negmedspace` | `a\negmedspace b` | ![](renders/negmedspace.png) |  |
| `\ncong` | `\ncong` | ![](renders/ncong.png) |  |
| `\ne` | `\ne` | ![](renders/ne.png) |  |
| `\nearrow` | `\nearrow` | ![](renders/nearrow.png) |  |
| `\neg` | `\neg` | ![](renders/neg.png) |  |
| `\negthickspace` | `a\negthickspace b` | ![](renders/negthickspace.png) |  |
| `\negthinspace` | `a\negthinspace b` | ![](renders/negthinspace.png) |  |
| `\neq` | `\neq` | ![](renders/neq.png) |  |
| `\newcommand` | `\newcommand\chk{\checkmark} \chk` | ![](renders/newcommand.png) |  |
| `\newenvironment` | — | — | goldens: rej-unsup-newenvironment |
| `\Newextarrow` | — | — | goldens: rej-unsup-newextarrow |
| `\newline` | `a\newline b` | ![](renders/newline.png) | Breaks env rows like `\\`; inert mspace in running math |
| `\nexists` | `\nexists` | ![](renders/nexists.png) |  |
| `\ngeq` | `\ngeq` | ![](renders/ngeq.png) |  |
| `\ngeqq` | `\ngeqq` | ![](renders/ngeqq.png) |  |
| `\ngeqslant` | `\ngeqslant` | ![](renders/ngeqslant.png) |  |
| `\ngtr` | `\ngtr` | ![](renders/ngtr.png) |  |
| `\ni` | `\ni` | ![](renders/ni.png) |  |
| `\nleftarrow` | `\nleftarrow` | ![](renders/nleftarrow.png) |  |
| `\nLeftarrow` | `\nLeftarrow` | ![](renders/nleftarrow-2.png) |  |
| `\nLeftrightarrow` | `\nLeftrightarrow` | ![](renders/nleftrightarrow.png) |  |
| `\nleftrightarrow` | `\nleftrightarrow` | ![](renders/nleftrightarrow-2.png) |  |
| `\nleq` | `\nleq` | ![](renders/nleq.png) |  |
| `\nleqq` | `\nleqq` | ![](renders/nleqq.png) |  |
| `\nleqslant` | `\nleqslant` | ![](renders/nleqslant.png) |  |
| `\nless` | `\nless` | ![](renders/nless.png) |  |
| `\nmid` | `\nmid` | ![](renders/nmid.png) |  |
| `\nobreak` | `x \nobreak y` | ![](renders/nobreak.png) |  |
| `\nobreakspace` | `a\nobreakspace b` | ![](renders/nobreakspace.png) |  |
| `\noexpand` | `x \noexpand y` | ![](renders/noexpand.png) |  |
| `\nolimits` | `\lim\nolimits_x` | ![](renders/nolimits.png) |  |
| `\nonumber` | `\begin{align}\na&=b+c \nonumber\\\nd+e&=f\n\end{align}` | ![](renders/nonumber.png) |  |
| `\normalfont` | — | — | goldens: rej-unsup-normalfont |
| `\normalsize` | `\normalsize normalsize` | ![](renders/normalsize.png) |  |
| `\not` | `\not =` | ![](renders/not.png) |  |
| `\notag` | `\begin{align}\na&=b+c \notag\\\nd+e&=f\n\end{align}` | ![](renders/notag.png) |  |
| `\notin` | `\notin` | ![](renders/notin.png) |  |
| `\notni` | `\notni` | ![](renders/notni.png) |  |
| `\nparallel` | `\nparallel` | ![](renders/nparallel.png) |  |
| `\nprec` | `\nprec` | ![](renders/nprec.png) |  |
| `\npreceq` | `\npreceq` | ![](renders/npreceq.png) |  |
| `\nRightarrow` | `\nRightarrow` | ![](renders/nrightarrow.png) |  |
| `\nrightarrow` | `\nrightarrow` | ![](renders/nrightarrow-2.png) |  |
| `\nshortmid` | `\nshortmid` | ![](renders/nshortmid.png) |  |
| `\nshortparallel` | `\nshortparallel` | ![](renders/nshortparallel.png) |  |
| `\nsim` | `\nsim` | ![](renders/nsim.png) |  |
| `\nsubseteq` | `\nsubseteq` | ![](renders/nsubseteq.png) |  |
| `\nsubseteqq` | `\nsubseteqq` | ![](renders/nsubseteqq.png) |  |
| `\nsucc` | `\nsucc` | ![](renders/nsucc.png) |  |
| `\nsucceq` | `\nsucceq` | ![](renders/nsucceq.png) |  |
| `\nsupseteq` | `\nsupseteq` | ![](renders/nsupseteq.png) |  |
| `\nsupseteqq` | `\nsupseteqq` | ![](renders/nsupseteqq.png) |  |
| `\ntriangleleft` | `\ntriangleleft` | ![](renders/ntriangleleft.png) |  |
| `\ntrianglelefteq` | `\ntrianglelefteq` | ![](renders/ntrianglelefteq.png) |  |
| `\ntriangleright` | `\ntriangleright` | ![](renders/ntriangleright.png) |  |
| `\ntrianglerighteq` | `\ntrianglerighteq` | ![](renders/ntrianglerighteq.png) |  |
| `\Nu` | `\Nu` | ![](renders/nu.png) |  |
| `\nu` | `\nu` | ![](renders/nu-2.png) |  |
| `\nVDash` | `\nVDash` | ![](renders/nvdash.png) |  |
| `\nVdash` | `\nVdash` | ![](renders/nvdash-2.png) |  |
| `\nvDash` | `\nvDash` | ![](renders/nvdash-3.png) |  |
| `\nvdash` | `\nvdash` | ![](renders/nvdash-4.png) |  |
| `\nwarrow` | `\nwarrow` | ![](renders/nwarrow.png) |  |

## O

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\O` | `\text{\O}` | ![](renders/o.png) |  |
| `\o` | `\text{\o}` | ![](renders/o-2.png) |  |
| `\odot` | `\odot` | ![](renders/odot.png) |  |
| `\OE` | `\text{\OE}` | ![](renders/oe.png) |  |
| `\oe` | `\text{\oe}` | ![](renders/oe-2.png) |  |
| `\officialeuro` | — | — | goldens: rej-unsup-officialeuro |
| `\oiiint` | `\oiiint` | ![](renders/oiiint.png) |  |
| `\oiint` | `\oiint` | ![](renders/oiint.png) |  |
| `\oint` | `\oint` | ![](renders/oint.png) |  |
| `\oldstyle` | — | — | goldens: rej-unsup-oldstyle |
| `\omega` | `\omega` | ![](renders/omega.png) |  |
| `\Omega` | `\Omega` | ![](renders/omega-2.png) |  |
| `\Omicron` | `\Omicron` | ![](renders/omicron.png) |  |
| `\omicron` | `\omicron` | ![](renders/omicron-2.png) |  |
| `\ominus` | `\ominus` | ![](renders/ominus.png) |  |
| `\operatorname` | `\operatorname{asin} x` | ![](renders/operatorname.png) |  |
| `\operatorname*` | `\operatorname*{asin}\limits_y x` | ![](renders/operatornamestar.png) |  |
| `\operatornamewithlimits` | `\operatornamewithlimits{asin}\limits_y x` | ![](renders/operatornamewithlimits.png) |  |
| `\oplus` | `\oplus` | ![](renders/oplus.png) |  |
| `\or` | — | — | goldens: rej-unsup-or |
| `\origof` | `\origof` | ![](renders/origof.png) |  |
| `\oslash` | `\oslash` | ![](renders/oslash.png) |  |
| `\otimes` | `\otimes` | ![](renders/otimes.png) |  |
| `\over` | `{a+1 \over b+2}+c` | ![](renders/over.png) |  |
| `\overbrace` | `\overbrace{x+⋯+x}^{n\text{ times}}` | ![](renders/overbrace.png) |  |
| `\overbracket` | `\overbracket{x+⋯+x}^{n\text{ times}}` | ![](renders/overbracket.png) |  |
| `\overgroup` | `\overgroup{AB}` | ![](renders/overgroup.png) |  |
| `\overleftarrow` | `\overleftarrow{AB}` | ![](renders/overleftarrow.png) |  |
| `\overleftharpoon` | `\overleftharpoon{AB}` | ![](renders/overleftharpoon.png) |  |
| `\overleftrightarrow` | `\overleftrightarrow{AB}` | ![](renders/overleftrightarrow.png) |  |
| `\overline` | `\overline{\text{a long argument}}` | ![](renders/overline.png) |  |
| `\overlinesegment` | `\overlinesegment{AB}` | ![](renders/overlinesegment.png) |  |
| `\overparen` | — | — | goldens: rej-unsup-overparen |
| `\Overrightarrow` | `\Overrightarrow{AB}` | ![](renders/overrightarrow.png) |  |
| `\overrightarrow` | `\overrightarrow{AB}` | ![](renders/overrightarrow-2.png) |  |
| `\overrightharpoon` | `\overrightharpoon{ac}` | ![](renders/overrightharpoon.png) |  |
| `\overset` | `\overset{!}{=}` | ![](renders/overset.png) |  |
| `\overwithdelims` | — | — | goldens: rej-unsup-overwithdelims |
| `\owns` | `\owns` | ![](renders/owns.png) |  |

## P

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\P` | `\text{\P}` | ![](renders/p.png) |  |
| `\pagecolor` | — | — | goldens: rej-unsup-pagecolor |
| `\parallel` | `\parallel` | ![](renders/parallel.png) |  |
| `\part` | — | — | goldens: rej-unsup-part |
| `\partial` | `\partial` | ![](renders/partial.png) |  |
| `\perp` | `\perp` | ![](renders/perp.png) |  |
| `\phantom` | `\Gamma^{\phantom{i}j}_{i\phantom{j}k}` | ![](renders/phantom.png) |  |
| `\phase` | `\phase{-78^\circ}` | ![](renders/phase.png) |  |
| `\Phi` | `\Phi` | ![](renders/phi.png) |  |
| `\phi` | `\phi` | ![](renders/phi-2.png) |  |
| `\Pi` | `\Pi` | ![](renders/pi.png) |  |
| `\pi` | `\pi` | ![](renders/pi-2.png) |  |
| `{picture}` | — | — | goldens: rej-unsup-picture |
| `\pitchfork` | `\pitchfork` | ![](renders/pitchfork.png) |  |
| `\plim` | `\plim` | ![](renders/plim.png) |  |
| `\plusmn` | `\plusmn` | ![](renders/plusmn.png) |  |
| `\pm` | `\pm` | ![](renders/pm.png) |  |
| `\pmatrix` | — | — | goldens: rej-unsup-pmatrix |
| `{pmatrix}` | `\begin{pmatrix}\na & b \\\nc & d\n\end{pmatrix}` | ![](renders/pmatrix.png) |  |
| `{pmatrix*}` | `\begin{pmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{pmatrix*}` | ![](renders/pmatrixstar.png) |  |
| `\pmb` | `\pmb{\mu}` | ![](renders/pmb.png) |  |
| `\pmod` | `x\pmod a` | ![](renders/pmod.png) |  |
| `\pod` | `x \pod a` | ![](renders/pod.png) |  |
| `\pounds` | `\pounds` | ![](renders/pounds.png) |  |
| `\Pr` | `\Pr` | ![](renders/pr.png) |  |
| `\prec` | `\prec` | ![](renders/prec.png) |  |
| `\precapprox` | `\precapprox` | ![](renders/precapprox.png) |  |
| `\preccurlyeq` | `\preccurlyeq` | ![](renders/preccurlyeq.png) |  |
| `\preceq` | `\preceq` | ![](renders/preceq.png) |  |
| `\precnapprox` | `\precnapprox` | ![](renders/precnapprox.png) |  |
| `\precneqq` | `\precneqq` | ![](renders/precneqq.png) |  |
| `\precnsim` | `\precnsim` | ![](renders/precnsim.png) |  |
| `\precsim` | `\precsim` | ![](renders/precsim.png) |  |
| `\prime` | `\prime` | ![](renders/prime-3.png) |  |
| `\prod` | `\prod` | ![](renders/prod.png) |  |
| `\projlim` | `\projlim` | ![](renders/projlim.png) |  |
| `\propto` | `\propto` | ![](renders/propto.png) |  |
| `\providecommand` | `\providecommand\greet{\text{Hello}} \greet` | ![](renders/providecommand.png) |  |
| `\psi` | `\psi` | ![](renders/psi.png) |  |
| `\Psi` | `\Psi` | ![](renders/psi-2.png) |  |
| `\pu` | — | — | goldens: rej-unsup-pu |

## QR

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\Q` | — | — | goldens: rej-unsup-q |
| `\qquad` | `a\qquad\qquad{b}` | ![](renders/qquad.png) |  |
| `\quad` | `a\quad\quad{b}` | ![](renders/quad.png) |  |
| `\R` | `\R` | ![](renders/r.png) |  |
| `\r` | `\text{\r{a}}` | ![](renders/r-2.png) |  |
| `\raise` | — | — | goldens: rej-unsup-raise |
| `\raisebox` | `h\raisebox{2pt}{ighe}r` | ![](renders/raisebox.png) |  |
| `\rang` | `\langle A\rang` | ![](renders/rang.png) |  |
| `\rangle` | `\langle A\rangle` | ![](renders/rangle.png) |  |
| `\Rarr` | `\Rarr` | ![](renders/rarr.png) |  |
| `\rArr` | `\rArr` | ![](renders/rarr-2.png) |  |
| `\rarr` | `\rarr` | ![](renders/rarr-3.png) |  |
| `\ratio` | `\ratio` | ![](renders/ratio.png) |  |
| `\rBrace` | `\rBrace` | ![](renders/rbrace.png) |  |
| `\rbrace` | `\rbrace` | ![](renders/rbrace-2.png) |  |
| `\rbrack` | `\rbrack` | ![](renders/rbrack.png) |  |
| `{rcases}` | `\begin{rcases}\na &\text{if } b  \\\nc &\text{if } d\n\end{rcases}` | ![](renders/rcases.png) |  |
| `\rceil` | `\rceil` | ![](renders/rceil.png) |  |
| `\Re` | `\Re` | ![](renders/re.png) |  |
| `\real` | `\real` | ![](renders/real.png) |  |
| `\Reals` | `\Reals` | ![](renders/reals.png) |  |
| `\reals` | `\reals` | ![](renders/reals-2.png) |  |
| `\ref` | — | — | goldens: rej-unsup-ref |
| `\reflectbox` | `\reflectbox{$x^2$}` | ![](renders/reflectbox.png) |  |
| `\relax` | `x \relax y` | ![](renders/relax.png) |  |
| `\renewcommand` | `\def\hail{Hi!}\n\renewcommand\hail{\text{Ahoy!}}\n\hail` | ![](renders/renewcommand.png) |  |
| `\renewenvironment` | — | — | goldens: rej-unsup-renewenvironment |
| `\require` | — | — | goldens: rej-unsup-require |
| `\restriction` | `\restriction` | ![](renders/restriction.png) |  |
| `\rfloor` | `\rfloor` | ![](renders/rfloor.png) |  |
| `\rgroup` | `\rgroup` | ![](renders/rgroup.png) |  |
| `\rhd` | `\rhd` | ![](renders/rhd.png) |  |
| `\Rho` | `\Rho` | ![](renders/rho.png) |  |
| `\rho` | `\rho` | ![](renders/rho-2.png) |  |
| `\right` | `\left.\dfrac a b\right)` | ![](renders/right.png) |  |
| `\Rightarrow` | `\Rightarrow` | ![](renders/rightarrow.png) |  |
| `\rightarrow` | `\rightarrow` | ![](renders/rightarrow-2.png) |  |
| `\rightarrowtail` | `\rightarrowtail` | ![](renders/rightarrowtail.png) |  |
| `\rightharpoondown` | `\rightharpoondown` | ![](renders/rightharpoondown.png) |  |
| `\rightharpoonup` | `\rightharpoonup` | ![](renders/rightharpoonup.png) |  |
| `\rightleftarrows` | `\rightleftarrows` | ![](renders/rightleftarrows.png) |  |
| `\rightleftharpoons` | `\rightleftharpoons` | ![](renders/rightleftharpoons.png) |  |
| `\rightrightarrows` | `\rightrightarrows` | ![](renders/rightrightarrows.png) |  |
| `\rightsquigarrow` | `\rightsquigarrow` | ![](renders/rightsquigarrow.png) |  |
| `\rightthreetimes` | `\rightthreetimes` | ![](renders/rightthreetimes.png) |  |
| `\risingdotseq` | `\risingdotseq` | ![](renders/risingdotseq.png) |  |
| `\rlap` | `\rlap{\,/}{=}` | ![](renders/rlap.png) |  |
| `\rm` | `\rm AaBb12` | ![](renders/rm.png) |  |
| `\rmoustache` | `\rmoustache` | ![](renders/rmoustache.png) |  |
| `\root` | — | — | goldens: rej-unsup-root |
| `\rotatebox` | — | — | goldens: rej-unsup-rotatebox |
| `\rparen` | `\rparen` | ![](renders/rparen.png) |  |
| `\rq` | `\rq` | ![](renders/rq.png) |  |
| `\rrbracket` | `\rrbracket` | ![](renders/rrbracket.png) |  |
| `\Rrightarrow` | `\Rrightarrow` | ![](renders/rrightarrow.png) |  |
| `\Rsh` | `\Rsh` | ![](renders/rsh.png) |  |
| `\rtimes` | `\rtimes` | ![](renders/rtimes.png) |  |
| `\Rule` | — | — | goldens: rej-unsup-rule |
| `\rule` | `x\rule[6pt]{2ex}{1ex}x` | ![](renders/rule.png) |  |
| `\rVert` | `\rVert` | ![](renders/rvert.png) |  |
| `\rvert` | `\rvert` | ![](renders/rvert-2.png) |  |

## S

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\@secondoftwo` | `\@secondoftwo{a}{b}` | ![](renders/secondoftwo.png) |  |
| `\S` | `\text{\S}` | ![](renders/s.png) |  |
| `\Sampi` | — | — | goldens: rej-unsup-sampi |
| `\sampi` | — | — | goldens: rej-unsup-sampi-2 |
| `\sc` | — | — | goldens: rej-unsup-sc |
| `\scalebox` | — | — | goldens: rej-unsup-scalebox |
| `\scr` | — | — | goldens: rej-unsup-scr |
| `\scriptscriptstyle` | `\scriptscriptstyle \frac cd` | ![](renders/scriptscriptstyle.png) |  |
| `\scriptsize` | `\scriptsize scriptsize` | ![](renders/scriptsize.png) |  |
| `\scriptstyle` | `\frac ab + {\scriptstyle \frac cd}` | ![](renders/scriptstyle.png) |  |
| `\sdot` | `\sdot` | ![](renders/sdot.png) |  |
| `\searrow` | `\searrow` | ![](renders/searrow.png) |  |
| `\sec` | `\sec` | ![](renders/sec.png) |  |
| `\sect` | `\text{\sect}` | ![](renders/sect.png) |  |
| `\set` | `\set{x&#124;x<5}` | ![](renders/set.png) |  |
| `\Set` | `\Set{ x &#124; x<\frac 1 2}` | ![](renders/set-2.png) |  |
| `\setlength` | — | — | goldens: rej-unsup-setlength |
| `\setminus` | `\setminus` | ![](renders/setminus.png) |  |
| `\sf` | `\sf AaBb123` | ![](renders/sf.png) |  |
| `\sharp` | `\sharp` | ![](renders/sharp.png) |  |
| `\shortmid` | `\shortmid` | ![](renders/shortmid.png) |  |
| `\shortparallel` | `\shortparallel` | ![](renders/shortparallel.png) |  |
| `\shoveleft` | — | — | goldens: rej-unsup-shoveleft |
| `\shoveright` | — | — | goldens: rej-unsup-shoveright |
| `\sideset` | — | — | goldens: rej-unsup-sideset |
| `\Sigma` | `\Sigma` | ![](renders/sigma.png) |  |
| `\sigma` | `\sigma` | ![](renders/sigma-2.png) |  |
| `\sim` | `\sim` | ![](renders/sim.png) |  |
| `\simcolon` | `\simcolon` | ![](renders/simcolon.png) |  |
| `\simcoloncolon` | `\simcoloncolon` | ![](renders/simcoloncolon.png) |  |
| `\simeq` | `\simeq` | ![](renders/simeq.png) |  |
| `\sin` | `\sin` | ![](renders/sin.png) |  |
| `\sinh` | `\sinh` | ![](renders/sinh.png) |  |
| `\sixptsize` | `\sixptsize sixptsize` | ![](renders/sixptsize.png) |  |
| `\sh` | `\sh` | ![](renders/sh.png) |  |
| `\skew` | — | — | goldens: rej-unsup-skew |
| `\skip` | — | — | goldens: rej-unsup-skip |
| `\sl` | — | — | goldens: rej-unsup-sl |
| `\small` | `\small small` | ![](renders/small.png) |  |
| `\smallfrown` | `\smallfrown` | ![](renders/smallfrown.png) |  |
| `\smallint` | `\smallint` | ![](renders/smallint.png) |  |
| `{smallmatrix}` | `\begin{smallmatrix}\na & b \\\nc & d\n\end{smallmatrix}` | ![](renders/smallmatrix.png) |  |
| `\smallsetminus` | `\smallsetminus` | ![](renders/smallsetminus.png) |  |
| `\smallsmile` | `\smallsmile` | ![](renders/smallsmile.png) |  |
| `\smash` | `\left(x^{\smash{2}}\right)` | ![](renders/smash.png) |  |
| `\smile` | `\smile` | ![](renders/smile.png) |  |
| `\smiley` | — | — | goldens: rej-unsup-smiley |
| `\sout` | `\text{\sout{abc}}` | ![](renders/sout.png) |  |
| `\Space` | — | — | goldens: rej-unsup-space |
| `\space` | `a\space b` | ![](renders/space.png) |  |
| `\spades` | `\spades` | ![](renders/spades.png) |  |
| `\spadesuit` | `\spadesuit` | ![](renders/spadesuit.png) |  |
| `\sphericalangle` | `\sphericalangle` | ![](renders/sphericalangle.png) |  |
| `{split}` | `\begin{equation}\n\begin{split}\na &=b+c\\\n&=e+f\n\end{split}\n\end{equation}` | ![](renders/split.png) |  |
| `\sqcap` | `\sqcap` | ![](renders/sqcap.png) |  |
| `\sqcup` | `\sqcup` | ![](renders/sqcup.png) |  |
| `\square` | `\square` | ![](renders/square.png) |  |
| `\sqrt` | `\sqrt[3]{x}` | ![](renders/sqrt.png) |  |
| `\sqsubset` | `\sqsubset` | ![](renders/sqsubset.png) |  |
| `\sqsubseteq` | `\sqsubseteq` | ![](renders/sqsubseteq.png) |  |
| `\sqsupset` | `\sqsupset` | ![](renders/sqsupset.png) |  |
| `\sqsupseteq` | `\sqsupseteq` | ![](renders/sqsupseteq.png) |  |
| `\ss` | `\text{\ss}` | ![](renders/ss.png) |  |
| `\stackrel` | `\stackrel{!}{=}` | ![](renders/stackrel.png) |  |
| `\star` | `\star` | ![](renders/star.png) |  |
| `\Stigma` | — | — | goldens: rej-unsup-stigma |
| `\stigma` | — | — | goldens: rej-unsup-stigma-2 |
| `\strut` | — | — | goldens: rej-unsup-strut |
| `\style` | — | — | goldens: rej-unsup-style |
| `\sub` | `\sub` | ![](renders/sub.png) |  |
| `{subarray}` | `\sum_{\begin{subarray}{l}1\le i\le n\end{subarray}}x_i` | ![](renders/subarray.png) |  |
| `\sube` | `\sube` | ![](renders/sube.png) |  |
| `\Subset` | `\Subset` | ![](renders/subset.png) |  |
| `\subset` | `\subset` | ![](renders/subset-2.png) |  |
| `\subseteq` | `\subseteq` | ![](renders/subseteq.png) |  |
| `\subseteqq` | `\subseteqq` | ![](renders/subseteqq.png) |  |
| `\subsetneq` | `\subsetneq` | ![](renders/subsetneq.png) |  |
| `\subsetneqq` | `\subsetneqq` | ![](renders/subsetneqq.png) |  |
| `\substack` | `\sum_{\substack{0<i<m\\0<j<n}}` | ![](renders/substack.png) |  |
| `\succ` | `\succ` | ![](renders/succ.png) |  |
| `\succapprox` | `\succapprox` | ![](renders/succapprox.png) |  |
| `\succcurlyeq` | `\succcurlyeq` | ![](renders/succcurlyeq.png) |  |
| `\succeq` | `\succeq` | ![](renders/succeq.png) |  |
| `\succnapprox` | `\succnapprox` | ![](renders/succnapprox.png) |  |
| `\succneqq` | `\succneqq` | ![](renders/succneqq.png) |  |
| `\succnsim` | `\succnsim` | ![](renders/succnsim.png) |  |
| `\succsim` | `\succsim` | ![](renders/succsim.png) |  |
| `\sum` | `\sum` | ![](renders/sum.png) |  |
| `\sup` | `\sup` | ![](renders/sup.png) |  |
| `\supe` | `\supe` | ![](renders/supe.png) |  |
| `\Supset` | `\Supset` | ![](renders/supset.png) |  |
| `\supset` | `\supset` | ![](renders/supset-2.png) |  |
| `\supseteq` | `\supseteq` | ![](renders/supseteq.png) |  |
| `\supseteqq` | `\supseteqq` | ![](renders/supseteqq.png) |  |
| `\supsetneq` | `\supsetneq` | ![](renders/supsetneq.png) |  |
| `\supsetneqq` | `\supsetneqq` | ![](renders/supsetneqq.png) |  |
| `\surd` | `\surd` | ![](renders/surd.png) |  |
| `\swarrow` | `\swarrow` | ![](renders/swarrow.png) |  |

## T

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\tag` | `\tag{3.1c} a^2+b^2=c^2` | ![](renders/tag.png) | Hoists to the equation; a row-local tag keeps its number columns despite `\nonumber` |
| `\tag*` | `\tag*{3.1c} a^2+b^2=c^2` | ![](renders/tagstar.png) |  |
| `\tan` | `\tan` | ![](renders/tan.png) |  |
| `\tanh` | `\tanh` | ![](renders/tanh.png) |  |
| `\Tau` | `\Tau` | ![](renders/tau.png) |  |
| `\tau` | `\tau` | ![](renders/tau-2.png) |  |
| `\tbinom` | `\tbinom n k` | ![](renders/tbinom.png) |  |
| `\TeX` | `\TeX` | ![](renders/tex.png) |  |
| `\text` | `\text{ yes }\&\text{ no }` | ![](renders/text.png) |  |
| `\textasciitilde` | `\text{\textasciitilde}` | ![](renders/textasciitilde.png) |  |
| `\textasciicircum` | `\text{\textasciicircum}` | ![](renders/textasciicircum.png) |  |
| `\textbackslash` | `\text{\textbackslash}` | ![](renders/textbackslash.png) |  |
| `\textbar` | `\text{\textbar}` | ![](renders/textbar.png) |  |
| `\textbardbl` | `\text{\textbardbl}` | ![](renders/textbardbl.png) |  |
| `\textbf` | `\textbf{AaBb123}` | ![](renders/textbf.png) |  |
| `\textbraceleft` | `\text{\textbraceleft}` | ![](renders/textbraceleft.png) |  |
| `\textbraceright` | `\text{\textbraceright}` | ![](renders/textbraceright.png) |  |
| `\textcircled` | `\text{\textcircled a}` | ![](renders/textcircled.png) |  |
| `\textcopyright` | `\textcopyright` | ![](renders/textcopyright.png) |  |
| `\textcolor` | `\textcolor{blue}{F=ma}` | ![](renders/textcolor.png) |  |
| `\textdagger` | `\text{\textdagger}` | ![](renders/textdagger.png) |  |
| `\textdaggerdbl` | `\text{\textdaggerdbl}` | ![](renders/textdaggerdbl.png) |  |
| `\textdegree` | `\text{\textdegree}` | ![](renders/textdegree.png) |  |
| `\textdollar` | `\text{\textdollar}` | ![](renders/textdollar.png) |  |
| `\textellipsis` | `\text{\textellipsis}` | ![](renders/textellipsis.png) |  |
| `\textemdash` | `\text{\textemdash}` | ![](renders/textemdash.png) |  |
| `\textendash` | `\text{\textendash}` | ![](renders/textendash.png) |  |
| `\textgreater` | `\text{\textgreater}` | ![](renders/textgreater.png) |  |
| `\textit` | `\textit{AaBb}` | ![](renders/textit.png) |  |
| `\textless` | `\text{\textless}` | ![](renders/textless.png) |  |
| `\textmd` | `\textmd{AaBb123}` | ![](renders/textmd.png) |  |
| `\textnormal` | `\textnormal{AB}` | ![](renders/textnormal.png) |  |
| `\TextOrMath` | `\TextOrMath{a}{b}` | ![](renders/textormath.png) |  |
| `\textquotedblleft` | `\text{\textquotedblleft}` | ![](renders/textquotedblleft.png) |  |
| `\textquotedblright` | `\text{\textquotedblright}` | ![](renders/textquotedblright.png) |  |
| `\textquoteleft` | `\text{\textquoteleft}` | ![](renders/textquoteleft.png) |  |
| `\textquoteright` | `\text{\textquoteright}` | ![](renders/textquoteright.png) |  |
| `\textregistered` | `\text{\textregistered}` | ![](renders/textregistered.png) |  |
| `\textrm` | `\textrm{AaBb123}` | ![](renders/textrm.png) |  |
| `\textsc` | — | — | goldens: rej-unsup-textsc |
| `\textsf` | `\textsf{AaBb123}` | ![](renders/textsf.png) |  |
| `\textsl` | — | — | goldens: textsl |
| `\textsterling` | `\text{\textsterling}` | ![](renders/textsterling.png) |  |
| `\textstyle` | `\textstyle\sum_0^n` | ![](renders/textstyle.png) |  |
| `\texttip` | — | — | goldens: rej-unsup-texttip |
| `\texttt` | `\texttt{AaBb123}` | ![](renders/texttt.png) |  |
| `\textunderscore` | `\text{\textunderscore}` | ![](renders/textunderscore.png) |  |
| `\textup` | `\textup{AaBb123}` | ![](renders/textup.png) |  |
| `\textvisiblespace` | — | — | goldens: rej-unsup-textvisiblespace |
| `\tfrac` | `\tfrac ab` | ![](renders/tfrac.png) |  |
| `\tg` | `\tg` | ![](renders/tg.png) |  |
| `\th` | `\th` | ![](renders/th.png) |  |
| `\therefore` | `\therefore` | ![](renders/therefore.png) |  |
| `\Theta` | `\Theta` | ![](renders/theta.png) |  |
| `\theta` | `\theta` | ![](renders/theta-2.png) |  |
| `\thetasym` | `\thetasym` | ![](renders/thetasym.png) |  |
| `\thickapprox` | `\thickapprox` | ![](renders/thickapprox.png) |  |
| `\thicksim` | `\thicksim` | ![](renders/thicksim.png) |  |
| `\thickspace` | `a\thickspace b` | ![](renders/thickspace.png) |  |
| `\thinspace` | `a\thinspace b` | ![](renders/thinspace.png) |  |
| `\tilde` | `\tilde M` | ![](renders/tilde-3.png) |  |
| `\times` | `\times` | ![](renders/times.png) |  |
| `\Tiny` | — | — | goldens: rej-unsup-tiny |
| `\tiny` | `\tiny tiny` | ![](renders/tiny.png) |  |
| `\to` | `\to` | ![](renders/to.png) |  |
| `\toggle` | — | — | goldens: rej-unsup-toggle |
| `\top` | `\top` | ![](renders/top.png) |  |
| `\triangle` | `\triangle` | ![](renders/triangle.png) |  |
| `\triangledown` | `\triangledown` | ![](renders/triangledown.png) |  |
| `\triangleleft` | `\triangleleft` | ![](renders/triangleleft.png) |  |
| `\trianglelefteq` | `\trianglelefteq` | ![](renders/trianglelefteq.png) |  |
| `\triangleq` | `\triangleq` | ![](renders/triangleq.png) |  |
| `\triangleright` | `\triangleright` | ![](renders/triangleright.png) |  |
| `\trianglerighteq` | `\trianglerighteq` | ![](renders/trianglerighteq.png) |  |
| `\tt` | `{\tt AaBb123}` | ![](renders/tt.png) |  |
| `\twoheadleftarrow` | `\twoheadleftarrow` | ![](renders/twoheadleftarrow.png) |  |
| `\twoheadrightarrow` | `\twoheadrightarrow` | ![](renders/twoheadrightarrow.png) |  |

## U

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\u` | `\text{\u{a}}` | ![](renders/u.png) |  |
| `\Uarr` | `\Uarr` | ![](renders/uarr.png) |  |
| `\uArr` | `\uArr` | ![](renders/uarr-2.png) |  |
| `\uarr` | `\uarr` | ![](renders/uarr-3.png) |  |
| `\ulcorner` | `\ulcorner` | ![](renders/ulcorner.png) |  |
| `\underbar` | `\underbar{X}` | ![](renders/underbar.png) |  |
| `\underbrace` | `\underbrace{x+⋯+x}_{n\text{ times}}` | ![](renders/underbrace.png) |  |
| `\underbracket` | `\underbracket{x+⋯+x}_{n\text{ times}}` | ![](renders/underbracket.png) |  |
| `\undergroup` | `\undergroup{AB}` | ![](renders/undergroup.png) |  |
| `\underleftarrow` | `\underleftarrow{AB}` | ![](renders/underleftarrow.png) |  |
| `\underleftrightarrow` | `\underleftrightarrow{AB}` | ![](renders/underleftrightarrow.png) |  |
| `\underrightarrow` | `\underrightarrow{AB}` | ![](renders/underrightarrow.png) |  |
| `\underline` | `\underline{\text{a long argument}}` | ![](renders/underline.png) |  |
| `\underlinesegment` | `\underlinesegment{AB}` | ![](renders/underlinesegment.png) |  |
| `\underparen` | — | — | goldens: rej-unsup-underparen |
| `\underset` | `\underset{!}{=}` | ![](renders/underset.png) |  |
| `\unicode` | — | — | goldens: rej-unsup-unicode |
| `\unlhd` | `\unlhd` | ![](renders/unlhd.png) |  |
| `\unrhd` | `\unrhd` | ![](renders/unrhd.png) |  |
| `\up` | — | — | goldens: rej-unsup-up |
| `\Uparrow` | `\Uparrow` | ![](renders/uparrow.png) |  |
| `\uparrow` | `\uparrow` | ![](renders/uparrow-2.png) |  |
| `\Updownarrow` | `\Updownarrow` | ![](renders/updownarrow.png) |  |
| `\updownarrow` | `\updownarrow` | ![](renders/updownarrow-2.png) |  |
| `\upharpoonleft` | `\upharpoonleft` | ![](renders/upharpoonleft.png) |  |
| `\upharpoonright` | `\upharpoonright` | ![](renders/upharpoonright.png) |  |
| `\uplus` | `\uplus` | ![](renders/uplus.png) |  |
| `\uproot` | — | — | goldens: rej-unsup-uproot |
| `\upshape` | — | — | goldens: rej-unsup-upshape |
| `\Upsilon` | `\Upsilon` | ![](renders/upsilon.png) |  |
| `\upsilon` | `\upsilon` | ![](renders/upsilon-2.png) |  |
| `\upuparrows` | `\upuparrows` | ![](renders/upuparrows.png) |  |
| `\urcorner` | `\urcorner` | ![](renders/urcorner.png) |  |
| `\url` | `\url{https://katex.org/}` | ![](renders/url.png) |  |
| `\utilde` | `\utilde{AB}` | ![](renders/utilde.png) |  |

## V

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\v` | `\text{\v{a}}` | ![](renders/v.png) |  |
| `\varcoppa` | — | — | goldens: rej-unsup-varcoppa |
| `\varDelta` | `\varDelta` | ![](renders/vardelta.png) |  |
| `\varepsilon` | `\varepsilon` | ![](renders/varepsilon.png) |  |
| `\varGamma` | `\varGamma` | ![](renders/vargamma.png) |  |
| `\varinjlim` | `\varinjlim` | ![](renders/varinjlim.png) |  |
| `\varkappa` | `\varkappa` | ![](renders/varkappa.png) |  |
| `\varLambda` | `\varLambda` | ![](renders/varlambda.png) |  |
| `\varliminf` | `\varliminf` | ![](renders/varliminf.png) |  |
| `\varlimsup` | `\varlimsup` | ![](renders/varlimsup.png) |  |
| `\varnothing` | `\varnothing` | ![](renders/varnothing.png) |  |
| `\varOmega` | `\varOmega` | ![](renders/varomega.png) |  |
| `\varPhi` | `\varPhi` | ![](renders/varphi.png) |  |
| `\varphi` | `\varphi` | ![](renders/varphi-2.png) |  |
| `\varPi` | `\varPi` | ![](renders/varpi.png) |  |
| `\varpi` | `\varpi` | ![](renders/varpi-2.png) |  |
| `\varprojlim` | `\varprojlim` | ![](renders/varprojlim.png) |  |
| `\varpropto` | `\varpropto` | ![](renders/varpropto.png) |  |
| `\varPsi` | `\varPsi` | ![](renders/varpsi.png) |  |
| `\varrho` | `\varrho` | ![](renders/varrho.png) |  |
| `\varSigma` | `\varSigma` | ![](renders/varsigma.png) |  |
| `\varsigma` | `\varsigma` | ![](renders/varsigma-2.png) |  |
| `\varstigma` | — | — | goldens: rej-unsup-varstigma |
| `\varsubsetneq` | `\varsubsetneq` | ![](renders/varsubsetneq.png) |  |
| `\varsubsetneqq` | `\varsubsetneqq` | ![](renders/varsubsetneqq.png) |  |
| `\varsupsetneq` | `\varsupsetneq` | ![](renders/varsupsetneq.png) |  |
| `\varsupsetneqq` | `\varsupsetneqq` | ![](renders/varsupsetneqq.png) |  |
| `\varTheta` | `\varTheta` | ![](renders/vartheta.png) |  |
| `\vartheta` | `\vartheta` | ![](renders/vartheta-2.png) |  |
| `\vartriangle` | `\vartriangle` | ![](renders/vartriangle.png) |  |
| `\vartriangleleft` | `\vartriangleleft` | ![](renders/vartriangleleft.png) |  |
| `\vartriangleright` | `\vartriangleright` | ![](renders/vartriangleright.png) |  |
| `\varUpsilon` | `\varUpsilon` | ![](renders/varupsilon.png) |  |
| `\varXi` | `\varXi` | ![](renders/varxi.png) |  |
| `\vcentcolon` | `\mathrel{\vcentcolon =}` | ![](renders/vcentcolon.png) |  |
| `\vcenter` | `a+\left(\vcenter{\frac{\frac a b}c}\right)` | ![](renders/vcenter.png) |  |
| `\Vdash` | `\Vdash` | ![](renders/vdash.png) |  |
| `\vDash` | `\vDash` | ![](renders/vdash-2.png) |  |
| `\vdash` | `\vdash` | ![](renders/vdash-3.png) |  |
| `\vdots` | `\vdots` | ![](renders/vdots.png) |  |
| `\vec` | `\vec{F}` | ![](renders/vec.png) |  |
| `\vee` | `\vee` | ![](renders/vee.png) |  |
| `\veebar` | `\veebar` | ![](renders/veebar.png) |  |
| `\verb` | `\verb!\frac a b!` | ![](renders/verb.png) |  |
| `\verb*` | `\verb*&#124;a b&#124;` | ![](renders/verbstar.png) |  |
| `\Vert` | `\Vert` | ![](renders/vert.png) |  |
| `\vert` | `\vert` | ![](renders/vert-2.png) |  |
| `\vfil` | — | — | goldens: rej-unsup-vfil |
| `\vfill` | — | — | goldens: rej-unsup-vfill |
| `\vline` | — | — | goldens: rej-unsup-vline |
| `{Vmatrix}` | `\begin{Vmatrix}\na & b \\\nc & d\n\end{Vmatrix}` | ![](renders/vmatrix.png) |  |
| `{Vmatrix*}` | `\begin{Vmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{Vmatrix*}` | ![](renders/vmatrixstar.png) |  |
| `{vmatrix}` | `\begin{vmatrix}\na & b \\\nc & d\n\end{vmatrix}` | ![](renders/vmatrix-2.png) |  |
| `{vmatrix*}` | `\begin{vmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{vmatrix*}` | ![](renders/vmatrixstar-2.png) |  |
| `\vphantom` | `\overline{\vphantom{M}a}` | ![](renders/vphantom.png) |  |
| `\Vvdash` | `\Vvdash` | ![](renders/vvdash.png) |  |

## W

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\wedge` | `\wedge` | ![](renders/wedge.png) |  |
| `\weierp` | `\weierp` | ![](renders/weierp.png) |  |
| `\widecheck` | `\widecheck{AB}` | ![](renders/widecheck.png) |  |
| `\widehat` | `\widehat{AB}` | ![](renders/widehat.png) |  |
| `\wideparen` | — | — | goldens: rej-unsup-wideparen |
| `\widetilde` | `\widetilde{AB}` | ![](renders/widetilde.png) |  |
| `\wp` | `\wp` | ![](renders/wp.png) |  |
| `\wr` | `\wr` | ![](renders/wr.png) |  |

## X

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\xcancel` | `\xcancel{ABC}` | ![](renders/xcancel.png) |  |
| `\xdef` | `\def\foo{a}\xdef\fcopy{\foo}\def\foo{}\fcopy` | ![](renders/xdef.png) |  |
| `\Xi` | `\Xi` | ![](renders/xi.png) |  |
| `\xi` | `\xi` | ![](renders/xi-2.png) |  |
| `\xhookleftarrow` | `\xhookleftarrow{abc}` | ![](renders/xhookleftarrow.png) |  |
| `\xhookrightarrow` | `\xhookrightarrow{abc}` | ![](renders/xhookrightarrow.png) |  |
| `\xLeftarrow` | `\xLeftarrow{abc}` | ![](renders/xleftarrow.png) |  |
| `\xleftarrow` | `\xleftarrow{abc}` | ![](renders/xleftarrow-2.png) |  |
| `\xleftharpoondown` | `\xleftharpoondown{abc}` | ![](renders/xleftharpoondown.png) |  |
| `\xleftharpoonup` | `\xleftharpoonup{abc}` | ![](renders/xleftharpoonup.png) |  |
| `\xLeftrightarrow` | `\xLeftrightarrow{abc}` | ![](renders/xleftrightarrow.png) |  |
| `\xleftrightarrow` | `\xleftrightarrow{abc}` | ![](renders/xleftrightarrow-2.png) |  |
| `\xleftrightharpoons` | `\xleftrightharpoons{abc}` | ![](renders/xleftrightharpoons.png) |  |
| `\xlongequal` | `\xlongequal{abc}` | ![](renders/xlongequal.png) |  |
| `\xmapsto` | `\xmapsto{abc}` | ![](renders/xmapsto.png) |  |
| `\xRightarrow` | `\xRightarrow{abc}` | ![](renders/xrightarrow.png) |  |
| `\xrightarrow` | `\xrightarrow{abc}` | ![](renders/xrightarrow-2.png) |  |
| `\xrightharpoondown` | `\xrightharpoondown{abc}` | ![](renders/xrightharpoondown.png) |  |
| `\xrightharpoonup` | `\xrightharpoonup{abc}` | ![](renders/xrightharpoonup.png) |  |
| `\xrightleftharpoons` | `\xrightleftharpoons{abc}` | ![](renders/xrightleftharpoons.png) |  |
| `\xtofrom` | `\xtofrom{abc}` | ![](renders/xtofrom.png) |  |
| `\xtwoheadleftarrow` | `\xtwoheadleftarrow{abc}` | ![](renders/xtwoheadleftarrow.png) |  |
| `\xtwoheadrightarrow` | `\xtwoheadrightarrow{abc}` | ![](renders/xtwoheadrightarrow.png) |  |

## YZ

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\yen` | `\yen` | ![](renders/yen.png) |  |
| `\Z` | `\Z` | ![](renders/z.png) |  |
| `\Zeta` | `\Zeta` | ![](renders/zeta.png) |  |
| `\zeta` | `\zeta` | ![](renders/zeta-2.png) |  |

