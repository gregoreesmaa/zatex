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
| `\(…\)` | `\text{\(\frac a b\)}` | *no render (overclaim)* | inline-math delimiters, not math-mode input; pinned KaTeX rejects inside math |
| `\ ` | `a\ b` | ![](renders/ctrlspace.png) |  |
| `\"` | `\text{\"{a}}` | ![](renders/quot.png) |  |
| `\$` | `\$` | ![](renders/dollar.png) |  |
| `\,` | `a\,\,{b}` | ![](renders/comma.png) |  |
| `\.` | `\text{\.{a}}` | ![](renders/dot.png) |  |
| `\:` | `a\:\:{b}` | ![](renders/colon.png) |  |
| `\;` | `a\n\;\;{b}` | ![](renders/semi.png) |  |
| `_` | `x_i` | ![](renders/us.png) |  |
| `\_` | `\_` | ![](renders/us-2.png) |  |
| `\`` | `\text{\`{a}}` | ![](renders/fn.png) |  |
| `<` | `<` | ![](renders/lt.png) |  |
| `\=` | `\text{\={a}}` | ![](renders/eq.png) |  |
| `>` | `>` | ![](renders/gt.png) |  |
| `\>` | — | — | owner #14 |
| `[` | `[` | ![](renders/fn-2.png) |  |
| `]` | `]` | ![](renders/fn-3.png) |  |
| `{` | `{a}` | ![](renders/fn-4.png) |  |
| `}` | `{a}` | ![](renders/fn-5.png) |  |
| `\{` | `\{` | ![](renders/fn-6.png) |  |
| `\}` | `\}` | ![](renders/fn-7.png) |  |
| `|` | `\vert` | ![](renders/pipe.png) |  |
| `\|` | `\\|x\\|` | ![](renders/pipe-2.png) |  |
| `~` | `\text{no~no~no~breaks}` | ![](renders/tilde.png) |  |
| `\~` | `\text{\~{a}}` | ![](renders/tilde-2.png) |  |
| `\\ ` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/newline.png) |  |
| `^` | `x^i` | ![](renders/pow.png) |  |
| `\^` | `\text{\^{a}}` | ![](renders/pow-2.png) |  |

