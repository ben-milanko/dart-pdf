# Blank page from an inverted clip range in the colorant buffer

A real-world A3 engineering drawing (an ARTC level-crossing GA sheet, one
page, ~38k strokes) rendered as a completely blank page. The page declares
`/OP` in its ExtGStates, so the overprint colorant buffer
(`PdfOverprintCompositor` + `PdfColorantRaster`) is built for it, and part
way through the content stream a stroke threw:

```
RangeError (end): Invalid value: Not in inclusive range 79992..104448: 79988
  PdfColorantRaster.paintFlat (raster/colorant_raster.dart:260)
  PdfOverprintCompositor._resolve / .strokeShape
  PdfInterpreter._paint -> drawPage
```

The exception escapes `drawPage`, so nothing that had been recorded up to
that point reached the device - hence blank, not partial.

## The bug

Every span loop in `PdfColorantRaster` clips a run to the active clip box
the same way:

```dart
if (from < _clipX0) from = _clipX0;
if (to > _clipX1) to = _clipX1;
```

A scanline can be inside the clip's *rows* while its run lies entirely
outside the clip's *columns* - any slanted or off-to-the-side shape crossing
a narrow clip. Both clamps then fire and leave `to < from`: an inverted
range. The `for (var x = from; x < to; x++)` loops that most of the class
uses no-op on that, which is why this went unnoticed. The two `fillRange`
fast paths - `paintFlat` when there is no clip mask, and `markCovered` when
there is no clip - do not: `fillRange(start, end)` with `end < start` throws.

The fast paths were the later addition, so the crash needed a page that both
builds a colorant buffer (declares overprint) and paints an unmasked
rectangular-clipped shape that misses the clip's columns on some row. This
drawing is full of them.

## The fix

`if (to <= from) continue;` after the clamp in `paintFlat` and
`markCovered`. Behaviour-neutral everywhere else: an empty run wrote nothing
before (it threw or it no-op'd), and writes nothing now.

`test/colorant_raster_clip_test.dart` pins it directly on the raster - a
draw wholly left of a right-hand clip must be a no-op rather than a throw,
and a draw that straddles the clip edge must still fill exactly the part
inside. Both no-op tests fail without the change.

## Worth noting

The blast radius here was out of all proportion to the defect: one bad
`fillRange` in an accelerator for a *colour-accuracy* feature took out the
entire page. The overprint compositor already has a kill switch
(`PdfInterpreter.debugResolveOverprint`); nothing currently catches a
failure inside it and falls back to the unresolved paint. That is a
separate change, but if a third crash of this shape turns up it is probably
the right answer.
