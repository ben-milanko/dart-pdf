# Right-click "Save to stamps": a placed stamp goes back into the collection

The stamp collection was write-only from the page's point of view: you
could design a stamp in the picker and place it, but a stamp already sitting
in a document - one a colleague stamped, or one you made in an earlier
session on another device - could not be picked back up. This adds the
missing direction: right-click a /Stamp → **Save to stamps**.

## The design travels with the annotation

A placed stamp is deliberately *one* /Stamp whose parts are compiled into a
single appearance stream (`addTemplateStamp`), which is what makes it cheap
to move, resize, flatten, sync and print - but it also means the appearance
is the only trace of the design. Decompiling a content stream back into
`PdfStampTemplate` components is not something to attempt, so
`addTemplateStamp` now records the template as private annotation metadata:

    dict['DartPdfStampTemplate'] = <the template's JSON>

read back by `PdfAnnotation.stampTemplate`. Same shape as the existing
`DartPdfStampType` / `DartPdfStampTags` / `DartPdfImageStamp` markers, so it
survives saves, copies, sync, and reopens for free.

Two decisions worth remembering:

- **The stored design is unresolved.** The annotation's /Contents holds the
  caption with `{{date}}` already filled in (what the page shows); the
  metadata holds the design as authored. That's the whole point - a stamp
  saved off a page has to keep stamping *today's* date, not the day someone
  else placed it. It also means the metadata is **not** usable to regenerate
  the appearance on restyle (that would re-render the literal `{{date}}`);
  the restyle path is untouched and still falls back to the text look for
  template stamps, exactly as before.
- **There's a size cap** (`PdfAnnotationEditing.maxStampTemplateMetadataBytes`,
  64 KB of encoded JSON). Text/shape designs are a few hundred bytes, so the
  cap only bites on a template carrying a picture - whose bytes the appearance
  stream already pays for once, and which would otherwise be paid for again by
  every placement. Over the cap the stamp places and prints identically; it
  just can't be recovered from the page.

## Recovering a stamp

`PdfEditingController.customStampOf(annotation)` is the single reading:

1. metadata present → the design comes back exactly, with `type`/`tags`;
2. otherwise a /Stamp with a caption → a classic text stamp from /Contents
   plus its colour (this is what makes a foreign document's `APPROVED`
   stamp reusable, approximated in our own rounded-box look);
3. nothing else - count check-marks (`isCheckMark`), pictures
   (`isImageStamp`) and pasted vector snapshots (`isVectorSnapshotStamp`)
   have no design to save, so they yield null and the menu entry is absent.

`saveSelectedAsCustomStamp()` saves it, skips exact duplicates already in the
collection, and makes it the `activeStamp` - so the obvious next action
(stamp it somewhere else) needs no trip through the picker. It's single-
selection only: a block of stamps has no one design.

## UI

One entry in `showPdfAnnotationMenu` (`pdf-annot-menu-save-stamp`), in the
same group as "Set as default style" - both capture the selection for
reuse - plus a floating snackbar, because a menu action with no visible
result reads as broken. New strings `menuSaveToStamps` /
`stampSavedToCollection`, translated across all 20 locales.

Tests: `annotation_editor_test.dart` (metadata round-trip, unresolved
fields, the cap), `editing_stamps_test.dart` (recovery, dedupe, re-placing
with a fresh date, the "not offered" cases), `editing_menu_test.dart` (the
menu entry and its snackbar).
