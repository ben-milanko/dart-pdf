# Viewer takes keyboard focus on open

Symptom: right after the app launched (or a document opened), tool keys,
arrows, ⌘Z etc. did nothing until the user clicked the page. The viewer's
`Shortcuts` wrap its own `Focus` (`_PdfViewerState._focusNode`), and nothing
ever focused that node until a pointer-down on the page (the raw listener's
`requestFocus`) or a host calling `PdfViewerController.requestKeyboardFocus`. With
primary focus null, key events reach no `Shortcuts` at all.

Fix: `_claimInitialFocus` (pdf_viewer.dart) queues
`_focusNode.enclosingScope?.autofocus(_focusNode)` from a post-frame callback
the first time the focus node is built.

Why not `Focus(autofocus: true)`: Flutter applies same-frame autofocus
requests first-come, and the viewer's `Focus` is built before a deeper
`EditableText` - so a host's autofocused search field in the same frame
would lose focus to the viewer. The post-frame request is queued after every
build-time autofocus (those apply in a microtask after the frame), so a host
field wins and the viewer's request is discarded. Autofocus also never fires
when the scope already has a focused child, so tab switches / reopened
documents don't steal from anything.

Tests: `editing_tool_shortcuts_test.dart` - "a freshly opened viewer takes
keys before any click" and "a host field autofocused alongside the viewer
keeps focus".
