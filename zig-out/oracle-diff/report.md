# Oracle diff report (triage only — not a gate, not truth)

ZaTeX vs 3 independent oracle engines per case. `score(c) = max` oracle similarity: closeness to *at least one* oracle means low attention; a low max means ZaTeX is the solo outlier. `spread` is the minimum oracle-oracle similarity; rows with spread < 0.90 are tagged `spec-ambiguous` (oracles disagree with each other — spec ambiguity, never a ZaTeX bug). When oracles disagree, pinned KaTeX 0.18.7 remains the sole truth for accept/reject and geometry disputes.

Normalization per case: tight-crop ink bbox + 10px white pad, uniform rescale to height 128 (aspect preserved), centered on the union canvas; block SSIM on grayscale. Absolute-size divergences are out of scope here (covered by layout-IR tests).

| case | source | score | KaTeX | MathJax | LuaTeX | spread | tag | renders |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mat-pmatrix #33 | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` | 0.264 | 0.264 | 0.163 | 0.184 | 0.271 | spec-ambiguous | [Z](png/mat-pmatrix.zatex.png) [K](png/mat-pmatrix.katex.png) [M](png/mat-pmatrix.mathjax.png) [L](png/mat-pmatrix.luatex.png) |
| frac-binom #32 | `\binom n k` | 0.341 | 0.251 | 0.161 | 0.341 | 0.175 | spec-ambiguous | [Z](png/frac-binom.zatex.png) [K](png/frac-binom.katex.png) [M](png/frac-binom.mathjax.png) [L](png/frac-binom.luatex.png) |
| brace-over  | `\overbrace{a+b}^{n}` | 0.480 | 0.436 | 0.477 | 0.480 | 0.432 | spec-ambiguous | [Z](png/brace-over.zatex.png) [K](png/brace-over.katex.png) [M](png/brace-over.mathjax.png) [L](png/brace-over.luatex.png) |
| op-lim  | `\lim_{x\to 0} f(x)` | 0.495 | 0.439 | 0.332 | 0.495 | 0.254 | spec-ambiguous | [Z](png/op-lim.zatex.png) [K](png/op-lim.katex.png) [M](png/op-lim.mathjax.png) [L](png/op-lim.luatex.png) |
| frac-dfrac #32 | `\dfrac{a-1}{b-1}` | 0.510 | 0.480 | 0.307 | 0.510 | 0.368 | spec-ambiguous | [Z](png/frac-dfrac.zatex.png) [K](png/frac-dfrac.katex.png) [M](png/frac-dfrac.mathjax.png) [L](png/frac-dfrac.luatex.png) |
| space-kern #36 | `I\kern-2.5pt R` | 0.514 | 0.306 | 0.205 | 0.514 | 0.415 | spec-ambiguous | [Z](png/space-kern.zatex.png) [K](png/space-kern.katex.png) [M](png/space-kern.mathjax.png) [L](png/space-kern.luatex.png) |
| agree-int  | `\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}` | 0.519 | 0.507 | 0.479 | 0.519 | 0.450 | spec-ambiguous | [Z](png/agree-int.zatex.png) [K](png/agree-int.katex.png) [M](png/agree-int.mathjax.png) [L](png/agree-int.luatex.png) |
| color-plain #35 | `\color{#0000FF} AaBb123` | 0.527 | 0.348 | 0.322 | 0.527 | 0.319 | spec-ambiguous | [Z](png/color-plain.zatex.png) [K](png/color-plain.katex.png) [M](png/color-plain.mathjax.png) [L](png/color-plain.luatex.png) |
| acc-ddot  | `\ddot{y}` | 0.527 | 0.385 | 0.494 | 0.527 | 0.412 | spec-ambiguous | [Z](png/acc-ddot.zatex.png) [K](png/acc-ddot.katex.png) [M](png/acc-ddot.mathjax.png) [L](png/acc-ddot.luatex.png) |
| sqrt-frac  | `\sqrt{\frac{a}{b}}` | 0.550 | 0.455 | 0.277 | 0.550 | 0.258 | spec-ambiguous | [Z](png/sqrt-frac.zatex.png) [K](png/sqrt-frac.katex.png) [M](png/sqrt-frac.mathjax.png) [L](png/sqrt-frac.luatex.png) |
| mat-array #33 | `\begin{array}{cc} a & b \\ c & d \end{array}` | 0.551 | 0.551 | 0.384 | 0.380 | 0.369 | spec-ambiguous | [Z](png/mat-array.zatex.png) [K](png/mat-array.katex.png) [M](png/mat-array.mathjax.png) [L](png/mat-array.luatex.png) |
| font-bf #34 | `\mathbf{AaBb123}` | 0.552 | 0.305 | 0.411 | 0.552 | 0.266 | spec-ambiguous | [Z](png/font-bf.zatex.png) [K](png/font-bf.katex.png) [M](png/font-bf.mathjax.png) [L](png/font-bf.luatex.png) |
| acc-bar #30 | `\bar{y}` | 0.555 | 0.386 | 0.529 | 0.555 | 0.447 | spec-ambiguous | [Z](png/acc-bar.zatex.png) [K](png/acc-bar.katex.png) [M](png/acc-bar.mathjax.png) [L](png/acc-bar.luatex.png) |
| miss-circleds #37 | `\circledS` | 0.559 | 0.413 | 0.551 | 0.559 | 0.400 | spec-ambiguous | [Z](png/miss-circleds.zatex.png) [K](png/miss-circleds.katex.png) [M](png/miss-circleds.mathjax.png) [L](png/miss-circleds.luatex.png) |
| space-thin #36 | `a\,\,{b}` | 0.561 | 0.516 | 0.539 | 0.561 | 0.420 | spec-ambiguous | [Z](png/space-thin.zatex.png) [K](png/space-thin.katex.png) [M](png/space-thin.mathjax.png) [L](png/space-thin.luatex.png) |
| acc-hat #30 | `\hat{\theta}` | 0.568 | 0.498 | 0.313 | 0.568 | 0.321 | spec-ambiguous | [Z](png/acc-hat.zatex.png) [K](png/acc-hat.katex.png) [M](png/acc-hat.mathjax.png) [L](png/acc-hat.luatex.png) |
| delim-auto  | `\left(\frac{a}{b}\right)` | 0.571 | 0.460 | 0.118 | 0.571 | 0.070 | spec-ambiguous | [Z](png/delim-auto.zatex.png) [K](png/delim-auto.katex.png) [M](png/delim-auto.mathjax.png) [L](png/delim-auto.luatex.png) |
| brace-under  | `\underbrace{c}_{m}` | 0.574 | 0.556 | 0.564 | 0.574 | 0.548 | spec-ambiguous | [Z](png/brace-under.zatex.png) [K](png/brace-under.katex.png) [M](png/brace-under.mathjax.png) [L](png/brace-under.luatex.png) |
| wide-tilde #31 | `\widetilde{AB}` | 0.575 | 0.480 | 0.483 | 0.575 | 0.409 | spec-ambiguous | [Z](png/wide-tilde.zatex.png) [K](png/wide-tilde.katex.png) [M](png/wide-tilde.mathjax.png) [L](png/wide-tilde.luatex.png) |
| brace-both  | `\overbrace{a+b}^{n} + \underbrace{c}_{m}` | 0.578 | 0.506 | 0.578 | 0.534 | 0.514 | spec-ambiguous | [Z](png/brace-both.zatex.png) [K](png/brace-both.katex.png) [M](png/brace-both.mathjax.png) [L](png/brace-both.luatex.png) |
| acc-vec #30 | `\vec{F}` | 0.599 | 0.523 | 0.565 | 0.599 | 0.536 | spec-ambiguous | [Z](png/acc-vec.zatex.png) [K](png/acc-vec.katex.png) [M](png/acc-vec.mathjax.png) [L](png/acc-vec.luatex.png) |
| wide-hat #31 | `\widehat{AB}` | 0.602 | 0.426 | 0.527 | 0.602 | 0.391 | spec-ambiguous | [Z](png/wide-hat.zatex.png) [K](png/wide-hat.katex.png) [M](png/wide-hat.mathjax.png) [L](png/wide-hat.luatex.png) |
| acc-dddot  | `\dddot{z}` | 0.607 | 0.576 | 0.607 | 0.585 | 0.412 | spec-ambiguous | [Z](png/acc-dddot.zatex.png) [K](png/acc-dddot.katex.png) [M](png/acc-dddot.mathjax.png) [L](png/acc-dddot.luatex.png) |
| acc-tilde  | `\tilde{x}` | 0.616 | 0.497 | 0.586 | 0.616 | 0.530 | spec-ambiguous | [Z](png/acc-tilde.zatex.png) [K](png/acc-tilde.katex.png) [M](png/acc-tilde.mathjax.png) [L](png/acc-tilde.luatex.png) |
| sqrt-disp  | `\sqrt{x^2+1}` | 0.620 | 0.462 | 0.416 | 0.620 | 0.366 | spec-ambiguous | [Z](png/sqrt-disp.zatex.png) [K](png/sqrt-disp.katex.png) [M](png/sqrt-disp.mathjax.png) [L](png/sqrt-disp.luatex.png) |
| sqrt-nest  | `\sqrt{1+\sqrt{1+x}}` | 0.627 | 0.507 | 0.462 | 0.627 | 0.402 | spec-ambiguous | [Z](png/sqrt-nest.zatex.png) [K](png/sqrt-nest.katex.png) [M](png/sqrt-nest.mathjax.png) [L](png/sqrt-nest.luatex.png) |
| sup-nest  | `x^{y^z}` | 0.629 | 0.548 | 0.527 | 0.629 | 0.497 | spec-ambiguous | [Z](png/sup-nest.zatex.png) [K](png/sup-nest.katex.png) [M](png/sup-nest.mathjax.png) [L](png/sup-nest.luatex.png) |
| frac-nest  | `\frac{1}{1+\frac{1}{x}}` | 0.634 | 0.622 | 0.544 | 0.634 | 0.501 | spec-ambiguous | [Z](png/frac-nest.zatex.png) [K](png/frac-nest.katex.png) [M](png/frac-nest.mathjax.png) [L](png/frac-nest.luatex.png) |
| font-cal  | `\mathcal{AB}` | 0.635 | 0.405 | 0.635 | 0.516 | 0.449 | spec-ambiguous | [Z](png/font-cal.zatex.png) [K](png/font-cal.katex.png) [M](png/font-cal.mathjax.png) [L](png/font-cal.luatex.png) |
| font-bb #34 | `\mathbb{AB}` | 0.637 | 0.449 | 0.637 | 0.525 | 0.295 | spec-ambiguous | [Z](png/font-bb.zatex.png) [K](png/font-bb.katex.png) [M](png/font-bb.mathjax.png) [L](png/font-bb.luatex.png) |
| acc-breve  | `\breve{a}` | 0.639 | 0.561 | 0.451 | 0.639 | 0.477 | spec-ambiguous | [Z](png/acc-breve.zatex.png) [K](png/acc-breve.katex.png) [M](png/acc-breve.mathjax.png) [L](png/acc-breve.luatex.png) |
| acc-acute #30 | `\acute e` | 0.653 | 0.523 | 0.526 | 0.653 | 0.453 | spec-ambiguous | [Z](png/acc-acute.zatex.png) [K](png/acc-acute.katex.png) [M](png/acc-acute.mathjax.png) [L](png/acc-acute.luatex.png) |
| agree-sum  | `\sum_{i=1}^n i^2 = \frac{n(n+1)(2n+1)}{6}` | 0.654 | 0.654 | 0.446 | 0.601 | 0.460 | spec-ambiguous | [Z](png/agree-sum.zatex.png) [K](png/agree-sum.katex.png) [M](png/agree-sum.mathjax.png) [L](png/agree-sum.luatex.png) |
| agree-quad  | `x^2` | 0.661 | 0.559 | 0.576 | 0.661 | 0.475 | spec-ambiguous | [Z](png/agree-quad.zatex.png) [K](png/agree-quad.katex.png) [M](png/agree-quad.mathjax.png) [L](png/agree-quad.luatex.png) |
| acc-check  | `\check{a}` | 0.665 | 0.520 | 0.491 | 0.665 | 0.462 | spec-ambiguous | [Z](png/acc-check.zatex.png) [K](png/acc-check.katex.png) [M](png/acc-check.mathjax.png) [L](png/acc-check.luatex.png) |
| text-mbox  | `\text{hello }x` | 0.669 | 0.445 | 0.420 | 0.669 | 0.440 | spec-ambiguous | [Z](png/text-mbox.zatex.png) [K](png/text-mbox.katex.png) [M](png/text-mbox.mathjax.png) [L](png/text-mbox.luatex.png) |
| neg-not  | `\not\in` | 0.671 | 0.434 | 0.428 | 0.671 | 0.420 | spec-ambiguous | [Z](png/neg-not.zatex.png) [K](png/neg-not.katex.png) [M](png/neg-not.mathjax.png) [L](png/neg-not.luatex.png) |
| frac-basic #32 | `\frac a b` | 0.677 | 0.636 | 0.489 | 0.677 | 0.427 | spec-ambiguous | [Z](png/frac-basic.zatex.png) [K](png/frac-basic.katex.png) [M](png/frac-basic.mathjax.png) [L](png/frac-basic.luatex.png) |
| rel-chain  | `a \le b \ne c \approx d` | 0.683 | 0.615 | 0.461 | 0.683 | 0.422 | spec-ambiguous | [Z](png/rel-chain.zatex.png) [K](png/rel-chain.katex.png) [M](png/rel-chain.mathjax.png) [L](png/rel-chain.luatex.png) |
| sqrt-idx  | `\sqrt[3]{x}` | 0.704 | 0.643 | 0.534 | 0.704 | 0.433 | spec-ambiguous | [Z](png/sqrt-idx.zatex.png) [K](png/sqrt-idx.katex.png) [M](png/sqrt-idx.mathjax.png) [L](png/sqrt-idx.luatex.png) |
| color-text  | `\textcolor{red}{x}+y` | 0.709 | 0.610 | 0.585 | 0.709 | 0.526 | spec-ambiguous | [Z](png/color-text.zatex.png) [K](png/color-text.katex.png) [M](png/color-text.mathjax.png) [L](png/color-text.luatex.png) |
| delim-vert  | `\left\|x\right\|` | 0.712 | 0.680 | 0.712 | 0.174 | 0.220 | spec-ambiguous | [Z](png/delim-vert.zatex.png) [K](png/delim-vert.katex.png) [M](png/delim-vert.mathjax.png) [L](png/delim-vert.luatex.png) |
| box-fcolor  | `\fcolorbox{red}{yellow}{x}` | 0.726 | 0.459 | 0.260 | 0.726 | 0.223 | spec-ambiguous | [Z](png/box-fcolor.zatex.png) [K](png/box-fcolor.katex.png) [M](png/box-fcolor.mathjax.png) [L](png/box-fcolor.luatex.png) |
| miss-trileft #37 | `\triangleleft` | 0.730 | 0.619 | 0.663 | 0.730 | 0.656 | spec-ambiguous | [Z](png/miss-trileft.zatex.png) [K](png/miss-trileft.katex.png) [M](png/miss-trileft.mathjax.png) [L](png/miss-trileft.luatex.png) |
| acc-vec-dot  | `\vec{v} + \dot{x} + \ddot{y}` | 0.757 | 0.450 | 0.553 | 0.757 | 0.406 | spec-ambiguous | [Z](png/acc-vec-dot.zatex.png) [K](png/acc-vec-dot.katex.png) [M](png/acc-vec-dot.mathjax.png) [L](png/acc-vec-dot.luatex.png) |
| box-color  | `\colorbox{yellow}{a+b}` | 0.857 | 0.660 | 0.376 | 0.857 | 0.359 | spec-ambiguous | [Z](png/box-color.zatex.png) [K](png/box-color.katex.png) [M](png/box-color.mathjax.png) [L](png/box-color.luatex.png) |
| wide-check #31 | `\widecheck{AB}` | 0.876 | 0.876 | 0.406 | missing | 0.382 | spec-ambiguous missing:luatex | [Z](png/wide-check.zatex.png) [K](png/wide-check.katex.png) [M](png/wide-check.mathjax.png) [L](png/wide-check.luatex.png) |

