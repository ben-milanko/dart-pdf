# Metric-compatible substitutes for the standard 14

A capital `J` in the example app's demo page ("Run JavaScript", plain
`/F1 12 Tf … Tj` against base-14 Helvetica) drew with about 2.7pt of air
after it, as if the word were `J avaScript`. Nothing was wrong with the
PDF, the kerning, or the placement machinery. It was the substitute face.

## What the gap actually was

A standard-14 font carries no font program, so the advances come from the
AFM tables (`PdfFontInfo._fillStandardWidths`, tables in
`content_writer.dart`) and the glyphs come from whatever the host has.
`CanvasPdfDevice`'s fallback chain named `Helvetica` first and the bundled
`DejaVu Sans` behind it, so on any platform without a real Helvetica -
Linux, Windows, web, Android - every base-14 sans page was drawn in DejaVu.

DejaVu is not metrically related to Helvetica, and `J` is the worst pairing
in the whole alphabet:

| glyph | Helvetica slot | DejaVu, as drawn | leftover |
| --- | --- | --- | --- |
| J | 500 | 275 | **+225** |
| S | 667 | 592 | +75 |
| R | 722 | 648 | +74 |
| P (next worst) | 667 | 603 | +64 |
| t | 278 | 366 | −88 |

`exactSubstitutedGlyphPlacement` (#649) pins each character to the PDF's
own pen offset so selection, search and hit boxes land on the ink, and
`_buildPlacedLayout` cuts a word wherever the substitute drifts past
0.02 em. So the surplus advance cannot be smeared across the line the way
a whole-run stretch would smear it: it opens as white space at the cut,
right after the `J`. Counting sidebearings the visible gap was ~4.5pt
against ~1.2pt for an ordinary letter pair. The same mechanism made `Run`
read as `R un`.

That is the design working as specified. The fix is not to loosen the
placement - it is to stop substituting a face whose advances disagree.

The cuts also cost draw calls, so this is not only a correctness fix.
Running that string through `pdfCanvas2dTextLayout` with each face's real
advances:

```
DejaVu metrics: [R@0.0, u@77.5, n@137.1, J@226.6, av@280.3, aS@393.6,
                 cr@524.8, i@614.2, p@638.0, t@697.7]   → 10 pieces
Heros metrics:  [Run@0.0, JavaScript@211.2]             →  2 pieces
```

Ten `fillText`s, one per near-glyph, with every disagreement spent as a
gap - against two words shaped whole with their kerning intact.

## What landed

`dart_pdf_editor_assets` now bundles URW's metric-compatible clones of the
base 14, alongside the Adventor faces it already shipped for Century
Gothic:

- **TeX Gyre Heros** → Helvetica, Arial, and any unembedded font with no
  more specific match
- **TeX Gyre Termes** → Times
- **TeX Gyre Cursor** → Courier
- **TeX Gyre Adventor** → Century Gothic / Avant Garde (unchanged)

Regular, bold, italic and bold-italic each: 1.46 MB of new files, 780 KB
over the wire gzipped. They are declared font families rather than lazily
registered like the font-menu faces, because the renderer *names* them
while painting and needs them from the first paint - so that is what they
add to CanvasKit's web cold start, in exchange for every standard-14 page
being spaced the way it was typeset. The distinction from the five menu
faces deliberately kept out of FontManifest holds: those are previews most
sessions never open, these are drawn on the first page that has text.

The web harness can't put a number on that: `app/tool/perf_harness` does
not depend on `dart_pdf_editor_assets`, so a `tool/perf.sh webdiff` build
carries neither the old nor the new fonts and would measure noise. What
the change costs is the byte count above, once, HTTP-cached; what it saves
per paint is the piece count above.

The metric claim is checked, not assumed:
`packages/dart_pdf_editor_assets/test/substitute_metrics_test.dart` parses
every shipped file with pdf_graphics' own OpenType parser and compares all
95 ASCII advances against `PdfStandardFont`'s AFM tables. Heros matches
Helvetica and Helvetica-Bold exactly, Cursor is a flat 600, Termes matches
all four Times tables. CI runs it, so a font upgrade cannot quietly
reintroduce the gaps.

## Where the policy lives

`font_substitution.dart` was a pair of Adventor helpers and is now the one
place that answers "what face draws this run": `PdfBundledSubstitute` (the
family, its asset files per weight/slant, the host faces that carry the
same metrics, the CSS generic) plus `pdfBundledSubstituteFor(name)`. It is
exported from `dart_pdf_editor`, because three renderers have to agree:

- **CanvasKit / native** - `CanvasPdfDevice._styleFor` asks for
  `substitute.packageFamily` first, then the bare family, then the host's
  metric equivalents, then the shared script-coverage chain. A run only
  reaches DejaVu now for a character the clone has no glyph for.
- **canvas2d web worker** - Flutter's FontManifest does not cross the
  worker boundary, so the worker loads the faces itself through
  `FontFace`. `_loadWorkerAdventorFonts` became
  `_loadWorkerSubstituteFont` + `_workerSubstituteFaces`, which collects
  only the weights and slants a page actually shows (a page of upright
  Helvetica pulls one file) and skips invisible OCR layers.
- **flutter_gpu** - `FlutterGpuSystemTextOutliner` outlines the face
  Canvas would draw, so it had to move too, or the accelerated backend
  (the app's default, `systemTextOutlines: true`) would have kept drawing
  system faces and kept the gap. It now reads the bundled asset bytes
  through `rootBundle` and prefers them, falling back to the platform
  catalogue only once a face is known to be absent. While a face is still
  loading it returns null - the scene stays on the exact Canvas fallback -
  rather than outlining a face Canvas would not draw. An oblique that a
  family ships no file for is refused the same way: Canvas has the engine
  slant the upright face, and no outline here can reproduce that.

## Times italics needed the tables too

Bundling Termes-Italic without fixing the width lookup would have
reproduced the same defect for italic Times: `_fillStandardWidths` mapped
every `times*` name to `timesRomanWidths`, and Times-Italic's advances
genuinely differ (`A` is 611 against the roman's 722). The four Times
tables already existed in `content_writer.dart` for `PdfStandardFont` - the
fill just never selected among them. It does now (Helvetica keeps one
table for upright and oblique, which is what its AFM says).

## Known wrinkle, left alone

Code 39 is the one code where the checked-in tables disagree with each
other: StandardEncoding - the default for a base-14 font with no
/Encoding - puts `quoteright` there, WinAnsiEncoding puts the narrower
`quotesingle`, and the tables split (Times-Roman and Times-Italic carry
quoteright's 333, Times-Bold and Times-BoldItalic quotesingle's 278). The
width fill is by code, so it cannot serve both; the real fix is to fill by
glyph name through the resolved encoding, which is a separate change. The
metrics test accepts either glyph at that code and says why.
