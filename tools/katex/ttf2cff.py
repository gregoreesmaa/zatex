#!/usr/bin/env python3
"""KaTeX TTF -> CFF-OTF via exact quadratic elevation (issue #92).

The software backend rasterizes CFF (Type2) outlines only, while the
pinned KaTeX bundle ships TrueType-glyf TTFs -- so the vendored test
fixtures are converted copies. Each quadratic segment degree-elevates
to exactly one cubic (lossless; no tolerance involved); components are
decomposed; cmap/hmtx/head/hhea/maxp/name/OS/2/post are preserved, and
the CFF CharStrings INDEX follows glyph order (GID == index), which is
what the backend rasterizes. T2CharStringPen rounds to integer units.

The vendored set was produced with fontTools 4.60 by:
  for f in Main-Regular Main-Bold Main-Italic Main-BoldItalic \
           Math-Italic AMS-Regular SansSerif-Regular Typewriter-Regular \
           Caligraphic-Regular Fraktur-Regular Script-Regular; do
    python3 tools/katex/ttf2cff.py \
      tools/katex/node_modules/katex/dist/fonts/KaTeX_$f.ttf \
      packages/zatex/fixtures/fonts/katex/KaTeX_$f.otf KaTeX_$f
  done

Usage: ttf2cff.py IN.ttf OUT.otf PSNAME
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPointPen


class Collector:
    def __init__(self, glyphSet):
        self.glyphSet = glyphSet
        self.contours = []
        self.cur = None

    def beginPath(self):
        self.cur = []

    def endPath(self):
        self.contours.append(self.cur)
        self.cur = None

    def addComponent(self, name, transformation):
        self.glyphSet[name].drawPoints(
            TransformPointPen(self, transformation))

    def addPoint(self, pt, segmentType=None, smooth=False, name=None, **kw):
        self.cur.append((pt, segmentType))


def replay(contours, pen):
    for contour in contours:
        if not contour:
            continue
        # rotate to an on-curve start
        start_idx = None
        for k, (pt, typ) in enumerate(contour):
            if typ != "qcurve":
                start_idx = k
                break
        if start_idx is None:
            continue  # all off-curve: degenerate, skip
        pts = contour[start_idx:] + contour[:start_idx]
        pen.moveTo(pts[0][0])
        cur = pts[0][0]
        pending = []
        items = pts[1:] + [(pts[0][0], "close")]
        for pt, typ in items:
            if typ == "line":
                if pending:
                    # on-curve endpoint of a quadratic run arrives
                    # typed as a line point: flush the run into it.
                    flush(pen, cur, pending, pt)
                    pending = []
                else:
                    pen.lineTo(pt)
                cur = pt
            elif typ == "qcurve":
                pending.append(pt)
            elif typ in (None, "close"):
                flush(pen, cur, pending, pt)
                cur = pt
                pending = []
            else:
                raise ValueError("unexpected segment %r" % typ)
        pen.closePath()


def flush(pen, p0, offs, pend):
    # pts: off-curve points, all but the last (the on-curve endpoint).
    pts = list(offs) + [pend]
    cur = p0
    j = 0
    while j < len(pts) - 1:
        if j + 1 < len(pts) - 1:
            # next point is also off-curve: implied on-curve midpoint.
            mid = ((pts[j][0] + pts[j + 1][0]) / 2,
                   (pts[j][1] + pts[j + 1][1]) / 2)
            emit(pen, cur, pts[j], mid)
            cur = mid
            j += 1
        else:
            emit(pen, cur, pts[j], pts[j + 1])
            j += 2


def emit(pen, p0, p1, p3):
    c1 = ((p0[0] + 2 * p1[0]) / 3, (p0[1] + 2 * p1[1]) / 3)
    c2 = ((p3[0] + 2 * p1[0]) / 3, (p3[1] + 2 * p1[1]) / 3)
    pen.curveTo(c1, c2, p3)


def convert(src, dst, psname):
    f = TTFont(src)
    upm = f["head"].unitsPerEm
    order = f.getGlyphOrder()
    gs = f.getGlyphSet()
    hmtx = f["hmtx"]
    cmap = f.getBestCmap()

    charstrings = {}
    metrics = {}
    for name in order:
        adv, lsb = hmtx[name]
        metrics[name] = (adv, lsb)
        col = Collector(gs)
        gs[name].drawPoints(col)
        pen = T2CharStringPen(adv, None)
        replay(col.contours, pen)
        charstrings[name] = pen.getCharString()

    fb = FontBuilder(upm, isTTF=False)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=f["hhea"].ascent,
                             descent=f["hhea"].descent)
    n = f["name"]
    def rec(nid):
        try:
            return n.getDebugName(nid) or psname
        except Exception:
            return psname
    fb.setupNameTable({
        "familyName": rec(1), "styleName": rec(2),
        "uniqueFontIdentifier": rec(3), "fullName": rec(4),
        "psName": psname, "version": rec(5),
    })
    fb.setupOS2()
    fb.setupPost()
    fb.setupMaxp()
    finfo = {"version": rec(5), "Notice": rec(0),
             "FullName": rec(4), "FamilyName": rec(1),
             "Weight": rec(2)}
    fb.setupCFF(psname, finfo, charstrings,
                {"nominalWidthX": 0, "defaultWidthX": 0})
    fb.save(dst)
    print("wrote", dst, "glyphs:", len(order))


if __name__ == "__main__":
    convert(sys.argv[1], sys.argv[2], sys.argv[3])
