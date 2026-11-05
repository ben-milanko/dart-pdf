# Redaction: no traces left behind, and image-replacement mode

A follow-up to #1256 (doc/dev-log/2026-11-05-redaction-hidden-content.md).
Two notes on the burned output, and a request for a stronger mode.

## The two notes

1. **Removed widths.** A fully removed run left a kern-only `TJ` of exactly
   its width (`[-25568] TJ`). With the font's metrics, candidate strings can
   be tested against that number. For short, guessable content (names,
   amounts) that can be enough to recover it.
2. **Leftover structure.** Empty `q 0.92 0.94 1 rg ... Q` groups (the state
   of a removed shape), the `Td` stops of removed lines, and the empty text
   objects around them showed where boxed items stood. A word cut by a box
   ("rives") gave away the letter beside it.

## What changed

- **Cleanup pass** (`_tidyRedactedContent`, `redaction_burn.dart`). It runs
  on every stream the burn changed and leaves what it draws as it was:
  - `q`...`Q` groups that draw nothing go;
  - a text object that shows nothing keeps only its lasting text state
    (`Tf`, `Tc`, `TL`...);
  - a kern-only show that no later text relies on goes, because only a new
    position or the end of the object follows it;
  - runs of positioning operators fold into one `Tm`, so the stops along
    the way don't survive.

  A form inherits its leading, so a `T*` there never folds. The tests check
  that kept text doesn't move (`test/redaction_traces_test.dart`).
- **Whole words** (`burnRedactions(wholeWords: true)`, the default). A word
  that loses any letter loses all of them, and the fill grows over the
  letters taken beyond the box (`session.extraFills`). Words are split at
  spaces, and at kerns of a fifth of an em or more, within one show
  operator. A word split across two `Tj`s is still cut letter by letter.
- **What can't be fixed while the layout holds.** A kern that later text on
  the same line relies on stays. That text sits where it always did, so the
  gap before it is the removed width whatever encodes it, and anyone
  measuring the visible positions gets the same number. Image mode keeps the
  positions too, in the pixels. Hiding the width would mean reflowing the
  line, which moves text the box didn't cover. This is documented on
  `burnRedactions`.

## Image-replacement mode

`PdfEditor.replacePagesWithImages(Map<int, PdfPageRaster>)`
(`redaction_raster.dart`) replaces each page with one Flate RGB image:
- the media box and crop box are set to the displayed size, upright
  (rotation 0);
- every inheritable attribute is set explicitly, so nothing comes back from
  an ancestor;
- annotations go, and so do form fields that only they showed;
- structure elements whose `/Pg` is the page lose `/ActualText`, `/Alt` and
  `/E`;
- the file is compacted again.

The page object itself stays, so outlines and links still land on it.
`pdf_document` can't render pages, so the host supplies the pixels.

`PdfEditingController.applyRedactionsAsImages({dpi = 200, render})` does
this in three steps:
1. burn a private copy of the current bytes, because a burn edits the
   document it is given in place, and the open one must not change while
   pages render;
2. render each marked page with `PdfPageRenderer.renderImage`, as
   displayed, with annotations drawn;
3. replace those pages.

If the document is edited while the pages render, it gives up and leaves
the marks, rather than overwrite that edit.

The Apply-redactions dialog offers it as a checkbox ("Replace redacted pages
with images"). `PdfConfirmRequest.option` (a `PdfConfirmOption` holding a
`ValueNotifier<bool>`) is the new, non-breaking presenter seam. A custom
presenter that ignores it leaves the value false, which means an ordinary
burn. Strings are translated in all 22 editor locales.
