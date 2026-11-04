# Last-used-tool shortcut (X)

**X** re-arms the tool used before the current one, Select aside.

- `PdfEditingController.lastUsedTool` (editing_controller.dart): the `tool`
  setter remembers the last two distinct non-Select tools *left*
  (`_rememberToolLeft`). `lastUsedTool` is the newest of those that isn't
  armed now, so: rectangle → Select → X re-arms rectangle; ink → ellipse →
  X → X flips ink/ellipse. Arming a markup kind goes through `tool = null`,
  so the tool it replaced is remembered too. Null until a tool has been used.
- `PdfArmLastToolIntent` (viewer_intents.dart), bound to plain X in
  `pdfViewerDefaultShortcuts`. The viewer action routes through `_armTool`,
  so under `PdfEditorCommands` a measure tool still asks for its scale.
  Disabled without an editing session or history, so X passes through then.
- A host tool shortcut on plain X still wins (the tool loop in
  `_keyBindings` removes base bindings on the same key).
- Tests: viewer_intents_test.dart.
