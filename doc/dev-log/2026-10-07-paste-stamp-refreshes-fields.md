# Pasted template stamps refresh their fields

Copy/paste of annotations (`PdfEditingController.pasteAnnotations`) used to
reproduce every copy verbatim through `PdfAnnotationClipboard.pasteAnnotation`.
For a `{{date}}` template stamp that meant the pasted copy showed the day the
original was placed - a host (Trax) reported users copy-pasting approval
stamps and getting stale dates.

Pasting a stamp is placing it again, so `_pasteRestampedTemplate` now
re-renders a copied template stamp from its recorded design
(`PdfAnnotation.stampTemplate`) with `_resolvedStampTemplateValues()` -
today's date/time and the current `preferences.author` for `{{username}}` -
via `PdfEditor.addTemplateStamp`, in the same revision as the rest of the
paste (one undo). Position, size, colour, opacity (/CA), type and tags carry
over; the copy is read through `PdfAnnotationSnapshot.annotationForPreview` so
a paste onto a differently rotated page uses the re-oriented /Rect, and
`addTemplateStamp(pageRotation:)` draws it upright there.

Still verbatim:

- stamps without a recorded template (legacy text stamps, image stamps,
  templates past `maxStampTemplateMetadataBytes`) - nothing to re-render from;
- designs with no `{{` placeholders - a re-render would change nothing;
- stamps the user rotated: `_appearanceTurnedBy` compares the appearance
  /Matrix angle with the page-rotation delta the paste folds in, and any extra
  turn falls back so the rotation isn't lost.

`applySelectedAnnotationsToPages` is unchanged: it copies at the moment of the
gesture, so its fields are already current.

Tests: `pasting a template stamp` group in `test/editing_clipboard_test.dart`.
