# Ctrl/⌘+S on a brand-new untitled document

## Symptom

Creating a new document (app menu → *New document…*) and immediately
pressing **Ctrl+S** / **⌘S** did nothing - the file could not be saved
until an edit was made first. The stock Save button was likewise greyed
out on the fresh document.

## Cause

`PdfEditorView._save()` (and the Save button's `onPressed`) gate on
`_canSave`, which was `_session.isModified`. A freshly-created blank
document has made no edits yet, so `PdfEditingController.isModified`
(`_cursor > 0 || _hardModified`) is `false` and the shortcut early-returned.
The SDK has no concept of a document's on-disk origin, so it treated a
never-saved new file the same as an unchanged opened file.

The app already tracks this state: a `New` tab is created with
`initiallyDirty: true`, which sets `DocumentTab.savedLength = -1` (no saved
baseline). But that flag never reached the SDK's save gate.

## Fix

- `PdfEditorView` gains `alwaysAllowSave` (default `false`). When `true`,
  `_canSave => _session.isModified || alwaysAllowSave`, so Save stays live
  even with no unsaved edits. Save As (`onSaveAs`) was already ungated.
- `DocumentTab.isUnsaved` (`session != null && savedLength < 0`) marks a
  document that has never been written to disk. `markSaved()` sets a
  real baseline, clearing it.
- `EditorScreen._buildBody` passes `alwaysAllowSave: tab.isUnsaved`. The
  first Ctrl+S on a new tab has no origin, so `_save(tab)` routes through
  the Save As flow (save dialog / download / share sheet).

Opened-from-disk documents are unaffected: they have a saved baseline, so
`isUnsaved` is `false` and Save stays gated on real edits.

## Tests

`app/test/save_shortcuts_test.dart`: *Ctrl+S saves a brand-new untitled
document before any edit* creates a document via the menu and asserts the
injected `saveDocumentAs` seam fires on a plain Ctrl+S with no edits.
The SDK's existing *save button is disabled until there are changes*
(`pdf_shell_test.dart`) still passes, pinning the default-`false` behaviour.
