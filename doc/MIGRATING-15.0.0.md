# Migrating to 15.0.0

Update the eight established packages together to 15.0.0. The CLI uses 0.11.0, the printing companion 0.12.0 and the GPU companion 0.13.0.

## Inline text editing

`PdfEditingController` no longer exposes `editingTextStyleRevision`, `editingTextStyleRequest`, `editSelectedTextRevision`, `isEditingTextFocusCommitHeld`, `editingTextFocusHoldRevision`, `shouldKeepEditingTextFocused`, `setEditingTextSelection`, `beginEditingTextFocusHold`, `endEditingTextFocusHold`, `beginKeepEditingTextFocused` or `endKeepEditingTextFocused`.

Use `textEditSession` to observe the active `PdfTextEditSession`. Its buffer owns the text selection. `holdCommit()` and `keepFocused()` return disposable focus-hold handles. Custom inline editors use `beginTextEdit`, `endTextEdit` and `applyTextEditCommit`. `setEditingText` remains for the form-field editor. The supplied editor widgets handle these changes internally. See `doc/dev-log/2026-11-05-text-edit-session.md`.

## Redaction

Applying redactions now removes metadata, attachments and document JavaScript by default. Shared images, forms or content streams may be removed or replaced in every location where they are used. Ambiguous geometry can cause more content to be removed than the marked area. Review the output before sharing it.

This is not a guarantee against every crafted PDF. Embedded font programs remain; crafted glyph outlines, ligatures and missing Unicode mappings have documented limitations. Disabling `removeHiddenInformation` can leave compressed attachments containing removed text. See `doc/dev-log/2026-11-05-redaction-hidden-content.md` for the full scope and limitations.
