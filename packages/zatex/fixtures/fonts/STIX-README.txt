STIX Two Math overline subset (issue #92 determinism tail).

Full-file source: STIX Two Math (macOS Supplemental fonts; upstream
https://github.com/stipub/stixfonts), subset to U+203E OVERLINE via
  python3 -m fontTools.subset STIXTwoMath.otf --unicodes=U+203E \
      --output-file=STIXTwoMath-overline.otf --recalc-bounds \
      --desubroutinize --name-IDs='*'
(fontTools 4.60). The over/under construct hook for \underbar is
U+203E, which neither Latin Modern Math nor any KaTeX face carries;
without this vendored glyph the bar resolves only through the
machine-dependent system-STIX tail (blank where STIX is absent).
With it, \underbar renders byte-identically on every machine; the
system STIX tail remains for exotic codepoints outside the parity
corpus.

Copyright 2001-2021 The STIX Fonts Project Authors
(https://github.com/stipub/stixfonts). Licensed under the SIL Open
Font License, Version 1.1 (https://scripts.sil.org/OFL).
