# Image tool hides itself when no `imagePicker` is wired

## Symptom

A downstream app (a `PdfEditorView` host) enabled the Insert tool group but
never supplied an `imagePicker`. The Insert group still offered the image
tool, so tapping it was a silent no-op - a dead button with no feedback. The
reporter hit it and reasonably assumed the feature was broken.

The image tool is inert without a picker *by design*: the picture has to come
from somewhere (a file picker, a clipboard read), and the package can't pull
in `dart:io`/plugin dependencies to provide one. `PdfViewer.imagePicker` /
`PdfEditorView.imagePicker` / `PdfEditingToolbar.imagePicker` is the seam the
host wires. The bug was only that we *showed the button anyway* when the seam
was left unwired.

## Fix

Two parts, both cheap:

1. **Hide, don't no-op.** `PdfEditingToolbar._entryVisible` now drops
   `PdfEditTool.image` from the Insert group when `imagePicker == null`. This
   is the same visibility path the existing `tools` / `groups` filters use, so
   it covers both the desktop group strip and the mobile bottom-sheet grid, and
   flows through `PdfEditorView` (which builds the stock toolbar with
   `imagePicker: widget.imagePicker`). The overlay's tap/drag handlers already
   short-circuit on a null picker, so arming the tool directly through the
   controller stays a safe no-op - the toolbar just no longer offers a way in.

2. **Make the seam obvious.** Doc comments on `imagePicker`
   (`pdf_viewer.dart`, `pdf_editor_view.dart`, `editing_overlay.dart`,
   `editing_toolbar.dart`) and on the `PdfEditTool.image` enum value now spell
   out that the callback *must* be wired for the tool to appear/work, name the
   typical wiring, and describe the hide-when-null behavior - so the next
   human or AI reading the API sees the requirement instead of discovering a
   dead button.

## Test

`editing_image_test.dart` gains an "image tool visibility in the toolbar"
group: the image tool is `findsNothing` with no picker and `findsOneWidget`
once an `imagePicker` is supplied (Insert strip raised by arming the always-
present free-text tool).
