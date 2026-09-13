# KaTeX syntax mirror (generated — do not edit)

A render of every accepted function, generated from `docs/support-table.md` by `tools/gen_doc_renders.py` (renders via `zatex-png` into `docs/renders/`; expected render gaps live in `tools/doc_gaps.json`). Status, evidence, and ownership live in the support table — edit that, never this file.

## Symbols

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `!` | `x!` | ![](renders/bang.png) |  |
| `\!` | `x\!x` | ![](renders/bang-2.png) |  |
| `#` | `\def\f#1{#1}\f{x}` | ![](renders/hash.png) |  |
| `\#` | `\#` | ![](renders/hash-2.png) |  |
| `%` | `a% note\nb` | ![](renders/pct.png) |  |
| `\%` | `\%` | ![](renders/pct-2.png) |  |
| `&` | `\begin{aligned}a&=b\end{aligned}` | ![](renders/amp.png) |  |
| `\&` | `\&` | ![](renders/amp-2.png) |  |
| `'` | `x'` | ![](renders/prime.png) |  |
| `\'` | `\'e` | ![](renders/prime-2.png) |  |
| `(` | `(x)` | ![](renders/lp.png) |  |
| `)` | `(x)` | ![](renders/rp.png) |  |
| `\(…\)` | `\(x^2\)` | *no render (overclaim)* | inline-math delimiters, not math-mode input; pinned KaTeX rejects inside math |
| `\ ` | `a\ b` | ![](renders/ctrlspace.png) |  |
| `\"` | `\"o` | ![](renders/quot.png) |  |
| `\$` | `\$` | ![](renders/dollar.png) |  |
| `\,` | `x\,x` | ![](renders/comma.png) |  |
| `\.` | `\.o` | ![](renders/dot.png) |  |
| `\:` | `x\:x` | ![](renders/colon.png) |  |
| `\;` | `x\;x` | ![](renders/semi.png) |  |
| `_` | `x_i` | ![](renders/us.png) |  |
| `\_` | `\_` | ![](renders/us-2.png) |  |
| `\`` | `\`a` | ![](renders/fn.png) |  |
| `<` | `x<y` | ![](renders/lt.png) |  |
| `\=` | `\={x}` | ![](renders/eq.png) |  |
| `>` | `x>y` | ![](renders/gt.png) |  |
| `\>` | — | — | owner #14 |
| `[` | `[x]` | ![](renders/fn-2.png) |  |
| `]` | `x]` | ![](renders/fn-3.png) |  |
| `{` | `{a}` | ![](renders/fn-4.png) |  |
| `}` | `{a}` | ![](renders/fn-5.png) |  |
| `\{` | `\{x\}` | ![](renders/fn-6.png) |  |
| `\}` | `\{x\}` | ![](renders/fn-7.png) |  |
| `|` | `a\|b` | ![](renders/pipe.png) |  |
| `\|` | `\\|x\\|` | ![](renders/pipe-2.png) |  |
| `~` | `a~b` | ![](renders/tilde.png) |  |
| `\~` | `\~n` | ![](renders/tilde-2.png) |  |
| `\\ ` | `\begin{matrix}a\\b\end{matrix}` | ![](renders/newline.png) |  |
| `^` | `x^2` | ![](renders/pow.png) |  |
| `\^` | `\^{x}` | ![](renders/pow-2.png) |  |

