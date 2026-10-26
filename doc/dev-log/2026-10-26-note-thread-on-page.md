# A note shows its whole comment thread

Symptom (real Acrobat review file): tapping a sticky note on the page showed
only the *last reply* - "In addition reflect these changes…" - never the
note it answered. Acrobat writes a reply as a `/Text` annotation with /IRT →
the note, the **same /Rect** as the note, appended later in /Annots. The
renderer already skips replies and review-state annotations
(`PdfInterpreter.drawAnnotations`, matching Acrobat), but the editor's
on-page hit tests didn't, so the topmost-wins test picked the invisible reply
sitting on the icon. Our own `replyToAnnotation` copies the parent's /Rect
too, so editor-authored threads hit the same thing.

Fix, two halves:

- `PdfEditingController._isThreadContent` (reply or state annotation) is
  skipped by `selectableAnnotationAt`, `selectAnnotationsIn` (rubber band +
  ⌘A) and `lockedAnnotationAt`; the overlay's snap targets skip them too.
  The on-page tests now agree with what is painted. Replies stay reachable as
  thread content (sidebar, properties panel), never as page objects.
- The properties panel grows a **Comments** group for a single selected
  markup annotation (`_threadRows` in editing_properties.dart): every reply
  under the thread root, depth-indented with author • time
  (`pdfPanelTimestamp`, now shared with the sidebar), then a reply field
  (`pdf-prop-reply-field` / `-send`) that calls
  `PdfEditingController.replyToAnnotation` on the root. The note's own text
  stays the Contents row above. A half-typed reply clears when the selection
  changes, not on a revision, so sending keeps the note selected.

Not done: moving a note leaves its (invisible) replies at the old /Rect,
which is harmless now that nothing on the page hits them.

Tests: `dart_pdf_editor/test/editing_note_thread_test.dart`.
