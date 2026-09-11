# Exported pages now open after they are saved

"Export pages…" (and the thumbnail selection toolbar's export button, and
the page tile context menu's Export entry) wrote a standalone PDF of the
chosen pages and then said nothing at all. The user had pulled pages out of
a document, and the only evidence was a file somewhere in the save dialog's
folder. Now the export opens in a new tab as soon as it is written.

One host callback carries all three entry points. `PdfEditorView`'s
`onExportPages` receives the finished bytes -
`controller.exportSelectedPages()` / `exportPageRange()` /
`exportPages(targets)`, all of which come out of
`PdfPageExtraction.extractPages` - so the change is entirely in the app's
handler (`app/lib/editor_screen.dart`). It was:

```dart
onExportPages: (bytes) => unawaited(saveBytesAs(context, bytes, tab.title,
    pdfLabel: appL10n(context).fileTypePdf)),
```

and is now `_exportPages(tab, bytes)`, which saves and then hands the same
bytes to `_openBytes` - the path the OCR result and the initial document
already take, so the new tab records a Recent and persists into the session
like any other open document.

Notes on the details:

- The new tab adopts the save destination as its origin when there is one
  (`result.path`, i.e. a desktop save dialog), with a fresh
  `securityBookmarkForPath` so a sandboxed macOS folder stays writable.
  Save then writes straight back to the file that was just created instead
  of asking again. A web download or a mobile share sheet reports success
  with no path, so that tab opens over the exported bytes alone and its
  first Save asks for a location - which is the same deal any new document
  gets there.
- The tab's title is the basename of where it landed, matching what Save As
  does to the tab it saved (`path.split(RegExp(r'[/\\]')).last`); with no
  path it keeps the suggested name through `ensurePdfName`.
- The export path had no toast either, so a write that failed (full disk,
  a folder gone read-only) passed in complete silence - `SaveResult.failed`
  carries a message and nothing was reading it. `_exportPages` toasts
  `result.message` exactly like `_save` does, which also means a cancelled
  save stays quiet (its message is null).
- The source document is untouched: an export reads the document, and the
  test pins `session.bytes` across the round trip to keep it that way.
- Save As went through a lambda over `widget.saveDocumentAs` that was
  copied out three times (`_save`, `_reduceFileSize`, and now the export).
  That is one getter now, `_saveAsDocument`, so the export uses the same
  injectable seam the other two do - which is also what makes it testable
  without the platform save dialog.

`app/test/export_pages_test.dart` drives the four outcomes (saved to a path,
cancelled, downloaded without a path, failed) through that seam, asserting
the extracted pages themselves - `PdfTextExtractor` over the new tab's
document - rather than just the tab count.

Still not wired: `PdfEditorView.onSplitPages` ("Split PDF…", one document
per range) has no host handler in the app at all, so that action never
appears. Whatever opens its outputs will want the same treatment.
