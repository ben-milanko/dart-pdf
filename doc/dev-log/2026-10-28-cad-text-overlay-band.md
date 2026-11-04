# Selection band for CAD text overlays

CAD exports draw their lettering as vector paths and lay an invisible text
run over it for search. A MicroStation drawing (`MTM-CAM-GSR-0182`, Creator
"MicroStation 8.11.9.292") showed the search/selection highlight sitting about
a quarter em below "STAGE 3": it cut through the tops of the capitals and hung
below them.

## What the file does

```
BT 3 Tr 1 0 0 rg /T1_0 14.173 Tf
1.0794 0 0 1 406.7401 136.7681 Tm (STAGE 3) Tj ET
```

`/T1_0` is base-14 Times-Roman with **no /Widths** and nothing embedded. The
horizontal geometry was already right: the built-in Times AFM widths put the
run at x 406.7–467.5, and the vector glyphs span 407.4–464.7. The vertical was
wrong. CAD text height is the **cap height**, so the drawn capitals run from y
136.5 to 151.2, i.e. baseline to roughly 1.0 × font size. Extraction's fixed
-0.25..0.75 em band put the highlight at 133.2–147.4.

## Fix

`PdfTextRun.overlaysDrawnText` = render mode 3, no glyph list (not embedded,
not Type3), and `PdfFontInfo.declaresNoWidths` (a simple font dictionary with
no /Widths). `_appendExtractedRun` bands such runs 0..1 em
(`_overlayTextDescent`/`_overlayTextAscent`). On the drawing that gives
136.77–150.94.

Why the /Widths condition: our own OCR writer (`injectTextLayer`) also writes
`3 Tr` text in non-embedded base-14 Helvetica, and it places the baseline so
the **default** band covers the word box. OCR runs on any page, vector-only
ones included, so "is there an image underneath" can't tell the two apart. OCR
writers state the widths they measured with (ours writes explicit 32–255
/Widths), while the CAD exporter just names a font. An OCR tool that omits
/Widths would now get the 0..1 band too. That's an accepted risk for this
heuristic.

The flag travels everywhere `invisible` does: `PdfRecordedText`, the
`TranslatingPdfDevice`, and the render-command codec (format **v13**, one bool
after `invisible`).

## Not covered

- AutoCAD's SHX text is made searchable through "AutoCAD SHX Text" comment
  annotations, not `3 Tr` page text, so it doesn't go through this path.
- Horizontal drift when a CAD stroke font is much wider or narrower than the
  named stand-in. Fixing that means fitting the band to the vector paths drawn
  under the run (collect path bounds in the extraction device), which costs
  path bookkeeping on every page and needs a perf A/B.