## A

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\AA` | `\AA` | ![](renders/aa.png) |  |
| `\aa` | `\aa` | ![](renders/aa-2.png) |  |
| `\above` | — | — | owner #1 |
| `\abovewithdelims` | — | — | goldens: rej-unsup-abovewithdelims |
| `\acute` | `\acute{x}` | ![](renders/acute.png) |  |
| `\AE` | `\text{\AE}` | ![](renders/ae.png) |  |
| `\ae` | `\text{\ae}` | ![](renders/ae-2.png) |  |
| `\alef` | — | — | owner #1 |
| `\alefsym` | — | — | owner #1 |
| `\aleph` | `x \aleph y` | ![](renders/aleph.png) |  |
| `{align}` | `\begin{align}a&=b\end{align}` | *no render (overclaim)* | pinned KaTeX rejects unstarred align; table needs a reject row |
| `{align*}` | `\begin{align*}a&=b\end{align*}` | *no render (engine)* | top-level align missing; KaTeX accepts |
| `{aligned}` | `\begin{aligned}a&=b+c\\d&=e\end{aligned}` | ![](renders/aligned.png) |  |
| `{alignat}` | `\begin{alignat}{2}a&=b&c&=d\end{alignat}` | *no render (engine)* | top-level alignat missing (alignedat works); KaTeX accepts |
| `{alignat*}` | `\begin{alignat*}{2}a&=b&c&=d\end{alignat*}` | *no render (engine)* | top-level alignat missing; KaTeX accepts |
| `{alignedat}` | `\begin{alignedat}{2}a&=b&c&=d\end{alignedat}` | ![](renders/alignedat.png) |  |
| `\allowbreak` | — | — | owner #1 |
| `\Alpha` | `x \Alpha y` | ![](renders/alpha.png) |  |
| `\alpha` | `x \alpha y` | ![](renders/alpha-2.png) |  |
| `\amalg` | `x \amalg y` | ![](renders/amalg.png) |  |
| `\And` | — | — | owner #1 |
| `\and` | — | — | goldens: rej-unsup-and |
| `\ang` | — | — | goldens: rej-unsup-ang |
| `\angl` | — | — | owner #1 |
| `\angln` | — | — | owner #1 |
| `\angle` | `x \angle y` | ![](renders/angle.png) |  |
| `\approx` | `x \approx y` | ![](renders/approx.png) |  |
| `\approxeq` | `x \approxeq y` | ![](renders/approxeq.png) |  |
| `\approxcolon` | — | — | owner #1 |
| `\approxcoloncolon` | — | — | owner #1 |
| `\arccos` | `\arccos x` | ![](renders/arccos.png) |  |
| `\arcctg` | — | — | owner #1 |
| `\arcsin` | `\arcsin x` | ![](renders/arcsin.png) |  |
| `\arctan` | `\arctan x` | ![](renders/arctan.png) |  |
| `\arctg` | — | — | owner #1 |
| `\arg` | `\arg x` | ![](renders/arg.png) |  |
| `\argmax` | — | — | owner #1 |
| `\argmin` | — | — | owner #1 |
| `{array}` | `\begin{array}{cc\|c}a&b&c\\\hline d&e&f\end{array}` | ![](renders/array.png) |  |
| `\array` | — | — | goldens: rej-unsup-array |
| `\arraystretch` | `\renewcommand{\arraystretch}{1.5}\begin{matrix}a\\b\end{matrix}` | *no render (engine)* | renewcommand of arraystretch rejected; KaTeX accepts |
| `\Arrowvert` | — | — | goldens: rej-unsup-arrowvert |
| `\arrowvert` | — | — | goldens: rej-unsup-arrowvert-2 |
| `\ast` | `x \ast y` | ![](renders/ast.png) |  |
| `\asymp` | `x \asymp y` | ![](renders/asymp.png) |  |
| `\atop` | `{a\atop b}` | ![](renders/atop.png) |  |
| `\atopwithdelims` | — | — | goldens: rej-unsup-atopwithdelims |

## B

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\backepsilon` | — | — | owner #1 |
| `\backprime` | `x \backprime y` | ![](renders/backprime.png) |  |
| `\backsim` | — | — | owner #1 |
| `\backsimeq` | — | — | owner #1 |
| `\backslash` | `x \backslash y` | ![](renders/backslash.png) |  |
| `\bar` | `\bar{x}` | ![](renders/bar.png) |  |
| `\barwedge` | — | — | owner #1 |
| `\Bbb` | — | — | owner #1 |
| `\Bbbk` | — | — | owner #1 |
| `\bbox` | — | — | goldens: rej-unsup-bbox |
| `\bcancel` | — | — | owner #7 |
| `\because` | — | — | owner #1 |
| `\begin` | `\begin{pmatrix}a\end{pmatrix}` | ![](renders/begin.png) |  |
| `\begingroup` | — | — | owner #1 |
| `\Beta` | `x \Beta y` | ![](renders/beta.png) |  |
| `\beta` | `x \beta y` | ![](renders/beta-2.png) |  |
| `\beth` | `x \beth y` | ![](renders/beth.png) |  |
| `\between` | — | — | owner #1 |
| `\bf` | — | — | owner #1 |
| `\bfseries` | — | — | goldens: rej-unsup-bfseries |
| `\big` | `\big(x\big)` | ![](renders/big.png) |  |
| `\Big` | `\Big(x\Big)` | ![](renders/big-2.png) |  |
| `\bigcap` | `\bigcap_{i=1}^n x` | ![](renders/bigcap.png) |  |
| `\bigcirc` | — | — | owner #1 |
| `\bigcup` | `\bigcup_{i=1}^n x` | ![](renders/bigcup.png) |  |
| `\bigg` | `\bigg(x\bigg)` | ![](renders/bigg.png) |  |
| `\Bigg` | `\Bigg(x\Bigg)` | ![](renders/bigg-2.png) |  |
| `\biggl` | — | — | owner #4 |
| `\Biggl` | — | — | owner #4 |
| `\biggm` | `a\biggm\|b` | ![](renders/biggm.png) |  |
| `\Biggm` | `a\Biggm\|b` | ![](renders/biggm-2.png) |  |
| `\biggr` | — | — | owner #4 |
| `\Biggr` | — | — | owner #4 |
| `\bigl` | `\bigl(x\bigr)` | ![](renders/bigl.png) |  |
| `\Bigl` | `\Bigl(x\Bigr)` | ![](renders/bigl-2.png) |  |
| `\bigm` | `a\bigm\|b` | ![](renders/bigm.png) |  |
| `\Bigm` | `a\Bigm\|b` | ![](renders/bigm-2.png) |  |
| `\bigodot` | `\bigodot_{i=1}^n x` | ![](renders/bigodot.png) |  |
| `\bigominus` | — | — | goldens: rej-unsup-bigominus |
| `\bigoplus` | `\bigoplus_{i=1}^n x` | ![](renders/bigoplus.png) |  |
| `\bigoslash` | — | — | goldens: rej-unsup-bigoslash |
| `\bigotimes` | `\bigotimes_{i=1}^n x` | ![](renders/bigotimes.png) |  |
| `\bigr` | `\bigl(x\bigr)` | ![](renders/bigr.png) |  |
| `\Bigr` | `\Bigl(x\Bigr)` | ![](renders/bigr-2.png) |  |
| `\bigsqcap` | — | — | goldens: rej-unsup-bigsqcap |
| `\bigsqcup` | — | — | owner #1 |
| `\bigstar` | — | — | owner #1 |
| `\bigtriangledown` | `x \bigtriangledown y` | ![](renders/bigtriangledown.png) |  |
| `\bigtriangleup` | `x \bigtriangleup y` | ![](renders/bigtriangleup.png) |  |
| `\biguplus` | `\biguplus_{i=1}^n x` | ![](renders/biguplus.png) |  |
| `\bigvee` | `\bigvee_{i=1}^n x` | ![](renders/bigvee.png) |  |
| `\bigwedge` | `\bigwedge_{i=1}^n x` | ![](renders/bigwedge.png) |  |
| `\binom` | `\binom{n}{k}` | ![](renders/binom.png) |  |
| `\blacklozenge` | — | — | owner #1 |
| `\blacksquare` | — | — | owner #1 |
| `\blacktriangle` | — | — | owner #1 |
| `\blacktriangledown` | — | — | owner #1 |
| `\blacktriangleleft` | — | — | owner #1 |
| `\blacktriangleright` | — | — | owner #1 |
| `\bm` | — | — | owner #1 |
| `{Bmatrix}` | `\begin{Bmatrix}a&b\\c&d\end{Bmatrix}` | ![](renders/bmatrix.png) |  |
| `{Bmatrix*}` | `\begin{Bmatrix*}a&b\\c&d\end{Bmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `{bmatrix}` | `\begin{bmatrix}a&b\\c&d\end{bmatrix}` | ![](renders/bmatrix-2.png) |  |
| `{bmatrix*}` | `\begin{bmatrix*}a&b\\c&d\end{bmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\bmod` | — | — | owner #1 |
| `\bold` | — | — | owner #1 |
| `\boldsymbol` | `\boldsymbol{\alpha}` | ![](renders/boldsymbol.png) |  |
| `\bot` | `x \bot y` | ![](renders/bot.png) |  |
| `\bowtie` | `x \bowtie y` | ![](renders/bowtie.png) |  |
| `\Box` | — | — | owner #1 |
| `\boxdot` | `x \boxdot y` | ![](renders/boxdot.png) |  |
| `\boxed` | `\boxed{x^2}` | ![](renders/boxed.png) |  |
| `\boxminus` | `x \boxminus y` | ![](renders/boxminus.png) |  |
| `\boxplus` | `x \boxplus y` | ![](renders/boxplus.png) |  |
| `\boxtimes` | `x \boxtimes y` | ![](renders/boxtimes.png) |  |
| `\Bra` | `\Bra{x}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\bra` | `\bra{x}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\braket` | `\braket{x}{y}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\Braket` | `\Braket{x}{y}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\brace` | — | — | owner #2 |
| `\bracevert` | — | — | goldens: rej-unsup-bracevert |
| `\brack` | — | — | owner #2 |
| `\breve` | `\breve{x}` | ![](renders/breve.png) |  |
| `\buildrel` | — | — | goldens: rej-unsup-buildrel |
| `\bull` | — | — | owner #1 |
| `\bullet` | `x \bullet y` | ![](renders/bullet.png) |  |
| `\Bumpeq` | — | — | owner #1 |
| `\bumpeq` | — | — | owner #1 |

## C

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\C` | — | — | goldens: rej-unsup-c |
| `\cal` | — | — | owner #1 |
| `\cancel` | `\cancel{x}` | ![](renders/cancel.png) |  |
| `\cancelto` | — | — | goldens: rej-unsup-cancelto |
| `\Cap` | — | — | owner #1 |
| `\cap` | `x \cap y` | ![](renders/cap.png) |  |
| `{cases}` | `f(x)=\begin{cases}1&x>0\\0&x=0\end{cases}` | ![](renders/cases.png) |  |
| `\cases` | — | — | goldens: rej-unsup-cases |
| `{CD}` | `\begin{CD}a@>b>>c\end{CD}` | *no render (overclaim)* | pinned KaTeX rejects CD; table needs a reject row |
| `\cdot` | `x \cdot y` | ![](renders/cdot.png) |  |
| `\cdotp` | `x \cdotp y` | ![](renders/cdotp.png) |  |
| `\cdots` | `x \cdots y` | ![](renders/cdots.png) |  |
| `\ce` | — | — | owner #1 |
| `\cee` | — | — | goldens: rej-unsup-cee |
| `\centerdot` | `x \centerdot y` | ![](renders/centerdot.png) |  |
| `\cf` | — | — | goldens: rej-unsup-cf |
| `\cfrac` | `\cfrac{a}{b}` | ![](renders/cfrac.png) |  |
| `\char` | — | — | owner #1 |
| `\check` | `\check{x}` | ![](renders/check.png) |  |
| `\ch` | — | — | owner #1 |
| `\checkmark` | `x \checkmark y` | ![](renders/checkmark.png) |  |
| `\Chi` | `x \Chi y` | ![](renders/chi.png) |  |
| `\chi` | `x \chi y` | ![](renders/chi-2.png) |  |
| `\choose` | `{n\choose k}` | ![](renders/choose.png) |  |
| `\circ` | `x \circ y` | ![](renders/circ.png) |  |
| `\circeq` | — | — | owner #1 |
| `\circlearrowleft` | — | — | owner #1 |
| `\circlearrowright` | — | — | owner #1 |
| `\circledast` | — | — | owner #1 |
| `\circledcirc` | — | — | owner #1 |
| `\circleddash` | — | — | owner #1 |
| `\circledR` | `x \circledR y` | ![](renders/circledr.png) |  |
| `\circledS` | `x \circledS y` | ![](renders/circleds.png) |  |
| `\class` | — | — | goldens: rej-unsup-class |
| `\cline` | — | — | goldens: rej-unsup-cline |
| `\clubs` | — | — | owner #1 |
| `\clubsuit` | `x \clubsuit y` | ![](renders/clubsuit.png) |  |
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
| `\color` | `\color{red}x` | ![](renders/color.png) |  |
| `\colorbox` | `\colorbox{yellow}{a+b}` | ![](renders/colorbox.png) |  |
| `\complement` | — | — | owner #1 |
| `\Complex` | — | — | owner #1 |
| `\cong` | `x \cong y` | ![](renders/cong.png) |  |
| `\Coppa` | — | — | goldens: rej-unsup-coppa |
| `\coppa` | — | — | goldens: rej-unsup-coppa-2 |
| `\coprod` | `\coprod_{i=1}^n x` | ![](renders/coprod.png) |  |
| `\copyright` | — | — | owner #1 |
| `\cos` | `\cos x` | ![](renders/cos.png) |  |
| `\cosec` | — | — | owner #1 |
| `\cosh` | `\cosh x` | ![](renders/cosh.png) |  |
| `\cot` | `\cot x` | ![](renders/cot.png) |  |
| `\cotg` | — | — | owner #1 |
| `\coth` | `\coth x` | ![](renders/coth.png) |  |
| `\cr` | `\begin{matrix}a\cr b\end{matrix}` | *no render (engine)* | in-matrix \cr exhausts buffers (NoSpace); KaTeX accepts |
| `\csc` | `\csc x` | ![](renders/csc.png) |  |
| `\cssId` | — | — | goldens: rej-unsup-cssid |
| `\ctg` | — | — | owner #1 |
| `\cth` | — | — | owner #1 |
| `\Cup` | — | — | owner #1 |
| `\cup` | `x \cup y` | ![](renders/cup.png) |  |
| `\curlyeqprec` | — | — | owner #1 |
| `\curlyeqsucc` | — | — | owner #1 |
| `\curlyvee` | — | — | owner #1 |
| `\curlywedge` | — | — | owner #1 |
| `\curvearrowleft` | — | — | owner #1 |
| `\curvearrowright` | — | — | owner #1 |

## D

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\dag` | `x \dag y` | ![](renders/dag.png) |  |
| `\Dagger` | — | — | owner #1 |
| `\dagger` | `x \dagger y` | ![](renders/dagger.png) |  |
| `\daleth` | `x \daleth y` | ![](renders/daleth.png) |  |
| `\Darr` | — | — | owner #1 |
| `\dArr` | — | — | owner #1 |
| `\darr` | — | — | owner #1 |
| `\dashleftarrow` | — | — | owner #1 |
| `\dashrightarrow` | — | — | owner #1 |
| `\dashv` | `x \dashv y` | ![](renders/dashv.png) |  |
| `\dbinom` | `\dbinom{n}{k}` | ![](renders/dbinom.png) |  |
| `\dblcolon` | — | — | owner #1 |
| `{dcases}` | `\begin{dcases}1&x>0\\0&x=0\end{dcases}` | *no render (engine)* | display cases missing; KaTeX accepts |
| `\ddag` | `x \ddag y` | ![](renders/ddag.png) |  |
| `\ddagger` | `x \ddagger y` | ![](renders/ddagger.png) |  |
| `\ddddot` | `\ddddot{x}` | ![](renders/ddddot.png) |  |
| `\dddot` | `\dddot{x}` | ![](renders/dddot.png) |  |
| `\ddot` | `\ddot{x}` | ![](renders/ddot.png) |  |
| `\ddots` | `x \ddots y` | ![](renders/ddots.png) |  |
| `\DeclareMathOperator` | — | — | reject rows: rej-declare-op |
| `\def` | `\def\h{x}\h` | ![](renders/def.png) |  |
| `\definecolor` | — | — | reject rows: definecolor |
| `\deg` | `\deg x` | ![](renders/deg.png) |  |
| `\degree` | — | — | owner #1 |
| `\delta` | `x \delta y` | ![](renders/delta.png) |  |
| `\Delta` | `x \Delta y` | ![](renders/delta-2.png) |  |
| `\det` | `\det x` | ![](renders/det.png) |  |
| `\Digamma` | — | — | goldens: rej-unsup-digamma |
| `\digamma` | `x \digamma y` | ![](renders/digamma.png) |  |
| `\dfrac` | `\dfrac{a}{b}` | ![](renders/dfrac.png) |  |
| `\diagdown` | — | — | owner #1 |
| `\diagup` | — | — | owner #1 |
| `\Diamond` | — | — | owner #1 |
| `\diamond` | `x \diamond y` | ![](renders/diamond.png) |  |
| `\diamonds` | — | — | owner #1 |
| `\diamondsuit` | `x \diamondsuit y` | ![](renders/diamondsuit.png) |  |
| `\dim` | `\dim x` | ![](renders/dim.png) |  |
| `\displaylines` | — | — | goldens: rej-unsup-displaylines |
| `\displaystyle` | `{\displaystyle\sum_i x}` | ![](renders/displaystyle.png) |  |
| `\div` | `x \div y` | ![](renders/div.png) |  |
| `\divideontimes` | — | — | owner #1 |
| `\dot` | `\dot{x}` | ![](renders/dot-2.png) |  |
| `\Doteq` | — | — | owner #1 |
| `\doteq` | `x \doteq y` | ![](renders/doteq.png) |  |
| `\doteqdot` | — | — | owner #1 |
| `\dotplus` | — | — | owner #1 |
| `\dots` | `x \dots y` | ![](renders/dots.png) |  |
| `\dotsb` | — | — | owner #1 |
| `\dotsc` | — | — | owner #1 |
| `\dotsi` | `x \dotsi y` | *no render (engine)* | dotsi alias missing from symbol table; KaTeX accepts |
| `\dotsm` | — | — | owner #1 |
| `\dotso` | — | — | owner #1 |
| `\doublebarwedge` | — | — | owner #1 |
| `\doublecap` | — | — | owner #1 |
| `\doublecup` | — | — | owner #1 |
| `\Downarrow` | `x \Downarrow y` | ![](renders/downarrow.png) |  |
| `\downarrow` | `x \downarrow y` | ![](renders/downarrow-2.png) |  |
| `\downdownarrows` | — | — | owner #1 |
| `\downharpoonleft` | — | — | owner #1 |
| `\downharpoonright` | — | — | owner #1 |
| `{drcases}` | `\begin{drcases}1&x>0\end{drcases}` | *no render (engine)* | display right-cases missing; KaTeX accepts |

## E

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\edef` | `\edef\e{z}\e` | *no render (engine)* | edef macro definition missing; KaTeX accepts |
| `\ell` | `x \ell y` | ![](renders/ell.png) |  |
| `\else` | — | — | goldens: rej-unsup-else |
| `\em` | — | — | goldens: rej-unsup-em |
| `\emph` | — | — | owner #7 |
| `\empty` | — | — | owner #1 |
| `\emptyset` | `x \emptyset y` | ![](renders/emptyset.png) |  |
| `\enclose` | — | — | goldens: rej-unsup-enclose |
| `\end` | `\begin{pmatrix}a\end{pmatrix}` | ![](renders/end.png) |  |
| `\endgroup` | — | — | owner #1 |
| `\enspace` | — | — | owner #1 |
| `\Epsilon` | `x \Epsilon y` | ![](renders/epsilon.png) |  |
| `\epsilon` | `x \epsilon y` | ![](renders/epsilon-2.png) |  |
| `\eqalign` | — | — | goldens: rej-unsup-eqalign |
| `\eqalignno` | — | — | goldens: rej-unsup-eqalignno |
| `\eqcirc` | `x \eqcirc y` | ![](renders/eqcirc.png) |  |
| `\Eqcolon` | — | — | owner #1 |
| `\eqcolon` | — | — | owner #1 |
| `{equation}` | `\begin{equation}a=b\end{equation}` | *no render (overclaim)* | pinned KaTeX rejects equation; table needs a reject row |
| `{equation*}` | `\begin{equation*}a=b\end{equation*}` | *no render (overclaim)* | pinned KaTeX rejects equation*; table needs a reject row |
| `{eqnarray}` | — | — | goldens: rej-unsup-eqnarray |
| `\Eqqcolon` | — | — | owner #1 |
| `\eqqcolon` | — | — | owner #1 |
| `\eqref` | — | — | goldens: rej-unsup-eqref |
| `\eqsim` | — | — | owner #1 |
| `\eqslantgtr` | — | — | owner #1 |
| `\eqslantless` | — | — | owner #1 |
| `\equalscolon` | — | — | owner #1 |
| `\equalscoloncolon` | — | — | owner #1 |
| `\equiv` | `x \equiv y` | ![](renders/equiv.png) |  |
| `\Eta` | `x \Eta y` | ![](renders/eta.png) |  |
| `\eta` | `x \eta y` | ![](renders/eta-2.png) |  |
| `\eth` | `x \eth y` | ![](renders/eth.png) |  |
| `\euro` | — | — | goldens: rej-unsup-euro |
| `\exist` | — | — | owner #1 |
| `\exists` | `x \exists y` | ![](renders/exists.png) |  |
| `\exp` | `\exp x` | ![](renders/exp.png) |  |
| `\expandafter` | — | — | owner #1 |

## F

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\fallingdotseq` | — | — | owner #1 |
| `\fbox` | — | — | owner #7 |
| `\fcolorbox` | `\fcolorbox{red}{#ff0}{x}` | ![](renders/fcolorbox.png) |  |
| `\fi` | — | — | goldens: rej-unsup-fi |
| `\Finv` | `x \Finv y` | ![](renders/finv.png) |  |
| `\flat` | `x \flat y` | ![](renders/flat.png) |  |
| `\footnotesize` | — | — | owner #1 |
| `\forall` | `x \forall y` | ![](renders/forall.png) |  |
| `\frac` | `\frac{a}{b}` | ![](renders/frac.png) |  |
| `\frak` | — | — | owner #1 |
| `\frown` | `x \frown y` | ![](renders/frown.png) |  |
| `\futurelet` | — | — | owner #7 |

## G

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\Game` | `x \Game y` | ![](renders/game.png) |  |
| `\Gamma` | `x \Gamma y` | ![](renders/gamma.png) |  |
| `\gamma` | `x \gamma y` | ![](renders/gamma-2.png) |  |
| `{gather}` | `\begin{gather}a\\b\end{gather}` | *no render (overclaim)* | pinned KaTeX rejects gather; table needs a reject row |
| `{gathered}` | `\begin{gathered}a\\b\end{gathered}` | ![](renders/gathered.png) |  |
| `\gcd` | `\gcd x` | ![](renders/gcd.png) |  |
| `\gdef` | `\gdef\g{y}\g` | ![](renders/gdef.png) |  |
| `\ge` | `x \ge y` | ![](renders/ge.png) |  |
| `\geneuro` | — | — | goldens: rej-unsup-geneuro |
| `\geneuronarrow` | — | — | goldens: rej-unsup-geneuronarrow |
| `\geneurowide` | — | — | goldens: rej-unsup-geneurowide |
| `\genfrac` | `\genfrac(){0pt}{1}{a}{b}` | ![](renders/genfrac.png) |  |
| `\geq` | `x \geq y` | ![](renders/geq.png) |  |
| `\geqq` | — | — | owner #1 |
| `\geqslant` | — | — | owner #1 |
| `\gets` | `x \gets y` | ![](renders/gets.png) |  |
| `\gg` | `x \gg y` | ![](renders/gg.png) |  |
| `\ggg` | `x \ggg y` | ![](renders/ggg.png) |  |
| `\gggtr` | — | — | owner #1 |
| `\gimel` | `x \gimel y` | ![](renders/gimel.png) |  |
| `\global` | `\global\def\g{y}\g` | *no render (engine)* | global prefix missing; KaTeX accepts |
| `\gnapprox` | — | — | owner #1 |
| `\gneq` | — | — | owner #1 |
| `\gneqq` | — | — | owner #1 |
| `\gnsim` | — | — | owner #1 |
| `\grave` | `\grave{x}` | ![](renders/grave.png) |  |
| `\gt` | — | — | owner #1 |
| `\gtrdot` | — | — | owner #1 |
| `\gtrapprox` | `x \gtrapprox y` | ![](renders/gtrapprox.png) |  |
| `\gtreqless` | — | — | owner #1 |
| `\gtreqqless` | — | — | owner #1 |
| `\gtrless` | — | — | owner #1 |
| `\gtrsim` | `x \gtrsim y` | ![](renders/gtrsim.png) |  |
| `\gvertneqq` | — | — | owner #1 |

## H

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\H` | `\H{o}` | ![](renders/h.png) |  |
| `\Harr` | — | — | owner #1 |
| `\hArr` | — | — | owner #1 |
| `\harr` | — | — | owner #1 |
| `\hat` | `\hat{x}` | ![](renders/hat.png) |  |
| `\hbar` | `x \hbar y` | ![](renders/hbar.png) |  |
| `\hbox` | — | — | owner #7 |
| `\hbox to <dimen>` | — | — | KaTeX accepts (sweep-proven); owner #7 |
| `\hdashline` | `\begin{array}{c}a\\\hdashline b\end{array}` | ![](renders/hdashline.png) |  |
| `\hearts` | — | — | owner #1 |
| `\heartsuit` | `x \heartsuit y` | ![](renders/heartsuit.png) |  |
| `\hfil` | — | — | goldens: rej-unsup-hfil |
| `\hfill` | — | — | goldens: rej-unsup-hfill |
| `\hline` | `\begin{array}{c}a\\\hline b\end{array}` | ![](renders/hline.png) |  |
| `\hom` | `\hom x` | ![](renders/hom.png) |  |
| `\hookleftarrow` | `x \hookleftarrow y` | ![](renders/hookleftarrow.png) |  |
| `\hookrightarrow` | `x \hookrightarrow y` | ![](renders/hookrightarrow.png) |  |
| `\hphantom` | — | — | owner #7 |
| `\href` | `\href{https://example.com}{link}` | ![](renders/href.png) |  |
| `\hskip` | — | — | owner #1 |
| `\hslash` | `x \hslash y` | ![](renders/hslash.png) |  |
| `\hspace` | `a\hspace{1em}b` | ![](renders/hspace.png) |  |
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
| `\iiint` | `\iiint_{i=1}^n x` | ![](renders/iiint.png) |  |
| `\iint` | `\iint_{i=1}^n x` | ![](renders/iint.png) |  |
| `\Im` | `x \Im y` | ![](renders/im.png) |  |
| `\image` | — | — | owner #1 |
| `\imageof` | — | — | owner #1 |
| `\imath` | `x \imath y` | ![](renders/imath.png) |  |
| `\impliedby` | — | — | owner #1 |
| `\implies` | — | — | owner #1 |
| `\in` | `x \in y` | ![](renders/in.png) |  |
| `\includegraphics` | — | — | owner #7 |
| `\inf` | `\inf x` | ![](renders/inf.png) |  |
| `\infin` | — | — | owner #1 |
| `\infty` | `x \infty y` | ![](renders/infty.png) |  |
| `\injlim` | — | — | owner #1 |
| `\int` | `\int_{i=1}^n x` | ![](renders/int.png) |  |
| `\intercal` | — | — | owner #1 |
| `\intop` | — | — | owner #1 |
| `\Iota` | `x \Iota y` | ![](renders/iota.png) |  |
| `\iota` | `x \iota y` | ![](renders/iota-2.png) |  |
| `\isin` | — | — | owner #1 |
| `\it` | — | — | owner #1 |
| `\itshape` | — | — | goldens: rej-unsup-itshape |

## JK

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\j` | `\text{\j}` | ![](renders/j.png) |  |
| `\jmath` | `x \jmath y` | ![](renders/jmath.png) |  |
| `\Join` | `x \Join y` | ![](renders/join.png) |  |
| `\Kappa` | `x \Kappa y` | ![](renders/kappa.png) |  |
| `\kappa` | `x \kappa y` | ![](renders/kappa-2.png) |  |
| `\KaTeX` | — | — | owner #1 |
| `\ker` | `\ker x` | ![](renders/ker.png) |  |
| `\kern` | `a\kern2ptb` | ![](renders/kern.png) |  |
| `\Ket` | `\Ket{x}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\ket` | `\ket{x}` | *no render (engine)* | bra-ket notation missing; KaTeX accepts |
| `\Koppa` | — | — | goldens: rej-unsup-koppa |
| `\koppa` | — | — | goldens: rej-unsup-koppa-2 |

## L

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\L` | — | — | goldens: rej-unsup-l |
| `\l` | — | — | goldens: rej-unsup-l-2 |
| `\Lambda` | `x \Lambda y` | ![](renders/lambda.png) |  |
| `\lambda` | `x \lambda y` | ![](renders/lambda-2.png) |  |
| `\label` | — | — | goldens: rej-unsup-label |
| `\land` | `x \land y` | ![](renders/land.png) |  |
| `\lang` | `x \lang y` | ![](renders/lang.png) |  |
| `\langle` | `x \langle y` | ![](renders/langle.png) |  |
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
| `\lceil` | `x \lceil y` | ![](renders/lceil.png) |  |
| `\ldotp` | `x \ldotp y` | ![](renders/ldotp.png) |  |
| `\ldots` | `x \ldots y` | ![](renders/ldots.png) |  |
| `\le` | `x \le y` | ![](renders/le.png) |  |
| `\leadsto` | — | — | owner #1 |
| `\left` | `\left(x\right)` | ![](renders/left.png) |  |
| `\leftarrow` | `x \leftarrow y` | ![](renders/leftarrow.png) |  |
| `\Leftarrow` | `x \Leftarrow y` | ![](renders/leftarrow-2.png) |  |
| `\LeftArrow` | — | — | goldens: rej-unsup-leftarrow |
| `\leftarrowtail` | — | — | owner #1 |
| `\leftharpoondown` | `x \leftharpoondown y` | ![](renders/leftharpoondown.png) |  |
| `\leftharpoonup` | `x \leftharpoonup y` | ![](renders/leftharpoonup.png) |  |
| `\leftleftarrows` | — | — | owner #1 |
| `\Leftrightarrow` | `x \Leftrightarrow y` | ![](renders/leftrightarrow.png) |  |
| `\leftrightarrow` | `x \leftrightarrow y` | ![](renders/leftrightarrow-2.png) |  |
| `\leftrightarrows` | — | — | owner #1 |
| `\leftrightharpoons` | — | — | owner #1 |
| `\leftrightsquigarrow` | — | — | owner #1 |
| `\leftroot` | — | — | goldens: rej-unsup-leftroot |
| `\leftthreetimes` | — | — | owner #1 |
| `\leq` | `x \leq y` | ![](renders/leq.png) |  |
| `\leqalignno` | — | — | goldens: rej-unsup-leqalignno |
| `\leqq` | — | — | owner #1 |
| `\leqslant` | — | — | owner #1 |
| `\lessapprox` | `x \lessapprox y` | ![](renders/lessapprox.png) |  |
| `\lessdot` | — | — | owner #1 |
| `\lesseqgtr` | — | — | owner #1 |
| `\lesseqqgtr` | — | — | owner #1 |
| `\lessgtr` | — | — | owner #1 |
| `\lesssim` | `x \lesssim y` | ![](renders/lesssim.png) |  |
| `\let` | `\let\c=\alpha\c` | ![](renders/let.png) |  |
| `\lfloor` | `x \lfloor y` | ![](renders/lfloor.png) |  |
| `\lg` | `\lg x` | ![](renders/lg.png) |  |
| `\lgroup` | — | — | owner #4 |
| `\lhd` | `x \lhd y` | ![](renders/lhd.png) |  |
| `\lim` | `\lim_{x\to0}` | ![](renders/lim.png) |  |
| `\liminf` | `\liminf_{x\to0}` | ![](renders/liminf.png) |  |
| `\limits` | `\int\limits_0^1 x` | ![](renders/limits.png) |  |
| `\limsup` | `\limsup_{x\to0}` | ![](renders/limsup.png) |  |
| `\ll` | `x \ll y` | ![](renders/ll.png) |  |
| `\llap` | `\llap{x}y` | ![](renders/llap.png) |  |
| `\llbracket` | — | — | owner #1 |
| `\llcorner` | `x \llcorner y` | ![](renders/llcorner.png) |  |
| `\Lleftarrow` | — | — | owner #1 |
| `\lll` | `x \lll y` | ![](renders/lll.png) |  |
| `\llless` | — | — | owner #1 |
| `\lmoustache` | — | — | owner #4 |
| `\ln` | `\ln x` | ![](renders/ln.png) |  |
| `\lnapprox` | — | — | owner #1 |
| `\lneq` | — | — | owner #1 |
| `\lneqq` | — | — | owner #1 |
| `\lnot` | `x \lnot y` | ![](renders/lnot.png) |  |
| `\lnsim` | — | — | owner #1 |
| `\log` | `\log x` | ![](renders/log.png) |  |
| `\long` | — | — | owner #7 |
| `\Longleftarrow` | `x \Longleftarrow y` | ![](renders/longleftarrow.png) |  |
| `\longleftarrow` | `x \longleftarrow y` | ![](renders/longleftarrow-2.png) |  |
| `\Longleftrightarrow` | `x \Longleftrightarrow y` | ![](renders/longleftrightarrow.png) |  |
| `\longleftrightarrow` | `x \longleftrightarrow y` | ![](renders/longleftrightarrow-2.png) |  |
| `\longmapsto` | — | — | owner #1 |
| `\Longrightarrow` | `x \Longrightarrow y` | ![](renders/longrightarrow.png) |  |
| `\longrightarrow` | `x \longrightarrow y` | ![](renders/longrightarrow-2.png) |  |
| `\looparrowleft` | — | — | owner #1 |
| `\looparrowright` | — | — | owner #1 |
| `\lor` | `x \lor y` | ![](renders/lor.png) |  |
| `\lower` | — | — | goldens: rej-unsup-lower |
| `\lozenge` | — | — | owner #1 |
| `\lparen` | — | — | owner #1 |
| `\Lrarr` | — | — | owner #1 |
| `\lrArr` | — | — | owner #1 |
| `\lrarr` | — | — | owner #1 |
| `\lrcorner` | `x \lrcorner y` | ![](renders/lrcorner.png) |  |
| `\lq` | — | — | owner #1 |
| `\Lsh` | — | — | owner #1 |
| `\lt` | — | — | owner #1 |
| `\ltimes` | — | — | owner #1 |
| `\lVert` | `x \lVert y` | ![](renders/lvert.png) |  |
| `\lvert` | `x \lvert y` | ![](renders/lvert-2.png) |  |
| `\lvertneqq` | — | — | owner #1 |

## M

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\maltese` | `x \maltese y` | ![](renders/maltese.png) |  |
| `\mapsfrom` | — | — | owner #1 |
| `\mapsto` | `x \mapsto y` | ![](renders/mapsto.png) |  |
| `\mathbb` | `\mathbb{R}` | ![](renders/mathbb.png) |  |
| `\mathbf` | `\mathbf{B}` | ![](renders/mathbf.png) |  |
| `\mathbin` | — | — | owner #1 |
| `\mathcal` | `\mathcal{E}` | ![](renders/mathcal.png) |  |
| `\mathchoice` | `\mathchoice{a}{b}{c}{d}` | ![](renders/mathchoice.png) |  |
| `\mathclap` | `\mathclap{x}` | ![](renders/mathclap.png) |  |
| `\mathclose` | — | — | owner #1 |
| `\mathellipsis` | — | — | owner #1 |
| `\mathfrak` | `\mathfrak{G}` | ![](renders/mathfrak.png) |  |
| `\mathinner` | `\mathinner{x}` | *no render (engine)* | atom-class wrappers missing; KaTeX accepts |
| `\mathit` | `\mathit{C}` | ![](renders/mathit.png) |  |
| `\mathllap` | `\mathllap{x}y` | ![](renders/mathllap.png) |  |
| `\mathnormal` | — | — | owner #1 |
| `\mathop` | `\mathop{x}` | *no render (engine)* | atom-class wrappers missing; KaTeX accepts |
| `\mathopen` | — | — | owner #1 |
| `\mathord` | — | — | owner #1 |
| `\mathpunct` | — | — | owner #1 |
| `\mathreflectbox` | — | — | owner #1 |
| `\mathrel` | `\mathrel{x}` | *no render (engine)* | atom-class wrappers missing; KaTeX accepts |
| `\mathrlap` | `\mathrlap{x}y` | ![](renders/mathrlap.png) |  |
| `\mathring` | `\mathring{x}` | ![](renders/mathring.png) |  |
| `\mathrm` | `\mathrm{A}` | ![](renders/mathrm.png) |  |
| `\mathscr` | `\mathscr{F}` | ![](renders/mathscr.png) |  |
| `\mathsf` | `\mathsf{H}` | ![](renders/mathsf.png) |  |
| `\mathsterling` | — | — | owner #1 |
| `\mathstrut` | `x\mathstrut y` | *no render (engine)* | strut missing; KaTeX accepts |
| `\mathtip` | — | — | goldens: rej-unsup-mathtip |
| `\mathtt` | `\mathtt{I}` | ![](renders/mathtt.png) |  |
| `\matrix` | — | — | reject rows: rej-env-mismatch |
| `{matrix}` | `\begin{matrix}a&b\\c&d\end{matrix}` | ![](renders/matrix.png) |  |
| `{matrix*}` | `\begin{matrix*}a&b\\c&d\end{matrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\max` | `\max x` | ![](renders/max.png) |  |
| `\mbox` | — | — | goldens: rej-unsup-mbox |
| `\md` | — | — | goldens: rej-unsup-md |
| `\mdseries` | — | — | goldens: rej-unsup-mdseries |
| `\measuredangle` | `x \measuredangle y` | ![](renders/measuredangle.png) |  |
| `\medspace` | — | — | owner #1 |
| `\mho` | `x \mho y` | ![](renders/mho.png) |  |
| `\mid` | `x \mid y` | ![](renders/mid.png) |  |
| `\middle` | `\left(a\middle\|b\right)` | ![](renders/middle.png) |  |
| `\min` | `\min x` | ![](renders/min.png) |  |
| `\minuscolon` | — | — | owner #1 |
| `\minuscoloncolon` | — | — | owner #1 |
| `\minuso` | — | — | owner #1 |
| `\mit` | — | — | goldens: rej-unsup-mit |
| `\mkern` | — | — | owner #1 |
| `\mmlToken` | — | — | goldens: rej-unsup-mmltoken |
| `\mod` | `x\mod y` | *no render (engine)* | mod spacing missing; KaTeX accepts |
| `\models` | `x \models y` | ![](renders/models.png) |  |
| `\moveleft` | — | — | goldens: rej-unsup-moveleft |
| `\moveright` | — | — | goldens: rej-unsup-moveright |
| `\mp` | `x \mp y` | ![](renders/mp.png) |  |
| `\mskip` | — | — | owner #1 |
| `\mspace` | — | — | goldens: rej-unsup-mspace |
| `\Mu` | `x \Mu y` | ![](renders/mu.png) |  |
| `\mu` | `x \mu y` | ![](renders/mu-2.png) |  |
| `\multicolumn` | — | — | goldens: rej-unsup-multicolumn |
| `{multiline}` | — | — | goldens: rej-unsup-multiline |
| `\multimap` | — | — | owner #1 |

## N

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\N` | — | — | owner #1 |
| `\nabla` | `x \nabla y` | ![](renders/nabla.png) |  |
| `\natnums` | — | — | owner #1 |
| `\natural` | `x \natural y` | ![](renders/natural.png) |  |
| `\negmedspace` | — | — | owner #1 |
| `\ncong` | — | — | owner #1 |
| `\ne` | `x \ne y` | ![](renders/ne.png) |  |
| `\nearrow` | `x \nearrow y` | ![](renders/nearrow.png) |  |
| `\neg` | `x \neg y` | ![](renders/neg.png) |  |
| `\negthickspace` | — | — | owner #1 |
| `\negthinspace` | — | — | owner #1 |
| `\neq` | `x \neq y` | ![](renders/neq.png) |  |
| `\newcommand` | `\newcommand{\f}{x^2}\f` | ![](renders/newcommand.png) |  |
| `\newenvironment` | — | — | goldens: rej-unsup-newenvironment |
| `\Newextarrow` | — | — | goldens: rej-unsup-newextarrow |
| `\newline` | — | — | owner #1 |
| `\nexists` | `x \nexists y` | ![](renders/nexists.png) |  |
| `\ngeq` | — | — | owner #1 |
| `\ngeqq` | — | — | owner #1 |
| `\ngeqslant` | — | — | owner #1 |
| `\ngtr` | — | — | owner #1 |
| `\ni` | `x \ni y` | ![](renders/ni.png) |  |
| `\nleftarrow` | — | — | owner #1 |
| `\nLeftarrow` | — | — | owner #1 |
| `\nLeftrightarrow` | — | — | owner #1 |
| `\nleftrightarrow` | — | — | owner #1 |
| `\nleq` | — | — | owner #1 |
| `\nleqq` | — | — | owner #1 |
| `\nleqslant` | — | — | owner #1 |
| `\nless` | — | — | owner #1 |
| `\nmid` | `x \nmid y` | ![](renders/nmid.png) |  |
| `\nobreak` | — | — | owner #1 |
| `\nobreakspace` | — | — | owner #1 |
| `\noexpand` | — | — | owner #1 |
| `\nolimits` | `\sum\nolimits_{i} x` | ![](renders/nolimits.png) |  |
| `\nonumber` | `\begin{aligned}a&=b\nonumber\end{aligned}` | *no render (engine)* | equation numbering context missing; KaTeX accepts |
| `\normalfont` | — | — | goldens: rej-unsup-normalfont |
| `\normalsize` | — | — | owner #1 |
| `\not` | `a\not\in b` | ![](renders/not.png) |  |
| `\notag` | `\begin{aligned}a&=b\notag\end{aligned}` | *no render (engine)* | equation numbering context missing; KaTeX accepts |
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
| `\Nu` | `x \Nu y` | ![](renders/nu.png) |  |
| `\nu` | `x \nu y` | ![](renders/nu-2.png) |  |
| `\nVDash` | — | — | owner #1 |
| `\nVdash` | — | — | owner #1 |
| `\nvDash` | — | — | owner #1 |
| `\nvdash` | — | — | owner #1 |
| `\nwarrow` | `x \nwarrow y` | ![](renders/nwarrow.png) |  |

## O

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\O` | `\text{\O}` | ![](renders/o.png) |  |
| `\o` | `\text{\o}` | ![](renders/o-2.png) |  |
| `\odot` | `x \odot y` | ![](renders/odot.png) |  |
| `\OE` | `\text{\OE}` | ![](renders/oe.png) |  |
| `\oe` | `\text{\oe}` | ![](renders/oe-2.png) |  |
| `\officialeuro` | — | — | goldens: rej-unsup-officialeuro |
| `\oiiint` | — | — | owner #3 |
| `\oiint` | — | — | owner #3 |
| `\oint` | `\oint_{i=1}^n x` | ![](renders/oint.png) |  |
| `\oldstyle` | — | — | goldens: rej-unsup-oldstyle |
| `\omega` | `x \omega y` | ![](renders/omega.png) |  |
| `\Omega` | `x \Omega y` | ![](renders/omega-2.png) |  |
| `\Omicron` | — | — | owner #1 |
| `\omicron` | — | — | owner #1 |
| `\ominus` | `x \ominus y` | ![](renders/ominus.png) |  |
| `\operatorname` | `\operatorname{sin}x` | ![](renders/operatorname.png) |  |
| `\operatorname*` | `\operatorname*{lim}_{n}` | ![](renders/operatornamestar.png) |  |
| `\operatornamewithlimits` | `\operatornamewithlimits{lim}_n` | *no render (engine)* | with-limits operator name missing; KaTeX accepts |
| `\oplus` | `x \oplus y` | ![](renders/oplus.png) |  |
| `\or` | — | — | goldens: rej-unsup-or |
| `\origof` | — | — | owner #1 |
| `\oslash` | `x \oslash y` | ![](renders/oslash.png) |  |
| `\otimes` | `x \otimes y` | ![](renders/otimes.png) |  |
| `\over` | `{a\over b}` | ![](renders/over.png) |  |
| `\overbrace` | `x \overbrace y` | ![](renders/overbrace.png) |  |
| `\overbracket` | `x \overbracket y` | *no render (engine)* | bracket overline missing (brace works); KaTeX accepts |
| `\overgroup` | — | — | owner #5 |
| `\overleftarrow` | `x \overleftarrow y` | ![](renders/overleftarrow.png) |  |
| `\overleftharpoon` | — | — | owner #1 |
| `\overleftrightarrow` | — | — | owner #5 |
| `\overline` | `x \overline y` | ![](renders/overline.png) |  |
| `\overlinesegment` | — | — | owner #5 |
| `\overparen` | — | — | goldens: rej-unsup-overparen |
| `\Overrightarrow` | — | — | owner #1 |
| `\overrightarrow` | `x \overrightarrow y` | ![](renders/overrightarrow.png) |  |
| `\overrightharpoon` | — | — | owner #1 |
| `\overset` | `\overset{!}{=}` | ![](renders/overset.png) |  |
| `\overwithdelims` | — | — | goldens: rej-unsup-overwithdelims |
| `\owns` | `x \owns y` | ![](renders/owns.png) |  |

## P

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\P` | `\P` | ![](renders/p.png) |  |
| `\pagecolor` | — | — | goldens: rej-unsup-pagecolor |
| `\parallel` | `x \parallel y` | ![](renders/parallel.png) |  |
| `\part` | — | — | goldens: rej-unsup-part |
| `\partial` | `x \partial y` | ![](renders/partial.png) |  |
| `\perp` | `x \perp y` | ![](renders/perp.png) |  |
| `\phantom` | `\phantom{x}y` | ![](renders/phantom.png) |  |
| `\phase` | `\phase{30}` | *no render (engine)* | phase notation missing; KaTeX accepts |
| `\Phi` | `x \Phi y` | ![](renders/phi.png) |  |
| `\phi` | `x \phi y` | ![](renders/phi-2.png) |  |
| `\Pi` | `x \Pi y` | ![](renders/pi.png) |  |
| `\pi` | `x \pi y` | ![](renders/pi-2.png) |  |
| `{picture}` | — | — | goldens: rej-unsup-picture |
| `\pitchfork` | — | — | owner #1 |
| `\plim` | — | — | owner #1 |
| `\plusmn` | — | — | owner #1 |
| `\pm` | `x \pm y` | ![](renders/pm.png) |  |
| `\pmatrix` | — | — | goldens: rej-unsup-pmatrix |
| `{pmatrix}` | `\begin{pmatrix}a&b\\c&d\end{pmatrix}` | ![](renders/pmatrix.png) |  |
| `{pmatrix*}` | `\begin{pmatrix*}a&b\\c&d\end{pmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\pmb` | `\pmb{x}` | *no render (engine)* | poor-man's bold missing; KaTeX accepts |
| `\pmod` | — | — | owner #1 |
| `\pod` | — | — | owner #1 |
| `\pounds` | `x \pounds y` | ![](renders/pounds.png) |  |
| `\Pr` | `\Pr x` | ![](renders/pr.png) |  |
| `\prec` | `x \prec y` | ![](renders/prec.png) |  |
| `\precapprox` | — | — | owner #1 |
| `\preccurlyeq` | — | — | owner #1 |
| `\preceq` | `x \preceq y` | ![](renders/preceq.png) |  |
| `\precnapprox` | — | — | owner #1 |
| `\precneqq` | — | — | owner #1 |
| `\precnsim` | — | — | owner #1 |
| `\precsim` | — | — | owner #1 |
| `\prime` | `x \prime y` | ![](renders/prime-3.png) |  |
| `\prod` | `\prod_{i=1}^n x` | ![](renders/prod.png) |  |
| `\projlim` | — | — | owner #1 |
| `\propto` | `x \propto y` | ![](renders/propto.png) |  |
| `\providecommand` | `\providecommand{\g}{g}\g` | ![](renders/providecommand.png) |  |
| `\psi` | `x \psi y` | ![](renders/psi.png) |  |
| `\Psi` | `x \Psi y` | ![](renders/psi-2.png) |  |
| `\pu` | — | — | owner #1 |

## QR

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\Q` | — | — | goldens: rej-unsup-q |
| `\qquad` | `x\qquad y` | ![](renders/qquad.png) |  |
| `\quad` | `x\quad y` | ![](renders/quad.png) |  |
| `\R` | — | — | owner #1 |
| `\r` | `\r{a}` | ![](renders/r.png) |  |
| `\raise` | — | — | goldens: rej-unsup-raise |
| `\raisebox` | `\raisebox{2pt}{x}` | ![](renders/raisebox.png) |  |
| `\rang` | `x \rang y` | ![](renders/rang.png) |  |
| `\rangle` | `x \rangle y` | ![](renders/rangle.png) |  |
| `\Rarr` | — | — | owner #1 |
| `\rArr` | — | — | owner #1 |
| `\rarr` | — | — | owner #1 |
| `\ratio` | — | — | owner #1 |
| `\rBrace` | — | — | owner #1 |
| `\rbrace` | — | — | owner #1 |
| `\rbrack` | — | — | owner #1 |
| `{rcases}` | `\begin{rcases}1&x>0\end{rcases}` | *no render (engine)* | right-cases missing; KaTeX accepts |
| `\rceil` | `x \rceil y` | ![](renders/rceil.png) |  |
| `\Re` | `x \Re y` | ![](renders/re.png) |  |
| `\real` | — | — | owner #1 |
| `\Reals` | — | — | owner #1 |
| `\reals` | — | — | owner #1 |
| `\ref` | — | — | goldens: rej-unsup-ref |
| `\reflectbox` | — | — | owner #1 |
| `\relax` | — | — | owner #1 |
| `\renewcommand` | `\renewcommand{\sum}{S}\sum` | ![](renders/renewcommand.png) |  |
| `\renewenvironment` | — | — | goldens: rej-unsup-renewenvironment |
| `\require` | — | — | goldens: rej-unsup-require |
| `\restriction` | — | — | owner #1 |
| `\rfloor` | `x \rfloor y` | ![](renders/rfloor.png) |  |
| `\rgroup` | — | — | owner #4 |
| `\rhd` | `x \rhd y` | ![](renders/rhd.png) |  |
| `\Rho` | `x \Rho y` | ![](renders/rho.png) |  |
| `\rho` | `x \rho y` | ![](renders/rho-2.png) |  |
| `\right` | `\left(x\right)` | ![](renders/right.png) |  |
| `\Rightarrow` | `x \Rightarrow y` | ![](renders/rightarrow.png) |  |
| `\rightarrow` | `x \rightarrow y` | ![](renders/rightarrow-2.png) |  |
| `\rightarrowtail` | — | — | owner #1 |
| `\rightharpoondown` | `x \rightharpoondown y` | ![](renders/rightharpoondown.png) |  |
| `\rightharpoonup` | `x \rightharpoonup y` | ![](renders/rightharpoonup.png) |  |
| `\rightleftarrows` | — | — | owner #1 |
| `\rightleftharpoons` | `x \rightleftharpoons y` | ![](renders/rightleftharpoons.png) |  |
| `\rightrightarrows` | — | — | owner #1 |
| `\rightsquigarrow` | — | — | owner #1 |
| `\rightthreetimes` | — | — | owner #1 |
| `\risingdotseq` | — | — | owner #1 |
| `\rlap` | `\rlap{x}y` | ![](renders/rlap.png) |  |
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
| `\rule` | `\rule{1em}{2pt}` | ![](renders/rule.png) |  |
| `\rVert` | `x \rVert y` | ![](renders/rvert.png) |  |
| `\rvert` | `x \rvert y` | ![](renders/rvert-2.png) |  |

## S

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\S` | `\S` | ![](renders/s.png) |  |
| `\Sampi` | — | — | goldens: rej-unsup-sampi |
| `\sampi` | — | — | goldens: rej-unsup-sampi-2 |
| `\sc` | — | — | goldens: rej-unsup-sc |
| `\scalebox` | — | — | goldens: rej-unsup-scalebox |
| `\scr` | — | — | goldens: rej-unsup-scr |
| `\scriptscriptstyle` | `{\scriptscriptstyle\sum_i x}` | ![](renders/scriptscriptstyle.png) |  |
| `\scriptsize` | — | — | owner #1 |
| `\scriptstyle` | `{\scriptstyle\sum_i x}` | ![](renders/scriptstyle.png) |  |
| `\sdot` | — | — | owner #1 |
| `\searrow` | `x \searrow y` | ![](renders/searrow.png) |  |
| `\sec` | `\sec x` | ![](renders/sec.png) |  |
| `\sect` | `\sect` | ![](renders/sect.png) |  |
| `\set` | — | — | owner #1 |
| `\Set` | `\Set{x\|x>0}` | *no render (engine)* | set notation missing; KaTeX accepts |
| `\setlength` | — | — | goldens: rej-unsup-setlength |
| `\setminus` | `x \setminus y` | ![](renders/setminus.png) |  |
| `\sf` | — | — | owner #1 |
| `\sharp` | `x \sharp y` | ![](renders/sharp.png) |  |
| `\shortmid` | — | — | owner #1 |
| `\shortparallel` | — | — | owner #1 |
| `\shoveleft` | — | — | goldens: rej-unsup-shoveleft |
| `\shoveright` | — | — | goldens: rej-unsup-shoveright |
| `\sideset` | — | — | goldens: rej-unsup-sideset |
| `\Sigma` | `x \Sigma y` | ![](renders/sigma.png) |  |
| `\sigma` | `x \sigma y` | ![](renders/sigma-2.png) |  |
| `\sim` | `x \sim y` | ![](renders/sim.png) |  |
| `\simcolon` | — | — | owner #1 |
| `\simcoloncolon` | — | — | owner #1 |
| `\simeq` | `x \simeq y` | ![](renders/simeq.png) |  |
| `\sin` | `\sin x` | ![](renders/sin.png) |  |
| `\sinh` | `\sinh x` | ![](renders/sinh.png) |  |
| `\sixptsize` | — | — | owner #1 |
| `\sh` | — | — | owner #1 |
| `\skew` | — | — | goldens: rej-unsup-skew |
| `\skip` | — | — | goldens: rej-unsup-skip |
| `\sl` | — | — | goldens: rej-unsup-sl |
| `\small` | — | — | owner #1 |
| `\smallfrown` | — | — | owner #1 |
| `\smallint` | — | — | owner #1 |
| `{smallmatrix}` | `\bigl(\begin{smallmatrix}a&b\\c&d\end{smallmatrix}\bigr)` | ![](renders/smallmatrix.png) |  |
| `\smallsetminus` | — | — | owner #1 |
| `\smallsmile` | — | — | owner #1 |
| `\smash` | `\smash[t]{x}^{2}` | ![](renders/smash.png) |  |
| `\smile` | `x \smile y` | ![](renders/smile.png) |  |
| `\smiley` | — | — | goldens: rej-unsup-smiley |
| `\sout` | `\sout{x}` | *no render (engine)* | strikeout missing; KaTeX accepts |
| `\Space` | — | — | goldens: rej-unsup-space |
| `\space` | — | — | owner #1 |
| `\spades` | — | — | owner #1 |
| `\spadesuit` | `x \spadesuit y` | ![](renders/spadesuit.png) |  |
| `\sphericalangle` | `x \sphericalangle y` | ![](renders/sphericalangle.png) |  |
| `{split}` | `\begin{equation}\begin{split}a&=b\\c&=d\end{split}\end{equation}` | *no render (overclaim)* | pinned KaTeX rejects standalone split; table needs a reject row |
| `\sqcap` | `x \sqcap y` | ![](renders/sqcap.png) |  |
| `\sqcup` | `x \sqcup y` | ![](renders/sqcup.png) |  |
| `\square` | — | — | owner #1 |
| `\sqrt` | `\sqrt{x}` | ![](renders/sqrt.png) |  |
| `\sqsubset` | `x \sqsubset y` | ![](renders/sqsubset.png) |  |
| `\sqsubseteq` | `x \sqsubseteq y` | ![](renders/sqsubseteq.png) |  |
| `\sqsupset` | `x \sqsupset y` | ![](renders/sqsupset.png) |  |
| `\sqsupseteq` | `x \sqsupseteq y` | ![](renders/sqsupseteq.png) |  |
| `\ss` | `\text{\ss}` | ![](renders/ss.png) |  |
| `\stackrel` | — | — | owner #1 |
| `\star` | `x \star y` | ![](renders/star.png) |  |
| `\Stigma` | — | — | goldens: rej-unsup-stigma |
| `\stigma` | — | — | goldens: rej-unsup-stigma-2 |
| `\strut` | — | — | goldens: rej-unsup-strut |
| `\style` | — | — | goldens: rej-unsup-style |
| `\sub` | — | — | owner #1 |
| `{subarray}` | — | — | KaTeX accepts with alignment arg (sweep-proven); owner #14 |
| `\sube` | — | — | owner #1 |
| `\Subset` | — | — | owner #1 |
| `\subset` | `x \subset y` | ![](renders/subset.png) |  |
| `\subseteq` | `x \subseteq y` | ![](renders/subseteq.png) |  |
| `\subseteqq` | — | — | owner #1 |
| `\subsetneq` | `x \subsetneq y` | ![](renders/subsetneq.png) |  |
| `\subsetneqq` | — | — | owner #1 |
| `\substack` | `\sum_{\substack{a\\b}}x` | ![](renders/substack.png) |  |
| `\succ` | `x \succ y` | ![](renders/succ.png) |  |
| `\succapprox` | — | — | owner #1 |
| `\succcurlyeq` | — | — | owner #1 |
| `\succeq` | `x \succeq y` | ![](renders/succeq.png) |  |
| `\succnapprox` | — | — | owner #1 |
| `\succneqq` | — | — | owner #1 |
| `\succnsim` | — | — | owner #1 |
| `\succsim` | — | — | owner #1 |
| `\sum` | `\sum_{i=1}^n x` | ![](renders/sum.png) |  |
| `\sup` | `\sup x` | ![](renders/sup.png) |  |
| `\supe` | — | — | owner #1 |
| `\Supset` | — | — | owner #1 |
| `\supset` | `x \supset y` | ![](renders/supset.png) |  |
| `\supseteq` | `x \supseteq y` | ![](renders/supseteq.png) |  |
| `\supseteqq` | — | — | owner #1 |
| `\supsetneq` | `x \supsetneq y` | ![](renders/supsetneq.png) |  |
| `\supsetneqq` | — | — | owner #1 |
| `\surd` | `x \surd y` | ![](renders/surd.png) |  |
| `\swarrow` | `x \swarrow y` | ![](renders/swarrow.png) |  |

## T

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\tag` | — | — | owner #1 |
| `\tag*` | — | — | owner #1 |
| `\tan` | `\tan x` | ![](renders/tan.png) |  |
| `\tanh` | `\tanh x` | ![](renders/tanh.png) |  |
| `\Tau` | `x \Tau y` | ![](renders/tau.png) |  |
| `\tau` | `x \tau y` | ![](renders/tau-2.png) |  |
| `\tbinom` | — | — | owner #2 |
| `\TeX` | — | — | owner #1 |
| `\text` | `\text{for }x` | ![](renders/text.png) |  |
| `\textasciitilde` | `\text{\textasciitilde}` | ![](renders/textasciitilde.png) |  |
| `\textasciicircum` | `\text{\textasciicircum}` | ![](renders/textasciicircum.png) |  |
| `\textbackslash` | `\text{\textbackslash}` | ![](renders/textbackslash.png) |  |
| `\textbar` | `\text{\textbar}` | ![](renders/textbar.png) |  |
| `\textbardbl` | `\text{\textbardbl}` | ![](renders/textbardbl.png) |  |
| `\textbf` | `\textbf{a+b}` | ![](renders/textbf.png) |  |
| `\textbraceleft` | `\text{\textbraceleft}` | ![](renders/textbraceleft.png) |  |
| `\textbraceright` | `\text{\textbraceright}` | ![](renders/textbraceright.png) |  |
| `\textcircled` | `\textcircled{a}` | *no render (engine)* | enclosing circle missing; KaTeX accepts |
| `\textcolor` | `\textcolor{blue}{x}` | ![](renders/textcolor.png) |  |
| `\textdagger` | `\text{\textdagger}` | ![](renders/textdagger.png) |  |
| `\textdaggerdbl` | `\text{\textdaggerdbl}` | ![](renders/textdaggerdbl.png) |  |
| `\textdegree` | `\text{\textdegree}` | ![](renders/textdegree.png) |  |
| `\textdollar` | `\text{\textdollar}` | ![](renders/textdollar.png) |  |
| `\textellipsis` | `\text{\textellipsis}` | ![](renders/textellipsis.png) |  |
| `\textemdash` | `\text{\textemdash}` | ![](renders/textemdash.png) |  |
| `\textendash` | `\text{\textendash}` | ![](renders/textendash.png) |  |
| `\textgreater` | `\text{\textgreater}` | ![](renders/textgreater.png) |  |
| `\textit` | `\textit{a+b}` | ![](renders/textit.png) |  |
| `\textless` | `\text{\textless}` | ![](renders/textless.png) |  |
| `\textmd` | — | — | owner #1 |
| `\textnormal` | `\textnormal{x}` | ![](renders/textnormal.png) |  |
| `\textquotedblleft` | `\text{\textquotedblleft}` | ![](renders/textquotedblleft.png) |  |
| `\textquotedblright` | `\text{\textquotedblright}` | ![](renders/textquotedblright.png) |  |
| `\textquoteleft` | `\text{\textquoteleft}` | ![](renders/textquoteleft.png) |  |
| `\textquoteright` | `\text{\textquoteright}` | ![](renders/textquoteright.png) |  |
| `\textregistered` | `\textregistered` | ![](renders/textregistered.png) |  |
| `\textrm` | `\textrm{x}` | ![](renders/textrm.png) |  |
| `\textsc` | — | — | goldens: rej-unsup-textsc |
| `\textsf` | `\textsf{x}` | ![](renders/textsf.png) |  |
| `\textsl` | — | — | reject rows: textsl |
| `\textsterling` | `\text{\textsterling}` | ![](renders/textsterling.png) |  |
| `\textstyle` | `{\textstyle\sum_i x}` | ![](renders/textstyle.png) |  |
| `\texttip` | — | — | goldens: rej-unsup-texttip |
| `\texttt` | `\texttt{x}` | ![](renders/texttt.png) |  |
| `\textunderscore` | `\text{\textunderscore}` | ![](renders/textunderscore.png) |  |
| `\textup` | — | — | owner #1 |
| `\textvisiblespace` | — | — | goldens: rej-unsup-textvisiblespace |
| `\tfrac` | `\tfrac{a}{b}` | ![](renders/tfrac.png) |  |
| `\tg` | — | — | owner #1 |
| `\th` | — | — | owner #1 |
| `\therefore` | — | — | owner #1 |
| `\Theta` | `x \Theta y` | ![](renders/theta.png) |  |
| `\theta` | `x \theta y` | ![](renders/theta-2.png) |  |
| `\thetasym` | — | — | owner #1 |
| `\thickapprox` | — | — | owner #1 |
| `\thicksim` | — | — | owner #1 |
| `\thickspace` | — | — | owner #1 |
| `\thinspace` | — | — | owner #1 |
| `\tilde` | `\tilde{x}` | ![](renders/tilde-3.png) |  |
| `\times` | `x \times y` | ![](renders/times.png) |  |
| `\Tiny` | — | — | goldens: rej-unsup-tiny |
| `\tiny` | — | — | owner #1 |
| `\to` | `x \to y` | ![](renders/to.png) |  |
| `\toggle` | — | — | goldens: rej-unsup-toggle |
| `\top` | `x \top y` | ![](renders/top.png) |  |
| `\triangle` | — | — | owner #1 |
| `\triangledown` | — | — | owner #1 |
| `\triangleleft` | `x \triangleleft y` | ![](renders/triangleleft.png) |  |
| `\trianglelefteq` | — | — | owner #1 |
| `\triangleq` | — | — | owner #1 |
| `\triangleright` | `x \triangleright y` | ![](renders/triangleright.png) |  |
| `\trianglerighteq` | — | — | owner #1 |
| `\tt` | — | — | owner #1 |
| `\twoheadleftarrow` | — | — | owner #1 |
| `\twoheadrightarrow` | — | — | owner #1 |

## U

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\u` | `\u{x}` | ![](renders/u.png) |  |
| `\Uarr` | — | — | owner #1 |
| `\uArr` | — | — | owner #1 |
| `\uarr` | — | — | owner #1 |
| `\ulcorner` | `x \ulcorner y` | ![](renders/ulcorner.png) |  |
| `\underbar` | — | — | owner #1 |
| `\underbrace` | `x \underbrace y` | ![](renders/underbrace.png) |  |
| `\underbracket` | `x \underbracket y` | *no render (engine)* | bracket underline missing; KaTeX accepts |
| `\undergroup` | — | — | owner #5 |
| `\underleftarrow` | — | — | owner #5 |
| `\underleftrightarrow` | — | — | owner #5 |
| `\underrightarrow` | — | — | owner #5 |
| `\underline` | `x \underline y` | ![](renders/underline.png) |  |
| `\underlinesegment` | — | — | owner #5 |
| `\underparen` | — | — | goldens: rej-unsup-underparen |
| `\underset` | `\underset{*}{+}` | ![](renders/underset.png) |  |
| `\unicode` | — | — | goldens: rej-unsup-unicode |
| `\unlhd` | `x \unlhd y` | ![](renders/unlhd.png) |  |
| `\unrhd` | `x \unrhd y` | ![](renders/unrhd.png) |  |
| `\up` | — | — | goldens: rej-unsup-up |
| `\Uparrow` | `x \Uparrow y` | ![](renders/uparrow.png) |  |
| `\uparrow` | `x \uparrow y` | ![](renders/uparrow-2.png) |  |
| `\Updownarrow` | `x \Updownarrow y` | ![](renders/updownarrow.png) |  |
| `\updownarrow` | `x \updownarrow y` | ![](renders/updownarrow-2.png) |  |
| `\upharpoonleft` | — | — | owner #1 |
| `\upharpoonright` | — | — | owner #1 |
| `\uplus` | `x \uplus y` | ![](renders/uplus.png) |  |
| `\uproot` | — | — | goldens: rej-unsup-uproot |
| `\upshape` | — | — | goldens: rej-unsup-upshape |
| `\Upsilon` | `x \Upsilon y` | ![](renders/upsilon.png) |  |
| `\upsilon` | `x \upsilon y` | ![](renders/upsilon-2.png) |  |
| `\upuparrows` | — | — | owner #1 |
| `\urcorner` | `x \urcorner y` | ![](renders/urcorner.png) |  |
| `\url` | `\url{https://example.com/a}` | ![](renders/url.png) |  |
| `\utilde` | — | — | owner #5 |

## V

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\v` | `\v{x}` | ![](renders/v.png) |  |
| `\varcoppa` | — | — | goldens: rej-unsup-varcoppa |
| `\varDelta` | — | — | owner #1 |
| `\varepsilon` | `x \varepsilon y` | ![](renders/varepsilon.png) |  |
| `\varGamma` | — | — | owner #1 |
| `\varinjlim` | — | — | owner #1 |
| `\varkappa` | — | — | owner #1 |
| `\varLambda` | — | — | owner #1 |
| `\varliminf` | — | — | owner #1 |
| `\varlimsup` | — | — | owner #1 |
| `\varnothing` | `x \varnothing y` | ![](renders/varnothing.png) |  |
| `\varOmega` | — | — | owner #1 |
| `\varPhi` | — | — | owner #1 |
| `\varphi` | `x \varphi y` | ![](renders/varphi.png) |  |
| `\varPi` | — | — | owner #1 |
| `\varpi` | `x \varpi y` | ![](renders/varpi.png) |  |
| `\varprojlim` | — | — | owner #1 |
| `\varpropto` | — | — | owner #1 |
| `\varPsi` | — | — | owner #1 |
| `\varrho` | `x \varrho y` | ![](renders/varrho.png) |  |
| `\varSigma` | — | — | owner #1 |
| `\varsigma` | `x \varsigma y` | ![](renders/varsigma.png) |  |
| `\varstigma` | — | — | goldens: rej-unsup-varstigma |
| `\varsubsetneq` | — | — | owner #1 |
| `\varsubsetneqq` | — | — | owner #1 |
| `\varsupsetneq` | — | — | owner #1 |
| `\varsupsetneqq` | — | — | owner #1 |
| `\varTheta` | — | — | owner #1 |
| `\vartheta` | `x \vartheta y` | ![](renders/vartheta.png) |  |
| `\vartriangle` | — | — | owner #1 |
| `\vartriangleleft` | — | — | owner #1 |
| `\vartriangleright` | — | — | owner #1 |
| `\varUpsilon` | — | — | owner #1 |
| `\varXi` | — | — | owner #1 |
| `\vcentcolon` | — | — | owner #1 |
| `\vcenter` | `\vcenter{x}` | *no render (engine)* | vertical centering missing; KaTeX accepts |
| `\Vdash` | — | — | owner #1 |
| `\vDash` | — | — | owner #1 |
| `\vdash` | `x \vdash y` | ![](renders/vdash.png) |  |
| `\vdots` | `x \vdots y` | ![](renders/vdots.png) |  |
| `\vec` | `\vec{x}` | ![](renders/vec.png) |  |
| `\vee` | `x \vee y` | ![](renders/vee.png) |  |
| `\veebar` | — | — | owner #1 |
| `\verb` | `\verb\|x\|` | ![](renders/verb.png) |  |
| `\Vert` | `x \Vert y` | ![](renders/vert.png) |  |
| `\vert` | `x \vert y` | ![](renders/vert-2.png) |  |
| `\vfil` | — | — | goldens: rej-unsup-vfil |
| `\vfill` | — | — | goldens: rej-unsup-vfill |
| `\vline` | — | — | goldens: rej-unsup-vline |
| `{Vmatrix}` | `\begin{Vmatrix}a&b\\c&d\end{Vmatrix}` | ![](renders/vmatrix.png) |  |
| `{Vmatrix*}` | `\begin{Vmatrix*}a&b\\c&d\end{Vmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `{vmatrix}` | `\begin{vmatrix}a&b\\c&d\end{vmatrix}` | ![](renders/vmatrix-2.png) |  |
| `{vmatrix*}` | `\begin{vmatrix*}a&b\\c&d\end{vmatrix*}` | *no render (engine)* | starred env names do not lex; KaTeX accepts |
| `\vphantom` | `\vphantom{X}y` | ![](renders/vphantom.png) |  |
| `\Vvdash` | — | — | owner #1 |

## W

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\wedge` | `x \wedge y` | ![](renders/wedge.png) |  |
| `\weierp` | — | — | owner #1 |
| `\widecheck` | `\widecheck{x}` | ![](renders/widecheck.png) |  |
| `\widehat` | `\widehat{x}` | ![](renders/widehat.png) |  |
| `\wideparen` | — | — | goldens: rej-unsup-wideparen |
| `\widetilde` | `\widetilde{x}` | ![](renders/widetilde.png) |  |
| `\wp` | `x \wp y` | ![](renders/wp.png) |  |
| `\wr` | `x \wr y` | ![](renders/wr.png) |  |

## X

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\xcancel` | — | — | owner #7 |
| `\xdef` | `\xdef\g{y}\g` | *no render (engine)* | xdef macro definition missing; KaTeX accepts |
| `\Xi` | `x \Xi y` | ![](renders/xi.png) |  |
| `\xi` | `x \xi y` | ![](renders/xi-2.png) |  |
| `\xhookleftarrow` | — | — | owner #1 |
| `\xhookrightarrow` | — | — | owner #1 |
| `\xLeftarrow` | — | — | owner #1 |
| `\xleftarrow` | `\xleftarrow[sub]{sup}` | ![](renders/xleftarrow.png) |  |
| `\xleftharpoondown` | — | — | owner #1 |
| `\xleftharpoonup` | — | — | owner #1 |
| `\xLeftrightarrow` | — | — | owner #1 |
| `\xleftrightarrow` | — | — | owner #1 |
| `\xleftrightharpoons` | — | — | owner #1 |
| `\xlongequal` | — | — | owner #1 |
| `\xmapsto` | — | — | owner #1 |
| `\xRightarrow` | — | — | owner #1 |
| `\xrightarrow` | `\xrightarrow{a}b` | ![](renders/xrightarrow.png) |  |
| `\xrightharpoondown` | — | — | owner #1 |
| `\xrightharpoonup` | — | — | owner #1 |
| `\xrightleftharpoons` | — | — | owner #1 |
| `\xtofrom` | — | — | owner #1 |
| `\xtwoheadleftarrow` | — | — | owner #1 |
| `\xtwoheadrightarrow` | — | — | owner #1 |

## YZ

| Function | Example | Render | Note |
| --- | --- | --- | --- |
| `\yen` | `x \yen y` | ![](renders/yen.png) |  |
| `\Z` | — | — | owner #1 |
| `\Zeta` | `x \Zeta y` | ![](renders/zeta.png) |  |
| `\zeta` | `x \zeta y` | ![](renders/zeta-2.png) |  |

