# Unembedded Calibri draws in Carlito, not Heros (2026-09-18)

## The report

A 92-page signed T&C plan, printed to PDF by PDF-XChange Lite's GDI driver
out of Word on Windows 11. Its cover page looked, in the reporter's words,
cursed: the headings crowded, letters touching, the rhythm wrong in a way
that read as a broken font rather than a different one.

## What the file says

Page 1 names three fonts, none of them embedded:

    /F0  /Calibri            /TrueType  /WinAnsiEncoding  NOT-EMBEDDED
    /F1  /Calibri-Bold       /TrueType  /WinAnsiEncoding  NOT-EMBEDDED
    /F2  /Calibri-BoldItalic /TrueType  /WinAnsiEncoding  NOT-EMBEDDED

Document-wide it is 201 unembedded font references against 91 embedded ones
(the embedded ones all live in the attachment pages appended from page 81).
This is ordinary Office output: the driver assumes the reader has Calibri,
because on Windows it does.

`pdfBundledSubstituteFor` had no Calibri entry, so Calibri fell through the
Courier and Times gates to the default sans - TeX Gyre Heros, the Helvetica
clone. Helvetica is a much wider face than Calibri:

| cover heading, 15.96pt | reserved by the PDF | Heros/Helvetica needs |
|---|---|---|
| 27 characters of Calibri-Bold | 193.7pt | 227.9pt |
| 30 characters of Calibri-BoldItalic | 205.3pt | 235.0pt |

Per glyph: `C` 529 against Helvetica's 722, `s` 399 against 556, `R` 563
against 722, `g` 474 against 611. Every letter is wider than the slot the
page reserved for it, by 0.5-3pt at that size.

Line width did not give this away, because it cannot:
`exactSubstitutedGlyphPlacement` puts every character at the PDF's own pen
offset, so the line always ends where the PDF says. The surplus goes
*inside* the word - each glyph crowds the next. It is the mirror image of
the failure the standard-14 substitutes were introduced for (a narrow face
opening white space inside words), and it reads worse, because overlapping
ink looks like a corrupt font where a gap just looks loose.

The grey boxes on that cover are not a font problem at all - they are Word
field shading, printed as `.902 g ... re f` fills. They did confirm the
diagnosis, though: the box behind the italic line is 205.56pt wide against
that line's 205.3pt of Calibri. The document's own layout is right to a
third of a point. Only the glyph source was wrong.

(The file is a client document, so nothing from it is checked in but the
font metrics - which are facts about Calibri, not about the document.)

## The fix

`PdfBundledSubstitute.carlito`. Carlito is Google's metric-compatible
Calibri clone, and "metric-compatible" here is not approximate: it matches
every one of the 265 advances the four Calibri styles name in that
document's /Widths arrays, to the unit, in all four styles. Those tables are
checked into `substitute_metrics_test.dart` (codes no page showed are marked
-1 and skipped) so the contract is enforced the same way the AFM tables
enforce the TeX Gyre faces.

On the cover page, measuring the ink in the italic line's band: 12 clean
letter gaps before, 22 after, with 11% less ink over the same span. Same
pen offsets, glyphs that fit between them.

Three details worth keeping:

- **Carlito ships unmodified**, so it is TrueType where the TeX Gyre faces
  are CFF, and it is big: 2.7 MB for four faces against their 1.5 MB. It
  could be subset to a tenth of that, but the OFL reserves the name
  "Carlito", so a subset cannot be called Carlito - slimming it means
  renaming it, and that is a decision to take deliberately rather than in
  passing. If web cold start becomes the binding constraint, that is the
  lever.
- `assetFile()` grew an `assetSuffix`, because it hardcoded `.otf`. The web
  worker's `FontFace` had the matching assumption baked into its CSS
  `format("opentype")` hint; that now comes from
  `PdfBundledSubstitute.fontFaceFormat`. A strict engine rejects a TrueType
  face declared as opentype.
- `systemFallbacks` is `['Calibri']` alone, not `['Calibri', 'Carlito']` -
  the family name itself already reaches a host-installed Carlito, and the
  canvas2d list would otherwise name it twice.

## Not done

`PdfFontInfo._fillStandardWidths` still knows only the standard-14 families,
so a page that names Calibri *and* omits /Widths gets default advances. Every
real Office file carries /Widths, so this is theoretical - but it is the one
remaining place where Calibri is not fully modelled. Cambria/Caladea is the
same shape of problem, unsolved.
