# Collapse PdfViewer's document + editing dual input (issue #319)

`PdfViewer` used to take `document` **and** `editing`/`formController`
separately, tied by an unchecked invariant: `document` had to be
`editing.document`, and the host had to rebuild the viewer with the
current revision on every controller notification. That was interface
knowledge pushed onto every host, asserted only in debug builds.

## What changed

The viewer now reads the displayed document from the controller and
subscribes to it directly - the pair can no longer desync.

`pdf_viewer.dart`, `_PdfViewerState`:

- `_revisionController` - the controller that owns the revisions:
  `widget.editing ?? (interactiveForms ? widget.formController : null)`.
  This is the same resolution the annotation layer / page-image helpers
  already used, lifted into one getter.
- `_document` - `_revisionController?.document ?? widget.document!`. Every
  internal read of the document (`_loadPages`, `_labels`, text extraction)
  goes through this instead of `widget.document`.
- `_loadedDocument` - what `_loadPages` last read; a swap is detected
  against it.
- `_onRevisionControllerChanged` - the subscription callback (added in
  `initState`, moved in `didUpdateWidget` when the controller identity
  changes, removed in `dispose`). If the controller advanced a revision it
  runs `_swapDocument`; otherwise it `setState`s for the tool/selection/
  eyedropper state the build reads. This is exactly what the host's
  `ListenableBuilder` used to do.
- `_swapDocument` - the document-swap reconciliation (same-geometry
  rebind vs. full reset) extracted out of `didUpdateWidget` so both the
  host-rebuild path and the controller-notification path share it.

`PdfViewer.document` is now nullable; a constructor assert requires a
document source (`document`, `editing`, or `formController`). The build
assert enforcing `document == editing.document` is gone. Hosts that pass a
controller may drop both `document:` and the wrapping `ListenableBuilder`
around the viewer.

## Why it still keeps the viewport across revisions

The identity-swap optimization keys on document identity, which the
controller already changes per revision - unchanged. `_sameGeometryAs`
still decides rebind-vs-reset.

## Backward compatibility

Hosts that still wrap the viewer in a `ListenableBuilder` and pass
`document: editing.document` keep working: the redundant host rebuild and
the viewer's own subscription both fire, but the swap runs once (the
controller has already advanced its `document` by the time either fires,
so whichever runs first reconciles and the other sees
`_loadedDocument == _document`). The reader keeps its `ListenableBuilder`
because it also drives `PdfReflowView` and reacts to preferences, and its
no-form path is the standalone-`document` reader path.

## Tests

`pdf_viewer_test.dart` - new `editing controller drives the document`
group: the viewer follows revisions with no host `ListenableBuilder` and
no `document` (both `editing` and `formController`), and a deliberately
stale standalone `document` never desyncs it.