## A

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\AA` | `\text{\AA}` | ![](renders/aa.png) |  |
| `\aa` | `\text{\aa}` | ![](renders/aa-2.png) |  |
| `\above` | — | — | owner #1 |
| `\abovewithdelims` | — | — | goldens: rej-unsup-abovewithdelims |
| `\acute` | `\acute e` | ![](renders/acute.png) |  |
| `\AE` | `\text{\AE}` | ![](renders/ae.png) |  |
| `\ae` | `\text{\ae}` | ![](renders/ae-2.png) |  |
| `\alef` | — | — | owner #1 |
| `\alefsym` | — | — | owner #1 |
| `\aleph` | `\aleph` | ![](renders/aleph.png) |  |
| `{align}` | `\begin{align}\na&=b+c \\\nd+e&=f\n\end{align}` | *no render (overclaim)* | pinned KaTeX rejects unstarred align; table needs a reject row |
| `{align*}` | `\begin{align*}\na&=b+c \\\nd+e&=f\n\end{align*}` | *no render (engine)* | top-level align missing; KaTeX accepts |
| `{aligned}` | `\begin{aligned}\na&=b+c \\\nd+e&=f\n\end{aligned}` | ![](renders/aligned.png) |  |
| `{alignat}` | `\begin{alignat}{2}\n10&x+ &3&y = 2 \\\n 3&x+&13&y = 4\n\end{alignat}` | *no render (engine)* | top-level alignat missing (alignedat works); KaTeX accepts |
| `{alignat*}` | `\begin{alignat*}{2}\n10&x+ &3&y = 2 \\\n 3&x+&13&y = 4\n\end{alignat*}` | *no render (engine)* | top-level alignat missing; KaTeX accepts |
| `{alignedat}` | `\begin{alignedat}{2}\n10&x+ &3&y = 2 \\\n 3&x+&13&y = 4\n\end{alignedat}` | ![](renders/alignedat.png) |  |
| `\allowbreak` | — | — | owner #1 |
| `\Alpha` | `\Alpha` | ![](renders/alpha.png) |  |
| `\alpha` | `\alpha` | ![](renders/alpha-2.png) |  |
| `\amalg` | `\amalg` | ![](renders/amalg.png) |  |
| `\And` | — | — | owner #1 |
| `\and` | — | — | goldens: rej-unsup-and |
| `\ang` | — | — | goldens: rej-unsup-ang |
| `\angl` | — | — | owner #1 |
| `\angln` | — | — | owner #1 |
| `\angle` | `\angle` | ![](renders/angle.png) |  |
| `\approx` | `\approx` | ![](renders/approx.png) |  |
| `\approxeq` | `\approxeq` | ![](renders/approxeq.png) |  |
| `\approxcolon` | — | — | owner #1 |
| `\approxcoloncolon` | — | — | owner #1 |
| `\arccos` | `\arccos` | ![](renders/arccos.png) |  |
| `\arcctg` | — | — | owner #1 |
| `\arcsin` | `\arcsin` | ![](renders/arcsin.png) |  |
| `\arctan` | `\arctan` | ![](renders/arctan.png) |  |
| `\arctg` | — | — | owner #1 |
| `\arg` | `\arg` | ![](renders/arg.png) |  |
| `\argmax` | — | — | owner #1 |
| `\argmin` | — | — | owner #1 |
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
| `\backepsilon` | — | — | owner #1 |
| `\backprime` | `\backprime` | ![](renders/backprime.png) |  |
| `\backsim` | — | — | owner #1 |
| `\backsimeq` | — | — | owner #1 |
| `\backslash` | `\backslash` | ![](renders/backslash.png) |  |
| `\bar` | `\bar{y}` | ![](renders/bar.png) |  |
| `\barwedge` | — | — | owner #1 |
| `\Bbb` | — | — | owner #1 |
| `\Bbbk` | — | — | owner #1 |
| `\bbox` | — | — | goldens: rej-unsup-bbox |
| `\bcancel` | — | — | owner #7 |
| `\because` | — | — | owner #1 |
| `\begin` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/begin.png) |  |
| `\begingroup` | — | — | owner #1 |
| `\Beta` | `\Beta` | ![](renders/beta.png) |  |
| `\beta` | `\beta` | ![](renders/beta-2.png) |  |
| `\beth` | `\beth` | ![](renders/beth.png) |  |
| `\between` | — | — | owner #1 |
| `\bf` | — | — | owner #1 |
| `\bfseries` | — | — | goldens: rej-unsup-bfseries |
| `\big` | `\big(\big)` | ![](renders/big.png) |  |
| `\Big` | `\Big(\Big)` | ![](renders/big-2.png) |  |
| `\bigcap` | `\bigcap` | ![](renders/bigcap.png) |  |
| `\bigcirc` | — | — | owner #1 |
| `\bigcup` | `\bigcup` | ![](renders/bigcup.png) |  |
| `\bigg` | `\bigg(\bigg)` | ![](renders/bigg.png) |  |
| `\Bigg` | `\Bigg(\Bigg)` | ![](renders/bigg-2.png) |  |
| `\biggl` | — | — | owner #4 |
| `\Biggl` | — | — | owner #4 |
| `\biggm` | `\biggm\vert` | ![](renders/biggm.png) |  |
| `\Biggm` | `\Biggm\vert` | ![](renders/biggm-2.png) |  |
| `\biggr` | — | — | owner #4 |
| `\Biggr` | — | — | owner #4 |
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
| `\bigsqcup` | — | — | owner #1 |
| `\bigstar` | — | — | owner #1 |
| `\bigtriangledown` | `\bigtriangledown` | ![](renders/bigtriangledown.png) |  |
| `\bigtriangleup` | `\bigtriangleup` | ![](renders/bigtriangleup.png) |  |
| `\biguplus` | `\biguplus` | ![](renders/biguplus.png) |  |
| `\bigvee` | `\bigvee` | ![](renders/bigvee.png) |  |
| `\bigwedge` | `\bigwedge` | ![](renders/bigwedge.png) |  |
| `\binom` | `\binom n k` | ![](renders/binom.png) |  |
| `\blacklozenge` | — | — | owner #1 |
| `\blacksquare` | — | — | owner #1 |
| `\blacktriangle` | — | — | owner #1 |
| `\blacktriangledown` | — | — | owner #1 |
| `\blacktriangleleft` | — | — | owner #1 |
| `\blacktriangleright` | — | — | owner #1 |
| `\bm` | — | — | owner #1 |
| `{Bmatrix}` | `\begin{Bmatrix}\na & b \\\nc & d\n\end{Bmatrix}` | ![](renders/bmatrix.png) |  |
| `{Bmatrix*}` | `\begin{Bmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{Bmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `{bmatrix}` | `\begin{bmatrix}\na & b \\\nc & d\n\end{bmatrix}` | ![](renders/bmatrix-2.png) |  |
| `{bmatrix*}` | `\begin{bmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{bmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\bmod` | — | — | owner #1 |
| `\bold` | — | — | owner #1 |
| `\boldsymbol` | `\boldsymbol{AaBb}` | ![](renders/boldsymbol.png) |  |
| `\bot` | `\bot` | ![](renders/bot.png) |  |
| `\bowtie` | `\bowtie` | ![](renders/bowtie.png) |  |
| `\Box` | — | — | owner #1 |
| `\boxdot` | `\boxdot` | ![](renders/boxdot.png) |  |
| `\boxed` | `\boxed{ab}` | ![](renders/boxed.png) |  |
| `\boxminus` | `\boxminus` | ![](renders/boxminus.png) |  |
| `\boxplus` | `\boxplus` | ![](renders/boxplus.png) |  |
| `\boxtimes` | `\boxtimes` | ![](renders/boxtimes.png) |  |
| `\Bra` | `\Bra{\psi}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\bra` | `\bra{\psi}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\braket` | `\braket{\phi\VERT\psi}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\Braket` | `\Braket{ ϕ \VERT \frac{∂^2}{∂ t^2} \VERT ψ }` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\brace` | — | — | owner #2 |
| `\bracevert` | — | — | goldens: rej-unsup-bracevert |
| `\brack` | — | — | owner #2 |
| `\breve` | `\breve{eu}` | ![](renders/breve.png) |  |
| `\buildrel` | — | — | goldens: rej-unsup-buildrel |
| `\bull` | — | — | owner #1 |
| `\bullet` | `\bullet` | ![](renders/bullet.png) |  |
| `\Bumpeq` | — | — | owner #1 |
| `\bumpeq` | — | — | owner #1 |

## C

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\C` | — | — | goldens: rej-unsup-c |
| `\cal` | — | — | owner #1 |
| `\cancel` | `\cancel{5}` | ![](renders/cancel.png) |  |
| `\cancelto` | — | — | goldens: rej-unsup-cancelto |
| `\Cap` | — | — | owner #1 |
| `\cap` | `\cap` | ![](renders/cap.png) |  |
| `{cases}` | `\begin{cases}\na &\text{if } b  \\\nc &\text{if } d\n\end{cases}` | ![](renders/cases.png) |  |
| `\cases` | — | — | goldens: rej-unsup-cases |
| `{CD}` | `\begin{CD}\nA  @>a>>  B  \\\n@VbVV    @AAcA \\\nC  @=     D\n\end{CD}` | *no render (overclaim)* | pinned KaTeX rejects CD; table needs a reject row |
| `\cdot` | `\cdot` | ![](renders/cdot.png) |  |
| `\cdotp` | `\cdotp` | ![](renders/cdotp.png) |  |
| `\cdots` | `\cdots` | ![](renders/cdots.png) |  |
| `\ce` | — | — | owner #1 |
| `\cee` | — | — | goldens: rej-unsup-cee |
| `\centerdot` | `a\centerdot b` | ![](renders/centerdot.png) |  |
| `\cf` | — | — | goldens: rej-unsup-cf |
| `\cfrac` | `\cfrac{2}{1+\cfrac{2}{1+\cfrac{2}{1}}}` | ![](renders/cfrac.png) |  |
| `\char` | — | — | owner #1 |
| `\check` | `\check{oe}` | ![](renders/check.png) |  |
| `\ch` | — | — | owner #1 |
| `\checkmark` | `\checkmark` | ![](renders/checkmark.png) |  |
| `\Chi` | `\Chi` | ![](renders/chi.png) |  |
| `\chi` | `\chi` | ![](renders/chi-2.png) |  |
| `\choose` | `{n+1 \choose k+2}` | ![](renders/choose.png) |  |
| `\circ` | `\circ` | ![](renders/circ.png) |  |
| `\circeq` | — | — | owner #1 |
| `\circlearrowleft` | — | — | owner #1 |
| `\circlearrowright` | — | — | owner #1 |
| `\circledast` | — | — | owner #1 |
| `\circledcirc` | — | — | owner #1 |
| `\circleddash` | — | — | owner #1 |
| `\circledR` | `\circledR` | ![](renders/circledr.png) |  |
| `\circledS` | `\circledS` | ![](renders/circleds.png) |  |
| `\class` | — | — | goldens: rej-unsup-class |
| `\cline` | — | — | goldens: rej-unsup-cline |
| `\clubs` | — | — | owner #1 |
| `\clubsuit` | `\clubsuit` | ![](renders/clubsuit.png) |  |
| `\cnums` | — | — | owner #1 |
| `\colon` | — | — | owner #1 |
| `\Colonapprox` | — | — | owner #1 |
| `\colonapprox` | — | — | owner #1 |
| `\coloncolon` | — | — | owner #1 |
| `\coloncolonapprox` | — | — | owner #1 |
| `\coloncolonequals` | — | — | owner #1 |
| `\coloncolonminus` | — | — | owner #1 |
| `\coloncolonsim` | — | — | owner #1 |
| `\Coloneq` | — | — | owner #1 |
| `\coloneq` | — | — | owner #1 |
| `\colonequals` | — | — | owner #1 |
| `\Coloneqq` | — | — | owner #1 |
| `\coloneqq` | — | — | owner #1 |
| `\colonminus` | — | — | owner #1 |
| `\Colonsim` | — | — | owner #1 |
| `\colonsim` | — | — | owner #1 |
| `\color` | `\color{#0000FF} AaBb123` | ![](renders/color.png) |  |
| `\colorbox` | `\colorbox{red}{Black on red}` | ![](renders/colorbox.png) |  |
| `\complement` | — | — | owner #1 |
| `\Complex` | — | — | owner #1 |
| `\cong` | `\cong` | ![](renders/cong.png) |  |
| `\Coppa` | — | — | goldens: rej-unsup-coppa |
| `\coppa` | — | — | goldens: rej-unsup-coppa-2 |
| `\coprod` | `\coprod` | ![](renders/coprod.png) |  |
| `\copyright` | — | — | owner #1 |
| `\cos` | `\cos` | ![](renders/cos.png) |  |
| `\cosec` | — | — | owner #1 |
| `\cosh` | `\cosh` | ![](renders/cosh.png) |  |
| `\cot` | `\cot` | ![](renders/cot.png) |  |
| `\cotg` | — | — | owner #1 |
| `\coth` | `\coth` | ![](renders/coth.png) |  |
| `\cr` | `\begin{matrix}\na & b \cr\nc & d\n\end{matrix}` | *no render (engine)* | in-matrix \cr exhausts buffers (NoSpace); KaTeX accepts |
| `\csc` | `\csc` | ![](renders/csc.png) |  |
| `\cssId` | — | — | goldens: rej-unsup-cssid |
| `\ctg` | — | — | owner #1 |
| `\cth` | — | — | owner #1 |
| `\Cup` | — | — | owner #1 |
| `\cup` | `\cup` | ![](renders/cup.png) |  |
| `\curlyeqprec` | — | — | owner #1 |
| `\curlyeqsucc` | — | — | owner #1 |
| `\curlyvee` | — | — | owner #1 |
| `\curlywedge` | — | — | owner #1 |
| `\curvearrowleft` | — | — | owner #1 |
| `\curvearrowright` | — | — | owner #1 |

## D

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\dag` | `\dag` | ![](renders/dag.png) |  |
| `\Dagger` | — | — | owner #1 |
| `\dagger` | `\dagger` | ![](renders/dagger.png) |  |
| `\daleth` | `\daleth` | ![](renders/daleth.png) |  |
| `\Darr` | — | — | owner #1 |
| `\dArr` | — | — | owner #1 |
| `\darr` | — | — | owner #1 |
| `\dashleftarrow` | — | — | owner #1 |
| `\dashrightarrow` | — | — | owner #1 |
| `\dashv` | `\dashv` | ![](renders/dashv.png) |  |
| `\dbinom` | `\dbinom n k` | ![](renders/dbinom.png) |  |
| `\dblcolon` | — | — | owner #1 |
| `{dcases}` | `\begin{dcases}\na &\text{if } b  \\\nc &\text{if } d\n\end{dcases}` | *no render (engine)* | display cases missing; KaTeX accepts |
| `\ddag` | `\ddag` | ![](renders/ddag.png) |  |
| `\ddagger` | `\ddagger` | ![](renders/ddagger.png) |  |
| `\ddddot` | `\ddddot x` | ![](renders/ddddot.png) |  |
| `\dddot` | `\dddot x` | ![](renders/dddot.png) |  |
| `\ddot` | `\ddot x` | ![](renders/ddot.png) |  |
| `\ddots` | `\ddots` | ![](renders/ddots.png) |  |
| `\DeclareMathOperator` | — | — | reject rows: rej-declare-op |
| `\def` | `\def\foo{x^2} \foo + \foo` | ![](renders/def.png) |  |
| `\definecolor` | — | — | reject rows: definecolor |
| `\deg` | `\deg` | ![](renders/deg.png) |  |
| `\degree` | — | — | owner #1 |
| `\delta` | `\delta` | ![](renders/delta.png) |  |
| `\Delta` | `\Delta` | ![](renders/delta-2.png) |  |
| `\det` | `\det` | ![](renders/det.png) |  |
| `\Digamma` | — | — | goldens: rej-unsup-digamma |
| `\digamma` | `\digamma` | ![](renders/digamma.png) |  |
| `\dfrac` | `\dfrac{a-1}{b-1}` | ![](renders/dfrac.png) |  |
| `\diagdown` | — | — | owner #1 |
| `\diagup` | — | — | owner #1 |
| `\Diamond` | — | — | owner #1 |
| `\diamond` | `\diamond` | ![](renders/diamond.png) |  |
| `\diamonds` | — | — | owner #1 |
| `\diamondsuit` | `\diamondsuit` | ![](renders/diamondsuit.png) |  |
| `\dim` | `\dim` | ![](renders/dim.png) |  |
| `\displaylines` | — | — | goldens: rej-unsup-displaylines |
| `\displaystyle` | `\displaystyle\sum_0^n` | ![](renders/displaystyle.png) |  |
| `\div` | `\div` | ![](renders/div.png) |  |
| `\divideontimes` | — | — | owner #1 |
| `\dot` | `\dot x` | ![](renders/dot-2.png) |  |
| `\Doteq` | — | — | owner #1 |
| `\doteq` | `\doteq` | ![](renders/doteq.png) |  |
| `\doteqdot` | — | — | owner #1 |
| `\dotplus` | — | — | owner #1 |
| `\dots` | `x_1 + \dots + x_n` | ![](renders/dots.png) |  |
| `\dotsb` | — | — | owner #1 |
| `\dotsc` | — | — | owner #1 |
| `\dotsi` | `\int_{A_1}\int_{A_2}\dotsi` | *no render (engine)* | dotsi alias missing from symbol table; KaTeX accepts |
| `\dotsm` | — | — | owner #1 |
| `\dotso` | — | — | owner #1 |
| `\doublebarwedge` | — | — | owner #1 |
| `\doublecap` | — | — | owner #1 |
| `\doublecup` | — | — | owner #1 |
| `\Downarrow` | `\Downarrow` | ![](renders/downarrow.png) |  |
| `\downarrow` | `\downarrow` | ![](renders/downarrow-2.png) |  |
| `\downdownarrows` | — | — | owner #1 |
| `\downharpoonleft` | — | — | owner #1 |
| `\downharpoonright` | — | — | owner #1 |
| `{drcases}` | `\begin{drcases}\na &\text{if } b  \\\nc &\text{if } d\n\end{drcases}` | *no render (engine)* | display right-cases missing; KaTeX accepts |

## E

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\edef` | `\def\foo{a}\edef\fcopy{\foo}\def\foo{}\fcopy` | *no render (engine)* | edef macro definition missing; KaTeX accepts |
| `\ell` | `\ell` | ![](renders/ell.png) |  |
| `\else` | — | — | goldens: rej-unsup-else |
| `\em` | — | — | goldens: rej-unsup-em |
| `\emph` | — | — | owner #7 |
| `\empty` | — | — | owner #1 |
| `\emptyset` | `\emptyset` | ![](renders/emptyset.png) |  |
| `\enclose` | — | — | goldens: rej-unsup-enclose |
| `\end` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/end.png) |  |
| `\endgroup` | — | — | owner #1 |
| `\enspace` | — | — | owner #1 |
| `\Epsilon` | `\Epsilon` | ![](renders/epsilon.png) |  |
| `\epsilon` | `\epsilon` | ![](renders/epsilon-2.png) |  |
| `\eqalign` | — | — | goldens: rej-unsup-eqalign |
| `\eqalignno` | — | — | goldens: rej-unsup-eqalignno |
| `\eqcirc` | `\eqcirc` | ![](renders/eqcirc.png) |  |
| `\Eqcolon` | — | — | owner #1 |
| `\eqcolon` | — | — | owner #1 |
| `{equation}` | `\begin{equation}\na = b + c\n\end{equation}` | *no render (overclaim)* | pinned KaTeX rejects equation; table needs a reject row |
| `{equation*}` | `\begin{equation*}\na = b + c\n\end{equation*}` | *no render (overclaim)* | pinned KaTeX rejects equation*; table needs a reject row |
| `{eqnarray}` | — | — | goldens: rej-unsup-eqnarray |
| `\Eqqcolon` | — | — | owner #1 |
| `\eqqcolon` | — | — | owner #1 |
| `\eqref` | — | — | goldens: rej-unsup-eqref |
| `\eqsim` | — | — | owner #1 |
| `\eqslantgtr` | — | — | owner #1 |
| `\eqslantless` | — | — | owner #1 |
| `\equalscolon` | — | — | owner #1 |
| `\equalscoloncolon` | — | — | owner #1 |
| `\equiv` | `\equiv` | ![](renders/equiv.png) |  |
| `\Eta` | `\Eta` | ![](renders/eta.png) |  |
| `\eta` | `\eta` | ![](renders/eta-2.png) |  |
| `\eth` | `\eth` | ![](renders/eth.png) |  |
| `\euro` | — | — | goldens: rej-unsup-euro |
| `\exist` | — | — | owner #1 |
| `\exists` | `\exists` | ![](renders/exists.png) |  |
| `\exp` | `\exp` | ![](renders/exp.png) |  |
| `\expandafter` | — | — | owner #1 |

## F

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\fallingdotseq` | — | — | owner #1 |
| `\fbox` | — | — | owner #7 |
| `\fcolorbox` | `\fcolorbox{red}{aqua}{A}` | ![](renders/fcolorbox.png) |  |
| `\fi` | — | — | goldens: rej-unsup-fi |
| `\Finv` | `\Finv` | ![](renders/finv.png) |  |
| `\flat` | `\flat` | ![](renders/flat.png) |  |
| `\footnotesize` | — | — | owner #1 |
| `\forall` | `\forall` | ![](renders/forall.png) |  |
| `\frac` | `\frac a b` | ![](renders/frac.png) |  |
| `\frak` | — | — | owner #1 |
| `\frown` | `\frown` | ![](renders/frown.png) |  |
| `\futurelet` | — | — | owner #7 |

## G

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\Game` | `\Game` | ![](renders/game.png) |  |
| `\Gamma` | `\Gamma` | ![](renders/gamma.png) |  |
| `\gamma` | `\gamma` | ![](renders/gamma-2.png) |  |
| `{gather}` | `\begin{gather}\na=b \\ \ne=b+c\n\end{gather}` | *no render (overclaim)* | pinned KaTeX rejects gather; table needs a reject row |
| `{gathered}` | `\begin{gathered}\na=b \\ \ne=b+c\n\end{gathered}` | ![](renders/gathered.png) |  |
| `\gcd` | `\gcd` | ![](renders/gcd.png) |  |
| `\gdef` | `\gdef\sqr#1{#1^2} \sqr{y} + \sqr{y}` | ![](renders/gdef.png) |  |
| `\ge` | `\ge` | ![](renders/ge.png) |  |
| `\geneuro` | — | — | goldens: rej-unsup-geneuro |
| `\geneuronarrow` | — | — | goldens: rej-unsup-geneuronarrow |
| `\geneurowide` | — | — | goldens: rej-unsup-geneurowide |
| `\genfrac` | `\genfrac ( ] {2pt}{0}a{a+1}` | ![](renders/genfrac.png) |  |
| `\geq` | `\geq` | ![](renders/geq.png) |  |
| `\geqq` | — | — | owner #1 |
| `\geqslant` | — | — | owner #1 |
| `\gets` | `\gets` | ![](renders/gets.png) |  |
| `\gg` | `\gg` | ![](renders/gg.png) |  |
| `\ggg` | `\ggg` | ![](renders/ggg.png) |  |
| `\gggtr` | — | — | owner #1 |
| `\gimel` | `\gimel` | ![](renders/gimel.png) |  |
| `\global` | `\global\def\add#1#2{#1+#2} \add 2 3` | *no render (engine)* | global prefix missing; KaTeX accepts |
| `\gnapprox` | — | — | owner #1 |
| `\gneq` | — | — | owner #1 |
| `\gneqq` | — | — | owner #1 |
| `\gnsim` | — | — | owner #1 |
| `\grave` | `\grave{eu}` | ![](renders/grave.png) |  |
| `\gt` | — | — | owner #1 |
| `\gtrdot` | — | — | owner #1 |
| `\gtrapprox` | `\gtrapprox` | ![](renders/gtrapprox.png) |  |
| `\gtreqless` | — | — | owner #1 |
| `\gtreqqless` | — | — | owner #1 |
| `\gtrless` | — | — | owner #1 |
| `\gtrsim` | `\gtrsim` | ![](renders/gtrsim.png) |  |
| `\gvertneqq` | — | — | owner #1 |

## H

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\H` | `\text{\H{a}}` | ![](renders/h.png) |  |
| `\Harr` | — | — | owner #1 |
| `\hArr` | — | — | owner #1 |
| `\harr` | — | — | owner #1 |
| `\hat` | `\hat{\theta}` | ![](renders/hat.png) |  |
| `\hbar` | `\hbar` | ![](renders/hbar.png) |  |
| `\hbox` | — | — | owner #7 |
| `\hbox to <dimen>` | — | — | KaTeX accepts (sweep-proven); owner #7 |
| `\hdashline` | `\begin{matrix}\na & b \\\n\hdashline\nc & d\n\end{matrix}` | ![](renders/hdashline.png) |  |
| `\hearts` | — | — | owner #1 |
| `\heartsuit` | `\heartsuit` | ![](renders/heartsuit.png) |  |
| `\hfil` | — | — | goldens: rej-unsup-hfil |
| `\hfill` | — | — | goldens: rej-unsup-hfill |
| `\hline` | `\begin{matrix}\na & b \\ \hline\nc & d\n\end{matrix}` | ![](renders/hline.png) |  |
| `\hom` | `\hom` | ![](renders/hom.png) |  |
| `\hookleftarrow` | `\hookleftarrow` | ![](renders/hookleftarrow.png) |  |
| `\hookrightarrow` | `\hookrightarrow` | ![](renders/hookrightarrow.png) |  |
| `\hphantom` | — | — | owner #7 |
| `\href` | `\href{https://katex.org/}{\KaTeX}` | *no render (engine)* | \KaTeX logo command missing; KaTeX accepts |
| `\hskip` | — | — | owner #1 |
| `\hslash` | `\hslash` | ![](renders/hslash.png) |  |
| `\hspace` | `s\hspace7ex k` | ![](renders/hspace.png) |  |
| `\htmlClass` | — | — | owner #7 |
| `\htmlData` | — | — | owner #7 |
| `\htmlId` | — | — | owner #7 |
| `\htmlStyle` | — | — | owner #7 |
| `\huge` | — | — | owner #1 |
| `\Huge` | — | — | owner #1 |

## I

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\i` | `\text{\i}` | ![](renders/i.png) |  |
| `\idotsint` | — | — | goldens: rej-unsup-idotsint |
| `\iddots` | — | — | goldens: rej-unsup-iddots |
| `\if` | — | — | goldens: rej-unsup-if |
| `\iff` | — | — | owner #1 |
| `\ifmode` | — | — | goldens: rej-unsup-ifmode |
| `\ifx` | — | — | goldens: rej-unsup-ifx |
| `\iiiint` | — | — | goldens: rej-unsup-iiiint |
| `\iiint` | `\iiint` | ![](renders/iiint.png) |  |
| `\iint` | `\iint` | ![](renders/iint.png) |  |
| `\Im` | `\Im` | ![](renders/im.png) |  |
| `\image` | — | — | owner #1 |
| `\imageof` | — | — | owner #1 |
| `\imath` | `\imath` | ![](renders/imath.png) |  |
| `\impliedby` | — | — | owner #1 |
| `\implies` | — | — | owner #1 |
| `\in` | `\in` | ![](renders/in.png) |  |
| `\includegraphics` | — | — | owner #7 |
| `\inf` | `\inf` | ![](renders/inf.png) |  |
| `\infin` | — | — | owner #1 |
| `\infty` | `\infty` | ![](renders/infty.png) |  |
| `\injlim` | — | — | owner #1 |
| `\int` | `\int` | ![](renders/int.png) |  |
| `\intercal` | — | — | owner #1 |
| `\intop` | — | — | owner #1 |
| `\Iota` | `\Iota` | ![](renders/iota.png) |  |
| `\iota` | `\iota` | ![](renders/iota-2.png) |  |
| `\isin` | — | — | owner #1 |
| `\it` | — | — | owner #1 |
| `\itshape` | — | — | goldens: rej-unsup-itshape |

## JK

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\j` | `\text{\j}` | ![](renders/j.png) |  |
| `\jmath` | `\jmath` | ![](renders/jmath.png) |  |
| `\Join` | `\Join` | ![](renders/join.png) |  |
| `\Kappa` | `\Kappa` | ![](renders/kappa.png) |  |
| `\kappa` | `\kappa` | ![](renders/kappa-2.png) |  |
| `\KaTeX` | — | — | owner #1 |
| `\ker` | `\ker` | ![](renders/ker.png) |  |
| `\kern` | `I\kern-2.5pt R` | ![](renders/kern.png) |  |
| `\Ket` | `\Ket{\psi}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\ket` | `\ket{\psi}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
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
| `\Larr` | — | — | owner #1 |
| `\lArr` | — | — | owner #1 |
| `\larr` | — | — | owner #1 |
| `\large` | — | — | owner #1 |
| `\Large` | — | — | owner #1 |
| `\LARGE` | — | — | owner #1 |
| `\LaTeX` | — | — | owner #1 |
| `\lBrace` | — | — | owner #1 |
| `\lbrace` | — | — | owner #1 |
| `\lbrack` | — | — | owner #1 |
| `\lceil` | `\lceil` | ![](renders/lceil.png) |  |
| `\ldotp` | `\ldotp` | ![](renders/ldotp.png) |  |
| `\ldots` | `\ldots` | ![](renders/ldots.png) |  |
| `\le` | `\le` | ![](renders/le.png) |  |
| `\leadsto` | — | — | owner #1 |
| `\left` | `\left\lbrace \dfrac ab \right.` | *no render (engine)* | lbrace/rbrace delimiters after \left/\right unsupported; KaTeX accepts |
| `\leftarrow` | `\leftarrow` | ![](renders/leftarrow.png) |  |
| `\Leftarrow` | `\Leftarrow` | ![](renders/leftarrow-2.png) |  |
| `\LeftArrow` | — | — | goldens: rej-unsup-leftarrow |
| `\leftarrowtail` | — | — | owner #1 |
| `\leftharpoondown` | `\leftharpoondown` | ![](renders/leftharpoondown.png) |  |
| `\leftharpoonup` | `\leftharpoonup` | ![](renders/leftharpoonup.png) |  |
| `\leftleftarrows` | — | — | owner #1 |
| `\Leftrightarrow` | `\Leftrightarrow` | ![](renders/leftrightarrow.png) |  |
| `\leftrightarrow` | `\leftrightarrow` | ![](renders/leftrightarrow-2.png) |  |
| `\leftrightarrows` | — | — | owner #1 |
| `\leftrightharpoons` | — | — | owner #1 |
| `\leftrightsquigarrow` | — | — | owner #1 |
| `\leftroot` | — | — | goldens: rej-unsup-leftroot |
| `\leftthreetimes` | — | — | owner #1 |
| `\leq` | `\leq` | ![](renders/leq.png) |  |
| `\leqalignno` | — | — | goldens: rej-unsup-leqalignno |
| `\leqq` | — | — | owner #1 |
| `\leqslant` | — | — | owner #1 |
| `\lessapprox` | `\lessapprox` | ![](renders/lessapprox.png) |  |
| `\lessdot` | — | — | owner #1 |
| `\lesseqgtr` | — | — | owner #1 |
| `\lesseqqgtr` | — | — | owner #1 |
| `\lessgtr` | — | — | owner #1 |
| `\lesssim` | `\lesssim` | ![](renders/lesssim.png) |  |
| `\let` | `\let\c=\alpha\c` | ![](renders/let.png) |  |
| `\lfloor` | `\lfloor` | ![](renders/lfloor.png) |  |
| `\lg` | `\lg` | ![](renders/lg.png) |  |
| `\lgroup` | — | — | owner #4 |
| `\lhd` | `\lhd` | ![](renders/lhd.png) |  |
| `\lim` | `\lim` | ![](renders/lim.png) |  |
| `\liminf` | `\liminf` | ![](renders/liminf.png) |  |
| `\limits` | `\lim\limits_x` | ![](renders/limits.png) |  |
| `\limsup` | `\limsup` | ![](renders/limsup.png) |  |
| `\ll` | `\ll` | ![](renders/ll.png) |  |
| `\llap` | `{=}\llap{/\,}` | ![](renders/llap.png) |  |
| `\llbracket` | — | — | owner #1 |
| `\llcorner` | `\llcorner` | ![](renders/llcorner.png) |  |
| `\Lleftarrow` | — | — | owner #1 |
| `\lll` | `\lll` | ![](renders/lll.png) |  |
| `\llless` | — | — | owner #1 |
| `\lmoustache` | — | — | owner #4 |
| `\ln` | `\ln` | ![](renders/ln.png) |  |
| `\lnapprox` | — | — | owner #1 |
| `\lneq` | — | — | owner #1 |
| `\lneqq` | — | — | owner #1 |
| `\lnot` | `\lnot` | ![](renders/lnot.png) |  |
| `\lnsim` | — | — | owner #1 |
| `\log` | `\log` | ![](renders/log.png) |  |
| `\long` | — | — | owner #7 |
| `\Longleftarrow` | `\Longleftarrow` | ![](renders/longleftarrow.png) |  |
| `\longleftarrow` | `\longleftarrow` | ![](renders/longleftarrow-2.png) |  |
| `\Longleftrightarrow` | `\Longleftrightarrow` | ![](renders/longleftrightarrow.png) |  |
| `\longleftrightarrow` | `\longleftrightarrow` | ![](renders/longleftrightarrow-2.png) |  |
| `\longmapsto` | — | — | owner #1 |
| `\Longrightarrow` | `\Longrightarrow` | ![](renders/longrightarrow.png) |  |
| `\longrightarrow` | `\longrightarrow` | ![](renders/longrightarrow-2.png) |  |
| `\looparrowleft` | — | — | owner #1 |
| `\looparrowright` | — | — | owner #1 |
| `\lor` | `\lor` | ![](renders/lor.png) |  |
| `\lower` | — | — | goldens: rej-unsup-lower |
| `\lozenge` | — | — | owner #1 |
| `\lparen` | — | — | owner #1 |
| `\Lrarr` | — | — | owner #1 |
| `\lrArr` | — | — | owner #1 |
| `\lrarr` | — | — | owner #1 |
| `\lrcorner` | `\lrcorner` | ![](renders/lrcorner.png) |  |
| `\lq` | — | — | owner #1 |
| `\Lsh` | — | — | owner #1 |
| `\lt` | — | — | owner #1 |
| `\ltimes` | — | — | owner #1 |
| `\lVert` | `\lVert` | ![](renders/lvert.png) |  |
| `\lvert` | `\lvert` | ![](renders/lvert-2.png) |  |
| `\lvertneqq` | — | — | owner #1 |

## M

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\maltese` | `\maltese` | ![](renders/maltese.png) |  |
| `\mapsfrom` | — | — | owner #1 |
| `\mapsto` | `\mapsto` | ![](renders/mapsto.png) |  |
| `\mathbb` | `\mathbb{AB}` | ![](renders/mathbb.png) |  |
| `\mathbf` | `\mathbf{AaBb123}` | ![](renders/mathbf.png) |  |
| `\mathbin` | — | — | owner #1 |
| `\mathcal` | `\mathcal{AaBb123}` | ![](renders/mathcal.png) |  |
| `\mathchoice` | `a\mathchoice{\,}{\,\,}{\,\,\,}{\,\,\,\,}b` | ![](renders/mathchoice.png) |  |
| `\mathclap` | `\sum_{\mathclap{1\le i\le n}} x_{i}` | ![](renders/mathclap.png) |  |
| `\mathclose` | — | — | owner #1 |
| `\mathellipsis` | — | — | owner #1 |
| `\mathfrak` | `\mathfrak{AaBb}` | ![](renders/mathfrak.png) |  |
| `\mathinner` | `ab\mathinner{\text{inside}}cd` | *no render (engine)* | atom-class wrappers missing; KaTeX accepts |
| `\mathit` | `\mathit{AaBb}` | ![](renders/mathit.png) |  |
| `\mathllap` | `{=}\mathllap{/\,}` | ![](renders/mathllap.png) |  |
| `\mathnormal` | — | — | owner #1 |
| `\mathop` | `\mathop{\star}_a^b` | *no render (engine)* | atom-class wrappers missing; KaTeX accepts |
| `\mathopen` | — | — | owner #1 |
| `\mathord` | — | — | owner #1 |
| `\mathpunct` | — | — | owner #1 |
| `\mathreflectbox` | — | — | owner #1 |
| `\mathrel` | `a \mathrel{\#} b` | *no render (engine)* | atom-class wrappers missing; KaTeX accepts |
| `\mathrlap` | `\mathrlap{\,/}{=}` | ![](renders/mathrlap.png) |  |
| `\mathring` | `\mathring{a}` | ![](renders/mathring.png) |  |
| `\mathrm` | `\mathrm{AaBb123}` | ![](renders/mathrm.png) |  |
| `\mathscr` | `\mathscr{AaBb123}` | ![](renders/mathscr.png) |  |
| `\mathsf` | `\mathsf{AaBb123}` | ![](renders/mathsf.png) |  |
| `\mathsterling` | — | — | owner #1 |
| `\mathstrut` | `\sqrt{\mathstrut a}` | *no render (engine)* | strut missing; KaTeX accepts |
| `\mathtip` | — | — | goldens: rej-unsup-mathtip |
| `\mathtt` | `\mathtt{AaBb123}` | ![](renders/mathtt.png) |  |
| `\matrix` | — | — | reject rows: rej-env-mismatch |
| `{matrix}` | `\begin{matrix}\na & b \\\nc & d\n\end{matrix}` | ![](renders/matrix.png) |  |
| `{matrix*}` | `\begin{matrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{matrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\max` | `\max` | ![](renders/max.png) |  |
| `\mbox` | — | — | goldens: rej-unsup-mbox |
| `\md` | — | — | goldens: rej-unsup-md |
| `\mdseries` | — | — | goldens: rej-unsup-mdseries |
| `\measuredangle` | `\measuredangle` | ![](renders/measuredangle.png) |  |
| `\medspace` | — | — | owner #1 |
| `\mho` | `\mho` | ![](renders/mho.png) |  |
| `\mid` | `\{x∈ℝ\mid x>0\}` | ![](renders/mid.png) |  |
| `\middle` | `P\left(A\middle\vert B\right)` | ![](renders/middle.png) |  |
| `\min` | `\min` | ![](renders/min.png) |  |
| `\minuscolon` | — | — | owner #1 |
| `\minuscoloncolon` | — | — | owner #1 |
| `\minuso` | — | — | owner #1 |
| `\mit` | — | — | goldens: rej-unsup-mit |
| `\mkern` | — | — | owner #1 |
| `\mmlToken` | — | — | goldens: rej-unsup-mmltoken |
| `\mod` | `3\equiv 5 \mod 2` | *no render (engine)* | mod spacing missing; KaTeX accepts |
| `\models` | `\models` | ![](renders/models.png) |  |
| `\moveleft` | — | — | goldens: rej-unsup-moveleft |
| `\moveright` | — | — | goldens: rej-unsup-moveright |
| `\mp` | `\mp` | ![](renders/mp.png) |  |
| `\mskip` | — | — | owner #1 |
| `\mspace` | — | — | goldens: rej-unsup-mspace |
| `\Mu` | `\Mu` | ![](renders/mu.png) |  |
| `\mu` | `\mu` | ![](renders/mu-2.png) |  |
| `\multicolumn` | — | — | goldens: rej-unsup-multicolumn |
| `{multiline}` | — | — | goldens: rej-unsup-multiline |
| `\multimap` | — | — | owner #1 |

## N

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\N` | — | — | owner #1 |
| `\nabla` | `\nabla` | ![](renders/nabla.png) |  |
| `\natnums` | — | — | owner #1 |
| `\natural` | `\natural` | ![](renders/natural.png) |  |
| `\negmedspace` | — | — | owner #1 |
| `\ncong` | — | — | owner #1 |
| `\ne` | `\ne` | ![](renders/ne.png) |  |
| `\nearrow` | `\nearrow` | ![](renders/nearrow.png) |  |
| `\neg` | `\neg` | ![](renders/neg.png) |  |
| `\negthickspace` | — | — | owner #1 |
| `\negthinspace` | — | — | owner #1 |
| `\neq` | `\neq` | ![](renders/neq.png) |  |
| `\newcommand` | `\newcommand\chk{\checkmark} \chk` | ![](renders/newcommand.png) |  |
| `\newenvironment` | — | — | goldens: rej-unsup-newenvironment |
| `\Newextarrow` | — | — | goldens: rej-unsup-newextarrow |
| `\newline` | — | — | owner #1 |
| `\nexists` | `\nexists` | ![](renders/nexists.png) |  |
| `\ngeq` | — | — | owner #1 |
| `\ngeqq` | — | — | owner #1 |
| `\ngeqslant` | — | — | owner #1 |
| `\ngtr` | — | — | owner #1 |
| `\ni` | `\ni` | ![](renders/ni.png) |  |
| `\nleftarrow` | — | — | owner #1 |
| `\nLeftarrow` | — | — | owner #1 |
| `\nLeftrightarrow` | — | — | owner #1 |
| `\nleftrightarrow` | — | — | owner #1 |
| `\nleq` | — | — | owner #1 |
| `\nleqq` | — | — | owner #1 |
| `\nleqslant` | — | — | owner #1 |
| `\nless` | — | — | owner #1 |
| `\nmid` | `\nmid` | ![](renders/nmid.png) |  |
| `\nobreak` | — | — | owner #1 |
| `\nobreakspace` | — | — | owner #1 |
| `\noexpand` | — | — | owner #1 |
| `\nolimits` | `\lim\nolimits_x` | ![](renders/nolimits.png) |  |
| `\nonumber` | `\begin{align}\na&=b+c \nonumber\\\nd+e&=f\n\end{align}` | *no render (engine)* | equation numbering context missing; KaTeX accepts |
| `\normalfont` | — | — | goldens: rej-unsup-normalfont |
| `\normalsize` | — | — | owner #1 |
| `\not` | `\not =` | ![](renders/not.png) |  |
| `\notag` | `\begin{align}\na&=b+c \notag\\\nd+e&=f\n\end{align}` | *no render (engine)* | equation numbering context missing; KaTeX accepts |
| `\notin` | — | — | owner #1 |
| `\notni` | — | — | owner #1 |
| `\nparallel` | — | — | owner #1 |
| `\nprec` | — | — | owner #1 |
| `\npreceq` | — | — | owner #1 |
| `\nRightarrow` | — | — | owner #1 |
| `\nrightarrow` | — | — | owner #1 |
| `\nshortmid` | — | — | owner #1 |
| `\nshortparallel` | — | — | owner #1 |
| `\nsim` | — | — | owner #1 |
| `\nsubseteq` | — | — | owner #1 |
| `\nsubseteqq` | — | — | owner #1 |
| `\nsucc` | — | — | owner #1 |
| `\nsucceq` | — | — | owner #1 |
| `\nsupseteq` | — | — | owner #1 |
| `\nsupseteqq` | — | — | owner #1 |
| `\ntriangleleft` | — | — | owner #1 |
| `\ntrianglelefteq` | — | — | owner #1 |
| `\ntriangleright` | — | — | owner #1 |
| `\ntrianglerighteq` | — | — | owner #1 |
| `\Nu` | `\Nu` | ![](renders/nu.png) |  |
| `\nu` | `\nu` | ![](renders/nu-2.png) |  |
| `\nVDash` | — | — | owner #1 |
| `\nVdash` | — | — | owner #1 |
| `\nvDash` | — | — | owner #1 |
| `\nvdash` | — | — | owner #1 |
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
| `\oiiint` | — | — | owner #3 |
| `\oiint` | — | — | owner #3 |
| `\oint` | `\oint` | ![](renders/oint.png) |  |
| `\oldstyle` | — | — | goldens: rej-unsup-oldstyle |
| `\omega` | `\omega` | ![](renders/omega.png) |  |
| `\Omega` | `\Omega` | ![](renders/omega-2.png) |  |
| `\Omicron` | — | — | owner #1 |
| `\omicron` | — | — | owner #1 |
| `\ominus` | `\ominus` | ![](renders/ominus.png) |  |
| `\operatorname` | `\operatorname{asin} x` | ![](renders/operatorname.png) |  |
| `\operatorname*` | `\operatorname*{asin}\limits_y x` | *no render (engine)* | \limits placement unsupported; KaTeX accepts |
| `\operatornamewithlimits` | `\operatornamewithlimits{asin}\limits_y x` | *no render (engine)* | with-limits operator name missing; KaTeX accepts |
| `\oplus` | `\oplus` | ![](renders/oplus.png) |  |
| `\or` | — | — | goldens: rej-unsup-or |
| `\origof` | — | — | owner #1 |
| `\oslash` | `\oslash` | ![](renders/oslash.png) |  |
| `\otimes` | `\otimes` | ![](renders/otimes.png) |  |
| `\over` | `{a+1 \over b+2}+c` | ![](renders/over.png) |  |
| `\overbrace` | `\overbrace{x+⋯+x}^{n\text{ times}}` | ![](renders/overbrace.png) |  |
| `\overbracket` | `\overbracket{x+⋯+x}^{n\text{ times}}` | *no render (engine)* | bracket overline missing (brace works); KaTeX accepts |
| `\overgroup` | — | — | owner #5 |
| `\overleftarrow` | `\overleftarrow{AB}` | ![](renders/overleftarrow.png) |  |
| `\overleftharpoon` | — | — | owner #1 |
| `\overleftrightarrow` | — | — | owner #5 |
| `\overline` | `\overline{\text{a long argument}}` | ![](renders/overline.png) |  |
| `\overlinesegment` | — | — | owner #5 |
| `\overparen` | — | — | goldens: rej-unsup-overparen |
| `\Overrightarrow` | — | — | owner #1 |
| `\overrightarrow` | `\overrightarrow{AB}` | ![](renders/overrightarrow.png) |  |
| `\overrightharpoon` | — | — | owner #1 |
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
| `\phase` | `\phase{-78^\circ}` | *no render (engine)* | phase notation missing; KaTeX accepts |
| `\Phi` | `\Phi` | ![](renders/phi.png) |  |
| `\phi` | `\phi` | ![](renders/phi-2.png) |  |
| `\Pi` | `\Pi` | ![](renders/pi.png) |  |
| `\pi` | `\pi` | ![](renders/pi-2.png) |  |
| `{picture}` | — | — | goldens: rej-unsup-picture |
| `\pitchfork` | — | — | owner #1 |
| `\plim` | — | — | owner #1 |
| `\plusmn` | — | — | owner #1 |
| `\pm` | `\pm` | ![](renders/pm.png) |  |
| `\pmatrix` | — | — | goldens: rej-unsup-pmatrix |
| `{pmatrix}` | `\begin{pmatrix}\na & b \\\nc & d\n\end{pmatrix}` | ![](renders/pmatrix.png) |  |
| `{pmatrix*}` | `\begin{pmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{pmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\pmb` | `\pmb{\mu}` | *no render (engine)* | poor-man's bold missing; KaTeX accepts |
| `\pmod` | — | — | owner #1 |
| `\pod` | — | — | owner #1 |
| `\pounds` | `\pounds` | ![](renders/pounds.png) |  |
| `\Pr` | `\Pr` | ![](renders/pr.png) |  |
| `\prec` | `\prec` | ![](renders/prec.png) |  |
| `\precapprox` | — | — | owner #1 |
| `\preccurlyeq` | — | — | owner #1 |
| `\preceq` | `\preceq` | ![](renders/preceq.png) |  |
| `\precnapprox` | — | — | owner #1 |
| `\precneqq` | — | — | owner #1 |
| `\precnsim` | — | — | owner #1 |
| `\precsim` | — | — | owner #1 |
| `\prime` | `\prime` | ![](renders/prime-3.png) |  |
| `\prod` | `\prod` | ![](renders/prod.png) |  |
| `\projlim` | — | — | owner #1 |
| `\propto` | `\propto` | ![](renders/propto.png) |  |
| `\providecommand` | `\providecommand\greet{\text{Hello}} \greet` | ![](renders/providecommand.png) |  |
| `\psi` | `\psi` | ![](renders/psi.png) |  |
| `\Psi` | `\Psi` | ![](renders/psi-2.png) |  |
| `\pu` | — | — | owner #1 |

## QR

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\Q` | — | — | goldens: rej-unsup-q |
| `\qquad` | `a\qquad\qquad{b}` | ![](renders/qquad.png) |  |
| `\quad` | `a\quad\quad{b}` | ![](renders/quad.png) |  |
| `\R` | — | — | owner #1 |
| `\r` | `\text{\r{a}}` | ![](renders/r.png) |  |
| `\raise` | — | — | goldens: rej-unsup-raise |
| `\raisebox` | `h\raisebox{2pt}{ighe}r` | ![](renders/raisebox.png) |  |
| `\rang` | `\langle A\rang` | ![](renders/rang.png) |  |
| `\rangle` | `\langle A\rangle` | ![](renders/rangle.png) |  |
| `\Rarr` | — | — | owner #1 |
| `\rArr` | — | — | owner #1 |
| `\rarr` | — | — | owner #1 |
| `\ratio` | — | — | owner #1 |
| `\rBrace` | — | — | owner #1 |
| `\rbrace` | — | — | owner #1 |
| `\rbrack` | — | — | owner #1 |
| `{rcases}` | `\begin{rcases}\na &\text{if } b  \\\nc &\text{if } d\n\end{rcases}` | *no render (engine)* | right-cases missing; KaTeX accepts |
| `\rceil` | `\rceil` | ![](renders/rceil.png) |  |
| `\Re` | `\Re` | ![](renders/re.png) |  |
| `\real` | — | — | owner #1 |
| `\Reals` | — | — | owner #1 |
| `\reals` | — | — | owner #1 |
| `\ref` | — | — | goldens: rej-unsup-ref |
| `\reflectbox` | — | — | owner #1 |
| `\relax` | — | — | owner #1 |
| `\renewcommand` | `\def\hail{Hi!}\n\renewcommand\hail{\text{Ahoy!}}\n\hail` | ![](renders/renewcommand.png) |  |
| `\renewenvironment` | — | — | goldens: rej-unsup-renewenvironment |
| `\require` | — | — | goldens: rej-unsup-require |
| `\restriction` | — | — | owner #1 |
| `\rfloor` | `\rfloor` | ![](renders/rfloor.png) |  |
| `\rgroup` | — | — | owner #4 |
| `\rhd` | `\rhd` | ![](renders/rhd.png) |  |
| `\Rho` | `\Rho` | ![](renders/rho.png) |  |
| `\rho` | `\rho` | ![](renders/rho-2.png) |  |
| `\right` | `\left.\dfrac a b\right)` | ![](renders/right.png) |  |
| `\Rightarrow` | `\Rightarrow` | ![](renders/rightarrow.png) |  |
| `\rightarrow` | `\rightarrow` | ![](renders/rightarrow-2.png) |  |
| `\rightarrowtail` | — | — | owner #1 |
| `\rightharpoondown` | `\rightharpoondown` | ![](renders/rightharpoondown.png) |  |
| `\rightharpoonup` | `\rightharpoonup` | ![](renders/rightharpoonup.png) |  |
| `\rightleftarrows` | — | — | owner #1 |
| `\rightleftharpoons` | `\rightleftharpoons` | ![](renders/rightleftharpoons.png) |  |
| `\rightrightarrows` | — | — | owner #1 |
| `\rightsquigarrow` | — | — | owner #1 |
| `\rightthreetimes` | — | — | owner #1 |
| `\risingdotseq` | — | — | owner #1 |
| `\rlap` | `\rlap{\,/}{=}` | ![](renders/rlap.png) |  |
| `\rm` | — | — | owner #1 |
| `\rmoustache` | — | — | owner #4 |
| `\root` | — | — | goldens: rej-unsup-root |
| `\rotatebox` | — | — | goldens: rej-unsup-rotatebox |
| `\rparen` | — | — | owner #1 |
| `\rq` | — | — | owner #1 |
| `\rrbracket` | — | — | owner #1 |
| `\Rrightarrow` | — | — | owner #1 |
| `\Rsh` | — | — | owner #1 |
| `\rtimes` | — | — | owner #1 |
| `\Rule` | — | — | goldens: rej-unsup-rule |
| `\rule` | `x\rule[6pt]{2ex}{1ex}x` | ![](renders/rule.png) |  |
| `\rVert` | `\rVert` | ![](renders/rvert.png) |  |
| `\rvert` | `\rvert` | ![](renders/rvert-2.png) |  |

## S

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\S` | `\text{\S}` | ![](renders/s.png) |  |
| `\Sampi` | — | — | goldens: rej-unsup-sampi |
| `\sampi` | — | — | goldens: rej-unsup-sampi-2 |
| `\sc` | — | — | goldens: rej-unsup-sc |
| `\scalebox` | — | — | goldens: rej-unsup-scalebox |
| `\scr` | — | — | goldens: rej-unsup-scr |
| `\scriptscriptstyle` | `\scriptscriptstyle \frac cd` | ![](renders/scriptscriptstyle.png) |  |
| `\scriptsize` | — | — | owner #1 |
| `\scriptstyle` | `\frac ab + {\scriptstyle \frac cd}` | ![](renders/scriptstyle.png) |  |
| `\sdot` | — | — | owner #1 |
| `\searrow` | `\searrow` | ![](renders/searrow.png) |  |
| `\sec` | `\sec` | ![](renders/sec.png) |  |
| `\sect` | `\text{\sect}` | ![](renders/sect.png) |  |
| `\set` | — | — | owner #1 |
| `\Set` | `\Set{ x \VERT x<\frac 1 2 }` | *no render (engine)* | set notation missing; KaTeX accepts |
| `\setlength` | — | — | goldens: rej-unsup-setlength |
| `\setminus` | `\setminus` | ![](renders/setminus.png) |  |
| `\sf` | — | — | owner #1 |
| `\sharp` | `\sharp` | ![](renders/sharp.png) |  |
| `\shortmid` | — | — | owner #1 |
| `\shortparallel` | — | — | owner #1 |
| `\shoveleft` | — | — | goldens: rej-unsup-shoveleft |
| `\shoveright` | — | — | goldens: rej-unsup-shoveright |
| `\sideset` | — | — | goldens: rej-unsup-sideset |
| `\Sigma` | `\Sigma` | ![](renders/sigma.png) |  |
| `\sigma` | `\sigma` | ![](renders/sigma-2.png) |  |
| `\sim` | `\sim` | ![](renders/sim.png) |  |
| `\simcolon` | — | — | owner #1 |
| `\simcoloncolon` | — | — | owner #1 |
| `\simeq` | `\simeq` | ![](renders/simeq.png) |  |
| `\sin` | `\sin` | ![](renders/sin.png) |  |
| `\sinh` | `\sinh` | ![](renders/sinh.png) |  |
| `\sixptsize` | — | — | owner #1 |
| `\sh` | — | — | owner #1 |
| `\skew` | — | — | goldens: rej-unsup-skew |
| `\skip` | — | — | goldens: rej-unsup-skip |
| `\sl` | — | — | goldens: rej-unsup-sl |
| `\small` | — | — | owner #1 |
| `\smallfrown` | — | — | owner #1 |
| `\smallint` | — | — | owner #1 |
| `{smallmatrix}` | `\begin{smallmatrix}\na & b \\\nc & d\n\end{smallmatrix}` | ![](renders/smallmatrix.png) |  |
| `\smallsetminus` | — | — | owner #1 |
| `\smallsmile` | — | — | owner #1 |
| `\smash` | `\left(x^{\smash{2}}\right)` | ![](renders/smash.png) |  |
| `\smile` | `\smile` | ![](renders/smile.png) |  |
| `\smiley` | — | — | goldens: rej-unsup-smiley |
| `\sout` | `\text{\sout{abc}}` | *no render (engine)* | strikeout missing; KaTeX accepts |
| `\Space` | — | — | goldens: rej-unsup-space |
| `\space` | — | — | owner #1 |
| `\spades` | — | — | owner #1 |
| `\spadesuit` | `\spadesuit` | ![](renders/spadesuit.png) |  |
| `\sphericalangle` | `\sphericalangle` | ![](renders/sphericalangle.png) |  |
| `{split}` | `\begin{equation}\n\begin{split}\na &=b+c\\\n&=e+f\n\end{split}\n\end{equation}` | *no render (overclaim)* | pinned KaTeX rejects standalone split; table needs a reject row |
| `\sqcap` | `\sqcap` | ![](renders/sqcap.png) |  |
| `\sqcup` | `\sqcup` | ![](renders/sqcup.png) |  |
| `\square` | — | — | owner #1 |
| `\sqrt` | `\sqrt[3]{x}` | ![](renders/sqrt.png) |  |
| `\sqsubset` | `\sqsubset` | ![](renders/sqsubset.png) |  |
| `\sqsubseteq` | `\sqsubseteq` | ![](renders/sqsubseteq.png) |  |
| `\sqsupset` | `\sqsupset` | ![](renders/sqsupset.png) |  |
| `\sqsupseteq` | `\sqsupseteq` | ![](renders/sqsupseteq.png) |  |
| `\ss` | `\text{\ss}` | ![](renders/ss.png) |  |
| `\stackrel` | — | — | owner #1 |
| `\star` | `\star` | ![](renders/star.png) |  |
| `\Stigma` | — | — | goldens: rej-unsup-stigma |
| `\stigma` | — | — | goldens: rej-unsup-stigma-2 |
| `\strut` | — | — | goldens: rej-unsup-strut |
| `\style` | — | — | goldens: rej-unsup-style |
| `\sub` | — | — | owner #1 |
| `{subarray}` | — | — | KaTeX accepts with alignment arg (sweep-proven); owner #14 |
| `\sube` | — | — | owner #1 |
| `\Subset` | — | — | owner #1 |
| `\subset` | `\subset` | ![](renders/subset.png) |  |
| `\subseteq` | `\subseteq` | ![](renders/subseteq.png) |  |
| `\subseteqq` | — | — | owner #1 |
| `\subsetneq` | `\subsetneq` | ![](renders/subsetneq.png) |  |
| `\subsetneqq` | — | — | owner #1 |
| `\substack` | `\sum_{\substack{0<i<m\\0<j<n}}` | ![](renders/substack.png) |  |
| `\succ` | `\succ` | ![](renders/succ.png) |  |
| `\succapprox` | — | — | owner #1 |
| `\succcurlyeq` | — | — | owner #1 |
| `\succeq` | `\succeq` | ![](renders/succeq.png) |  |
| `\succnapprox` | — | — | owner #1 |
| `\succneqq` | — | — | owner #1 |
| `\succnsim` | — | — | owner #1 |
| `\succsim` | — | — | owner #1 |
| `\sum` | `\sum` | ![](renders/sum.png) |  |
| `\sup` | `\sup` | ![](renders/sup.png) |  |
| `\supe` | — | — | owner #1 |
| `\Supset` | — | — | owner #1 |
| `\supset` | `\supset` | ![](renders/supset.png) |  |
| `\supseteq` | `\supseteq` | ![](renders/supseteq.png) |  |
| `\supseteqq` | — | — | owner #1 |
| `\supsetneq` | `\supsetneq` | ![](renders/supsetneq.png) |  |
| `\supsetneqq` | — | — | owner #1 |
| `\surd` | `\surd` | ![](renders/surd.png) |  |
| `\swarrow` | `\swarrow` | ![](renders/swarrow.png) |  |

## T

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\tag` | — | — | owner #1 |
| `\tag*` | — | — | owner #1 |
| `\tan` | `\tan` | ![](renders/tan.png) |  |
| `\tanh` | `\tanh` | ![](renders/tanh.png) |  |
| `\Tau` | `\Tau` | ![](renders/tau.png) |  |
| `\tau` | `\tau` | ![](renders/tau-2.png) |  |
| `\tbinom` | — | — | owner #2 |
| `\TeX` | — | — | owner #1 |
| `\text` | `\text{ yes }\&\text{ no }` | ![](renders/text.png) |  |
| `\textasciitilde` | `\text{\textasciitilde}` | ![](renders/textasciitilde.png) |  |
| `\textasciicircum` | `\text{\textasciicircum}` | ![](renders/textasciicircum.png) |  |
| `\textbackslash` | `\text{\textbackslash}` | ![](renders/textbackslash.png) |  |
| `\textbar` | `\text{\textbar}` | ![](renders/textbar.png) |  |
| `\textbardbl` | `\text{\textbardbl}` | ![](renders/textbardbl.png) |  |
| `\textbf` | `\textbf{AaBb123}` | ![](renders/textbf.png) |  |
| `\textbraceleft` | `\text{\textbraceleft}` | ![](renders/textbraceleft.png) |  |
| `\textbraceright` | `\text{\textbraceright}` | ![](renders/textbraceright.png) |  |
| `\textcircled` | `\text{\textcircled a}` | *no render (engine)* | enclosing circle missing; KaTeX accepts |
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
| `\textmd` | — | — | owner #1 |
| `\textnormal` | `\textnormal{AB}` | ![](renders/textnormal.png) |  |
| `\textquotedblleft` | `\text{\textquotedblleft}` | ![](renders/textquotedblleft.png) |  |
| `\textquotedblright` | `\text{\textquotedblright}` | ![](renders/textquotedblright.png) |  |
| `\textquoteleft` | `\text{\textquoteleft}` | ![](renders/textquoteleft.png) |  |
| `\textquoteright` | `\text{\textquoteright}` | ![](renders/textquoteright.png) |  |
| `\textregistered` | `\text{\textregistered}` | *no render (engine)* | \textregistered inside \text unsupported; KaTeX accepts |
| `\textrm` | `\textrm{AaBb123}` | ![](renders/textrm.png) |  |
| `\textsc` | — | — | goldens: rej-unsup-textsc |
| `\textsf` | `\textsf{AaBb123}` | ![](renders/textsf.png) |  |
| `\textsl` | — | — | reject rows: textsl |
| `\textsterling` | `\text{\textsterling}` | ![](renders/textsterling.png) |  |
| `\textstyle` | `\textstyle\sum_0^n` | ![](renders/textstyle.png) |  |
| `\texttip` | — | — | goldens: rej-unsup-texttip |
| `\texttt` | `\texttt{AaBb123}` | ![](renders/texttt.png) |  |
| `\textunderscore` | `\text{\textunderscore}` | ![](renders/textunderscore.png) |  |
| `\textup` | — | — | owner #1 |
| `\textvisiblespace` | — | — | goldens: rej-unsup-textvisiblespace |
| `\tfrac` | `\tfrac ab` | ![](renders/tfrac.png) |  |
| `\tg` | — | — | owner #1 |
| `\th` | — | — | owner #1 |
| `\therefore` | — | — | owner #1 |
| `\Theta` | `\Theta` | ![](renders/theta.png) |  |
| `\theta` | `\theta` | ![](renders/theta-2.png) |  |
| `\thetasym` | — | — | owner #1 |
| `\thickapprox` | — | — | owner #1 |
| `\thicksim` | — | — | owner #1 |
| `\thickspace` | — | — | owner #1 |
| `\thinspace` | — | — | owner #1 |
| `\tilde` | `\tilde M` | ![](renders/tilde-3.png) |  |
| `\times` | `\times` | ![](renders/times.png) |  |
| `\Tiny` | — | — | goldens: rej-unsup-tiny |
| `\tiny` | — | — | owner #1 |
| `\to` | `\to` | ![](renders/to.png) |  |
| `\toggle` | — | — | goldens: rej-unsup-toggle |
| `\top` | `\top` | ![](renders/top.png) |  |
| `\triangle` | — | — | owner #1 |
| `\triangledown` | — | — | owner #1 |
| `\triangleleft` | `\triangleleft` | ![](renders/triangleleft.png) |  |
| `\trianglelefteq` | — | — | owner #1 |
| `\triangleq` | — | — | owner #1 |
| `\triangleright` | `\triangleright` | ![](renders/triangleright.png) |  |
| `\trianglerighteq` | — | — | owner #1 |
| `\tt` | — | — | owner #1 |
| `\twoheadleftarrow` | — | — | owner #1 |
| `\twoheadrightarrow` | — | — | owner #1 |

## U

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\u` | `\text{\u{a}}` | ![](renders/u.png) |  |
| `\Uarr` | — | — | owner #1 |
| `\uArr` | — | — | owner #1 |
| `\uarr` | — | — | owner #1 |
| `\ulcorner` | `\ulcorner` | ![](renders/ulcorner.png) |  |
| `\underbar` | — | — | owner #1 |
| `\underbrace` | `\underbrace{x+⋯+x}_{n\text{ times}}` | ![](renders/underbrace.png) |  |
| `\underbracket` | `\underbracket{x+⋯+x}_{n\text{ times}}` | *no render (engine)* | bracket underline missing; KaTeX accepts |
| `\undergroup` | — | — | owner #5 |
| `\underleftarrow` | — | — | owner #5 |
| `\underleftrightarrow` | — | — | owner #5 |
| `\underrightarrow` | — | — | owner #5 |
| `\underline` | `\underline{\text{a long argument}}` | ![](renders/underline.png) |  |
| `\underlinesegment` | — | — | owner #5 |
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
| `\upharpoonleft` | — | — | owner #1 |
| `\upharpoonright` | — | — | owner #1 |
| `\uplus` | `\uplus` | ![](renders/uplus.png) |  |
| `\uproot` | — | — | goldens: rej-unsup-uproot |
| `\upshape` | — | — | goldens: rej-unsup-upshape |
| `\Upsilon` | `\Upsilon` | ![](renders/upsilon.png) |  |
| `\upsilon` | `\upsilon` | ![](renders/upsilon-2.png) |  |
| `\upuparrows` | — | — | owner #1 |
| `\urcorner` | `\urcorner` | ![](renders/urcorner.png) |  |
| `\url` | `\url{https://katex.org/}` | ![](renders/url.png) |  |
| `\utilde` | — | — | owner #5 |

## V

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\v` | `\text{\v{a}}` | ![](renders/v.png) |  |
| `\varcoppa` | — | — | goldens: rej-unsup-varcoppa |
| `\varDelta` | — | — | owner #1 |
| `\varepsilon` | `\varepsilon` | ![](renders/varepsilon.png) |  |
| `\varGamma` | — | — | owner #1 |
| `\varinjlim` | — | — | owner #1 |
| `\varkappa` | — | — | owner #1 |
| `\varLambda` | — | — | owner #1 |
| `\varliminf` | — | — | owner #1 |
| `\varlimsup` | — | — | owner #1 |
| `\varnothing` | `\varnothing` | ![](renders/varnothing.png) |  |
| `\varOmega` | — | — | owner #1 |
| `\varPhi` | — | — | owner #1 |
| `\varphi` | `\varphi` | ![](renders/varphi.png) |  |
| `\varPi` | — | — | owner #1 |
| `\varpi` | `\varpi` | ![](renders/varpi.png) |  |
| `\varprojlim` | — | — | owner #1 |
| `\varpropto` | — | — | owner #1 |
| `\varPsi` | — | — | owner #1 |
| `\varrho` | `\varrho` | ![](renders/varrho.png) |  |
| `\varSigma` | — | — | owner #1 |
| `\varsigma` | `\varsigma` | ![](renders/varsigma.png) |  |
| `\varstigma` | — | — | goldens: rej-unsup-varstigma |
| `\varsubsetneq` | — | — | owner #1 |
| `\varsubsetneqq` | — | — | owner #1 |
| `\varsupsetneq` | — | — | owner #1 |
| `\varsupsetneqq` | — | — | owner #1 |
| `\varTheta` | — | — | owner #1 |
| `\vartheta` | `\vartheta` | ![](renders/vartheta.png) |  |
| `\vartriangle` | — | — | owner #1 |
| `\vartriangleleft` | — | — | owner #1 |
| `\vartriangleright` | — | — | owner #1 |
| `\varUpsilon` | — | — | owner #1 |
| `\varXi` | — | — | owner #1 |
| `\vcentcolon` | — | — | owner #1 |
| `\vcenter` | `a+\left(\vcenter{\frac{\frac a b}c}\right)` | *no render (engine)* | vertical centering missing; KaTeX accepts |
| `\Vdash` | — | — | owner #1 |
| `\vDash` | — | — | owner #1 |
| `\vdash` | `\vdash` | ![](renders/vdash.png) |  |
| `\vdots` | `\vdots` | ![](renders/vdots.png) |  |
| `\vec` | `\vec{F}` | ![](renders/vec.png) |  |
| `\vee` | `\vee` | ![](renders/vee.png) |  |
| `\veebar` | — | — | owner #1 |
| `\verb` | `\verb!\frac a b!` | ![](renders/verb.png) |  |
| `\Vert` | `\Vert` | ![](renders/vert.png) |  |
| `\vert` | `\vert` | ![](renders/vert-2.png) |  |
| `\vfil` | — | — | goldens: rej-unsup-vfil |
| `\vfill` | — | — | goldens: rej-unsup-vfill |
| `\vline` | — | — | goldens: rej-unsup-vline |
| `{Vmatrix}` | `\begin{Vmatrix}\na & b \\\nc & d\n\end{Vmatrix}` | ![](renders/vmatrix.png) |  |
| `{Vmatrix*}` | `\begin{Vmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{Vmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `{vmatrix}` | `\begin{vmatrix}\na & b \\\nc & d\n\end{vmatrix}` | ![](renders/vmatrix-2.png) |  |
| `{vmatrix*}` | `\begin{vmatrix*}[r]\n0 & -1 \\\n-1 & 0\n\end{vmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\vphantom` | `\overline{\vphantom{M}a}` | ![](renders/vphantom.png) |  |
| `\Vvdash` | — | — | owner #1 |

## W

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\wedge` | `\wedge` | ![](renders/wedge.png) |  |
| `\weierp` | — | — | owner #1 |
| `\widecheck` | `\widecheck{AB}` | ![](renders/widecheck.png) |  |
| `\widehat` | `\widehat{AB}` | ![](renders/widehat.png) |  |
| `\wideparen` | — | — | goldens: rej-unsup-wideparen |
| `\widetilde` | `\widetilde{AB}` | ![](renders/widetilde.png) |  |
| `\wp` | `\wp` | ![](renders/wp.png) |  |
| `\wr` | `\wr` | ![](renders/wr.png) |  |

## X

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\xcancel` | — | — | owner #7 |
| `\xdef` | `\def\foo{a}\xdef\fcopy{\foo}\def\foo{}\fcopy` | *no render (engine)* | xdef macro definition missing; KaTeX accepts |
| `\Xi` | `\Xi` | ![](renders/xi.png) |  |
| `\xi` | `\xi` | ![](renders/xi-2.png) |  |
| `\xhookleftarrow` | — | — | owner #1 |
| `\xhookrightarrow` | — | — | owner #1 |
| `\xLeftarrow` | — | — | owner #1 |
| `\xleftarrow` | `\xleftarrow{abc}` | ![](renders/xleftarrow.png) |  |
| `\xleftharpoondown` | — | — | owner #1 |
| `\xleftharpoonup` | — | — | owner #1 |
| `\xLeftrightarrow` | — | — | owner #1 |
| `\xleftrightarrow` | — | — | owner #1 |
| `\xleftrightharpoons` | — | — | owner #1 |
| `\xlongequal` | — | — | owner #1 |
| `\xmapsto` | — | — | owner #1 |
| `\xRightarrow` | — | — | owner #1 |
| `\xrightarrow` | `\xrightarrow{abc}` | ![](renders/xrightarrow.png) |  |
| `\xrightharpoondown` | — | — | owner #1 |
| `\xrightharpoonup` | — | — | owner #1 |
| `\xrightleftharpoons` | — | — | owner #1 |
| `\xtofrom` | — | — | owner #1 |
| `\xtwoheadleftarrow` | — | — | owner #1 |
| `\xtwoheadrightarrow` | — | — | owner #1 |

## YZ

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\yen` | `\yen` | ![](renders/yen.png) |  |
| `\Z` | — | — | owner #1 |
| `\Zeta` | `\Zeta` | ![](renders/zeta.png) |  |
| `\zeta` | `\zeta` | ![](renders/zeta-2.png) |  |

